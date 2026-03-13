import 'dart:io';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/player_model.dart';
import '../models/report_model.dart';
import '../models/sport_type_config.dart';
import '../models/tournament_model.dart';
import 'team_service.dart';
import 'tournament_service.dart';

class ReportService {
  final TeamService _teamService;
  final TournamentService _tournamentService;

  ReportService(this._teamService, this._tournamentService);

  /// Load all data needed for a tournament report.
  Future<ReportData> loadReportData(int tId) async {
    final boards = await _teamService.getBoardAssignmentsForTournament(tId);
    final games = await _tournamentService.getGamesGroupedByBoard(tId);
    final allTeams = await _teamService.getTeamListForTournament(tId);

    // Convert record-based board entries to BoardPlayerEntry objects
    final boardPlayers = <int, List<BoardPlayerEntry>>{};
    for (final entry in boards.entries) {
      boardPlayers[entry.key] = entry.value
          .map((p) => BoardPlayerEntry(
                teamId: p.teamId,
                teamName: p.teamName,
                teamNumber: p.teamNumber,
                player: p.player,
              ))
          .toList();
    }

    final results = <int, Map<int, Map<int, double>>>{};
    final details = <int, Map<int, Map<int, String>>>{};
    for (final entry in games.entries) {
      final boardNum = entry.key;
      results.putIfAbsent(boardNum, () => {});
      details.putIfAbsent(boardNum, () => {});
      for (final game in entry.value) {
        final wId = game.white.player_id!;
        final bId = game.black.player_id!;
        if (game.whiteResult != null) {
          results[boardNum]!.putIfAbsent(wId, () => {})[bId] = game.whiteResult!;
        }
        if (game.blackResult != null) {
          results[boardNum]!.putIfAbsent(bId, () => {})[wId] = game.blackResult!;
        }
        if (game.whiteDetail != null && game.whiteDetail!.isNotEmpty) {
          details[boardNum]!.putIfAbsent(wId, () => {})[bId] = game.whiteDetail!;
        }
        if (game.blackDetail != null && game.blackDetail!.isNotEmpty) {
          details[boardNum]!.putIfAbsent(bId, () => {})[wId] = game.blackDetail!;
        }
      }
    }

    // Load no-show players so phantom logic treats them as absent too
    final noShowIds = await _teamService.getNoShowPlayerIds(tId);

    // Add phantom "absent" entries for teams missing from each board.
    final absentIds = <int>{...noShowIds};
    for (final boardNum in boardPlayers.keys) {
      final presentTeamIds = boardPlayers[boardNum]!.map((p) => p.teamId).toSet();
      for (final team in allTeams) {
        if (presentTeamIds.contains(team.teamId)) continue;
        final phantomId = -(team.teamId * 100 + boardNum);
        absentIds.add(phantomId);
        boardPlayers[boardNum]!.add(BoardPlayerEntry(
          teamId: team.teamId,
          teamName: team.teamName,
          teamNumber: team.teamNumber,
          player: Player(
            player_id: phantomId,
            player_surname: 'Відсутн.',
            player_name: '',
            player_lastname: '',
            player_gender: 0,
            player_date_birth: '',
          ),
        ));
        results.putIfAbsent(boardNum, () => {});
        details.putIfAbsent(boardNum, () => {});
        results[boardNum]!.putIfAbsent(phantomId, () => {});
        details[boardNum]!.putIfAbsent(phantomId, () => {});
        for (final realPlayer in boardPlayers[boardNum]!) {
          final realId = realPlayer.player.player_id!;
          if (realId == phantomId || absentIds.contains(realId)) continue;
          results[boardNum]![phantomId]![realId] = 0.0;
          results[boardNum]!.putIfAbsent(realId, () => {})[phantomId] = 1.0;
          // Add set details for phantom games: real wins 11:0 11:0
          details[boardNum]!.putIfAbsent(realId, () => {})[phantomId] = '11:0 11:0';
          details[boardNum]![phantomId]![realId] = '0:11 0:11';
        }
      }
    }
    // Ensure no-show players have results vs all real players
    for (final boardNum in boardPlayers.keys) {
      results.putIfAbsent(boardNum, () => {});
      details.putIfAbsent(boardNum, () => {});
      for (final noShowId in noShowIds) {
        final onBoard = boardPlayers[boardNum]!.any((p) => p.player.player_id == noShowId);
        if (!onBoard) continue;
        results[boardNum]!.putIfAbsent(noShowId, () => {});
        details[boardNum]!.putIfAbsent(noShowId, () => {});
        for (final other in boardPlayers[boardNum]!) {
          final otherId = other.player.player_id!;
          if (otherId == noShowId || absentIds.contains(otherId)) continue;
          if (results[boardNum]![noShowId]![otherId] == null) {
            results[boardNum]![noShowId]![otherId] = 0.0;
            results[boardNum]!.putIfAbsent(otherId, () => {})[noShowId] = 1.0;
            details[boardNum]!.putIfAbsent(otherId, () => {})[noShowId] = '11:0 11:0';
            details[boardNum]![noShowId]![otherId] = '0:11 0:11';
          }
        }
      }
    }
    // Cross-set absent vs absent (phantom + no-show): both get 0
    for (final boardNum in boardPlayers.keys) {
      final absentOnBoard = boardPlayers[boardNum]!
          .where((p) => absentIds.contains(p.player.player_id))
          .map((p) => p.player.player_id!)
          .toList();
      for (int i = 0; i < absentOnBoard.length; i++) {
        for (int j = i + 1; j < absentOnBoard.length; j++) {
          results[boardNum]!.putIfAbsent(absentOnBoard[i], () => {})[absentOnBoard[j]] = 0.0;
          results[boardNum]!.putIfAbsent(absentOnBoard[j], () => {})[absentOnBoard[i]] = 0.0;
        }
      }
    }

    return ReportData(
      boardPlayers: boardPlayers,
      boardResults: results,
      boardResultDetails: details,
    );
  }

