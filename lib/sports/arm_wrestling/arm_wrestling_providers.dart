import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../viewmodels/shared_providers.dart';
import 'arm_wrestling_service.dart';

final armWrestlingServiceProvider = Provider(
  (ref) => ArmWrestlingService(ref.watch(dbServiceProvider)),
);

/// Weight category assignments: playerId → categoryId (1-5).
final armWrestlingCategoriesProvider = FutureProvider.family<Map<int, int>, int>(
  (ref, tId) => ref.watch(armWrestlingServiceProvider).getWeightCategoryAssignments(tId),
);

/// Category validation status.
final armWrestlingCategoryValidationProvider = FutureProvider.family<
    Map<int, ({bool isValid, int count, String label})>, int>(
  (ref, tId) => ref.watch(armWrestlingServiceProvider).validateCategories(tId),
);
