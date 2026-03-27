import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../viewmodels/player_viewmodel.dart';
import '../../viewmodels/team_viewmodel.dart';
import 'powerlifting_providers.dart';

class PowerliftingResultsTab extends ConsumerStatefulWidget {
  final int tId;
  const PowerliftingResultsTab({super.key, required this.tId});

  @override
  ConsumerState<PowerliftingResultsTab> createState() => _PowerliftingResultsTabState();
}

class _PowerliftingResultsTabState extends ConsumerState<PowerliftingResultsTab> {
  bool _loading = true;
  List<({int playerId, String playerName, int teamId, String teamName})> _players = [];
  Map<int, int> _places = {};
  Map<int, String> _categories = {};
  Map<int, double> _weights = {};
  int? _hoveredRow;

  @override
  void initState() { super.initState(); _loadData(); }

  Future<void> _loadData() async {
    final playerSvc = ref.read(playerServiceProvider);
    final teamSvc = ref.read(teamServiceProvider);
    final plSvc = ref.read(powerliftingServiceProvider);

    final playerTeamsMap = await teamSvc.getPlayerTeamsMap(widget.tId);
    final allPlayers = await playerSvc.getAllPlayers();

    final playersList = <({int playerId, String playerName, int teamId, String teamName})>[];
    for (final entry in playerTeamsMap.entries) {
      final pId = entry.key;
      final team = entry.value;
      final pInfo = allPlayers.where((p) => p.player_id == pId).firstOrNull;
      if (pInfo != null) {
        final name = '${pInfo.player_surname ?? ''} ${pInfo.player_name ?? ''} ${pInfo.player_lastname ?? ''}'.trim();
        playersList.add((playerId: pId, playerName: name, teamId: team.team_id!, teamName: team.team_name));
      }
    }

    final places = await plSvc.getPlayerPlaces(widget.tId);
    final categories = await plSvc.getPlayerCategories(widget.tId);
    final weights = await plSvc.getPlayerWeights(widget.tId);
    setState(() { _players = playersList; _places = places; _categories = categories; _weights = weights; _loading = false; });
  }

  Future<void> _editResult(int playerId, int teamId, String playerName, int? currentPlace, String? currentCategory, double? currentWeight) async {
    final placeCtrl = TextEditingController(text: currentPlace?.toString() ?? '');
    final catCtrl = TextEditingController(text: currentCategory ?? '');
    final weightCtrl = TextEditingController(text: currentWeight?.toStringAsFixed(1) ?? '');
    final existingCategories = _categories.values.toSet().toList()..sort();

    final result = await showDialog<({int place, String category, double? weight})?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Результат\n$playerName', style: const TextStyle(fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: placeCtrl, keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Зайняте місце (1, 2, 3...)', border: OutlineInputBorder()), autofocus: true),
          const SizedBox(height: 12),
          Autocomplete<String>(
            initialValue: catCtrl.value,
            optionsBuilder: (v) => v.text.isEmpty ? existingCategories : existingCategories.where((c) => c.toLowerCase().contains(v.text.toLowerCase())),
            fieldViewBuilder: (ctx, ctrl, focusNode, onSubmit) {
              ctrl.text = catCtrl.text;
              return TextField(controller: ctrl, focusNode: focusNode,
                decoration: const InputDecoration(labelText: 'Вагова категорія', hintText: 'напр. до 75 кг', border: OutlineInputBorder()),
                onChanged: (v) => catCtrl.text = v);
            },
            onSelected: (v) => catCtrl.text = v,
          ),
          const SizedBox(height: 12),
          TextField(controller: weightCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Вага спортсмена (кг)', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Скасувати')),
          ElevatedButton(onPressed: () {
            final place = int.tryParse(placeCtrl.text);
            if (place != null) Navigator.pop(ctx, (place: place, category: catCtrl.text.trim(), weight: double.tryParse(weightCtrl.text)));
          }, child: const Text('Зберегти')),
        ],
      ),
    );

    placeCtrl.dispose(); catCtrl.dispose(); weightCtrl.dispose();
    if (result != null) {
      final svc = ref.read(powerliftingServiceProvider);
      await svc.savePlayerPlace(tId: widget.tId, playerId: playerId, teamId: teamId, place: result.place);
      if (result.category.isNotEmpty) {
        await svc.savePlayerCategory(playerId: playerId, tId: widget.tId, category: result.category);
      }
      if (result.weight != null) {
        await svc.savePlayerWeight(playerId: playerId, tId: widget.tId, weight: result.weight!);
      }
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_players.isEmpty) return const Center(child: Text('Додайте гравців для введення результатів'));

    final sortedPlayers = List.of(_players)..sort((a, b) {
      final pA = _places[a.playerId], pB = _places[b.playerId];
      if (pA != null && pB != null) return pA.compareTo(pB);
      if (pA != null) return -1;
      if (pB != null) return 1;
      return a.playerName.compareTo(b.playerName);
    });

    return Card(elevation: 0, shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey.shade300, width: 1), borderRadius: BorderRadius.circular(8)),
      child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Особисті результати', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const Spacer(), IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
        ]),
        const SizedBox(height: 12),
        Expanded(child: ListView.separated(
          itemCount: sortedPlayers.length + 1,
          separatorBuilder: (ctx, i) => Divider(height: 1, color: Colors.grey.shade200),
          itemBuilder: (ctx, i) {
            if (i == 0) return _buildHeader();
            final p = sortedPlayers[i - 1];
            final place = _places[p.playerId];
            final category = _categories[p.playerId];
            final weight = _weights[p.playerId];
            return MouseRegion(
              onEnter: (_) => setState(() => _hoveredRow = i), onExit: (_) => setState(() => _hoveredRow = null),
              child: InkWell(
                onTap: () => _editResult(p.playerId, p.teamId, p.playerName, place, category, weight),
                child: Container(color: _hoveredRow == i ? Colors.indigo.shade50 : null, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    SizedBox(width: 50, child: Text(place?.toString() ?? '-', style: TextStyle(fontWeight: place != null ? FontWeight.bold : FontWeight.normal, fontSize: 16))),
                    Expanded(flex: 2, child: Text(p.playerName)),
                    Expanded(flex: 1, child: Text(category ?? '', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
                    SizedBox(width: 60, child: Text(weight != null ? '${weight.toStringAsFixed(1)}' : '', style: TextStyle(fontSize: 12, color: Colors.grey.shade600), textAlign: TextAlign.center)),
                    Expanded(flex: 2, child: Text(p.teamName, style: TextStyle(color: Colors.grey.shade700))),
                    Icon(Icons.edit, size: 16, color: Colors.indigo.shade300),
                  ]))));
          },
        )),
      ])));
  }

  Widget _buildHeader() => Container(color: Colors.grey.shade100, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: const Row(children: [SizedBox(width: 50, child: Text('Місце', style: TextStyle(fontWeight: FontWeight.bold))),
      Expanded(flex: 2, child: Text('Гравець', style: TextStyle(fontWeight: FontWeight.bold))),
      Expanded(flex: 1, child: Text('Категорія', style: TextStyle(fontWeight: FontWeight.bold))),
      SizedBox(width: 60, child: Text('Вага', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
      Expanded(flex: 2, child: Text('Команда', style: TextStyle(fontWeight: FontWeight.bold))), SizedBox(width: 16)]));
}
