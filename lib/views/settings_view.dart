import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/database_sync_service.dart';
import '../viewmodels/font_scale_provider.dart';
import '../viewmodels/shared_providers.dart';
import '../viewmodels/theme_provider.dart';

class SettingsView extends ConsumerStatefulWidget {
  const SettingsView({super.key});

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView> {
  int _autoTabSeconds = 10;

  @override
  void initState() {
    super.initState();
    _loadAutoTabSetting();
  }

  Future<void> _loadAutoTabSetting() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _autoTabSeconds = prefs.getInt('auto_tab_cycle_seconds') ?? 10;
      });
    }
  }

  Future<void> _saveAutoTabSetting(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('auto_tab_cycle_seconds', seconds);
    if (mounted) {
      setState(() {
        _autoTabSeconds = seconds;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeProvider);
    final fontScale = ref.watch(fontScaleProvider);

    return SingleChildScrollView(
      child: Column(
        children: [
          // ── General settings card ──
          Card(
            margin: const EdgeInsets.fromLTRB(24, 8, 24, 12),
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Налаштування',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Загальні налаштування додатку.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    secondary: Icon(isDark ? Icons.dark_mode : Icons.light_mode,
                        color: isDark ? Colors.amber : Colors.indigo),
                    title: const Text('Темна тема'),
                    subtitle: Text(isDark ? 'Увімкнено' : 'Вимкнено'),
                    value: isDark,
                    onChanged: (_) => ref.read(themeProvider.notifier).toggle(),
                    shape: RoundedRectangleBorder(
                      side: BorderSide(color: Theme.of(context).dividerColor, width: 1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const Icon(Icons.autorenew, color: Colors.teal),
                    title: const Text('Автоперемикання вкладок (нове вікно)'),
                    subtitle: Text(
                      _autoTabSeconds == 0
                          ? 'Вимкнено'
                          : 'Кожні $_autoTabSeconds секунд',
                    ),
                    trailing: SizedBox(
                      width: 160,
                      child: DropdownButton<int>(
                        value: _autoTabSeconds,
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('Вимкнено')),
                          DropdownMenuItem(value: 5, child: Text('5 секунд')),
                          DropdownMenuItem(value: 10, child: Text('10 секунд')),
                          DropdownMenuItem(value: 15, child: Text('15 секунд')),
                          DropdownMenuItem(value: 20, child: Text('20 секунд')),
                          DropdownMenuItem(value: 30, child: Text('30 секунд')),
                          DropdownMenuItem(value: 60, child: Text('60 секунд')),
                        ],
                        onChanged: (val) {
                          if (val != null) _saveAutoTabSetting(val);
                        },
                      ),
                    ),
                    shape: RoundedRectangleBorder(
                      side: BorderSide(color: Theme.of(context).dividerColor, width: 1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const Icon(Icons.text_fields, color: Colors.deepPurple),
                    title: const Text('Розмір шрифту'),
                    subtitle: Text('${(fontScale * 100).round()}%'),
                    trailing: SizedBox(
                      width: 200,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: fontScale > 0.7
                                ? () => ref.read(fontScaleProvider.notifier).decrease()
                                : null,
                          ),
                          Expanded(
                            child: Slider(
                              value: fontScale.clamp(0.7, 1.5),
                              min: 0.7,
                              max: 1.5,
                              divisions: 16,
                              label: '${(fontScale * 100).round()}%',
                              onChanged: (val) {
                                ref.read(fontScaleProvider.notifier).setScale(val);
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: fontScale < 1.5
                                ? () => ref.read(fontScaleProvider.notifier).increase()
                                : null,
                          ),
                        ],
                      ),
                    ),
                    shape: RoundedRectangleBorder(
                      side: BorderSide(color: Theme.of(context).dividerColor, width: 1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Database tools card ──
          Card(
            margin: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            elevation: 2,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'База даних',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Синхронізація та експорт даних.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),

                  // ── Sync from external DB ──
                  ListTile(
                    leading: const Icon(Icons.sync, color: Colors.teal),
                    title: const Text('Синхронізувати базу даних'),
                    subtitle: const Text(
                      'Імпорт даних із зовнішнього .db файлу '
                      '(старі БД з відсутніми полями підтримуються)',
                    ),
                    trailing:
                        const Icon(Icons.arrow_forward_ios, size: 16),
                    shape: RoundedRectangleBorder(
                      side:
                          BorderSide(color: Colors.grey.shade300, width: 1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    onTap: () => _syncDatabase(context, ref),
                  ),

                  const SizedBox(height: 12),

                  // ── Export structure ──
                  ListTile(
                    leading:
                        const Icon(Icons.account_tree, color: Colors.orange),
                    title: const Text('Експорт структури БД'),
                    subtitle: const Text(
                      'Зберегти схему таблиць у JSON файл',
                    ),
                    trailing:
                        const Icon(Icons.arrow_forward_ios, size: 16),
                    shape: RoundedRectangleBorder(
                      side:
                          BorderSide(color: Colors.grey.shade300, width: 1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    onTap: () => _exportStructure(context, ref),
                  ),

                  const SizedBox(height: 12),

                  // ── Export data ──
                  ListTile(
                    leading:
                        const Icon(Icons.table_chart, color: Colors.blue),
                    title: const Text('Експорт даних БД'),
                    subtitle: const Text(
                      'Зберегти всі дані таблиць у JSON файл',
                    ),
                    trailing:
                        const Icon(Icons.arrow_forward_ios, size: 16),
                    shape: RoundedRectangleBorder(
                      side:
                          BorderSide(color: Colors.grey.shade300, width: 1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    onTap: () => _exportData(context, ref),
                  ),

                  const SizedBox(height: 12),

                  // ── Export full (structure + data) ──
                  ListTile(
                    leading: const Icon(Icons.download, color: Colors.indigo),
                    title: const Text('Повний експорт БД'),
                    subtitle: const Text(
                      'Структура + дані в одному JSON файлі',
                    ),
                    trailing:
                        const Icon(Icons.arrow_forward_ios, size: 16),
                    shape: RoundedRectangleBorder(
                      side:
                          BorderSide(color: Colors.grey.shade300, width: 1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    onTap: () => _exportFull(context, ref),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────
  //  Action handlers
  // ────────────────────────────────────────────────────────────

  Future<void> _syncDatabase(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Оберіть файл бази даних (.db)',
      type: FileType.any,
    );

    if (result == null || result.files.single.path == null) return;

    final filePath = result.files.single.path!;
    if (!filePath.endsWith('.db')) {
      if (context.mounted) {
        _showSnackBar(context, 'Будь ласка, оберіть файл з розширенням .db',
            isError: true);
      }
      return;
    }

    if (context.mounted) {
      _showLoadingDialog(context, 'Синхронізація...');
    }

    try {
      final syncService =
          DatabaseSyncService(ref.read(dbServiceProvider));
      final log = await syncService.synchroniseFrom(filePath);

      if (context.mounted) {
        Navigator.of(context).pop(); // dismiss loading
        _showResultDialog(context, 'Результат синхронізації', log);
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop(); // dismiss loading
        _showSnackBar(context, 'Помилка синхронізації: $e', isError: true);
      }
    }
  }

  Future<void> _exportStructure(BuildContext context, WidgetRef ref) async {
    await _doExport(
      context,
      ref,
      exportType: 'structure',
      defaultFileName: 'db_structure.json',
    );
  }

  Future<void> _exportData(BuildContext context, WidgetRef ref) async {
    await _doExport(
      context,
      ref,
      exportType: 'data',
      defaultFileName: 'db_data.json',
    );
  }

  Future<void> _exportFull(BuildContext context, WidgetRef ref) async {
    await _doExport(
      context,
      ref,
      exportType: 'full',
      defaultFileName: 'db_full_export.json',
    );
  }

  Future<void> _doExport(
    BuildContext context,
    WidgetRef ref, {
    required String exportType,
    required String defaultFileName,
  }) async {
    // Let user choose save location.
    String? savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'Зберегти як',
      fileName: defaultFileName,
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    // On some platforms saveFile returns null — fall back to documents dir.
    if (savePath == null) {
      try {
        final dir = await getApplicationDocumentsDirectory();
        savePath = '${dir.path}/$defaultFileName';
      } catch (_) {
        if (context.mounted) {
          _showSnackBar(context, 'Не вдалося визначити місце збереження',
              isError: true);
        }
        return;
      }
    }

    if (!savePath.endsWith('.json')) {
      savePath = '$savePath.json';
    }

    if (context.mounted) {
      _showLoadingDialog(context, 'Експорт...');
    }

    try {
      final syncService =
          DatabaseSyncService(ref.read(dbServiceProvider));

      late String json;
      switch (exportType) {
        case 'structure':
          json = await syncService.exportStructureJson();
          break;
        case 'data':
          json = await syncService.exportDataJson();
          break;
        case 'full':
        default:
          json = await syncService.exportFullJson();
          break;
      }

      await syncService.saveJsonToFile(json, savePath);

      if (context.mounted) {
        Navigator.of(context).pop(); // dismiss loading
        _showSnackBar(context, 'Збережено: $savePath');
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop(); // dismiss loading
        _showSnackBar(context, 'Помилка експорту: $e', isError: true);
      }
    }
  }

  // ────────────────────────────────────────────────────────────
  //  UI helpers
  // ────────────────────────────────────────────────────────────

  void _showLoadingDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 24),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  void _showResultDialog(BuildContext context, String title, String body) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: SelectableText(
            body,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(BuildContext context, String message,
      {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: isError ? 5 : 3),
      ),
    );
  }
}
