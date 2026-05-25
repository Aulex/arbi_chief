import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../models/tournament_model.dart';
import '../../services/team_service.dart';
import '../../services/tournament_service.dart';
import '../sport_type_config.dart';
import 'futsal_scoring.dart';
import 'futsal_service.dart';

/// Futsal-specific PDF report builder.
///
/// Loads team-vs-team game data and generates pages for every tournament phase:
/// per-group cross-tables, finals (top 2 from each group), consolation
/// (3rd+ from each group), and a total standings summary.
class FutsalReportBuilder {
  final FutsalService _futsalService;
  final TeamService _teamService;
  // ignore: unused_field
  final TournamentService _tournamentService;

  FutsalReportBuilder(this._futsalService, this._teamService, this._tournamentService);

  Future<bool> hasData(int tId) async {
    final teams = await _teamService.getTeamListForTournament(tId);
    return teams.isNotEmpty;
  }

  Future<pw.Document> buildPdf(Tournament tournament, SportTypeConfig config) async {
    final pdf = pw.Document();
    if (tournament.t_id == null) return pdf;
    final tId = tournament.t_id!;
    final tournamentName = tournament.t_name;

    // --- Load data ---
    final teamList = await _teamService.getTeamListForTournament(tId);
    final rawGames = await _futsalService.getTeamGamesForTournament(tId);
    final groupAssignments = await _futsalService.getGroupAssignments(tId);
    final removedTeamIds = await _futsalService.getRemovedTeamIds(tId);

    final allTeams = await _teamService.getAllTeams();
    final teams = <_TeamInfo>[];
    for (final t in teamList) {
      final team = allTeams.where((at) => at.team_id == t.teamId).firstOrNull;
      var entityId = team?.entity_id;
      entityId ??= await _futsalService.ensureTeamEntity(t.teamId);
      teams.add(_TeamInfo(
        teamId: t.teamId,
        teamName: t.teamName,
        teamNumber: t.teamNumber,
        entityId: entityId,
      ));
    }

    // --- Fonts ---
    pw.Font fontRegular;
    pw.Font fontBold;
    try {
      final regData = await rootBundle.load('assets/fonts/times.ttf');
      final boldData = await rootBundle.load('assets/fonts/timesbd.ttf');
      fontRegular = pw.Font.ttf(regData);
      fontBold = pw.Font.ttf(boldData);
    } catch (_) {
      fontRegular = await PdfGoogleFonts.notoSansRegular();
      fontBold = await PdfGoogleFonts.notoSansBold();
    }
    final theme = pw.ThemeData.withFont(base: fontRegular, bold: fontBold);

    if (teams.isEmpty) {
      pdf.addPage(pw.Page(
        theme: theme,
        build: (_) => pw.Center(child: pw.Text('Немає даних про команди')),
      ));
      return pdf;
    }

    final gamesMapBidi = <(int, int), String>{};
    final noShowPairs = <(int, int)>{};
    for (final g in rawGames) {
      if (g.eventResult != null) {
        gamesMapBidi[(g.teamAEntityId, g.teamBEntityId)] = g.eventResult!;
        final p = g.eventResult!.split(':');
        if (p.length == 2) {
          gamesMapBidi[(g.teamBEntityId, g.teamAEntityId)] = '${p[1]}:${p[0]}';
        }
      }
      if (g.esId == 4) {
        noShowPairs.add((g.teamAEntityId, g.teamBEntityId));
      }
    }

    final ctx = _BuildContext(
      pdf: pdf,
      tournamentName: tournamentName,
      teams: teams,
      gamesMapBidi: gamesMapBidi,
      removedTeamIds: removedTeamIds,
      noShowPairs: noShowPairs,
      groupAssignments: groupAssignments,
      theme: theme,
      fontRegular: fontRegular,
      fontBold: fontBold,
    );

    // Use group mode only when there are ≥ 9 teams AND group assignments exist
    // (same threshold as the UI).
    final hasGroups = groupAssignments.isNotEmpty && teams.length >= 9;
    final groupNames = hasGroups
        ? (groupAssignments.values.toSet().toList()..sort())
        : <String>[];

    if (hasGroups) {
      // 1. Per-group cross-tables
      for (final groupName in groupNames) {
        final groupTeams = _getGroupTeams(ctx, groupName);
        if (groupTeams.isEmpty) continue;
        _addCrossTablePage(
          ctx: ctx,
          subtitle: 'Група $groupName',
          teams: groupTeams,
        );
      }

      // 2. Finals (top 2 from each group, with carry-over)
      final finalists = _getTopFromEachGroup(ctx, groupNames, 2);
      if (finalists.isNotEmpty) {
        _addCrossTablePage(
          ctx: ctx,
          subtitle: 'Фінал — місця 1–${finalists.length}',
          teams: finalists,
        );
      }

      // 3. Consolation (3rd+ from each group)
      final consolation = _getRestFromEachGroup(ctx, groupNames, 3);
      if (consolation.isNotEmpty) {
        final startPlace = groupNames.length * 2 + 1;
        _addCrossTablePage(
          ctx: ctx,
          subtitle: 'Місця $startPlace+',
          teams: consolation,
        );
      }

      // 4. Total standings summary
      _addTotalStandingsPage(
        ctx: ctx,
        groupNames: groupNames,
      );
    } else {
      _addCrossTablePage(
        ctx: ctx,
        subtitle: 'Турнірна таблиця',
        teams: teams,
      );
    }

    if (ctx.pagesAdded == 0) {
      _addCrossTablePage(
        ctx: ctx,
        subtitle: 'Турнірна таблиця',
        teams: teams,
      );
    }
    if (ctx.pagesAdded == 0) {
      pdf.addPage(pw.Page(
        theme: theme,
        build: (_) => pw.Center(child: pw.Text('Немає даних для звіту')),
      ));
    }

    return pdf;
  }

