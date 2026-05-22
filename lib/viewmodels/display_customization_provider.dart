import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/display_customization.dart';

/// Holds the user's manual colour overrides (background / surface / text),
/// persisted across sessions.
class DisplayCustomizationNotifier extends Notifier<DisplayCustomization> {
  static const _bgKey = 'custom_background_color';
  static const _surfaceKey = 'custom_surface_color';
  static const _textKey = 'custom_text_color';

  @override
  DisplayCustomization build() {
    _loadFromPrefs();
    return DisplayCustomization.none;
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    Color? read(String key) {
      final value = prefs.getInt(key);
      return value == null ? null : Color(value);
    }

    final loaded = DisplayCustomization(
      backgroundColor: read(_bgKey),
      surfaceColor: read(_surfaceKey),
      textColor: read(_textKey),
    );
    if (loaded != state) {
      state = loaded;
    }
  }

  Future<void> _persist(String key, Color? color) async {
    final prefs = await SharedPreferences.getInstance();
    if (color == null) {
      await prefs.remove(key);
    } else {
      await prefs.setInt(key, color.toARGB32());
    }
  }

  Future<void> setBackgroundColor(Color? color) async {
    state = state.copyWith(backgroundColor: color);
    await _persist(_bgKey, color);
  }

  Future<void> setSurfaceColor(Color? color) async {
    state = state.copyWith(surfaceColor: color);
    await _persist(_surfaceKey, color);
  }

  Future<void> setTextColor(Color? color) async {
    state = state.copyWith(textColor: color);
    await _persist(_textKey, color);
  }

  /// Replaces all overrides at once (used when applying a preset).
  Future<void> apply(DisplayCustomization customization) async {
    state = customization;
    await _persist(_bgKey, customization.backgroundColor);
    await _persist(_surfaceKey, customization.surfaceColor);
    await _persist(_textKey, customization.textColor);
  }

  Future<void> reset() => apply(DisplayCustomization.none);
}

final displayCustomizationProvider =
    NotifierProvider<DisplayCustomizationNotifier, DisplayCustomization>(
  () => DisplayCustomizationNotifier(),
);
