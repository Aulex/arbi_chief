import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'arm_wrestling_providers.dart';
import 'arm_wrestling_scoring.dart';

/// Team standings tab: sum of 3 best placements across 3 different weight
/// categories (lower is better). Per-category individual standings live in
/// the "Усі гравці" tab.
class ArmWrestlingTeamStandingsTab extends ConsumerWidget {
  final int tId;
  const ArmWrestlingTeamStandingsTab({super.key, required this.tId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(armWrestlingStandingsProvider(tId));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Помилка: $e')),
      data: (bundle) => _Body(bundle: bundle),
    );
  }
}

class _Body extends StatelessWidget {
  final ArmWrestlingStandingsBundle bundle;
  const _Body({required this.bundle});

  @override
  Widget build(BuildContext context) {
    if (bundle.teamStandings.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.groups_outlined, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                'Командний залік з\'явиться, коли в категоріях буде ≥ '
                '$minParticipantsForCategory учасників і будуть зіграні матчі.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: Colors.indigo.shade200),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.groups_outlined, color: Colors.indigo.shade700, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Командний залік',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo.shade900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Сума очок 3-х кращих учасників з 3-х різних вагових категорій '
                '(менше — краще). Відсутні учасники штрафуються за правилами.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              Table(
                columnWidths: const {
                  0: FixedColumnWidth(40),
                  1: FlexColumnWidth(2),
                  2: FixedColumnWidth(70),
                  3: FlexColumnWidth(3),
                },
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  TableRow(
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
                    ),
                    children: [
                      _headerCell('М'),
                      _headerCell('Команда'),
                      _headerCell('Очки', align: TextAlign.center),
                      _headerCell('Деталі'),
                    ],
                  ),
                  for (final ts in bundle.teamStandings)
                    TableRow(
                      decoration: BoxDecoration(
                        color: ts.place <= 3
                            ? Colors.amber.withOpacity(0.05 * (4 - ts.place))
                            : null,
                      ),
                      children: [
                        _dataCell('${ts.place}', fontWeight: FontWeight.bold),
                        _dataCell(ts.teamName),
                        _dataCell(
                          '${ts.totalPoints}',
                          align: TextAlign.center,
                          fontWeight: FontWeight.bold,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: ts.contributors.map((c) {
                              return Container(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.indigo.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${c.categoryLabel}: ${c.place}-е м.',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.indigo.shade800),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerCell(String text, {TextAlign align = TextAlign.left}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade700,
        ),
      ),
    );
  }

  Widget _dataCell(
    String text, {
    TextAlign align = TextAlign.left,
    FontWeight fontWeight = FontWeight.normal,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(fontSize: 13, fontWeight: fontWeight, color: color),
      ),
    );
  }
}
