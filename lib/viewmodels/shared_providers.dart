import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/database_service.dart';

// Move this here so both Player and Tournament viewmodels can use it
final dbServiceProvider = Provider((ref) => DatabaseService());
