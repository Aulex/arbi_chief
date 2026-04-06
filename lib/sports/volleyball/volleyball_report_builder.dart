import 'dart:io';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../models/tournament_model.dart';
import '../../services/team_service.dart';
import '../../services/tournament_service.dart';
import '../sport_type_config.dart';
import 'volleyball_scoring.dart';
import 'volleyball_service.dart';

/// Volleyball-specific PDF report builder.
///
/// Loads team-vs-team game data and generates pages for every tournament phase:
/// groups, finals, cross-group matches, cycle matches, and a total standings
/// summary — mirroring the UI's segmented view.
class VolleyballReportBuilder {
  final VolleyballService _volleyballService;
  final TeamService _teamService;
  final TournamentService _tournamentService;

  VolleyballReportBuilder(this._volleyballService, this._teamService, this._tournamentService);

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
    final groupAssignments = await _volleyballService.getGroupAssignments(tId);
    final removedTeamIds = await _volleyballService.getRemovedTeamIds(tId);

    // Load tournament phase settings
    final finalsPlacesStr = await _tournamentService.getAttrValue(tId, 12);
    final crossGroupStr = await _tournamentService.getAttrValue(tId, 13);
    final cycleStr = await _tournamentService.getAttrValue(tId, 14);

    final finalsPlaces = _parsePlaces(finalsPlacesStr, defaultPlaces: [1, 2]);
    final crossGroupMatchPlaces = _parsePlaces(crossGroupStr);
    final cyclePlaces = _parsePlaces(cycleStr);

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

    // Build games maps: one-direction (for standings) and two-direction (for cell lookups)
    final gamesMap = <(int, int), String>{}; // one direction only
    final gamesMapBidi = <(int, int), String>{}; // both directions
    final noShowPairs = <(int, int)>{};
    for (final g in rawGames) {
      if (g.teamADetail != null) {
        gamesMap[(g.teamAEntityId, g.teamBEntityId)] = g.teamADetail!;
        gamesMapBidi[(g.teamAEntityId, g.teamBEntityId)] = g.teamADetail!;
      }
      if (g.teamBDetail != null) {
        gamesMapBidi[(g.teamBEntityId, g.teamAEntityId)] = g.teamBDetail!;
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

    // --- Build context for phase helpers ---
    final ctx = _BuildContext(
      pdf: pdf,
      tournamentName: tournamentName,
      teams: teams,
      gamesMap: gamesMap,
      gamesMapBidi: gamesMapBidi,
      removedTeamIds: removedTeamIds,
      noShowPairs: noShowPairs,
      groupAssignments: groupAssignments,
      theme: theme,
      fontRegular: fontRegular,
      fontBold: fontBold,
    );

    // --- Determine layout: groups or single round-robin ---
    final hasGroups = groupAssignments.isNotEmpty;
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

      // 2. Finals cross-table
      if (finalsPlaces.isNotEmpty) {
        final finalists = _getTeamsAtPlaces(ctx, groupNames, finalsPlaces);
        if (finalists.isNotEmpty) {
          _addCrossTablePage(
            ctx: ctx,
            subtitle: 'Фінальні матчі',
            teams: finalists,
          );
        }
      }

      // 3. Cross-group direct matches
      if (crossGroupMatchPlaces.isNotEmpty) {
        final numGroups = groupNames.length;
        final finalsTeamCount = finalsPlaces.length * numGroups;
        for (int i = 0; i < crossGroupMatchPlaces.length; i++) {
          final place = crossGroupMatchPlaces[i];
          final teamsAtPlace = _getTeamsAtSinglePlace(ctx, groupNames, place);
          if (teamsAtPlace.length < 2) continue;

          final overallStart = finalsTeamCount + 1 + i * numGroups;
          final overallEnd = overallStart + numGroups - 1;
          final placeLabel = overallStart == overallEnd
              ? 'За $overallStart місце'
              : 'За $overallStart–$overallEnd місце';

          if (teamsAtPlace.length == 2) {
            _addDirectMatchPage(
              ctx: ctx,
              subtitle: 'Стиковий матч — $placeLabel',
              teamA: teamsAtPlace[0],
              teamB: teamsAtPlace[1],
            );
          } else {
            _addCrossTablePage(
              ctx: ctx,
              subtitle: 'Стикові матчі — $placeLabel',
              teams: teamsAtPlace,
            );
          }
        }
      }

      // 4. Cycle (round-robin) matches
      if (cyclePlaces.isNotEmpty) {
        final cycleTeams = _getTeamsAtPlaces(ctx, groupNames, cyclePlaces);
        if (cycleTeams.isNotEmpty) {
          _addCrossTablePage(
            ctx: ctx,
            subtitle: 'Колові матчі',
            teams: cycleTeams,
          );
        }
      }

      // 5. Total standings (підсумок) — all phases combined
      _addTotalStandingsPage(
        ctx: ctx,
        groupNames: groupNames,
        finalsPlaces: finalsPlaces,
        crossGroupMatchPlaces: crossGroupMatchPlaces,
        cyclePlaces: cyclePlaces,
      );
    } else {
      // Single round-robin cross-table
      _addCrossTablePage(
        ctx: ctx,
        subtitle: 'Крос-таблиця',
        teams: teams,
      );
    }

    return pdf;
  }

