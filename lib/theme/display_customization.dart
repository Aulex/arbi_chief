import 'package:flutter/material.dart';

/// User-defined colour overrides applied on top of the active theme.
///
/// A `null` field means "use the theme default" for that surface.
@immutable
class DisplayCustomization {
  /// Scaffold / window background.
  final Color? backgroundColor;

  /// Cards, forms, dialogs and other raised surfaces.
  final Color? surfaceColor;

  /// Primary text colour.
  final Color? textColor;

  const DisplayCustomization({
    this.backgroundColor,
    this.surfaceColor,
    this.textColor,
  });

  static const none = DisplayCustomization();

  bool get isEmpty =>
      backgroundColor == null && surfaceColor == null && textColor == null;

  DisplayCustomization copyWith({
    Object? backgroundColor = _unset,
    Object? surfaceColor = _unset,
    Object? textColor = _unset,
  }) {
    return DisplayCustomization(
      backgroundColor: backgroundColor == _unset
          ? this.backgroundColor
          : backgroundColor as Color?,
      surfaceColor:
          surfaceColor == _unset ? this.surfaceColor : surfaceColor as Color?,
      textColor: textColor == _unset ? this.textColor : textColor as Color?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DisplayCustomization &&
      other.backgroundColor == backgroundColor &&
      other.surfaceColor == surfaceColor &&
      other.textColor == textColor;

  @override
  int get hashCode => Object.hash(backgroundColor, surfaceColor, textColor);
}

const _unset = Object();

/// A ready-made display configuration the user can apply with one tap.
@immutable
class DisplayPreset {
  final String name;
  final IconData icon;
  final bool dark;
  final bool highContrast;
  final DisplayCustomization customization;

  const DisplayPreset({
    required this.name,
    required this.icon,
    required this.dark,
    required this.highContrast,
    this.customization = DisplayCustomization.none,
  });
}

/// Curated presets shown in Settings.
const List<DisplayPreset> displayPresets = [
  DisplayPreset(
    name: 'Стандарт',
    icon: Icons.brightness_5,
    dark: false,
    highContrast: false,
  ),
  DisplayPreset(
    name: 'Яскраве сонце',
    icon: Icons.wb_sunny,
    dark: false,
    highContrast: true,
    customization: DisplayCustomization(
      backgroundColor: Color(0xFFFFFFFF),
      surfaceColor: Color(0xFFFFFFFF),
      textColor: Color(0xFF000000),
    ),
  ),
  DisplayPreset(
    name: 'Кремовий папір',
    icon: Icons.menu_book,
    dark: false,
    highContrast: true,
    customization: DisplayCustomization(
      backgroundColor: Color(0xFFEFE9D6),
      surfaceColor: Color(0xFFFBF7EA),
      textColor: Color(0xFF1A1408),
    ),
  ),
  DisplayPreset(
    name: 'Темна',
    icon: Icons.dark_mode,
    dark: true,
    highContrast: false,
  ),
  DisplayPreset(
    name: 'Темна контрастна',
    icon: Icons.contrast,
    dark: true,
    highContrast: true,
  ),
  DisplayPreset(
    name: 'Нічна (чорний фон)',
    icon: Icons.nightlight,
    dark: true,
    highContrast: true,
    customization: DisplayCustomization(
      backgroundColor: Color(0xFF000000),
      surfaceColor: Color(0xFF0B0B0B),
      textColor: Color(0xFFFFFFFF),
    ),
  ),
];

/// Swatch palette offered by the in-app colour picker.
const List<Color> pickerSwatches = [
  Color(0xFFFFFFFF), Color(0xFFF5F5F5), Color(0xFFEFE9D6), Color(0xFFFBF7EA),
  Color(0xFFE3F2FD), Color(0xFFE8F5E9), Color(0xFFFFF8E1), Color(0xFFFCE4EC),
  Color(0xFF9E9E9E), Color(0xFF607D8B), Color(0xFF455A64), Color(0xFF263238),
  Color(0xFF1B2838), Color(0xFF0D1B2A), Color(0xFF121212), Color(0xFF000000),
  Color(0xFF212121), Color(0xFF3F51B5), Color(0xFF1565C0), Color(0xFF2E7D32),
];
