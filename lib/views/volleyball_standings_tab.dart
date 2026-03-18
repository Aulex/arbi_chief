import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/volleyball_model.dart';
import '../viewmodels/volleyball_viewmodel.dart';

/// Tab showing volleyball standings with cross-table.
class VolleyballStandingsTab extends ConsumerStatefulWidget {
  final int tId;
  const VolleyballStandingsTab({super.key, required this.tId});

  @override
  ConsumerState<VolleyballStandingsTab> createState() =>
      _VolleyballStandingsTabState();
}

class _VolleyballStandingsTabState
    extends ConsumerState<VolleyballStandingsTab> {
  List<VolleyballTeamStanding> _standings = [];
  List<VolleyballMatch> _matches = [];
  List<String> _groups = [];
  String? _selectedGroup;
  bool _loading = true;

  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();
  int? _hoveredRow;
  int? _hoveredCol;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final svc = ref.read(volleyballServiceProvider);
    final groups = await svc.getGroups(widget.tId);

    setState(() {
      _groups = groups;
      if (_selectedGroup == null && groups.isNotEmpty) {
        _selectedGroup = groups.first;
      }
    });

    await _reloadStandings();
  }

  Future<void> _reloadStandings() async {
    final svc = ref.read(volleyballServiceProvider);
    final standings = await svc.getStandings(widget.tId,
        groupName: _selectedGroup);
    final matches = _selectedGroup != null
        ? await svc.getMatches(widget.tId, groupName: _selectedGroup)
        : await svc.getMatches(widget.tId);

    setState(() {
      _standings = standings;
      _matches = matches;
      _loading = false;
    });
  }

  /// Find match result between two teams for cross-table display.
  VolleyballMatch? _findMatch(int team1Id, int team2Id) {
    for (final m in _matches) {
      if ((m.homeTeamId == team1Id && m.awayTeamId == team2Id) ||
          (m.homeTeamId == team2Id && m.awayTeamId == team1Id)) {
        return m;
      }
    }
    return null;
  }

  /// Get result string from team1's perspective.
  String _getResultDisplay(int team1Id, int team2Id) {
    final m = _findMatch(team1Id, team2Id);
    if (m == null || !m.isPlayed) return '';
    if (m.homeTeamId == team1Id) {
      return '${m.homeSets}:${m.awaySets}';
    } else {
      return '${m.awaySets}:${m.homeSets}';
    }
  }

  /// Get set details from team1's perspective.
  String _getSetDetails(int team1Id, int team2Id) {
    final m = _findMatch(team1Id, team2Id);
    if (m == null || !m.isPlayed) return '';
    if (m.homeTeamId == team1Id) {
      return m.setScoresDisplay;
    }
    // Mirror the set scores
    final parts = <String>[];
    if (m.set1Home != null && m.set1Away != null) {
      parts.add('${m.set1Away}:${m.set1Home}');
    }
    if (m.set2Home != null && m.set2Away != null) {
      parts.add('${m.set2Away}:${m.set2Home}');
    }
    if (m.set3Home != null && m.set3Away != null) {
      parts.add('${m.set3Away}:${m.set3Home}');
    }
    return parts.join(' ');
  }

  /// Did team1 win against team2?
  bool? _didWin(int team1Id, int team2Id) {
    final m = _findMatch(team1Id, team2Id);
    if (m == null || !m.isPlayed) return null;
    if (m.homeTeamId == team1Id) return m.homeSets > m.awaySets;
    return m.awaySets > m.homeSets;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Group selector
        if (_groups.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Row(
              children: [
                const Text('Підгрупа: ',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                ..._groups.map((g) => Padding(
                      padding: const EdgeInsets.only(right: 4.0),
                      child: ChoiceChip(
                        label: Text('Група $g'),
                        selected: _selectedGroup == g,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _selectedGroup = g);
                            _reloadStandings();
                          }
                        },
                      ),
                    )),
                // "All" chip for showing overall
                ChoiceChip(
                  label: const Text('Фінал'),
                  selected: _selectedGroup == null,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedGroup = null);
                      _reloadStandings();
                    }
                  },
                ),
              ],
            ),
          ),
        // Refresh
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: 'Оновити',
              onPressed: _reloadStandings,
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Standings table + cross-table
        if (_standings.isEmpty)
          Expanded(
            child: Center(
              child: Text(
                'Немає даних для відображення',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),
          )
        else
          Expanded(child: _buildCrossTable()),
      ],
    );
  }

  Widget _buildCrossTable() {
    final teams = _standings;
    final n = teams.length;

    // Column widths
    const placeW = 40.0;
    const nameW = 180.0;
    const cellW = 72.0;
    const statsW = 56.0;

    return Scrollbar(
      controller: _horizontalController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _horizontalController,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: placeW + nameW + (n * cellW) + (statsW * 5) + 16,
          child: Column(
            children: [
              // Header row
              _buildHeaderRow(teams, placeW, nameW, cellW, statsW),
              const Divider(height: 1),
              // Data rows
              Expanded(
                child: ListView.builder(
                  controller: _verticalController,
                  itemCount: n,
                  itemBuilder: (ctx, rowIdx) {
                    final team = teams[rowIdx];
                    return _buildDataRow(
                        team, rowIdx, teams, placeW, nameW, cellW, statsW);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderRow(List<VolleyballTeamStanding> teams, double placeW,
      double nameW, double cellW, double statsW) {
    return Container(
      height: 40,
      color: Colors.indigo.shade50,
      child: Row(
        children: [
          SizedBox(width: placeW, child: const Center(child: Text('М', style: TextStyle(fontWeight: FontWeight.bold)))),
          SizedBox(width: nameW, child: const Padding(
            padding: EdgeInsets.only(left: 8),
            child: Align(alignment: Alignment.centerLeft, child: Text('Команда', style: TextStyle(fontWeight: FontWeight.bold))),
          )),
          ...List.generate(teams.length, (i) => SizedBox(
                width: cellW,
                child: Center(
                    child: Text('${i + 1}',
                        style: const TextStyle(fontWeight: FontWeight.bold))),
              )),
          SizedBox(width: statsW, child: const Center(child: Text('О', style: TextStyle(fontWeight: FontWeight.bold)))),
          SizedBox(width: statsW, child: const Center(child: Text('В', style: TextStyle(fontWeight: FontWeight.bold)))),
          SizedBox(width: statsW, child: const Center(child: Text('П', style: TextStyle(fontWeight: FontWeight.bold)))),
          SizedBox(width: statsW, child: const Center(child: Text('Парт', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)))),
          SizedBox(width: statsW, child: const Center(child: Text('Очки', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)))),
        ],
      ),
    );
  }

  Widget _buildDataRow(
    VolleyballTeamStanding team,
    int rowIdx,
    List<VolleyballTeamStanding> teams,
    double placeW,
    double nameW,
    double cellW,
    double statsW,
  ) {
    final isEven = rowIdx % 2 == 0;
    final bgColor = _hoveredRow == rowIdx
        ? Colors.indigo.shade50
        : isEven
            ? Colors.grey.shade50
            : Colors.white;

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredRow = rowIdx),
      onExit: (_) => setState(() => _hoveredRow = null),
      child: Container(
        height: 48,
        color: bgColor,
        child: Row(
          children: [
            // Place
            SizedBox(
              width: placeW,
              child: Center(
                child: Text('${team.place}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            // Team name
            SizedBox(
              width: nameW,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  team.teamName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
            // Cross-table cells
            ...List.generate(teams.length, (colIdx) {
              if (rowIdx == colIdx) {
                // Diagonal
                return Container(
                  width: cellW,
                  color: Colors.grey.shade300,
                );
              }
              final opponent = teams[colIdx];
              final result = _getResultDisplay(team.teamId, opponent.teamId);
              final setDetails = _getSetDetails(team.teamId, opponent.teamId);
              final won = _didWin(team.teamId, opponent.teamId);

              Color? cellColor;
              if (_hoveredCol == colIdx && _hoveredRow == rowIdx) {
                cellColor = Colors.indigo.shade100;
              } else if (won == true) {
                cellColor = Colors.green.shade50;
              } else if (won == false) {
                cellColor = Colors.red.shade50;
              }

              return MouseRegion(
                onEnter: (_) => setState(() => _hoveredCol = colIdx),
                onExit: (_) => setState(() => _hoveredCol = null),
                child: Tooltip(
                  message: setDetails.isNotEmpty
                      ? '${team.teamName} vs ${opponent.teamName}\n$setDetails'
                      : '${team.teamName} vs ${opponent.teamName}',
                  child: Container(
                    width: cellW,
                    decoration: BoxDecoration(
                      color: cellColor,
                      border: Border(
                        left: BorderSide(color: Colors.grey.shade300, width: 0.5),
                        right: BorderSide(color: Colors.grey.shade300, width: 0.5),
                      ),
                    ),
                    child: Center(
                      child: result.isNotEmpty
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  result,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: won == true
                                        ? Colors.green.shade700
                                        : won == false
                                            ? Colors.red.shade700
                                            : null,
                                  ),
                                ),
                                if (setDetails.isNotEmpty)
                                  Text(
                                    setDetails,
                                    style: TextStyle(
                                        fontSize: 9,
                                        color: Colors.grey.shade600),
                                  ),
                              ],
                            )
                          : Text('-',
                              style:
                                  TextStyle(color: Colors.grey.shade400)),
                    ),
                  ),
                ),
              );
            }),
            // Stats columns
            SizedBox(
              width: statsW,
              child: Center(
                  child: Text('${team.points}',
                      style: const TextStyle(fontWeight: FontWeight.bold))),
            ),
            SizedBox(
              width: statsW,
              child: Center(child: Text('${team.wins}')),
            ),
            SizedBox(
              width: statsW,
              child: Center(child: Text('${team.losses}')),
            ),
            SizedBox(
              width: statsW,
              child: Center(
                  child: Text(team.setRatio,
                      style: const TextStyle(fontSize: 12))),
            ),
            SizedBox(
              width: statsW,
              child: Center(
                  child: Text(team.pointsRatio,
                      style: const TextStyle(fontSize: 12))),
            ),
          ],
        ),
      ),
    );
  }
}
