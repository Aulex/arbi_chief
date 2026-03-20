import '../models/swimming_model.dart';
import 'database_service.dart';

class SwimmingService {
  final DatabaseService _dbService;

  SwimmingService(this._dbService);

  // ── CRUD ──

  Future<int> saveResult(SwimmingResult result) async {
    final db = await _dbService.database;
    
    // 1. Get Entity ID
    int? entityId;
    if (result.playerId != null) {
      final rows = await db.query('CMP_PLAYER', columns: ['entity_id'], where: 'player_id = ?', whereArgs: [result.playerId]);
      if (rows.isNotEmpty) entityId = rows.first['entity_id'] as int?;
    } else {
      final rows = await db.query('CMP_TEAM', columns: ['entity_id'], where: 'team_id = ?', whereArgs: [result.teamId]);
      if (rows.isNotEmpty) entityId = rows.first['entity_id'] as int?;
    }

    if (entityId == null) throw Exception("Entity ID not found for participant");

    // 2. Create/Update CMP_EVENT
    int eventId;
    if (result.id != null) {
      // Find event associated with this subevent
      final subRows = await db.query('CMP_SUBEVENT', columns: ['ev_id'], where: 'se_id = ?', whereArgs: [result.id]);
      eventId = subRows.first['ev_id'] as int;
      
      await db.update('CMP_EVENT', {
        'event_result': result.totalDsec.toString(),
      }, where: 'event_id = ?', whereArgs: [eventId]);
    } else {
      // Find or create a tournament stage for this tournament
      final stageRows = await db.query('CMP_TOURNAMENT_STAGE', columns: ['ts_id'], where: 't_id = ?', whereArgs: [result.tournamentId]);
      int tsId;
      if (stageRows.isNotEmpty) {
        tsId = stageRows.first['ts_id'] as int;
      } else {
        tsId = await db.insert('CMP_TOURNAMENT_STAGE', {
          't_id': result.tournamentId,
          'ts_name': 'Основний етап',
          'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_s_ts',
        });
      }

      eventId = await db.insert('CMP_EVENT', {
        'ts_id': tsId,
        'et_id': result.category == SwimmingCategory.relay ? 2 : 1,
        'event_result': result.totalDsec.toString(),
        'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_s_ev',
      });
    }

    // 3. Save CMP_SUBEVENT
    final subEventMap = {
      'ev_id': eventId,
      'entity_id': entityId,
      'se_result': result.totalDsec.toDouble(),
      'se_note': result.category.name,
      'sync_uid': '${DateTime.now().microsecondsSinceEpoch}_s_se',
    };

    if (result.id != null) {
      await db.update('CMP_SUBEVENT', subEventMap, where: 'se_id = ?', whereArgs: [result.id]);
      return result.id!;
    } else {
      return await db.insert('CMP_SUBEVENT', subEventMap);
    }
  }

  Future<void> deleteResult(int seId) async {
    final db = await _dbService.database;
    // Get event ID first
    final rows = await db.query('CMP_SUBEVENT', columns: ['ev_id'], where: 'se_id = ?', whereArgs: [seId]);
    if (rows.isNotEmpty) {
      final evId = rows.first['ev_id'] as int;
      await db.delete('CMP_SUBEVENT', where: 'se_id = ?', whereArgs: [seId]);
      await db.delete('CMP_EVENT', where: 'event_id = ?', whereArgs: [evId]);
    }
  }

  Future<void> deleteAllResults(int tId) async {
    final db = await _dbService.database;
    // Only delete swimming-related subevents (those with swimming category names in se_note)
    final swimmingCategories = SwimmingCategory.values.map((c) => "'${c.name}'").join(',');
    // Find event IDs that have swimming subevents
    final eventRows = await db.rawQuery('''
      SELECT DISTINCT se.ev_id
      FROM CMP_SUBEVENT se
      JOIN CMP_EVENT e ON se.ev_id = e.event_id
      WHERE e.ts_id IN (SELECT ts_id FROM CMP_TOURNAMENT_STAGE WHERE t_id = ?)
        AND se.se_note IN ($swimmingCategories)
    ''', [tId]);

    if (eventRows.isEmpty) return;
    final eventIds = eventRows.map((r) => r['ev_id'] as int).toList();
    final placeholders = eventIds.map((_) => '?').join(',');

    await db.rawDelete('DELETE FROM CMP_SUBEVENT WHERE ev_id IN ($placeholders)', eventIds);
    await db.rawDelete('DELETE FROM CMP_EVENT WHERE event_id IN ($placeholders)', eventIds);
  }

