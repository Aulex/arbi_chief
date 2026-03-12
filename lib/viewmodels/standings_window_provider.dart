import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:path_provider/path_provider.dart';

/// Holds the current sub-window controller (if open).
class StandingsWindowNotifier extends Notifier<WindowController?> {
  @override
  WindowController? build() => null;

  void setController(WindowController? controller) {
    state = controller;
  }
}

final standingsWindowControllerProvider =
    NotifierProvider<StandingsWindowNotifier, WindowController?>(
  () => StandingsWindowNotifier(),
);

/// Serializable standings snapshot that gets sent to the sub-window.
/// Updated every time CrossTableTab reloads data.
class StandingsSnapshot {
  final String tournamentName;
  final int? tType;
  final int boardCount;
  final String boardLabel;
  final String boardLabelPlural;
  final String boardAbbrev;

  /// boardNum → list of player standings rows (sorted by place)
  final Map<int, List<StandingsPlayerRow>> boardStandings;

  /// Team standings (sorted by place)
  final List<StandingsTeamRow> teamStandings;

  /// Short tab labels for boards
  final Map<int, String> boardTabLabels;

  /// Cross-table data per board: boardNum → list of players (ordered) with their results
  /// Each player has results map: opponentIndex → result value (1.0, 0.5, 0.0)
  final Map<int, List<CrossTablePlayerRow>> crossTableData;

  /// Team cross-table data
  final List<CrossTableTeamRow> teamCrossTableData;

  StandingsSnapshot({
    required this.tournamentName,
    required this.tType,
    required this.boardCount,
    required this.boardLabel,
    required this.boardLabelPlural,
    required this.boardAbbrev,
    required this.boardStandings,
    required this.teamStandings,
    required this.boardTabLabels,
    this.crossTableData = const {},
    this.teamCrossTableData = const [],
  });

  Map<String, dynamic> toJson() => {
        'tournamentName': tournamentName,
        'tType': tType,
        'boardCount': boardCount,
        'boardLabel': boardLabel,
        'boardLabelPlural': boardLabelPlural,
        'boardAbbrev': boardAbbrev,
        'boardTabLabels': boardTabLabels.map((k, v) => MapEntry('$k', v)),
        'boardStandings': boardStandings.map(
          (k, v) => MapEntry('$k', v.map((r) => r.toJson()).toList()),
        ),
        'teamStandings': teamStandings.map((r) => r.toJson()).toList(),
        'crossTableData': crossTableData.map(
          (k, v) => MapEntry('$k', v.map((r) => r.toJson()).toList()),
        ),
        'teamCrossTableData': teamCrossTableData.map((r) => r.toJson()).toList(),
      };

  factory StandingsSnapshot.fromJson(Map<String, dynamic> json) {
    return StandingsSnapshot(
      tournamentName: json['tournamentName'] ?? '',
      tType: json['tType'],
      boardCount: json['boardCount'] ?? 0,
      boardLabel: json['boardLabel'] ?? '',
      boardLabelPlural: json['boardLabelPlural'] ?? '',
      boardAbbrev: json['boardAbbrev'] ?? '',
      boardTabLabels: (json['boardTabLabels'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(int.parse(k), v as String)),
      boardStandings:
          (json['boardStandings'] as Map<String, dynamic>? ?? {}).map(
        (k, v) => MapEntry(
          int.parse(k),
          (v as List).map((r) => StandingsPlayerRow.fromJson(r)).toList(),
        ),
      ),
      teamStandings: (json['teamStandings'] as List? ?? [])
          .map((r) => StandingsTeamRow.fromJson(r))
          .toList(),
      crossTableData:
          (json['crossTableData'] as Map<String, dynamic>? ?? {}).map(
        (k, v) => MapEntry(
          int.parse(k),
          (v as List).map((r) => CrossTablePlayerRow.fromJson(r)).toList(),
        ),
      ),
      teamCrossTableData: (json['teamCrossTableData'] as List? ?? [])
          .map((r) => CrossTableTeamRow.fromJson(r))
          .toList(),
    );
  }
}

class StandingsPlayerRow {
  final int place;
  final String playerName;
  final String teamName;
  final int? teamNumber;
  final double points;
  final double displayPoints;
  final int gamesPlayed;
  final double? bergerCoefficient;
  final int? ballsScored;
  final int? ballsConceded;

