import 'dart:math';
import '../../services/database_service.dart';

/// Futsal-specific database operations.
///
/// Handles team-vs-team game CRUD with goal results, group assignments,
/// and no-show/removal tracking.
class FutsalService {
  final DatabaseService _dbService;
  FutsalService(this._dbService);

  // --- Team Game CRUD ---

  /// Create a game between two teams and return the event_id.
  Future<int> createTeamGame({
    required int tId,
    required int teamAId,
    required int teamBId,
  }) async {
    final db = await _dbService.database;
    final today = DateTime.now().toIso8601String().split('T').first;

    final aEntId = await _dbService.ensureTeamEntity(db, teamAId);
    final bEntId = await _dbService.ensureTeamEntity(db, teamBId);

    final eventId = await db.insert('CMP_EVENT', {
      't_id': tId,
      'event_date_begin': today,
      'et_id': 2, // Командний
    });

    await db.insert('CMP_SUBEVENT', {
      'ev_id': eventId,
      'entity_id': aEntId,
      'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_fa_se',
    });
    await db.insert('CMP_SUBEVENT', {
      'ev_id': eventId,
      'entity_id': bEntId,
      'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_fb_se',
    });

    return eventId;
  }

  /// Save goal results for a match.
  /// [detail] is "goalsA:goalsB" e.g. "3:1".
  /// [esId]=4 marks the game as a no-show (forfeit).
  Future<void> saveGoalResult({
    required int eventId,
    required int teamAEntityId,
    required int teamBEntityId,
    required int goalsA,
    required int goalsB,
    int? esId,
  }) async {
    final db = await _dbService.database;

    await db.transaction((txn) async {
      // Clear old subevents
      await txn.delete('CMP_SUBEVENT', where: 'ev_id = ?', whereArgs: [eventId]);

      // Insert result subevents
      await txn.insert('CMP_SUBEVENT', {
        'ev_id': eventId,
        'entity_id': teamAEntityId,
        'se_result': goalsA.toDouble(),
        'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_fa_r',
      });
      await txn.insert('CMP_SUBEVENT', {
        'ev_id': eventId,
        'entity_id': teamBEntityId,
        'se_result': goalsB.toDouble(),
        'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_fb_r',
      });

      // Build event_result string and es_id (no-show marker)
      await txn.update('CMP_EVENT', {
        'event_result': '$goalsA:$goalsB',
        'es_id': esId,
      }, where: 'event_id = ?', whereArgs: [eventId]);
    });
  }

  /// Get all team games for a tournament.
  Future<List<({
    int eventId,
    int teamAEntityId,
    int teamBEntityId,
    int? teamAId,
    int? teamBId,
    String? eventResult,
    int? esId,
  })>> getTeamGamesForTournament(int tId) async {
    final db = await _dbService.database;

    final events = await db.query(
      'CMP_EVENT',
      where: 't_id = ? AND et_id = 2',
      whereArgs: [tId],
      orderBy: 'event_id',
    );

    final result = <({
      int eventId,
      int teamAEntityId,
      int teamBEntityId,
      int? teamAId,
      int? teamBId,
      String? eventResult,
      int? esId,
    })>[];

    for (final event in events) {
      final eventId = event['event_id'] as int;
      final eventResult = event['event_result'] as String?;
      final esId = event['es_id'] as int?;

      final subevents = await db.query(
        'CMP_SUBEVENT',
        where: 'ev_id = ?',
        whereArgs: [eventId],
        orderBy: 'se_id',
      );

      if (subevents.isEmpty) continue;

      final entityIds = subevents.map((s) => s['entity_id'] as int).toSet().toList();
      if (entityIds.length < 2) continue;

      final aEntId = entityIds[0];
      final bEntId = entityIds[1];

      final aTeam = await db.query('CMP_TEAM', columns: ['team_id'], where: 'entity_id = ?', whereArgs: [aEntId]);
      final bTeam = await db.query('CMP_TEAM', columns: ['team_id'], where: 'entity_id = ?', whereArgs: [bEntId]);

      result.add((
        eventId: eventId,
        teamAEntityId: aEntId,
        teamBEntityId: bEntId,
        teamAId: aTeam.isNotEmpty ? aTeam.first['team_id'] as int? : null,
        teamBId: bTeam.isNotEmpty ? bTeam.first['team_id'] as int? : null,
        eventResult: eventResult,
        esId: esId,
      ));
    }

    return result;
  }