  // ---------------------------------------------------------------------------
  // Phase helpers
  // ---------------------------------------------------------------------------

  List<_TeamInfo> _getGroupTeams(_BuildContext ctx, String groupName) {
    return ctx.teams.where((t) => ctx.groupAssignments[t.teamId] == groupName).toList();
  }

  /// Top [count] teams from each group, ordered by group-phase standings.
  List<_TeamInfo> _getTopFromEachGroup(
    _BuildContext ctx,
    List<String> groupNames,
    int count,
  ) {
    final result = <_TeamInfo>[];
    for (final groupName in groupNames) {
      final groupTeams = _getGroupTeams(ctx, groupName);
      final standings = _calculateStandings(ctx, groupTeams);
      for (int i = 0; i < count && i < standings.length; i++) {
        final s = standings[i];
        if (s.isRemoved) continue;
        final team = groupTeams.where((t) => t.teamId == s.teamId).firstOrNull;
        if (team != null) result.add(team);
      }
    }
    return result;
  }

  /// Teams from rank [startRank] (1-based) onward in each group.
  List<_TeamInfo> _getRestFromEachGroup(
    _BuildContext ctx,
    List<String> groupNames,
    int startRank,
  ) {
    final result = <_TeamInfo>[];
    for (final groupName in groupNames) {
      final groupTeams = _getGroupTeams(ctx, groupName);
      final standings = _calculateStandings(ctx, groupTeams);
      for (int i = startRank - 1; i < standings.length; i++) {
        final s = standings[i];
        if (s.isRemoved) continue;
        final team = groupTeams.where((t) => t.teamId == s.teamId).firstOrNull;
        if (team != null) result.add(team);
      }
    }
    return result;
  }

  List<FutsalStanding> _calculateStandings(_BuildContext ctx, List<_TeamInfo> teams) {
    final teamEntityIds = teams.map((t) => t.entityId).whereType<int>().toSet();
    final filteredGames = <(int, int), String>{};
    final seenPairs = <(int, int)>{};

    for (final entry in ctx.gamesMapBidi.entries) {
      final (aEntId, bEntId) = entry.key;
      if (teamEntityIds.contains(aEntId) && teamEntityIds.contains(bEntId)) {
        if (seenPairs.contains((bEntId, aEntId))) continue;
        seenPairs.add((aEntId, bEntId));
        filteredGames[(aEntId, bEntId)] = entry.value;
      }
    }

    return calculateStandings(
      teams: teams.map((t) => (teamId: t.teamId, teamName: t.teamName, entityId: t.entityId)).toList(),
      games: filteredGames,
      removedTeamIds: ctx.removedTeamIds,
      noShowGamePairs: ctx.noShowPairs,
    );
  }

  // ---------------------------------------------------------------------------
  // Cross-table page
  // ---------------------------------------------------------------------------