  StandingsPlayerRow({
    required this.place,
    required this.playerName,
    required this.teamName,
    this.teamNumber,
    required this.points,
    required this.displayPoints,
    required this.gamesPlayed,
    this.bergerCoefficient,
    this.ballsScored,
    this.ballsConceded,
  });

  Map<String, dynamic> toJson() => {
        'place': place,
        'playerName': playerName,
        'teamName': teamName,
        'teamNumber': teamNumber,
        'points': points,
        'displayPoints': displayPoints,
        'gamesPlayed': gamesPlayed,
        'bergerCoefficient': bergerCoefficient,
        'ballsScored': ballsScored,
        'ballsConceded': ballsConceded,
      };

  factory StandingsPlayerRow.fromJson(Map<String, dynamic> json) {
    return StandingsPlayerRow(
      place: json['place'] ?? 0,
      playerName: json['playerName'] ?? '',
      teamName: json['teamName'] ?? '',
      teamNumber: json['teamNumber'],
      points: (json['points'] ?? 0).toDouble(),
      displayPoints: (json['displayPoints'] ?? 0).toDouble(),
      gamesPlayed: json['gamesPlayed'] ?? 0,
      bergerCoefficient: json['bergerCoefficient']?.toDouble(),
      ballsScored: json['ballsScored'],
      ballsConceded: json['ballsConceded'],
    );
  }
}

class StandingsTeamRow {
  final int place;
  final String teamName;
  final int? teamNumber;
  final double points;
  final String tiebreaker; // e.g. "Д1: 3.5" or "Сети: +5"

  StandingsTeamRow({
    required this.place,
    required this.teamName,
    this.teamNumber,
    required this.points,
    required this.tiebreaker,
  });

  Map<String, dynamic> toJson() => {
        'place': place,
        'teamName': teamName,
        'teamNumber': teamNumber,
        'points': points,
        'tiebreaker': tiebreaker,
      };

  factory StandingsTeamRow.fromJson(Map<String, dynamic> json) {
    return StandingsTeamRow(
      place: json['place'] ?? 0,
      teamName: json['teamName'] ?? '',
      teamNumber: json['teamNumber'],
      points: (json['points'] ?? 0).toDouble(),
      tiebreaker: json['tiebreaker'] ?? '',
    );
  }
}

/// A player row in the cross table (ordered by team number).
class CrossTablePlayerRow {
  final String playerName;
  final String teamName;
  final int? teamNumber;
  /// Results vs each player by index in the same list (null = not played, -1 = self)
  final Map<int, double?> results;
  /// Detail strings (table tennis set scores) vs each player by index
  final Map<int, String> details;
  final double points;
  final int gamesPlayed;

  CrossTablePlayerRow({
    required this.playerName,
    required this.teamName,
    this.teamNumber,
    required this.results,
    this.details = const {},
    required this.points,
    required this.gamesPlayed,
  });

  Map<String, dynamic> toJson() => {
    'playerName': playerName,
    'teamName': teamName,
    'teamNumber': teamNumber,
    'results': results.map((k, v) => MapEntry('$k', v)),
    'details': details.map((k, v) => MapEntry('$k', v)),
    'points': points,
    'gamesPlayed': gamesPlayed,
  };

