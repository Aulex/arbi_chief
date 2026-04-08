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
/// [noShowEventTeamIds] — set of team IDs with no-show events (for 0pts).
List<VolleyballStanding> calculateStandings({
  required List<({int teamId, String teamName, int? entityId})> teams,
  required Map<(int, int), String> games,
  Set<int> removedTeamIds = const {},
  Map<int, int> noShowCounts = const {},
}) {
  final standings = <int, VolleyballStanding>{};

  for (final team in teams) {
    standings[team.teamId] = VolleyballStanding(
      teamId: team.teamId,
      teamName: team.teamName,
      entityId: team.entityId,
      isRemoved: removedTeamIds.contains(team.teamId),
    );
  }

  // Process all games
  for (final entry in games.entries) {
    final (aEntId, bEntId) = entry.key;
    final detail = entry.value;

    // Find teams by entity_id
    final teamA = teams.where((t) => t.entityId == aEntId).firstOrNull;
    final teamB = teams.where((t) => t.entityId == bEntId).firstOrNull;
    if (teamA == null || teamB == null) continue;

    final standingA = standings[teamA.teamId]!;
    final standingB = standings[teamB.teamId]!;

    // Skip removed teams' results
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

  // Sort: removed teams last, then by match points desc, then tiebreakers
  result.sort((a, b) {
    if (a.isRemoved != b.isRemoved) return a.isRemoved ? 1 : -1;
    final ptsCmp = b.matchPoints.compareTo(a.matchPoints);
    if (ptsCmp != 0) return ptsCmp;

    // Tiebreaker 1: Head-to-head
    final h2h = _headToHeadPoints(a, b, games, teams);
    if (h2h != 0) return -h2h; // positive = a wins

    // Tiebreaker 2: Set ratio
    final setRatioCmp = b.setRatio.compareTo(a.setRatio);
    if (setRatioCmp != 0) return setRatioCmp;

    // Tiebreaker 3: Point ratio
    return b.pointRatio.compareTo(a.pointRatio);
  });

  // Assign ranks
  for (int i = 0; i < result.length; i++) {
    result[i].rank = i + 1;
  }

  return result;
}

/// Head-to-head point comparison between two teams.
/// Returns positive if teamA wins h2h, negative if teamB wins, 0 if tied.
int _headToHeadPoints(
  VolleyballStanding a,
  VolleyballStanding b,
  Map<(int, int), String> games,
  List<({int teamId, String teamName, int? entityId})> teams,
) {
  if (a.entityId == null || b.entityId == null) return 0;

  // Check both directions
  final abDetail = games[(a.entityId!, b.entityId!)];
  final baDetail = games[(b.entityId!, a.entityId!)];

  int aPoints = 0;
  int bPoints = 0;

  if (abDetail != null) {
    final sets = countSetsFromDetail(abDetail);
    if (sets.won > sets.lost) {
      aPoints += volleyballWinPoints;
      bPoints += volleyballLossPoints;
    } else {
      bPoints += volleyballWinPoints;
      aPoints += volleyballLossPoints;
    }
  }

  if (baDetail != null) {
    final sets = countSetsFromDetail(baDetail);
    if (sets.won > sets.lost) {
      bPoints += volleyballWinPoints;
      aPoints += volleyballLossPoints;
    } else {
      aPoints += volleyballWinPoints;
      bPoints += volleyballLossPoints;
    }
  }

  return aPoints - bPoints;
}

/// Mirror a detail string: "25:20 25:18" → "20:25 18:25".
String _mirrorDetail(String detail) {
  return detail.split(' ').map((s) {
    final parts = s.split(':');
    if (parts.length != 2) return s;
    return '${parts[1]}:${parts[0]}';
  }).join(' ');
}
