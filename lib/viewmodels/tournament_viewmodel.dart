import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/tournament_model.dart';
import '../services/tournament_service.dart';
import 'shared_providers.dart';

// --- Service Provider ---
final tournamentServiceProvider = Provider(
  (ref) => TournamentService(ref.watch(dbServiceProvider)),
);

// --- Tournament State Management ---
class TournamentNotifier extends AsyncNotifier<List<Tournament>> {
  @override
  Future<List<Tournament>> build() async {
    // Watching the service ensures we refresh if the database connection changes
    return ref.watch(tournamentServiceProvider).getAllTournaments();
  }

  // Updated to match the CMP_TOURNAMENT table structure 🏆
  Future<void> addTournament({
    required String name,
    required String dateBegin, // Expected as dd.mm.yyyy from UI
    required String dateEnd, // Expected as dd.mm.yyyy from UI
    int? typeId,
    int? locationId,
    int? organizerId,
  }) async {
    final t = Tournament(
      t_id: null, // SQLite handles autoincrement
      t_name: name,
      // Using our model's helper to store as yyyy-mm-dd 📅
      t_date_begin: Tournament.formatForDB(dateBegin),
      t_date_end: Tournament.formatForDB(dateEnd),
      t_type: typeId,
      t_location: locationId,
      t_org: organizerId,
    );

    await ref.read(tournamentServiceProvider).saveTournament(t);

    // Refresh the local list
    ref.invalidateSelf();
  }

  Future<void> updateTournament(Tournament tournament) async {
    await ref.read(tournamentServiceProvider).saveTournament(tournament);
    ref.invalidateSelf();
  }

  Future<void> removeTournament(int id) async {
    await ref.read(tournamentServiceProvider).deleteTournament(id);
    ref.invalidateSelf();
  }
}

// --- Global Tournament Provider ---
final tournamentProvider =
    AsyncNotifierProvider<TournamentNotifier, List<Tournament>>(
      TournamentNotifier.new,
    );
