import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../viewmodels/shared_providers.dart';
import 'cycling_service.dart';

final cyclingServiceProvider = Provider(
  (ref) => CyclingService(ref.watch(dbServiceProvider)),
);
