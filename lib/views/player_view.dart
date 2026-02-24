import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../viewmodels/player_viewmodel.dart';
import '../models/player_model.dart';

class PlayerView extends ConsumerWidget {
  const PlayerView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playersAsync = ref.watch(playerProvider);

    return Card(
      margin: const EdgeInsets.all(24),
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
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            Expanded(
              child: playersAsync.when(
                data: (players) {
                  if (players.isEmpty) {
                    return const Center(child: Text("Гравців не знайдено."));
                  }
                  return LayoutBuilder(
                    builder: (context, constraints) {
                    return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: constraints.maxWidth),
                      child: DataTable(
                      headingTextStyle: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.black54,
                      ),
                      columns: const [
                        DataColumn(label: Text('Ім\'я')),
                        DataColumn(label: Text('Рейтинг'), numeric: true),
                        DataColumn(label: Text('Стать')),
                        DataColumn(label: Text('Команда')),
                        DataColumn(label: Text('Дія')),
                      ],
                      rows:
                          players.map((p) {
                            return DataRow(
                              cells: [
                                DataCell(Text(p.fullName)),
                                DataCell(Text('1850')), // Mock data
                                DataCell(
                                  Text(
                                    p.player_gender == 0
                                        ? 'Чоловіча'
                                        : 'Жіноча',
                                  ),
                                ),
                                DataCell(
                                  Chip(
                                    label: Text('1 ДПРЗ'), // Mock data
                                    backgroundColor: Colors.grey.shade200,
                                  ),
                                ),
                                DataCell(
                                  IconButton(
                                    icon: const Icon(
                                      Icons.edit,
                                      color: Colors.blue,
                                    ),
                                    onPressed: () => _showForm(context, ref, p),
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
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, s) => Center(child: Text("Помилка: $e")),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showForm(BuildContext context, WidgetRef ref, [Player? player]) {
    final nameC = TextEditingController(text: player?.player_name ?? "");
    final surnameC = TextEditingController(text: player?.player_surname ?? "");
    final lastnameC = TextEditingController(
      text: player?.player_lastname ?? "",
    );
    final dobC = TextEditingController(text: player?.birthDateForUI ?? "");
    int gender = player?.player_gender ?? 0;

    showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setST) => AlertDialog(
                  title: Text(player == null ? "Додати гравця" : "Редагувати гравця"),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _field(nameC, "Ім'я"),
                        const SizedBox(height: 10),
                        _field(surnameC, "Прізвище"),
                        const SizedBox(height: 10),
                        _field(lastnameC, "По батькові"),
                        const SizedBox(height: 10),
                        TextField(
                          controller: dobC,
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: "Дата народження",
                            isDense: true,
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.calendar_today),
                              onPressed: () async {
                                DateTime initial = DateTime(2000);
                                if (dobC.text.isNotEmpty && dobC.text.contains('.')) {
                                  final parts = dobC.text.split('.');
                                  if (parts.length == 3) {
                                    final parsed = DateTime.tryParse(
                                      '${parts[2]}-${parts[1]}-${parts[0]}',
                                    );
                                    if (parsed != null) initial = parsed;
                                  }
                                }
                                final picked = await showDatePicker(
                                  context: context,
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
                              },
                            ),
                          ),
                          onTap: () async {
                            DateTime initial = DateTime(2000);
                            if (dobC.text.isNotEmpty && dobC.text.contains('.')) {
                              final parts = dobC.text.split('.');
                              if (parts.length == 3) {
                                final parsed = DateTime.tryParse(
                                  '${parts[2]}-${parts[1]}-${parts[0]}',
                                );
                                if (parsed != null) initial = parsed;
                              }
                            }
                            final picked = await showDatePicker(
                              context: context,
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
                          },
                        ),
                        const SizedBox(height: 15),
                        DropdownButtonFormField<int>(
                          value: gender,
                          decoration: const InputDecoration(
                            labelText: "Стать",
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 0, child: Text("Чоловіча")),
                            DropdownMenuItem(value: 1, child: Text("Жіноча")),
                          ],
                          onChanged: (v) => setST(() => gender = v!),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Скасувати"),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        if (nameC.text.isNotEmpty && surnameC.text.isNotEmpty) {
                          if (player == null) {
                            ref
                                .read(playerProvider.notifier)
                                .addPlayer(
                                  name: nameC.text.trim(),
                                  surname: surnameC.text.trim(),
                                  lastname: lastnameC.text.trim(),
                                  gender: gender,
                                  dob: dobC.text.trim(),
                                );
                          } else {
                            final updatedPlayer = player.copyWith(
                              player_name: nameC.text.trim(),
                              player_surname: surnameC.text.trim(),
                              player_lastname: lastnameC.text.trim(),
                              player_gender: gender,
                              player_date_birth: Player.formatForDB(
                                dobC.text.trim(),
                              ),
                            );
                            ref
                                .read(playerProvider.notifier)
                                .updatePlayer(updatedPlayer);
                          }
                          Navigator.pop(context);
                        }
                      },
                      child: const Text("Зберегти"),
                    ),
                  ],
                ),
          ),
    );
  }

  Widget _field(TextEditingController c, String l) {
    return TextField(
      controller: c,
      decoration: InputDecoration(
        labelText: l,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
