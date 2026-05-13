import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'athletics_model.dart';
import 'athletics_providers.dart';

/// Displays team standings for athletics competitions.
class AthleticsTeamStandingsTab extends ConsumerStatefulWidget {
  final int tId;

  const AthleticsTeamStandingsTab({super.key, required this.tId});

  @override
  ConsumerState<AthleticsTeamStandingsTab> createState() =>
      _AthleticsTeamStandingsTabState();
}

class _AthleticsTeamStandingsTabState
    extends ConsumerState<AthleticsTeamStandingsTab> {
  List<AthleticsTeamStanding> _standings = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStandings();
  }

  Future<void> _loadStandings() async {
    setState(() => _loading = true);
    final svc = ref.read(athleticsServiceProvider);
    final customCoefficients = await svc.getCustomCoefficients(widget.tId);
    final standings = await svc.getTeamStandings(
      widget.tId, customCoefficients: customCoefficients,
    );
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
              'Командний залік — Легка атлетика',
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
          'Очки = сума місць (2 чоловіки + 1 жінка з різних вікових категорій). '
          'Менше очок = краще. '
          'Якщо команда не представлена у категорії, нараховується штраф = '
          'кількість учасників у найбільшій категорії + 1.',
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
                Text('Ж35', style: TextStyle(fontWeight: FontWeight.bold)),
            numeric: true),
        DataColumn(
            label:
                Text('Ж49', style: TextStyle(fontWeight: FontWeight.bold)),
            numeric: true),
        DataColumn(
            label:
                Text('Ж50', style: TextStyle(fontWeight: FontWeight.bold)),
            numeric: true),
        DataColumn(
            label: Text('Залік',
                style: TextStyle(fontWeight: FontWeight.bold))),
        DataColumn(
            label: Text('Σ віку',
                style: TextStyle(fontWeight: FontWeight.bold)),
            numeric: true),
        DataColumn(
            label: Text('Очки',
                style: TextStyle(fontWeight: FontWeight.bold)),
            numeric: true),
      ],
      rows: _standings.map((s) {
        final m35 =
            _formatPlaces(s.categoryPlaces[AthleticsCategory.m35] ?? []);
        final m49 =
            _formatPlaces(s.categoryPlaces[AthleticsCategory.m49] ?? []);
        final m50 =
            _formatPlaces(s.categoryPlaces[AthleticsCategory.m50] ?? []);
        final f35 =
            _formatPlaces(s.categoryPlaces[AthleticsCategory.f35] ?? []);
        final f49 =
            _formatPlaces(s.categoryPlaces[AthleticsCategory.f49] ?? []);
        final f50 =
            _formatPlaces(s.categoryPlaces[AthleticsCategory.f50] ?? []);

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
            DataCell(Text(f35)),
            DataCell(Text(f49)),
            DataCell(Text(f50)),
            DataCell(Text(
              s.scoringPlaces.join('+'),
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.indigo.shade700,
                  fontWeight: FontWeight.w500),
            )),
            DataCell(Text(
              s.sumOfAges > 0 ? '${s.sumOfAges}' : '—',
            )),
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
}
