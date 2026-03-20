/// Chess/checkers scoring utilities.
///
/// Provides Berger coefficient, result formatting, and tiebreaker logic
/// specific to chess and checkers. Used by cross-table UI and PDF reports.

/// Points multiplier for chess/checkers: raw points (1 = win, 0.5 = draw).
const int chessPointMultiplier = 1;

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

/// Format a chess result: 1, 0, or ½.
String formatChessResult(double? result) {
  if (result == null) return '';
  if (result == 1.0) return '1';
  if (result == 0.0) return '0';
  if (result == 0.5) return '½';
  return result.toString();
}
