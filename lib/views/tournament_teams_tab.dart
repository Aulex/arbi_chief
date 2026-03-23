import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/tournament_model.dart';
import '../models/team_model.dart';
import '../models/player_model.dart';
import '../models/sport_type_config.dart';
import '../viewmodels/player_viewmodel.dart';
import '../viewmodels/team_viewmodel.dart';
import '../viewmodels/tournament_viewmodel.dart';

/// Teams tab — two panels: team list (left) and player-to-team assignment (right).
class TournamentTeamsTab extends ConsumerStatefulWidget {
  final Tournament tournament;
  final SportTypeConfig config;
  const TournamentTeamsTab({super.key, required this.tournament, required this.config});

  @override
  ConsumerState<TournamentTeamsTab> createState() => _TournamentTeamsTabState();
}

class _TournamentTeamsTabState extends ConsumerState<TournamentTeamsTab> {
  bool _loading = true;
  List<({Team team, int? teamNumber, Map<int, int> boards})> _teamData = [];
  Map<int, Player> _playerMap = {};
  Map<int, List<int>> _teamMembers = {}; // team_id → list of member player IDs (for swimming)
  int? _selectedTeamId;
  String _teamSearch = '';
  String _playerSearch = '';
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final teamSvc = ref.read(teamServiceProvider);
    final tId = widget.tournament.t_id!;
    final data = await teamSvc.getTeamsForTournament(tId);

    final tournamentSvc = ref.read(tournamentServiceProvider);
    final participants = await tournamentSvc.getParticipants(tId);
    final pMap = <int, Player>{
      for (final p in participants)
        if (p.player_id != null) p.player_id!: p
    };

    // For swimming (no boards), load team members (reserves)
    final membersMap = <int, List<int>>{};
    if (widget.config.boardCount == 0) {
      for (final d in data) {
        final members = await teamSvc.getTeamMemberIds(d.team.team_id!, tId);
        membersMap[d.team.team_id!] = members;
      }
    }

