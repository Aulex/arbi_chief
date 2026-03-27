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
}
