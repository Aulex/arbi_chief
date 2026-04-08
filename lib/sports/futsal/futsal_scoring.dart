/// Futsal scoring utilities.
///
/// Provides result formatting and tiebreaker logic specific to Futsal.
/// Rules: 3 pts win, 1 pt draw, 0 pt loss.
/// Tie-breakers: H2H, H2H Goal Diff, Total Goal Diff, Total Goals.

class FutsalStanding {
  final int teamId;
  final String teamName;
  final int? entityId;
  int matchPoints;
  int wins;
  int draws;
  int losses;
  int goalsScored;
  int goalsConceded;
  bool isRemoved;
  int rank;

  FutsalStanding({
    required this.teamId,
    required this.teamName,
    this.entityId,
    this.matchPoints = 0,
    this.wins = 0,
    this.draws = 0,
    this.losses = 0,
    this.goalsScored = 0,
    this.goalsConceded = 0,
    this.isRemoved = false,
    this.rank = 0,
  });

  int get goalDifference => goalsScored - goalsConceded;
}

List<FutsalStanding> calculateStandings({
  required List<({int teamId, String teamName, int? entityId})> teams,
  required Map<(int, int), String> games,
  Set<int> removedTeamIds = const {},
}) {
  final standings = <int, FutsalStanding>{};

  for (final team in teams) {
    standings[team.teamId] = FutsalStanding(
      teamId: team.teamId,
      teamName: team.teamName,
      entityId: team.entityId,
      isRemoved: removedTeamIds.contains(team.teamId),
    );
  }

  for (final entry in games.entries) {
    final (aEntId, bEntId) = entry.key;
    final detail = entry.value;

    final teamAInfo = teams.where((t) => t.entityId == aEntId).firstOrNull;
    final teamBInfo = teams.where((t) => t.entityId == bEntId).firstOrNull;
    if (teamAInfo == null || teamBInfo == null) continue;

    final standingA = standings[teamAInfo.teamId]!;
    final standingB = standings[teamBInfo.teamId]!;

    if (standingA.isRemoved || standingB.isRemoved) continue;

    final parts = detail.split(':');
    if (parts.length != 2) continue;
    final aGoals = int.tryParse(parts[0]) ?? 0;
    final bGoals = int.tryParse(parts[1]) ?? 0;

    standingA.goalsScored += aGoals;
    standingA.goalsConceded += bGoals;
    standingB.goalsScored += bGoals;
    standingB.goalsConceded += aGoals;

    if (aGoals > bGoals) {
      standingA.matchPoints += 3;
      standingA.wins++;
      standingB.losses++;
    } else if (aGoals < bGoals) {
      standingB.matchPoints += 3;
      standingB.wins++;
      standingA.losses++;
    } else {
      standingA.matchPoints += 1;
      standingB.matchPoints += 1;
      standingA.draws++;
      standingB.draws++;
    }
  }

  final result = standings.values.toList();

  result.sort((a, b) {
    if (a.isRemoved != b.isRemoved) return a.isRemoved ? 1 : -1;
    final ptsCmp = b.matchPoints.compareTo(a.matchPoints);
    if (ptsCmp != 0) return ptsCmp;

    // Tie-breaker 1: Head-to-head points
    final h2hPoints = _getH2HPoints(a, b, games);
    if (h2hPoints != 0) return -h2hPoints;

    // Tie-breaker 2: H2H goal difference
    final h2hGoalDiff = _getH2HGoalDiff(a, b, games);
    if (h2hGoalDiff != 0) return -h2hGoalDiff;

    // Tie-breaker 3: Total goal difference
    final diffCmp = b.goalDifference.compareTo(a.goalDifference);
    if (diffCmp != 0) return diffCmp;

    // Tie-breaker 4: Total goals scored
    return b.goalsScored.compareTo(a.goalsScored);
  });

  for (int i = 0; i < result.length; i++) {
    result[i].rank = i + 1;
  }

  return result;
}

int _getH2HPoints(FutsalStanding a, FutsalStanding b, Map<(int, int), String> games) {
  if (a.entityId == null || b.entityId == null) return 0;
  final ab = games[(a.entityId!, b.entityId!)];
  final ba = games[(b.entityId!, a.entityId!)];

  int aPts = 0;
  int bPts = 0;

  void add(String? detail, bool isAB) {
    if (detail == null) return;
    final p = detail.split(':');
    if (p.length != 2) return;
    final g1 = int.tryParse(p[0]) ?? 0;
    final g2 = int.tryParse(p[1]) ?? 0;
    if (g1 > g2) {
      if (isAB) aPts += 3; else bPts += 3;
    } else if (g1 < g2) {
      if (isAB) bPts += 3; else aPts += 3;
    } else {
      aPts += 1;
      bPts += 1;
    }
  }

  add(ab, true);
  add(ba, false);
  return aPts - bPts;
}

int _getH2HGoalDiff(FutsalStanding a, FutsalStanding b, Map<(int, int), String> games) {
  if (a.entityId == null || b.entityId == null) return 0;
  final ab = games[(a.entityId!, b.entityId!)];
  final ba = games[(b.entityId!, a.entityId!)];

  int aDiff = 0;
  if (ab != null) {
    final p = ab.split(':');
    if (p.length == 2) aDiff += (int.tryParse(p[0]) ?? 0) - (int.tryParse(p[1]) ?? 0);
  }
  if (ba != null) {
    final p = ba.split(':');
    if (p.length == 2) aDiff += (int.tryParse(p[1]) ?? 0) - (int.tryParse(p[0]) ?? 0);
  }
  return aDiff;
}
