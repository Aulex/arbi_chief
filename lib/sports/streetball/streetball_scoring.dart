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

const String noShowWinScore = '21:0';
const String noShowLossScore = '0:21';

enum StreetballConductionSystem {
  roundRobin,
  mixedGroupsAndFinals,
}

StreetballConductionSystem pickStreetballConductionSystem(int teamCount) {
  return teamCount <= 8
      ? StreetballConductionSystem.roundRobin
      : StreetballConductionSystem.mixedGroupsAndFinals;
}

List<StreetballStanding> calculateStandings({
  required List<({int teamId, String teamName, int? entityId})> teams,
  required Map<(int, int), String> games,
  Set<int> removedTeamIds = const {},
  Set<(int, int)> noShowGamePairs = const {},
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

    final isNoShow = noShowGamePairs.contains((aEntId, bEntId)) || 
                     noShowGamePairs.contains((bEntId, aEntId));

    if (aPts > bPts) {
      standingA.matchPoints += 2;
      standingA.wins++;
      standingB.matchPoints += isNoShow ? 0 : 1;
      standingB.losses++;
    } else if (bPts > aPts) {
      standingB.matchPoints += 2;
      standingB.wins++;
      standingA.matchPoints += isNoShow ? 0 : 1;
      standingA.losses++;
    } else {
      standingA.matchPoints += 1;
      standingB.matchPoints += 1;
    }
  }

  final result = standings.values.toList();

  result.sort((a, b) {
    if (a.isRemoved != b.isRemoved) return a.isRemoved ? 1 : -1;
    final ptsCmp = b.matchPoints.compareTo(a.matchPoints);
    if (ptsCmp != 0) return ptsCmp;
    return 0;
  });

  // Resolve ties by rules:
  // 1) head-to-head result,
  // 2) better scored/conceded difference in games among tied teams,
  // 3) more scored points.
  final resolved = <StreetballStanding>[];
  int i = 0;
  while (i < result.length) {
    final tied = <StreetballStanding>[result[i]];
    int j = i + 1;
    while (j < result.length && result[j].matchPoints == result[i].matchPoints) {
      tied.add(result[j]);
      j++;
    }
    if (tied.length == 1) {
      resolved.add(tied.first);
    } else {
      resolved.addAll(_resolveTieGroup(tied, games, noShowGamePairs));
    }
    i = j;
  }

  for (int k = 0; k < resolved.length; k++) {
    resolved[k].rank = k + 1;
  }

  return resolved;
}

List<StreetballStanding> _resolveTieGroup(
  List<StreetballStanding> group,
  Map<(int, int), String> games,
  Set<(int, int)> noShowGamePairs,
) {
  if (group.length <= 1) return group;

  final inGroupEntityIds = group.map((s) => s.entityId).whereType<int>().toSet();
  final h2hPoints = <int, int>{};
  final h2hDiff = <int, int>{};
  final scored = <int, int>{};

  for (final s in group) {
    if (s.entityId == null) continue;
    h2hPoints[s.entityId!] = 0;
    h2hDiff[s.entityId!] = 0;
    scored[s.entityId!] = 0;
  }

  for (final entry in games.entries) {
    final (aEntId, bEntId) = entry.key;
    if (!inGroupEntityIds.contains(aEntId) || !inGroupEntityIds.contains(bEntId)) {
      continue;
    }
    if (aEntId == bEntId) continue;
    if (noShowGamePairs.contains((aEntId, bEntId)) ||
        noShowGamePairs.contains((bEntId, aEntId))) {
      continue;
    }

    final parts = entry.value.split(':');
    if (parts.length != 2) continue;
    final aPts = int.tryParse(parts[0]) ?? 0;
    final bPts = int.tryParse(parts[1]) ?? 0;

    h2hDiff[aEntId] = (h2hDiff[aEntId] ?? 0) + (aPts - bPts);
    h2hDiff[bEntId] = (h2hDiff[bEntId] ?? 0) + (bPts - aPts);
    scored[aEntId] = (scored[aEntId] ?? 0) + aPts;
    scored[bEntId] = (scored[bEntId] ?? 0) + bPts;

    if (aPts > bPts) {
      h2hPoints[aEntId] = (h2hPoints[aEntId] ?? 0) + 2;
      h2hPoints[bEntId] = (h2hPoints[bEntId] ?? 0) + 1;
    } else {
      h2hPoints[bEntId] = (h2hPoints[bEntId] ?? 0) + 2;
      h2hPoints[aEntId] = (h2hPoints[aEntId] ?? 0) + 1;
    }
  }

  group.sort((a, b) {
    final aEnt = a.entityId;
    final bEnt = b.entityId;
    if (aEnt == null || bEnt == null) return b.pointsScored.compareTo(a.pointsScored);

    final h2hPtsCmp = (h2hPoints[bEnt] ?? 0).compareTo(h2hPoints[aEnt] ?? 0);
    if (h2hPtsCmp != 0) return h2hPtsCmp;

    final h2hDiffCmp = (h2hDiff[bEnt] ?? 0).compareTo(h2hDiff[aEnt] ?? 0);
    if (h2hDiffCmp != 0) return h2hDiffCmp;

    return (scored[bEnt] ?? 0).compareTo(scored[aEnt] ?? 0);
  });

  return group;
}