  void _addCrossTablePage({
    required _BuildContext ctx,
    required String subtitle,
    required List<_TeamInfo> teams,
  }) {
    final n = teams.length;
    if (n == 0) return;

    final standings = _calculateStandings(ctx, teams);
    final rankMap = <int, int>{};
    for (final s in standings) {
      rankMap[s.teamId] = s.rank;
    }

    final sorted = List.of(teams)
      ..sort((a, b) {
        final aRemoved = ctx.removedTeamIds.contains(a.teamId);
        final bRemoved = ctx.removedTeamIds.contains(b.teamId);
        if (aRemoved != bRemoved) return aRemoved ? 1 : -1;
        final aRank = rankMap[a.teamId] ?? 9999;
        final bRank = rankMap[b.teamId] ?? 9999;
        if (aRank != bRank) return aRank.compareTo(bRank);
        final aNum = a.teamNumber ?? 9999;
        final bNum = b.teamNumber ?? 9999;
        if (aNum != bNum) return aNum.compareTo(bNum);
        return a.teamName.compareTo(b.teamName);
      });

    final useA3 = n > 8;
    final pageFormat = useA3 ? PdfPageFormat.a3.landscape : PdfPageFormat.a4.landscape;
    const fontSize = 7.0;
    final cellWidth = n <= 6 ? 52.0 : n <= 10 ? 44.0 : 36.0;

    final hdrStyle = pw.TextStyle(fontSize: fontSize, fontWeight: pw.FontWeight.bold);
    final cellSt = pw.TextStyle(fontSize: fontSize, font: ctx.fontRegular);
    final cellBold = pw.TextStyle(fontSize: fontSize, font: ctx.fontBold, fontWeight: pw.FontWeight.bold);
    final removedStyle = pw.TextStyle(
      fontSize: fontSize,
      font: ctx.fontRegular,
      fontStyle: pw.FontStyle.italic,
      color: PdfColors.red,
    );

    final headerCells = <pw.Widget>[
      _cell('№', hdrStyle),
      _cell('Команда', hdrStyle, align: pw.Alignment.centerLeft),
      for (int i = 0; i < n; i++)
        _cell('${sorted[i].teamNumber ?? (i + 1)}', hdrStyle),
      _cell('О', hdrStyle),
      _cell('В', hdrStyle),
      _cell('Н', hdrStyle),
      _cell('П', hdrStyle),
      _cell('М+', hdrStyle),
      _cell('М-', hdrStyle),
      _cell('РМ', hdrStyle),
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
      final isRemoved = ctx.removedTeamIds.contains(team.teamId);
      final nameStyle = isRemoved ? removedStyle : cellSt;
      final rowBg = i.isOdd ? const pw.BoxDecoration(color: PdfColors.grey100) : null;

      final cells = <pw.Widget>[
        _cell('${team.teamNumber ?? (i + 1)}', cellSt),
        _cell(team.teamName, nameStyle, align: pw.Alignment.centerLeft),
        for (int j = 0; j < n; j++)
          if (i == j)
            _diagonalCell()
          else
            _matchResultCell(team, sorted[j], ctx.gamesMapBidi, cellSt, cellBold),
        _cell('${standing?.matchPoints ?? 0}', cellBold),
        _cell('${standing?.wins ?? 0}', cellSt),
        _cell('${standing?.draws ?? 0}', cellSt),
        _cell('${standing?.losses ?? 0}', cellSt),
        _cell('${standing?.goalsScored ?? 0}', cellSt),
        _cell('${standing?.goalsConceded ?? 0}', cellSt),
        _cell(_signed((standing?.goalsScored ?? 0) - (standing?.goalsConceded ?? 0)), cellSt),
        _cell(isRemoved ? '—' : '${rankMap[team.teamId] ?? ''}', cellBold),
      ];

      rows.add(pw.TableRow(decoration: rowBg, children: cells));
    }

    final nameColWidth = useA3 ? 100.0 : 80.0;
    final colWidths = <int, pw.TableColumnWidth>{
      0: const pw.FixedColumnWidth(24),
      1: pw.FixedColumnWidth(nameColWidth),
      for (int i = 0; i < n; i++)
        2 + i: pw.FixedColumnWidth(cellWidth),
      2 + n: const pw.FixedColumnWidth(26),     // О
      2 + n + 1: const pw.FixedColumnWidth(22), // В
      2 + n + 2: const pw.FixedColumnWidth(22), // Н
      2 + n + 3: const pw.FixedColumnWidth(22), // П
      2 + n + 4: const pw.FixedColumnWidth(26), // М+
      2 + n + 5: const pw.FixedColumnWidth(26), // М-
      2 + n + 6: const pw.FixedColumnWidth(28), // РМ
      2 + n + 7: const pw.FixedColumnWidth(32), // Місце
    };

    ctx.pagesAdded++;
    ctx.pdf.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(20),
        theme: ctx.theme,
        header: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(ctx.tournamentName, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(subtitle, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
          ],
        ),
        build: (pw.Context context) => [
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400),
            columnWidths: colWidths,
            defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
            children: rows,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Total standings page (підсумок) — combines all phases
  // ---------------------------------------------------------------------------

  void _addTotalStandingsPage({
    required _BuildContext ctx,
    required List<String> groupNames,
  }) {
    final rankedTeams = <_RankedTeam>[];
    final assignedTeamIds = <int>{};
    int nextPlace = 1;

    void addFromStandings(List<FutsalStanding> standings, String phase) {
      for (final s in standings) {
        if (assignedTeamIds.contains(s.teamId)) continue;
        if (s.isRemoved) continue;
        rankedTeams.add(_RankedTeam(
          teamId: s.teamId,
          teamName: s.teamName,
          overallPlace: nextPlace++,
          phase: phase,
        ));
        assignedTeamIds.add(s.teamId);
      }
    }

    // 1. Finals (places 1 – 2·groupCount)
    final finalists = _getTopFromEachGroup(ctx, groupNames, 2);
    if (finalists.isNotEmpty) {
      addFromStandings(_calculateStandings(ctx, finalists), 'Фінал');
    }

    // 2. Consolation (3rd+ in each group)
    final consolation = _getRestFromEachGroup(ctx, groupNames, 3);
    if (consolation.isNotEmpty) {
      addFromStandings(_calculateStandings(ctx, consolation), 'Місця 9+');
    }

    // 3. Any leftover teams — ranked by group standings
    for (final groupName in groupNames) {
      final groupTeams = _getGroupTeams(ctx, groupName);
      addFromStandings(_calculateStandings(ctx, groupTeams), 'Група $groupName');
    }

    // 4. Removed teams listed at the end without a place
    final removedList = ctx.teams.where((t) => ctx.removedTeamIds.contains(t.teamId)).toList();
    if (rankedTeams.isEmpty && removedList.isEmpty) return;

    const fontSize = 9.0;
    final hdrStyle = pw.TextStyle(fontSize: fontSize, fontWeight: pw.FontWeight.bold);
    final cellSt = pw.TextStyle(fontSize: fontSize, font: ctx.fontRegular);
    final cellBold = pw.TextStyle(fontSize: fontSize, font: ctx.fontBold, fontWeight: pw.FontWeight.bold);
    final removedStyle = pw.TextStyle(
      fontSize: fontSize,
      font: ctx.fontRegular,
      fontStyle: pw.FontStyle.italic,
      color: PdfColors.red,
    );

    final headerCells = <pw.Widget>[
      _cell('Місце', hdrStyle),
      _cell('Команда', hdrStyle, align: pw.Alignment.centerLeft),
      _cell('Етап', hdrStyle),
    ];

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: headerCells,
      ),
    ];

