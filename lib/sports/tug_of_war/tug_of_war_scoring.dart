/// Tug of War scoring utilities.
///
/// Rules (per regulation):
///   Win        → 2 points
///   Loss       → 1 point
///   No-show    → 0 points (opponent receives a win = 2 points)
///   2nd no-show or unsporting conduct → team is removed; all its results
///   are annulled and it gets no place in the final table.
///
/// Tie-breakers: head-to-head, then smaller total team weight.
///
/// Match results are stored in the existing `event_result` text column using
/// these encodings:
///   "1:0" / "0:1"  – normal win/loss
///   "W:N" / "N:W"  – win by opponent no-show (N = no-show side)

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

  final result = standings.values.toList();

  result.sort((a, b) {
    if (a.isRemoved != b.isRemoved) return a.isRemoved ? 1 : -1;
    final ptsCmp = b.matchPoints.compareTo(a.matchPoints);
    if (ptsCmp != 0) return ptsCmp;

    final h2h = _getH2HPoints(a, b, games);
    if (h2h != 0) return -h2h;

    if (a.teamWeight != b.teamWeight) {
      if (a.teamWeight == null) return 1;
      if (b.teamWeight == null) return -1;
      return a.teamWeight!.compareTo(b.teamWeight!);
    }

    return a.teamName.compareTo(b.teamName);
  });

  for (int i = 0; i < result.length; i++) {
    if (result[i].isRemoved) {
      result[i].rank = 0;
    } else {
      result[i].rank = i + 1;
    }
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
    final r = _decode(detail);
    if (r == null) return;
    if (isAB) { aPts += r.aPts; bPts += r.bPts; }
    else { aPts += r.bPts; bPts += r.aPts; }
  }

  add(ab, true);
  add(ba, false);
  return aPts - bPts;
}
