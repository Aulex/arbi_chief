/// Volleyball scoring utilities.
///
/// Provides set/point counting, result formatting, and tiebreaker logic
/// specific to volleyball. Used by cross-table UI and PDF reports.

/// Volleyball match points: Win=2, Loss=1, No-show=0.
const int volleyballWinPoints = 2;
const int volleyballLossPoints = 1;
const int volleyballNoShowPoints = 0;

/// Count set wins and losses from a detail string like "25:20 25:18" or "25:20 20:25 15:10".
({int won, int lost}) countSetsFromDetail(String detail) {
  int won = 0;
  int lost = 0;
  for (final s in detail.split(' ')) {
    final parts = s.split(':');
    if (parts.length != 2) continue;
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    if (a == null || b == null) continue;
    if (a > b) {
      won++;
    } else if (b > a) {
      lost++;
    }
  }
  return (won: won, lost: lost);
}

/// Count total points scored and conceded from a detail string.
({int scored, int conceded}) countPointsFromDetail(String detail) {
  int scored = 0;
  int conceded = 0;
  for (final s in detail.split(' ')) {
    final parts = s.split(':');
    if (parts.length != 2) continue;
    scored += int.tryParse(parts[0]) ?? 0;
    conceded += int.tryParse(parts[1]) ?? 0;
  }
  return (scored: scored, conceded: conceded);
}

/// Format a volleyball cell result from detail string.
/// Shows set count like "2:0" or "2:1".
String formatVolleyballCell(String detail) {
  final sets = countSetsFromDetail(detail);
  return '${sets.won}:${sets.lost}';
}

/// Format result for a no-show game.
String formatNoShowResult(bool isWinner) {
  return isWinner ? '+' : '-';
}

/// Default no-show game detail strings (2:0 via 25:0, 25:0).
const String noShowWinDetail = '25:0 25:0';
const String noShowLossDetail = '0:25 0:25';

/// Determine match winner from set scores detail string.
/// Returns true if the team (whose perspective the detail is from) won.
bool isMatchWinner(String detail) {
  final sets = countSetsFromDetail(detail);
  return sets.won > sets.lost;
}

/// Volleyball standing entry for a team.
class VolleyballStanding {
  final int teamId;
  final String teamName;
  final int? entityId;
  int matchPoints;
  int wins;
  int losses;
  int setsWon;
  int setsLost;
  int pointsScored;
  int pointsConceded;
  bool isRemoved;
  int rank;

  VolleyballStanding({
    required this.teamId,
    required this.teamName,
    this.entityId,
    this.matchPoints = 0,
    this.wins = 0,
    this.losses = 0,
    this.setsWon = 0,
    this.setsLost = 0,
    this.pointsScored = 0,
    this.pointsConceded = 0,
    this.isRemoved = false,
    this.rank = 0,
  });

  double get setRatio => setsLost == 0 ? setsWon.toDouble() : setsWon / setsLost;
  double get pointRatio => pointsConceded == 0 ? pointsScored.toDouble() : pointsScored / pointsConceded;
}

