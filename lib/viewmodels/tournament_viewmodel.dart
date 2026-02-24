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

  Future<void> addTournament({
    required String name,
    required String dateBegin,
    required String dateEnd,
    int? typeId,
    int? locationId,
    int? organizerId,
    String? selectedTimeControl,
    String? selectedPairingSystem,
  }) async {
    final svc = ref.read(tournamentServiceProvider);

    final t = Tournament(
      t_id: null,
      t_name: name,
      t_date_begin: Tournament.formatForDB(dateBegin),
      t_date_end: Tournament.formatForDB(dateEnd),
      t_type: typeId,
      t_location: locationId,
      t_org: organizerId,
    );

    final tId = await svc.saveTournament(t);

    // Save "Тип контролю часу" (attr_id=1)
    if (selectedTimeControl != null) {
      final dictId = await svc.getDictId(1, selectedTimeControl);
      if (dictId != null) {
        await svc.saveAttrValue(tId: tId, attrId: 1, dictId: dictId);
      }
    }

    // Save "Система жеребкування" (attr_id=2)
    if (selectedPairingSystem != null) {
      final dictId = await svc.getDictId(2, selectedPairingSystem);
      if (dictId != null) {
        await svc.saveAttrValue(tId: tId, attrId: 2, dictId: dictId);
      }
    }

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
