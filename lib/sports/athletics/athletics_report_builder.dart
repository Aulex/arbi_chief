import 'dart:io';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../models/tournament_model.dart';
import 'athletics_model.dart';
import 'athletics_service.dart';

/// Athletics-specific PDF report builder.
///
/// Generates per-category individual standings (place, athlete, team, age,
/// raw time, coefficient, adjusted time), a team standings page, and an
/// optional age-coefficient table page used in the tournament.
class AthleticsReportBuilder {
  final AthleticsService _service;

  AthleticsReportBuilder(this._service);

  Future<bool> hasData(int tId) async {
    for (final cat in AthleticsCategory.values) {
      final results = await _service.getResults(tId, category: cat);
      if (results.isNotEmpty) return true;
    }
    return false;
  }

  Future<pw.Document> buildPdf(Tournament tournament) async {
    final tId = tournament.t_id!;
    final pdf = pw.Document();
    final tournamentName = tournament.t_name;

    final coeffs = await _service.getCustomCoefficients(tId);

    final categoryStandings = <AthleticsCategory, List<RankedAthleticsResult>>{};
    for (final cat in AthleticsCategory.values) {
      categoryStandings[cat] = await _service.getCategoryStandings(
        tId, cat, customCoefficients: coeffs,
      );
    }
    final overallMen = await _service.getOverallStandings(
      tId, isMale: true, customCoefficients: coeffs,
    );
    final overallWomen = await _service.getOverallStandings(
      tId, isMale: false, customCoefficients: coeffs,
    );
    final teamResult = await _service.getTeamStandings(
      tId, customCoefficients: coeffs,
    );
    final teamStandings = teamResult.standings;

    final theme = await _loadTheme();

    // --- Per-category individual standings ---
    for (final cat in AthleticsCategory.values) {
      final standings = categoryStandings[cat] ?? const [];
      if (standings.isEmpty) continue;
      pdf.addPage(_buildCategoryPage(
        tournamentName: tournamentName,
        category: cat,
        standings: standings,
        theme: theme,
      ));
    }

    // --- Overall (no age categories) standings: men 3000м, then women 1500м ---
    if (overallMen.isNotEmpty) {
      pdf.addPage(_buildOverallStandingsPage(
        tournamentName: tournamentName,
        title: 'Загальний залік — Чоловіки (3000 м)',
        standings: overallMen,
        theme: theme,
      ));
    }
    if (overallWomen.isNotEmpty) {
      pdf.addPage(_buildOverallStandingsPage(
        tournamentName: tournamentName,
        title: 'Загальний залік — Жінки (1500 м)',
        standings: overallWomen,
        theme: theme,
      ));
    }

    // --- Team standings ---
    if (teamStandings.isNotEmpty) {
      pdf.addPage(_buildTeamStandingsPage(
        tournamentName: tournamentName,
        standings: teamStandings,
        penaltyPlace: teamResult.penaltyPlace,
        largestCategory: teamResult.largestCategory,
        theme: theme,
      ));
    }

    // --- Age coefficients table ---
    if (coeffs != null && coeffs.isNotEmpty) {
      pdf.addPage(_buildCoefficientsPage(
        tournamentName: tournamentName,
        coeffs: coeffs,
        theme: theme,
      ));
    }

    return pdf;
  }

  // ---------------------------------------------------------------------------

  Future<pw.ThemeData> _loadTheme() async {
    pw.Font fontRegular;
    pw.Font fontBold;
    final reg = File('C:\\Windows\\Fonts\\times.ttf');
    final bold = File('C:\\Windows\\Fonts\\timesbd.ttf');
    if (Platform.isWindows && await reg.exists() && await bold.exists()) {
      try {
        final regBytes = await reg.readAsBytes();
        final boldBytes = await bold.readAsBytes();
        fontRegular = pw.Font.ttf(ByteData.sublistView(regBytes));
        fontBold = pw.Font.ttf(ByteData.sublistView(boldBytes));
        return pw.ThemeData.withFont(base: fontRegular, bold: fontBold);
      } catch (_) {
        // Fall through to Google fallback.
      }
    }
    fontRegular = await PdfGoogleFonts.notoSansRegular();
    fontBold = await PdfGoogleFonts.notoSansBold();
    return pw.ThemeData.withFont(base: fontRegular, bold: fontBold);
  }

