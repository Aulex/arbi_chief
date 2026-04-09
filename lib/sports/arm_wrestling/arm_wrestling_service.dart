import '../../services/database_service.dart';
import 'arm_wrestling_scoring.dart';

/// Arm wrestling-specific database operations.
///
/// Handles weight category assignment, participant redistribution,
/// and category validation per competition rules.
class ArmWrestlingService {
  final DatabaseService _dbService;
  ArmWrestlingService(this._dbService);

  // --- Weight Category Management ---

  /// Get weight category assignments for players in a tournament.
  /// Returns Map<playerId, weightCategoryId> where categoryId matches WeightCategory.id (1-5).
  /// Uses team_number in CMP_PLAYER_TEAM for storage.
  Future<Map<int, int>> getWeightCategoryAssignments(int tId) async {
    final db = await _dbService.database;
    final rows = await db.query(
      'CMP_PLAYER_TEAM',
      columns: ['player_id', 'team_number'],
      where: 't_id = ? AND team_number IS NOT NULL AND team_number > 0',
      whereArgs: [tId],
    );
    final result = <int, int>{};
    for (final row in rows) {
      final playerId = row['player_id'] as int;
      final category = row['team_number'] as int;
      if (category >= 1 && category <= 5) {
        result[playerId] = category;
      }
    }
    return result;
  }

  /// Set weight category for a player in a tournament.
  /// [categoryId] is 1-5 matching WeightCategory enum.
  Future<void> setWeightCategory(int tId, int playerId, int categoryId) async {
    final db = await _dbService.database;
    final existing = await db.query(
      'CMP_PLAYER_TEAM',
      where: 't_id = ? AND player_id = ?',
      whereArgs: [tId, playerId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      await db.update(
        'CMP_PLAYER_TEAM',
        {'team_number': categoryId},
        where: 'pte_id = ?',
        whereArgs: [existing.first['pte_id']],
      );
    }
  }

  /// Get participant counts per weight category.
  Future<Map<int, int>> getCategoryCounts(int tId) async {
    final db = await _dbService.database;
    final rows = await db.rawQuery('''
      SELECT team_number, COUNT(*) as cnt
      FROM CMP_PLAYER_TEAM
      WHERE t_id = ? AND team_number IS NOT NULL AND team_number > 0
      GROUP BY team_number
    ''', [tId]);
    final result = <int, int>{};
    for (final row in rows) {
      result[row['team_number'] as int] = row['cnt'] as int;
    }
    return result;
  }

  /// Check which categories are valid (have enough participants).
  /// Returns set of valid category IDs.
  ///
  /// Rules:
  /// - If a category (except 100kg+) has <5 participants, they should move to heavier
  /// - If any category (including 100kg+) has 1-4 participants after redistribution, it's cancelled
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

  /// Auto-redistribute players from underfilled categories to heavier ones.
  /// Categories with <5 participants (except 100kg+) get merged into the next heavier.
  /// Returns number of players moved.
  Future<int> redistributeCategories(int tId) async {
    final db = await _dbService.database;
    int moved = 0;

    // Process categories from lightest to heaviest (1→4, skip 5=over100)
    for (int catId = 1; catId <= 4; catId++) {
      final players = await db.query(
        'CMP_PLAYER_TEAM',
        where: 't_id = ? AND team_number = ?',
        whereArgs: [tId, catId],
      );

      if (players.length < minParticipantsForCategory && players.isNotEmpty) {
        // Move all players to next heavier category
        final nextCatId = catId + 1;
        await db.update(
          'CMP_PLAYER_TEAM',
          {'team_number': nextCatId},
          where: 't_id = ? AND team_number = ?',
          whereArgs: [tId, catId],
        );
        moved += players.length;
      }
    }

    return moved;
  }

  /// Get players grouped by weight category for a tournament.
  Future<Map<int, List<({int playerId, String playerName, int teamId, String teamName})>>>
      getPlayersByCategory(int tId) async {
    final db = await _dbService.database;
    final rows = await db.rawQuery('''
      SELECT pt.player_id, pt.team_number, pt.team_id,
             p.player_surname, p.player_name, p.player_lastname,
             t.team_name
      FROM CMP_PLAYER_TEAM pt
      JOIN CMP_PLAYER p ON p.player_id = pt.player_id
      LEFT JOIN CMP_TEAM t ON t.team_id = pt.team_id
      WHERE pt.t_id = ? AND pt.team_number IS NOT NULL AND pt.team_number > 0
      ORDER BY pt.team_number, p.player_surname
    ''', [tId]);

    final result = <int, List<({int playerId, String playerName, int teamId, String teamName})>>{};
    for (final row in rows) {
      final catId = row['team_number'] as int;
      final surname = row['player_surname'] as String? ?? '';
      final name = row['player_name'] as String? ?? '';
      final lastname = row['player_lastname'] as String? ?? '';
      final fullName = '$surname $name $lastname'.trim();
      result.putIfAbsent(catId, () => []).add((
        playerId: row['player_id'] as int,
        playerName: fullName,
        teamId: row['team_id'] as int? ?? 0,
        teamName: row['team_name'] as String? ?? '',
      ));
    }
    return result;
  }

  /// Get all team names for a tournament.
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

  // --- Player Body Weight (attr_id=17) ---

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
