import 'dart:math';
import '../../services/database_service.dart';

/// Volleyball-specific database operations.
///
/// Handles team-vs-team game CRUD with multi-set results,
/// group assignments, and no-show tracking.
class VolleyballService {
  final DatabaseService _dbService;
  VolleyballService(this._dbService);

  // --- Team Game CRUD ---

  /// Create a game between two teams and return the event_id.
  Future<int> createTeamGame({
    required int tId,
    required int teamAId,
    required int teamBId,
  }) async {
    final db = await _dbService.database;
    final today = DateTime.now().toIso8601String().split('T').first;

    final aEntId = await _ensureTeamEntity(db, teamAId);
    final bEntId = await _ensureTeamEntity(db, teamBId);

    final eventId = await db.insert('CMP_EVENT', {
      't_id': tId,
      'event_date_begin': today,
      'et_id': 2, // Командний
    });

    await db.insert('CMP_SUBEVENT', {
      'ev_id': eventId,
      'entity_id': aEntId,
      'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_va_se',
    });
    await db.insert('CMP_SUBEVENT', {
      'ev_id': eventId,
      'entity_id': bEntId,
      'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_vb_se',
    });

    return eventId;
  }

  /// Save set results for a volleyball match.
  /// [sets] is a list of (teamAScore, teamBScore) per set.
  Future<void> saveSetResults({
    required int eventId,
    required int teamAEntityId,
    required int teamBEntityId,
    required List<({int a, int b})> sets,
    int? esId,
  }) async {
    final db = await _dbService.database;

    await db.transaction((txn) async {
      // Clear old subevents
      await txn.delete('CMP_SUBEVENT', where: 'ev_id = ?', whereArgs: [eventId]);

      // Insert per-set results
      for (int i = 0; i < sets.length; i++) {
        final set = sets[i];
        await txn.insert('CMP_SUBEVENT', {
          'ev_id': eventId,
          'entity_id': teamAEntityId,
          'se_result': set.a.toDouble(),
          'se_note': 'Set ${i + 1}',
          'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_va_s$i',
        });
        await txn.insert('CMP_SUBEVENT', {
          'ev_id': eventId,
          'entity_id': teamBEntityId,
          'se_result': set.b.toDouble(),
          'se_note': 'Set ${i + 1}',
          'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_vb_s$i',
        });
      }

      // Determine winner from sets
      int aWon = 0, bWon = 0;
      for (final set in sets) {
        if (set.a > set.b) {
          aWon++;
        } else if (set.b > set.a) {
          bWon++;
        }
      }

      // Build event_result string ("2:1", "2:0", etc.)
      final eventResult = '$aWon:$bWon';

      await txn.update('CMP_EVENT', {
        'event_result': eventResult,
        'es_id': esId,
      }, where: 'event_id = ?', whereArgs: [eventId]);
    });
  }

