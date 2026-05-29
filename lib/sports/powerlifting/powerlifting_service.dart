import '../../services/database_service.dart';

/// Powerlifting database service.
///
/// Stores, per athlete in a tournament:
///   * weight category   — CMP_PLAYER_TEAM_ATTR_VALUE attr_id = 15
///   * body weight (kg)   — CMP_PLAYER_TEAM_ATTR_VALUE attr_id = 17
///   * lot / start order  — CMP_PLAYER_TEAM_ATTR_VALUE attr_id = 25
///   * nine lift attempts — CMP_SUBEVENT rows keyed by se_note
///
/// Each attempt is stored as a CMP_SUBEVENT row whose se_note is one of
/// 'sq1','sq2','sq3','bp1','bp2','bp3','dl1','dl2','dl3'. se_result holds the
/// barbell weight in kg: a positive value is a good lift, a negative value is a
/// failed ("no") lift at that weight, and an absent row means the attempt was
/// not taken.
class PowerliftingService {
  final DatabaseService _dbService;

  PowerliftingService(this._dbService);

  static const List<String> squatKeys = ['sq1', 'sq2', 'sq3'];
  static const List<String> benchKeys = ['bp1', 'bp2', 'bp3'];
  static const List<String> deadliftKeys = ['dl1', 'dl2', 'dl3'];
  static const List<String> allAttemptKeys = [
    'sq1', 'sq2', 'sq3', 'bp1', 'bp2', 'bp3', 'dl1', 'dl2', 'dl3', //
  ];

  Future<int> _ensureEventId(int tId) async {
    final db = await _dbService.database;
    final events = await db.query('CMP_EVENT',
        columns: ['event_id'], where: 't_id = ? AND et_id = 1', whereArgs: [tId]);
    if (events.isNotEmpty) return events.first['event_id'] as int;
    final today = DateTime.now().toIso8601String().split('T').first;
    return db.insert('CMP_EVENT', {
      't_id': tId,
      'event_date_begin': today,
      'et_id': 1,
      'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_pl_ev',
    });
  }

  Future<int?> _entityId(int playerId) async {
    final db = await _dbService.database;
    final rows = await db.query('CMP_PLAYER',
        columns: ['entity_id'], where: 'player_id = ?', whereArgs: [playerId]);
    if (rows.isEmpty) return null;
    return rows.first['entity_id'] as int;
  }

  /// Saves a single attempt. [kg] of 0 removes the attempt; otherwise [good]
  /// distinguishes a successful lift from a failed one.
  Future<void> saveAttempt({
    required int tId,
    required int playerId,
    required String attemptKey,
    required double kg,
    required bool good,
  }) async {
    final db = await _dbService.database;
    final entityId = await _entityId(playerId);
    if (entityId == null) return;
    final eventId = await _ensureEventId(tId);

    final existing = await db.query('CMP_SUBEVENT',
        columns: ['se_id'],
        where: 'ev_id = ? AND entity_id = ? AND se_note = ?',
        whereArgs: [eventId, entityId, attemptKey]);

    if (kg <= 0) {
      if (existing.isNotEmpty) {
        await db.delete('CMP_SUBEVENT',
            where: 'se_id = ?', whereArgs: [existing.first['se_id']]);
      }
      return;
    }

    final value = good ? kg : -kg;
    if (existing.isNotEmpty) {
      await db.update('CMP_SUBEVENT', {'se_result': value},
          where: 'se_id = ?', whereArgs: [existing.first['se_id']]);
    } else {
      await db.insert('CMP_SUBEVENT', {
        'ev_id': eventId,
        'entity_id': entityId,
        'se_result': value,
        'se_note': attemptKey,
        'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_pl_$attemptKey',
      });
    }
  }

