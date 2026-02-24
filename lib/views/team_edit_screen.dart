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

  // slot 1-3 = Дошка 1-3, slot 4-6 = Запасний 1-3
  final Map<int, int?> _slotToPlayerId = {
    1: null,
    2: null,
    3: null,
    4: null,
    5: null,
    6: null,
  };

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
      for (final a in assignments) {
        if (_slotToPlayerId.containsKey(a.player_state)) {
          _slotToPlayerId[a.player_state] = a.player_id;
        }
      }
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
    // Separate female players for Дошка 3
    final femalePlayers =
        allPlayers.where((p) => p.player_gender == 1).toList();

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
          // Roster card
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
                    'Склад команди',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Призначте гравців на дошки та запасних.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const Divider(height: 24),
                  _buildSlotDropdown(
                    slot: 1,
                    label: 'Дошка 1',
                    players: allPlayers,
                  ),
                  const SizedBox(height: 12),
                  _buildSlotDropdown(
                    slot: 2,
                    label: 'Дошка 2',
                    players: allPlayers,
                  ),
                  const SizedBox(height: 12),
                  _buildSlotDropdown(
                    slot: 3,
                    label: 'Дошка 3',
                    subtitle: 'Тільки жінки',
                    players: femalePlayers,
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 12),
                  _buildSlotDropdown(
                    slot: 4,
                    label: 'Запасний 1',
                    players: allPlayers,
                  ),
                  const SizedBox(height: 12),
                  _buildSlotDropdown(
                    slot: 5,
                    label: 'Запасний 2',
                    players: allPlayers,
                  ),
                  const SizedBox(height: 12),
                  _buildSlotDropdown(
                    slot: 6,
                    label: 'Запасний 3',
                    players: allPlayers,
                  ),
                ],
              ),
            ),
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

  Widget _buildSlotDropdown({
    required int slot,
    required String label,
    String? subtitle,
    required List<Player> players,
  }) {
    final selectedId = _slotToPlayerId[slot];
    // Ensure selected value exists in the player list
    final validSelected =
        players.any((p) => p.player_id == selectedId) ? selectedId : null;

    return Row(
      children: [
        SizedBox(
          width: 140,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.orange.shade700,
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: DropdownButtonFormField<int?>(
            value: validSelected,
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            hint: const Text('Оберіть гравця'),
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('— Не обрано —'),
              ),
              ...players.map((p) => DropdownMenuItem<int?>(
                    value: p.player_id,
                    child: Text(p.fullName),
                  )),
            ],
            onChanged: (value) {
              setState(() {
                _slotToPlayerId[slot] = value;
              });
            },
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final name = _nameC.text.trim();
    if (name.isEmpty) return;

    final updatedTeam = widget.team.copyWith(team_name: name);
    await ref.read(teamServiceProvider).saveTeam(updatedTeam);
    await ref
        .read(teamServiceProvider)
        .saveAssignments(widget.team.team_id!, _slotToPlayerId);

    ref.invalidate(teamProvider);

    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}
