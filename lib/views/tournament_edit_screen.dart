import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'tournament_add_screen.dart';
import '../models/tournament_model.dart';
import '../models/player_model.dart';
import '../viewmodels/nav_provider.dart';
import '../viewmodels/player_viewmodel.dart';
import '../viewmodels/tournament_viewmodel.dart';
import '../viewmodels/team_viewmodel.dart';

class TournamentEditScreen extends ConsumerStatefulWidget {
  final Tournament tournament;
  const TournamentEditScreen({super.key, required this.tournament});

  @override
  ConsumerState<TournamentEditScreen> createState() =>
      _TournamentEditScreenState();
}

class _TournamentEditScreenState extends ConsumerState<TournamentEditScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Header
            Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: Colors.grey.shade300, width: 1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () {
                              ref
                                  .read(tournamentNavProvider.notifier)
                                  .showList();
                            },
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Керування турніром: ${widget.tournament.t_name}',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              SelectableText(
                                'Ідентифікатор турніру: ${widget.tournament.t_id}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ],
                      ),
                      ElevatedButton.icon(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Видалити турнір?'),
                              content: Text(
                                'Ви впевнені, що хочете видалити турнір "${widget.tournament.t_name}"?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('Скасувати'),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                  ),
                                  onPressed: () {
                                    ref
                                        .read(tournamentProvider.notifier)
                                        .removeTournament(widget.tournament.t_id!);
                                    Navigator.pop(ctx);
                                    ref
                                        .read(tournamentNavProvider.notifier)
                                        .showList();
                                  },
                                  child: const Text(
                                    'Видалити',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Видалити турнір'),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.red,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Tab Bar
              const TabBar(
                isScrollable: true,
                labelColor: Colors.indigo,
                indicatorColor: Colors.indigo,
                tabs: [
                  Tab(icon: Icon(Icons.grid_view_outlined), text: 'Огляд'),
                  Tab(icon: Icon(Icons.leaderboard_outlined), text: 'Таблиця'),
                  Tab(icon: Icon(Icons.people_outline), text: 'Учасники'),
                  Tab(
                      icon: Icon(Icons.summarize_outlined), text: 'Звіти'),
                  Tab(
                    icon: Icon(Icons.settings_outlined),
                    text: 'Налаштування',
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Tab Bar View
              Expanded(
                child: TabBarView(
                  children: [
                    _buildOverviewTab(),
                    _buildTableTab(),
                    _buildParticipantsTab(),
                    _ReportsTab(tournament: widget.tournament),
                    TournamentAddScreen(
                      tournament: widget.tournament,
                      isEditMode: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
    );
  }

  Widget _buildOverviewTab() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade300, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Огляд турніру',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text('Тут буде відображатися загальна інформація про турнір.'),
          ],
        ),
      ),
    );
  }

  Widget _buildBoardsTab() {
    final tId = widget.tournament.t_id!;
    final svc = ref.read(tournamentServiceProvider);
    final teamSvc = ref.read(teamServiceProvider);

    return FutureBuilder<String?>(
      future: svc.getAttrDictValue(tId, 2), // attr_id=2: Система жеребкування
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final pairingSystem = snapshot.data;

        if (pairingSystem == 'Колова') {
          return _buildRoundRobinPairing(teamSvc, tId);
        }

        // Placeholder for other systems
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: Colors.grey.shade300, width: 1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Дошки',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  pairingSystem != null
                      ? 'Система жеребкування: $pairingSystem (в розробці)'
                      : 'Система жеребкування не обрана.',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRoundRobinPairing(dynamic teamSvc, int tId) {
    return FutureBuilder<
        Map<int, List<({int teamId, String teamName, Player player})>>>(
      future: teamSvc.getBoardAssignmentsForTournament(tId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final boards = snapshot.data ?? {};

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: Colors.grey.shade300, width: 1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Дошки — Колова система',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Розподіл гравців по дошках з командних складів.',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // 3 boards in a row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int boardNum = 1; boardNum <= 3; boardNum++) ...[
                    if (boardNum > 1) const SizedBox(width: 16),
                    Expanded(
                      child: _buildBoardPairingCard(
                        boardNum,
                        boards[boardNum] ?? [],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBoardPairingCard(
    int boardNum,
    List<({int teamId, String teamName, Player player})> entries,
  ) {
    final isWomenBoard = boardNum == 3;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: isWomenBoard ? Colors.pink.shade200 : Colors.grey.shade300,
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
                  backgroundColor:
                      isWomenBoard ? Colors.pink : Colors.indigo,
                  child: Text(
                    '$boardNum',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  isWomenBoard
                      ? 'Дошка $boardNum (жіноча)'
                      : 'Дошка $boardNum',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),
            if (entries.isEmpty)
              Text(
                'Немає гравців на цій дошці',
                style: TextStyle(color: Colors.grey.shade500),
              )
            else
              ...entries.map((e) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_outline),
                    title: Text(e.player.fullName),
                    subtitle: Text(e.teamName),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _buildGamesTab() {
    return _GameResultsTab(tId: widget.tournament.t_id!);
  }

  Widget _buildTableTab() {
    return _CrossTableTab(tId: widget.tournament.t_id!);
  }

  Widget _buildParticipantsTab() {
    final tId = widget.tournament.t_id!;
    final participantsAsync = ref.watch(participantsProvider(tId));
    final allPlayersAsync = ref.watch(playerProvider);

    return participantsAsync.when(
      data: (participants) {
        final participantIds = participants.map((p) => p.player_id).toSet();

        return allPlayersAsync.when(
          data: (allPlayers) {
            final available = allPlayers
                .where((p) => !participantIds.contains(p.player_id))
                .toList()
              ..sort((a, b) => a.player_surname.compareTo(b.player_surname));

            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _buildPlayerListCard(
                    title: 'Учасники (${participants.length})',
                    subtitle: 'Гравці, зареєстровані в цьому турнірі.',
                    players: participants,
                    emptyText: 'Немає учасників',
                    actionIcon: Icons.remove_circle_outline,
                    actionColor: Colors.redAccent,
                    onAction: (player) async {
                      final svc = ref.read(tournamentServiceProvider);
                      await svc.removeParticipant(tId, player.player_id!);
                      ref.invalidate(participantsProvider(tId));
                    },
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: _buildPlayerListCard(
                    title: 'Доступні гравці (${available.length})',
                    subtitle: 'Додайте гравців із загального списку.',
                    players: available,
                    emptyText: 'Немає доступних гравців',
                    actionIcon: Icons.add_circle_outline,
                    actionColor: Colors.green,
                    onAction: (player) async {
                      final svc = ref.read(tournamentServiceProvider);
                      await svc.addParticipant(tId, player.player_id!);
                      ref.invalidate(participantsProvider(tId));
                    },
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, s) => Center(child: Text('Помилка: $e')),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => Center(child: Text('Помилка: $e')),
    );
  }

  Widget _buildPlayerListCard({
    required String title,
    required String subtitle,
    required List<Player> players,
    required String emptyText,
    required IconData actionIcon,
    required Color actionColor,
    required void Function(Player) onAction,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade300, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const Divider(height: 24),
            Expanded(
              child: players.isEmpty
                  ? Center(child: Text(emptyText))
                  : ListView.separated(
                      itemCount: players.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final player = players[index];
                        return ListTile(
                          title: Text(player.fullName),
                          subtitle: player.birthDateForUI.isNotEmpty
                              ? Text(player.birthDateForUI)
                              : null,
                          trailing: IconButton(
                            icon: Icon(actionIcon, color: actionColor),
                            onPressed: () => onAction(player),
                          ),
                          contentPadding: EdgeInsets.zero,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tab showing game results grouped by board, with inline result editing.
class _GameResultsTab extends ConsumerStatefulWidget {
  final int tId;
  const _GameResultsTab({required this.tId});

  @override
  ConsumerState<_GameResultsTab> createState() => _GameResultsTabState();
}

class _GameResultsTabState extends ConsumerState<_GameResultsTab> {
  Map<int, List<({int eventId, Player white, Player black, String? dateBegin, double? whiteResult, double? blackResult})>> _boardGames = {};
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
    final isWomen = boardNum == 3;
    final boardLabel = boardNum == 0
        ? 'Інші ігри'
        : (isWomen ? 'Дошка $boardNum (жіноча)' : 'Дошка $boardNum');

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

/// Tab with sub-tabs: Дошка 1, Дошка 2, Дошка 3, Команди.
/// Cross-tables are interactive — tap cells to enter results.
class _CrossTableTab extends ConsumerStatefulWidget {
  final int tId;
  const _CrossTableTab({required this.tId});

  @override
  ConsumerState<_CrossTableTab> createState() => _CrossTableTabState();
}

class _CrossTableTabState extends ConsumerState<_CrossTableTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = true;
  Map<int, List<({int teamId, String teamName, Player player})>> _boardPlayers = {};
  Map<int, Map<int, Map<int, double>>> _boardResults = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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
  }) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('$rowPlayerName  vs  $colPlayerName', style: const TextStyle(fontSize: 16)),
        children: [
          _resultOption(ctx, label: 'Перемога', symbol: '1', color: Colors.green, value: 1.0, current: currentResult),
          _resultOption(ctx, label: 'Нічия', symbol: '½', color: Colors.amber, value: 0.5, current: currentResult),
          _resultOption(ctx, label: 'Поразка', symbol: '0', color: Colors.red, value: 0.0, current: currentResult),
          if (currentResult != null) ...[
            const Divider(),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, -1.0),
              child: Row(children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(6)),
                  alignment: Alignment.center,
                  child: Icon(Icons.close, size: 18, color: Colors.grey.shade700),
                ),
                const SizedBox(width: 12),
                const Text('Очистити'),
              ]),
            ),
          ],
        ],
      ),
    ).then((value) {
      if (value == null) return;
      _onResultSelected(rowPlayerId, colPlayerId, value == -1.0 ? null : value);
    });
  }

  Widget _resultOption(BuildContext ctx, {
    required String label,
    required String symbol,
    required MaterialColor color,
    required double value,
    required double? current,
  }) {
    return SimpleDialogOption(
      onPressed: () => Navigator.pop(ctx, value),
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(color: color.shade100, borderRadius: BorderRadius.circular(6)),
          alignment: Alignment.center,
          child: Text(symbol, style: TextStyle(fontWeight: FontWeight.bold, color: color.shade800)),
        ),
        const SizedBox(width: 12),
        Text(label),
        if (current == value) ...[const Spacer(), Icon(Icons.check, color: color.shade700, size: 20)],
      ]),
    );
  }

  // --- Calculations ---

  double _totalPoints(int boardNum, int playerId) {
    return (_boardResults[boardNum]?[playerId] ?? {}).values.fold(0.0, (sum, r) => sum + r);
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

  /// Sort players: by points desc, then head-to-head, then Berger coefficient.
  List<({int teamId, String teamName, Player player})> _sortedStandings(
    int boardNum,
    List<({int teamId, String teamName, Player player})> players,
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
      // 3. Berger coefficient
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
              Text('Додайте учасників та розподіліть їх по дошках.', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ]),
          ),
        ),
      );
    }

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Colors.indigo,
          indicatorColor: Colors.indigo,
          tabs: const [
            Tab(text: 'Дошка 1'),
            Tab(text: 'Дошка 2'),
            Tab(text: 'Дошка 3'),
            Tab(text: 'Команди'),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildBoardTab(1),
              _buildBoardTab(2),
              _buildBoardTab(3),
              _buildTeamsTab(),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _clearBoardResults(int boardNum) async {
    final svc = ref.read(tournamentServiceProvider);
    final games = await svc.getGamesGroupedByBoard(widget.tId);
    final boardGames = games[boardNum] ?? [];
    for (final game in boardGames) {
      await svc.deleteGame(game.eventId);
    }
    await _loadData();
  }

  Widget _buildBoardTab(int boardNum) {
    final players = _boardPlayers[boardNum] ?? [];
    if (players.isEmpty) {
      return Center(
        child: Text('Немає гравців на дошці $boardNum', style: TextStyle(color: Colors.grey.shade600)),
      );
    }

    final hasResults = _boardResults[boardNum]?.isNotEmpty == true;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasResults)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text('Очистити результати'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Очистити результати?'),
                      content: Text('Видалити всі результати ігор на дошці $boardNum?'),
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
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: _buildCrossTable(boardNum, players),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 2,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: _buildStandings(boardNum, players),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Teams leaderboard ---

  Widget _buildTeamsTab() {
    // Collect unique teams and sum their points across all boards
    final teamScores = <int, ({String teamName, double total, Map<int, double> perBoard})>{};

    for (final boardEntry in _boardPlayers.entries) {
      final boardNum = boardEntry.key;
      for (final p in boardEntry.value) {
        final existing = teamScores[p.teamId];
        final pts = _totalPoints(boardNum, p.player.player_id!);
        if (existing != null) {
          final newPerBoard = Map<int, double>.from(existing.perBoard);
          newPerBoard[boardNum] = (newPerBoard[boardNum] ?? 0) + pts;
          teamScores[p.teamId] = (
            teamName: existing.teamName,
            total: existing.total + pts,
            perBoard: newPerBoard,
          );
        } else {
          teamScores[p.teamId] = (
            teamName: p.teamName,
            total: pts,
            perBoard: {boardNum: pts},
          );
        }
      }
    }

    final sortedTeams = teamScores.entries.toList()
      ..sort((a, b) => b.value.total.compareTo(a.value.total));

    if (sortedTeams.isEmpty) {
      return Center(
        child: Text('Немає даних для командного заліку', style: TextStyle(color: Colors.grey.shade600)),
      );
    }

    const headerStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black54);
    const cellStyle = TextStyle(fontSize: 13, color: Colors.black87);

    final boards = _boardPlayers.keys.toList()..sort();

    return SingleChildScrollView(
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
                _tableCell('Місце', style: headerStyle),
                _tableCell('Команда', style: headerStyle, minWidth: 160),
                for (final b in boards)
                  _tableCell('Дошка $b', style: headerStyle),
                _tableCell('Всього', style: headerStyle),
              ],
            ),
            for (int i = 0; i < sortedTeams.length; i++)
              TableRow(
                decoration: i.isEven ? null : BoxDecoration(color: Colors.grey.shade50),
                children: [
                  _tableCell(
                    '${i + 1}',
                    style: cellStyle.copyWith(fontWeight: FontWeight.bold),
                  ),
                  _tableCell(
                    sortedTeams[i].value.teamName,
                    style: cellStyle,
                    minWidth: 160,
                    leftAlign: true,
                  ),
                  for (final b in boards)
                    _tableCell(
                      _formatPoints(sortedTeams[i].value.perBoard[b] ?? 0),
                      style: cellStyle,
                    ),
                  _tableCell(
                    _formatPoints(sortedTeams[i].value.total),
                    style: cellStyle.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // --- Cross-table ---

  Widget _buildCrossTable(
    int boardNum,
    List<({int teamId, String teamName, Player player})> players,
  ) {
    final n = players.length;
    const headerStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black54);
    const cellStyle = TextStyle(fontSize: 13, color: Colors.black87);

    return Table(
      border: TableBorder.all(color: Colors.grey.shade300, width: 1),
      defaultColumnWidth: const IntrinsicColumnWidth(),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: BoxDecoration(color: Colors.grey.shade100),
          children: [
            _tableCell('№', style: headerStyle),
            _tableCell('ПІБ', style: headerStyle, minWidth: 140),
            _tableCell('Команда', style: headerStyle, minWidth: 100),
            for (int i = 0; i < n; i++)
              _tableCell('${i + 1}', style: headerStyle, minWidth: 36),
            _tableCell('Бали', style: headerStyle),
            _tableCell('К-сть\nігор', style: headerStyle),
            _tableCell('К.\nБергера', style: headerStyle),
          ],
        ),
        for (int i = 0; i < n; i++)
          TableRow(
            decoration: i.isEven ? null : BoxDecoration(color: Colors.grey.shade50),
            children: [
              _tableCell('${i + 1}', style: cellStyle),
              _tableCell(
                '${players[i].player.player_surname} ${players[i].player.player_name}',
                style: cellStyle, minWidth: 140, leftAlign: true,
              ),
              _tableCell(players[i].teamName, style: cellStyle, minWidth: 100, leftAlign: true),
              for (int j = 0; j < n; j++)
                if (i == j)
                  _diagonalCell()
                else
                  _tappableResultCell(boardNum: boardNum, rowPlayer: players[i], colPlayer: players[j]),
              _tableCell(
                _formatPoints(_totalPoints(boardNum, players[i].player.player_id!)),
                style: cellStyle.copyWith(fontWeight: FontWeight.bold),
              ),
              _tableCell('${_gamesPlayed(boardNum, players[i].player.player_id!)}', style: cellStyle),
              _tableCell(
                _formatPoints(_bergerCoefficient(boardNum, players[i].player.player_id!)),
                style: cellStyle,
              ),
            ],
          ),
      ],
    );
  }

  // --- Standings ---

  Widget _buildStandings(
    int boardNum,
    List<({int teamId, String teamName, Player player})> players,
  ) {
    final sorted = _sortedStandings(boardNum, players);

    const headerStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black54);
    const cellStyle = TextStyle(fontSize: 13, color: Colors.black87);

    return Table(
      border: TableBorder.all(color: Colors.grey.shade300, width: 1),
      defaultColumnWidth: const IntrinsicColumnWidth(),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: BoxDecoration(color: Colors.grey.shade100),
          children: [
            _tableCell('ПІБ', style: headerStyle, minWidth: 140),
            _tableCell('Команда', style: headerStyle, minWidth: 100),
            _tableCell('Бали', style: headerStyle),
            _tableCell('К.\nБергера', style: headerStyle),
            _tableCell('Місце', style: headerStyle),
          ],
        ),
        for (int i = 0; i < sorted.length; i++)
          TableRow(
            decoration: i.isEven ? null : BoxDecoration(color: Colors.grey.shade50),
            children: [
              _tableCell(
                '${sorted[i].player.player_surname} ${sorted[i].player.player_name}',
                style: cellStyle, minWidth: 140, leftAlign: true,
              ),
              _tableCell(sorted[i].teamName, style: cellStyle, minWidth: 100, leftAlign: true),
              _tableCell(
                _formatPoints(_totalPoints(boardNum, sorted[i].player.player_id!)),
                style: cellStyle.copyWith(fontWeight: FontWeight.bold),
              ),
              _tableCell(
                _formatPoints(_bergerCoefficient(boardNum, sorted[i].player.player_id!)),
                style: cellStyle,
              ),
              _tableCell('${i + 1}', style: cellStyle.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
      ],
    );
  }

  // --- Cell widgets ---

  Widget _tableCell(String text, {TextStyle? style, double? minWidth, bool leftAlign = false}) {
    return Container(
      constraints: minWidth != null ? BoxConstraints(minWidth: minWidth) : null,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      alignment: leftAlign ? Alignment.centerLeft : Alignment.center,
      child: Text(text, textAlign: leftAlign ? TextAlign.left : TextAlign.center, style: style),
    );
  }

  Widget _diagonalCell() {
    return Container(
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      color: Colors.grey.shade800,
    );
  }

  Widget _tappableResultCell({
    required int boardNum,
    required ({int teamId, String teamName, Player player}) rowPlayer,
    required ({int teamId, String teamName, Player player}) colPlayer,
  }) {
    final result = _boardResults[boardNum]?[rowPlayer.player.player_id!]?[colPlayer.player.player_id!];
    final text = _formatResult(result);

    Color? bgColor;
    if (text == '1') bgColor = Colors.green.shade50;
    else if (text == '0') bgColor = Colors.red.shade50;
    else if (text == '½') bgColor = Colors.amber.shade50;

    return GestureDetector(
      onTap: () => _showResultPicker(
        context,
        rowPlayerId: rowPlayer.player.player_id!,
        colPlayerId: colPlayer.player.player_id!,
        rowPlayerName: '${rowPlayer.player.player_surname} ${rowPlayer.player.player_name}',
        colPlayerName: '${colPlayer.player.player_surname} ${colPlayer.player.player_name}',
        currentResult: result,
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          color: bgColor ?? Colors.transparent,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: text.isEmpty
              ? Icon(Icons.edit_outlined, size: 14, color: Colors.grey.shade400)
              : Text(
                  text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: text == '1' ? Colors.green.shade700
                        : text == '0' ? Colors.red.shade700
                        : Colors.amber.shade800,
                  ),
                ),
        ),
      ),
    );
  }
}

/// Reports tab — generates and exports a PDF with board cross-tables and team ratings.
class _ReportsTab extends ConsumerStatefulWidget {
  final Tournament tournament;
  const _ReportsTab({required this.tournament});

  @override
  ConsumerState<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends ConsumerState<_ReportsTab> {
  bool _loading = true;
  Map<int, List<({int teamId, String teamName, Player player})>> _boardPlayers = {};
  Map<int, Map<int, Map<int, double>>> _boardResults = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final teamSvc = ref.read(teamServiceProvider);
    final tournamentSvc = ref.read(tournamentServiceProvider);
    final tId = widget.tournament.t_id!;

    final boards = await teamSvc.getBoardAssignmentsForTournament(tId);
    final games = await tournamentSvc.getGamesGroupedByBoard(tId);

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

  double _totalPoints(int boardNum, int playerId) {
    return (_boardResults[boardNum]?[playerId] ?? {}).values.fold(0.0, (sum, r) => sum + r);
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

  List<({int teamId, String teamName, Player player})> _sortedStandings(
    int boardNum,
    List<({int teamId, String teamName, Player player})> players,
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

  String _fmtPts(double points) {
    if (points == points.roundToDouble()) return points.toStringAsFixed(1);
    String s = points.toStringAsFixed(2);
    if (s.endsWith('0')) s = s.substring(0, s.length - 1);
    return s;
  }

  String _fmtResult(double? result) {
    if (result == null) return '';
    if (result == 1.0) return '1';
    if (result == 0.0) return '0';
    if (result == 0.5) return '1/2';
    return result.toString();
  }

  Future<pw.Document> _buildPdf() async {
    final pdf = pw.Document();
    final tournamentName = widget.tournament.t_name;
    final boards = _boardPlayers.keys.toList()..sort();

    // Board cross-tables (landscape pages)
    for (final boardNum in boards) {
      final players = _boardPlayers[boardNum] ?? [];
      if (players.isEmpty) continue;
      final sorted = _sortedStandings(boardNum, players);
      final n = sorted.length;
      final isWomen = boardNum == 3;
      final boardLabel = isWomen ? 'Дошка $boardNum (жіноча)' : 'Дошка $boardNum';

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(24),
          header: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(tournamentName, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text(boardLabel, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
            ],
          ),
          build: (context) {
            final headerRow = [
              '№',
              'ПІБ',
              'Команда',
              for (int i = 1; i <= n; i++) '$i',
              'Бали',
              'К.Б.',
              'Місце',
            ];

            final dataRows = <List<String>>[];
            for (int i = 0; i < n; i++) {
              final p = sorted[i];
              final pId = p.player.player_id!;
              final row = <String>[
                '${i + 1}',
                '${p.player.player_surname} ${p.player.player_name}',
                p.teamName,
              ];
              for (int j = 0; j < n; j++) {
                if (i == j) {
                  row.add('X');
                } else {
                  final result = _boardResults[boardNum]?[pId]?[sorted[j].player.player_id!];
                  row.add(_fmtResult(result));
                }
              }
              row.add(_fmtPts(_totalPoints(boardNum, pId)));
              row.add(_fmtPts(_bergerCoefficient(boardNum, pId)));
              row.add('${i + 1}');
              dataRows.add(row);
            }

            return [
              pw.TableHelper.fromTextArray(
                headers: headerRow,
                data: dataRows,
                headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                cellStyle: const pw.TextStyle(fontSize: 8),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
                cellAlignment: pw.Alignment.center,
                columnWidths: {
                  0: const pw.FixedColumnWidth(24),
                  1: const pw.FlexColumnWidth(3),
                  2: const pw.FlexColumnWidth(2),
                  for (int i = 3; i < 3 + n; i++)
                    i: const pw.FixedColumnWidth(22),
                  3 + n: const pw.FixedColumnWidth(32),
                  4 + n: const pw.FixedColumnWidth(32),
                  5 + n: const pw.FixedColumnWidth(32),
                },
                border: pw.TableBorder.all(color: PdfColors.grey400),
              ),
            ];
          },
        ),
      );
    }

    // Team ratings page
    final teamScores = <int, ({String teamName, double total, Map<int, double> perBoard})>{};
    for (final boardEntry in _boardPlayers.entries) {
      final boardNum = boardEntry.key;
      for (final p in boardEntry.value) {
        final existing = teamScores[p.teamId];
        final pts = _totalPoints(boardNum, p.player.player_id!);
        if (existing != null) {
          final newPerBoard = Map<int, double>.from(existing.perBoard);
          newPerBoard[boardNum] = (newPerBoard[boardNum] ?? 0) + pts;
          teamScores[p.teamId] = (
            teamName: existing.teamName,
            total: existing.total + pts,
            perBoard: newPerBoard,
          );
        } else {
          teamScores[p.teamId] = (
            teamName: p.teamName,
            total: pts,
            perBoard: {boardNum: pts},
          );
        }
      }
    }
    final sortedTeams = teamScores.entries.toList()
      ..sort((a, b) => b.value.total.compareTo(a.value.total));

    if (sortedTeams.isNotEmpty) {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          header: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(tournamentName, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text('Командний залік', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
            ],
          ),
          build: (context) {
            final headerRow = [
              'Місце',
              'Команда',
              for (final b in boards) 'Дошка $b',
              'Всього',
            ];
            final dataRows = <List<String>>[];
            for (int i = 0; i < sortedTeams.length; i++) {
              final team = sortedTeams[i].value;
              dataRows.add([
                '${i + 1}',
                team.teamName,
                for (final b in boards) _fmtPts(team.perBoard[b] ?? 0),
                _fmtPts(team.total),
              ]);
            }

            return [
              pw.TableHelper.fromTextArray(
                headers: headerRow,
                data: dataRows,
                headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                cellStyle: const pw.TextStyle(fontSize: 9),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
                cellAlignment: pw.Alignment.center,
                columnWidths: {
                  0: const pw.FixedColumnWidth(36),
                  1: const pw.FlexColumnWidth(3),
                  for (int i = 2; i < 2 + boards.length; i++)
                    i: const pw.FixedColumnWidth(52),
                  2 + boards.length: const pw.FixedColumnWidth(52),
                },
                border: pw.TableBorder.all(color: PdfColors.grey400),
              ),
            ];
          },
        ),
      );
    }

    return pdf;
  }

  Future<void> _exportPdf() async {
    final doc = await _buildPdf();
    final bytes = await doc.save();
    final name = widget.tournament.t_name.replaceAll(RegExp(r'[^\w\s\-]'), '').trim();
    await Printing.sharePdf(bytes: bytes, filename: 'Звіт_$name.pdf');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final hasData = _boardPlayers.isNotEmpty;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade300, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.summarize_outlined, color: Colors.indigo.shade400),
                const SizedBox(width: 12),
                const Text(
                  'Звіти турніру',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Експорт поточного стану турніру у PDF-документ.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const Divider(height: 32),
            if (!hasData)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.info_outline, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'Немає даних для звіту',
                        style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Додайте учасників та розподіліть їх по дошках.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              _reportCard(
                icon: Icons.picture_as_pdf,
                title: 'Повний звіт',
                description: 'Крос-таблиці всіх дошок та командний залік.',
                onTap: _exportPdf,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _reportCard({
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.indigo.shade100, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: Colors.red.shade400, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(description, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ],
                ),
              ),
              Icon(Icons.download_outlined, color: Colors.indigo.shade300),
            ],
          ),
        ),
      ),
    );
  }
}