  /// Returns Map<playerId, Map<attemptKey, ({double kg, bool good})>>.
  Future<Map<int, Map<String, ({double kg, bool good})>>> getAttempts(
      int tId) async {
    final db = await _dbService.database;
    final rows = await db.rawQuery('''
      SELECT p.player_id, se.se_note, se.se_result
      FROM CMP_EVENT e
      JOIN CMP_SUBEVENT se ON se.ev_id = e.event_id
      JOIN CMP_PLAYER p ON p.entity_id = se.entity_id
      WHERE e.t_id = ? AND e.et_id = 1
        AND se.se_note IN ('sq1','sq2','sq3','bp1','bp2','bp3','dl1','dl2','dl3')
        AND se.se_result IS NOT NULL
    ''', [tId]);

    final map = <int, Map<String, ({double kg, bool good})>>{};
    for (final r in rows) {
      final pid = r['player_id'] as int;
      final key = r['se_note'] as String;
      final raw = (r['se_result'] as num).toDouble();
      map.putIfAbsent(pid, () => {})[key] = (kg: raw.abs(), good: raw > 0);
    }
    return map;
  }

  /// Best valid (good) lift in kg per discipline for each player.
  Future<Map<int, ({double squat, double bench, double deadlift})>> getBestLifts(
      int tId) async {
    final attempts = await getAttempts(tId);
    final result = <int, ({double squat, double bench, double deadlift})>{};
    attempts.forEach((pid, byKey) {
      double best(List<String> keys) {
        double b = 0;
        for (final k in keys) {
          final a = byKey[k];
          if (a != null && a.good && a.kg > b) b = a.kg;
        }
        return b;
      }

      result[pid] = (
        squat: best(squatKeys),
        bench: best(benchKeys),
        deadlift: best(deadliftKeys),
      );
    });
    return result;
  }

  Future<int?> _pteId(int playerId, int tId) async {
    final db = await _dbService.database;
    final rows = await db.query('CMP_PLAYER_TEAM',
        columns: ['pte_id'],
        where: 'player_id = ? AND t_id = ?',
        whereArgs: [playerId, tId],
        limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['pte_id'] as int;
  }

  Future<void> _saveAttr(
      {required int playerId,
      required int tId,
      required int attrId,
      required String value}) async {
    final db = await _dbService.database;
    final pteId = await _pteId(playerId, tId);
    if (pteId == null) return;
    await db.delete('CMP_PLAYER_TEAM_ATTR_VALUE',
        where: 'pte_id = ? AND attr_id = ?', whereArgs: [pteId, attrId]);
    await db.insert('CMP_PLAYER_TEAM_ATTR_VALUE', {
      'pte_id': pteId,
      'attr_id': attrId,
      'attr_value': value,
      'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_a${attrId}_$playerId',
    });
  }

  Future<Map<int, String>> _loadAttr(int tId, int attrId) async {
    final db = await _dbService.database;
    final rows = await db.rawQuery('''
      SELECT pt.player_id, v.attr_value
      FROM CMP_PLAYER_TEAM pt
      JOIN CMP_PLAYER_TEAM_ATTR_VALUE v ON pt.pte_id = v.pte_id
      WHERE pt.t_id = ? AND v.attr_id = ? AND v.attr_value IS NOT NULL
    ''', [tId, attrId]);
    return {for (final r in rows) r['player_id'] as int: r['attr_value'] as String};
  }

  Future<void> savePlayerCategory(
          {required int playerId, required int tId, required String category}) =>
      _saveAttr(playerId: playerId, tId: tId, attrId: 15, value: category);

  Future<Map<int, String>> getPlayerCategories(int tId) => _loadAttr(tId, 15);

  Future<void> savePlayerWeight(
          {required int playerId, required int tId, required double weight}) =>
      _saveAttr(
          playerId: playerId, tId: tId, attrId: 17, value: weight.toString());

  Future<Map<int, double>> getPlayerWeights(int tId) async {
    final raw = await _loadAttr(tId, 17);
    final map = <int, double>{};
    raw.forEach((pid, v) {
      final w = double.tryParse(v);
      if (w != null) map[pid] = w;
    });
    return map;
  }

  Future<void> savePlayerLot(
          {required int playerId, required int tId, required int lot}) =>
      _saveAttr(playerId: playerId, tId: tId, attrId: 25, value: lot.toString());

  Future<Map<int, int>> getPlayerLots(int tId) async {
    final raw = await _loadAttr(tId, 25);
    final map = <int, int>{};
    raw.forEach((pid, v) {
      final l = int.tryParse(v);
      if (l != null) map[pid] = l;
    });
    return map;
  }
}
