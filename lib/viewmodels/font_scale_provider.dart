import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FontScaleNotifier extends Notifier<double> {
  static const _key = 'font_scale';

  @override
  double build() {
    _loadFromPrefs();
    return 1.0;
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final scale = prefs.getDouble(_key) ?? 1.0;
    if (scale != state) {
      state = scale;
    }
  }

  Future<void> setScale(double scale) async {
    state = scale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_key, scale);
  }

  Future<void> increase() async {
    if (state < 1.5) {
      await setScale(((state + 0.05) * 100).roundToDouble() / 100);
    }
  }

  Future<void> decrease() async {
    if (state > 0.7) {
      await setScale(((state - 0.05) * 100).roundToDouble() / 100);
    }
  }
}

final fontScaleProvider = NotifierProvider<FontScaleNotifier, double>(
  () => FontScaleNotifier(),
);
