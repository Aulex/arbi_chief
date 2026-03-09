import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/player_model.dart';
import '../models/sport_type_config.dart';
import '../viewmodels/tournament_viewmodel.dart';

/// Tab showing game results grouped by board, with inline result editing.
class GameResultsTab extends ConsumerStatefulWidget {
  final int tId;
  final SportTypeConfig config;
  const GameResultsTab({super.key, required this.tId, required this.config});

  @override
  ConsumerState<GameResultsTab> createState() => GameResultsTabState();
}

class GameResultsTabState extends ConsumerState<GameResultsTab> {
  Map<int, List<({int eventId, Player white, Player black, String? dateBegin, double? whiteResult, double? blackResult, String? whiteDetail, String? blackDetail})>> _boardGames = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadGames();
  }

  Future<void> _loadGames() async {
    final svc = ref.read(tournamentServiceProvider);
    final data = await svc.getGamesGroupedByBoard(widget.tId);
    if (mounted) {
      setState(() {
        _boardGames = data;
        _loading = false;
      });
    }
  }

  String _resultLabel(double? w, double? b) {
    if (w == null || b == null) return '—';
    if (w == 1.0 && b == 0.0) return '1 - 0';
    if (w == 0.0 && b == 1.0) return '0 - 1';
    if (w == 0.5 && b == 0.5) return '½ - ½';
    return '—';
  }

  Future<void> _setResult(int eventId, int boardNum, int idx, String? val) async {
    if (val == null) return;
    double? w, b;
    switch (val) {
      case '1 - 0':
        w = 1.0; b = 0.0;
      case '½ - ½':
        w = 0.5; b = 0.5;
      case '0 - 1':
        w = 0.0; b = 1.0;
      default:
        w = null; b = null;
    }
    final games = _boardGames[boardNum]!;
    final old = games[idx];
    setState(() {
      games[idx] = (
        eventId: old.eventId,
        white: old.white,
        black: old.black,
        dateBegin: old.dateBegin,
        whiteResult: w,
        blackResult: b,
        whiteDetail: old.whiteDetail,
        blackDetail: old.blackDetail,
      );
    });
    final svc = ref.read(tournamentServiceProvider);
    await svc.saveGameResult(eventId, w, b);
  }

  Future<void> _deleteGame(int eventId, int boardNum, int idx) async {
    final svc = ref.read(tournamentServiceProvider);
    await svc.deleteGame(eventId);
    setState(() {
      _boardGames[boardNum]!.removeAt(idx);
      if (_boardGames[boardNum]!.isEmpty) {
        _boardGames.remove(boardNum);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_boardGames.isEmpty) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: Colors.grey.shade300, width: 1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.sports_esports_outlined, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(
                  'Ігор ще немає',
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final sortedBoards = _boardGames.keys.toList()..sort();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < sortedBoards.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            _buildBoardCard(sortedBoards[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildBoardCard(int boardNum) {
    final games = _boardGames[boardNum]!;
    final isWomen = widget.config.lastBoardWomenOnly && boardNum == widget.config.boardCount;
    final boardLabel = boardNum == 0
        ? 'Інші ігри'
        : widget.config.tabLabel(boardNum);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: isWomen ? Colors.pink.shade200 : Colors.grey.shade300,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: boardNum == 0
                      ? Colors.grey
                      : (isWomen ? Colors.pink : Colors.indigo),
                  child: Text(
                    boardNum == 0 ? '?' : '$boardNum',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  boardLabel,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Text(
                  '(${games.length})',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
            const Divider(height: 24),
            SizedBox(
              width: double.infinity,
              child: DataTable(
                headingTextStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black54,
                ),
                columnSpacing: 24,
                columns: const [
                  DataColumn(label: Text('#')),
                  DataColumn(label: Text('Білі')),
                  DataColumn(label: Text('Результат')),
                  DataColumn(label: Text('Чорні')),
                  DataColumn(label: Text('')),
                ],
                rows: games.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final g = entry.value;
                  final result = _resultLabel(g.whiteResult, g.blackResult);

                  return DataRow(
                    cells: [
                      DataCell(Text('${idx + 1}')),
                      DataCell(Text(g.white.fullName)),
                      DataCell(
                        DropdownButton<String>(
                          value: result,
                          underline: const SizedBox(),
                          style: const TextStyle(fontSize: 14, color: Colors.black87),
                          items: const [
                            DropdownMenuItem(value: '—', child: Text('—')),
                            DropdownMenuItem(value: '1 - 0', child: Text('1 - 0')),
                            DropdownMenuItem(value: '½ - ½', child: Text('½ - ½')),
                            DropdownMenuItem(value: '0 - 1', child: Text('0 - 1')),
                          ],
                          onChanged: (val) => _setResult(g.eventId, boardNum, idx, val),
                        ),
                      ),
                      DataCell(Text(g.black.fullName)),
                      DataCell(
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                          onPressed: () => _deleteGame(g.eventId, boardNum, idx),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
