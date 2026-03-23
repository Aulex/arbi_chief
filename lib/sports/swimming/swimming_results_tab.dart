import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'swimming_model.dart';
import 'swimming_service.dart';
import '../../viewmodels/shared_providers.dart';

/// Provider for SwimmingService.
final swimmingServiceProvider = Provider(
  (ref) => SwimmingService(ref.watch(dbServiceProvider)),
);

/// Main tab for entering and viewing swimming results per category.
class SwimmingResultsTab extends ConsumerStatefulWidget {
  final int tId;

  const SwimmingResultsTab({super.key, required this.tId});

  @override
  ConsumerState<SwimmingResultsTab> createState() => _SwimmingResultsTabState();
}

class _SwimmingResultsTabState extends ConsumerState<SwimmingResultsTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _categories = [
    SwimmingCategory.m35,
    SwimmingCategory.m49,
    SwimmingCategory.m50,
    SwimmingCategory.f35,
    SwimmingCategory.f49,
    SwimmingCategory.relay,
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categories.length, vsync: this);
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
            tabs: _categories
                .map((c) => Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            c == SwimmingCategory.relay
                                ? Icons.groups_outlined
                                : c == SwimmingCategory.f35 ||
                                        c == SwimmingCategory.f49
                                    ? Icons.woman_outlined
                                    : Icons.man_outlined,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(c.label),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 12),
        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: _categories
                .map((c) => _CategoryResultsView(
                      tId: widget.tId,
                      category: c,
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }
}

/// Shows the results list for a single swimming category with add/edit/delete.
class _CategoryResultsView extends ConsumerStatefulWidget {
  final int tId;
  final SwimmingCategory category;

  const _CategoryResultsView({required this.tId, required this.category});

  @override
  ConsumerState<_CategoryResultsView> createState() =>
      _CategoryResultsViewState();
}

