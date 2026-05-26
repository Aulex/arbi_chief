import '../../services/database_service.dart';

/// Kettlebell database service.
/// Simply stores the individual place (rank) achieved by each participant.
class KettlebellService {
  final DatabaseService _dbService;

  KettlebellService(this._dbService);

  Future<void> savePlayerPlace({
    required int tId,
    required int playerId,
    required int teamId,
    required int place,
  }) async {
    final db = await _dbService.database;
    final rows = await db.query('CMP_PLAYER', columns: ['entity_id'], where: 'player_id = ?', whereArgs: [playerId]);
    if (rows.isEmpty) return;
    final entityId = rows.first['entity_id'] as int;

    final events = await db.query('CMP_EVENT', columns: ['event_id'], where: 't_id = ? AND et_id = 1', whereArgs: [tId]);
    int eventId;
    if (events.isEmpty) {
      final today = DateTime.now().toIso8601String().split('T').first;
      eventId = await db.insert('CMP_EVENT', {
        't_id': tId,
        'event_date_begin': today,
        'et_id': 1,
        'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_kb_ev',
      });
    } else {
      eventId = events.first['event_id'] as int;
    }

    final subRows = await db.query('CMP_SUBEVENT', columns: ['se_id'], where: 'ev_id = ? AND entity_id = ?', whereArgs: [eventId, entityId]);
    if (subRows.isNotEmpty) {
      await db.update('CMP_SUBEVENT', {
        'se_result': place.toDouble(),
      }, where: 'se_id = ?', whereArgs: [subRows.first['se_id']]);
    } else {
      await db.insert('CMP_SUBEVENT', {
        'ev_id': eventId,
        'entity_id': entityId,
        'se_result': place.toDouble(),
        'se_note': 'place',
        'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_kb_se',
      });
    }
  }

  /// Remove a stored place for [playerId] (used when ranking changes and the
  /// player no longer has any valid reps).
  Future<void> clearPlayerPlace({required int tId, required int playerId}) async {
    final db = await _dbService.database;
    final pRows = await db.query('CMP_PLAYER', columns: ['entity_id'], where: 'player_id = ?', whereArgs: [playerId]);
    if (pRows.isEmpty) return;
    final entityId = pRows.first['entity_id'] as int;
    final evRows = await db.query('CMP_EVENT', columns: ['event_id'], where: 't_id = ? AND et_id = 1', whereArgs: [tId]);
    if (evRows.isEmpty) return;
    final eventId = evRows.first['event_id'] as int;
    await db.delete('CMP_SUBEVENT', where: 'ev_id = ? AND entity_id = ?', whereArgs: [eventId, entityId]);
  }

  Future<Map<int, int>> getPlayerPlaces(int tId) async {
    final db = await _dbService.database;
    final rows = await db.rawQuery('''
      SELECT p.player_id, se.se_result as place
      FROM CMP_EVENT e
      JOIN CMP_SUBEVENT se ON se.ev_id = e.event_id
      JOIN CMP_PLAYER p ON p.entity_id = se.entity_id
      WHERE e.t_id = ? AND e.et_id = 1 AND se.se_result IS NOT NULL
    ''', [tId]);

    final map = <int, int>{};
    for (final r in rows) {
      map[r['player_id'] as int] = (r['place'] as num).toInt();
    }
    return map;
  }

  Future<void> savePlayerCategory({required int playerId, required int tId, required String category}) async {
    final db = await _dbService.database;
    final pteRows = await db.query('CMP_PLAYER_TEAM', columns: ['pte_id'],
      where: 'player_id = ? AND t_id = ?', whereArgs: [playerId, tId], limit: 1);
    if (pteRows.isEmpty) return;
    final pteId = pteRows.first['pte_id'] as int;
    await db.delete('CMP_PLAYER_TEAM_ATTR_VALUE', where: 'pte_id = ? AND attr_id = 15', whereArgs: [pteId]);
    await db.insert('CMP_PLAYER_TEAM_ATTR_VALUE', {
      'pte_id': pteId, 'attr_id': 15, 'attr_value': category,
      'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_cat_$playerId',
    });
  }

  Future<Map<int, String>> getPlayerCategories(int tId) async {
    final db = await _dbService.database;
    final rows = await db.rawQuery('''
      SELECT pt.player_id, v.attr_value
      FROM CMP_PLAYER_TEAM pt
      JOIN CMP_PLAYER_TEAM_ATTR_VALUE v ON pt.pte_id = v.pte_id
      WHERE pt.t_id = ? AND v.attr_id = 15 AND v.attr_value IS NOT NULL
    ''', [tId]);
    return {for (final r in rows) r['player_id'] as int: r['attr_value'] as String};
  }

  /// Save player body weight (kg) via attr_id=17.
  Future<void> savePlayerWeight({required int playerId, required int tId, required double weight}) async {
    final db = await _dbService.database;
    final pteRows = await db.query('CMP_PLAYER_TEAM', columns: ['pte_id'],
      where: 'player_id = ? AND t_id = ?', whereArgs: [playerId, tId], limit: 1);
    if (pteRows.isEmpty) return;
    final pteId = pteRows.first['pte_id'] as int;
    await db.delete('CMP_PLAYER_TEAM_ATTR_VALUE', where: 'pte_id = ? AND attr_id = 17', whereArgs: [pteId]);
    await db.insert('CMP_PLAYER_TEAM_ATTR_VALUE', {
      'pte_id': pteId, 'attr_id': 17, 'attr_value': weight.toString(),
      'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_pw_$playerId',
    });
  }

