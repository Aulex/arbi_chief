import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'tournament_add_screen.dart';
import '../models/tournament_model.dart';
import '../models/player_model.dart';
import '../viewmodels/player_viewmodel.dart';

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
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Керування турніром'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
        ),
        body: Padding(
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
                      ElevatedButton.icon(
                        onPressed: () {
                          // Delete logic
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
                  Tab(icon: Icon(Icons.shuffle_outlined), text: 'Жеребкування'),
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
                    _buildPairingTab(),
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

  Widget _buildPairingTab() {
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
              'Жеребкування та результати',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Створюйте пари для наступного туру та вводьте результати матчів.',
            ),
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Жеребкування ще не розпочато.'),
                    SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: null, // Logic to be added
                      child: Text('Розпочати 1-й тур'),
                    ),
                  ],
                ),
              ),
            ),
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
    final playersAsync = ref.watch(playerProvider);

    return playersAsync.when(
      data: (allPlayers) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Expanded(
              child: _ParticipantsCard(
                title: 'Учасники (0)',
                subtitle: 'Гравці, зареєстровані в цьому турнірі.',
                players: [],
                actionIcon: Icons.remove_circle_outline,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: _AvailablePlayersCard(
                allPlayers: allPlayers,
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => Center(child: Text('Помилка: $e')),
    );
  }
}

class _ParticipantsCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Player> players;
  final IconData actionIcon;

  const _ParticipantsCard({
    required this.title,
    required this.subtitle,
    required this.players,
    required this.actionIcon,
  });

  @override
  Widget build(BuildContext context) {
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
                  ? const Center(child: Text('Немає учасників'))
                  : ListView.separated(
                      itemCount: players.length,
                      separatorBuilder: (context, index) => const Divider(),
                      itemBuilder: (context, index) {
                        return ListTile(
                          title: Text(players[index].fullName),
                          trailing: IconButton(
                            icon: Icon(actionIcon, color: Colors.red),
                            onPressed: () {
                              /* Remove logic */
                            },
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

class _AvailablePlayersCard extends StatelessWidget {
  final List<Player> allPlayers;

  const _AvailablePlayersCard({required this.allPlayers});

  @override
  Widget build(BuildContext context) {
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
              'Доступні гравці (${allPlayers.length})',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Додайте гравців із загального списку.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const Divider(height: 24),
            Expanded(
              child: allPlayers.isEmpty
                  ? const Center(child: Text('Немає доступних гравців'))
                  : ListView.separated(
                      itemCount: allPlayers.length,
                      separatorBuilder: (context, index) => const Divider(),
                      itemBuilder: (context, index) {
                        final player = allPlayers[index];
                        return ListTile(
                          title: Text(player.fullName),
                          subtitle: Text(
                            player.birthDateForUI.isNotEmpty
                                ? player.birthDateForUI
                                : '',
                          ),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.add_circle_outline,
                              color: Colors.green,
                            ),
                            onPressed: () {
                              /* Add to tournament logic */
                            },
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
