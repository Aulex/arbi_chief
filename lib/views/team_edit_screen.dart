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

  /// Board members ordered by board number (index 0 = board 1, etc.)
  List<int> _members = [];

  /// Bench (reserve) players
  List<int> _reserves = [];

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _nameC = TextEditingController(text: widget.team.team_name);
    _loadAssignments();
  }

  Future<void> _loadAssignments() async {
    final service = ref.read(teamServiceProvider);
    // Load board members in board-number order
    final boardMembers = await service.getBoardMembers(widget.team.team_id!);
    // Load reserves
    final assignments = await service.getTeamAssignments(widget.team.team_id!);
    final reserves = assignments
        .where((a) => a.player_state == 1)
        .map((a) => a.player_id)
        .toList();
    setState(() {
      _members = boardMembers;
      _reserves = reserves;
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
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
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
              Expanded(
                child: _buildBoardCard(allPlayers),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: _buildBenchCard(allPlayers),
              ),
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

  /// Card for board assignments (main roster with board numbers).
  Widget _buildBoardCard(List<Player> allPlayers) {
    final assigned = allPlayers
        .where((p) => _members.contains(p.player_id))
        .toList();
    // Sort assigned by their position in _members
    assigned.sort((a, b) =>
        _members.indexOf(a.player_id!).compareTo(_members.indexOf(b.player_id!)));

    final usedIds = {..._members, ..._reserves};
    final available = allPlayers
        .where((p) => !usedIds.contains(p.player_id))
        .toList();

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
              'Дошки (${_members.length})',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Гравці основного складу з номерами дошок.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const Divider(height: 24),
            // Add player dropdown
            DropdownButtonFormField<int?>(
              key: ValueKey('board_${usedIds.length}'),
              value: null,
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                hintText: 'Додати гравця на дошку...',
              ),
              items: available.map((p) => DropdownMenuItem<int?>(
                    value: p.player_id,
                    child: Text(p.fullName),
                  )).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _members.add(value));
                }
              },
            ),
            const SizedBox(height: 12),
            // Board list
            ...List.generate(assigned.length, (index) {
              final player = assigned[index];
              final boardNum = index + 1;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.indigo,
                  child: Text(
                    '$boardNum',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                title: Text(player.fullName),
                subtitle: Text('Дошка $boardNum'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Move up
                    IconButton(
                      icon: const Icon(Icons.arrow_upward, size: 20),
                      onPressed: index > 0
                          ? () {
                              setState(() {
                                final id = _members.removeAt(index);
                                _members.insert(index - 1, id);
                              });
                            }
                          : null,
                    ),
                    // Move down
                    IconButton(
                      icon: const Icon(Icons.arrow_downward, size: 20),
                      onPressed: index < assigned.length - 1
                          ? () {
                              setState(() {
                                final id = _members.removeAt(index);
                                _members.insert(index + 1, id);
                              });
                            }
                          : null,
                    ),
                    // Remove
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline,
                          color: Colors.red),
                      onPressed: () =>
                          setState(() => _members.remove(player.player_id!)),
                    ),
                  ],
                ),
              );
            }),
            if (assigned.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Немає гравців на дошках',
                  style: TextStyle(color: Colors.grey.shade500),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Card for bench (reserve) players.
  Widget _buildBenchCard(List<Player> allPlayers) {
    final assigned = allPlayers
        .where((p) => _reserves.contains(p.player_id))
        .toList();

    final usedIds = {..._members, ..._reserves};
    final available = allPlayers
        .where((p) => !usedIds.contains(p.player_id))
        .toList();

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
            // Add player dropdown
            DropdownButtonFormField<int?>(
              key: ValueKey('bench_${usedIds.length}'),
              value: null,
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
            // Bench list
            ...assigned.map((p) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.grey.shade400,
                    child: const Icon(Icons.event_seat, size: 16, color: Colors.white),
                  ),
                  title: Text(p.fullName),
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle_outline,
                        color: Colors.red),
                    onPressed: () =>
                        setState(() => _reserves.remove(p.player_id!)),
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
    await service.saveAssignments(widget.team.team_id!, _members, _reserves);

    ref.invalidate(teamProvider);

    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}
