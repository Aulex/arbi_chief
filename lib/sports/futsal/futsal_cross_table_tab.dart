import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_colors.dart';
import '../../viewmodels/team_viewmodel.dart';
import 'futsal_providers.dart';
import 'futsal_scoring.dart' as scoring;

/// Futsal team-vs-team cross-table tab.
///
/// Mode A (< 9 teams or no groups): single round-robin cross-table.
/// Mode B (groups assigned): segmented view with per-group tables, finals, and consolation.
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
  AppColors get _ct => context.appColors;

  bool _loading = true;
  List<({int teamId, String teamName, int? teamNumber, int? entityId})> _teams = [];
  Map<(int, int), _GameData> _games = {};
  Map<int, String> _groupAssignments = {};
  Set<int> _removedTeamIds = {};
  Set<(int, int)> _noShowGamePairs = {};
  int _selectedSegment = 0; // 0=Групи/Таблиця, 1=Фінал, 2=Місця 9+

  int? _hoveredRow;
  int? _hoveredCol;

  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();

  final Map<String, ScrollController> _groupVertControllers = {};
  final Map<String, ScrollController> _groupHorizControllers = {};

  ScrollController _groupVert(String g) =>
      _groupVertControllers.putIfAbsent(g, () => ScrollController());
  ScrollController _groupHoriz(String g) =>
      _groupHorizControllers.putIfAbsent(g, () => ScrollController());

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    for (final c in _groupVertControllers.values) c.dispose();
    for (final c in _groupHorizControllers.values) c.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final teamSvc = ref.read(teamServiceProvider);
    final fSvc = ref.read(futsalServiceProvider);

    final teamList = await teamSvc.getTeamListForTournament(widget.tId);
    final games = await fSvc.getTeamGamesForTournament(widget.tId);
    final groups = await fSvc.getGroupAssignments(widget.tId);
    final removed = await fSvc.getRemovedTeamIds(widget.tId);

    final allTeams = await teamSvc.getAllTeams();
    final teams = <({int teamId, String teamName, int? teamNumber, int? entityId})>[];
    for (final t in teamList) {
      final team = allTeams.where((at) => at.team_id == t.teamId).firstOrNull;
      var entityId = team?.entity_id;
      if (entityId == null && team != null) {
        entityId = await fSvc.ensureTeamEntity(t.teamId);
      }
      teams.add((
        teamId: t.teamId,
        teamName: t.teamName,
        teamNumber: t.teamNumber,
        entityId: entityId,
      ));
    }

    final gamesMap = <(int, int), _GameData>{};
    final noShowPairs = <(int, int)>{};
    for (final g in games) {
      gamesMap[(g.teamAEntityId, g.teamBEntityId)] = _GameData(
        eventId: g.eventId,
        eventResult: g.eventResult,
        esId: g.esId,
      );
      gamesMap[(g.teamBEntityId, g.teamAEntityId)] = _GameData(
        eventId: g.eventId,
        eventResult: g.eventResult != null ? _mirrorResult(g.eventResult!) : null,
        esId: g.esId,
      );
      if (g.esId == 4) {
        noShowPairs.add((g.teamAEntityId, g.teamBEntityId));
      }
    }

    setState(() {
      _teams = teams;
      _games = gamesMap;
      _groupAssignments = groups;
      _removedTeamIds = removed;
      _noShowGamePairs = noShowPairs;
      _loading = false;
    });
  }

  String _mirrorResult(String result) {
    final parts = result.split(':');
    if (parts.length != 2) return result;
    return '${parts[1]}:${parts[0]}';
  }

  /// Group mode is active only when there are enough teams (≥ 9) AND
  /// at least one team is actually assigned to a group. This prevents
  /// stale group assignments from triggering the group view after teams
  /// have been removed from the tournament.
  bool get _useGroupMode => _teams.length >= 9 && _groupAssignments.isNotEmpty;

  List<({int teamId, String teamName, int? teamNumber, int? entityId})> _getGroupTeams(
      String groupName) {
    return _teams.where((t) => _groupAssignments[t.teamId] == groupName).toList();
  }

  /// Top [count] teams from a group by current standings.
  List<({int teamId, String teamName, int? teamNumber, int? entityId})> _getTopTeamsFromGroup(
      String groupName, int count) {
    final groupTeams = _getGroupTeams(groupName);
    final standings = _calculateStandings(groupTeams);
    return standings
        .take(count)
        .map((s) => groupTeams.firstWhere((t) => t.teamId == s.teamId))
        .toList();
  }

  /// Teams from position [startRank] (1-based) onward in a group.
  List<({int teamId, String teamName, int? teamNumber, int? entityId})> _getRestTeamsFromGroup(
      String groupName, int startRank) {
    final groupTeams = _getGroupTeams(groupName);
    final standings = _calculateStandings(groupTeams);
    return standings
        .skip(startRank - 1)
        .map((s) => groupTeams.firstWhere((t) => t.teamId == s.teamId))
        .toList();
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
      removedTeamIds: _removedTeamIds,
      noShowGamePairs: _noShowGamePairs,
    );
  }

  /// Build carry-over games map: only games between teams that were in the same group.
  Map<(int, int), _GameData> _buildCarryOverGames(
      List<({int teamId, String teamName, int? teamNumber, int? entityId})> teams) {
    final carryOver = <(int, int), _GameData>{};
    for (int i = 0; i < teams.length; i++) {
      for (int j = i + 1; j < teams.length; j++) {
        final a = teams[i];
        final b = teams[j];
        if (a.entityId == null || b.entityId == null) continue;
        final groupA = _groupAssignments[a.teamId];
        final groupB = _groupAssignments[b.teamId];
        if (groupA == groupB && groupA != null) {
          final game = _games[(a.entityId!, b.entityId!)];
          if (game != null) carryOver[(a.entityId!, b.entityId!)] = game;
        }
      }
    }
    return carryOver;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_teams.isEmpty) {
      return const Center(child: Text('Додайте команди для відображення таблиці'));
    }

    if (_useGroupMode) return _buildGroupModeView();
    return _buildRoundRobinTable(_teams, _verticalController, _horizontalController);
  }

  // ─── Group Mode ───────────────────────────────────────────────────────────

  Widget _buildGroupModeView() {
    final groupNames = _groupAssignments.values.toSet().toList()..sort();
    final segments = <ButtonSegment<int>>[
      const ButtonSegment(value: 0, label: Text('Підгрупи')),
      const ButtonSegment(value: 1, label: Text('Фінал (місця 1–8)')),
      const ButtonSegment(value: 2, label: Text('За місцями (9+)')),
    ];

    final validValues = segments.map((s) => s.value).toSet();
    if (!validValues.contains(_selectedSegment)) _selectedSegment = 0;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<int>(
              segments: segments,
              selected: {_selectedSegment},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() => _selectedSegment = v.first),
            ),
          ),
        ),
        Expanded(child: _buildSegmentContent(groupNames)),
      ],
    );
  }

  Widget _buildSegmentContent(List<String> groupNames) {
    switch (_selectedSegment) {
      case 0:
        return _buildGroupsView(groupNames);
      case 1:
        return _buildFinalsView(groupNames);
      case 2:
        return _buildConsolationView(groupNames);
      default:
        return _buildGroupsView(groupNames);
    }
  }

  Widget _buildGroupsView(List<String> groupNames) {
    if (groupNames.isEmpty) {
      return Center(
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: Colors.grey.shade300, width: 1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'Призначте команди до груп у вкладці "Групи", щоб відкрити фінальний та розрахунковий етапи.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (groupNames.length == 1) {
      final g = groupNames.first;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Група $g', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: _buildRoundRobinTable(
              _getGroupTeams(g),
              _groupVert(g),
              _groupHoriz(g),
            ),
          ),
        ],
      );
    }

    return ListView(
      children: [
        for (final g in groupNames) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 8),
            child: Text('Група $g', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          SizedBox(
            height: _getGroupTeams(g).length * 40.0 + 120,
            child: _buildRoundRobinTable(
              _getGroupTeams(g),
              _groupVert(g),
              _groupHoriz(g),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFinalsView(List<String> groupNames) {
    if (groupNames.isEmpty) {
      return const Center(child: Text('Спочатку призначте команди до груп'));
    }
    final finalists = groupNames.expand((g) => _getTopTeamsFromGroup(g, 2)).toList();
    if (finalists.isEmpty) {
      return const Center(child: Text('Спочатку проведіть груповий етап'));
    }
    final carryOver = _buildCarryOverGames(finalists);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Фінал — місця 1–${finalists.length} (враховуються результати підгрупового етапу)',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: _buildRoundRobinTable(
            finalists,
            _verticalController,
            _horizontalController,
            carryOverGames: carryOver,
            readOnlyCarryOver: true,
          ),
        ),
      ],
    );
  }

  Widget _buildConsolationView(List<String> groupNames) {
    if (groupNames.isEmpty) {
      return const Center(child: Text('Спочатку призначте команди до груп'));
    }

    // Teams from position 3+ in each group
    final consolationTeams = groupNames.expand((g) => _getRestTeamsFromGroup(g, 3)).toList();

    if (consolationTeams.isEmpty) {
      return const Center(
        child: Text('Немає команд для розіграшу місць (потрібно по ≥ 3 команди в підгрупі)'),
      );
    }

    // Group consolation teams into pools of ~4 for places 9-16, 17-24, etc.
    // For simplicity, show them all in one round-robin with carry-over results.
    final carryOver = _buildCarryOverGames(consolationTeams);
    final startPlace = groupNames.length * 2 + 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Місця $startPlace+ (враховуються результати підгрупового етапу)',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: _buildRoundRobinTable(
            consolationTeams,
            _verticalController,
            _horizontalController,
            carryOverGames: carryOver,
            readOnlyCarryOver: true,
          ),
        ),
      ],
    );
  }

  // ─── Round-Robin Cross-Table ──────────────────────────────────────────────

  Widget _buildRoundRobinTable(
    List<({int teamId, String teamName, int? teamNumber, int? entityId})> teams,
    ScrollController vertCtrl,
    ScrollController horizCtrl, {
    Map<(int, int), _GameData>? carryOverGames,
    bool readOnlyCarryOver = false,
  }) {
    final standings = _calculateStandings(teams);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: _ct.tableBorder, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Турнірна таблиця',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (_games.isNotEmpty && !_useGroupMode)
                  TextButton.icon(
                    icon: const Icon(Icons.delete_sweep_outlined, size: 14),
                    label: const Text('Очистити', style: TextStyle(fontSize: 11)),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _confirmClearResults,
                  ),
                const SizedBox(width: 8),
                Text('${teams.length} команд',
                    style: TextStyle(fontSize: 12, color: _ct.mutedText)),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Scrollbar(
                controller: vertCtrl,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: vertCtrl,
                  child: Scrollbar(
                    controller: horizCtrl,
                    thumbVisibility: true,
                    notificationPredicate: (n) => n.depth == 1,
                    child: SingleChildScrollView(
                      controller: horizCtrl,
                      scrollDirection: Axis.horizontal,
                      child: _buildGrid(teams, standings,
                          carryOverGames: carryOverGames,
                          readOnlyCarryOver: readOnlyCarryOver),
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
    List<scoring.FutsalStanding> standings, {
    Map<(int, int), _GameData>? carryOverGames,
    bool readOnlyCarryOver = false,
  }) {
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
        n + 2: const FixedColumnWidth(statsWidth),
        n + 3: const FixedColumnWidth(statsWidth),
        n + 4: const FixedColumnWidth(statsWidth),
        n + 5: const FixedColumnWidth(separatorWidth),
        n + 6: const FixedColumnWidth(nameWidth),
        n + 7: const FixedColumnWidth(statsWidth),
        n + 8: const FixedColumnWidth(placeWidth),
      },
      border: TableBorder.all(color: _ct.tableBorder, width: 0.5),
      children: [
        TableRow(
          decoration: BoxDecoration(color: _ct.tableHeaderBg),
          children: [
            _headerCell('#'),
            _headerCell('Команда'),
            for (int j = 0; j < n; j++) _headerCell('${teams[j].teamNumber ?? j + 1}'),
            _headerCell('О'),
            _headerCell('М'),
            _headerCell('Р'),
            Container(
                height: 36,
                decoration: BoxDecoration(
                    color: _ct.separatorCell,
                    border: Border.all(color: _ct.separatorCell, width: 0.5))),
            _headerCell('Команда'),
            _headerCell('Очки'),
            _headerCell('Місце'),
          ],
        ),
        for (int i = 0; i < n; i++)
          _buildTeamRow(i, teams, standingsByTeam, standings,
              carryOverGames: carryOverGames, readOnlyCarryOver: readOnlyCarryOver),
      ],
    );
  }

  TableRow _buildTeamRow(
    int i,
    List<({int teamId, String teamName, int? teamNumber, int? entityId})> teams,
    Map<int, scoring.FutsalStanding> standingsByTeam,
    List<scoring.FutsalStanding> sortedStandings, {
    Map<(int, int), _GameData>? carryOverGames,
    bool readOnlyCarryOver = false,
  }) {
    final team = teams[i];
    final standing = standingsByTeam[team.teamId];
    final standingRow = i < sortedStandings.length ? sortedStandings[i] : null;

    final isRemoved = _removedTeamIds.contains(team.teamId);
    final standingIsRemoved =
        standingRow != null && _removedTeamIds.contains(standingRow.teamId);

    return TableRow(
      decoration: BoxDecoration(
        color: _hoveredRow == i ? _ct.hoverHighlight : null,
      ),
      children: [
        _dataCell('${team.teamNumber ?? i + 1}', bold: true),
        isRemoved
            ? GestureDetector(
                onTap: () => _confirmUndoRemoval(team.teamId, team.teamName),
                child: _teamNameCell(team.teamName, isRemoved: true),
              )
            : _teamNameCell(team.teamName),
        for (int j = 0; j < teams.length; j++)
          _buildGameCell(i, j, teams,
              carryOverGames: carryOverGames, readOnlyCarryOver: readOnlyCarryOver),
        _dataCell('${standing?.matchPoints ?? 0}', bold: true),
        _dataCell('${standing?.goalsScored ?? 0}:${standing?.goalsConceded ?? 0}'),
        _dataCell(
            '${(standing?.goalDifference ?? 0) >= 0 ? '+' : ''}${standing?.goalDifference ?? 0}'),
        Container(
            height: 36,
            decoration: BoxDecoration(
                color: Colors.black,
                border: Border.all(color: Colors.black, width: 0.5))),
        _teamNameCell(standingRow?.teamName ?? '', isRemoved: standingIsRemoved),
        _dataCell('${standingRow?.matchPoints ?? 0}', bold: true),
        _dataCell(standingIsRemoved ? '—' : '${standingRow?.rank ?? i + 1}',
            bold: true),
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
    if (i == j) return Container(height: 36, color: _ct.diagonalCell);

    final teamA = teams[i];
    final teamB = teams[j];
    if (teamA.entityId == null || teamB.entityId == null) {
      return const SizedBox(height: 36);
    }

    final game = _games[(teamA.entityId!, teamB.entityId!)];
    final isCarryOver = carryOverGames != null &&
        (carryOverGames.containsKey((teamA.entityId!, teamB.entityId!)) ||
            carryOverGames.containsKey((teamB.entityId!, teamA.entityId!)));
    final isRemoved =
        _removedTeamIds.contains(teamA.teamId) || _removedTeamIds.contains(teamB.teamId);

    String cellText = '';
    Color? bgColor;
    Color? fgColor;

    if (game != null && game.eventResult != null) {
      cellText = game.eventResult!;
      final parts = cellText.split(':');
      if (parts.length == 2) {
        final a = int.tryParse(parts[0]) ?? 0;
        final b = int.tryParse(parts[1]) ?? 0;
        if (game.esId == 4) {
          bgColor = _ct.resultSpecialBg;
          fgColor = _ct.resultSpecialFg;
        } else if (a > b) {
          bgColor = _ct.resultWinBg;
          fgColor = _ct.resultWinFg;
        } else if (a < b) {
          bgColor = _ct.resultLossBg;
          fgColor = _ct.resultLossFg;
        } else {
          bgColor = _ct.resultDrawBg;
          fgColor = _ct.resultDrawFg;
        }
      }
    }

    if (isRemoved) {
      bgColor = _ct.disabledCell;
      fgColor = null;
    }

    final readOnly = isRemoved || (isCarryOver && readOnlyCarryOver);

    Widget cellWidget = Container(
      height: 36,
      alignment: Alignment.center,
      color: bgColor ??
          (_hoveredCol == j && _hoveredRow == i ? _ct.hoverHighlight : null),
      child: Text(
        cellText,
        style: TextStyle(
            fontSize: 12,
            fontWeight: cellText.isNotEmpty ? FontWeight.w600 : null,
            color: fgColor),
      ),
    );

    if (isCarryOver && readOnlyCarryOver) {
      cellWidget = Tooltip(
        message: 'Результат перенесено з групи',
        child: cellWidget,
      );
    }

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
        onTap: readOnly ? null : () => _showScoreDialog(teamA, teamB, game),
        child: cellWidget,
      ),
    );
  }

  Future<void> _showScoreDialog(
    ({int teamId, String teamName, int? teamNumber, int? entityId}) teamA,
    ({int teamId, String teamName, int? teamNumber, int? entityId}) teamB,
    _GameData? existingGame,
  ) async {
    int existingGoalsA = 0;
    int existingGoalsB = 0;
    // Don't pre-fill scores from a no-show game (those are forfeit 10:0).
    if (existingGame?.eventResult != null && existingGame!.esId != 4) {
      final parts = existingGame.eventResult!.split(':');
      if (parts.length == 2) {
        existingGoalsA = int.tryParse(parts[0]) ?? 0;
        existingGoalsB = int.tryParse(parts[1]) ?? 0;
      }
    }

    final result = await showDialog<_ScoreDialogResult?>(
      context: context,
      builder: (ctx) => _FutsalScoreDialog(
        teamAName: teamA.teamName,
        teamBName: teamB.teamName,
        initialScoreA: existingGoalsA,
        initialScoreB: existingGoalsB,
        hasExisting: existingGame != null,
        onDelete: existingGame != null
            ? () {
                Navigator.pop(ctx);
                _deleteGame(existingGame.eventId);
              }
            : null,
      ),
    );

    if (result == null) return;

    final fSvc = ref.read(futsalServiceProvider);

    // No-show: 10:0 forfeit per futsal rules.
    if (result.noShowTeam != null) {
      final eventId = existingGame?.eventId ??
          await fSvc.findOrCreateTeamGame(
            tId: widget.tId,
            teamAId: teamA.teamId,
            teamBId: teamB.teamId,
          );
      final noShowIsA = result.noShowTeam == 'A';
      await fSvc.saveGoalResult(
        eventId: eventId,
        teamAEntityId: teamA.entityId!,
        teamBEntityId: teamB.entityId!,
        goalsA: noShowIsA ? 0 : 10,
        goalsB: noShowIsA ? 10 : 0,
        esId: 4,
      );

      await _checkNoShows(teamA.teamId);
      await _checkNoShows(teamB.teamId);
      await _loadData();
      return;
    }

    final goalsA = result.goalsA!;
    final goalsB = result.goalsB!;

    if (goalsA == 0 && goalsB == 0) {
      if (existingGame != null) {
        await fSvc.deleteTeamGame(existingGame.eventId);
      }
      await _loadData();
      return;
    }

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
      goalsA: goalsA,
      goalsB: goalsB,
    );

    await _loadData();
  }

  Future<void> _deleteGame(int eventId) async {
    final fSvc = ref.read(futsalServiceProvider);
    await fSvc.deleteTeamGame(eventId);
    await _loadData();
  }

  /// After saving a no-show, check if [teamId] has 2+ no-shows total.
  /// If so, per the rules, the team is removed from the tournament and
  /// all of their results are annulled.
  Future<void> _checkNoShows(int teamId) async {
    final fSvc = ref.read(futsalServiceProvider);
    final count = await fSvc.countNoShows(widget.tId, teamId);
    if (count >= 2) {
      await fSvc.deleteAllTeamGames(widget.tId, teamId);
      await fSvc.markTeamRemoved(widget.tId, teamId);
    } else {
      await fSvc.unmarkTeamRemoved(widget.tId, teamId);
    }
  }

  Future<void> _confirmUndoRemoval(int teamId, String teamName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Повернути команду?'),
        content: Text('Зняти статус неявки для "$teamName"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('Скасувати')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: const Text('Повернути')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(futsalServiceProvider).unmarkTeamRemoved(widget.tId, teamId);
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
    await fSvc.clearAllRemovedState(widget.tId);
    await _loadData();
  }

  Widget _headerCell(String text) {
    return Container(
      height: 36,
      alignment: Alignment.center,
      color: _ct.tableHeaderBg,
      child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  Widget _dataCell(String text, {bool bold = false}) {
    return Container(
      height: 36,
      alignment: Alignment.center,
      child:
          Text(text, style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.bold : null)),
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
          color: isRemoved ? _ct.mutedText : null,
          decoration: isRemoved ? TextDecoration.lineThrough : null,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _GameData {
  final int eventId;
  final String? eventResult;
  final int? esId;
  _GameData({required this.eventId, this.eventResult, this.esId});
}

/// Result from the score dialog.
/// Either a pair of goal scores, or a no-show indicator for one team.
class _ScoreDialogResult {
  final int? goalsA;
  final int? goalsB;
  /// Which team didn't show: 'A' or 'B', or null for normal result.
  final String? noShowTeam;

  _ScoreDialogResult.goals(this.goalsA, this.goalsB) : noShowTeam = null;
  _ScoreDialogResult.noShow(this.noShowTeam) : goalsA = null, goalsB = null;
}

class _FutsalScoreDialog extends StatefulWidget {
  final String teamAName;
  final String teamBName;
  final int initialScoreA;
  final int initialScoreB;
  final bool hasExisting;
  final VoidCallback? onDelete;

  const _FutsalScoreDialog({
    required this.teamAName,
    required this.teamBName,
    required this.initialScoreA,
    required this.initialScoreB,
    required this.hasExisting,
    this.onDelete,
  });

  @override
  State<_FutsalScoreDialog> createState() => _FutsalScoreDialogState();
}

class _FutsalScoreDialogState extends State<_FutsalScoreDialog> {
  late final TextEditingController _controllerA;
  late final TextEditingController _controllerB;

  @override
  void initState() {
    super.initState();
    _controllerA = TextEditingController(
        text: widget.initialScoreA > 0 ? '${widget.initialScoreA}' : '');
    _controllerB = TextEditingController(
        text: widget.initialScoreB > 0 ? '${widget.initialScoreB}' : '');
  }

  @override
  void dispose() {
    _controllerA.dispose();
    _controllerB.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            Row(
              children: [
                const SizedBox(
                  width: 60,
                  child: Text(
                    'Рахунок',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: TextField(
                      controller: _controllerA,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textAlign: TextAlign.center,
                      autofocus: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(':',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: TextField(
                      controller: _controllerB,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        PopupMenuButton<String>(
          tooltip: 'Неявка команди',
          offset: const Offset(0, -100),
          onSelected: (team) {
            Navigator.pop(context, _ScoreDialogResult.noShow(team));
          },
          itemBuilder: (ctx) => [
            PopupMenuItem(value: 'A', child: Text('Неявка: ${widget.teamAName}')),
            PopupMenuItem(value: 'B', child: Text('Неявка: ${widget.teamBName}')),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.orange.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_off, size: 16, color: Colors.orange.shade700),
                const SizedBox(width: 4),
                Text('Неявка', style: TextStyle(color: Colors.orange.shade700)),
              ],
            ),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.hasExisting && widget.onDelete != null)
              TextButton(
                onPressed: widget.onDelete,
                child: const Text('Видалити', style: TextStyle(color: Colors.red)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Скасувати'),
            ),
            ElevatedButton(
              onPressed: () {
                final a = int.tryParse(_controllerA.text) ?? 0;
                final b = int.tryParse(_controllerB.text) ?? 0;
                Navigator.pop(context, _ScoreDialogResult.goals(a, b));
              },
              child: const Text('Зберегти'),
            ),
          ],
        ),
      ],
    );
  }
}
