import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/player_model.dart';
import '../models/team_model.dart';
import '../sports/athletics/athletics_model.dart';
import '../sports/athletics/athletics_providers.dart';
import '../sports/arm_wrestling/arm_wrestling_providers.dart';
import '../sports/arm_wrestling/arm_wrestling_scoring.dart';
import '../sports/cycling/cycling_model.dart';
import '../sports/cycling/cycling_providers.dart';
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

enum _PlayerSortKey { number, name, age }

class TournamentPlayersTabState extends ConsumerState<TournamentPlayersTab> {
  List<Player> _participants = [];
  List<Player> _available = [];
  Map<int, int> _playerNumbers = const {};
  Map<int, int> _playerYearsOfBirth = const {};
  int? _referenceYear;
  bool _loading = true;
  String _search = '';
  final FocusNode _focusNode = FocusNode();
  late _PlayerSortKey _sortKey = _usesAgeCategories
      ? _PlayerSortKey.number
      : _PlayerSortKey.name;
  bool _sortAsc = true;
  int? _hoveredRow;

  int _ageFor(Player p) {
    if (_usesAgeCategories && p.player_id != null) {
      final yob = _playerYearsOfBirth[p.player_id!];
      final ref = _referenceYear;
      if (yob != null && ref != null) return ref - yob;
    }
    return p.player_age ?? 0;
  }

  int _compareForSort(Player a, Player b) {
    int cmp;
    switch (_sortKey) {
      case _PlayerSortKey.number:
        final na = a.player_id == null ? null : _playerNumbers[a.player_id!];
        final nb = b.player_id == null ? null : _playerNumbers[b.player_id!];
        if (na == null && nb == null) {
          cmp = 0;
        } else if (na == null) {
          cmp = 1;
        } else if (nb == null) {
          cmp = -1;
        } else {
          cmp = na.compareTo(nb);
        }
        break;
      case _PlayerSortKey.name:
        cmp = a.player_surname.toLowerCase().compareTo(b.player_surname.toLowerCase());
        break;
      case _PlayerSortKey.age:
        final aa = _ageFor(a);
        final ab = _ageFor(b);
        if (aa == 0 && ab == 0) {
          cmp = 0;
        } else if (aa == 0) {
          cmp = 1;
        } else if (ab == 0) {
          cmp = -1;
        } else {
          cmp = aa.compareTo(ab);
        }
        break;
    }
    if (cmp == 0) {
      cmp = a.player_surname.toLowerCase().compareTo(b.player_surname.toLowerCase());
    }
    return _sortAsc ? cmp : -cmp;
  }

  void _setSort(_PlayerSortKey key) {
    setState(() {
      if (_sortKey == key) {
        _sortAsc = !_sortAsc;
      } else {
        _sortKey = key;
        _sortAsc = true;
      }
    });
  }

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

  // ── Age-category sports (athletics t_type 10, cycling t_type 12) ──
  //
  // Both expose the participant-number / year-of-birth / assigned-category
  // attributes and the "hide DOB, show year of birth" player form. The
  // year-of-birth helpers below dispatch to whichever sport service owns
  // the current tournament; the participant number lives on the generic
  // TournamentService and needs no dispatch.

  bool get _usesAgeCategories =>
      widget.tType == 10 || widget.tType == 12;

  Future<Map<int, int>> _fetchYearsOfBirth() => widget.tType == 12
      ? ref.read(cyclingServiceProvider).getPlayerYearsOfBirth(widget.tId)
      : ref.read(athleticsServiceProvider).getPlayerYearsOfBirth(widget.tId);

  Future<int> _fetchReferenceYear() => widget.tType == 12
      ? ref.read(cyclingServiceProvider).getTournamentReferenceYear(widget.tId)
      : ref.read(athleticsServiceProvider).getTournamentReferenceYear(widget.tId);

  Future<int?> _fetchYearOfBirth(int playerId) => widget.tType == 12
      ? ref.read(cyclingServiceProvider)
          .getPlayerYearOfBirth(playerId: playerId, tId: widget.tId)
      : ref.read(athleticsServiceProvider)
          .getPlayerYearOfBirth(playerId: playerId, tId: widget.tId);

  Future<void> _saveYearOfBirth(int playerId, int year) => widget.tType == 12
      ? ref.read(cyclingServiceProvider).savePlayerYearOfBirth(
          playerId: playerId, tId: widget.tId, year: year)
      : ref.read(athleticsServiceProvider).savePlayerYearOfBirth(
          playerId: playerId, tId: widget.tId, year: year);

