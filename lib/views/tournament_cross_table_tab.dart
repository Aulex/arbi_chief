import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/player_model.dart';
import '../models/sport_type_config.dart';
import '../viewmodels/tournament_viewmodel.dart';
import '../viewmodels/team_viewmodel.dart';

/// Tab with sub-tabs: Дошка 1, Дошка 2, Дошка 3, Команди.
/// Cross-tables are interactive — tap cells to enter results.
class CrossTableTab extends ConsumerStatefulWidget {
  final int tId;
  final String tournamentName;
  final SportTypeConfig config;
  final int? tType;
  const CrossTableTab({super.key, required this.tId, required this.tournamentName, required this.config, this.tType});

  @override
  ConsumerState<CrossTableTab> createState() => _CrossTableTabState();
}

class _CrossTableTabState extends ConsumerState<CrossTableTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = true;
  Map<int, List<({int teamId, String teamName, int? teamNumber, Player player})>> _boardPlayers = {};
  Map<int, Map<int, Map<int, double>>> _boardResults = {};
  /// Stores set score detail strings: boardNum → playerId → opponentId → detail (e.g. "11:7 11:4")
  Map<int, Map<int, Map<int, String>>> _boardResultDetails = {};
  Set<int> _absentPlayerIds = {};
  int? _hoveredRow;
  int? _hoveredCol;
  int? _hoveredTeamRow;
  int? _hoveredTeamCol;

  bool get _isTableTennis => widget.tType == 11;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: widget.config.boardCount + 1, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final teamSvc = ref.read(teamServiceProvider);
    final tournamentSvc = ref.read(tournamentServiceProvider);

    final boards = await teamSvc.getBoardAssignmentsForTournament(widget.tId);
    final games = await tournamentSvc.getGamesGroupedByBoard(widget.tId);
    final allTeams = await teamSvc.getTeamListForTournament(widget.tId);

    final results = <int, Map<int, Map<int, double>>>{};
    final details = <int, Map<int, Map<int, String>>>{};
    for (final entry in games.entries) {
      final boardNum = entry.key;
      results.putIfAbsent(boardNum, () => {});
      details.putIfAbsent(boardNum, () => {});
      for (final game in entry.value) {
        final wId = game.white.player_id!;
        final bId = game.black.player_id!;
        if (game.whiteResult != null) {
          results[boardNum]!.putIfAbsent(wId, () => {})[bId] = game.whiteResult!;
        }
        if (game.blackResult != null) {
          results[boardNum]!.putIfAbsent(bId, () => {})[wId] = game.blackResult!;
        }
        if (game.whiteDetail != null && game.whiteDetail!.isNotEmpty) {
          details[boardNum]!.putIfAbsent(wId, () => {})[bId] = game.whiteDetail!;
        }
        if (game.blackDetail != null && game.blackDetail!.isNotEmpty) {
          details[boardNum]!.putIfAbsent(bId, () => {})[wId] = game.blackDetail!;
        }
      }
    }

    // Load no-show players first so phantom logic treats them as absent too
    final noShowIds = await teamSvc.getNoShowPlayerIds(widget.tId);

    // Add phantom "absent" entries for teams missing from each board.
    final absentIds = <int>{...noShowIds};
    for (final boardNum in boards.keys) {
      final presentTeamIds = boards[boardNum]!.map((p) => p.teamId).toSet();
      for (final team in allTeams) {
        if (presentTeamIds.contains(team.teamId)) continue;
        // Sentinel ID: negative, unique per team+board
        final phantomId = -(team.teamId * 100 + boardNum);
        absentIds.add(phantomId);
        boards[boardNum]!.add((
          teamId: team.teamId,
          teamName: team.teamName,
          teamNumber: team.teamNumber,
          player: Player(
            player_id: phantomId,
            player_surname: 'Відсутн.',
            player_name: '',
            player_lastname: '',
            player_gender: 0,
            player_date_birth: '',
          ),
        ));
        // Set results: absent=0 vs every real player, real player=1 vs absent
        // No-show players (in absentIds) also get 0 vs phantom
        results.putIfAbsent(boardNum, () => {});
        results[boardNum]!.putIfAbsent(phantomId, () => {});
        for (final realPlayer in boards[boardNum]!) {
          final realId = realPlayer.player.player_id!;
          if (realId == phantomId || absentIds.contains(realId)) continue;
          results[boardNum]![phantomId]![realId] = 0.0;
          results[boardNum]!.putIfAbsent(realId, () => {})[phantomId] = 1.0;
        }
      }
    }
    // Cross-set absent vs absent (phantom + no-show): both get 0
    for (final boardNum in boards.keys) {
      final absentOnBoard = boards[boardNum]!
          .where((p) => absentIds.contains(p.player.player_id))
          .map((p) => p.player.player_id!)
          .toList();
      for (int i = 0; i < absentOnBoard.length; i++) {
        for (int j = i + 1; j < absentOnBoard.length; j++) {
          results[boardNum]!.putIfAbsent(absentOnBoard[i], () => {})[absentOnBoard[j]] = 0.0;
          results[boardNum]!.putIfAbsent(absentOnBoard[j], () => {})[absentOnBoard[i]] = 0.0;
        }
      }
    }

    if (mounted) {
      setState(() {
        _boardPlayers = boards;
        _boardResults = results;
        _boardResultDetails = details;
        _absentPlayerIds = absentIds;
        _loading = false;
      });
    }
  }

  // --- Result entry ---

  Future<void> _onResultSelected(int rowPlayerId, int colPlayerId, double? result) async {
    final svc = ref.read(tournamentServiceProvider);

    if (result == null) {
      final eventId = await svc.findGameBetweenPlayers(widget.tId, rowPlayerId, colPlayerId);
      if (eventId != null) {
        await svc.saveResultForPlayer(eventId, rowPlayerId, null);
      }
    } else {
      final tsId = await svc.getOrCreateDefaultStage(widget.tId);
      var eventId = await svc.findGameBetweenPlayers(widget.tId, rowPlayerId, colPlayerId);
      eventId ??= await svc.createGame(
        tsId: tsId,
        whitePlayerId: rowPlayerId,
        blackPlayerId: colPlayerId,
      );
      await svc.saveResultForPlayer(eventId, rowPlayerId, result);
    }

    await _loadData();
  }

  void _showResultPicker(
    BuildContext context, {
    required int rowPlayerId,
    required int colPlayerId,
    required String rowPlayerName,
    required String colPlayerName,
    required double? currentResult,
    int? boardNum,
  }) {
    if (_isTableTennis) {
      _showTableTennisResultPicker(
        context,
        rowPlayerId: rowPlayerId,
        colPlayerId: colPlayerId,
        rowPlayerName: rowPlayerName,
        colPlayerName: colPlayerName,
        currentResult: currentResult,
        boardNum: boardNum,
      );
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: EdgeInsets.zero,
        title: Container(
          decoration: BoxDecoration(
            color: Colors.indigo.shade50,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  rowPlayerName,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.indigo.shade900),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('vs', style: TextStyle(fontSize: 13, color: Colors.indigo.shade400)),
              ),
              Expanded(
                child: Text(
                  colPlayerName,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.indigo.shade900),
                ),
              ),
            ],
          ),
        ),
        contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _resultOptionCard(ctx, label: 'Перемога', symbol: '1', color: Colors.green, value: 1.0, current: currentResult),
            const SizedBox(height: 6),
            _resultOptionCard(ctx, label: 'Нічия', symbol: '½', color: Colors.amber, value: 0.5, current: currentResult),
            const SizedBox(height: 6),
            _resultOptionCard(ctx, label: 'Поразка', symbol: '0', color: Colors.red, value: 0.0, current: currentResult),
            if (currentResult != null) ...[
              const SizedBox(height: 10),
              Divider(height: 1, color: Colors.grey.shade200),
              const SizedBox(height: 6),
              _resultOptionCard(ctx, label: 'Очистити', symbol: '×', color: Colors.grey, value: -1.0, current: currentResult),
            ],
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Скасувати')),
        ],
      ),
    ).then((value) {
      if (value == null) return;
      _onResultSelected(rowPlayerId, colPlayerId, value == -1.0 ? null : value);
    });
  }

  void _showTableTennisResultPicker(
    BuildContext context, {
    required int rowPlayerId,
    required int colPlayerId,
    required String rowPlayerName,
    required String colPlayerName,
    required double? currentResult,
    int? boardNum,
  }) {
    // Pre-fill controllers from existing detail
    final existingDetail = boardNum != null
        ? (_boardResultDetails[boardNum]?[rowPlayerId]?[colPlayerId])
        : null;
    final existingSets = existingDetail?.split(' ') ?? [];

    // Up to 3 sets (best of 3 in table tennis)
    final controllers = List.generate(3, (i) {
      final parts = i < existingSets.length ? existingSets[i].split(':') : [];
      return (
        row: TextEditingController(text: parts.length == 2 ? parts[0] : ''),
        col: TextEditingController(text: parts.length == 2 ? parts[1] : ''),
      );
    });

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setST) {
            // Count set wins to determine if 3rd set should be disabled
            int rowWins = 0;
            int colWins = 0;
            for (int s = 0; s < 2; s++) {
              final r = int.tryParse(controllers[s].row.text) ?? 0;
              final c = int.tryParse(controllers[s].col.text) ?? 0;
              if (r > 0 || c > 0) {
                if (r > c) rowWins++;
                else if (c > r) colWins++;
              }
            }
            // Also count 3rd set if not disabled
            if (rowWins < 2 && colWins < 2) {
              final r3 = int.tryParse(controllers[2].row.text) ?? 0;
              final c3 = int.tryParse(controllers[2].col.text) ?? 0;
              if (r3 > 0 || c3 > 0) {
                if (r3 > c3) rowWins++;
                else if (c3 > r3) colWins++;
              }
            }
            final thirdSetDisabled = rowWins >= 2 || colWins >= 2;
            if (thirdSetDisabled) {
              controllers[2].row.text = '';
              controllers[2].col.text = '';
            }

            // Determine live result for preview
            final hasResult = rowWins > 0 || colWins > 0;
            Color scoreColor = Colors.black54;
            if (hasResult) {
              if (rowWins > colWins) scoreColor = Colors.green.shade700;
              else if (colWins > rowWins) scoreColor = Colors.red.shade700;
              else scoreColor = Colors.amber.shade800;
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              titlePadding: EdgeInsets.zero,
              title: Container(
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.sports_tennis, color: Colors.indigo.shade400, size: 20),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                rowPlayerName,
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.indigo.shade900),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            hasResult ? '$rowWins : $colWins' : 'vs',
                            style: TextStyle(
                              fontSize: hasResult ? 22 : 14,
                              fontWeight: FontWeight.bold,
                              color: scoreColor,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.sports_tennis, color: Colors.indigo.shade400, size: 20),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                colPlayerName,
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.indigo.shade900),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              content: SizedBox(
                width: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 4),
                    // Set rows
                    for (int i = 0; i < 3; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Container(
                          decoration: BoxDecoration(
                            color: (i == 2 && thirdSetDisabled) ? Colors.grey.shade50 : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: (i == 2 && thirdSetDisabled) ? Colors.grey.shade200 : Colors.grey.shade300,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(
                            children: [
                              Container(
                                width: 54,
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: (i == 2 && thirdSetDisabled) ? Colors.grey.shade100 : Colors.indigo.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Сет ${i + 1}',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: (i == 2 && thirdSetDisabled) ? Colors.grey.shade400 : Colors.indigo.shade700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: controllers[i].row,
                                  enabled: !(i == 2 && thirdSetDisabled),
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                    filled: true,
                                    fillColor: (i == 2 && thirdSetDisabled) ? Colors.grey.shade100 : Colors.grey.shade100,
                                    hintText: '0',
                                    hintStyle: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.normal),
                                  ),
                                  onChanged: (_) => setST(() {}),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Text(':', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: (i == 2 && thirdSetDisabled) ? Colors.grey.shade300 : Colors.black54)),
                              ),
                              Expanded(
                                child: TextField(
                                  controller: controllers[i].col,
                                  enabled: !(i == 2 && thirdSetDisabled),
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                    filled: true,
                                    fillColor: (i == 2 && thirdSetDisabled) ? Colors.grey.shade100 : Colors.grey.shade100,
                                    hintText: '0',
                                    hintStyle: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.normal),
                                  ),
                                  onChanged: (_) => setST(() {}),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              actions: [
                Row(
                  children: [
                    if (currentResult != null)
                      TextButton.icon(
                        icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _onResultSelected(rowPlayerId, colPlayerId, null);
                        },
                        label: Text('Очистити', style: TextStyle(color: Colors.red.shade400)),
                      ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Скасувати'),
                    ),
                    const SizedBox(width: 4),
                    FilledButton.icon(
                      icon: const Icon(Icons.check, size: 18),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _onTableTennisResultSaved(rowPlayerId, colPlayerId, controllers);
                      },
                      label: const Text('Зберегти'),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      for (final c in controllers) {
        c.row.dispose();
        c.col.dispose();
      }
    });
  }

  Future<void> _onTableTennisResultSaved(
    int rowPlayerId,
    int colPlayerId,
    List<({TextEditingController row, TextEditingController col})> controllers,
  ) async {
    // Parse set scores
    final rowSets = <String>[];
    final colSets = <String>[];
    int rowWins = 0;
    int colWins = 0;

    for (final c in controllers) {
      final rowScore = int.tryParse(c.row.text);
      final colScore = int.tryParse(c.col.text);
      if (rowScore == null || colScore == null) continue;
      if (rowScore == 0 && colScore == 0) continue;
      rowSets.add('$rowScore:$colScore');
      colSets.add('$colScore:$rowScore');
      if (rowScore > colScore) {
        rowWins++;
      } else if (colScore > rowScore) {
        colWins++;
      }
    }

    if (rowSets.isEmpty) return;

    final rowResult = rowWins > colWins ? 1.0 : (rowWins < colWins ? 0.0 : 0.5);
    final rowDetail = rowSets.join(' ');
    final colDetail = colSets.join(' ');

    final svc = ref.read(tournamentServiceProvider);
    final tsId = await svc.getOrCreateDefaultStage(widget.tId);
    var eventId = await svc.findGameBetweenPlayers(widget.tId, rowPlayerId, colPlayerId);
    eventId ??= await svc.createGame(
      tsId: tsId,
      whitePlayerId: rowPlayerId,
      blackPlayerId: colPlayerId,
    );
    await svc.saveTableTennisResult(eventId, rowPlayerId,
      rowResult: rowResult,
      rowDetail: rowDetail,
      colDetail: colDetail,
    );

    await _loadData();
  }

  Widget _resultOptionCard(BuildContext ctx, {
    required String label,
    required String symbol,
    required MaterialColor color,
    required double value,
    required double? current,
  }) {
    final isSelected = current == value;
    return Material(
      color: isSelected ? color.shade50 : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => Navigator.pop(ctx, value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSelected ? color.shade300 : Colors.grey.shade200),
          ),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: color.shade100, borderRadius: BorderRadius.circular(8)),
              alignment: Alignment.center,
              child: Text(symbol, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color.shade800)),
            ),
            const SizedBox(width: 14),
            Text(label, style: TextStyle(fontSize: 14, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
            if (isSelected) ...[const Spacer(), Icon(Icons.check_circle, color: color.shade600, size: 22)],
          ]),
        ),
      ),
    );
  }

  // --- Calculations ---

  /// Raw points multiplier: 2 for racket sports (TT), 1 for board sports.
  int get _pointMultiplier => _isTableTennis ? 2 : 1;

  double _totalPoints(int boardNum, int playerId) {
    return (_boardResults[boardNum]?[playerId] ?? {}).values.fold(0.0, (sum, r) => sum + r);
  }

  /// Display points: for table tennis, a win gives 2 pts (loss 0).
  double _displayPoints(int boardNum, int playerId) {
    return _totalPoints(boardNum, playerId) * _pointMultiplier;
  }

  int _gamesPlayed(int boardNum, int playerId) {
    return (_boardResults[boardNum]?[playerId] ?? {}).length;
  }

  /// Коефіцієнт Бергера = сума очок переможених суперників
  /// + половина очок суперників, з якими нічия.
  double _bergerCoefficient(int boardNum, int playerId) {
    final results = _boardResults[boardNum]?[playerId] ?? {};
    double sb = 0;
    for (final entry in results.entries) {
      final result = entry.value;
      final opponentPoints = _totalPoints(boardNum, entry.key);
      if (result == 1.0) {
        sb += opponentPoints;          // перемога: повна сума очок суперника
      } else if (result == 0.5) {
        sb += opponentPoints * 0.5;    // нічия: половина очок суперника
      }
      // поразка: 0
    }
    return sb;
  }

  /// Total balls scored and conceded for table tennis.
  ({int scored, int conceded}) _totalBalls(int boardNum, int playerId) {
    int scored = 0;
    int conceded = 0;
    final details = _boardResultDetails[boardNum]?[playerId] ?? {};
    for (final detail in details.values) {
      for (final s in detail.split(' ')) {
        final parts = s.split(':');
        if (parts.length != 2) continue;
        scored += int.tryParse(parts[0]) ?? 0;
        conceded += int.tryParse(parts[1]) ?? 0;
      }
    }
    return (scored: scored, conceded: conceded);
  }

  List<({int teamId, String teamName, int? teamNumber, Player player})> _sortedStandings(
    int boardNum,
    List<({int teamId, String teamName, int? teamNumber, Player player})> players,
  ) {
    final sorted = List.of(players);
    sorted.sort((a, b) {
      final aId = a.player.player_id!;
      final bId = b.player.player_id!;
      // 1. Total points
      final pa = _totalPoints(boardNum, aId);
      final pb = _totalPoints(boardNum, bId);
      if (pa != pb) return pb.compareTo(pa);
      // 2. Head-to-head result
      final aVsB = _boardResults[boardNum]?[aId]?[bId];
      final bVsA = _boardResults[boardNum]?[bId]?[aId];
      if (aVsB != null && bVsA != null) {
        if (aVsB > bVsA) return -1; // a won head-to-head → a ranks higher
        if (aVsB < bVsA) return 1;
      }
      // 3. Berger coefficient (skip for table tennis, use balls diff)
      if (_isTableTennis) {
        final aBalls = _totalBalls(boardNum, aId);
        final bBalls = _totalBalls(boardNum, bId);
        final aDiff = aBalls.scored - aBalls.conceded;
        final bDiff = bBalls.scored - bBalls.conceded;
        return bDiff.compareTo(aDiff);
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

  /// Format phantom/absent result for table tennis: show "+"/"-" since no sets were played.
  String _formatTTPhantomResult(double? result) {
    if (result == null) return '';
    if (result == 1.0) return '+';
    if (result == 0.0) return '-';
    return result.toString();
  }

  String _formatPoints(double points) {
    if (points == points.roundToDouble()) return points.toStringAsFixed(1);
    String s = points.toStringAsFixed(2);
    if (s.endsWith('0')) s = s.substring(0, s.length - 1);
    return s;
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_boardPlayers.isEmpty) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: Colors.grey.shade300, width: 1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.table_chart_outlined, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text('Немає даних для таблиці', style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              Text('Додайте учасників та розподіліть їх по ${widget.config.boardLabelPlural}.', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ]),
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: Colors.indigo,
                indicatorColor: Colors.indigo,
                tabAlignment: TabAlignment.start,
                labelPadding: const EdgeInsets.symmetric(horizontal: 16),
                tabs: [
                  for (int i = 1; i <= widget.config.boardCount; i++)
                    Tab(text: widget.config.shortTabLabel(i), height: 36),
                  const Tab(text: 'Команди', height: 36),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              for (int i = 1; i <= widget.config.boardCount; i++)
                _buildBoardTab(i),
              _buildTeamsTab(),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _clearBoardResults(int boardNum) async {
    final svc = ref.read(tournamentServiceProvider);
    final teamSvc = ref.read(teamServiceProvider);

    // Reset game results to null (keep the game records)
    final games = await svc.getGamesGroupedByBoard(widget.tId);
    final boardGames = games[boardNum] ?? [];
    final eventIds = boardGames.map((g) => g.eventId).toList();
    await svc.resetGameResults(eventIds);

    // Clear неявка attribute for no-show players on this board
    final players = _boardPlayers[boardNum] ?? [];
    for (final p in players) {
      final pid = p.player.player_id!;
      if (_absentPlayerIds.contains(pid) && pid > 0) {
        await teamSvc.clearNoShowAttr(pid, widget.tId);
      }
    }

    await _loadData();
  }

  Widget _buildBoardTab(int boardNum) {
    final players = _boardPlayers[boardNum] ?? [];
    if (players.isEmpty) {
      return Center(
        child: Text('Немає гравців: ${widget.config.shortTabLabel(boardNum)}', style: TextStyle(color: Colors.grey.shade600)),
      );
    }

    final hasResults = _boardResults[boardNum]?.isNotEmpty == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasResults)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.delete_sweep_outlined, size: 14),
              label: const Text('Очистити', style: TextStyle(fontSize: 11)),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Очистити результати?'),
                    content: Text('Видалити всі результати ігор: ${widget.config.shortTabLabel(boardNum)}?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Скасувати')),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _clearBoardResults(boardNum);
                        },
                        child: const Text('Очистити', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        Expanded(
          child: Scrollbar(
            child: SingleChildScrollView(
              child: Scrollbar(
                notificationPredicate: (n) => n.depth == 1,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _buildCombinedTable(boardNum, players),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --- Teams cross table ---

  /// Calculate team match score: sum individual board results for teamA vs teamB.
  ({double a, double b}) _teamMatchScore(int teamAId, int teamBId) {
    double aTotal = 0;
    double bTotal = 0;
    for (final boardEntry in _boardPlayers.entries) {
      final boardNum = boardEntry.key;
      final playerA = boardEntry.value.where((p) => p.teamId == teamAId).firstOrNull;
      final playerB = boardEntry.value.where((p) => p.teamId == teamBId).firstOrNull;
      if (playerA == null || playerB == null) continue;
      // Skip games involving phantom players (negative IDs)
      if (playerA.player.player_id! < 0 || playerB.player.player_id! < 0) continue;
      final aResult = _boardResults[boardNum]?[playerA.player.player_id!]?[playerB.player.player_id!];
      final bResult = _boardResults[boardNum]?[playerB.player.player_id!]?[playerA.player.player_id!];
      if (aResult != null) aTotal += aResult;
      if (bResult != null) bTotal += bResult;
    }
    return (a: aTotal, b: bTotal);
  }

  /// Convert board-level match score to team match points.
  /// Win=2, Loss=0, Draw=1 (when missing one player per side).
  ({double a, double b}) _teamMatchPoints(int teamAId, int teamBId) {
    final score = _teamMatchScore(teamAId, teamBId);
    if (score.a > score.b) return (a: 2.0, b: 0.0);
    if (score.b > score.a) return (a: 0.0, b: 2.0);
    if (score.a > 0 || score.b > 0) return (a: 1.0, b: 1.0);
    return (a: 0.0, b: 0.0);
  }

  Widget _buildTeamsTab() {
    final teamMap = <int, ({String teamName, int? teamNumber})>{};
    for (final boardEntry in _boardPlayers.entries) {
      for (final p in boardEntry.value) {
        teamMap.putIfAbsent(p.teamId, () => (teamName: p.teamName, teamNumber: p.teamNumber));
      }
    }

    if (teamMap.isEmpty) {
      return Center(
        child: Text('Немає даних для командного заліку', style: TextStyle(color: Colors.grey.shade600)),
      );
    }

    final teamIds = teamMap.keys.toList();
    final teamPoints = <int, double>{};
    final teamBoardDiff = <int, double>{}; // total board win diff across tournament
    final teamBoard3Pts = <int, double>{}; // women's racket (last board)
    for (final aId in teamIds) {
      double total = 0;
      double boardWins = 0;
      double boardLosses = 0;
      for (final bId in teamIds) {
        if (aId == bId) continue;
        total += _teamMatchPoints(aId, bId).a;
        final score = _teamMatchScore(aId, bId);
        boardWins += score.a;
        boardLosses += score.b;
      }
      teamPoints[aId] = total;
      teamBoardDiff[aId] = boardWins - boardLosses;
      final lastBoard = widget.config.boardCount;
      final b3p = (_boardPlayers[lastBoard] ?? []).where((p) => p.teamId == aId).firstOrNull;
      teamBoard3Pts[aId] = b3p != null ? _totalPoints(lastBoard, b3p.player.player_id!) : 0;
    }

    // Sort: points → h2h → board diff between them → board diff in tournament → women's racket
    teamIds.sort((a, b) {
      final pa = teamPoints[a]!;
      final pb = teamPoints[b]!;
      if (pa != pb) return pb.compareTo(pa);
      // 2. Head-to-head
      final h2h = _teamMatchPoints(a, b);
      if (h2h.a > h2h.b) return -1;
      if (h2h.b > h2h.a) return 1;
      // 3. Board win diff between them (in direct match)
      final directScore = _teamMatchScore(a, b);
      final directDiffA = directScore.a - directScore.b;
      final directDiffB = directScore.b - directScore.a;
      if (directDiffA != directDiffB) return directDiffB.compareTo(directDiffA);
      // 4. Board win diff across entire tournament
      final bdA = teamBoardDiff[a]!;
      final bdB = teamBoardDiff[b]!;
      if (bdA != bdB) return bdB.compareTo(bdA);
      // 5. Women's racket (last board) result
      return teamBoard3Pts[b]!.compareTo(teamBoard3Pts[a]!);
    });

    final n = teamIds.length;
    const headerStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54);
    const cellStyle = TextStyle(fontSize: 12, color: Colors.black87);

    return Scrollbar(
      child: SingleChildScrollView(
        child: Scrollbar(
          notificationPredicate: (n) => n.depth == 1,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
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
                    isHighlighted: _hoveredTeamCol == i,
                    style: headerStyle,
                  ),
                _tableCell('Очки', style: headerStyle),
                _tableCell('${widget.config.boardAbbrev}1', style: headerStyle),
                _tableCell('${widget.config.boardAbbrev}${widget.config.boardCount}', style: headerStyle),
                _tableCell('Місце', style: headerStyle),
              ],
            ),
            for (int i = 0; i < n; i++)
              TableRow(
                decoration: i.isEven ? null : BoxDecoration(color: Colors.grey.shade50),
                children: [
                  _tableCell('${teamMap[teamIds[i]]!.teamNumber ?? (i + 1)}', style: cellStyle),
                  _highlightableNameCell(teamMap[teamIds[i]]!.teamName, isHighlighted: _hoveredTeamRow == i, style: cellStyle, minWidth: 140),
                  for (int j = 0; j < n; j++)
                    if (i == j)
                      _diagonalCell()
                    else
                      _teamResultCell(teamIds[i], teamIds[j], teamMap, rowIdx: i, colIdx: j),
                  _tableCell(
                    _formatPoints(teamPoints[teamIds[i]]!),
                    style: cellStyle.copyWith(fontWeight: FontWeight.bold),
                  ),
                  _tableCell(_formatPoints(teamBoardDiff[teamIds[i]]!), style: cellStyle),
                  _tableCell(_formatPoints(teamBoard3Pts[teamIds[i]]!), style: cellStyle),
                  _tableCell('${i + 1}', style: cellStyle.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
          ],
        ),
      ),
      ),
      ),
    );
  }

  Widget _teamResultCell(int teamAId, int teamBId, Map<int, ({String teamName, int? teamNumber})> teamMap, {required int rowIdx, required int colIdx}) {
    final matchPts = _teamMatchPoints(teamAId, teamBId);
    final boardScore = _teamMatchScore(teamAId, teamBId);
    final pts = matchPts.a;
    final label = '${pts.toInt()}';

    final isHighlighted = _hoveredTeamRow == rowIdx || _hoveredTeamCol == colIdx;
    Color? bgColor;
    if (pts == 2.0) bgColor = Colors.green.shade50;
    else if (pts == 0.0 && (boardScore.a > 0 || boardScore.b > 0)) bgColor = Colors.red.shade50;
    else if (pts == 1.0) bgColor = Colors.amber.shade50;
    else if (isHighlighted) bgColor = Colors.indigo.shade50;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() { _hoveredTeamRow = rowIdx; _hoveredTeamCol = colIdx; }),
      onExit: (_) => setState(() { _hoveredTeamRow = null; _hoveredTeamCol = null; }),
      child: GestureDetector(
        onTap: () => _showTeamMatchDetails(context, teamAId, teamBId, teamMap),
        child: Container(
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
        ),
      ),
    );
  }

  void _showTeamMatchDetails(
    BuildContext context,
    int teamAId,
    int teamBId,
    Map<int, ({String teamName, int? teamNumber})> teamMap,
  ) {
    final teamAName = teamMap[teamAId]!.teamName;
    final teamBName = teamMap[teamBId]!.teamName;
    final boardNums = _boardPlayers.keys.toList()..sort();
    final totalScore = _teamMatchScore(teamAId, teamBId);
    final matchPts = _teamMatchPoints(teamAId, teamBId);

    Color totalColor = Colors.black87;
    if (totalScore.a > totalScore.b) totalColor = Colors.green.shade700;
    else if (totalScore.b > totalScore.a) totalColor = Colors.red.shade700;
    else if (totalScore.a > 0 || totalScore.b > 0) totalColor = Colors.amber.shade800;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: EdgeInsets.zero,
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        title: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.indigo.shade400, Colors.indigo.shade600],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      teamAName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 6, offset: const Offset(0, 2)),
                      ],
                    ),
                    child: Text(
                      '${_formatPoints(totalScore.a)} : ${_formatPoints(totalScore.b)}',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: totalColor),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      teamBName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Очки: ${matchPts.a.toInt()} : ${matchPts.b.toInt()}',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
        content: SizedBox(
          width: 460,
          child: Table(
            border: TableBorder(
              horizontalInside: BorderSide(color: Colors.grey.shade200, width: 1),
            ),
            defaultColumnWidth: const IntrinsicColumnWidth(),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                ),
                children: [
                  _tableCell(widget.config.boardLabel, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.indigo.shade400)),
                  _tableCell(teamAName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.indigo.shade700), minWidth: 120, leftAlign: true),
                  _tableCell('Рахунок', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.indigo.shade400)),
                  _tableCell(teamBName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.indigo.shade700), minWidth: 120, leftAlign: true),
                ],
              ),
              for (final boardNum in boardNums)
                _buildBoardMatchRow(boardNum, teamAId, teamBId, dialogContext: ctx, teamMap: teamMap),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        actions: [
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Закрити'),
          ),
        ],
      ),
    );
  }

  TableRow _buildBoardMatchRow(int boardNum, int teamAId, int teamBId, {BuildContext? dialogContext, Map<int, ({String teamName, int? teamNumber})>? teamMap}) {
    final playersOnBoard = _boardPlayers[boardNum] ?? [];
    final playerA = playersOnBoard.where((p) => p.teamId == teamAId).firstOrNull;
    final playerB = playersOnBoard.where((p) => p.teamId == teamBId).firstOrNull;

    final aIsPhantom = playerA != null && _absentPlayerIds.contains(playerA.player.player_id);
    final bIsPhantom = playerB != null && _absentPlayerIds.contains(playerB.player.player_id);
    final hasPhantom = aIsPhantom || bIsPhantom;

    final aName = playerA != null
        ? '${playerA.player.player_surname} ${playerA.player.player_name}'
        : '—';
    final bName = playerB != null
        ? '${playerB.player.player_surname} ${playerB.player.player_name}'
        : '—';

    String scoreText = '';
    Color scoreColor = Colors.black87;
    if (hasPhantom && playerA != null && playerB != null) {
      // Phantom player game: always show 0 : 0
      scoreText = '0 : 0';
      scoreColor = Colors.grey.shade500;
    } else if (playerA != null && playerB != null) {
      final aResult = _boardResults[boardNum]?[playerA.player.player_id!]?[playerB.player.player_id!];
      final bResult = _boardResults[boardNum]?[playerB.player.player_id!]?[playerA.player.player_id!];
      if (aResult != null && bResult != null) {
        scoreText = '${_formatResult(aResult)} : ${_formatResult(bResult)}';
        if (aResult > bResult) scoreColor = Colors.green.shade700;
        else if (aResult < bResult) scoreColor = Colors.red.shade700;
        else scoreColor = Colors.amber.shade800;
      }
    }

    // Don't allow editing phantom player games
    final canEdit = playerA != null && playerB != null && !hasPhantom && dialogContext != null && teamMap != null;

    const cellStyle = TextStyle(fontSize: 12, color: Colors.black87);
    final phantomStyle = TextStyle(fontSize: 12, color: Colors.grey.shade500, fontStyle: FontStyle.italic);

    Widget scoreCell;
    if (canEdit) {
      final displayText = scoreText.isEmpty ? '—' : scoreText;
      final displayColor = scoreText.isEmpty ? Colors.grey.shade400 : scoreColor;
      scoreCell = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            final rowId = playerA.player.player_id!;
            final colId = playerB.player.player_id!;
            final currentResult = _boardResults[boardNum]?[rowId]?[colId];
            // Close the team details dialog first
            Navigator.pop(dialogContext);
            // Show result picker
            _showResultPicker(
              context,
              rowPlayerId: rowId,
              colPlayerId: colId,
              rowPlayerName: aName,
              colPlayerName: bName,
              currentResult: currentResult,
              boardNum: boardNum,
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            alignment: Alignment.center,
            color: Colors.transparent,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(displayText, textAlign: TextAlign.center, style: cellStyle.copyWith(fontWeight: FontWeight.bold, color: displayColor)),
                const SizedBox(width: 4),
                Icon(Icons.edit_outlined, size: 12, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
      );
    } else {
      scoreCell = _tableCell(scoreText, style: cellStyle.copyWith(fontWeight: FontWeight.bold, color: scoreColor));
    }

    return TableRow(
      children: [
        _tableCell('${widget.config.boardAbbrev}$boardNum', style: cellStyle.copyWith(fontWeight: FontWeight.bold)),
        _tableCell(aName, style: aIsPhantom ? phantomStyle : cellStyle, minWidth: 120, leftAlign: true),
        scoreCell,
        _tableCell(bName, style: bIsPhantom ? phantomStyle : cellStyle, minWidth: 120, leftAlign: true),
      ],
    );
  }

  // --- Cross-table ---

  Widget _buildCombinedTable(
    int boardNum,
    List<({int teamId, String teamName, int? teamNumber, Player player})> rawPlayers,
  ) {
    final players = List.of(rawPlayers)
      ..sort((a, b) {
        final aNum = a.teamNumber ?? 9999;
        final bNum = b.teamNumber ?? 9999;
        if (aNum != bNum) return aNum.compareTo(bNum);
        return a.teamName.compareTo(b.teamName);
      });
    final n = players.length;
    final sorted = _sortedStandings(boardNum, players);
    const headerStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54);
    const cellStyle = TextStyle(fontSize: 12, color: Colors.black87);

    final isTT = _isTableTennis;

    return Table(
      border: TableBorder.all(color: Colors.grey.shade300, width: 1),
      defaultColumnWidth: const IntrinsicColumnWidth(),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        // Header row
        TableRow(
          decoration: BoxDecoration(color: Colors.grey.shade100),
          children: [
            // Cross table headers
            _tableCell('№к', style: headerStyle),
            _tableCell('Команда', style: headerStyle, minWidth: 70),
            _tableCell('ПІБ', style: headerStyle, minWidth: 130),
            for (int i = 0; i < n; i++)
              _verticalHeaderCell(
                number: i + 1,
                surname: players[i].player.player_surname,
                isHighlighted: _hoveredCol == i,
                style: headerStyle,
              ),
            _tableCell('Бали', style: headerStyle),
            _tableCell('Ігор', style: headerStyle),
            if (!isTT) _tableCell('К.Б.', style: headerStyle),
            if (isTT) _tableCell('М.З.', style: headerStyle),
            if (isTT) _tableCell('М.П.', style: headerStyle),
            // Standings headers
            _tableCell('№к', style: headerStyle),
            _tableCell('ПІБ', style: headerStyle, minWidth: 130),
            _tableCell('Команда', style: headerStyle, minWidth: 90),
            _tableCell('Бали', style: headerStyle),
            if (!isTT) _tableCell('К.Б.', style: headerStyle),
            if (isTT) _tableCell('М.З.', style: headerStyle),
            if (isTT) _tableCell('М.П.', style: headerStyle),
            _tableCell('Місце', style: headerStyle),
          ],
        ),
        // Data rows
        for (int i = 0; i < n; i++)
          TableRow(
            decoration: i.isEven ? null : BoxDecoration(color: Colors.grey.shade50),
            children: [
              // Cross table cells
              _tableCell(
                '${players[i].teamNumber ?? ''}',
                style: cellStyle.copyWith(color: Colors.grey.shade600, fontSize: 11),
              ),
              _tableCell(players[i].teamName, style: cellStyle, minWidth: 70, leftAlign: true),
              if (_absentPlayerIds.contains(players[i].player.player_id) && players[i].player.player_id! < 0)
                _tableCell(
                  '${players[i].player.player_surname} ${players[i].player.player_name}',
                  style: cellStyle.copyWith(color: Colors.red.shade400, fontStyle: FontStyle.italic),
                  minWidth: 130, leftAlign: true,
                )
              else if (_absentPlayerIds.contains(players[i].player.player_id))
                _tappableNameCell(
                  '${players[i].player.player_surname} ${players[i].player.player_name}',
                  isHighlighted: _hoveredRow == i,
                  style: cellStyle.copyWith(color: Colors.red.shade700, fontStyle: FontStyle.italic),
                  minWidth: 130,
                  onTap: () => _showPlayerOptions(context, boardNum, players[i], players),
                )
              else
                _tappableNameCell(
                  '${players[i].player.player_surname} ${players[i].player.player_name}',
                  isHighlighted: _hoveredRow == i,
                  style: cellStyle,
                  minWidth: 130,
                  onTap: () => _showPlayerOptions(context, boardNum, players[i], players),
                ),
              for (int j = 0; j < n; j++)
                if (i == j)
                  _diagonalCell()
                else if (_absentPlayerIds.contains(players[i].player.player_id) || _absentPlayerIds.contains(players[j].player.player_id))
                  _staticResultCell(boardNum: boardNum, rowPlayer: players[i], colPlayer: players[j], rowIdx: i, colIdx: j)
                else
                  _tappableResultCell(boardNum: boardNum, rowPlayer: players[i], colPlayer: players[j], rowIdx: i, colIdx: j),
              _tableCell(
                _formatPoints(_displayPoints(boardNum, players[i].player.player_id!)),
                style: cellStyle.copyWith(fontWeight: FontWeight.bold),
              ),
              _tableCell('${_gamesPlayed(boardNum, players[i].player.player_id!)}', style: cellStyle),
              if (!isTT)
                _tableCell(
                  _formatPoints(_bergerCoefficient(boardNum, players[i].player.player_id!)),
                  style: cellStyle,
                ),
              if (isTT)
                _tableCell('${_totalBalls(boardNum, players[i].player.player_id!).scored}', style: cellStyle),
              if (isTT)
                _tableCell('${_totalBalls(boardNum, players[i].player.player_id!).conceded}', style: cellStyle),
              // Standings cells (sorted order)
              _tableCell(
                '${sorted[i].teamNumber ?? ''}',
                style: cellStyle.copyWith(color: Colors.grey.shade600, fontSize: 11),
              ),
              _tableCell(
                '${sorted[i].player.player_surname} ${sorted[i].player.player_name}',
                style: cellStyle, minWidth: 130, leftAlign: true,
              ),
              _tableCell(sorted[i].teamName, style: cellStyle, minWidth: 90, leftAlign: true),
              _tableCell(
                _formatPoints(_displayPoints(boardNum, sorted[i].player.player_id!)),
                style: cellStyle.copyWith(fontWeight: FontWeight.bold),
              ),
              if (!isTT)
                _tableCell(
                  _formatPoints(_bergerCoefficient(boardNum, sorted[i].player.player_id!)),
                  style: cellStyle,
                ),
              if (isTT)
                _tableCell('${_totalBalls(boardNum, sorted[i].player.player_id!).scored}', style: cellStyle),
              if (isTT)
                _tableCell('${_totalBalls(boardNum, sorted[i].player.player_id!).conceded}', style: cellStyle),
              _tableCell('${i + 1}', style: cellStyle.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
      ],
    );
  }

  // --- Cell widgets ---

  Widget _verticalHeaderCell({required int number, required String surname, required bool isHighlighted, TextStyle? style}) {
    final effectiveStyle = isHighlighted
        ? (style ?? const TextStyle()).copyWith(color: Colors.indigo.shade800)
        : style;
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.bottom,
      child: Container(
        constraints: const BoxConstraints(minWidth: 36),
        color: isHighlighted ? Colors.indigo.shade100 : null,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RotatedBox(
              quarterTurns: 3,
              child: Text(surname, style: effectiveStyle),
            ),
            const SizedBox(height: 2),
            Text('$number', style: effectiveStyle),
          ],
        ),
      ),
    );
  }

  Widget _highlightableNameCell(String text, {required bool isHighlighted, TextStyle? style, double? minWidth}) {
    return Container(
      constraints: minWidth != null ? BoxConstraints(minWidth: minWidth) : null,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      color: isHighlighted ? Colors.indigo.shade100 : null,
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        textAlign: TextAlign.left,
        style: isHighlighted
            ? (style ?? const TextStyle()).copyWith(color: Colors.indigo.shade800)
            : style,
      ),
    );
  }

  Widget _tappableNameCell(String text, {required bool isHighlighted, TextStyle? style, double? minWidth, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          constraints: minWidth != null ? BoxConstraints(minWidth: minWidth) : null,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          color: isHighlighted ? Colors.indigo.shade100 : null,
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            textAlign: TextAlign.left,
            style: isHighlighted
                ? (style ?? const TextStyle()).copyWith(color: Colors.indigo.shade800)
                : style,
          ),
        ),
      ),
    );
  }

  void _showPlayerOptions(
    BuildContext context,
    int boardNum,
    ({int teamId, String teamName, int? teamNumber, Player player}) player,
    List<({int teamId, String teamName, int? teamNumber, Player player})> allPlayers,
  ) {
    final name = '${player.player.player_surname} ${player.player.player_name}';
    final isNoShow = _absentPlayerIds.contains(player.player.player_id);
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(name, style: const TextStyle(fontSize: 16)),
        children: [
          if (!isNoShow)
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(ctx);
                _markPlayerNoShow(boardNum, player, allPlayers);
              },
              child: Row(children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(6)),
                  alignment: Alignment.center,
                  child: Icon(Icons.person_off, size: 18, color: Colors.red.shade800),
                ),
                const SizedBox(width: 12),
                const Text('Неявка'),
              ]),
            ),
          if (isNoShow)
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(ctx);
                _clearPlayerNoShow(player);
              },
              child: Row(children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(color: Colors.blue.shade100, borderRadius: BorderRadius.circular(6)),
                  alignment: Alignment.center,
                  child: Icon(Icons.person_add, size: 18, color: Colors.blue.shade800),
                ),
                const SizedBox(width: 12),
                const Text('Очистити'),
              ]),
            ),
        ],
      ),
    );
  }

  Future<void> _markPlayerNoShow(
    int boardNum,
    ({int teamId, String teamName, int? teamNumber, Player player}) player,
    List<({int teamId, String teamName, int? teamNumber, Player player})> allPlayers,
  ) async {
    final svc = ref.read(tournamentServiceProvider);
    final teamSvc = ref.read(teamServiceProvider);
    final playerId = player.player.player_id!;
    final tsId = await svc.getOrCreateDefaultStage(widget.tId);
    final opponentIds = allPlayers
        .where((p) => p.player.player_id != playerId && p.player.player_id! > 0)
        .map((p) => p.player.player_id!)
        .toList();
    await svc.markPlayerNoShow(widget.tId, tsId, playerId, opponentIds, alsoAbsentIds: _absentPlayerIds);
    await teamSvc.markPlayerNoShowAttr(playerId, widget.tId);
    await _loadData();
  }

  Future<void> _clearPlayerNoShow(
    ({int teamId, String teamName, int? teamNumber, Player player}) player,
  ) async {
    final svc = ref.read(tournamentServiceProvider);
    final teamSvc = ref.read(teamServiceProvider);
    final playerId = player.player.player_id!;
    await svc.clearPlayerNoShow(widget.tId, playerId);
    await teamSvc.clearNoShowAttr(playerId, widget.tId);
    await _loadData();
  }

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

  Widget _staticResultCell({
    required int boardNum,
    required ({int teamId, String teamName, int? teamNumber, Player player}) rowPlayer,
    required ({int teamId, String teamName, int? teamNumber, Player player}) colPlayer,
    required int rowIdx,
    required int colIdx,
  }) {
    final rowId = rowPlayer.player.player_id!;
    final colId = colPlayer.player.player_id!;
    final result = _boardResults[boardNum]?[rowId]?[colId];
    final detail = _boardResultDetails[boardNum]?[rowId]?[colId];
    final text = _isTableTennis && detail != null && detail.isNotEmpty
        ? _formatTableTennisCell(detail, result)
        : _isTableTennis ? _formatTTPhantomResult(result) : _formatResult(result);

    Color? bgColor;
    if (result == 1.0) {
      bgColor = Colors.green.shade50;
    } else if (result == 0.0 && result != null) {
      bgColor = Colors.red.shade50;
    } else if (result == 0.5) {
      bgColor = Colors.amber.shade50;
    }

    return Container(
      constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
      color: bgColor ?? Colors.transparent,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: text.isEmpty
          ? const SizedBox.shrink()
          : Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: result == 1.0 ? Colors.green.shade700
                    : result == 0.0 && result != null ? Colors.red.shade700
                    : result == 0.5 ? Colors.amber.shade800
                    : Colors.black87,
              ),
            ),
    );
  }

  Widget _tappableResultCell({
    required int boardNum,
    required ({int teamId, String teamName, int? teamNumber, Player player}) rowPlayer,
    required ({int teamId, String teamName, int? teamNumber, Player player}) colPlayer,
    required int rowIdx,
    required int colIdx,
  }) {
    final rowId = rowPlayer.player.player_id!;
    final colId = colPlayer.player.player_id!;
    final result = _boardResults[boardNum]?[rowId]?[colId];
    final detail = _boardResultDetails[boardNum]?[rowId]?[colId];
    final text = _isTableTennis && detail != null && detail.isNotEmpty
        ? _formatTableTennisCell(detail, result)
        : _formatResult(result);

    final isHighlighted = _hoveredRow == rowIdx || _hoveredCol == colIdx;
    Color? bgColor;
    if (result == 1.0) {
      bgColor = Colors.green.shade50;
    } else if (result == 0.0 && result != null) {
      bgColor = Colors.red.shade50;
    } else if (result == 0.5) {
      bgColor = Colors.amber.shade50;
    } else if (isHighlighted) {
      bgColor = Colors.indigo.shade50;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() { _hoveredRow = rowIdx; _hoveredCol = colIdx; }),
      onExit: (_) => setState(() { _hoveredRow = null; _hoveredCol = null; }),
      child: GestureDetector(
        onTap: () => _showResultPicker(
          context,
          rowPlayerId: rowId,
          colPlayerId: colId,
          rowPlayerName: '${rowPlayer.player.player_surname} ${rowPlayer.player.player_name}',
          colPlayerName: '${colPlayer.player.player_surname} ${colPlayer.player.player_name}',
          currentResult: result,
          boardNum: boardNum,
        ),
        child: Container(
          constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
          color: bgColor ?? Colors.transparent,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          child: text.isEmpty
              ? Icon(Icons.edit_outlined, size: 12, color: Colors.grey.shade400)
              : Text(
                  text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: result == 1.0 ? Colors.green.shade700
                        : result == 0.0 && result != null ? Colors.red.shade700
                        : result == 0.5 ? Colors.amber.shade800
                        : Colors.black87,
                  ),
                ),
        ),
      ),
    );
  }

  /// Format table tennis cell display: "3:1" set score + ball details on second line
  String _formatTableTennisCell(String detail, double? result) {
    final sets = detail.split(' ');
    int rowWins = 0;
    int colWins = 0;
    for (final s in sets) {
      final parts = s.split(':');
      if (parts.length != 2) continue;
      final a = int.tryParse(parts[0]) ?? 0;
      final b = int.tryParse(parts[1]) ?? 0;
      if (a > b) rowWins++;
      else if (b > a) colWins++;
    }
    // Show only game result (e.g. 2-0, 2-1)
    return '$rowWins:$colWins';
  }
}
