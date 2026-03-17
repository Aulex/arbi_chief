import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../viewmodels/standings_window_provider.dart';

/// Standalone app that runs in the sub-window.
/// Receives standings data from the main window via inter-window messaging.
class StandingsWindowApp extends StatefulWidget {
  final WindowController controller;
  final String argument;

  const StandingsWindowApp({
    super.key,
    required this.controller,
    required this.argument,
  });

  @override
  State<StandingsWindowApp> createState() => _StandingsWindowAppState();
}

class _StandingsWindowAppState extends State<StandingsWindowApp> {
  StandingsSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    // Parse initial data
    try {
      final data = jsonDecode(widget.argument) as Map<String, dynamic>;
      if (data.isNotEmpty) {
        _snapshot = StandingsSnapshot.fromJson(data);
      }
    } catch (_) {}

    // Listen for updates from main window via WindowMethodChannel
    const channel = WindowMethodChannel(standingsChannelName);
    channel.setMethodCallHandler((call) async {
      if (call.method == 'updateStandings') {
        try {
          final data =
              jsonDecode(call.arguments as String) as Map<String, dynamic>;
          if (mounted) {
            setState(() {
              _snapshot = StandingsSnapshot.fromJson(data);
            });
          }
        } catch (_) {}
      }
      return '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Турнірна таблиця',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: Colors.indigo,
      ),
      home: _StandingsDisplay(
        snapshot: _snapshot,
        onSnapshotRefreshed: (fresh) {
          if (mounted) {
            setState(() {
              _snapshot = fresh;
            });
          }
        },
      ),
    );
  }
}

class _StandingsDisplay extends StatefulWidget {
  final StandingsSnapshot? snapshot;
  final ValueChanged<StandingsSnapshot>? onSnapshotRefreshed;
  const _StandingsDisplay({required this.snapshot, this.onSnapshotRefreshed});

  @override
  State<_StandingsDisplay> createState() => _StandingsDisplayState();
}

