/// Tug of War scoring utilities.
///
/// Rules (per regulation):
///   Win        → 2 points
///   Loss       → 1 point
///   No-show    → 0 points (opponent receives a win = 2 points)
///   2nd no-show or unsporting conduct → team is removed; all its results
///   are annulled and it gets no place in the final table.
///
/// Tie-breakers (in order): result in head-to-head meetings among the tied
/// teams, then smaller total team weight.
///
/// Match results are stored in the existing `event_result` text column using
/// these encodings:
///   "1:0" / "0:1"  – normal win/loss
///   "W:N" / "N:W"  – win by opponent no-show (N = no-show side)

/// Number of no-shows that, per the regulation, mandates removal from the
/// tournament (all results annulled, no final place).
const int kNoShowRemovalThreshold = 2;

class TugOfWarStanding {
  final int teamId;
  final String teamName;
  final int? entityId;
  int matchPoints;
  int wins;
  int losses;
  int noShows;
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
    this.noShows = 0,
    this.teamWeight,
    this.isRemoved = false,
    this.rank = 0,
  });

  /// True when the team has reached the no-show count that the regulation says
  /// requires removal from the tournament. Surfaced in the UI as a reminder;
  /// removal itself stays a deliberate arbiter action.
  bool get mustBeRemovedForNoShows =>
      !isRemoved && noShows >= kNoShowRemovalThreshold;
}

({int aPts, int bPts, bool aWin, bool bWin, bool aNoShow, bool bNoShow})? _decode(String detail) {
  final parts = detail.split(':');
  if (parts.length != 2) return null;
  final aTok = parts[0].trim().toUpperCase();
  final bTok = parts[1].trim().toUpperCase();
  final aNoShow = aTok == 'N';
  final bNoShow = bTok == 'N';
  if (aNoShow && bNoShow) return null;
  if (aNoShow) return (aPts: 0, bPts: 2, aWin: false, bWin: true, aNoShow: true, bNoShow: false);
  if (bNoShow) return (aPts: 2, bPts: 0, aWin: true, bWin: false, aNoShow: false, bNoShow: true);
  final a = int.tryParse(aTok) ?? 0;
  final b = int.tryParse(bTok) ?? 0;
  if (a > b) return (aPts: 2, bPts: 1, aWin: true, bWin: false, aNoShow: false, bNoShow: false);
  if (b > a) return (aPts: 1, bPts: 2, aWin: false, bWin: true, aNoShow: false, bNoShow: false);
  return null;
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

    // Removed teams: results are annulled and don't count for anyone.
    if (standingA.isRemoved || standingB.isRemoved) continue;

    final r = _decode(detail);
    if (r == null) continue;
    standingA.matchPoints += r.aPts;
    standingB.matchPoints += r.bPts;
    if (r.aWin) standingA.wins++;
    if (r.bWin) standingB.wins++;
    if (r.aNoShow) {
      standingA.noShows++;
      standingA.losses++;
    } else if (!r.aWin) {
      standingA.losses++;
    }
    if (r.bNoShow) {
      standingB.noShows++;
      standingB.losses++;
    } else if (!r.bWin) {
      standingB.losses++;
    }
  }

  final all = standings.values.toList();
  final active = all.where((s) => !s.isRemoved).toList();
  final removed = all.where((s) => s.isRemoved).toList();

  // Order active teams by points, then resolve equal-point groups using a
  // head-to-head mini-table (transitive, correct for 3+ way ties), then by
  // lower total weight, then name.
  active.sort((a, b) => b.matchPoints.compareTo(a.matchPoints));

  final ordered = <TugOfWarStanding>[];
  int i = 0;
  while (i < active.length) {
    int j = i;
    while (j < active.length && active[j].matchPoints == active[i].matchPoints) {
      j++;
    }
    final group = active.sublist(i, j);
    if (group.length > 1) {
      final h2h = _h2hPointsWithin(group, games);
      group.sort((a, b) {
        final ha = h2h[a.teamId] ?? 0;
        final hb = h2h[b.teamId] ?? 0;
        if (ha != hb) return hb.compareTo(ha);
        if (a.teamWeight != b.teamWeight) {
          if (a.teamWeight == null) return 1;
          if (b.teamWeight == null) return -1;
          return a.teamWeight!.compareTo(b.teamWeight!);
        }
        return a.teamName.compareTo(b.teamName);
      });
    }
    ordered.addAll(group);
    i = j;
  }

  removed.sort((a, b) => a.teamName.compareTo(b.teamName));

  final result = [...ordered, ...removed];
  for (int k = 0; k < result.length; k++) {
    result[k].rank = result[k].isRemoved ? 0 : k + 1;
  }

  return result;
}

/// Head-to-head points each team earned in games played *only against other
/// members of the tied group*. Each pair is counted once.
Map<int, int> _h2hPointsWithin(
  List<TugOfWarStanding> group,
  Map<(int, int), String> games,
) {
  final entityToTeam = <int, int>{
    for (final s in group)
      if (s.entityId != null) s.entityId!: s.teamId,
  };
  final pts = <int, int>{for (final s in group) s.teamId: 0};
  final seen = <(int, int)>{};

  for (final entry in games.entries) {
    final (a, b) = entry.key;
    if (!entityToTeam.containsKey(a) || !entityToTeam.containsKey(b)) continue;
    final key = a < b ? (a, b) : (b, a);
    if (seen.contains(key)) continue;
    seen.add(key);

    final r = _decode(entry.value);
    if (r == null) continue;
    pts[entityToTeam[a]!] = pts[entityToTeam[a]!]! + r.aPts;
    pts[entityToTeam[b]!] = pts[entityToTeam[b]!]! + r.bPts;
  }
  return pts;
}
