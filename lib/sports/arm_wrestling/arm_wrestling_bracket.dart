/// Pure-Dart double-elimination bracket engine for a single weight category.
///
/// Storage policy (per the design decisions):
///   • Seeding is the player's participant number (CMP_PLAYER_TEAM_ATTR_VALUE
///     attr_id = 19). Drag-and-drop swaps numbers between two players.
///   • Matches are plain CMP_EVENT rows with two CMP_SUBEVENT participants
///     and `event_result` = '1' or '2' for which subevent won. NO bracket
///     slot id is persisted — we derive the bracket entirely from
///     (seed list, played matches) every render.
///
/// The bracket includes winners, losers, grand final and an optional grand
/// final RESET match (played only if the losers-bracket champion wins the
/// first GF). Byes are inserted to round the field up to the next power of
/// two and are auto-advanced.
library;

import 'dart:math' as math;

/// Which half of the bracket a match belongs to.
enum BracketSide { winners, losers, grandFinal, grandFinalReset }

/// A single match. `winnerPlayerId == null` means the result is not yet
/// recorded. A slot's player can be:
///   • a real player id (`playerAId != null`)
///   • a bye (`playerAId == null` and `isAByeSlot == true`) — the upstream
///     match was a bye / had no real player, so this slot is permanently
///     empty. The opponent auto-advances.
///   • pending (`playerAId == null` and `isAByeSlot == false`) — the
///     upstream match has not yet been decided. No auto-advance, the
///     slot is not clickable yet.
class BracketMatch {
  final String id;                // stable slot id: "W1.1", "L2.1", "GF", "GFR"
  final BracketSide side;
  final int round;                // 1-based within `side`
  final int slot;                 // 1-based within (side, round)
  final int? playerAId;
  final int? playerBId;
  final bool isAByeSlot;
  final bool isBByeSlot;
  final int? winnerPlayerId;
  /// Backing CMP_EVENT id, if this match has been entered into the DB.
  final int? eventId;
  /// Order index used to disambiguate duplicate pairings (GF + GFR), based
  /// on the order the events were created.
  final int eventOrderIndex;

  const BracketMatch({
    required this.id,
    required this.side,
    required this.round,
    required this.slot,
    this.playerAId,
    this.playerBId,
    this.isAByeSlot = false,
    this.isBByeSlot = false,
    this.winnerPlayerId,
    this.eventId,
    this.eventOrderIndex = 0,
  });

  /// Both sides have real players → match is playable.
  bool get isPlayable => playerAId != null && playerBId != null;

  /// A bye match: exactly one side is a bye slot, the other is a real
  /// player. The real player auto-advances; no result is recorded.
  bool get isByeAdvancement =>
      (isAByeSlot && playerBId != null && !isBByeSlot) ||
      (isBByeSlot && playerAId != null && !isAByeSlot);

  bool get isDecided => winnerPlayerId != null;

  int? get loserPlayerId {
    if (!isPlayable || !isDecided) return null;
    return winnerPlayerId == playerAId ? playerBId : playerAId;
  }
}

/// A slot in a bracket round — used internally during building. Outside
/// callers only see BracketMatch.
class _Slot {
  final int? playerId;
  final bool isBye;
  const _Slot._(this.playerId, this.isBye);
  const _Slot.player(int id) : this._(id, false);
  const _Slot.bye() : this._(null, true);
  const _Slot.pending() : this._(null, false);
}

/// Input to bracket generation: the result of a CMP_EVENT match between
/// two players in this category, in DB insertion order.
class RawMatch {
  final int eventId;
  final int playerAId;
  final int playerBId;
  final int? winnerPlayerId;
  const RawMatch({
    required this.eventId,
    required this.playerAId,
    required this.playerBId,
    this.winnerPlayerId,
  });
}

class Bracket {
  /// Ordered seed list. Each entry is a playerId; `null` means a bye slot.
  /// Length is always a power of two ≥ number of real players, ≥ 2.
  final List<int?> seeds;
  /// Slot id → BracketMatch.
  final Map<String, BracketMatch> matches;
  /// Number of winners-bracket rounds.
  final int winnersRounds;
  /// Number of losers-bracket rounds.
  final int losersRounds;
  /// Final ranking (1st, 2nd, 3rd…) once enough matches have been decided.
  /// playerId at index i → place i+1.
  final List<int> ranking;

  const Bracket({
    required this.seeds,
    required this.matches,
    required this.winnersRounds,
    required this.losersRounds,
    required this.ranking,
  });

  /// Total number of "real" players (non-byes) in the seed list.
  int get realPlayerCount => seeds.where((s) => s != null).length;