  // ---------------------------------------------------------------------------
  // Phase helpers
  // ---------------------------------------------------------------------------

  List<_TeamInfo> _getGroupTeams(_BuildContext ctx, String groupName) {
    return ctx.teams
        .where((t) => ctx.groupAssignments[t.teamId] == groupName)
        .toList();
  }

  List<_TeamInfo> _getTeamsAtPlaces(
    _BuildContext ctx,
    List<String> groupNames,
    List<int> places,
  ) {
    final result = <_TeamInfo>[];
    for (final groupName in groupNames) {
      final groupTeams = _getGroupTeams(ctx, groupName);
      final standings = _calculateStandings(ctx, groupTeams);
      for (final place in places) {
        final idx = place - 1;
        if (idx >= 0 && idx < standings.length) {
          final s = standings[idx];
          final team = groupTeams.where((t) => t.teamId == s.teamId).firstOrNull;
          if (team != null) result.add(team);
        }
      }
    }
    return result;
  }

  List<_TeamInfo> _getTeamsAtSinglePlace(
    _BuildContext ctx,
    List<String> groupNames,
    int place,
  ) {
    final result = <_TeamInfo>[];
    for (final groupName in groupNames) {
      final groupTeams = _getGroupTeams(ctx, groupName);
      final standings = _calculateStandings(ctx, groupTeams);
      final idx = place - 1;
      if (idx >= 0 && idx < standings.length) {
        final s = standings[idx];
        final team = groupTeams.where((t) => t.teamId == s.teamId).firstOrNull;
        if (team != null) result.add(team);
      }
    }
    return result;
  }

  /// Calculate standings for a subset of teams using only their mutual games.
  List<VolleyballStanding> _calculateStandings(_BuildContext ctx, List<_TeamInfo> teams) {
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

  List<int> _parsePlaces(String? value, {List<int> defaultPlaces = const []}) {
    if (value == null || value.trim().isEmpty) return defaultPlaces;
    return value
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toList();
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

    // Sort teams by number
    final sorted = List.of(teams)
      ..sort((a, b) {
        final aNum = a.teamNumber ?? 9999;
        final bNum = b.teamNumber ?? 9999;
        if (aNum != bNum) return aNum.compareTo(bNum);
        return a.teamName.compareTo(b.teamName);
      });

    final standings = _calculateStandings(ctx, sorted);
    final rankMap = <int, int>{};
    for (final s in standings) {
      rankMap[s.teamId] = s.rank;
    }

    final useA3 = n > 8;
    final pageFormat = useA3 ? PdfPageFormat.a3.landscape : PdfPageFormat.a4.landscape;
    final fontSize = 7.0;
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
        _cell('${standing?.losses ?? 0}', cellSt),
        _cell('${standing?.setsWon ?? 0}', cellSt),
        _cell('${standing?.setsLost ?? 0}', cellSt),
        _cell('${standing?.pointsScored ?? 0}', cellSt),
        _cell('${standing?.pointsConceded ?? 0}', cellSt),
        _cell('${rankMap[team.teamId] ?? ''}', cellBold),
      ];

      rows.add(pw.TableRow(decoration: rowBg, children: cells));
    }

