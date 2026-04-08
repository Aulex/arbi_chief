import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../viewmodels/team_viewmodel.dart';
import '../../viewmodels/tournament_viewmodel.dart';
import 'streetball_providers.dart';
import 'streetball_scoring.dart' as scoring;

/// Streetball team-vs-team cross-table tab.
///
/// Mode A (< 9 teams): single round-robin table.
/// Mode B (>= 9 teams): group/stage view with finals, cross-group matches,
/// and cycle places.
class StreetballCrossTableTab extends ConsumerStatefulWidget {
  final int tId;
  final String tournamentName;

  const StreetballCrossTableTab({
    super.key,
    required this.tId,
    required this.tournamentName,
  });

  @override
  ConsumerState<StreetballCrossTableTab> createState() =>
      _StreetballCrossTableTabState();
}

class _StreetballCrossTableTabState
    extends ConsumerState<StreetballCrossTableTab> {
  bool _loading = true;
  List<({int teamId, String teamName, int? teamNumber, int? entityId})> _teams =
      [];
  Map<(int, int), _GameData> _games = {};
  Map<int, String> _groupAssignments = {};

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
    final svc = ref.read(streetballServiceProvider);
    final tSvc = ref.read(tournamentServiceProvider);

    final teamList = await teamSvc.getTeamListForTournament(widget.tId);
    final games = await svc.getTeamGamesForTournament(widget.tId);
    final groups = await svc.getGroupAssignments(widget.tId);

    final finalsPlacesStr = await tSvc.getAttrValue(widget.tId, 12);
    final crossGroupStr = await tSvc.getAttrValue(widget.tId, 13);
    final cycleStr = await tSvc.getAttrValue(widget.tId, 14);

    final allTeams = await teamSvc.getAllTeams();
    final teams =
        <({int teamId, String teamName, int? teamNumber, int? entityId})>[];
    for (final t in teamList) {
      final team = allTeams.where((at) => at.team_id == t.teamId).firstOrNull;
      teams.add((
        teamId: t.teamId,
        teamName: t.teamName,
        teamNumber: t.teamNumber,
        entityId: team?.entity_id,
      ));
    }

    final gamesMap = <(int, int), _GameData>{};
    for (final g in games) {
      gamesMap[(g.teamAEntityId, g.teamBEntityId)] = _GameData(
        eventId: g.eventId,
        eventResult: g.eventResult,
      );
      gamesMap[(g.teamBEntityId, g.teamAEntityId)] = _GameData(
        eventId: g.eventId,
        eventResult: g.eventResult != null ? _mirror(g.eventResult!) : null,
      );
    }

    final groupMode = teams.length >= 9;

    setState(() {
      _teams = teams;
      _games = gamesMap;
      _groupAssignments = groups;
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

  List<scoring.StreetballStanding> _calcStandings(
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
    return _buildSimpleCrossTable(finalists, showSystemBanner: false);
  }

  Widget _buildCrossGroupMatchView(List<String> groupNames) {
    if (groupNames.isEmpty || _crossGroupMatchPlaces.isEmpty) {
      return const Center(child: Text('Налаштуйте групи та місця для стикових матчів'));
    }

    return ListView(
      children: [
        for (final place in _crossGroupMatchPlaces) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 8),
            child: Text(
              '$place місце з груп',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          Builder(
            builder: (context) {
              final teams = _getTeamsAtSinglePlace(groupNames, place);
              if (teams.length < 2) {
                return const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('Недостатньо команд для цієї стадії'),
                );
              }
              return SizedBox(
                height: teams.length * 40.0 + 120,
                child: _buildSimpleCrossTable(teams, showSystemBanner: false),
              );
            },
          ),
        ],
      ],
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

    return _buildSimpleCrossTable(teams, showSystemBanner: false);
  }

  Widget _buildTotalStandingsView(List<String> groupNames) {
    if (groupNames.isEmpty) {
      return const Center(child: Text('Призначте команди до груп'));
    }

    final combined = <({int teamId, String teamName, int? teamNumber, int? entityId})>[];
    combined.addAll(_getTeamsAtPlaces(groupNames, _finalsPlaces));
    combined.addAll(_getTeamsAtPlaces(groupNames, _crossGroupMatchPlaces));
    combined.addAll(_getTeamsAtPlaces(groupNames, _cyclePlaces));

    final seen = <int>{};
    final unique = combined.where((t) => seen.add(t.teamId)).toList();
    if (unique.isEmpty) {
      return const Center(child: Text('Немає даних для підсумкової таблиці'));
    }

    return _buildSimpleCrossTable(unique, showSystemBanner: false);
  }

  Widget _buildSimpleCrossTable(
    List<({int teamId, String teamName, int? teamNumber, int? entityId})> teams, {
    ScrollController? verticalController,
    ScrollController? horizontalController,
    bool showSystemBanner = true,
  }) {
    final standings = _calcStandings(teams);
    final n = teams.length;
    final standingsByTeam = {for (final s in standings) s.teamId: s};
    final vCtrl = verticalController ?? _vCtrl;
    final hCtrl = horizontalController ?? _hCtrl;

    final conductionSystem = scoring.pickStreetballConductionSystem(_teams.length);
    final systemLabel =
        conductionSystem == scoring.StreetballConductionSystem.roundRobin
            ? 'Колова система (1 коло)'
            : 'Змішана система (групи + фінальні ігри)';
    final systemDescription =
        conductionSystem == scoring.StreetballConductionSystem.roundRobin
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
                                  color: Colors.black,
                                  border: Border.all(color: Colors.black, width: 0.5),
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
                                _nc(teams[i].teamName),
                                for (int j = 0; j < n; j++) _gc(i, j, teams),
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
                                    color: Colors.black,
                                    border: Border.all(color: Colors.black, width: 0.5),
                                  ),
                                ),
                                _nc(i < standings.length ? standings[i].teamName : ''),
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
  ) {
    if (i == j) return Container(height: 36, color: Colors.grey.shade300);
    final tA = teams[i];
    final tB = teams[j];
    if (tA.entityId == null || tB.entityId == null) return const SizedBox(height: 36);

    final game = _games[(tA.entityId!, tB.entityId!)];
    String cellText = '';
    Color? bg;

    if (game?.eventResult != null) {
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
        onTap: () => _showDialog(tA, tB, game),
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
    if (existing?.eventResult != null) {
      final p = existing!.eventResult!.split(':');
      if (p.length == 2) {
        eA = int.tryParse(p[0]) ?? 0;
        eB = int.tryParse(p[1]) ?? 0;
      }
    }

    final cA = TextEditingController(text: eA > 0 ? '$eA' : '');
    final cB = TextEditingController(text: eB > 0 ? '$eB' : '');

    final result = await showDialog<({int goalsA, int goalsB})?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${tA.teamName}  vs  ${tB.teamName}', style: const TextStyle(fontSize: 16)),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 80,
              child: TextField(
                controller: cA,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  labelText: tA.teamName.length > 10 ? tA.teamName.substring(0, 10) : tA.teamName,
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
                controller: cB,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  labelText: tB.teamName.length > 10 ? tB.teamName.substring(0, 10) : tB.teamName,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (existing != null)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _del(existing.eventId);
              },
              child: const Text('Видалити', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Скасувати'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(
                ctx,
                (goalsA: int.tryParse(cA.text) ?? 0, goalsB: int.tryParse(cB.text) ?? 0),
              );
            },
            child: const Text('Зберегти'),
          ),
        ],
      ),
    );

    cA.dispose();
    cB.dispose();

    if (result == null) return;

    final svc = ref.read(streetballServiceProvider);
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
      goalsA: result.goalsA,
      goalsB: result.goalsB,
    );

    await _loadData();
  }

  Future<void> _del(int id) async {
    await ref.read(streetballServiceProvider).deleteTeamGame(id);
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
    final svc = ref.read(streetballServiceProvider);
    for (final id in _games.values.map((g) => g.eventId).toSet()) {
      await svc.deleteTeamGame(id);
    }
    await _loadData();
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

  Widget _nc(String n) => Container(
        height: 36,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          n,
          style: const TextStyle(fontSize: 12),
          overflow: TextOverflow.ellipsis,
        ),
      );
}

class _GameData {
  final int eventId;
  final String? eventResult;

  _GameData({required this.eventId, this.eventResult});
}
