import '../../services/database_service.dart';

/// Futsal-specific database operations.
///
/// Handles team-vs-team game CRUD with goal results.
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
  Future<void> saveGoalResult({
    required int eventId,
    required int teamAEntityId,
    required int teamBEntityId,
    required int goalsA,
    required int goalsB,
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

      // Build event_result string
      await txn.update('CMP_EVENT', {
        'event_result': '$goalsA:$goalsB',
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
    })>[];

    for (final event in events) {
      final eventId = event['event_id'] as int;
      final eventResult = event['event_result'] as String?;

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
}
