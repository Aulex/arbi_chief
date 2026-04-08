import 'package:flutter_riverpod/flutter_riverpod.dart';

class SelectedSportTypeNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void select(int typeId) => state = typeId;
}

final selectedSportTypeProvider =
    NotifierProvider<SelectedSportTypeNotifier, int?>(
  () => SelectedSportTypeNotifier(),
);