    if (mounted) {
      setState(() {
        _teamData = data;
        _teamMembers = membersMap;
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

  Future<void> _showBoardPlayerPicker(int boardNum, ({Team team, int? teamNumber, Map<int, int> boards}) teamData) async {
    String search = '';
    // Get all players, excluding those already assigned to boards in this team (except current board)
    final assignedPlayerIds = <int>{};
    for (final entry in teamData.boards.entries) {
      if (entry.key != boardNum && entry.value != 0) {
        assignedPlayerIds.add(entry.value);
      }
    }
    // Also exclude players assigned to other teams
    final allTeamPlayerIds = <int>{};
    for (final td in _teamData) {
      if (td.team.team_id == teamData.team.team_id) continue;
      allTeamPlayerIds.addAll(td.boards.values);
    }

    // Load existing reserves to preserve them
    final service = ref.read(teamServiceProvider);
    final assignments = await service.getTeamAssignments(teamData.team.team_id!, widget.tournament.t_id!);
    final existingReserves = assignments
        .where((a) => a.player_state == 1 && a.player_id != null)
        .map((a) => a.player_id!)
        .toList();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setST) {
          final allPlayers = _playerMap.values.toList()
            ..sort((a, b) => a.player_surname.compareTo(b.player_surname));
          final available = allPlayers.where((p) {
            if (assignedPlayerIds.contains(p.player_id)) return false;
            if (allTeamPlayerIds.contains(p.player_id)) return false;
            if (search.isNotEmpty && !p.fullName.toLowerCase().contains(search.toLowerCase())) return false;
            
            // Gender constraint for board 3 (or last board) if configured
            if (widget.config.lastBoardWomenOnly && boardNum == widget.config.boardCount) {
              if (p.player_gender != 1) return false;
            }
            
            return true;
          }).toList();

          final currentPlayerId = teamData.boards[boardNum];
          final currentPlayer = currentPlayerId != null ? _playerMap[currentPlayerId] : null;

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
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.indigo,
                          child: Text('$boardNum', style: const TextStyle(color: Colors.white, fontSize: 14)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${widget.config.shortTabLabel(boardNum)} — ${teamData.team.team_name}',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    if (currentPlayer != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text('Поточний: ${currentPlayer.fullName}', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: () async {
                              final svc = ref.read(teamServiceProvider);
                              // Remove current player from this board
                              final newBoards = Map<int, int>.from(teamData.boards)..remove(boardNum);
                              await svc.saveAssignments(teamData.team.team_id!, widget.tournament.t_id!, newBoards, existingReserves);
                              if (dialogContext.mounted) Navigator.pop(dialogContext);
                              _reloadData();
                            },
                            icon: const Icon(Icons.clear, size: 16, color: Colors.red),
                            label: const Text('Зняти', style: TextStyle(color: Colors.red, fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    // Load reserves to preserve them
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Пошук гравця...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (v) => setST(() => search = v),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: available.isEmpty
                          ? const Center(child: Text('Немає доступних гравців'))
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: available.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final player = available[index];
                                return ListTile(
                                  dense: true,
                                  title: Text(player.fullName),
                                  subtitle: player.birthDateForUI.isNotEmpty
                                      ? Text(player.birthDateForUI, style: const TextStyle(fontSize: 12))
                                      : null,
                                  trailing: const Icon(Icons.add_circle_outline, color: Colors.green),
                                  contentPadding: EdgeInsets.zero,
                                  onTap: () async {
                                    final svc = ref.read(teamServiceProvider);
                                    final newBoards = Map<int, int>.from(teamData.boards);
                                    newBoards[boardNum] = player.player_id!;
                                    await svc.saveAssignments(teamData.team.team_id!, widget.tournament.t_id!, newBoards, existingReserves);
                                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                                    _reloadData();
                                  },
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            _showAddPlayerToTournamentAndBoard(teamData, preselectedBoard: boardNum);
                          },
                          icon: const Icon(Icons.person_add, size: 18),
                          label: const Text('Додати гравця'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Закрити'),
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

  void _showEditTeamDialog(Team team, {int? currentTeamNumber}) {
    final nameC = TextEditingController(text: team.team_name);
    final numberC = TextEditingController(text: currentTeamNumber?.toString() ?? '');

    Future<void> saveEdit(BuildContext ctx) async {
      final name = nameC.text.trim();
      final numberText = numberC.text.trim();
      final newNumber = numberText.isEmpty ? null : int.tryParse(numberText);
      final nameChanged = name.isNotEmpty && name != team.team_name;
      final numberChanged = newNumber != currentTeamNumber;
      if (!nameChanged && !numberChanged) {
        Navigator.pop(ctx);
        return;
      }
      if (nameChanged) {
        await ref.read(teamProvider.notifier).updateTeam(team.copyWith(team_name: name));
      }
      if (numberChanged && newNumber != null && team.team_id != null && widget.tournament.t_id != null) {
        final service = ref.read(teamServiceProvider);
        await service.setTeamNumber(team.team_id!, widget.tournament.t_id!, newNumber);
      }
      if (ctx.mounted) Navigator.pop(ctx);
      _reloadData();
    }

    showDialog(
      context: context,
      builder: (ctx) => Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.enter &&
              (HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlLeft) ||
               HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlRight))) {
            saveEdit(ctx);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: AlertDialog(
          title: const Text('Редагувати команду'),
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
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
              onPressed: () => saveEdit(ctx),
              child: const Text('Зберегти (Ctrl+Enter)'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddTeamDialog() {
    final nameC = TextEditingController();
    final numberC = TextEditingController(text: '${_teamData.length + 1}');
    Team? selectedExisting;
    List<Team> allTeams = [];

    // Load all teams for search
    ref.read(teamProvider.future).then((teams) {
      allTeams = teams;
    });

    Future<void> saveTeam(BuildContext ctx) async {
      final name = nameC.text.trim();
      if (name.isEmpty) return;
      final num = int.tryParse(numberC.text.trim()) ?? (_teamData.length + 1);

      if (selectedExisting != null) {
        // Register existing team in tournament
        final service = ref.read(teamServiceProvider);
        await service.registerTeamInTournament(selectedExisting!.team_id!, widget.tournament.t_id!, num);
      } else {
        // Create new team and register
        final newTeam = await ref.read(teamProvider.notifier).addTeam(name: name);
        final service = ref.read(teamServiceProvider);
        await service.registerTeamInTournament(newTeam.team_id!, widget.tournament.t_id!, num);
      }
      if (ctx.mounted) Navigator.pop(ctx);
      _reloadData();
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setST) {
          final registeredTeamIds = _teamData.map((d) => d.team.team_id).toSet();

          return Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.enter &&
                  (HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlLeft) ||
                   HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlRight))) {
                saveTeam(ctx);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.groups_outlined, color: Colors.indigo),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Додати команду',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (selectedExisting != null)
                            Chip(
                              label: Text(selectedExisting!.team_name, style: const TextStyle(fontSize: 12)),
                              deleteIcon: const Icon(Icons.close, size: 16),
                              onDeleted: () {
                                setST(() {
                                  selectedExisting = null;
                                  nameC.clear();
                                });
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Search bar for existing teams
                      Autocomplete<Team>(
                        optionsBuilder: (textEditingValue) {
                          if (textEditingValue.text.length < 2) return const Iterable<Team>.empty();
                          return allTeams.where((t) {
                            if (registeredTeamIds.contains(t.team_id)) return false;
                            return t.team_name.toLowerCase().contains(textEditingValue.text.toLowerCase());
                          }).take(8);
                        },
                        displayStringForOption: (team) => team.team_name,
                        fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
                          return TextField(
                            controller: textController,
                            focusNode: focusNode,
                            decoration: InputDecoration(
                              hintText: 'Пошук з бази команд...',
                              prefixIcon: const Icon(Icons.search, size: 20),
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                          );
                        },
                        onSelected: (team) {
                          setST(() {
                            selectedExisting = team;
                            nameC.text = team.team_name;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      const Divider(),
                      const SizedBox(height: 16),
                      TextField(
                        controller: nameC,
                        decoration: InputDecoration(
                          labelText: 'Назва команди',
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: numberC,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Номер команди',
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Скасувати'),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => saveTeam(ctx),
                            child: Text(selectedExisting != null ? 'Додати (Ctrl+Enter)' : 'Створити (Ctrl+Enter)'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
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
      await service.removeTeamFromTournament(team.team_id!, widget.tournament.t_id!);
      if (_selectedTeamId == team.team_id) _selectedTeamId = null;
      _reloadData();
    }
  }

  void _showAddPlayerToTournamentAndBoard(({Team team, int? teamNumber, Map<int, int> boards}) teamData, {int? preselectedBoard}) {
    final nameC = TextEditingController();
    final surnameC = TextEditingController();
    final lastnameC = TextEditingController();
    final dobC = TextEditingController();
    int gender = 0;
    Player? selectedExisting;
    List<Player> allPlayers = [];
    int? selectedBoard;

    ref.read(playerProvider.future).then((players) {
      allPlayers = players;
    });

    // Use preselected board or find first empty board
    if (preselectedBoard != null) {
      selectedBoard = preselectedBoard;
    } else {
      for (int i = 1; i <= widget.config.boardCount; i++) {
        if (!teamData.boards.containsKey(i)) {
          selectedBoard = i;
          break;
        }
      }
    }

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

    Future<void> savePlayer(BuildContext dialogContext) async {
      if (surnameC.text.trim().isEmpty || nameC.text.trim().isEmpty) return;
      
      // Gender validation for board 3 (or last board) if configured
      if (widget.config.lastBoardWomenOnly && selectedBoard == widget.config.boardCount) {
        if (gender != 1) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('На цю ${widget.config.boardLabel.toLowerCase()}у можна призначати тільки жінок'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }

      final tournamentSvc = ref.read(tournamentServiceProvider);
      final teamSvc = ref.read(teamServiceProvider);
      int playerId;

      if (selectedExisting != null) {
        // Update and add existing player
        await ref.read(playerProvider.notifier).updatePlayer(
          selectedExisting!.copyWith(
            player_name: nameC.text.trim(),
            player_surname: surnameC.text.trim(),
            player_lastname: lastnameC.text.trim(),
            player_gender: gender,
            player_date_birth: Player.formatForDB(dobC.text.trim()),
          ),
        );
        playerId = selectedExisting!.player_id!;
      } else {
        // Create new player
        await ref.read(playerProvider.notifier).addPlayer(
          name: nameC.text.trim(),
          surname: surnameC.text.trim(),
          lastname: lastnameC.text.trim(),
          gender: gender,
          dob: dobC.text.trim(),
        );
        final updatedPlayers = await ref.read(playerProvider.future);
        final newPlayer = updatedPlayers
            .where((p) =>
                p.player_surname == surnameC.text.trim() &&
                p.player_name == nameC.text.trim())
            .lastOrNull;
        if (newPlayer == null || newPlayer.player_id == null) return;
        playerId = newPlayer.player_id!;
      }

      // Add to tournament
      await tournamentSvc.addParticipant(widget.tournament.t_id!, playerId);

      // Assign to team
      if (widget.config.boardCount == 0) {
        // Swimming: add as team member (reserve)
        final service = ref.read(teamServiceProvider);
        final assignments = await service.getTeamAssignments(teamData.team.team_id!, widget.tournament.t_id!);
        final existingReserves = assignments
            .where((a) => a.player_state == 1 && a.player_id != null)
            .map((a) => a.player_id!)
            .toList();
        existingReserves.add(playerId);
        await service.saveAssignments(teamData.team.team_id!, widget.tournament.t_id!, teamData.boards, existingReserves);
      } else if (selectedBoard != null) {
        // Board-based sports: assign to board
        final service = ref.read(teamServiceProvider);
        final assignments = await service.getTeamAssignments(teamData.team.team_id!, widget.tournament.t_id!);
        final existingReserves = assignments
            .where((a) => a.player_state == 1 && a.player_id != null)
            .map((a) => a.player_id!)
            .toList();
        final newBoards = Map<int, int>.from(teamData.boards);
        newBoards[selectedBoard!] = playerId;
        await service.saveAssignments(teamData.team.team_id!, widget.tournament.t_id!, newBoards, existingReserves);
      }

      if (dialogContext.mounted) Navigator.pop(dialogContext);
      _reloadData();
    }

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setST) {
          // Get IDs already assigned to any team
          final assignedPlayerIds = <int>{};
          for (final td in _teamData) {
            assignedPlayerIds.addAll(td.boards.values);
          }

          return Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.enter &&
                  (HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlLeft) ||
                   HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlRight))) {
                savePlayer(dialogContext);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 550),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.person_add_alt_1, color: Colors.indigo),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Додати гравця — ${teamData.team.team_name}',
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (selectedExisting != null)
                            Chip(
                              label: Text(selectedExisting!.fullName, style: const TextStyle(fontSize: 12)),
                              deleteIcon: const Icon(Icons.close, size: 16),
                              onDeleted: () {
                                setST(() {
                                  selectedExisting = null;
                                  nameC.clear();
                                  surnameC.clear();
                                  lastnameC.clear();
                                  dobC.clear();
                                  gender = 0;
                                });
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Autocomplete<Player>(
                        optionsBuilder: (textEditingValue) {
                          if (textEditingValue.text.length < 2) return const Iterable<Player>.empty();
                          return allPlayers.where((p) {
                            return p.fullName.toLowerCase().contains(textEditingValue.text.toLowerCase());
                          }).take(8);
                        },
                        displayStringForOption: (player) => player.fullName,
                        fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
                          return TextField(
                            controller: textController,
                            focusNode: focusNode,
                            decoration: InputDecoration(
                              hintText: 'Пошук з бази гравців...',
                              prefixIcon: const Icon(Icons.search, size: 20),
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                          );
                        },
                        onSelected: (player) {
                          setST(() {
                            selectedExisting = player;
                            surnameC.text = player.player_surname;
                            nameC.text = player.player_name;
                            lastnameC.text = player.player_lastname;
                            dobC.text = player.birthDateForUI;
                            gender = player.player_gender;
                          });
                        },
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
                      if (widget.config.lastBoardWomenOnly && selectedBoard == widget.config.boardCount)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, size: 16, color: Colors.orange),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Увага: на цю ${widget.config.boardLabel.toLowerCase()}у можна призначати тільки жінок',
                                  style: const TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (widget.config.boardCount > 0) ...[
                        const SizedBox(height: 16),
                        DropdownButtonFormField<int?>(
                          value: selectedBoard,
                          decoration: InputDecoration(
                            labelText: 'Призначити на ${widget.config.boardLabel.toLowerCase()}у',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          items: [
                            const DropdownMenuItem<int?>(value: null, child: Text('— Не призначати —')),
                            for (int i = 1; i <= widget.config.boardCount; i++)
                              DropdownMenuItem<int?>(
                                value: i,
                                child: Text(widget.config.shortTabLabel(i)),
                              ),
                          ],
                          onChanged: (v) => setST(() => selectedBoard = v),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text('Скасувати'),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => savePlayer(dialogContext),
                            child: Text(selectedExisting != null ? 'Додати (Ctrl+Enter)' : 'Створити (Ctrl+Enter)'),
                          ),
                        ],
                      ),
                    ],
                  ),
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

    final selectedData = _selectedTeamId != null
        ? _teamData.where((d) => d.team.team_id == _selectedTeamId).firstOrNull
        : null;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.insert ||
              event.logicalKey == LogicalKeyboardKey.numpadAdd) {
            _showAddTeamDialog();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Row(
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
                  const SizedBox(height: 8),
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Пошук...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onChanged: (v) => setState(() => _teamSearch = v),
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
                      child: Builder(
                        builder: (context) {
                          final filtered = _teamSearch.isEmpty
                              ? _teamData
                              : _teamData.where((d) => d.team.team_name.toLowerCase().contains(_teamSearch.toLowerCase())).toList();
                          if (filtered.isEmpty) {
                            return Center(
                              child: Text('Нічого не знайдено', style: TextStyle(color: Colors.grey.shade600)),
                            );
                          }
                          return ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final d = filtered[index];
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
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.edit, color: Colors.grey.shade600, size: 18),
                                      tooltip: 'Редагувати назву',
                                      onPressed: () => _showEditTeamDialog(d.team, currentTeamNumber: d.teamNumber),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.remove_circle_outline, color: Colors.red.shade300, size: 20),
                                      tooltip: 'Видалити з турніру',
                                      onPressed: () => _removeTeamFromTournament(d.team),
                                    ),
                                  ],
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                onTap: () => setState(() => _selectedTeamId = d.team.team_id),
                              );
                            },
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
                            widget.config.boardCount == 0
                                ? 'для додавання гравців.'
                                : 'для призначення гравців на позиції.',
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
                                    widget.config.boardCount == 0
                                        ? 'Додайте гравців до команди.'
                                        : 'Призначте гравців на позиції.',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => _showAddPlayerToTournamentAndBoard(selectedData),
                              icon: const Icon(Icons.person_add, size: 18),
                              label: const Text('Новий гравець'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Player search bar
                        TextField(
                          decoration: InputDecoration(
                            hintText: 'Пошук гравця для додавання...',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          onChanged: (v) => setState(() => _playerSearch = v),
                        ),
                        // Search results
                        if (_playerSearch.length >= 2) ...[
                          const SizedBox(height: 4),
                          Builder(
                            builder: (context) {
                              final assignedInThisTeam = selectedData.boards.values.toSet();
                              // Also exclude team members (reserves) for swimming
                              final membersInThisTeam = _teamMembers[selectedData.team.team_id] ?? [];
                              final assignedInOtherTeams = <int>{};
                              for (final td in _teamData) {
                                if (td.team.team_id == selectedData.team.team_id) continue;
                                assignedInOtherTeams.addAll(td.boards.values);
                                assignedInOtherTeams.addAll(_teamMembers[td.team.team_id] ?? []);
                              }
                              final results = _playerMap.values.where((p) {
                                if (assignedInThisTeam.contains(p.player_id)) return false;
                                if (membersInThisTeam.contains(p.player_id)) return false;
                                if (assignedInOtherTeams.contains(p.player_id)) return false;
                                return p.fullName.toLowerCase().contains(_playerSearch.toLowerCase());
                              }).toList()
                                ..sort((a, b) => a.player_surname.compareTo(b.player_surname));
                              final display = results.take(5).toList();

                              if (display.isEmpty) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Text('Нічого не знайдено', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                                );
                              }
                              // Find first empty board (for board-based sports)
                              final bool isNoBoardSport = widget.config.boardCount == 0;
                              int? firstEmptyBoard;
                              if (!isNoBoardSport) {
                                for (int i = 1; i <= widget.config.boardCount; i++) {
                                  if (!selectedData.boards.containsKey(i)) {
                                    firstEmptyBoard = i;
                                    break;
                                  }
                                }
                              }

                              final bool canAdd = isNoBoardSport || firstEmptyBoard != null;

                              return ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 200),
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: display.length,
                                  itemBuilder: (context, index) {
                                    final player = display[index];
                                    return ListTile(
                                      dense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                                      title: Text(player.fullName, style: const TextStyle(fontSize: 13)),
                                      subtitle: player.birthDateForUI.isNotEmpty
                                          ? Text(player.birthDateForUI, style: const TextStyle(fontSize: 11))
                                          : null,
                                      trailing: IconButton(
                                        icon: const Icon(Icons.add_circle, color: Colors.green, size: 24),
                                        tooltip: canAdd
                                            ? (isNoBoardSport
                                                ? 'Додати до команди'
                                                : 'Додати на ${widget.config.shortTabLabel(firstEmptyBoard!)}')
                                            : 'Немає вільних позицій',
                                        onPressed: !canAdd
                                            ? null
                                            : () async {
                                                final svc = ref.read(teamServiceProvider);
                                                final assignments = await svc.getTeamAssignments(
                                                  selectedData.team.team_id!, widget.tournament.t_id!);
                                                final existingReserves = assignments
                                                    .where((a) => a.player_state == 1 && a.player_id != null)
                                                    .map((a) => a.player_id!)
                                                    .toList();
                                                if (isNoBoardSport) {
                                                  // For swimming: add as team member (reserve)
                                                  existingReserves.add(player.player_id!);
                                                  await svc.saveAssignments(
                                                    selectedData.team.team_id!, widget.tournament.t_id!, selectedData.boards, existingReserves);
                                                } else {
                                                  // For board-based sports: assign to first empty board
                                                  final newBoards = Map<int, int>.from(selectedData.boards);
                                                  newBoards[firstEmptyBoard!] = player.player_id!;
                                                  await svc.saveAssignments(
                                                    selectedData.team.team_id!, widget.tournament.t_id!, newBoards, existingReserves);
                                                }
                                                // Also add to tournament participants
                                                final tournamentSvc = ref.read(tournamentServiceProvider);
                                                await tournamentSvc.addParticipant(widget.tournament.t_id!, player.player_id!);
                                                setState(() => _playerSearch = '');
                                                _reloadData();
                                              },
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                        ],
                        const Divider(height: 24),
                        Expanded(
                          child: widget.config.boardCount == 0
                              // Swimming: show team members list
                              ? Builder(
                                  builder: (context) {
                                    final members = _teamMembers[selectedData.team.team_id] ?? [];
                                    if (members.isEmpty) {
                                      return Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.person_outline, size: 40, color: Colors.grey.shade400),
                                            const SizedBox(height: 8),
                                            Text(
                                              'Гравців поки немає',
                                              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Знайдіть гравця через пошук вище.',
                                              style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                    return ListView.separated(
                                      itemCount: members.length,
                                      separatorBuilder: (_, __) => const Divider(height: 1),
                                      itemBuilder: (context, index) {
                                        final playerId = members[index];
                                        final label = _playerLabel(playerId);
                                        return ListTile(
                                          leading: CircleAvatar(
                                            radius: 16,
                                            backgroundColor: Colors.green.shade100,
                                            child: Text(
                                              '${index + 1}',
                                              style: TextStyle(fontSize: 12, color: Colors.green.shade800),
                                            ),
                                          ),
                                          title: Text(label, style: const TextStyle(fontSize: 13)),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                          trailing: IconButton(
                                            icon: Icon(Icons.remove_circle_outline, color: Colors.red.shade300, size: 20),
                                            tooltip: 'Видалити з команди',
                                            onPressed: () async {
                                              final svc = ref.read(teamServiceProvider);
                                              final updatedMembers = List<int>.from(members)..removeAt(index);
                                              await svc.saveAssignments(
                                                selectedData.team.team_id!, widget.tournament.t_id!, selectedData.boards, updatedMembers);
                                              _reloadData();
                                            },
                                          ),
                                        );
                                      },
                                    );
                                  },
                                )
                              // Board-based sports: show board positions
                              : ListView.separated(
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
                                      trailing: Icon(Icons.person_search, size: 20, color: Colors.grey.shade500),
                                      onTap: () => _showBoardPlayerPicker(boardNum, selectedData),
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
    ),
    );
  }
}
