import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/report_model.dart';
import '../services/report_service.dart';
import 'tournament_viewmodel.dart';
import 'team_viewmodel.dart';

final reportServiceProvider = Provider(
  (ref) => ReportService(
    ref.watch(teamServiceProvider),
    ref.watch(tournamentServiceProvider),
  ),
);

/// Provides report data for a given tournament ID.
/// Usage: ref.watch(reportDataProvider(tournamentId))
final reportDataProvider = FutureProvider.family<ReportData, int>(
  (ref, tournamentId) {
    final svc = ref.watch(reportServiceProvider);
    return svc.loadReportData(tournamentId);
  },
);