class _CategoryResultsViewState extends ConsumerState<_CategoryResultsView>
    with AutomaticKeepAliveClientMixin {
  List<RankedSwimmingResult> _standings = [];
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadStandings();
  }

  Future<void> _loadStandings() async {
    setState(() => _loading = true);
    final svc = ref.read(swimmingServiceProvider);
    final standings =
        await svc.getCategoryStandings(widget.tId, widget.category);
    if (mounted) {
      setState(() {
        _standings = standings;
        _loading = false;
      });
    }
  }

  Future<void> _addResult() async {
    final result = await showDialog<SwimmingResult>(
      context: context,
      builder: (ctx) => _SwimmingResultDialog(
        tId: widget.tId,
        category: widget.category,
      ),
    );
    if (result != null) {
      final svc = ref.read(swimmingServiceProvider);
      await svc.saveResult(result);
      await _loadStandings();
    }
  }

  Future<void> _editResult(RankedSwimmingResult ranked) async {
    final result = await showDialog<SwimmingResult>(
      context: context,
      builder: (ctx) => _SwimmingResultDialog(
        tId: widget.tId,
        category: widget.category,
        existing: ranked.result,
      ),
    );
    if (result != null) {
      final svc = ref.read(swimmingServiceProvider);
      await svc.saveResult(result);
      await _loadStandings();
    }
  }

  Future<void> _deleteResult(RankedSwimmingResult ranked) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Видалити результат?'),
        content: Text(
            'Видалити результат ${ranked.playerName ?? ranked.teamName}?'),
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
      final svc = ref.read(swimmingServiceProvider);
      await svc.deleteResult(ranked.result.id!);
      await _loadStandings();
    }
  }

  void _showBulkImportDialog() {
    final textC = TextEditingController();
    List<_ParsedResult> preview = [];
    bool importing = false;
    bool parsing = false;

    Future<void> updatePreview(String text, Function(void Function()) setST) async {
      if (text.trim().isEmpty) {
        setST(() => preview = []);
        return;
      }
      setST(() => parsing = true);
      final svc = ref.read(swimmingServiceProvider);
      // Replace all Unicode whitespace characters
      final cleanText = text.replaceAll(
          RegExp(
              r'[\u00A0\u2000-\u200B\u200C\u200D\u202F\u205F\u2060\u3000\uFEFF]'),
          ' ');
      final lines = cleanText.split('\n').where((l) => l.trim().isNotEmpty).toList();
      final results = <_ParsedResult>[];

      for (final line in lines) {
        final parts = line.split('\t').map((s) => s.trim()).toList();
        if (parts.length < 5) continue;

        final fullName = parts[0];
        final teamName = parts[1];
        final min = int.tryParse(parts[2]) ?? 0;
        final sec = int.tryParse(parts[3]) ?? 0;
        final ms = int.tryParse(parts[4]) ?? 0;

        final ids = await svc.findParticipant(widget.tId, fullName, teamName);
        results.add(_ParsedResult(
          fullName: fullName,
          teamName: teamName,
          min: min,
          sec: sec,
          ms: ms,
          playerId: ids.playerId,
          teamId: ids.teamId,
        ));
      }
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
                  'Вставте дані з Excel (5 стовпців):\nПІБ | Команда | Хв | Сек | Мс',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: textC,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    hintText: 'Шуба Ростислав Едуардович\tЕРП\t0\t24\t43',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (val) => updatePreview(val, setST),
                ),
                const SizedBox(height: 12),
                const Text('Попередній перегляд:', style: TextStyle(fontWeight: FontWeight.bold)),
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
                            ? const Center(child: Text('Немає даних для імпорту', style: TextStyle(color: Colors.grey)))
                            : ListView.separated(
                                padding: const EdgeInsets.all(8),
                                itemCount: preview.length,
                                separatorBuilder: (_, __) => const Divider(),
                                itemBuilder: (ctx, i) {
                                  final p = preview[i];
                                  final ok = p.teamId != null && (widget.category == SwimmingCategory.relay || p.playerId != null);
                                  return Row(
                                    children: [
                                      Icon(
                                        ok ? Icons.check_circle : Icons.error,
                                        color: ok ? Colors.green : Colors.red,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(p.fullName, style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: (widget.category != SwimmingCategory.relay && p.playerId == null) ? Colors.red : null,
                                            )),
                                            Text('${p.teamName} • ${p.min}:${p.sec.toString().padLeft(2, '0')}.${p.ms.toString().padLeft(2, '0')}',
                                                style: TextStyle(fontSize: 12, color: p.teamId == null ? Colors.red : Colors.grey.shade600)),
                                          ],
                                        ),
                                      ),
                                      if (!ok)
                                        Text(
                                          p.teamId == null ? 'Команду не знайдено' : 'Учасника не знайдено',
                                          style: const TextStyle(fontSize: 10, color: Colors.red),
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
              onPressed: (importing || preview.isEmpty || !preview.any((p) => p.teamId != null && (widget.category == SwimmingCategory.relay || p.playerId != null)))
                  ? null
                  : () async {
                      setST(() => importing = true);
                      try {
                        final svc = ref.read(swimmingServiceProvider);
                        int count = 0;
                        for (final p in preview) {
                          final ok = p.teamId != null && (widget.category == SwimmingCategory.relay || p.playerId != null);
                          if (ok) {
                            await svc.saveResult(SwimmingResult(
                              tournamentId: widget.tId,
                              category: widget.category,
                              playerId: p.playerId,
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
                            SnackBar(content: Text('Імпортовано результатів: $count')),
                          );
                        }
                      } catch (e) {
                        setST(() => importing = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Помилка імпорту: $e')),
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
                  '${widget.category.fullName} — 50 м в/стиль',
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
                        child: _buildResultsTable(
                            constraints.maxWidth, isNarrow),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildResultsTable(double availableWidth, bool isNarrow) {
    final isRelay = widget.category == SwimmingCategory.relay;

    return SizedBox(
      width: availableWidth,
      child: DataTable(
        columnSpacing: isNarrow ? 12 : 24,
        horizontalMargin: isNarrow ? 8 : 24,
        headingRowColor: WidgetStatePropertyAll(Colors.grey.shade100),
        columns: [
          const DataColumn(
              label:
                  Text('М', style: TextStyle(fontWeight: FontWeight.bold))),
          if (!isRelay)
            const DataColumn(
                label: Text('ПІБ',
                    style: TextStyle(fontWeight: FontWeight.bold))),
          const DataColumn(
              label: Text('Команда',
                  style: TextStyle(fontWeight: FontWeight.bold))),
          const DataColumn(
              label: Text('Час',
                  style: TextStyle(fontWeight: FontWeight.bold))),
          const DataColumn(
              label:
                  Text('', style: TextStyle(fontWeight: FontWeight.bold))),
        ],
        rows: _standings.map((r) {
          return DataRow(
            cells: [
              DataCell(Text(
                '${r.place}',
                style: TextStyle(
                  fontWeight:
                      r.place <= 3 ? FontWeight.bold : FontWeight.normal,
                  color: r.place == 1
                      ? Colors.amber.shade800
                      : r.place == 2
                          ? Colors.grey.shade600
                          : r.place == 3
                              ? Colors.brown
                              : null,
                ),
              )),
              if (!isRelay) DataCell(Text(r.playerName ?? '')),
              DataCell(Text(r.teamName ?? '')),
              DataCell(Text(
                r.result.timeFormatted,
                style:
                    const TextStyle(fontFamily: 'monospace', fontSize: 14),
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

/// Dialog for adding/editing a swimming result.
class _SwimmingResultDialog extends ConsumerStatefulWidget {
  final int tId;
  final SwimmingCategory category;
  final SwimmingResult? existing;

  const _SwimmingResultDialog({
    required this.tId,
    required this.category,
    this.existing,
  });

  @override
  ConsumerState<_SwimmingResultDialog> createState() =>
      _SwimmingResultDialogState();
}

class _SwimmingResultDialogState extends ConsumerState<_SwimmingResultDialog> {
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

  bool get _isRelay => widget.category == SwimmingCategory.relay;

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
    if (_selectedTeamId != null && !_isRelay) {
      await _loadPlayers(_selectedTeamId!);
    }
    setState(() {
      _teams = teams;
      _loading = false;
    });
  }

  Future<void> _loadPlayers(int teamId) async {
    final svc = ref.read(swimmingServiceProvider);
    final players = await svc.getTeamPlayers(widget.tId, teamId);
    if (mounted) {
      setState(() => _players = players);
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedTeamId == null) return;
    if (!_isRelay && _selectedPlayerId == null) return;

    final result = SwimmingResult(
      id: widget.existing?.id,
      tournamentId: widget.tId,
      playerId: _isRelay ? null : _selectedPlayerId,
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
                    Text(widget.category.fullName,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 16),
                    // Team dropdown
                    DropdownButtonFormField<int>(
                      value: _selectedTeamId,
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
                        if (val != null && !_isRelay) _loadPlayers(val);
                      },
                      validator: (v) =>
                          v == null ? 'Оберіть команду' : null,
                    ),
                    if (!_isRelay) ...[
                      const SizedBox(height: 12),
                      // Player dropdown – key forces rebuild when team changes
                      DropdownButtonFormField<int>(
                        key: ValueKey('player_$_selectedTeamId'),
                        value: _players.any((p) => p.playerId == _selectedPlayerId)
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
                    ],
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

  _ParsedResult({
    required this.fullName,
    required this.teamName,
    required this.min,
    required this.sec,
    required this.ms,
    this.playerId,
    this.teamId,
  });
}
