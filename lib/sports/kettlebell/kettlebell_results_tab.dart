import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../viewmodels/player_viewmodel.dart';
import '../../viewmodels/team_viewmodel.dart';
import '../../viewmodels/tournament_viewmodel.dart';
import 'kettlebell_providers.dart';
import 'kettlebell_scoring.dart';

/// Top-level kettlebell results tab. Mirrors cycling: an inner TabBar with
/// "Всі учасники" followed by one tab per body-weight category.
class KettlebellResultsTab extends ConsumerStatefulWidget {
  final int tId;
  const KettlebellResultsTab({super.key, required this.tId});

  @override
  ConsumerState<KettlebellResultsTab> createState() => _KettlebellResultsTabState();
}

/// Body-weight category labels used as inner-tab partitions.
const _kbCategories = <String>[
  'до 70 кг',
  'до 80 кг',
  'до 90 кг',
  'до 100 кг',
  'понад 100 кг',
];

class _KettlebellResultsTabState extends ConsumerState<KettlebellResultsTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1 + _kbCategories.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
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
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.groups_outlined, size: 18),
                SizedBox(width: 6),
                Text('Всі учасники'),
              ]),
            ),
            ..._kbCategories.map((c) => Tab(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.fitness_center_outlined, size: 18),
                    const SizedBox(width: 6),
                    Text(c),
                  ]),
                )),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Expanded(
        child: TabBarView(
          controller: _tabController,
          children: [
            _KettlebellPlayersList(tId: widget.tId, filterCategory: null),
            ..._kbCategories.map((c) => _KettlebellPlayersList(tId: widget.tId, filterCategory: c)),
          ],
        ),
      ),
    ]);
  }
}

/// Player list view; either the full roster (filterCategory == null) or
/// a single body-weight category slice.
class _KettlebellPlayersList extends ConsumerStatefulWidget {
  final int tId;
  final String? filterCategory;
  const _KettlebellPlayersList({required this.tId, required this.filterCategory});

  @override
  ConsumerState<_KettlebellPlayersList> createState() => _KettlebellPlayersListState();
}

