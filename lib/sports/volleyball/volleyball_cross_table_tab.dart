import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../viewmodels/team_viewmodel.dart';
import 'volleyball_providers.dart';
import 'volleyball_service.dart';
import 'volleyball_scoring.dart' as scoring;

/// Volleyball cross-table tab.
///
/// Mode A (< 9 teams): Single team-vs-team round-robin cross-table.
/// Mode B (≥ 9 teams): Segmented view with groups, finals, and consolation.
class VolleyballCrossTableTab extends ConsumerStatefulWidget {
  final int tId;
  final String tournamentName;

  const VolleyballCrossTableTab({
    super.key,
    required this.tId,
    required this.tournamentName,
  });

  @override
  ConsumerState<VolleyballCrossTableTab> createState() => _VolleyballCrossTableTabState();
}

class _VolleyballCrossTableTabState extends ConsumerState<VolleyballCrossTableTab> {
  bool _loading = true;
  List<({int teamId, String teamName, int? teamNumber, int? entityId})> _teams = [];
  Map<(int, int), _GameData> _games = {}; // (teamAEntityId, teamBEntityId) → data
  Map<int, String> _groupAssignments = {};
  Set<int> _removedTeamIds = {};
  int _selectedSegment = 0; // 0=Групи, 1=Фінал, 2+=Місця

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
    final vSvc = ref.read(volleyballServiceProvider);

    final teamList = await teamSvc.getTeamListForTournament(widget.tId);
    final games = await vSvc.getTeamGamesForTournament(widget.tId);
    final groups = await vSvc.getGroupAssignments(widget.tId);
    final removed = await vSvc.getRemovedTeamIds(widget.tId);

