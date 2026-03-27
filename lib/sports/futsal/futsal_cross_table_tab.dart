import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../viewmodels/team_viewmodel.dart';
import 'futsal_providers.dart';
import 'futsal_scoring.dart' as scoring;

/// Futsal team-vs-team cross-table tab.
///
/// Simple round-robin with goal-based result entry (score:score).
class FutsalCrossTableTab extends ConsumerStatefulWidget {
  final int tId;
  final String tournamentName;

  const FutsalCrossTableTab({
    super.key,
    required this.tId,
    required this.tournamentName,
  });

  @override
  ConsumerState<FutsalCrossTableTab> createState() => _FutsalCrossTableTabState();
}

class _FutsalCrossTableTabState extends ConsumerState<FutsalCrossTableTab> {
  bool _loading = true;
  List<({int teamId, String teamName, int? teamNumber, int? entityId})> _teams = [];
  Map<(int, int), _GameData> _games = {};
  int? _hoveredRow;
  int? _hoveredCol;

  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final teamSvc = ref.read(teamServiceProvider);
    final fSvc = ref.read(futsalServiceProvider);

    final teamList = await teamSvc.getTeamListForTournament(widget.tId);
    final games = await fSvc.getTeamGamesForTournament(widget.tId);

    // Build teams with entity_ids
    final teams = <({int teamId, String teamName, int? teamNumber, int? entityId})>[];
    for (final t in teamList) {
      final allTeams = await teamSvc.getAllTeams();
      final team = allTeams.where((at) => at.team_id == t.teamId).firstOrNull;
      teams.add((
        teamId: t.teamId,
        teamName: t.teamName,
        teamNumber: t.teamNumber,
        entityId: team?.entity_id,
      ));
    }

    // Build games map (both directions for mirrored display)
    final gamesMap = <(int, int), _GameData>{};
    for (final g in games) {
      gamesMap[(g.teamAEntityId, g.teamBEntityId)] = _GameData(
        eventId: g.eventId,
        eventResult: g.eventResult,
      );
      gamesMap[(g.teamBEntityId, g.teamAEntityId)] = _GameData(
        eventId: g.eventId,
        eventResult: g.eventResult != null ? _mirrorResult(g.eventResult!) : null,
      );
    }