  factory CrossTablePlayerRow.fromJson(Map<String, dynamic> json) {
    return CrossTablePlayerRow(
      playerName: json['playerName'] ?? '',
      teamName: json['teamName'] ?? '',
      teamNumber: json['teamNumber'],
      results: (json['results'] as Map<String, dynamic>? ?? {}).map(
        (k, v) => MapEntry(int.parse(k), v?.toDouble()),
      ),
      details: (json['details'] as Map<String, dynamic>? ?? {}).map(
        (k, v) => MapEntry(int.parse(k), v as String),
      ),
      points: (json['points'] ?? 0).toDouble(),
      gamesPlayed: json['gamesPlayed'] ?? 0,
    );
  }
}

/// A team row in the cross table.
class CrossTableTeamRow {
  final String teamName;
  final int? teamNumber;
  /// Match points vs each team by index in the same list
  final Map<int, double> matchPoints;
  /// Board score detail vs each team: "2.5 : 0.5" style
  final Map<int, String> scoreDetails;
  final double totalPoints;

  CrossTableTeamRow({
    required this.teamName,
    this.teamNumber,
    required this.matchPoints,
    this.scoreDetails = const {},
    required this.totalPoints,
  });

  Map<String, dynamic> toJson() => {
    'teamName': teamName,
    'teamNumber': teamNumber,
    'matchPoints': matchPoints.map((k, v) => MapEntry('$k', v)),
    'scoreDetails': scoreDetails.map((k, v) => MapEntry('$k', v)),
    'totalPoints': totalPoints,
  };

  factory CrossTableTeamRow.fromJson(Map<String, dynamic> json) {
    return CrossTableTeamRow(
      teamName: json['teamName'] ?? '',
      teamNumber: json['teamNumber'],
      matchPoints: (json['matchPoints'] as Map<String, dynamic>? ?? {}).map(
        (k, v) => MapEntry(int.parse(k), (v ?? 0).toDouble()),
      ),
      scoreDetails: (json['scoreDetails'] as Map<String, dynamic>? ?? {}).map(
        (k, v) => MapEntry(int.parse(k), v as String),
      ),
      totalPoints: (json['totalPoints'] ?? 0).toDouble(),
    );
  }
}

/// Provider holding the latest standings data. CrossTableTab updates this.
class StandingsSnapshotNotifier extends Notifier<StandingsSnapshot?> {
  @override
  StandingsSnapshot? build() => null;

  void update(StandingsSnapshot snapshot) {
    state = snapshot;
  }
}

final standingsSnapshotProvider =
    NotifierProvider<StandingsSnapshotNotifier, StandingsSnapshot?>(
  () => StandingsSnapshotNotifier(),
);

/// Channel name used for main↔sub-window communication.
const standingsChannelName = 'standings_channel';

/// File name for sharing standings data between windows.
const _standingsFileName = 'standings_snapshot.json';

/// Get the path to the shared standings file.
Future<String> _getStandingsFilePath() async {
  final dir = await getApplicationDocumentsDirectory();
  return '${dir.path}/$_standingsFileName';
}

/// Send standings data to the sub-window (if open) via WindowMethodChannel,
/// and also write to a shared file for reliable polling.
Future<void> sendStandingsToWindow(
    WindowController? controller, StandingsSnapshot snapshot) async {
  final json = jsonEncode(snapshot.toJson());

  // Always write to file so sub-window can poll
  try {
    final path = await _getStandingsFilePath();
    await File(path).writeAsString(json);
  } catch (_) {}

  if (controller == null) return;
  try {
    const channel = WindowMethodChannel(standingsChannelName);
    await channel.invokeMethod('updateStandings', json);
  } catch (_) {
    // Window may have been closed
  }
}

/// Read the latest standings snapshot from the shared file.
Future<StandingsSnapshot?> readStandingsFromFile() async {
  try {
    final path = await _getStandingsFilePath();
    final file = File(path);
    if (!await file.exists()) return null;
    final json = await file.readAsString();
    final data = jsonDecode(json) as Map<String, dynamic>;
    if (data.isEmpty) return null;
    return StandingsSnapshot.fromJson(data);
  } catch (_) {
    return null;
  }
}
