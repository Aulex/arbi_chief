import '../models/volleyball_model.dart';
import 'database_service.dart';

class VolleyballService {
  final DatabaseService _dbService;

  VolleyballService(this._dbService);

  // ── CRUD ──

  Future<int> saveMatch(VolleyballMatch match) async {
    final db = await _dbService.database;
    final map = match.toMap();
    if (match.id != null) {
      await db.update('CMP_VOLLEYBALL_MATCH', map,
          where: 'vm_id = ?', whereArgs: [match.id]);
      return match.id!;
    } else {
      return await db.insert('CMP_VOLLEYBALL_MATCH', map);
    }
  }

  Future<void> deleteMatch(int vmId) async {
    final db = await _dbService.database;
    await db.delete('CMP_VOLLEYBALL_MATCH',
        where: 'vm_id = ?', whereArgs: [vmId]);
  }

  Future<void> deleteAllMatches(int tId) async {
    final db = await _dbService.database;
    await db.delete('CMP_VOLLEYBALL_MATCH',
        where: 't_id = ?', whereArgs: [tId]);
  }

  /// Get all matches for a tournament, optionally filtered by group/stage.
  Future<List<VolleyballMatch>> getMatches(int tId,
      {String? groupName, String? stage}) async {
    final db = await _dbService.database;
    var where = 't_id = ?';
    final whereArgs = <dynamic>[tId];
    if (groupName != null) {
      where += ' AND group_name = ?';
      whereArgs.add(groupName);
    }
    if (stage != null) {
      where += ' AND stage = ?';
      whereArgs.add(stage);
    }
    final rows = await db.query('CMP_VOLLEYBALL_MATCH',
        where: where, whereArgs: whereArgs, orderBy: 'vm_id ASC');
    return rows.map((r) => VolleyballMatch.fromMap(r)).toList();
  }

  /// Find a match between two teams in a tournament (any order).
  Future<VolleyballMatch?> findMatchBetweenTeams(
      int tId, int team1Id, int team2Id,
      {String? groupName, String? stage}) async {
    final db = await _dbService.database;
    var where =
        't_id = ? AND ((home_team_id = ? AND away_team_id = ?) OR (home_team_id = ? AND away_team_id = ?))';
    final whereArgs = <dynamic>[tId, team1Id, team2Id, team2Id, team1Id];
    if (groupName != null) {
      where += ' AND group_name = ?';
      whereArgs.add(groupName);
    }
    if (stage != null) {
      where += ' AND stage = ?';
      whereArgs.add(stage);
    }
    final rows = await db.query('CMP_VOLLEYBALL_MATCH',
        where: where, whereArgs: whereArgs, limit: 1);
    if (rows.isEmpty) return null;
    return VolleyballMatch.fromMap(rows.first);
  }

  // ── Round-Robin Generation ──

  /// Generate all round-robin matches for teams within a group/stage.
  /// Does not overwrite existing matches.
  Future<void> generateRoundRobinMatches(
    int tId,
    List<int> teamIds, {
    String? groupName,
    String stage = 'group',
  }) async {
    final db = await _dbService.database;
    for (int i = 0; i < teamIds.length; i++) {
      for (int j = i + 1; j < teamIds.length; j++) {
        // Check if match already exists
        final existing = await findMatchBetweenTeams(
            tId, teamIds[i], teamIds[j],
            groupName: groupName, stage: stage);
        if (existing != null) continue;

        await db.insert('CMP_VOLLEYBALL_MATCH', {
          't_id': tId,
          'group_name': groupName,
          'stage': stage,
          'home_team_id': teamIds[i],
          'away_team_id': teamIds[j],
          'home_sets': 0,
          'away_sets': 0,
          'is_forfeit': 0,
        });
      }
    }
  }

  // ── Standings Calculation ──

