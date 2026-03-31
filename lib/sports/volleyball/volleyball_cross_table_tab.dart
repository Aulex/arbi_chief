import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../viewmodels/team_viewmodel.dart';
import '../../viewmodels/tournament_viewmodel.dart';
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
  int _selectedSegment = 0; // 0=Групи, 1=Фінал, 2=Місця(матчі), 3=Місця(колова)

  /// Places from each group that advance to finals (attr_id=10), e.g. [1,2,3].
  List<int> _finalsPlaces = [1, 2];
  /// Places for cross-group match play (attr_id=11), e.g. [4,5].
  List<int> _crossGroupMatchPlaces = [];
  /// Places for round-robin/cycle system (attr_id=12), e.g. [6,7].
  List<int> _cyclePlaces = [];

  int? _hoveredRow;
  int? _hoveredCol;

  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();

  // Per-group scroll controllers (keyed by group name) to avoid sharing
  // a single ScrollController across multiple ScrollPositions.
  final Map<String, ScrollController> _groupVerticalControllers = {};
  final Map<String, ScrollController> _groupHorizontalControllers = {};

  ScrollController _getGroupVerticalController(String group) {
    return _groupVerticalControllers.putIfAbsent(group, () => ScrollController());
  }

  ScrollController _getGroupHorizontalController(String group) {
    return _groupHorizontalControllers.putIfAbsent(group, () => ScrollController());
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    for (final c in _groupVerticalControllers.values) {
      c.dispose();
    }
    for (final c in _groupHorizontalControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    final teamSvc = ref.read(teamServiceProvider);
    final vSvc = ref.read(volleyballServiceProvider);
    final tSvc = ref.read(tournamentServiceProvider);

    final teamList = await teamSvc.getTeamListForTournament(widget.tId);
    final games = await vSvc.getTeamGamesForTournament(widget.tId);
    final groups = await vSvc.getGroupAssignments(widget.tId);
    final removed = await vSvc.getRemovedTeamIds(widget.tId);

    // Load tournament settings for volleyball group mode
    final finalsPlacesStr = await tSvc.getAttrValue(widget.tId, 12);
    final crossGroupStr = await tSvc.getAttrValue(widget.tId, 13);
    final cycleStr = await tSvc.getAttrValue(widget.tId, 14);

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
      _finalsPlaces = _parsePlaces(finalsPlacesStr, defaultPlaces: [1, 2]);
      _crossGroupMatchPlaces = _parsePlaces(crossGroupStr);
      _cyclePlaces = _parsePlaces(cycleStr);
      _loading = false;
    });
  }

  /// Parse comma-separated place numbers like "1,2,3" into [1,2,3].
  List<int> _parsePlaces(String? value, {List<int> defaultPlaces = const []}) {
    if (value == null || value.trim().isEmpty) return defaultPlaces;
    return value
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toList();
  }

  /// Get teams from a group at given 1-based place positions.
  List<({int teamId, String teamName, int? teamNumber, int? entityId})>
      _getTeamsAtPlaces(List<String> groupNames, List<int> places) {
    final result = <({int teamId, String teamName, int? teamNumber, int? entityId})>[];
    for (final groupName in groupNames) {
      final groupTeams = _getGroupTeams(groupName);
      final standings = _calculateStandings(groupTeams);
      for (final place in places) {
        final idx = place - 1; // Convert 1-based to 0-based
        if (idx >= 0 && idx < standings.length) {
          final s = standings[idx];
          final team = groupTeams.where((t) => t.teamId == s.teamId).firstOrNull;
          if (team != null) result.add(team);
        }
      }
    }
    return result;
  }

  /// Build carry-over games map for teams that were in the same group.
  Map<(int, int), _GameData> _buildCarryOverGames(
    List<({int teamId, String teamName, int? teamNumber, int? entityId})> teams,
  ) {
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
          if (game != null) {
            carryOver[(a.entityId!, b.entityId!)] = game;
          }
        }
      }
    }
    return carryOver;
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
    ScrollController? verticalController,
    ScrollController? horizontalController,
  }) {
    final standings = _calculateStandings(teams);
    final vCtrl = verticalController ?? _verticalController;
    final hCtrl = horizontalController ?? _horizontalController;

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
                controller: vCtrl,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: vCtrl,
                  child: Scrollbar(
                    controller: hCtrl,
                    thumbVisibility: true,
                    notificationPredicate: (n) => n.depth == 1,
                    child: SingleChildScrollView(
                      controller: hCtrl,
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
    const placeWidth = 48.0;
    const statsWidth = 56.0;
    const separatorWidth = 15.0;

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
            _headerCell('П'),
            _headerCell('Р'),
            // Separator
            Container(
              height: 36,
              decoration: BoxDecoration(
                color: Colors.black,
                border: Border.all(color: Colors.black, width: 0.5),
              ),
            ),
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
        // Rank (team number from team tab)
        _dataCell('${team.teamNumber ?? i + 1}', bold: true),
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
        Container(
          height: 36,
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border.all(color: Colors.black, width: 0.5),
          ),
        ),
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
    final numGroups = groupNames.length;

    // Calculate overall place ranges for each phase, capped at actual team count
    final totalTeamCount = _teams.length;
    final finalsTeamCount = (_finalsPlaces.length * numGroups).clamp(0, totalTeamCount);
    final crossGroupTeamCount = (_crossGroupMatchPlaces.length * numGroups).clamp(0, totalTeamCount - finalsTeamCount);

    // Build segments dynamically based on configured settings
    final segments = <ButtonSegment<int>>[
      const ButtonSegment(value: 0, label: Text('Групи')),
    ];

    // Segment 1: Finals
    if (_finalsPlaces.isNotEmpty) {
      final endPlace = finalsTeamCount.clamp(1, totalTeamCount);
      final rangeLabel = endPlace == 1 ? '1' : '1–$endPlace';
      segments.add(ButtonSegment(
        value: 1,
        label: Text('Фінальні матчі ($rangeLabel)'),
      ));
    }

    // Segment 2: Cross-group direct matches (стикові матчі)
    if (_crossGroupMatchPlaces.isNotEmpty) {
      final start = finalsTeamCount + 1;
      final end = (finalsTeamCount + crossGroupTeamCount).clamp(start, totalTeamCount);
      final rangeLabel = start == end ? '$start' : '$start–$end';
      segments.add(ButtonSegment(
        value: 2,
        label: Text('Стикові матчі ($rangeLabel)'),
      ));
    }

    // Segment 3: Round-robin/cycle matches (колові матчі)
    if (_cyclePlaces.isNotEmpty) {
      final cycleTeamCount = (_cyclePlaces.length * numGroups).clamp(0, totalTeamCount - finalsTeamCount - crossGroupTeamCount);
      final start = finalsTeamCount + crossGroupTeamCount + 1;
      final end = (finalsTeamCount + crossGroupTeamCount + cycleTeamCount).clamp(start, totalTeamCount);
      final rangeLabel = start == end ? '$start' : '$start–$end';
      segments.add(ButtonSegment(
        value: 3,
        label: Text('Колові матчі ($rangeLabel)'),
      ));
    }

    // Segment 4: Total standings (always last)
    segments.add(const ButtonSegment(
      value: 4,
      label: Text('Підсумок'),
    ));
    final validValues = segments.map((s) => s.value).toSet();
    if (!validValues.contains(_selectedSegment)) {
      _selectedSegment = 0;
    }

    return Column(
      children: [
        // Segmented control
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
        // Content
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
        return _buildCrossGroupMatchView(groupNames);
      case 3:
        return _buildCyclePlacesView(groupNames);
      case 4:
        return _buildTotalStandingsView(groupNames);
      default:
        return _buildGroupsView(groupNames);
    }
  }

  Widget _buildGroupsView(List<String> groupNames) {
    if (groupNames.length == 1) {
      final groupName = groupNames.first;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 8),
            child: Text(
              'Група $groupName',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: _buildSimpleCrossTable(
              _getGroupTeams(groupName),
              verticalController: _getGroupVerticalController(groupName),
              horizontalController: _getGroupHorizontalController(groupName),
            ),
          ),
        ],
      );
    }
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
            height: _getGroupTeams(groupName).length * 40.0 + 120,
            child: _buildSimpleCrossTable(
              _getGroupTeams(groupName),
              verticalController: _getGroupVerticalController(groupName),
              horizontalController: _getGroupHorizontalController(groupName),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFinalsView(List<String> groupNames) {
    final finalists = _getTeamsAtPlaces(groupNames, _finalsPlaces);
    final carryOver = _buildCarryOverGames(finalists);

    if (finalists.isEmpty) {
      return const Center(child: Text('Спочатку проведіть груповий етап'));
    }

    return _buildSimpleCrossTable(
      finalists,
      carryOverGames: carryOver,
      readOnlyCarryOver: true,
    );
  }

  /// Cross-group direct matches for specified places (attr_id=11).
  ///
  /// Each place produces one team per group. Teams at the same place
  /// from different groups play a single direct match (not round-robin).
  Widget _buildCrossGroupMatchView(List<String> groupNames) {
    final numGroups = groupNames.length;
    final finalsTeamCount = _finalsPlaces.length * numGroups;

    // Build match cards for each place
    final matchCards = <Widget>[];
    for (int i = 0; i < _crossGroupMatchPlaces.length; i++) {
      final place = _crossGroupMatchPlaces[i];
      final teamsAtPlace = _getTeamsAtSinglePlace(groupNames, place);

      if (teamsAtPlace.length < 2) continue;

      // Calculate overall placement being contested
      final overallStart = finalsTeamCount + 1 + i * numGroups;
      final overallEnd = overallStart + numGroups - 1;
      final placeLabel = overallStart == overallEnd
          ? 'За $overallStart місце'
          : 'За $overallStart–$overallEnd місце';

      if (teamsAtPlace.length == 2) {
        // Direct match between two teams
        matchCards.add(_buildDirectMatchCard(
          teamsAtPlace[0],
          teamsAtPlace[1],
          title: placeLabel,
          subtitle: '($place місце з груп)',
        ));
      } else {
        // 3+ groups at same place: small round-robin
        matchCards.add(Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 8),
          child: Text(
            '$placeLabel ($place місце з груп)',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ));
        final carryOver = _buildCarryOverGames(teamsAtPlace);
        matchCards.add(SizedBox(
          height: teamsAtPlace.length * 40.0 + 100,
          child: _buildSimpleCrossTable(
            teamsAtPlace,
            carryOverGames: carryOver,
            readOnlyCarryOver: true,
          ),
        ));
      }
    }

    if (matchCards.isEmpty) {
      return const Center(child: Text('Немає команд для розіграшу'));
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: matchCards,
    );
  }

  /// Get teams from all groups at a single 1-based place.
  List<({int teamId, String teamName, int? teamNumber, int? entityId})>
      _getTeamsAtSinglePlace(List<String> groupNames, int place) {
    final result = <({int teamId, String teamName, int? teamNumber, int? entityId})>[];
    for (final groupName in groupNames) {
      final groupTeams = _getGroupTeams(groupName);
      final standings = _calculateStandings(groupTeams);
      final idx = place - 1;
      if (idx >= 0 && idx < standings.length) {
        final s = standings[idx];
        final team = groupTeams.where((t) => t.teamId == s.teamId).firstOrNull;
        if (team != null) result.add(team);
      }
    }
    return result;
  }

  /// Build a card for a single direct match between two teams.
  Widget _buildDirectMatchCard(
    ({int teamId, String teamName, int? teamNumber, int? entityId}) teamA,
    ({int teamId, String teamName, int? teamNumber, int? entityId}) teamB, {
    required String title,
    String? subtitle,
  }) {
    // Look up existing game data
    _GameData? gameData;
    if (teamA.entityId != null && teamB.entityId != null) {
      gameData = _games[(teamA.entityId!, teamB.entityId!)];
    }

    // Parse set details for display
    String scoreDisplay = '—';
    String setDetails = '';
    Color? cardColor;
    if (gameData?.detail != null && gameData!.detail!.isNotEmpty) {
      final detail = gameData.detail!;
      final setResult = scoring.formatVolleyballCell(detail);
      scoreDisplay = setResult;
      setDetails = detail.replaceAll(' ', '  ·  ');
      // Determine winner color
      if (scoring.isMatchWinner(detail)) {
        cardColor = Colors.green.withValues(alpha: 0.08);
      }
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: cardColor,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showSetScoreDialog(teamA, teamB, gameData),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row
              Row(
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              // Match row: Team A — score — Team B
              Row(
                children: [
                  Expanded(
                    child: Text(
                      teamA.teamName,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                      textAlign: TextAlign.right,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1B2838) : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        scoreDisplay,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      teamB.teamName,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                      textAlign: TextAlign.left,
                    ),
                  ),
                ],
              ),
              // Set details
              if (setDetails.isNotEmpty) ...[
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    setDetails,
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Round-robin/cycle system for specified places (attr_id=12).
  Widget _buildCyclePlacesView(List<String> groupNames) {
    final teams = _getTeamsAtPlaces(groupNames, _cyclePlaces);
    final carryOver = _buildCarryOverGames(teams);

    if (teams.isEmpty) {
      return const Center(child: Text('Немає команд для колової системи'));
    }

    return _buildSimpleCrossTable(
      teams,
      carryOverGames: carryOver,
      readOnlyCarryOver: true,
    );
  }

  /// Total standings — combines results from all phases into one ranked table.
  Widget _buildTotalStandingsView(List<String> groupNames) {
    final numGroups = groupNames.length;
    final rankedTeams = <({int teamId, String teamName, int overallPlace, String phase})>[];
    final assignedTeamIds = <int>{};
    int nextPlace = 1;

    // 1. Finals teams
    if (_finalsPlaces.isNotEmpty) {
      final finalists = _getTeamsAtPlaces(groupNames, _finalsPlaces);
      final standings = _calculateStandings(finalists);
      for (final s in standings) {
        rankedTeams.add((
          teamId: s.teamId,
          teamName: s.teamName,
          overallPlace: nextPlace++,
          phase: 'Фінал',
        ));
        assignedTeamIds.add(s.teamId);
      }
    }

    // 2. Direct match (стикові) teams — per place
    for (int i = 0; i < _crossGroupMatchPlaces.length; i++) {
      final place = _crossGroupMatchPlaces[i];
      final teamsAtPlace = _getTeamsAtSinglePlace(groupNames, place);
      if (teamsAtPlace.length >= 2) {
        final standings = _calculateStandings(teamsAtPlace);
        for (final s in standings) {
          if (assignedTeamIds.contains(s.teamId)) continue;
          rankedTeams.add((
            teamId: s.teamId,
            teamName: s.teamName,
            overallPlace: nextPlace++,
            phase: 'Стикові',
          ));
          assignedTeamIds.add(s.teamId);
        }
      } else {
        // Not enough results yet — assign by group place
        for (final t in teamsAtPlace) {
          if (assignedTeamIds.contains(t.teamId)) continue;
          rankedTeams.add((
            teamId: t.teamId,
            teamName: t.teamName,
            overallPlace: nextPlace++,
            phase: 'Стикові',
          ));
          assignedTeamIds.add(t.teamId);
        }
      }
    }

    // 3. Cycle (колові) teams
    if (_cyclePlaces.isNotEmpty) {
      final cycleTeams = _getTeamsAtPlaces(groupNames, _cyclePlaces);
      final standings = _calculateStandings(cycleTeams);
      for (final s in standings) {
        if (assignedTeamIds.contains(s.teamId)) continue;
        rankedTeams.add((
          teamId: s.teamId,
          teamName: s.teamName,
          overallPlace: nextPlace++,
          phase: 'Колові',
        ));
        assignedTeamIds.add(s.teamId);
      }
    }

    // 4. Remaining teams (not in any phase) — ranked by group standings
    for (final groupName in groupNames) {
      final groupTeams = _getGroupTeams(groupName);
      final standings = _calculateStandings(groupTeams);
      for (final s in standings) {
        if (assignedTeamIds.contains(s.teamId)) continue;
        rankedTeams.add((
          teamId: s.teamId,
          teamName: s.teamName,
          overallPlace: nextPlace++,
          phase: 'Група $groupName',
        ));
        assignedTeamIds.add(s.teamId);
      }
    }

    if (rankedTeams.isEmpty) {
      return const Center(child: Text('Немає даних для підсумку'));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerBg = isDark ? const Color(0xFF1B2838) : Colors.grey.shade100;
    final borderColor = isDark ? const Color(0xFF2A3A4E) : Colors.grey.shade300;
    final headerStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.bold,
      color: isDark ? Colors.grey.shade300 : Colors.black87,
    );
    final cellStyle = TextStyle(
      fontSize: 13,
      color: isDark ? Colors.grey.shade300 : Colors.black87,
    );

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: borderColor, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Загальний підсумок',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '${rankedTeams.length} команд',
              style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: Table(
                  defaultColumnWidth: const IntrinsicColumnWidth(),
                  border: TableBorder.all(color: borderColor, width: 0.5),
                  children: [
                    // Header
                    TableRow(
                      decoration: BoxDecoration(color: headerBg),
                      children: [
                        _standingsHeaderCell('Місце', headerStyle),
                        _standingsHeaderCell('Команда', headerStyle, minWidth: 200),
                        _standingsHeaderCell('Етап', headerStyle, minWidth: 80),
                      ],
                    ),
                    // Data rows
                    for (int i = 0; i < rankedTeams.length; i++)
                      TableRow(
                        decoration: i.isEven
                            ? null
                            : BoxDecoration(color: isDark ? const Color(0xFF152238) : Colors.grey.shade50),
                        children: [
                          _standingsDataCell('${rankedTeams[i].overallPlace}', cellStyle, bold: true),
                          _standingsDataCell(rankedTeams[i].teamName, cellStyle, leftAlign: true),
                          _standingsDataCell(rankedTeams[i].phase, cellStyle),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _standingsHeaderCell(String text, TextStyle style, {double minWidth = 48}) {
    return Container(
      constraints: BoxConstraints(minWidth: minWidth, minHeight: 36),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Text(text, style: style, textAlign: TextAlign.center),
    );
  }

  Widget _standingsDataCell(String text, TextStyle style, {bool bold = false, bool leftAlign = false}) {
    return Container(
      constraints: const BoxConstraints(minWidth: 48, minHeight: 36),
      alignment: leftAlign ? Alignment.centerLeft : Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Text(
        text,
        style: bold ? style.copyWith(fontWeight: FontWeight.bold) : style,
      ),
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
