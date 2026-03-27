import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../viewmodels/team_viewmodel.dart';
import 'tug_of_war_providers.dart';
import 'tug_of_war_scoring.dart' as scoring;

/// Tug of War team-vs-team cross-table tab.
///
/// Win/loss only (no draws, no goals). 2pts for win, 0pts for loss.
class TugOfWarCrossTableTab extends ConsumerStatefulWidget {
  final int tId;
  final String tournamentName;
  const TugOfWarCrossTableTab({super.key, required this.tId, required this.tournamentName});

  @override
  ConsumerState<TugOfWarCrossTableTab> createState() => _TugOfWarCrossTableTabState();
}

class _TugOfWarCrossTableTabState extends ConsumerState<TugOfWarCrossTableTab> {
  bool _loading = true;
  List<({int teamId, String teamName, int? teamNumber, int? entityId})> _teams = [];
  Map<(int, int), _GameData> _games = {};
  int? _hoveredRow;
  int? _hoveredCol;
  final ScrollController _vCtrl = ScrollController();
  final ScrollController _hCtrl = ScrollController();

  @override
  void initState() { super.initState(); _loadData(); }

  @override
  void dispose() { _vCtrl.dispose(); _hCtrl.dispose(); super.dispose(); }

  Future<void> _loadData() async {
    final teamSvc = ref.read(teamServiceProvider);
    final svc = ref.read(tugOfWarServiceProvider);
    final teamList = await teamSvc.getTeamListForTournament(widget.tId);
    final games = await svc.getTeamGamesForTournament(widget.tId);
    final teams = <({int teamId, String teamName, int? teamNumber, int? entityId})>[];
    for (final t in teamList) {
      final allTeams = await teamSvc.getAllTeams();
      final team = allTeams.where((at) => at.team_id == t.teamId).firstOrNull;
      teams.add((teamId: t.teamId, teamName: t.teamName, teamNumber: t.teamNumber, entityId: team?.entity_id));
    }
    final gamesMap = <(int, int), _GameData>{};
    for (final g in games) {
      gamesMap[(g.teamAEntityId, g.teamBEntityId)] = _GameData(eventId: g.eventId, eventResult: g.eventResult);
      gamesMap[(g.teamBEntityId, g.teamAEntityId)] = _GameData(eventId: g.eventId, eventResult: g.eventResult != null ? _mirror(g.eventResult!) : null);
    }
    setState(() { _teams = teams; _games = gamesMap; _loading = false; });
  }

  String _mirror(String r) { final p = r.split(':'); return p.length == 2 ? '${p[1]}:${p[0]}' : r; }

