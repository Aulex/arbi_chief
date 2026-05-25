import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../viewmodels/shared_providers.dart';
import '../../viewmodels/tournament_viewmodel.dart';
import 'arm_wrestling_scoring.dart';
import 'arm_wrestling_service.dart';

final armWrestlingServiceProvider = Provider(
  (ref) => ArmWrestlingService(ref.watch(dbServiceProvider)),
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

/// Loads players + games + weights for a tournament and computes every
/// standings table the UI needs. Both the "Усі гравці" tab and the team
/// standings tab subscribe to this.
final armWrestlingStandingsProvider =
    FutureProvider.family<ArmWrestlingStandingsBundle, int>((ref, tId) async {
  final armSvc = ref.watch(armWrestlingServiceProvider);
  final tournamentSvc = ref.watch(tournamentServiceProvider);

  // Best-effort migration from the legacy `team_number`-as-category storage.
  await armSvc.migrateLegacyTeamNumberStorage(tId);

  final playersByCategory = await armSvc.getPlayersByCategory(tId);
  final validation = await armSvc.validateCategories(tId);
  final playerWeights = await armSvc.getPlayerWeights(tId);
  final teamNames = await armSvc.getTeamNames(tId);
  final games = await tournamentSvc.getGamesGroupedByBoard(tId);

  // Build result matrix per category from games.
  final categoryResults = <int, Map<int, Map<int, double>>>{};
  for (final entry in games.entries) {
    final catId = entry.key;
    categoryResults.putIfAbsent(catId, () => {});
    for (final game in entry.value) {
      final wId = game.white.player_id!;
      final bId = game.black.player_id!;
      if (game.whiteResult != null) {
        categoryResults[catId]!.putIfAbsent(wId, () => {})[bId] = game.whiteResult!;
      }
      if (game.blackResult != null) {
        categoryResults[catId]!.putIfAbsent(bId, () => {})[wId] = game.blackResult!;
      }
    }
  }

  // Per-category individual standings.
  final catStandings = <int, List<ArmWrestlingStanding>>{};
  for (final entry in playersByCategory.entries) {
    final catId = entry.key;
    final players = entry.value
        .map((p) => ArmWrestlingPlayer(
              playerId: p.playerId,
              playerName: p.playerName,
              teamName: p.teamName,
              teamId: p.teamId,
              playerNumber: p.playerNumber,
              weight: p.weight ?? playerWeights[p.playerId],
            ))
        .toList();
    catStandings[catId] = calculateCategoryStandings(
      players: players,
      results: categoryResults[catId] ?? {},
    );
  }

  // Only valid categories count toward team standings.
  final validCatStandings = <int, List<ArmWrestlingStanding>>{};
  for (final entry in catStandings.entries) {
    final v = validation[entry.key];
    if (v != null && v.isValid) validCatStandings[entry.key] = entry.value;
  }

  final allTeamIds = <int>{};
  for (final standings in catStandings.values) {
    for (final s in standings) {
      allTeamIds.add(s.teamId);
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
