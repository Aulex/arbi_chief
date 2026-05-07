import 'dart:convert';
import 'athletics_model.dart';
import '../../services/database_service.dart';

/// Athletics database service — stores time-based results per category.
/// Follows the SwimmingService pattern: uses CMP_EVENT/CMP_SUBEVENT tables.
class AthleticsService {
  final DatabaseService _dbService;

  AthleticsService(this._dbService);

  // ── CRUD ──

  Future<int> saveResult(AthleticsResult result) async {
    final db = await _dbService.database;

    // 1. Get Entity ID for player
    final rows = await db.query('CMP_PLAYER', columns: ['entity_id'],
        where: 'player_id = ?', whereArgs: [result.playerId]);
    if (rows.isEmpty) throw Exception("Player entity not found");
    final entityId = rows.first['entity_id'] as int;

    // 2. Create/Update CMP_EVENT
    int eventId;
    if (result.id != null) {
      final subRows = await db.query('CMP_SUBEVENT', columns: ['ev_id'],
          where: 'se_id = ?', whereArgs: [result.id]);
      if (subRows.isEmpty) throw Exception("Subevent not found");
      eventId = subRows.first['ev_id'] as int;

      await db.update('CMP_EVENT', {
        'event_result': result.totalDsec.toString(),
      }, where: 'event_id = ?', whereArgs: [eventId]);
    } else {
      eventId = await db.insert('CMP_EVENT', {
        't_id': result.tournamentId,
        'et_id': 1, // Individual
        'event_result': result.totalDsec.toString(),
        'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_ath_ev',
      });
    }

    // 3. Save CMP_SUBEVENT
    final subEventMap = {
      'ev_id': eventId,
      'entity_id': entityId,
      'se_result': result.totalDsec.toDouble(),
      'se_note': result.category.name,
      'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_ath_se',
    };

    if (result.id != null) {
      await db.update('CMP_SUBEVENT', subEventMap,
          where: 'se_id = ?', whereArgs: [result.id]);
      return result.id!;
    } else {
      return await db.insert('CMP_SUBEVENT', subEventMap);
    }
  }

  Future<void> deleteResult(int seId) async {
    final db = await _dbService.database;
    final rows = await db.query('CMP_SUBEVENT', columns: ['ev_id'],
        where: 'se_id = ?', whereArgs: [seId]);
    if (rows.isNotEmpty) {
      final evId = rows.first['ev_id'] as int;
      await db.delete('CMP_SUBEVENT', where: 'se_id = ?', whereArgs: [seId]);
      await db.delete('CMP_EVENT', where: 'event_id = ?', whereArgs: [evId]);
    }
  }

  Future<void> deleteAllResults(int tId) async {
    final db = await _dbService.database;
    final athCategories =
        AthleticsCategory.values.map((c) => "'${c.name}'").join(',');
    final eventRows = await db.rawQuery('''
      SELECT DISTINCT se.ev_id
      FROM CMP_SUBEVENT se
      JOIN CMP_EVENT e ON se.ev_id = e.event_id
      WHERE e.t_id = ?
        AND se.se_note IN ($athCategories)
    ''', [tId]);

    if (eventRows.isEmpty) return;
    final eventIds = eventRows.map((r) => r['ev_id'] as int).toList();
    final placeholders = eventIds.map((_) => '?').join(',');
    await db.rawDelete(
        'DELETE FROM CMP_SUBEVENT WHERE ev_id IN ($placeholders)', eventIds);
    await db.rawDelete(
        'DELETE FROM CMP_EVENT WHERE event_id IN ($placeholders)', eventIds);
  }

  Future<void> clearCategoryResults(int tId, AthleticsCategory category) async {
    final db = await _dbService.database;
    final eventRows = await db.rawQuery('''
      SELECT DISTINCT se.ev_id
      FROM CMP_SUBEVENT se
      JOIN CMP_EVENT e ON se.ev_id = e.event_id
      WHERE e.t_id = ?
        AND se.se_note = ?
    ''', [tId, category.name]);

    if (eventRows.isEmpty) return;
    final eventIds = eventRows.map((r) => r['ev_id'] as int).toList();
    final placeholders = eventIds.map((_) => '?').join(',');
    await db.rawDelete(
        'DELETE FROM CMP_SUBEVENT WHERE ev_id IN ($placeholders)', eventIds);
    await db.rawDelete(
        'DELETE FROM CMP_EVENT WHERE event_id IN ($placeholders)', eventIds);
  }