  pw.Page _buildCategoryPage({
    required String tournamentName,
    required AthleticsCategory category,
    required List<RankedAthleticsResult> standings,
    required pw.ThemeData theme,
  }) {
    final hdrStyle = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);
    final cellSt = const pw.TextStyle(fontSize: 9);
    final cellBold = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          _cell('№', hdrStyle),
          _cell('Спортсмен', hdrStyle, align: pw.Alignment.centerLeft),
          _cell('Команда', hdrStyle, align: pw.Alignment.centerLeft),
          _cell('Вік', hdrStyle),
          _cell('Час', hdrStyle),
          _cell('Коеф.', hdrStyle),
          _cell('Заліковий час', hdrStyle),
          _cell('Місце', hdrStyle),
        ],
      ),
    ];

    for (int i = 0; i < standings.length; i++) {
      final s = standings[i];
      final adj = _formatAdjusted(s.adjustedDsec);
      final bg = i.isOdd
          ? const pw.BoxDecoration(color: PdfColors.grey100)
          : null;
      rows.add(pw.TableRow(
        decoration: bg,
        children: [
          _cell(s.playerNumber != null ? '${s.playerNumber}' : '—', cellBold),
          _cell(s.playerName ?? '', cellSt, align: pw.Alignment.centerLeft),
          _cell(s.teamName ?? '', cellSt, align: pw.Alignment.centerLeft),
          _cell(s.age > 0 ? '${s.age}' : '—', cellSt),
          _cell(s.result.timeFormatted, cellSt),
          _cell(s.coefficient.toStringAsFixed(4), cellSt),
          _cell(adj, cellBold),
          _cell('${s.place}', cellBold),
        ],
      ));
    }

    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      theme: theme,
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(tournamentName,
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(
            '${category.fullName} (${category.distanceLabel})',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400),
            columnWidths: const {
              0: pw.FixedColumnWidth(36),
              1: pw.FlexColumnWidth(3),
              2: pw.FlexColumnWidth(3),
              3: pw.FixedColumnWidth(32),
              4: pw.FixedColumnWidth(56),
              5: pw.FixedColumnWidth(48),
              6: pw.FixedColumnWidth(72),
              7: pw.FixedColumnWidth(40),
            },
            defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
            children: rows,
          ),
        ],
      ),
    );
  }

  pw.Page _buildOverallStandingsPage({
    required String tournamentName,
    required String title,
    required List<RankedAthleticsResult> standings,
    required pw.ThemeData theme,
  }) {
    final hdrStyle = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);
    final cellSt = const pw.TextStyle(fontSize: 9);
    final cellBold = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          _cell('№', hdrStyle),
          _cell('Спортсмен', hdrStyle, align: pw.Alignment.centerLeft),
          _cell('Команда', hdrStyle, align: pw.Alignment.centerLeft),
          _cell('Вік', hdrStyle),
          _cell('Час', hdrStyle),
          _cell('Коеф.', hdrStyle),
          _cell('Заліковий час', hdrStyle),
          _cell('Місце', hdrStyle),
        ],
      ),
    ];

    for (int i = 0; i < standings.length; i++) {
      final s = standings[i];
      final adj = _formatAdjusted(s.adjustedDsec);
      final bg = i.isOdd
          ? const pw.BoxDecoration(color: PdfColors.grey100)
          : null;
      rows.add(pw.TableRow(
        decoration: bg,
        children: [
          _cell(s.playerNumber != null ? '${s.playerNumber}' : '—', cellBold),
          _cell(s.playerName ?? '', cellSt, align: pw.Alignment.centerLeft),
          _cell(s.teamName ?? '', cellSt, align: pw.Alignment.centerLeft),
          _cell(s.age > 0 ? '${s.age}' : '—', cellSt),
          _cell(s.result.timeFormatted, cellSt),
          _cell(s.coefficient.toStringAsFixed(4), cellSt),
          _cell(adj, cellBold),
          _cell('${s.place}', cellBold),
        ],
      ));
    }

    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      theme: theme,
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(tournamentName,
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(title,
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400),
            columnWidths: const {
              0: pw.FixedColumnWidth(36),
              1: pw.FlexColumnWidth(3),
              2: pw.FlexColumnWidth(3),
              3: pw.FixedColumnWidth(32),
              4: pw.FixedColumnWidth(56),
              5: pw.FixedColumnWidth(48),
              6: pw.FixedColumnWidth(72),
              7: pw.FixedColumnWidth(40),
            },
            defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
            children: rows,
          ),
        ],
      ),
    );
  }

  pw.Page _buildTeamStandingsPage({
    required String tournamentName,
    required List<AthleticsTeamStanding> standings,
    required int penaltyPlace,
    required AthleticsCategory? largestCategory,
    required pw.ThemeData theme,
  }) {
    final hdrStyle = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);
    final cellSt = const pw.TextStyle(fontSize: 9);
    final cellBold = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);

    final sorted = List.of(standings)..sort((a, b) => a.place.compareTo(b.place));

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          _cell('Команда', hdrStyle, align: pw.Alignment.centerLeft),
          _cell('Залікові місця', hdrStyle),
          _cell('Сума місць', hdrStyle),
          _cell('Місце', hdrStyle),
        ],
      ),
    ];

    for (int i = 0; i < sorted.length; i++) {
      final s = sorted[i];
      final scoring = s.scoringPlaces.isEmpty
          ? '—'
          : s.scoringPlaces.join(' + ');
      final bg = i.isOdd
          ? const pw.BoxDecoration(color: PdfColors.grey100)
          : null;
      rows.add(pw.TableRow(
        decoration: bg,
        children: [
          _cell(s.teamName, cellSt, align: pw.Alignment.centerLeft),
          _cell(scoring, cellSt),
          _cell('${s.totalPoints}', cellBold),
          _cell('${s.place}', cellBold),
        ],
      ));
    }

    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      theme: theme,
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(tournamentName,
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text('Командний залік',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400),
            columnWidths: const {
              0: pw.FlexColumnWidth(4),
              1: pw.FixedColumnWidth(80),
              2: pw.FixedColumnWidth(60),
              3: pw.FixedColumnWidth(40),
            },
            defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
            children: rows,
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            largestCategory != null && penaltyPlace > 1
                ? 'Сума місць — менше краще. Залікові місця: 2 чоловіки + '
                    '1 жінка з різних вікових категорій. Штраф за відсутність '
                    'у категорії = $penaltyPlace (${largestCategory.label}: '
                    '${penaltyPlace - 1} учасників + 1).'
                : 'Сума місць — менше краще. Залікові місця: 2 чоловіки + '
                    '1 жінка з різних вікових категорій.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
    );
  }

  pw.Page _buildCoefficientsPage({
    required String tournamentName,
    required Map<int, ({double men3000, double women1500})> coeffs,
    required pw.ThemeData theme,
  }) {
    final hdrStyle = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);
    final cellSt = const pw.TextStyle(fontSize: 9);

    final ages = coeffs.keys.toList()..sort();
    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          _cell('Вік', hdrStyle),
          _cell('Чол. 3000м', hdrStyle),
          _cell('Жін. 1500м', hdrStyle),
        ],
      ),
    ];
    for (int i = 0; i < ages.length; i++) {
      final age = ages[i];
      final v = coeffs[age]!;
      final bg = i.isOdd
          ? const pw.BoxDecoration(color: PdfColors.grey100)
          : null;
      rows.add(pw.TableRow(
        decoration: bg,
        children: [
          _cell('$age', cellSt),
          _cell(v.men3000.toStringAsFixed(4), cellSt),
          _cell(v.women1500.toStringAsFixed(4), cellSt),
        ],
      ));
    }

    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      theme: theme,
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(tournamentName,
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text('Вікові коефіцієнти',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400),
            columnWidths: const {
              0: pw.FixedColumnWidth(60),
              1: pw.FlexColumnWidth(1),
              2: pw.FlexColumnWidth(1),
            },
            defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
            children: rows,
          ),
        ],
      ),
    );
  }

  pw.Widget _cell(String text, pw.TextStyle style,
      {pw.Alignment align = pw.Alignment.center}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      alignment: align,
      child: pw.Text(
        text,
        style: style,
        textAlign: align == pw.Alignment.centerLeft
            ? pw.TextAlign.left
            : pw.TextAlign.center,
      ),
    );
  }

  String _formatAdjusted(double dsec) {
    final total = dsec.round();
    final min = total ~/ 6000;
    final sec = (total % 6000) ~/ 100;
    final ds = total % 100;
    return '$min:${sec.toString().padLeft(2, '0')}.${ds.toString().padLeft(2, '0')}';
  }
}
