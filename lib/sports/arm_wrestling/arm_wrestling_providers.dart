import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../viewmodels/shared_providers.dart';
import 'arm_wrestling_bracket.dart';
import 'arm_wrestling_bracket_service.dart';
import 'arm_wrestling_scoring.dart';
import 'arm_wrestling_service.dart';

final armWrestlingServiceProvider = Provider(
  (ref) => ArmWrestlingService(ref.watch(dbServiceProvider)),
);

final armWrestlingBracketServiceProvider = Provider(
  (ref) => ArmWrestlingBracketService(ref.watch(dbServiceProvider)),
);

/// Weight category assignments: playerId → categoryId (1-5).
final armWrestlingCategoriesProvider = FutureProvider.family<Map<int, int>, int>(
  (ref, tId) => ref.watch(armWrestlingServiceProvider).getWeightCategoryAssignments(tId),
);

/// Category validation status.
final armWrestlingCategoryValidationProvider = FutureProvider.family<
    Map<int, ({bool isValid, int count, String label})>, int>(
  (ref, tId) => ref.watch(armWrestlingServiceProvider).validateCategories(tId),
);

/// Bundle of everything the standings UI needs in one query.
class ArmWrestlingStandingsBundle {
  /// Per-category individual standings, ordered by place.
  final Map<int, List<ArmWrestlingStanding>> categoryStandings;
  /// Team standings (lowest sum wins).
  final List<ArmWrestlingTeamStanding> teamStandings;
  /// Which categories have at least the minimum participant count.
  final Map<int, ({bool isValid, int count, String label})> validation;
  /// playerId → kg, for inline editing.
  final Map<int, double> playerWeights;

  const ArmWrestlingStandingsBundle({
    required this.categoryStandings,
    required this.teamStandings,
    required this.validation,
    required this.playerWeights,
  });
}

/// Loads bracket + match results for every category and turns them into the
/// per-category and team standings the UI needs. Places come from the
/// double-elimination bracket; the round-robin win count is kept around as
/// a tie-breaker for players whose bracket place is not yet decided.
final armWrestlingStandingsProvider =
    FutureProvider.family<ArmWrestlingStandingsBundle, int>((ref, tId) async {
  final armSvc = ref.watch(armWrestlingServiceProvider);
  final bracketSvc = ref.watch(armWrestlingBracketServiceProvider);

  // Best-effort migration from the legacy `team_number`-as-category storage.
  await armSvc.migrateLegacyTeamNumberStorage(tId);

  final validation = await armSvc.validateCategories(tId);
  final playerWeights = await armSvc.getPlayerWeights(tId);
  final teamNames = await armSvc.getTeamNames(tId);

  final catStandings = <int, List<ArmWrestlingStanding>>{};
  for (final cat in WeightCategory.values) {
    final loaded = await bracketSvc.loadCategory(tId, cat.id);
    if (loaded.players.isEmpty) continue;

    final bracket = buildBracket(
      seededPlayerIds: loaded.players.map((p) => p.playerId).toList(),
      rawMatches: loaded.raws,
    );

    // Per-player W/L from raw matches (display + tentative ranking among
    // still-alive players).
    final wins = <int, int>{};
    final losses = <int, int>{};
    final games = <int, int>{};
    for (final r in loaded.raws) {
      games[r.playerAId] = (games[r.playerAId] ?? 0) + 1;
      games[r.playerBId] = (games[r.playerBId] ?? 0) + 1;
      if (r.winnerPlayerId == r.playerAId) {
        wins[r.playerAId] = (wins[r.playerAId] ?? 0) + 1;
        losses[r.playerBId] = (losses[r.playerBId] ?? 0) + 1;
      } else if (r.winnerPlayerId == r.playerBId) {
        wins[r.playerBId] = (wins[r.playerBId] ?? 0) + 1;
        losses[r.playerAId] = (losses[r.playerAId] ?? 0) + 1;
      }
    }

    final placeByPid = <int, int>{};
    for (int i = 0; i < bracket.ranking.length; i++) {
      placeByPid[bracket.ranking[i]] = i + 1;
    }
    final placedCount = bracket.ranking.length;

    // Tentative placement for still-alive players: order by wins desc then
    // fewer losses, append after the ranked players.
    final stillAlive = loaded.players
        .where((p) => !placeByPid.containsKey(p.playerId))
        .toList()
      ..sort((a, b) {
        final wa = wins[a.playerId] ?? 0;
        final wb = wins[b.playerId] ?? 0;
        if (wa != wb) return wb.compareTo(wa);
        final la = losses[a.playerId] ?? 0;
        final lb = losses[b.playerId] ?? 0;
        if (la != lb) return la.compareTo(lb);
        return (a.number ?? 9999).compareTo(b.number ?? 9999);
      });
    for (int i = 0; i < stillAlive.length; i++) {
      placeByPid[stillAlive[i].playerId] = placedCount + i + 1;
    }

    final standings = loaded.players.map((p) {
      return ArmWrestlingStanding(
        playerId: p.playerId,
        playerName: p.fullName,
        teamName: p.teamName,
        teamId: -1, // resolved below from team lookup
        playerNumber: p.number,
        weight: p.weight ?? playerWeights[p.playerId],
        wins: wins[p.playerId] ?? 0,
        losses: losses[p.playerId] ?? 0,
        gamesPlayed: games[p.playerId] ?? 0,
        place: placeByPid[p.playerId] ?? 0,
      );
    }).toList()
      ..sort((a, b) {
        if (a.place == 0 && b.place == 0) return 0;
        if (a.place == 0) return 1;
        if (b.place == 0) return -1;
        return a.place.compareTo(b.place);
      });

    catStandings[cat.id] = standings;
  }

  // Resolve teamId per standing via getPlayersByCategory (it carries the
  // team mapping). We only need it for team standings.
  final playersByCategory = await armSvc.getPlayersByCategory(tId);
  final teamIdByPlayer = <int, int>{};
  for (final list in playersByCategory.values) {
    for (final p in list) {
      teamIdByPlayer[p.playerId] = p.teamId;
    }
  }
  // Rebuild standings with the proper teamId (the field is final, so we
  // can't backfill in place).
  catStandings.forEach((catId, list) {
    catStandings[catId] = list.map((s) {
      final tid = teamIdByPlayer[s.playerId] ?? 0;
      return ArmWrestlingStanding(
        playerId: s.playerId,
        playerName: s.playerName,
        teamName: s.teamName,
        teamId: tid,
        playerNumber: s.playerNumber,
        weight: s.weight,
        wins: s.wins,
        losses: s.losses,
        gamesPlayed: s.gamesPlayed,
        place: s.place,
      );
    }).toList();
  });

  // Only fully decided positions contribute to team standings.
  final validCatStandings = <int, List<ArmWrestlingStanding>>{};
  for (final entry in catStandings.entries) {
    final v = validation[entry.key];
    if (v != null && v.isValid) validCatStandings[entry.key] = entry.value;
  }

  final allTeamIds = <int>{};
  for (final standings in catStandings.values) {
    for (final s in standings) {
      if (s.teamId > 0) allTeamIds.add(s.teamId);
    }
  }

  final teamStandings = calculateTeamStandings(
    categoryStandings: validCatStandings,
    teamIds: allTeamIds,
    teamNames: teamNames,
    playerWeights: playerWeights,
  );

  return ArmWrestlingStandingsBundle(
    categoryStandings: catStandings,
    teamStandings: teamStandings,
    validation: validation,
    playerWeights: playerWeights,
  );
});