  /// All matches in display order: W round 1, W2, …, L1, L2, …, GF, GFR.
  Iterable<BracketMatch> get inOrder sync* {
    for (int r = 1; r <= winnersRounds; r++) {
      int slot = 1;
      while (true) {
        final m = matches['W$r.$slot'];
        if (m == null) break;
        yield m;
        slot++;
      }
    }
    for (int r = 1; r <= losersRounds; r++) {
      int slot = 1;
      while (true) {
        final m = matches['L$r.$slot'];
        if (m == null) break;
        yield m;
        slot++;
      }
    }
    final gf = matches['GF'];
    if (gf != null) yield gf;
    final gfr = matches['GFR'];
    if (gfr != null) yield gfr;
  }
}

/// Standard recursive bracket-position seeding: emits a permutation of
/// [1..n] where adjacent pairs are W-round-1 opponents.
///   positions(1)  = [1]
///   positions(2)  = [1, 2]
///   positions(4)  = [1, 4, 2, 3]
///   positions(8)  = [1, 8, 4, 5, 2, 7, 3, 6]
List<int> seedPositions(int n) {
  assert(n >= 1 && (n & (n - 1)) == 0, 'n must be a power of two');
  if (n == 1) return [1];
  final prev = seedPositions(n ~/ 2);
  final out = <int>[];
  for (final p in prev) {
    out.add(p);
    out.add(n + 1 - p);
  }
  return out;
}

