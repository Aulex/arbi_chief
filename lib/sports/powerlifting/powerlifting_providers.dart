import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../viewmodels/shared_providers.dart';
import 'powerlifting_service.dart';

final powerliftingServiceProvider = Provider(
  (ref) => PowerliftingService(ref.watch(dbServiceProvider)),
);
