import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/report_model.dart';
import '../services/report_service.dart';
import '../sports/volleyball/volleyball_providers.dart';
import '../sports/streetball/streetball_providers.dart';
import 'tournament_viewmodel.dart';
import 'team_viewmodel.dart';

final reportServiceProvider = Provider(
  (ref) => ReportService(
    ref.watch(teamServiceProvider),
    ref.watch(tournamentServiceProvider),
    ref.watch(volleyballServiceProvider),
    ref.watch(streetballServiceProvider),
  ),
);

/// Provides report data for a given tournament ID and sport type.
/// Usage: ref.watch(reportDataProvider((tId: tournamentId, sportType: type)))
final reportDataProvider = FutureProvider.family<ReportData, ({int tId, int? sportType})>(
  (ref, params) {
    final svc = ref.watch(reportServiceProvider);
    return svc.loadReportData(params.tId, sportType: params.sportType);
  },
);