  Future<void> _clearYearOfBirth(int playerId) => widget.tType == 12
      ? ref.read(cyclingServiceProvider)
          .clearPlayerYearOfBirth(playerId: playerId, tId: widget.tId)
      : ref.read(athleticsServiceProvider)
          .clearPlayerYearOfBirth(playerId: playerId, tId: widget.tId);



  Future<void> _bulkSaveAssignedCategoriesFromLabels(Map<int, String> playerLabels) async {
    if (playerLabels.isEmpty) return;
    if (widget.tType == 12) {
      final categories = <int, CyclingCategory>{};
      for (final entry in playerLabels.entries) {
        final key = entry.value.toLowerCase().trim();
        final cat = CyclingCategory.values.where(
          (c) => c.label.toLowerCase() == key || c.name.toLowerCase() == key,
        ).firstOrNull;
        if (cat != null) categories[entry.key] = cat;
      }
      if (categories.isNotEmpty) {
        await ref.read(cyclingServiceProvider).bulkSaveAssignedCategories(
            tId: widget.tId, categories: categories);
      }
    } else {
      final categories = <int, AthleticsCategory>{};
      for (final entry in playerLabels.entries) {
        final key = entry.value.toLowerCase().trim();
        final cat = AthleticsCategory.values.where(
          (c) => c.label.toLowerCase() == key || c.name.toLowerCase() == key,
        ).firstOrNull;
        if (cat != null) categories[entry.key] = cat;
      }
      if (categories.isNotEmpty) {
        await ref.read(athleticsServiceProvider).bulkSaveAssignedCategories(
            tId: widget.tId, categories: categories);
      }
    }
  }

