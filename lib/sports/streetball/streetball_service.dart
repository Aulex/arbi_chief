import 'dart:math';

import '../../services/database_service.dart';

/// Streetball-specific database operations.
class StreetballService {
  final DatabaseService _dbService;
  StreetballService(this._dbService);

  Future<int> createTeamGame({required int tId, required int teamAId, required int teamBId}) async {
    final db = await _dbService.database;
    final today = DateTime.now().toIso8601String().split('T').first;
    final aEntId = await _dbService.ensureTeamEntity(db, teamAId);
    final bEntId = await _dbService.ensureTeamEntity(db, teamBId);
    final eventId = await db.insert('CMP_EVENT', {'t_id': tId, 'event_date_begin': today, 'et_id': 2});
    await db.insert('CMP_SUBEVENT', {'ev_id': eventId, 'entity_id': aEntId, 'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_sa_se'});
    await db.insert('CMP_SUBEVENT', {'ev_id': eventId, 'entity_id': bEntId, 'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_sb_se'});
    return eventId;
  }

  Future<void> saveGoalResult({required int eventId, required int teamAEntityId, required int teamBEntityId, required int goalsA, required int goalsB}) async {
    final db = await _dbService.database;
    await db.transaction((txn) async {
      await txn.delete('CMP_SUBEVENT', where: 'ev_id = ?', whereArgs: [eventId]);
      await txn.insert('CMP_SUBEVENT', {'ev_id': eventId, 'entity_id': teamAEntityId, 'se_result': goalsA.toDouble(), 'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_sa_r'});
      await txn.insert('CMP_SUBEVENT', {'ev_id': eventId, 'entity_id': teamBEntityId, 'se_result': goalsB.toDouble(), 'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_sb_r'});
      await txn.update('CMP_EVENT', {'event_result': '$goalsA:$goalsB'}, where: 'event_id = ?', whereArgs: [eventId]);
    });
  }

  Future<List<({int eventId, int teamAEntityId, int teamBEntityId, int? teamAId, int? teamBId, String? eventResult})>> getTeamGamesForTournament(int tId) async {
    final db = await _dbService.database;
    final events = await db.query('CMP_EVENT', where: 't_id = ? AND et_id = 2', whereArgs: [tId], orderBy: 'event_id');
    final result = <({int eventId, int teamAEntityId, int teamBEntityId, int? teamAId, int? teamBId, String? eventResult})>[];
    for (final event in events) {
      final eventId = event['event_id'] as int;
      final eventResult = event['event_result'] as String?;
      final subevents = await db.query('CMP_SUBEVENT', where: 'ev_id = ?', whereArgs: [eventId], orderBy: 'se_id');
      if (subevents.isEmpty) continue;
      final entityIds = subevents.map((s) => s['entity_id'] as int).toSet().toList();
      if (entityIds.length < 2) continue;
      final aTeam = await db.query('CMP_TEAM', columns: ['team_id'], where: 'entity_id = ?', whereArgs: [entityIds[0]]);
      final bTeam = await db.query('CMP_TEAM', columns: ['team_id'], where: 'entity_id = ?', whereArgs: [entityIds[1]]);
      result.add((eventId: eventId, teamAEntityId: entityIds[0], teamBEntityId: entityIds[1], teamAId: aTeam.isNotEmpty ? aTeam.first['team_id'] as int? : null, teamBId: bTeam.isNotEmpty ? bTeam.first['team_id'] as int? : null, eventResult: eventResult));
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

  // --- Group Management (same approach as Volleyball) ---

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
        'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_sb_grp_$teamId',
      });
    }
  }

  /// Clear all group assignments for a tournament.
  Future<void> clearGroupAssignments(int tId) async {
    final db = await _dbService.database;
    await db.delete('CMP_TEAM_ATTR', where: 't_id = ? AND attr_id = 11', whereArgs: [tId]);
  }

  /// Auto-assign groups: for 9+ teams create balanced groups of 3-5 teams.
  Future<void> autoAssignGroups(int tId, List<int> teamIds) async {
    if (teamIds.isEmpty) return;
    final db = await _dbService.database;

    final teamCount = teamIds.length;
    int groupCount;
    if (teamCount <= 8) {
      groupCount = 1;
    } else {
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
          'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_sb_grp_${shuffled[i]}',
        });
      }
    });
  }
}
