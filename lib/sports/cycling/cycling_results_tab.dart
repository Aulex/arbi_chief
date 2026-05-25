import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'cycling_model.dart';
import 'cycling_providers.dart';
import '../../viewmodels/shared_providers.dart';
import '../../viewmodels/tournament_viewmodel.dart';

/// Main tab for entering and viewing cycling results per category.
class CyclingResultsTab extends ConsumerStatefulWidget {
  final int tId;

  /// Outer (tournament-level) tab controller, used by the inline-entry
  /// 'Всі учасники' subtab to also refresh when the user returns to the
  /// Results section from a sibling top-level tab (Players, Teams, …).
  final TabController? outerTabController;

  /// Index of the Results tab inside [outerTabController].
  final int outerTabIndex;

  const CyclingResultsTab({
    super.key,
    required this.tId,
    this.outerTabController,
    this.outerTabIndex = 0,
  });

  @override
  ConsumerState<CyclingResultsTab> createState() =>
      _CyclingResultsTabState();
}

class _CyclingResultsTabState extends ConsumerState<CyclingResultsTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _categories = [
    CyclingCategory.m35,
    CyclingCategory.m49,
    CyclingCategory.m50,
    CyclingCategory.f35,
    CyclingCategory.f49,
  ];

  /// Tab count: 1 (Всі учасники) + per-category.
  int get _tabCount => 1 + _categories.length;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCount, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Category tabs
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: Colors.grey.shade300, width: 1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: Colors.indigo,
            indicatorColor: Colors.indigo,
            indicatorWeight: 2,
            tabAlignment: TabAlignment.start,
            tabs: [
              const Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.groups_outlined, size: 18),
                    SizedBox(width: 6),
                    Text('Всі учасники'),
                  ],
                ),
              ),
              ..._categories.map((c) => Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          c.isMale
                              ? Icons.man_outlined
                              : Icons.woman_outlined,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(c.label),
                      ],
                    ),
                  )),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _AllParticipantsView(
                tId: widget.tId,
                tabController: _tabController,
                outerTabController: widget.outerTabController,
                outerTabIndex: widget.outerTabIndex,
              ),
              ..._categories.map((c) => _CategoryResultsView(
                    tId: widget.tId,
                    category: c,
                  )),
            ],
          ),
        ),
      ],
    );
  }
}

/// Sortable columns in the per-category results view.
enum _CategorySortKey { number, name, team, age, time, place }

/// Shows the results list for a single cycling category with add/edit/delete.
class _CategoryResultsView extends ConsumerStatefulWidget {
  final int tId;
  final CyclingCategory category;

  const _CategoryResultsView({required this.tId, required this.category});

  @override
  ConsumerState<_CategoryResultsView> createState() =>
      _CategoryResultsViewState();
}

