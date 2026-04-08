import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../viewmodels/shared_providers.dart';
import 'basketball_service.dart';

final basketballServiceProvider = Provider(
  (ref) => BasketballService(ref.watch(dbServiceProvider)),
);
