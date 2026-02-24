import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'tournament_add_screen.dart';
import '../models/tournament_model.dart';

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
    final tournamentPlayers = [
      'Олександр Смирнов',
      'Максим Кузнєцов',
      'Сергій Соколов',
    ];
    final availablePlayers = [
      'Дмитро Іванов',
      'Андрій Попов',
      'Олексій Лєбєдєв',
      'Артем Козлов',
      'Ілля Новіков',
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _buildPlayerListCard(
            'Учасники (3)',
            'Гравці, зареєстровані в цьому турнірі.',
            tournamentPlayers,
            Icons.remove_circle_outline,
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: _buildPlayerListCard(
            'Доступні гравці (57)',
            'Додайте гравців із загального списку.',
            availablePlayers,
            Icons.add_circle_outline,
          ),
        ),
      ],
    );
  }

  Widget _buildPlayerListCard(
    String title,
    String subtitle,
    List<String> players,
    IconData actionIcon,
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
              child: ListView.separated(
                itemCount: players.length,
                separatorBuilder: (context, index) => const Divider(),
                itemBuilder: (context, index) {
                  return ListTile(
                    title: Text(players[index]),
                    trailing: IconButton(
                      icon: Icon(
                        actionIcon,
                        color:
                            actionIcon == Icons.add_circle_outline
                                ? Colors.green
                                : Colors.red,
                      ),
                      onPressed: () {
                        /* Add/Remove logic */
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