  // ---------------------------------------------------------------------------
  // Scoring helpers
  // ---------------------------------------------------------------------------

  double totalPoints(ReportData data, int boardNum, int playerId) {
    return (data.boardResults[boardNum]?[playerId] ?? {}).values.fold(0.0, (sum, r) => sum + r);
  }

  /// Display points: for table tennis, a win gives 2 pts (multiplied).
  double displayPoints(ReportData data, int boardNum, int playerId, bool isTableTennis) {
    return totalPoints(data, boardNum, playerId) * (isTableTennis ? 2 : 1);
  }

  double bergerCoefficient(ReportData data, int boardNum, int playerId) {
    final results = data.boardResults[boardNum]?[playerId] ?? {};
    double sb = 0;
    for (final entry in results.entries) {
      final result = entry.value;
      final opponentPoints = totalPoints(data, boardNum, entry.key);
      if (result == 1.0) {
        sb += opponentPoints;
      } else if (result == 0.5) {
        sb += opponentPoints * 0.5;
      }
    }
    return sb;
  }

  ({int scored, int conceded}) totalBalls(ReportData data, int boardNum, int playerId) {
    int scored = 0;
    int conceded = 0;
    final det = data.boardResultDetails[boardNum]?[playerId] ?? {};
    for (final detail in det.values) {
      for (final s in detail.split(' ')) {
        final parts = s.split(':');
        if (parts.length != 2) continue;
        scored += int.tryParse(parts[0]) ?? 0;
        conceded += int.tryParse(parts[1]) ?? 0;
      }
    }
    return (scored: scored, conceded: conceded);
  }

  int gamesPlayed(ReportData data, int boardNum, int playerId) {
    return (data.boardResults[boardNum]?[playerId] ?? {}).length;
  }

  List<BoardPlayerEntry> sortedStandings(
    ReportData data,
    int boardNum,
    List<BoardPlayerEntry> players,
    bool isTableTennis,
  ) {
    final sorted = List.of(players);
    sorted.sort((a, b) {
      final aId = a.player.player_id!;
      final bId = b.player.player_id!;
      final pa = totalPoints(data, boardNum, aId);
      final pb = totalPoints(data, boardNum, bId);
      if (pa != pb) return pb.compareTo(pa);
      final aVsB = data.boardResults[boardNum]?[aId]?[bId];
      final bVsA = data.boardResults[boardNum]?[bId]?[aId];
      if (aVsB != null && bVsA != null) {
        if (aVsB > bVsA) return -1;
        if (aVsB < bVsA) return 1;
      }
      if (isTableTennis) {
        final aBalls = totalBalls(data, boardNum, aId);
        final bBalls = totalBalls(data, boardNum, bId);
        final aDiff = aBalls.scored - aBalls.conceded;
        final bDiff = bBalls.scored - bBalls.conceded;
        return bDiff.compareTo(aDiff);
      }
      final ba = bergerCoefficient(data, boardNum, aId);
      final bb = bergerCoefficient(data, boardNum, bId);
      return bb.compareTo(ba);
    });
    return sorted;
  }

