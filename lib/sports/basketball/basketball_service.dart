import 'dart:math';

import '../../services/database_service.dart';

/// Basketball-specific database operations.
///
/// Handles team-vs-team game CRUD with goal/point results,
/// group assignments, and no-show tracking.
class BasketballService {
  final DatabaseService _dbService;
  BasketballService(this._dbService);

  // --- Team Game CRUD ---

  Future<int> createTeamGame({required int tId, required int teamAId, required int teamBId}) async {
    final db = await _dbService.database;
    final today = DateTime.now().toIso8601String().split('T').first;
    final aEntId = await _dbService.ensureTeamEntity(db, teamAId);
    final bEntId = await _dbService.ensureTeamEntity(db, teamBId);
    final eventId = await db.insert('CMP_EVENT', {'t_id': tId, 'event_date_begin': today, 'et_id': 2});
    await db.insert('CMP_SUBEVENT', {'ev_id': eventId, 'entity_id': aEntId, 'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_ba_se'});
    await db.insert('CMP_SUBEVENT', {'ev_id': eventId, 'entity_id': bEntId, 'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_bb_se'});
    return eventId;
  }

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
      await txn.delete('CMP_SUBEVENT', where: 'ev_id = ?', whereArgs: [eventId]);
      await txn.insert('CMP_SUBEVENT', {'ev_id': eventId, 'entity_id': teamAEntityId, 'se_result': goalsA.toDouble(), 'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_ba_r'});
      await txn.insert('CMP_SUBEVENT', {'ev_id': eventId, 'entity_id': teamBEntityId, 'se_result': goalsB.toDouble(), 'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_bb_r'});
      await txn.update('CMP_EVENT', {'event_result': '$goalsA:$goalsB', 'es_id': esId}, where: 'event_id = ?', whereArgs: [eventId]);
    });
  }

  Future<List<({int eventId, int teamAEntityId, int teamBEntityId, int? teamAId, int? teamBId, String? eventResult, int? esId})>> getTeamGamesForTournament(int tId) async {
    final db = await _dbService.database;
    final events = await db.query('CMP_EVENT', where: 't_id = ? AND et_id = 2', whereArgs: [tId], orderBy: 'event_id');
    final result = <({int eventId, int teamAEntityId, int teamBEntityId, int? teamAId, int? teamBId, String? eventResult, int? esId})>[];
    for (final event in events) {
      final eventId = event['event_id'] as int;
      final eventResult = event['event_result'] as String?;
      final esId = event['es_id'] as int?;
      final subevents = await db.query('CMP_SUBEVENT', where: 'ev_id = ?', whereArgs: [eventId], orderBy: 'se_id');
      if (subevents.isEmpty) continue;
      final entityIds = subevents.map((s) => s['entity_id'] as int).toSet().toList();
      if (entityIds.length < 2) continue;
      final aTeam = await db.query('CMP_TEAM', columns: ['team_id'], where: 'entity_id = ?', whereArgs: [entityIds[0]]);
      final bTeam = await db.query('CMP_TEAM', columns: ['team_id'], where: 'entity_id = ?', whereArgs: [entityIds[1]]);
      result.add((eventId: eventId, teamAEntityId: entityIds[0], teamBEntityId: entityIds[1], teamAId: aTeam.isNotEmpty ? aTeam.first['team_id'] as int? : null, teamBId: bTeam.isNotEmpty ? bTeam.first['team_id'] as int? : null, eventResult: eventResult, esId: esId));
    }
    return result;
  }

  Future<int> findOrCreateTeamGame({required int tId, required int teamAId, required int teamBId}) async {
    final db = await _dbService.database;
    final aEntId = await _dbService.ensureTeamEntity(db, teamAId);
    final bEntId = await _dbService.ensureTeamEntity(db, teamBId);
    final existing = await db.rawQuery('SELECT e.event_id FROM CMP_EVENT e JOIN CMP_SUBEVENT se1 ON se1.ev_id = e.event_id AND se1.entity_id = ? JOIN CMP_SUBEVENT se2 ON se2.ev_id = e.event_id AND se2.entity_id = ? WHERE e.t_id = ? AND e.et_id = 2 GROUP BY e.event_id LIMIT 1', [aEntId, bEntId, tId]);
    if (existing.isNotEmpty) return existing.first['event_id'] as int;
    return createTeamGame(tId: tId, teamAId: teamAId, teamBId: teamBId);
  }

  Future<void> deleteTeamGame(int eventId) async {
    final db = await _dbService.database;
    await db.transaction((txn) async {
      await txn.delete('CMP_SUBEVENT', where: 'ev_id = ?', whereArgs: [eventId]);
      await txn.delete('CMP_EVENT', where: 'event_id = ?', whereArgs: [eventId]);
    });
  }

  // --- No-Show Handling ---

  Future<int> countNoShows(int tId, int teamId) async {
    final db = await _dbService.database;
    final teamRows = await db.query('CMP_TEAM', columns: ['entity_id'], where: 'team_id = ?', whereArgs: [teamId]);
    if (teamRows.isEmpty) return 0;
    final entityId = teamRows.first['entity_id'] as int?;
    if (entityId == null) return 0;

    final rows = await db.rawQuery('''
      SELECT COUNT(DISTINCT e.event_id) as cnt FROM CMP_EVENT e
      JOIN CMP_SUBEVENT se ON se.ev_id = e.event_id AND se.entity_id = ?
      WHERE e.t_id = ? AND e.es_id = 4
      AND NOT EXISTS (
        SELECT 1 FROM CMP_SUBEVENT se2
        WHERE se2.ev_id = e.event_id AND se2.entity_id = ?
        AND se2.se_result > 0
      )
    ''', [entityId, tId, entityId]);
    return (rows.first['cnt'] as int?) ?? 0;
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
      await db.update('CMP_TEAM_ATTR', {'attr_value': 'removed'}, where: 'ta_id = ?', whereArgs: [existing.first['ta_id']]);
    } else {
      await db.insert('CMP_TEAM_ATTR', {
        'team_id': teamId,
        't_id': tId,
        'attr_id': 10,
        'attr_value': 'removed',
        'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_bb_rem_$teamId',
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

  Future<Set<int>> getRemovedTeamIds(int tId) async {
    final db = await _dbService.database;
    final rows = await db.query(
      'CMP_TEAM_ATTR',
      where: 't_id = ? AND attr_id = 10 AND attr_value = ?',
      whereArgs: [tId, 'removed'],
    );
    return rows.map((r) => r['team_id'] as int).toSet();
  }

  Future<void> deleteAllTeamGames(int tId, int teamId) async {
    final db = await _dbService.database;
    final teamRows = await db.query('CMP_TEAM', columns: ['entity_id'], where: 'team_id = ?', whereArgs: [teamId]);
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

  Future<void> clearAllRemovedState(int tId) async {
    final db = await _dbService.database;
    await db.delete('CMP_TEAM_ATTR', where: 't_id = ? AND attr_id = 10', whereArgs: [tId]);
  }

  /// Public wrapper to ensure a team has an entity_id.
  Future<int> ensureTeamEntity(int teamId) async {
    final db = await _dbService.database;
    return _dbService.ensureTeamEntity(db, teamId);
  }

  // --- Group Management ---

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
        'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_bb_grp_$teamId',
      });
    }
  }

  Future<void> clearGroupAssignments(int tId) async {
    final db = await _dbService.database;
    await db.delete('CMP_TEAM_ATTR', where: 't_id = ? AND attr_id = 11', whereArgs: [tId]);
  }

  Future<void> autoAssignGroups(int tId, List<int> teamIds) async {
    if (teamIds.isEmpty) return;
    final db = await _dbService.database;

    final teamCount = teamIds.length;
    int groupCount;
    if (teamCount <= 8) {
      groupCount = 1;
    } else {
      // Basketball rules: groups of 3-5 teams
      groupCount = (teamCount / 4).ceil();
      while (groupCount > 1 && (teamCount / groupCount) < 3) {
        groupCount--;
      }
      while ((teamCount / groupCount) > 5) {
        groupCount++;
      }
    }

    final shuffled = List<int>.from(teamIds)..shuffle(Random());
    final groupNames = List.generate(groupCount, (i) => String.fromCharCode(65 + i));

    await db.transaction((txn) async {
      await txn.delete('CMP_TEAM_ATTR', where: 't_id = ? AND attr_id = 11', whereArgs: [tId]);

      for (int i = 0; i < shuffled.length; i++) {
        final groupName = groupNames[i % groupCount];
        await txn.insert('CMP_TEAM_ATTR', {
          'team_id': shuffled[i],
          't_id': tId,
          'attr_id': 11,
          'attr_value': groupName,
          'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_bb_grp_${shuffled[i]}',
        });
      }
    });
  }
}