/// Calculate standings from game results.
///
/// [teams] — list of (teamId, teamName, entityId) tuples.
/// [games] — map of (teamAEntityId, teamBEntityId) → detail string from teamA's perspective.
/// [removedTeamIds] — set of team IDs that have been removed (2nd no-show).
/// [noShowGamePairs] — set of (entityA, entityB) pairs for forfeited games (es_id=4).
///   These specific games are excluded from tiebreaker calculations per the rules.
List<VolleyballStanding> calculateStandings({
  required List<({int teamId, String teamName, int? entityId})> teams,
  required Map<(int, int), String> games,
  Set<int> removedTeamIds = const {},
  Set<(int, int)> noShowGamePairs = const {},
}) {
  final standings = <int, VolleyballStanding>{};

  // Build entity→teamId lookup
  final entityToTeamId = <int, int>{};
  for (final team in teams) {
    standings[team.teamId] = VolleyballStanding(
      teamId: team.teamId,
      teamName: team.teamName,
      entityId: team.entityId,
      isRemoved: removedTeamIds.contains(team.teamId),
    );
    if (team.entityId != null) {
      entityToTeamId[team.entityId!] = team.teamId;
    }
  }

  // Process all games
  for (final entry in games.entries) {
    final (aEntId, bEntId) = entry.key;
    final detail = entry.value;

    final aTeamId = entityToTeamId[aEntId];
    final bTeamId = entityToTeamId[bEntId];
    if (aTeamId == null || bTeamId == null) continue;

    final standingA = standings[aTeamId]!;
    final standingB = standings[bTeamId]!;

    // Skip removed teams' results (2nd no-show — all results annulled)
    if (standingA.isRemoved || standingB.isRemoved) continue;

    final sets = countSetsFromDetail(detail);
    final points = countPointsFromDetail(detail);
    final mirrorDetail = _mirrorDetail(detail);
    final mirrorSets = countSetsFromDetail(mirrorDetail);
    final mirrorPoints = countPointsFromDetail(mirrorDetail);

    // Team A stats
    standingA.setsWon += sets.won;
    standingA.setsLost += sets.lost;
    standingA.pointsScored += points.scored;
    standingA.pointsConceded += points.conceded;

    // Team B stats (mirror)
    standingB.setsWon += mirrorSets.won;
    standingB.setsLost += mirrorSets.lost;
    standingB.pointsScored += mirrorPoints.scored;
    standingB.pointsConceded += mirrorPoints.conceded;

    if (sets.won > sets.lost) {
      standingA.matchPoints += volleyballWinPoints;
      standingA.wins++;
      standingB.matchPoints += volleyballLossPoints;
      standingB.losses++;
    } else {
      standingB.matchPoints += volleyballWinPoints;
      standingB.wins++;
      standingA.matchPoints += volleyballLossPoints;
      standingA.losses++;
    }
  }

  final result = standings.values.toList();

  // Sort: removed teams last, then by match points desc, then tiebreakers.
  //
  // Rules: when 2+ teams are tied on points, break tie using games
  // **between the tied teams only**, excluding games against no-show teams:
  //   1. Head-to-head points among tied group
  //   2. Set ratio in games among tied group
  //   3. Point ratio in games among tied group

  // Step 1: sort by removed flag and match points
  result.sort((a, b) {
    if (a.isRemoved != b.isRemoved) return a.isRemoved ? 1 : -1;
    return b.matchPoints.compareTo(a.matchPoints);
  });

  // Step 2: identify groups of teams tied on match points and resolve each
  int i = 0;
  while (i < result.length) {
    // Skip removed teams
    if (result[i].isRemoved) { i++; continue; }

    // Find the extent of this tied group
    int j = i + 1;
    while (j < result.length &&
           !result[j].isRemoved &&
           result[j].matchPoints == result[i].matchPoints) {
      j++;
    }

    if (j - i > 1) {
      // Multiple teams tied — resolve using head-to-head mini-tournament
      final tiedGroup = result.sublist(i, j);
      final resolved = _resolveTiedGroup(tiedGroup, games, teams, noShowGamePairs);
      result.replaceRange(i, j, resolved);
    }

    i = j;
  }

  // Assign ranks
  for (int i = 0; i < result.length; i++) {
    result[i].rank = i + 1;
  }

  return result;
}

