import 'cycling_model.dart';
import '../../services/database_service.dart';

/// Cycling database service — stores time-based results per age category.
///
/// Mirrors [AthleticsService] but ranks by raw time (no age coefficients) and
/// uses 5 categories instead of 6 (women have only Ж35 / Ж49).
///
/// Player-team attributes are reused from the athletics set — a `pte_id`
/// belongs to exactly one tournament, so there is no cross-sport collision:
///   attr_id 19 = participant number   (also managed by TournamentService)
///   attr_id 20 = assigned category override
///   attr_id 21 = year of birth
class CyclingService {
  static const int _eventTypeIndividual = 1;
  static const int _attrIdPlayerNumber = 19;
  static const int _attrIdAssignedCategory = 20;
  static const int _attrIdYearOfBirth = 21;

  final DatabaseService _dbService;

  CyclingService(this._dbService);

  // ───────────────────────────────────────────────────────────────────────
  // Legacy place-based API (kept so the current cycling tabs keep compiling
  // until they are rewritten; will be removed with that rewrite).
  // ───────────────────────────────────────────────────────────────────────

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
        'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_cy_ev',
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
        'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_cy_se',
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
      WHERE e.t_id = ? AND e.et_id = 1 AND se.se_note = 'place' AND se.se_result IS NOT NULL
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

  // ───────────────────────────────────────────────────────────────────────
  // Time-based API (athletics parity)
  // ───────────────────────────────────────────────────────────────────────

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