  /// Get all results for a tournament, optionally filtered by category.
  Future<List<AthleticsResult>> getResults(int tId,
      {AthleticsCategory? category}) async {
    final db = await _dbService.database;
    final athCategories =
        AthleticsCategory.values.map((c) => "'${c.name}'").join(',');

    String sql = '''
      SELECT se.se_id as sr_id, e.t_id, se.se_result as time_total, se.se_note as category,
             p.player_id,
             COALESCE(pt.team_id, 0) as team_id
      FROM CMP_SUBEVENT se
      JOIN CMP_EVENT e ON se.ev_id = e.event_id
      LEFT JOIN CMP_PLAYER p ON se.entity_id = p.entity_id
      LEFT JOIN CMP_PLAYER_TEAM pt ON p.player_id = pt.player_id AND pt.t_id = e.t_id AND pt.player_state IN (0,1)
      WHERE e.t_id = ? AND se.se_note IN ($athCategories)
    ''';

    final List<dynamic> args = [tId];
    if (category != null) {
      sql += ' AND se.se_note = ?';
      args.add(category.name);
    }
    sql += ' ORDER BY se.se_result ASC';

    final rows = await db.rawQuery(sql, args);
    return rows.map((r) {
      final total = (r['time_total'] as num?)?.toInt() ?? 0;
      return AthleticsResult(
        id: r['sr_id'] as int,
        tournamentId: tId,
        playerId: r['player_id'] as int? ?? 0,
        teamId: r['team_id'] as int? ?? 0,
        category: AthleticsCategory.fromDb(r['category'] as String),
        timeMin: total ~/ 6000,
        timeSec: (total % 6000) ~/ 100,
        timeDsec: total % 100,
      );
    }).toList();
  }

  // ── Individual Standings ──

  /// Calculate age from birth date string.
  int _calculateAge(String? dobStr) {
    if (dobStr == null || dobStr.isEmpty) return 0;
    try {
      final dob = DateTime.parse(dobStr);
      final now = DateTime.now();
      int age = now.year - dob.year;
      if (now.month < dob.month ||
          (now.month == dob.month && now.day < dob.day)) {
        age--;
      }
      return age;
    } catch (_) {
      return 0;
    }
  }

  /// Returns ranked results for a category, sorted by adjusted time.
  /// Each player gets an individual coefficient based on their age.
  /// [customCoefficients] — optional custom table overriding defaults.
  Future<List<RankedAthleticsResult>> getCategoryStandings(
    int tId,
    AthleticsCategory category, {
    Map<int, ({double men3000, double women1500})>? customCoefficients,
  }) async {
    final db = await _dbService.database;
    final rows = await db.rawQuery('''
      SELECT se.se_id as sr_id, e.t_id, se.se_result as time_total, se.se_note as category,
             p.player_id, p.player_surname, p.player_name, p.player_lastname,
             p.player_date_birth, p.player_age, p.player_gender,
             COALESCE(pt.team_id, 0) as team_id,
             COALESCE(t2.team_name, '') as team_name
      FROM CMP_SUBEVENT se
      JOIN CMP_EVENT e ON se.ev_id = e.event_id
      LEFT JOIN CMP_PLAYER p ON se.entity_id = p.entity_id
      LEFT JOIN CMP_PLAYER_TEAM pt ON p.player_id = pt.player_id AND pt.t_id = e.t_id AND pt.player_state IN (0,1)
      LEFT JOIN CMP_TEAM t2 ON pt.team_id = t2.team_id
      WHERE e.t_id = ? AND se.se_note = ?
    ''', [tId, category.name]);

    // Build results with per-player coefficients
    final results = <({AthleticsResult result, int age, double coeff, double adjDsec, String playerName, String? teamName})>[];
    for (final row in rows) {
      final total = (row['time_total'] as num?)?.toInt() ?? 0;
      final dob = row['player_date_birth'] as String?;
      final dbAge = row['player_age'] as int?;
      int age = _calculateAge(dob);
      if (age <= 0 && dbAge != null && dbAge > 0) {
        age = dbAge;
      }
      final isMale = category.isMale;

      final coeff = AthleticsCoefficients.getCoefficientFromTable(
        age, isMale, customCoefficients,
      );

      final r = AthleticsResult(
        id: row['sr_id'] as int,
        tournamentId: tId,
        playerId: row['player_id'] as int? ?? 0,
        teamId: row['team_id'] as int? ?? 0,
        category: category,
        timeMin: total ~/ 6000,
        timeSec: (total % 6000) ~/ 100,
        timeDsec: total % 100,
      );

      final adjDsec = r.adjustedDsec(coeff);

      final surname = row['player_surname'] as String? ?? '';
      final name = row['player_name'] as String? ?? '';
      final lastname = row['player_lastname'] as String? ?? '';

      results.add((
        result: r,
        age: age,
        coeff: coeff,
        adjDsec: adjDsec,
        playerName: '$surname $name $lastname'.trim(),
        teamName: row['team_name'] as String?,
      ));
    }

    // Sort by adjusted time
    results.sort((a, b) => a.adjDsec.compareTo(b.adjDsec));

    // Assign places with tie handling
    final ranked = <RankedAthleticsResult>[];
    int place = 1;
    for (int i = 0; i < results.length; i++) {
      final r = results[i];
      if (i > 0 && r.adjDsec.round() != results[i - 1].adjDsec.round()) {
        place = i + 1;
      }
      ranked.add(RankedAthleticsResult(
        result: r.result,
        place: place,
        playerName: r.playerName,
        teamName: r.teamName,
        age: r.age,
        coefficient: r.coeff,
        adjustedDsec: r.adjDsec,
      ));
    }
    return ranked;
  }

