import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/tournament_model.dart';

class TournamentNavState {
  final String view;
  final Tournament? tournament;
  const TournamentNavState({required this.view, this.tournament});
}

class TournamentNavNotifier extends Notifier<TournamentNavState> {
  @override
  TournamentNavState build() {
    return const TournamentNavState(view: 'list');
  }

  void showList() => state = const TournamentNavState(view: 'list');
  void showAdd() => state = const TournamentNavState(view: 'add');
  void showEdit(Tournament t) =>
      state = TournamentNavState(view: 'edit', tournament: t);
}

final tournamentNavProvider =
    NotifierProvider<TournamentNavNotifier, TournamentNavState>(
  () {
    return TournamentNavNotifier();
  },
);
