import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'tournament_add_screen.dart';
import 'team_edit_screen.dart';
import '../models/tournament_model.dart';
import '../models/team_model.dart';
import '../models/player_model.dart';
import '../models/sport_type_config.dart';
import '../viewmodels/nav_provider.dart';
import '../viewmodels/player_viewmodel.dart';
import '../viewmodels/tournament_viewmodel.dart';
import '../viewmodels/team_viewmodel.dart';

class TournamentEditScreen extends ConsumerStatefulWidget {
  final Tournament tournament;
  const TournamentEditScreen({super.key, required this.tournament});

  @override
  ConsumerState<TournamentEditScreen> createState() =>
      _TournamentEditScreenState();
}

class _TournamentEditScreenState extends ConsumerState<TournamentEditScreen> {
  SportTypeConfig get _sportConfig => getConfigForType(widget.tournament.t_type);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24.0, 8.0, 24.0, 24.0),
        child: Column(
          children: [
            // Header with back arrow | tabs
            Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: Colors.grey.shade300, width: 1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, size: 20),
                        onPressed: () {
                          ref
                              .read(tournamentNavProvider.notifier)
                              .showList();
                        },
                      ),
                      SizedBox(
                        height: 32,
                        child: VerticalDivider(
                          thickness: 1,
                          width: 24,
                          color: Colors.grey.shade300,
                        ),
                      ),
                      Expanded(
                        child: TabBar(
                          isScrollable: true,
                          labelColor: Colors.indigo,
                          indicatorColor: Colors.indigo,
                          indicatorWeight: 2,
                          tabAlignment: TabAlignment.start,
                          tabs: const [
                            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.leaderboard_outlined, size: 18), SizedBox(width: 6), Text('Таблиця')])),
                            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.people_outline, size: 18), SizedBox(width: 6), Text('Гравці')])),
                            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.groups_outlined, size: 18), SizedBox(width: 6), Text('Команди')])),
                            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.settings_outlined, size: 18), SizedBox(width: 6), Text('Налаштування')])),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Tab Bar View
              Expanded(
                child: TabBarView(
                  children: [
                    _buildTableTab(),
                    _TournamentPlayersTab(tId: widget.tournament.t_id!, tType: widget.tournament.t_type),
                    _TournamentTeamsTab(tournament: widget.tournament, config: _sportConfig),
                    TournamentAddScreen(
                      tournament: widget.tournament,
                      isEditMode: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
    );
  }

  Widget _buildBoardsTab() {
    final tId = widget.tournament.t_id!;
    final svc = ref.read(tournamentServiceProvider);
    final teamSvc = ref.read(teamServiceProvider);

    return FutureBuilder<String?>(
      future: svc.getAttrDictValue(tId, 2), // attr_id=2: Система жеребкування
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final pairingSystem = snapshot.data;

        if (pairingSystem == 'Колова') {
          return _buildRoundRobinPairing(teamSvc, tId);
        }

        // Placeholder for other systems
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: Colors.grey.shade300, width: 1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Дошки',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  pairingSystem != null
                      ? 'Система жеребкування: $pairingSystem (в розробці)'
                      : 'Система жеребкування не обрана.',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRoundRobinPairing(dynamic teamSvc, int tId) {
    return FutureBuilder<
        Map<int, List<({int teamId, String teamName, int? teamNumber, Player player})>>>(
      future: teamSvc.getBoardAssignmentsForTournament(tId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final boards = snapshot.data ?? {};

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: Colors.grey.shade300, width: 1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_sportConfig.boardLabel}и — Колова система',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Розподіл гравців по ${_sportConfig.boardLabelPlural} з командних складів.',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int boardNum = 1; boardNum <= _sportConfig.boardCount; boardNum++) ...[
                    if (boardNum > 1) const SizedBox(width: 16),
                    Expanded(
                      child: _buildBoardPairingCard(
                        boardNum,
                        boards[boardNum] ?? [],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBoardPairingCard(
    int boardNum,
    List<({int teamId, String teamName, int? teamNumber, Player player})> entries,
  ) {
    final isWomenBoard = _sportConfig.lastBoardWomenOnly && boardNum == _sportConfig.boardCount;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: isWomenBoard ? Colors.pink.shade200 : Colors.grey.shade300,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor:
                      isWomenBoard ? Colors.pink : Colors.indigo,
                  child: Text(
                    '$boardNum',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _sportConfig.tabLabel(boardNum),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),
            if (entries.isEmpty)
              Text(
                'Немає гравців на цій позиції',
                style: TextStyle(color: Colors.grey.shade500),
              )
            else
              ...entries.map((e) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_outline),
                    title: Text(e.player.fullName),
                    subtitle: Text(e.teamName),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _buildGamesTab() {
    return _GameResultsTab(tId: widget.tournament.t_id!, config: _sportConfig);
  }

  Widget _buildTableTab() {
    return _CrossTableTab(tId: widget.tournament.t_id!, tournamentName: widget.tournament.t_name, config: _sportConfig, tType: widget.tournament.t_type);
  }

}

/// Players tab — single list of tournament players with search, add, and create new.
class _TournamentPlayersTab extends ConsumerStatefulWidget {
  final int tId;
  final int? tType;
  const _TournamentPlayersTab({required this.tId, required this.tType});

  @override
  ConsumerState<_TournamentPlayersTab> createState() => _TournamentPlayersTabState();
}

class _TournamentPlayersTabState extends ConsumerState<_TournamentPlayersTab> {
  List<Player> _participants = [];
  List<Player> _available = [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final svc = ref.read(tournamentServiceProvider);
    final participants = await svc.getParticipants(widget.tId);
    final allPlayers = await ref.read(playerProvider.future);
    final participantIds = participants.map((p) => p.player_id).toSet();
    final available = allPlayers
        .where((p) => !participantIds.contains(p.player_id))
        .toList()
      ..sort((a, b) => a.player_surname.compareTo(b.player_surname));

    if (mounted) {
      setState(() {
        _participants = participants
          ..sort((a, b) => a.player_surname.compareTo(b.player_surname));
        _available = available;
        _loading = false;
      });
    }
  }

  void _removePlayer(Player player) {
    setState(() {
      _participants.removeWhere((p) => p.player_id == player.player_id);
      _available
        ..add(player)
        ..sort((a, b) => a.player_surname.compareTo(b.player_surname));
    });
    ref.read(tournamentServiceProvider).removeParticipant(widget.tId, player.player_id!);
  }

  void _showAddPlayerDialog() {
    String dialogSearch = '';
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setST) {
          final filtered = _available.where((p) {
            if (dialogSearch.isEmpty) return true;
            return p.fullName.toLowerCase().contains(dialogSearch.toLowerCase());
          }).toList();

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.person_add, color: Colors.indigo),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text('Додати гравця', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            _showCreatePlayerDialog();
                          },
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Створити нового'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Пошук гравця...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (v) => setST(() => dialogSearch = v),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: filtered.isEmpty
                          ? const Center(child: Text('Немає доступних гравців'))
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final player = filtered[index];
                                return ListTile(
                                  dense: true,
                                  title: Text(player.fullName),
                                  subtitle: player.birthDateForUI.isNotEmpty
                                      ? Text(player.birthDateForUI, style: const TextStyle(fontSize: 12))
                                      : null,
                                  trailing: IconButton(
                                    icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                                    onPressed: () {
                                      setState(() {
                                        _available.removeWhere((p) => p.player_id == player.player_id);
                                        _participants
                                          ..add(player)
                                          ..sort((a, b) => a.player_surname.compareTo(b.player_surname));
                                      });
                                      ref.read(tournamentServiceProvider).addParticipant(widget.tId, player.player_id!);
                                      setST(() {}); // refresh dialog list
                                    },
                                  ),
                                  contentPadding: EdgeInsets.zero,
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('Закрити'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showCreatePlayerDialog() {
    final nameC = TextEditingController();
    final surnameC = TextEditingController();
    final lastnameC = TextEditingController();
    final dobC = TextEditingController();
    int gender = 0;

    Future<void> pickDate(BuildContext dialogContext, StateSetter setST) async {
      final picked = await showDatePicker(
        context: dialogContext,
        initialDate: DateTime(2000),
        firstDate: DateTime(1920),
        lastDate: DateTime.now(),
        locale: const Locale('uk'),
      );
      if (picked != null) {
        final day = picked.day.toString().padLeft(2, '0');
        final month = picked.month.toString().padLeft(2, '0');
        final year = picked.year.toString();
        dobC.text = '$day.$month.$year';
      }
    }

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setST) {
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.person_add_alt_1, color: Colors.indigo),
                        SizedBox(width: 12),
                        Text(
                          'Створити нового гравця',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Divider(),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: surnameC,
                            decoration: InputDecoration(
                              labelText: 'Прізвище',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: nameC,
                            decoration: InputDecoration(
                              labelText: "Ім'я",
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: lastnameC,
                      decoration: InputDecoration(
                        labelText: 'По батькові',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: dobC,
                            readOnly: true,
                            decoration: InputDecoration(
                              labelText: 'Дата народження',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.calendar_today, size: 20),
                                onPressed: () => pickDate(dialogContext, setST),
                              ),
                            ),
                            onTap: () => pickDate(dialogContext, setST),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: gender,
                            decoration: InputDecoration(
                              labelText: 'Стать',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            items: const [
                              DropdownMenuItem(value: 0, child: Text('Чоловіча')),
                              DropdownMenuItem(value: 1, child: Text('Жіноча')),
                            ],
                            onChanged: (v) => setST(() => gender = v!),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Скасувати'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () async {
                            if (nameC.text.trim().isEmpty || surnameC.text.trim().isEmpty) return;
                            await ref.read(playerProvider.notifier).addPlayer(
                              name: nameC.text.trim(),
                              surname: surnameC.text.trim(),
                              lastname: lastnameC.text.trim(),
                              gender: gender,
                              dob: dobC.text.trim(),
                            );
                            if (dialogContext.mounted) Navigator.pop(dialogContext);
                            _loadData();
                          },
                          child: const Text('Створити'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final filtered = _search.isEmpty
        ? _participants
        : _participants.where((p) => p.fullName.toLowerCase().contains(_search.toLowerCase())).toList();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade300, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Гравці турніру (${_participants.length})',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Гравці, додані до цього турніру.',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _showAddPlayerDialog,
                  icon: const Icon(Icons.person_add_alt_1, size: 18),
                  label: const Text('Додати гравця'),
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.indigo,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                hintText: 'Пошук...',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
            const Divider(height: 24),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('Немає гравців'))
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final player = filtered[index];
                        return ListTile(
                          title: Text(player.fullName),
                          subtitle: player.birthDateForUI.isNotEmpty
                              ? Text(player.birthDateForUI)
                              : null,
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                            tooltip: 'Видалити з турніру',
                            onPressed: () => _removePlayer(player),
                          ),
                          contentPadding: EdgeInsets.zero,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tab showing game results grouped by board, with inline result editing.
class _GameResultsTab extends ConsumerStatefulWidget {
  final int tId;
  final SportTypeConfig config;
  const _GameResultsTab({required this.tId, required this.config});

  @override
  ConsumerState<_GameResultsTab> createState() => _GameResultsTabState();
}

class _GameResultsTabState extends ConsumerState<_GameResultsTab> {
  Map<int, List<({int eventId, Player white, Player black, String? dateBegin, double? whiteResult, double? blackResult, String? whiteDetail, String? blackDetail})>> _boardGames = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadGames();
  }

  Future<void> _loadGames() async {
    final svc = ref.read(tournamentServiceProvider);
    final data = await svc.getGamesGroupedByBoard(widget.tId);
    if (mounted) {
      setState(() {
        _boardGames = data;
        _loading = false;
      });
    }
  }

  String _resultLabel(double? w, double? b) {
    if (w == null || b == null) return '—';
    if (w == 1.0 && b == 0.0) return '1 - 0';
    if (w == 0.0 && b == 1.0) return '0 - 1';
    if (w == 0.5 && b == 0.5) return '½ - ½';
    return '—';
  }

  Future<void> _setResult(int eventId, int boardNum, int idx, String? val) async {
    if (val == null) return;
    double? w, b;
    switch (val) {
      case '1 - 0':
        w = 1.0; b = 0.0;
      case '½ - ½':
        w = 0.5; b = 0.5;
      case '0 - 1':
        w = 0.0; b = 1.0;
      default:
        w = null; b = null;
    }
    final games = _boardGames[boardNum]!;
    final old = games[idx];
    setState(() {
      games[idx] = (
        eventId: old.eventId,
        white: old.white,
        black: old.black,
        dateBegin: old.dateBegin,
        whiteResult: w,
        blackResult: b,
        whiteDetail: old.whiteDetail,
        blackDetail: old.blackDetail,
      );
    });
    final svc = ref.read(tournamentServiceProvider);
    await svc.saveGameResult(eventId, w, b);
  }

  Future<void> _deleteGame(int eventId, int boardNum, int idx) async {
    final svc = ref.read(tournamentServiceProvider);
    await svc.deleteGame(eventId);
    setState(() {
      _boardGames[boardNum]!.removeAt(idx);
      if (_boardGames[boardNum]!.isEmpty) {
        _boardGames.remove(boardNum);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_boardGames.isEmpty) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: Colors.grey.shade300, width: 1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.sports_esports_outlined, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(
                  'Ігор ще немає',
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final sortedBoards = _boardGames.keys.toList()..sort();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < sortedBoards.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            _buildBoardCard(sortedBoards[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildBoardCard(int boardNum) {
    final games = _boardGames[boardNum]!;
    final isWomen = widget.config.lastBoardWomenOnly && boardNum == widget.config.boardCount;
    final boardLabel = boardNum == 0
        ? 'Інші ігри'
        : widget.config.tabLabel(boardNum);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: isWomen ? Colors.pink.shade200 : Colors.grey.shade300,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: boardNum == 0
                      ? Colors.grey
                      : (isWomen ? Colors.pink : Colors.indigo),
                  child: Text(
                    boardNum == 0 ? '?' : '$boardNum',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  boardLabel,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Text(
                  '(${games.length})',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
            const Divider(height: 24),
            SizedBox(
              width: double.infinity,
              child: DataTable(
                headingTextStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black54,
                ),
                columnSpacing: 24,
                columns: const [
                  DataColumn(label: Text('#')),
                  DataColumn(label: Text('Білі')),
                  DataColumn(label: Text('Результат')),
                  DataColumn(label: Text('Чорні')),
                  DataColumn(label: Text('')),
                ],
                rows: games.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final g = entry.value;
                  final result = _resultLabel(g.whiteResult, g.blackResult);

                  return DataRow(
                    cells: [
                      DataCell(Text('${idx + 1}')),
                      DataCell(Text(g.white.fullName)),
                      DataCell(
                        DropdownButton<String>(
                          value: result,
                          underline: const SizedBox(),
                          style: const TextStyle(fontSize: 14, color: Colors.black87),
                          items: const [
                            DropdownMenuItem(value: '—', child: Text('—')),
                            DropdownMenuItem(value: '1 - 0', child: Text('1 - 0')),
                            DropdownMenuItem(value: '½ - ½', child: Text('½ - ½')),
                            DropdownMenuItem(value: '0 - 1', child: Text('0 - 1')),
                          ],
                          onChanged: (val) => _setResult(g.eventId, boardNum, idx, val),
                        ),
                      ),
                      DataCell(Text(g.black.fullName)),
                      DataCell(
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                          onPressed: () => _deleteGame(g.eventId, boardNum, idx),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tab with sub-tabs: Дошка 1, Дошка 2, Дошка 3, Команди.
/// Cross-tables are interactive — tap cells to enter results.
class _CrossTableTab extends ConsumerStatefulWidget {
  final int tId;
  final String tournamentName;
  final SportTypeConfig config;
  final int? tType;
  const _CrossTableTab({required this.tId, required this.tournamentName, required this.config, this.tType});

  @override
  ConsumerState<_CrossTableTab> createState() => _CrossTableTabState();
}

class _CrossTableTabState extends ConsumerState<_CrossTableTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = true;
  Map<int, List<({int teamId, String teamName, int? teamNumber, Player player})>> _boardPlayers = {};
  Map<int, Map<int, Map<int, double>>> _boardResults = {};
  /// Stores set score detail strings: boardNum → playerId → opponentId → detail (e.g. "11:7 11:4")
  Map<int, Map<int, Map<int, String>>> _boardResultDetails = {};
  Set<int> _absentPlayerIds = {};
  int? _hoveredRow;
  int? _hoveredCol;
  int? _hoveredTeamRow;
  int? _hoveredTeamCol;

  bool get _isTableTennis => widget.tType == 11;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: widget.config.boardCount + 1, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final teamSvc = ref.read(teamServiceProvider);
    final tournamentSvc = ref.read(tournamentServiceProvider);

    final boards = await teamSvc.getBoardAssignmentsForTournament(widget.tId);
    final games = await tournamentSvc.getGamesGroupedByBoard(widget.tId);
    final allTeams = await teamSvc.getTeamListForTournament(widget.tId);

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

    // Load no-show players first so phantom logic treats them as absent too
    final noShowIds = await teamSvc.getNoShowPlayerIds(widget.tId);

    // Add phantom "absent" entries for teams missing from each board.
    final absentIds = <int>{...noShowIds};
    for (final boardNum in boards.keys) {
      final presentTeamIds = boards[boardNum]!.map((p) => p.teamId).toSet();
      for (final team in allTeams) {
        if (presentTeamIds.contains(team.teamId)) continue;
        // Sentinel ID: negative, unique per team+board
        final phantomId = -(team.teamId * 100 + boardNum);
        absentIds.add(phantomId);
        boards[boardNum]!.add((
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
        // Set results: absent=0 vs every real player, real player=1 vs absent
        // No-show players (in absentIds) also get 0 vs phantom
        results.putIfAbsent(boardNum, () => {});
        results[boardNum]!.putIfAbsent(phantomId, () => {});
        for (final realPlayer in boards[boardNum]!) {
          final realId = realPlayer.player.player_id!;
          if (realId == phantomId || absentIds.contains(realId)) continue;
          results[boardNum]![phantomId]![realId] = 0.0;
          results[boardNum]!.putIfAbsent(realId, () => {})[phantomId] = 1.0;
        }
      }
    }
    // Cross-set absent vs absent (phantom + no-show): both get 0
    for (final boardNum in boards.keys) {
      final absentOnBoard = boards[boardNum]!
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

    if (mounted) {
      setState(() {
        _boardPlayers = boards;
        _boardResults = results;
        _boardResultDetails = details;
        _absentPlayerIds = absentIds;
        _loading = false;
      });
    }
  }

  // --- Result entry ---

  Future<void> _onResultSelected(int rowPlayerId, int colPlayerId, double? result) async {
    final svc = ref.read(tournamentServiceProvider);

    if (result == null) {
      final eventId = await svc.findGameBetweenPlayers(widget.tId, rowPlayerId, colPlayerId);
      if (eventId != null) {
        await svc.saveResultForPlayer(eventId, rowPlayerId, null);
      }
    } else {
      final tsId = await svc.getOrCreateDefaultStage(widget.tId);
      var eventId = await svc.findGameBetweenPlayers(widget.tId, rowPlayerId, colPlayerId);
      eventId ??= await svc.createGame(
        tsId: tsId,
        whitePlayerId: rowPlayerId,
        blackPlayerId: colPlayerId,
      );
      await svc.saveResultForPlayer(eventId, rowPlayerId, result);
    }

    await _loadData();
  }

  void _showResultPicker(
    BuildContext context, {
    required int rowPlayerId,
    required int colPlayerId,
    required String rowPlayerName,
    required String colPlayerName,
    required double? currentResult,
    int? boardNum,
  }) {
    if (_isTableTennis) {
      _showTableTennisResultPicker(
        context,
        rowPlayerId: rowPlayerId,
        colPlayerId: colPlayerId,
        rowPlayerName: rowPlayerName,
        colPlayerName: colPlayerName,
        currentResult: currentResult,
        boardNum: boardNum,
      );
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('$rowPlayerName  vs  $colPlayerName', style: const TextStyle(fontSize: 16)),
        children: [
          _resultOption(ctx, label: 'Перемога', symbol: '1', color: Colors.green, value: 1.0, current: currentResult),
          _resultOption(ctx, label: 'Нічия', symbol: '½', color: Colors.amber, value: 0.5, current: currentResult),
          _resultOption(ctx, label: 'Поразка', symbol: '0', color: Colors.red, value: 0.0, current: currentResult),
          if (currentResult != null) ...[
            const Divider(),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, -1.0),
              child: Row(children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(6)),
                  alignment: Alignment.center,
                  child: Icon(Icons.close, size: 18, color: Colors.grey.shade700),
                ),
                const SizedBox(width: 12),
                const Text('Очистити'),
              ]),
            ),
          ],
        ],
      ),
    ).then((value) {
      if (value == null) return;
      _onResultSelected(rowPlayerId, colPlayerId, value == -1.0 ? null : value);
    });
  }

  void _showTableTennisResultPicker(
    BuildContext context, {
    required int rowPlayerId,
    required int colPlayerId,
    required String rowPlayerName,
    required String colPlayerName,
    required double? currentResult,
    int? boardNum,
  }) {
    // Pre-fill controllers from existing detail
    final existingDetail = boardNum != null
        ? (_boardResultDetails[boardNum]?[rowPlayerId]?[colPlayerId])
        : null;
    final existingSets = existingDetail?.split(' ') ?? [];

    // Up to 3 sets (best of 3 in table tennis)
    final controllers = List.generate(3, (i) {
      final parts = i < existingSets.length ? existingSets[i].split(':') : [];
      return (
        row: TextEditingController(text: parts.length == 2 ? parts[0] : ''),
        col: TextEditingController(text: parts.length == 2 ? parts[1] : ''),
      );
    });

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('$rowPlayerName  vs  $colPlayerName', style: const TextStyle(fontSize: 15)),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header row
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const SizedBox(width: 40),
                      Expanded(child: Text(rowPlayerName.split(' ').first, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      const SizedBox(width: 16),
                      Expanded(child: Text(colPlayerName.split(' ').first, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    ],
                  ),
                ),
                // Set rows
                for (int i = 0; i < 3; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        SizedBox(width: 40, child: Text('Сет ${i + 1}', style: const TextStyle(fontSize: 12, color: Colors.black54))),
                        Expanded(
                          child: TextField(
                            controller: controllers[i].row,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Text(':', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                        Expanded(
                          child: TextField(
                            controller: controllers[i].col,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            if (currentResult != null)
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _onResultSelected(rowPlayerId, colPlayerId, null);
                },
                child: Text('Очистити', style: TextStyle(color: Colors.grey.shade700)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Скасувати'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _onTableTennisResultSaved(rowPlayerId, colPlayerId, controllers);
              },
              child: const Text('Зберегти'),
            ),
          ],
        );
      },
    ).then((_) {
      for (final c in controllers) {
        c.row.dispose();
        c.col.dispose();
      }
    });
  }

  Future<void> _onTableTennisResultSaved(
    int rowPlayerId,
    int colPlayerId,
    List<({TextEditingController row, TextEditingController col})> controllers,
  ) async {
    // Parse set scores
    final rowSets = <String>[];
    final colSets = <String>[];
    int rowWins = 0;
    int colWins = 0;

    for (final c in controllers) {
      final rowScore = int.tryParse(c.row.text);
      final colScore = int.tryParse(c.col.text);
      if (rowScore == null || colScore == null) continue;
      if (rowScore == 0 && colScore == 0) continue;
      rowSets.add('$rowScore:$colScore');
      colSets.add('$colScore:$rowScore');
      if (rowScore > colScore) {
        rowWins++;
      } else if (colScore > rowScore) {
        colWins++;
      }
    }

    if (rowSets.isEmpty) return;

    final rowResult = rowWins > colWins ? 1.0 : (rowWins < colWins ? 0.0 : 0.5);
    final rowDetail = rowSets.join(' ');
    final colDetail = colSets.join(' ');

    final svc = ref.read(tournamentServiceProvider);
    final tsId = await svc.getOrCreateDefaultStage(widget.tId);
    var eventId = await svc.findGameBetweenPlayers(widget.tId, rowPlayerId, colPlayerId);
    eventId ??= await svc.createGame(
      tsId: tsId,
      whitePlayerId: rowPlayerId,
      blackPlayerId: colPlayerId,
    );
    await svc.saveTableTennisResult(eventId, rowPlayerId,
      rowResult: rowResult,
      rowDetail: rowDetail,
      colDetail: colDetail,
    );

    await _loadData();
  }

  Widget _resultOption(BuildContext ctx, {
    required String label,
    required String symbol,
    required MaterialColor color,
    required double value,
    required double? current,
  }) {
    return SimpleDialogOption(
      onPressed: () => Navigator.pop(ctx, value),
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(color: color.shade100, borderRadius: BorderRadius.circular(6)),
          alignment: Alignment.center,
          child: Text(symbol, style: TextStyle(fontWeight: FontWeight.bold, color: color.shade800)),
        ),
        const SizedBox(width: 12),
        Text(label),
        if (current == value) ...[const Spacer(), Icon(Icons.check, color: color.shade700, size: 20)],
      ]),
    );
  }

  // --- Calculations ---

  double _totalPoints(int boardNum, int playerId) {
    return (_boardResults[boardNum]?[playerId] ?? {}).values.fold(0.0, (sum, r) => sum + r);
  }

  int _gamesPlayed(int boardNum, int playerId) {
    return (_boardResults[boardNum]?[playerId] ?? {}).length;
  }

  /// Коефіцієнт Бергера = сума очок переможених суперників
  /// + половина очок суперників, з якими нічия.
  double _bergerCoefficient(int boardNum, int playerId) {
    final results = _boardResults[boardNum]?[playerId] ?? {};
    double sb = 0;
    for (final entry in results.entries) {
      final result = entry.value;
      final opponentPoints = _totalPoints(boardNum, entry.key);
      if (result == 1.0) {
        sb += opponentPoints;          // перемога: повна сума очок суперника
      } else if (result == 0.5) {
        sb += opponentPoints * 0.5;    // нічия: половина очок суперника
      }
      // поразка: 0
    }
    return sb;
  }

  List<({int teamId, String teamName, int? teamNumber, Player player})> _sortedStandings(
    int boardNum,
    List<({int teamId, String teamName, int? teamNumber, Player player})> players,
  ) {
    final sorted = List.of(players);
    sorted.sort((a, b) {
      final aId = a.player.player_id!;
      final bId = b.player.player_id!;
      // 1. Total points
      final pa = _totalPoints(boardNum, aId);
      final pb = _totalPoints(boardNum, bId);
      if (pa != pb) return pb.compareTo(pa);
      // 2. Head-to-head result
      final aVsB = _boardResults[boardNum]?[aId]?[bId];
      final bVsA = _boardResults[boardNum]?[bId]?[aId];
      if (aVsB != null && bVsA != null) {
        if (aVsB > bVsA) return -1; // a won head-to-head → a ranks higher
        if (aVsB < bVsA) return 1;
      }
      // 3. Berger coefficient
      final ba = _bergerCoefficient(boardNum, aId);
      final bb = _bergerCoefficient(boardNum, bId);
      return bb.compareTo(ba);
    });
    return sorted;
  }

  String _formatResult(double? result) {
    if (result == null) return '';
    if (result == 1.0) return '1';
    if (result == 0.0) return '0';
    if (result == 0.5) return '½';
    return result.toString();
  }

  String _formatPoints(double points) {
    if (points == points.roundToDouble()) return points.toStringAsFixed(1);
    String s = points.toStringAsFixed(2);
    if (s.endsWith('0')) s = s.substring(0, s.length - 1);
    return s;
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_boardPlayers.isEmpty) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: Colors.grey.shade300, width: 1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.table_chart_outlined, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text('Немає даних для таблиці', style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              Text('Додайте учасників та розподіліть їх по ${widget.config.boardLabelPlural}.', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ]),
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: Colors.indigo,
                indicatorColor: Colors.indigo,
                tabAlignment: TabAlignment.start,
                labelPadding: const EdgeInsets.symmetric(horizontal: 16),
                tabs: [
                  for (int i = 1; i <= widget.config.boardCount; i++)
                    Tab(text: widget.config.shortTabLabel(i), height: 36),
                  const Tab(text: 'Команди', height: 36),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              for (int i = 1; i <= widget.config.boardCount; i++)
                _buildBoardTab(i),
              _buildTeamsTab(),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _clearBoardResults(int boardNum) async {
    final svc = ref.read(tournamentServiceProvider);
    final teamSvc = ref.read(teamServiceProvider);

    // Reset game results to null (keep the game records)
    final games = await svc.getGamesGroupedByBoard(widget.tId);
    final boardGames = games[boardNum] ?? [];
    final eventIds = boardGames.map((g) => g.eventId).toList();
    await svc.resetGameResults(eventIds);

    // Clear неявка attribute for no-show players on this board
    final players = _boardPlayers[boardNum] ?? [];
    for (final p in players) {
      final pid = p.player.player_id!;
      if (_absentPlayerIds.contains(pid) && pid > 0) {
        await teamSvc.clearNoShowAttr(pid, widget.tId);
      }
    }

    await _loadData();
  }

  Widget _buildBoardTab(int boardNum) {
    final players = _boardPlayers[boardNum] ?? [];
    if (players.isEmpty) {
      return Center(
        child: Text('Немає гравців: ${widget.config.shortTabLabel(boardNum)}', style: TextStyle(color: Colors.grey.shade600)),
      );
    }

    final hasResults = _boardResults[boardNum]?.isNotEmpty == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasResults)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.delete_sweep_outlined, size: 14),
              label: const Text('Очистити', style: TextStyle(fontSize: 11)),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Очистити результати?'),
                    content: Text('Видалити всі результати ігор: ${widget.config.shortTabLabel(boardNum)}?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Скасувати')),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _clearBoardResults(boardNum);
                        },
                        child: const Text('Очистити', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        Expanded(
          child: Scrollbar(
            child: SingleChildScrollView(
              child: Scrollbar(
                notificationPredicate: (n) => n.depth == 1,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _buildCombinedTable(boardNum, players),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --- Teams cross table ---

  /// Calculate team match score: sum individual board results for teamA vs teamB.
  ({double a, double b}) _teamMatchScore(int teamAId, int teamBId) {
    double aTotal = 0;
    double bTotal = 0;
    for (final boardEntry in _boardPlayers.entries) {
      final boardNum = boardEntry.key;
      final playerA = boardEntry.value.where((p) => p.teamId == teamAId).firstOrNull;
      final playerB = boardEntry.value.where((p) => p.teamId == teamBId).firstOrNull;
      if (playerA == null || playerB == null) continue;
      final aResult = _boardResults[boardNum]?[playerA.player.player_id!]?[playerB.player.player_id!];
      final bResult = _boardResults[boardNum]?[playerB.player.player_id!]?[playerA.player.player_id!];
      if (aResult != null) aTotal += aResult;
      if (bResult != null) bTotal += bResult;
    }
    return (a: aTotal, b: bTotal);
  }

  /// Convert board-level match score to team match points.
  /// Win=2, Loss=0, Draw=1 (when missing one player per side).
  ({double a, double b}) _teamMatchPoints(int teamAId, int teamBId) {
    final score = _teamMatchScore(teamAId, teamBId);
    if (score.a > score.b) return (a: 2.0, b: 0.0);
    if (score.b > score.a) return (a: 0.0, b: 2.0);
    if (score.a > 0 || score.b > 0) return (a: 1.0, b: 1.0);
    return (a: 0.0, b: 0.0);
  }

  Widget _buildTeamsTab() {
    final teamMap = <int, ({String teamName, int? teamNumber})>{};
    for (final boardEntry in _boardPlayers.entries) {
      for (final p in boardEntry.value) {
        teamMap.putIfAbsent(p.teamId, () => (teamName: p.teamName, teamNumber: p.teamNumber));
      }
    }

    if (teamMap.isEmpty) {
      return Center(
        child: Text('Немає даних для командного заліку', style: TextStyle(color: Colors.grey.shade600)),
      );
    }

    final teamIds = teamMap.keys.toList();
    final teamPoints = <int, double>{};
    final teamBoardDiff = <int, double>{}; // total board win diff across tournament
    final teamBoard3Pts = <int, double>{}; // women's racket (last board)
    for (final aId in teamIds) {
      double total = 0;
      double boardWins = 0;
      double boardLosses = 0;
      for (final bId in teamIds) {
        if (aId == bId) continue;
        total += _teamMatchPoints(aId, bId).a;
        final score = _teamMatchScore(aId, bId);
        boardWins += score.a;
        boardLosses += score.b;
      }
      teamPoints[aId] = total;
      teamBoardDiff[aId] = boardWins - boardLosses;
      final lastBoard = widget.config.boardCount;
      final b3p = (_boardPlayers[lastBoard] ?? []).where((p) => p.teamId == aId).firstOrNull;
      teamBoard3Pts[aId] = b3p != null ? _totalPoints(lastBoard, b3p.player.player_id!) : 0;
    }

    // Sort: points → h2h → board diff between them → board diff in tournament → women's racket
    teamIds.sort((a, b) {
      final pa = teamPoints[a]!;
      final pb = teamPoints[b]!;
      if (pa != pb) return pb.compareTo(pa);
      // 2. Head-to-head
      final h2h = _teamMatchPoints(a, b);
      if (h2h.a > h2h.b) return -1;
      if (h2h.b > h2h.a) return 1;
      // 3. Board win diff between them (in direct match)
      final directScore = _teamMatchScore(a, b);
      final directDiffA = directScore.a - directScore.b;
      final directDiffB = directScore.b - directScore.a;
      if (directDiffA != directDiffB) return directDiffB.compareTo(directDiffA);
      // 4. Board win diff across entire tournament
      final bdA = teamBoardDiff[a]!;
      final bdB = teamBoardDiff[b]!;
      if (bdA != bdB) return bdB.compareTo(bdA);
      // 5. Women's racket (last board) result
      return teamBoard3Pts[b]!.compareTo(teamBoard3Pts[a]!);
    });

    final n = teamIds.length;
    const headerStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54);
    const cellStyle = TextStyle(fontSize: 12, color: Colors.black87);

    return Scrollbar(
      child: SingleChildScrollView(
        child: Scrollbar(
          notificationPredicate: (n) => n.depth == 1,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              border: TableBorder.all(color: Colors.grey.shade300, width: 1),
              defaultColumnWidth: const IntrinsicColumnWidth(),
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              decoration: BoxDecoration(color: Colors.grey.shade100),
              children: [
                _tableCell('№', style: headerStyle),
                _tableCell('Команда', style: headerStyle, minWidth: 140),
                for (int i = 0; i < n; i++)
                  _verticalHeaderCell(
                    number: teamMap[teamIds[i]]!.teamNumber ?? (i + 1),
                    surname: teamMap[teamIds[i]]!.teamName,
                    isHighlighted: _hoveredTeamCol == i,
                    style: headerStyle,
                  ),
                _tableCell('Очки', style: headerStyle),
                _tableCell('Р.Д.', style: headerStyle),
                _tableCell('Ж.${widget.config.boardAbbrev}.', style: headerStyle),
                _tableCell('Місце', style: headerStyle),
              ],
            ),
            for (int i = 0; i < n; i++)
              TableRow(
                decoration: i.isEven ? null : BoxDecoration(color: Colors.grey.shade50),
                children: [
                  _tableCell('${teamMap[teamIds[i]]!.teamNumber ?? (i + 1)}', style: cellStyle),
                  _highlightableNameCell(teamMap[teamIds[i]]!.teamName, isHighlighted: _hoveredTeamRow == i, style: cellStyle, minWidth: 140),
                  for (int j = 0; j < n; j++)
                    if (i == j)
                      _diagonalCell()
                    else
                      _teamResultCell(teamIds[i], teamIds[j], teamMap, rowIdx: i, colIdx: j),
                  _tableCell(
                    _formatPoints(teamPoints[teamIds[i]]!),
                    style: cellStyle.copyWith(fontWeight: FontWeight.bold),
                  ),
                  _tableCell(_formatPoints(teamBoardDiff[teamIds[i]]!), style: cellStyle),
                  _tableCell(_formatPoints(teamBoard3Pts[teamIds[i]]!), style: cellStyle),
                  _tableCell('${i + 1}', style: cellStyle.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
          ],
        ),
      ),
      ),
      ),
    );
  }

  Widget _teamResultCell(int teamAId, int teamBId, Map<int, ({String teamName, int? teamNumber})> teamMap, {required int rowIdx, required int colIdx}) {
    final matchPts = _teamMatchPoints(teamAId, teamBId);
    final boardScore = _teamMatchScore(teamAId, teamBId);
    final pts = matchPts.a;
    final label = '${pts.toInt()}';

    final isHighlighted = _hoveredTeamRow == rowIdx || _hoveredTeamCol == colIdx;
    Color? bgColor;
    if (pts == 2.0) bgColor = Colors.green.shade50;
    else if (pts == 0.0 && (boardScore.a > 0 || boardScore.b > 0)) bgColor = Colors.red.shade50;
    else if (pts == 1.0) bgColor = Colors.amber.shade50;
    else if (isHighlighted) bgColor = Colors.indigo.shade50;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() { _hoveredTeamRow = rowIdx; _hoveredTeamCol = colIdx; }),
      onExit: (_) => setState(() { _hoveredTeamRow = null; _hoveredTeamCol = null; }),
      child: GestureDetector(
        onTap: () => _showTeamMatchDetails(context, teamAId, teamBId, teamMap),
        child: Container(
          constraints: const BoxConstraints(minWidth: 50, minHeight: 32),
          color: bgColor ?? Colors.transparent,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: pts == 2.0 ? Colors.green.shade700
                  : pts == 0.0 ? Colors.red.shade700
                  : Colors.amber.shade800,
            ),
          ),
        ),
      ),
    );
  }

  void _showTeamMatchDetails(
    BuildContext context,
    int teamAId,
    int teamBId,
    Map<int, ({String teamName, int? teamNumber})> teamMap,
  ) {
    final teamAName = teamMap[teamAId]!.teamName;
    final teamBName = teamMap[teamBId]!.teamName;
    final boardNums = _boardPlayers.keys.toList()..sort();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$teamAName  —  $teamBName', style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 420,
          child: Table(
            border: TableBorder.all(color: Colors.grey.shade300, width: 1),
            defaultColumnWidth: const IntrinsicColumnWidth(),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                decoration: BoxDecoration(color: Colors.grey.shade100),
                children: [
                  _tableCell(widget.config.boardLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black54)),
                  _tableCell(teamAName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black54), minWidth: 120, leftAlign: true),
                  _tableCell('', style: const TextStyle(fontSize: 12)),
                  _tableCell(teamBName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black54), minWidth: 120, leftAlign: true),
                ],
              ),
              for (final boardNum in boardNums)
                _buildBoardMatchRow(boardNum, teamAId, teamBId),
              // Total row
              TableRow(
                decoration: BoxDecoration(color: Colors.grey.shade100),
                children: [
                  _tableCell('', style: const TextStyle(fontSize: 12)),
                  _tableCell('Разом', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87), minWidth: 120, leftAlign: true),
                  _tableCell(
                    '${_formatPoints(_teamMatchScore(teamAId, teamBId).a)} : ${_formatPoints(_teamMatchScore(teamAId, teamBId).b)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                  ),
                  _tableCell('', style: const TextStyle(fontSize: 12), minWidth: 120),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрити')),
        ],
      ),
    );
  }

  TableRow _buildBoardMatchRow(int boardNum, int teamAId, int teamBId) {
    final playersOnBoard = _boardPlayers[boardNum] ?? [];
    final playerA = playersOnBoard.where((p) => p.teamId == teamAId).firstOrNull;
    final playerB = playersOnBoard.where((p) => p.teamId == teamBId).firstOrNull;

    final aName = playerA != null
        ? '${playerA.player.player_surname} ${playerA.player.player_name}'
        : '—';
    final bName = playerB != null
        ? '${playerB.player.player_surname} ${playerB.player.player_name}'
        : '—';

    String scoreText = '';
    Color scoreColor = Colors.black87;
    if (playerA != null && playerB != null) {
      final aResult = _boardResults[boardNum]?[playerA.player.player_id!]?[playerB.player.player_id!];
      final bResult = _boardResults[boardNum]?[playerB.player.player_id!]?[playerA.player.player_id!];
      if (aResult != null && bResult != null) {
        scoreText = '${_formatResult(aResult)} : ${_formatResult(bResult)}';
        if (aResult > bResult) scoreColor = Colors.green.shade700;
        else if (aResult < bResult) scoreColor = Colors.red.shade700;
        else scoreColor = Colors.amber.shade800;
      }
    }

    const cellStyle = TextStyle(fontSize: 12, color: Colors.black87);
    return TableRow(
      children: [
        _tableCell('$boardNum', style: cellStyle.copyWith(fontWeight: FontWeight.bold)),
        _tableCell(aName, style: cellStyle, minWidth: 120, leftAlign: true),
        _tableCell(scoreText, style: cellStyle.copyWith(fontWeight: FontWeight.bold, color: scoreColor)),
        _tableCell(bName, style: cellStyle, minWidth: 120, leftAlign: true),
      ],
    );
  }

  // --- Cross-table ---

  Widget _buildCombinedTable(
    int boardNum,
    List<({int teamId, String teamName, int? teamNumber, Player player})> rawPlayers,
  ) {
    final players = List.of(rawPlayers)
      ..sort((a, b) {
        final aNum = a.teamNumber ?? 9999;
        final bNum = b.teamNumber ?? 9999;
        if (aNum != bNum) return aNum.compareTo(bNum);
        return a.teamName.compareTo(b.teamName);
      });
    final n = players.length;
    final sorted = _sortedStandings(boardNum, players);
    const headerStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54);
    const cellStyle = TextStyle(fontSize: 12, color: Colors.black87);

    return Table(
      border: TableBorder.all(color: Colors.grey.shade300, width: 1),
      defaultColumnWidth: const IntrinsicColumnWidth(),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        // Header row
        TableRow(
          decoration: BoxDecoration(color: Colors.grey.shade100),
          children: [
            // Cross table headers
            _tableCell('№к', style: headerStyle),
            _tableCell('Команда', style: headerStyle, minWidth: 70),
            _tableCell('ПІБ', style: headerStyle, minWidth: 130),
            for (int i = 0; i < n; i++)
              _verticalHeaderCell(
                number: i + 1,
                surname: players[i].player.player_surname,
                isHighlighted: _hoveredCol == i,
                style: headerStyle,
              ),
            _tableCell('Бали', style: headerStyle),
            _tableCell('Ігор', style: headerStyle),
            _tableCell('К.Б.', style: headerStyle),
            // Standings headers
            _tableCell('№к', style: headerStyle),
            _tableCell('ПІБ', style: headerStyle, minWidth: 130),
            _tableCell('Команда', style: headerStyle, minWidth: 90),
            _tableCell('Бали', style: headerStyle),
            _tableCell('К.Б.', style: headerStyle),
            _tableCell('Місце', style: headerStyle),
          ],
        ),
        // Data rows
        for (int i = 0; i < n; i++)
          TableRow(
            decoration: i.isEven ? null : BoxDecoration(color: Colors.grey.shade50),
            children: [
              // Cross table cells
              _tableCell(
                '${players[i].teamNumber ?? ''}',
                style: cellStyle.copyWith(color: Colors.grey.shade600, fontSize: 11),
              ),
              _tableCell(players[i].teamName, style: cellStyle, minWidth: 70, leftAlign: true),
              if (_absentPlayerIds.contains(players[i].player.player_id) && players[i].player.player_id! < 0)
                // Phantom absent (team missing from board) — not tappable
                _tableCell(
                  '${players[i].player.player_surname} ${players[i].player.player_name}',
                  style: cellStyle.copyWith(color: Colors.red.shade400, fontStyle: FontStyle.italic),
                  minWidth: 130, leftAlign: true,
                )
              else if (_absentPlayerIds.contains(players[i].player.player_id))
                // Real no-show player — tappable to clear
                _tappableNameCell(
                  '${players[i].player.player_surname} ${players[i].player.player_name}',
                  isHighlighted: _hoveredRow == i,
                  style: cellStyle.copyWith(color: Colors.red.shade700, fontStyle: FontStyle.italic),
                  minWidth: 130,
                  onTap: () => _showPlayerOptions(context, boardNum, players[i], players),
                )
              else
                _tappableNameCell(
                  '${players[i].player.player_surname} ${players[i].player.player_name}',
                  isHighlighted: _hoveredRow == i,
                  style: cellStyle,
                  minWidth: 130,
                  onTap: () => _showPlayerOptions(context, boardNum, players[i], players),
                ),
              for (int j = 0; j < n; j++)
                if (i == j)
                  _diagonalCell()
                else if (_absentPlayerIds.contains(players[i].player.player_id) || _absentPlayerIds.contains(players[j].player.player_id))
                  _staticResultCell(boardNum: boardNum, rowPlayer: players[i], colPlayer: players[j], rowIdx: i, colIdx: j)
                else
                  _tappableResultCell(boardNum: boardNum, rowPlayer: players[i], colPlayer: players[j], rowIdx: i, colIdx: j),
              _tableCell(
                _formatPoints(_totalPoints(boardNum, players[i].player.player_id!)),
                style: cellStyle.copyWith(fontWeight: FontWeight.bold),
              ),
              _tableCell('${_gamesPlayed(boardNum, players[i].player.player_id!)}', style: cellStyle),
              _tableCell(
                _formatPoints(_bergerCoefficient(boardNum, players[i].player.player_id!)),
                style: cellStyle,
              ),
              // Standings cells (sorted order)
              _tableCell(
                '${sorted[i].teamNumber ?? ''}',
                style: cellStyle.copyWith(color: Colors.grey.shade600, fontSize: 11),
              ),
              _tableCell(
                '${sorted[i].player.player_surname} ${sorted[i].player.player_name}',
                style: cellStyle, minWidth: 130, leftAlign: true,
              ),
              _tableCell(sorted[i].teamName, style: cellStyle, minWidth: 90, leftAlign: true),
              _tableCell(
                _formatPoints(_totalPoints(boardNum, sorted[i].player.player_id!)),
                style: cellStyle.copyWith(fontWeight: FontWeight.bold),
              ),
              _tableCell(
                _formatPoints(_bergerCoefficient(boardNum, sorted[i].player.player_id!)),
                style: cellStyle,
              ),
              _tableCell('${i + 1}', style: cellStyle.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
      ],
    );
  }

  // --- Cell widgets ---

  Widget _verticalHeaderCell({required int number, required String surname, required bool isHighlighted, TextStyle? style}) {
    final effectiveStyle = isHighlighted
        ? (style ?? const TextStyle()).copyWith(color: Colors.indigo.shade800)
        : style;
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.bottom,
      child: Container(
        constraints: const BoxConstraints(minWidth: 36),
        color: isHighlighted ? Colors.indigo.shade100 : null,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RotatedBox(
              quarterTurns: 3,
              child: Text(surname, style: effectiveStyle),
            ),
            const SizedBox(height: 2),
            Text('$number', style: effectiveStyle),
          ],
        ),
      ),
    );
  }

  Widget _highlightableNameCell(String text, {required bool isHighlighted, TextStyle? style, double? minWidth}) {
    return Container(
      constraints: minWidth != null ? BoxConstraints(minWidth: minWidth) : null,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      color: isHighlighted ? Colors.indigo.shade100 : null,
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        textAlign: TextAlign.left,
        style: isHighlighted
            ? (style ?? const TextStyle()).copyWith(color: Colors.indigo.shade800)
            : style,
      ),
    );
  }

  Widget _tappableNameCell(String text, {required bool isHighlighted, TextStyle? style, double? minWidth, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          constraints: minWidth != null ? BoxConstraints(minWidth: minWidth) : null,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          color: isHighlighted ? Colors.indigo.shade100 : null,
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            textAlign: TextAlign.left,
            style: isHighlighted
                ? (style ?? const TextStyle()).copyWith(color: Colors.indigo.shade800)
                : style,
          ),
        ),
      ),
    );
  }

  void _showPlayerOptions(
    BuildContext context,
    int boardNum,
    ({int teamId, String teamName, int? teamNumber, Player player}) player,
    List<({int teamId, String teamName, int? teamNumber, Player player})> allPlayers,
  ) {
    final name = '${player.player.player_surname} ${player.player.player_name}';
    final isNoShow = _absentPlayerIds.contains(player.player.player_id);
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(name, style: const TextStyle(fontSize: 16)),
        children: [
          if (!isNoShow)
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(ctx);
                _markPlayerNoShow(boardNum, player, allPlayers);
              },
              child: Row(children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(6)),
                  alignment: Alignment.center,
                  child: Icon(Icons.person_off, size: 18, color: Colors.red.shade800),
                ),
                const SizedBox(width: 12),
                const Text('Неявка'),
              ]),
            ),
          if (isNoShow)
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(ctx);
                _clearPlayerNoShow(player);
              },
              child: Row(children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(color: Colors.blue.shade100, borderRadius: BorderRadius.circular(6)),
                  alignment: Alignment.center,
                  child: Icon(Icons.person_add, size: 18, color: Colors.blue.shade800),
                ),
                const SizedBox(width: 12),
                const Text('Очистити'),
              ]),
            ),
        ],
      ),
    );
  }

  Future<void> _markPlayerNoShow(
    int boardNum,
    ({int teamId, String teamName, int? teamNumber, Player player}) player,
    List<({int teamId, String teamName, int? teamNumber, Player player})> allPlayers,
  ) async {
    final svc = ref.read(tournamentServiceProvider);
    final teamSvc = ref.read(teamServiceProvider);
    final playerId = player.player.player_id!;
    final tsId = await svc.getOrCreateDefaultStage(widget.tId);
    final opponentIds = allPlayers
        .where((p) => p.player.player_id != playerId && p.player.player_id! > 0)
        .map((p) => p.player.player_id!)
        .toList();
    await svc.markPlayerNoShow(widget.tId, tsId, playerId, opponentIds, alsoAbsentIds: _absentPlayerIds);
    await teamSvc.markPlayerNoShowAttr(playerId, widget.tId);
    await _loadData();
  }

  Future<void> _clearPlayerNoShow(
    ({int teamId, String teamName, int? teamNumber, Player player}) player,
  ) async {
    final svc = ref.read(tournamentServiceProvider);
    final teamSvc = ref.read(teamServiceProvider);
    final playerId = player.player.player_id!;
    await svc.clearPlayerNoShow(widget.tId, playerId);
    await teamSvc.clearNoShowAttr(playerId, widget.tId);
    await _loadData();
  }

  Widget _tableCell(String text, {TextStyle? style, double? minWidth, bool leftAlign = false}) {
    return Container(
      constraints: minWidth != null ? BoxConstraints(minWidth: minWidth) : null,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      alignment: leftAlign ? Alignment.centerLeft : Alignment.center,
      child: Text(text, textAlign: leftAlign ? TextAlign.left : TextAlign.center, style: style),
    );
  }

  Widget _diagonalCell() {
    return Container(
      constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
      color: Colors.grey.shade800,
    );
  }

  Widget _staticResultCell({
    required int boardNum,
    required ({int teamId, String teamName, int? teamNumber, Player player}) rowPlayer,
    required ({int teamId, String teamName, int? teamNumber, Player player}) colPlayer,
    required int rowIdx,
    required int colIdx,
  }) {
    final rowId = rowPlayer.player.player_id!;
    final colId = colPlayer.player.player_id!;
    final result = _boardResults[boardNum]?[rowId]?[colId];
    final detail = _boardResultDetails[boardNum]?[rowId]?[colId];
    final text = _isTableTennis && detail != null && detail.isNotEmpty
        ? _formatTableTennisCell(detail, result)
        : _formatResult(result);

    Color? bgColor;
    if (result == 1.0) {
      bgColor = Colors.green.shade50;
    } else if (result == 0.0 && result != null) {
      bgColor = Colors.red.shade50;
    } else if (result == 0.5) {
      bgColor = Colors.amber.shade50;
    }

    return Container(
      constraints: BoxConstraints(minWidth: _isTableTennis ? 72 : 36, minHeight: 32),
      color: bgColor ?? Colors.transparent,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: text.isEmpty
          ? const SizedBox.shrink()
          : Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: _isTableTennis ? 10 : 12,
                fontWeight: FontWeight.bold,
                color: result == 1.0 ? Colors.green.shade700
                    : result == 0.0 && result != null ? Colors.red.shade700
                    : result == 0.5 ? Colors.amber.shade800
                    : Colors.black87,
              ),
            ),
    );
  }

  Widget _tappableResultCell({
    required int boardNum,
    required ({int teamId, String teamName, int? teamNumber, Player player}) rowPlayer,
    required ({int teamId, String teamName, int? teamNumber, Player player}) colPlayer,
    required int rowIdx,
    required int colIdx,
  }) {
    final rowId = rowPlayer.player.player_id!;
    final colId = colPlayer.player.player_id!;
    final result = _boardResults[boardNum]?[rowId]?[colId];
    final detail = _boardResultDetails[boardNum]?[rowId]?[colId];
    final text = _isTableTennis && detail != null && detail.isNotEmpty
        ? _formatTableTennisCell(detail, result)
        : _formatResult(result);

    final isHighlighted = _hoveredRow == rowIdx || _hoveredCol == colIdx;
    Color? bgColor;
    if (result == 1.0) {
      bgColor = Colors.green.shade50;
    } else if (result == 0.0 && result != null) {
      bgColor = Colors.red.shade50;
    } else if (result == 0.5) {
      bgColor = Colors.amber.shade50;
    } else if (isHighlighted) {
      bgColor = Colors.indigo.shade50;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() { _hoveredRow = rowIdx; _hoveredCol = colIdx; }),
      onExit: (_) => setState(() { _hoveredRow = null; _hoveredCol = null; }),
      child: GestureDetector(
        onTap: () => _showResultPicker(
          context,
          rowPlayerId: rowId,
          colPlayerId: colId,
          rowPlayerName: '${rowPlayer.player.player_surname} ${rowPlayer.player.player_name}',
          colPlayerName: '${colPlayer.player.player_surname} ${colPlayer.player.player_name}',
          currentResult: result,
          boardNum: boardNum,
        ),
        child: Container(
          constraints: BoxConstraints(minWidth: _isTableTennis ? 72 : 36, minHeight: 32),
          color: bgColor ?? Colors.transparent,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          child: text.isEmpty
              ? Icon(Icons.edit_outlined, size: 12, color: Colors.grey.shade400)
              : Text(
                  text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: _isTableTennis ? 10 : 12,
                    fontWeight: FontWeight.bold,
                    color: result == 1.0 ? Colors.green.shade700
                        : result == 0.0 && result != null ? Colors.red.shade700
                        : result == 0.5 ? Colors.amber.shade800
                        : Colors.black87,
                  ),
                ),
        ),
      ),
    );
  }

  /// Format table tennis cell display: "3:1" set score + ball details on second line
  String _formatTableTennisCell(String detail, double? result) {
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
    // Show set score + individual game scores
    return '$rowWins:$colWins\n(${sets.join(', ')})';
  }
}

