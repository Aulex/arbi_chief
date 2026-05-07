import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../viewmodels/shared_providers.dart';
import 'athletics_service.dart';

final athleticsServiceProvider = Provider(
  (ref) => AthleticsService(ref.watch(dbServiceProvider)),
);
