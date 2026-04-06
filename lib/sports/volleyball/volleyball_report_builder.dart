import 'dart:io';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../models/tournament_model.dart';
import '../../services/team_service.dart';
import '../sport_type_config.dart';
import 'volleyball_scoring.dart';
import 'volleyball_service.dart';

/// Volleyball-specific PDF report builder.
///
/// Loads team-vs-team game data and generates:
/// - Team cross-table with set results
/// - Standings table with match points, sets, and points
class VolleyballReportBuilder {
  final VolleyballService _volleyballService;
  final TeamService _teamService;

  VolleyballReportBuilder(this._volleyballService, this._teamService);

  /// Check whether the tournament has any volleyball data to report on.
  Future<bool> hasData(int tId) async {
    final games = await _volleyballService.getTeamGamesForTournament(tId);
    return games.isNotEmpty;
  }

  /// Build the full volleyball PDF report.
  Future<pw.Document> buildPdf(Tournament tournament, SportTypeConfig config) async {
    final tId = tournament.t_id!;
    final pdf = pw.Document();
    final tournamentName = tournament.t_name;

    // --- Load data ---
    final teamList = await _teamService.getTeamListForTournament(tId);
    final rawGames = await _volleyballService.getTeamGamesForTournament(tId);
    final groups = await _volleyballService.getGroupAssignments(tId);
    final removedTeamIds = await _volleyballService.getRemovedTeamIds(tId);

    // Build team info with entity IDs
    final allTeams = await _teamService.getAllTeams();
    final teams = <_TeamInfo>[];
    for (final t in teamList) {
      final team = allTeams.where((at) => at.team_id == t.teamId).firstOrNull;
      var entityId = team?.entity_id;
      if (entityId == null) {
        entityId = await _volleyballService.ensureTeamEntity(t.teamId);
      }
      teams.add(_TeamInfo(
        teamId: t.teamId,
        teamName: t.teamName,
        teamNumber: t.teamNumber,
        entityId: entityId,
      ));
    }

    if (teams.isEmpty) return pdf;

    // Build games map: (entityA, entityB) → detail string (from A's perspective)
    final gamesMap = <(int, int), String>{};
    final noShowPairs = <(int, int)>{};
    for (final g in rawGames) {
      if (g.teamADetail != null) {
        gamesMap[(g.teamAEntityId, g.teamBEntityId)] = g.teamADetail!;
      }
      if (g.esId == 4) {
        noShowPairs.add((g.teamAEntityId, g.teamBEntityId));
      }
    }

    // --- Fonts ---
    pw.Font fontRegular;
    pw.Font fontBold;
    try {
      final regBytes = await File('C:\\Windows\\Fonts\\times.ttf').readAsBytes();
      final boldBytes = await File('C:\\Windows\\Fonts\\timesbd.ttf').readAsBytes();
      fontRegular = pw.Font.ttf(ByteData.sublistView(regBytes));
      fontBold = pw.Font.ttf(ByteData.sublistView(boldBytes));
    } catch (_) {
      fontRegular = await PdfGoogleFonts.notoSansRegular();
      fontBold = await PdfGoogleFonts.notoSansBold();
    }
    final theme = pw.ThemeData.withFont(base: fontRegular, bold: fontBold);

    // --- Determine layout: groups or single round-robin ---
    final hasGroups = groups.isNotEmpty;
    final groupNames = hasGroups
        ? (groups.values.toSet().toList()..sort())
        : <String>[];

    if (hasGroups) {
      // Per-group cross-tables and standings
      for (final groupName in groupNames) {
        final groupTeamIds = groups.entries
            .where((e) => e.value == groupName)
            .map((e) => e.key)
            .toSet();
        final groupTeams = teams.where((t) => groupTeamIds.contains(t.teamId)).toList();
        if (groupTeams.isEmpty) continue;

        _addCrossTablePage(
          pdf: pdf,
          title: tournamentName,
          subtitle: 'Група $groupName',
          teams: groupTeams,
          gamesMap: gamesMap,
          removedTeamIds: removedTeamIds,
          noShowPairs: noShowPairs,
          theme: theme,
          fontRegular: fontRegular,
          fontBold: fontBold,
        );
      }

      // Overall standings across all groups
      _addStandingsPage(
        pdf: pdf,
        title: tournamentName,
        subtitle: 'Загальна турнірна таблиця',
        teams: teams,
        gamesMap: gamesMap,
        removedTeamIds: removedTeamIds,
        noShowPairs: noShowPairs,
        groups: groups,
        theme: theme,
        fontRegular: fontRegular,
        fontBold: fontBold,
      );
    } else {
      // Single round-robin cross-table
      _addCrossTablePage(
        pdf: pdf,
        title: tournamentName,
        subtitle: 'Крос-таблиця',
        teams: teams,
        gamesMap: gamesMap,
        removedTeamIds: removedTeamIds,
        noShowPairs: noShowPairs,
        theme: theme,
        fontRegular: fontRegular,
        fontBold: fontBold,
      );
    }

    return pdf;
  }

