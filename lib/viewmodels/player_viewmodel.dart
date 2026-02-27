import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/player_model.dart';
import '../services/player_service.dart';
import 'shared_providers.dart';

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
    // Automatically re-fetches when playerServiceProvider changes
    return ref.watch(playerServiceProvider).getAllPlayers();
  }

  // Updated to match CMP_PLAYER table and your Player model 🧬
  Future<void> addPlayer({
    required String name,
    required String surname,
    required String lastname,
    required int gender,
    required String dob, // Expecting "dd.mm.yyyy" from the UI
  }) async {
    final p = Player(
      player_id: null, // SQLite handles autoincrement
      player_name: name,
      player_surname: surname,
      player_lastname: lastname,
      player_gender: gender,
      // Uses the static helper in your model to store as "yyyy-mm-dd" 📅
      player_date_birth: Player.formatForDB(dob),
    );

    await ref.read(playerServiceProvider).savePlayer(p);

    // Refresh the local state 🔄
    ref.invalidateSelf();
  }

  Future<void> updatePlayer(Player player) async {
    await ref.read(playerServiceProvider).savePlayer(player);
    ref.invalidateSelf();
  }

  Future<void> removePlayer(int id) async {
    // Optimistic update: remove from local list immediately
    final current = state.value ?? [];
    state = AsyncData(current.where((p) => p.player_id != id).toList());
    await ref.read(playerServiceProvider).deletePlayer(id);
  }
}

// --- Global Player Provider ---
final playerProvider = AsyncNotifierProvider<PlayerNotifier, List<Player>>(
  PlayerNotifier.new,
);
