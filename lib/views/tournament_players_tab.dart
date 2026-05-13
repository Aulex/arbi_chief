import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/player_model.dart';
import '../models/team_model.dart';
import '../sports/athletics/athletics_providers.dart';
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
  Map<int, int> _playerNumbers = const {};
  Map<int, int> _playerYearsOfBirth = const {};
  int? _referenceYear;
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
    final allPlayersFuture = ref.read(playerProvider.future);

    final participants = await svc.getParticipants(widget.tId);
    if (!mounted) return;

    final allPlayers = await allPlayersFuture;
    if (!mounted) return;

    final isAthletics = widget.tType == 10;
    final numbers = isAthletics
        ? await svc.getPlayerNumbers(widget.tId)
        : const <int, int>{};
    if (!mounted) return;
    final yearsOfBirth = isAthletics
        ? await ref.read(athleticsServiceProvider).getPlayerYearsOfBirth(widget.tId)
        : const <int, int>{};
    if (!mounted) return;
    final referenceYear = isAthletics
        ? await ref.read(athleticsServiceProvider).getTournamentReferenceYear(widget.tId)
        : null;
    if (!mounted) return;

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
        _playerNumbers = numbers;
        _playerYearsOfBirth = yearsOfBirth;
        _referenceYear = referenceYear;
        _loading = false;
      });
    }
  }

  void _showEditPlayerDialog(Player player) {
    final nameC = TextEditingController(text: player.player_name);
    final surnameC = TextEditingController(text: player.player_surname);
    final lastnameC = TextEditingController(text: player.player_lastname);
    final dobC = TextEditingController(text: player.birthDateForUI);
    final ageC = TextEditingController(text: player.player_age != null ? player.player_age.toString() : '');
    final weightC = TextEditingController();
    final numberC = TextEditingController();
    final yobC = TextEditingController();
    int gender = player.player_gender;
    final needsWeight = const {8, 9, 13}.contains(widget.tType);
    final isAthletics = widget.tType == 10;

    // Load existing weight
    if (needsWeight && player.player_id != null) {
      ref.read(tournamentServiceProvider).getPlayerWeight(
        playerId: player.player_id!, tId: widget.tId,
      ).then((w) {
        if (w != null) weightC.text = w.toStringAsFixed(1);
      });
    }

    // Load existing participant number and year of birth
    if (isAthletics && player.player_id != null) {
      ref.read(tournamentServiceProvider).getPlayerNumber(
        playerId: player.player_id!, tId: widget.tId,
      ).then((n) {
        if (n != null) numberC.text = n.toString();
      });
      ref.read(athleticsServiceProvider).getPlayerYearOfBirth(
        playerId: player.player_id!, tId: widget.tId,
      ).then((y) {
        if (y != null) yobC.text = y.toString();
      });
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

    Future<void> saveEdit(BuildContext dialogContext) async {
      if (nameC.text.trim().isEmpty || surnameC.text.trim().isEmpty) return;
      int? parsedAge = int.tryParse(ageC.text.trim());
      await ref.read(playerProvider.notifier).updatePlayer(
        player.copyWith(
          player_name: nameC.text.trim(),
          player_surname: surnameC.text.trim(),
          player_lastname: lastnameC.text.trim(),
          player_gender: gender,
          player_date_birth: Player.formatForDB(dobC.text.trim()),
          player_age: parsedAge,
        ),
      );
      final weightVal = double.tryParse(weightC.text.trim());
      if (weightVal != null && weightVal > 0 && player.player_id != null) {
        await ref.read(tournamentServiceProvider).savePlayerWeight(
          playerId: player.player_id!, tId: widget.tId, weight: weightVal);
      }
      if (isAthletics && player.player_id != null) {
        final numText = numberC.text.trim();
        final numVal = int.tryParse(numText);
        if (numVal != null && numVal > 0) {
          await ref.read(tournamentServiceProvider).savePlayerNumber(
            playerId: player.player_id!, tId: widget.tId, number: numVal);
        } else if (numText.isEmpty) {
          await ref.read(tournamentServiceProvider).clearPlayerNumber(
            playerId: player.player_id!, tId: widget.tId);
        }
        final yobText = yobC.text.trim();
        final yobVal = int.tryParse(yobText);
        final maxYob = _referenceYear ?? DateTime.now().year;
        if (yobVal != null && yobVal >= 1900 && yobVal <= maxYob) {
          await ref.read(athleticsServiceProvider).savePlayerYearOfBirth(
            playerId: player.player_id!, tId: widget.tId, year: yobVal);
        } else if (yobText.isEmpty) {
          await ref.read(athleticsServiceProvider).clearPlayerYearOfBirth(
            playerId: player.player_id!, tId: widget.tId);
        }
      }
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
                        if (!isAthletics) ...[
                          Expanded(
                            flex: 2,
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
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: ageC,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: InputDecoration(
                              labelText: 'Вік (опц.)',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 1,
                          child: DropdownButtonFormField<int>(
                            value: gender,
                            decoration: InputDecoration(
                              labelText: 'Стать',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            items: const [
                              DropdownMenuItem(value: 0, child: Text('Чол')),
                              DropdownMenuItem(value: 1, child: Text('Жін')),
                            ],
                            onChanged: (v) => setST(() => gender = v!),
                          ),
                        ),
                      ],
                    ),
                    if (needsWeight) ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: weightC,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                        decoration: InputDecoration(
                          labelText: 'Вага (кг)',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                    if (isAthletics) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: numberC,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: InputDecoration(
                                labelText: 'Номер учасника',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: yobC,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(4),
                              ],
                              decoration: InputDecoration(
                                labelText: 'Рік народження',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                        ],
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

  void _showBulkImportTeamsDialog() {
    _focusNode.unfocus();
    final textC = TextEditingController();
    int format = 0; // 0: ПІБ + Команда, 1: ПІ + Команда
    bool importing = false;
    String? error;

    List<_ParsedTeamPlayer> parseText(String text, int fmt) {
      text = text.replaceAll(RegExp(r'[\u00A0\u2000-\u200B\u200C\u200D\u202F\u205F\u2060\u3000\uFEFF]'), ' ');
      final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
      final result = <_ParsedTeamPlayer>[];
      for (final line in lines) {
        List<String> parts = line.split(RegExp(r'\t|;')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        int? age;
        if (parts.length >= 3) {
          final lastPart = parts.last;
          final parsedAge = int.tryParse(lastPart);
          if (parsedAge != null && parsedAge > 4 && parsedAge < 150) {
            age = parsedAge;
            parts.removeLast();
          }
        }

        if (parts.length == 1) {
          final spaceParts = line.split(RegExp(r'\s+')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
          int? spaceAge;
          if (spaceParts.length >= 4) {
            final lastSpace = spaceParts.last;
            final parsedSpaceAge = int.tryParse(lastSpace);
            if (parsedSpaceAge != null && parsedSpaceAge > 4 && parsedSpaceAge < 150) {
              spaceAge = parsedSpaceAge;
              spaceParts.removeLast();
            }
          }

          if (fmt == 0) {
            if (spaceParts.length >= 4) {
              result.add(_ParsedTeamPlayer(surname: spaceParts[0], name: spaceParts[1], lastname: spaceParts[2], teamName: spaceParts.sublist(3).join(' '), age: spaceAge));
            }
          } else {
            if (spaceParts.length >= 3) {
              result.add(_ParsedTeamPlayer(surname: spaceParts[0], name: spaceParts[1], lastname: '', teamName: spaceParts.sublist(2).join(' '), age: spaceAge));
            }
          }
        } else if (parts.length == 2) {
          // Two tab-separated fields: first = "Surname Name [Patronymic]", second = team
          final nameParts = parts[0].split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
          final teamName = parts[1];
          if (fmt == 0) {
            if (nameParts.length >= 2) {
              result.add(_ParsedTeamPlayer(
                surname: nameParts[0],
                name: nameParts[1],
                lastname: nameParts.length > 2 ? nameParts.sublist(2).join(' ') : '',
                teamName: teamName,
                age: age,
              ));
            }
          } else {
            if (nameParts.length >= 2) {
              result.add(_ParsedTeamPlayer(
                surname: nameParts[0],
                name: nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '',
                lastname: '',
                teamName: teamName,
                age: age,
              ));
            }
          }
        } else {
          if (fmt == 0) {
            if (parts.length >= 4) {
              result.add(_ParsedTeamPlayer(surname: parts[0], name: parts[1], lastname: parts[2], teamName: parts.sublist(3).join(' '), age: age));
            }
          } else {
            if (parts.length >= 3) {
              result.add(_ParsedTeamPlayer(
                surname: parts[0],
                name: parts[1],
                lastname: '',
                teamName: parts.sublist(2).join(' '),
                age: age,
              ));
            }
          }
        }
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
          final parsed = parseText(textC.text, format);
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
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('Формат:', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 12),
                        ChoiceChip(
                          label: const Text('ПІБ + Команда'),
                          selected: format == 0,
                          onSelected: (v) => setST(() => format = 0),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('ПІ + Команда'),
                          selected: format == 1,
                          onSelected: (v) => setST(() => format = 1),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      format == 0
                        ? 'Кожен рядок: Прізвище  Ім\'я  По батькові  Команда  Вік (через TAB/;/пробіл). Вік опційно.'
                        : 'Кожен рядок: Прізвище  Ім\'я  Команда  Вік (через TAB/;/пробіл). Вік опційно.',
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
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
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                        onChanged: (_) {
                          setST(() => error = null);
                        },
                      ),
                    ),
                    Builder(builder: (ctx) {
                      final parsed = parseText(textC.text, format);
                      // Group by team for preview
                      final teamGroups = <String, List<_ParsedTeamPlayer>>{};
                      for (final p in parsed) {
                        teamGroups.putIfAbsent(p.teamName, () => []).add(p);
                      }
                      if (teamGroups.isEmpty) return const SizedBox.shrink();
                      
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                                          '(${Player.detectGender(entry.value[i].name, entry.value[i].lastname) == 0 ? 'Ч' : 'Ж'}${entry.value[i].age != null ? ', Вік: ${entry.value[i].age}' : ''})',
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
                      );
                    }),
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
                                    final currentParsed = parseText(textC.text, format);
                                    final teamSvc = ref.read(teamServiceProvider);
                                    final playerNotifier = ref.read(playerProvider.notifier);
                                    final tournamentSvc = ref.read(tournamentServiceProvider);
                                    final tType = widget.tType;
                                    final isAthletics = tType == 10;

                                    // Group by team
                                    final groups = <String, List<_ParsedTeamPlayer>>{};
                                    for (final p in currentParsed) {
                                      if (p.surname.isEmpty) continue;
                                      groups.putIfAbsent(p.teamName, () => []).add(p);
                                    }

                                    int totalPlayers = 0;
                                    int totalTeams = 0;

                                    // For athletics: continue numbering from current max.
                                    int nextNumber = 0;
                                    if (isAthletics) {
                                      final existing = await tournamentSvc.getPlayerNumbers(widget.tId);
                                      nextNumber = existing.values.fold<int>(0, (m, n) => n > m ? n : m) + 1;
                                    }

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
                                          age: p.age,
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

                                      // Athletics: assign sequential participant numbers (max+1, +2 ...)
                                      if (isAthletics) {
                                        for (final pid in playerIds) {
                                          await tournamentSvc.savePlayerNumber(
                                            playerId: pid,
                                            tId: widget.tId,
                                            number: nextNumber,
                                          );
                                          nextNumber++;
                                        }
                                      }

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

  void _showExportDialog() {
    bool includeTeams = true;
    final svc = ref.read(tournamentServiceProvider);
    
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setST) => FutureBuilder<List<Player>>(
          future: svc.getParticipants(widget.tId),
          builder: (ctx, snapshot) {
            String content = 'Завантаження...';
            if (snapshot.hasData) {
              final players = snapshot.data!;
              players.sort((a, b) => a.player_surname.compareTo(b.player_surname));
              
              if (includeTeams) {
                // Fetch team assignments for everyone
                content = '';
                return FutureBuilder<Map<int, Team>>(
                  future: ref.read(teamServiceProvider).getPlayerTeamsMap(widget.tId),
                  builder: (ctx, teamSnapshot) {
                    if (teamSnapshot.hasData) {
                      final teamMap = teamSnapshot.data!;
                      content = players.map((p) {
                        final team = teamMap[p.player_id];
                        return '${p.fullName}${team != null ? ' ${team.team_name}' : ''}';
                      }).join('\n');
                    }
                    return _buildExportUI(ctx, setST, content, includeTeams, (val) => setST(() => includeTeams = val));
                  },
                );
              } else {
                content = players.map((p) => p.fullName).join('\n');
              }
            }
            return _buildExportUI(ctx, setST, content, includeTeams, (val) => setST(() => includeTeams = val));
          },
        ),
      ),
    );
  }

  Widget _buildExportUI(BuildContext ctx, StateSetter setST, String content, bool includeTeams, Function(bool) onToggle) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.output, color: Colors.indigo),
          SizedBox(width: 12),
          Text('Експорт гравців'),
        ],
      ),
      content: SizedBox(
        width: 600,
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Формат:'),
                const SizedBox(width: 16),
                ChoiceChip(
                  label: const Text('Тільки ПІБ'),
                  selected: !includeTeams,
                  onSelected: (val) => onToggle(false),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('ПІБ + Команда'),
                  selected: includeTeams,
                  onSelected: (val) => onToggle(true),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Скопіюйте текст нижче (Ctrl+C):',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                controller: TextEditingController(text: content),
                readOnly: true,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Закрити'),
        ),
        FilledButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: content));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Скопійовано в буфер обміну')),
            );
          },
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Копіювати'),
        ),
      ],
    );
  }

  void _showAddPlayerDialog() {
    final nameC = TextEditingController();
    final surnameC = TextEditingController();
    final lastnameC = TextEditingController();
    final dobC = TextEditingController();
    final weightC = TextEditingController();
    final numberC = TextEditingController();
    final yobC = TextEditingController();
    int gender = 0;
    String searchQuery = '';
    Player? selectedExisting;
    List<Player> allPlayers = [];
    final needsWeight = const {8, 9, 13}.contains(widget.tType);
    final isAthletics = widget.tType == 10;

    // Load all players for search
    ref.read(playerProvider.future).then((players) {
      allPlayers = players;
    });

    // Pre-fill the participant number with max(existing) + 1 for athletics.
    if (isAthletics) {
      ref.read(tournamentServiceProvider)
          .getPlayerNumbers(widget.tId)
          .then((map) {
        if (numberC.text.trim().isEmpty) {
          final maxNum = map.values.fold<int>(0, (m, n) => n > m ? n : m);
          numberC.text = (maxNum + 1).toString();
        }
      });
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
      // Resolve playerId once for any post-creation attribute saves.
      final resolvedPlayerId = selectedExisting?.player_id ??
          (await ref.read(playerProvider.future))
              .where((p) => p.player_surname == surnameC.text.trim() && p.player_name == nameC.text.trim())
              .lastOrNull?.player_id;

      // Save weight if entered
      final weightVal = double.tryParse(weightC.text.trim());
      if (weightVal != null && weightVal > 0 && resolvedPlayerId != null) {
        await ref.read(tournamentServiceProvider).savePlayerWeight(
          playerId: resolvedPlayerId, tId: widget.tId, weight: weightVal);
      }

      // Save participant number if entered (athletics only)
      if (isAthletics && resolvedPlayerId != null) {
        final numVal = int.tryParse(numberC.text.trim());
        if (numVal != null && numVal > 0) {
          await ref.read(tournamentServiceProvider).savePlayerNumber(
            playerId: resolvedPlayerId, tId: widget.tId, number: numVal);
        }
        final yobVal = int.tryParse(yobC.text.trim());
        final maxYob = _referenceYear ?? DateTime.now().year;
        if (yobVal != null && yobVal >= 1900 && yobVal <= maxYob) {
          await ref.read(athleticsServiceProvider).savePlayerYearOfBirth(
            playerId: resolvedPlayerId, tId: widget.tId, year: yobVal);
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
                          if (!isAthletics) ...[
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
                          ],
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
                      if (needsWeight) ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: weightC,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                          decoration: InputDecoration(
                            labelText: 'Вага (кг)',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                      if (isAthletics) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: numberC,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                decoration: InputDecoration(
                                  labelText: 'Номер учасника',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextField(
                                controller: yobC,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(4),
                                ],
                                decoration: InputDecoration(
                                  labelText: 'Рік народження',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
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
            _showBulkImportTeamsDialog();
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
                OutlinedButton.icon(
                  onPressed: _showExportDialog,
                  icon: const Icon(Icons.output, size: 18),
                  label: const Text('Експорт'),
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
                        final isAthletics = widget.tType == 10;
                        final number = player.player_id == null
                            ? null
                            : _playerNumbers[player.player_id!];
                        return ListTile(
                          leading: isAthletics
                              ? Container(
                                  width: 44,
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: number != null
                                        ? Colors.indigo.shade50
                                        : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: number != null
                                          ? Colors.indigo.shade200
                                          : Colors.grey.shade300,
                                    ),
                                  ),
                                  child: Text(
                                    number != null ? '$number' : '—',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: number != null
                                          ? Colors.indigo.shade700
                                          : Colors.grey.shade500,
                                    ),
                                  ),
                                )
                              : null,
                          title: Text(player.fullName),
                          subtitle: () {
                            // Athletics: prefer year-of-birth from the
                            // tournament-scoped attribute and display the
                            // computed age (= reference_year - YOB). Fall
                            // back to the stored player_age when YOB is
                            // empty. Non-athletics tournaments keep the
                            // existing DOB / age display.
                            if (isAthletics && player.player_id != null) {
                              final yob = _playerYearsOfBirth[player.player_id!];
                              final ref = _referenceYear;
                              if (yob != null && ref != null) {
                                return Text('Вік: ${ref - yob}');
                              }
                              if (player.player_age != null) {
                                return Text('Вік: ${player.player_age}');
                              }
                              return null;
                            }
                            if (player.birthDateForUI.isNotEmpty) {
                              return Text(player.birthDateForUI);
                            }
                            if (player.player_age != null) {
                              return Text('Вік: ${player.player_age}');
                            }
                            return null;
                          }(),
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
  final int? age;
  const _ParsedPlayer({required this.surname, required this.name, required this.lastname, this.age});
}

class _ParsedTeamPlayer {
  final String teamName;
  final String surname;
  final String name;
  final String lastname;
  final int? age;
  const _ParsedTeamPlayer({required this.teamName, required this.surname, required this.name, required this.lastname, this.age});
}
