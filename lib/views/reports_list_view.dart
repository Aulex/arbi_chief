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

        Tournament? selectedTournament = tournaments.first;

        showDialog(
          context: context,
          builder: (ctx) {
            return StatefulBuilder(
              builder: (ctx, setST) {
                return AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: Row(
                    children: [
                      Icon(icon, color: iconColor, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  content: SizedBox(
                    width: 400,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Оберіть турнір:',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<Tournament>(
                          value: selectedTournament,
                          isExpanded: true,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          items: tournaments.map((t) => DropdownMenuItem<Tournament>(
                            value: t,
                            child: Text(t.t_name, overflow: TextOverflow.ellipsis),
                          )).toList(),
                          onChanged: (v) {
                            setST(() => selectedTournament = v);
                          },
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Скасувати'),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: selectedTournament == null
                          ? null
                          : () {
                              Navigator.pop(ctx);
                              _generateReport(context, ref, selectedTournament!);
                            },
                      child: const Text('OK'),
                    ),
                  ],
                );
              },
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
              autoExport: true,
            ),
          ),
        ),
      ),
    );
  }
}
