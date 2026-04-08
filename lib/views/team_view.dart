import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../viewmodels/team_viewmodel.dart';
import '../models/team_model.dart';

class TeamView extends ConsumerStatefulWidget {
  const TeamView({super.key});

  @override
  ConsumerState<TeamView> createState() => _TeamViewState();
}

class _TeamViewState extends ConsumerState<TeamView> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final teamsAsync = ref.watch(teamProvider);

    return Card(
      margin: const EdgeInsets.fromLTRB(24, 8, 24, 24),
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
                      'Перегляд та керування командами. Склад команд налаштовується в турнірі.',
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
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Пошук команди...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onChanged: (value) => setState(() => _searchQuery = value.trim().toLowerCase()),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            Expanded(
              child: teamsAsync.when(
                data: (teams) {
                  final filtered = _searchQuery.isEmpty
                      ? teams
                      : teams.where((t) => t.team_name.toLowerCase().contains(_searchQuery)).toList();
                  if (filtered.isEmpty) {
                    return Center(
                      child: Text(
                        _searchQuery.isEmpty ? "Команд не знайдено." : "Нічого не знайдено за запитом '$_searchQuery'.",
                      ),
                    );
                  }

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
                              DataColumn(label: Text('Дія')),
                            ],
                            rows: filtered.map((t) {
                              return DataRow(
                                cells: [
                                  DataCell(Text(t.team_name)),
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit_outlined,
                                              color: Colors.indigo),
                                          tooltip: 'Редагувати',
                                          onPressed: () =>
                                              _showRenameDialog(context, ref, t),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline,
                                              color: Colors.redAccent),
                                          tooltip: 'Видалити',
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
                await ref
                    .read(teamProvider.notifier)
                    .addTeam(name: nameC.text.trim());
                if (dialogCtx.mounted) Navigator.pop(dialogCtx);
              }
            },
            child: const Text("Зберегти"),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref, Team team) {
    final nameC = TextEditingController(text: team.team_name);

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text("Перейменувати команду"),
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
                await ref
                    .read(teamProvider.notifier)
                    .updateTeam(team.copyWith(team_name: nameC.text.trim()));
                if (dialogCtx.mounted) Navigator.pop(dialogCtx);
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
