import '../../services/database_service.dart';
import 'arm_wrestling_bracket.dart';

/// Glue between the bracket engine ([buildBracket]) and the existing tables
/// (CMP_EVENT / CMP_SUBEVENT / CMP_PLAYER_TEAM_ATTR_VALUE).
///
/// No new tables: the seed is the participant number (attr_id = 19), each
/// match is a CMP_EVENT with two CMP_SUBEVENT participants, and bracket
/// position is derived on the fly.
class ArmWrestlingBracketService {
  final DatabaseService _db;
  ArmWrestlingBracketService(this._db);

  static const int _attrWeightCat = 9;
  static const int _attrPlayerNumber = 19;

  /// Load the seeded player list and all played matches for one category.
  /// Seed order = ascending participant number (attr_id = 19). Players
  /// without a number are sorted last (by player_id).
  Future<({List<({int playerId, String fullName, String teamName, int? number, double? weight})> players, List<RawMatch> raws})>
      loadCategory(int tId, int categoryId) async {
    final db = await _db.database;

    final playerRows = await db.rawQuery('''
      SELECT pt.player_id,
             p.player_surname, p.player_name, p.player_lastname,
             t.team_name,
             CAST(vn.attr_value AS INTEGER) AS player_number,
             vw.attr_value AS weight_value
      FROM CMP_PLAYER_TEAM pt
      JOIN CMP_PLAYER_TEAM_ATTR_VALUE vc
        ON vc.pte_id = pt.pte_id AND vc.attr_id = ? AND CAST(vc.attr_value AS INTEGER) = ?
      JOIN CMP_PLAYER p ON p.player_id = pt.player_id
      LEFT JOIN CMP_TEAM t ON t.team_id = pt.team_id
      LEFT JOIN CMP_PLAYER_TEAM_ATTR_VALUE vn
        ON vn.pte_id = pt.pte_id AND vn.attr_id = ?
      LEFT JOIN CMP_PLAYER_TEAM_ATTR_VALUE vw
        ON vw.pte_id = pt.pte_id AND vw.attr_id = 17
      WHERE pt.t_id = ? AND pt.player_id IS NOT NULL
    ''', [_attrWeightCat, categoryId, _attrPlayerNumber, tId]);

    final players = <({int playerId, String fullName, String teamName, int? number, double? weight})>[];
    for (final r in playerRows) {
      final surname = r['player_surname'] as String? ?? '';
      final name = r['player_name'] as String? ?? '';
      final lastname = r['player_lastname'] as String? ?? '';
      players.add((
        playerId: r['player_id'] as int,
        fullName: '$surname $name $lastname'.trim(),
        teamName: r['team_name'] as String? ?? '',
        number: r['player_number'] as int?,
        weight: double.tryParse(r['weight_value'] as String? ?? ''),
      ));
    }
    // Ascending seed = ascending number; null numbers last.
    players.sort((a, b) {
      final an = a.number;
      final bn = b.number;
      if (an == null && bn == null) return a.playerId.compareTo(b.playerId);
      if (an == null) return 1;
      if (bn == null) return -1;
      final c = an.compareTo(bn);
      if (c != 0) return c;
      return a.playerId.compareTo(b.playerId);
    });

    // Load all matches where both players are in this category, ordered by
    // event_id (stable creation order — disambiguates GF vs GFR).
    final ids = players.map((p) => p.playerId).toSet();
    final raws = <RawMatch>[];
    if (ids.isNotEmpty) {
      final eventRows = await db.rawQuery('''
        SELECT e.event_id, e.event_result,
               p1.player_id AS p1_id,
               p2.player_id AS p2_id,
               se1.es_id AS se1_state, se2.es_id AS se2_state
        FROM CMP_EVENT e
        JOIN CMP_SUBEVENT se1 ON se1.ev_id = e.event_id
        JOIN CMP_SUBEVENT se2 ON se2.ev_id = e.event_id AND se2.entity_id > se1.entity_id
        JOIN CMP_PLAYER p1 ON se1.entity_id = p1.entity_id
        JOIN CMP_PLAYER p2 ON se2.entity_id = p2.entity_id
        WHERE e.t_id = ?
        ORDER BY e.event_id
      ''', [tId]);
      for (final r in eventRows) {
        final p1 = r['p1_id'] as int;
        final p2 = r['p2_id'] as int;
        if (!ids.contains(p1) || !ids.contains(p2)) continue;
        // es_id 4 = "вийшов" / completed-with-result, 1 = won, 2 = lost,
        // 3 = draw. For arm wrestling there are no draws — we read the
        // winner directly from the subevent state.
        final s1 = r['se1_state'] as int?;
        final s2 = r['se2_state'] as int?;
        int? winner;
        if (s1 == 1 && s2 == 2) winner = p1;
        else if (s2 == 1 && s1 == 2) winner = p2;
        raws.add(RawMatch(
          eventId: r['event_id'] as int,
          playerAId: p1,
          playerBId: p2,
          winnerPlayerId: winner,
        ));
      }
    }

    return (players: players, raws: raws);
  }

