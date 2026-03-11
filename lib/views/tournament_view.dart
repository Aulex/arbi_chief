import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../viewmodels/tournament_viewmodel.dart';
import '../viewmodels/nav_provider.dart';

class TournamentView extends ConsumerWidget {
  const TournamentView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tournamentsAsync = ref.watch(tournamentProvider);

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
                      'Турніри',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Керуйте поточними та минулими турнірами.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed:
                      () => ref.read(tournamentNavProvider.notifier).showAdd(),
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Створити турнір'),
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
              child: tournamentsAsync.when(
                data:
                    (tournaments) =>
                        tournaments.isEmpty
                            ? const Center(
                              child: Text(
                                "Турнірів ще немає. Натисніть 'Створити турнір', щоб почати.",
                              ),
                            )
                            : ListView.builder(
                              itemCount: tournaments.length,
                              itemBuilder: (context, index) {
                                final t = tournaments[index];
                                return Card(
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    side: BorderSide(
                                      color: Colors.grey.shade300,
                                      width: 1,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: ListTile(
                                    onTap: () {
                                      ref
                                          .read(tournamentNavProvider.notifier)
                                          .showEdit(t);
                                    },
                                    leading: const Icon(
                                      Symbols.emoji_events_rounded,
                                      color: Colors.indigo,
                                    ),
                                    title: Text(
                                      t.t_name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    trailing: TextButton.icon(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.red,
                                        size: 20,
                                      ),
                                      label: const Text(
                                        'Видалити',
                                        style: TextStyle(color: Colors.red),
                                      ),
                                      style: TextButton.styleFrom(
                                        backgroundColor: Colors.red.withOpacity(0.1),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text('Видалити турнір?'),
                                            content: Text(
                                              'Ви впевнені, що хочете видалити турнір "${t.t_name}"?',
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
                                                      .removeTournament(t.t_id!);
                                                  Navigator.pop(ctx);
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
                                    ),
                                  ),
                                );
                              },
                            ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, s) => Center(child: Text("Помилка: $e")),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
