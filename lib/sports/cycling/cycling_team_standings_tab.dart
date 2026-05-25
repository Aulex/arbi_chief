import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'cycling_model.dart';
import 'cycling_providers.dart';

/// Displays team standings for cycling competitions.
class CyclingTeamStandingsTab extends ConsumerStatefulWidget {
  final int tId;

  const CyclingTeamStandingsTab({super.key, required this.tId});

  @override
  ConsumerState<CyclingTeamStandingsTab> createState() =>
      _CyclingTeamStandingsTabState();
}

class _CyclingTeamStandingsTabState
    extends ConsumerState<CyclingTeamStandingsTab> {
  List<CyclingTeamStanding> _standings = [];
  int _penaltyPlace = 0;
  CyclingCategory? _largestCategory;
  bool _loading = true;
  int? _hoveredRow;

  @override
  void initState() {
    super.initState();
    _loadStandings();
  }

  Future<void> _loadStandings() async {
    setState(() => _loading = true);
    final svc = ref.read(cyclingServiceProvider);
    final result = await svc.getTeamStandings(widget.tId);
    if (mounted) {
      setState(() {
        _standings = result.standings;
        _penaltyPlace = result.penaltyPlace;
        _largestCategory = result.largestCategory;
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
              'Командний залік — Велоспорт',
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
          _largestCategory != null && _penaltyPlace > 1
              ? 'Очки = сума місць (2 чоловіки + 1 жінка з різних вікових '
                  'категорій). Менше очок = краще. Якщо команда не '
                  'представлена у категорії, нараховується штраф = '
                  '$_penaltyPlace (${_largestCategory!.label}: '
                  '${_penaltyPlace - 1} учасників + 1).'
              : 'Очки = сума місць (2 чоловіки + 1 жінка з різних вікових '
                  'категорій). Менше очок = краще. Якщо команда не '
                  'представлена у категорії, нараховується штраф = '
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
            clipBehavior: Clip.antiAlias,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  child: SingleChildScrollView(
                    child: _buildTable(constraints.maxWidth),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTable(double availableWidth) {
    final headerStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w800,
      color: Colors.grey.shade900,
    );
    final cellStyle = const TextStyle(fontSize: 13);

    Widget headerCell(String text, {int? flex, double? width, TextAlign align = TextAlign.center}) {
      final w = Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        alignment: align == TextAlign.left
            ? Alignment.centerLeft
            : align == TextAlign.right
                ? Alignment.centerRight
                : Alignment.center,
        child: Text(text, style: headerStyle, textAlign: align),
      );
      if (flex != null) return Expanded(flex: flex, child: w);
      return SizedBox(width: width, child: w);
    }

    Widget dataCell(Widget child, {int? flex, double? width, AlignmentGeometry align = Alignment.center}) {
      final w = Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        alignment: align,
        child: child,
      );
      if (flex != null) return Expanded(flex: flex, child: w);
      return SizedBox(width: width, child: w);
    }

    return SizedBox(
      width: availableWidth,
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade400, width: 1.5),
              ),
            ),
            child: Row(
              children: [
                headerCell('М', width: 48),
                headerCell('Команда', flex: 3, align: TextAlign.left),
                headerCell('Ч35', flex: 1),
                headerCell('Ч49', flex: 1),
                headerCell('Ч50', flex: 1),
                headerCell('Ж35', flex: 1),
                headerCell('Ж49', flex: 1),
                headerCell('Залік', flex: 2),
                headerCell('Σ віку', width: 64),
                headerCell('Очки', width: 64),
              ],
            ),
          ),
          for (int i = 0; i < _standings.length; i++)
            _buildStandingRow(i, _standings[i], dataCell, cellStyle),
        ],
      ),
    );
  }

  Widget _buildStandingRow(
    int index,
    CyclingTeamStanding s,
    Widget Function(Widget, {int? flex, double? width, AlignmentGeometry align}) dataCell,
    TextStyle cellStyle,
  ) {
    final isHovered = _hoveredRow == index;
    final m35 = _formatPlaces(s.categoryPlaces[CyclingCategory.m35] ?? []);
    final m49 = _formatPlaces(s.categoryPlaces[CyclingCategory.m49] ?? []);
    final m50 = _formatPlaces(s.categoryPlaces[CyclingCategory.m50] ?? []);
    final f35 = _formatPlaces(s.categoryPlaces[CyclingCategory.f35] ?? []);
    final f49 = _formatPlaces(s.categoryPlaces[CyclingCategory.f49] ?? []);

    final baseBg = s.place == 1
        ? Colors.amber.shade50
        : s.place == 2
            ? Colors.grey.shade50
            : s.place == 3
                ? Colors.brown.shade50
                : null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredRow = index),
      onExit: (_) {
        if (_hoveredRow == index) setState(() => _hoveredRow = null);
      },
      child: Container(
        decoration: BoxDecoration(
          color: isHovered ? Colors.indigo.shade100 : baseBg,
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade200, width: 1),
          ),
        ),
        child: Row(
          children: [
            dataCell(
              Text(
                '${s.place}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: s.place <= 3 ? FontWeight.bold : FontWeight.normal,
                  color: s.place == 1
                      ? Colors.amber.shade800
                      : s.place == 2
                          ? Colors.grey.shade600
                          : s.place == 3
                              ? Colors.brown
                              : null,
                ),
              ),
              width: 48,
            ),
            dataCell(
              Text(s.teamName,
                  style: cellStyle.copyWith(fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis),
              flex: 3,
              align: Alignment.centerLeft,
            ),
            dataCell(Text(m35, style: cellStyle), flex: 1),
            dataCell(Text(m49, style: cellStyle), flex: 1),
            dataCell(Text(m50, style: cellStyle), flex: 1),
            dataCell(Text(f35, style: cellStyle), flex: 1),
            dataCell(Text(f49, style: cellStyle), flex: 1),
            dataCell(
              Text(
                s.scoringPlaces.join('+'),
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.indigo.shade700,
                    fontWeight: FontWeight.w500),
              ),
              flex: 2,
            ),
            dataCell(
              Text(s.sumOfAges > 0 ? '${s.sumOfAges}' : '—', style: cellStyle),
              width: 64,
            ),
            dataCell(
              Text(
                '${s.totalPoints}',
                style: cellStyle.copyWith(fontWeight: FontWeight.bold),
              ),
              width: 64,
            ),
          ],
        ),
      ),
    );
  }

  String _formatPlaces(List<int> places) {
    if (places.isEmpty) return '-';
    return places.join('+');
  }
}