  /// Swap participant numbers between two players (drag-and-drop reseeding).
  /// If a side has no number yet, it borrows the other side's pre-existing
  /// number; missing numbers on both sides are no-ops.
  Future<void> swapSeeds(int tId, int playerAId, int playerBId) async {
    final db = await _db.database;
    Future<int?> getNum(int pid) async {
      final rows = await db.rawQuery('''
        SELECT CAST(v.attr_value AS INTEGER) AS n
        FROM CMP_PLAYER_TEAM pt
        JOIN CMP_PLAYER_TEAM_ATTR_VALUE v
          ON v.pte_id = pt.pte_id AND v.attr_id = ?
        WHERE pt.t_id = ? AND pt.player_id = ?
        LIMIT 1
      ''', [_attrPlayerNumber, tId, pid]);
      if (rows.isEmpty) return null;
      return rows.first['n'] as int?;
    }
    Future<void> setNum(int pid, int? n) async {
      final pteRows = await db.query('CMP_PLAYER_TEAM',
          columns: ['pte_id'],
          where: 'player_id = ? AND t_id = ?',
          whereArgs: [pid, tId],
          limit: 1);
      if (pteRows.isEmpty) return;
      final pteId = pteRows.first['pte_id'] as int;
      await db.delete('CMP_PLAYER_TEAM_ATTR_VALUE',
          where: 'pte_id = ? AND attr_id = ?',
          whereArgs: [pteId, _attrPlayerNumber]);
      if (n != null) {
        await db.insert('CMP_PLAYER_TEAM_ATTR_VALUE', {
          'pte_id': pteId,
          'attr_id': _attrPlayerNumber,
          'attr_value': n.toString(),
          'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_pn_$pid',
        });
      }
    }

    final a = await getNum(playerAId);
    final b = await getNum(playerBId);
    if (a == null && b == null) return;
    await setNum(playerAId, b);
    await setNum(playerBId, a);
  }

  /// Move [playerId] to participant number [newNumber], shifting other
  /// players in this category as needed so the seed list stays a contiguous
  /// 1..N sequence. This is what drag-and-drop calls when reordering.
  Future<void> reorderTo({
    required int tId,
    required int categoryId,
    required int playerId,
    required int newPosition,
  }) async {
    final loaded = await loadCategory(tId, categoryId);
    final ordered = loaded.players.toList();
    final from = ordered.indexWhere((p) => p.playerId == playerId);
    if (from < 0) return;
    final target = newPosition.clamp(0, ordered.length - 1);
    if (from == target) return;
    final moving = ordered.removeAt(from);
    ordered.insert(target, moving);
    // Reassign 1..N participant numbers in the new order.
    final db = await _db.database;
    for (int i = 0; i < ordered.length; i++) {
      final pteRows = await db.query('CMP_PLAYER_TEAM',
          columns: ['pte_id'],
          where: 'player_id = ? AND t_id = ?',
          whereArgs: [ordered[i].playerId, tId],
          limit: 1);
      if (pteRows.isEmpty) continue;
      final pteId = pteRows.first['pte_id'] as int;
      await db.delete('CMP_PLAYER_TEAM_ATTR_VALUE',
          where: 'pte_id = ? AND attr_id = ?',
          whereArgs: [pteId, _attrPlayerNumber]);
      await db.insert('CMP_PLAYER_TEAM_ATTR_VALUE', {
        'pte_id': pteId,
        'attr_id': _attrPlayerNumber,
        'attr_value': (i + 1).toString(),
        'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_pn_${ordered[i].playerId}',
      });
    }
  }
}