  /// Save kettlebell gear weight (kg) via attr_id=24.
  Future<void> saveKettlebellWeight({required int playerId, required int tId, required double kettlebellWeight}) async {
    final db = await _dbService.database;
    final pteRows = await db.query('CMP_PLAYER_TEAM', columns: ['pte_id'],
      where: 'player_id = ? AND t_id = ?', whereArgs: [playerId, tId], limit: 1);
    if (pteRows.isEmpty) return;
    final pteId = pteRows.first['pte_id'] as int;
    await db.delete('CMP_PLAYER_TEAM_ATTR_VALUE', where: 'pte_id = ? AND attr_id = 24', whereArgs: [pteId]);
    await db.insert('CMP_PLAYER_TEAM_ATTR_VALUE', {
      'pte_id': pteId, 'attr_id': 24, 'attr_value': kettlebellWeight.toString(),
      'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_kw_$playerId',
    });
  }

  /// Save per-hand rep counts. Right hand → attr_id=22, left hand → attr_id=23.
  Future<void> savePlayerReps({
    required int playerId,
    required int tId,
    required int rightReps,
    required int leftReps,
  }) async {
    final db = await _dbService.database;
    final pteRows = await db.query('CMP_PLAYER_TEAM', columns: ['pte_id'],
      where: 'player_id = ? AND t_id = ?', whereArgs: [playerId, tId], limit: 1);
    if (pteRows.isEmpty) return;
    final pteId = pteRows.first['pte_id'] as int;
    for (final pair in [(22, rightReps), (23, leftReps)]) {
      final attrId = pair.$1;
      final value = pair.$2;
      await db.delete(
        'CMP_PLAYER_TEAM_ATTR_VALUE',
        where: 'pte_id = ? AND attr_id = ?',
        whereArgs: [pteId, attrId],
      );
      await db.insert('CMP_PLAYER_TEAM_ATTR_VALUE', {
        'pte_id': pteId,
        'attr_id': attrId,
        'attr_value': value.toString(),
        'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_kbr${attrId}_$playerId',
      });
    }
  }

  /// Map<playerId, (right, left)> for every kettlebell participant.
  Future<Map<int, ({int right, int left})>> getPlayerReps(int tId) async {
    final db = await _dbService.database;
    final rows = await db.rawQuery('''
      SELECT pt.player_id, v.attr_id, v.attr_value
      FROM CMP_PLAYER_TEAM pt
      JOIN CMP_PLAYER_TEAM_ATTR_VALUE v ON pt.pte_id = v.pte_id
      WHERE pt.t_id = ? AND v.attr_id IN (22, 23) AND v.attr_value IS NOT NULL
    ''', [tId]);
    final right = <int, int>{};
    final left = <int, int>{};
    for (final r in rows) {
      final pid = r['player_id'] as int;
      final aid = r['attr_id'] as int;
      final v = int.tryParse(r['attr_value'] as String? ?? '');
      if (v == null) continue;
      if (aid == 22) {
        right[pid] = v;
      } else {
        left[pid] = v;
      }
    }
    final out = <int, ({int right, int left})>{};
    for (final pid in {...right.keys, ...left.keys}) {
      out[pid] = (right: right[pid] ?? 0, left: left[pid] ?? 0);
    }
    return out;
  }

  /// Get kettlebell gear weights for a tournament. Returns Map<playerId, weightKg>.
  Future<Map<int, double>> getKettlebellWeights(int tId) async {
    final db = await _dbService.database;
    final rows = await db.rawQuery('''
      SELECT pt.player_id, v.attr_value
      FROM CMP_PLAYER_TEAM pt
      JOIN CMP_PLAYER_TEAM_ATTR_VALUE v ON pt.pte_id = v.pte_id
      WHERE pt.t_id = ? AND v.attr_id = 24 AND v.attr_value IS NOT NULL
    ''', [tId]);
    final map = <int, double>{};
    for (final r in rows) {
      final w = double.tryParse(r['attr_value'] as String? ?? '');
      if (w != null) map[r['player_id'] as int] = w;
    }
    return map;
  }

  /// Get player weights for a tournament. Returns Map<playerId, weightKg>.
  Future<Map<int, double>> getPlayerWeights(int tId) async {
    final db = await _dbService.database;
    final rows = await db.rawQuery('''
      SELECT pt.player_id, v.attr_value
      FROM CMP_PLAYER_TEAM pt
      JOIN CMP_PLAYER_TEAM_ATTR_VALUE v ON pt.pte_id = v.pte_id
      WHERE pt.t_id = ? AND v.attr_id = 17 AND v.attr_value IS NOT NULL
    ''', [tId]);
    final map = <int, double>{};
    for (final r in rows) {
      final w = double.tryParse(r['attr_value'] as String? ?? '');
      if (w != null) map[r['player_id'] as int] = w;
    }
    return map;
  }
}
