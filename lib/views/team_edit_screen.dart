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

  // player_state: 0 = active member, 1 = reserve
  List<int> _members = [];
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
    final assignments = await service.getTeamAssignments(widget.team.team_id!);
    setState(() {
      _members = assignments
          .where((a) => a.player_state == 0)
          .map((a) => a.player_id)
          .toList();
      _reserves = assignments
          .where((a) => a.player_state == 1)
          .map((a) => a.player_id)
          .toList();
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
          // Members & Reserves
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildPlayerListCard(
                  title: 'Основний склад (${_members.length})',
                  subtitle: 'Гравці основного складу команди.',
                  playerIds: _members,
                  allPlayers: allPlayers,
                  onAdd: (playerId) {
                    setState(() => _members.add(playerId));
                  },
                  onRemove: (playerId) {
                    setState(() => _members.remove(playerId));
                  },
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: _buildPlayerListCard(
                  title: 'Запасні (${_reserves.length})',
                  subtitle: 'Запасні гравці команди.',
                  playerIds: _reserves,
                  allPlayers: allPlayers,
                  onAdd: (playerId) {
                    setState(() => _reserves.add(playerId));
                  },
                  onRemove: (playerId) {
                    setState(() => _reserves.remove(playerId));
                  },
                ),
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

  Widget _buildPlayerListCard({
    required String title,
    required String subtitle,
    required List<int> playerIds,
    required List<Player> allPlayers,
    required void Function(int playerId) onAdd,
    required void Function(int playerId) onRemove,
  }) {
    // Players already assigned to this list
    final assigned = allPlayers
        .where((p) => playerIds.contains(p.player_id))
        .toList();
    // Available = not in members and not in reserves
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
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const Divider(height: 24),
            // Add player dropdown
            DropdownButtonFormField<int?>(
              value: null,
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                hintText: 'Додати гравця...',
              ),
              items: available.map((p) => DropdownMenuItem<int?>(
                    value: p.player_id,
                    child: Text(p.fullName),
                  )).toList(),
              onChanged: (value) {
                if (value != null) {
                  onAdd(value);
                }
              },
            ),
            const SizedBox(height: 12),
            // Assigned players list
            ...assigned.map((p) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(p.fullName),
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle_outline,
                        color: Colors.red),
                    onPressed: () => onRemove(p.player_id!),
                  ),
                )),
            if (assigned.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Немає гравців',
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
