/// Checkers scoring utilities.
///
/// Provides Sonneborn-Berger coefficient, result formatting, and tiebreaker logic.
/// Specific to checkers (identical to chess rules).

/// Points multiplier for checkers: raw points (1 = win, 0.5 = draw).
const int checkersPointMultiplier = 1;

/// Calculate Sonneborn-Berger coefficient for a player.
/// Sum of opponent points weighted by result: full for win, half for draw.
double bergerCoefficient(
  Map<int, Map<int, double>>? boardResults,
  int boardNum,
  int playerId,
  double Function(int boardNum, int playerId) totalPointsFn,
) {
  final results = boardResults?[playerId] ?? {};
  double sb = 0;
  for (final entry in results.entries) {
    final result = entry.value;
    final opponentPoints = totalPointsFn(boardNum, entry.key);
    if (result == 1.0) {
      sb += opponentPoints;
    } else if (result == 0.5) {
      sb += opponentPoints * 0.5;
    }
  }
  return sb;
}

/// Format a checkers result: 1, 0, or ½.
String formatCheckersResult(double? result) {
  if (result == null) return '';
  if (result == 1.0) return '1';
  if (result == 0.0) return '0';
  if (result == 0.5) return '½';
  return result.toString();
}

/// Checkers tiebreaker: compare two players by Berger coefficient.
int checkersTiebreaker({
  required Map<int, Map<int, double>>? boardResults,
  required int boardNum,
  required int aId,
  required int bId,
  required double Function(int boardNum, int playerId) totalPointsFn,
}) {
  final ba = bergerCoefficient(boardResults, boardNum, aId, totalPointsFn);
  final bb = bergerCoefficient(boardResults, boardNum, bId, totalPointsFn);
  return bb.compareTo(ba);
}

/// Checkers team tiebreaker: board 1 points, then board 3 (women's) points.
int checkersTeamTiebreaker({
  required int a,
  required int b,
  required Map<int, double> teamBoard1Pts,
  required Map<int, double> teamBoard3Pts,
}) {
  final b1a = teamBoard1Pts[a]!;
  final b1b = teamBoard1Pts[b]!;
  if (b1a != b1b) return b1b.compareTo(b1a);
  return teamBoard3Pts[b]!.compareTo(teamBoard3Pts[a]!);
}
