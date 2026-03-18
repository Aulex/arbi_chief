import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/player_model.dart';
import '../models/team_model.dart';
import '../viewmodels/player_viewmodel.dart';
import '../viewmodels/team_viewmodel.dart';
import '../viewmodels/tournament_viewmodel.dart';

/// Players tab — single list of tournament players with search, add, and create new.
class TournamentPlayersTab extends ConsumerStatefulWidget {
  final int tId;
  final int? tType;
  const TournamentPlayersTab({super.key, required this.tId, required this.tType});

  @override
  ConsumerState<TournamentPlayersTab> createState() => TournamentPlayersTabState();
}

class TournamentPlayersTabState extends ConsumerState<TournamentPlayersTab> {
  List<Player> _participants = [];
  List<Player> _available = [];
  bool _loading = true;
  String _search = '';
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
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

  void _showEditPlayerDialog(Player player) {
    final nameC = TextEditingController(text: player.player_name);
    final surnameC = TextEditingController(text: player.player_surname);
    final lastnameC = TextEditingController(text: player.player_lastname);
    final dobC = TextEditingController(text: player.birthDateForUI);
    int gender = player.player_gender;

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

    Future<void> saveEdit(BuildContext dialogContext) async {
      if (nameC.text.trim().isEmpty || surnameC.text.trim().isEmpty) return;
      await ref.read(playerProvider.notifier).updatePlayer(
        player.copyWith(
          player_name: nameC.text.trim(),
          player_surname: surnameC.text.trim(),
          player_lastname: lastnameC.text.trim(),
          player_gender: gender,
          player_date_birth: Player.formatForDB(dobC.text.trim()),
        ),
      );
      if (dialogContext.mounted) Navigator.pop(dialogContext);
      _loadData();
    }

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setST) {
          return Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.enter &&
                  (HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlLeft) ||
                   HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlRight))) {
                saveEdit(dialogContext);
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
                    const Row(
                      children: [
                        Icon(Icons.edit, color: Colors.indigo),
                        SizedBox(width: 12),
                        Text(
                          'Редагувати гравця',
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
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Скасувати'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => saveEdit(dialogContext),
                          child: const Text('Зберегти (Ctrl+Enter)'),
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

  void _removePlayer(Player player) {
    setState(() {
      _participants.removeWhere((p) => p.player_id == player.player_id);
      _available
        ..add(player)
        ..sort((a, b) => a.player_surname.compareTo(b.player_surname));
    });
    ref.read(tournamentServiceProvider).removeParticipant(widget.tId, player.player_id!);
  }

  void _showBulkImportDialog() {
    _focusNode.unfocus();
    final textC = TextEditingController();
    bool importing = false;
    String? error;
    int importedCount = 0;

    List<_ParsedPlayer> _parseText(String text) {
      final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
      final result = <_ParsedPlayer>[];
      for (final line in lines) {
        // Split by tab (Excel), semicolon, or spaces
        final parts = line
            .split(RegExp(r'\t|;|\s+'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (parts.isEmpty) continue;
        result.add(_ParsedPlayer(
          surname: parts.isNotEmpty ? parts[0] : '',
          name: parts.length > 1 ? parts[1] : '',
          lastname: parts.length > 2 ? parts[2] : '',
        ));
      }
      return result;
    }

    // Use controller listener to catch ALL text changes (typing, paste, programmatic)
    late void Function(void Function()) _setST;
    textC.addListener(() {
      _setST(() {});
    });

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setST) {
          _setST = setST;
          final parsed = _parseText(textC.text);
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600, maxHeight: 600),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.upload_file, color: Colors.indigo),
                        SizedBox(width: 12),
                        Text(
                          'Швидкий імпорт гравців',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Вставте дані з Excel (Ctrl+V). Кожен рядок — один гравець.\n'
                      'Формат: Прізвище  Ім\'я  По батькові (розділені табуляцією або ;)',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: TextField(
                        controller: textC,
                        autofocus: true,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        decoration: InputDecoration(
                          hintText: 'Іваненко\tІван\tІванович\nПетренко\tПетро\tПетрович',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                        onChanged: (_) {
                          setST(() => error = null);
                        },
                      ),
                    ),
                    if (parsed.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Розпізнано гравців: ${parsed.length}',
                        style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.indigo),
                      ),
                      const SizedBox(height: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 120),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: parsed.length,
                          itemBuilder: (_, i) {
                            final p = parsed[i];
                            final genderLabel = Player.detectGender(p.name, p.lastname) == 0 ? 'Ч' : 'Ж';
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 1),
                              child: Text(
                                '${i + 1}. ${p.surname} ${p.name} ${p.lastname} ($genderLabel)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: p.surname.isEmpty ? Colors.red : Colors.black87,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: importing ? null : () => Navigator.pop(dialogContext),
                          child: const Text('Скасувати'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: importing || parsed.isEmpty
                              ? null
                              : () async {
                                  setST(() => importing = true);
                                  try {
                                    final validPlayers = parsed.where((p) => p.surname.isNotEmpty).toList();
                                    // Bulk-insert all players in a single transaction
                                    final playerIds = await ref.read(playerProvider.notifier).bulkAddPlayers(
                                      validPlayers.map((p) => (
                                        surname: p.surname,
                                        name: p.name,
                                        lastname: p.lastname,
                                        gender: Player.detectGender(p.name, p.lastname),
                                        dob: '',
                                      )).toList(),
                                    );
                                    // Bulk-add all new players to tournament in a single transaction
                                    await ref.read(tournamentServiceProvider)
                                        .bulkAddParticipants(widget.tId, playerIds);
                                    importedCount = playerIds.length;
                                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                                    _loadData();
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Імпортовано гравців: $importedCount')),
                                      );
                                    }
                                  } catch (e) {
                                    setST(() {
                                      importing = false;
                                      error = 'Помилка: $e';
                                    });
                                  }
                                },
                          icon: importing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.download_done),
                          label: Text(importing ? 'Імпорт...' : 'Імпортувати (${parsed.length})'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                          ),
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

  void _showBulkImportTeamsDialog() {
    _focusNode.unfocus();
    final textC = TextEditingController();
    bool importing = false;
    String? error;

    List<_ParsedTeamPlayer> _parseText(String text) {
      final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
      final result = <_ParsedTeamPlayer>[];
      for (final line in lines) {
        List<String> parts;
        if (line.contains('\t')) {
          // Tab-separated (Excel paste)
          parts = line.split('\t').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        } else if (line.contains(';')) {
          // Semicolon-separated
          parts = line.split(';').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        } else {
          // Space-separated
          parts = line.trim().split(RegExp(r'\s+'));
        }
        // Format: Прізвище Ім'я По батькові Команда
        if (parts.length < 3) continue; // need at least surname + name + lastname (team optional)
        final surname = parts[0];
        final name = parts[1];
        final lastname = parts[2];
        final teamName = parts.length >= 4 ? parts.sublist(3).join(' ') : '';
        if (teamName.isEmpty) continue; // team is required for this import
        result.add(_ParsedTeamPlayer(
          teamName: teamName,
          surname: surname,
          name: name,
          lastname: lastname,
        ));
      }
      return result;
    }

    // Use controller listener to catch ALL text changes (typing, paste, programmatic)
    late void Function(void Function()) _setST;
    textC.addListener(() {
      _setST(() {});
    });

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setST) {
          _setST = setST;
          // Parse fresh from controller on every build
          final parsed = _parseText(textC.text);
          // Group by team for preview
          final teamGroups = <String, List<_ParsedTeamPlayer>>{};
          for (final p in parsed) {
            teamGroups.putIfAbsent(p.teamName, () => []).add(p);
          }

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700, maxHeight: 650),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.group_add, color: Colors.indigo),
                        SizedBox(width: 12),
                        Text(
                          'Імпорт гравців/команд',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Вставте дані з Excel (Ctrl+V). Кожен рядок — один гравець.\n'
                      'Формат: Прізвище\tІм\'я\tПо батькові\tКоманда',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: TextField(
                        controller: textC,
                        autofocus: true,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        decoration: InputDecoration(
                          hintText: 'Іваненко\tІван\tІванович\tДинамо\nПетренко\tПетро\tПетрович\tДинамо\nСидоренко\tСидір\tСидорович\tШахтар',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                        onChanged: (_) {
                          setST(() => error = null);
                        },
                      ),
                    ),
                    if (teamGroups.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Розпізнано: ${teamGroups.length} команд, ${parsed.length} гравців',
                        style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.indigo),
                      ),
                      const SizedBox(height: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 150),
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            for (final entry in teamGroups.entries) ...[
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '${entry.key} (${entry.value.length})',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                              for (var i = 0; i < entry.value.length; i++)
                                Padding(
                                  padding: const EdgeInsets.only(left: 16),
                                  child: Text(
                                    '${i + 1}. ${entry.value[i].surname} ${entry.value[i].name} ${entry.value[i].lastname} '
                                    '(${Player.detectGender(entry.value[i].name, entry.value[i].lastname) == 0 ? 'Ч' : 'Ж'})',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: entry.value[i].surname.isEmpty ? Colors.red : Colors.black87,
                                    ),
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: importing ? null : () => Navigator.pop(dialogContext),
                          child: const Text('Скасувати'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: importing || parsed.isEmpty
                              ? null
                              : () async {
                                  setST(() => importing = true);
                                  try {
                                    final teamSvc = ref.read(teamServiceProvider);
                                    final playerNotifier = ref.read(playerProvider.notifier);
                                    final tournamentSvc = ref.read(tournamentServiceProvider);
                                    final tType = widget.tType;

                                    // Group by team
                                    final groups = <String, List<_ParsedTeamPlayer>>{};
                                    for (final p in parsed) {
                                      if (p.surname.isEmpty) continue;
                                      groups.putIfAbsent(p.teamName, () => []).add(p);
                                    }

                                    int totalPlayers = 0;
                                    int totalTeams = 0;

                                    for (final entry in groups.entries) {
                                      final teamName = entry.key;
                                      final players = entry.value;

                                      // Create or find team
                                      final allTeams = await teamSvc.getAllTeams(tType: tType);
                                      var team = allTeams.cast<Team?>().firstWhere(
                                        (t) => t!.team_name.toLowerCase() == teamName.toLowerCase(),
                                        orElse: () => null,
                                      );
                                      if (team == null) {
                                        team = await teamSvc.saveTeam(Team(
                                          team_name: teamName,
                                          t_type: tType,
                                        ));
                                        totalTeams++;
                                      }

                                      // Bulk-create players
                                      final playerIds = await playerNotifier.bulkAddPlayers(
                                        players.map((p) => (
                                          surname: p.surname,
                                          name: p.name,
                                          lastname: p.lastname,
                                          gender: Player.detectGender(p.name, p.lastname),
                                          dob: '',
                                        )).toList(),
                                      );

                                      // Add players to tournament
                                      await tournamentSvc.bulkAddParticipants(widget.tId, playerIds);

                                      // Assign players to team in tournament
                                      // Get existing team number or assign next
                                      final existingTeams = await teamSvc.getTeamsForTournament(widget.tId);
                                      final maxNum = existingTeams.fold<int>(0, (m, t) => t.teamNumber != null && t.teamNumber! > m ? t.teamNumber! : m);
                                      final isAlreadyRegistered = existingTeams.any((t) => t.team.team_id == team!.team_id);

                                      if (!isAlreadyRegistered) {
                                        await teamSvc.registerTeamInTournament(team.team_id!, widget.tId, maxNum + 1);
                                      }

                                      // Get current board members and add new players as reserves
                                      final currentBoards = await teamSvc.getBoardMembers(team.team_id!, widget.tId);
                                      final currentReserves = await teamSvc.getTeamMemberIds(team.team_id!, widget.tId);
                                      final allReserves = [...currentReserves, ...playerIds];
                                      await teamSvc.saveAssignments(team.team_id!, widget.tId, currentBoards, allReserves);

                                      totalPlayers += playerIds.length;
                                    }

                                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                                    _loadData();
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Імпортовано: $totalPlayers гравців у $totalTeams нових команд')),
                                      );
                                    }
                                  } catch (e) {
                                    setST(() {
                                      importing = false;
                                      error = 'Помилка: $e';
                                    });
                                  }
                                },
                          icon: importing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.download_done),
                          label: Text(importing ? 'Імпорт...' : 'Імпортувати (${parsed.length})'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                          ),
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

  void _showAddPlayerDialog() {
    final nameC = TextEditingController();
    final surnameC = TextEditingController();
    final lastnameC = TextEditingController();
    final dobC = TextEditingController();
    int gender = 0;
    String searchQuery = '';
    Player? selectedExisting;
    List<Player> allPlayers = [];

    // Load all players for search
    ref.read(playerProvider.future).then((players) {
      allPlayers = players;
    });

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
      if (nameC.text.trim().isEmpty || surnameC.text.trim().isEmpty) return;

      if (selectedExisting != null) {
        // Update existing player data and add to tournament
        await ref.read(playerProvider.notifier).updatePlayer(
          selectedExisting!.copyWith(
            player_name: nameC.text.trim(),
            player_surname: surnameC.text.trim(),
            player_lastname: lastnameC.text.trim(),
            player_gender: gender,
            player_date_birth: Player.formatForDB(dobC.text.trim()),
          ),
        );
        await ref.read(tournamentServiceProvider).addParticipant(widget.tId, selectedExisting!.player_id!);
      } else {
        // Create new player
        await ref.read(playerProvider.notifier).addPlayer(
          name: nameC.text.trim(),
          surname: surnameC.text.trim(),
          lastname: lastnameC.text.trim(),
          gender: gender,
          dob: dobC.text.trim(),
        );
        // Auto-add newly created player to the tournament
        final updatedPlayers = await ref.read(playerProvider.future);
        final newPlayer = updatedPlayers
            .where((p) =>
                p.player_surname == surnameC.text.trim() &&
                p.player_name == nameC.text.trim())
            .lastOrNull;
        if (newPlayer != null && newPlayer.player_id != null) {
          await ref.read(tournamentServiceProvider).addParticipant(widget.tId, newPlayer.player_id!);
        }
      }
      if (dialogContext.mounted) Navigator.pop(dialogContext);
      _loadData();
    }

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setST) {
          final participantIds = _participants.map((p) => p.player_id).toSet();
          final searchResults = searchQuery.length >= 2
              ? allPlayers.where((p) {
                  if (participantIds.contains(p.player_id)) return false;
                  return p.fullName.toLowerCase().contains(searchQuery.toLowerCase());
                }).take(8).toList()
              : <Player>[];

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
                          const Expanded(
                            child: Text(
                              'Додати гравця',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
                      // Search bar for existing players
                      Autocomplete<Player>(
                        optionsBuilder: (textEditingValue) {
                          if (textEditingValue.text.length < 2) return const Iterable<Player>.empty();
                          return allPlayers.where((p) {
                            if (participantIds.contains(p.player_id)) return false;
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
                            onChanged: (v) => setST(() => searchQuery = v),
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
                            searchQuery = '';
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
                              autofocus: true,
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

    final filtered = _search.isEmpty
        ? _participants
        : _participants.where((p) => p.fullName.toLowerCase().contains(_search.toLowerCase())).toList();

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.insert ||
              event.logicalKey == LogicalKeyboardKey.numpadAdd) {
            _showAddPlayerDialog();
            return KeyEventResult.handled;
          }
          // Ctrl+I for bulk import
          if (event.logicalKey == LogicalKeyboardKey.keyI &&
              (HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlLeft) ||
               HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlRight))) {
            _showBulkImportDialog();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
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
                OutlinedButton.icon(
                  onPressed: _showBulkImportDialog,
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: const Text('Імпорт гравців'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.indigo,
                    side: const BorderSide(color: Colors.indigo),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _showBulkImportTeamsDialog,
                  icon: const Icon(Icons.group_add, size: 18),
                  label: const Text('Імпорт гравців/команд'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.indigo,
                    side: const BorderSide(color: Colors.indigo),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                const SizedBox(width: 8),
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
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.edit, color: Colors.grey.shade600, size: 18),
                                tooltip: 'Редагувати гравця',
                                onPressed: () => _showEditPlayerDialog(player),
                              ),
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                                tooltip: 'Видалити з турніру',
                                onPressed: () => _removePlayer(player),
                              ),
                            ],
                          ),
                          contentPadding: EdgeInsets.zero,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _ParsedPlayer {
  final String surname;
  final String name;
  final String lastname;
  const _ParsedPlayer({required this.surname, required this.name, required this.lastname});
}

class _ParsedTeamPlayer {
  final String teamName;
  final String surname;
  final String name;
  final String lastname;
  const _ParsedTeamPlayer({required this.teamName, required this.surname, required this.name, required this.lastname});
}
