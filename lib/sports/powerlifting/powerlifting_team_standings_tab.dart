import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../viewmodels/team_viewmodel.dart';
import 'powerlifting_data.dart';
import 'powerlifting_scoring.dart' as scoring;

class PowerliftingTeamStandingsTab extends ConsumerStatefulWidget {
  final int tId;
  const PowerliftingTeamStandingsTab({super.key, required this.tId});

  @override
  ConsumerState<PowerliftingTeamStandingsTab> createState() =>
      _PowerliftingTeamStandingsTabState();
}

class _PowerliftingTeamStandingsTabState
    extends ConsumerState<PowerliftingTeamStandingsTab> {
  bool _loading = true;
  List<scoring.PowerliftingStanding> _standings = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final teamSvc = ref.read(teamServiceProvider);
    final tourTeams = await teamSvc.getTeamListForTournament(widget.tId);
    final teams =
        tourTeams.map((t) => (teamId: t.teamId, teamName: t.teamName)).toList();

    final athletes = await loadPowerliftingAthletesW(ref, widget.tId);
    final individual = scoring.calculateIndividualStandings(athletes);

    final standings = scoring.calculateTeamStandings(
      teams: teams,
      individualResults: individual,
      maxResultsPerTeam: 3,
    );

    if (!mounted) return;
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
          borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Командний залік',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: _standings.length + 1,
              separatorBuilder: (ctx, i) =>
                  Divider(height: 1, color: Colors.grey.shade200),
              itemBuilder: (ctx, i) {
                if (i == 0) return _buildHeader();
                final s = _standings[i - 1];
                final scored = s.totalPoints > 0;
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    SizedBox(
                        width: 40,
                        child: Text(scored ? '${s.rank}' : '—',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold))),
                    Expanded(flex: 3, child: Text(s.teamName)),
                    Expanded(
                        flex: 3,
                        child: Text(
                            scored ? s.contributingCategories.join(', ') : '',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade600))),
                    Expanded(
                        flex: 2,
                        child: Text(scored ? s.places.join(' + ') : '',
                            style: TextStyle(color: Colors.grey.shade700))),
                    SizedBox(
                        width: 60,
                        child: Text(scored ? '${s.totalPoints}' : '—',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            textAlign: TextAlign.right)),
                  ]),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildHeader() => Container(
        color: Colors.grey.shade100,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: const Row(children: [
          SizedBox(
              width: 40,
              child:
                  Text('Місце', style: TextStyle(fontWeight: FontWeight.bold))),
          Expanded(
              flex: 3,
              child: Text('Команда',
                  style: TextStyle(fontWeight: FontWeight.bold))),
          Expanded(
              flex: 3,
              child: Text('Категорії',
                  style: TextStyle(fontWeight: FontWeight.bold))),
          Expanded(
              flex: 2,
              child: Text('Місця',
                  style: TextStyle(fontWeight: FontWeight.bold))),
          SizedBox(
              width: 60,
              child: Text('Очки',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontWeight: FontWeight.bold))),
        ]),
      );
}
