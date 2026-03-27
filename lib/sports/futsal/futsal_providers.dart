import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../viewmodels/shared_providers.dart';
import 'futsal_service.dart';

final futsalServiceProvider = Provider(
  (ref) => FutsalService(ref.watch(dbServiceProvider)),
);
