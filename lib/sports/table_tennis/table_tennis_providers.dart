import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../viewmodels/shared_providers.dart';
import 'table_tennis_service.dart';

final tableTennisServiceProvider = Provider(
  (ref) => TableTennisService(ref.watch(dbServiceProvider)),
);