  /// Find or create a game between two teams. Returns the event_id.
  Future<int> findOrCreateTeamGame({
    required int tId,
    required int teamAId,
    required int teamBId,
  }) async {
    final db = await _dbService.database;
    final aEntId = await _dbService.ensureTeamEntity(db, teamAId);
    final bEntId = await _dbService.ensureTeamEntity(db, teamBId);

    final existing = await db.rawQuery('''
      SELECT e.event_id FROM CMP_EVENT e
      JOIN CMP_SUBEVENT se1 ON se1.ev_id = e.event_id AND se1.entity_id = ?
      JOIN CMP_SUBEVENT se2 ON se2.ev_id = e.event_id AND se2.entity_id = ?
      WHERE e.t_id = ? AND e.et_id = 2
      GROUP BY e.event_id
      LIMIT 1
    ''', [aEntId, bEntId, tId]);

    if (existing.isNotEmpty) {
      return existing.first['event_id'] as int;
    }

    return createTeamGame(tId: tId, teamAId: teamAId, teamBId: teamBId);
  }

  /// Delete a team game and its subevents.
  Future<void> deleteTeamGame(int eventId) async {
    final db = await _dbService.database;
    await db.transaction((txn) async {
      await txn.delete('CMP_SUBEVENT', where: 'ev_id = ?', whereArgs: [eventId]);
      await txn.delete('CMP_EVENT', where: 'event_id = ?', whereArgs: [eventId]);
    });
  }

  // --- Group Management (attr_id = 11) ---

  Future<Map<int, String>> getGroupAssignments(int tId) async {
    final db = await _dbService.database;
    final rows = await db.query(
      'CMP_TEAM_ATTR',
      where: 't_id = ? AND attr_id = 11',
      whereArgs: [tId],
    );
    final result = <int, String>{};
    for (final row in rows) {
      final teamId = row['team_id'] as int;
      final group = row['attr_value'] as String? ?? '';
      if (group.isNotEmpty) result[teamId] = group;
    }
    return result;
  }

