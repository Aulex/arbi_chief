import '../models/swimming_model.dart';
import 'database_service.dart';

class SwimmingService {
  final DatabaseService _dbService;

  SwimmingService(this._dbService);

  // ── CRUD ──

  Future<int> saveResult(SwimmingResult result) async {
    final db = await _dbService.database;
    final map = result.toMap();
    if (result.id != null) {
      await db.update('CMP_SWIMMING_RESULT', map,
          where: 'sr_id = ?', whereArgs: [result.id]);
      return result.id!;
    } else {
      return await db.insert('CMP_SWIMMING_RESULT', map);
    }
  }

  Future<void> deleteResult(int srId) async {
    final db = await _dbService.database;
    await db.delete('CMP_SWIMMING_RESULT',
        where: 'sr_id = ?', whereArgs: [srId]);
  }

  Future<void> deleteAllResults(int tId) async {
    final db = await _dbService.database;
    await db.delete('CMP_SWIMMING_RESULT',
        where: 't_id = ?', whereArgs: [tId]);
  }

  /// Get all results for a tournament, optionally filtered by category.
  Future<List<SwimmingResult>> getResults(int tId,
      {SwimmingCategory? category}) async {
    final db = await _dbService.database;
    final where = category != null
        ? 't_id = ? AND category = ?'
        : 't_id = ?';
    final whereArgs = category != null
        ? [tId, category.name]
        : [tId];
    final rows = await db.query('CMP_SWIMMING_RESULT',
        where: where, whereArgs: whereArgs, orderBy: 'time_total ASC');
    return rows.map((r) => SwimmingResult.fromMap(r)).toList();
  }

  // ── Individual Standings ──

  /// Returns ranked results for a category, sorted by time.
  /// Handles ties (same time = same place).
  Future<List<RankedSwimmingResult>> getCategoryStandings(
      int tId, SwimmingCategory category) async {
    final db = await _dbService.database;
    final rows = await db.rawQuery('''
      SELECT sr.*, p.player_surname, p.player_name, p.player_lastname,
             t.team_name
      FROM CMP_SWIMMING_RESULT sr
      LEFT JOIN CMP_PLAYER p ON sr.player_id = p.player_id
      JOIN CMP_TEAM t ON sr.team_id = t.team_id
      WHERE sr.t_id = ? AND sr.category = ?
      ORDER BY sr.time_total ASC
    ''', [tId, category.name]);

    final ranked = <RankedSwimmingResult>[];
    int place = 1;
    for (int i = 0; i < rows.length; i++) {
      final r = SwimmingResult.fromMap(rows[i]);
      // Tie: same time as previous = same place
      if (i > 0) {
        final prev = SwimmingResult.fromMap(rows[i - 1]);
        if (r.totalDsec != prev.totalDsec) {
          place = i + 1;
        }
      }

      String? playerName;
      if (category != SwimmingCategory.relay) {
        final surname = rows[i]['player_surname'] as String? ?? '';
        final name = rows[i]['player_name'] as String? ?? '';
        final lastname = rows[i]['player_lastname'] as String? ?? '';
        playerName = '$surname $name $lastname'.trim();
      }

      ranked.add(RankedSwimmingResult(
        result: r,
        place: place,
        playerName: playerName,
        teamName: rows[i]['team_name'] as String?,
      ));
    }
    return ranked;
  }

  // ── Team Standings ──

