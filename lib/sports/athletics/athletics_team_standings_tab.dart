import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../viewmodels/team_viewmodel.dart';
import 'athletics_providers.dart';
import 'athletics_scoring.dart' as scoring;

class AthleticsTeamStandingsTab extends ConsumerStatefulWidget {
  final int tId;
  const AthleticsTeamStandingsTab({super.key, required this.tId});

  @override
  ConsumerState<AthleticsTeamStandingsTab> createState() => _AthleticsTeamStandingsTabState();
}

class _AthleticsTeamStandingsTabState extends ConsumerState<AthleticsTeamStandingsTab> {
  bool _loading = true;
  List<scoring.AthleticsStanding> _standings = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final teamSvc = ref.read(teamServiceProvider);
    final athSvc = ref.read(athleticsServiceProvider);

    final tourTeams = await teamSvc.getTeamListForTournament(widget.tId);
    final teams = tourTeams.map((t) => (teamId: t.teamId, teamName: t.teamName)).toList();
    
    // For removed teams (not used actively but logic requires it)
    final removedIds = <int>{};

    // Get individual places
    final placesMap = await athSvc.getPlayerPlaces(widget.tId);
    
    // Map playerId -> teamId
    final playerTeamsMap = await teamSvc.getPlayerTeamsMap(widget.tId);
    final playerTeams = {for (final entry in playerTeamsMap.entries) entry.key: entry.value.team_id!};

    // Convert to list of ({int teamId, int place})
    final individualResults = <({int teamId, int place})>[];
    for (final entry in placesMap.entries) {
      final pId = entry.key;
      final place = entry.value;
      final tId = playerTeams[pId];
      if (tId != null) {
        individualResults.add((teamId: tId, place: place));
      }
    }

    final standings = scoring.calculateStandings(
      teams: teams,
      individualResults: individualResults,
      maxResultsPerTeam: 3, // Typically top 3 per team
      removedTeamIds: removedIds,
    );

    setState(() {
      _standings = standings;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_standings.isEmpty) {
      return const Center(child: Text('Командний залік порожній.'));
    }

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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Командний залік', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: _standings.length + 1,
                separatorBuilder: (ctx, i) => Divider(height: 1, color: Colors.grey.shade200),
                itemBuilder: (ctx, i) {
                  if (i == 0) return _buildHeader();
                  final s = _standings[i - 1];
                  
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        SizedBox(width: 40, child: Text('${s.rank}', style: const TextStyle(fontWeight: FontWeight.bold))),
                        Expanded(flex: 3, child: Text(s.teamName)),
                        Expanded(flex: 2, child: Text(s.places.join(', '), style: TextStyle(color: Colors.grey.shade600))),
                        SizedBox(width: 60, child: Text('${s.totalPoints}', style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
                      ],
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
          SizedBox(width: 40, child: Text('Місце', style: TextStyle(fontWeight: FontWeight.bold))),
          Expanded(flex: 3, child: Text('Команда', style: TextStyle(fontWeight: FontWeight.bold))),
          Expanded(flex: 2, child: Text('Кращі результати', style: TextStyle(fontWeight: FontWeight.bold))),
          SizedBox(width: 60, child: Text('Сума', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}