class _CategoryResultsViewState extends ConsumerState<_CategoryResultsView>
    with AutomaticKeepAliveClientMixin {
  List<RankedCyclingResult> _standings = [];
  bool _loading = true;
  int? _hoveredRow;
  _CategorySortKey _sortKey = _CategorySortKey.place;
  bool _sortAsc = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadStandings();
  }

  Future<void> _loadStandings() async {
    setState(() => _loading = true);
    final svc = ref.read(cyclingServiceProvider);
    final standings =
        await svc.getCategoryParticipants(widget.tId, widget.category);
    if (mounted) {
      setState(() {
        _standings = standings;
        _loading = false;
      });
    }
  }

  Future<void> _addResult() async {
    final result = await showDialog<CyclingResult>(
      context: context,
      builder: (ctx) => _CyclingResultDialog(
        tId: widget.tId,
        category: widget.category,
      ),
    );
    if (result != null) {
      final svc = ref.read(cyclingServiceProvider);
      await svc.saveResult(result);
      await _loadStandings();
    }
  }

  Future<void> _editResult(RankedCyclingResult ranked) async {
    final result = await showDialog<CyclingResult>(
      context: context,
      builder: (ctx) => _CyclingResultDialog(
        tId: widget.tId,
        category: widget.category,
        existing: ranked.result,
        prefilledPlayerId: ranked.pendingPlayerId,
        prefilledTeamId: ranked.pendingTeamId,
      ),
    );
    if (result != null) {
      final svc = ref.read(cyclingServiceProvider);
      await svc.saveResult(result);
      await _loadStandings();
    }
  }

  Future<void> _deleteResult(RankedCyclingResult ranked) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Видалити результат?'),
        content: Text('Видалити результат ${ranked.playerName}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Скасувати')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Видалити')),
        ],
      ),
    );
    if (confirmed == true) {
      final svc = ref.read(cyclingServiceProvider);
      await svc.deleteResult(ranked.result!.id!);
      await _loadStandings();
    }
  }

  Future<void> _clearResults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Очистити всі результати?'),
        content: Text('Ви впевнені, що хочете видалити всі результати для категорії ${widget.category.fullName}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Скасувати')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Очистити')),
        ],
      ),
    );
    if (confirmed == true) {
      final svc = ref.read(cyclingServiceProvider);
      await svc.clearCategoryResults(widget.tId, widget.category);
      await _loadStandings();
    }
  }

  void _showBulkImportDialog() {
    final textC = TextEditingController();
    List<_ParsedResult> preview = [];
    bool importing = false;
    bool parsing = false;
    int parseToken = 0;

    Future<void> updatePreview(
        String text, Function(void Function()) setST) async {
      final myToken = ++parseToken;
      if (text.trim().isEmpty) {
        setST(() => preview = []);
        return;
      }
      setST(() => parsing = true);
      final svc = ref.read(cyclingServiceProvider);
      final cleanText = text.replaceAll(
          RegExp(
              r'[\u00A0\u2000-\u200B\u200C\u200D\u202F\u205F\u2060\u3000\uFEFF]'),
          ' ');
      final lines =
          cleanText.split('\n').where((l) => l.trim().isNotEmpty).toList();
      final results = <_ParsedResult>[];

      for (final line in lines) {
        final parts = line.split('\t').map((s) => s.trim()).toList();
        if (parts.length < 5) continue;

        final fullName = parts[0];
        final teamName = parts[1];
        final hour = int.tryParse(parts[2]) ?? -1;
        final min = int.tryParse(parts[3]) ?? -1;
        final sec = int.tryParse(parts[4]) ?? -1;

        final timeValid = hour >= 0 &&
            min >= 0 && min <= 59 &&
            sec >= 0 && sec <= 59 &&
            (hour + min + sec) > 0;

        final ids = await svc.findParticipant(widget.tId, fullName, teamName);
        if (myToken != parseToken) return; // a newer parse has started
        results.add(_ParsedResult(
          fullName: fullName,
          teamName: teamName,
          hour: hour < 0 ? 0 : hour,
          min: min < 0 ? 0 : min,
          sec: sec < 0 ? 0 : sec,
          playerId: ids.playerId,
          teamId: ids.teamId,
          timeValid: timeValid,
        ));
      }
      if (myToken != parseToken) return;
      setST(() {
        preview = results;
        parsing = false;
      });
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setST) => AlertDialog(
          title: const Text('Імпорт результатів (Excel)'),
          content: SizedBox(
            width: 700,
            height: 500,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Вставте дані з Excel (5 стовпців):\nПІБ | Команда | Год | Хв | Сек',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: textC,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (val) => updatePreview(val, setST),
                ),
                const SizedBox(height: 12),
                const Text('Попередній перегляд:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: parsing
                        ? const Center(child: CircularProgressIndicator())
                        : preview.isEmpty
                            ? const Center(
                                child: Text('Немає даних для імпорту',
                                    style: TextStyle(color: Colors.grey)))
                            : ListView.separated(
                                padding: const EdgeInsets.all(8),
                                itemCount: preview.length,
                                separatorBuilder: (_, __) => const Divider(),
                                itemBuilder: (ctx, i) {
                                  final p = preview[i];
                                  final ok = p.teamId != null &&
                                      p.playerId != null &&
                                      p.timeValid;
                                  return Row(
                                    children: [
                                      Icon(
                                        ok
                                            ? Icons.check_circle
                                            : Icons.error,
                                        color:
                                            ok ? Colors.green : Colors.red,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(p.fullName,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: p.playerId == null
                                                      ? Colors.red
                                                      : null,
                                                )),
                                            Text(
                                                '${p.teamName} • ${p.hour}:${p.min.toString().padLeft(2, '0')}:${p.sec.toString().padLeft(2, '0')}',
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color: (p.teamId == null ||
                                                            !p.timeValid)
                                                        ? Colors.red
                                                        : Colors
                                                            .grey.shade600)),
                                          ],
                                        ),
                                      ),
                                      if (!ok)
                                        Text(
                                          p.teamId == null
                                              ? 'Команду не знайдено'
                                              : p.playerId == null
                                                  ? 'Учасника не знайдено'
                                                  : 'Некоректний час',
                                          style: const TextStyle(
                                              fontSize: 10, color: Colors.red),
                                        ),
                                    ],
                                  );
                                },
                              ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Скасувати'),
            ),
            FilledButton(
              onPressed: (importing ||
                      preview.isEmpty ||
                      !preview.any((p) =>
                          p.teamId != null &&
                          p.playerId != null &&
                          p.timeValid))
                  ? null
                  : () async {
                      setST(() => importing = true);
                      try {
                        final svc = ref.read(cyclingServiceProvider);
                        int count = 0;
                        final resultsToSave = <CyclingResult>[];
                        for (final p in preview) {
                          if (p.teamId != null &&
                              p.playerId != null &&
                              p.timeValid) {
                            resultsToSave.add(CyclingResult(
                              tournamentId: widget.tId,
                              category: widget.category,
                              playerId: p.playerId!,
                              teamId: p.teamId!,
                              timeHour: p.hour,
                              timeMin: p.min,
                              timeSec: p.sec,
                            ));
                            count++;
                          }
                        }
                        if (resultsToSave.isNotEmpty) {
                          await svc.saveResults(resultsToSave);
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        _loadStandings();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content:
                                    Text('Імпортовано результатів: $count')),
                          );
                        }
                      } catch (e) {
                        setST(() => importing = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text('Помилка імпорту: $e')),
                          );
                        }
                      }
                    },
              child: Text(importing ? 'Імпорт...' : 'Імпортувати'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Re-load if a global refresh was triggered (e.g. from the 'All participants' tab)
    ref.listen(resultsRefreshProvider, (prev, next) {
      if (prev != next) {
        _loadStandings();
      }
    });

    if (_loading) return const Center(child: CircularProgressIndicator());

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 500;

        return Column(
          children: [
            // Header: category name (max left) | buttons (max right)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    '${widget.category.fullName} (${_standings.length})',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: _showBulkImportDialog,
                      icon: const Icon(Icons.upload_file, size: 18),
                      label: const Text('Імпорт'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.indigo.shade400,
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _addResult,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Додати'),
                    ),
                    FilledButton.icon(
                      onPressed: _clearResults,
                      icon: const Icon(Icons.clear_all, size: 18),
                      label: const Text('Очистити'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red.shade400,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Results table
            Expanded(
              child: _standings.isEmpty
                  ? Center(
                      child: Text(
                        'Немає результатів',
                        style: TextStyle(
                            color: Colors.grey.shade500, fontSize: 14),
                      ),
                    )
                  : Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        side: BorderSide(
                            color: Colors.grey.shade300, width: 1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: SingleChildScrollView(
                        child:
                            _buildResultsTable(constraints.maxWidth, isNarrow),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  void _toggleSort(_CategorySortKey key) {
    setState(() {
      if (_sortKey == key) {
        _sortAsc = !_sortAsc;
      } else {
        _sortKey = key;
        // Place defaults to ascending (1, 2, 3…); others default to ascending too.
        _sortAsc = true;
      }
    });
  }

  List<RankedCyclingResult> _sortedStandings() {
    int cmpInt(int? a, int? b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return a.compareTo(b);
    }
    int cmpStr(String? a, String? b) {
      final ae = a == null || a.trim().isEmpty;
      final be = b == null || b.trim().isEmpty;
      if (ae && be) return 0;
      if (ae) return 1;
      if (be) return -1;
      return a!.toLowerCase().compareTo(b!.toLowerCase());
    }
    final sorted = List<RankedCyclingResult>.from(_standings);
    sorted.sort((a, b) {
      int r;
      switch (_sortKey) {
        case _CategorySortKey.number:
          r = cmpInt(a.playerNumber, b.playerNumber);
          break;
        case _CategorySortKey.name:
          r = cmpStr(a.playerName, b.playerName);
          break;
        case _CategorySortKey.team:
          r = cmpStr(a.teamName, b.teamName);
          break;
        case _CategorySortKey.age:
          r = cmpInt(
            a.age > 0 ? a.age : null,
            b.age > 0 ? b.age : null,
          );
          break;
        case _CategorySortKey.time:
          r = cmpInt(
            a.result?.totalSec,
            b.result?.totalSec,
          );
          break;
        case _CategorySortKey.place:
          r = cmpInt(
            a.place > 0 ? a.place : null,
            b.place > 0 ? b.place : null,
          );
          break;
      }
      if (r != 0) return _sortAsc ? r : -r;
      return cmpStr(a.playerName, b.playerName);
    });
    return sorted;
  }

  Widget _buildResultsTable(double availableWidth, bool isNarrow) {
    final sorted = _sortedStandings();
    // Determine the № column width from the widest player number text.
    final tp = TextPainter(textDirection: TextDirection.ltr);
    double maxNumW = 0;
    final numStyle = TextStyle(
      fontWeight: FontWeight.bold,
      color: Colors.indigo.shade700,
      fontSize: 13,
    );
    for (final r in sorted) {
      final t = r.playerNumber != null ? '${r.playerNumber}' : '—';
      tp.text = TextSpan(text: t, style: numStyle);
      tp.layout();
      if (tp.width > maxNumW) maxNumW = tp.width;
    }
    // Header label '№' too (with room for the sort arrow).
    final headerStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w800,
      color: Colors.grey.shade900,
    );
    tp.text = TextSpan(text: '№', style: headerStyle);
    tp.layout();
    if (tp.width > maxNumW) maxNumW = tp.width;
    final numColW = maxNumW + 32; // padding + arrow space

    final actionsW = isNarrow ? 48.0 : 96.0;
    final placeW = 56.0;
    final timeW = 110.0;
    final ageW = 56.0;
    final hPad = isNarrow ? 8.0 : 16.0;

    Widget headerCell(
      String text, {
      double? width,
      int? flex,
      TextAlign align = TextAlign.left,
      required _CategorySortKey sortBy,
    }) {
      final isActive = _sortKey == sortBy;
      final activeStyle = isActive
          ? headerStyle.copyWith(color: Colors.indigo.shade700)
          : headerStyle;
      final mainAxis = align == TextAlign.center
          ? MainAxisAlignment.center
          : align == TextAlign.right
              ? MainAxisAlignment.end
              : MainAxisAlignment.start;
      final wrapped = InkWell(
        onTap: () => _toggleSort(sortBy),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: hPad / 2, vertical: 12),
          child: Row(
            mainAxisAlignment: mainAxis,
            children: [
              Flexible(
                child: Text(
                  text,
                  style: activeStyle,
                  textAlign: align,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isActive) ...[
                const SizedBox(width: 2),
                Icon(
                  _sortAsc ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                  size: 18,
                  color: Colors.indigo.shade700,
                ),
              ],
            ],
          ),
        ),
      );
      if (flex != null) return Expanded(flex: flex, child: wrapped);
      return SizedBox(width: width, child: wrapped);
    }

    return SizedBox(
      width: availableWidth,
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade400, width: 1.5),
              ),
            ),
            child: Row(
              children: [
                headerCell('№', width: numColW, align: TextAlign.left, sortBy: _CategorySortKey.number),
                headerCell('ПІБ', flex: 3, sortBy: _CategorySortKey.name),
                headerCell('Команда', flex: 2, sortBy: _CategorySortKey.team),
                headerCell('Вік', width: ageW, align: TextAlign.center, sortBy: _CategorySortKey.age),
                headerCell('Час', width: timeW, align: TextAlign.center, sortBy: _CategorySortKey.time),
                headerCell('М', width: placeW, align: TextAlign.center, sortBy: _CategorySortKey.place),
                SizedBox(width: actionsW),
              ],
            ),
          ),
          for (int i = 0; i < sorted.length; i++)
            _buildResultRow(i, sorted[i], numColW, ageW, timeW, placeW, actionsW, hPad, isNarrow),
        ],
      ),
    );
  }

  Widget _buildResultRow(
    int index,
    RankedCyclingResult r,
    double numColW,
    double ageW,
    double timeW,
    double placeW,
    double actionsW,
    double hPad,
    bool isNarrow,
  ) {
    final isHovered = _hoveredRow == index;
    final cellStyle = const TextStyle(fontSize: 13);
    final numStyle = TextStyle(
      fontWeight: FontWeight.bold,
      color: r.playerNumber != null
          ? Colors.indigo.shade700
          : Colors.grey.shade500,
      fontSize: 13,
    );

    Widget cell({double? width, int? flex, required Widget child, AlignmentGeometry align = Alignment.centerLeft}) {
      final wrapped = Padding(
        padding: EdgeInsets.symmetric(horizontal: hPad / 2, vertical: 10),
        child: Align(alignment: align, child: child),
      );
      if (flex != null) return Expanded(flex: flex, child: wrapped);
      return SizedBox(width: width, child: wrapped);
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredRow = index),
      onExit: (_) {
        if (_hoveredRow == index) setState(() => _hoveredRow = null);
      },
      child: Container(
        decoration: BoxDecoration(
          color: isHovered ? Colors.indigo.shade50 : null,
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade200, width: 1),
          ),
        ),
        child: Row(
          children: [
            cell(
              width: numColW,
              align: Alignment.centerLeft,
              child: Text(
                r.playerNumber != null ? '${r.playerNumber}' : '—',
                style: numStyle,
              ),
            ),
            cell(flex: 3, child: Text(r.playerName ?? '', style: cellStyle, overflow: TextOverflow.ellipsis)),
            cell(flex: 2, child: Text(r.teamName ?? '', style: cellStyle, overflow: TextOverflow.ellipsis)),
            cell(
              width: ageW,
              align: Alignment.center,
              child: Text('${r.age > 0 ? r.age : '-'}', style: cellStyle),
            ),
            cell(
              width: timeW,
              align: Alignment.center,
              child: Text(
                r.result != null ? r.result!.timeFormatted : '—',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
              ),
            ),
            cell(
              width: placeW,
              align: Alignment.center,
              child: Text(
                r.place > 0 ? '${r.place}' : '—',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: r.place > 0 && r.place <= 3
                      ? FontWeight.bold
                      : FontWeight.normal,
                  color: r.place == 1
                      ? Colors.amber.shade800
                      : r.place == 2
                          ? Colors.grey.shade600
                          : r.place == 3
                              ? Colors.brown
                              : null,
                ),
              ),
            ),
            SizedBox(
              width: actionsW,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                        r.result == null ? Icons.add_circle_outline : Icons.edit_outlined,
                        size: 18),
                    onPressed: () => _editResult(r),
                    tooltip: r.result == null ? 'Додати результат' : 'Редагувати',
                  ),
                  if (!isNarrow && r.result != null)
                    IconButton(
                      icon: Icon(Icons.delete_outline,
                          size: 18, color: Colors.red.shade400),
                      onPressed: () => _deleteResult(r),
                      tooltip: 'Видалити',
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog for adding/editing a cycling result.
class _CyclingResultDialog extends ConsumerStatefulWidget {
  final int tId;
  final CyclingCategory category;
  final CyclingResult? existing;
  final int? prefilledPlayerId;
  final int? prefilledTeamId;

  const _CyclingResultDialog({
    required this.tId,
    required this.category,
    this.existing,
    this.prefilledPlayerId,
    this.prefilledTeamId,
  });

  @override
  ConsumerState<_CyclingResultDialog> createState() =>
      _CyclingResultDialogState();
}

class _CyclingResultDialogState
    extends ConsumerState<_CyclingResultDialog> {
  final _formKey = GlobalKey<FormState>();
  final _hourCtrl = TextEditingController();
  final _minCtrl = TextEditingController();
  final _secCtrl = TextEditingController();

  List<({int teamId, String teamName})> _teams = [];
  List<({int playerId, String fullName, String? birthDate, int? gender})>
      _players = [];
  int? _selectedTeamId;
  int? _selectedPlayerId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _hourCtrl.text = widget.existing!.timeHour.toString();
      _minCtrl.text = widget.existing!.timeMin.toString();
      _secCtrl.text = widget.existing!.timeSec.toString();
      _selectedTeamId = widget.existing!.teamId;
      _selectedPlayerId = widget.existing!.playerId;
    } else {
      _hourCtrl.text = '0';
      if (widget.prefilledTeamId != null) {
        _selectedTeamId = widget.prefilledTeamId;
        _selectedPlayerId = widget.prefilledPlayerId;
      }
    }
    _loadTeams();
  }

  @override
  void dispose() {
    _hourCtrl.dispose();
    _minCtrl.dispose();
    _secCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTeams() async {
    final db = await ref.read(dbServiceProvider).database;
    final rows = await db.rawQuery('''
      SELECT DISTINCT t.team_id, t.team_name
      FROM CMP_PLAYER_TEAM pt
      JOIN CMP_TEAM t ON pt.team_id = t.team_id
      WHERE pt.t_id = ?
      ORDER BY t.team_name
    ''', [widget.tId]);
    final teams = rows
        .map((r) => (
              teamId: r['team_id'] as int,
              teamName: r['team_name'] as String,
            ))
        .toList();
    if (_selectedTeamId != null) {
      await _loadPlayers(_selectedTeamId!);
    }
    setState(() {
      _teams = teams;
      _loading = false;
    });
  }

  Future<void> _loadPlayers(int teamId) async {
    final svc = ref.read(cyclingServiceProvider);
    final players = await svc.getTeamPlayers(widget.tId, teamId);
    if (mounted) {
      setState(() => _players = players);
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedTeamId == null || _selectedPlayerId == null) return;

    final result = CyclingResult(
      id: widget.existing?.id,
      tournamentId: widget.tId,
      playerId: _selectedPlayerId!,
      teamId: _selectedTeamId!,
      category: widget.category,
      timeHour: int.tryParse(_hourCtrl.text) ?? 0,
      timeMin: int.tryParse(_minCtrl.text) ?? 0,
      timeSec: int.tryParse(_secCtrl.text) ?? 0,
    );
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    return AlertDialog(
      title: Text(isEdit ? 'Редагувати результат' : 'Додати результат'),
      content: SizedBox(
        width: 400,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.category.fullName,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 16),
                    // Team dropdown
                    DropdownButtonFormField<int>(
                      initialValue: _teams.any((t) => t.teamId == _selectedTeamId)
                          ? _selectedTeamId
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Команда',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: _teams
                          .map((t) => DropdownMenuItem(
                              value: t.teamId, child: Text(t.teamName)))
                          .toList(),
                      onChanged: (val) {
                        setState(() {
                          _selectedTeamId = val;
                          _selectedPlayerId = null;
                          _players = [];
                        });
                        if (val != null) _loadPlayers(val);
                      },
                      validator: (v) => v == null ? 'Оберіть команду' : null,
                    ),
                    const SizedBox(height: 12),
                    // Player dropdown
                    DropdownButtonFormField<int>(
                      key: ValueKey('player_$_selectedTeamId'),
                      initialValue: _players
                              .any((p) => p.playerId == _selectedPlayerId)
                          ? _selectedPlayerId
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Учасник',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: _players
                          .map((p) => DropdownMenuItem(
                              value: p.playerId,
                              child: Text(
                                '${p.fullName}${p.birthDate != null ? ' (${p.birthDate})' : ''}',
                              )))
                          .toList(),
                      onChanged: (val) =>
                          setState(() => _selectedPlayerId = val),
                      validator: (v) =>
                          v == null ? 'Оберіть учасника' : null,
                    ),
                    const SizedBox(height: 16),
                    // Time input
                    const Text('Час:',
                        style: TextStyle(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        SizedBox(
                          width: 80,
                          child: TextFormField(
                            controller: _hourCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Год',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            validator: (v) =>
                                v == null || v.isEmpty ? '!' : null,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text(':', style: TextStyle(fontSize: 20)),
                        ),
                        SizedBox(
                          width: 80,
                          child: TextFormField(
                            controller: _minCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Хв',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            validator: (v) {
                              if (v == null || v.isEmpty) return '!';
                              final min = int.tryParse(v);
                              if (min == null || min > 59) return '0-59';
                              return null;
                            },
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text(':', style: TextStyle(fontSize: 20)),
                        ),
                        SizedBox(
                          width: 80,
                          child: TextFormField(
                            controller: _secCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Сек',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            validator: (v) {
                              if (v == null || v.isEmpty) return '!';
                              final sec = int.tryParse(v);
                              if (sec == null || sec > 59) return '0-59';
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Скасувати'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(isEdit ? 'Зберегти' : 'Додати'),
        ),
      ],
    );
  }
}

class _ParsedResult {
  final String fullName;
  final String teamName;
  final int hour;
  final int min;
  final int sec;
  final int? playerId;
  final int? teamId;
  final bool timeValid;

  _ParsedResult({
    required this.fullName,
    required this.teamName,
    required this.hour,
    required this.min,
    required this.sec,
    this.playerId,
    this.teamId,
    this.timeValid = true,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// All-participants tab: inline category override + inline time entry
// ─────────────────────────────────────────────────────────────────────────────

/// Per-row mutable state for the inline-entry "Всі учасники" tab.
class _ParticipantRowState {
  final CyclingParticipantEntry entry;
  CyclingCategory selectedCategory;
  int? resultId;
  final TextEditingController numberC;
  final TextEditingController hourC;
  final TextEditingController minC;
  final TextEditingController secC;
  bool saving = false;
  String? error;

  // Snapshot of what's actually persisted; used to detect "no real change".
  CyclingCategory savedCategory;
  String savedNumber;
  String savedHour;
  String savedMin;
  String savedSec;

  _ParticipantRowState(this.entry)
      : selectedCategory = entry.assignedCategory
            ?? entry.resultCategory
            ?? entry.autoCategory,
        savedCategory = entry.assignedCategory
            ?? entry.resultCategory
            ?? entry.autoCategory,
        resultId = entry.resultId,
        numberC = TextEditingController(
          text: entry.playerNumber?.toString() ?? '',
        ),
        savedNumber = entry.playerNumber?.toString() ?? '',
        hourC = TextEditingController(
          text: entry.resultTotalSec != null
              ? (entry.resultTotalSec! ~/ 3600).toString()
              : '',
        ),
        minC = TextEditingController(
          text: entry.resultTotalSec != null
              ? ((entry.resultTotalSec! % 3600) ~/ 60)
                  .toString()
                  .padLeft(2, '0')
              : '',
        ),
        secC = TextEditingController(
          text: entry.resultTotalSec != null
              ? (entry.resultTotalSec! % 60).toString().padLeft(2, '0')
              : '',
        ),
        savedHour = entry.resultTotalSec != null
            ? (entry.resultTotalSec! ~/ 3600).toString()
            : '',
        savedMin = entry.resultTotalSec != null
            ? ((entry.resultTotalSec! % 3600) ~/ 60)
                .toString()
                .padLeft(2, '0')
            : '',
        savedSec = entry.resultTotalSec != null
            ? (entry.resultTotalSec! % 60).toString().padLeft(2, '0')
            : '';

  void dispose() {
    numberC.dispose();
    hourC.dispose();
    minC.dispose();
    secC.dispose();
  }

  bool get isDirty {
    if (selectedCategory != savedCategory) return true;
    if (numberC.text.trim() != savedNumber) return true;
    if (hourC.text.trim() != savedHour) return true;
    if (minC.text.trim() != savedMin) return true;
    if (secC.text.trim() != savedSec) return true;
    return false;
  }

  /// Parsed positive integer from numberC, or null if empty / invalid.
  int? get parsedNumber {
    final t = numberC.text.trim();
    if (t.isEmpty) return null;
    final n = int.tryParse(t);
    if (n == null || n <= 0) return null;
    return n;
  }

  /// Returns parsed (hour, min, sec) when all three fields are present and
  /// valid (min 0–59, sec 0–59, total > 0); otherwise null.
  ({int hour, int min, int sec})? parseTime() {
    final hour = int.tryParse(hourC.text.trim());
    final min = int.tryParse(minC.text.trim());
    final sec = int.tryParse(secC.text.trim());
    if (hour == null || min == null || sec == null) return null;
    if (min < 0 || min > 59) return null;
    if (sec < 0 || sec > 59) return null;
    if (hour + min + sec == 0) return null;
    return (hour: hour, min: min, sec: sec);
  }

  bool get isCleared =>
      hourC.text.trim().isEmpty &&
      minC.text.trim().isEmpty &&
      secC.text.trim().isEmpty;
}

/// Sortable columns in the 'Всі учасники' tab.
enum _ParticipantSortKey { number, name, team, age, category }

class _AllParticipantsView extends ConsumerStatefulWidget {
  final int tId;
  final TabController tabController;
  final TabController? outerTabController;
  final int outerTabIndex;
  const _AllParticipantsView({
    required this.tId,
    required this.tabController,
    this.outerTabController,
    this.outerTabIndex = 0,
  });

  @override
  ConsumerState<_AllParticipantsView> createState() =>
      _AllParticipantsViewState();
}

class _AllParticipantsViewState extends ConsumerState<_AllParticipantsView>
    with AutomaticKeepAliveClientMixin {
  static const int _myTabIndex = 0;

  List<_ParticipantRowState> _rows = [];
  bool _loading = true;
  bool _wasVisible = true; // starts visible on this tab
  _ParticipantSortKey _sortKey = _ParticipantSortKey.number;
  bool _sortAsc = true;
  int? _hoveredRow;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.tabController.addListener(_onTabChange);
    widget.outerTabController?.addListener(_onTabChange);
    _loadData();
  }

  @override
  void dispose() {
    widget.tabController.removeListener(_onTabChange);
    widget.outerTabController?.removeListener(_onTabChange);
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  /// Whether this tab is currently the user's focused view. The inner tab
  /// must be 'Всі учасники' AND, if there is an outer tournament-level
  /// controller, it must be on the Results tab.
  bool _isCurrentlyVisible() {
    final inner = widget.tabController;
    if (inner.indexIsChanging || inner.index != _myTabIndex) return false;
    final outer = widget.outerTabController;
    if (outer == null) return true;
    if (outer.indexIsChanging) return false;
    return outer.index == widget.outerTabIndex;
  }

  /// Re-fetches participants whenever the user returns to this tab — either
  /// by switching between Results subtabs or by navigating back to Results
  /// from a sibling tournament-level tab (Players, Teams, …). Waits for any
  /// in-flight row save first so we don't overwrite pending edits with a
  /// stale snapshot.
  void _onTabChange() {
    final visible = _isCurrentlyVisible();
    if (visible && !_wasVisible) {
      _wasVisible = true;
      _loadDataAfterPendingSaves();
    } else if (!visible && _wasVisible) {
      _wasVisible = false;
    }
  }

  Future<void> _loadDataAfterPendingSaves() async {
    // Saves are kicked off synchronously by Focus(onFocusChange) right
    // before the tab switch. Wait for them to settle so we don't read
    // stale data.
    while (_rows.any((r) => r.saving)) {
      if (!mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    if (!mounted) return;
    await _loadData();
  }

  bool _reloading = false;
  bool _pendingReload = false;

  Future<void> _loadData() async {
    // If a reload is already in flight, schedule a follow-up so we don't
    // discard a refresh triggered after newer data became available.
    if (_reloading) {
      _pendingReload = true;
      return;
    }
    _reloading = true;
    _pendingReload = false;
    try {
      final svc = ref.read(cyclingServiceProvider);
      final entries = await svc.getAllParticipants(widget.tId);
      if (!mounted) return;
      // Snapshot the old rows so we can dispose their controllers AFTER
      // the new tree is in place (avoids the brief "no data" frame and
      // the corresponding flicker).
      final oldRows = _rows;
      final rows = entries.map((e) => _ParticipantRowState(e)).toList();
      _sortRows(rows);
      setState(() {
        _rows = rows;
        _loading = false;
      });
      for (final r in oldRows) {
        r.dispose();
      }
    } finally {
      _reloading = false;
      if (_pendingReload) {
        _pendingReload = false;
        _loadData();
      }
    }
  }

  /// Sorts [rows] in-place per the current sort key + direction.
  /// Missing values (no number, no team, age 0, …) are always placed at
  /// the bottom regardless of sort direction.
  void _sortRows(List<_ParticipantRowState> rows) {
    int cmpInt(int? a, int? b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return a.compareTo(b);
    }
    int cmpStr(String a, String b) {
      final ae = a.trim().isEmpty;
      final be = b.trim().isEmpty;
      if (ae && be) return 0;
      if (ae) return 1;
      if (be) return -1;
      return a.toLowerCase().compareTo(b.toLowerCase());
    }
    final asc = _sortAsc;
    rows.sort((a, b) {
      int r;
      switch (_sortKey) {
        case _ParticipantSortKey.number:
          r = cmpInt(a.parsedNumber, b.parsedNumber);
          break;
        case _ParticipantSortKey.name:
          r = cmpStr(a.entry.fullName, b.entry.fullName);
          break;
        case _ParticipantSortKey.team:
          r = cmpStr(a.entry.teamName, b.entry.teamName);
          break;
        case _ParticipantSortKey.age:
          r = cmpInt(
            a.entry.age > 0 ? a.entry.age : null,
            b.entry.age > 0 ? b.entry.age : null,
          );
          break;
        case _ParticipantSortKey.category:
          r = a.selectedCategory.index.compareTo(b.selectedCategory.index);
          break;
      }
      if (r != 0) return asc ? r : -r;
      // Stable tiebreaker: name.
      return a.entry.fullName.toLowerCase()
          .compareTo(b.entry.fullName.toLowerCase());
    });
  }

  void _toggleSort(_ParticipantSortKey key) {
    setState(() {
      if (_sortKey == key) {
        _sortAsc = !_sortAsc;
      } else {
        _sortKey = key;
        _sortAsc = true;
      }
      _sortRows(_rows);
    });
  }

  Future<void> _saveRow(_ParticipantRowState row) async {
    if (!row.isDirty || row.saving) return;
    setState(() {
      row.saving = true;
      row.error = null;
    });
    final svc = ref.read(cyclingServiceProvider);
    final tournamentSvc = ref.read(tournamentServiceProvider);

    try {
      // 1) Persist the assigned-category override if it changed from auto.
      if (row.selectedCategory != row.savedCategory) {
        if (row.selectedCategory == row.entry.autoCategory) {
          await svc.clearAssignedCategory(
            playerId: row.entry.playerId, tId: widget.tId);
        } else {
          await svc.saveAssignedCategory(
            playerId: row.entry.playerId,
            tId: widget.tId,
            category: row.selectedCategory,
          );
        }
      }

      // 2) Persist the participant number if it changed.
      if (row.numberC.text.trim() != row.savedNumber) {
        final n = row.parsedNumber;
        if (n != null) {
          await tournamentSvc.savePlayerNumber(
            playerId: row.entry.playerId,
            tId: widget.tId,
            number: n,
          );
        } else if (row.numberC.text.trim().isEmpty) {
          await tournamentSvc.clearPlayerNumber(
            playerId: row.entry.playerId,
            tId: widget.tId,
          );
        } else {
          // Non-empty but unparseable — surface as an error and keep editing.
          setState(() {
            row.saving = false;
            row.error = 'Невірний номер';
          });
          return;
        }
      }

      // 3) Save / update / delete result based on field state.
      if (row.isCleared) {
        // User cleared all 3 fields → delete existing result if any.
        if (row.resultId != null) {
          await svc.deleteResult(row.resultId!);
          row.resultId = null;
        }
      } else {
        final parsed = row.parseTime();
        if (parsed != null) {
          final result = CyclingResult(
            id: row.resultId,
            tournamentId: widget.tId,
            playerId: row.entry.playerId,
            teamId: row.entry.teamId,
            category: row.selectedCategory,
            timeHour: parsed.hour,
            timeMin: parsed.min,
            timeSec: parsed.sec,
          );
          final id = await svc.saveResult(result);
          row.resultId = id;
        } else {
          // Partial / invalid time — keep the input as-is but don't save.
          // Surface the issue to the user.
          setState(() {
            row.saving = false;
            row.error = 'Невірний час';
          });
          return;
        }
      }

      // Snapshot the saved state so the next focus-out is a no-op until
      // the user actually changes something again.
      row.savedCategory = row.selectedCategory;
      row.savedNumber = row.numberC.text.trim();
      row.savedHour = row.hourC.text.trim();
      row.savedMin = row.minC.text.trim();
      row.savedSec = row.secC.text.trim();

      // Trigger a refresh for other tabs (category standings)
      ref.read(resultsRefreshProvider.notifier).increment();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        row.error = 'Помилка: $e';
      });
    } finally {
      if (mounted) setState(() => row.saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.groups_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'Немає учасників у турнірі',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Всі учасники (${_rows.length})',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          'Введіть час прямо у таблиці. Збереження відбувається при переході '
          'на інший рядок або вкладку. Хв 0–59, Сек 0–59.',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: Colors.grey.shade300, width: 1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: ListView.separated(
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1, color: Colors.grey.shade200),
                    itemBuilder: (context, i) => _buildRow(_rows[i], i),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static const double _wNumber = 56;
  static const double _wAge = 48;
  static const double _wCategory = 90;
  static const double _wTimeField = 56;
  static const double _wStatus = 28;

  Widget _buildHeader() {
    final st = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w800,
      color: Colors.grey.shade900,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        border: Border(bottom: BorderSide(color: Colors.grey.shade400, width: 1.5)),
      ),
      child: Row(
        children: [
          _sortableHeader(
            width: _wNumber,
            label: '№',
            style: st,
            key: _ParticipantSortKey.number,
            align: TextAlign.center,
          ),
          _sortableHeader(
            flex: 3,
            label: 'ПІБ',
            style: st,
            key: _ParticipantSortKey.name,
          ),
          _sortableHeader(
            flex: 2,
            label: 'Команда',
            style: st,
            key: _ParticipantSortKey.team,
          ),
          _sortableHeader(
            width: _wAge,
            label: 'Вік',
            style: st,
            key: _ParticipantSortKey.age,
            align: TextAlign.center,
          ),
          _sortableHeader(
            width: _wCategory,
            label: 'Категорія',
            style: st,
            key: _ParticipantSortKey.category,
            align: TextAlign.center,
          ),
          SizedBox(
            width: _wTimeField,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              child: Text('Год', style: st, textAlign: TextAlign.center),
            ),
          ),
          SizedBox(
            width: _wTimeField,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              child: Text('Хв', style: st, textAlign: TextAlign.center),
            ),
          ),
          SizedBox(
            width: _wTimeField,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              child: Text('Сек', style: st, textAlign: TextAlign.center),
            ),
          ),
          SizedBox(width: _wStatus, child: const SizedBox.shrink()),
        ],
      ),
    );
  }

  /// Builds a header cell that toggles sort by [key] on tap. Shows a small
  /// up/down arrow next to the label when [key] is the active sort.
  Widget _sortableHeader({
    double? width,
    int? flex,
    required String label,
    required TextStyle style,
    required _ParticipantSortKey key,
    TextAlign align = TextAlign.left,
  }) {
    final isActive = _sortKey == key;
    final content = InkWell(
      onTap: () => _toggleSort(key),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          mainAxisAlignment: align == TextAlign.center
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          children: [
            Flexible(
              child: Text(
                label,
                style: isActive
                    ? style.copyWith(color: Colors.indigo.shade700)
                    : style,
                textAlign: align,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: 2),
              Icon(
                _sortAsc ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                size: 16,
                color: Colors.indigo.shade700,
              ),
            ],
          ],
        ),
      ),
    );
    if (flex != null) return Expanded(flex: flex, child: content);
    return SizedBox(width: width, child: content);
  }

  Widget _buildRow(_ParticipantRowState row, int index) {
    final allowed = CyclingCategory.allowedCategoriesFor(row.entry.autoCategory);
    // Defensive: if a stored override is no longer allowed (e.g. rules changed),
    // include it in the items so the dropdown can still display the value.
    final items = {...allowed, row.selectedCategory}.toList();
    final overridden = row.selectedCategory != row.entry.autoCategory;
    final isHovered = _hoveredRow == index;

    return Focus(
      canRequestFocus: false,
      onFocusChange: (hasFocus) {
        if (!hasFocus) _saveRow(row);
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hoveredRow = index),
        onExit: (_) {
          if (_hoveredRow == index) setState(() => _hoveredRow = null);
        },
        child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        color: isHovered ? Colors.indigo.shade50 : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: _wNumber,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: TextField(
                  controller: row.numberC,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(5),
                  ],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo.shade700,
                    fontSize: 14,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(row.entry.fullName,
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(row.entry.teamName,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    overflow: TextOverflow.ellipsis),
              ),
            ),
            SizedBox(
              width: _wAge,
              child: Text(
                row.entry.age > 0 ? '${row.entry.age}' : '—',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            SizedBox(
              width: _wCategory,
              child: DropdownButtonHideUnderline(
                child: DropdownButton<CyclingCategory>(
                  isDense: true,
                  isExpanded: true,
                  value: row.selectedCategory,
                  items: items
                      .map((c) => DropdownMenuItem(
                            value: c,
                            child: Text(
                              c.label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight:
                                    c == row.entry.autoCategory
                                        ? FontWeight.normal
                                        : FontWeight.w600,
                                color: c == row.entry.autoCategory
                                    ? Colors.black87
                                    : Colors.deepOrange.shade700,
                              ),
                            ),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => row.selectedCategory = v);
                  },
                ),
              ),
            ),
            _buildTimeField(row.hourC, 2),
            _buildTimeField(row.minC, 2),
            _buildTimeField(row.secC, 2),
            SizedBox(
              width: _wStatus,
              child: row.saving
                  ? const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : row.error != null
                      ? Tooltip(
                          message: row.error!,
                          child: Icon(Icons.error_outline,
                              size: 18, color: Colors.red.shade400),
                        )
                      : overridden
                          ? Tooltip(
                              message:
                                  'Призначено в категорію ${row.selectedCategory.label} (авто: ${row.entry.autoCategory.label})',
                              child: Icon(Icons.swap_horiz,
                                  size: 18, color: Colors.deepOrange.shade400),
                            )
                          : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildTimeField(TextEditingController c, int maxLength) {
    return SizedBox(
      width: _wTimeField,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(maxLength),
          ],
          textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
          decoration: const InputDecoration(
            isDense: true,
            contentPadding:
                EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            border: OutlineInputBorder(),
          ),
        ),
      ),
    );
  }
}
