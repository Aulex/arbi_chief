/// Table tennis scoring utilities.
///
/// Provides set/ball counting, result formatting, and tiebreaker logic
/// specific to table tennis. Used by cross-table UI and PDF reports.

/// Points multiplier for table tennis: a win gives 2 match points.
const int tableTennisPointMultiplier = 2;

/// Count set wins and losses from a detail string like "11:7 11:4 8:11".
({int won, int lost}) countSetsFromDetail(String detail) {
  int won = 0;
  int lost = 0;
  for (final s in detail.split(' ')) {
    final parts = s.split(':');
    if (parts.length != 2) continue;
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    if (a == null || b == null) continue;
    if (a > b) won++;
    else if (b > a) lost++;
  }
  return (won: won, lost: lost);
}

/// Count total balls scored and conceded from a detail string.
({int scored, int conceded}) countBallsFromDetail(String detail) {
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

/// Calculate total balls scored/conceded across all opponents for a player.
({int scored, int conceded}) totalBalls(
  Map<int, Map<int, String>>? boardDetails,
  int playerId,
) {
  int scored = 0;
  int conceded = 0;
  final det = boardDetails?[playerId] ?? {};
  for (final detail in det.values) {
    final balls = countBallsFromDetail(detail);
    scored += balls.scored;
    conceded += balls.conceded;
  }
  return (scored: scored, conceded: conceded);
}

/// Format a table tennis cell result from detail string.
/// Shows set count like "2:0" or "2:1".
String formatTableTennisCell(String detail, double? result) {
  int setsWon = 0;
  int setsLost = 0;
  for (final s in detail.split(' ')) {
    final parts = s.split(':');
    if (parts.length != 2) continue;
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    if (a == null || b == null) continue;
    if (a > b) setsWon++;
    else if (b > a) setsLost++;
  }
  return '$setsWon:$setsLost';
}

/// Format result for phantom/absent player in table tennis.
String formatPhantomResult(double? result) {
  if (result == null) return '';
  if (result == 1.0) return '+';
  if (result == 0.0) return '-';
  return '';
}

/// Default phantom game detail strings.
const String phantomWinDetail = '11:0 11:0';
const String phantomLossDetail = '0:11 0:11';

/// Finds a player ID for a given team within a board's player list.
/// [findPlayerIdForTeam] is a callback: (boardNum, teamId) → playerId or null.
typedef PlayerIdLookup = int? Function(int boardNum, int teamId);

/// Calculate direct set difference between two teams across all boards.
int teamDirectSetDiffWith(
  Set<int> boardNums,
  Map<int, Map<int, Map<int, String>>> boardResultDetails,
  int teamAId,
  int teamBId,
  PlayerIdLookup findPlayer,
) {
  int setsWon = 0;
  int setsLost = 0;
  for (final boardNum in boardNums) {
    final aPlayerId = findPlayer(boardNum, teamAId);
    final bPlayerId = findPlayer(boardNum, teamBId);
    if (aPlayerId == null || bPlayerId == null) continue;
    final detail = boardResultDetails[boardNum]?[aPlayerId]?[bPlayerId];
    if (detail == null || detail.isEmpty) continue;
    final sets = countSetsFromDetail(detail);
    setsWon += sets.won;
    setsLost += sets.lost;
  }
  return setsWon - setsLost;
}

/// Calculate direct ball difference between two teams.
int teamDirectBallDiffWith(
  Set<int> boardNums,
  Map<int, Map<int, Map<int, String>>> boardResultDetails,
  int teamAId,
  int teamBId,
  PlayerIdLookup findPlayer,
) {
  int scored = 0;
  int conceded = 0;
  for (final boardNum in boardNums) {
    final aPlayerId = findPlayer(boardNum, teamAId);
    final bPlayerId = findPlayer(boardNum, teamBId);
    if (aPlayerId == null || bPlayerId == null) continue;
    final detail = boardResultDetails[boardNum]?[aPlayerId]?[bPlayerId];
    if (detail == null || detail.isEmpty) continue;
    final balls = countBallsFromDetail(detail);
    scored += balls.scored;
    conceded += balls.conceded;
  }
  return scored - conceded;
}

/// Calculate total set difference across all opponents for a team.
int teamTotalSetDiffWith(
  Set<int> boardNums,
  Map<int, Map<int, Map<int, String>>> boardResultDetails,
  int teamId,
  PlayerIdLookup findPlayer,
) {
  int setsWon = 0;
  int setsLost = 0;
  for (final boardNum in boardNums) {
    final teamPlayerId = findPlayer(boardNum, teamId);
    if (teamPlayerId == null) continue;
    final playerDetails = boardResultDetails[boardNum]?[teamPlayerId] ?? {};
    for (final detail in playerDetails.values) {
      final sets = countSetsFromDetail(detail);
      setsWon += sets.won;
      setsLost += sets.lost;
    }
  }
  return setsWon - setsLost;
}
