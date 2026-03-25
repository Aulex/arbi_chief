import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../viewmodels/tournament_viewmodel.dart';
import 'arm_wrestling_providers.dart';
import 'arm_wrestling_scoring.dart';

/// Tab showing arm wrestling team standings based on individual placements.
class ArmWrestlingTeamStandingsTab extends ConsumerStatefulWidget {
  final int tId;
  const ArmWrestlingTeamStandingsTab({super.key, required this.tId});

  @override
  ConsumerState<ArmWrestlingTeamStandingsTab> createState() =>
      _ArmWrestlingTeamStandingsTabState();
}

class _ArmWrestlingTeamStandingsTabState
    extends ConsumerState<ArmWrestlingTeamStandingsTab> {
  bool _loading = true;
  List<ArmWrestlingTeamStanding> _teamStandings = [];
  Map<int, List<ArmWrestlingStanding>> _categoryStandings = {};
  Map<int, ({bool isValid, int count, String label})> _categoryValidation = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final armSvc = ref.read(armWrestlingServiceProvider);
    final tournamentSvc = ref.read(tournamentServiceProvider);

    // Load players by category and games
    final playersByCategory = await armSvc.getPlayersByCategory(widget.tId);
    final teamNames = await armSvc.getTeamNames(widget.tId);
    final categoryValidation = await armSvc.validateCategories(widget.tId);
    final games = await tournamentSvc.getGamesGroupedByBoard(widget.tId);

    // Build results per category (boardNum = categoryId)
    final categoryResults = <int, Map<int, Map<int, double>>>{};
    for (final entry in games.entries) {
      final catId = entry.key;
      categoryResults.putIfAbsent(catId, () => {});
      for (final game in entry.value) {
        final wId = game.white.player_id!;
        final bId = game.black.player_id!;
        if (game.whiteResult != null) {
          categoryResults[catId]!.putIfAbsent(wId, () => {})[bId] = game.whiteResult!;
        }
        if (game.blackResult != null) {
          categoryResults[catId]!.putIfAbsent(bId, () => {})[wId] = game.blackResult!;
        }
      }
    }

    // Calculate individual standings per category
    final catStandings = <int, List<ArmWrestlingStanding>>{};
    for (final catEntry in playersByCategory.entries) {
      final catId = catEntry.key;
      final players = catEntry.value;
      final results = categoryResults[catId] ?? {};

      catStandings[catId] = calculateCategoryStandings(
        players: players,
        results: results,
      );
    }

    // Get all team IDs
    final allTeamIds = <int>{};
    for (final standings in catStandings.values) {
      for (final s in standings) {
        allTeamIds.add(s.teamId);
      }
    }

    // Calculate team standings
    final teamStandings = calculateTeamStandings(
      categoryStandings: catStandings,
      teamIds: allTeamIds,
      teamNames: teamNames,
    );

    if (mounted) {
      setState(() {
        _categoryStandings = catStandings;
        _teamStandings = teamStandings;
        _categoryValidation = categoryValidation;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category validation warnings
          ..._buildCategoryWarnings(),
          const SizedBox(height: 16),
          // Individual standings per category
          ..._buildCategoryStandings(),
          const SizedBox(height: 24),
          // Team standings
          _buildTeamStandings(),
        ],
      ),
    );
  }

  List<Widget> _buildCategoryWarnings() {
    final warnings = <Widget>[];
    for (final entry in _categoryValidation.entries) {
      final cat = entry.value;
      if (!cat.isValid && cat.count > 0) {
        warnings.add(
          Card(
            color: Colors.orange.shade50,
            elevation: 0,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: Colors.orange.shade200),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${cat.label}: ${cat.count} учасник(ів) — менше $minParticipantsForCategory. '
                      'Учасники мають перейти у важчу категорію.',
                      style: TextStyle(color: Colors.orange.shade900, fontSize: 13),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final svc = ref.read(armWrestlingServiceProvider);
                      await svc.redistributeCategories(widget.tId);
                      _loadData();
                    },
                    child: const Text('Перемістити'),
                  ),
                ],
              ),
            ),
          ),
        );
        warnings.add(const SizedBox(height: 8));
      }
    }
    return warnings;
  }

  List<Widget> _buildCategoryStandings() {
    final widgets = <Widget>[];

    for (final cat in WeightCategory.values) {
      final standings = _categoryStandings[cat.id];
      if (standings == null || standings.isEmpty) continue;

      final validation = _categoryValidation[cat.id];
      final isValid = validation?.isValid ?? false;

      widgets.add(
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: isValid ? Colors.grey.shade300 : Colors.red.shade200,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: isValid ? Colors.indigo : Colors.red.shade300,
                      child: Text(
                        '${cat.id}',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      cat.label,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '(${standings.length} учасн.)',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                    if (!isValid) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Не проводиться',
                          style: TextStyle(fontSize: 11, color: Colors.red.shade700),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                _buildStandingsTable(standings),
              ],
            ),
          ),
        ),
      );
      widgets.add(const SizedBox(height: 12));
    }

    return widgets;
  }

  Widget _buildStandingsTable(List<ArmWrestlingStanding> standings) {
    return Table(
      columnWidths: const {
        0: FixedColumnWidth(40),  // Place
        1: FlexColumnWidth(3),    // Player
        2: FlexColumnWidth(2),    // Team
        3: FixedColumnWidth(60),  // Wins
        4: FixedColumnWidth(60),  // Losses
        5: FixedColumnWidth(60),  // Games
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
          ),
          children: [
            _headerCell('М'),
            _headerCell('Учасник'),
            _headerCell('Команда'),
            _headerCell('П', align: TextAlign.center),
            _headerCell('Пор', align: TextAlign.center),
            _headerCell('Ігри', align: TextAlign.center),
          ],
        ),
        for (final s in standings)
          TableRow(
            decoration: BoxDecoration(
              color: s.place <= 3 ? Colors.amber.withOpacity(0.05 * (4 - s.place)) : null,
            ),
            children: [
              _dataCell('${s.place}', fontWeight: FontWeight.bold),
              _dataCell(s.playerName),
              _dataCell(s.teamName),
              _dataCell('${s.wins}', align: TextAlign.center,
                  color: s.wins > 0 ? Colors.green.shade700 : null),
              _dataCell('${s.losses}', align: TextAlign.center,
                  color: s.losses > 0 ? Colors.red.shade700 : null),
              _dataCell('${s.gamesPlayed}', align: TextAlign.center),
            ],
          ),
      ],
    );
  }

  Widget _buildTeamStandings() {
    if (_teamStandings.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.indigo.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.groups_outlined, color: Colors.indigo.shade700, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Командний залік',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo.shade900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Сума очок 3-х кращих учасників з 3-х різних вагових категорій (менше — краще)',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            Table(
              columnWidths: const {
                0: FixedColumnWidth(40),  // Place
                1: FlexColumnWidth(2),    // Team
                2: FixedColumnWidth(70),  // Total
                3: FlexColumnWidth(3),    // Details
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
                  ),
                  children: [
                    _headerCell('М'),
                    _headerCell('Команда'),
                    _headerCell('Очки', align: TextAlign.center),
                    _headerCell('Деталі'),
                  ],
                ),
                for (final ts in _teamStandings)
                  TableRow(
                    decoration: BoxDecoration(
                      color: ts.place <= 3
                          ? Colors.amber.withOpacity(0.05 * (4 - ts.place))
                          : null,
                    ),
                    children: [
                      _dataCell('${ts.place}', fontWeight: FontWeight.bold),
                      _dataCell(ts.teamName),
                      _dataCell(
                        '${ts.totalPoints}',
                        align: TextAlign.center,
                        fontWeight: FontWeight.bold,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: ts.contributors.map((c) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade50,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${c.categoryLabel}: ${c.place}-е м.',
                                style: TextStyle(fontSize: 11, color: Colors.indigo.shade800),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerCell(String text, {TextAlign align = TextAlign.left}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade700,
        ),
      ),
    );
  }

  Widget _dataCell(
    String text, {
    TextAlign align = TextAlign.left,
    FontWeight fontWeight = FontWeight.normal,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(
          fontSize: 13,
          fontWeight: fontWeight,
          color: color,
        ),
      ),
    );
  }
}