/// Teams tab — two panels: team list (left) and player-to-team assignment (right).
class _TournamentTeamsTab extends ConsumerStatefulWidget {
  final Tournament tournament;
  final SportTypeConfig config;
  const _TournamentTeamsTab({required this.tournament, required this.config});

  @override
  ConsumerState<_TournamentTeamsTab> createState() => _TournamentTeamsTabState();
}

class _TournamentTeamsTabState extends ConsumerState<_TournamentTeamsTab> {
  bool _loading = true;
  List<({Team team, int? teamNumber, Map<int, int> boards})> _teamData = [];
  Map<int, Player> _playerMap = {};
  int? _selectedTeamId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final teamSvc = ref.read(teamServiceProvider);
    final tId = widget.tournament.t_id!;
    final data = await teamSvc.getTeamsForTournament(tId);

    final players = await ref.read(playerProvider.future);
    final pMap = <int, Player>{
      for (final p in players)
        if (p.player_id != null) p.player_id!: p
    };

    if (mounted) {
      setState(() {
        _teamData = data;
        _playerMap = pMap;
        _loading = false;
        // Keep selection if still valid
        if (_selectedTeamId != null && !data.any((d) => d.team.team_id == _selectedTeamId)) {
          _selectedTeamId = null;
        }
      });
    }
  }

  String _playerLabel(int? playerId) {
    if (playerId == null) return '—';
    final p = _playerMap[playerId];
    if (p == null) return '—';
    final initName = p.player_name.isNotEmpty ? ' ${p.player_name[0]}.' : '';
    return '${p.player_surname}$initName';
  }

  void _reloadData() {
    setState(() => _loading = true);
    _loadData();
  }

  void _showAddTeamDialog() {
    final nameC = TextEditingController();
    final numberC = TextEditingController(text: '${_teamData.length + 1}');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Додати команду'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameC,
              decoration: const InputDecoration(
                labelText: 'Назва команди',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: numberC,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Номер команди',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Скасувати'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameC.text.trim();
              if (name.isEmpty) return;
              final num = int.tryParse(numberC.text.trim()) ?? (_teamData.length + 1);
              // Create team and add to tournament
              await ref.read(teamProvider.notifier).addTeam(name: name);
              // Get newly created team
              final allTeams = await ref.read(teamProvider.future);
              final newTeam = allTeams.where((t) => t.team_name == name).lastOrNull;
              if (newTeam != null) {
                final service = ref.read(teamServiceProvider);
                // Create empty board assignments to register team in tournament
                await service.saveAssignments(newTeam.team_id!, widget.tournament.t_id!, {}, []);
                await service.setTeamNumber(newTeam.team_id!, widget.tournament.t_id!, num);
              }
              if (ctx.mounted) Navigator.pop(ctx);
              _reloadData();
            },
            child: const Text('Зберегти'),
          ),
        ],
      ),
    );
  }

  Future<void> _removeTeamFromTournament(Team team) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Видалити команду з турніру?'),
        content: Text('Видалити склад команди "${team.team_name}" з цього турніру?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Скасувати')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Видалити', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final service = ref.read(teamServiceProvider);
      await service.saveAssignments(team.team_id!, widget.tournament.t_id!, {}, []);
      if (_selectedTeamId == team.team_id) _selectedTeamId = null;
      _reloadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final selectedData = _selectedTeamId != null
        ? _teamData.where((d) => d.team.team_id == _selectedTeamId).firstOrNull
        : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left panel: team list
        Expanded(
          flex: 2,
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: Colors.grey.shade300, width: 1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Команди',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Список команд турніру.',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _showAddTeamDialog,
                        icon: const Icon(Icons.add_circle_outline, size: 18),
                        label: const Text('Додати'),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.indigo,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  if (_teamData.isEmpty)
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.groups_outlined, size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                              'Команд поки немає',
                              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.separated(
                        itemCount: _teamData.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final d = _teamData[index];
                          final isSelected = d.team.team_id == _selectedTeamId;
                          return ListTile(
                            selected: isSelected,
                            selectedTileColor: Colors.indigo.shade50,
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: isSelected ? Colors.indigo : Colors.grey.shade300,
                              child: Text(
                                '${d.teamNumber ?? ''}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isSelected ? Colors.white : Colors.black87,
                                ),
                              ),
                            ),
                            title: Text(d.team.team_name),
                            trailing: IconButton(
                              icon: Icon(Icons.remove_circle_outline, color: Colors.red.shade300, size: 20),
                              tooltip: 'Видалити з турніру',
                              onPressed: () => _removeTeamFromTournament(d.team),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                            onTap: () => setState(() => _selectedTeamId = d.team.team_id),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        // Right panel: player assignment for selected team
        Expanded(
          flex: 3,
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: Colors.grey.shade300, width: 1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: selectedData == null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.touch_app_outlined, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          Text(
                            'Оберіть команду зліва',
                            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'для призначення гравців на позиції.',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Склад: ${selectedData.team.team_name}',
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Призначте гравців на позиції.',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => TeamEditScreen(
                                      team: selectedData.team,
                                      tId: widget.tournament.t_id!,
                                      config: widget.config,
                                    ),
                                  ),
                                );
                                _reloadData();
                              },
                              icon: const Icon(Icons.edit, size: 18),
                              label: const Text('Редагувати'),
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        Expanded(
                          child: ListView.separated(
                            itemCount: widget.config.boardCount,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final boardNum = index + 1;
                              final playerId = selectedData.boards[boardNum];
                              final label = _playerLabel(playerId);
                              return ListTile(
                                leading: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: playerId != null ? Colors.green.shade100 : Colors.grey.shade200,
                                  child: Text(
                                    '$boardNum',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: playerId != null ? Colors.green.shade800 : Colors.grey.shade600,
                                    ),
                                  ),
                                ),
                                title: Text(widget.config.shortTabLabel(boardNum)),
                                subtitle: Text(label, style: const TextStyle(fontSize: 13)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Reports tab — generates and exports a PDF with board cross-tables and team ratings.
class ReportsTab extends ConsumerStatefulWidget {
  final Tournament tournament;
  final SportTypeConfig config;
  const ReportsTab({super.key, required this.tournament, required this.config});

  @override
  @override
  ConsumerState<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends ConsumerState<ReportsTab> {
  bool _loading = true;
  Map<int, List<({int teamId, String teamName, int? teamNumber, Player player})>> _boardPlayers = {};
  Map<int, Map<int, Map<int, double>>> _boardResults = {};
  Map<int, Map<int, Map<int, String>>> _boardResultDetails = {};

  bool get _isTableTennis => widget.tournament.t_type == 11;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final teamSvc = ref.read(teamServiceProvider);
    final tournamentSvc = ref.read(tournamentServiceProvider);
    final tId = widget.tournament.t_id!;

    final boards = await teamSvc.getBoardAssignmentsForTournament(tId);
    final games = await tournamentSvc.getGamesGroupedByBoard(tId);
    final allTeams = await teamSvc.getTeamListForTournament(tId);

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
    final noShowIds = await teamSvc.getNoShowPlayerIds(tId);

    // Add phantom "absent" entries for teams missing from each board.
    final absentIds = <int>{...noShowIds};
    for (final boardNum in boards.keys) {
      final presentTeamIds = boards[boardNum]!.map((p) => p.teamId).toSet();
      for (final team in allTeams) {
        if (presentTeamIds.contains(team.teamId)) continue;
        final phantomId = -(team.teamId * 100 + boardNum);
        absentIds.add(phantomId);
        boards[boardNum]!.add((
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
        results[boardNum]!.putIfAbsent(phantomId, () => {});
        for (final realPlayer in boards[boardNum]!) {
          final realId = realPlayer.player.player_id!;
          if (realId == phantomId || absentIds.contains(realId)) continue;
          results[boardNum]![phantomId]![realId] = 0.0;
          results[boardNum]!.putIfAbsent(realId, () => {})[phantomId] = 1.0;
        }
      }
    }
    // Cross-set absent vs absent (phantom + no-show): both get 0
    for (final boardNum in boards.keys) {
      final absentOnBoard = boards[boardNum]!
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

    if (mounted) {
      setState(() {
        _boardPlayers = boards;
        _boardResults = results;
        _boardResultDetails = details;
        _loading = false;
      });
    }
  }

  double _totalPoints(int boardNum, int playerId) {
    return (_boardResults[boardNum]?[playerId] ?? {}).values.fold(0.0, (sum, r) => sum + r);
  }

  double _bergerCoefficient(int boardNum, int playerId) {
    final results = _boardResults[boardNum]?[playerId] ?? {};
    double sb = 0;
    for (final entry in results.entries) {
      final result = entry.value;
      final opponentPoints = _totalPoints(boardNum, entry.key);
      if (result == 1.0) {
        sb += opponentPoints;
      } else if (result == 0.5) {
        sb += opponentPoints * 0.5;
      }
    }
    return sb;
  }

  List<({int teamId, String teamName, int? teamNumber, Player player})> _sortedStandings(
    int boardNum,
    List<({int teamId, String teamName, int? teamNumber, Player player})> players,
  ) {
    final sorted = List.of(players);
    sorted.sort((a, b) {
      final aId = a.player.player_id!;
      final bId = b.player.player_id!;
      final pa = _totalPoints(boardNum, aId);
      final pb = _totalPoints(boardNum, bId);
      if (pa != pb) return pb.compareTo(pa);
      final aVsB = _boardResults[boardNum]?[aId]?[bId];
      final bVsA = _boardResults[boardNum]?[bId]?[aId];
      if (aVsB != null && bVsA != null) {
        if (aVsB > bVsA) return -1;
        if (aVsB < bVsA) return 1;
      }
      final ba = _bergerCoefficient(boardNum, aId);
      final bb = _bergerCoefficient(boardNum, bId);
      return bb.compareTo(ba);
    });
    return sorted;
  }

  int _gamesPlayed(int boardNum, int playerId) {
    return (_boardResults[boardNum]?[playerId] ?? {}).length;
  }

  ({double a, double b}) _teamMatchScore(int teamAId, int teamBId) {
    double aTotal = 0;
    double bTotal = 0;
    for (final boardEntry in _boardPlayers.entries) {
      final boardNum = boardEntry.key;
      final playerA = boardEntry.value.where((p) => p.teamId == teamAId).firstOrNull;
      final playerB = boardEntry.value.where((p) => p.teamId == teamBId).firstOrNull;
      if (playerA == null || playerB == null) continue;
      final aResult = _boardResults[boardNum]?[playerA.player.player_id!]?[playerB.player.player_id!];
      final bResult = _boardResults[boardNum]?[playerB.player.player_id!]?[playerA.player.player_id!];
      if (aResult != null) aTotal += aResult;
      if (bResult != null) bTotal += bResult;
    }
    return (a: aTotal, b: bTotal);
  }

  ({double a, double b}) _teamMatchPoints(int teamAId, int teamBId) {
    final score = _teamMatchScore(teamAId, teamBId);
    if (score.a > score.b) return (a: 2.0, b: 0.0);
    if (score.b > score.a) return (a: 0.0, b: 2.0);
    if (score.a > 0 || score.b > 0) return (a: 1.0, b: 1.0);
    return (a: 0.0, b: 0.0);
  }

  String _fmtPts(double points) {
    if (points == points.roundToDouble()) return points.toStringAsFixed(1);
    String s = points.toStringAsFixed(2);
    if (s.endsWith('0')) s = s.substring(0, s.length - 1);
    return s;
  }

  String _fmtResult(double? result) {
    if (result == null) return '';
    if (result == 1.0) return '1';
    if (result == 0.0) return '0';
    if (result == 0.5) return '1/2';
    return result.toString();
  }

  /// Format table tennis result for PDF: "3:1 (11:7, 11:4, ...)"
  String _fmtResultTT(int boardNum, int rowId, int colId) {
    final detail = _boardResultDetails[boardNum]?[rowId]?[colId];
    final result = _boardResults[boardNum]?[rowId]?[colId];
    if (result == null) return '';
    if (detail == null || detail.isEmpty) return _fmtResult(result);
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

  Future<pw.Document> _buildPdf() async {
    final pdf = pw.Document();
    final tournamentName = widget.tournament.t_name;
    final boards = _boardPlayers.keys.toList()..sort();

    // Load Times New Roman from Windows system fonts (available on all Windows PCs)
    pw.Font fontRegular;
    pw.Font fontBold;
    try {
      final regBytes = await File('C:\\Windows\\Fonts\\times.ttf').readAsBytes();
      final boldBytes = await File('C:\\Windows\\Fonts\\timesbd.ttf').readAsBytes();
      fontRegular = pw.Font.ttf(ByteData.sublistView(regBytes));
      fontBold = pw.Font.ttf(ByteData.sublistView(boldBytes));
    } catch (_) {
      // Fallback to Noto Sans if not on Windows
      fontRegular = await PdfGoogleFonts.notoSansRegular();
      fontBold = await PdfGoogleFonts.notoSansBold();
    }
    final theme = pw.ThemeData.withFont(base: fontRegular, bold: fontBold);

    // --- Board cross-tables (landscape pages) ---
    // Matches the UI's _buildCombinedTable: cross-table + standings side by side
    for (final boardNum in boards) {
      final rawPlayers = _boardPlayers[boardNum] ?? [];
      if (rawPlayers.isEmpty) continue;

      // Sort by team number (same as UI _buildCombinedTable)
      final players = List.of(rawPlayers)
        ..sort((a, b) {
          final aNum = a.teamNumber ?? 9999;
          final bNum = b.teamNumber ?? 9999;
          if (aNum != bNum) return aNum.compareTo(bNum);
          return a.teamName.compareTo(b.teamName);
        });
      final n = players.length;
      final sorted = _sortedStandings(boardNum, players);
      final boardLabel = widget.config.tabLabel(boardNum);

      // Build cross-table + standings as one wide table (identical to UI)
      final hdrStyle = pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold);
      final cellSt = pw.TextStyle(fontSize: 7, font: fontRegular);
      final cellBold = pw.TextStyle(fontSize: 7, font: fontBold, fontWeight: pw.FontWeight.bold);

      // Cross-table columns: №к, Команда, ПІБ, [1..n], Бали, Ігор, К.Б.
      // Standings columns: №к, ПІБ, Команда, Бали, К.Б., Місце
      final totalCols = 3 + n + 3 + 6; // cross(3+n+3) + standings(6)

      final headerCells = <pw.Widget>[
        _pdfCell('№к', hdrStyle, align: pw.Alignment.center),
        _pdfCell('Команда', hdrStyle, align: pw.Alignment.center),
        _pdfCell('ПІБ', hdrStyle, align: pw.Alignment.center),
        for (int i = 0; i < n; i++)
          _pdfCell('${i + 1}', hdrStyle, align: pw.Alignment.center),
        _pdfCell('Бали', hdrStyle, align: pw.Alignment.center),
        _pdfCell('Ігор', hdrStyle, align: pw.Alignment.center),
        _pdfCell('К.Б.', hdrStyle, align: pw.Alignment.center),
        // Standings
        _pdfCell('№к', hdrStyle, align: pw.Alignment.center),
        _pdfCell('ПІБ', hdrStyle, align: pw.Alignment.center),
        _pdfCell('Команда', hdrStyle, align: pw.Alignment.center),
        _pdfCell('Бали', hdrStyle, align: pw.Alignment.center),
        _pdfCell('К.Б.', hdrStyle, align: pw.Alignment.center),
        _pdfCell('Місце', hdrStyle, align: pw.Alignment.center),
      ];

      final dataTableRows = <pw.TableRow>[];
      // Header
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
          // Cross-table part
          _pdfCell('${p.teamNumber ?? ''}', cellSt),
          _pdfCell(p.teamName, cellSt, align: pw.Alignment.centerLeft),
          _pdfCell('${p.player.player_surname} ${p.player.player_name}'.trim(), nameStyle, align: pw.Alignment.centerLeft),
          for (int j = 0; j < n; j++)
            if (i == j)
              _pdfDiagonalCell()
            else
              _pdfCell(
                _isTableTennis
                    ? _fmtResultTT(boardNum, pId, players[j].player.player_id!)
                    : _fmtResult(_boardResults[boardNum]?[pId]?[players[j].player.player_id!]),
                cellSt,
              ),
          _pdfCell(_fmtPts(_totalPoints(boardNum, pId)), cellBold),
          _pdfCell('${_gamesPlayed(boardNum, pId)}', cellSt),
          _pdfCell(_fmtPts(_bergerCoefficient(boardNum, pId)), cellSt),
          // Standings part
          _pdfCell('${s.teamNumber ?? ''}', cellSt),
          _pdfCell('${s.player.player_surname} ${s.player.player_name}'.trim(), cellSt, align: pw.Alignment.centerLeft),
          _pdfCell(s.teamName, cellSt, align: pw.Alignment.centerLeft),
          _pdfCell(_fmtPts(_totalPoints(boardNum, sId)), cellBold),
          _pdfCell(_fmtPts(_bergerCoefficient(boardNum, sId)), cellSt),
          _pdfCell('${i + 1}', cellBold),
        ];

        dataTableRows.add(pw.TableRow(decoration: rowBg, children: cells));
      }

      // Column widths
      final colWidths = <int, pw.TableColumnWidth>{
        0: const pw.FixedColumnWidth(22),  // №к
        1: const pw.FlexColumnWidth(2),    // Команда
        2: const pw.FlexColumnWidth(3),    // ПІБ
        for (int i = 0; i < n; i++)
          3 + i: pw.FixedColumnWidth(_isTableTennis ? 52 : 20),
        3 + n: const pw.FixedColumnWidth(28),     // Бали
        3 + n + 1: const pw.FixedColumnWidth(24), // Ігор
        3 + n + 2: const pw.FixedColumnWidth(28), // К.Б.
        // Standings
        3 + n + 3: const pw.FixedColumnWidth(22),  // №к
        3 + n + 4: const pw.FlexColumnWidth(3),    // ПІБ
        3 + n + 5: const pw.FlexColumnWidth(2),    // Команда
        3 + n + 6: const pw.FixedColumnWidth(28),  // Бали
        3 + n + 7: const pw.FixedColumnWidth(28),  // К.Б.
        3 + n + 8: const pw.FixedColumnWidth(30),  // Місце
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

    // --- Team standings page (matches UI _buildTeamsTab) ---
    final teamMap = <int, ({String teamName, int? teamNumber})>{};
    for (final boardEntry in _boardPlayers.entries) {
      for (final p in boardEntry.value) {
        teamMap.putIfAbsent(p.teamId, () => (teamName: p.teamName, teamNumber: p.teamNumber));
      }
    }

    if (teamMap.isNotEmpty) {
      final teamIds = teamMap.keys.toList();
      final teamPoints = <int, double>{};
      final teamBoardDiff = <int, double>{};
      final teamBoard3Pts = <int, double>{};
      for (final aId in teamIds) {
        double total = 0;
        double boardWins = 0;
        double boardLosses = 0;
        for (final bId in teamIds) {
          if (aId == bId) continue;
          total += _teamMatchPoints(aId, bId).a;
          final score = _teamMatchScore(aId, bId);
          boardWins += score.a;
          boardLosses += score.b;
        }
        teamPoints[aId] = total;
        teamBoardDiff[aId] = boardWins - boardLosses;
        final lastBoard = widget.config.boardCount;
        final b3p = (_boardPlayers[lastBoard] ?? []).where((p) => p.teamId == aId).firstOrNull;
        teamBoard3Pts[aId] = b3p != null ? _totalPoints(lastBoard, b3p.player.player_id!) : 0;
      }

      // Sort: points → h2h → board diff between them → board diff in tournament → women's racket
      teamIds.sort((a, b) {
        final pa = teamPoints[a]!;
        final pb = teamPoints[b]!;
        if (pa != pb) return pb.compareTo(pa);
        final h2h = _teamMatchPoints(a, b);
        if (h2h.a > h2h.b) return -1;
        if (h2h.b > h2h.a) return 1;
        final directScore = _teamMatchScore(a, b);
        final directDiffA = directScore.a - directScore.b;
        final directDiffB = directScore.b - directScore.a;
        if (directDiffA != directDiffB) return directDiffB.compareTo(directDiffA);
        final bdA = teamBoardDiff[a]!;
        final bdB = teamBoardDiff[b]!;
        if (bdA != bdB) return bdB.compareTo(bdA);
        return teamBoard3Pts[b]!.compareTo(teamBoard3Pts[a]!);
      });

      final tn = teamIds.length;
      final hdrStyle = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);
      final cellSt = pw.TextStyle(fontSize: 8, font: fontRegular);
      final cellBold = pw.TextStyle(fontSize: 8, font: fontBold, fontWeight: pw.FontWeight.bold);

      // Header: №, Команда, [team1..teamN], Очки, Р.Д., Ж.Р., Місце
      final teamHdrCells = <pw.Widget>[
        _pdfCell('№', hdrStyle),
        _pdfCell('Команда', hdrStyle, align: pw.Alignment.center),
        for (int i = 0; i < tn; i++)
          _pdfCell('${teamMap[teamIds[i]]!.teamNumber ?? (i + 1)}', hdrStyle),
        _pdfCell('Очки', hdrStyle),
        _pdfCell('Р.Д.', hdrStyle),
        _pdfCell('Ж.${widget.config.boardAbbrev}.', hdrStyle),
        _pdfCell('Місце', hdrStyle),
      ];

      final teamTableRows = <pw.TableRow>[
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: teamHdrCells,
        ),
      ];

      for (int i = 0; i < tn; i++) {
        final tid = teamIds[i];
        final rowBg = i.isOdd ? const pw.BoxDecoration(color: PdfColors.grey100) : null;

        final cells = <pw.Widget>[
          _pdfCell('${teamMap[tid]!.teamNumber ?? (i + 1)}', cellSt),
          _pdfCell(teamMap[tid]!.teamName, cellSt, align: pw.Alignment.centerLeft),
          for (int j = 0; j < tn; j++)
            if (i == j)
              _pdfDiagonalCell()
            else
              _pdfTeamResultCell(tid, teamIds[j], cellSt, cellBold),
          _pdfCell(_fmtPts(teamPoints[tid]!), cellBold),
          _pdfCell(_fmtPts(teamBoardDiff[tid]!), cellSt),
          _pdfCell(_fmtPts(teamBoard3Pts[tid]!), cellSt),
          _pdfCell('${i + 1}', cellBold),
        ];

        teamTableRows.add(pw.TableRow(decoration: rowBg, children: cells));
      }

      final teamColWidths = <int, pw.TableColumnWidth>{
        0: const pw.FixedColumnWidth(28), // №
        1: const pw.FlexColumnWidth(3),   // Команда
        for (int i = 0; i < tn; i++)
          2 + i: const pw.FixedColumnWidth(44),
        2 + tn: const pw.FixedColumnWidth(36),     // Очки
        2 + tn + 1: const pw.FixedColumnWidth(32), // Р.Д.
        2 + tn + 2: const pw.FixedColumnWidth(32), // Ж.Р.
        2 + tn + 3: const pw.FixedColumnWidth(36), // Місце
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

  pw.Widget _pdfCell(String text, pw.TextStyle style, {pw.Alignment align = pw.Alignment.center}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      alignment: align,
      child: pw.Text(text, style: style, textAlign: align == pw.Alignment.centerLeft ? pw.TextAlign.left : pw.TextAlign.center),
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

  pw.Widget _pdfTeamResultCell(int teamAId, int teamBId, pw.TextStyle cellSt, pw.TextStyle cellBold) {
    final matchPts = _teamMatchPoints(teamAId, teamBId);
    final boardScore = _teamMatchScore(teamAId, teamBId);
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

  Future<void> _exportPdf() async {
    final doc = await _buildPdf();
    final bytes = await doc.save();
    final name = widget.tournament.t_name.replaceAll(RegExp(r'[^\w\s\-]'), '').trim();
    await Printing.sharePdf(bytes: bytes, filename: 'Звіт_$name.pdf');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final hasData = _boardPlayers.isNotEmpty;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade300, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.summarize_outlined, color: Colors.indigo.shade400),
                const SizedBox(width: 12),
                const Text(
                  'Звіти турніру',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Експорт поточного стану турніру у PDF-документ.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const Divider(height: 32),
            if (!hasData)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.info_outline, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'Немає даних для звіту',
                        style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Додайте учасників та розподіліть їх по ${widget.config.boardLabelPlural}.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              _reportCard(
                icon: Icons.picture_as_pdf,
                title: 'Повний звіт',
                description: 'Крос-таблиці всіх дошок та командний залік.',
                onTap: _exportPdf,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _reportCard({
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.indigo.shade100, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: Colors.red.shade400, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(description, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ],
                ),
              ),
              Icon(Icons.download_outlined, color: Colors.indigo.shade300),
            ],
          ),
        ),
      ),
    );
  }
}
