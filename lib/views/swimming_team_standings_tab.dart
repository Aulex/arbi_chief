import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/swimming_model.dart';
import 'swimming_results_tab.dart';

/// Displays team standings for swimming competitions.
class SwimmingTeamStandingsTab extends ConsumerStatefulWidget {
  final int tId;

  const SwimmingTeamStandingsTab({super.key, required this.tId});

  @override
  ConsumerState<SwimmingTeamStandingsTab> createState() =>
      _SwimmingTeamStandingsTabState();
}

class _SwimmingTeamStandingsTabState
    extends ConsumerState<SwimmingTeamStandingsTab> {
  List<SwimmingTeamStanding> _standings = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStandings();
  }

  Future<void> _loadStandings() async {
    setState(() => _loading = true);
    final svc = ref.read(swimmingServiceProvider);
    final standings = await svc.getTeamStandings(widget.tId);
    if (mounted) {
      setState(() {
        _standings = standings;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_standings.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.emoji_events_outlined,
                size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text('Немає результатів для командного заліку',
                style: TextStyle(color: Colors.grey.shade500)),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _loadStandings,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Оновити'),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Командний залік — Плавання',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _loadStandings,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Оновити'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Очки = сума місць (2×Ч35 + 2×Ч49 + 1×Ч50 + 1×Жін. + Естафета). Менше очок = краще.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: Colors.grey.shade300, width: 1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                child: _buildTable(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTable() {
    return DataTable(
      columnSpacing: 16,
      headingRowColor: WidgetStatePropertyAll(Colors.grey.shade100),
      columns: const [
        DataColumn(
            label:
                Text('М', style: TextStyle(fontWeight: FontWeight.bold))),
        DataColumn(
            label: Text('Команда',
                style: TextStyle(fontWeight: FontWeight.bold))),
        DataColumn(
            label:
                Text('Ч35', style: TextStyle(fontWeight: FontWeight.bold)),
            numeric: true),
        DataColumn(
            label:
                Text('Ч49', style: TextStyle(fontWeight: FontWeight.bold)),
            numeric: true),
        DataColumn(
            label:
                Text('Ч50', style: TextStyle(fontWeight: FontWeight.bold)),
            numeric: true),
        DataColumn(
            label:
                Text('Жін.', style: TextStyle(fontWeight: FontWeight.bold)),
            numeric: true),
        DataColumn(
            label: Text('Естаф.',
                style: TextStyle(fontWeight: FontWeight.bold)),
            numeric: true),
        DataColumn(
            label: Text('Очки',
                style: TextStyle(fontWeight: FontWeight.bold)),
            numeric: true),
      ],
      rows: _standings.map((s) {
        final m35 = _formatPlaces(s.categoryPlaces[SwimmingCategory.m35] ?? []);
        final m49 = _formatPlaces(s.categoryPlaces[SwimmingCategory.m49] ?? []);
        final m50 = _formatPlaces(s.categoryPlaces[SwimmingCategory.m50] ?? []);
        // Best woman place from either f35 or f49
        final f35p = s.categoryPlaces[SwimmingCategory.f35] ?? [];
        final f49p = s.categoryPlaces[SwimmingCategory.f49] ?? [];
        final bestWoman = _bestWomanPlace(f35p, f49p);
        final relay =
            _formatPlaces(s.categoryPlaces[SwimmingCategory.relay] ?? []);

        return DataRow(
          color: s.place <= 3
              ? WidgetStatePropertyAll(
                  s.place == 1
                      ? Colors.amber.shade50
                      : s.place == 2
                          ? Colors.grey.shade50
                          : Colors.brown.shade50,
                )
              : null,
          cells: [
            DataCell(Text(
              '${s.place}',
              style: TextStyle(
                fontWeight:
                    s.place <= 3 ? FontWeight.bold : FontWeight.normal,
                color: s.place == 1
                    ? Colors.amber.shade800
                    : s.place == 2
                        ? Colors.grey.shade600
                        : s.place == 3
                            ? Colors.brown
                            : null,
              ),
            )),
            DataCell(Text(s.teamName,
                style: const TextStyle(fontWeight: FontWeight.w500))),
            DataCell(Text(m35)),
            DataCell(Text(m49)),
            DataCell(Text(m50)),
            DataCell(Text(bestWoman)),
            DataCell(Text(relay)),
            DataCell(Text(
              '${s.totalPoints}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            )),
          ],
        );
      }).toList(),
    );
  }

  String _formatPlaces(List<int> places) {
    if (places.isEmpty) return '-';
    return places.join('+');
  }

  String _bestWomanPlace(List<int> f35, List<int> f49) {
    final all = <int>[];
    if (f35.isNotEmpty) all.add(f35.first);
    if (f49.isNotEmpty) all.add(f49.first);
    if (all.isEmpty) return '-';
    all.sort();
    return '${all.first}';
  }
}
