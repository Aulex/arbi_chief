import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../viewmodels/team_viewmodel.dart';
import 'basketball_providers.dart';
import 'basketball_scoring.dart' as scoring;

/// Basketball team-vs-team cross-table tab.
class BasketballCrossTableTab extends ConsumerStatefulWidget {
  final int tId;
  final String tournamentName;
  const BasketballCrossTableTab({super.key, required this.tId, required this.tournamentName});

  @override
  ConsumerState<BasketballCrossTableTab> createState() => _BasketballCrossTableTabState();
}

class _BasketballCrossTableTabState extends ConsumerState<BasketballCrossTableTab> {
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
    final svc = ref.read(basketballServiceProvider);
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

  List<scoring.BasketballStanding> _calcStandings(List<({int teamId, String teamName, int? teamNumber, int? entityId})> teams) {
    final eIds = teams.map((t) => t.entityId).whereType<int>().toSet();
    final fg = <(int, int), String>{}; final seen = <(int, int)>{};
    for (final e in _games.entries) { final (a, b) = e.key; if (eIds.contains(a) && eIds.contains(b)) { if (seen.contains((b, a))) continue; seen.add((a, b)); if (e.value.eventResult != null) fg[(a, b)] = e.value.eventResult!; } }
    return scoring.calculateStandings(teams: teams.map((t) => (teamId: t.teamId, teamName: t.teamName, entityId: t.entityId)).toList(), games: fg);
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
            child: Table(defaultColumnWidth: const FixedColumnWidth(56), columnWidths: {0: const FixedColumnWidth(36), 1: const FixedColumnWidth(180), n + 2: const FixedColumnWidth(56), n + 3: const FixedColumnWidth(56), n + 4: const FixedColumnWidth(56), n + 5: const FixedColumnWidth(15), n + 6: const FixedColumnWidth(180), n + 7: const FixedColumnWidth(56), n + 8: const FixedColumnWidth(48)},
              border: TableBorder.all(color: Colors.grey.shade300, width: 0.5), children: [
                TableRow(decoration: BoxDecoration(color: Colors.grey.shade100), children: [_hc('#'), _hc('Команда'), for (int j = 0; j < n; j++) _hc('${_teams[j].teamNumber ?? j + 1}'), _hc('О'), _hc('М'), _hc('Р'), Container(height: 36, decoration: BoxDecoration(color: Colors.black, border: Border.all(color: Colors.black, width: 0.5))), _hc('Команда'), _hc('Очки'), _hc('Місце')]),
                for (int i = 0; i < n; i++) TableRow(decoration: BoxDecoration(color: _hoveredRow == i ? Colors.indigo.shade50 : null), children: [
                  _dc('${_teams[i].teamNumber ?? i + 1}', bold: true), _nc(_teams[i].teamName),
                  for (int j = 0; j < n; j++) _gc(i, j),
                  _dc('${standingsByTeam[_teams[i].teamId]?.matchPoints ?? 0}', bold: true),
                  _dc('${standingsByTeam[_teams[i].teamId]?.pointsScored ?? 0}:${standingsByTeam[_teams[i].teamId]?.pointsConceded ?? 0}'),
                  _dc('${((standingsByTeam[_teams[i].teamId]?.pointsScored ?? 0) - (standingsByTeam[_teams[i].teamId]?.pointsConceded ?? 0)) >= 0 ? '+' : ''}${((standingsByTeam[_teams[i].teamId]?.pointsScored ?? 0) - (standingsByTeam[_teams[i].teamId]?.pointsConceded ?? 0))}'),
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
    if (game?.eventResult != null) { cellText = game!.eventResult!; final p = cellText.split(':'); if (p.length == 2) { final a = int.tryParse(p[0]) ?? 0, b = int.tryParse(p[1]) ?? 0; bg = a > b ? Colors.green.shade50 : a < b ? Colors.red.shade50 : Colors.amber.shade50; } }
    return MouseRegion(onEnter: (_) => setState(() { _hoveredRow = i; _hoveredCol = j; }), onExit: (_) => setState(() { _hoveredRow = null; _hoveredCol = null; }),
      child: GestureDetector(onTap: () => _showDialog(tA, tB, game),
        child: Container(height: 36, alignment: Alignment.center, color: bg ?? (_hoveredCol == j && _hoveredRow == i ? Colors.indigo.shade50 : null),
          child: Text(cellText, style: TextStyle(fontSize: 12, fontWeight: cellText.isNotEmpty ? FontWeight.w500 : null)))));
  }

  Future<void> _showDialog(dynamic tA, dynamic tB, _GameData? existing) async {
    int eA = 0, eB = 0;
    if (existing?.eventResult != null) { final p = existing!.eventResult!.split(':'); if (p.length == 2) { eA = int.tryParse(p[0]) ?? 0; eB = int.tryParse(p[1]) ?? 0; } }
    final cA = TextEditingController(text: eA > 0 ? '$eA' : ''), cB = TextEditingController(text: eB > 0 ? '$eB' : '');
    final result = await showDialog<({int goalsA, int goalsB})?>(context: context, builder: (ctx) => AlertDialog(
      title: Text('${tA.teamName}  vs  ${tB.teamName}', style: const TextStyle(fontSize: 16)),
      content: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: 80, child: TextField(controller: cA, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], textAlign: TextAlign.center, decoration: InputDecoration(labelText: tA.teamName.length > 10 ? tA.teamName.substring(0, 10) : tA.teamName, border: const OutlineInputBorder()), autofocus: true)),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text(':', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
        SizedBox(width: 80, child: TextField(controller: cB, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], textAlign: TextAlign.center, decoration: InputDecoration(labelText: tB.teamName.length > 10 ? tB.teamName.substring(0, 10) : tB.teamName, border: const OutlineInputBorder())))]),
      actions: [
        if (existing != null) TextButton(onPressed: () { Navigator.pop(ctx); _del(existing.eventId); }, child: const Text('Видалити', style: TextStyle(color: Colors.red))),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Скасувати')),
        ElevatedButton(onPressed: () { Navigator.pop(ctx, (goalsA: int.tryParse(cA.text) ?? 0, goalsB: int.tryParse(cB.text) ?? 0)); }, child: const Text('Зберегти'))]));
    cA.dispose(); cB.dispose();
    if (result == null) return;
    final svc = ref.read(basketballServiceProvider);
    final eventId = existing?.eventId ?? await svc.findOrCreateTeamGame(tId: widget.tId, teamAId: tA.teamId, teamBId: tB.teamId);
    await svc.saveGoalResult(eventId: eventId, teamAEntityId: tA.entityId!, teamBEntityId: tB.entityId!, goalsA: result.goalsA, goalsB: result.goalsB);
    await _loadData();
  }

  Future<void> _del(int id) async { await ref.read(basketballServiceProvider).deleteTeamGame(id); await _loadData(); }
  void _confirmClear() { showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('Очистити результати?'), content: const Text('Видалити всі результати ігор?'), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Скасувати')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () { Navigator.pop(ctx); _clearAll(); }, child: const Text('Очистити', style: TextStyle(color: Colors.white)))])); }
  Future<void> _clearAll() async { final svc = ref.read(basketballServiceProvider); for (final id in _games.values.map((g) => g.eventId).toSet()) { await svc.deleteTeamGame(id); } await _loadData(); }

  Widget _hc(String t) => Container(height: 36, alignment: Alignment.center, color: Colors.grey.shade100, child: Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)));
  Widget _dc(String t, {bool bold = false}) => Container(height: 36, alignment: Alignment.center, child: Text(t, style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.bold : null)));
  Widget _nc(String n) => Container(height: 36, alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(n, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis));
}

class _GameData { final int eventId; final String? eventResult; _GameData({required this.eventId, this.eventResult}); }
