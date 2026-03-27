import '../../services/database_service.dart';

/// Tug of War-specific database operations.
class TugOfWarService {
  final DatabaseService _dbService;
  TugOfWarService(this._dbService);

  Future<int> createTeamGame({required int tId, required int teamAId, required int teamBId}) async {
    final db = await _dbService.database;
    final today = DateTime.now().toIso8601String().split('T').first;
    final aEntId = await _dbService.ensureTeamEntity(db, teamAId);
    final bEntId = await _dbService.ensureTeamEntity(db, teamBId);
    final eventId = await db.insert('CMP_EVENT', {'t_id': tId, 'event_date_begin': today, 'et_id': 2});
    await db.insert('CMP_SUBEVENT', {'ev_id': eventId, 'entity_id': aEntId, 'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_ta_se'});
    await db.insert('CMP_SUBEVENT', {'ev_id': eventId, 'entity_id': bEntId, 'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_tb_se'});
    return eventId;
  }

  /// Save win/loss result. [winnerId] is the entity_id of the winning team.
  Future<void> saveResult({required int eventId, required int teamAEntityId, required int teamBEntityId, required int winnerEntityId}) async {
    final db = await _dbService.database;
    final aWins = winnerEntityId == teamAEntityId;
    await db.transaction((txn) async {
      await txn.delete('CMP_SUBEVENT', where: 'ev_id = ?', whereArgs: [eventId]);
      await txn.insert('CMP_SUBEVENT', {'ev_id': eventId, 'entity_id': teamAEntityId, 'se_result': aWins ? 1.0 : 0.0, 'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_ta_r'});
      await txn.insert('CMP_SUBEVENT', {'ev_id': eventId, 'entity_id': teamBEntityId, 'se_result': aWins ? 0.0 : 1.0, 'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_tb_r'});
      await txn.update('CMP_EVENT', {'event_result': aWins ? '1:0' : '0:1'}, where: 'event_id = ?', whereArgs: [eventId]);
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

  /// Save team weight (kg) via CMP_TEAM_ATTR attr_id=16.
  Future<void> saveTeamWeight(int tId, int teamId, double weight) async {
    final db = await _dbService.database;
    final existing = await db.query(
      'CMP_TEAM_ATTR',
      where: 't_id = ? AND team_id = ? AND attr_id = 16',
      whereArgs: [tId, teamId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      await db.update(
        'CMP_TEAM_ATTR',
        {'attr_value': weight.toString()},
        where: 'ta_id = ?',
        whereArgs: [existing.first['ta_id']],
      );
    } else {
      await db.insert('CMP_TEAM_ATTR', {
        'team_id': teamId,
        't_id': tId,
        'attr_id': 16,
        'attr_value': weight.toString(),
        'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_tw_$teamId',
      });
    }
  }

  /// Get team weights for a tournament. Returns Map<teamId, weightKg>.
  Future<Map<int, double>> getTeamWeights(int tId) async {
    final db = await _dbService.database;
    final rows = await db.query(
      'CMP_TEAM_ATTR',
      where: 't_id = ? AND attr_id = 16',
      whereArgs: [tId],
    );
    final result = <int, double>{};
    for (final r in rows) {
      final teamId = r['team_id'] as int;
      final w = double.tryParse(r['attr_value'] as String? ?? '');
      if (w != null) result[teamId] = w;
    }
    return result;
  }
}