    // Build teams with entity_ids
    final teams = <({int teamId, String teamName, int? teamNumber, int? entityId})>[];
    for (final t in teamList) {
      // Look up entity_id
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
        detail: g.teamADetail,
        eventResult: g.eventResult,
        esId: g.esId,
      );
      // Mirror: store reverse direction with team B's detail
      gamesMap[(g.teamBEntityId, g.teamAEntityId)] = _GameData(
        eventId: g.eventId,
        detail: g.teamBDetail,
        eventResult: g.eventResult,
        esId: g.esId,
      );
    }

    setState(() {
      _teams = teams;
      _games = gamesMap;
      _groupAssignments = groups;
      _removedTeamIds = removed;
      _loading = false;
    });
  }

  bool get _useGroupMode => _teams.length >= 9 && _groupAssignments.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_teams.isEmpty) {
      return const Center(
        child: Text('Додайте команди для відображення таблиці'),
      );
    }

    if (_useGroupMode) {
      return _buildGroupModeView();
    }

    return _buildSimpleCrossTable(_teams);
  }

  // --- Simple Round-Robin Cross-Table (< 9 teams) ---

  Widget _buildSimpleCrossTable(
    List<({int teamId, String teamName, int? teamNumber, int? entityId})> teams, {
    Map<(int, int), _GameData>? carryOverGames,
    bool readOnlyCarryOver = false,
  }) {
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
                Text(
                  'Турнірна таблиця',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
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
                Text(
                  '${teams.length} команд',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
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
                      child: _buildCrossTableGrid(teams, standings, carryOverGames: carryOverGames, readOnlyCarryOver: readOnlyCarryOver),
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

  Widget _buildCrossTableGrid(
    List<({int teamId, String teamName, int? teamNumber, int? entityId})> teams,
    List<scoring.VolleyballStanding> standings, {
    Map<(int, int), _GameData>? carryOverGames,
    bool readOnlyCarryOver = false,
  }) {
    const cellWidth = 56.0;
    const nameWidth = 180.0;
    const rankWidth = 36.0;
    const statsWidth = 56.0;
    const separatorWidth = 4.0;

    final standingsByTeam = {for (final s in standings) s.teamId: s};

    // Column indices:
    // 0: rank, 1: name, 2..n+1: opponent cells, n+2: О, n+3: П, n+4: Р
    // n+5: separator, n+6: команда, n+7: очки, n+8: місце
    final n = teams.length;

    return Table(
      defaultColumnWidth: const FixedColumnWidth(cellWidth),
      columnWidths: {
        0: const FixedColumnWidth(rankWidth),
        1: const FixedColumnWidth(nameWidth),
        n + 2: const FixedColumnWidth(statsWidth),
        n + 3: const FixedColumnWidth(statsWidth),
        n + 4: const FixedColumnWidth(statsWidth),
        n + 5: const FixedColumnWidth(separatorWidth),
        n + 6: const FixedColumnWidth(nameWidth),
        n + 7: const FixedColumnWidth(statsWidth),
        n + 8: const FixedColumnWidth(rankWidth),
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
              _headerCell('${j + 1}'),
            _headerCell('О'),
            _headerCell('П'),
            _headerCell('Р'),
            // Separator
            Container(height: 36, color: Colors.black),
            // Standings headers
            _headerCell('Команда'),
            _headerCell('Очки'),
            _headerCell('Місце'),
          ],
        ),
        // Data rows
        for (int i = 0; i < n; i++)
          _buildTeamRow(i, teams, standingsByTeam, standings, carryOverGames: carryOverGames, readOnlyCarryOver: readOnlyCarryOver),
      ],
    );
  }

  TableRow _buildTeamRow(
    int i,
    List<({int teamId, String teamName, int? teamNumber, int? entityId})> teams,
    Map<int, scoring.VolleyballStanding> standingsByTeam,
    List<scoring.VolleyballStanding> sortedStandings, {
    Map<(int, int), _GameData>? carryOverGames,
    bool readOnlyCarryOver = false,
  }) {
    final team = teams[i];
    final standing = standingsByTeam[team.teamId];
    final isRemoved = _removedTeamIds.contains(team.teamId);

    // Standings row (sorted by place)
    final standingRow = i < sortedStandings.length ? sortedStandings[i] : null;

    return TableRow(
      decoration: BoxDecoration(
        color: isRemoved
            ? Colors.grey.shade200
            : _hoveredRow == i
                ? Colors.indigo.shade50
                : null,
      ),
      children: [
        // Rank
        _dataCell('${standing?.rank ?? i + 1}', bold: true),
        // Team name
        _teamNameCell(team.teamName, isRemoved: isRemoved),
        // Opponent cells
        for (int j = 0; j < teams.length; j++)
          _buildGameCell(i, j, teams, carryOverGames: carryOverGames, readOnlyCarryOver: readOnlyCarryOver),
        // Points
        _dataCell('${standing?.matchPoints ?? 0}', bold: true),
        // Set ratio
        _dataCell('${standing?.setsWon ?? 0}:${standing?.setsLost ?? 0}'),
        // Point ratio
        _dataCell('${standing?.pointsScored ?? 0}:${standing?.pointsConceded ?? 0}'),
        // Black separator
        Container(height: 36, color: Colors.black),
        // Standings: team name, points, place
        _teamNameCell(standingRow?.teamName ?? ''),
        _dataCell('${standingRow?.matchPoints ?? 0}', bold: true),
        _dataCell('${standingRow?.rank ?? i + 1}', bold: true),
      ],
    );
  }

  Widget _buildGameCell(
    int i,
    int j,
    List<({int teamId, String teamName, int? teamNumber, int? entityId})> teams, {
    Map<(int, int), _GameData>? carryOverGames,
    bool readOnlyCarryOver = false,
  }) {
    if (i == j) {
      return Container(
        height: 36,
        color: Colors.grey.shade300,
      );
    }

    final teamA = teams[i];
    final teamB = teams[j];
    if (teamA.entityId == null || teamB.entityId == null) {
      return const SizedBox(height: 36);
    }

    final game = _games[(teamA.entityId!, teamB.entityId!)];
    final isCarryOver = carryOverGames != null &&
        carryOverGames.containsKey((teamA.entityId!, teamB.entityId!));
    final isRemoved = _removedTeamIds.contains(teamA.teamId) ||
        _removedTeamIds.contains(teamB.teamId);

    String cellText = '';
    Color? bgColor;

    if (game != null && game.detail != null) {
      cellText = scoring.formatVolleyballCell(game.detail!);
      if (scoring.isMatchWinner(game.detail!)) {
        bgColor = Colors.green.shade50;
      } else {
        bgColor = Colors.red.shade50;
      }
    } else if (game != null && game.esId == 4) {
      cellText = '-';
      bgColor = Colors.orange.shade50;
    }

    if (isCarryOver) {
      bgColor = Colors.amber.shade50;
    }
    if (isRemoved) {
      bgColor = Colors.grey.shade200;
    }

    final isReadOnly = isRemoved || (isCarryOver && readOnlyCarryOver);

    return MouseRegion(
      onEnter: (_) => setState(() {
        _hoveredRow = i;
        _hoveredCol = j;
      }),
      onExit: (_) => setState(() {
        _hoveredRow = null;
        _hoveredCol = null;
      }),
      child: GestureDetector(
        onTap: isReadOnly
            ? null
            : () => _showSetScoreDialog(teamA, teamB, game),
        child: Container(
          height: 36,
          alignment: Alignment.center,
          color: bgColor ?? (_hoveredCol == j && _hoveredRow == i ? Colors.indigo.shade50 : null),
          child: Text(
            cellText,
            style: TextStyle(
              fontSize: 12,
              fontWeight: cellText.isNotEmpty ? FontWeight.w500 : null,
              color: isRemoved ? Colors.grey : null,
            ),
          ),
        ),
      ),
    );
  }

  // --- Group Mode (≥ 9 teams) ---

  Widget _buildGroupModeView() {
    final groupNames = _groupAssignments.values.toSet().toList()..sort();

    return Column(
      children: [
        // Segmented control
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SegmentedButton<int>(
            segments: [
              const ButtonSegment(value: 0, label: Text('Групи')),
              const ButtonSegment(value: 1, label: Text('Фінал (1-8)')),
              if (_teams.length > 8)
                ButtonSegment(value: 2, label: Text('Місця 9-${_teams.length}')),
            ],
            selected: {_selectedSegment},
            onSelectionChanged: (v) => setState(() => _selectedSegment = v.first),
          ),
        ),
        // Content
        Expanded(
          child: _selectedSegment == 0
              ? _buildGroupsView(groupNames)
              : _selectedSegment == 1
                  ? _buildFinalsView(groupNames)
                  : _buildConsolationView(groupNames),
        ),
      ],
    );
  }

  Widget _buildGroupsView(List<String> groupNames) {
    return ListView(
      children: [
        for (final groupName in groupNames) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 8),
            child: Text(
              'Група $groupName',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          SizedBox(
            height: _getGroupTeams(groupName).length * 40.0 + 100,
            child: _buildSimpleCrossTable(_getGroupTeams(groupName)),
          ),
        ],
      ],
    );
  }

  Widget _buildFinalsView(List<String> groupNames) {
    // Top 2 from each group
    final finalists = <({int teamId, String teamName, int? teamNumber, int? entityId})>[];
    for (final groupName in groupNames) {
      final groupTeams = _getGroupTeams(groupName);
      final standings = _calculateStandings(groupTeams);
      for (int i = 0; i < 2 && i < standings.length; i++) {
        final s = standings[i];
        final team = groupTeams.where((t) => t.teamId == s.teamId).firstOrNull;
        if (team != null) finalists.add(team);
      }
    }

    // Carry-over: games between finalists who were in the same group
    final carryOver = <(int, int), _GameData>{};
    for (int i = 0; i < finalists.length; i++) {
      for (int j = i + 1; j < finalists.length; j++) {
        final a = finalists[i];
        final b = finalists[j];
        if (a.entityId == null || b.entityId == null) continue;
        // Same group?
        final groupA = _groupAssignments[a.teamId];
        final groupB = _groupAssignments[b.teamId];
        if (groupA == groupB && groupA != null) {
          final game = _games[(a.entityId!, b.entityId!)];
          if (game != null) {
            carryOver[(a.entityId!, b.entityId!)] = game;
          }
        }
      }
    }

    if (finalists.isEmpty) {
      return const Center(child: Text('Спочатку проведіть груповий етап'));
    }

    return _buildSimpleCrossTable(
      finalists,
      carryOverGames: carryOver,
      readOnlyCarryOver: true,
    );
  }

  Widget _buildConsolationView(List<String> groupNames) {
    // Teams that didn't make finals (3rd place and below from each group)
    final consolation = <({int teamId, String teamName, int? teamNumber, int? entityId})>[];
    for (final groupName in groupNames) {
      final groupTeams = _getGroupTeams(groupName);
      final standings = _calculateStandings(groupTeams);
      for (int i = 2; i < standings.length; i++) {
        final s = standings[i];
        final team = groupTeams.where((t) => t.teamId == s.teamId).firstOrNull;
        if (team != null) consolation.add(team);
      }
    }

    // Carry-over for consolation teams from same group
    final carryOver = <(int, int), _GameData>{};
    for (int i = 0; i < consolation.length; i++) {
      for (int j = i + 1; j < consolation.length; j++) {
        final a = consolation[i];
        final b = consolation[j];
        if (a.entityId == null || b.entityId == null) continue;
        final groupA = _groupAssignments[a.teamId];
        final groupB = _groupAssignments[b.teamId];
        if (groupA == groupB && groupA != null) {
          final game = _games[(a.entityId!, b.entityId!)];
          if (game != null) {
            carryOver[(a.entityId!, b.entityId!)] = game;
          }
        }
      }
    }

    if (consolation.isEmpty) {
      return const Center(child: Text('Немає команд для розіграшу'));
    }

    return _buildSimpleCrossTable(
      consolation,
      carryOverGames: carryOver,
      readOnlyCarryOver: true,
    );
  }

  List<({int teamId, String teamName, int? teamNumber, int? entityId})> _getGroupTeams(String groupName) {
    return _teams.where((t) => _groupAssignments[t.teamId] == groupName).toList();
  }

  // --- Standings Calculation ---

  List<scoring.VolleyballStanding> _calculateStandings(
    List<({int teamId, String teamName, int? teamNumber, int? entityId})> teams,
  ) {
    // Build games map for these teams only (one direction per game to avoid double-counting)
    final teamEntityIds = teams.map((t) => t.entityId).whereType<int>().toSet();
    final filteredGames = <(int, int), String>{};
    final seenPairs = <(int, int)>{};

    for (final entry in _games.entries) {
      final (aEntId, bEntId) = entry.key;
      if (teamEntityIds.contains(aEntId) && teamEntityIds.contains(bEntId)) {
        // Skip if we've already added the reverse direction
        if (seenPairs.contains((bEntId, aEntId))) continue;
        seenPairs.add((aEntId, bEntId));
        final detail = entry.value.detail;
        if (detail != null) {
          filteredGames[(aEntId, bEntId)] = detail;
        }
      }
    }

    return scoring.calculateStandings(
      teams: teams.map((t) => (teamId: t.teamId, teamName: t.teamName, entityId: t.entityId)).toList(),
      games: filteredGames,
      removedTeamIds: _removedTeamIds,
    );
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
    final vSvc = ref.read(volleyballServiceProvider);
    final eventIds = _games.values.map((g) => g.eventId).toSet();
    for (final id in eventIds) {
      await vSvc.deleteTeamGame(id);
    }
    await _loadData();
  }

  // --- Set Score Dialog ---

  Future<void> _showSetScoreDialog(
    ({int teamId, String teamName, int? teamNumber, int? entityId}) teamA,
    ({int teamId, String teamName, int? teamNumber, int? entityId}) teamB,
    _GameData? existingGame,
  ) async {
    // Parse existing sets if available
    final existingSets = <({int a, int b})>[];
    if (existingGame?.detail != null) {
      for (final s in existingGame!.detail!.split(' ')) {
        final parts = s.split(':');
        if (parts.length == 2) {
          existingSets.add((
            a: int.tryParse(parts[0]) ?? 0,
            b: int.tryParse(parts[1]) ?? 0,
          ));
        }
      }
    }
    // Pad to 3 sets
    while (existingSets.length < 3) {
      existingSets.add((a: 0, b: 0));
    }

    final controllers = <List<TextEditingController>>[];
    for (final set in existingSets) {
      controllers.add([
        TextEditingController(text: set.a > 0 ? '${set.a}' : ''),
        TextEditingController(text: set.b > 0 ? '${set.b}' : ''),
      ]);
    }

    final result = await showDialog<List<({int a, int b})>?>(
      context: context,
      builder: (ctx) => _SetScoreDialog(
        teamAName: teamA.teamName,
        teamBName: teamB.teamName,
        controllers: controllers,
      ),
    );

    if (result == null) return;

    // Filter out empty sets
    final validSets = result.where((s) => s.a > 0 || s.b > 0).toList();
    if (validSets.isEmpty) {
      // Delete existing game if it exists
      if (existingGame != null) {
        final vSvc = ref.read(volleyballServiceProvider);
        await vSvc.deleteTeamGame(existingGame.eventId);
      }
      await _loadData();
      return;
    }

    final vSvc = ref.read(volleyballServiceProvider);
    final eventId = existingGame?.eventId ??
        await vSvc.findOrCreateTeamGame(
          tId: widget.tId,
          teamAId: teamA.teamId,
          teamBId: teamB.teamId,
        );

    await vSvc.saveSetResults(
      eventId: eventId,
      teamAEntityId: teamA.entityId!,
      teamBEntityId: teamB.entityId!,
      sets: validSets,
    );

    // Check for no-shows and auto-removal
    await _checkNoShows(teamA.teamId);
    await _checkNoShows(teamB.teamId);

    await _loadData();
  }

  Future<void> _checkNoShows(int teamId) async {
    final vSvc = ref.read(volleyballServiceProvider);
    final count = await vSvc.countNoShows(widget.tId, teamId);
    if (count >= 2) {
      await vSvc.markTeamRemoved(widget.tId, teamId);
    }
  }

  // --- Helper Widgets ---

  Widget _headerCell(String text) {
    return Container(
      height: 36,
      alignment: Alignment.center,
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _dataCell(String text, {bool bold = false}) {
    return Container(
      height: 36,
      alignment: Alignment.center,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: bold ? FontWeight.bold : null,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _teamNameCell(String name, {bool isRemoved = false}) {
    return Container(
      height: 36,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        name,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: isRemoved ? Colors.grey : null,
          decoration: isRemoved ? TextDecoration.lineThrough : null,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

}

// --- Data Classes ---

class _GameData {
  final int eventId;
  final String? detail;
  final String? eventResult;
  final int? esId;

  const _GameData({
    required this.eventId,
    this.detail,
    this.eventResult,
    this.esId,
  });
}

// --- Set Score Dialog ---

class _SetScoreDialog extends StatefulWidget {
  final String teamAName;
  final String teamBName;
  final List<List<TextEditingController>> controllers;

  const _SetScoreDialog({
    required this.teamAName,
    required this.teamBName,
    required this.controllers,
  });

  @override
  State<_SetScoreDialog> createState() => _SetScoreDialogState();
}

class _SetScoreDialogState extends State<_SetScoreDialog> {
  @override
  Widget build(BuildContext context) {
    // Determine if set 3 should be enabled
    int aWon = 0, bWon = 0;
    for (int i = 0; i < 2; i++) {
      final a = int.tryParse(widget.controllers[i][0].text) ?? 0;
      final b = int.tryParse(widget.controllers[i][1].text) ?? 0;
      if (a > b && a > 0) aWon++;
      else if (b > a && b > 0) bWon++;
    }
    final set3Enabled = aWon == 1 && bWon == 1;

    return AlertDialog(
      title: Text(
        '${widget.teamAName} — ${widget.teamBName}',
        style: const TextStyle(fontSize: 16),
      ),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                const SizedBox(width: 60),
                Expanded(
                  child: Text(
                    widget.teamAName,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.teamBName,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (int i = 0; i < 3; i++) ...[
              _buildSetRow(i, enabled: i < 2 || set3Enabled),
              if (i < 2) const SizedBox(height: 8),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Скасувати'),
        ),
        FilledButton(
          onPressed: () {
            final sets = <({int a, int b})>[];
            for (int i = 0; i < 3; i++) {
              final a = int.tryParse(widget.controllers[i][0].text) ?? 0;
              final b = int.tryParse(widget.controllers[i][1].text) ?? 0;
              sets.add((a: a, b: b));
            }
            Navigator.pop(context, sets);
          },
          child: const Text('Зберегти'),
        ),
      ],
    );
  }

  Widget _buildSetRow(int setNum, {bool enabled = true}) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              'Сет ${setNum + 1}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: widget.controllers[setNum][0],
                enabled: enabled,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(':', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: widget.controllers[setNum][1],
                enabled: enabled,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