  // ── Team Standings ──

  /// Calculate team standings according to the rules:
  /// Best 3 results: 2 men + 1 woman, each from a different category.
  /// Points = place numbers (1st=1, 2nd=2, etc.), lowest total wins.
  /// Missing entries = last place in largest category + 1 penalty.
  /// Tiebreakers: 1) more 1st/2nd/3rd places, 2) lowest sum of times,
  ///              3) largest sum of ages, 4) best woman result.
  Future<List<AthleticsTeamStanding>> getTeamStandings(
    int tId, {
    Map<int, ({double men3000, double women1500})>? customCoefficients,
  }) async {
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

    // Get standings for each category (with per-player age coefficients)
    final categoryStandings = <AthleticsCategory, List<RankedAthleticsResult>>{};
    for (final cat in AthleticsCategory.values) {
      categoryStandings[cat] = await getCategoryStandings(
        tId, cat, customCoefficients: customCoefficients,
      );
    }

    // Apply category merging rule: if <5 participants, merge into younger category
    // and cancellation: if <=4 participants total (including after merge), don't run
    _applyCategoryMerging(categoryStandings);

    // Penalty for missing entry = last place in largest category + 1
    int maxCatSize = 0;
    for (final standings in categoryStandings.values) {
      if (standings.length > maxCatSize) maxCatSize = standings.length;
    }
    final penaltyPlace = maxCatSize + 1;

    /// Get actual places for a team in a category's standings.
    List<int> bestPlacesForTeam(
        List<RankedAthleticsResult> standings, int teamId, int count) {
      final teamResults = standings
          .where((r) => r.result.teamId == teamId)
          .map((r) => r.place)
          .toList();
      teamResults.sort();
      return teamResults.take(count).toList();
    }


    /// Get age for a player from birth date.
    Future<int> getPlayerAge(int playerId) async {
      final pRows = await db.query('CMP_PLAYER',
          columns: ['player_date_birth'],
          where: 'player_id = ?', whereArgs: [playerId]);
      if (pRows.isEmpty) return 0;
      final dob = pRows.first['player_date_birth'] as String? ?? '';
      return _calculateAge(dob);
    }

    // Active male categories (those with results after merging)
    final activeMaleCats = AthleticsCategory.maleCategories
        .where((c) => categoryStandings[c]!.isNotEmpty)
        .toList();
    // Active female categories
    final activeFemaleCats = AthleticsCategory.femaleCategories
        .where((c) => categoryStandings[c]!.isNotEmpty)
        .toList();

    // Build team standings
    final teamStandings = <_TeamScore>[];

    for (final row in teamRows) {
      final teamId = row['team_id'] as int;
      final teamName = row['team_name'] as String;

      // Pick best 2 men from different categories
      final maleOptions = <({AthleticsCategory cat, int place, int time, int playerId})>[];
      for (final cat in activeMaleCats) {
        final standings = categoryStandings[cat]!;
        final teamResults = standings.where((r) => r.result.teamId == teamId).toList();
        if (teamResults.isNotEmpty) {
          maleOptions.add((
            cat: cat,
            place: teamResults.first.place,
            time: teamResults.first.result.totalDsec,
            playerId: teamResults.first.result.playerId,
          ));
        }
      }
      maleOptions.sort((a, b) => a.place.compareTo(b.place));

      // Pick best 2 from different categories
      final selectedMale = <({AthleticsCategory cat, int place, int time, int playerId})>[];
      final usedCats = <AthleticsCategory>{};
      for (final opt in maleOptions) {
        if (!usedCats.contains(opt.cat) && selectedMale.length < 2) {
          selectedMale.add(opt);
          usedCats.add(opt.cat);
        }
      }

      // Pick best 1 woman from different category
      final femaleOptions = <({AthleticsCategory cat, int place, int time, int playerId})>[];
      for (final cat in activeFemaleCats) {
        final standings = categoryStandings[cat]!;
        final teamResults = standings.where((r) => r.result.teamId == teamId).toList();
        if (teamResults.isNotEmpty) {
          femaleOptions.add((
            cat: cat,
            place: teamResults.first.place,
            time: teamResults.first.result.totalDsec,
            playerId: teamResults.first.result.playerId,
          ));
        }
      }
      femaleOptions.sort((a, b) => a.place.compareTo(b.place));

      final selectedFemale = femaleOptions.isNotEmpty ? femaleOptions.first : null;

      // Build scoring places
      final scoringPlaces = <int>[];
      final contributingPlayerIds = <int>[];
      double bestWomanTime = double.infinity;

      // 2 male places
      for (int i = 0; i < 2; i++) {
        if (i < selectedMale.length) {
          scoringPlaces.add(selectedMale[i].place);
          contributingPlayerIds.add(selectedMale[i].playerId);
        } else {
          scoringPlaces.add(penaltyPlace);
        }
      }
      // 1 female place
      if (selectedFemale != null) {
        scoringPlaces.add(selectedFemale.place);
        contributingPlayerIds.add(selectedFemale.playerId);
        bestWomanTime = selectedFemale.time.toDouble();
      } else {
        scoringPlaces.add(penaltyPlace);
      }

      final totalPoints = scoringPlaces.fold(0, (sum, p) => sum + p);

      // Sum of times for tiebreak
      int sumOfTimes = 0;
      for (int i = 0; i < 2; i++) {
        if (i < selectedMale.length) sumOfTimes += selectedMale[i].time;
      }
      if (selectedFemale != null) sumOfTimes += selectedFemale.time;

      // Sum of ages for tiebreak
      int sumOfAges = 0;
      for (final pid in contributingPlayerIds) {
        sumOfAges += await getPlayerAge(pid);
      }

      final categoryPlacesMap = <AthleticsCategory, List<int>>{};
      for (final cat in AthleticsCategory.values) {
        categoryPlacesMap[cat] = bestPlacesForTeam(
          categoryStandings[cat]!, teamId,
          cat.isMale ? 1 : 1,
        );
      }

      teamStandings.add(_TeamScore(
        teamId: teamId,
        teamName: teamName,
        categoryPlaces: categoryPlacesMap,
        scoringPlaces: scoringPlaces,
        totalPoints: totalPoints,
        sumOfTimes: sumOfTimes,
        sumOfAges: sumOfAges,
        bestWomanTime: bestWomanTime,
      ));
    }

    // Sort with all tiebreakers
    teamStandings.sort((a, b) {
      // Primary: lowest total points
      final cmp = a.totalPoints.compareTo(b.totalPoints);
      if (cmp != 0) return cmp;

      // Tiebreak 1: more 1st places, then 2nd, 3rd, etc.
      final maxPlace = teamStandings
          .expand((t) => t.scoringPlaces)
          .fold(0, (m, p) => p > m ? p : m);
      for (int p = 1; p <= maxPlace; p++) {
        final aCount = a.scoringPlaces.where((x) => x == p).length;
        final bCount = b.scoringPlaces.where((x) => x == p).length;
        if (aCount != bCount) return bCount.compareTo(aCount); // more is better
      }

      // Tiebreak 2: lowest sum of times
      final timeCmp = a.sumOfTimes.compareTo(b.sumOfTimes);
      if (timeCmp != 0) return timeCmp;

      // Tiebreak 3: largest sum of ages
      final ageCmp = b.sumOfAges.compareTo(a.sumOfAges); // larger is better
      if (ageCmp != 0) return ageCmp;

      // Tiebreak 4: best result among women
      final womanCmp = a.bestWomanTime.compareTo(b.bestWomanTime);
      if (womanCmp != 0) return womanCmp;

      return 0;
    });

    // Assign places
    final result = <AthleticsTeamStanding>[];
    for (int i = 0; i < teamStandings.length; i++) {
      final t = teamStandings[i];
      int place = i + 1;
      if (i > 0) {
        final prev = teamStandings[i - 1];
        if (t.totalPoints == prev.totalPoints) {
          // Check all tiebreakers for true tie
          bool isTied = true;
          final maxPlace = teamStandings
              .expand((ts) => ts.scoringPlaces)
              .fold(0, (m, p) => p > m ? p : m);
          for (int p = 1; p <= maxPlace; p++) {
            if (t.scoringPlaces.where((x) => x == p).length !=
                prev.scoringPlaces.where((x) => x == p).length) {
              isTied = false;
              break;
            }
          }
          if (isTied && t.sumOfTimes == prev.sumOfTimes &&
              t.sumOfAges == prev.sumOfAges &&
              t.bestWomanTime == prev.bestWomanTime) {
            place = result[i - 1].place;
          }
        }
      }
      result.add(AthleticsTeamStanding(
        teamId: t.teamId,
        teamName: t.teamName,
        categoryPlaces: t.categoryPlaces,
        scoringPlaces: t.scoringPlaces,
        totalPoints: t.totalPoints,
        sumOfTimes: t.sumOfTimes,
        sumOfAges: t.sumOfAges,
        bestWomanTime: t.bestWomanTime,
        place: place,
      ));
    }
    return result;
  }