  Future<int> saveResult(CyclingResult result) async {
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
        'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_cy_ev',
      });
    }

    // 3. Save CMP_SUBEVENT
    final subEventMap = {
      'ev_id': eventId,
      'entity_id': entityId,
      'se_result': result.totalDsec,
      'se_note': result.category.name,
      'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_cy_se',
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
    final cyCategories =
        CyclingCategory.values.map((c) => "'${c.name}'").join(',');
    final eventRows = await db.rawQuery('''
      SELECT DISTINCT se.ev_id
      FROM CMP_SUBEVENT se
      JOIN CMP_EVENT e ON se.ev_id = e.event_id
      WHERE e.t_id = ?
        AND se.se_note IN ($cyCategories)
    ''', [tId]);

    if (eventRows.isEmpty) return;
    final eventIds = eventRows.map((r) => r['ev_id'] as int).toList();
    final placeholders = eventIds.map((_) => '?').join(',');
    await db.rawDelete(
        'DELETE FROM CMP_SUBEVENT WHERE ev_id IN ($placeholders)', eventIds);
    await db.rawDelete(
        'DELETE FROM CMP_EVENT WHERE event_id IN ($placeholders)', eventIds);
  }

  Future<void> clearCategoryResults(int tId, CyclingCategory category) async {
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
  Future<List<CyclingResult>> getResults(int tId,
      {CyclingCategory? category}) async {
    final db = await _dbService.database;
    final cyCategories =
        CyclingCategory.values.map((c) => "'${c.name}'").join(',');

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
      WHERE e.t_id = ? AND se.se_note IN ($cyCategories)
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
      return CyclingResult(
        id: r['sr_id'] as int,
        tournamentId: tId,
        playerId: r['player_id'] as int? ?? 0,
        teamId: r['team_id'] as int? ?? 0,
        category: CyclingCategory.fromDb(r['category'] as String),
        timeMin: total ~/ 6000,
        timeSec: (total % 6000) ~/ 100,
        timeDsec: total % 100,
      );
    }).toList();
  }

  // ── Individual Standings ──

  /// Calculate age relative to a reference year (typically tournament year).
  /// Year-based, matching the rule "born YYYY+ → category X".
  int _calculateAge(String? dobStr, int referenceYear) {
    if (dobStr == null || dobStr.isEmpty) return 0;
    try {
      final dob = DateTime.parse(dobStr);
      return referenceYear - dob.year;
    } catch (_) {
      return 0;
    }
  }

  /// Returns ranked results for a category, sorted by raw time.
  Future<List<RankedCyclingResult>> getCategoryStandings(
    int tId,
    CyclingCategory category,
  ) async {
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
                 AND pt.player_state IN (0,1) AND v.attr_id = $_attrIdPlayerNumber
               LIMIT 1
             ) as player_number,
             (
               SELECT v.attr_value FROM CMP_PLAYER_TEAM pt
               JOIN CMP_PLAYER_TEAM_ATTR_VALUE v ON pt.pte_id = v.pte_id
               WHERE pt.player_id = p.player_id AND pt.t_id = e.t_id
                 AND pt.player_state IN (0,1) AND v.attr_id = $_attrIdYearOfBirth
               LIMIT 1
             ) as year_of_birth
      FROM CMP_SUBEVENT se
      JOIN CMP_EVENT e ON se.ev_id = e.event_id
      LEFT JOIN CMP_PLAYER p ON se.entity_id = p.entity_id
      WHERE e.t_id = ? AND se.se_note = ?
    ''', [tId, category.name]);

    final results = <({CyclingResult result, int age, String playerName, String? teamName, int? playerNumber})>[];
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

      final r = CyclingResult(
        id: row['sr_id'] as int,
        tournamentId: tId,
        playerId: row['player_id'] as int? ?? 0,
        teamId: row['team_id'] as int? ?? 0,
        category: category,
        timeMin: total ~/ 6000,
        timeSec: (total % 6000) ~/ 100,
        timeDsec: total % 100,
      );

      final surname = row['player_surname'] as String? ?? '';
      final name = row['player_name'] as String? ?? '';
      final lastname = row['player_lastname'] as String? ?? '';
      final number = int.tryParse(row['player_number'] as String? ?? '');

      results.add((
        result: r,
        age: age,
        playerName: '$surname $name $lastname'.trim(),
        teamName: row['team_name'] as String?,
        playerNumber: number,
      ));
    }

    // Sort by raw time.
    results.sort((a, b) => a.result.totalDsec.compareTo(b.result.totalDsec));

    // Assign places with tie handling (equal raw times share a place).
    final ranked = <RankedCyclingResult>[];
    int place = 1;
    for (int i = 0; i < results.length; i++) {
      final r = results[i];
      if (i > 0 && r.result.totalDsec != results[i - 1].result.totalDsec) {
        place = i + 1;
      }
      ranked.add(RankedCyclingResult(
        result: r.result,
        place: place,
        playerName: r.playerName,
        teamName: r.teamName,
        age: r.age,
        playerNumber: r.playerNumber,
      ));
    }
    return ranked;
  }

  /// Returns ranked results for all male or female athletes combined across
  /// age categories, ranked by raw time. Used for the "absolute" gender
  /// standings page in the report.
  Future<List<RankedCyclingResult>> getOverallStandings(
    int tId, {
    required bool isMale,
  }) async {
    final cats = isMale
        ? CyclingCategory.maleCategories
        : CyclingCategory.femaleCategories;

    final all = <RankedCyclingResult>[];
    for (final cat in cats) {
      all.addAll(await getCategoryStandings(tId, cat));
    }
    all.sort((a, b) => a.result.totalDsec.compareTo(b.result.totalDsec));

    final ranked = <RankedCyclingResult>[];
    int place = 1;
    for (int i = 0; i < all.length; i++) {
      final r = all[i];
      if (i > 0 && r.result.totalDsec != all[i - 1].result.totalDsec) {
        place = i + 1;
      }
      ranked.add(RankedCyclingResult(
        result: r.result,
        place: place,
        playerName: r.playerName,
        teamName: r.teamName,
        age: r.age,
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
    List<CyclingTeamStanding> standings,
    int penaltyPlace,
    CyclingCategory? largestCategory,
  })> getTeamStandings(int tId) async {
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
      return (standings: <CyclingTeamStanding>[], penaltyPlace: 1, largestCategory: null);
    }

    // Get standings for each category.
    final categoryStandings = <CyclingCategory, List<RankedCyclingResult>>{};
    for (final cat in CyclingCategory.values) {
      categoryStandings[cat] = await getCategoryStandings(tId, cat);
    }

    // Apply category merging rule: if <5 participants, merge into younger
    // category. Categories with <=4 participants are not "held" per the
    // rules but their athletes still contribute places to team scoring.
    _applyCategoryMerging(categoryStandings);

    // Penalty for missing entry = last place in largest category + 1.
    int maxCatSize = 0;
    CyclingCategory? maxCat;
    for (final entry in categoryStandings.entries) {
      if (entry.value.length > maxCatSize) {
        maxCatSize = entry.value.length;
        maxCat = entry.key;
      }
    }
    final penaltyPlace = maxCatSize + 1;

    /// Best (lowest) place for a team in a category's standings.
    List<int> placesForTeam(
        List<RankedCyclingResult> standings, int teamId) {
      final teamResults = standings
          .where((r) => r.result.teamId == teamId)
          .map((r) => r.place)
          .toList();
      if (teamResults.isEmpty) return const [];
      teamResults.sort();
      return [teamResults.first];
    }

    final activeMaleCats = CyclingCategory.maleCategories
        .where((c) => categoryStandings[c]!.isNotEmpty)
        .toList();
    final activeFemaleCats = CyclingCategory.femaleCategories
        .where((c) => categoryStandings[c]!.isNotEmpty)
        .toList();

    final teamStandings = <_CyclingTeamScore>[];

    for (final row in teamRows) {
      final teamId = row['team_id'] as int;
      final teamName = row['team_name'] as String;

      // Pick best 2 men from different categories.
      final maleOptions = <({CyclingCategory cat, int place, int time, int age})>[];
      for (final cat in activeMaleCats) {
        final standings = categoryStandings[cat]!;
        final teamResults = standings.where((r) => r.result.teamId == teamId).toList();
        if (teamResults.isNotEmpty) {
          maleOptions.add((
            cat: cat,
            place: teamResults.first.place,
            time: teamResults.first.result.totalDsec,
            age: teamResults.first.age,
          ));
        }
      }
      maleOptions.sort((a, b) => a.place.compareTo(b.place));

      final selectedMale = <({CyclingCategory cat, int place, int time, int age})>[];
      final usedCats = <CyclingCategory>{};
      for (final opt in maleOptions) {
        if (!usedCats.contains(opt.cat) && selectedMale.length < 2) {
          selectedMale.add(opt);
          usedCats.add(opt.cat);
        }
      }

      // Pick best 1 woman.
      final femaleOptions = <({CyclingCategory cat, int place, int time, int age})>[];
      for (final cat in activeFemaleCats) {
        final standings = categoryStandings[cat]!;
        final teamResults = standings.where((r) => r.result.teamId == teamId).toList();
        if (teamResults.isNotEmpty) {
          femaleOptions.add((
            cat: cat,
            place: teamResults.first.place,
            time: teamResults.first.result.totalDsec,
            age: teamResults.first.age,
          ));
        }
      }
      femaleOptions.sort((a, b) => a.place.compareTo(b.place));

      final selectedFemale = femaleOptions.isNotEmpty ? femaleOptions.first : null;

      // Build scoring places.
      final scoringPlaces = <int>[];
      double bestWomanTime = double.infinity;
      int sumOfAges = 0;

      for (int i = 0; i < 2; i++) {
        if (i < selectedMale.length) {
          scoringPlaces.add(selectedMale[i].place);
          sumOfAges += selectedMale[i].age;
        } else {
          scoringPlaces.add(penaltyPlace);
        }
      }
      if (selectedFemale != null) {
        scoringPlaces.add(selectedFemale.place);
        sumOfAges += selectedFemale.age;
        bestWomanTime = selectedFemale.time.toDouble();
      } else {
        scoringPlaces.add(penaltyPlace);
      }

      final totalPoints = scoringPlaces.fold<int>(0, (sum, p) => sum + p);

      int sumOfTimes = 0;
      for (int i = 0; i < 2; i++) {
        if (i < selectedMale.length) sumOfTimes += selectedMale[i].time;
      }
      if (selectedFemale != null) sumOfTimes += selectedFemale.time;

      final categoryPlacesMap = <CyclingCategory, List<int>>{};
      for (final cat in CyclingCategory.values) {
        categoryPlacesMap[cat] = placesForTeam(categoryStandings[cat]!, teamId);
      }

      teamStandings.add(_CyclingTeamScore(
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

    final maxPlace = teamStandings
        .expand((t) => t.scoringPlaces)
        .fold<int>(0, (m, p) => p > m ? p : m);

    teamStandings.sort((a, b) {
      // Primary: lowest total points.
      final cmp = a.totalPoints.compareTo(b.totalPoints);
      if (cmp != 0) return cmp;

      // Tiebreak 1: more 1st places, then 2nd, 3rd, etc.
      for (int p = 1; p <= maxPlace; p++) {
        final aCount = a.scoringPlaces.where((x) => x == p).length;
        final bCount = b.scoringPlaces.where((x) => x == p).length;
        if (aCount != bCount) return bCount.compareTo(aCount);
      }

      // Tiebreak 2: lowest sum of times.
      final timeCmp = a.sumOfTimes.compareTo(b.sumOfTimes);
      if (timeCmp != 0) return timeCmp;

      // Tiebreak 3: largest sum of ages.
      final ageCmp = b.sumOfAges.compareTo(a.sumOfAges);
      if (ageCmp != 0) return ageCmp;

      // Tiebreak 4: best result among women.
      final womanCmp = a.bestWomanTime.compareTo(b.bestWomanTime);
      if (womanCmp != 0) return womanCmp;

      return 0;
    });

    final result = <CyclingTeamStanding>[];
    for (int i = 0; i < teamStandings.length; i++) {
      final t = teamStandings[i];
      int place = i + 1;
      if (i > 0) {
        final prev = teamStandings[i - 1];
        if (t.totalPoints == prev.totalPoints) {
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
      result.add(CyclingTeamStanding(
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

  /// Apply category merging: if a category has <5 participants, merge it into
  /// the next younger category. Cycling merge order: m50→m49→m35, f49→f35.
  void _applyCategoryMerging(
      Map<CyclingCategory, List<RankedCyclingResult>> standings) {
    final mergeOrder = [
      (from: CyclingCategory.m50, to: CyclingCategory.m49),
      (from: CyclingCategory.m49, to: CyclingCategory.m35),
      (from: CyclingCategory.f49, to: CyclingCategory.f35),
    ];

    for (final merge in mergeOrder) {
      if (standings[merge.from]!.length < 5 && standings[merge.from]!.isNotEmpty) {
        standings[merge.to]!.addAll(standings[merge.from]!);
        standings[merge.from] = [];
        standings[merge.to]!.sort((a, b) =>
            a.result.totalDsec.compareTo(b.result.totalDsec));
        _reRank(standings[merge.to]!);
      }
    }
  }

  void _reRank(List<RankedCyclingResult> standings) {
    int place = 1;
    for (int i = 0; i < standings.length; i++) {
      if (i > 0 &&
          standings[i].result.totalDsec != standings[i - 1].result.totalDsec) {
        place = i + 1;
      }
      final current = standings[i];
      standings[i] = RankedCyclingResult(
        result: current.result,
        place: place,
        playerName: current.playerName,
        teamName: current.teamName,
        age: current.age,
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

  Future<void> saveAssignedCategory({
    required int playerId,
    required int tId,
    required CyclingCategory category,
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

  /// Map of playerId → assigned CyclingCategory for the tournament.
  /// Only contains entries where an override exists.
  Future<Map<int, CyclingCategory>> getAssignedCategories(int tId) async {
    final db = await _dbService.database;
    final rows = await db.rawQuery('''
      SELECT pt.player_id, v.attr_value
      FROM CMP_PLAYER_TEAM pt
      JOIN CMP_PLAYER_TEAM_ATTR_VALUE v ON pt.pte_id = v.pte_id
      WHERE pt.t_id = ? AND v.attr_id = ? AND v.attr_value IS NOT NULL
    ''', [tId, _attrIdAssignedCategory]);
    final map = <int, CyclingCategory>{};
    for (final r in rows) {
      final pid = r['player_id'] as int;
      final value = r['attr_value'] as String? ?? '';
      if (value.isEmpty) continue;
      map[pid] = CyclingCategory.fromDb(value);
    }
    return map;
  }

  // ── Year of birth override (CMP_PLAYER_TEAM_ATTR_VALUE attr_id=21) ──

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

  /// Map of playerId → year-of-birth for every cycling participant in [tId]
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

  /// All cycling participants of a tournament with their assignment state
  /// and existing result (if any). Used by the inline-entry "Всі учасники" tab.
  Future<List<CyclingParticipantEntry>> getAllParticipants(int tId) async {
    final db = await _dbService.database;
    final referenceYear = await _tournamentReferenceYear(tId);

    final cyCategories =
        CyclingCategory.values.map((c) => "'${c.name}'").join(',');
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
                 AND se.se_note IN ($cyCategories)
               ORDER BY se.se_id DESC LIMIT 1
             ) as result_id,
             (
               SELECT se.se_result FROM CMP_SUBEVENT se
               JOIN CMP_EVENT e ON se.ev_id = e.event_id
               WHERE e.t_id = pt.t_id AND se.entity_id = p.entity_id
                 AND se.se_note IN ($cyCategories)
               ORDER BY se.se_id DESC LIMIT 1
             ) as result_total,
             (
               SELECT se.se_note FROM CMP_SUBEVENT se
               JOIN CMP_EVENT e ON se.ev_id = e.event_id
               WHERE e.t_id = pt.t_id AND se.entity_id = p.entity_id
                 AND se.se_note IN ($cyCategories)
               ORDER BY se.se_id DESC LIMIT 1
             ) as result_category
      FROM CMP_PLAYER_TEAM pt
      JOIN CMP_PLAYER p ON pt.player_id = p.player_id
      LEFT JOIN CMP_TEAM t ON pt.team_id = t.team_id
      WHERE pt.t_id = ? AND pt.player_state IN (0, 1)
      ORDER BY p.player_surname, p.player_name
    ''', [tId]);

    final entries = <CyclingParticipantEntry>[];
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
      final autoCat = CyclingCategory.detectCategory(
        age > 0 ? birthYear : null,
        gender,
      );
      final surname = r['player_surname'] as String? ?? '';
      final name = r['player_name'] as String? ?? '';
      final lastname = r['player_lastname'] as String? ?? '';

      final assignedRaw = r['assigned_category'] as String?;
      final assigned = (assignedRaw != null && assignedRaw.isNotEmpty)
          ? CyclingCategory.fromDb(assignedRaw)
          : null;

      final number = int.tryParse(r['player_number'] as String? ?? '');
      final resultId = r['result_id'] as int?;
      final resultTotal = (r['result_total'] as num?)?.toInt();
      final resultCategoryRaw = r['result_category'] as String?;
      final resultCategory = (resultCategoryRaw != null && resultCategoryRaw.isNotEmpty)
          ? CyclingCategory.fromDb(resultCategoryRaw)
          : null;

      entries.add(CyclingParticipantEntry(
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
}

class _CyclingTeamScore {
  final int teamId;
  final String teamName;
  final Map<CyclingCategory, List<int>> categoryPlaces;
  final List<int> scoringPlaces;
  final int totalPoints;
  final int sumOfTimes;
  final int sumOfAges;
  final double bestWomanTime;

  _CyclingTeamScore({
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