  // ---------------------------------------------------------------------------
  // Cross-table page
  // ---------------------------------------------------------------------------

  void _addCrossTablePage({
    required pw.Document pdf,
    required String title,
    required String subtitle,
    required List<_TeamInfo> teams,
    required Map<(int, int), String> gamesMap,
    required Set<int> removedTeamIds,
    required Set<(int, int)> noShowPairs,
    required pw.ThemeData theme,
    required pw.Font fontRegular,
    required pw.Font fontBold,
  }) {
    final n = teams.length;
    if (n == 0) return;

    // Sort teams by number
    final sorted = List.of(teams)
      ..sort((a, b) {
        final aNum = a.teamNumber ?? 9999;
        final bNum = b.teamNumber ?? 9999;
        if (aNum != bNum) return aNum.compareTo(bNum);
        return a.teamName.compareTo(b.teamName);
      });

    // Calculate standings for the right-side ranking
    final standings = calculateStandings(
      teams: sorted.map((t) => (teamId: t.teamId, teamName: t.teamName, entityId: t.entityId)).toList(),
      games: gamesMap,
      removedTeamIds: removedTeamIds,
      noShowGamePairs: noShowPairs,
    );
    // Build rank lookup: teamId → rank
    final rankMap = <int, int>{};
    for (final s in standings) {
      rankMap[s.teamId] = s.rank;
    }

    final useA3 = n > 8;
    final pageFormat = useA3 ? PdfPageFormat.a3.landscape : PdfPageFormat.a4.landscape;
    final fontSize = 7.0;
    final cellWidth = n <= 6 ? 52.0 : n <= 10 ? 44.0 : 36.0;

    final hdrStyle = pw.TextStyle(fontSize: fontSize, fontWeight: pw.FontWeight.bold);
    final cellSt = pw.TextStyle(fontSize: fontSize, font: fontRegular);
    final cellBold = pw.TextStyle(fontSize: fontSize, font: fontBold, fontWeight: pw.FontWeight.bold);
    final removedStyle = pw.TextStyle(
      fontSize: fontSize,
      font: fontRegular,
      fontStyle: pw.FontStyle.italic,
      color: PdfColors.red,
    );

    // Header row
    final headerCells = <pw.Widget>[
      _cell('№', hdrStyle),
      _cell('Команда', hdrStyle, align: pw.Alignment.centerLeft),
      for (int i = 0; i < n; i++)
        _cell('${sorted[i].teamNumber ?? (i + 1)}', hdrStyle),
      _cell('Очки', hdrStyle),
      _cell('П', hdrStyle),
      _cell('Пр', hdrStyle),
      _cell('С+', hdrStyle),
      _cell('С-', hdrStyle),
      _cell('М+', hdrStyle),
      _cell('М-', hdrStyle),
      _cell('Місце', hdrStyle),
    ];

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: headerCells,
      ),
    ];

    for (int i = 0; i < n; i++) {
      final team = sorted[i];
      final standing = standings.where((s) => s.teamId == team.teamId).firstOrNull;
      final isRemoved = removedTeamIds.contains(team.teamId);
      final nameStyle = isRemoved ? removedStyle : cellSt;
      final rowBg = i.isOdd ? const pw.BoxDecoration(color: PdfColors.grey100) : null;

      final cells = <pw.Widget>[
        _cell('${team.teamNumber ?? (i + 1)}', cellSt),
        _cell(team.teamName, nameStyle, align: pw.Alignment.centerLeft),
        for (int j = 0; j < n; j++)
          if (i == j)
            _diagonalCell()
          else
            _matchResultCell(team, sorted[j], gamesMap, cellSt, cellBold),
        _cell('${standing?.matchPoints ?? 0}', cellBold),
        _cell('${standing?.wins ?? 0}', cellSt),
        _cell('${standing?.losses ?? 0}', cellSt),
        _cell('${standing?.setsWon ?? 0}', cellSt),
        _cell('${standing?.setsLost ?? 0}', cellSt),
        _cell('${standing?.pointsScored ?? 0}', cellSt),
        _cell('${standing?.pointsConceded ?? 0}', cellSt),
        _cell('${rankMap[team.teamId] ?? ''}', cellBold),
      ];

      rows.add(pw.TableRow(decoration: rowBg, children: cells));
    }

    // Column widths
    final nameColWidth = useA3 ? 100.0 : 80.0;
    final colWidths = <int, pw.TableColumnWidth>{
      0: const pw.FixedColumnWidth(24),
      1: pw.FixedColumnWidth(nameColWidth),
      for (int i = 0; i < n; i++)
        2 + i: pw.FixedColumnWidth(cellWidth),
      2 + n: const pw.FixedColumnWidth(30), // Очки
      2 + n + 1: const pw.FixedColumnWidth(22), // П
      2 + n + 2: const pw.FixedColumnWidth(22), // Пр
      2 + n + 3: const pw.FixedColumnWidth(24), // С+
      2 + n + 4: const pw.FixedColumnWidth(24), // С-
      2 + n + 5: const pw.FixedColumnWidth(26), // М+
      2 + n + 6: const pw.FixedColumnWidth(26), // М-
      2 + n + 7: const pw.FixedColumnWidth(32), // Місце
    };

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(20),
        theme: theme,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(subtitle, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400),
              columnWidths: colWidths,
              defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
              children: rows,
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Standings page (for grouped tournaments — overall summary)
  // ---------------------------------------------------------------------------

  void _addStandingsPage({
    required pw.Document pdf,
    required String title,
    required String subtitle,
    required List<_TeamInfo> teams,
    required Map<(int, int), String> gamesMap,
    required Set<int> removedTeamIds,
    required Set<(int, int)> noShowPairs,
    required Map<int, String> groups,
    required pw.ThemeData theme,
    required pw.Font fontRegular,
    required pw.Font fontBold,
  }) {
    // Calculate standings per group
    final groupNames = groups.values.toSet().toList()..sort();
    final allStandings = <VolleyballStanding>[];

    for (final groupName in groupNames) {
      final groupTeamIds = groups.entries
          .where((e) => e.value == groupName)
          .map((e) => e.key)
          .toSet();
      final groupTeams = teams.where((t) => groupTeamIds.contains(t.teamId)).toList();

      final standings = calculateStandings(
        teams: groupTeams.map((t) => (teamId: t.teamId, teamName: t.teamName, entityId: t.entityId)).toList(),
        games: gamesMap,
        removedTeamIds: removedTeamIds,
        noShowGamePairs: noShowPairs,
      );
      allStandings.addAll(standings);
    }

    // Add teams without group assignment
    final ungroupedTeams = teams.where((t) => !groups.containsKey(t.teamId)).toList();
    if (ungroupedTeams.isNotEmpty) {
      final standings = calculateStandings(
        teams: ungroupedTeams.map((t) => (teamId: t.teamId, teamName: t.teamName, entityId: t.entityId)).toList(),
        games: gamesMap,
        removedTeamIds: removedTeamIds,
        noShowGamePairs: noShowPairs,
      );
      allStandings.addAll(standings);
    }

    if (allStandings.isEmpty) return;

    final fontSize = 8.0;
    final hdrStyle = pw.TextStyle(fontSize: fontSize, fontWeight: pw.FontWeight.bold);
    final cellSt = pw.TextStyle(fontSize: fontSize, font: fontRegular);
    final cellBold = pw.TextStyle(fontSize: fontSize, font: fontBold, fontWeight: pw.FontWeight.bold);
    final removedStyle = pw.TextStyle(
      fontSize: fontSize,
      font: fontRegular,
      fontStyle: pw.FontStyle.italic,
      color: PdfColors.red,
    );

    final headerCells = <pw.Widget>[
      _cell('Місце', hdrStyle),
      _cell('Команда', hdrStyle, align: pw.Alignment.centerLeft),
      _cell('Група', hdrStyle),
      _cell('Очки', hdrStyle),
      _cell('П', hdrStyle),
      _cell('Пр', hdrStyle),
      _cell('С+', hdrStyle),
      _cell('С-', hdrStyle),
      _cell('С+/-', hdrStyle),
      _cell('М+', hdrStyle),
      _cell('М-', hdrStyle),
      _cell('М+/-', hdrStyle),
    ];

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: headerCells,
      ),
    ];

    for (int i = 0; i < allStandings.length; i++) {
      final s = allStandings[i];
      final group = groups[s.teamId] ?? '';
      final isRemoved = s.isRemoved;
      final nameStyle = isRemoved ? removedStyle : cellSt;
      final rowBg = i.isOdd ? const pw.BoxDecoration(color: PdfColors.grey100) : null;

      final setDiff = s.setsWon - s.setsLost;
      final ptDiff = s.pointsScored - s.pointsConceded;

      rows.add(pw.TableRow(
        decoration: rowBg,
        children: [
          _cell('${s.rank}', cellBold),
          _cell(s.teamName, nameStyle, align: pw.Alignment.centerLeft),
          _cell(group, cellSt),
          _cell('${s.matchPoints}', cellBold),
          _cell('${s.wins}', cellSt),
          _cell('${s.losses}', cellSt),
          _cell('${s.setsWon}', cellSt),
          _cell('${s.setsLost}', cellSt),
          _cell('${setDiff >= 0 ? '+' : ''}$setDiff', cellSt),
          _cell('${s.pointsScored}', cellSt),
          _cell('${s.pointsConceded}', cellSt),
          _cell('${ptDiff >= 0 ? '+' : ''}$ptDiff', cellSt),
        ],
      ));
    }

    final colWidths = <int, pw.TableColumnWidth>{
      0: const pw.FixedColumnWidth(36),
      1: const pw.FixedColumnWidth(140),
      2: const pw.FixedColumnWidth(40),
      3: const pw.FixedColumnWidth(34),
      4: const pw.FixedColumnWidth(28),
      5: const pw.FixedColumnWidth(28),
      6: const pw.FixedColumnWidth(28),
      7: const pw.FixedColumnWidth(28),
      8: const pw.FixedColumnWidth(34),
      9: const pw.FixedColumnWidth(30),
      10: const pw.FixedColumnWidth(30),
      11: const pw.FixedColumnWidth(34),
    };

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        theme: theme,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(subtitle, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400),
              columnWidths: colWidths,
              defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
              children: rows,
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Cell helpers
  // ---------------------------------------------------------------------------

  /// Render a match result cell showing set score and details.
  pw.Widget _matchResultCell(
    _TeamInfo teamA,
    _TeamInfo teamB,
    Map<(int, int), String> gamesMap,
    pw.TextStyle cellSt,
    pw.TextStyle cellBold,
  ) {
    if (teamA.entityId == null || teamB.entityId == null) {
      return _cell('', cellSt);
    }
    final detail = gamesMap[(teamA.entityId!, teamB.entityId!)];
    if (detail == null) return _cell('', cellSt);

    final setResult = formatVolleyballCell(detail);
    final sets = detail.split(' ');
    final detailStr = sets.join(', ');

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      alignment: pw.Alignment.center,
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(setResult, style: cellBold, textAlign: pw.TextAlign.center),
          pw.Text('($detailStr)', style: cellSt.copyWith(fontSize: 5.5), textAlign: pw.TextAlign.center),
        ],
      ),
    );
  }

  pw.Widget _cell(String text, pw.TextStyle style, {pw.Alignment align = pw.Alignment.center}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      alignment: align,
      child: pw.Text(
        text,
        style: style,
        textAlign: align == pw.Alignment.centerLeft ? pw.TextAlign.left : pw.TextAlign.center,
      ),
    );
  }

  pw.Widget _diagonalCell() {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      color: PdfColors.grey600,
      alignment: pw.Alignment.center,
      child: pw.Text(''),
    );
  }
}

/// Internal team info holder.
class _TeamInfo {
  final int teamId;
  final String teamName;
  final int? teamNumber;
  final int? entityId;

  const _TeamInfo({
    required this.teamId,
    required this.teamName,
    this.teamNumber,
    this.entityId,
  });
}