  /// Apply category merging: if a category has <5 participants, merge into younger category.
  /// If <=4 participants after merging (including base categories), cancel the category.
  void _applyCategoryMerging(
      Map<AthleticsCategory, List<RankedAthleticsResult>> standings) {
    // Order: m50 → m49 → m35, f50 → f49 → f35
    final mergeOrder = [
      (from: AthleticsCategory.m50, to: AthleticsCategory.m49),
      (from: AthleticsCategory.m49, to: AthleticsCategory.m35),
      (from: AthleticsCategory.f50, to: AthleticsCategory.f49),
      (from: AthleticsCategory.f49, to: AthleticsCategory.f35),
    ];

    for (final merge in mergeOrder) {
      if (standings[merge.from]!.length < 5 && standings[merge.from]!.isNotEmpty) {
        // Move results to the younger category
        standings[merge.to]!.addAll(standings[merge.from]!);
        standings[merge.from] = [];
        // Re-sort and re-rank the target category
        standings[merge.to]!.sort((a, b) =>
            a.result.totalDsec.compareTo(b.result.totalDsec));
        _reRank(standings[merge.to]!);
      }
    }

    // Cancel categories with <=4 participants
    for (final cat in AthleticsCategory.values) {
      if (standings[cat]!.length <= 4) {
        // Don't cancel, just keep as is — results still count for team scoring
        // The rule says "competitions in such categories are not held" but
        // participants can still get places for team scoring
      }
    }
  }