/// Resolve a group of teams tied on match points.
///
/// Computes head-to-head stats using only games between teams in the group,
/// excluding forfeited (no-show) games per the rules:
/// "результати ігор з командами, які не з'явилися на ігри, не зараховуються"
///
/// Sorts by: h2h points → h2h set ratio → h2h point ratio.
List<VolleyballStanding> _resolveTiedGroup(
  List<VolleyballStanding> group,
  Map<(int, int), String> allGames,
  List<({int teamId, String teamName, int? entityId})> allTeams,
  Set<(int, int)> noShowGamePairs,
) {
  if (group.length <= 1) return group;

  // Compute head-to-head stats among this group, excluding no-show teams
  final entityIds = group.map((s) => s.entityId).whereType<int>().toSet();
  // Build entity→teamId for this group
  final entToTeam = <int, int>{};
  for (final s in group) {
    if (s.entityId != null) entToTeam[s.entityId!] = s.teamId;
  }

  final h2hStats = <int, ({int points, int setsWon, int setsLost, int ptScored, int ptConceded})>{};

  for (final s in group) {
    h2hStats[s.teamId] = (points: 0, setsWon: 0, setsLost: 0, ptScored: 0, ptConceded: 0);
  }

  for (final entry in allGames.entries) {
    final (aEntId, bEntId) = entry.key;
    if (!entityIds.contains(aEntId) || !entityIds.contains(bEntId)) continue;

    final aTeamId = entToTeam[aEntId];
    final bTeamId = entToTeam[bEntId];
    if (aTeamId == null || bTeamId == null) continue;

    // Exclude specific forfeited (no-show) games from tiebreaker
    if (noShowGamePairs.contains((aEntId, bEntId)) ||
        noShowGamePairs.contains((bEntId, aEntId))) continue;

    final detail = entry.value;
    final sets = countSetsFromDetail(detail);
    final pts = countPointsFromDetail(detail);
    final mirrorSets = countSetsFromDetail(_mirrorDetail(detail));
    final mirrorPts = countPointsFromDetail(_mirrorDetail(detail));

    final aOld = h2hStats[aTeamId]!;
    final bOld = h2hStats[bTeamId]!;

    int aWinPts = 0, bWinPts = 0;
    if (sets.won > sets.lost) {
      aWinPts = volleyballWinPoints;
      bWinPts = volleyballLossPoints;
    } else {
      bWinPts = volleyballWinPoints;
      aWinPts = volleyballLossPoints;
    }

    h2hStats[aTeamId] = (
      points: aOld.points + aWinPts,
      setsWon: aOld.setsWon + sets.won,
      setsLost: aOld.setsLost + sets.lost,
      ptScored: aOld.ptScored + pts.scored,
      ptConceded: aOld.ptConceded + pts.conceded,
    );
    h2hStats[bTeamId] = (
      points: bOld.points + bWinPts,
      setsWon: bOld.setsWon + mirrorSets.won,
      setsLost: bOld.setsLost + mirrorSets.lost,
      ptScored: bOld.ptScored + mirrorPts.scored,
      ptConceded: bOld.ptConceded + mirrorPts.conceded,
    );
  }

  // Sort by h2h points → h2h set ratio → h2h point ratio
  group.sort((a, b) {
    final aH = h2hStats[a.teamId]!;
    final bH = h2hStats[b.teamId]!;

    // 1. Head-to-head points
    final ptsCmp = bH.points.compareTo(aH.points);
    if (ptsCmp != 0) return ptsCmp;

    // 2. Set ratio among tied group
    final aSetRatio = aH.setsLost == 0 ? aH.setsWon.toDouble() : aH.setsWon / aH.setsLost;
    final bSetRatio = bH.setsLost == 0 ? bH.setsWon.toDouble() : bH.setsWon / bH.setsLost;
    final setCmp = bSetRatio.compareTo(aSetRatio);
    if (setCmp != 0) return setCmp;

    // 3. Point ratio among tied group
    final aPtRatio = aH.ptConceded == 0 ? aH.ptScored.toDouble() : aH.ptScored / aH.ptConceded;
    final bPtRatio = bH.ptConceded == 0 ? bH.ptScored.toDouble() : bH.ptScored / bH.ptConceded;
    return bPtRatio.compareTo(aPtRatio);
  });

  return group;
}

/// Mirror a detail string: "25:20 25:18" → "20:25 18:25".
String _mirrorDetail(String detail) {
  return detail.split(' ').map((s) {
    final parts = s.split(':');
    if (parts.length != 2) return s;
    return '${parts[1]}:${parts[0]}';
  }).join(' ');
}
