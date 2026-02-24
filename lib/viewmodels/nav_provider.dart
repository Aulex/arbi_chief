import 'package:flutter_riverpod/flutter_riverpod.dart';

// Notifier to handle switching between 'list' and 'add'
class TournamentNavNotifier extends Notifier<String> {
  @override
  String build() {
    return 'list'; // Default view
  }

  void showList() => state = 'list';
  void showAdd() => state = 'add';
}

final tournamentNavProvider = NotifierProvider<TournamentNavNotifier, String>(
  () {
    return TournamentNavNotifier();
  },
);
