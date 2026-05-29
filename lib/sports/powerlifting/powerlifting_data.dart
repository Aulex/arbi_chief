import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/player_model.dart';
import '../../viewmodels/player_viewmodel.dart';
import '../../viewmodels/team_viewmodel.dart';
import 'powerlifting_providers.dart';
import 'powerlifting_scoring.dart';

/// Loads every athlete registered in a powerlifting tournament together with
/// their category, body weight, lot, gender and best lifts, ready for scoring.
Future<List<PowerliftingAthlete>> loadPowerliftingAthletesW(
    WidgetRef ref, int tId) async {
  final playerSvc = ref.read(playerServiceProvider);
  final teamSvc = ref.read(teamServiceProvider);
  final plSvc = ref.read(powerliftingServiceProvider);

  final playerTeamsMap = await teamSvc.getPlayerTeamsMap(tId);
  final List<Player> allPlayers = await playerSvc.getAllPlayers();
  final categories = await plSvc.getPlayerCategories(tId);
  final weights = await plSvc.getPlayerWeights(tId);
  final lots = await plSvc.getPlayerLots(tId);
  final bestLifts = await plSvc.getBestLifts(tId);

  final playersById = <int, Player>{
    for (final p in allPlayers)
      if (p.player_id != null) p.player_id!: p,
  };

  final athletes = <PowerliftingAthlete>[];
  for (final entry in playerTeamsMap.entries) {
    final pId = entry.key;
    final team = entry.value;
    final pInfo = playersById[pId];
    if (pInfo == null) continue;
    final name =
        '${pInfo.player_surname} ${pInfo.player_name} ${pInfo.player_lastname}'
            .trim();
    final lifts = bestLifts[pId];
    athletes.add(PowerliftingAthlete(
      playerId: pId,
      teamId: team.team_id!,
      teamName: team.team_name,
      playerName: name,
      category: categories[pId] ?? '',
      bodyWeight: weights[pId] ?? 0.0,
      gender: pInfo.player_gender,
      lot: lots[pId] ?? 0,
      bestSquat: lifts?.squat ?? 0.0,
      bestBench: lifts?.bench ?? 0.0,
      bestDeadlift: lifts?.deadlift ?? 0.0,
    ));
  }
  return athletes;
}
