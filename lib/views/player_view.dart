import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../viewmodels/player_viewmodel.dart';
import '../viewmodels/team_viewmodel.dart';
import '../models/player_model.dart';
import '../models/team_model.dart';

class PlayerView extends ConsumerWidget {
  const PlayerView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playersAsync = ref.watch(playerProvider);

    return Card(
      margin: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Гравці',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Перегляд та керування всіма зареєстрованими гравцями.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _showBulkImportDialog(context, ref),
                      icon: const Icon(Icons.content_paste),
                      label: const Text('Імпорт з Excel'),
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.teal,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: () => _showForm(context, ref),
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Додати гравця'),
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.indigo,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            Expanded(
              child: playersAsync.when(
                data: (players) {
                  if (players.isEmpty) {
                    return const Center(child: Text("Гравців не знайдено."));
                  }
                  final sorted = List.of(players)
                    ..sort((a, b) => a.player_surname.compareTo(b.player_surname));
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints:
                              BoxConstraints(minWidth: constraints.maxWidth),
                          child: DataTable(
                            headingTextStyle: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.black54,
                            ),
                            columns: const [
                              DataColumn(label: Text('Ім\'я')),
                              DataColumn(
                                  label: Text('Рейтинг'), numeric: true),
                              DataColumn(label: Text('Стать')),
                              DataColumn(label: Text('Дія')),
                            ],
                            rows: sorted.map((p) {
                              return DataRow(
                                cells: [
                                  DataCell(Text(p.fullName)),
                                  DataCell(Text('—')),
                                  DataCell(
                                    Text(
                                      p.player_gender == 0
                                          ? 'Чоловіча'
                                          : 'Жіноча',
                                    ),
                                  ),
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit_outlined,
                                              color: Colors.indigo),
                                          tooltip: 'Редагувати',
                                          onPressed: () =>
                                              _showForm(context, ref, p),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                              Icons.delete_outline,
                                              color: Colors.redAccent),
                                          tooltip: 'Видалити',
                                          onPressed: () => _confirmDelete(
                                              context, ref, p),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      );
                    },
                  );
                },
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, s) => Center(child: Text("Помилка: $e")),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, Player player) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Видалити гравця?'),
        content: Text('Ви впевнені, що хочете видалити ${player.fullName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Скасувати'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              ref
                  .read(playerProvider.notifier)
                  .removePlayer(player.player_id!);
              Navigator.pop(context);
            },
            child: const Text('Видалити'),
          ),
        ],
      ),
    );
  }

  void _showForm(BuildContext context, WidgetRef ref, [Player? player]) {
    final nameC = TextEditingController(text: player?.player_name ?? "");
    final surnameC =
        TextEditingController(text: player?.player_surname ?? "");
    final lastnameC =
        TextEditingController(text: player?.player_lastname ?? "");
    final dobC = TextEditingController(text: player?.birthDateForUI ?? "");
    int gender = player?.player_gender ?? 0;
    final isEdit = player != null;

    Future<void> pickDate(BuildContext dialogContext, StateSetter setST) async {
      DateTime initial = DateTime(2000);
      if (dobC.text.isNotEmpty && dobC.text.contains('.')) {
        final parts = dobC.text.split('.');
        if (parts.length == 3) {
          final parsed =
              DateTime.tryParse('${parts[2]}-${parts[1]}-${parts[0]}');
          if (parsed != null) initial = parsed;
        }
      }
      final picked = await showDatePicker(
        context: dialogContext,
        initialDate: initial,
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                        Icon(
                          isEdit ? Icons.edit_outlined : Icons.person_add_alt_1,
                          color: Colors.indigo,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          isEdit ? 'Редагувати гравця' : 'Додати гравця',
                          style: Theme.of(dialogContext)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Divider(),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildField(surnameC, 'Прізвище', autofocus: !isEdit),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildField(nameC, "Ім'я"),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildField(lastnameC, 'По батькові'),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: dobC,
                            readOnly: true,
                            decoration: InputDecoration(
                              labelText: 'Дата народження',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
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
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            items: const [
                              DropdownMenuItem(
                                  value: 0, child: Text('Чоловіча')),
                              DropdownMenuItem(
                                  value: 1, child: Text('Жіноча')),
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
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Скасувати'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () {
                            if (nameC.text.trim().isEmpty ||
                                surnameC.text.trim().isEmpty) return;
                            if (player == null) {
                              ref.read(playerProvider.notifier).addPlayer(
                                    name: nameC.text.trim(),
                                    surname: surnameC.text.trim(),
                                    lastname: lastnameC.text.trim(),
                                    gender: gender,
                                    dob: dobC.text.trim(),
                                  );
                            } else {
                              ref
                                  .read(playerProvider.notifier)
                                  .updatePlayer(player.copyWith(
                                    player_name: nameC.text.trim(),
                                    player_surname: surnameC.text.trim(),
                                    player_lastname: lastnameC.text.trim(),
                                    player_gender: gender,
                                    player_date_birth:
                                        Player.formatForDB(dobC.text.trim()),
                                  ));
                            }
                            Navigator.pop(dialogContext);
                          },
                          child: Text(isEdit ? 'Зберегти' : 'Додати'),
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

  Widget _buildField(TextEditingController c, String label, {bool autofocus = false}) {
    return TextField(
      controller: c,
      autofocus: autofocus,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showBulkImportDialog(BuildContext context, WidgetRef ref) {
    final textC = TextEditingController();
    bool isImporting = false;

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
          final parsed = _parseImportText(textC.text);
          final teamNames = parsed.map((r) => r.teamName).toSet();

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 750, maxHeight: 650),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.content_paste, color: Colors.teal),
                        const SizedBox(width: 12),
                        Text(
                          'Імпорт гравців та команд з Excel',
                          style: Theme.of(dialogContext)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      'Вставте дані з Excel. Формат рядка: Прізвище  Ім\'я  По батькові  Команда',
                      style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 180,
                      child: TextField(
                        controller: textC,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        decoration: InputDecoration(
                          hintText: 'Іванов\tІван\tІванович\tДинамо',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onChanged: (_) {
                          setST(() {});
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (parsed.isNotEmpty) ...[
                      Text(
                        'Знайдено: ${parsed.length} гравців у ${teamNames.length} командах',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: teamNames.map((teamName) {
                              final teamPlayers = parsed.where((r) => r.teamName == teamName).toList();
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.teal.shade50,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        teamName,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.teal.shade800,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    ...teamPlayers.map((p) => Padding(
                                      padding: const EdgeInsets.only(left: 16, top: 2),
                                      child: Text(
                                        '${p.surname} ${p.name} ${p.lastname}  —  ${p.gender == 0 ? 'Ч' : 'Ж'}',
                                        style: Theme.of(dialogContext).textTheme.bodyMedium,
                                      ),
                                    )),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ] else
                      const Expanded(
                        child: Center(
                          child: Text(
                            'Вставте дані для перегляду',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: isImporting ? null : () => Navigator.pop(dialogContext),
                          child: const Text('Скасувати'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          icon: isImporting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.download),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: parsed.isEmpty || isImporting
                              ? null
                              : () async {
                                  setST(() => isImporting = true);
                                  await _performBulkImport(ref, parsed);
                                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                                },
                          label: Text(isImporting ? 'Імпорт...' : 'Імпортувати'),
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

  List<_ImportRow> _parseImportText(String text) {
    // Replace all Unicode whitespace characters (from Excel) with regular spaces
    text = text.replaceAll(RegExp(r'[\u00A0\u2000-\u200B\u200C\u200D\u202F\u205F\u2060\u3000\uFEFF]'), ' ');
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty);
    final result = <_ImportRow>[];
    for (final line in lines) {
      List<String> parts;
      if (line.contains('\t')) {
        parts = line.split('\t').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      } else {
        parts = line.trim().split(RegExp(r'\s+'));
      }
      if (parts.length >= 4) {
        final surname = parts[0];
        final name = parts[1];
        final lastname = parts[2];
        final teamName = parts.sublist(3).join(' ');
        final gender = Player.detectGender(name, lastname);
        result.add(_ImportRow(
          surname: surname,
          name: name,
          lastname: lastname,
          teamName: teamName,
          gender: gender,
        ));
      }
    }
    return result;
  }

  Future<void> _performBulkImport(WidgetRef ref, List<_ImportRow> rows) async {
    // Get unique team names from import
    final teamNames = rows.map((r) => r.teamName).toSet();

    // Load existing teams
    List<Team> existingTeams;
    try {
      existingTeams = await ref.read(teamProvider.future);
    } catch (_) {
      existingTeams = [];
    }

    // Create missing teams
    for (final name in teamNames) {
      final exists = existingTeams.any(
        (t) => t.team_name.toLowerCase() == name.toLowerCase(),
      );
      if (!exists) {
        final newTeam = await ref.read(teamProvider.notifier).addTeam(name: name);
        existingTeams.add(newTeam);
      }
    }

    // Bulk-add players
    final playerData = rows
        .map((r) => (
              name: r.name,
              surname: r.surname,
              lastname: r.lastname,
              gender: r.gender,
              dob: '',
            ))
        .toList();
    await ref.read(playerProvider.notifier).bulkAddPlayers(playerData);
  }
}

class _ImportRow {
  final String surname;
  final String name;
  final String lastname;
  final String teamName;
  final int gender;

  const _ImportRow({
    required this.surname,
    required this.name,
    required this.lastname,
    required this.teamName,
    required this.gender,
  });
}