  /// Calculate team standings according to the rules:
  /// Best 7 results: 2×Ч35 + 2×Ч49 + 1×Ч50 + 1×woman (any age) + 1×relay.
  /// Points = place numbers (1st=1, 2nd=2, etc.).
  /// Missing entries = last place + 1 penalty.
  Future<List<SwimmingTeamStanding>> getTeamStandings(int tId) async {
    final db = await _dbService.database;

    // Get all teams in the tournament
    final teamRows = await db.rawQuery('''
      SELECT DISTINCT t.team_id, t.team_name
      FROM CMP_PLAYER_TEAM pt
      JOIN CMP_TEAM t ON pt.team_id = t.team_id
      WHERE pt.t_id = ?
      ORDER BY t.team_name
    ''', [tId]);

    if (teamRows.isEmpty) return [];

    // Get standings for each individual category
    final m35Standings = await getCategoryStandings(tId, SwimmingCategory.m35);
    final m49Standings = await getCategoryStandings(tId, SwimmingCategory.m49);
    final m50Standings = await getCategoryStandings(tId, SwimmingCategory.m50);
    final f35Standings = await getCategoryStandings(tId, SwimmingCategory.f35);
    final f49Standings = await getCategoryStandings(tId, SwimmingCategory.f49);
    final relayStandings =
        await getCategoryStandings(tId, SwimmingCategory.relay);

    // Penalty for missing entry = last place in category + 1
    int penaltyFor(List<RankedSwimmingResult> standings) {
      if (standings.isEmpty) return 1;
      return standings.last.place + 1;
    }

    /// Get best N places for a team in a category's standings.
    List<int> bestPlacesForTeam(
        List<RankedSwimmingResult> standings, int teamId, int count) {
      final teamResults = standings
          .where((r) => r.result.teamId == teamId)
          .map((r) => r.place)
          .toList();
      teamResults.sort();
      // Take best N, pad with penalty if not enough
      final penalty = penaltyFor(standings);
      while (teamResults.length < count) {
        teamResults.add(penalty);
      }
      return teamResults.take(count).toList();
    }

    // Build team standings
    final teamStandings = <_TeamScore>[];

    for (final row in teamRows) {
      final teamId = row['team_id'] as int;
      final teamName = row['team_name'] as String;

      // 2 best from M35
      final m35Places = bestPlacesForTeam(m35Standings, teamId, 2);
      // 2 best from M49
      final m49Places = bestPlacesForTeam(m49Standings, teamId, 2);
      // 1 best from M50
      final m50Places = bestPlacesForTeam(m50Standings, teamId, 1);

      // 1 best woman from EITHER f35 or f49 (best single result)
      final f35Places = bestPlacesForTeam(f35Standings, teamId, 1);
      final f49Places = bestPlacesForTeam(f49Standings, teamId, 1);
      final bestWomanPlace = [f35Places.first, f49Places.first]..sort();
      final womanPlaces = [bestWomanPlace.first];

      // 1 relay
      final relayPlaces = bestPlacesForTeam(relayStandings, teamId, 1);

      final allScoringPlaces = [
        ...m35Places,
        ...m49Places,
        ...m50Places,
        ...womanPlaces,
        ...relayPlaces,
      ];
      final totalPoints = allScoringPlaces.fold(0, (sum, p) => sum + p);

      final categoryPlaces = <SwimmingCategory, List<int>>{
        SwimmingCategory.m35: m35Places,
        SwimmingCategory.m49: m49Places,
        SwimmingCategory.m50: m50Places,
        SwimmingCategory.f35: f35Places,
        SwimmingCategory.f49: f49Places,
        SwimmingCategory.relay: relayPlaces,
      };

      teamStandings.add(_TeamScore(
        teamId: teamId,
        teamName: teamName,
        categoryPlaces: categoryPlaces,
        scoringPlaces: allScoringPlaces,
        totalPoints: totalPoints,
      ));
    }

    // Sort: lowest total points first.
    // Tiebreak: more 1st places, then more 2nd places, etc.
    teamStandings.sort((a, b) {
      final cmp = a.totalPoints.compareTo(b.totalPoints);
      if (cmp != 0) return cmp;

      // Count places for tiebreak
      final maxPlace = teamStandings
          .expand((t) => t.scoringPlaces)
          .fold(0, (m, p) => p > m ? p : m);
      for (int p = 1; p <= maxPlace; p++) {
        final aCount = a.scoringPlaces.where((x) => x == p).length;
        final bCount = b.scoringPlaces.where((x) => x == p).length;
        if (aCount != bCount) return bCount.compareTo(aCount); // more is better
      }
      return 0;
    });

    // Assign places
    final result = <SwimmingTeamStanding>[];
    for (int i = 0; i < teamStandings.length; i++) {
      final t = teamStandings[i];
      int place = i + 1;
      // Same total + same tiebreak = same place
      if (i > 0) {
        final prev = teamStandings[i - 1];
        if (t.totalPoints == prev.totalPoints) {
          final prevPlace = result[i - 1].place;
          // Check if truly tied
          bool sameTiebreak = true;
          final maxPlace = teamStandings
              .expand((ts) => ts.scoringPlaces)
              .fold(0, (m, p) => p > m ? p : m);
          for (int p = 1; p <= maxPlace; p++) {
            final tCount = t.scoringPlaces.where((x) => x == p).length;
            final pCount = prev.scoringPlaces.where((x) => x == p).length;
            if (tCount != pCount) {
              sameTiebreak = false;
              break;
            }
          }
          if (sameTiebreak) place = prevPlace;
        }
      }
      result.add(SwimmingTeamStanding(
        teamId: t.teamId,
        teamName: t.teamName,
        categoryPlaces: t.categoryPlaces,
        scoringPlaces: t.scoringPlaces,
        totalPoints: t.totalPoints,
        place: place,
      ));
    }
    return result;
  }

