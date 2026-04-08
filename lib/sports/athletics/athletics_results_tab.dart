import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../viewmodels/player_viewmodel.dart';
import '../../viewmodels/team_viewmodel.dart';
import 'athletics_providers.dart';

class AthleticsResultsTab extends ConsumerStatefulWidget {
  final int tId;
  const AthleticsResultsTab({super.key, required this.tId});

  @override
  ConsumerState<AthleticsResultsTab> createState() => _AthleticsResultsTabState();
}

class _AthleticsResultsTabState extends ConsumerState<AthleticsResultsTab> {
  bool _loading = true;
  List<({int playerId, String playerName, int teamId, String teamName})> _players = [];
  Map<int, int> _places = {};
  Map<int, String> _categories = {};
  int? _hoveredRow;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final playerSvc = ref.read(playerServiceProvider);
    final teamSvc = ref.read(teamServiceProvider);
    final athSvc = ref.read(athleticsServiceProvider);

    final playerTeamsMap = await teamSvc.getPlayerTeamsMap(widget.tId);
    final allPlayers = await playerSvc.getAllPlayers();

    final playersList = <({int playerId, String playerName, int teamId, String teamName})>[];
    for (final entry in playerTeamsMap.entries) {
      final pId = entry.key;
      final team = entry.value;

      final pInfo = allPlayers.where((p) => p.player_id == pId).firstOrNull;
      if (pInfo != null) {
        final name = '${pInfo.player_surname ?? ''} ${pInfo.player_name ?? ''} ${pInfo.player_lastname ?? ''}'.trim();
        playersList.add((
          playerId: pId,
          playerName: name,
          teamId: team.team_id!,
          teamName: team.team_name,
        ));
      }
    }

    final places = await athSvc.getPlayerPlaces(widget.tId);
    final categories = await athSvc.getPlayerCategories(widget.tId);

    setState(() {
      _players = playersList;
      _places = places;
      _categories = categories;
      _loading = false;
    });
  }

  Future<void> _editResult(int playerId, int teamId, String playerName, int? currentPlace, String? currentCategory) async {
    final placeCtrl = TextEditingController(text: currentPlace?.toString() ?? '');
    final catCtrl = TextEditingController(text: currentCategory ?? '');

    // Collect existing categories for suggestions
    final existingCategories = _categories.values.toSet().toList()..sort();

    final result = await showDialog<({int place, String category})?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Результат\n$playerName', style: const TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: placeCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Зайняте місце (1, 2, 3...)',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            Autocomplete<String>(
              initialValue: catCtrl.value,
              optionsBuilder: (textEditingValue) {
                if (textEditingValue.text.isEmpty) return existingCategories;
                return existingCategories.where(
                  (c) => c.toLowerCase().contains(textEditingValue.text.toLowerCase()),
                );
              },
              fieldViewBuilder: (ctx, ctrl, focusNode, onSubmit) {
                ctrl.text = catCtrl.text;
                return TextField(
                  controller: ctrl,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                    labelText: 'Категорія (вікова/статева)',
                    hintText: 'напр. Чоловіки, Жінки 18-25',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => catCtrl.text = v,
                );
              },
              onSelected: (v) => catCtrl.text = v,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Скасувати')),
          ElevatedButton(
            onPressed: () {
              final place = int.tryParse(placeCtrl.text);
              if (place != null) {
                Navigator.pop(ctx, (place: place, category: catCtrl.text.trim()));
              }
            },
            child: const Text('Зберегти'),
          ),
        ],
      ),
    );

    placeCtrl.dispose();
    catCtrl.dispose();
    if (result != null) {
      final svc = ref.read(athleticsServiceProvider);
      await svc.savePlayerPlace(
        tId: widget.tId, playerId: playerId, teamId: teamId, place: result.place,
      );
      if (result.category.isNotEmpty) {
        await svc.savePlayerCategory(
          playerId: playerId, tId: widget.tId, category: result.category,
        );
      }
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_players.isEmpty) {
      return const Center(child: Text('Додайте гравців для введення результатів'));
    }

    final sortedPlayers = List.of(_players);
    sortedPlayers.sort((a, b) {
      final placeA = _places[a.playerId];
      final placeB = _places[b.playerId];
      if (placeA != null && placeB != null) return placeA.compareTo(placeB);
      if (placeA != null) return -1;
      if (placeB != null) return 1;
      return a.playerName.compareTo(b.playerName);
    });

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade300, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Особисті результати', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: sortedPlayers.length + 1,
                separatorBuilder: (ctx, i) => Divider(height: 1, color: Colors.grey.shade200),
                itemBuilder: (ctx, i) {
                  if (i == 0) return _buildHeader();
                  final p = sortedPlayers[i - 1];
                  final place = _places[p.playerId];
                  final category = _categories[p.playerId];

                  return MouseRegion(
                    onEnter: (_) => setState(() => _hoveredRow = i),
                    onExit: (_) => setState(() => _hoveredRow = null),
                    child: InkWell(
                      onTap: () => _editResult(p.playerId, p.teamId, p.playerName, place, category),
                      child: Container(
                        color: _hoveredRow == i ? Colors.indigo.shade50 : null,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            SizedBox(width: 50, child: Text(place?.toString() ?? '-', style: TextStyle(fontWeight: place != null ? FontWeight.bold : FontWeight.normal, fontSize: 16))),
                            Expanded(flex: 2, child: Text(p.playerName)),
                            Expanded(flex: 1, child: Text(category ?? '', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
                            Expanded(flex: 2, child: Text(p.teamName, style: TextStyle(color: Colors.grey.shade700))),
                            Icon(Icons.edit, size: 16, color: Colors.indigo.shade300),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: Colors.grey.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: const Row(
        children: [
          SizedBox(width: 50, child: Text('Місце', style: TextStyle(fontWeight: FontWeight.bold))),
          Expanded(flex: 2, child: Text('Гравець', style: TextStyle(fontWeight: FontWeight.bold))),
          Expanded(flex: 1, child: Text('Категорія', style: TextStyle(fontWeight: FontWeight.bold))),
          Expanded(flex: 2, child: Text('Команда', style: TextStyle(fontWeight: FontWeight.bold))),
          SizedBox(width: 16),
        ],
      ),
    );
  }
}
