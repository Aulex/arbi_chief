import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../viewmodels/tournament_viewmodel.dart';
import 'arm_wrestling_providers.dart';
import 'arm_wrestling_scoring.dart';

/// Flat all-players view — one row per player across every weight category,
/// modelled on the cycling "Всі учасники" tab.
class ArmWrestlingAllPlayersTab extends ConsumerStatefulWidget {
  final int tId;
  const ArmWrestlingAllPlayersTab({super.key, required this.tId});

  @override
  ConsumerState<ArmWrestlingAllPlayersTab> createState() =>
      _ArmWrestlingAllPlayersTabState();
}

enum _SortKey { number, name, team, weight, category }

class _Row {
  final int playerId;
  final String fullName;
  final String teamName;
  final int teamId;
  final int categoryId;
  final int place;
  final int wins;
  final int losses;
  final int gamesPlayed;
  final TextEditingController numberC;
  final TextEditingController weightC;
  int? savedNumber;
  String savedWeight;
  bool saving = false;
  String? error;

  _Row({
    required this.playerId,
    required this.fullName,
    required this.teamName,
    required this.teamId,
    required this.categoryId,
    required this.place,
    required this.wins,
    required this.losses,
    required this.gamesPlayed,
    required int? number,
    required double? weight,
  })  : numberC = TextEditingController(text: number != null ? '$number' : ''),
        weightC = TextEditingController(
            text: weight != null ? weight.toStringAsFixed(1) : ''),
        savedNumber = number,
        savedWeight = weight != null ? weight.toStringAsFixed(1) : '';

  int? get parsedNumber {
    final t = numberC.text.trim();
    if (t.isEmpty) return null;
    return int.tryParse(t);
  }

  double? get parsedWeight {
    final t = weightC.text.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  bool get isDirty {
    if (parsedNumber != savedNumber) return true;
    if (weightC.text.trim() != savedWeight) return true;
    return false;
  }

  void dispose() {
    numberC.dispose();
    weightC.dispose();
  }
}

class _ArmWrestlingAllPlayersTabState
    extends ConsumerState<ArmWrestlingAllPlayersTab>
    with AutomaticKeepAliveClientMixin {
  List<_Row> _rows = [];
  bool _loading = true;
  _SortKey _sortKey = _SortKey.category;
  bool _sortAsc = true;
  int? _hoveredRow;
  ProviderSubscription<AsyncValue<ArmWrestlingStandingsBundle>>? _sub;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _sub = ref.listenManual<AsyncValue<ArmWrestlingStandingsBundle>>(
      armWrestlingStandingsProvider(widget.tId),
      (_, next) {
        next.whenData(_rebuildFromBundle);
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _sub?.close();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _rebuildFromBundle(ArmWrestlingStandingsBundle bundle) {
    final oldRows = _rows;
    final rows = <_Row>[];
    for (final cat in WeightCategory.values) {
      final standings = bundle.categoryStandings[cat.id] ?? const [];
      for (final s in standings) {
        rows.add(_Row(
          playerId: s.playerId,
          fullName: s.playerName,
          teamName: s.teamName,
          teamId: s.teamId,
          categoryId: cat.id,
          place: s.place,
          wins: s.wins,
          losses: s.losses,
          gamesPlayed: s.gamesPlayed,
          number: s.playerNumber,
          weight: s.weight ?? bundle.playerWeights[s.playerId],
        ));
      }
    }
    _sort(rows);
    setState(() {
      _rows = rows;
      _loading = false;
    });
    for (final r in oldRows) {
      r.dispose();
    }
  }

  void _sort(List<_Row> rows) {
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
    rows.sort((a, b) {
      int r;
      switch (_sortKey) {
        case _SortKey.number:
          r = cmpInt(a.parsedNumber ?? a.savedNumber, b.parsedNumber ?? b.savedNumber);
          break;
        case _SortKey.name:
          r = cmpStr(a.fullName, b.fullName);
          break;
        case _SortKey.team:
          r = cmpStr(a.teamName, b.teamName);
          break;
        case _SortKey.weight:
          r = (a.parsedWeight ?? -1).compareTo(b.parsedWeight ?? -1);
          break;
        case _SortKey.category:
          r = a.categoryId.compareTo(b.categoryId);
          if (r == 0) {
            final an = a.parsedNumber ?? a.savedNumber ?? 9999;
            final bn = b.parsedNumber ?? b.savedNumber ?? 9999;
            r = an.compareTo(bn);
          }
          break;
      }
      if (r != 0) return _sortAsc ? r : -r;
      return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
    });
  }

  void _toggleSort(_SortKey key) {
    setState(() {
      if (_sortKey == key) {
        _sortAsc = !_sortAsc;
      } else {
        _sortKey = key;
        _sortAsc = true;
      }
      _sort(_rows);
    });
  }

  Future<void> _saveRow(_Row row) async {
    if (!row.isDirty || row.saving) return;
    setState(() {
      row.saving = true;
      row.error = null;
    });
    final svc = ref.read(armWrestlingServiceProvider);
    final tournamentSvc = ref.read(tournamentServiceProvider);
    try {
      // Number
      if (row.parsedNumber != row.savedNumber) {
        final n = row.parsedNumber;
        if (n != null && n > 0) {
          await tournamentSvc.savePlayerNumber(
              playerId: row.playerId, tId: widget.tId, number: n);
        } else if (row.numberC.text.trim().isEmpty) {
          await tournamentSvc.clearPlayerNumber(
              playerId: row.playerId, tId: widget.tId);
        } else {
          setState(() {
            row.saving = false;
            row.error = 'Невірний номер';
          });
          return;
        }
        row.savedNumber = n;
      }
      // Weight + auto-recompute category
      final weightText = row.weightC.text.trim();
      if (weightText != row.savedWeight) {
        final w = row.parsedWeight;
        if (w != null && w > 0) {
          await svc.savePlayerWeight(
              playerId: row.playerId, tId: widget.tId, weight: w);
          final newCat = _categoryFromWeight(w);
          if (newCat != row.categoryId) {
            await svc.setWeightCategory(widget.tId, row.playerId, newCat);
          }
          row.savedWeight = w.toStringAsFixed(1);
          // Refresh bundle (place + category may have changed).
          ref.invalidate(armWrestlingStandingsProvider(widget.tId));
        } else if (weightText.isEmpty) {
          row.savedWeight = '';
        } else {
          setState(() {
            row.saving = false;
            row.error = 'Невірна вага';
          });
          return;
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => row.error = 'Помилка: $e');
    } finally {
      if (mounted) setState(() => row.saving = false);
    }
  }

  static int _categoryFromWeight(double w) {
    if (w <= 70) return WeightCategory.under70.id;
    if (w <= 80) return WeightCategory.under80.id;
    if (w <= 90) return WeightCategory.under90.id;
    if (w <= 100) return WeightCategory.under100.id;
    return WeightCategory.over100.id;
  }

  Future<void> _setCategory(_Row row, int catId) async {
    final svc = ref.read(armWrestlingServiceProvider);
    await svc.setWeightCategory(widget.tId, row.playerId, catId);
    ref.invalidate(armWrestlingStandingsProvider(widget.tId));
  }

  // --- layout ---

  static const double _wNumber = 56;
  static const double _wWeight = 70;
  static const double _wCategory = 130;
  static const double _wStatus = 28;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.fitness_center, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'Немає учасників із призначеною ваговою категорією.\n'
              'Імпортуйте гравців із колонкою «Вага» або призначте категорії вручну.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Всі учасники (${_rows.length})',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Редагуйте номер та вагу прямо у таблиці. Зміна ваги автоматично '
            'оновлює вагову категорію.',
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
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, color: Colors.grey.shade200),
                      itemBuilder: (context, i) => _buildRow(_rows[i], i),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

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
        border:
            Border(bottom: BorderSide(color: Colors.grey.shade400, width: 1.5)),
      ),
      child: Row(
        children: [
          _sortableHeader(
              width: _wNumber,
              label: '№',
              style: st,
              key: _SortKey.number,
              align: TextAlign.center),
          _sortableHeader(
              flex: 3, label: 'ПІБ', style: st, key: _SortKey.name),
          _sortableHeader(
              flex: 2, label: 'Команда', style: st, key: _SortKey.team),
          _sortableHeader(
              width: _wWeight,
              label: 'Вага',
              style: st,
              key: _SortKey.weight,
              align: TextAlign.center),
          _sortableHeader(
              width: _wCategory,
              label: 'Категорія',
              style: st,
              key: _SortKey.category,
              align: TextAlign.center),
          const SizedBox(width: _wStatus),
        ],
      ),
    );
  }