class _KettlebellPlayersListState extends ConsumerState<_KettlebellPlayersList>
    with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  List<({int playerId, String playerName, int teamId, String teamName})> _players = [];
  Map<int, int> _places = {};
  Map<int, String> _categories = {};
  Map<int, double> _weights = {};
  Map<int, double> _kbWeights = {};
  Map<int, int> _numbers = {};
  Map<int, ({int right, int left})> _reps = {};
  int? _hoveredRow;

  double _totalFor(int playerId) => kettlebellTotalScore(
        rightReps: _reps[playerId]?.right,
        leftReps: _reps[playerId]?.left,
        gearWeightKg: _kbWeights[playerId],
      );

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final playerSvc = ref.read(playerServiceProvider);
    final teamSvc = ref.read(teamServiceProvider);
    final kbSvc = ref.read(kettlebellServiceProvider);

    final playerTeamsMap = await teamSvc.getPlayerTeamsMap(widget.tId);
    final allPlayers = await playerSvc.getAllPlayers();

    final playersList = <({int playerId, String playerName, int teamId, String teamName})>[];
    for (final entry in playerTeamsMap.entries) {
      final pId = entry.key;
      final team = entry.value;
      final pInfo = allPlayers.where((p) => p.player_id == pId).firstOrNull;
      if (pInfo != null) {
        final name = '${pInfo.player_surname ?? ''} ${pInfo.player_name ?? ''} ${pInfo.player_lastname ?? ''}'.trim();
        playersList.add((playerId: pId, playerName: name, teamId: team.team_id!, teamName: team.team_name));
      }
    }

    final places = await kbSvc.getPlayerPlaces(widget.tId);
    final categories = await kbSvc.getPlayerCategories(widget.tId);
    final weights = await kbSvc.getPlayerWeights(widget.tId);
    final kbWeights = await kbSvc.getKettlebellWeights(widget.tId);
    final numbers = await ref.read(tournamentServiceProvider).getPlayerNumbers(widget.tId);
    final reps = await kbSvc.getPlayerReps(widget.tId);

    // Ensure every player with a body weight has a derived category if missing.
    for (final entry in weights.entries) {
      categories.putIfAbsent(entry.key, () => kettlebellCategoryFromBodyWeight(entry.value));
    }

    if (!mounted) return;
    setState(() {
      _players = playersList;
      _places = places;
      _categories = categories;
      _weights = weights;
      _kbWeights = kbWeights;
      _numbers = numbers;
      _reps = reps;
      _loading = false;
    });
  }

  /// Recompute and persist places for every player whose body-weight category
  /// matches [category]. Higher total score → lower place number. Players in
  /// the category without a valid total have any old place removed.
  Future<void> _recomputePlacesForCategory(String category) async {
    final svc = ref.read(kettlebellServiceProvider);
    final teamByPlayer = {for (final p in _players) p.playerId: p.teamId};

    final candidates = <({int playerId, double total})>[];
    final unranked = <int>[];
    for (final p in _players) {
      if (_categories[p.playerId] != category) continue;
      final total = _totalFor(p.playerId);
      if (total > 0) {
        candidates.add((playerId: p.playerId, total: total));
      } else {
        unranked.add(p.playerId);
      }
    }
    candidates.sort((a, b) => b.total.compareTo(a.total));

    for (var i = 0; i < candidates.length; i++) {
      final c = candidates[i];
      final teamId = teamByPlayer[c.playerId];
      if (teamId == null) continue;
      await svc.savePlayerPlace(
        tId: widget.tId,
        playerId: c.playerId,
        teamId: teamId,
        place: i + 1,
      );
    }
    for (final pid in unranked) {
      await svc.clearPlayerPlace(tId: widget.tId, playerId: pid);
    }
  }

  Future<void> _editResult(
    int playerId,
    String playerName,
    String? currentCategory,
    double? currentWeight,
    double? currentKbWeight,
    int? currentRight,
    int? currentLeft,
  ) async {
    final rightCtrl = TextEditingController(text: (currentRight ?? 0) == 0 ? '' : currentRight.toString());
    final leftCtrl = TextEditingController(text: (currentLeft ?? 0) == 0 ? '' : currentLeft.toString());
    final weightCtrl = TextEditingController(text: currentWeight?.toStringAsFixed(1) ?? '');
    final kbWeightCtrl = TextEditingController(text: currentKbWeight?.toStringAsFixed(0) ?? '');
    String derivedCategory =
        currentCategory ?? (currentWeight != null ? kettlebellCategoryFromBodyWeight(currentWeight) : '');

    double previewTotal() {
      final r = int.tryParse(rightCtrl.text) ?? 0;
      final l = int.tryParse(leftCtrl.text) ?? 0;
      final kw = double.tryParse(kbWeightCtrl.text.replaceAll(',', '.'));
      return kettlebellTotalScore(rightReps: r, leftReps: l, gearWeightKg: kw);
    }

    final result = await showDialog<
        ({
          int right,
          int left,
          String category,
          double? weight,
          double? kbWeight,
        })?>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setST) {
        return AlertDialog(
          title: Text('Результат\n$playerName', style: const TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: rightCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Ривки правою',
                        border: OutlineInputBorder(),
                      ),
                      autofocus: true,
                      onChanged: (_) => setST(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: leftCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Ривки лівою',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setST(() {}),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: weightCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Вага спортсмена (кг)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    final w = double.tryParse(v.replaceAll(',', '.'));
                    setST(() =>
                        derivedCategory = w != null ? kettlebellCategoryFromBodyWeight(w) : '');
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: kbWeightCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Вага гирі (кг)',
                    border: OutlineInputBorder(),
                    helperText: 'Коефіцієнти: 8→0.35, 16→0.55, 24→1.0, 32→1.25',
                  ),
                  onChanged: (_) => setST(() {}),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Категорія: ${derivedCategory.isEmpty ? '—' : derivedCategory}\n'
                    'Сума: ${previewTotal().toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Скасувати'),
            ),
            ElevatedButton(
              onPressed: () {
                final r = int.tryParse(rightCtrl.text) ?? 0;
                final l = int.tryParse(leftCtrl.text) ?? 0;
                final w = double.tryParse(weightCtrl.text.replaceAll(',', '.'));
                final kw = double.tryParse(kbWeightCtrl.text.replaceAll(',', '.'));
                Navigator.pop(ctx, (
                  right: r,
                  left: l,
                  category: w != null ? kettlebellCategoryFromBodyWeight(w) : derivedCategory,
                  weight: w,
                  kbWeight: kw,
                ));
              },
              child: const Text('Зберегти'),
            ),
          ],
        );
      }),
    );

    Future<void>.delayed(const Duration(milliseconds: 400), () {
      rightCtrl.dispose();
      leftCtrl.dispose();
      weightCtrl.dispose();
      kbWeightCtrl.dispose();
    });
    if (result != null) {
      final svc = ref.read(kettlebellServiceProvider);
      if (result.weight != null) {
        await svc.savePlayerWeight(
          playerId: playerId,
          tId: widget.tId,
          weight: result.weight!,
        );
      }
      if (result.category.isNotEmpty) {
        await svc.savePlayerCategory(
          playerId: playerId,
          tId: widget.tId,
          category: result.category,
        );
      }
      if (result.kbWeight != null) {
        await svc.saveKettlebellWeight(
          playerId: playerId,
          tId: widget.tId,
          kettlebellWeight: result.kbWeight!,
        );
      }
      await svc.savePlayerReps(
        playerId: playerId,
        tId: widget.tId,
        rightReps: result.right,
        leftReps: result.left,
      );
      // Reload local state so the recompute sees fresh numbers, then rerank.
      await _loadData();
      if (result.category.isNotEmpty) {
        await _recomputePlacesForCategory(result.category);
        await _loadData();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());

    final filter = widget.filterCategory;
    final filtered = filter == null
        ? List.of(_players)
        : _players.where((p) => _categories[p.playerId] == filter).toList();

    if (filtered.isEmpty) {
      return Center(child: Text(filter == null
          ? 'Додайте гравців для введення результатів'
          : 'У категорії "$filter" поки немає учасників'));
    }

    filtered.sort((a, b) {
      final pA = _places[a.playerId], pB = _places[b.playerId];
      if (pA != null && pB != null) return pA.compareTo(pB);
      if (pA != null) return -1;
      if (pB != null) return 1;
      return a.playerName.compareTo(b.playerName);
    });

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade300, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(
              filter == null ? 'Всі учасники' : 'Категорія: $filter',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: filtered.length + 1,
              separatorBuilder: (ctx, i) => Divider(height: 1, color: Colors.grey.shade200),
              itemBuilder: (ctx, i) {
                if (i == 0) return _buildHeader(showPlace: filter != null);
                final p = filtered[i - 1];
                final place = _places[p.playerId];
                final category = _categories[p.playerId];
                final weight = _weights[p.playerId];
                final kbWeight = _kbWeights[p.playerId];
                final number = _numbers[p.playerId];
                final reps = _reps[p.playerId];
                final total = _totalFor(p.playerId);
                return MouseRegion(
                  onEnter: (_) => setState(() => _hoveredRow = i),
                  onExit: (_) => setState(() => _hoveredRow = null),
                  child: InkWell(
                    onTap: () => _editResult(
                      p.playerId,
                      p.playerName,
                      category,
                      weight,
                      kbWeight,
                      reps?.right,
                      reps?.left,
                    ),
                    child: Container(
                      color: _hoveredRow == i ? Colors.indigo.shade50 : null,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(children: [
                        if (filter != null)
                          SizedBox(width: 50, child: Text(place?.toString() ?? '-', style: TextStyle(fontWeight: place != null ? FontWeight.bold : FontWeight.normal, fontSize: 16))),
                        SizedBox(width: 40, child: Text(number?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600))),
                        Expanded(flex: 2, child: Text(p.playerName)),
                        if (filter == null)
                          Expanded(flex: 1, child: Text(category ?? '', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
                        SizedBox(width: 56, child: Text(weight != null ? weight.toStringAsFixed(1) : '', style: TextStyle(fontSize: 12, color: Colors.grey.shade600), textAlign: TextAlign.center)),
                        SizedBox(width: 50, child: Text(kbWeight != null ? '${kbWeight.toStringAsFixed(0)}' : '', style: TextStyle(fontSize: 12, color: Colors.grey.shade600), textAlign: TextAlign.center)),
                        SizedBox(width: 40, child: Text((reps?.right ?? 0) == 0 ? '' : '${reps!.right}', textAlign: TextAlign.center)),
                        SizedBox(width: 40, child: Text((reps?.left ?? 0) == 0 ? '' : '${reps!.left}', textAlign: TextAlign.center)),
                        SizedBox(width: 60, child: Text(total > 0 ? total.toStringAsFixed(2) : '', style: const TextStyle(fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
                        Expanded(flex: 2, child: Text(p.teamName, style: TextStyle(color: Colors.grey.shade700))),
                        Icon(Icons.edit, size: 16, color: Colors.indigo.shade300),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildHeader({required bool showPlace}) => Container(
        color: Colors.grey.shade100,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          if (showPlace)
            const SizedBox(width: 50, child: Text('Місце', style: TextStyle(fontWeight: FontWeight.bold))),
          const SizedBox(width: 40, child: Text('№', style: TextStyle(fontWeight: FontWeight.bold))),
          const Expanded(flex: 2, child: Text('Гравець', style: TextStyle(fontWeight: FontWeight.bold))),
          if (!showPlace)
            const Expanded(flex: 1, child: Text('Категорія', style: TextStyle(fontWeight: FontWeight.bold))),
          const SizedBox(width: 56, child: Text('Вага', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
          const SizedBox(width: 50, child: Text('Гиря', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
          const SizedBox(width: 40, child: Text('Пр', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
          const SizedBox(width: 40, child: Text('Лів', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
          const SizedBox(width: 60, child: Text('Сума', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
          const Expanded(flex: 2, child: Text('Команда', style: TextStyle(fontWeight: FontWeight.bold))),
          const SizedBox(width: 16),
        ]),
      );
}