    for (int i = 0; i < rankedTeams.length; i++) {
      final t = rankedTeams[i];
      final rowBg = i.isOdd ? const pw.BoxDecoration(color: PdfColors.grey100) : null;
      rows.add(pw.TableRow(
        decoration: rowBg,
        children: [
          _cell('${t.overallPlace}', cellBold),
          _cell(t.teamName, cellSt, align: pw.Alignment.centerLeft),
          _cell(t.phase, cellSt),
        ],
      ));
    }

    for (final t in removedList) {
      rows.add(pw.TableRow(
        children: [
          _cell('—', cellSt),
          _cell(t.teamName, removedStyle, align: pw.Alignment.centerLeft),
          _cell('Знято', removedStyle),
        ],
      ));
    }

    final colWidths = <int, pw.TableColumnWidth>{
      0: const pw.FixedColumnWidth(50),
      1: const pw.FlexColumnWidth(),
      2: const pw.FixedColumnWidth(100),
    };

    ctx.pagesAdded++;
    ctx.pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        theme: ctx.theme,
        header: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(ctx.tournamentName, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('Загальний підсумок', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
          ],
        ),
        build: (pw.Context context) => [
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400),
            columnWidths: colWidths,
            defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
            children: rows,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Cell helpers
  // ---------------------------------------------------------------------------

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

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      alignment: pw.Alignment.center,
      child: pw.Text(detail, style: cellBold, textAlign: pw.TextAlign.center),
    );
  }

  String _signed(int v) => v > 0 ? '+$v' : '$v';

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

class _BuildContext {
  final pw.Document pdf;
  final String tournamentName;
  final List<_TeamInfo> teams;
  final Map<(int, int), String> gamesMapBidi;
  final Set<int> removedTeamIds;
  final Set<(int, int)> noShowPairs;
  final Map<int, String> groupAssignments;
  final pw.ThemeData theme;
  final pw.Font fontRegular;
  final pw.Font fontBold;
  int pagesAdded = 0;

  _BuildContext({
    required this.pdf,
    required this.tournamentName,
    required this.teams,
    required this.gamesMapBidi,
    required this.removedTeamIds,
    required this.noShowPairs,
    required this.groupAssignments,
    required this.theme,
    required this.fontRegular,
    required this.fontBold,
  });
}

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

class _RankedTeam {
  final int teamId;
  final String teamName;
  final int overallPlace;
  final String phase;

  const _RankedTeam({
    required this.teamId,
    required this.teamName,
    required this.overallPlace,
    required this.phase,
  });
}
