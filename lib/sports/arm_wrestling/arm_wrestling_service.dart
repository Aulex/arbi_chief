import '../../services/database_service.dart';
import 'arm_wrestling_scoring.dart';

/// Arm wrestling-specific database operations.
///
/// A player's weight category (1..5) is stored as the player's board number
/// in `CMP_PLAYER_TEAM_ATTR_VALUE` (attr_id = 9). The player must also be in
/// `player_state = 0` so the generic board queries pick them up.
///
/// `CMP_PLAYER_TEAM.team_number` is the team's running number — NOT the
/// weight category. (Earlier versions overloaded that column; everything
/// here now goes through attr_id = 9.)
class ArmWrestlingService {
  final DatabaseService _dbService;
  ArmWrestlingService(this._dbService);

  static const int _attrBoardNumber = 9;

  /// Get weight category assignments for players in a tournament.
  /// Returns Map<playerId, categoryId> where categoryId is 1..5.
  Future<Map<int, int>> getWeightCategoryAssignments(int tId) async {
    final db = await _dbService.database;
    final rows = await db.rawQuery('''
      SELECT pt.player_id, CAST(v.attr_value AS INTEGER) AS cat
      FROM CMP_PLAYER_TEAM pt
      JOIN CMP_PLAYER_TEAM_ATTR_VALUE v
        ON v.pte_id = pt.pte_id AND v.attr_id = ?
      WHERE pt.t_id = ? AND pt.player_id IS NOT NULL
    ''', [_attrBoardNumber, tId]);
    final result = <int, int>{};
    for (final row in rows) {
      final playerId = row['player_id'] as int;
      final cat = row['cat'] as int?;
      if (cat != null && cat >= 1 && cat <= 5) {
        result[playerId] = cat;
      }
    }
    return result;
  }

  /// Set weight category for a player. Promotes the player to board-member
  /// state (player_state = 0) and writes attr_id = 9 = categoryId.
  Future<void> setWeightCategory(int tId, int playerId, int categoryId) async {
    final db = await _dbService.database;
    final rows = await db.query(
      'CMP_PLAYER_TEAM',
      columns: ['pte_id'],
      where: 't_id = ? AND player_id = ?',
      whereArgs: [tId, playerId],
    );
    for (final row in rows) {
      final pteId = row['pte_id'] as int;
      await db.update(
        'CMP_PLAYER_TEAM',
        {'player_state': 0},
        where: 'pte_id = ?',
        whereArgs: [pteId],
      );
      await db.delete(
        'CMP_PLAYER_TEAM_ATTR_VALUE',
        where: 'pte_id = ? AND attr_id = ?',
        whereArgs: [pteId, _attrBoardNumber],
      );
      await db.insert('CMP_PLAYER_TEAM_ATTR_VALUE', {
        'pte_id': pteId,
        'attr_id': _attrBoardNumber,
        'attr_value': categoryId.toString(),
        'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_awc_$playerId',
      });
    }
  }

  /// Remove a player's weight category assignment.
  Future<void> clearWeightCategory(int tId, int playerId) async {
    final db = await _dbService.database;
    final rows = await db.query(
      'CMP_PLAYER_TEAM',
      columns: ['pte_id'],
      where: 't_id = ? AND player_id = ?',
      whereArgs: [tId, playerId],
    );
    for (final row in rows) {
      final pteId = row['pte_id'] as int;
      await db.delete(
        'CMP_PLAYER_TEAM_ATTR_VALUE',
        where: 'pte_id = ? AND attr_id = ?',
        whereArgs: [pteId, _attrBoardNumber],
      );
      await db.update(
        'CMP_PLAYER_TEAM',
        {'player_state': 1},
        where: 'pte_id = ?',
        whereArgs: [pteId],
      );
    }
  }

  /// Participant count per weight category.
  Future<Map<int, int>> getCategoryCounts(int tId) async {
    final assignments = await getWeightCategoryAssignments(tId);
    final result = <int, int>{};
    for (final cat in assignments.values) {
      result[cat] = (result[cat] ?? 0) + 1;
    }
    return result;
  }

  /// Snapshot of which categories meet the 5-participant minimum.
  Future<Map<int, ({bool isValid, int count, String label})>> validateCategories(int tId) async {
    final counts = await getCategoryCounts(tId);
    final result = <int, ({bool isValid, int count, String label})>{};
    for (final cat in WeightCategory.values) {
      final count = counts[cat.id] ?? 0;
      final isValid = count >= minParticipantsForCategory;
      result[cat.id] = (isValid: isValid, count: count, label: cat.label);
    }
    return result;
  }

  /// Auto-promote players from underfilled categories (1..4) to the next heavier.
  /// "Понад 100 кг" cannot accept overflow and is left alone.
  /// Returns number of players moved.
  Future<int> redistributeCategories(int tId) async {
    final assignments = await getWeightCategoryAssignments(tId);
    int moved = 0;
    for (int catId = 1; catId <= 4; catId++) {
      final inCat = assignments.entries
          .where((e) => e.value == catId)
          .map((e) => e.key)
          .toList();
      if (inCat.length < minParticipantsForCategory && inCat.isNotEmpty) {
        final nextCatId = catId + 1;
        for (final pid in inCat) {
          await setWeightCategory(tId, pid, nextCatId);
          assignments[pid] = nextCatId;
        }
        moved += inCat.length;
      }
    }
    return moved;
  }

