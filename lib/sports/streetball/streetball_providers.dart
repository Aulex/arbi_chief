import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../viewmodels/shared_providers.dart';
import 'streetball_service.dart';

final streetballServiceProvider = Provider(
  (ref) => StreetballService(ref.watch(dbServiceProvider)),
);