class _StandingsDisplayState extends State<_StandingsDisplay>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  Timer? _autoTabTimer;
  int _autoTabSeconds = 0; // 0 = disabled

  @override
  void initState() {
    super.initState();
    _loadAutoTabSetting();
    _initTabController();
  }

  Future<void> _loadAutoTabSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seconds = prefs.getInt('auto_tab_cycle_seconds') ?? 10;
      if (mounted) {
        setState(() {
          _autoTabSeconds = seconds;
        });
        _restartAutoTabTimer();
      }
    } catch (_) {}
  }

  void _initTabController() {
    final s = widget.snapshot;
    if (s != null) {
      _tabController?.dispose();
      _tabController = TabController(length: s.boardCount + 1, vsync: this);
    }
  }

  void _restartAutoTabTimer() {
    _autoTabTimer?.cancel();
    if (_autoTabSeconds > 0 && _tabController != null) {
      _autoTabTimer = Timer.periodic(
        Duration(seconds: _autoTabSeconds),
        (_) async {
          if (_tabController != null && mounted) {
            // Refresh data from file on each tab cycle
            await _refreshFromFile();
            final next = (_tabController!.index + 1) % _tabController!.length;
            _tabController!.animateTo(next);
          }
        },
      );
    }
  }

  Future<void> _refreshFromFile() async {
    try {
      final fresh = await readStandingsFromFile();
      if (fresh != null && mounted) {
        // Only rebuild if data actually changed (compare tournament name + standings)
        final current = widget.snapshot;
        if (current == null ||
            fresh.tournamentName != current.tournamentName ||
            fresh.boardCount != current.boardCount ||
            _snapshotChanged(current, fresh)) {
          // We can't directly update widget.snapshot, so we trigger rebuild
          // through the parent StandingsWindowApp
          widget.onSnapshotRefreshed?.call(fresh);
        }
      }
    } catch (_) {}
  }

  bool _snapshotChanged(StandingsSnapshot a, StandingsSnapshot b) {
    // Quick check: compare serialized cross table and standings lengths
    for (final boardNum in b.boardStandings.keys) {
      final aRows = a.boardStandings[boardNum] ?? [];
      final bRows = b.boardStandings[boardNum] ?? [];
      if (aRows.length != bRows.length) return true;
      for (int i = 0; i < aRows.length; i++) {
        if (aRows[i].points != bRows[i].points ||
            aRows[i].gamesPlayed != bRows[i].gamesPlayed) return true;
      }
      final aCross = a.crossTableData[boardNum] ?? [];
      final bCross = b.crossTableData[boardNum] ?? [];
      if (aCross.length != bCross.length) return true;
      for (int i = 0; i < aCross.length; i++) {
        if (aCross[i].points != bCross[i].points ||
            aCross[i].gamesPlayed != bCross[i].gamesPlayed) return true;
      }
    }
    if (a.teamStandings.length != b.teamStandings.length) return true;
    for (int i = 0; i < a.teamStandings.length; i++) {
      if (a.teamStandings[i].points != b.teamStandings[i].points) return true;
    }
    return false;
  }

  @override
  void didUpdateWidget(covariant _StandingsDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldCount = oldWidget.snapshot?.boardCount ?? 0;
    final newCount = widget.snapshot?.boardCount ?? 0;
    if (oldCount != newCount) {
      final oldIndex = _tabController?.index ?? 0;
      _initTabController();
      if (_tabController != null && oldIndex < _tabController!.length) {
        _tabController!.index = oldIndex;
      }
      _restartAutoTabTimer();
    }
  }

  @override
  void dispose() {
    _autoTabTimer?.cancel();
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.snapshot == null) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Очікування даних...'),
            ],
          ),
        ),
      );
    }

    final s = widget.snapshot!;
    final isTT = s.tType == 11;

    if (_tabController == null || _tabController!.length != s.boardCount + 1) {
      _initTabController();
      _restartAutoTabTimer();
    }

    return Scaffold(
      body: Column(
        children: [
          // Header
          Container(
            color: Colors.indigo,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.leaderboard, color: Colors.white, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    s.tournamentName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_autoTabSeconds > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.autorenew, color: Colors.white70, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          '${_autoTabSeconds}с',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // Sub-tabs
          Container(
            color: Colors.indigo.shade50,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: Colors.indigo,
              indicatorColor: Colors.indigo,
              tabAlignment: TabAlignment.start,
              labelPadding: const EdgeInsets.symmetric(horizontal: 16),
              tabs: [
                for (int i = 1; i <= s.boardCount; i++)
                  Tab(
                    text: s.boardTabLabels[i] ?? '${s.boardAbbrev}$i',
                    height: 36,
                  ),
                const Tab(text: 'Команди', height: 36),
              ],
            ),
          ),
          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                for (int i = 1; i <= s.boardCount; i++)
                  _buildBoardTab(s, i, isTT),
                _buildTeamsTab(s, isTT),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoardTab(StandingsSnapshot s, int boardNum, bool isTT) {
    final crossTable = s.crossTableData[boardNum] ?? [];
    final standings = s.boardStandings[boardNum] ?? [];

    if (crossTable.isEmpty && standings.isEmpty) {
      return Center(
        child: Text(
          'Немає даних',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final verticalController = ScrollController();
        final horizontalController = ScrollController();
        return Scrollbar(
          thumbVisibility: true,
          controller: verticalController,
          child: Scrollbar(
            thumbVisibility: true,
            controller: horizontalController,
            notificationPredicate: (notification) => notification.depth == 1,
            child: SingleChildScrollView(
              controller: verticalController,
              child: SingleChildScrollView(
                controller: horizontalController,
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: constraints.maxWidth,
                  ),
                  child: _buildCombinedBoardTable(crossTable, standings, isTT),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Wraps a cell widget with bold border on specified sides to highlight the result grid perimeter.
  Widget _boldBorderCell(Widget child, {bool left = false, bool right = false, bool top = false, bool bottom = false}) {
    const boldWidth = 2.0;
    const boldColor = Colors.black;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: left ? const BorderSide(color: boldColor, width: boldWidth) : BorderSide.none,
          right: right ? const BorderSide(color: boldColor, width: boldWidth) : BorderSide.none,
          top: top ? const BorderSide(color: boldColor, width: boldWidth) : BorderSide.none,
          bottom: bottom ? const BorderSide(color: boldColor, width: boldWidth) : BorderSide.none,
        ),
      ),
      child: child,
    );
  }

  Widget _buildCombinedBoardTable(
    List<CrossTablePlayerRow> crossTable,
    List<StandingsPlayerRow> standings,
    bool isTT,
  ) {
    final n = crossTable.length;
    if (n == 0) return const SizedBox.shrink();

    final headerStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54);
    final cellStyle = TextStyle(fontSize: 12, color: Colors.black87);
    final headerBg = Colors.grey.shade100;
    final oddRowBg = Colors.grey.shade50;

    // Column layout: №к | Команда | ПІБ | [n result cols] | Бали | Ігор | ПІБ | Команда | Бали | Місце
    // Indices:        0     1       2     3..n+2             n+3    n+4    n+5    n+6     n+7    n+8
    final columnWidths = <int, TableColumnWidth>{};
    // Team and name columns expand to fill available space
    columnWidths[1] = const FlexColumnWidth(1); // Команда (cross)
    columnWidths[2] = const FlexColumnWidth(2); // ПІБ (cross)
    columnWidths[n + 5] = const FlexColumnWidth(2); // ПІБ (standings)
    columnWidths[n + 6] = const FlexColumnWidth(1); // Команда (standings)

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Table(
          border: TableBorder(
            top: BorderSide(color: Colors.grey.shade300, width: 1),
            bottom: BorderSide(color: Colors.grey.shade300, width: 1),
            left: BorderSide(color: Colors.grey.shade300, width: 1),
            right: BorderSide(color: Colors.grey.shade300, width: 1),
            horizontalInside: const BorderSide(color: Color(0xFF000000), width: 1),
            verticalInside: const BorderSide(color: Color(0xFF000000), width: 1),
          ),
          defaultColumnWidth: const IntrinsicColumnWidth(),
          columnWidths: {
            1: const FlexColumnWidth(1), // Команда (cross)
            2: const FlexColumnWidth(2), // ПІБ (cross)
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            // Header row
            TableRow(
              decoration: BoxDecoration(color: headerBg),
              children: [
                _tableCell('№к', style: headerStyle),
                _tableCell('Команда', style: headerStyle, minWidth: 70),
                _tableCell('ПІБ', style: headerStyle, minWidth: 130),
                for (int i = 0; i < n; i++)
                  _verticalHeaderCell(number: crossTable[i].teamNumber ?? (i + 1), surname: crossTable[i].playerName, style: headerStyle),
                _tableCell('Бали', style: headerStyle),
                _tableCell('Ігор', style: headerStyle),
              ],
            ),
            // Data rows
            for (int i = 0; i < n; i++)
              TableRow(
                decoration: i.isEven ? null : BoxDecoration(color: oddRowBg),
                children: [
                  _tableCell('${crossTable[i].teamNumber ?? ''}', style: cellStyle.copyWith(color: Colors.grey.shade600, fontSize: 11)),
                  _tableCell(crossTable[i].teamName, style: cellStyle, minWidth: 70, leftAlign: true),
                  _tableCell(crossTable[i].playerName, style: cellStyle, minWidth: 130, leftAlign: true),
                  for (int j = 0; j < n; j++)
                    (i == j)
                      ? _diagonalCell()
                      : _resultCell(crossTable[i].results[j], crossTable[i].details[j], isTT),
                  _tableCell(
                    _formatPts(crossTable[i].points),
                    style: cellStyle.copyWith(fontWeight: FontWeight.bold),
                  ),
                  _tableCell('${crossTable[i].gamesPlayed}', style: cellStyle),
                ],
              ),
          ],
        ),
        const SizedBox(width: 4),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black, width: 2),
          ),
          child: Table(
            border: TableBorder(
              horizontalInside: const BorderSide(color: Color(0xFF000000), width: 1),
              verticalInside: const BorderSide(color: Color(0xFF000000), width: 1),
            ),
            defaultColumnWidth: const IntrinsicColumnWidth(),
            columnWidths: {
              0: const FlexColumnWidth(2), // ПІБ (standings)
              1: const FlexColumnWidth(1), // Команда (standings)
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                decoration: BoxDecoration(color: headerBg),
                children: [
                  _tableCell('ПІБ', style: headerStyle, minWidth: 130),
                  _tableCell('Команда', style: headerStyle, minWidth: 90),
                  _tableCell('Бали', style: headerStyle),
                  _tableCell('Місце', style: headerStyle),
                ],
              ),
              for (int i = 0; i < n; i++)
                TableRow(
                  decoration: i.isEven ? null : BoxDecoration(color: oddRowBg),
                  children: [
                    if (i < standings.length) ...[
                      _tableCell(standings[i].playerName, style: cellStyle, minWidth: 130, leftAlign: true),
                      _tableCell(standings[i].teamName, style: cellStyle, minWidth: 90, leftAlign: true),
                      _tableCell(
                        _formatPts(standings[i].displayPoints),
                        style: cellStyle.copyWith(fontWeight: FontWeight.bold),
                      ),
                      _placeCell(standings[i].place, cellStyle),
                    ] else ...[
                      _tableCell('', style: cellStyle, minWidth: 130),
                      _tableCell('', style: cellStyle, minWidth: 90),
                      _tableCell('', style: cellStyle),
                      _tableCell('', style: cellStyle),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTeamsTab(StandingsSnapshot s, bool isTT) {
    final crossTable = s.teamCrossTableData;
    final standings = s.teamStandings;

    if (crossTable.isEmpty && standings.isEmpty) {
      return Center(
        child: Text(
          'Немає даних',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final verticalController = ScrollController();
        final horizontalController = ScrollController();
        return Scrollbar(
          thumbVisibility: true,
          controller: verticalController,
          child: Scrollbar(
            thumbVisibility: true,
            controller: horizontalController,
            notificationPredicate: (notification) => notification.depth == 1,
            child: SingleChildScrollView(
              controller: verticalController,
              child: SingleChildScrollView(
                controller: horizontalController,
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: constraints.maxWidth,
                  ),
                  child: _buildTeamCrossTable(crossTable, standings, isTT),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTeamCrossTable(
    List<CrossTableTeamRow> crossTable,
    List<StandingsTeamRow> standings,
    bool isTT,
  ) {
    final n = crossTable.length;
    if (n == 0) return const SizedBox.shrink();

    final headerStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54);
    final cellStyle = TextStyle(fontSize: 12, color: Colors.black87);
    final headerBg = Colors.grey.shade100;
    final oddRowBg = Colors.grey.shade50;

    // Column layout: № | Команда | [n result cols] | Очки | Команда | Очки | Місце
    // Indices:       0     1      2..n+1              n+2    n+3      n+4    n+5
    final teamColumnWidths = <int, TableColumnWidth>{};
    teamColumnWidths[1] = const FlexColumnWidth(2); // Команда (cross)
    teamColumnWidths[n + 3] = const FlexColumnWidth(2); // Команда (standings)

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Table(
          border: TableBorder(
            top: BorderSide(color: Colors.grey.shade300, width: 1),
            bottom: BorderSide(color: Colors.grey.shade300, width: 1),
            left: BorderSide(color: Colors.grey.shade300, width: 1),
            right: BorderSide(color: Colors.grey.shade300, width: 1),
            horizontalInside: const BorderSide(color: Color(0xFF000000), width: 1),
            verticalInside: const BorderSide(color: Color(0xFF000000), width: 1),
          ),
          defaultColumnWidth: const IntrinsicColumnWidth(),
          columnWidths: {1: const FlexColumnWidth(2)}, // Команда (cross)
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              decoration: BoxDecoration(color: headerBg),
              children: [
                _tableCell('№', style: headerStyle),
                _tableCell('Команда', style: headerStyle, minWidth: 140),
                for (int i = 0; i < n; i++)
                  _verticalHeaderCell(
                    number: crossTable[i].teamNumber ?? (i + 1),
                    surname: crossTable[i].teamName,
                    style: headerStyle,
                  ),
                _tableCell('Очки', style: headerStyle),
              ],
            ),
            for (int i = 0; i < n; i++)
              TableRow(
                decoration: i.isEven ? null : BoxDecoration(color: oddRowBg),
                children: [
                  _tableCell('${crossTable[i].teamNumber ?? (i + 1)}', style: cellStyle),
                  _tableCell(crossTable[i].teamName, style: cellStyle, minWidth: 140, leftAlign: true),
                  for (int j = 0; j < n; j++)
                    (i == j)
                      ? _diagonalCell()
                      : _teamMatchCell(crossTable[i].matchPoints[j]),
                  _tableCell(
                    _formatPts(crossTable[i].totalPoints),
                    style: cellStyle.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(width: 4),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black, width: 2),
          ),
          child: Table(
            border: TableBorder(
              horizontalInside: const BorderSide(color: Color(0xFF000000), width: 1),
              verticalInside: const BorderSide(color: Color(0xFF000000), width: 1),
            ),
            defaultColumnWidth: const IntrinsicColumnWidth(),
            columnWidths: {0: const FlexColumnWidth(2)}, // Команда (standings)
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                decoration: BoxDecoration(color: headerBg),
                children: [
                  _tableCell('Команда', style: headerStyle, minWidth: 140),
                  _tableCell('Очки', style: headerStyle),
                  _tableCell('Місце', style: headerStyle),
                ],
              ),
              for (int i = 0; i < n; i++)
                TableRow(
                  decoration: i.isEven ? null : BoxDecoration(color: oddRowBg),
                  children: [
                    if (i < standings.length) ...[
                      _tableCell(standings[i].teamName, style: cellStyle, minWidth: 140, leftAlign: true),
                      _tableCell(
                        _formatPts(standings[i].points),
                        style: cellStyle.copyWith(fontWeight: FontWeight.bold),
                      ),
                      _placeCell(standings[i].place, cellStyle),
                    ] else ...[
                      _tableCell('', style: cellStyle, minWidth: 140),
                      _tableCell('', style: cellStyle),
                      _tableCell('', style: cellStyle),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _resultCell(double? result, String? detail, bool isTT) {
    String text;
    if (isTT && detail != null && detail.isNotEmpty) {
      // Show set score like "2:0"
      final sets = detail.split(' ');
      int rowWins = 0;
      int colWins = 0;
      for (final s in sets) {
        final parts = s.split(':');
        if (parts.length != 2) continue;
        final a = int.tryParse(parts[0]) ?? 0;
        final b = int.tryParse(parts[1]) ?? 0;
        if (a > b) rowWins++;
        else if (b > a) colWins++;
      }
      text = '$rowWins:$colWins';
    } else if (result == null) {
      text = '';
    } else if (result == 1.0) {
      text = '1';
    } else if (result == 0.0) {
      text = '0';
    } else if (result == 0.5) {
      text = '½';
    } else {
      text = '';
    }

    Color? bgColor;
    if (result == 1.0) bgColor = Colors.green.shade50;
    else if (result == 0.0 && result != null) bgColor = Colors.red.shade50;
    else if (result == 0.5) bgColor = Colors.amber.shade50;

    return Container(
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      color: bgColor ?? Colors.transparent,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      child: text.isEmpty
          ? const SizedBox.shrink()
          : Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: result == 1.0
                    ? Colors.green.shade700
                    : result == 0.0 && result != null
                        ? Colors.red.shade700
                        : result == 0.5
                            ? Colors.amber.shade800
                            : Colors.black87,
              ),
            ),
    );
  }

  Widget _teamMatchCell(double? pts) {
    if (pts == null) {
      return Container(
        constraints: const BoxConstraints(minWidth: 40, minHeight: 28),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
        child: Text('—', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
      );
    }

    Color? bgColor;
    if (pts == 2.0) bgColor = Colors.green.shade50;
    else if (pts == 0.0) bgColor = Colors.red.shade50;
    else if (pts == 1.0) bgColor = Colors.amber.shade50;

    return Container(
      constraints: const BoxConstraints(minWidth: 40, minHeight: 28),
      color: bgColor ?? Colors.transparent,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      child: Text(
        '${pts.toInt()}',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: pts == 2.0
              ? Colors.green.shade700
              : pts == 0.0
                  ? Colors.red.shade700
                  : Colors.amber.shade800,
        ),
      ),
    );
  }

  Widget _placeCell(int place, TextStyle cellStyle) {
    final isTopThree = place <= 3;
    Color? bgColor;
    Color? textColor;
    if (place == 1) {
      bgColor = Colors.amber.shade50;
      textColor = Colors.amber.shade800;
    } else if (place == 2) {
      bgColor = Colors.blueGrey.shade50;
      textColor = Colors.blueGrey.shade700;
    } else if (place == 3) {
      bgColor = Colors.orange.shade50;
      textColor = Colors.orange.shade700;
    }

    return Container(
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      color: bgColor ?? Colors.transparent,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      child: Text(
        '$place',
        style: cellStyle.copyWith(
          fontWeight: FontWeight.bold,
          fontSize: isTopThree ? 14 : 12,
          color: textColor,
        ),
      ),
    );
  }

  Widget _tableCell(String text, {TextStyle? style, double? minWidth, bool leftAlign = false}) {
    return Container(
      constraints: minWidth != null ? BoxConstraints(minWidth: minWidth) : null,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      alignment: leftAlign ? Alignment.centerLeft : Alignment.center,
      child: Text(text, textAlign: leftAlign ? TextAlign.left : TextAlign.center, style: style),
    );
  }

  Widget _verticalHeaderCell({required int number, required String surname, TextStyle? style}) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.bottom,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RotatedBox(
              quarterTurns: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  surname,
                  style: style,
                  softWrap: false,
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text('$number', style: style),
          ],
        ),
      ),
    );
  }

  Widget _diagonalCell() {
    return Container(
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      color: Colors.grey.shade800,
    );
  }

  String _formatPts(double pts) {
    if (pts == pts.roundToDouble()) return pts.toStringAsFixed(0);
    String s = pts.toStringAsFixed(2);
    if (s.endsWith('0')) s = s.substring(0, s.length - 1);
    return s;
  }
}