/// Build the bracket from the seed list (already sorted by seed) and any
/// matches recorded so far. Matches that are not yet played simply leave
/// `winnerPlayerId == null` on their slot.
Bracket buildBracket({
  required List<int> seededPlayerIds,
  required List<RawMatch> rawMatches,
}) {
  if (seededPlayerIds.isEmpty) {
    return const Bracket(
      seeds: [],
      matches: {},
      winnersRounds: 0,
      losersRounds: 0,
      ranking: [],
    );
  }

  // Round up to next power of two; pad with byes.
  int bracketSize = 1;
  while (bracketSize < seededPlayerIds.length) bracketSize <<= 1;
  if (bracketSize < 2) bracketSize = 2;

  final positions = seedPositions(bracketSize);
  final seeds = List<int?>.filled(bracketSize, null);
  for (int i = 0; i < bracketSize; i++) {
    final seedRank = positions[i];
    if (seedRank <= seededPlayerIds.length) {
      seeds[i] = seededPlayerIds[seedRank - 1];
    }
  }

  // Index raw matches by unordered pair, preserving DB insertion order so
  // GF and GFR can be told apart.
  final byPair = <String, List<RawMatch>>{};
  final orderedRaw = [...rawMatches];
  for (final m in orderedRaw) {
    final key = _pairKey(m.playerAId, m.playerBId);
    byPair.putIfAbsent(key, () => []).add(m);
  }

  final matches = <String, BracketMatch>{};
  final winnersRounds = (math.log(bracketSize) / math.ln2).round();

  // --- WINNERS BRACKET ---
  // Tracked per round: winners[] and losers[] as _Slot lists so we can
  // distinguish "real player advanced" from "bye pass-through" from
  // "pending upstream".
  final List<List<_Slot>> wRoundWinners = [];
  final List<List<_Slot>> wRoundLosers = [];

  List<List<_Slot>> currentRoundPairs = [];
  for (int i = 0; i < bracketSize; i += 2) {
    currentRoundPairs.add([
      seeds[i] == null ? const _Slot.bye() : _Slot.player(seeds[i]!),
      seeds[i + 1] == null ? const _Slot.bye() : _Slot.player(seeds[i + 1]!),
    ]);
  }

  for (int r = 1; r <= winnersRounds; r++) {
    final winners = <_Slot>[];
    final losers = <_Slot>[];
    for (int s = 0; s < currentRoundPairs.length; s++) {
      final pair = currentRoundPairs[s];
      final result = _emitMatch(
        matches: matches,
        byPair: byPair,
        orderedRaw: orderedRaw,
        slotId: 'W$r.${s + 1}',
        side: BracketSide.winners,
        round: r,
        slot: s + 1,
        a: pair[0],
        b: pair[1],
      );
      winners.add(result.$1);
      losers.add(result.$2);
    }
    wRoundWinners.add(winners);
    wRoundLosers.add(losers);

    if (r < winnersRounds) {
      final next = <List<_Slot>>[];
      for (int i = 0; i < winners.length; i += 2) {
        next.add([
          winners[i],
          i + 1 < winners.length ? winners[i + 1] : const _Slot.bye(),
        ]);
      }
      currentRoundPairs = next;
    }
  }

  // --- LOSERS BRACKET ---
  // Layout for k winners-rounds: 2*(k-1) L-rounds.
  // Odd L rounds pair losers/winners of the previous L round (or W1 for L1).
  // Even L rounds pair previous-L-round winners with fresh W-round losers.
  final losersRounds = math.max(0, 2 * (winnersRounds - 1));
  final List<List<_Slot>> lRoundWinners = [];

  if (losersRounds >= 1) {
    final w1Losers = wRoundLosers[0];
    final pairs = <List<_Slot>>[];
    for (int i = 0; i < w1Losers.length; i += 2) {
      pairs.add([
        w1Losers[i],
        i + 1 < w1Losers.length ? w1Losers[i + 1] : const _Slot.bye(),
      ]);
    }
    final winners = <_Slot>[];
    for (int s = 0; s < pairs.length; s++) {
      final res = _emitMatch(
        matches: matches,
        byPair: byPair,
        orderedRaw: orderedRaw,
        slotId: 'L1.${s + 1}',
        side: BracketSide.losers,
        round: 1,
        slot: s + 1,
        a: pairs[s][0],
        b: pairs[s][1],
      );
      winners.add(res.$1);
    }
    lRoundWinners.add(winners);
  }

  for (int r = 2; r <= losersRounds; r++) {
    final pairs = <List<_Slot>>[];
    if (r.isEven) {
      final wRoundIndex = r ~/ 2; // 0-based: 1 → roundLosers[1] (W2)
      final wLosers = wRoundIndex < wRoundLosers.length
          ? wRoundLosers[wRoundIndex]
          : const <_Slot>[];
      final prevLWinners = lRoundWinners.isNotEmpty ? lRoundWinners.last : const <_Slot>[];
      final n = math.max(prevLWinners.length, wLosers.length);
      for (int i = 0; i < n; i++) {
        pairs.add([
          i < prevLWinners.length ? prevLWinners[i] : const _Slot.bye(),
          i < wLosers.length ? wLosers[i] : const _Slot.bye(),
        ]);
      }
    } else {
      final prev = lRoundWinners.last;
      for (int i = 0; i < prev.length; i += 2) {
        pairs.add([
          prev[i],
          i + 1 < prev.length ? prev[i + 1] : const _Slot.bye(),
        ]);
      }
    }
    final winners = <_Slot>[];
    for (int s = 0; s < pairs.length; s++) {
      final res = _emitMatch(
        matches: matches,
        byPair: byPair,
        orderedRaw: orderedRaw,
        slotId: 'L$r.${s + 1}',
        side: BracketSide.losers,
        round: r,
        slot: s + 1,
        a: pairs[s][0],
        b: pairs[s][1],
      );
      winners.add(res.$1);
    }
    lRoundWinners.add(winners);
  }

  // --- GRAND FINAL ---
  final wChampion = wRoundWinners.isNotEmpty ? wRoundWinners.last.firstOrNull : null;
  final lChampion = lRoundWinners.isNotEmpty ? lRoundWinners.last.firstOrNull : null;
  int? gfWinner;
  int? gfLoser;
  if (wChampion != null && lChampion != null) {
    _emitMatch(
      matches: matches,
      byPair: byPair,
      orderedRaw: orderedRaw,
      slotId: 'GF',
      side: BracketSide.grandFinal,
      round: 1,
      slot: 1,
      a: wChampion,
      b: lChampion,
    );
    final gf = matches['GF']!;
    gfWinner = gf.winnerPlayerId;
    gfLoser = gf.loserPlayerId;

    // Bracket reset: only played if the LB winner won the first GF.
    if (gfWinner != null && lChampion.playerId != null && gfWinner == lChampion.playerId) {
      _emitMatch(
        matches: matches,
        byPair: byPair,
        orderedRaw: orderedRaw,
        slotId: 'GFR',
        side: BracketSide.grandFinalReset,
        round: 1,
        slot: 1,
        a: wChampion,
        b: lChampion,
      );
      final gfr = matches['GFR']!;
      if (gfr.isDecided) {
        gfWinner = gfr.winnerPlayerId;
        gfLoser = gfr.loserPlayerId;
      } else {
        gfWinner = null;
        gfLoser = null;
      }
    }
  }

  final ranking = _computeRanking(
    matches: matches,
    winnersRounds: winnersRounds,
    losersRounds: losersRounds,
    gfWinner: gfWinner,
    gfLoser: gfLoser,
    wChampion: wChampion?.playerId,
  );

  return Bracket(
    seeds: seeds,
    matches: matches,
    winnersRounds: winnersRounds,
    losersRounds: losersRounds,
    ranking: ranking,
  );
}