  /// Get all results for a tournament, optionally filtered by category.
  Future<List<SwimmingResult>> getResults(int tId,
      {SwimmingCategory? category}) async {
    final db = await _dbService.database;
    
    final swimmingCategories = SwimmingCategory.values.map((c) => "'${c.name}'").join(',');
    String sql = '''
      SELECT se.se_id as sr_id, e.ts_id as t_id, se.se_result as time_total, se.se_note as category,
             p.player_id, t.team_id
      FROM CMP_SUBEVENT se
      JOIN CMP_EVENT e ON se.ev_id = e.event_id
      JOIN CMP_TOURNAMENT_STAGE stage ON e.ts_id = stage.ts_id
      LEFT JOIN CMP_PLAYER p ON se.entity_id = p.entity_id
      LEFT JOIN CMP_TEAM t ON se.entity_id = t.entity_id
      WHERE stage.t_id = ? AND se.se_note IN ($swimmingCategories)
    ''';

    final List<dynamic> args = [tId];
    if (category != null) {
      sql += ' AND se.se_note = ?';
      args.add(category.name);
    }
    sql += ' ORDER BY se.se_result ASC';

    final rows = await db.rawQuery(sql, args);
    return rows.map((r) {
      final total = (r['time_total'] as num).toInt();
      return SwimmingResult(
        id: r['sr_id'] as int,
        tournamentId: tId,
        playerId: r['player_id'] as int?,
        teamId: (r['team_id'] as int?) ?? 0,
        category: SwimmingCategory.fromDb(r['category'] as String),
        timeMin: total ~/ 6000,
        timeSec: (total % 6000) ~/ 100,
        timeDsec: total % 100,
      );
    }).toList();
  }

  // ── Individual Standings ──

  /// Returns ranked results for a category, sorted by time.
  /// Handles ties (same time = same place).
  Future<List<RankedSwimmingResult>> getCategoryStandings(
      int tId, SwimmingCategory category) async {
    final db = await _dbService.database;
    final rows = await db.rawQuery('''
      SELECT se.se_id as sr_id, e.ts_id as t_id, se.se_result as time_total, se.se_note as category,
             p.player_id, p.player_surname, p.player_name, p.player_lastname,
             t.team_id, t.team_name
      FROM CMP_SUBEVENT se
      JOIN CMP_EVENT e ON se.ev_id = e.event_id
      JOIN CMP_TOURNAMENT_STAGE stage ON e.ts_id = stage.ts_id
      LEFT JOIN CMP_PLAYER p ON se.entity_id = p.entity_id
      LEFT JOIN CMP_TEAM t ON se.entity_id = t.entity_id
      WHERE stage.t_id = ? AND se.se_note = ?
      ORDER BY se.se_result ASC
    ''', [tId, category.name]);

    final ranked = <RankedSwimmingResult>[];
    int place = 1;
    for (int i = 0; i < rows.length; i++) {
      final total = (rows[i]['time_total'] as num).toInt();
      final r = SwimmingResult(
        id: rows[i]['sr_id'] as int,
        tournamentId: tId,
        playerId: rows[i]['player_id'] as int?,
        teamId: (rows[i]['team_id'] as int?) ?? 0,
        category: SwimmingCategory.fromDb(rows[i]['category'] as String),
        timeMin: total ~/ 6000,
        timeSec: (total % 6000) ~/ 100,
        timeDsec: total % 100,
      );
      // Tie: same time as previous = same place
      if (i > 0) {
        final prevTotal = (rows[i - 1]['time_total'] as num).toInt();
        if (total != prevTotal) {
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

    // 1. Find team within the tournament
    final teamRows = await db.rawQuery('''
      SELECT DISTINCT t.team_id
      FROM CMP_TEAM t
      JOIN CMP_PLAYER_TEAM pt ON t.team_id = pt.team_id
      WHERE pt.t_id = ? AND t.team_name = ? COLLATE NOCASE
    ''', [tId, teamName.trim()]);

    if (teamRows.isEmpty) return (playerId: null, teamId: null);
    final teamId = teamRows.first['team_id'] as int;

    // 2. Find player within that team in the tournament
    // Construct the full name in SQL, replacing multiple spaces with single space for better matching
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
