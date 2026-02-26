import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../viewmodels/team_viewmodel.dart';
import '../viewmodels/player_viewmodel.dart';
import '../models/team_model.dart';
import '../models/player_model.dart';
import 'team_edit_screen.dart';

class TeamView extends ConsumerWidget {
  const TeamView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamsAsync = ref.watch(teamProvider);
    final playersAsync = ref.watch(playerProvider);
    final boardsAsync = ref.watch(allTeamBoardsProvider);

    return Card(
      margin: const EdgeInsets.all(24),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                    Text(
                      'Команди',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Перегляд та керування всіма командами.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: () => _showAddDialog(context, ref),
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Додати команду'),
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.indigo,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            Expanded(
              child: teamsAsync.when(
                data: (teams) {
                  if (teams.isEmpty) {
                    return const Center(child: Text("Команд не знайдено."));
                  }

                  final players = playersAsync.valueOrNull ?? [];
                  final playerMap = {
                    for (final p in players)
                      if (p.player_id != null) p.player_id!: p
                  };
                  final boardsMap = boardsAsync.valueOrNull ?? {};

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints:
                              BoxConstraints(minWidth: constraints.maxWidth),
                          child: DataTable(
                            headingTextStyle: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.black54,
                            ),
                            columns: const [
                              DataColumn(label: Text('Назва команди')),
                              DataColumn(label: Text('Дошка 1')),
                              DataColumn(label: Text('Дошка 2')),
                              DataColumn(label: Text('Дошка 3')),
                              DataColumn(label: Text('Дія')),
                            ],
                            rows: teams.map((t) {
                              final boards = boardsMap[t.team_id] ?? {};
                              return DataRow(
                                cells: [
                                  DataCell(Text(t.team_name)),
                                  DataCell(Text(_playerLabel(boards[1], playerMap))),
                                  DataCell(Text(_playerLabel(boards[2], playerMap))),
                                  DataCell(Text(_playerLabel(boards[3], playerMap))),
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit,
                                              color: Colors.blue),
                                          onPressed: () async {
                                            await Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    TeamEditScreen(team: t),
                                              ),
                                            );
                                            ref.invalidate(allTeamBoardsProvider);
                                          },
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete,
                                              color: Colors.red),
                                          onPressed: () =>
                                              _confirmDelete(context, ref, t),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      );
                    },
                  );
                },
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, s) => Center(child: Text("Помилка: $e")),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _playerLabel(int? playerId, Map<int, Player> playerMap) {
    if (playerId == null) return '—';
    final p = playerMap[playerId];
    if (p == null) return '—';
    final initName = p.player_name.isNotEmpty ? ' ${p.player_name[0]}.' : '';
    return '${p.player_surname}$initName';
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    final nameC = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text("Додати команду"),
        content: TextField(
          controller: nameC,
          decoration: const InputDecoration(
            labelText: "Назва команди",
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text("Скасувати"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameC.text.trim().isNotEmpty) {
                final newTeam = await ref
                    .read(teamProvider.notifier)
                    .addTeam(name: nameC.text.trim());
                if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                if (context.mounted) {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TeamEditScreen(team: newTeam),
                    ),
                  );
                  ref.invalidate(allTeamBoardsProvider);
                }
              }
            },
            child: const Text("Зберегти"),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, Team team) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Видалити команду?"),
        content: Text(
            "Ви впевнені, що хочете видалити команду \"${team.team_name}\"?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Скасувати"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              ref.read(teamProvider.notifier).removeTeam(team.team_id!);
              Navigator.pop(context);
            },
            child: const Text("Видалити",
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