  Future<void> setGroupAssignment(int tId, int teamId, String group) async {
    final db = await _dbService.database;
    final existing = await db.query(
      'CMP_TEAM_ATTR',
      where: 't_id = ? AND team_id = ? AND attr_id = 11',
      whereArgs: [tId, teamId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      await db.update(
        'CMP_TEAM_ATTR',
        {'attr_value': group},
        where: 'ta_id = ?',
        whereArgs: [existing.first['ta_id']],
      );
    } else {
      await db.insert('CMP_TEAM_ATTR', {
        'team_id': teamId,
        't_id': tId,
        'attr_id': 11,
        'attr_value': group,
        'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_fgrp_$teamId',
      });
    }
  }

  Future<void> clearGroupAssignments(int tId) async {
    final db = await _dbService.database;
    await db.delete('CMP_TEAM_ATTR', where: 't_id = ? AND attr_id = 11', whereArgs: [tId]);
  }

  /// Distribute teams randomly into groups of 3–5.
  Future<void> autoAssignGroups(int tId, List<int> teamIds) async {
    if (teamIds.isEmpty) return;
    final db = await _dbService.database;

    final n = teamIds.length;
    // Aim for groups of 3-5; start with groups of 4
    int groupCount = (n / 4).ceil().clamp(2, n);
    // Ensure no group is smaller than 3 if possible
    while (groupCount > 1 && (n / groupCount).floor() < 3) {
      groupCount--;
    }

    final shuffled = List<int>.from(teamIds)..shuffle(Random());
    final groupNames = List.generate(groupCount, (i) => String.fromCharCode(65 + i));

    await db.transaction((txn) async {
      await txn.delete('CMP_TEAM_ATTR', where: 't_id = ? AND attr_id = 11', whereArgs: [tId]);
      for (int i = 0; i < shuffled.length; i++) {
        await txn.insert('CMP_TEAM_ATTR', {
          'team_id': shuffled[i],
          't_id': tId,
          'attr_id': 11,
          'attr_value': groupNames[i % groupCount],
          'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_fgrp_${shuffled[i]}',
        });
      }
    });
  }

  // --- No-Show / Removal (attr_id = 10) ---

  Future<Set<int>> getRemovedTeamIds(int tId) async {
    final db = await _dbService.database;
    final rows = await db.query(
      'CMP_TEAM_ATTR',
      where: 't_id = ? AND attr_id = 10 AND attr_value = ?',
      whereArgs: [tId, 'removed'],
    );
    return rows.map((r) => r['team_id'] as int).toSet();
  }

  Future<void> markTeamRemoved(int tId, int teamId) async {
    final db = await _dbService.database;
    final existing = await db.query(
      'CMP_TEAM_ATTR',
      where: 't_id = ? AND team_id = ? AND attr_id = 10',
      whereArgs: [tId, teamId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      await db.update(
        'CMP_TEAM_ATTR',
        {'attr_value': 'removed'},
        where: 'ta_id = ?',
        whereArgs: [existing.first['ta_id']],
      );
    } else {
      await db.insert('CMP_TEAM_ATTR', {
        'team_id': teamId,
        't_id': tId,
        'attr_id': 10,
        'attr_value': 'removed',
        'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_frem_$teamId',
      });
    }
  }

  Future<void> unmarkTeamRemoved(int tId, int teamId) async {
    final db = await _dbService.database;
    await db.delete(
      'CMP_TEAM_ATTR',
      where: 't_id = ? AND team_id = ? AND attr_id = 10 AND attr_value = ?',
      whereArgs: [tId, teamId, 'removed'],
    );
  }

  /// Count the number of no-show events for this team (where the team
  /// scored 0 in a game flagged with es_id = 4).
  Future<int> countNoShows(int tId, int teamId) async {
    final db = await _dbService.database;
    final teamRows = await db.query(
      'CMP_TEAM',
      columns: ['entity_id'],
      where: 'team_id = ?',
      whereArgs: [teamId],
    );
    if (teamRows.isEmpty) return 0;
    final entityId = teamRows.first['entity_id'] as int?;
    if (entityId == null) return 0;

    final rows = await db.rawQuery('''
      SELECT COUNT(DISTINCT e.event_id) as cnt FROM CMP_EVENT e
      JOIN CMP_SUBEVENT se ON se.ev_id = e.event_id AND se.entity_id = ?
      WHERE e.t_id = ? AND e.es_id = 4 AND e.et_id = 2
      AND NOT EXISTS (
        SELECT 1 FROM CMP_SUBEVENT se2
        WHERE se2.ev_id = e.event_id AND se2.entity_id = ?
        AND se2.se_result > 0
      )
    ''', [entityId, tId, entityId]);
    return (rows.first['cnt'] as int?) ?? 0;
  }

  /// Delete every team-vs-team game in this tournament involving [teamId].
  /// Used when a team is removed after a 2nd no-show — per futsal rules,
  /// all of their game results are annulled.
  Future<void> deleteAllTeamGames(int tId, int teamId) async {
    final db = await _dbService.database;
    final teamRows = await db.query(
      'CMP_TEAM',
      columns: ['entity_id'],
      where: 'team_id = ?',
      whereArgs: [teamId],
    );
    if (teamRows.isEmpty) return;
    final entityId = teamRows.first['entity_id'] as int?;
    if (entityId == null) return;

    final events = await db.rawQuery('''
      SELECT DISTINCT e.event_id FROM CMP_EVENT e
      JOIN CMP_SUBEVENT se ON se.ev_id = e.event_id
      WHERE e.t_id = ? AND e.et_id = 2 AND se.entity_id = ?
    ''', [tId, entityId]);

    await db.transaction((txn) async {
      for (final row in events) {
        final eventId = row['event_id'] as int;
        await txn.delete('CMP_SUBEVENT', where: 'ev_id = ?', whereArgs: [eventId]);
        await txn.delete('CMP_EVENT', where: 'event_id = ?', whereArgs: [eventId]);
      }
    });
  }

  /// Clear the "removed" flag for every team in this tournament.
  Future<void> clearAllRemovedState(int tId) async {
    final db = await _dbService.database;
    await db.delete(
      'CMP_TEAM_ATTR',
      where: 't_id = ? AND attr_id = 10',
      whereArgs: [tId],
    );
  }

  /// Public helper: ensure a team entity exists.
  Future<int> ensureTeamEntity(int teamId) async {
    final db = await _dbService.database;
    return _dbService.ensureTeamEntity(db, teamId);
  }
}
