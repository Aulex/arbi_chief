import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/player_model.dart';
import '../viewmodels/tournament_viewmodel.dart';
import '../viewmodels/team_viewmodel.dart';

class TvDisplayScreen extends ConsumerStatefulWidget {
  final int tournamentId;
  final String tournamentName;
  const TvDisplayScreen({super.key, required this.tournamentId, required this.tournamentName});

  @override
  ConsumerState<TvDisplayScreen> createState() => _TvDisplayScreenState();
}

class _TvDisplayScreenState extends ConsumerState<TvDisplayScreen> {
  Map<int, List<({int teamId, String teamName, int? teamNumber, Player player})>> _boardPlayers = {};
  Map<int, Map<int, Map<int, double>>> _boardResults = {};
  bool _loading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) => _loadData());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    final teamSvc = ref.read(teamServiceProvider);
    final tournamentSvc = ref.read(tournamentServiceProvider);

    final boards = await teamSvc.getBoardAssignmentsForTournament(widget.tournamentId);
    final games = await tournamentSvc.getGamesGroupedByBoard(widget.tournamentId);

    final results = <int, Map<int, Map<int, double>>>{};
    for (final entry in games.entries) {
      final boardNum = entry.key;
      results.putIfAbsent(boardNum, () => {});
      for (final game in entry.value) {
        final wId = game.white.player_id!;
        final bId = game.black.player_id!;
        if (game.whiteResult != null) {
          results[boardNum]!.putIfAbsent(wId, () => {})[bId] = game.whiteResult!;
        }
        if (game.blackResult != null) {
          results[boardNum]!.putIfAbsent(bId, () => {})[wId] = game.blackResult!;
        }
      }
    }

    if (mounted) {
      setState(() {
        _boardPlayers = boards;
        _boardResults = results;
        _loading = false;
      });
    }
  }

  // --- Calculations ---

  double _totalPoints(int boardNum, int playerId) {
    return (_boardResults[boardNum]?[playerId] ?? {}).values.fold(0.0, (sum, r) => sum + r);
  }

  int _gamesPlayed(int boardNum, int playerId) {
    return (_boardResults[boardNum]?[playerId] ?? {}).length;
  }

  double _bergerCoefficient(int boardNum, int playerId) {
    final results = _boardResults[boardNum]?[playerId] ?? {};
    double sb = 0;
    for (final entry in results.entries) {
      final result = entry.value;
      final opponentPoints = _totalPoints(boardNum, entry.key);
      if (result == 1.0) {
        sb += opponentPoints;
      } else if (result == 0.5) {
        sb += opponentPoints * 0.5;
      }
    }
    return sb;
  }

  ({double a, double b}) _teamMatchScore(int teamAId, int teamBId) {
    double aTotal = 0;
    double bTotal = 0;
    for (final boardEntry in _boardPlayers.entries) {
      final boardNum = boardEntry.key;
      final playerA = boardEntry.value.where((p) => p.teamId == teamAId).firstOrNull;
      final playerB = boardEntry.value.where((p) => p.teamId == teamBId).firstOrNull;
      if (playerA == null || playerB == null) continue;
      final aResult = _boardResults[boardNum]?[playerA.player.player_id!]?[playerB.player.player_id!];
      final bResult = _boardResults[boardNum]?[playerB.player.player_id!]?[playerA.player.player_id!];
      if (aResult != null) aTotal += aResult;
      if (bResult != null) bTotal += bResult;
    }
    return (a: aTotal, b: bTotal);
  }

  ({double a, double b}) _teamMatchPoints(int teamAId, int teamBId) {
    final score = _teamMatchScore(teamAId, teamBId);
    if (score.a > score.b) return (a: 2.0, b: 0.0);
    if (score.b > score.a) return (a: 0.0, b: 2.0);
    if (score.a > 0 || score.b > 0) return (a: 1.0, b: 1.0);
    return (a: 0.0, b: 0.0);
  }

  List<({int teamId, String teamName, int? teamNumber, Player player})> _sortedStandings(
    int boardNum,
    List<({int teamId, String teamName, int? teamNumber, Player player})> players,
  ) {
    final sorted = List.of(players);
    sorted.sort((a, b) {
      final aId = a.player.player_id!;
      final bId = b.player.player_id!;
      final pa = _totalPoints(boardNum, aId);
      final pb = _totalPoints(boardNum, bId);
      if (pa != pb) return pb.compareTo(pa);
      final aVsB = _boardResults[boardNum]?[aId]?[bId];
      final bVsA = _boardResults[boardNum]?[bId]?[aId];
      if (aVsB != null && bVsA != null) {
        if (aVsB > bVsA) return -1;
        if (aVsB < bVsA) return 1;
      }
      final ba = _bergerCoefficient(boardNum, aId);
      final bb = _bergerCoefficient(boardNum, bId);
      return bb.compareTo(ba);
    });
    return sorted;
  }

  String _formatResult(double? result) {
    if (result == null) return '';
    if (result == 1.0) return '1';
    if (result == 0.0) return '0';
    if (result == 0.5) return '½';
    return result.toString();
  }

  String _formatPoints(double points) {
    if (points == points.roundToDouble()) return points.toStringAsFixed(1);
    String s = points.toStringAsFixed(2);
    if (s.endsWith('0')) s = s.substring(0, s.length - 1);
    return s;
  }

  // --- Table cell helpers ---

  Widget _tableCell(String text, {TextStyle? style, double? minWidth, bool leftAlign = false}) {
    return Container(
      constraints: minWidth != null ? BoxConstraints(minWidth: minWidth) : null,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      alignment: leftAlign ? Alignment.centerLeft : Alignment.center,
      child: Text(text, textAlign: leftAlign ? TextAlign.left : TextAlign.center, style: style),
    );
  }

  Widget _diagonalCell() {
    return Container(
      constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
      color: Colors.grey.shade800,
    );
  }

  Widget _resultCell(int boardNum, int rowPlayerId, int colPlayerId) {
    final result = _boardResults[boardNum]?[rowPlayerId]?[colPlayerId];
    final text = _formatResult(result);

    Color? bgColor;
    if (text == '1') bgColor = Colors.green.shade50;
    else if (text == '0') bgColor = Colors.red.shade50;
    else if (text == '½') bgColor = Colors.amber.shade50;

    return Container(
      constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
      color: bgColor ?? Colors.transparent,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: text == '1' ? Colors.green.shade700
              : text == '0' ? Colors.red.shade700
              : text == '½' ? Colors.amber.shade800
              : Colors.black87,
        ),
      ),
    );
  }

  Widget _teamResultCell(int teamAId, int teamBId) {
    final matchPts = _teamMatchPoints(teamAId, teamBId);
    final boardScore = _teamMatchScore(teamAId, teamBId);
    final pts = matchPts.a;
    final label = '${_formatPoints(boardScore.a)}\n(${pts.toInt()})';

    Color? bgColor;
    if (pts == 2.0) bgColor = Colors.green.shade50;
    else if (pts == 0.0 && (boardScore.a > 0 || boardScore.b > 0)) bgColor = Colors.red.shade50;
    else if (pts == 1.0) bgColor = Colors.amber.shade50;

    return Container(
      constraints: const BoxConstraints(minWidth: 50, minHeight: 32),
      color: bgColor ?? Colors.transparent,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: pts == 2.0 ? Colors.green.shade700
              : pts == 0.0 ? Colors.red.shade700
              : Colors.amber.shade800,
        ),
      ),
    );
  }

  Widget _verticalHeaderCell({required int number, required String surname, TextStyle? style}) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.bottom,
      child: Container(
        constraints: const BoxConstraints(minWidth: 36),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RotatedBox(
              quarterTurns: 3,
              child: Text(surname, style: style),
            ),
            const SizedBox(height: 2),
            Text('$number', style: style),
          ],
        ),
      ),
    );
  }

  // --- Board cross table ---

  Widget _buildBoardCrossTable(int boardNum) {
    final players = _boardPlayers[boardNum] ?? [];
    if (players.isEmpty) {
      return Center(child: Text('Немає гравців на дошці $boardNum', style: TextStyle(color: Colors.grey.shade600)));
    }

    final n = players.length;
    const headerStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54);
    const cellStyle = TextStyle(fontSize: 12, color: Colors.black87);

    return Table(
      border: TableBorder.all(color: Colors.grey.shade300, width: 1),
      defaultColumnWidth: const IntrinsicColumnWidth(),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: BoxDecoration(color: Colors.grey.shade100),
          children: [
            _tableCell('№', style: headerStyle),
            _tableCell('ПІБ', style: headerStyle, minWidth: 130),
            for (int i = 0; i < n; i++)
              _verticalHeaderCell(
                number: i + 1,
                surname: players[i].player.player_surname,
                style: headerStyle,
              ),
            _tableCell('Бали', style: headerStyle),
            _tableCell('Ігор', style: headerStyle),
            _tableCell('К.Б.', style: headerStyle),
            _tableCell('Місце', style: headerStyle),
          ],
        ),
        for (int i = 0; i < n; i++) ...[
          () {
            final sorted = _sortedStandings(boardNum, players);
            final place = sorted.indexWhere((p) => p.player.player_id == players[i].player.player_id) + 1;
            return TableRow(
              decoration: i.isEven ? null : BoxDecoration(color: Colors.grey.shade50),
              children: [
                _tableCell('${i + 1}', style: cellStyle),
                _tableCell(
                  '${players[i].player.player_surname} ${players[i].player.player_name}',
                  style: cellStyle, minWidth: 130, leftAlign: true,
                ),
                for (int j = 0; j < n; j++)
                  if (i == j) _diagonalCell()
                  else _resultCell(boardNum, players[i].player.player_id!, players[j].player.player_id!),
                _tableCell(
                  _formatPoints(_totalPoints(boardNum, players[i].player.player_id!)),
                  style: cellStyle.copyWith(fontWeight: FontWeight.bold),
                ),
                _tableCell('${_gamesPlayed(boardNum, players[i].player.player_id!)}', style: cellStyle),
                _tableCell(
                  _formatPoints(_bergerCoefficient(boardNum, players[i].player.player_id!)),
                  style: cellStyle,
                ),
                _tableCell('$place', style: cellStyle.copyWith(fontWeight: FontWeight.bold)),
              ],
            );
          }(),
        ],
      ],
    );
  }

  // --- Teams table ---

  Widget _buildTeamsTable() {
    final teamMap = <int, ({String teamName, int? teamNumber})>{};
    for (final boardEntry in _boardPlayers.entries) {
      for (final p in boardEntry.value) {
        teamMap.putIfAbsent(p.teamId, () => (teamName: p.teamName, teamNumber: p.teamNumber));
      }
    }

    if (teamMap.isEmpty) {
      return Center(child: Text('Немає даних', style: TextStyle(color: Colors.grey.shade600)));
    }

    final teamIds = teamMap.keys.toList();
    final teamPoints = <int, double>{};
    final teamBoard1Pts = <int, double>{};
    final teamBoard3Pts = <int, double>{};
    for (final aId in teamIds) {
      double total = 0;
      for (final bId in teamIds) {
        if (aId == bId) continue;
        total += _teamMatchPoints(aId, bId).a;
      }
      teamPoints[aId] = total;
      final b1p = (_boardPlayers[1] ?? []).where((p) => p.teamId == aId).firstOrNull;
      teamBoard1Pts[aId] = b1p != null ? _totalPoints(1, b1p.player.player_id!) : 0;
      final b3p = (_boardPlayers[3] ?? []).where((p) => p.teamId == aId).firstOrNull;
      teamBoard3Pts[aId] = b3p != null ? _totalPoints(3, b3p.player.player_id!) : 0;
    }

    teamIds.sort((a, b) {
      final pa = teamPoints[a]!;
      final pb = teamPoints[b]!;
      if (pa != pb) return pb.compareTo(pa);
      final h2h = _teamMatchPoints(a, b);
      if (h2h.a > h2h.b) return -1;
      if (h2h.b > h2h.a) return 1;
      final b1a = teamBoard1Pts[a]!;
      final b1b = teamBoard1Pts[b]!;
      if (b1a != b1b) return b1b.compareTo(b1a);
      return teamBoard3Pts[b]!.compareTo(teamBoard3Pts[a]!);
    });

    final n = teamIds.length;
    const headerStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54);
    const cellStyle = TextStyle(fontSize: 12, color: Colors.black87);

    return Table(
      border: TableBorder.all(color: Colors.grey.shade300, width: 1),
      defaultColumnWidth: const IntrinsicColumnWidth(),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: BoxDecoration(color: Colors.grey.shade100),
          children: [
            _tableCell('№', style: headerStyle),
            _tableCell('Команда', style: headerStyle, minWidth: 140),
            for (int i = 0; i < n; i++)
              _verticalHeaderCell(
                number: teamMap[teamIds[i]]!.teamNumber ?? (i + 1),
                surname: teamMap[teamIds[i]]!.teamName,
                style: headerStyle,
              ),
            _tableCell('Очки', style: headerStyle),
            _tableCell('Д.1', style: headerStyle),
            _tableCell('Д.3', style: headerStyle),
            _tableCell('Місце', style: headerStyle),
          ],
        ),
        for (int i = 0; i < n; i++)
          TableRow(
            decoration: i.isEven ? null : BoxDecoration(color: Colors.grey.shade50),
            children: [
              _tableCell('${teamMap[teamIds[i]]!.teamNumber ?? (i + 1)}', style: cellStyle),
              _tableCell(teamMap[teamIds[i]]!.teamName, style: cellStyle, minWidth: 140, leftAlign: true),
              for (int j = 0; j < n; j++)
                if (i == j) _diagonalCell()
                else _teamResultCell(teamIds[i], teamIds[j]),
              _tableCell(
                _formatPoints(teamPoints[teamIds[i]]!),
                style: cellStyle.copyWith(fontWeight: FontWeight.bold),
              ),
              _tableCell(_formatPoints(teamBoard1Pts[teamIds[i]]!), style: cellStyle),
              _tableCell(_formatPoints(teamBoard3Pts[teamIds[i]]!), style: cellStyle),
              _tableCell('${i + 1}', style: cellStyle.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
      ],
    );
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.tournamentName),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.fullscreen),
            tooltip: 'На весь екран',
            onPressed: () {
              // Already full-screen as a route; user can drag to second monitor
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int boardNum = 1; boardNum <= 3; boardNum++) ...[
                    Text(
                      'Дошка $boardNum',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: _buildBoardCrossTable(boardNum),
                    ),
                    const SizedBox(height: 24),
                  ],
                  const Text(
                    'Командний залік',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: _buildTeamsTable(),
                  ),
                ],
              ),
            ),
    );
  }
}