  Widget _sortableHeader({
    double? width,
    int? flex,
    required String label,
    required TextStyle style,
    required _SortKey key,
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

  Widget _buildRow(_Row row, int index) {
    final isHovered = _hoveredRow == index;
    // No outer Focus wrapper around the whole row — that swallowed the
    // dropdown's tap (focus moving out to the overlay triggered _saveRow
    // and an associated rebuild). Each editable text field gets its own
    // Focus listener so the dropdown stays untouched.
    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredRow = index),
      onExit: (_) {
        if (_hoveredRow == index) setState(() => _hoveredRow = null);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        color: isHovered ? Colors.indigo.shade100 : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: _wNumber,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Focus(
                  canRequestFocus: false,
                  onFocusChange: (hasFocus) {
                    if (!hasFocus) _saveRow(row);
                  },
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
            ),
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(row.fullName,
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(row.teamName,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade700),
                      overflow: TextOverflow.ellipsis),
                ),
              ),
              SizedBox(
                width: _wWeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Focus(
                    canRequestFocus: false,
                    onFocusChange: (hasFocus) {
                      if (!hasFocus) _saveRow(row);
                    },
                    child: TextField(
                      controller: row.weightC,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                        LengthLimitingTextInputFormatter(6),
                      ],
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: _wCategory,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    isDense: true,
                    isExpanded: true,
                    value: row.categoryId,
                    items: WeightCategory.values
                        .map((c) => DropdownMenuItem(
                              value: c.id,
                              child: Text(c.label,
                                  style: const TextStyle(fontSize: 13)),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v == null || v == row.categoryId) return;
                      _setCategory(row, v);
                    },
                  ),
                ),
              ),
              SizedBox(
                width: _wStatus,
                child: row.saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : row.error != null
                        ? Tooltip(
                            message: row.error!,
                            child: Icon(Icons.error_outline,
                                size: 18, color: Colors.red.shade400),
                          )
                        : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
  }
}
