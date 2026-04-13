/// Basketball scoring utilities.
///
/// Rules: 2 pts win, 1 pt loss, 0 pt no-show.
/// Tie-breakers (among tied group, excluding no-show games):
///   1. H2H match points
///   2. H2H point ratio (scored/conceded)
///   3. Total point ratio (scored/conceded)

/// Match points.
const int basketballWinPoints = 2;
const int basketballLossPoints = 1;
const int basketballNoShowPoints = 0;

/// No-show forfeit score (per basketball rules: 25:0).
const String basketballNoShowWinScore = '25:0';
const String basketballNoShowLossScore = '0:25';

class BasketballStanding {
  final int teamId;
  final String teamName;
  final int? entityId;
  int matchPoints;
  int wins;
  int losses;
  int pointsScored;
  int pointsConceded;
  bool isRemoved;
  int rank;

  BasketballStanding({
    required this.teamId,
    required this.teamName,
    this.entityId,
    this.matchPoints = 0,
    this.wins = 0,
    this.losses = 0,
    this.pointsScored = 0,
    this.pointsConceded = 0,
    this.isRemoved = false,
    this.rank = 0,
  });

  double get pointRatio => pointsConceded == 0 ? pointsScored.toDouble() : pointsScored / pointsConceded;
}

/// Calculate standings from game results.
///
/// [teams] — list of (teamId, teamName, entityId) tuples.
/// [games] — map of (teamAEntityId, teamBEntityId) → score string "goalsA:goalsB".
///   Only one direction per game (no duplicates).
/// [removedTeamIds] — teams removed after 2nd no-show.
/// [noShowGamePairs] — (entityA, entityB) pairs for forfeited games (es_id=4).
///   These games are excluded from tiebreaker calculations per the rules.
List<BasketballStanding> calculateStandings({
  required List<({int teamId, String teamName, int? entityId})> teams,
  required Map<(int, int), String> games,
  Set<int> removedTeamIds = const {},
  Set<(int, int)> noShowGamePairs = const {},
}) {
  final standings = <int, BasketballStanding>{};

  final entityToTeamId = <int, int>{};
  for (final team in teams) {
    standings[team.teamId] = BasketballStanding(
      teamId: team.teamId,
      teamName: team.teamName,
      entityId: team.entityId,
      isRemoved: removedTeamIds.contains(team.teamId),
    );
    if (team.entityId != null) {
      entityToTeamId[team.entityId!] = team.teamId;
    }
  }

  for (final entry in games.entries) {
    final (aEntId, bEntId) = entry.key;
    final detail = entry.value;

    final aTeamId = entityToTeamId[aEntId];
    final bTeamId = entityToTeamId[bEntId];
    if (aTeamId == null || bTeamId == null) continue;

    final standingA = standings[aTeamId]!;
    final standingB = standings[bTeamId]!;

    if (standingA.isRemoved || standingB.isRemoved) continue;

    final parts = detail.split(':');
    if (parts.length != 2) continue;
    final aPts = int.tryParse(parts[0]) ?? 0;
    final bPts = int.tryParse(parts[1]) ?? 0;

    standingA.pointsScored += aPts;
    standingA.pointsConceded += bPts;
    standingB.pointsScored += bPts;
    standingB.pointsConceded += aPts;

    if (aPts > bPts) {
      standingA.matchPoints += basketballWinPoints;
      standingA.wins++;
      standingB.matchPoints += basketballLossPoints;
      standingB.losses++;
    } else {
      standingB.matchPoints += basketballWinPoints;
      standingB.wins++;
      standingA.matchPoints += basketballLossPoints;
      standingA.losses++;
    }
  }

  final result = standings.values.toList();

  // Step 1: sort by removed flag and match points
  result.sort((a, b) {
    if (a.isRemoved != b.isRemoved) return a.isRemoved ? 1 : -1;
    return b.matchPoints.compareTo(a.matchPoints);
  });

  // Step 2: identify groups of teams tied on match points and resolve each
  int i = 0;
  while (i < result.length) {
    if (result[i].isRemoved) { i++; continue; }

    int j = i + 1;
    while (j < result.length &&
           !result[j].isRemoved &&
           result[j].matchPoints == result[i].matchPoints) {
      j++;
    }

    if (j - i > 1) {
      final tiedGroup = result.sublist(i, j);
      final resolved = _resolveTiedGroup(tiedGroup, games, teams, noShowGamePairs);
      result.replaceRange(i, j, resolved);
    }

    i = j;
  }

  for (int i = 0; i < result.length; i++) {
    result[i].rank = i + 1;
  }

  return result;
}

