import 'package:sqflite/sqflite.dart';
import '../../services/database_service.dart';

/// Table tennis specific game service methods.
///
/// Handles multi-set result saving/reading that is unique to table tennis.
/// General game CRUD (createGame, deleteGame, etc.) remains in TournamentService.
class TableTennisService {
  final DatabaseService _dbService;
  TableTennisService(this._dbService);

  /// Save table tennis match result with set-by-set scores.
  /// [rowDetail] is the detail string for the row player (e.g. "11:7 11:4 8:11").
  /// [colDetail] is the mirror detail for the opponent (e.g. "7:11 4:11 11:8").
  /// Win/loss (1.0/0.0) is derived from who won more sets.
  Future<void> saveResult(int eventId, int rowPlayerId, int colPlayerId, {
    required double rowResult,
    required String rowDetail,
    required String colDetail,
  }) async {
    final db = await _dbService.database;

    // Get Entity IDs for both players (creating if missing for legacy compatibility)
    final rowEntId = await _dbService.ensurePlayerEntity(db, rowPlayerId);
    final colEntId = await _dbService.ensurePlayerEntity(db, colPlayerId);

    await db.transaction((txn) async {
      // Clear old subevents for this event to rebuild from sets
      await txn.delete('CMP_SUBEVENT', where: 'ev_id = ?', whereArgs: [eventId]);

      // Parse rowDetail (e.g. "11:7 11:4")
      final rowSets = rowDetail.trim().split(RegExp(r'\s+'));
      final colSets = colDetail.trim().split(RegExp(r'\s+'));

      for (int i = 0; i < rowSets.length; i++) {
        final rParts = rowSets[i].split(':');
        final cParts = i < colSets.length ? colSets[i].split(':') : ['0', '0'];

        final rScore = double.tryParse(rParts[0]) ?? 0.0;
        final cScore = double.tryParse(cParts[0]) ?? 0.0;

        await txn.insert('CMP_SUBEVENT', {
          'ev_id': eventId,
          'entity_id': rowEntId,
          'se_result': rScore,
          'se_note': 'Set ${i + 1}',
          'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_r_s$i',
        });
        await txn.insert('CMP_SUBEVENT', {
          'ev_id': eventId,
          'entity_id': colEntId,
          'se_result': cScore,
          'se_note': 'Set ${i + 1}',
          'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_c_s$i',
        });
      }

      // Update overall summary in CMP_EVENT
      int? esId;
      if (rowResult == 1.0) esId = 1; // Перемога
      else if (rowResult == 0.0) esId = 2; // Поразка

      await txn.update('CMP_EVENT', {
        'event_result': rowResult.toString(),
        'es_id': esId,
      }, where: 'event_id = ?', whereArgs: [eventId]);
    });
  }

  /// Get set score details for a specific player in a game.
  /// For multi-set games, reconstructs "11:7 11:4" format from subevents.
  /// Returns null for single-result games (chess).
  Future<String?> getResultDetail(int eventId, int playerId) async {
    final db = await _dbService.database;
    final pRows = await db.query('CMP_PLAYER', columns: ['entity_id'], where: 'player_id = ?', whereArgs: [playerId]);
    if (pRows.isEmpty) return null;
    final playerEntId = pRows.first['entity_id'] as int?;
    if (playerEntId == null) return null;

    final subRows = await db.query('CMP_SUBEVENT', where: 'ev_id = ?', whereArgs: [eventId], orderBy: 'se_id');

    final playerSubs = subRows.where((s) => s['entity_id'] == playerEntId).toList();
    final opponentSubs = subRows.where((s) => s['entity_id'] != playerEntId).toList();
    if (playerSubs.length <= 1) return null;

    // Multi-set: reconstruct "score:score" per set
    final sets = <String>[];
    for (int i = 0; i < playerSubs.length; i++) {
      final pScore = (playerSubs[i]['se_result'] as num?)?.toInt() ?? 0;
      final oScore = i < opponentSubs.length ? (opponentSubs[i]['se_result'] as num?)?.toInt() ?? 0 : 0;
      sets.add('$pScore:$oScore');
    }
    return sets.join(' ');
  }
}
