import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      length: 6,
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
                  Tab(icon: Icon(Icons.dashboard_outlined), text: 'Дошки'),
                  Tab(icon: Icon(Icons.sports_esports_outlined), text: 'Ігри'),
                  Tab(icon: Icon(Icons.leaderboard_outlined), text: 'Таблиця'),
                  Tab(icon: Icon(Icons.people_outline), text: 'Учасники'),
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
                    _buildBoardsTab(),
                    _buildGamesTab(),
                    _buildTableTab(),
                    _buildParticipantsTab(),
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
    final tId = widget.tournament.t_id!;
    final svc = ref.read(tournamentServiceProvider);
    final teamSvc = ref.read(teamServiceProvider);

    return FutureBuilder(
      future: Future.wait([
        svc.getGamesForTournament(tId),
        teamSvc.getBoardAssignmentsForTournament(tId),
      ]),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final games = snapshot.data![0]
            as List<({int eventId, Player white, Player black, String? dateBegin})>;
        final boards = snapshot.data![1]
            as Map<int, List<({int teamId, String teamName, Player player})>>;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Create game card
              _buildCreateGameCard(boards, tId),
              const SizedBox(height: 16),
              // Games list
              _buildGamesListCard(games, tId),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCreateGameCard(
    Map<int, List<({int teamId, String teamName, Player player})>> boards,
    int tId,
  ) {
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
              'Створити гру',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Оберіть дошку та двох гравців з однієї дошки.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const Divider(height: 24),
            _CreateGameForm(boards: boards, tId: tId),
          ],
        ),
      ),
    );
  }

  Widget _buildGamesListCard(
    List<({int eventId, Player white, Player black, String? dateBegin})> games,
    int tId,
  ) {
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
              'Список ігор (${games.length})',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Divider(height: 24),
            if (games.isEmpty)
              Text(
                'Ігор ще немає. Створіть першу гру вище.',
                style: TextStyle(color: Colors.grey.shade500),
              )
            else
              ...games.asMap().entries.map((entry) {
                final i = entry.key;
                final g = entry.value;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.indigo,
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                  ),
                  title: Text(
                      '${g.white.fullName}  —  ${g.black.fullName}'),
                  subtitle: g.dateBegin != null ? Text(g.dateBegin!) : null,
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () async {
                      final svc = ref.read(tournamentServiceProvider);
                      await svc.deleteGame(g.eventId);
                      setState(() {});
                    },
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildTableTab() {
    // Mock data for the table
    final players = [
      {
        'rank': '1',
        'name': 'Олександр Смирнов',
        'points': '0.0',
        'played': '0',
      },
      {'rank': '1', 'name': 'Максим Кузнєцов', 'points': '0.0', 'played': '0'},
      {'rank': '1', 'name': 'Сергій Соколов', 'points': '0.0', 'played': '0'},
    ];

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
              'Поточна таблиця',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('Онлайн-таблиця з результатами та тай-брейками.'),
            const SizedBox(height: 16),
            Expanded(
              child: DataTable(
                headingTextStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black54,
                ),
                columns: const [
                  DataColumn(label: Text('Ранг')),
                  DataColumn(label: Text('Гравець')),
                  DataColumn(label: Text('Очки'), numeric: true),
                  DataColumn(label: Text('Ігор зіграно'), numeric: true),
                ],
                rows:
                    players.map((player) {
                      return DataRow(
                        cells: [
                          DataCell(Text(player['rank']!)),
                          DataCell(Text(player['name']!)),
                          DataCell(Text(player['points']!)),
                          DataCell(Text(player['played']!)),
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
                .toList();

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

/// Stateful form for creating a game: pick board -> pick two players -> create.
class _CreateGameForm extends ConsumerStatefulWidget {
  final Map<int, List<({int teamId, String teamName, Player player})>> boards;
  final int tId;

  const _CreateGameForm({required this.boards, required this.tId});

  @override
  ConsumerState<_CreateGameForm> createState() => _CreateGameFormState();
}

class _CreateGameFormState extends ConsumerState<_CreateGameForm> {
  int? _selectedBoard;
  int? _player1Id;
  int? _player2Id;

  @override
  Widget build(BuildContext context) {
    final boardNumbers = widget.boards.keys.toList()..sort();
    final playersOnBoard = _selectedBoard != null
        ? widget.boards[_selectedBoard!] ?? []
        : <({int teamId, String teamName, Player player})>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Board selector
        DropdownButtonFormField<int?>(
          key: ValueKey('board_select_${widget.tId}'),
          value: _selectedBoard,
          isExpanded: true,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            labelText: 'Дошка',
          ),
          items: boardNumbers.map((b) {
            final label = b == 3 ? 'Дошка $b (жіноча)' : 'Дошка $b';
            return DropdownMenuItem<int?>(value: b, child: Text(label));
          }).toList(),
          onChanged: (value) {
            setState(() {
              _selectedBoard = value;
              _player1Id = null;
              _player2Id = null;
            });
          },
        ),
        const SizedBox(height: 12),
        // Two player selectors in a row
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int?>(
                key: ValueKey('p1_${_selectedBoard}_${_player2Id}'),
                value: _player1Id,
                isExpanded: true,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  labelText: 'Гравець 1',
                ),
                items: playersOnBoard
                    .where((e) => e.player.player_id != _player2Id)
                    .map((e) => DropdownMenuItem<int?>(
                          value: e.player.player_id,
                          child: Text(
                              '${e.player.fullName} (${e.teamName})'),
                        ))
                    .toList(),
                onChanged: _selectedBoard == null
                    ? null
                    : (value) => setState(() => _player1Id = value),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('—', style: TextStyle(fontSize: 20)),
            ),
            Expanded(
              child: DropdownButtonFormField<int?>(
                key: ValueKey('p2_${_selectedBoard}_${_player1Id}'),
                value: _player2Id,
                isExpanded: true,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  labelText: 'Гравець 2',
                ),
                items: playersOnBoard
                    .where((e) => e.player.player_id != _player1Id)
                    .map((e) => DropdownMenuItem<int?>(
                          value: e.player.player_id,
                          child: Text(
                              '${e.player.fullName} (${e.teamName})'),
                        ))
                    .toList(),
                onChanged: _selectedBoard == null
                    ? null
                    : (value) => setState(() => _player2Id = value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.indigo,
            ),
            onPressed:
                (_player1Id != null && _player2Id != null) ? _create : null,
            icon: const Icon(Icons.add),
            label: const Text('Створити гру'),
          ),
        ),
      ],
    );
  }

  Future<void> _create() async {
    final svc = ref.read(tournamentServiceProvider);
    final tsId = await svc.getOrCreateDefaultStage(widget.tId);
    await svc.createGame(
      tsId: tsId,
      whitePlayerId: _player1Id!,
      blackPlayerId: _player2Id!,
    );
    setState(() {
      _player1Id = null;
      _player2Id = null;
    });
    // Trigger rebuild of parent to refresh games list
    if (context.mounted) {
      (context.findAncestorStateOfType<_TournamentEditScreenState>())
          ?.setState(() {});
    }
  }
}
