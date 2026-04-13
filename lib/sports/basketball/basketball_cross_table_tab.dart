import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../viewmodels/team_viewmodel.dart';
import '../../viewmodels/tournament_viewmodel.dart';
import 'basketball_providers.dart';
import 'basketball_scoring.dart' as scoring;

/// Basketball team-vs-team cross-table tab.
///
/// Mode A (< 9 teams): single round-robin table.
/// Mode B (>= 9 teams): group/stage view with finals, cross-group matches,
/// and cycle places.
class BasketballCrossTableTab extends ConsumerStatefulWidget {
  final int tId;
  final String tournamentName;

  const BasketballCrossTableTab({
    super.key,
    required this.tId,
    required this.tournamentName,
  });

  @override
  ConsumerState<BasketballCrossTableTab> createState() =>
      _BasketballCrossTableTabState();
}

class _BasketballCrossTableTabState
    extends ConsumerState<BasketballCrossTableTab> {
  bool _loading = true;
  List<({int teamId, String teamName, int? teamNumber, int? entityId})> _teams =
      [];
  Map<(int, int), _GameData> _games = {};
  Map<int, String> _groupAssignments = {};
  Set<int> _removedTeamIds = {};
  Set<(int, int)> _noShowGamePairs = {};

  /// Places from each group that advance to finals (attr_id=12).
  List<int> _finalsPlaces = [1, 2];

  /// Places for cross-group direct matches (attr_id=13).
  List<int> _crossGroupMatchPlaces = [3, 4];

  /// Places for round-robin/cycle system (attr_id=14).
  List<int> _cyclePlaces = [5, 6];

  int _selectedSegment = 0; // 0 groups, 1 finals, 2 cross-group, 3 cycle, 4 total

  int? _hoveredRow;
  int? _hoveredCol;

  final ScrollController _vCtrl = ScrollController();
  final ScrollController _hCtrl = ScrollController();

  final Map<String, ScrollController> _groupVCtrls = {};
  final Map<String, ScrollController> _groupHCtrls = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _vCtrl.dispose();
    _hCtrl.dispose();
    for (final c in _groupVCtrls.values) {
      c.dispose();
    }
    for (final c in _groupHCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  ScrollController _groupVCtrl(String group) {
    return _groupVCtrls.putIfAbsent(group, ScrollController.new);
  }

  ScrollController _groupHCtrl(String group) {
    return _groupHCtrls.putIfAbsent(group, ScrollController.new);
  }

  Future<void> _loadData() async {
    final teamSvc = ref.read(teamServiceProvider);
    final svc = ref.read(basketballServiceProvider);
    final tSvc = ref.read(tournamentServiceProvider);

    final teamList = await teamSvc.getTeamListForTournament(widget.tId);
    final games = await svc.getTeamGamesForTournament(widget.tId);
    final groups = await svc.getGroupAssignments(widget.tId);
    final removed = await svc.getRemovedTeamIds(widget.tId);

    final finalsPlacesStr = await tSvc.getAttrValue(widget.tId, 12);
    final crossGroupStr = await tSvc.getAttrValue(widget.tId, 13);
    final cycleStr = await tSvc.getAttrValue(widget.tId, 14);

    final allTeams = await teamSvc.getAllTeams();
    final teams =
        <({int teamId, String teamName, int? teamNumber, int? entityId})>[];
    for (final t in teamList) {
      final team = allTeams.where((at) => at.team_id == t.teamId).firstOrNull;
      var entityId = team?.entity_id;
      if (entityId == null) {
        entityId = await svc.ensureTeamEntity(t.teamId);
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
        eventResult: g.eventResult != null ? _mirror(g.eventResult!) : null,
        esId: g.esId,
      );
      if (g.esId == 4) noShowPairs.add((g.teamAEntityId, g.teamBEntityId));
    }

    final groupMode = teams.length >= 9;

    setState(() {
      _teams = teams;
      _games = gamesMap;
      _groupAssignments = groups;
      _removedTeamIds = removed;
      _noShowGamePairs = noShowPairs;
      _finalsPlaces = _parsePlaces(
        finalsPlacesStr,
        defaultPlaces: groupMode ? [1, 2] : const [],
      );
      _crossGroupMatchPlaces = _parsePlaces(
        crossGroupStr,
        defaultPlaces: groupMode ? [3, 4] : const [],
      );
      _cyclePlaces = _parsePlaces(
        cycleStr,
        defaultPlaces: groupMode ? [5, 6] : const [],
      );
      _loading = false;
    });
  }

  String _mirror(String r) {
    final p = r.split(':');
    return p.length == 2 ? '${p[1]}:${p[0]}' : r;
  }

  List<int> _parsePlaces(String? value, {List<int> defaultPlaces = const []}) {
    if (value == null || value.trim().isEmpty) return defaultPlaces;
    return value
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toList();
  }

  List<({int teamId, String teamName, int? teamNumber, int? entityId})>
      _getGroupTeams(String groupName) {
    return _teams.where((t) => _groupAssignments[t.teamId] == groupName).toList();
  }

  List<({int teamId, String teamName, int? teamNumber, int? entityId})>
      _getTeamsAtSinglePlace(List<String> groupNames, int place) {
    final result =
        <({int teamId, String teamName, int? teamNumber, int? entityId})>[];
    for (final groupName in groupNames) {
      final groupTeams = _getGroupTeams(groupName);
      if (groupTeams.isEmpty) continue;
      final standings = _calcStandings(groupTeams);
      final idx = place - 1;
      if (idx >= 0 && idx < standings.length) {
        final s = standings[idx];
        final team = groupTeams.where((t) => t.teamId == s.teamId).firstOrNull;
        if (team != null) result.add(team);
      }
    }
    return result;
  }

  List<({int teamId, String teamName, int? teamNumber, int? entityId})>
      _getTeamsAtPlaces(List<String> groupNames, List<int> places) {
    final result =
        <({int teamId, String teamName, int? teamNumber, int? entityId})>[];
    for (final place in places) {
      result.addAll(_getTeamsAtSinglePlace(groupNames, place));
    }
    return result;
  }

  Map<(int, int), _GameData> _buildCarryOverGames(
    List<({int teamId, String teamName, int? teamNumber, int? entityId})> teams,
  ) {
    final carryOver = <(int, int), _GameData>{};
    for (int i = 0; i < teams.length; i++) {
      for (int j = i + 1; j < teams.length; j++) {
        final a = teams[i];
        final b = teams[j];
        if (a.entityId == null || b.entityId == null) continue;
        final ga = _groupAssignments[a.teamId];
        final gb = _groupAssignments[b.teamId];
        if (ga == gb && ga != null) {
          final game = _games[(a.entityId!, b.entityId!)];
          if (game != null) carryOver[(a.entityId!, b.entityId!)] = game;
        }
      }
    }
    return carryOver;
  }

  List<scoring.BasketballStanding> _calcStandings(
    List<({int teamId, String teamName, int? teamNumber, int? entityId})> teams,
  ) {
    final eIds = teams.map((t) => t.entityId).whereType<int>().toSet();
    final fg = <(int, int), String>{};
    final seen = <(int, int)>{};

    for (final e in _games.entries) {
      final (a, b) = e.key;
      if (!eIds.contains(a) || !eIds.contains(b)) continue;
      if (seen.contains((b, a))) continue;
      seen.add((a, b));
      if (e.value.eventResult != null) {
        fg[(a, b)] = e.value.eventResult!;
      }
    }

    return scoring.calculateStandings(
      teams: teams
          .map((t) => (
                teamId: t.teamId,
                teamName: t.teamName,
                entityId: t.entityId,
              ))
          .toList(),
      games: fg,
      removedTeamIds: _removedTeamIds,
      noShowGamePairs: _noShowGamePairs,
    );
  }

  bool get _useGroupMode => _teams.length >= 9;

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_teams.isEmpty) {
      return const Center(child: Text('Додайте команди для відображення таблиці'));
    }

    if (_useGroupMode) {
      return _buildGroupModeView();
    }

    return _buildSimpleCrossTable(_teams);
  }

  Widget _buildGroupModeView() {
    final groupNames = _groupAssignments.values.toSet().toList()..sort();
    final totalTeamCount = _teams.length;
    final numGroups = groupNames.length;
    final finalsTeamCount = (_finalsPlaces.length * numGroups).clamp(0, totalTeamCount);
    final crossGroupTeamCount =
        (_crossGroupMatchPlaces.length * numGroups).clamp(0, totalTeamCount - finalsTeamCount);

    final segments = <ButtonSegment<int>>[
      const ButtonSegment(value: 0, label: Text('Групи')),
    ];

    if (_finalsPlaces.isNotEmpty) {
      final endPlace = finalsTeamCount.clamp(1, totalTeamCount);
      final range = endPlace == 1 ? '1' : '1–$endPlace';
      segments.add(ButtonSegment(value: 1, label: Text('Фінал ($range)')));
    }

    if (_crossGroupMatchPlaces.isNotEmpty) {
      final start = finalsTeamCount + 1;
      final end = (finalsTeamCount + crossGroupTeamCount).clamp(start, totalTeamCount);
      final range = start == end ? '$start' : '$start–$end';
      segments.add(ButtonSegment(value: 2, label: Text('Стикові ($range)')));
    }

    if (_cyclePlaces.isNotEmpty) {
      final cycleTeamCount = (_cyclePlaces.length * numGroups)
          .clamp(0, totalTeamCount - finalsTeamCount - crossGroupTeamCount);
      final start = finalsTeamCount + crossGroupTeamCount + 1;
      final end =
          (finalsTeamCount + crossGroupTeamCount + cycleTeamCount).clamp(start, totalTeamCount);
      final range = start == end ? '$start' : '$start–$end';
      segments.add(ButtonSegment(value: 3, label: Text('Колова ($range)')));
    }

    segments.add(const ButtonSegment(value: 4, label: Text('Підсумок')));

    final validValues = segments.map((s) => s.value).toSet();
    if (!validValues.contains(_selectedSegment)) {
      _selectedSegment = 0;
    }

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
              'Призначте команди до груп у вкладці "Групи", щоб відкрити '
              'фінальні, стикові та колові етапи.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

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
              verticalController: _groupVCtrl(groupName),
              horizontalController: _groupHCtrl(groupName),
              showSystemBanner: false,
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
              verticalController: _groupVCtrl(groupName),
              horizontalController: _groupHCtrl(groupName),
              showSystemBanner: false,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFinalsView(List<String> groupNames) {
    final finalists = _getTeamsAtPlaces(groupNames, _finalsPlaces);
    if (finalists.isEmpty) {
      return const Center(child: Text('Спочатку проведіть груповий етап'));
    }
    return _buildSimpleCrossTable(
      finalists,
      showSystemBanner: false,
      carryOverGames: _buildCarryOverGames(finalists),
      readOnlyCarryOver: true,
    );
  }

  Widget _buildCrossGroupMatchView(List<String> groupNames) {
    if (groupNames.isEmpty || _crossGroupMatchPlaces.isEmpty) {
      return const Center(child: Text('Налаштуйте групи та місця для стикових матчів'));
    }

    final numGroups = groupNames.length;
    final finalsTeamCount = _finalsPlaces.length * numGroups;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? const Color(0xFF2A3A4E) : Colors.grey.shade300;
    final cellStyle = TextStyle(
      fontSize: 13,
      color: isDark ? Colors.grey.shade300 : Colors.black87,
    );

    // Collect 2-team direct match rows and 3+ team round-robin groups
    final matchRows = <({
      String placeLabel, String subtitle,
      ({int teamId, String teamName, int? teamNumber, int? entityId}) teamA,
      ({int teamId, String teamName, int? teamNumber, int? entityId}) teamB,
      _GameData? gameData,
    })>[];
    final roundRobinWidgets = <Widget>[];

    for (int i = 0; i < _crossGroupMatchPlaces.length; i++) {
      final place = _crossGroupMatchPlaces[i];
      final teamsAtPlace = _getTeamsAtSinglePlace(groupNames, place);
      if (teamsAtPlace.length < 2) continue;

      final overallStart = finalsTeamCount + 1 + i * numGroups;
      final overallEnd = overallStart + numGroups - 1;
      final placeLabel = overallStart == overallEnd
          ? 'За $overallStart місце'
          : 'За $overallStart–$overallEnd місце';

      if (teamsAtPlace.length == 2) {
        _GameData? gameData;
        if (teamsAtPlace[0].entityId != null && teamsAtPlace[1].entityId != null) {
          gameData = _games[(teamsAtPlace[0].entityId!, teamsAtPlace[1].entityId!)];
        }
        matchRows.add((
          placeLabel: placeLabel,
          subtitle: '($place місце з груп)',
          teamA: teamsAtPlace[0],
          teamB: teamsAtPlace[1],
          gameData: gameData,
        ));
      } else {
        roundRobinWidgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 8),
          child: Text(
            '$placeLabel ($place місце з груп)',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ));
        final carryOver = _buildCarryOverGames(teamsAtPlace);
        roundRobinWidgets.add(SizedBox(
          height: teamsAtPlace.length * 40.0 + 120,
          child: _buildSimpleCrossTable(
            teamsAtPlace,
            showSystemBanner: false,
            carryOverGames: carryOver,
            readOnlyCarryOver: true,
          ),
        ));
      }
    }

    if (matchRows.isEmpty && roundRobinWidgets.isEmpty) {
      return const Center(child: Text('Немає команд для розіграшу'));
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        if (matchRows.isNotEmpty)
          Card(
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
                  const Text(
                    'Стикові матчі',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  for (int i = 0; i < matchRows.length; i++)
                    _buildDirectMatchRow(i, matchRows[i], cellStyle, borderColor, isDark),
                ],
              ),
            ),
          ),
        ...roundRobinWidgets,
      ],
    );
  }

  Widget _buildDirectMatchRow(
    int index,
    ({
      String placeLabel, String subtitle,
      ({int teamId, String teamName, int? teamNumber, int? entityId}) teamA,
      ({int teamId, String teamName, int? teamNumber, int? entityId}) teamB,
      _GameData? gameData,
    }) match,
    TextStyle cellStyle,
    Color borderColor,
    bool isDark,
  ) {
    final gameData = match.gameData;
    String scoreDisplay = '—';
    if (gameData?.eventResult != null && gameData!.eventResult!.isNotEmpty) {
      scoreDisplay = gameData.eventResult!;
    }

    final bgColor = index.isOdd
        ? (isDark ? const Color(0xFF152238) : Colors.grey.shade50)
        : null;

    return InkWell(
      onTap: () => _showDialog(match.teamA, match.teamB, gameData),
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          border: Border(bottom: BorderSide(color: borderColor, width: 0.5)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 130,
              child: Text(match.placeLabel, style: cellStyle.copyWith(fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: Text(match.teamA.teamName, style: cellStyle, textAlign: TextAlign.right),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(scoreDisplay, style: cellStyle.copyWith(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
            Expanded(
              child: Text(match.teamB.teamName, style: cellStyle),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCyclePlacesView(List<String> groupNames) {
    if (groupNames.isEmpty || _cyclePlaces.isEmpty) {
      return const Center(child: Text('Налаштуйте групи та місця для колової стадії'));
    }

    final teams = _getTeamsAtPlaces(groupNames, _cyclePlaces);
    if (teams.length < 2) {
      return const Center(child: Text('Недостатньо команд для колової стадії'));
    }

    return _buildSimpleCrossTable(
      teams,
      showSystemBanner: false,
      carryOverGames: _buildCarryOverGames(teams),
      readOnlyCarryOver: true,
    );
  }

  Widget _buildTotalStandingsView(List<String> groupNames) {
    if (groupNames.isEmpty) {
      return const Center(child: Text('Призначте команди до груп'));
    }

    // Compute cumulative stats across ALL tournament games for each team
    final allStandings = _calcStandings(_teams);
    final cumulativeByTeam = {for (final s in allStandings) s.teamId: s};

    final rankedTeams = <({
      int teamId, String teamName, int overallPlace, String phase,
      int matchPoints, int pointsScored, int pointsConceded,
    })>[];
    final assignedTeamIds = <int>{};
    int nextPlace = 1;

    void addFromStandings(List<scoring.BasketballStanding> standings, String phase) {
      for (final s in standings) {
        if (assignedTeamIds.contains(s.teamId)) continue;
        if (s.isRemoved) continue;
        final cumulative = cumulativeByTeam[s.teamId];
        rankedTeams.add((
          teamId: s.teamId,
          teamName: s.teamName,
          overallPlace: nextPlace++,
          phase: phase,
          matchPoints: cumulative?.matchPoints ?? s.matchPoints,
          pointsScored: cumulative?.pointsScored ?? s.pointsScored,
          pointsConceded: cumulative?.pointsConceded ?? s.pointsConceded,
        ));
        assignedTeamIds.add(s.teamId);
      }
    }

    // 1. Finals teams
    if (_finalsPlaces.isNotEmpty) {
      final finalists = _getTeamsAtPlaces(groupNames, _finalsPlaces);
      addFromStandings(_calcStandings(finalists), 'Фінал');
    }

    // 2. Direct match (стикові) teams — per place
    for (int i = 0; i < _crossGroupMatchPlaces.length; i++) {
      final place = _crossGroupMatchPlaces[i];
      final teamsAtPlace = _getTeamsAtSinglePlace(groupNames, place);
      addFromStandings(_calcStandings(teamsAtPlace), 'Стикові');
    }

    // 3. Cycle (колові) teams
    if (_cyclePlaces.isNotEmpty) {
      final cycleTeams = _getTeamsAtPlaces(groupNames, _cyclePlaces);
      addFromStandings(_calcStandings(cycleTeams), 'Колові');
    }

    // 4. Remaining teams (not in any phase) — ranked by group standings
    for (final groupName in groupNames) {
      final groupTeams = _getGroupTeams(groupName);
      addFromStandings(_calcStandings(groupTeams), 'Група $groupName');
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
            const Text(
              'Загальний підсумок',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '${rankedTeams.length} команд',
              style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: SizedBox(
                  width: double.infinity,
                  child: Table(
                    columnWidths: const {
                      0: FixedColumnWidth(60),
                      1: FlexColumnWidth(),
                      2: FixedColumnWidth(100),
                    },
                    border: TableBorder.all(color: borderColor, width: 0.5),
                    children: [
                      TableRow(
                        decoration: BoxDecoration(color: headerBg),
                        children: [
                          _standingsHeaderCell('Місце', headerStyle),
                          _standingsHeaderCell('Команда', headerStyle, minWidth: 200),
                          _standingsHeaderCell('Етап', headerStyle, minWidth: 80),
                        ],
                      ),
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

  Widget _buildSimpleCrossTable(
    List<({int teamId, String teamName, int? teamNumber, int? entityId})> teams, {
    ScrollController? verticalController,
    ScrollController? horizontalController,
    bool showSystemBanner = true,
    Map<(int, int), _GameData>? carryOverGames,
    bool readOnlyCarryOver = false,
  }) {
    final standings = _calcStandings(teams);
    final n = teams.length;
    final standingsByTeam = {for (final s in standings) s.teamId: s};
    final vCtrl = verticalController ?? _vCtrl;
    final hCtrl = horizontalController ?? _hCtrl;

    final conductionSystem = scoring.pickBasketballConductionSystem(_teams.length);
    final systemLabel =
        conductionSystem == scoring.BasketballConductionSystem.roundRobin
            ? 'Колова система (1 коло)'
            : 'Змішана система (групи + фінальні ігри)';
    final systemDescription =
        conductionSystem == scoring.BasketballConductionSystem.roundRobin
            ? 'Для 8 команд і менше: усі команди грають між собою в одне коло.'
            : 'Для 9+ команд: команди діляться на групи 3–5, по 2 кращі виходять у фінальний етап.';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade300, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Турнірна таблиця',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                    onPressed: _confirmClear,
                  ),
                const SizedBox(width: 8),
                Text(
                  '$n команд',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
            if (showSystemBanner) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  border: Border.all(color: Colors.indigo.shade100),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Система проведення: $systemLabel',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      systemDescription,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Нюанси стрітболу: матч до 10 хв або 21 очка; за нічиєї після 10 хв — додатковий період до 2 очок.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
            ],
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
                      child: Table(
                        defaultColumnWidth: const FixedColumnWidth(56),
                        columnWidths: {
                          0: const FixedColumnWidth(36),
                          1: const FixedColumnWidth(180),
                          n + 2: const FixedColumnWidth(56),
                          n + 3: const FixedColumnWidth(56),
                          n + 4: const FixedColumnWidth(56),
                          n + 5: const FixedColumnWidth(15),
                          n + 6: const FixedColumnWidth(180),
                          n + 7: const FixedColumnWidth(56),
                          n + 8: const FixedColumnWidth(48),
                        },
                        border: TableBorder.all(color: Colors.grey.shade300, width: 0.5),
                        children: [
                          TableRow(
                            decoration: BoxDecoration(color: Colors.grey.shade100),
                            children: [
                              _hc('#'),
                              _hc('Команда'),
                              for (int j = 0; j < n; j++)
                                _hc('${teams[j].teamNumber ?? j + 1}'),
                              _hc('О'),
                              _hc('М'),
                              _hc('Р'),
                              Container(
                                height: 36,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade400,
                                  border: Border.all(color: Colors.grey.shade400, width: 0.5),
                                ),
                              ),
                              _hc('Команда'),
                              _hc('Очки'),
                              _hc('Місце'),
                            ],
                          ),
                          for (int i = 0; i < n; i++)
                            TableRow(
                              decoration: BoxDecoration(
                                color: _hoveredRow == i ? Colors.indigo.shade50 : null,
                              ),
                              children: [
                                _dc('${teams[i].teamNumber ?? i + 1}', bold: true),
                                _removedTeamIds.contains(teams[i].teamId)
                                    ? GestureDetector(
                                        onTap: () => _confirmUndoRemoval(teams[i].teamId, teams[i].teamName),
                                        child: _nc(teams[i].teamName, isRemoved: true),
                                      )
                                    : _nc(teams[i].teamName),
                                for (int j = 0; j < n; j++)
                                  _gc(
                                    i,
                                    j,
                                    teams,
                                    carryOverGames: carryOverGames,
                                    readOnlyCarryOver: readOnlyCarryOver,
                                  ),
                                _dc(
                                  '${standingsByTeam[teams[i].teamId]?.matchPoints ?? 0}',
                                  bold: true,
                                ),
                                _dc(
                                  '${standingsByTeam[teams[i].teamId]?.pointsScored ?? 0}:${standingsByTeam[teams[i].teamId]?.pointsConceded ?? 0}',
                                ),
                                _dc(
                                  '${((standingsByTeam[teams[i].teamId]?.pointsScored ?? 0) - (standingsByTeam[teams[i].teamId]?.pointsConceded ?? 0)) >= 0 ? '+' : ''}${((standingsByTeam[teams[i].teamId]?.pointsScored ?? 0) - (standingsByTeam[teams[i].teamId]?.pointsConceded ?? 0))}',
                                ),
                                Container(
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade400,
                                    border: Border.all(color: Colors.grey.shade400, width: 0.5),
                                  ),
                                ),
                                _nc(
                                  i < standings.length ? standings[i].teamName : '',
                                  isRemoved: i < standings.length && _removedTeamIds.contains(standings[i].teamId),
                                ),
                                _dc(
                                  '${i < standings.length ? standings[i].matchPoints : 0}',
                                  bold: true,
                                ),
                                _dc(
                                  '${i < standings.length ? standings[i].rank : i + 1}',
                                  bold: true,
                                ),
                              ],
                            ),
                        ],
                      ),
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

  Widget _gc(
    int i,
    int j,
    List<({int teamId, String teamName, int? teamNumber, int? entityId})> teams,
    {Map<(int, int), _GameData>? carryOverGames, bool readOnlyCarryOver = false,}
  ) {
    if (i == j) return Container(height: 36, color: Colors.grey.shade300);
    final tA = teams[i];
    final tB = teams[j];
    if (tA.entityId == null || tB.entityId == null) return const SizedBox(height: 36);

    final game = _games[(tA.entityId!, tB.entityId!)];
    final isCarryOver = carryOverGames != null && carryOverGames.containsKey((tA.entityId!, tB.entityId!));
    final isRemoved = _removedTeamIds.contains(tA.teamId) || _removedTeamIds.contains(tB.teamId);
    String cellText = '';
    Color? bg;

    if (game?.esId == 4) {
      cellText = '-';
      bg = Colors.orange.shade100;
    } else if (game?.eventResult != null) {
      cellText = game!.eventResult!;
      final p = cellText.split(':');
      if (p.length == 2) {
        final a = int.tryParse(p[0]) ?? 0;
        final b = int.tryParse(p[1]) ?? 0;
        bg = a > b
            ? Colors.green.shade50
            : a < b
                ? Colors.red.shade50
                : Colors.amber.shade50;
      }
    }
    if (isCarryOver && game == null) bg = Colors.amber.shade50;
    if (isRemoved) bg = Colors.grey.shade200;
    final readOnly = isRemoved || (isCarryOver && readOnlyCarryOver);

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
        onTap: readOnly ? null : () => _showDialog(tA, tB, game),
        child: Container(
          height: 36,
          alignment: Alignment.center,
          color: bg ?? (_hoveredCol == j && _hoveredRow == i ? Colors.indigo.shade50 : null),
          child: Text(
            cellText,
            style: TextStyle(
              fontSize: 12,
              fontWeight: cellText.isNotEmpty ? FontWeight.w500 : null,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showDialog(dynamic tA, dynamic tB, _GameData? existing) async {
    int eA = 0;
    int eB = 0;
    if (existing?.eventResult != null && existing!.esId != 4) {
      final p = existing.eventResult!.split(':');
      if (p.length == 2) {
        eA = int.tryParse(p[0]) ?? 0;
        eB = int.tryParse(p[1]) ?? 0;
      }
    }

    final cA = TextEditingController(text: eA > 0 ? '$eA' : '');
    final cB = TextEditingController(text: eB > 0 ? '$eB' : '');

    final result = await showDialog<_ScoreDialogResult?>(
      context: context,
      builder: (ctx) => _BasketballScoreDialog(
        teamAName: tA.teamName as String,
        teamBName: tB.teamName as String,
        controllerA: cA,
        controllerB: cB,
        hasExisting: existing != null,
        onDelete: existing != null ? () {
          Navigator.pop(ctx);
          _del(existing.eventId);
        } : null,
      ),
    );

    cA.dispose();
    cB.dispose();

    if (result == null) return;

    final svc = ref.read(basketballServiceProvider);

    // Handle no-show
    if (result.noShowTeam != null) {
      final eventId = existing?.eventId ??
          await svc.findOrCreateTeamGame(
            tId: widget.tId,
            teamAId: tA.teamId,
            teamBId: tB.teamId,
          );

      final noShowIsA = result.noShowTeam == 'A';
      await svc.saveGoalResult(
        eventId: eventId,
        teamAEntityId: tA.entityId!,
        teamBEntityId: tB.entityId!,
        goalsA: noShowIsA ? 0 : 21,
        goalsB: noShowIsA ? 21 : 0,
        esId: 4,
      );

      await _checkNoShows(tA.teamId);
      await _checkNoShows(tB.teamId);
      await _loadData();
      return;
    }

    // Normal score
    final goalsA = result.goalsA!;
    final goalsB = result.goalsB!;

    if (goalsA == 0 && goalsB == 0) {
      // Delete existing game if both scores are 0
      if (existing != null) {
        await svc.deleteTeamGame(existing.eventId);
      }
      await _loadData();
      return;
    }

    final eventId = existing?.eventId ??
        await svc.findOrCreateTeamGame(
          tId: widget.tId,
          teamAId: tA.teamId,
          teamBId: tB.teamId,
        );

    await svc.saveGoalResult(
      eventId: eventId,
      teamAEntityId: tA.entityId!,
      teamBEntityId: tB.entityId!,
      goalsA: goalsA,
      goalsB: goalsB,
    );

    await _checkNoShows(tA.teamId);
    await _checkNoShows(tB.teamId);
    await _loadData();
  }

  Future<void> _del(int id) async {
    await ref.read(basketballServiceProvider).deleteTeamGame(id);
    await _loadData();
  }

  void _confirmClear() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Очистити результати?'),
        content: const Text('Видалити всі результати ігор?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Скасувати'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              _clearAll();
            },
            child: const Text('Очистити', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _clearAll() async {
    final svc = ref.read(basketballServiceProvider);
    for (final id in _games.values.map((g) => g.eventId).toSet()) {
      await svc.deleteTeamGame(id);
    }
    await svc.clearAllRemovedState(widget.tId);
    await _loadData();
  }

  Future<void> _confirmUndoRemoval(int teamId, String teamName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Повернути команду?'),
        content: Text('Зняти статус неявки для "$teamName"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Скасувати')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Повернути')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(basketballServiceProvider).unmarkTeamRemoved(widget.tId, teamId);
    await _loadData();
  }

  Future<void> _checkNoShows(int teamId) async {
    final svc = ref.read(basketballServiceProvider);
    final count = await svc.countNoShows(widget.tId, teamId);
    if (count >= 2) {
      await svc.deleteAllTeamGames(widget.tId, teamId);
      await svc.markTeamRemoved(widget.tId, teamId);
    } else {
      await svc.unmarkTeamRemoved(widget.tId, teamId);
    }
  }

  Widget _hc(String t) => Container(
        height: 36,
        alignment: Alignment.center,
        color: Colors.grey.shade100,
        child: Text(
          t,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      );

  Widget _dc(String t, {bool bold = false}) => Container(
        height: 36,
        alignment: Alignment.center,
        child: Text(
          t,
          style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.bold : null),
        ),
      );

  Widget _nc(String n, {bool isRemoved = false}) => Container(
        height: 36,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          n,
          style: TextStyle(
            fontSize: 12,
            color: isRemoved ? Colors.grey : null,
            decoration: isRemoved ? TextDecoration.lineThrough : null,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      );
}

class _GameData {
  final int eventId;
  final String? eventResult;
  final int? esId;

  const _GameData({required this.eventId, this.eventResult, this.esId});
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

class _BasketballScoreDialog extends StatelessWidget {
  final String teamAName;
  final String teamBName;
  final TextEditingController controllerA;
  final TextEditingController controllerB;
  final bool hasExisting;
  final VoidCallback? onDelete;

  const _BasketballScoreDialog({
    required this.teamAName,
    required this.teamBName,
    required this.controllerA,
    required this.controllerB,
    required this.hasExisting,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        '$teamAName — $teamBName',
        style: const TextStyle(fontSize: 16),
      ),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with team names
            Row(
              children: [
                const SizedBox(width: 60),
                Expanded(
                  child: Text(
                    teamAName,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    teamBName,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Score input row
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
                      controller: controllerA,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textAlign: TextAlign.center,
                      autofocus: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        isDense: true,
                      ),
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
                      controller: controllerB,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
        // No-show button with dropdown (left side)
        PopupMenuButton<String>(
          tooltip: 'Неявка команди',
          offset: const Offset(0, -100),
          onSelected: (team) {
            Navigator.pop(context, _ScoreDialogResult.noShow(team));
          },
          itemBuilder: (ctx) => [
            PopupMenuItem(
              value: 'A',
              child: Text('Неявка: $teamAName'),
            ),
            PopupMenuItem(
              value: 'B',
              child: Text('Неявка: $teamBName'),
            ),
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
        // Right side: delete + cancel + save
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasExisting && onDelete != null)
              TextButton(
                onPressed: onDelete,
                child: const Text('Видалити', style: TextStyle(color: Colors.red)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Скасувати'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () {
                final a = int.tryParse(controllerA.text) ?? 0;
                final b = int.tryParse(controllerB.text) ?? 0;
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
