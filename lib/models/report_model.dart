import 'player_model.dart';

/// Holds all pre-loaded data needed to render a tournament report / PDF.
class ReportData {
  final Map<int, List<BoardPlayerEntry>> boardPlayers;
  final Map<int, Map<int, Map<int, double>>> boardResults;
  final Map<int, Map<int, Map<int, String>>> boardResultDetails;

  const ReportData({
    required this.boardPlayers,
    required this.boardResults,
    required this.boardResultDetails,
  });

  bool get isEmpty => boardPlayers.isEmpty;
  bool get isNotEmpty => boardPlayers.isNotEmpty;
}

/// A single player entry on a board, tied to a team.
class BoardPlayerEntry {
  final int teamId;
  final String teamName;
  final int? teamNumber;
  final Player player;

  const BoardPlayerEntry({
    required this.teamId,
    required this.teamName,
    required this.teamNumber,
    required this.player,
  });
}
