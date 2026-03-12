import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';

/// Holds the current sub-window controller (if open).
final standingsWindowControllerProvider =
    StateProvider<WindowController?>((ref) => null);

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

/// Provider holding the latest standings data. CrossTableTab updates this.
final standingsSnapshotProvider =
    StateProvider<StandingsSnapshot?>((ref) => null);

/// Send standings data to the sub-window (if open).
Future<void> sendStandingsToWindow(
    WindowController? controller, StandingsSnapshot snapshot) async {
  if (controller == null) return;
  try {
    final json = jsonEncode(snapshot.toJson());
    await controller.invokeMethod('updateStandings', json);
  } catch (_) {
    // Window may have been closed
  }
}
