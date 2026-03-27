import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../viewmodels/team_viewmodel.dart';
import 'cycling_providers.dart';
import 'cycling_scoring.dart' as scoring;

class CyclingTeamStandingsTab extends ConsumerStatefulWidget {
  final int tId;
  const CyclingTeamStandingsTab({super.key, required this.tId});

  @override
  ConsumerState<CyclingTeamStandingsTab> createState() => _CyclingTeamStandingsTabState();
}

class _CyclingTeamStandingsTabState extends ConsumerState<CyclingTeamStandingsTab> {
  bool _loading = true;
  List<scoring.CyclingStanding> _standings = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final teamSvc = ref.read(teamServiceProvider);
    final cySvc = ref.read(cyclingServiceProvider);

    final tourTeams = await teamSvc.getTeamListForTournament(widget.tId);
    final teams = tourTeams.map((t) => (teamId: t.teamId, teamName: t.teamName)).toList();
    final removedIds = <int>{};

    final placesMap = await cySvc.getPlayerPlaces(widget.tId);
    final categoriesMap = await cySvc.getPlayerCategories(widget.tId);
    final playerTeamsMap = await teamSvc.getPlayerTeamsMap(widget.tId);
    final playerTeams = {for (final entry in playerTeamsMap.entries) entry.key: entry.value.team_id!};

    final individualResults = <({int teamId, int place, String? category})>[];
    for (final entry in placesMap.entries) {
      final tId = playerTeams[entry.key];
      if (tId != null) individualResults.add((teamId: tId, place: entry.value, category: categoriesMap[entry.key]));
    }

    final standings = scoring.calculateStandings(
      teams: teams,
      individualResults: individualResults,
      maxResultsPerTeam: 3,
      removedTeamIds: removedIds,
    );

    setState(() { _standings = standings; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_standings.isEmpty) return const Center(child: Text('Командний залік порожній.'));

    return Card(elevation: 0, shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey.shade300, width: 1), borderRadius: BorderRadius.circular(8)),
      child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Командний залік', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData)]),
        const SizedBox(height: 12),
        Expanded(child: ListView.separated(
          itemCount: _standings.length + 1,
          separatorBuilder: (ctx, i) => Divider(height: 1, color: Colors.grey.shade200),
          itemBuilder: (ctx, i) {
            if (i == 0) return _buildHeader();
            final s = _standings[i - 1];
            return Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), child: Row(children: [
              SizedBox(width: 40, child: Text('${s.rank}', style: const TextStyle(fontWeight: FontWeight.bold))),
              Expanded(flex: 3, child: Text(s.teamName)),
              Expanded(flex: 2, child: Text(s.places.join(', '), style: TextStyle(color: Colors.grey.shade600))),
              SizedBox(width: 60, child: Text('${s.totalPoints}', style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
            ]));
          },
        )),
      ])));
  }

  Widget _buildHeader() => Container(color: Colors.grey.shade100, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), child: const Row(children: [SizedBox(width: 40, child: Text('Місце', style: TextStyle(fontWeight: FontWeight.bold))), Expanded(flex: 3, child: Text('Команда', style: TextStyle(fontWeight: FontWeight.bold))), Expanded(flex: 2, child: Text('Кращі результати', style: TextStyle(fontWeight: FontWeight.bold))), SizedBox(width: 60, child: Text('Сума', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right))]));
}
