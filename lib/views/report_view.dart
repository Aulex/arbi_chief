import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/report_model.dart';
import '../models/sport_type_config.dart';
import '../models/tournament_model.dart';
import '../viewmodels/report_viewmodel.dart';

/// Standalone report widget for a single tournament.
/// Shows export options and triggers PDF generation via ReportService.
class ReportView extends ConsumerStatefulWidget {
  final Tournament tournament;
  final SportTypeConfig config;
  final bool autoExport;

  const ReportView({
    super.key,
    required this.tournament,
    required this.config,
    this.autoExport = false,
  });

  @override
  ConsumerState<ReportView> createState() => _ReportViewState();
}

class _ReportViewState extends ConsumerState<ReportView> {
  @override
  Widget build(BuildContext context) {
    final dataAsync = ref.watch(reportDataProvider(widget.tournament.t_id!));

    return dataAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => Center(child: Text('Помилка: $e')),
      data: (data) {
        if (widget.autoExport && data.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _exportPdf(data);
          });
        }
        return _buildContent(data);
      },
    );
  }

  Widget _buildContent(ReportData data) {
    final hasData = data.isNotEmpty;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade300, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.summarize_outlined, color: Colors.indigo.shade400),
                const SizedBox(width: 12),
                const Text(
                  'Звіти турніру',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Експорт поточного стану турніру у PDF-документ.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const Divider(height: 32),
            if (!hasData)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.info_outline, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'Немає даних для звіту',
                        style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Додайте учасників та розподіліть їх по ${widget.config.boardLabelPlural}.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              _reportCard(
                icon: Icons.picture_as_pdf,
                title: 'Повний звіт',
                description: 'Крос-таблиці всіх дошок та командний залік.',
                onTap: () => _exportPdf(data),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _exportPdf(ReportData data) async {
    final svc = ref.read(reportServiceProvider);
    await svc.exportPdf(widget.tournament, widget.config, data);
  }

  Widget _reportCard({
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.indigo.shade100, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: Colors.red.shade400, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(description, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ],
                ),
              ),
              Icon(Icons.download_outlined, color: Colors.indigo.shade300),
            ],
          ),
        ),
      ),
    );
  }
}
