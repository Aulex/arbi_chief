import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/tournament_model.dart';
import '../models/player_model.dart';
import '../services/tournament_service.dart';
import 'shared_providers.dart';
import 'sport_type_provider.dart';

// --- Service Provider ---
final tournamentServiceProvider = Provider(
  (ref) => TournamentService(ref.watch(dbServiceProvider)),
);

// --- Tournament State Management ---
class TournamentNotifier extends AsyncNotifier<List<Tournament>> {
  @override
  Future<List<Tournament>> build() async {
    final tType = ref.watch(selectedSportTypeProvider);
    return ref.watch(tournamentServiceProvider).getAllTournaments(tType: tType);
  }

  Future<void> addTournament({
    int? existingId,
    required String name,
    required String dateBegin,
    required String dateEnd,
    int? typeId,
    int? locationId,
    int? organizerId,
    String? selectedTimeControl,
    String? selectedPairingSystem,
    String? rounds,
    String? selectedStartingListSort,
    String? selectedScoringFormat,
    bool? allowSubstitutes,
    Map<String, String>? scoringPoints,
    List<String>? selectedTieBreakers,
    String? finalsPlaces,
    String? crossGroupMatchPlaces,
    String? cyclePlaces,
  }) async {
    final svc = ref.read(tournamentServiceProvider);
    final effectiveTypeId = typeId ?? ref.read(selectedSportTypeProvider);

    final t = Tournament(
      t_id: existingId,
      t_name: name,
      t_date_begin: Tournament.formatForDB(dateBegin),
      t_date_end: Tournament.formatForDB(dateEnd),
      t_type: effectiveTypeId,
      t_location: locationId,
      t_org: organizerId,
    );

    final tId = await svc.saveTournament(t);

    // attr_id=1: "Тип контролю часу" — DICT
    if (selectedTimeControl != null) {
      final dictId = await svc.getDictId(1, selectedTimeControl);
      if (dictId != null) {
        await svc.saveAttrValue(tId: tId, attrId: 1, dictId: dictId);
      }
    }

    // attr_id=2: "Система жеребкування" — DICT
    if (selectedPairingSystem != null) {
      final dictId = await svc.getDictId(2, selectedPairingSystem);
      if (dictId != null) {
        await svc.saveAttrValue(tId: tId, attrId: 2, dictId: dictId);
      }
    }

    // attr_id=3: "Кількість кіл" — INTEGER
    if (rounds != null && rounds.isNotEmpty) {
      await svc.saveAttrValue(tId: tId, attrId: 3, attrValue: rounds);
    }

    // attr_id=4: "Сортування стартового списку" — DICT
    if (selectedStartingListSort != null) {
      final dictId = await svc.getDictId(4, selectedStartingListSort);
      if (dictId != null) {
        await svc.saveAttrValue(tId: tId, attrId: 4, dictId: dictId);
      }
    }

    // attr_id=5: "Формат заліку" — DICT
    if (selectedScoringFormat != null) {
      final dictId = await svc.getDictId(5, selectedScoringFormat);
      if (dictId != null) {
        await svc.saveAttrValue(tId: tId, attrId: 5, dictId: dictId);
      }
    }

    // attr_id=6: "Запасні гравці" — INTEGER (0/1)
    if (allowSubstitutes != null) {
      await svc.saveAttrValue(
        tId: tId, attrId: 6, attrValue: allowSubstitutes ? '1' : '0',
      );
    }

    // attr_id=7: "Система нарахування очок" — multi-row (dict_id + attr_value)
    if (scoringPoints != null) {
      final values = <({int? dictId, String? attrValue})>[];
      for (final entry in scoringPoints.entries) {
        final dictId = await svc.getDictId(7, entry.key);
        if (dictId != null) {
          values.add((dictId: dictId, attrValue: entry.value));
        }
      }
      await svc.saveAttrValues(tId: tId, attrId: 7, values: values);
    }

    // attr_id=8: "Тай-брейки" — multi-row (dict_id only)
    if (selectedTieBreakers != null) {
      final values = <({int? dictId, String? attrValue})>[];
      for (final tb in selectedTieBreakers) {
        final dictId = await svc.getDictId(8, tb);
        if (dictId != null) {
          values.add((dictId: dictId, attrValue: null));
        }
      }
      await svc.saveAttrValues(tId: tId, attrId: 8, values: values);
    }

    // attr_id=10: "Місця до фіналу з груп" — TEXT
    if (finalsPlaces != null && finalsPlaces.isNotEmpty) {
      await svc.saveAttrValue(tId: tId, attrId: 10, attrValue: finalsPlaces);
    }

    // attr_id=11: "Місця для матчів між групами" — TEXT
    if (crossGroupMatchPlaces != null && crossGroupMatchPlaces.isNotEmpty) {
      await svc.saveAttrValue(tId: tId, attrId: 11, attrValue: crossGroupMatchPlaces);
    }

    // attr_id=12: "Місця для колової системи" — TEXT
    if (cyclePlaces != null && cyclePlaces.isNotEmpty) {
      await svc.saveAttrValue(tId: tId, attrId: 12, attrValue: cyclePlaces);
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

// --- Tournament Participants (family provider keyed by t_id) ---
final participantsProvider =
    FutureProvider.family<List<Player>, int>((ref, tId) {
  return ref.watch(tournamentServiceProvider).getParticipants(tId);
});
