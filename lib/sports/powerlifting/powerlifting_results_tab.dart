import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'powerlifting_data.dart';
import 'powerlifting_providers.dart';
import 'powerlifting_scoring.dart';
import 'powerlifting_service.dart';

class PowerliftingResultsTab extends ConsumerStatefulWidget {
  final int tId;
  const PowerliftingResultsTab({super.key, required this.tId});

  @override
  ConsumerState<PowerliftingResultsTab> createState() =>
      _PowerliftingResultsTabState();
}

class _PowerliftingResultsTabState
    extends ConsumerState<PowerliftingResultsTab> {
  bool _loading = true;
  List<PowerliftingAthlete> _athletes = [];
  Map<int, Map<String, ({double kg, bool good})>> _attempts = {};
  int? _hoveredRow;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final plSvc = ref.read(powerliftingServiceProvider);
    final athletes = await loadPowerliftingAthletesW(ref, widget.tId);
    final attempts = await plSvc.getAttempts(widget.tId);
    if (!mounted) return;
    setState(() {
      _athletes = athletes;
      _attempts = attempts;
      _loading = false;
    });
  }

  Future<void> _editResult(PowerliftingAthlete a) async {
    final attempts = _attempts[a.playerId] ?? {};
    final catCtrl = ValueNotifier<String?>(
        kPowerliftingCategories.contains(a.category) ? a.category : null);
    final weightCtrl = TextEditingController(
        text: a.bodyWeight > 0 ? a.bodyWeight.toStringAsFixed(1) : '');
    final lotCtrl =
        TextEditingController(text: a.lot > 0 ? a.lot.toString() : '');

    final kgCtrls = <String, TextEditingController>{};
    final goodFlags = <String, bool>{};
    for (final key in PowerliftingService.allAttemptKeys) {
      final at = attempts[key];
      kgCtrls[key] = TextEditingController(
          text: at != null ? _fmt(at.kg) : '');
      goodFlags[key] = at?.good ?? true;
    }

    Widget liftSection(String title, List<String> keys) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Text(title,
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        ...keys.asMap().entries.map((e) {
          final key = e.value;
          return StatefulBuilder(builder: (ctx, setRow) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                SizedBox(
                    width: 70,
                    child: Text('Підхід ${e.key + 1}',
                        style: const TextStyle(fontSize: 13))),
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: kgCtrls[key],
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'кг',
                        border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 12),
                ChoiceChip(
                  label: const Text('✓'),
                  selected: goodFlags[key]!,
                  selectedColor: Colors.green.shade200,
                  onSelected: (_) => setRow(() => goodFlags[key] = true),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('✗'),
                  selected: !goodFlags[key]!,
                  selectedColor: Colors.red.shade200,
                  onSelected: (_) => setRow(() => goodFlags[key] = false),
                ),
              ]),
            );
          });
        }),
      ]);
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(a.playerName, style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ValueListenableBuilder<String?>(
                valueListenable: catCtrl,
                builder: (ctx, value, _) => DropdownButtonFormField<String>(
                  value: value,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Вагова категорія',
                      border: OutlineInputBorder()),
                  items: kPowerliftingCategories
                      .map((c) =>
                          DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => catCtrl.value = v,
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: weightCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Власна вага (кг)',
                        border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: lotCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                        labelText: 'Жереб', border: OutlineInputBorder()),
                  ),
                ),
              ]),
              liftSection('Присідання', PowerliftingService.squatKeys),
              liftSection('Жим лежачи', PowerliftingService.benchKeys),
              liftSection('Станова тяга', PowerliftingService.deadliftKeys),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Скасувати')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Зберегти')),
        ],
      ),
    );

    if (saved == true) {
      final svc = ref.read(powerliftingServiceProvider);
      if (catCtrl.value != null) {
        await svc.savePlayerCategory(
            playerId: a.playerId, tId: widget.tId, category: catCtrl.value!);
      }
      final weight = double.tryParse(weightCtrl.text.replaceAll(',', '.'));
      if (weight != null) {
        await svc.savePlayerWeight(
            playerId: a.playerId, tId: widget.tId, weight: weight);
      }
      final lot = int.tryParse(lotCtrl.text);
      if (lot != null) {
        await svc.savePlayerLot(
            playerId: a.playerId, tId: widget.tId, lot: lot);
      }
      for (final key in PowerliftingService.allAttemptKeys) {
        final kg = double.tryParse(kgCtrls[key]!.text.replaceAll(',', '.')) ?? 0;
        await svc.saveAttempt(
            tId: widget.tId,
            playerId: a.playerId,
            attemptKey: key,
            kg: kg,
            good: goodFlags[key]!);
      }
      await _loadData();
    }

    catCtrl.dispose();
    weightCtrl.dispose();
    lotCtrl.dispose();
    for (final c in kgCtrls.values) {
      c.dispose();
    }
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_athletes.isEmpty) {
      return const Center(
          child: Text('Додайте гравців для введення результатів'));
    }

    final sorted = List.of(_athletes)
      ..sort((a, b) {
        final catA = kPowerliftingCategories.indexOf(a.category);
        final catB = kPowerliftingCategories.indexOf(b.category);
        if (catA != catB) return (catA == -1 ? 99 : catA).compareTo(catB == -1 ? 99 : catB);
        return b.total.compareTo(a.total);
      });

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          side: BorderSide(color: Colors.grey.shade300, width: 1),
          borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('Особисті результати',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: sorted.length + 1,
              separatorBuilder: (ctx, i) =>
                  Divider(height: 1, color: Colors.grey.shade200),
              itemBuilder: (ctx, i) {
                if (i == 0) return _buildHeader();
                final a = sorted[i - 1];
                return MouseRegion(
                  onEnter: (_) => setState(() => _hoveredRow = i),
                  onExit: (_) => setState(() => _hoveredRow = null),
                  child: InkWell(
                    onTap: () => _editResult(a),
                    child: Container(
                      color: _hoveredRow == i ? Colors.indigo.shade50 : null,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      child: Row(children: [
                        Expanded(flex: 3, child: Text(a.playerName)),
                        Expanded(
                            flex: 2,
                            child: Text(a.teamName,
                                style: TextStyle(color: Colors.grey.shade700))),
                        SizedBox(
                            width: 80,
                            child: Text(a.category,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600))),
                        SizedBox(
                            width: 48,
                            child: Text(a.bodyWeight > 0 ? _fmt(a.bodyWeight) : '',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 12))),
                        _liftCell(a.bestSquat),
                        _liftCell(a.bestBench),
                        _liftCell(a.bestDeadlift),
                        SizedBox(
                            width: 60,
                            child: Text(
                                a.squatValid ? _fmt(a.total) : '—',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold))),
                        const SizedBox(width: 8),
                        Icon(Icons.edit, size: 16, color: Colors.indigo.shade300),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _liftCell(double v) => SizedBox(
      width: 46,
      child: Text(v > 0 ? _fmt(v) : '0',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 12,
              color: v > 0 ? Colors.black87 : Colors.red.shade400)));

  Widget _buildHeader() => Container(
        color: Colors.grey.shade100,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: const Row(children: [
          Expanded(
              flex: 3,
              child: Text('Гравець',
                  style: TextStyle(fontWeight: FontWeight.bold))),
          Expanded(
              flex: 2,
              child: Text('Команда',
                  style: TextStyle(fontWeight: FontWeight.bold))),
          SizedBox(
              width: 80,
              child: Text('Категорія',
                  style: TextStyle(fontWeight: FontWeight.bold))),
          SizedBox(
              width: 48,
              child: Text('Вага',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold))),
          SizedBox(
              width: 46,
              child: Text('Прис',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold))),
          SizedBox(
              width: 46,
              child: Text('Жим',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold))),
          SizedBox(
              width: 46,
              child: Text('Тяга',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold))),
          SizedBox(
              width: 60,
              child: Text('Сума',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontWeight: FontWeight.bold))),
          SizedBox(width: 24),
        ]),
      );
}