    setState(() {
      _teams = teams;
      _games = gamesMap;
      _loading = false;
    });
  }

  String _mirrorResult(String result) {
    final parts = result.split(':');
    if (parts.length != 2) return result;
    return '${parts[1]}:${parts[0]}';
  }

  List<scoring.FutsalStanding> _calculateStandings(
    List<({int teamId, String teamName, int? teamNumber, int? entityId})> teams,
  ) {
    final teamEntityIds = teams.map((t) => t.entityId).whereType<int>().toSet();
    final filteredGames = <(int, int), String>{};
    final seenPairs = <(int, int)>{};

    for (final entry in _games.entries) {
      final (aEntId, bEntId) = entry.key;
      if (teamEntityIds.contains(aEntId) && teamEntityIds.contains(bEntId)) {
        if (seenPairs.contains((bEntId, aEntId))) continue;
        seenPairs.add((aEntId, bEntId));
        final result = entry.value.eventResult;
        if (result != null) {
          filteredGames[(aEntId, bEntId)] = result;
        }
      }
    }

    return scoring.calculateStandings(
      teams: teams.map((t) => (teamId: t.teamId, teamName: t.teamName, entityId: t.entityId)).toList(),
      games: filteredGames,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_teams.isEmpty) {
      return const Center(child: Text('Додайте команди для відображення таблиці'));
    }

    return _buildCrossTable(_teams);
  }

  Widget _buildCrossTable(
    List<({int teamId, String teamName, int? teamNumber, int? entityId})> teams,
  ) {
    final standings = _calculateStandings(teams);

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
                const Text('Турнірна таблиця', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (_games.isNotEmpty)
                  TextButton.icon(
                    icon: const Icon(Icons.delete_sweep_outlined, size: 14),
                    label: const Text('Очистити', style: TextStyle(fontSize: 11)),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => _confirmClearResults(),
                  ),
                const SizedBox(width: 8),
                Text('${teams.length} команд', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Scrollbar(
                controller: _verticalController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _verticalController,
                  child: Scrollbar(
                    controller: _horizontalController,
                    thumbVisibility: true,
                    notificationPredicate: (n) => n.depth == 1,
                    child: SingleChildScrollView(
                      controller: _horizontalController,
                      scrollDirection: Axis.horizontal,
                      child: _buildGrid(teams, standings),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(
    List<({int teamId, String teamName, int? teamNumber, int? entityId})> teams,
    List<scoring.FutsalStanding> standings,
  ) {
    const cellWidth = 56.0;
    const nameWidth = 180.0;
    const rankWidth = 36.0;
    const placeWidth = 48.0;
    const statsWidth = 56.0;
    const separatorWidth = 15.0;

    final standingsByTeam = {for (final s in standings) s.teamId: s};
    final n = teams.length;

    return Table(
      defaultColumnWidth: const FixedColumnWidth(cellWidth),
      columnWidths: {
        0: const FixedColumnWidth(rankWidth),
        1: const FixedColumnWidth(nameWidth),
        n + 2: const FixedColumnWidth(statsWidth), // О (Очки)
        n + 3: const FixedColumnWidth(statsWidth), // В (Виграші)
        n + 4: const FixedColumnWidth(statsWidth), // Р (Різниця)
        n + 5: const FixedColumnWidth(separatorWidth),
        n + 6: const FixedColumnWidth(nameWidth),
        n + 7: const FixedColumnWidth(statsWidth),
        n + 8: const FixedColumnWidth(placeWidth),
      },
      border: TableBorder.all(color: Colors.grey.shade300, width: 0.5),
      children: [
        // Header row
        TableRow(
          decoration: BoxDecoration(color: Colors.grey.shade100),
          children: [
            _headerCell('#'),
            _headerCell('Команда'),
            for (int j = 0; j < n; j++)
              _headerCell('${teams[j].teamNumber ?? j + 1}'),
            _headerCell('О'),
            _headerCell('М'),
            _headerCell('Р'),
            Container(height: 36, decoration: BoxDecoration(color: Colors.black, border: Border.all(color: Colors.black, width: 0.5))),
            _headerCell('Команда'),
            _headerCell('Очки'),
            _headerCell('Місце'),
          ],
        ),
        // Data rows
        for (int i = 0; i < n; i++)
          _buildTeamRow(i, teams, standingsByTeam, standings),
      ],
    );
  }

  TableRow _buildTeamRow(
    int i,
    List<({int teamId, String teamName, int? teamNumber, int? entityId})> teams,
    Map<int, scoring.FutsalStanding> standingsByTeam,
    List<scoring.FutsalStanding> sortedStandings,
  ) {
    final team = teams[i];
    final standing = standingsByTeam[team.teamId];
    final standingRow = i < sortedStandings.length ? sortedStandings[i] : null;

    return TableRow(
      decoration: BoxDecoration(
        color: _hoveredRow == i ? Colors.indigo.shade50 : null,
      ),
      children: [
        _dataCell('${team.teamNumber ?? i + 1}', bold: true),
        _teamNameCell(team.teamName),
        for (int j = 0; j < teams.length; j++)
          _buildGameCell(i, j, teams),
        // Match points
        _dataCell('${standing?.matchPoints ?? 0}', bold: true),
        // Goals scored:conceded
        _dataCell('${standing?.goalsScored ?? 0}:${standing?.goalsConceded ?? 0}'),
        // Goal difference
        _dataCell('${(standing?.goalDifference ?? 0) >= 0 ? '+' : ''}${standing?.goalDifference ?? 0}'),
        // Black separator
        Container(height: 36, decoration: BoxDecoration(color: Colors.black, border: Border.all(color: Colors.black, width: 0.5))),
        // Standings
        _teamNameCell(standingRow?.teamName ?? ''),
        _dataCell('${standingRow?.matchPoints ?? 0}', bold: true),
        _dataCell('${standingRow?.rank ?? i + 1}', bold: true),
      ],
    );
  }

  Widget _buildGameCell(
    int i,
    int j,
    List<({int teamId, String teamName, int? teamNumber, int? entityId})> teams,
  ) {
    if (i == j) {
      return Container(height: 36, color: Colors.grey.shade300);
    }

    final teamA = teams[i];
    final teamB = teams[j];
    if (teamA.entityId == null || teamB.entityId == null) {
      return const SizedBox(height: 36);
    }

    final game = _games[(teamA.entityId!, teamB.entityId!)];

    String cellText = '';
    Color? bgColor;

    if (game != null && game.eventResult != null) {
      cellText = game.eventResult!;
      final parts = cellText.split(':');
      if (parts.length == 2) {
        final a = int.tryParse(parts[0]) ?? 0;
        final b = int.tryParse(parts[1]) ?? 0;
        if (a > b) {
          bgColor = Colors.green.shade50;
        } else if (a < b) {
          bgColor = Colors.red.shade50;
        } else {
          bgColor = Colors.amber.shade50;
        }
      }
    }

    return MouseRegion(
      onEnter: (_) => setState(() { _hoveredRow = i; _hoveredCol = j; }),
      onExit: (_) => setState(() { _hoveredRow = null; _hoveredCol = null; }),
      child: GestureDetector(
        onTap: () => _showScoreDialog(teamA, teamB, game),
        child: Container(
          height: 36,
          alignment: Alignment.center,
          color: bgColor ?? (_hoveredCol == j && _hoveredRow == i ? Colors.indigo.shade50 : null),
          child: Text(
            cellText,
            style: TextStyle(fontSize: 12, fontWeight: cellText.isNotEmpty ? FontWeight.w500 : null),
          ),
        ),
      ),
    );
  }

  Future<void> _showScoreDialog(
    ({int teamId, String teamName, int? teamNumber, int? entityId}) teamA,
    ({int teamId, String teamName, int? teamNumber, int? entityId}) teamB,
    _GameData? existingGame,
  ) async {
    // Parse existing score
    int existingGoalsA = 0;
    int existingGoalsB = 0;
    if (existingGame?.eventResult != null) {
      final parts = existingGame!.eventResult!.split(':');
      if (parts.length == 2) {
        existingGoalsA = int.tryParse(parts[0]) ?? 0;
        existingGoalsB = int.tryParse(parts[1]) ?? 0;
      }
    }

    final goalsAController = TextEditingController(text: existingGoalsA > 0 ? '$existingGoalsA' : '');
    final goalsBController = TextEditingController(text: existingGoalsB > 0 ? '$existingGoalsB' : '');

    final result = await showDialog<({int goalsA, int goalsB})?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${teamA.teamName}  vs  ${teamB.teamName}', style: const TextStyle(fontSize: 16)),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 80,
              child: TextField(
                controller: goalsAController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  labelText: teamA.teamName.length > 10 ? teamA.teamName.substring(0, 10) : teamA.teamName,
                  border: const OutlineInputBorder(),
                ),
                autofocus: true,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(':', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            ),
            SizedBox(
              width: 80,
              child: TextField(
                controller: goalsBController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  labelText: teamB.teamName.length > 10 ? teamB.teamName.substring(0, 10) : teamB.teamName,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (existingGame != null)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _deleteGame(existingGame.eventId);
              },
              child: const Text('Видалити', style: TextStyle(color: Colors.red)),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Скасувати')),
          ElevatedButton(
            onPressed: () {
              final goalsA = int.tryParse(goalsAController.text) ?? 0;
              final goalsB = int.tryParse(goalsBController.text) ?? 0;
              Navigator.pop(ctx, (goalsA: goalsA, goalsB: goalsB));
            },
            child: const Text('Зберегти'),
          ),
        ],
      ),
    );

    goalsAController.dispose();
    goalsBController.dispose();

    if (result == null) return;

    final fSvc = ref.read(futsalServiceProvider);
    final eventId = existingGame?.eventId ??
        await fSvc.findOrCreateTeamGame(
          tId: widget.tId,
          teamAId: teamA.teamId,
          teamBId: teamB.teamId,
        );

    await fSvc.saveGoalResult(
      eventId: eventId,
      teamAEntityId: teamA.entityId!,
      teamBEntityId: teamB.entityId!,
      goalsA: result.goalsA,
      goalsB: result.goalsB,
    );

    await _loadData();
  }

  Future<void> _deleteGame(int eventId) async {
    final fSvc = ref.read(futsalServiceProvider);
    await fSvc.deleteTeamGame(eventId);
    await _loadData();
  }

  void _confirmClearResults() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Очистити результати?'),
        content: const Text('Видалити всі результати ігор у таблиці?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Скасувати')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              _clearAllResults();
            },
            child: const Text('Очистити', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _clearAllResults() async {
    final fSvc = ref.read(futsalServiceProvider);
    final eventIds = _games.values.map((g) => g.eventId).toSet();
    for (final id in eventIds) {
      await fSvc.deleteTeamGame(id);
    }
    await _loadData();
  }

  Widget _headerCell(String text) {
    return Container(
      height: 36,
      alignment: Alignment.center,
      color: Colors.grey.shade100,
      child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  Widget _dataCell(String text, {bool bold = false}) {
    return Container(
      height: 36,
      alignment: Alignment.center,
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.bold : null)),
    );
  }

  Widget _teamNameCell(String name) {
    return Container(
      height: 36,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(name, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
    );
  }
}

class _GameData {
  final int eventId;
  final String? eventResult;
  _GameData({required this.eventId, this.eventResult});
}