  void _reRank(List<RankedAthleticsResult> standings) {
    int place = 1;
    for (int i = 0; i < standings.length; i++) {
      if (i > 0 && standings[i].result.totalDsec != standings[i - 1].result.totalDsec) {
        place = i + 1;
      }
      standings[i] = RankedAthleticsResult(
        result: standings[i].result,
        place: place,
        playerName: standings[i].playerName,
        teamName: standings[i].teamName,
        coefficient: standings[i].coefficient,
        adjustedDsec: standings[i].adjustedDsec,
      );
    }
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

    final teamRows = await db.rawQuery('''
      SELECT DISTINCT t.team_id
      FROM CMP_TEAM t
      JOIN CMP_PLAYER_TEAM pt ON t.team_id = pt.team_id
      WHERE pt.t_id = ? AND t.team_name = ? COLLATE NOCASE
    ''', [tId, teamName.trim()]);

    if (teamRows.isEmpty) return (playerId: null, teamId: null);
    final teamId = teamRows.first['team_id'] as int;

    final playerRows = await db.rawQuery('''
      SELECT p.player_id
      FROM CMP_PLAYER_TEAM pt
      JOIN CMP_PLAYER p ON pt.player_id = p.player_id
      WHERE pt.t_id = ? AND pt.team_id = ?
      AND (
        TRIM(REPLACE(REPLACE(REPLACE(
          COALESCE(p.player_surname, '') || ' ' || COALESCE(p.player_name, '') || ' ' || COALESCE(p.player_lastname, ''),
          '  ', ' '), '  ', ' '), '  ', ' ')
        ) = ? COLLATE NOCASE
      )
    ''', [tId, teamId, fullName.trim().replaceAll(RegExp(r'\s+'), ' ')]);

    return (
      playerId:
          playerRows.isNotEmpty ? playerRows.first['player_id'] as int : null,
      teamId: teamId,
    );
  }

