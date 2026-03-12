import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
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

    // Listen for updates from main window
    widget.controller.setWindowMethodHandler((call) async {
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
      home: _StandingsDisplay(snapshot: _snapshot),
    );
  }
}

class _StandingsDisplay extends StatelessWidget {
  final StandingsSnapshot? snapshot;
  const _StandingsDisplay({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    if (snapshot == null) {
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

    final s = snapshot!;
    final isTT = s.tType == 11;

    return Scaffold(
      body: DefaultTabController(
        length: s.boardCount + 1,
        child: Column(
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
                ],
              ),
            ),
            // Sub-tabs
            Container(
              color: Colors.indigo.shade50,
              child: TabBar(
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
                children: [
                  for (int i = 1; i <= s.boardCount; i++)
                    _buildBoardStandings(s.boardStandings[i] ?? [], isTT),
                  _buildTeamStandings(s.teamStandings, isTT),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBoardStandings(List<StandingsPlayerRow> rows, bool isTT) {
    if (rows.isEmpty) {
      return Center(
        child: Text(
          'Немає даних',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
              columnSpacing: 24,
              columns: [
                const DataColumn(
                    label: Text('Місце',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                const DataColumn(
                    label: Text('ПІБ',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                const DataColumn(
                    label: Text('Команда',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                const DataColumn(
                    label: Text('Бали',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    numeric: true),
                const DataColumn(
                    label: Text('Ігор',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    numeric: true),
                if (!isTT)
                  const DataColumn(
                      label: Text('К.Б.',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      numeric: true),
                if (isTT) ...[
                  const DataColumn(
                      label: Text('М.З.',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      numeric: true),
                  const DataColumn(
                      label: Text('М.П.',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      numeric: true),
                ],
              ],
              rows: rows.map((r) {
                final isTopThree = r.place <= 3;
                return DataRow(
                  color: isTopThree
                      ? WidgetStateProperty.all(
                          r.place == 1
                              ? Colors.amber.shade50
                              : r.place == 2
                                  ? Colors.grey.shade100
                                  : Colors.orange.shade50,
                        )
                      : null,
                  cells: [
                    DataCell(Text(
                      '${r.place}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: isTopThree ? 16 : 14,
                        color: r.place == 1
                            ? Colors.amber.shade800
                            : r.place == 2
                                ? Colors.grey.shade700
                                : r.place == 3
                                    ? Colors.orange.shade700
                                    : null,
                      ),
                    )),
                    DataCell(Text(r.playerName)),
                    DataCell(Text(r.teamName,
                        style: TextStyle(color: Colors.grey.shade600))),
                    DataCell(Text(
                      _formatPts(r.displayPoints),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    )),
                    DataCell(Text('${r.gamesPlayed}')),
                    if (!isTT)
                      DataCell(
                          Text(_formatPts(r.bergerCoefficient ?? 0))),
                    if (isTT) ...[
                      DataCell(Text('${r.ballsScored ?? 0}')),
                      DataCell(Text('${r.ballsConceded ?? 0}')),
                    ],
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTeamStandings(List<StandingsTeamRow> rows, bool isTT) {
    if (rows.isEmpty) {
      return Center(
        child: Text(
          'Немає даних',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
              columnSpacing: 24,
              columns: const [
                DataColumn(
                    label: Text('Місце',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('Команда',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('Очки',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    numeric: true),
                DataColumn(
                    label: Text('Додатковий показник',
                        style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: rows.map((r) {
                final isTopThree = r.place <= 3;
                return DataRow(
                  color: isTopThree
                      ? WidgetStateProperty.all(
                          r.place == 1
                              ? Colors.amber.shade50
                              : r.place == 2
                                  ? Colors.grey.shade100
                                  : Colors.orange.shade50,
                        )
                      : null,
                  cells: [
                    DataCell(Text(
                      '${r.place}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: isTopThree ? 16 : 14,
                        color: r.place == 1
                            ? Colors.amber.shade800
                            : r.place == 2
                                ? Colors.grey.shade700
                                : r.place == 3
                                    ? Colors.orange.shade700
                                    : null,
                      ),
                    )),
                    DataCell(Text(r.teamName,
                        style: const TextStyle(fontWeight: FontWeight.w500))),
                    DataCell(Text(
                      _formatPts(r.points),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    )),
                    DataCell(Text(r.tiebreaker,
                        style: TextStyle(color: Colors.grey.shade600))),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  String _formatPts(double pts) {
    if (pts == pts.roundToDouble()) return pts.toStringAsFixed(0);
    String s = pts.toStringAsFixed(2);
    if (s.endsWith('0')) s = s.substring(0, s.length - 1);
    return s;
  }
}
