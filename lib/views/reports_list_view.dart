import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../viewmodels/tournament_viewmodel.dart';
import '../viewmodels/navigation_viewmodel.dart';
import '../viewmodels/nav_provider.dart';

class ReportsListView extends ConsumerWidget {
  const ReportsListView({super.key});

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
                              onTap: () {
                                ref
                                    .read(tournamentNavProvider.notifier)
                                    .showEdit(t);
                                ref
                                    .read(navigationProvider.notifier)
                                    .setTab(0);
                              },
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