  ({double a, double b}) teamMatchScore(ReportData data, int teamAId, int teamBId) {
    double aTotal = 0;
    double bTotal = 0;
    for (final boardEntry in data.boardPlayers.entries) {
      final boardNum = boardEntry.key;
      final playerA = boardEntry.value.where((p) => p.teamId == teamAId).firstOrNull;
      final playerB = boardEntry.value.where((p) => p.teamId == teamBId).firstOrNull;
      if (playerA == null || playerB == null) continue;
      final aResult = data.boardResults[boardNum]?[playerA.player.player_id!]?[playerB.player.player_id!];
      final bResult = data.boardResults[boardNum]?[playerB.player.player_id!]?[playerA.player.player_id!];
      if (aResult != null) aTotal += aResult;
      if (bResult != null) bTotal += bResult;
    }
    return (a: aTotal, b: bTotal);
  }

  ({double a, double b}) teamMatchPoints(ReportData data, int teamAId, int teamBId) {
    final score = teamMatchScore(data, teamAId, teamBId);
    if (score.a > score.b) return (a: 2.0, b: 0.0);
    if (score.b > score.a) return (a: 0.0, b: 2.0);
    if (score.a > 0 || score.b > 0) return (a: 1.0, b: 1.0);
    return (a: 0.0, b: 0.0);
  }

  ({int won, int lost}) _countSetsFromDetail(String detail) {
    int won = 0;
    int lost = 0;
    for (final s in detail.split(' ')) {
      final parts = s.split(':');
      if (parts.length != 2) continue;
      final a = int.tryParse(parts[0]);
      final b = int.tryParse(parts[1]);
      if (a == null || b == null) continue;
      if (a > b) won++;
      else if (b > a) lost++;
    }
    return (won: won, lost: lost);
  }

  ({int scored, int conceded}) _countBallsFromDetail(String detail) {
    int scored = 0;
    int conceded = 0;
    for (final s in detail.split(' ')) {
      final parts = s.split(':');
      if (parts.length != 2) continue;
      scored += int.tryParse(parts[0]) ?? 0;
      conceded += int.tryParse(parts[1]) ?? 0;
    }
    return (scored: scored, conceded: conceded);
  }

  int teamDirectSetDiff(ReportData data, int teamAId, int teamBId) {
    int setsWon = 0;
    int setsLost = 0;
    for (final boardEntry in data.boardPlayers.entries) {
      final boardNum = boardEntry.key;
      final playerA = boardEntry.value.where((p) => p.teamId == teamAId).firstOrNull;
      final playerB = boardEntry.value.where((p) => p.teamId == teamBId).firstOrNull;
      if (playerA == null || playerB == null) continue;
      final aId = playerA.player.player_id!;
      final bId = playerB.player.player_id!;
      final detail = data.boardResultDetails[boardNum]?[aId]?[bId];
      if (detail == null || detail.isEmpty) continue;
      final sets = _countSetsFromDetail(detail);
      setsWon += sets.won;
      setsLost += sets.lost;
    }
    return setsWon - setsLost;
  }

  int teamDirectBallDiff(ReportData data, int teamAId, int teamBId) {
    int scored = 0;
    int conceded = 0;
    for (final boardEntry in data.boardPlayers.entries) {
      final boardNum = boardEntry.key;
      final playerA = boardEntry.value.where((p) => p.teamId == teamAId).firstOrNull;
      final playerB = boardEntry.value.where((p) => p.teamId == teamBId).firstOrNull;
      if (playerA == null || playerB == null) continue;
      final aId = playerA.player.player_id!;
      final bId = playerB.player.player_id!;
      final detail = data.boardResultDetails[boardNum]?[aId]?[bId];
      if (detail == null || detail.isEmpty) continue;
      final balls = _countBallsFromDetail(detail);
      scored += balls.scored;
      conceded += balls.conceded;
    }
    return scored - conceded;
  }

