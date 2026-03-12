import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'tournament_add_screen.dart';
import 'tournament_players_tab.dart';
import 'tournament_teams_tab.dart';
import 'tournament_cross_table_tab.dart';
import '../models/tournament_model.dart';
import '../models/player_model.dart';
import '../models/sport_type_config.dart';
import '../viewmodels/nav_provider.dart';
import '../viewmodels/tournament_viewmodel.dart';
import '../viewmodels/team_viewmodel.dart';
import '../viewmodels/standings_window_provider.dart';

class TournamentEditScreen extends ConsumerStatefulWidget {
  final Tournament tournament;
  const TournamentEditScreen({super.key, required this.tournament});

  @override
  ConsumerState<TournamentEditScreen> createState() =>
      _TournamentEditScreenState();
}

class _TournamentEditScreenState extends ConsumerState<TournamentEditScreen> {
  SportTypeConfig get _sportConfig => getConfigForType(widget.tournament.t_type);

  Future<void> _openStandingsWindow() async {
    // If already open, bring it to focus
    final existing = ref.read(standingsWindowControllerProvider);
    if (existing != null) {
      try {
        await existing.show();
        // Send latest standings data
        final snapshot = ref.read(standingsSnapshotProvider);
        if (snapshot != null) {
          await sendStandingsToWindow(existing, snapshot);
        }
        return;
      } catch (_) {
        // Window was closed, create new one
        ref.read(standingsWindowControllerProvider.notifier).setController(null);
      }
    }

    final snapshot = ref.read(standingsSnapshotProvider);
    final initialData = snapshot != null ? jsonEncode(snapshot.toJson()) : '{}';

    final window = await WindowController.create(
      WindowConfiguration(arguments: initialData),
    );
    await window.show();

    ref.read(standingsWindowControllerProvider.notifier).setController(window);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24.0, 8.0, 24.0, 24.0),
        child: Column(
          children: [
            // Header with back arrow | tabs
            Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: Colors.grey.shade300, width: 1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, size: 20),
                        onPressed: () {
                          ref
                              .read(tournamentNavProvider.notifier)
                              .showList();
                        },
                      ),
                      SizedBox(
                        height: 32,
                        child: VerticalDivider(
                          thickness: 1,
                          width: 24,
                          color: Colors.grey.shade300,
                        ),
                      ),
                      Expanded(
                        child: TabBar(
                          isScrollable: true,
                          labelColor: Colors.indigo,
                          indicatorColor: Colors.indigo,
                          indicatorWeight: 2,
                          tabAlignment: TabAlignment.start,
                          tabs: const [
                            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.leaderboard_outlined, size: 18), SizedBox(width: 6), Text('Таблиця')])),
                            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.people_outline, size: 18), SizedBox(width: 6), Text('Гравці')])),
                            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.groups_outlined, size: 18), SizedBox(width: 6), Text('Команди')])),
                            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.settings_outlined, size: 18), SizedBox(width: 6), Text('Налаштування')])),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 32,
                        child: VerticalDivider(
                          thickness: 1,
                          width: 24,
                          color: Colors.grey.shade300,
                        ),
                      ),
                      Tooltip(
                        message: 'Відкрити таблицю на другому моніторі',
                        child: IconButton(
                          icon: const Icon(Icons.open_in_new, size: 20),
                          onPressed: _openStandingsWindow,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Tab Bar View
              Expanded(
                child: TabBarView(
                  children: [
                    CrossTableTab(tId: widget.tournament.t_id!, tournamentName: widget.tournament.t_name, config: _sportConfig, tType: widget.tournament.t_type),
                    TournamentPlayersTab(tId: widget.tournament.t_id!, tType: widget.tournament.t_type),
                    TournamentTeamsTab(tournament: widget.tournament, config: _sportConfig),
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
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_sportConfig.boardLabel}и — Колова система',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Розподіл гравців по ${_sportConfig.boardLabelPlural} з командних складів.',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int boardNum = 1; boardNum <= _sportConfig.boardCount; boardNum++) ...[
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
    final isWomenBoard = _sportConfig.lastBoardWomenOnly && boardNum == _sportConfig.boardCount;

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
                  _sportConfig.tabLabel(boardNum),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),
            if (entries.isEmpty)
              Text(
                'Немає гравців на цій позиції',
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
}