  /// Get all players assigned to a team in a tournament.
  Future<List<({int playerId, String fullName, String? birthDate, int? gender})>>
      getTeamPlayers(int tId, int teamId) async {
    final db = await _dbService.database;
    final rows = await db.rawQuery('''
      SELECT p.player_id, p.player_surname, p.player_name,
             p.player_lastname, p.player_date_birth, p.player_gender
      FROM CMP_PLAYER_TEAM pt
      JOIN CMP_PLAYER p ON pt.player_id = p.player_id
      WHERE pt.t_id = ? AND pt.team_id = ? AND pt.player_state IN (0, 1)
      ORDER BY p.player_surname, p.player_name
    ''', [tId, teamId]);
    return rows.map((r) {
      final surname = r['player_surname'] as String? ?? '';
      final name = r['player_name'] as String? ?? '';
      final lastname = r['player_lastname'] as String? ?? '';
      return (
        playerId: r['player_id'] as int,
        fullName: '$surname $name $lastname'.trim(),
        birthDate: r['player_date_birth'] as String?,
        gender: r['player_gender'] as int?,
      );
    }).toList();
  }

  /// Finds a player ID and team ID based on their names within a tournament.
  Future<({int? playerId, int? teamId})> findParticipant(
      int tId, String fullName, String teamName) async {
    final db = await _dbService.database;

    // 1. Find team
    final teamRows = await db.query('CMP_TEAM',
        where: 'team_name = ? COLLATE NOCASE', whereArgs: [teamName.trim()]);
    if (teamRows.isEmpty) return (playerId: null, teamId: null);
    final teamId = teamRows.first['team_id'] as int;

    // 2. Find player within that team in the tournament
    final playerRows = await db.rawQuery('''
      SELECT p.player_id
      FROM CMP_PLAYER_TEAM pt
      JOIN CMP_PLAYER p ON pt.player_id = p.player_id
      WHERE pt.t_id = ? AND pt.team_id = ?
      AND (TRIM(p.player_surname || ' ' || p.player_name || ' ' || p.player_lastname) = ? COLLATE NOCASE)
    ''', [tId, teamId, fullName.trim()]);

    return (
      playerId: playerRows.isNotEmpty ? playerRows.first['player_id'] as int : null,
      teamId: teamId,
    );
  }
}

class _TeamScore {
  final int teamId;
  final String teamName;
  final Map<SwimmingCategory, List<int>> categoryPlaces;
  final List<int> scoringPlaces;
  final int totalPoints;

  _TeamScore({
    required this.teamId,
    required this.teamName,
    required this.categoryPlaces,
    required this.scoringPlaces,
    required this.totalPoints,
  });
}
