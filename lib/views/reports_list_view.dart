import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/sport_type_config.dart';
import '../models/tournament_model.dart';
import '../viewmodels/tournament_viewmodel.dart';
import 'tournament_edit_screen.dart';

class ReportsListView extends ConsumerWidget {
  const ReportsListView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              'Оберіть тип звіту для генерації.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade600,
                  ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            // Tournament-linked reports
            _ReportTypeCard(
              icon: Icons.picture_as_pdf,
              iconColor: Colors.red,
              title: 'Повний звіт турніру',
              description: 'Крос-таблиці всіх дошок та командний залік.',
              requiresTournament: true,
            ),
            // Future non-tournament reports can be added here:
            // _ReportTypeCard(
            //   icon: Icons.people,
            //   iconColor: Colors.blue,
            //   title: 'Список гравців',
            //   description: 'Загальний список всіх гравців у системі.',
            //   requiresTournament: false,
            // ),
          ],
        ),
      ),
    );
  }
}

class _ReportTypeCard extends ConsumerWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final bool requiresTournament;

  const _ReportTypeCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.requiresTournament,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.indigo.shade100, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          if (requiresTournament) {
            _showTournamentPicker(context, ref);
          } else {
            // For non-tournament reports, generate directly
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(description, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  void _showTournamentPicker(BuildContext context, WidgetRef ref) {
    final tournamentsAsync = ref.read(tournamentProvider);

    tournamentsAsync.when(
      data: (tournaments) {
        if (tournaments.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Турнірів ще немає.')),
          );
          return;
        }

        showDialog(
          context: context,
          builder: (ctx) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 450, maxHeight: 500),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(icon, color: iconColor, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Оберіть турнір:',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: tournaments.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final t = tournaments[index];
                            return Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                side: BorderSide(color: Colors.grey.shade300, width: 1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ListTile(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                leading: const Icon(Icons.emoji_events, color: Colors.indigo),
                                title: Text(t.t_name, style: const TextStyle(fontWeight: FontWeight.w500)),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _generateReport(context, ref, t);
                                },
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Скасувати'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
      loading: () {},
      error: (e, s) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Помилка: $e')),
        );
      },
    );
  }

  void _generateReport(BuildContext context, WidgetRef ref, Tournament tournament) {
    final config = getConfigForType(tournament.t_type);
    // Show a temporary full-screen overlay with ReportsTab which will trigger PDF export
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text('Звіт: ${tournament.t_name}'),
          ),
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: ReportsTab(
              tournament: tournament,
              config: config,
            ),
          ),
        ),
      ),
    );
  }
}