  /// Calculate standings for a set of matches.
  /// Implements the volleyball scoring rules:
  /// - Win = 2 pts, Loss = 1 pt, Forfeit = 0 pts
  /// - Tiebreakers: head-to-head → set ratio → point ratio
  /// - Results against disqualified teams (second no-show) are excluded.
  List<VolleyballTeamStanding> calculateStandings(
    List<VolleyballMatch> matches,
    Map<int, String> teamNames,
  ) {
    final teamIds = teamNames.keys.toList();

    // Count forfeits per team
    final forfeitCounts = <int, int>{};
    for (final m in matches) {
      if (m.isForfeit) {
        // The team that lost by forfeit gets counted
        if (m.homeSets < m.awaySets) {
          forfeitCounts[m.homeTeamId] =
              (forfeitCounts[m.homeTeamId] ?? 0) + 1;
        } else {
          forfeitCounts[m.awayTeamId] =
              (forfeitCounts[m.awayTeamId] ?? 0) + 1;
        }
      }
    }

    // Teams with 2+ forfeits are disqualified
    final disqualifiedTeams = forfeitCounts.entries
        .where((e) => e.value >= 2)
        .map((e) => e.key)
        .toSet();

    // Filter out matches involving disqualified teams
    final validMatches = matches
        .where((m) =>
            !disqualifiedTeams.contains(m.homeTeamId) &&
            !disqualifiedTeams.contains(m.awayTeamId))
        .toList();

    // Build standings for each non-disqualified team
    final scores = <int, _TeamScore>{};
    for (final teamId in teamIds) {
      if (disqualifiedTeams.contains(teamId)) continue;
      scores[teamId] = _TeamScore(
          teamId: teamId, teamName: teamNames[teamId] ?? '');
    }

    for (final m in validMatches) {
      if (!m.isPlayed) continue;

      final home = scores[m.homeTeamId];
      final away = scores[m.awayTeamId];
      if (home == null || away == null) continue;

      home.played++;
      away.played++;

      home.setsWon += m.homeSets;
      home.setsLost += m.awaySets;
      away.setsWon += m.awaySets;
      away.setsLost += m.homeSets;

      home.pointsWon += m.homePointsTotal;
      home.pointsLost += m.awayPointsTotal;
      away.pointsWon += m.awayPointsTotal;
      away.pointsLost += m.homePointsTotal;

      if (m.isForfeit) {
        // Forfeit: the losing team gets 0 pts
        if (m.homeSets > m.awaySets) {
          home.wins++;
          home.points += 2;
          away.losses++;
          away.forfeits++;
          // No-show team gets 0 points (not 1)
        } else {
          away.wins++;
          away.points += 2;
          home.losses++;
          home.forfeits++;
        }
      } else {
        if (m.homeSets > m.awaySets) {
          home.wins++;
          home.points += 2;
          away.losses++;
          away.points += 1;
        } else {
          away.wins++;
          away.points += 2;
          home.losses++;
          home.points += 1;
        }
      }
    }

    // Sort by points, then tiebreakers
    final sorted = scores.values.toList();
    _sortWithTiebreakers(sorted, validMatches);

    // Assign places
    final result = <VolleyballTeamStanding>[];
    for (int i = 0; i < sorted.length; i++) {
      final t = sorted[i];
      int place = i + 1;
      // Same place for tied teams (same points + can't break tie)
      if (i > 0 && _isTied(sorted[i - 1], t, validMatches)) {
        place = result[i - 1].place;
      }
      result.add(VolleyballTeamStanding(
        teamId: t.teamId,
        teamName: t.teamName,
        played: t.played,
        wins: t.wins,
        losses: t.losses,
        points: t.points,
        setsWon: t.setsWon,
        setsLost: t.setsLost,
        pointsWon: t.pointsWon,
        pointsLost: t.pointsLost,
        forfeits: t.forfeits,
        place: place,
      ));
    }
    return result;
  }

  void _sortWithTiebreakers(
      List<_TeamScore> teams, List<VolleyballMatch> matches) {
    teams.sort((a, b) {
      // 1. Points (descending)
      final cmp = b.points.compareTo(a.points);
      if (cmp != 0) return cmp;

      // 2. Head-to-head result
      final h2h = _headToHeadResult(a.teamId, b.teamId, matches);
      if (h2h != 0) return h2h;

      // 3. Set ratio (higher is better)
      final aSetRatio =
          a.setsLost > 0 ? a.setsWon / a.setsLost : a.setsWon.toDouble();
      final bSetRatio =
          b.setsLost > 0 ? b.setsWon / b.setsLost : b.setsWon.toDouble();
      final setCmp = bSetRatio.compareTo(aSetRatio);
      if (setCmp != 0) return setCmp;

      // 4. Point ratio (higher is better)
      final aPtRatio = a.pointsLost > 0
          ? a.pointsWon / a.pointsLost
          : a.pointsWon.toDouble();
      final bPtRatio = b.pointsLost > 0
          ? b.pointsWon / b.pointsLost
          : b.pointsWon.toDouble();
      return bPtRatio.compareTo(aPtRatio);
    });
  }

  /// Returns -1 if team1 beat team2, 1 if team2 beat team1, 0 if no result.
  int _headToHeadResult(
      int team1Id, int team2Id, List<VolleyballMatch> matches) {
    for (final m in matches) {
      if (!m.isPlayed) continue;
      if (m.homeTeamId == team1Id && m.awayTeamId == team2Id) {
        if (m.homeSets > m.awaySets) return -1;
        if (m.homeSets < m.awaySets) return 1;
      }
      if (m.homeTeamId == team2Id && m.awayTeamId == team1Id) {
        if (m.homeSets > m.awaySets) return 1;
        if (m.homeSets < m.awaySets) return -1;
      }
    }
    return 0;
  }

  bool _isTied(
      _TeamScore a, _TeamScore b, List<VolleyballMatch> matches) {
    if (a.points != b.points) return false;
    if (_headToHeadResult(a.teamId, b.teamId, matches) != 0) return false;
    final aSetRatio =
        a.setsLost > 0 ? a.setsWon / a.setsLost : a.setsWon.toDouble();
    final bSetRatio =
        b.setsLost > 0 ? b.setsWon / b.setsLost : b.setsWon.toDouble();
    if (aSetRatio != bSetRatio) return false;
    final aPtRatio = a.pointsLost > 0
        ? a.pointsWon / a.pointsLost
        : a.pointsWon.toDouble();
    final bPtRatio = b.pointsLost > 0
        ? b.pointsWon / b.pointsLost
        : b.pointsWon.toDouble();
    return aPtRatio == bPtRatio;
  }

