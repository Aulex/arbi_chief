import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the selected sport type (CMP_TOURNAMENT_TYPE.type_id).
/// Null means no sport has been selected yet.
final selectedSportTypeProvider = StateProvider<int?>((ref) => null);
