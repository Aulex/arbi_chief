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

/// Format a chess result for PDF: uses "1/2" instead of "½" for font compatibility.
String formatChessResultPdf(double? result) {
  if (result == null) return '';
  if (result == 1.0) return '1';
  if (result == 0.0) return '0';
  if (result == 0.5) return '1/2';
  return result.toString();
}

/// Chess/checkers tiebreaker: compare two players by Berger coefficient.
///
/// Returns negative if [aId] ranks higher, positive if [bId] ranks higher, 0 if equal.
/// Used after points and head-to-head are already equal.
int chessTiebreaker({
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

/// Chess/checkers team tiebreaker: board 1 points, then board 3 (women's) points.
///
/// Returns negative if team [a] ranks higher, positive if [b] ranks higher, 0 if equal.
/// Used after total team points and head-to-head match result are equal.
int chessTeamTiebreaker({
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
