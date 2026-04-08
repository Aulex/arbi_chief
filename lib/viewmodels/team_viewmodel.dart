import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/team_model.dart';
import '../services/team_service.dart';
import 'shared_providers.dart';
import 'sport_type_provider.dart';

final teamServiceProvider = Provider(
  (ref) => TeamService(ref.watch(dbServiceProvider)),
);

class TeamNotifier extends AsyncNotifier<List<Team>> {
  @override
  Future<List<Team>> build() async {
    final tType = ref.watch(selectedSportTypeProvider);
    return ref.watch(teamServiceProvider).getAllTeams(tType: tType);
  }

  Future<Team> addTeam({required String name}) async {
    final tType = ref.read(selectedSportTypeProvider);
    final team = Team(
      team_id: null,
      team_name: name,
      t_type: tType,
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