  /// Get all team games for a tournament with set details.
  Future<List<({
    int eventId,
    int teamAEntityId,
    int teamBEntityId,
    int? teamAId,
    int? teamBId,
    String? eventResult,
    int? esId,
    String? teamADetail,
    String? teamBDetail,
  })>> getTeamGamesForTournament(int tId) async {
    final db = await _dbService.database;

    // Get all team events for this tournament
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
      String? teamADetail,
      String? teamBDetail,
    })>[];

    for (final event in events) {
      final eventId = event['event_id'] as int;
      final eventResult = event['event_result'] as String?;
      final esId = event['es_id'] as int?;

      // Get the two participating team entities
      final subevents = await db.query(
        'CMP_SUBEVENT',
        where: 'ev_id = ?',
        whereArgs: [eventId],
        orderBy: 'se_id',
      );

      if (subevents.isEmpty) continue;

      // Get distinct entity_ids
      final entityIds = subevents.map((s) => s['entity_id'] as int).toSet().toList();
      if (entityIds.length < 2) continue;

      final aEntId = entityIds[0];
      final bEntId = entityIds[1];

      // Look up team_ids from entity_ids
      final aTeam = await db.query('CMP_TEAM', columns: ['team_id'], where: 'entity_id = ?', whereArgs: [aEntId]);
      final bTeam = await db.query('CMP_TEAM', columns: ['team_id'], where: 'entity_id = ?', whereArgs: [bEntId]);

      final aTeamId = aTeam.isNotEmpty ? aTeam.first['team_id'] as int? : null;
      final bTeamId = bTeam.isNotEmpty ? bTeam.first['team_id'] as int? : null;

      // Build detail strings from subevents
      final aSubs = subevents.where((s) => s['entity_id'] == aEntId).toList();
      final bSubs = subevents.where((s) => s['entity_id'] == bEntId).toList();

      String? aDetail;
      String? bDetail;
      if (aSubs.length > 1 || (aSubs.length == 1 && aSubs.first['se_result'] != null)) {
        // Multi-set: reconstruct "25:20 25:18"
        final setScores = <String>[];
        for (int i = 0; i < aSubs.length; i++) {
          final aScore = (aSubs[i]['se_result'] as num?)?.toInt() ?? 0;
          final bScore = i < bSubs.length ? (bSubs[i]['se_result'] as num?)?.toInt() ?? 0 : 0;
          if (aScore == 0 && bScore == 0 && aSubs[i]['se_result'] == null) continue;
          setScores.add('$aScore:$bScore');
        }
        if (setScores.isNotEmpty) {
          aDetail = setScores.join(' ');
          bDetail = setScores.map((s) {
            final parts = s.split(':');
            return '${parts[1]}:${parts[0]}';
          }).join(' ');
        }
      }

      result.add((
        eventId: eventId,
        teamAEntityId: aEntId,
        teamBEntityId: bEntId,
        teamAId: aTeamId,
        teamBId: bTeamId,
        eventResult: eventResult,
        esId: esId,
        teamADetail: aDetail,
        teamBDetail: bDetail,
      ));
    }

    return result;
  }

  // --- Group Management ---

  /// Get group assignments for all teams in a tournament.
  /// Returns Map<teamId, groupName>.
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

  /// Set group assignment for a team.
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
        'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_grp_$teamId',
      });
    }
  }

  /// Clear all group assignments for a tournament.
  Future<void> clearGroupAssignments(int tId) async {
    final db = await _dbService.database;
    await db.delete('CMP_TEAM_ATTR', where: 't_id = ? AND attr_id = 11', whereArgs: [tId]);
  }

  /// Auto-assign groups: shuffle teams and distribute into two groups
  /// when 9 or more teams, otherwise groups of 3-5.
  Future<void> autoAssignGroups(int tId, List<int> teamIds) async {
    if (teamIds.isEmpty) return;
    final db = await _dbService.database;

    final groupCount = teamIds.length >= 9
        ? 2
        : (teamIds.length / 4).ceil().clamp(1, teamIds.length);
    final shuffled = List<int>.from(teamIds)..shuffle(Random());

    // Group names: A, B, C, ...
    final groupNames = List.generate(groupCount, (i) => String.fromCharCode(65 + i));

    await db.transaction((txn) async {
      // Clear existing group assignments
      await txn.delete('CMP_TEAM_ATTR', where: 't_id = ? AND attr_id = 11', whereArgs: [tId]);

      // Distribute teams round-robin style
      for (int i = 0; i < shuffled.length; i++) {
        final groupName = groupNames[i % groupCount];
        await txn.insert('CMP_TEAM_ATTR', {
          'team_id': shuffled[i],
          't_id': tId,
          'attr_id': 11,
          'attr_value': groupName,
          'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_grp_${shuffled[i]}',
        });
      }
    });
  }

  // --- No-Show Handling ---

  /// Count no-show events for a team in a tournament.
  /// A no-show is an event where es_id=4 and the team participated.
  Future<int> countNoShows(int tId, int teamId) async {
    final db = await _dbService.database;
    final teamRows = await db.query('CMP_TEAM', columns: ['entity_id'], where: 'team_id = ?', whereArgs: [teamId]);
    if (teamRows.isEmpty) return 0;
    final entityId = teamRows.first['entity_id'] as int?;
    if (entityId == null) return 0;

    final rows = await db.rawQuery('''
      SELECT COUNT(*) as cnt FROM CMP_EVENT e
      JOIN CMP_SUBEVENT se ON se.ev_id = e.event_id
      WHERE e.t_id = ? AND e.es_id = 4 AND se.entity_id = ?
    ''', [tId, entityId]);

    return (rows.first['cnt'] as int?) ?? 0;
  }

  /// Mark a team as removed (after 2nd no-show).
  /// Uses CMP_TEAM_ATTR with attr_id=10 (Неявка), attr_value='removed'.

  /// Get team IDs that had at least one no-show event in this tournament.
  /// Used by tiebreaker logic to exclude games against no-show teams.
  Future<Set<int>> getNoShowTeamIds(int tId) async {
    final db = await _dbService.database;
    final rows = await db.rawQuery('''
      SELECT DISTINCT t.team_id FROM CMP_EVENT e
      JOIN CMP_SUBEVENT se ON se.ev_id = e.event_id
      JOIN CMP_TEAM t ON t.entity_id = se.entity_id
      WHERE e.t_id = ? AND e.es_id = 4
    ''', [tId]);
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
        'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_rem_$teamId',
      });
    }
  }

  /// Get set of removed team IDs for a tournament.
  Future<Set<int>> getRemovedTeamIds(int tId) async {
    final db = await _dbService.database;
    final rows = await db.query(
      'CMP_TEAM_ATTR',
      where: 't_id = ? AND attr_id = 10 AND attr_value = ?',
      whereArgs: [tId, 'removed'],
    );
    return rows.map((r) => r['team_id'] as int).toSet();
  }

  // --- Helpers ---

  Future<int> _ensureTeamEntity(dynamic db, int teamId) async {
    return _dbService.ensureTeamEntity(db, teamId);
  }

  /// Public wrapper to ensure a team has an entity_id.
  Future<int> ensureTeamEntity(int teamId) async {
    final db = await _dbService.database;
    return _dbService.ensureTeamEntity(db, teamId);
  }

  /// Find or create a game between two teams. Returns the event_id.
  Future<int> findOrCreateTeamGame({
    required int tId,
    required int teamAId,
    required int teamBId,
  }) async {
    final db = await _dbService.database;
    final aEntId = await _ensureTeamEntity(db, teamAId);
    final bEntId = await _ensureTeamEntity(db, teamBId);

    // Check if game already exists
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
}