  Future<void> _loadData() async {
    final svc = ref.read(tournamentServiceProvider);
    final allPlayersFuture = ref.read(playerProvider.future);

    final participants = await svc.getParticipants(widget.tId);
    if (!mounted) return;

    final allPlayers = await allPlayersFuture;
    if (!mounted) return;

    final usesAgeCats = _usesAgeCategories;
    final numbers = usesAgeCats
        ? await svc.getPlayerNumbers(widget.tId)
        : const <int, int>{};
    if (!mounted) return;
    final yearsOfBirth = usesAgeCats
        ? await _fetchYearsOfBirth()
        : const <int, int>{};
    if (!mounted) return;
    final referenceYear = usesAgeCats ? await _fetchReferenceYear() : null;
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
    final isAthletics = _usesAgeCategories;

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
      _fetchYearOfBirth(player.player_id!).then((y) {
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
          await _saveYearOfBirth(player.player_id!, yobVal);
        } else if (yobText.isEmpty) {
          await _clearYearOfBirth(player.player_id!);
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
    final isArm = widget.tType == 9;
    // 0: ПІБ + Команда, 1: ПІ + Команда, 2: Армрестлінг (ПІБ + Команда + Вага)
    int format = isArm ? 2 : 0;
    bool importing = false;
    String? error;

    // Row layout:
    //   age-category sports: <\u041F\u0406\u0411/\u041F\u0406>  \u0420\u0456\u043A  \u041A\u0430\u0442\u0435\u0433\u043E\u0440\u0456\u044F  \u041A\u043E\u043C\u0430\u043D\u0434\u0430  \u041D\u043E\u043C\u0435\u0440
    //   other sports:        <\u041F\u0406\u0411/\u041F\u0406>  \u0420\u0456\u043A  \u041A\u043E\u043C\u0430\u043D\u0434\u0430  \u041D\u043E\u043C\u0435\u0440
    // Fields are TAB/;-separated; a fully space-separated line is also
    // accepted (team name must then be a single word run between the
    // year/category and the trailing number).
    List<_ParsedTeamPlayer> parseText(String text, int fmt) {
      final usesAgeCats = _usesAgeCategories;
      final isArmFmt = fmt == 2;
      final nameWords = fmt == 1 ? 2 : 3;
      text = text.replaceAll(RegExp(r'[\u00A0\u2000-\u200B\u200C\u200D\u202F\u205F\u2060\u3000\uFEFF]'), ' ');
      final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
      final result = <_ParsedTeamPlayer>[];

      for (final line in lines) {
        if (isArmFmt) {
          // Arm wrestling: \u041F\u0440\u0456\u0437\u0432\u0438\u0449\u0435 \u0406\u043C'\u044F \u041F\u043E \u0431\u0430\u0442\u044C\u043A\u043E\u0432\u0456 [TAB/;] \u041A\u043E\u043C\u0430\u043D\u0434\u0430 [TAB/;] \u0412\u0430\u0433\u0430
          final fields = line
              .split(RegExp(r'\t|;'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          String nameBlock;
          String teamName;
          String? weightStr;
          if (fields.length >= 3) {
            nameBlock = fields[0];
            weightStr = fields.last;
            teamName = fields.sublist(1, fields.length - 1).join(' ');
          } else {
            final w = line.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
            if (w.length < 5) continue; // need surname+name+lastname+team+weight
            nameBlock = w.sublist(0, 3).join(' ');
            weightStr = w.last;
            teamName = w.sublist(3, w.length - 1).join(' ');
          }
          final nameParts = nameBlock.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
          if (nameParts.length < 2 || teamName.isEmpty) continue;
          final surname = nameParts[0];
          final name = nameParts[1];
          final lastname = nameParts.length > 2 ? nameParts.sublist(2).join(' ') : '';
          final weight = double.tryParse(weightStr.replaceAll(',', '.'));
          if (weight == null || weight <= 0) continue;
          result.add(_ParsedTeamPlayer(
            teamName: teamName,
            surname: surname,
            name: name,
            lastname: lastname,
            weight: weight,
          ));
          continue;
        }
        final fields = line
            .split(RegExp(r'\t|;'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();

        String nameBlock;
        String? yobStr;
        String? catStr;
        String teamName;
        String? numStr;

        final minFields = usesAgeCats ? 5 : 4;
        if (fields.length >= minFields) {
          nameBlock = fields[0];
          yobStr = fields[1];
          numStr = fields.last;
          if (usesAgeCats) {
            catStr = fields[2];
            teamName = fields.sublist(3, fields.length - 1).join(' ');
          } else {
            teamName = fields.sublist(2, fields.length - 1).join(' ');
          }
        } else {
          // Fallback: whole line is space-separated.
          final w = line.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
          final lead = nameWords + (usesAgeCats ? 2 : 1);
          if (w.length < lead + 2) continue; // need team + number
          nameBlock = w.sublist(0, nameWords).join(' ');
          yobStr = w[nameWords];
          if (usesAgeCats) catStr = w[nameWords + 1];
          numStr = w.last;
          teamName = w.sublist(lead, w.length - 1).join(' ');
        }

        final nameParts =
            nameBlock.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
        if (nameParts.length < 2 || teamName.isEmpty) continue;

        final String surname = nameParts[0];
        final String name;
        final String lastname;
        if (fmt == 0) {
          name = nameParts[1];
          lastname = nameParts.length > 2 ? nameParts.sublist(2).join(' ') : '';
        } else {
          name = nameParts.sublist(1).join(' ');
          lastname = '';
        }

        final yob = int.tryParse(yobStr ?? '');
        result.add(_ParsedTeamPlayer(
          teamName: teamName,
          surname: surname,
          name: name,
          lastname: lastname,
          yob: (yob != null && yob > 1900 && yob < 2100) ? yob : null,
          category: (usesAgeCats && catStr != null && catStr.isNotEmpty)
              ? catStr
              : null,
          playerNumber: int.tryParse(numStr ?? ''),
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
                        if (isArm) ...[
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Армрестлінг (ПІБ + Команда + Вага)'),
                            selected: format == 2,
                            onSelected: (v) => setST(() => format = 2),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      () {
                        if (format == 2) {
                          return 'Кожен рядок: Прізвище  Ім\'я  По батькові  Команда  Вага (кг) — через TAB/;. '
                              'Вагова категорія визначається автоматично (≤70, ≤80, ≤90, ≤100, >100).';
                        }
                        final namePart = format == 0
                            ? 'Прізвище  Ім\'я  По батькові'
                            : 'Прізвище  Ім\'я';
                        return _usesAgeCategories
                            ? 'Кожен рядок: $namePart  Рік народження  Категорія (Ч49)  Команда  Номер (через TAB/;).'
                            : 'Кожен рядок: $namePart  Рік народження  Команда  Номер (через TAB/;).';
                      }(),
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
                                          () {
                                            final p = entry.value[i];
                                            final gender =
                                                Player.detectGender(p.name, p.lastname) == 0 ? 'Ч' : 'Ж';
                                            final extra = [
                                              gender,
                                              if (p.yob != null) '${p.yob}',
                                              if (p.category != null) p.category!,
                                              if (p.playerNumber != null) '№${p.playerNumber}',
                                              if (p.weight != null)
                                                '${p.weight!.toStringAsFixed(1)} кг → '
                                                '${WeightCategory.fromId(armCategoryFromWeight(p.weight!))?.label ?? ''}',
                                            ].join(', ');
                                            return '${i + 1}. ${p.surname} ${p.name} ${p.lastname} ($extra)';
                                          }(),
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
                                    final usesAgeCats = _usesAgeCategories;

                                    // Group by team
                                    final groups = <String, List<_ParsedTeamPlayer>>{};
                                    for (final p in currentParsed) {
                                      if (p.surname.isEmpty) continue;
                                      groups.putIfAbsent(p.teamName, () => []).add(p);
                                    }

                                    // Flatten all players for bulk creation
                                    final allValidPlayers = <_ParsedTeamPlayer>[];
                                    for (final group in groups.values) {
                                      allValidPlayers.addAll(group);
                                    }

                                    if (allValidPlayers.isEmpty) return;

                                    // Bulk-create ALL players
                                    final allPlayerIds = await playerNotifier.bulkAddPlayers(
                                      allValidPlayers.map((p) => (
                                        surname: p.surname,
                                        name: p.name,
                                        lastname: p.lastname,
                                        gender: Player.detectGender(p.name, p.lastname),
                                        dob: (!usesAgeCats && p.yob != null)
                                            ? '01.01.${p.yob}'
                                            : '',
                                        age: null,
                                      )).toList(),
                                    );

                                    // Associate IDs back to players
                                    for (int i = 0; i < allValidPlayers.length; i++) {
                                      allValidPlayers[i].tempId = allPlayerIds[i];
                                    }

                                    // Add ALL players to tournament in one transaction
                                    await tournamentSvc.bulkAddParticipants(widget.tId, allPlayerIds);

                                    // Pre-fetch all teams to find/create as needed
                                    final allTeams = await teamSvc.getAllTeams(tType: tType);

                                    int totalPlayers = 0;
                                    int totalTeams = 0;

                                    for (final entry in groups.entries) {
                                      final teamName = entry.key;
                                      final playersInGroup = entry.value;
                                      final playerIdsInGroup = playersInGroup.map((p) => p.tempId!).toList();

                                      // Create or find team
                                      var team = allTeams.cast<Team?>().firstWhere(
                                        (t) => t!.team_name.toLowerCase() == teamName.toLowerCase(),
                                        orElse: () => null,
                                      );
                                      if (team == null) {
                                        team = await teamSvc.saveTeam(Team(
                                          team_name: teamName,
                                          t_type: tType,
                                        ));
                                        allTeams.add(team);
                                        totalTeams++;
                                      }

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
                                      final allReserves = [...currentReserves, ...playerIdsInGroup];
                                      await teamSvc.saveAssignments(team.team_id!, widget.tId, currentBoards, allReserves);

                                      // Bulk save player attributes for this team
                                      final playerNumbers = <int, int>{};
                                      final yearsOfBirth = <int, int>{};
                                      final categoryLabels = <int, String>{};

                                      for (final p in playersInGroup) {
                                        final pid = p.tempId!;
                                        if (p.playerNumber != null) {
                                          playerNumbers[pid] = p.playerNumber!;
                                        }
                                        if (usesAgeCats) {
                                          if (p.yob != null) {
                                            yearsOfBirth[pid] = p.yob!;
                                          }
                                          if (p.category != null) {
                                            categoryLabels[pid] = p.category!;
                                          }
                                        }
                                      }

                                      if (playerNumbers.isNotEmpty) {
                                        await tournamentSvc.bulkSavePlayerNumbers(
                                          tId: widget.tId,
                                          playerNumbers: playerNumbers,
                                        );
                                      }
                                      if (usesAgeCats) {
                                        if (yearsOfBirth.isNotEmpty) {
                                          if (widget.tType == 12) {
                                            await ref.read(cyclingServiceProvider).bulkSavePlayerYearsOfBirth(
                                              tId: widget.tId, yearsOfBirth: yearsOfBirth);
                                          } else {
                                            await ref.read(athleticsServiceProvider).bulkSavePlayerYearsOfBirth(
                                              tId: widget.tId, yearsOfBirth: yearsOfBirth);
                                          }
                                        }
                                        if (categoryLabels.isNotEmpty) {
                                          await _bulkSaveAssignedCategoriesFromLabels(categoryLabels);
                                        }
                                      }

                                      totalPlayers += playerIdsInGroup.length;
                                    }

                                    // Arm wrestling: save weight + assign weight category per player.
                                    if (format == 2) {
                                      final armSvc = ref.read(armWrestlingServiceProvider);
                                      for (final p in allValidPlayers) {
                                        if (p.weight == null || p.tempId == null) continue;
                                        await armSvc.savePlayerWeight(
                                          playerId: p.tempId!,
                                          tId: widget.tId,
                                          weight: p.weight!,
                                        );
                                        await armSvc.setWeightCategory(
                                          widget.tId,
                                          p.tempId!,
                                          armCategoryFromWeight(p.weight!),
                                        );
                                      }
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

  /// Player age for export: computed from the year-of-birth override for
  /// age-category sports (athletics / cycling), otherwise the stored
  /// player_age. Null when unknown.
  int? _playerExportAge(Player p) {
    if (_usesAgeCategories && p.player_id != null) {
      final yob = _playerYearsOfBirth[p.player_id!];
      final refYear = _referenceYear;
      if (yob != null && refYear != null) return refYear - yob;
    }
    return p.player_age;
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
                        final age = _playerExportAge(p);
                        return '${p.fullName}'
                            '${team != null ? ' ${team.team_name}' : ''}'
                            '${age != null ? ' $age' : ''}';
                      }).join('\n');
                    }
                    return _buildExportUI(ctx, setST, content, includeTeams, (val) => setST(() => includeTeams = val));
                  },
                );
              } else {
                content = players.map((p) {
                  final age = _playerExportAge(p);
                  return '${p.fullName}${age != null ? ' $age' : ''}';
                }).join('\n');
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
                  label: const Text('ПІБ + Вік'),
                  selected: !includeTeams,
                  onSelected: (val) => onToggle(false),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('ПІБ + Команда + Вік'),
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
    final isAthletics = _usesAgeCategories;

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
          await _saveYearOfBirth(resolvedPlayerId, yobVal);
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

    final filtered = (_search.isEmpty
            ? List<Player>.from(_participants)
            : _participants
                .where((p) => p.fullName.toLowerCase().contains(_search.toLowerCase()))
                .toList())
      ..sort(_compareForSort);

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
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Сортувати:', style: TextStyle(fontSize: 12, color: Colors.black54)),
                if (_usesAgeCategories) _buildSortChip(_PlayerSortKey.number, '№'),
                _buildSortChip(_PlayerSortKey.name, 'ПІБ'),
                _buildSortChip(_PlayerSortKey.age, 'Вік'),
              ],
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
                        final isAthletics = _usesAgeCategories;
                        final number = player.player_id == null
                            ? null
                            : _playerNumbers[player.player_id!];
                        final isHovered = _hoveredRow == index;
                        return MouseRegion(
                        onEnter: (_) => setState(() => _hoveredRow = index),
                        onExit: (_) {
                          if (_hoveredRow == index) setState(() => _hoveredRow = null);
                        },
                        child: Container(
                        color: isHovered ? Colors.indigo.shade100 : null,
                        child: ListTile(
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
                        ),
                        ),
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

  Widget _buildSortChip(_PlayerSortKey key, String label) {
    final isActive = _sortKey == key;
    return InkWell(
      onTap: () => _setSort(key),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? Colors.indigo.shade50 : Colors.transparent,
          border: Border.all(
            color: isActive ? Colors.indigo.shade300 : Colors.grey.shade400,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive ? Colors.indigo.shade700 : Colors.black87,
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
  final int? yob;
  final String? category;
  final int? playerNumber;
  final double? weight;
  int? tempId;

  _ParsedTeamPlayer({
    required this.teamName,
    required this.surname,
    required this.name,
    required this.lastname,
    this.yob,
    this.category,
    this.playerNumber,
    this.weight,
  });
}

/// Map a body weight in kg to arm wrestling category id (1..5).
int armCategoryFromWeight(double w) {
  if (w <= 70) return WeightCategory.under70.id;
  if (w <= 80) return WeightCategory.under80.id;
  if (w <= 90) return WeightCategory.under90.id;
  if (w <= 100) return WeightCategory.under100.id;
  return WeightCategory.over100.id;
}