  // ── Team Standings (convenience) ──

  /// Get full standings for a tournament (round-robin or specific group).
  Future<List<VolleyballTeamStanding>> getStandings(int tId,
      {String? groupName, String? stage}) async {
    final db = await _dbService.database;
    final matches =
        await getMatches(tId, groupName: groupName, stage: stage);

    // Get team names for teams in these matches
    final teamIds = <int>{};
    for (final m in matches) {
      teamIds.add(m.homeTeamId);
      teamIds.add(m.awayTeamId);
    }
    if (teamIds.isEmpty) return [];

    final teamNames = <int, String>{};
    for (final teamId in teamIds) {
      final rows = await db.query('CMP_TEAM',
          columns: ['team_name'],
          where: 'team_id = ?',
          whereArgs: [teamId],
          limit: 1);
      if (rows.isNotEmpty) {
        teamNames[teamId] = rows.first['team_name'] as String;
      }
    }

    return calculateStandings(matches, teamNames);
  }

  /// Get all groups for a mixed-system tournament.
  Future<List<String>> getGroups(int tId) async {
    final db = await _dbService.database;
    final rows = await db.rawQuery('''
      SELECT DISTINCT group_name FROM CMP_VOLLEYBALL_MATCH
      WHERE t_id = ? AND group_name IS NOT NULL
      ORDER BY group_name
    ''', [tId]);
    return rows
        .map((r) => r['group_name'] as String)
        .toList();
  }

  /// Get all teams participating in this volleyball tournament.
  Future<List<({int teamId, String teamName})>> getTeamsForTournament(
      int tId) async {
    final db = await _dbService.database;
    final rows = await db.rawQuery('''
      SELECT DISTINCT t.team_id, t.team_name
      FROM CMP_PLAYER_TEAM pt
      JOIN CMP_TEAM t ON pt.team_id = t.team_id
      WHERE pt.t_id = ?
      ORDER BY t.team_name
    ''', [tId]);
    return rows
        .map((r) => (
              teamId: r['team_id'] as int,
              teamName: r['team_name'] as String,
            ))
        .toList();
  }

  /// Record a forfeit (неявка) for a team against all opponents in a group.
  /// Score: 0:2 for the no-show team.
  Future<void> recordForfeit(int tId, int forfeitTeamId,
      {String? groupName, String stage = 'group'}) async {
    final matches =
        await getMatches(tId, groupName: groupName, stage: stage);

    for (final m in matches) {
      if (!m.isPlayed &&
          (m.homeTeamId == forfeitTeamId ||
              m.awayTeamId == forfeitTeamId)) {
        final isHome = m.homeTeamId == forfeitTeamId;
        await saveMatch(m.copyWith(
          homeSets: isHome ? 0 : 2,
          awaySets: isHome ? 2 : 0,
          set1Home: isHome ? 0 : 25,
          set1Away: isHome ? 25 : 0,
          set2Home: isHome ? 0 : 25,
          set2Away: isHome ? 25 : 0,
          isForfeit: true,
        ));
      }
    }
  }

  /// Get the match result between two specific teams, from team1's perspective.
  /// Returns the match or null if not found.
  Future<({int homeSets, int awaySets, String setScores})?> getResultForCrossTable(
    int tId,
    int team1Id,
    int team2Id, {
    String? groupName,
    String? stage,
  }) async {
    final match = await findMatchBetweenTeams(tId, team1Id, team2Id,
        groupName: groupName, stage: stage);
    if (match == null || !match.isPlayed) return null;

    // Return from team1's perspective
    if (match.homeTeamId == team1Id) {
      return (
        homeSets: match.homeSets,
        awaySets: match.awaySets,
        setScores: match.setScoresDisplay,
      );
    } else {
      return (
        homeSets: match.awaySets,
        awaySets: match.homeSets,
        setScores: _mirrorSetScores(match),
      );
    }
  }

  String _mirrorSetScores(VolleyballMatch m) {
    final parts = <String>[];
    if (m.set1Home != null && m.set1Away != null) {
      parts.add('${m.set1Away}:${m.set1Home}');
    }
    if (m.set2Home != null && m.set2Away != null) {
      parts.add('${m.set2Away}:${m.set2Home}');
    }
    if (m.set3Home != null && m.set3Away != null) {
      parts.add('${m.set3Away}:${m.set3Home}');
    }
    return parts.join(' ');
  }
}

class _TeamScore {
  final int teamId;
  final String teamName;
  int played = 0;
  int wins = 0;
  int losses = 0;
  int points = 0;
  int setsWon = 0;
  int setsLost = 0;
  int pointsWon = 0;
  int pointsLost = 0;
  int forfeits = 0;

  _TeamScore({required this.teamId, required this.teamName});
}