  int teamTotalSetDiff(ReportData data, int teamId) {
    int setsWon = 0;
    int setsLost = 0;
    for (final boardEntry in data.boardPlayers.entries) {
      final boardNum = boardEntry.key;
      final player = boardEntry.value.where((p) => p.teamId == teamId).firstOrNull;
      if (player == null) continue;
      final pId = player.player.player_id!;
      final details = data.boardResultDetails[boardNum]?[pId] ?? {};
      for (final detail in details.values) {
        final sets = _countSetsFromDetail(detail);
        setsWon += sets.won;
        setsLost += sets.lost;
      }
    }
    return setsWon - setsLost;
  }

  // ---------------------------------------------------------------------------
  // Formatting helpers
  // ---------------------------------------------------------------------------

  String fmtPlayerName(Player player) {
    final name = player.player_name.trim();
    if (name.isEmpty) return player.player_surname;
    return '${player.player_surname} ${name[0]}.';
  }

  String fmtPts(double points) {
    if (points == points.roundToDouble()) return points.toStringAsFixed(0);
    String s = points.toStringAsFixed(2);
    if (s.endsWith('0')) s = s.substring(0, s.length - 1);
    return s;
  }

  String fmtResult(double? result) {
    if (result == null) return '';
    if (result == 1.0) return '1';
    if (result == 0.0) return '0';
    if (result == 0.5) return '1/2';
    return result.toString();
  }

  String fmtResultTT(ReportData data, int boardNum, int rowId, int colId) {
    final detail = data.boardResultDetails[boardNum]?[rowId]?[colId];
    final result = data.boardResults[boardNum]?[rowId]?[colId];
    if (result == null) return '';
    if (detail == null || detail.isEmpty) return fmtResult(result);
    final sets = detail.split(' ');
    int rowWins = 0, colWins = 0;
    for (final s in sets) {
      final parts = s.split(':');
      if (parts.length != 2) continue;
      final a = int.tryParse(parts[0]) ?? 0;
      final b = int.tryParse(parts[1]) ?? 0;
      if (a > b) rowWins++;
      else if (b > a) colWins++;
    }
    return '$rowWins:$colWins\n(${sets.join(', ')})';
  }

  // ---------------------------------------------------------------------------
  // PDF generation
  // ---------------------------------------------------------------------------

