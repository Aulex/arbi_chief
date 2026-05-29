import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'powerlifting_data.dart';
import 'powerlifting_scoring.dart';

class PowerliftingIndividualStandingsTab extends ConsumerStatefulWidget {
  final int tId;
  const PowerliftingIndividualStandingsTab({super.key, required this.tId});

  @override
  ConsumerState<PowerliftingIndividualStandingsTab> createState() =>
      _PowerliftingIndividualStandingsTabState();
}

class _PowerliftingIndividualStandingsTabState
    extends ConsumerState<PowerliftingIndividualStandingsTab> {
  bool _loading = true;
  List<PowerliftingIndividualResult> _results = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final athletes = await loadPowerliftingAthletesW(ref, widget.tId);
    final results = calculateIndividualStandings(athletes);
    if (!mounted) return;
    setState(() {
      _results = results;
      _loading = false;
    });
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_results.isEmpty) {
      return const Center(
          child: Text('Вкажіть категорії та результати учасників.'));
    }

    // Group by display group, in canonical category order.
    final byGroup = <String, List<PowerliftingIndividualResult>>{};
    for (final r in _results) {
      byGroup.putIfAbsent(r.group, () => []).add(r);
    }
    final orderedGroups = kPowerliftingCategories
        .where((c) => byGroup.containsKey(c))
        .toList();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          side: BorderSide(color: Colors.grey.shade300, width: 1),
          borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('Особистий залік',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                for (final group in orderedGroups)
                  _buildGroup(group, byGroup[group]!),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildGroup(String group, List<PowerliftingIndividualResult> rows) {
    final useWilks = rows.first.useWilks;
    rows.sort((a, b) {
      if (a.place == null && b.place == null) {
        return b.athlete.total.compareTo(a.athlete.total);
      }
      if (a.place == null) return 1;
      if (b.place == null) return -1;
      return a.place!.compareTo(b.place!);
    });
    final notHeld = rows.every((r) => r.place == null) &&
        rows.first.statusNote != null &&
        rows.first.statusNote!.contains('не проводиться');

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(group,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          if (useWilks)
            const Chip(
                label: Text('Вілкс', style: TextStyle(fontSize: 11)),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero),
          if (notHeld)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text('— не проводиться (менше $kMinCategorySize)',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange.shade800,
                      fontStyle: FontStyle.italic)),
            ),
        ]),
        const SizedBox(height: 6),
        Container(
          color: Colors.grey.shade100,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(children: [
            const SizedBox(
                width: 44,
                child: Text('Місце',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 12))),
            const Expanded(
                flex: 3,
                child: Text('Гравець',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 12))),
            const Expanded(
                flex: 2,
                child: Text('Команда',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 12))),
            const SizedBox(
                width: 44,
                child: Text('Вага',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 12))),
            const SizedBox(
                width: 56,
                child: Text('Сума',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 12))),
            if (useWilks)
              const SizedBox(
                  width: 64,
                  child: Text('Вілкс',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 12))),
          ]),
        ),
        ...rows.map((r) => _buildRow(r, useWilks)),
      ]),
    );
  }

  Widget _buildRow(PowerliftingIndividualResult r, bool useWilks) {
    final a = r.athlete;
    final placed = r.place != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(color: Colors.grey.shade200, width: 1))),
      child: Row(children: [
        SizedBox(
            width: 44,
            child: Text(placed ? '${r.place}' : '—',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: placed ? Colors.black87 : Colors.grey))),
        Expanded(
          flex: 3,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.playerName),
            if (!placed && r.statusNote != null)
              Text(r.statusNote!,
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.red.shade400,
                      fontStyle: FontStyle.italic)),
          ]),
        ),
        Expanded(
            flex: 2,
            child: Text(a.teamName,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13))),
        SizedBox(
            width: 44,
            child: Text(a.bodyWeight > 0 ? _fmt(a.bodyWeight) : '',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12))),
        SizedBox(
            width: 56,
            child: Text(a.squatValid ? _fmt(a.total) : '0',
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.bold))),
        if (useWilks)
          SizedBox(
              width: 64,
              child: Text(a.squatValid ? a.wilks.toStringAsFixed(1) : '—',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 12, color: Colors.indigo.shade700))),
      ]),
    );
  }
}
