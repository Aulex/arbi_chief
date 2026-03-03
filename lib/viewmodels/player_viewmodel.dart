import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/player_model.dart';
import '../services/player_service.dart';
import 'shared_providers.dart';
import 'sport_type_provider.dart';

// --- Search Logic ---
final playerSearchProvider = NotifierProvider<PlayerSearchNotifier, String>(
  () => PlayerSearchNotifier(),
);

class PlayerSearchNotifier extends Notifier<String> {
  @override
  String build() => "";
  void updateSearch(String query) => state = query;
  void clear() => state = "";
}

// --- Service Provider ---
final playerServiceProvider = Provider(
  (ref) => PlayerService(ref.watch(dbServiceProvider)),
);

// --- Player State Management ---
class PlayerNotifier extends AsyncNotifier<List<Player>> {
  @override
  Future<List<Player>> build() async {
    final tType = ref.watch(selectedSportTypeProvider);
    return ref.watch(playerServiceProvider).getAllPlayers(tType: tType);
  }

  Future<void> addPlayer({
    required String name,
    required String surname,
    required String lastname,
    required int gender,
    required String dob,
  }) async {
    final tType = ref.read(selectedSportTypeProvider);
    final p = Player(
      player_id: null,
      player_name: name,
      player_surname: surname,
      player_lastname: lastname,
      player_gender: gender,
      player_date_birth: Player.formatForDB(dob),
      t_type: tType,
    );

    await ref.read(playerServiceProvider).savePlayer(p);
    ref.invalidateSelf();
  }

  Future<void> updatePlayer(Player player) async {
    await ref.read(playerServiceProvider).savePlayer(player);
    ref.invalidateSelf();
  }

  Future<void> removePlayer(int id) async {
    final current = state.value ?? [];
    state = AsyncData(current.where((p) => p.player_id != id).toList());
    await ref.read(playerServiceProvider).deletePlayer(id);
  }
}

// --- Global Player Provider ---
final playerProvider = AsyncNotifierProvider<PlayerNotifier, List<Player>>(
  PlayerNotifier.new,
);
