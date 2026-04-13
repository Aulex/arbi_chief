import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../viewmodels/shared_providers.dart';
import 'basketball_service.dart';

final basketballServiceProvider = Provider(
  (ref) => BasketballService(ref.watch(dbServiceProvider)),
);

final basketballGroupsProvider = FutureProvider.family<Map<int, String>, int>(
  (ref, tId) => ref.watch(basketballServiceProvider).getGroupAssignments(tId),
);

final basketballRemovedTeamsProvider = FutureProvider.family<Set<int>, int>(
  (ref, tId) => ref.watch(basketballServiceProvider).getRemovedTeamIds(tId),
);