    final nameColWidth = useA3 ? 100.0 : 80.0;
    final colWidths = <int, pw.TableColumnWidth>{
      0: const pw.FixedColumnWidth(24),
      1: pw.FixedColumnWidth(nameColWidth),
      for (int i = 0; i < n; i++)
        2 + i: pw.FixedColumnWidth(cellWidth),
      2 + n: const pw.FixedColumnWidth(30),
      2 + n + 1: const pw.FixedColumnWidth(22),
      2 + n + 2: const pw.FixedColumnWidth(22),
      2 + n + 3: const pw.FixedColumnWidth(24),
      2 + n + 4: const pw.FixedColumnWidth(24),
      2 + n + 5: const pw.FixedColumnWidth(26),
      2 + n + 6: const pw.FixedColumnWidth(26),
      2 + n + 7: const pw.FixedColumnWidth(32),
    };

    ctx.pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(20),
        theme: ctx.theme,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(ctx.tournamentName, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
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
  // Direct match page (2-team cross-group match)
  // ---------------------------------------------------------------------------

  void _addDirectMatchPage({
    required _BuildContext ctx,
    required String subtitle,
    required _TeamInfo teamA,
    required _TeamInfo teamB,
  }) {
    // For a 2-team match, just use the cross-table which handles it fine
    _addCrossTablePage(
      ctx: ctx,
      subtitle: subtitle,
      teams: [teamA, teamB],
    );
  }

  // ---------------------------------------------------------------------------
  // Total standings page (підсумок) — combines all phases
  // ---------------------------------------------------------------------------

  void _addTotalStandingsPage({
    required _BuildContext ctx,
    required List<String> groupNames,
    required List<int> finalsPlaces,
    required List<int> crossGroupMatchPlaces,
    required List<int> cyclePlaces,
  }) {
    final numGroups = groupNames.length;

    // Compute cumulative stats across ALL tournament games
    final allStandings = _calculateStandings(ctx, ctx.teams);
    final cumulativeByTeam = {for (final s in allStandings) s.teamId: s};

    final rankedTeams = <_RankedTeam>[];
    final assignedTeamIds = <int>{};
    int nextPlace = 1;

    void addFromStandings(List<VolleyballStanding> standings, String phase) {
      for (final s in standings) {
        if (assignedTeamIds.contains(s.teamId)) continue;
        if (s.isRemoved) continue;
        final cumulative = cumulativeByTeam[s.teamId];
        rankedTeams.add(_RankedTeam(
          teamId: s.teamId,
          teamName: s.teamName,
          overallPlace: nextPlace++,
          phase: phase,
          matchPoints: cumulative?.matchPoints ?? s.matchPoints,
          setsWon: cumulative?.setsWon ?? s.setsWon,
          setsLost: cumulative?.setsLost ?? s.setsLost,
          pointsScored: cumulative?.pointsScored ?? s.pointsScored,
          pointsConceded: cumulative?.pointsConceded ?? s.pointsConceded,
        ));
        assignedTeamIds.add(s.teamId);
      }
    }

    // 1. Finals teams
    if (finalsPlaces.isNotEmpty) {
      final finalists = _getTeamsAtPlaces(ctx, groupNames, finalsPlaces);
      addFromStandings(_calculateStandings(ctx, finalists), 'Фінал');
    }

    // 2. Direct match (стикові) teams — per place
    for (int i = 0; i < crossGroupMatchPlaces.length; i++) {
      final place = crossGroupMatchPlaces[i];
      final teamsAtPlace = _getTeamsAtSinglePlace(ctx, groupNames, place);
      addFromStandings(_calculateStandings(ctx, teamsAtPlace), 'Стикові');
    }

    // 3. Cycle (колові) teams
    if (cyclePlaces.isNotEmpty) {
      final cycleTeams = _getTeamsAtPlaces(ctx, groupNames, cyclePlaces);
      addFromStandings(_calculateStandings(ctx, cycleTeams), 'Колові');
    }

    // 4. Remaining teams — ranked by group standings
    for (final groupName in groupNames) {
      final groupTeams = _getGroupTeams(ctx, groupName);
      addFromStandings(_calculateStandings(ctx, groupTeams), 'Група $groupName');
    }

    if (rankedTeams.isEmpty) return;

    final fontSize = 8.0;
    final hdrStyle = pw.TextStyle(fontSize: fontSize, fontWeight: pw.FontWeight.bold);
    final cellSt = pw.TextStyle(fontSize: fontSize, font: ctx.fontRegular);
    final cellBold = pw.TextStyle(fontSize: fontSize, font: ctx.fontBold, fontWeight: pw.FontWeight.bold);

    final headerCells = <pw.Widget>[
      _cell('Місце', hdrStyle),
      _cell('Команда', hdrStyle, align: pw.Alignment.centerLeft),
      _cell('Етап', hdrStyle),
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

    for (int i = 0; i < rankedTeams.length; i++) {
      final t = rankedTeams[i];
      final rowBg = i.isOdd ? const pw.BoxDecoration(color: PdfColors.grey100) : null;
      final setDiff = t.setsWon - t.setsLost;
      final ptDiff = t.pointsScored - t.pointsConceded;

      rows.add(pw.TableRow(
        decoration: rowBg,
        children: [
          _cell('${t.overallPlace}', cellBold),
          _cell(t.teamName, cellSt, align: pw.Alignment.centerLeft),
          _cell(t.phase, cellSt),
          _cell('${t.matchPoints}', cellBold),
          _cell('${(cumulativeByTeam[t.teamId]?.wins ?? 0)}', cellSt),
          _cell('${(cumulativeByTeam[t.teamId]?.losses ?? 0)}', cellSt),
          _cell('${t.setsWon}', cellSt),
          _cell('${t.setsLost}', cellSt),
          _cell('${setDiff >= 0 ? '+' : ''}$setDiff', cellSt),
          _cell('${t.pointsScored}', cellSt),
          _cell('${t.pointsConceded}', cellSt),
          _cell('${ptDiff >= 0 ? '+' : ''}$ptDiff', cellSt),
        ],
      ));
    }

    final colWidths = <int, pw.TableColumnWidth>{
      0: const pw.FixedColumnWidth(36),
      1: const pw.FixedColumnWidth(140),
      2: const pw.FixedColumnWidth(56),
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

    ctx.pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        theme: ctx.theme,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(ctx.tournamentName, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('Загальний підсумок', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
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

// ---------------------------------------------------------------------------
// Internal data holders
// ---------------------------------------------------------------------------

/// Shared context passed between builder methods.
class _BuildContext {
  final pw.Document pdf;
  final String tournamentName;
  final List<_TeamInfo> teams;
  final Map<(int, int), String> gamesMap;
  final Map<(int, int), String> gamesMapBidi;
  final Set<int> removedTeamIds;
  final Set<(int, int)> noShowPairs;
  final Map<int, String> groupAssignments;
  final pw.ThemeData theme;
  final pw.Font fontRegular;
  final pw.Font fontBold;

  const _BuildContext({
    required this.pdf,
    required this.tournamentName,
    required this.teams,
    required this.gamesMap,
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
  final int matchPoints;
  final int setsWon;
  final int setsLost;
  final int pointsScored;
  final int pointsConceded;

  const _RankedTeam({
    required this.teamId,
    required this.teamName,
    required this.overallPlace,
    required this.phase,
    required this.matchPoints,
    required this.setsWon,
    required this.setsLost,
    required this.pointsScored,
    required this.pointsConceded,
  });
}