  // ── Age Coefficient Table (stored in CMP_ATTR_VALUE as JSON) ──

  /// Save a custom age coefficient table for a tournament.
  /// Uses attr_id=18 with a single JSON value: {"age": {"men3000": x, "women1500": y}, ...}
  /// Only saves entries that differ from the default table.
  Future<void> saveCustomCoefficients(
    int tId,
    Map<int, ({double men3000, double women1500})> customTable,
  ) async {
    final db = await _dbService.database;
    await db.delete('CMP_ATTR_VALUE',
        where: 't_id = ? AND attr_id = 18', whereArgs: [tId]);
    // Store all entries
    final allMap = <String, Map<String, double>>{};
    for (final entry in customTable.entries) {
      allMap['${entry.key}'] = {
        'm': entry.value.men3000,
        'w': entry.value.women1500,
      };
    }
    if (allMap.isEmpty) return;

    await db.insert('CMP_ATTR_VALUE', {
      't_id': tId,
      'attr_id': 18,
      'attr_value': jsonEncode(allMap),
    });
  }

  /// Load the custom age coefficient table for a tournament.
  /// Returns null if no coefficients are configured.
  Future<Map<int, ({double men3000, double women1500})>?> getCustomCoefficients(
    int tId,
  ) async {
    final db = await _dbService.database;
    final rows = await db.query('CMP_ATTR_VALUE',
        columns: ['attr_value'],
        where: 't_id = ? AND attr_id = 18', whereArgs: [tId]);
    if (rows.isEmpty) return null;

    final jsonStr = rows.first['attr_value'] as String? ?? '';
    if (jsonStr.isEmpty) return null;

    try {
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      final table = <int, ({double men3000, double women1500})>{};
      for (final entry in decoded.entries) {
        final age = int.tryParse(entry.key);
        if (age == null) continue;
        final vals = entry.value as Map<String, dynamic>;
        table[age] = (
          men3000: (vals['m'] as num?)?.toDouble() ?? 1.0,
          women1500: (vals['w'] as num?)?.toDouble() ?? 1.0,
        );
      }
      return table;
    } catch (_) {
      return null;
    }
  }
}

class _TeamScore {
  final int teamId;
  final String teamName;
  final Map<AthleticsCategory, List<int>> categoryPlaces;
  final List<int> scoringPlaces;
  final int totalPoints;
  final int sumOfTimes;
  final int sumOfAges;
  final double bestWomanTime;

  _TeamScore({
    required this.teamId,
    required this.teamName,
    required this.categoryPlaces,
    required this.scoringPlaces,
    required this.totalPoints,
    required this.sumOfTimes,
    required this.sumOfAges,
    required this.bestWomanTime,
  });
}
