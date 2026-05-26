import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../viewmodels/tournament_viewmodel.dart';
import 'arm_wrestling_bracket.dart';
import 'arm_wrestling_providers.dart';
import 'arm_wrestling_scoring.dart';

class _CategoryData {
  final List<({int playerId, String fullName, String teamName, int? number, double? weight})> players;
  final Bracket bracket;
  const _CategoryData({required this.players, required this.bracket});
}

final _categoryBracketProvider = FutureProvider.family
    .autoDispose<_CategoryData, ({int tId, int catId})>((ref, key) async {
  final svc = ref.watch(armWrestlingBracketServiceProvider);
  final loaded = await svc.loadCategory(key.tId, key.catId);
  final seedOrder = loaded.players.map((p) => p.playerId).toList();
  final bracket = buildBracket(
    seededPlayerIds: seedOrder,
    rawMatches: loaded.raws,
  );
  return _CategoryData(players: loaded.players, bracket: bracket);
});

/// Bracket view for one weight category. Shows the seed list (drag-and-drop
/// reorder while no matches are played) and the double-elimination bracket
/// with click-to-set-winner cells.
class ArmWrestlingBracketView extends ConsumerWidget {
  final int tId;
  final int categoryId;
  const ArmWrestlingBracketView({super.key, required this.tId, required this.categoryId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_categoryBracketProvider((tId: tId, catId: categoryId)));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Помилка: $e')),
      data: (data) => _Body(
        tId: tId,
        categoryId: categoryId,
        data: data,
        onChanged: () => ref.invalidate(_categoryBracketProvider((tId: tId, catId: categoryId))),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  final int tId;
  final int categoryId;
  final _CategoryData data;
  final VoidCallback onChanged;
  const _Body({
    required this.tId,
    required this.categoryId,
    required this.data,
    required this.onChanged,
  });

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  late Map<int, String> _nameByPid;
  late Map<int, String> _teamByPid;

  @override
  void initState() {
    super.initState();
    _refreshLookups();
  }

  @override
  void didUpdateWidget(covariant _Body oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) _refreshLookups();
  }

  void _refreshLookups() {
    _nameByPid = {for (final p in widget.data.players) p.playerId: p.fullName};
    _teamByPid = {for (final p in widget.data.players) p.playerId: p.teamName};
  }

  bool get _anyMatchPlayed =>
      widget.data.bracket.matches.values.any((m) => m.isDecided && m.eventId != null);

  Future<void> _reorderSeeds(int oldIndex, int newIndex) async {
    final players = widget.data.players;
    if (newIndex > oldIndex) newIndex--;
    final moving = players[oldIndex];
    final svc = ref.read(armWrestlingBracketServiceProvider);
    await svc.reorderTo(
      tId: widget.tId,
      categoryId: widget.categoryId,
      playerId: moving.playerId,
      newPosition: newIndex,
    );
    widget.onChanged();
    ref.invalidate(armWrestlingStandingsProvider(widget.tId));
  }

  Future<void> _setWinner(BracketMatch match, int winnerPlayerId) async {
    if (!match.isPlayable) return;
    final tournamentSvc = ref.read(tournamentServiceProvider);
    int? eventId = match.eventId;
    eventId ??= await tournamentSvc.createGame(
      tId: widget.tId,
      whitePlayerId: match.playerAId!,
      blackPlayerId: match.playerBId!,
    );
    final loserId = winnerPlayerId == match.playerAId ? match.playerBId! : match.playerAId!;
    await tournamentSvc.saveResultForPlayer(eventId!, winnerPlayerId, 1.0);
    await tournamentSvc.saveResultForPlayer(eventId, loserId, 0.0);
    widget.onChanged();
    ref.invalidate(armWrestlingStandingsProvider(widget.tId));
  }

  Future<void> _clearMatch(BracketMatch match) async {
    if (match.eventId == null) return;
    final tournamentSvc = ref.read(tournamentServiceProvider);
    await tournamentSvc.saveResultForPlayer(match.eventId!, match.playerAId!, null);
    await tournamentSvc.saveResultForPlayer(match.eventId!, match.playerBId!, null);
    widget.onChanged();
    ref.invalidate(armWrestlingStandingsProvider(widget.tId));
  }

  @override
  Widget build(BuildContext context) {
    final cat = WeightCategory.fromId(widget.categoryId);
    final players = widget.data.players;
    if (players.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.fitness_center, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'Немає учасників у категорії ${cat?.label ?? widget.categoryId}.',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSeedSection(),
          const SizedBox(height: 16),
          _buildBracketSection(),
          const SizedBox(height: 16),
          _buildRankingSection(),
        ],
      ),
    );
  }

  Widget _buildSeedSection() {
    final players = widget.data.players;
    final locked = _anyMatchPlayed;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.format_list_numbered, size: 18, color: Colors.indigo.shade700),
                const SizedBox(width: 6),
                Text(
                  'Посів (${players.length})',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo.shade900,
                  ),
                ),
                const SizedBox(width: 12),
                if (locked)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Text(
                      'Посів заблоковано — є зіграні матчі',
                      style: TextStyle(fontSize: 11, color: Colors.amber.shade900),
                    ),
                  )
                else
                  Text(
                    'Перетягніть, щоб змінити посів',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: (players.length * 36.0).clamp(36.0, 220.0),
              child: ReorderableListView.builder(
                buildDefaultDragHandles: !locked,
                itemCount: players.length,
                onReorder: locked ? (_, __) {} : _reorderSeeds,
                itemBuilder: (context, i) {
                  final p = players[i];
                  return Container(
                    key: ValueKey('seed-${p.playerId}'),
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Colors.grey.shade200),
                      ),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 32,
                          child: Text(
                            '${i + 1}.',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo.shade700,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 44,
                          child: Text(
                            p.number != null ? '№${p.number}' : '—',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(p.fullName,
                              style: const TextStyle(fontSize: 13),
                              overflow: TextOverflow.ellipsis),
                        ),
                        Expanded(
                          child: Text(p.teamName,
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (p.weight != null) ...[
                          const SizedBox(width: 6),
                          Text('${p.weight!.toStringAsFixed(1)} кг',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBracketSection() {
    final bracket = widget.data.bracket;
    if (bracket.realPlayerCount < 2) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Потрібно щонайменше 2 учасники для сітки.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
      );
    }
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Сітка (Double elimination)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo.shade900,
                )),
            const SizedBox(height: 4),
            Text(
              'Натисніть на ім\'я учасника, щоб відмітити його переможцем '
              'матчу (довге натискання — скасувати результат). Програш у верхній '
              'сітці переводить у нижню; програш у нижній або у фіналі — '
              'вибуття. «— без суперника —» означає що у цьому матчі лише один '
              'учасник: він автоматично переходить далі. «Очікування…» — слот, '
              'який займе переможець попереднього матчу.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _buildBracketColumns(bracket),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBracketColumns(Bracket bracket) {
    // Group matches by (side, round).
    final wByRound = <int, List<BracketMatch>>{};
    final lByRound = <int, List<BracketMatch>>{};
    BracketMatch? gf;
    BracketMatch? gfr;
    for (final m in bracket.inOrder) {
      switch (m.side) {
        case BracketSide.winners:
          wByRound.putIfAbsent(m.round, () => []).add(m);
          break;
        case BracketSide.losers:
          lByRound.putIfAbsent(m.round, () => []).add(m);
          break;
        case BracketSide.grandFinal:
          gf = m;
          break;
        case BracketSide.grandFinalReset:
          gfr = m;
          break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (wByRound.isNotEmpty)
          _bracketHalf(
            title: 'Верхня сітка',
            color: Colors.indigo,
            roundsByIndex: wByRound,
            sidePrefix: 'W',
          ),
        const SizedBox(height: 16),
        if (lByRound.isNotEmpty)
          _bracketHalf(
            title: 'Нижня сітка',
            color: Colors.deepOrange,
            roundsByIndex: lByRound,
            sidePrefix: 'L',
          ),
        if (gf != null) ...[
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _roundColumn('Великий фінал', [gf], Colors.purple),
              if (gfr != null) _roundColumn('Перегравання', [gfr], Colors.purple),
            ],
          ),
        ],
      ],
    );
  }

  // Vertical layout constants for bracket columns. _matchH is approximate —
  // a real card is ~52–60 px tall depending on whether the team line shows.
  // Centering uses an "expected pair gap" so later rounds line up with the
  // midpoint of the two upstream matches.
  static const double _matchH = 56;
  static const double _matchGap = 8;
  static const double _matchPitch = _matchH + _matchGap; // total stride per slot

  Widget _bracketHalf({
    required String title,
    required MaterialColor color,
    required Map<int, List<BracketMatch>> roundsByIndex,
    required String sidePrefix,
  }) {
    final rounds = roundsByIndex.keys.toList()..sort();
    final firstRoundCount =
        roundsByIndex[rounds.first]?.length ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color.shade700,
            )),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final r in rounds)
              _roundColumn(
                '$sidePrefix$r',
                roundsByIndex[r]!,
                color,
                // Each subsequent round's match groups twice as many round-1
                // slots, so the vertical pitch and leading offset double.
                slotPitchMultiplier:
                    _multiplierFor(rounds.length, rounds.indexOf(r), firstRoundCount,
                        roundsByIndex[r]!.length),
              ),
          ],
        ),
      ],
    );
  }

  /// How many round-1 "slot heights" one match in this round covers.
  ///
  /// For the W bracket this is `2^(roundIndex-1)`. For the L bracket the
  /// per-round count alternates (odd rounds halve, even rounds keep), so
  /// derive it from `firstRoundCount / thisRoundCount`.
  double _multiplierFor(int totalRounds, int roundIdx, int firstCount, int thisCount) {
    if (thisCount <= 0) return 1;
    return firstCount / thisCount;
  }

  Widget _roundColumn(
    String label,
    List<BracketMatch> matches,
    MaterialColor color, {
    double slotPitchMultiplier = 1,
  }) {
    // Leading offset before the first card so it lines up with the centre
    // of the corresponding pair in round 1.
    final leadingPad = (slotPitchMultiplier - 1) * _matchPitch / 2;
    // Between consecutive cards in this round.
    final betweenPad = slotPitchMultiplier * _matchPitch - _matchH;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color.shade700,
                letterSpacing: 0.5,
              ),
            ),
          ),
          SizedBox(height: leadingPad),
          for (int i = 0; i < matches.length; i++) ...[
            if (i > 0) SizedBox(height: betweenPad),
            _matchCard(matches[i], color),
          ],
        ],
      ),
    );
  }

  Widget _matchCard(BracketMatch m, MaterialColor color) {
    // Material ancestor required for InkWell to splash *and* for its
    // hit-test to behave reliably inside nested scroll views.
    final borderColor = m.isPlayable && !m.isDecided
        ? color.shade400   // ready-to-play matches get a stronger outline
        : color.shade200;
    return Material(
      type: MaterialType.card,
      color: Colors.white,
      elevation: 0,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 200,
        decoration: BoxDecoration(
          border: Border.all(
            color: borderColor,
            width: m.isPlayable && !m.isDecided ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 3,
                offset: const Offset(0, 1)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _matchPlayerRow(m, m.playerAId, isA: true, color: color),
            Divider(height: 1, color: color.shade100),
            _matchPlayerRow(m, m.playerBId, isA: false, color: color),
          ],
        ),
      ),
    );
  }

  Widget _matchPlayerRow(BracketMatch m, int? pid, {required bool isA, required MaterialColor color}) {
    final isByeSlot = isA ? m.isAByeSlot : m.isBByeSlot;
    final isPending = pid == null && !isByeSlot;
    final isWinner = m.isDecided && pid != null && pid == m.winnerPlayerId;
    final isLoser = m.isDecided && pid != null && pid != m.winnerPlayerId;
    final name = pid != null
        ? (_nameByPid[pid] ?? '—')
        : (isByeSlot ? '— без суперника —' : 'Очікування…');
    final team = pid != null ? (_teamByPid[pid] ?? '') : '';
    // Clickable only when the match is fully playable (two real players)
    // and this row's player is real. Bye advancements and pending slots
    // are not clickable.
    final canSelect = m.isPlayable && pid != null;
    final tooltip = canSelect
        ? 'Натисніть, щоб обрати $name переможцем'
        : (m.isByeAdvancement
            ? 'Прохід без бою: ${_nameByPid[m.winnerPlayerId ?? -1] ?? '—'} переходить далі'
            : null);

    final row = InkWell(
      onTap: canSelect ? () => _setWinner(m, pid) : null,
      onLongPress: m.isDecided && !m.isByeAdvancement
          ? () => _clearMatch(m)
          : null,
      mouseCursor: canSelect ? SystemMouseCursors.click : SystemMouseCursors.basic,
      hoverColor: canSelect ? color.shade50 : null,
      splashColor: canSelect ? color.shade100 : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isWinner ? color.shade50 : null,
        ),
        child: Row(
          children: [
            Icon(
              isWinner ? Icons.emoji_events : Icons.circle_outlined,
              size: 14,
              color: isWinner
                  ? color.shade700
                  : (isLoser ? Colors.grey.shade400 : color.shade300),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isWinner ? FontWeight.bold : FontWeight.w500,
                      color: isLoser
                          ? Colors.grey.shade500
                          : (isPending || isByeSlot
                              ? Colors.grey.shade400
                              : Colors.black87),
                      fontStyle: (isPending || isByeSlot) ? FontStyle.italic : null,
                      decoration: isLoser ? TextDecoration.lineThrough : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (team.isNotEmpty)
                    Text(
                      team,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip, child: row) : row;
  }

  Widget _buildRankingSection() {
    final ranking = widget.data.bracket.ranking;
    if (ranking.isEmpty) return const SizedBox.shrink();
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.green.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Підсумкові місця',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.green.shade800,
              ),
            ),
            const SizedBox(height: 6),
            for (int i = 0; i < ranking.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(
                        '${i + 1}.',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: i == 0
                              ? Colors.amber.shade700
                              : (i == 1
                                  ? Colors.grey.shade600
                                  : (i == 2 ? Colors.brown.shade400 : Colors.black87)),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(_nameByPid[ranking[i]] ?? 'ID ${ranking[i]}'),
                    ),
                    Text(
                      _teamByPid[ranking[i]] ?? '',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