  /// Players grouped by weight category for a tournament.
  Future<Map<int, List<({int playerId, String playerName, int teamId, String teamName, int? playerNumber, double? weight})>>>
      getPlayersByCategory(int tId) async {
    final db = await _dbService.database;
    final rows = await db.rawQuery('''
      SELECT pt.player_id,
             pt.team_id,
             CAST(v.attr_value AS INTEGER) AS cat,
             p.player_surname, p.player_name, p.player_lastname,
             t.team_name,
             CAST(vn.attr_value AS INTEGER) AS player_number,
             vw.attr_value AS weight_value
      FROM CMP_PLAYER_TEAM pt
      JOIN CMP_PLAYER_TEAM_ATTR_VALUE v
        ON v.pte_id = pt.pte_id AND v.attr_id = ?
      JOIN CMP_PLAYER p ON p.player_id = pt.player_id
      LEFT JOIN CMP_TEAM t ON t.team_id = pt.team_id
      LEFT JOIN CMP_PLAYER_TEAM_ATTR_VALUE vn
        ON vn.pte_id = pt.pte_id AND vn.attr_id = 19
      LEFT JOIN CMP_PLAYER_TEAM_ATTR_VALUE vw
        ON vw.pte_id = pt.pte_id AND vw.attr_id = 17
      WHERE pt.t_id = ? AND pt.player_id IS NOT NULL
      ORDER BY cat, p.player_surname
    ''', [_attrBoardNumber, tId]);

    final result = <int, List<({int playerId, String playerName, int teamId, String teamName, int? playerNumber, double? weight})>>{};
    for (final row in rows) {
      final catId = row['cat'] as int?;
      if (catId == null) continue;
      final surname = row['player_surname'] as String? ?? '';
      final name = row['player_name'] as String? ?? '';
      final lastname = row['player_lastname'] as String? ?? '';
      final fullName = '$surname $name $lastname'.trim();
      result.putIfAbsent(catId, () => []).add((
        playerId: row['player_id'] as int,
        playerName: fullName,
        teamId: row['team_id'] as int? ?? 0,
        teamName: row['team_name'] as String? ?? '',
        playerNumber: row['player_number'] as int?,
        weight: double.tryParse(row['weight_value'] as String? ?? ''),
      ));
    }
    return result;
  }

  /// Team names for a tournament.
  Future<Map<int, String>> getTeamNames(int tId) async {
    final db = await _dbService.database;
    final rows = await db.rawQuery('''
      SELECT DISTINCT t.team_id, t.team_name
      FROM CMP_TEAM t
      JOIN CMP_PLAYER_TEAM pt ON pt.team_id = t.team_id
      WHERE pt.t_id = ?
    ''', [tId]);
    return {
      for (final r in rows)
        r['team_id'] as int: r['team_name'] as String? ?? '',
    };
  }

  // --- Player Body Weight (attr_id = 17) ---

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

  /// One-time migration: move category data that used to live in
  /// `CMP_PLAYER_TEAM.team_number` into `attr_id = 9` and clear team_number.
  /// Only runs if the tournament has zero `attr_id = 9` rows (i.e. truly
  /// pre-fix data) and at least one player_state = 1 row with team_number in
  /// 1..5 — the legacy signature. Without this guard, a regular team number
  /// like 2 could be misread as the "≤80 kg" weight category.
  Future<int> migrateLegacyTeamNumberStorage(int tId) async {
    final db = await _dbService.database;
    final existing = await db.rawQuery('''
      SELECT 1 FROM CMP_PLAYER_TEAM pt
      JOIN CMP_PLAYER_TEAM_ATTR_VALUE v
        ON v.pte_id = pt.pte_id AND v.attr_id = ?
      WHERE pt.t_id = ? LIMIT 1
    ''', [_attrBoardNumber, tId]);
    if (existing.isNotEmpty) return 0;

    final rows = await db.rawQuery('''
      SELECT pt.pte_id, pt.player_id, pt.team_number
      FROM CMP_PLAYER_TEAM pt
      WHERE pt.t_id = ? AND pt.player_id IS NOT NULL
        AND pt.team_number BETWEEN 1 AND 5
        AND pt.player_state = 1
    ''', [tId]);
    if (rows.isEmpty) return 0;

    int migrated = 0;
    for (final row in rows) {
      final pteId = row['pte_id'] as int;
      final cat = row['team_number'] as int;
      await db.insert('CMP_PLAYER_TEAM_ATTR_VALUE', {
        'pte_id': pteId,
        'attr_id': _attrBoardNumber,
        'attr_value': cat.toString(),
        'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_awm_${row['player_id']}',
      });
      await db.update(
        'CMP_PLAYER_TEAM',
        {'player_state': 0, 'team_number': null},
        where: 'pte_id = ?',
        whereArgs: [pteId],
      );
      migrated++;
    }
    return migrated;
  }
}
