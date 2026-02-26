import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/team_model.dart';
import '../services/team_service.dart';
import 'shared_providers.dart';

final teamServiceProvider = Provider(
  (ref) => TeamService(ref.watch(dbServiceProvider)),
);

class TeamNotifier extends AsyncNotifier<List<Team>> {
  @override
  Future<List<Team>> build() async {
    return ref.watch(teamServiceProvider).getAllTeams();
  }

  Future<Team> addTeam({required String name}) async {
    final team = Team(
      team_id: null,
      team_name: name,
    );
    final saved = await ref.read(teamServiceProvider).saveTeam(team);
    ref.invalidateSelf();
    return saved;
  }

  Future<void> updateTeam(Team team) async {
    await ref.read(teamServiceProvider).saveTeam(team);
    ref.invalidateSelf();
  }

  Future<void> removeTeam(int id) async {
    await ref.read(teamServiceProvider).deleteTeam(id);
    ref.invalidateSelf();
  }
}

final teamProvider = AsyncNotifierProvider<TeamNotifier, List<Team>>(
  TeamNotifier.new,
);

/// Board assignments for all teams: teamId → { boardNumber → playerId }
final allTeamBoardsProvider =
    FutureProvider<Map<int, Map<int, int>>>((ref) async {
  final teams = await ref.watch(teamProvider.future);
  final service = ref.watch(teamServiceProvider);
  final result = <int, Map<int, int>>{};
  for (final t in teams) {
    if (t.team_id != null) {
      result[t.team_id!] = await service.getBoardMembers(t.team_id!);
    }
  }
  return result;
});
