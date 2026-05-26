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

/// A single played match. `winnerPlayerId == null` means the result is not
/// yet recorded. Both players are non-null for an actual head-to-head; one
/// can be null if it is a pending slot (waiting on an upstream match) or a
/// bye slot.
class BracketMatch {
  final String id;                // stable slot id: "W1.1", "L2.1", "GF", "GFR"
  final BracketSide side;
  final int round;                // 1-based within `side`
  final int slot;                 // 1-based within (side, round)
  final int? playerAId;
  final int? playerBId;
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
    this.winnerPlayerId,
    this.eventId,
    this.eventOrderIndex = 0,
  });

  bool get isReady => playerAId != null && playerBId != null;
  bool get isDecided => winnerPlayerId != null;
  int? get loserPlayerId {
    if (!isDecided || !isReady) return null;
    return winnerPlayerId == playerAId ? playerBId : playerAId;
  }
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

  // Round up to next power of two; pad with byes (null).
  int bracketSize = 1;
  while (bracketSize < seededPlayerIds.length) bracketSize <<= 1;
  if (bracketSize < 2) bracketSize = 2;

  final positions = seedPositions(bracketSize);
  // seeds[i] = player at bracket position i (0-based).
  final seeds = List<int?>.filled(bracketSize, null);
  for (int i = 0; i < bracketSize; i++) {
    final seedRank = positions[i]; // 1-based
    if (seedRank <= seededPlayerIds.length) {
      seeds[i] = seededPlayerIds[seedRank - 1];
    }
  }

  // Index raw matches by unordered pair, preserving order for repeats (GF + GFR).
  final byPair = <String, List<RawMatch>>{};
  int orderCounter = 0;
  final orderedRaw = [...rawMatches];
  for (final m in orderedRaw) {
    final key = _pairKey(m.playerAId, m.playerBId);
    byPair.putIfAbsent(key, () => []).add(m);
    orderCounter++;
  }
  // Within each pair list, preserve the order the matches arrived.

  final matches = <String, BracketMatch>{};
  final winnersRounds = (math.log(bracketSize) / math.ln2).round();

  // --- WINNERS BRACKET ---
  // Round 1 pairings: consecutive pairs from the seed list.
  final List<List<int?>> roundWinners = []; // roundWinners[r-1] = players advancing into round r+1
  final List<List<int?>> roundLosers = [];  // roundLosers[r-1] = losers of round r (parallel)

  // Build W round 1 from seed pairs
  final w1Pairs = <List<int?>>[];
  for (int i = 0; i < bracketSize; i += 2) {
    w1Pairs.add([seeds[i], seeds[i + 1]]);
  }

  List<List<int?>> currentRoundPairs = w1Pairs;
  for (int r = 1; r <= winnersRounds; r++) {
    final winners = <int?>[];
    final losers = <int?>[];
    for (int s = 0; s < currentRoundPairs.length; s++) {
      final pair = currentRoundPairs[s];
      final a = pair[0];
      final b = pair[1];
      final slotId = 'W$r.${s + 1}';
      int? winner;
      int? loser;
      int? eventId;
      int eventOrder = 0;
      // Bye handling: if exactly one side is null, the other auto-advances.
      if (a == null && b != null) {
        winner = b;
      } else if (b == null && a != null) {
        winner = a;
      } else if (a != null && b != null) {
        final raws = byPair[_pairKey(a, b)] ?? const [];
        if (raws.isNotEmpty) {
          final raw = raws.removeAt(0);
          winner = raw.winnerPlayerId;
          eventId = raw.eventId;
          eventOrder = orderedRaw.indexOf(raw);
        }
      }
      if (winner != null && a != null && b != null) {
        loser = (winner == a) ? b : a;
      } else if (winner != null && (a == null || b == null)) {
        // bye: no loser
        loser = null;
      }

      matches[slotId] = BracketMatch(
        id: slotId,
        side: BracketSide.winners,
        round: r,
        slot: s + 1,
        playerAId: a,
        playerBId: b,
        winnerPlayerId: winner,
        eventId: eventId,
        eventOrderIndex: eventOrder,
      );
      winners.add(winner);
      losers.add(loser);
    }
    roundWinners.add(winners);
    roundLosers.add(losers);

    if (r < winnersRounds) {
      // Build next round's pairs from this round's winners.
      final next = <List<int?>>[];
      for (int i = 0; i < winners.length; i += 2) {
        next.add([winners[i], winners.length > i + 1 ? winners[i + 1] : null]);
      }
      currentRoundPairs = next;
    }
  }

  // --- LOSERS BRACKET ---
  // Standard layout: for k winners-rounds, losers has 2*(k-1) rounds.
  // Odd L rounds pair the previous L round's winners with each other.
  // Even L rounds pair an L-round winner with a fresh W-round loser.
  // Exception: L round 1 pairs the W round 1 losers directly.
  final losersRounds = math.max(0, 2 * (winnersRounds - 1));
  final List<List<int?>> lRoundWinners = [];

  // L round 1: pair W round 1 losers in consecutive pairs.
  if (losersRounds >= 1) {
    final w1Losers = roundLosers[0];
    final pairs = <List<int?>>[];
    for (int i = 0; i < w1Losers.length; i += 2) {
      pairs.add([w1Losers[i], i + 1 < w1Losers.length ? w1Losers[i + 1] : null]);
    }
    final winners = <int?>[];
    for (int s = 0; s < pairs.length; s++) {
      winners.add(_emitMatch(
        matches: matches,
        byPair: byPair,
        orderedRaw: orderedRaw,
        slotId: 'L1.${s + 1}',
        side: BracketSide.losers,
        round: 1,
        slot: s + 1,
        a: pairs[s][0],
        b: pairs[s][1],
      ));
    }
    lRoundWinners.add(winners);
  }

  // Subsequent L rounds
  for (int r = 2; r <= losersRounds; r++) {
    final pairs = <List<int?>>[];
    if (r.isEven) {
      // Even round: pair previous L winners with fresh W losers (from W round r/2 + 1).
      final wRoundIndex = r ~/ 2; // 1-based W round index whose losers drop here
      final wLosers = (wRoundIndex < roundLosers.length) ? roundLosers[wRoundIndex] : <int?>[];
      final prevLWinners = lRoundWinners.isNotEmpty ? lRoundWinners.last : const <int?>[];
      // Pair L-bracket survivor i with W-loser i.
      final n = math.max(prevLWinners.length, wLosers.length);
      for (int i = 0; i < n; i++) {
        final a = i < prevLWinners.length ? prevLWinners[i] : null;
        final b = i < wLosers.length ? wLosers[i] : null;
        pairs.add([a, b]);
      }
    } else {
      // Odd round (>1): pair previous L round winners with each other.
      final prev = lRoundWinners.last;
      for (int i = 0; i < prev.length; i += 2) {
        pairs.add([prev[i], i + 1 < prev.length ? prev[i + 1] : null]);
      }
    }
    final winners = <int?>[];
    for (int s = 0; s < pairs.length; s++) {
      winners.add(_emitMatch(
        matches: matches,
        byPair: byPair,
        orderedRaw: orderedRaw,
        slotId: 'L$r.${s + 1}',
        side: BracketSide.losers,
        round: r,
        slot: s + 1,
        a: pairs[s][0],
        b: pairs[s][1],
      ));
    }
    lRoundWinners.add(winners);
  }

  // --- GRAND FINAL ---
  final wChampion = roundWinners.isNotEmpty ? roundWinners.last.firstOrNull : null;
  final lChampion = lRoundWinners.isNotEmpty ? lRoundWinners.last.firstOrNull : null;
  int? gfWinner;
  int? gfLoser;
  if (wChampion != null && lChampion != null) {
    final raws = byPair[_pairKey(wChampion, lChampion)] ?? const [];
    int? gfEventId;
    int gfOrder = 0;
    if (raws.isNotEmpty) {
      final raw = raws.removeAt(0);
      gfWinner = raw.winnerPlayerId;
      gfEventId = raw.eventId;
      gfOrder = orderedRaw.indexOf(raw);
      if (gfWinner != null) {
        gfLoser = (gfWinner == wChampion) ? lChampion : wChampion;
      }
    }
    matches['GF'] = BracketMatch(
      id: 'GF',
      side: BracketSide.grandFinal,
      round: 1,
      slot: 1,
      playerAId: wChampion,
      playerBId: lChampion,
      winnerPlayerId: gfWinner,
      eventId: gfEventId,
      eventOrderIndex: gfOrder,
    );

    // Bracket reset: only if the LB champion won the first GF.
    if (gfWinner == lChampion) {
      final extraRaws = byPair[_pairKey(wChampion, lChampion)] ?? const [];
      int? rWinner;
      int? rEventId;
      int rOrder = 0;
      if (extraRaws.isNotEmpty) {
        final raw = extraRaws.removeAt(0);
        rWinner = raw.winnerPlayerId;
        rEventId = raw.eventId;
        rOrder = orderedRaw.indexOf(raw);
      }
      matches['GFR'] = BracketMatch(
        id: 'GFR',
        side: BracketSide.grandFinalReset,
        round: 1,
        slot: 1,
        playerAId: wChampion,
        playerBId: lChampion,
        winnerPlayerId: rWinner,
        eventId: rEventId,
        eventOrderIndex: rOrder,
      );
      if (rWinner != null) {
        gfWinner = rWinner;
        gfLoser = (rWinner == wChampion) ? lChampion : wChampion;
      } else {
        gfWinner = null;
        gfLoser = null;
      }
    }
  }

  // --- RANKING ---
  final ranking = _computeRanking(
    seeds: seeds,
    matches: matches,
    winnersRounds: winnersRounds,
    losersRounds: losersRounds,
    gfWinner: gfWinner,
    gfLoser: gfLoser,
    lChampion: lChampion,
    wChampion: wChampion,
  );

  return Bracket(
    seeds: seeds,
    matches: matches,
    winnersRounds: winnersRounds,
    losersRounds: losersRounds,
    ranking: ranking,
  );
}

