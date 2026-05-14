import 'dart:convert';
import 'athletics_model.dart';
import '../../services/database_service.dart';

/// Athletics database service — stores time-based results per category.
/// Follows the SwimmingService pattern: uses CMP_EVENT/CMP_SUBEVENT tables.
class AthleticsService {
  static const int _eventTypeIndividual = 1;
  static const int _attrIdAgeCoefficients = 18;
  static const int _attrIdPlayerNumber = 19;
  static const int _attrIdAssignedCategory = 20;
  static const int _attrIdYearOfBirth = 21;

  final DatabaseService _dbService;

  AthleticsService(this._dbService);

  /// Returns the reference year for age calculations: tournament begin year
  /// when available, otherwise the current year.
  Future<int> _tournamentReferenceYear(int tId) async {
    final db = await _dbService.database;
    final rows = await db.query('CMP_TOURNAMENT',
        columns: ['t_date_begin'], where: 't_id = ?', whereArgs: [tId]);
    if (rows.isEmpty) return DateTime.now().year;
    final dateStr = rows.first['t_date_begin'] as String? ?? '';
    if (dateStr.isEmpty) return DateTime.now().year;
    final parsed = DateTime.tryParse(dateStr);
    return parsed?.year ?? DateTime.now().year;
  }

  /// Public accessor for the tournament reference year used in age math.
  Future<int> getTournamentReferenceYear(int tId) =>
      _tournamentReferenceYear(tId);

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
        'event_result': result.totalDsec,
      }, where: 'event_id = ?', whereArgs: [eventId]);
    } else {
      eventId = await db.insert('CMP_EVENT', {
        't_id': result.tournamentId,
        'et_id': _eventTypeIndividual,
        'event_result': result.totalDsec,
        'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_ath_ev',
      });
    }

    // 3. Save CMP_SUBEVENT
    final subEventMap = {
      'ev_id': eventId,
      'entity_id': entityId,
      'se_result': result.totalDsec,
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

  /// Bulk saves multiple results using a single transaction to drastically improve performance.
  Future<void> saveResults(List<AthleticsResult> results) async {
    final db = await _dbService.database;
    await db.transaction((txn) async {
      for (final result in results) {
        final rows = await txn.query('CMP_PLAYER', columns: ['entity_id'],
            where: 'player_id = ?', whereArgs: [result.playerId]);
        if (rows.isEmpty) continue;
        final entityId = rows.first['entity_id'] as int;

        int eventId;
        if (result.id != null) {
          final subRows = await txn.query('CMP_SUBEVENT', columns: ['ev_id'],
              where: 'se_id = ?', whereArgs: [result.id]);
          if (subRows.isEmpty) continue;
          eventId = subRows.first['ev_id'] as int;

          await txn.update('CMP_EVENT', {
            'event_result': result.totalDsec,
          }, where: 'event_id = ?', whereArgs: [eventId]);
        } else {
          eventId = await txn.insert('CMP_EVENT', {
            't_id': result.tournamentId,
            'et_id': _eventTypeIndividual,
            'event_result': result.totalDsec,
            'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_ath_ev',
          });
        }

        final subEventMap = {
          'ev_id': eventId,
          'entity_id': entityId,
          'se_result': result.totalDsec,
          'se_note': result.category.name,
          'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_ath_se',
        };

        if (result.id != null) {
          await txn.update('CMP_SUBEVENT', subEventMap,
              where: 'se_id = ?', whereArgs: [result.id]);
        } else {
          await txn.insert('CMP_SUBEVENT', subEventMap);
        }
      }
    });
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
             COALESCE((
               SELECT MIN(pt.team_id) FROM CMP_PLAYER_TEAM pt
               WHERE pt.player_id = p.player_id AND pt.t_id = e.t_id AND pt.player_state IN (0,1)
             ), 0) as team_id
      FROM CMP_SUBEVENT se
      JOIN CMP_EVENT e ON se.ev_id = e.event_id
      LEFT JOIN CMP_PLAYER p ON se.entity_id = p.entity_id
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

  /// Calculate age relative to a reference year (typically tournament year).
  /// Birth-day vs Jan 1 of reference year is treated as completing the year,
  /// matching the rule "born YYYY+ → category X" which is purely year-based.
  int _calculateAge(String? dobStr, int referenceYear) {
    if (dobStr == null || dobStr.isEmpty) return 0;
    try {
      final dob = DateTime.parse(dobStr);
      return referenceYear - dob.year;
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
    final referenceYear = await _tournamentReferenceYear(tId);
    final rows = await db.rawQuery('''
      SELECT se.se_id as sr_id, e.t_id, se.se_result as time_total, se.se_note as category,
             p.player_id, p.player_surname, p.player_name, p.player_lastname,
             p.player_date_birth, p.player_age, p.player_gender,
             COALESCE((
               SELECT MIN(pt.team_id) FROM CMP_PLAYER_TEAM pt
               WHERE pt.player_id = p.player_id AND pt.t_id = e.t_id AND pt.player_state IN (0,1)
             ), 0) as team_id,
             COALESCE((
               SELECT t2.team_name FROM CMP_PLAYER_TEAM pt
               JOIN CMP_TEAM t2 ON pt.team_id = t2.team_id
               WHERE pt.player_id = p.player_id AND pt.t_id = e.t_id AND pt.player_state IN (0,1)
               ORDER BY pt.team_id LIMIT 1
             ), '') as team_name,
             (
               SELECT v.attr_value FROM CMP_PLAYER_TEAM pt
               JOIN CMP_PLAYER_TEAM_ATTR_VALUE v ON pt.pte_id = v.pte_id
               WHERE pt.player_id = p.player_id AND pt.t_id = e.t_id
                 AND pt.player_state IN (0,1) AND v.attr_id = 19
               LIMIT 1
             ) as player_number,
             (
               SELECT v.attr_value FROM CMP_PLAYER_TEAM pt
               JOIN CMP_PLAYER_TEAM_ATTR_VALUE v ON pt.pte_id = v.pte_id
               WHERE pt.player_id = p.player_id AND pt.t_id = e.t_id
                 AND pt.player_state IN (0,1) AND v.attr_id = 21
               LIMIT 1
             ) as year_of_birth
      FROM CMP_SUBEVENT se
      JOIN CMP_EVENT e ON se.ev_id = e.event_id
      LEFT JOIN CMP_PLAYER p ON se.entity_id = p.entity_id
      WHERE e.t_id = ? AND se.se_note = ?
    ''', [tId, category.name]);

    // Build results with per-player coefficients
    final results = <({AthleticsResult result, int age, double coeff, double adjDsec, String playerName, String? teamName, int? playerNumber})>[];
    for (final row in rows) {
      final total = (row['time_total'] as num?)?.toInt() ?? 0;
      final dob = row['player_date_birth'] as String?;
      final dbAge = row['player_age'] as int?;
      final yob = int.tryParse(row['year_of_birth'] as String? ?? '');
      // Age priority: explicit year-of-birth → DOB year → stored player_age.
      int age = yob != null && yob > 0
          ? referenceYear - yob
          : _calculateAge(dob, referenceYear);
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
      final number = int.tryParse(row['player_number'] as String? ?? '');

      results.add((
        result: r,
        age: age,
        coeff: coeff,
        adjDsec: adjDsec,
        playerName: '$surname $name $lastname'.trim(),
        teamName: row['team_name'] as String?,
        playerNumber: number,
      ));
    }

    // Sort by adjusted time
    results.sort((a, b) => a.adjDsec.compareTo(b.adjDsec));

    // Assign places with tie handling
    final ranked = <RankedAthleticsResult>[];
    int place = 1;
    for (int i = 0; i < results.length; i++) {
      final r = results[i];
      if (i > 0 && !_adjustedTimesTied(r.adjDsec, results[i - 1].adjDsec)) {
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
        playerNumber: r.playerNumber,
      ));
    }
    return ranked;
  }

  /// Two adjusted times are considered tied when they round to the same
  /// decisecond — the precision used to display and report results.
  bool _adjustedTimesTied(double a, double b) => a.round() == b.round();

  /// Returns ranked results for all male or female athletes combined across
  /// age categories. Each athlete keeps their own age coefficient; ranking
  /// is by adjusted time. Used for the "absolute" gender standings.
  Future<List<RankedAthleticsResult>> getOverallStandings(
    int tId, {
    required bool isMale,
    Map<int, ({double men3000, double women1500})>? customCoefficients,
  }) async {
    final cats = isMale
        ? AthleticsCategory.maleCategories
        : AthleticsCategory.femaleCategories;

    final all = <RankedAthleticsResult>[];
    for (final cat in cats) {
      final standings = await getCategoryStandings(
        tId, cat, customCoefficients: customCoefficients,
      );
      all.addAll(standings);
    }
    all.sort((a, b) => a.adjustedDsec.compareTo(b.adjustedDsec));

    final ranked = <RankedAthleticsResult>[];
    int place = 1;
    for (int i = 0; i < all.length; i++) {
      final r = all[i];
      if (i > 0 && !_adjustedTimesTied(r.adjustedDsec, all[i - 1].adjustedDsec)) {
        place = i + 1;
      }
      ranked.add(RankedAthleticsResult(
        result: r.result,
        place: place,
        playerName: r.playerName,
        teamName: r.teamName,
        age: r.age,
        coefficient: r.coefficient,
        adjustedDsec: r.adjustedDsec,
        playerNumber: r.playerNumber,
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
  ///
  /// Returns the ranked standings plus the missing-entry penalty value and
  /// the category that determined it (largest active category, after merging).
  /// [largestCategory] is null when there are no participants at all.
  Future<({
    List<AthleticsTeamStanding> standings,
    int penaltyPlace,
    AthleticsCategory? largestCategory,
  })> getTeamStandings(
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

    if (teamRows.isEmpty) {
      return (standings: <AthleticsTeamStanding>[], penaltyPlace: 1, largestCategory: null);
    }

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
    AthleticsCategory? maxCat;
    for (final entry in categoryStandings.entries) {
      if (entry.value.length > maxCatSize) {
        maxCatSize = entry.value.length;
        maxCat = entry.key;
      }
    }
    final penaltyPlace = maxCatSize + 1;

    /// Best (lowest) place for a team in a category's standings.
    /// Returns a single-element list, or an empty list if the team has no
    /// athlete in this category. The team-standings UI shows one number per
    /// category — the place actually counted for scoring.
    List<int> placesForTeam(
        List<RankedAthleticsResult> standings, int teamId) {
      final teamResults = standings
          .where((r) => r.effectiveTeamId == teamId && r.result != null)
          .map((r) => r.place)
          .toList();
      if (teamResults.isEmpty) return const [];
      teamResults.sort();
      return [teamResults.first];
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
      final maleOptions = <({AthleticsCategory cat, int place, int time, int age})>[];
      for (final cat in activeMaleCats) {
        final standings = categoryStandings[cat]!;
        final teamResults = standings.where((r) => r.effectiveTeamId == teamId && r.result != null).toList();
        if (teamResults.isNotEmpty) {
          maleOptions.add((
            cat: cat,
            place: teamResults.first.place,
            time: teamResults.first.result!.totalDsec,
            age: teamResults.first.age,
          ));
        }
      }
      maleOptions.sort((a, b) => a.place.compareTo(b.place));

      // Pick best 2 from different categories
      final selectedMale = <({AthleticsCategory cat, int place, int time, int age})>[];
      final usedCats = <AthleticsCategory>{};
      for (final opt in maleOptions) {
        if (!usedCats.contains(opt.cat) && selectedMale.length < 2) {
          selectedMale.add(opt);
          usedCats.add(opt.cat);
        }
      }

      // Pick best 1 woman from different category
      final femaleOptions = <({AthleticsCategory cat, int place, int time, int age})>[];
      for (final cat in activeFemaleCats) {
        final standings = categoryStandings[cat]!;
        final teamResults = standings.where((r) => r.effectiveTeamId == teamId && r.result != null).toList();
        if (teamResults.isNotEmpty) {
          femaleOptions.add((
            cat: cat,
            place: teamResults.first.place,
            time: teamResults.first.result!.totalDsec,
            age: teamResults.first.age,
          ));
        }
      }
      femaleOptions.sort((a, b) => a.place.compareTo(b.place));

      final selectedFemale = femaleOptions.isNotEmpty ? femaleOptions.first : null;

      // Build scoring places
      final scoringPlaces = <int>[];
      double bestWomanTime = double.infinity;
      int sumOfAges = 0;

      // 2 male places
      for (int i = 0; i < 2; i++) {
        if (i < selectedMale.length) {
          scoringPlaces.add(selectedMale[i].place);
          sumOfAges += selectedMale[i].age;
        } else {
          scoringPlaces.add(penaltyPlace);
        }
      }
      // 1 female place
      if (selectedFemale != null) {
        scoringPlaces.add(selectedFemale.place);
        sumOfAges += selectedFemale.age;
        bestWomanTime = selectedFemale.time.toDouble();
      } else {
        scoringPlaces.add(penaltyPlace);
      }

      final totalPoints = scoringPlaces.fold<int>(0, (sum, p) => sum + p);

      // Sum of times for tiebreak
      int sumOfTimes = 0;
      for (int i = 0; i < 2; i++) {
        if (i < selectedMale.length) sumOfTimes += selectedMale[i].time;
      }
      if (selectedFemale != null) sumOfTimes += selectedFemale.time;

      final categoryPlacesMap = <AthleticsCategory, List<int>>{};
      for (final cat in AthleticsCategory.values) {
        categoryPlacesMap[cat] = placesForTeam(categoryStandings[cat]!, teamId);
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

    // Compute the highest place value once instead of inside every comparison.
    final maxPlace = teamStandings
        .expand((t) => t.scoringPlaces)
        .fold<int>(0, (m, p) => p > m ? p : m);

    // Sort with all tiebreakers
    teamStandings.sort((a, b) {
      // Primary: lowest total points
      final cmp = a.totalPoints.compareTo(b.totalPoints);
      if (cmp != 0) return cmp;

      // Tiebreak 1: more 1st places, then 2nd, 3rd, etc.
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
    return (
      standings: result,
      penaltyPlace: penaltyPlace,
      largestCategory: maxCat,
    );
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
        // Re-sort by adjusted time (each athlete keeps their own coefficient)
        // and re-rank.
        standings[merge.to]!.sort((a, b) =>
            a.adjustedDsec.compareTo(b.adjustedDsec));
        _reRank(standings[merge.to]!);
      }
    }
    // Categories with <=4 participants are kept as-is: per the rules the
    // competition is not "held" in that category, but the athletes still
    // contribute places to their team's scoring.
  }

  void _reRank(List<RankedAthleticsResult> standings) {
    int place = 1;
    for (int i = 0; i < standings.length; i++) {
      if (i > 0 && !_adjustedTimesTied(
          standings[i].adjustedDsec, standings[i - 1].adjustedDsec)) {
        place = i + 1;
      }
      final current = standings[i];
      standings[i] = RankedAthleticsResult(
        result: current.result,
        place: place,
        playerName: current.playerName,
        teamName: current.teamName,
        age: current.age,
        coefficient: current.coefficient,
        adjustedDsec: current.adjustedDsec,
        playerNumber: current.playerNumber,
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
        AND pt.player_state IN (0, 1)
    ''', [tId, teamName.trim()]);

    if (teamRows.isEmpty) return (playerId: null, teamId: null);
    final teamId = teamRows.first['team_id'] as int;

    final playerRows = await db.rawQuery('''
      SELECT p.player_id
      FROM CMP_PLAYER_TEAM pt
      JOIN CMP_PLAYER p ON pt.player_id = p.player_id
      WHERE pt.t_id = ? AND pt.team_id = ? AND pt.player_state IN (0, 1)
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

  // ── Assigned category override (CMP_PLAYER_TEAM_ATTR_VALUE attr_id=20) ──

  Future<void> savePlayerYearOfBirth({
    required int playerId,
    required int tId,
    required int year,
  }) async {
    final db = await _dbService.database;
    final pteRows = await db.query('CMP_PLAYER_TEAM', columns: ['pte_id'],
      where: 'player_id = ? AND t_id = ?', whereArgs: [playerId, tId], limit: 1);
    if (pteRows.isEmpty) return;
    final pteId = pteRows.first['pte_id'] as int;
    await db.delete('CMP_PLAYER_TEAM_ATTR_VALUE',
      where: 'pte_id = ? AND attr_id = ?',
      whereArgs: [pteId, _attrIdYearOfBirth]);
    await db.insert('CMP_PLAYER_TEAM_ATTR_VALUE', {
      'pte_id': pteId,
      'attr_id': _attrIdYearOfBirth,
      'attr_value': year.toString(),
      'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_yob_$playerId',
    });
  }

  /// Bulk save year of birth overrides for multiple players in a tournament.
  Future<void> bulkSavePlayerYearsOfBirth({
    required int tId,
    required Map<int, int> yearsOfBirth,
  }) async {
    if (yearsOfBirth.isEmpty) return;
    final db = await _dbService.database;
    await db.transaction((txn) async {
      for (final entry in yearsOfBirth.entries) {
        final playerId = entry.key;
        final year = entry.value;
        final pteRows = await txn.query('CMP_PLAYER_TEAM', columns: ['pte_id'],
          where: 'player_id = ? AND t_id = ?', whereArgs: [playerId, tId], limit: 1);
        if (pteRows.isEmpty) continue;
        final pteId = pteRows.first['pte_id'] as int;
        await txn.delete('CMP_PLAYER_TEAM_ATTR_VALUE',
          where: 'pte_id = ? AND attr_id = ?',
          whereArgs: [pteId, _attrIdYearOfBirth]);
        await txn.insert('CMP_PLAYER_TEAM_ATTR_VALUE', {
          'pte_id': pteId,
          'attr_id': _attrIdYearOfBirth,
          'attr_value': year.toString(),
          'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_yob_$playerId',
        });
      }
    });
  }

  Future<void> saveAssignedCategory({
    required int playerId,
    required int tId,
    required AthleticsCategory category,
  }) async {
    final db = await _dbService.database;
    final pteRows = await db.query('CMP_PLAYER_TEAM', columns: ['pte_id'],
      where: 'player_id = ? AND t_id = ?', whereArgs: [playerId, tId], limit: 1);
    if (pteRows.isEmpty) return;
    final pteId = pteRows.first['pte_id'] as int;
    await db.delete('CMP_PLAYER_TEAM_ATTR_VALUE',
      where: 'pte_id = ? AND attr_id = ?',
      whereArgs: [pteId, _attrIdAssignedCategory]);
    await db.insert('CMP_PLAYER_TEAM_ATTR_VALUE', {
      'pte_id': pteId,
      'attr_id': _attrIdAssignedCategory,
      'attr_value': category.name,
      'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_ac_$playerId',
    });
  }

  /// Bulk save assigned category overrides for multiple players in a tournament.
  Future<void> bulkSaveAssignedCategories({
    required int tId,
    required Map<int, AthleticsCategory> categories,
  }) async {
    if (categories.isEmpty) return;
    final db = await _dbService.database;
    await db.transaction((txn) async {
      for (final entry in categories.entries) {
        final playerId = entry.key;
        final category = entry.value;
        final pteRows = await txn.query('CMP_PLAYER_TEAM', columns: ['pte_id'],
          where: 'player_id = ? AND t_id = ?', whereArgs: [playerId, tId], limit: 1);
        if (pteRows.isEmpty) continue;
        final pteId = pteRows.first['pte_id'] as int;
        await txn.delete('CMP_PLAYER_TEAM_ATTR_VALUE',
          where: 'pte_id = ? AND attr_id = ?',
          whereArgs: [pteId, _attrIdAssignedCategory]);
        await txn.insert('CMP_PLAYER_TEAM_ATTR_VALUE', {
          'pte_id': pteId,
          'attr_id': _attrIdAssignedCategory,
          'attr_value': category.name,
          'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_ac_$playerId',
        });
      }
    });
  }

  Future<void> clearAssignedCategory({
    required int playerId,
    required int tId,
  }) async {
    final db = await _dbService.database;
    final pteRows = await db.query('CMP_PLAYER_TEAM', columns: ['pte_id'],
      where: 'player_id = ? AND t_id = ?', whereArgs: [playerId, tId], limit: 1);
    if (pteRows.isEmpty) return;
    final pteId = pteRows.first['pte_id'] as int;
    await db.delete('CMP_PLAYER_TEAM_ATTR_VALUE',
      where: 'pte_id = ? AND attr_id = ?',
      whereArgs: [pteId, _attrIdAssignedCategory]);
  }

  /// Map of playerId → assigned AthleticsCategory for the tournament.
  /// Only contains entries where an override exists.
  Future<Map<int, AthleticsCategory>> getAssignedCategories(int tId) async {
    final db = await _dbService.database;
    final rows = await db.rawQuery('''
      SELECT pt.player_id, v.attr_value
      FROM CMP_PLAYER_TEAM pt
      JOIN CMP_PLAYER_TEAM_ATTR_VALUE v ON pt.pte_id = v.pte_id
      WHERE pt.t_id = ? AND v.attr_id = ? AND v.attr_value IS NOT NULL
    ''', [tId, _attrIdAssignedCategory]);
    final map = <int, AthleticsCategory>{};
    for (final r in rows) {
      final pid = r['player_id'] as int;
      final value = r['attr_value'] as String? ?? '';
      if (value.isEmpty) continue;
      map[pid] = AthleticsCategory.fromDb(value);
    }
    return map;
  }

  Future<void> clearPlayerYearOfBirth({
    required int playerId,
    required int tId,
  }) async {
    final db = await _dbService.database;
    final pteRows = await db.query('CMP_PLAYER_TEAM', columns: ['pte_id'],
      where: 'player_id = ? AND t_id = ?', whereArgs: [playerId, tId], limit: 1);
    if (pteRows.isEmpty) return;
    final pteId = pteRows.first['pte_id'] as int;
    await db.delete('CMP_PLAYER_TEAM_ATTR_VALUE',
      where: 'pte_id = ? AND attr_id = ?',
      whereArgs: [pteId, _attrIdYearOfBirth]);
  }

  Future<int?> getPlayerYearOfBirth({
    required int playerId,
    required int tId,
  }) async {
    final db = await _dbService.database;
    final rows = await db.rawQuery('''
      SELECT v.attr_value
      FROM CMP_PLAYER_TEAM pt
      JOIN CMP_PLAYER_TEAM_ATTR_VALUE v ON pt.pte_id = v.pte_id
      WHERE pt.player_id = ? AND pt.t_id = ? AND v.attr_id = ?
      LIMIT 1
    ''', [playerId, tId, _attrIdYearOfBirth]);
    if (rows.isEmpty) return null;
    return int.tryParse(rows.first['attr_value'] as String? ?? '');
  }

  /// Map of playerId → year-of-birth for every athletics participant in [tId]
  /// who has an override saved. Used to populate the players-tab list.
  Future<Map<int, int>> getPlayerYearsOfBirth(int tId) async {
    final db = await _dbService.database;
    final rows = await db.rawQuery('''
      SELECT pt.player_id, v.attr_value
      FROM CMP_PLAYER_TEAM pt
      JOIN CMP_PLAYER_TEAM_ATTR_VALUE v ON pt.pte_id = v.pte_id
      WHERE pt.t_id = ? AND v.attr_id = ? AND v.attr_value IS NOT NULL
    ''', [tId, _attrIdYearOfBirth]);
    final map = <int, int>{};
    for (final r in rows) {
      final y = int.tryParse(r['attr_value'] as String? ?? '');
      if (y != null) map[r['player_id'] as int] = y;
    }
    return map;
  }

  // ── All participants (for the All-participants results tab) ──

  /// All athletics participants of a tournament with their assignment state
  /// and existing result (if any). Used by the inline-entry "Всі учасники" tab.
  Future<List<AthleticsParticipantEntry>> getAllParticipants(int tId) async {
    final db = await _dbService.database;
    final referenceYear = await _tournamentReferenceYear(tId);

    // One row per (player, team) assignment in the tournament; left-join the
    // (latest) athletics subevent for the same player so each player appears
    // even without a recorded time.
    final athCategories =
        AthleticsCategory.values.map((c) => "'${c.name}'").join(',');
    final rows = await db.rawQuery('''
      SELECT pt.player_id, pt.team_id,
             p.player_surname, p.player_name, p.player_lastname,
             p.player_date_birth, p.player_age, p.player_gender,
             t.team_name,
             (
               SELECT v.attr_value FROM CMP_PLAYER_TEAM_ATTR_VALUE v
               WHERE v.pte_id = pt.pte_id AND v.attr_id = $_attrIdPlayerNumber
               LIMIT 1
             ) as player_number,
             (
               SELECT v.attr_value FROM CMP_PLAYER_TEAM_ATTR_VALUE v
               WHERE v.pte_id = pt.pte_id AND v.attr_id = $_attrIdAssignedCategory
               LIMIT 1
             ) as assigned_category,
             (
               SELECT v.attr_value FROM CMP_PLAYER_TEAM_ATTR_VALUE v
               WHERE v.pte_id = pt.pte_id AND v.attr_id = $_attrIdYearOfBirth
               LIMIT 1
             ) as year_of_birth,
             (
               SELECT se.se_id FROM CMP_SUBEVENT se
               JOIN CMP_EVENT e ON se.ev_id = e.event_id
               WHERE e.t_id = pt.t_id AND se.entity_id = p.entity_id
                 AND se.se_note IN ($athCategories)
               ORDER BY se.se_id DESC LIMIT 1
             ) as result_id,
             (
               SELECT se.se_result FROM CMP_SUBEVENT se
               JOIN CMP_EVENT e ON se.ev_id = e.event_id
               WHERE e.t_id = pt.t_id AND se.entity_id = p.entity_id
                 AND se.se_note IN ($athCategories)
               ORDER BY se.se_id DESC LIMIT 1
             ) as result_total,
             (
               SELECT se.se_note FROM CMP_SUBEVENT se
               JOIN CMP_EVENT e ON se.ev_id = e.event_id
               WHERE e.t_id = pt.t_id AND se.entity_id = p.entity_id
                 AND se.se_note IN ($athCategories)
               ORDER BY se.se_id DESC LIMIT 1
             ) as result_category
      FROM CMP_PLAYER_TEAM pt
      JOIN CMP_PLAYER p ON pt.player_id = p.player_id
      LEFT JOIN CMP_TEAM t ON pt.team_id = t.team_id
      WHERE pt.t_id = ? AND pt.player_state IN (0, 1)
      ORDER BY p.player_surname, p.player_name
    ''', [tId]);

    final entries = <AthleticsParticipantEntry>[];
    for (final r in rows) {
      final dob = r['player_date_birth'] as String?;
      final dbAge = r['player_age'] as int?;
      final yob = int.tryParse(r['year_of_birth'] as String? ?? '');
      // Age priority: explicit year-of-birth → DOB year → stored player_age.
      int age = yob != null && yob > 0
          ? referenceYear - yob
          : _calculateAge(dob, referenceYear);
      if (age <= 0 && dbAge != null && dbAge > 0) age = dbAge;
      final birthYear = yob != null && yob > 0
          ? yob
          : ((dob != null && dob.isNotEmpty)
              ? (DateTime.tryParse(dob)?.year ?? (referenceYear - age))
              : (referenceYear - age));
      final gender = (r['player_gender'] as int?) ?? 0;
      final autoCat = AthleticsCategory.detectCategory(
        age > 0 ? birthYear : null,
        gender,
      );
      final surname = r['player_surname'] as String? ?? '';
      final name = r['player_name'] as String? ?? '';
      final lastname = r['player_lastname'] as String? ?? '';

      final assignedRaw = r['assigned_category'] as String?;
      final assigned = (assignedRaw != null && assignedRaw.isNotEmpty)
          ? AthleticsCategory.fromDb(assignedRaw)
          : null;

      final number = int.tryParse(r['player_number'] as String? ?? '');
      final resultId = r['result_id'] as int?;
      final resultTotal = (r['result_total'] as num?)?.toInt();
      final resultCategoryRaw = r['result_category'] as String?;
      final resultCategory = (resultCategoryRaw != null && resultCategoryRaw.isNotEmpty)
          ? AthleticsCategory.fromDb(resultCategoryRaw)
          : null;

      entries.add(AthleticsParticipantEntry(
        playerId: r['player_id'] as int,
        teamId: (r['team_id'] as int?) ?? 0,
        fullName: '$surname $name $lastname'.trim(),
        teamName: r['team_name'] as String? ?? '',
        age: age,
        gender: gender,
        playerNumber: number,
        autoCategory: autoCat,
        assignedCategory: assigned,
        resultId: resultId,
        resultTotalDsec: resultTotal,
        resultCategory: resultCategory,
      ));
    }
    return entries;
  }

  /// Get participants for a specific category, including result-less ones.
  /// Result-less participants will have a null `result` and place = 0.
  Future<List<RankedAthleticsResult>> getCategoryParticipants(
    int tId,
    AthleticsCategory category, {
    Map<int, ({double men3000, double women1500})>? customCoefficients,
  }) async {
    // 1. Get ranked standings (those who have results)
    final standings = await getCategoryStandings(
      tId,
      category,
      customCoefficients: customCoefficients,
    );

    // 2. Get all participants
    final allParticipants = await getAllParticipants(tId);

    // 3. Find participants whose effective category matches, but have no result
    final resultLess = allParticipants.where((p) {
      if (p.effectiveCategory != category) return false;
      return p.resultId == null;
    }).toList();

    // 4. Convert result-less to RankedAthleticsResult
    final pending = resultLess.map((p) {
      final coeff = AthleticsCoefficients.getCoefficientFromTable(
        p.age,
        category.isMale,
        customCoefficients,
      );

      return RankedAthleticsResult(
        result: null,
        place: 0, // 0 signifies no place yet
        playerName: p.fullName,
        teamName: p.teamName,
        age: p.age,
        coefficient: coeff,
        adjustedDsec: 0,
        playerNumber: p.playerNumber,
        pendingPlayerId: p.playerId,
        pendingTeamId: p.teamId,
      );
    });

    return [...standings, ...pending];
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
        where: 't_id = ? AND attr_id = ?',
        whereArgs: [tId, _attrIdAgeCoefficients]);
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
      'attr_id': _attrIdAgeCoefficients,
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
        where: 't_id = ? AND attr_id = ?',
        whereArgs: [tId, _attrIdAgeCoefficients]);
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
