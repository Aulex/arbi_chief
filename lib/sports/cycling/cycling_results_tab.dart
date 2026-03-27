import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../viewmodels/player_viewmodel.dart';
import '../../viewmodels/team_viewmodel.dart';
import 'cycling_providers.dart';

class CyclingResultsTab extends ConsumerStatefulWidget {
  final int tId;
  const CyclingResultsTab({super.key, required this.tId});

  @override
  ConsumerState<CyclingResultsTab> createState() => _CyclingResultsTabState();
}

class _CyclingResultsTabState extends ConsumerState<CyclingResultsTab> {
  bool _loading = true;
  List<({int playerId, String playerName, int teamId, String teamName})> _players = [];
  Map<int, int> _places = {};
  int? _hoveredRow;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final playerSvc = ref.read(playerServiceProvider);
    final teamSvc = ref.read(teamServiceProvider);
    final cySvc = ref.read(cyclingServiceProvider);

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

    final places = await cySvc.getPlayerPlaces(widget.tId);

    setState(() { _players = playersList; _places = places; _loading = false; });
  }

  Future<void> _editPlace(int playerId, int teamId, String playerName, int? currentPlace) async {
    final controller = TextEditingController(text: currentPlace?.toString() ?? '');
    final result = await showDialog<int?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Місце (результат)\n$playerName', style: const TextStyle(fontSize: 16)),
        content: TextField(
          controller: controller, keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Зайняте місце (1, 2, 3...)', border: OutlineInputBorder()), autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Скасувати')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, int.tryParse(controller.text)), child: const Text('Зберегти')),
        ],
      ),
    );
    controller.dispose();
    if (result != null) {
      await ref.read(cyclingServiceProvider).savePlayerPlace(tId: widget.tId, playerId: playerId, teamId: teamId, place: result);
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
        const Text('Особисті результати', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Expanded(child: ListView.separated(
          itemCount: sortedPlayers.length + 1,
          separatorBuilder: (ctx, i) => Divider(height: 1, color: Colors.grey.shade200),
          itemBuilder: (ctx, i) {
            if (i == 0) return _buildHeader();
            final p = sortedPlayers[i - 1];
            final place = _places[p.playerId];
            return MouseRegion(
              onEnter: (_) => setState(() => _hoveredRow = i), onExit: (_) => setState(() => _hoveredRow = null),
              child: InkWell(
                onTap: () => _editPlace(p.playerId, p.teamId, p.playerName, place),
                child: Container(color: _hoveredRow == i ? Colors.indigo.shade50 : null, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    SizedBox(width: 50, child: Text(place?.toString() ?? '-', style: TextStyle(fontWeight: place != null ? FontWeight.bold : FontWeight.normal, fontSize: 16))),
                    Expanded(flex: 2, child: Text(p.playerName)),
                    Expanded(flex: 2, child: Text(p.teamName, style: TextStyle(color: Colors.grey.shade700))),
                    Icon(Icons.edit, size: 16, color: Colors.indigo.shade300),
                  ]))));
          },
        )),
      ])));
  }

  Widget _buildHeader() => Container(color: Colors.grey.shade100, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), child: const Row(children: [SizedBox(width: 50, child: Text('Місце', style: TextStyle(fontWeight: FontWeight.bold))), Expanded(flex: 2, child: Text('Гравець', style: TextStyle(fontWeight: FontWeight.bold))), Expanded(flex: 2, child: Text('Команда', style: TextStyle(fontWeight: FontWeight.bold))), SizedBox(width: 16)]));
}