int? _emitMatch({
  required Map<String, BracketMatch> matches,
  required Map<String, List<RawMatch>> byPair,
  required List<RawMatch> orderedRaw,
  required String slotId,
  required BracketSide side,
  required int round,
  required int slot,
  required int? a,
  required int? b,
}) {
  int? winner;
  int? eventId;
  int eventOrder = 0;
  if (a == null && b != null) {
    winner = b;
  } else if (b == null && a != null) {
    winner = a;
  } else if (a != null && b != null) {
    final raws = byPair[_pairKey(a, b)] ?? const [];
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
    playerAId: a,
    playerBId: b,
    winnerPlayerId: winner,
    eventId: eventId,
    eventOrderIndex: eventOrder,
  );
  return winner;
}

String _pairKey(int a, int b) {
  final lo = a < b ? a : b;
  final hi = a < b ? b : a;
  return '$lo-$hi';
}

/// Derive final places from bracket state. Players are placed by elimination
/// round (later elimination = better place), and the GF winner takes 1st.
List<int> _computeRanking({
  required List<int?> seeds,
  required Map<String, BracketMatch> matches,
  required int winnersRounds,
  required int losersRounds,
  required int? gfWinner,
  required int? gfLoser,
  required int? lChampion,
  required int? wChampion,
}) {
  // Build "eliminated in round R of side X" map by scanning all matches.
  final eliminationOrder = <int, int>{}; // playerId → ordering value (lower = eliminated earlier)

  void elim(int? pid, int orderKey) {
    if (pid == null) return;
    if (!eliminationOrder.containsKey(pid)) {
      eliminationOrder[pid] = orderKey;
    }
  }

  // Degenerate 2-player bracket: no losers bracket, no GF. The W1.1
  // loser is the runner-up directly.
  if (losersRounds == 0) {
    final w11 = matches['W1.1'];
    if (w11 != null && w11.isDecided) {
      elim(w11.loserPlayerId, 1000);
    }
  }

  // Losers in winners bracket are NOT eliminated — they drop to losers.
  // Players are eliminated when they lose in losers bracket, GF, or GFR.
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
  // Determine 2nd place (loser of the decisive final).
  if (gfr != null) {
    if (gfr.isDecided) elim(gfr.loserPlayerId, 1000);
    if (gf != null && gf.isDecided && gf.loserPlayerId != null && !eliminationOrder.containsKey(gf.loserPlayerId)) {
      // The GF loser, if not the GFR loser, was eliminated in GFR (since it's the same two players).
      elim(gf.loserPlayerId, 1000);
    }
  } else if (gf != null && gf.isDecided) {
    elim(gf.loserPlayerId, 1000);
  }

  // Sort all known eliminated players by their elimination order (descending).
  // Higher elim order = eliminated later = better place.
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
