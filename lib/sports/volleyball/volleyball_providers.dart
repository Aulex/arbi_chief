import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../viewmodels/shared_providers.dart';
import 'volleyball_service.dart';

final volleyballServiceProvider = Provider(
  (ref) => VolleyballService(ref.watch(dbServiceProvider)),
);

final volleyballGroupsProvider = FutureProvider.family<Map<int, String>, int>(
  (ref, tId) => ref.watch(volleyballServiceProvider).getGroupAssignments(tId),
);

final volleyballRemovedTeamsProvider = FutureProvider.family<Set<int>, int>(
  (ref, tId) => ref.watch(volleyballServiceProvider).getRemovedTeamIds(tId),
);
