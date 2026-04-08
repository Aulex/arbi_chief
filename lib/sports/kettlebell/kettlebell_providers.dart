import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../viewmodels/shared_providers.dart';
import 'kettlebell_service.dart';

final kettlebellServiceProvider = Provider(
  (ref) => KettlebellService(ref.watch(dbServiceProvider)),
);