/// Resolve a group of teams tied on match points.
///
/// Computes head-to-head stats using only games between teams in the group,
/// excluding forfeited (no-show) games per the rules.
///
/// Sorts by: h2h points → h2h point ratio → total point ratio.
List<BasketballStanding> _resolveTiedGroup(
  List<BasketballStanding> group,
  Map<(int, int), String> allGames,
  List<({int teamId, String teamName, int? entityId})> allTeams,
  Set<(int, int)> noShowGamePairs,
) {
  if (group.length <= 1) return group;

  final entityIds = group.map((s) => s.entityId).whereType<int>().toSet();
  final entToTeam = <int, int>{};
  for (final s in group) {
    if (s.entityId != null) entToTeam[s.entityId!] = s.teamId;
  }

  final h2hStats = <int, ({int points, int ptScored, int ptConceded})>{};
  for (final s in group) {
    h2hStats[s.teamId] = (points: 0, ptScored: 0, ptConceded: 0);
  }

  for (final entry in allGames.entries) {
    final (aEntId, bEntId) = entry.key;
    if (!entityIds.contains(aEntId) || !entityIds.contains(bEntId)) continue;

    final aTeamId = entToTeam[aEntId];
    final bTeamId = entToTeam[bEntId];
    if (aTeamId == null || bTeamId == null) continue;

    // Exclude no-show games from tiebreaker
    if (noShowGamePairs.contains((aEntId, bEntId)) ||
        noShowGamePairs.contains((bEntId, aEntId))) continue;

    final detail = entry.value;
    final parts = detail.split(':');
    if (parts.length != 2) continue;
    final aPts = int.tryParse(parts[0]) ?? 0;
    final bPts = int.tryParse(parts[1]) ?? 0;

    final aOld = h2hStats[aTeamId]!;
    final bOld = h2hStats[bTeamId]!;

    int aWinPts = 0, bWinPts = 0;
    if (aPts > bPts) {
      aWinPts = basketballWinPoints;
      bWinPts = basketballLossPoints;
    } else {
      bWinPts = basketballWinPoints;
      aWinPts = basketballLossPoints;
    }

    h2hStats[aTeamId] = (
      points: aOld.points + aWinPts,
      ptScored: aOld.ptScored + aPts,
      ptConceded: aOld.ptConceded + bPts,
    );
    h2hStats[bTeamId] = (
      points: bOld.points + bWinPts,
      ptScored: bOld.ptScored + bPts,
      ptConceded: bOld.ptConceded + aPts,
    );
  }

  // Sort by h2h points → h2h point ratio → total point ratio
  group.sort((a, b) {
    final aH = h2hStats[a.teamId]!;
    final bH = h2hStats[b.teamId]!;

    // 1. Head-to-head match points
    final ptsCmp = bH.points.compareTo(aH.points);
    if (ptsCmp != 0) return ptsCmp;

    // 2. H2H point ratio (scored/conceded)
    final aH2hRatio = aH.ptConceded == 0 ? aH.ptScored.toDouble() : aH.ptScored / aH.ptConceded;
    final bH2hRatio = bH.ptConceded == 0 ? bH.ptScored.toDouble() : bH.ptScored / bH.ptConceded;
    final ratioCmp = bH2hRatio.compareTo(aH2hRatio);
    if (ratioCmp != 0) return ratioCmp;

    // 3. Total point ratio
    return b.pointRatio.compareTo(a.pointRatio);
  });

  return group;
}
