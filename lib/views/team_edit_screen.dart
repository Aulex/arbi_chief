import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/team_model.dart';
import '../models/player_model.dart';
import '../viewmodels/team_viewmodel.dart';
import '../viewmodels/player_viewmodel.dart';
import '../services/team_service.dart';

class TeamEditScreen extends ConsumerStatefulWidget {
  final Team team;
  const TeamEditScreen({super.key, required this.team});

  @override
  ConsumerState<TeamEditScreen> createState() => _TeamEditScreenState();
}

class _TeamEditScreenState extends ConsumerState<TeamEditScreen> {
  late TextEditingController _nameC;

  /// Board assignments: board number → player ID (null = empty board)
  Map<int, int?> _boards = {1: null, 2: null, 3: null};

  /// Bench (reserve) players
  List<int> _reserves = [];

  /// Players already assigned to other teams.
  Set<int> _takenByOtherTeams = {};

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _nameC = TextEditingController(text: widget.team.team_name);
    _loadAssignments();
  }

  Future<void> _loadAssignments() async {
    final service = ref.read(teamServiceProvider);
    final boardMembers = await service.getBoardMembers(widget.team.team_id!);
    final assignments = await service.getTeamAssignments(widget.team.team_id!);
    final reserves = assignments
        .where((a) => a.player_state == 1)
        .map((a) => a.player_id)
        .toList();
    final taken = await service.getPlayersInOtherTeams(widget.team.team_id!);
    setState(() {
      _boards = {
        1: boardMembers[1],
        2: boardMembers[2],
        3: boardMembers[3],
      };
      _reserves = reserves;
      _takenByOtherTeams = taken;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _nameC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playersAsync = ref.watch(playerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Редагування команди'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : playersAsync.when(
              data: (allPlayers) => _buildForm(context, allPlayers),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, s) => Center(child: Text('Помилка: $e')),
            ),
    );
  }

  Widget _buildForm(BuildContext context, List<Player> allPlayers) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Team name card
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
                  const Text(
                    'Назва команди',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameC,
                    decoration: const InputDecoration(
                      labelText: 'Назва команди',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Boards & Bench
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildBoardCard(allPlayers)),
              const SizedBox(width: 20),
              Expanded(child: _buildBenchCard(allPlayers)),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Скасувати'),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.indigo,
                ),
                onPressed: _save,
                child: const Text('Зберегти'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// IDs of all players currently used (boards + bench).
  Set<int> get _usedIds {
    final ids = <int>{};
    for (final id in _boards.values) {
      if (id != null) ids.add(id);
    }
    ids.addAll(_reserves);
    return ids;
  }

  /// Available players for a given board (excludes taken, used, other teams).
  List<Player> _availableForBoard(int boardNum, List<Player> allPlayers) {
    final used = _usedIds;
    // Current player on this board is also "available" (to keep selection)
    final currentId = _boards[boardNum];
    final list = allPlayers
        .where((p) =>
            p.player_id == currentId ||
            (!used.contains(p.player_id) && !_takenByOtherTeams.contains(p.player_id)))
        .toList();
    list.sort((a, b) => a.player_surname.compareTo(b.player_surname));
    return list;
  }

  Widget _buildBoardCard(List<Player> allPlayers) {
    final assignedCount = _boards.values.where((id) => id != null).length;

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
            Text(
              'Дошки ($assignedCount)',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Оберіть гравця для кожної дошки.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const Divider(height: 24),
            for (int boardNum = 1; boardNum <= 3; boardNum++)
              _buildBoardRow(boardNum, allPlayers),
          ],
        ),
      ),
    );
  }

  Widget _buildBoardRow(int boardNum, List<Player> allPlayers) {
    final available = _availableForBoard(boardNum, allPlayers);
    final currentId = _boards[boardNum];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Colors.indigo,
            child: Text(
              '$boardNum',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<int?>(
              key: ValueKey('board_${boardNum}_${_usedIds.length}'),
              value: currentId,
              isExpanded: true,
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                labelText: 'Дошка $boardNum',
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('— Не обрано —', style: TextStyle(color: Colors.grey)),
                ),
                ...available.map((p) => DropdownMenuItem<int?>(
                      value: p.player_id,
                      child: Text(p.fullName),
                    )),
              ],
              onChanged: (value) {
                setState(() => _boards[boardNum] = value);
              },
            ),
          ),
          if (currentId != null)
            IconButton(
              icon: const Icon(Icons.clear, color: Colors.red, size: 20),
              onPressed: () => setState(() => _boards[boardNum] = null),
            ),
        ],
      ),
    );
  }

  /// Card for bench (reserve) players.
  Widget _buildBenchCard(List<Player> allPlayers) {
    final assigned = allPlayers
        .where((p) => _reserves.contains(p.player_id))
        .toList();

    final used = _usedIds;
    final available = allPlayers
        .where((p) => !used.contains(p.player_id))
        .where((p) => !_takenByOtherTeams.contains(p.player_id))
        .toList()
      ..sort((a, b) => a.player_surname.compareTo(b.player_surname));

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
            Text(
              'Лава запасних (${_reserves.length})',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Запасні гравці команди.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const Divider(height: 24),
            DropdownButtonFormField<int?>(
              key: ValueKey('bench_${used.length}'),
              value: null,
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                hintText: 'Додати запасного гравця...',
              ),
              items: available.map((p) => DropdownMenuItem<int?>(
                    value: p.player_id,
                    child: Text(p.fullName),
                  )).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _reserves.add(value));
                }
              },
            ),
            const SizedBox(height: 12),
            ...assigned.map((p) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.grey.shade400,
                    child: const Icon(Icons.event_seat, size: 16, color: Colors.white),
                  ),
                  title: Text(p.fullName),
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                    onPressed: () => setState(() => _reserves.remove(p.player_id!)),
                  ),
                )),
            if (assigned.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Немає запасних гравців',
                  style: TextStyle(color: Colors.grey.shade500),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameC.text.trim();
    if (name.isEmpty) return;

    final updatedTeam = widget.team.copyWith(team_name: name);
    final service = ref.read(teamServiceProvider);
    await service.saveTeam(updatedTeam);

    // Build non-null board assignments
    final boardMembers = <int, int>{};
    for (final entry in _boards.entries) {
      if (entry.value != null) boardMembers[entry.key] = entry.value!;
    }
    await service.saveAssignments(widget.team.team_id!, boardMembers, _reserves);

    ref.invalidate(teamProvider);

    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}
