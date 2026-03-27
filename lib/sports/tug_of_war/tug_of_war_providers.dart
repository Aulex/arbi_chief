import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../viewmodels/shared_providers.dart';
import 'tug_of_war_service.dart';

final tugOfWarServiceProvider = Provider(
  (ref) => TugOfWarService(ref.watch(dbServiceProvider)),
);
