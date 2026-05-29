import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../viewmodels/team_viewmodel.dart';
import 'tug_of_war_providers.dart';
import 'tug_of_war_scoring.dart' as scoring;

/// Tug of War team-vs-team cross-table tab.
///
/// Win/loss only (no draws). 2 pts win, 1 pt loss, 0 pts no-show.
/// Supports marking a team as removed (e.g. 2nd no-show, unsporting conduct):
/// removed teams' results are annulled and they get no place.
class TugOfWarCrossTableTab extends ConsumerStatefulWidget {
  final int tId;
  final String tournamentName;
  const TugOfWarCrossTableTab({super.key, required this.tId, required this.tournamentName});

  @override
  ConsumerState<TugOfWarCrossTableTab> createState() => _TugOfWarCrossTableTabState();
}

class _TugOfWarCrossTableTabState extends ConsumerState<TugOfWarCrossTableTab> {
  static const double _maxTeamWeight = 800.0;

  bool _loading = true;
  List<({int teamId, String teamName, int? teamNumber, int? entityId})> _teams = [];
  Map<(int, int), _GameData> _games = {};
  Map<int, double> _teamWeights = {};
  Set<int> _removedTeams = {};
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
    final weights = await svc.getTeamWeights(widget.tId);
    final removed = await svc.getRemovedTeams(widget.tId);
    final teams = <({int teamId, String teamName, int? teamNumber, int? entityId})>[];
    final allTeams = await teamSvc.getAllTeams();
    for (final t in teamList) {
      final team = allTeams.where((at) => at.team_id == t.teamId).firstOrNull;
      teams.add((teamId: t.teamId, teamName: t.teamName, teamNumber: t.teamNumber, entityId: team?.entity_id));
    }
    final gamesMap = <(int, int), _GameData>{};
    for (final g in games) {
      gamesMap[(g.teamAEntityId, g.teamBEntityId)] = _GameData(eventId: g.eventId, eventResult: g.eventResult);
      gamesMap[(g.teamBEntityId, g.teamAEntityId)] = _GameData(eventId: g.eventId, eventResult: g.eventResult != null ? _mirror(g.eventResult!) : null);
    }
    setState(() { _teams = teams; _games = gamesMap; _teamWeights = weights; _removedTeams = removed; _loading = false; });
  }

  String _mirror(String r) { final p = r.split(':'); return p.length == 2 ? '${p[1]}:${p[0]}' : r; }

  List<scoring.TugOfWarStanding> _calcStandings(List<({int teamId, String teamName, int? teamNumber, int? entityId})> teams) {
    final eIds = teams.map((t) => t.entityId).whereType<int>().toSet();
    final fg = <(int, int), String>{}; final seen = <(int, int)>{};
    for (final e in _games.entries) {
      final (a, b) = e.key;
      if (eIds.contains(a) && eIds.contains(b)) {
        if (seen.contains((b, a))) continue;
        seen.add((a, b));
        if (e.value.eventResult != null) fg[(a, b)] = e.value.eventResult!;
      }
    }
    return scoring.calculateStandings(
      teams: teams.map((t) => (teamId: t.teamId, teamName: t.teamName, entityId: t.entityId, weight: _teamWeights[t.teamId])).toList(),
      games: fg,
      removedTeamIds: _removedTeams,
    );
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
        Row(children: [
          const Text('Турнірна таблиця', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(width: 12),
          Tooltip(message: 'Перемога — 2, поразка — 1, неявка — 0.\nЛіміт ваги команди — 800 кг.', child: Icon(Icons.info_outline, size: 16, color: Colors.grey.shade600)),
          const Spacer(),
          if (_games.isNotEmpty) TextButton.icon(icon: const Icon(Icons.delete_sweep_outlined, size: 14), label: const Text('Очистити', style: TextStyle(fontSize: 11)), style: TextButton.styleFrom(foregroundColor: Colors.red, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap), onPressed: _confirmClear),
          const SizedBox(width: 8), Text('$n команд', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))]),
        const SizedBox(height: 12),
        Expanded(child: Scrollbar(controller: _vCtrl, thumbVisibility: true, child: SingleChildScrollView(controller: _vCtrl,
          child: Scrollbar(controller: _hCtrl, thumbVisibility: true, notificationPredicate: (n) => n.depth == 1, child: SingleChildScrollView(controller: _hCtrl, scrollDirection: Axis.horizontal,
            child: Table(defaultColumnWidth: const FixedColumnWidth(56), columnWidths: {0: const FixedColumnWidth(36), 1: const FixedColumnWidth(180), 2: const FixedColumnWidth(64), n + 3: const FixedColumnWidth(56), n + 4: const FixedColumnWidth(56), n + 5: const FixedColumnWidth(15), n + 6: const FixedColumnWidth(180), n + 7: const FixedColumnWidth(56), n + 8: const FixedColumnWidth(48)},
              border: TableBorder.all(color: Colors.grey.shade300, width: 0.5), children: [
                TableRow(decoration: BoxDecoration(color: Colors.grey.shade100), children: [_hc('#'), _hc('Команда'), _hc('Вага, кг'), for (int j = 0; j < n; j++) _hc('${_teams[j].teamNumber ?? j + 1}'), _hc('О'), _hc('В'), Container(height: 36, decoration: BoxDecoration(color: Colors.black, border: Border.all(color: Colors.black, width: 0.5))), _hc('Команда'), _hc('Очки'), _hc('Місце')]),
                for (int i = 0; i < n; i++) TableRow(decoration: BoxDecoration(color: _removedTeams.contains(_teams[i].teamId) ? Colors.red.shade50 : (_hoveredRow == i ? Colors.indigo.shade50 : null)), children: [
                  _dc('${_teams[i].teamNumber ?? i + 1}', bold: true),
                  _teamNameCell(_teams[i], flagNoShow: standingsByTeam[_teams[i].teamId]?.mustBeRemovedForNoShows ?? false),
                  _weightCell(_teams[i].teamId),
                  for (int j = 0; j < n; j++) _gc(i, j),
                  _dc('${standingsByTeam[_teams[i].teamId]?.matchPoints ?? 0}', bold: true),
                  _dc('${standingsByTeam[_teams[i].teamId]?.wins ?? 0}'),
                  Container(height: 36, decoration: BoxDecoration(color: Colors.black, border: Border.all(color: Colors.black, width: 0.5))),
                  _nc(i < standings.length ? standings[i].teamName : '', strike: i < standings.length && standings[i].isRemoved),
                  _dc(i < standings.length && standings[i].isRemoved ? '—' : '${i < standings.length ? standings[i].matchPoints : 0}', bold: true),
                  _dc(i < standings.length && standings[i].isRemoved ? '—' : '${i < standings.length ? standings[i].rank : i + 1}', bold: true),
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
    final aRemoved = _removedTeams.contains(tA.teamId);
    final bRemoved = _removedTeams.contains(tB.teamId);
    final game = _games[(tA.entityId!, tB.entityId!)];
    String cellText = ''; Color? bg; Color? textColor;
    if (game?.eventResult != null) {
      final p = game!.eventResult!.split(':');
      if (p.length == 2) {
        final aTok = p[0].trim().toUpperCase();
        final bTok = p[1].trim().toUpperCase();
        if (aTok == 'N') { cellText = '0'; bg = Colors.orange.shade50; textColor = Colors.orange.shade800; }
        else if (bTok == 'N') { cellText = '+'; bg = Colors.green.shade50; textColor = Colors.green.shade700; }
        else {
          final a = int.tryParse(aTok) ?? 0, b = int.tryParse(bTok) ?? 0;
          if (a > b) { cellText = '+'; bg = Colors.green.shade50; textColor = Colors.green.shade700; }
          else { cellText = '−'; bg = Colors.red.shade50; textColor = Colors.red.shade700; }
        }
      }
    }
    final clickable = !aRemoved && !bRemoved;
    return MouseRegion(
      onEnter: clickable ? (_) => setState(() { _hoveredRow = i; _hoveredCol = j; }) : null,
      onExit: clickable ? (_) => setState(() { _hoveredRow = null; _hoveredCol = null; }) : null,
      cursor: clickable ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: clickable ? () => _showResultDialog(tA, tB, game) : null,
        child: Container(height: 36, alignment: Alignment.center,
          color: bg ?? (_hoveredCol == j && _hoveredRow == i ? Colors.indigo.shade50 : null),
          child: Text(cellText, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textColor)))));
  }

  /// Dialog: choose winner or mark either side as no-show.
  Future<void> _showResultDialog(dynamic tA, dynamic tB, _GameData? existing) async {
    final result = await showDialog<_ResultChoice?>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Результат поєдинку', style: TextStyle(fontSize: 16)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('${tA.teamName}  vs  ${tB.teamName}', style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 16),
        const Text('Переможець:', style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          ElevatedButton.icon(
            icon: const Icon(Icons.emoji_events, color: Colors.amber),
            label: Text(_truncate(tA.teamName)),
            onPressed: () => Navigator.pop(ctx, _ResultChoice.winner(tA.entityId as int)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.emoji_events, color: Colors.amber),
            label: Text(_truncate(tB.teamName)),
            onPressed: () => Navigator.pop(ctx, _ResultChoice.winner(tB.entityId as int)),
          ),
        ]),
        const SizedBox(height: 12),
        const Divider(),
        const SizedBox(height: 4),
        const Text('Неявка (0 очок):', style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.person_off_outlined, size: 18, color: Colors.orange),
            label: Text(_truncate(tA.teamName)),
            onPressed: () => Navigator.pop(ctx, _ResultChoice.noShow(tA.entityId as int)),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.person_off_outlined, size: 18, color: Colors.orange),
            label: Text(_truncate(tB.teamName)),
            onPressed: () => Navigator.pop(ctx, _ResultChoice.noShow(tB.entityId as int)),
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
    if (result.kind == _ResultKind.winner) {
      await svc.saveResult(eventId: eventId, teamAEntityId: tA.entityId!, teamBEntityId: tB.entityId!, winnerEntityId: result.entityId);
    } else {
      await svc.saveNoShow(eventId: eventId, teamAEntityId: tA.entityId!, teamBEntityId: tB.entityId!, noShowEntityId: result.entityId);
    }
    await _loadData();
  }

  String _truncate(String s) => s.length > 15 ? '${s.substring(0, 15)}…' : s;

  Future<void> _del(int id) async { await ref.read(tugOfWarServiceProvider).deleteTeamGame(id); await _loadData(); }
  void _confirmClear() { showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('Очистити результати?'), content: const Text('Видалити всі результати поєдинків?'), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Скасувати')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () { Navigator.pop(ctx); _clearAll(); }, child: const Text('Очистити', style: TextStyle(color: Colors.white)))])); }
  Future<void> _clearAll() async { final svc = ref.read(tugOfWarServiceProvider); for (final id in _games.values.map((g) => g.eventId).toSet()) { await svc.deleteTeamGame(id); } await _loadData(); }

  Widget _teamNameCell(({int teamId, String teamName, int? teamNumber, int? entityId}) t, {bool flagNoShow = false}) {
    final removed = _removedTeams.contains(t.teamId);
    return InkWell(
      onTap: () => _showTeamMenu(t),
      child: Container(
        height: 36, alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          if (removed) Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.block, size: 14, color: Colors.red.shade700))
          else if (flagNoShow) Padding(padding: const EdgeInsets.only(right: 4), child: Tooltip(message: 'Друга неявка — за правилами команду слід зняти з турніру', child: Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orange.shade800))),
          Expanded(child: Text(t.teamName, style: TextStyle(
            fontSize: 12,
            decoration: removed ? TextDecoration.lineThrough : null,
            color: removed ? Colors.red.shade700 : null,
          ), overflow: TextOverflow.ellipsis)),
        ]),
      ),
    );
  }

  Future<void> _showTeamMenu(({int teamId, String teamName, int? teamNumber, int? entityId}) t) async {
    final removed = _removedTeams.contains(t.teamId);
    final action = await showDialog<String?>(context: context, builder: (ctx) => AlertDialog(
      title: Text(t.teamName, style: const TextStyle(fontSize: 16)),
      content: Text(removed
        ? 'Команду знято з турніру. Усі її результати анульовано.'
        : 'Зняти команду з турніру?\nЗа правилами це робиться у разі другої неявки або неспортивної поведінки. Усі результати команди буде анульовано.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Скасувати')),
        if (removed)
          ElevatedButton(onPressed: () => Navigator.pop(ctx, 'restore'), child: const Text('Відновити'))
        else
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, 'remove'),
            child: const Text('Зняти з турніру', style: TextStyle(color: Colors.white)),
          ),
      ],
    ));
    if (action == null) return;
    await ref.read(tugOfWarServiceProvider).setTeamRemoved(widget.tId, t.teamId, action == 'remove');
    await _loadData();
  }

  Widget _weightCell(int teamId) {
    final w = _teamWeights[teamId];
    final over = w != null && w > _maxTeamWeight;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _editWeight(teamId, w),
      child: Container(
        height: 36, alignment: Alignment.center,
        color: over ? Colors.red.shade50 : null,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (over) Padding(padding: const EdgeInsets.only(right: 2), child: Icon(Icons.warning_amber_rounded, size: 12, color: Colors.red.shade700)),
          Text(w != null ? w.toStringAsFixed(1) : '—', style: TextStyle(
            fontSize: 11,
            color: over ? Colors.red.shade700 : (w != null ? null : Colors.grey.shade400),
            fontWeight: over ? FontWeight.bold : null,
          )),
        ]),
      ),
    );
  }

  Future<void> _editWeight(int teamId, double? current) async {
    final controller = TextEditingController(text: current?.toStringAsFixed(1) ?? '');
    final result = await showDialog<double?>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Вага команди (кг)', style: TextStyle(fontSize: 16)),
      content: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Вага (макс. 800 кг)', border: OutlineInputBorder(), helperText: 'Зважування проводиться за 1 год до старту'),
        autofocus: true,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Скасувати')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, double.tryParse(controller.text.replaceAll(',', '.'))), child: const Text('Зберегти')),
      ],
    ));
    controller.dispose();
    if (result != null) {
      await ref.read(tugOfWarServiceProvider).saveTeamWeight(widget.tId, teamId, result);
      if (result > _maxTeamWeight && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Увага: ${result.toStringAsFixed(1)} кг перевищує ліміт 800 кг'), backgroundColor: Colors.red),
        );
      }
      await _loadData();
    }
  }

  Widget _hc(String t) => Container(height: 36, alignment: Alignment.center, color: Colors.grey.shade100, child: Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)));
  Widget _dc(String t, {bool bold = false}) => Container(height: 36, alignment: Alignment.center, child: Text(t, style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.bold : null)));
  Widget _nc(String n, {bool strike = false}) => Container(height: 36, alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(n, style: TextStyle(fontSize: 12, decoration: strike ? TextDecoration.lineThrough : null, color: strike ? Colors.grey : null), overflow: TextOverflow.ellipsis));
}

class _GameData { final int eventId; final String? eventResult; _GameData({required this.eventId, this.eventResult}); }

enum _ResultKind { winner, noShow }

class _ResultChoice {
  final _ResultKind kind;
  final int entityId;
  _ResultChoice._(this.kind, this.entityId);
  factory _ResultChoice.winner(int entityId) => _ResultChoice._(_ResultKind.winner, entityId);
  factory _ResultChoice.noShow(int entityId) => _ResultChoice._(_ResultKind.noShow, entityId);
}