  Future<pw.Document> buildPdf(Tournament tournament, SportTypeConfig config, ReportData data) async {
    final pdf = pw.Document();
    final tournamentName = tournament.t_name;
    final boards = data.boardPlayers.keys.toList()..sort();
    final isTableTennis = tournament.t_type == 11;

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

    // --- Board cross-tables (landscape pages) ---
    for (final boardNum in boards) {
      final rawPlayers = data.boardPlayers[boardNum] ?? [];
      if (rawPlayers.isEmpty) continue;

      final players = List.of(rawPlayers)
        ..sort((a, b) {
          final aNum = a.teamNumber ?? 9999;
          final bNum = b.teamNumber ?? 9999;
          if (aNum != bNum) return aNum.compareTo(bNum);
          return a.teamName.compareTo(b.teamName);
        });
      final n = players.length;
      final sorted = sortedStandings(data, boardNum, players, isTableTennis);
      final boardLabel = config.tabLabel(boardNum);

      // Adaptive sizing: use A3 landscape for large tables so name columns stay visible
      final useA3 = n > 10;
      final pageFormat = useA3 ? PdfPageFormat.a3.landscape : PdfPageFormat.a4.landscape;
      final fontSize = useA3 ? 7.0 : 7.0;
      final matchCellWidth = n <= 6 ? 44.0 : n <= 10 ? 38.0 : n <= 14 ? 32.0 : 28.0;

      final hdrStyle = pw.TextStyle(fontSize: fontSize, fontWeight: pw.FontWeight.bold);
      final cellSt = pw.TextStyle(fontSize: fontSize, font: fontRegular);
      final cellBold = pw.TextStyle(fontSize: fontSize, font: fontBold, fontWeight: pw.FontWeight.bold);

      final isTT = isTableTennis;

      final headerCells = <pw.Widget>[
        _pdfCell('№к', hdrStyle, align: pw.Alignment.center),
        _pdfCell('Прізвище Ім\'я', hdrStyle, align: pw.Alignment.center),
        _pdfCell('Команда', hdrStyle, align: pw.Alignment.center),
        for (int i = 0; i < n; i++)
          _pdfCell('${i + 1}', hdrStyle, align: pw.Alignment.center),
        _pdfCell('Бали', hdrStyle, align: pw.Alignment.center),
        _pdfCell('Ігор', hdrStyle, align: pw.Alignment.center),
        if (!isTT) _pdfCell('К.Б.', hdrStyle, align: pw.Alignment.center),
        if (isTT) _pdfCell('М.З.', hdrStyle, align: pw.Alignment.center),
        if (isTT) _pdfCell('М.П.', hdrStyle, align: pw.Alignment.center),
        _pdfCell('№к', hdrStyle, align: pw.Alignment.center),
        _pdfCell('Прізвище Ім\'я', hdrStyle, align: pw.Alignment.center),
        _pdfCell('Команда', hdrStyle, align: pw.Alignment.center),
        _pdfCell('Бали', hdrStyle, align: pw.Alignment.center),
        if (!isTT) _pdfCell('К.Б.', hdrStyle, align: pw.Alignment.center),
        if (isTT) _pdfCell('М.З.', hdrStyle, align: pw.Alignment.center),
        if (isTT) _pdfCell('М.П.', hdrStyle, align: pw.Alignment.center),
        _pdfCell('Місце', hdrStyle, align: pw.Alignment.center),
      ];

      final dataTableRows = <pw.TableRow>[];
      dataTableRows.add(pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: headerCells,
      ));

      for (int i = 0; i < n; i++) {
        final p = players[i];
        final pId = p.player.player_id!;
        final s = sorted[i];
        final sId = s.player.player_id!;
        final isAbsent = pId < 0;
        final nameStyle = isAbsent
            ? pw.TextStyle(fontSize: 7, font: fontRegular, fontStyle: pw.FontStyle.italic, color: PdfColors.red)
            : cellSt;

        final rowBg = i.isOdd ? const pw.BoxDecoration(color: PdfColors.grey100) : null;

        final cells = <pw.Widget>[
          _pdfCell('${p.teamNumber ?? ''}', cellSt),
          _pdfCell(fmtPlayerName(p.player), nameStyle, align: pw.Alignment.centerLeft),
          _pdfCell(p.teamName, cellSt, align: pw.Alignment.centerLeft),
          for (int j = 0; j < n; j++)
            if (i == j)
              _pdfDiagonalCell()
            else
              _pdfCell(
                isTT
                    ? fmtResultTT(data, boardNum, pId, players[j].player.player_id!)
                    : fmtResult(data.boardResults[boardNum]?[pId]?[players[j].player.player_id!]),
                cellSt,
              ),
          _pdfCell(fmtPts(displayPoints(data, boardNum, pId, isTT)), cellBold),
          _pdfCell('${gamesPlayed(data, boardNum, pId)}', cellSt),
          if (!isTT) _pdfCell(fmtPts(bergerCoefficient(data, boardNum, pId)), cellSt),
          if (isTT) _pdfCell('${totalBalls(data, boardNum, pId).scored}', cellSt),
          if (isTT) _pdfCell('${totalBalls(data, boardNum, pId).conceded}', cellSt),
          _pdfCell('${s.teamNumber ?? ''}', cellSt),
          _pdfCell(fmtPlayerName(s.player), cellSt, align: pw.Alignment.centerLeft),
          _pdfCell(s.teamName, cellSt, align: pw.Alignment.centerLeft),
          _pdfCell(fmtPts(displayPoints(data, boardNum, sId, isTT)), cellBold),
          if (!isTT) _pdfCell(fmtPts(bergerCoefficient(data, boardNum, sId)), cellSt),
          if (isTT) _pdfCell('${totalBalls(data, boardNum, sId).scored}', cellSt),
          if (isTT) _pdfCell('${totalBalls(data, boardNum, sId).conceded}', cellSt),
          _pdfCell('${i + 1}', cellBold),
        ];

        dataTableRows.add(pw.TableRow(decoration: rowBg, children: cells));
      }

      // Use fixed minimum widths for name/team columns so they never get squeezed to 0
      final nameColWidth = useA3 ? 70.0 : 55.0;
      final teamColWidth = useA3 ? 80.0 : 65.0;

      final colWidths = <int, pw.TableColumnWidth>{
        0: const pw.FixedColumnWidth(22),
        1: pw.FixedColumnWidth(nameColWidth),
        2: pw.FixedColumnWidth(teamColWidth),
        for (int i = 0; i < n; i++)
          3 + i: pw.FixedColumnWidth(isTT ? matchCellWidth : 20),
        3 + n: const pw.FixedColumnWidth(28),
        3 + n + 1: const pw.FixedColumnWidth(24),
      };
      if (!isTT) {
        colWidths[3 + n + 2] = const pw.FixedColumnWidth(28);
        colWidths[3 + n + 3] = const pw.FixedColumnWidth(22);
        colWidths[3 + n + 4] = pw.FixedColumnWidth(nameColWidth);
        colWidths[3 + n + 5] = pw.FixedColumnWidth(teamColWidth);
        colWidths[3 + n + 6] = const pw.FixedColumnWidth(28);
        colWidths[3 + n + 7] = const pw.FixedColumnWidth(28);
        colWidths[3 + n + 8] = const pw.FixedColumnWidth(30);
      } else {
        colWidths[3 + n + 2] = const pw.FixedColumnWidth(28);
        colWidths[3 + n + 3] = const pw.FixedColumnWidth(28);
        colWidths[3 + n + 4] = const pw.FixedColumnWidth(22);
        colWidths[3 + n + 5] = pw.FixedColumnWidth(nameColWidth);
        colWidths[3 + n + 6] = pw.FixedColumnWidth(teamColWidth);
        colWidths[3 + n + 7] = const pw.FixedColumnWidth(28);
        colWidths[3 + n + 8] = const pw.FixedColumnWidth(28);
        colWidths[3 + n + 9] = const pw.FixedColumnWidth(28);
        colWidths[3 + n + 10] = const pw.FixedColumnWidth(30);
      }

      pdf.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: const pw.EdgeInsets.all(20),
          theme: theme,
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(tournamentName, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text(boardLabel, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400),
                columnWidths: colWidths,
                defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
                children: dataTableRows,
              ),
            ],
          ),
        ),
      );
    }

    // --- Team standings page ---
    final teamMap = <int, ({String teamName, int? teamNumber})>{};
    for (final boardEntry in data.boardPlayers.entries) {
      for (final p in boardEntry.value) {
        teamMap.putIfAbsent(p.teamId, () => (teamName: p.teamName, teamNumber: p.teamNumber));
      }
    }

    if (teamMap.isNotEmpty) {
      final teamIds = teamMap.keys.toList();
      final teamPoints = <int, double>{};
      final teamBoard1Pts = <int, double>{};
      final teamBoard3Pts = <int, double>{};
      for (final aId in teamIds) {
        double total = 0;
        for (final bId in teamIds) {
          if (aId == bId) continue;
          total += teamMatchPoints(data, aId, bId).a;
        }
        teamPoints[aId] = total;
        final b1p = (data.boardPlayers[1] ?? []).where((p) => p.teamId == aId).firstOrNull;
        teamBoard1Pts[aId] = b1p != null ? totalPoints(data, 1, b1p.player.player_id!) : 0;
        final lastBoard = config.boardCount;
        final b3p = (data.boardPlayers[lastBoard] ?? []).where((p) => p.teamId == aId).firstOrNull;
        teamBoard3Pts[aId] = b3p != null ? totalPoints(data, lastBoard, b3p.player.player_id!) : 0;
      }

      final isTT = isTableTennis;
      final teamTotalSetDiffMap = <int, int>{};
      if (isTT) {
        for (final id in teamIds) {
          teamTotalSetDiffMap[id] = teamTotalSetDiff(data, id);
        }
      }

      // Cross-table order: by team number (like the interface)
      final teamIdsByNumber = List<int>.from(teamIds)
        ..sort((a, b) {
          final aNum = teamMap[a]!.teamNumber ?? 9999;
          final bNum = teamMap[b]!.teamNumber ?? 9999;
          if (aNum != bNum) return aNum.compareTo(bNum);
          return teamMap[a]!.teamName.compareTo(teamMap[b]!.teamName);
        });

      // Standings order: by points + tiebreakers
      final sortedTeamIds = List<int>.from(teamIds)
        ..sort((a, b) {
          final pa = teamPoints[a]!;
          final pb = teamPoints[b]!;
          if (pa != pb) return pb.compareTo(pa);
          final h2h = teamMatchPoints(data, a, b);
          if (h2h.a > h2h.b) return -1;
          if (h2h.b > h2h.a) return 1;
          if (isTT) {
            final setDiffA = teamDirectSetDiff(data, a, b);
            final setDiffB = teamDirectSetDiff(data, b, a);
            if (setDiffA != setDiffB) return setDiffB.compareTo(setDiffA);
            final ballDiffA = teamDirectBallDiff(data, a, b);
            final ballDiffB = teamDirectBallDiff(data, b, a);
            if (ballDiffA != ballDiffB) return ballDiffB.compareTo(ballDiffA);
            final tsdA = teamTotalSetDiffMap[a]!;
            final tsdB = teamTotalSetDiffMap[b]!;
            if (tsdA != tsdB) return tsdB.compareTo(tsdA);
            return teamBoard3Pts[b]!.compareTo(teamBoard3Pts[a]!);
          } else {
            final b1a = teamBoard1Pts[a]!;
            final b1b = teamBoard1Pts[b]!;
            if (b1a != b1b) return b1b.compareTo(b1a);
            return teamBoard3Pts[b]!.compareTo(teamBoard3Pts[a]!);
          }
        });

      final tn = teamIdsByNumber.length;
      final hdrStyle = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);
      final cellSt = pw.TextStyle(fontSize: 8, font: fontRegular);
      final cellBold = pw.TextStyle(fontSize: 8, font: fontBold, fontWeight: pw.FontWeight.bold);

      final teamHdrCells = <pw.Widget>[
        _pdfCell('№', hdrStyle),
        _pdfCell('Команда', hdrStyle, align: pw.Alignment.center),
        for (int i = 0; i < tn; i++)
          _pdfTeamHeaderCell(
            '${teamMap[teamIdsByNumber[i]]!.teamNumber ?? (i + 1)}',
            teamMap[teamIdsByNumber[i]]!.teamName,
            hdrStyle,
          ),
        _pdfCell('Очки', hdrStyle),
        if (isTT)
          _pdfCell('Сети', hdrStyle)
        else
          _pdfCell('${config.boardAbbrev}1', hdrStyle),
        _pdfCell('${config.boardAbbrev}${config.boardCount}', hdrStyle),
        // Standings section (right side)
        _pdfCell('№', hdrStyle),
        _pdfCell('Команда', hdrStyle, align: pw.Alignment.center),
        _pdfCell('Очки', hdrStyle),
        _pdfCell('Місце', hdrStyle),
      ];

      final teamTableRows = <pw.TableRow>[
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: teamHdrCells,
        ),
      ];

      for (int i = 0; i < tn; i++) {
        final tid = teamIdsByNumber[i];
        final sid = sortedTeamIds[i];
        final rowBg = i.isOdd ? const pw.BoxDecoration(color: PdfColors.grey100) : null;

        final cells = <pw.Widget>[
          _pdfTeamHeaderCell(
            '${teamMap[tid]!.teamNumber ?? (i + 1)}',
            teamMap[tid]!.teamName,
            cellSt,
          ),
          _pdfCell(teamMap[tid]!.teamName, cellSt, align: pw.Alignment.centerLeft),
          for (int j = 0; j < tn; j++)
            if (i == j)
              _pdfDiagonalCell()
            else
              _pdfTeamResultCell(data, tid, teamIdsByNumber[j], cellSt, cellBold),
          _pdfCell(fmtPts(teamPoints[tid]!), cellBold),
          if (isTT)
            _pdfCell('${teamTotalSetDiffMap[tid]! >= 0 ? '+' : ''}${teamTotalSetDiffMap[tid]!}', cellSt)
          else
            _pdfCell(fmtPts(teamBoard1Pts[tid]!), cellSt),
          _pdfCell(fmtPts(teamBoard3Pts[tid]!), cellSt),
          // Standings section (right side, sorted by place)
          _pdfCell('${teamMap[sid]!.teamNumber ?? ''}', cellSt),
          _pdfCell(teamMap[sid]!.teamName, cellSt, align: pw.Alignment.centerLeft),
          _pdfCell(fmtPts(teamPoints[sid]!), cellBold),
          _pdfCell('${i + 1}', cellBold),
        ];

        teamTableRows.add(pw.TableRow(decoration: rowBg, children: cells));
      }

      final teamColWidths = <int, pw.TableColumnWidth>{
        0: const pw.FixedColumnWidth(38),
        1: const pw.FlexColumnWidth(3),
        for (int i = 0; i < tn; i++)
          2 + i: const pw.FixedColumnWidth(38),
        2 + tn: const pw.FixedColumnWidth(36),
        2 + tn + 1: const pw.FixedColumnWidth(32),
        2 + tn + 2: const pw.FixedColumnWidth(32),
        // Standings columns
        2 + tn + 3: const pw.FixedColumnWidth(28),
        2 + tn + 4: const pw.FlexColumnWidth(3),
        2 + tn + 5: const pw.FixedColumnWidth(36),
        2 + tn + 6: const pw.FixedColumnWidth(36),
      };

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(20),
          theme: theme,
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(tournamentName, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text('Командний залік', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400),
                columnWidths: teamColWidths,
                defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
                children: teamTableRows,
              ),
            ],
          ),
        ),
      );
    }

    return pdf;
  }

  Future<void> exportPdf(Tournament tournament, SportTypeConfig config, ReportData data) async {
    final doc = await buildPdf(tournament, config, data);
    final bytes = await doc.save();
    final name = tournament.t_name.replaceAll(RegExp(r'[^\w\s\-]'), '').trim();
    await Printing.sharePdf(bytes: bytes, filename: 'Звіт_$name.pdf');
  }

  // ---------------------------------------------------------------------------
  // PDF cell helpers
  // ---------------------------------------------------------------------------

  pw.Widget _pdfCell(String text, pw.TextStyle style, {pw.Alignment align = pw.Alignment.center}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      alignment: align,
      child: pw.Text(text, style: style, textAlign: align == pw.Alignment.centerLeft ? pw.TextAlign.left : pw.TextAlign.center),
    );
  }

  pw.Widget _pdfTeamHeaderCell(String number, String teamName, pw.TextStyle style) {
    final smallStyle = style.copyWith(fontSize: (style.fontSize ?? 8) - 2);
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      alignment: pw.Alignment.center,
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(number, style: style, textAlign: pw.TextAlign.center),
          pw.Text(teamName, style: smallStyle, textAlign: pw.TextAlign.center, maxLines: 2),
        ],
      ),
    );
  }

  pw.Widget _pdfDiagonalCell() {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      color: PdfColors.grey600,
      alignment: pw.Alignment.center,
      child: pw.Text(''),
    );
  }

  pw.Widget _pdfTeamResultCell(ReportData data, int teamAId, int teamBId, pw.TextStyle cellSt, pw.TextStyle cellBold) {
    final matchPts = teamMatchPoints(data, teamAId, teamBId);
    final boardScore = teamMatchScore(data, teamAId, teamBId);
    final pts = matchPts.a;
    final label = '${pts.toInt()}';

    PdfColor? bgColor;
    if (pts == 2.0) bgColor = PdfColors.green50;
    else if (pts == 0.0 && (boardScore.a > 0 || boardScore.b > 0)) bgColor = PdfColors.red50;
    else if (pts == 1.0) bgColor = PdfColors.amber50;

    PdfColor textColor = PdfColors.black;
    if (pts == 2.0) textColor = PdfColors.green800;
    else if (pts == 0.0) textColor = PdfColors.red800;
    else if (pts == 1.0) textColor = PdfColors.amber800;

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3),
      color: bgColor,
      alignment: pw.Alignment.center,
      child: pw.Text(label, style: cellBold.copyWith(color: textColor), textAlign: pw.TextAlign.center),
    );
  }
}
