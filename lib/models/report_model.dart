import 'player_model.dart';

/// Holds all pre-loaded data needed to render a tournament report / PDF.
class ReportData {
  final Map<int, List<BoardPlayerEntry>> boardPlayers;
  final Map<int, Map<int, Map<int, double>>> boardResults;
  final Map<int, Map<int, Map<int, String>>> boardResultDetails;

  /// True when the tournament has team-based data (volleyball, futsal, etc.)
  /// that is handled by a sport-specific report builder.
  final bool hasTeamData;

  const ReportData({
    required this.boardPlayers,
    required this.boardResults,
    required this.boardResultDetails,
    this.hasTeamData = false,
  });

  bool get isEmpty => boardPlayers.isEmpty && !hasTeamData;
  bool get isNotEmpty => !isEmpty;
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
