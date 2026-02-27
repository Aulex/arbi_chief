import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'tournament_add_screen.dart';
import 'team_edit_screen.dart';
import '../models/tournament_model.dart';
import '../models/team_model.dart';
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
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back, size: 20),
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
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              SelectableText(
                                'ID: ${widget.tournament.t_id}',
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
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Видалити'),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.red,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Tab Bar
              const TabBar(
                isScrollable: true,
                labelColor: Colors.indigo,
                indicatorColor: Colors.indigo,
                tabs: [
                  Tab(icon: Icon(Icons.leaderboard_outlined, size: 18), text: 'Таблиця'),
                  Tab(icon: Icon(Icons.people_outline, size: 18), text: 'Учасники'),
                  Tab(icon: Icon(Icons.groups_outlined, size: 18), text: 'Команди'),
                  Tab(icon: Icon(Icons.summarize_outlined, size: 18), text: 'Звіти'),
                  Tab(icon: Icon(Icons.settings_outlined, size: 18), text: 'Налаштування'),
                ],
              ),
              const SizedBox(height: 12),
              // Tab Bar View
              Expanded(
                child: TabBarView(
                  children: [
                    _buildTableTab(),
                    _TournamentParticipantsTab(tId: widget.tournament.t_id!),
                    _TournamentTeamsTab(tournament: widget.tournament),
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
        Map<int, List<({int teamId, String teamName, int? teamNumber, Player player})>>>(
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
    List<({int teamId, String teamName, int? teamNumber, Player player})> entries,
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

}

/// Participants tab with optimistic local state for instant add/remove.
class _TournamentParticipantsTab extends ConsumerStatefulWidget {
  final int tId;
  const _TournamentParticipantsTab({required this.tId});

  @override
  ConsumerState<_TournamentParticipantsTab> createState() => _TournamentParticipantsTabState();
}

class _TournamentParticipantsTabState extends ConsumerState<_TournamentParticipantsTab> {
  List<Player> _participants = [];
  List<Player> _available = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final svc = ref.read(tournamentServiceProvider);
    final participants = await svc.getParticipants(widget.tId);
    final allPlayers = await ref.read(playerProvider.future);
    final participantIds = participants.map((p) => p.player_id).toSet();
    final available = allPlayers
        .where((p) => !participantIds.contains(p.player_id))
        .toList()
      ..sort((a, b) => a.player_surname.compareTo(b.player_surname));

    if (mounted) {
      setState(() {
        _participants = participants;
        _available = available;
        _loading = false;
      });
    }
  }

  void _removeParticipant(Player player) {
    setState(() {
      _participants.removeWhere((p) => p.player_id == player.player_id);
      _available
        ..add(player)
        ..sort((a, b) => a.player_surname.compareTo(b.player_surname));
    });
    ref.read(tournamentServiceProvider).removeParticipant(widget.tId, player.player_id!);
  }

  void _addParticipant(Player player) {
    setState(() {
      _available.removeWhere((p) => p.player_id == player.player_id);
      _participants
        ..add(player)
        ..sort((a, b) => a.player_surname.compareTo(b.player_surname));
    });
    ref.read(tournamentServiceProvider).addParticipant(widget.tId, player.player_id!);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _buildPlayerListCard(
            title: 'Учасники (${_participants.length})',
            subtitle: 'Гравці, зареєстровані в цьому турнірі.',
            players: _participants,
            emptyText: 'Немає учасників',
            actionIcon: Icons.remove_circle_outline,
            actionColor: Colors.redAccent,
            onAction: _removeParticipant,
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: _buildPlayerListCard(
            title: 'Доступні гравці (${_available.length})',
            subtitle: 'Додайте гравців із загального списку.',
            players: _available,
            emptyText: 'Немає доступних гравців',
            actionIcon: Icons.add_circle_outline,
            actionColor: Colors.green,
            onAction: _addParticipant,
          ),
        ),
      ],
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
  Map<int, List<({int teamId, String teamName, int? teamNumber, Player player})>> _boardPlayers = {};
  Map<int, Map<int, Map<int, double>>> _boardResults = {};
  int? _hoveredRow;
  int? _hoveredCol;

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
          labelPadding: const EdgeInsets.symmetric(horizontal: 16),
          tabs: const [
            Tab(text: 'Дошка 1', height: 36),
            Tab(text: 'Дошка 2', height: 36),
            Tab(text: 'Дошка 3', height: 36),
            Tab(text: 'Команди', height: 36),
          ],
        ),
        const SizedBox(height: 6),
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
        Expanded(
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCrossTable(boardNum, players),
                    _buildStandings(boardNum, players),
                  ],
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

    // Sort: points desc, then h2h, board 1, board 3
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
                _tableCell('№', style: headerStyle),
                _tableCell('Команда', style: headerStyle, minWidth: 140),
                for (int i = 0; i < n; i++)
                  _verticalHeaderCell(
                    number: teamMap[teamIds[i]]!.teamNumber ?? (i + 1),
                    surname: teamMap[teamIds[i]]!.teamName,
                    isHighlighted: false,
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
                    if (i == j)
                      _diagonalCell()
                    else
                      _teamResultCell(teamIds[i], teamIds[j]),
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

  // --- Cross-table ---

  Widget _buildCrossTable(
    int boardNum,
    List<({int teamId, String teamName, int? teamNumber, Player player})> players,
  ) {
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
            _tableCell('К.Б.', style: headerStyle),
          ],
        ),
        for (int i = 0; i < n; i++)
          TableRow(
            decoration: i.isEven ? null : BoxDecoration(color: Colors.grey.shade50),
            children: [
              _tableCell(
                '${players[i].teamNumber ?? ''}',
                style: cellStyle.copyWith(color: Colors.grey.shade600, fontSize: 11),
              ),
              _tableCell(players[i].teamName, style: cellStyle, minWidth: 70, leftAlign: true),
              _highlightableNameCell(
                '${players[i].player.player_surname} ${players[i].player.player_name}',
                isHighlighted: _hoveredRow == i,
                style: cellStyle,
                minWidth: 130,
              ),
              for (int j = 0; j < n; j++)
                if (i == j)
                  _diagonalCell()
                else
                  _tappableResultCell(boardNum: boardNum, rowPlayer: players[i], colPlayer: players[j], rowIdx: i, colIdx: j),
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
    List<({int teamId, String teamName, int? teamNumber, Player player})> players,
  ) {
    final sorted = _sortedStandings(boardNum, players);

    const headerStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54);
    const cellStyle = TextStyle(fontSize: 12, color: Colors.black87);

    final borderSide = BorderSide(color: Colors.grey.shade300, width: 1);
    return Table(
      border: TableBorder(
        top: borderSide,
        right: borderSide,
        bottom: borderSide,
        left: BorderSide.none,
        horizontalInside: borderSide,
        verticalInside: borderSide,
      ),
      defaultColumnWidth: const IntrinsicColumnWidth(),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: BoxDecoration(color: Colors.grey.shade100),
          children: [
            _tableCell('№к', style: headerStyle),
            _tableCell('ПІБ', style: headerStyle, minWidth: 130),
            _tableCell('Команда', style: headerStyle, minWidth: 90),
            _tableCell('Бали', style: headerStyle),
            _tableCell('К.Б.', style: headerStyle),
            _tableCell('Місце', style: headerStyle),
          ],
        ),
        for (int i = 0; i < sorted.length; i++)
          TableRow(
            decoration: i.isEven ? null : BoxDecoration(color: Colors.grey.shade50),
            children: [
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

  Widget _tappableResultCell({
    required int boardNum,
    required ({int teamId, String teamName, int? teamNumber, Player player}) rowPlayer,
    required ({int teamId, String teamName, int? teamNumber, Player player}) colPlayer,
    required int rowIdx,
    required int colIdx,
  }) {
    final result = _boardResults[boardNum]?[rowPlayer.player.player_id!]?[colPlayer.player.player_id!];
    final text = _formatResult(result);

    final isHighlighted = _hoveredRow == rowIdx || _hoveredCol == colIdx;
    Color? bgColor;
    if (text == '1') {
      bgColor = Colors.green.shade50;
    } else if (text == '0') {
      bgColor = Colors.red.shade50;
    } else if (text == '½') {
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
          rowPlayerId: rowPlayer.player.player_id!,
          colPlayerId: colPlayer.player.player_id!,
          rowPlayerName: '${rowPlayer.player.player_surname} ${rowPlayer.player.player_name}',
          colPlayerName: '${colPlayer.player.player_surname} ${colPlayer.player.player_name}',
          currentResult: result,
        ),
        child: Container(
          constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
          color: bgColor ?? Colors.transparent,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: text.isEmpty
              ? Icon(Icons.edit_outlined, size: 12, color: Colors.grey.shade400)
              : Text(
                  text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
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

/// Teams tab — manage team compositions within this tournament.
class _TournamentTeamsTab extends ConsumerStatefulWidget {
  final Tournament tournament;
  const _TournamentTeamsTab({required this.tournament});

  @override
  ConsumerState<_TournamentTeamsTab> createState() => _TournamentTeamsTabState();
}

class _TournamentTeamsTabState extends ConsumerState<_TournamentTeamsTab> {
  bool _loading = true;
  List<({Team team, int? teamNumber, Map<int, int> boards})> _teamData = [];
  Map<int, Player> _playerMap = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final teamSvc = ref.read(teamServiceProvider);
    final tId = widget.tournament.t_id!;
    final data = await teamSvc.getTeamsForTournament(tId);

    final players = await ref.read(playerProvider.future);
    final pMap = <int, Player>{
      for (final p in players)
        if (p.player_id != null) p.player_id!: p
    };

    if (mounted) {
      setState(() {
        _teamData = data;
        _playerMap = pMap;
        _loading = false;
      });
    }
  }

  String _playerLabel(int? playerId) {
    if (playerId == null) return '—';
    final p = _playerMap[playerId];
    if (p == null) return '—';
    final initName = p.player_name.isNotEmpty ? ' ${p.player_name[0]}.' : '';
    return '${p.player_surname}$initName';
  }

  Future<void> _addTeamToTournament() async {
    final allTeams = await ref.read(teamProvider.future);
    final existingIds = _teamData.map((d) => d.team.team_id).toSet();
    final available = allTeams.where((t) => !existingIds.contains(t.team_id)).toList();

    if (available.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Всі команди вже додані до турніру.')),
        );
      }
      return;
    }

    if (!mounted) return;

    // Show dialog to select team and set number
    Team? selectedTeam;
    final numberC = TextEditingController(
      text: '${_teamData.length + 1}',
    );

    final result = await showDialog<({Team team, int number})>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Додати команду до турніру'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<Team>(
                  value: selectedTeam,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Команда',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: available.map((t) => DropdownMenuItem(
                    value: t,
                    child: Text(t.team_name),
                  )).toList(),
                  onChanged: (val) => setDialogState(() => selectedTeam = val),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: numberC,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Номер команди',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Скасувати'),
              ),
              ElevatedButton(
                onPressed: selectedTeam == null ? null : () {
                  final num = int.tryParse(numberC.text.trim()) ?? (_teamData.length + 1);
                  Navigator.pop(ctx, (team: selectedTeam!, number: num));
                },
                child: const Text('Далі'),
              ),
            ],
          ),
        );
      },
    );

    if (result != null && mounted) {
      final service = ref.read(teamServiceProvider);
      // Navigate to board edit first so rows get created
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TeamEditScreen(
            team: result.team,
            tId: widget.tournament.t_id!,
          ),
        ),
      );
      // Now set team_number on the newly created rows
      await service.setTeamNumber(
        result.team.team_id!, widget.tournament.t_id!, result.number,
      );
      _reloadData();
    }
  }

  void _reloadData() {
    setState(() => _loading = true);
    _loadData();
  }

  Future<void> _removeTeamFromTournament(Team team) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Видалити команду з турніру?'),
        content: Text('Видалити склад команди "${team.team_name}" з цього турніру?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Скасувати')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Видалити', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final service = ref.read(teamServiceProvider);
      await service.saveAssignments(team.team_id!, widget.tournament.t_id!, {}, []);
      _reloadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Команди турніру',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Склад команд у цьому турнірі.',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: _addTeamToTournament,
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Додати команду'),
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.indigo,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            if (_teamData.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.groups_outlined, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'Команд у турнірі поки немає',
                        style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Натисніть "Додати команду", щоб налаштувати склад.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: constraints.maxWidth),
                      child: DataTable(
                        headingTextStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.black54,
                        ),
                        columnSpacing: 24,
                        columns: const [
                          DataColumn(label: Text('№')),
                          DataColumn(label: Text('Команда')),
                          DataColumn(label: Text('Дошка 1')),
                          DataColumn(label: Text('Дошка 2')),
                          DataColumn(label: Text('Дошка 3')),
                          DataColumn(label: Text('Дія')),
                        ],
                    rows: _teamData.map((d) {
                      return DataRow(cells: [
                        DataCell(Text('${d.teamNumber ?? ''}')),
                        DataCell(Text(d.team.team_name)),
                        DataCell(Text(_playerLabel(d.boards[1]))),
                        DataCell(Text(_playerLabel(d.boards[2]))),
                        DataCell(Text(_playerLabel(d.boards[3]))),
                        DataCell(Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              tooltip: 'Редагувати склад',
                              onPressed: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => TeamEditScreen(
                                      team: d.team,
                                      tId: widget.tournament.t_id!,
                                    ),
                                  ),
                                );
                                _reloadData();
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                              tooltip: 'Видалити з турніру',
                              onPressed: () => _removeTeamFromTournament(d.team),
                            ),
                          ],
                        )),
                      ]);
                    }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
          ],
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
  Map<int, List<({int teamId, String teamName, int? teamNumber, Player player})>> _boardPlayers = {};
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

    // Load a font that supports Cyrillic (Ukrainian) characters
    final fontRegular = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();
    final theme = pw.ThemeData.withFont(base: fontRegular, bold: fontBold);

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
          theme: theme,
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
                cellStyle: pw.TextStyle(fontSize: 8, font: fontRegular),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
                cellAlignment: pw.Alignment.center,
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(2),
                  for (int i = 2; i < 2 + n; i++)
                    i: const pw.FixedColumnWidth(22),
                  2 + n: const pw.FixedColumnWidth(32),
                  3 + n: const pw.FixedColumnWidth(32),
                  4 + n: const pw.FixedColumnWidth(40),
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
          theme: theme,
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
                cellStyle: pw.TextStyle(fontSize: 9, font: fontRegular),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
                cellAlignment: pw.Alignment.center,
                columnWidths: {
                  0: const pw.FixedColumnWidth(44),
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