/// Emits one match and returns `(winnerSlot, loserSlot)` for the next round.
///
/// Auto-advance fires only when the opposite side is a true bye slot.
/// A `_Slot.pending()` opposite never triggers auto-advance.
(_Slot, _Slot) _emitMatch({
  required Map<String, BracketMatch> matches,
  required Map<String, List<RawMatch>> byPair,
  required List<RawMatch> orderedRaw,
  required String slotId,
  required BracketSide side,
  required int round,
  required int slot,
  required _Slot a,
  required _Slot b,
}) {
  int? winner;
  int? eventId;
  int eventOrder = 0;
  if (a.isBye && b.playerId != null) {
    winner = b.playerId;
  } else if (b.isBye && a.playerId != null) {
    winner = a.playerId;
  } else if (a.playerId != null && b.playerId != null) {
    final raws = byPair[_pairKey(a.playerId!, b.playerId!)] ?? const [];
    if (raws.isNotEmpty) {
      final raw = raws.removeAt(0);
      winner = raw.winnerPlayerId;
      eventId = raw.eventId;
      eventOrder = orderedRaw.indexOf(raw);
    }
  }
  matches[slotId] = BracketMatch(
    id: slotId,
    side: side,
    round: round,
    slot: slot,
    playerAId: a.playerId,
    playerBId: b.playerId,
    isAByeSlot: a.isBye,
    isBByeSlot: b.isBye,
    winnerPlayerId: winner,
    eventId: eventId,
    eventOrderIndex: eventOrder,
  );

  // Determine winner & loser slots for downstream rounds.
  _Slot winnerSlot;
  _Slot loserSlot;
  if (a.isBye && b.isBye) {
    winnerSlot = const _Slot.bye();
    loserSlot = const _Slot.bye();
  } else if (a.isBye) {
    // b auto-advanced; no loser.
    winnerSlot = b;
    loserSlot = const _Slot.bye();
  } else if (b.isBye) {
    winnerSlot = a;
    loserSlot = const _Slot.bye();
  } else if (a.playerId == null || b.playerId == null) {
    // Upstream is pending → this match is also pending.
    winnerSlot = const _Slot.pending();
    loserSlot = const _Slot.pending();
  } else if (winner != null) {
    final loserId = winner == a.playerId ? b.playerId! : a.playerId!;
    winnerSlot = _Slot.player(winner);
    loserSlot = _Slot.player(loserId);
  } else {
    // Both sides set but no result yet.
    winnerSlot = const _Slot.pending();
    loserSlot = const _Slot.pending();
  }
  return (winnerSlot, loserSlot);
}

String _pairKey(int a, int b) {
  final lo = a < b ? a : b;
  final hi = a < b ? b : a;
  return '$lo-$hi';
}

/// Derive final places from bracket state. Players are placed by elimination
/// round (later elimination = better place), and the GF winner takes 1st.
List<int> _computeRanking({
  required Map<String, BracketMatch> matches,
  required int winnersRounds,
  required int losersRounds,
  required int? gfWinner,
  required int? gfLoser,
  required int? wChampion,
}) {
  final eliminationOrder = <int, int>{};

  void elim(int? pid, int orderKey) {
    if (pid == null) return;
    if (!eliminationOrder.containsKey(pid)) {
      eliminationOrder[pid] = orderKey;
    }
  }

  // Degenerate 2-player bracket: no L bracket, no GF.
  if (losersRounds == 0) {
    final w11 = matches['W1.1'];
    if (w11 != null && w11.isDecided) elim(w11.loserPlayerId, 1000);
  }

  for (int r = 1; r <= losersRounds; r++) {
    int slot = 1;
    while (true) {
      final m = matches['L$r.$slot'];
      if (m == null) break;
      if (m.isDecided) elim(m.loserPlayerId, r * 10);
      slot++;
    }
  }
  final gf = matches['GF'];
  final gfr = matches['GFR'];
  if (gfr != null) {
    if (gfr.isDecided) elim(gfr.loserPlayerId, 1000);
    if (gf != null && gf.isDecided && gf.loserPlayerId != null && !eliminationOrder.containsKey(gf.loserPlayerId)) {
      elim(gf.loserPlayerId, 1000);
    }
  } else if (gf != null && gf.isDecided) {
    elim(gf.loserPlayerId, 1000);
  }

  final eliminated = eliminationOrder.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  final ranking = <int>[];
  final champion = gfWinner ?? (losersRounds == 0 ? wChampion : null);
  if (champion != null) ranking.add(champion);
  for (final e in eliminated) {
    if (e.key == champion) continue;
    if (ranking.contains(e.key)) continue;
    ranking.add(e.key);
  }
  return ranking;
}
