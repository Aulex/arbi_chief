import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/database_service.dart';

// Move this here so both Player and Tournament viewmodels can use it
final dbServiceProvider = Provider((ref) => DatabaseService());

/// A simple counter used to trigger refreshes of results/standings across
/// different tabs (e.g. from 'All players' to category-specific views).
final resultsRefreshProvider = NotifierProvider<ResultsRefreshNotifier, int>(
  () => ResultsRefreshNotifier(),
);

class ResultsRefreshNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void increment() => state++;
}