  List<scoring.TugOfWarStanding> _calcStandings(List<({int teamId, String teamName, int? teamNumber, int? entityId})> teams) {
    final eIds = teams.map((t) => t.entityId).whereType<int>().toSet();
    final fg = <(int, int), String>{}; final seen = <(int, int)>{};
    for (final e in _games.entries) { final (a, b) = e.key; if (eIds.contains(a) && eIds.contains(b)) { if (seen.contains((b, a))) continue; seen.add((a, b)); if (e.value.eventResult != null) fg[(a, b)] = e.value.eventResult!; } }
    return scoring.calculateStandings(teams: teams.map((t) => (teamId: t.teamId, teamName: t.teamName, entityId: t.entityId, weight: null as double?)).toList(), games: fg);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_teams.isEmpty) return const Center(child: Text('Додайте команди для відображення таблиці'));
    final standings = _calcStandings(_teams);
    final n = _teams.length;
    final standingsByTeam = {for (final s in standings) s.teamId: s};
    return Card(elevation: 0, shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey.shade300, width: 1), borderRadius: BorderRadius.circular(8)),
      child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Text('Турнірна таблиця', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), const Spacer(),
          if (_games.isNotEmpty) TextButton.icon(icon: const Icon(Icons.delete_sweep_outlined, size: 14), label: const Text('Очистити', style: TextStyle(fontSize: 11)), style: TextButton.styleFrom(foregroundColor: Colors.red, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap), onPressed: _confirmClear),
          const SizedBox(width: 8), Text('$n команд', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))]),
        const SizedBox(height: 12),
        Expanded(child: Scrollbar(controller: _vCtrl, thumbVisibility: true, child: SingleChildScrollView(controller: _vCtrl,
          child: Scrollbar(controller: _hCtrl, thumbVisibility: true, notificationPredicate: (n) => n.depth == 1, child: SingleChildScrollView(controller: _hCtrl, scrollDirection: Axis.horizontal,
            child: Table(defaultColumnWidth: const FixedColumnWidth(56), columnWidths: {0: const FixedColumnWidth(36), 1: const FixedColumnWidth(180), n + 2: const FixedColumnWidth(56), n + 3: const FixedColumnWidth(56), n + 4: const FixedColumnWidth(15), n + 5: const FixedColumnWidth(180), n + 6: const FixedColumnWidth(56), n + 7: const FixedColumnWidth(48)},
              border: TableBorder.all(color: Colors.grey.shade300, width: 0.5), children: [
                TableRow(decoration: BoxDecoration(color: Colors.grey.shade100), children: [_hc('#'), _hc('Команда'), for (int j = 0; j < n; j++) _hc('${_teams[j].teamNumber ?? j + 1}'), _hc('О'), _hc('В'), Container(height: 36, decoration: BoxDecoration(color: Colors.black, border: Border.all(color: Colors.black, width: 0.5))), _hc('Команда'), _hc('Очки'), _hc('Місце')]),
                for (int i = 0; i < n; i++) TableRow(decoration: BoxDecoration(color: _hoveredRow == i ? Colors.indigo.shade50 : null), children: [
                  _dc('${_teams[i].teamNumber ?? i + 1}', bold: true), _nc(_teams[i].teamName),
                  for (int j = 0; j < n; j++) _gc(i, j),
                  _dc('${standingsByTeam[_teams[i].teamId]?.matchPoints ?? 0}', bold: true),
                  _dc('${standingsByTeam[_teams[i].teamId]?.wins ?? 0}'),
                  Container(height: 36, decoration: BoxDecoration(color: Colors.black, border: Border.all(color: Colors.black, width: 0.5))),
                  _nc(i < standings.length ? standings[i].teamName : ''),
                  _dc('${i < standings.length ? standings[i].matchPoints : 0}', bold: true),
                  _dc('${i < standings.length ? standings[i].rank : i + 1}', bold: true),
                ]),
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

  Widget _gc(int i, int j) {
    if (i == j) return Container(height: 36, color: Colors.grey.shade300);
    final tA = _teams[i], tB = _teams[j];
    if (tA.entityId == null || tB.entityId == null) return const SizedBox(height: 36);
    final game = _games[(tA.entityId!, tB.entityId!)];
    String cellText = ''; Color? bg;
    if (game?.eventResult != null) {
      final p = game!.eventResult!.split(':');
      if (p.length == 2) {
        final a = int.tryParse(p[0]) ?? 0, b = int.tryParse(p[1]) ?? 0;
        if (a > b) { cellText = '+'; bg = Colors.green.shade50; }
        else { cellText = '−'; bg = Colors.red.shade50; }
      }
    }
    return MouseRegion(onEnter: (_) => setState(() { _hoveredRow = i; _hoveredCol = j; }), onExit: (_) => setState(() { _hoveredRow = null; _hoveredCol = null; }),
      child: GestureDetector(onTap: () => _showWinnerDialog(tA, tB, game),
        child: Container(height: 36, alignment: Alignment.center, color: bg ?? (_hoveredCol == j && _hoveredRow == i ? Colors.indigo.shade50 : null),
          child: Text(cellText, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: bg == Colors.green.shade50 ? Colors.green.shade700 : bg == Colors.red.shade50 ? Colors.red.shade700 : null)))));
  }

  /// Tug of War only has win/loss — show a simple two-button dialog.
  Future<void> _showWinnerDialog(dynamic tA, dynamic tB, _GameData? existing) async {
    final result = await showDialog<int?>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Хто переміг?', style: TextStyle(fontSize: 16)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('${tA.teamName}  vs  ${tB.teamName}', style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          ElevatedButton.icon(
            icon: const Icon(Icons.emoji_events, color: Colors.amber),
            label: Text(tA.teamName.length > 15 ? '${tA.teamName.substring(0, 15)}…' : tA.teamName),
            onPressed: () => Navigator.pop(ctx, tA.entityId as int),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.emoji_events, color: Colors.amber),
            label: Text(tB.teamName.length > 15 ? '${tB.teamName.substring(0, 15)}…' : tB.teamName),
            onPressed: () => Navigator.pop(ctx, tB.entityId as int),
          ),
        ]),
      ]),
      actions: [
        if (existing != null) TextButton(onPressed: () { Navigator.pop(ctx); _del(existing.eventId); }, child: const Text('Видалити', style: TextStyle(color: Colors.red))),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Скасувати')),
      ],
    ));
    if (result == null) return;
    final svc = ref.read(tugOfWarServiceProvider);
    final eventId = existing?.eventId ?? await svc.findOrCreateTeamGame(tId: widget.tId, teamAId: tA.teamId, teamBId: tB.teamId);
    await svc.saveResult(eventId: eventId, teamAEntityId: tA.entityId!, teamBEntityId: tB.entityId!, winnerEntityId: result);
    await _loadData();
  }

  Future<void> _del(int id) async { await ref.read(tugOfWarServiceProvider).deleteTeamGame(id); await _loadData(); }
  void _confirmClear() { showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('Очистити результати?'), content: const Text('Видалити всі результати ігор?'), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Скасувати')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () { Navigator.pop(ctx); _clearAll(); }, child: const Text('Очистити', style: TextStyle(color: Colors.white)))])); }
  Future<void> _clearAll() async { final svc = ref.read(tugOfWarServiceProvider); for (final id in _games.values.map((g) => g.eventId).toSet()) { await svc.deleteTeamGame(id); } await _loadData(); }

  Widget _hc(String t) => Container(height: 36, alignment: Alignment.center, color: Colors.grey.shade100, child: Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)));
  Widget _dc(String t, {bool bold = false}) => Container(height: 36, alignment: Alignment.center, child: Text(t, style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.bold : null)));
  Widget _nc(String n) => Container(height: 36, alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(n, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis));
}

class _GameData { final int eventId; final String? eventResult; _GameData({required this.eventId, this.eventResult}); }
