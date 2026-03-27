/// Streetball scoring utilities.
///
/// Rules: 2 pts win, 1 pt loss, 0 pt no-show.
/// Tie-breakers: H2H result, H2H goal difference, most goals scored.

class StreetballStanding {
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

  StreetballStanding({
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

  int get goalDifference => pointsScored - pointsConceded;
}

List<StreetballStanding> calculateStandings({
  required List<({int teamId, String teamName, int? entityId})> teams,
  required Map<(int, int), String> games,
  Set<int> removedTeamIds = const {},
}) {
  final standings = <int, StreetballStanding>{};

  for (final team in teams) {
    standings[team.teamId] = StreetballStanding(
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
    final aPts = int.tryParse(parts[0]) ?? 0;
    final bPts = int.tryParse(parts[1]) ?? 0;

    standingA.pointsScored += aPts;
    standingA.pointsConceded += bPts;
    standingB.pointsScored += bPts;
    standingB.pointsConceded += aPts;

    if (aPts > bPts) {
      standingA.matchPoints += 2;
      standingA.wins++;
      standingB.matchPoints += 1;
      standingB.losses++;
    } else {
      standingB.matchPoints += 2;
      standingB.wins++;
      standingA.matchPoints += 1;
      standingA.losses++;
    }
  }

  final result = standings.values.toList();

  result.sort((a, b) {
    if (a.isRemoved != b.isRemoved) return a.isRemoved ? 1 : -1;
    final ptsCmp = b.matchPoints.compareTo(a.matchPoints);
    if (ptsCmp != 0) return ptsCmp;

    // Tie-breaker 1: H2H result
    final h2hPts = _getH2HPoints(a, b, games);
    if (h2hPts != 0) return -h2hPts;

    // Tie-breaker 2: H2H goal difference
    final h2hDiffA = _getH2HGoalDiff(a, b, games);
    final h2hDiffB = _getH2HGoalDiff(b, a, games);
    if (h2hDiffA != h2hDiffB) return h2hDiffB.compareTo(h2hDiffA);

    // Tie-breaker 3: Most goals scored overall
    return b.pointsScored.compareTo(a.pointsScored);
  });

  for (int i = 0; i < result.length; i++) {
    result[i].rank = i + 1;
  }

  return result;
}

int _getH2HPoints(StreetballStanding a, StreetballStanding b, Map<(int, int), String> games) {
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
      if (isAB) { aPts += 2; bPts += 1; } else { bPts += 2; aPts += 1; }
    } else {
      if (isAB) { bPts += 2; aPts += 1; } else { aPts += 2; bPts += 1; }
    }
  }

  add(ab, true);
  add(ba, false);
  return aPts - bPts;
}

/// Goal difference for team [a] in H2H games against [b].
int _getH2HGoalDiff(StreetballStanding a, StreetballStanding b, Map<(int, int), String> games) {
  if (a.entityId == null || b.entityId == null) return 0;
  final ab = games[(a.entityId!, b.entityId!)];
  final ba = games[(b.entityId!, a.entityId!)];

  int scored = 0;
  int conceded = 0;

  if (ab != null) {
    final p = ab.split(':');
    if (p.length == 2) {
      scored += int.tryParse(p[0]) ?? 0;
      conceded += int.tryParse(p[1]) ?? 0;
    }
  }
  if (ba != null) {
    final p = ba.split(':');
    if (p.length == 2) {
      scored += int.tryParse(p[1]) ?? 0;
      conceded += int.tryParse(p[0]) ?? 0;
    }
  }

  return scored - conceded;
}
