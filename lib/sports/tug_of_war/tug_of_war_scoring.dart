/// Tug of War scoring utilities.
///
/// Rules: 2 pts win, 1 pt loss, 0 pt no-show.
/// Tie-breakers: H2H, Total team weight (less is better).

class TugOfWarStanding {
  final int teamId;
  final String teamName;
  final int? entityId;
  int matchPoints;
  int wins;
  int losses;
  double? teamWeight; // In kg, max 800 per regulation
  bool isRemoved;
  int rank;

  TugOfWarStanding({
    required this.teamId,
    required this.teamName,
    this.entityId,
    this.matchPoints = 0,
    this.wins = 0,
    this.losses = 0,
    this.teamWeight,
    this.isRemoved = false,
    this.rank = 0,
  });
}

List<TugOfWarStanding> calculateStandings({
  required List<({int teamId, String teamName, int? entityId, double? weight})> teams,
  required Map<(int, int), String> games,
  Set<int> removedTeamIds = const {},
}) {
  final standings = <int, TugOfWarStanding>{};

  for (final team in teams) {
    standings[team.teamId] = TugOfWarStanding(
      teamId: team.teamId,
      teamName: team.teamName,
      entityId: team.entityId,
      teamWeight: team.weight,
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

    // For Tug of War, result might be recorded as "1:0" for binary win/loss
    final parts = detail.split(':');
    if (parts.length != 2) continue;
    final aWin = int.tryParse(parts[0]) ?? 0;
    final bWin = int.tryParse(parts[1]) ?? 0;

    if (aWin > bWin) {
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

    // Tie-breaker 1: Head-to-head
    final h2h = _getH2HPoints(a, b, games);
    if (h2h != 0) return -h2h;

    // Tie-breaker 2: Total weight (less is better)
    if (a.teamWeight != b.teamWeight) {
      if (a.teamWeight == null) return 1;
      if (b.teamWeight == null) return -1;
      return a.teamWeight!.compareTo(b.teamWeight!);
    }

    return a.teamName.compareTo(b.teamName);
  });

  for (int i = 0; i < result.length; i++) {
    result[i].rank = i + 1;
  }

  return result;
}

int _getH2HPoints(TugOfWarStanding a, TugOfWarStanding b, Map<(int, int), String> games) {
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
