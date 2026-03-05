import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/sport_type_config.dart';
import '../models/tournament_model.dart';
import '../viewmodels/tournament_viewmodel.dart';
import 'tournament_edit_screen.dart';

class ReportsListView extends ConsumerStatefulWidget {
  const ReportsListView({super.key});

  @override
  ConsumerState<ReportsListView> createState() => _ReportsListViewState();
}

class _ReportsListViewState extends ConsumerState<ReportsListView> {
  Tournament? _selected;

  @override
  Widget build(BuildContext context) {
    final tournamentsAsync = ref.watch(tournamentProvider);

    if (_selected != null) {
      final config = getConfigForType(_selected!.t_type);
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, size: 20),
                  onPressed: () => setState(() => _selected = null),
                ),
                const SizedBox(width: 8),
                Text(
                  'Звіти: ${_selected!.t_name}',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ReportsTab(
                tournament: _selected!,
                config: config,
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Звіти',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Оберіть турнір для перегляду та генерації звітів.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade600,
                  ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            Expanded(
              child: tournamentsAsync.when(
                data: (tournaments) => tournaments.isEmpty
                    ? const Center(child: Text('Турнірів ще немає.'))
                    : ListView.builder(
                        itemCount: tournaments.length,
                        itemBuilder: (context, index) {
                          final t = tournaments[index];
                          return Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              side: BorderSide(
                                  color: Colors.grey.shade300, width: 1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ListTile(
                              onTap: () => setState(() => _selected = t),
                              leading: const Icon(
                                Icons.summarize_outlined,
                                color: Colors.indigo,
                              ),
                              title: Text(
                                t.t_name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500),
                              ),
                              trailing: const Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                                color: Colors.grey,
                              ),
                            ),
                          );
                        },
                      ),
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, s) => Center(child: Text('Помилка: $e')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
