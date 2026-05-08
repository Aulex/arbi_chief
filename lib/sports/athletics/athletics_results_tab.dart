import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'athletics_model.dart';
import 'athletics_providers.dart';
import '../../viewmodels/shared_providers.dart';

/// Main tab for entering and viewing athletics results per category.
class AthleticsResultsTab extends ConsumerStatefulWidget {
  final int tId;

  const AthleticsResultsTab({super.key, required this.tId});

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
                            c.isMale
                                ? Icons.man_outlined
                                : Icons.woman_outlined,
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
