import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'arm_wrestling_providers.dart';
import 'arm_wrestling_scoring.dart';

/// "Усі гравці" tab: per-category standings with player number, weight,
/// wins/losses. Mirrors the cycling all-participants pattern.
class ArmWrestlingAllPlayersTab extends ConsumerWidget {
  final int tId;
  const ArmWrestlingAllPlayersTab({super.key, required this.tId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(armWrestlingStandingsProvider(tId));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Помилка: $e')),
      data: (bundle) => _Body(tId: tId, bundle: bundle),
    );
  }
}

class _Body extends ConsumerWidget {
  final int tId;
  final ArmWrestlingStandingsBundle bundle;
  const _Body({required this.tId, required this.bundle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasAnyPlayers = bundle.categoryStandings.values.any((l) => l.isNotEmpty);
    if (!hasAnyPlayers) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fitness_center, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                'Немає учасників із призначеною ваговою категорією.\n'
                'Імпортуйте гравців із колонкою «Вага» або призначте категорії вручну.',
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._buildWarnings(context, ref),
          for (final cat in WeightCategory.values) ...[
            _buildCategory(context, ref, cat),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildWarnings(BuildContext context, WidgetRef ref) {
    final out = <Widget>[];
    for (final entry in bundle.validation.entries) {
      final v = entry.value;
      if (v.isValid || v.count == 0) continue;
      out.add(Card(
        color: Colors.orange.shade50,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: Colors.orange.shade200),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${v.label}: ${v.count} учасник(ів) — менше $minParticipantsForCategory. '
                  '${entry.key == WeightCategory.over100.id ? 'Категорія не проводиться.' : 'Учасники мають перейти у важчу категорію.'}',
                  style: TextStyle(color: Colors.orange.shade900, fontSize: 13),
                ),
              ),
              if (entry.key != WeightCategory.over100.id)
                TextButton(
                  onPressed: () async {
                    final svc = ref.read(armWrestlingServiceProvider);
                    await svc.redistributeCategories(tId);
                    ref.invalidate(armWrestlingStandingsProvider(tId));
                  },
                  child: const Text('Перемістити'),
                ),
            ],
          ),
        ),
      ));
      out.add(const SizedBox(height: 8));
    }
    return out;
  }

  Widget _buildCategory(BuildContext context, WidgetRef ref, WeightCategory cat) {
    final standings = bundle.categoryStandings[cat.id] ?? const <ArmWrestlingStanding>[];
    final v = bundle.validation[cat.id];
    final isValid = v?.isValid ?? false;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: isValid ? Colors.grey.shade300 : Colors.red.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: isValid ? Colors.indigo : Colors.grey.shade400,
                  child: Text('${cat.id}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                Text(cat.label,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Text('(${standings.length} учасн.)',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                if (!isValid && standings.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('Не проводиться',
                        style: TextStyle(fontSize: 11, color: Colors.red.shade700)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            if (standings.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('Немає учасників',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
              )
            else
              _StandingsTable(tId: tId, standings: standings, weights: bundle.playerWeights),
          ],
        ),
      ),
    );
  }
}

class _StandingsTable extends ConsumerWidget {
  final int tId;
  final List<ArmWrestlingStanding> standings;
  final Map<int, double> weights;
  const _StandingsTable({required this.tId, required this.standings, required this.weights});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Table(
      columnWidths: const {
        0: FixedColumnWidth(36),  // Place
        1: FixedColumnWidth(48),  // Number
        2: FlexColumnWidth(3),    // Player
        3: FlexColumnWidth(2),    // Team
        4: FixedColumnWidth(70),  // Weight
        5: FixedColumnWidth(50),  // Wins
        6: FixedColumnWidth(50),  // Losses
        7: FixedColumnWidth(50),  // Games
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
          ),
          children: [
            _headerCell('М'),
            _headerCell('№', align: TextAlign.center),
            _headerCell('Учасник'),
            _headerCell('Команда'),
            _headerCell('Вага', align: TextAlign.center),
            _headerCell('П', align: TextAlign.center),
            _headerCell('Пор', align: TextAlign.center),
            _headerCell('Ігри', align: TextAlign.center),
          ],
        ),
        for (final s in standings)
          TableRow(
            decoration: BoxDecoration(
              color: s.place <= 3
                  ? Colors.amber.withOpacity(0.05 * (4 - s.place))
                  : null,
            ),
            children: [
              _dataCell('${s.place}', fontWeight: FontWeight.bold),
              _dataCell(
                s.playerNumber != null ? '${s.playerNumber}' : '—',
                align: TextAlign.center,
                color: s.playerNumber != null ? null : Colors.grey.shade400,
              ),
              _dataCell(s.playerName),
              _dataCell(s.teamName),
              GestureDetector(
                onTap: () =>
                    _editWeight(context, ref, s.playerId, s.playerName, weights[s.playerId]),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        weights[s.playerId] != null
                            ? weights[s.playerId]!.toStringAsFixed(1)
                            : '-',
                        style: TextStyle(
                          fontSize: 13,
                          color: weights[s.playerId] != null ? null : Colors.grey.shade400,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.edit, size: 12, color: Colors.indigo.shade300),
                    ],
                  ),
                ),
              ),
              _dataCell('${s.wins}',
                  align: TextAlign.center,
                  color: s.wins > 0 ? Colors.green.shade700 : null),
              _dataCell('${s.losses}',
                  align: TextAlign.center,
                  color: s.losses > 0 ? Colors.red.shade700 : null),
              _dataCell('${s.gamesPlayed}', align: TextAlign.center),
            ],
          ),
      ],
    );
  }

  Future<void> _editWeight(BuildContext context, WidgetRef ref, int playerId,
      String playerName, double? currentWeight) async {
    final ctrl = TextEditingController(text: currentWeight?.toStringAsFixed(1) ?? '');
    final result = await showDialog<double?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Вага\n$playerName', style: const TextStyle(fontSize: 16)),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
          decoration: const InputDecoration(labelText: 'Вага (кг)', border: OutlineInputBorder()),
          autofocus: true,
          onSubmitted: (_) {
            final w = double.tryParse(ctrl.text);
            if (w != null && w > 0) Navigator.pop(ctx, w);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Скасувати')),
          ElevatedButton(
            onPressed: () {
              final w = double.tryParse(ctrl.text);
              if (w != null && w > 0) Navigator.pop(ctx, w);
            },
            child: const Text('Зберегти'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result != null) {
      final svc = ref.read(armWrestlingServiceProvider);
      await svc.savePlayerWeight(playerId: playerId, tId: tId, weight: result);
      ref.invalidate(armWrestlingStandingsProvider(tId));
    }
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

  Widget _dataCell(String text,
      {TextAlign align = TextAlign.left,
      FontWeight fontWeight = FontWeight.normal,
      Color? color}) {
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
