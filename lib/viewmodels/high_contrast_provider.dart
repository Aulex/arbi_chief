import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global "outdoor / high-contrast" display mode.
///
/// When enabled the app switches to pure black/white text, heavier font
/// weights and stronger dividers so the UI stays readable in bright sunlight.
class HighContrastNotifier extends Notifier<bool> {
  static const _key = 'high_contrast';

  @override
  bool build() {
    _loadFromPrefs();
    return false;
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getBool(_key) ?? false;
    if (value != state) {
      state = value;
    }
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, state);
  }
}

final highContrastProvider = NotifierProvider<HighContrastNotifier, bool>(
  () => HighContrastNotifier(),
);
