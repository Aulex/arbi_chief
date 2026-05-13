import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'athletics_model.dart';
import 'athletics_providers.dart';
import '../../viewmodels/shared_providers.dart';
import '../../viewmodels/tournament_viewmodel.dart';

/// Main tab for entering and viewing athletics results per category.
class AthleticsResultsTab extends ConsumerStatefulWidget {
  final int tId;

  /// Outer (tournament-level) tab controller, used by the inline-entry
  /// 'Всі учасники' subtab to also refresh when the user returns to the
  /// Results section from a sibling top-level tab (Players, Teams, …).
  final TabController? outerTabController;

  /// Index of the Results tab inside [outerTabController].
  final int outerTabIndex;

  const AthleticsResultsTab({
    super.key,
    required this.tId,
    this.outerTabController,
    this.outerTabIndex = 0,
  });

  @override
  ConsumerState<AthleticsResultsTab> createState() =>
      _AthleticsResultsTabState();
}

class _AthleticsResultsTabState extends ConsumerState<AthleticsResultsTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _categories = [
    AthleticsCategory.m35,
    AthleticsCategory.m49,
    AthleticsCategory.m50,
    AthleticsCategory.f35,
    AthleticsCategory.f49,
    AthleticsCategory.f50,
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

/// Shows the results list for a single athletics category with add/edit/delete.
class _CategoryResultsView extends ConsumerStatefulWidget {
  final int tId;
  final AthleticsCategory category;

  const _CategoryResultsView({required this.tId, required this.category});

  @override
  ConsumerState<_CategoryResultsView> createState() =>
      _CategoryResultsViewState();
}

class _CategoryResultsViewState extends ConsumerState<_CategoryResultsView>
    with AutomaticKeepAliveClientMixin {
  List<RankedAthleticsResult> _standings = [];
  bool _loading = true;
  Map<int, ({double men3000, double women1500})>? _customCoefficients;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadStandings();
  }

  Future<void> _loadStandings() async {
    setState(() => _loading = true);
    final svc = ref.read(athleticsServiceProvider);
    // Reload coefficients each time so edits in the settings tab are picked up.
    _customCoefficients = await svc.getCustomCoefficients(widget.tId);
    final standings = await svc.getCategoryStandings(
      widget.tId, widget.category,
      customCoefficients: _customCoefficients,
    );
    if (mounted) {
      setState(() {
        _standings = standings;
        _loading = false;
      });
    }
  }

  Future<void> _addResult() async {
    final result = await showDialog<AthleticsResult>(
      context: context,
      builder: (ctx) => _AthleticsResultDialog(
        tId: widget.tId,
        category: widget.category,
      ),
    );
    if (result != null) {
      final svc = ref.read(athleticsServiceProvider);
      await svc.saveResult(result);
      await _loadStandings();
    }
  }

  Future<void> _editResult(RankedAthleticsResult ranked) async {
    final result = await showDialog<AthleticsResult>(
      context: context,
      builder: (ctx) => _AthleticsResultDialog(
        tId: widget.tId,
        category: widget.category,
        existing: ranked.result,
      ),
    );
    if (result != null) {
      final svc = ref.read(athleticsServiceProvider);
      await svc.saveResult(result);
      await _loadStandings();
    }
  }

  Future<void> _deleteResult(RankedAthleticsResult ranked) async {
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
      final svc = ref.read(athleticsServiceProvider);
      await svc.deleteResult(ranked.result.id!);
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
      final svc = ref.read(athleticsServiceProvider);
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
      final svc = ref.read(athleticsServiceProvider);
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
        final min = int.tryParse(parts[2]) ?? -1;
        final sec = int.tryParse(parts[3]) ?? -1;
        final ms = int.tryParse(parts[4]) ?? -1;

        final timeValid = min >= 0 &&
            sec >= 0 && sec <= 59 &&
            ms >= 0 && ms <= 99 &&
            (min + sec + ms) > 0;

        final ids = await svc.findParticipant(widget.tId, fullName, teamName);
        if (myToken != parseToken) return; // a newer parse has started
        results.add(_ParsedResult(
          fullName: fullName,
          teamName: teamName,
          min: min < 0 ? 0 : min,
          sec: sec < 0 ? 0 : sec,
          ms: ms < 0 ? 0 : ms,
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
                  'Вставте дані з Excel (5 стовпців):\nПІБ | Команда | Хв | Сек | Дсек',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: textC,
                  maxLines: 5,
                  decoration: InputDecoration(
                    hintText:
                        'Шуба Ростислав Едуардович\tЕРП\t5\t24\t43',
                    border: const OutlineInputBorder(),
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
                                                '${p.teamName} • ${p.min}:${p.sec.toString().padLeft(2, '0')}.${p.ms.toString().padLeft(2, '0')}',
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
                        final svc = ref.read(athleticsServiceProvider);
                        int count = 0;
                        for (final p in preview) {
                          if (p.teamId != null &&
                              p.playerId != null &&
                              p.timeValid) {
                            await svc.saveResult(AthleticsResult(
                              tournamentId: widget.tId,
                              category: widget.category,
                              playerId: p.playerId!,
                              teamId: p.teamId!,
                              timeMin: p.min,
                              timeSec: p.sec,
                              timeDsec: p.ms,
                            ));
                            count++;
                          }
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
    if (_loading) return const Center(child: CircularProgressIndicator());

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 500;

        return Column(
          children: [
            // Header with add button
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${widget.category.fullName} — ${widget.category.distanceLabel}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
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

  Widget _buildResultsTable(double availableWidth, bool isNarrow) {
    return SizedBox(
      width: availableWidth,
      child: DataTable(
        columnSpacing: isNarrow ? 12 : 24,
        horizontalMargin: isNarrow ? 8 : 24,
        headingRowColor: WidgetStatePropertyAll(Colors.grey.shade100),
        columns: const [
          DataColumn(label: Text('№', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
          DataColumn(label: Text('ПІБ', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Команда', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Вік', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Час', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Коеф', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
          DataColumn(label: Text('Зал. час', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('М', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
          DataColumn(label: Text('', style: TextStyle(fontWeight: FontWeight.bold))),
        ],
        rows: _standings.map((r) {
          return DataRow(
            cells: [
              DataCell(Text(
                r.playerNumber != null ? '${r.playerNumber}' : '—',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: r.playerNumber != null
                      ? Colors.indigo.shade700
                      : Colors.grey.shade500,
                ),
              )),
              DataCell(Text(r.playerName ?? '')),
              DataCell(Text(r.teamName ?? '')),
              DataCell(Text('${r.age > 0 ? r.age : '-'}')),
              DataCell(Text(
                r.result.timeFormatted,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
              )),
              DataCell(Text(
                r.coefficient.toStringAsFixed(4),
                style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.grey.shade600),
              )),
              DataCell(Text(
                r.result.adjustedTimeFormatted(r.coefficient),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 14, color: Colors.indigo),
              )),
              DataCell(Text(
                '${r.place}',
                style: TextStyle(
                  fontWeight: r.place <= 3 ? FontWeight.bold : FontWeight.normal,
                  color: r.place == 1
                      ? Colors.amber.shade800
                      : r.place == 2
                          ? Colors.grey.shade600
                          : r.place == 3
                              ? Colors.brown
                              : null,
                ),
              )),
              DataCell(Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: () => _editResult(r),
                    tooltip: 'Редагувати',
                  ),
                  if (!isNarrow)
                    IconButton(
                      icon: Icon(Icons.delete_outline,
                          size: 18, color: Colors.red.shade400),
                      onPressed: () => _deleteResult(r),
                      tooltip: 'Видалити',
                    ),
                ],
              )),
            ],
          );
        }).toList(),
      ),
    );
  }
}

/// Dialog for adding/editing an athletics result.
class _AthleticsResultDialog extends ConsumerStatefulWidget {
  final int tId;
  final AthleticsCategory category;
  final AthleticsResult? existing;

  const _AthleticsResultDialog({
    required this.tId,
    required this.category,
    this.existing,
  });

  @override
  ConsumerState<_AthleticsResultDialog> createState() =>
      _AthleticsResultDialogState();
}

class _AthleticsResultDialogState
    extends ConsumerState<_AthleticsResultDialog> {
  final _formKey = GlobalKey<FormState>();
  final _minCtrl = TextEditingController();
  final _secCtrl = TextEditingController();
  final _dsecCtrl = TextEditingController();

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
      _minCtrl.text = widget.existing!.timeMin.toString();
      _secCtrl.text = widget.existing!.timeSec.toString();
      _dsecCtrl.text = widget.existing!.timeDsec.toString();
      _selectedTeamId = widget.existing!.teamId;
      _selectedPlayerId = widget.existing!.playerId;
    } else {
      _minCtrl.text = '0';
    }
    _loadTeams();
  }

  @override
  void dispose() {
    _minCtrl.dispose();
    _secCtrl.dispose();
    _dsecCtrl.dispose();
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
    final svc = ref.read(athleticsServiceProvider);
    final players = await svc.getTeamPlayers(widget.tId, teamId);
    if (mounted) {
      setState(() => _players = players);
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedTeamId == null || _selectedPlayerId == null) return;

    final result = AthleticsResult(
      id: widget.existing?.id,
      tournamentId: widget.tId,
      playerId: _selectedPlayerId!,
      teamId: _selectedTeamId!,
      category: widget.category,
      timeMin: int.tryParse(_minCtrl.text) ?? 0,
      timeSec: int.tryParse(_secCtrl.text) ?? 0,
      timeDsec: int.tryParse(_dsecCtrl.text) ?? 0,
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
                    Text(
                        '${widget.category.fullName} — ${widget.category.distanceLabel}',
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
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text('.', style: TextStyle(fontSize: 20)),
                        ),
                        SizedBox(
                          width: 80,
                          child: TextFormField(
                            controller: _dsecCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Дсек',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            validator: (v) {
                              if (v == null || v.isEmpty) return '!';
                              final dsec = int.tryParse(v);
                              if (dsec == null || dsec > 99) return '0-99';
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
  final int min;
  final int sec;
  final int ms;
  final int? playerId;
  final int? teamId;
  final bool timeValid;

  _ParsedResult({
    required this.fullName,
    required this.teamName,
    required this.min,
    required this.sec,
    required this.ms,
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
  final AthleticsParticipantEntry entry;
  AthleticsCategory selectedCategory;
  int? resultId;
  final TextEditingController numberC;
  final TextEditingController minC;
  final TextEditingController secC;
  final TextEditingController dsecC;
  bool saving = false;
  String? error;

  // Snapshot of what's actually persisted; used to detect "no real change".
  AthleticsCategory savedCategory;
  String savedNumber;
  String savedMin;
  String savedSec;
  String savedDsec;

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
        minC = TextEditingController(
          text: entry.resultTotalDsec != null
              ? (entry.resultTotalDsec! ~/ 6000).toString()
              : '',
        ),
        secC = TextEditingController(
          text: entry.resultTotalDsec != null
              ? ((entry.resultTotalDsec! % 6000) ~/ 100)
                  .toString()
                  .padLeft(2, '0')
              : '',
        ),
        dsecC = TextEditingController(
          text: entry.resultTotalDsec != null
              ? (entry.resultTotalDsec! % 100).toString().padLeft(2, '0')
              : '',
        ),
        savedMin = entry.resultTotalDsec != null
            ? (entry.resultTotalDsec! ~/ 6000).toString()
            : '',
        savedSec = entry.resultTotalDsec != null
            ? ((entry.resultTotalDsec! % 6000) ~/ 100)
                .toString()
                .padLeft(2, '0')
            : '',
        savedDsec = entry.resultTotalDsec != null
            ? (entry.resultTotalDsec! % 100).toString().padLeft(2, '0')
            : '';

  void dispose() {
    numberC.dispose();
    minC.dispose();
    secC.dispose();
    dsecC.dispose();
  }

  bool get isDirty {
    if (selectedCategory != savedCategory) return true;
    if (numberC.text.trim() != savedNumber) return true;
    if (minC.text.trim() != savedMin) return true;
    if (secC.text.trim() != savedSec) return true;
    if (dsecC.text.trim() != savedDsec) return true;
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

  /// Returns parsed (min, sec, dsec) when all three fields are present and
  /// valid (sec 0–59, dsec 0–99, total > 0); otherwise null.
  ({int min, int sec, int dsec})? parseTime() {
    final min = int.tryParse(minC.text.trim());
    final sec = int.tryParse(secC.text.trim());
    final dsec = int.tryParse(dsecC.text.trim());
    if (min == null || sec == null || dsec == null) return null;
    if (sec < 0 || sec > 59) return null;
    if (dsec < 0 || dsec > 99) return null;
    if (min + sec + dsec == 0) return null;
    return (min: min, sec: sec, dsec: dsec);
  }

  bool get isCleared =>
      minC.text.trim().isEmpty &&
      secC.text.trim().isEmpty &&
      dsecC.text.trim().isEmpty;
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
      final svc = ref.read(athleticsServiceProvider);
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
    final svc = ref.read(athleticsServiceProvider);
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
          final result = AthleticsResult(
            id: row.resultId,
            tournamentId: widget.tId,
            playerId: row.entry.playerId,
            teamId: row.entry.teamId,
            category: row.selectedCategory,
            timeMin: parsed.min,
            timeSec: parsed.sec,
            timeDsec: parsed.dsec,
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
      row.savedMin = row.minC.text.trim();
      row.savedSec = row.secC.text.trim();
      row.savedDsec = row.dsecC.text.trim();
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
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          'Введіть час прямо у таблиці. Збереження відбувається при переході '
          'на інший рядок або вкладку. Сек 0–59, Дсек 0–99.',
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
                    itemBuilder: (context, i) => _buildRow(_rows[i]),
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
      fontSize: 12,
      fontWeight: FontWeight.bold,
      color: Colors.grey.shade700,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
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
          SizedBox(
            width: _wTimeField,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              child: Text('Дсек', style: st, textAlign: TextAlign.center),
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

  Widget _buildRow(_ParticipantRowState row) {
    final allowed = AthleticsCategory.allowedCategoriesFor(row.entry.autoCategory);
    // Defensive: if a stored override is no longer allowed (e.g. rules changed),
    // include it in the items so the dropdown can still display the value.
    final items = {...allowed, row.selectedCategory}.toList();
    final overridden = row.selectedCategory != row.entry.autoCategory;

    return Focus(
      canRequestFocus: false,
      onFocusChange: (hasFocus) {
        if (!hasFocus) _saveRow(row);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                child: DropdownButton<AthleticsCategory>(
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
            _buildTimeField(row.minC, 3),
            _buildTimeField(row.secC, 2),
            _buildTimeField(row.dsecC, 2),
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
