import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'tournament_edit_screen.dart';
import '../viewmodels/tournament_viewmodel.dart';
import '../viewmodels/nav_provider.dart';

class TournamentView extends ConsumerWidget {
  const TournamentView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tournamentsAsync = ref.watch(tournamentProvider);

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
                                    leading: const Icon(
                                      Icons.emoji_events_outlined,
                                      color: Colors.indigo,
                                    ),
                                    title: Text(
                                      t.t_name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        OutlinedButton(
                                          onPressed: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder:
                                                    (context) =>
                                                        TournamentEditScreen(
                                                          tournament: t,
                                                        ),
                                              ),
                                            );
                                          },
                                          child: const Text('Керувати'),
                                          style: OutlinedButton.styleFrom(
                                            side: BorderSide(
                                              color: Colors.grey.shade300,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            color: Colors.red,
                                          ),
                                          onPressed: () {
                                            // TODO: Implement delete confirmation and logic
                                          },
                                          style: IconButton.styleFrom(
                                            backgroundColor: Colors.red
                                                .withOpacity(0.1),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                        ),
                                      ],
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
