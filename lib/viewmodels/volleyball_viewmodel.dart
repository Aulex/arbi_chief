import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/volleyball_service.dart';
import 'shared_providers.dart';

final volleyballServiceProvider = Provider(
  (ref) => VolleyballService(ref.watch(dbServiceProvider)),
);
