import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../viewmodels/shared_providers.dart';
import 'streetball_service.dart';

final streetballServiceProvider = Provider(
  (ref) => StreetballService(ref.watch(dbServiceProvider)),
);

final streetballGroupsProvider = FutureProvider.family<Map<int, String>, int>(
  (ref, tId) => ref.watch(streetballServiceProvider).getGroupAssignments(tId),
);

final streetballRemovedTeamsProvider = FutureProvider.family<Set<int>, int>(
  (ref, tId) => ref.watch(streetballServiceProvider).getRemovedTeamIds(tId),
);
