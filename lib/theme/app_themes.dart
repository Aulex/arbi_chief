import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'display_customization.dart';

/// Centralised application themes.
///
/// Both the light and dark themes support a [highContrast] "outdoor" variant
/// that boosts text contrast and divider strength for use in bright sunlight,
/// plus per-user colour overrides via [DisplayCustomization].

const _seedColor = Color(0xFF3F51B5); // Indigo

// Dark navy palette (kept consistent with the original dark theme).
const _darkScaffold = Color(0xFF0D1B2A);
const _darkSurface = Color(0xFF1B2838);
const _darkAppBar = Color(0xFF152238);
const _darkDivider = Color(0xFF2A3A4E);

/// Builds the application light theme.
ThemeData buildLightTheme({
  bool highContrast = false,
  DisplayCustomization custom = DisplayCustomization.none,
}) =>
    _buildTheme(
      brightness: Brightness.light,
      highContrast: highContrast,
      custom: custom,
    );

/// Builds the application dark theme.
ThemeData buildDarkTheme({
  bool highContrast = false,
  DisplayCustomization custom = DisplayCustomization.none,
}) =>
    _buildTheme(
      brightness: Brightness.dark,
      highContrast: highContrast,
      custom: custom,
    );

ThemeData _buildTheme({
  required Brightness brightness,
  required bool highContrast,
  required DisplayCustomization custom,
}) {
  final isDark = brightness == Brightness.dark;

  var colorScheme = ColorScheme.fromSeed(
    seedColor: _seedColor,
    brightness: brightness,
  );

  // Effective foreground (text) colour.
  final defaultFg = isDark ? Colors.white : Colors.black;
  final fg = custom.textColor ??
      (highContrast ? defaultFg : colorScheme.onSurface);

  // Effective background / surface colours. `null` keeps the framework default.
  final Color? background = custom.backgroundColor ??
      (highContrast
          ? (isDark ? const Color(0xFF05090F) : Colors.white)
          : (isDark ? _darkScaffold : null));
  final Color? surface = custom.surfaceColor ??
      (highContrast
          ? (isDark ? const Color(0xFF12212F) : Colors.white)
          : (isDark ? _darkSurface : null));

  final hasTextOverride = highContrast || custom.textColor != null;

  if (hasTextOverride || highContrast) {
    colorScheme = colorScheme.copyWith(
      onSurface: fg,
      onSurfaceVariant: highContrast
          ? (isDark ? const Color(0xFFD6DEEA) : const Color(0xFF1A1A1A))
          : (custom.textColor != null ? fg : null),
      outline: highContrast
          ? (isDark ? const Color(0xFFB6C2D4) : Colors.black)
          : null,
      outlineVariant: highContrast
          ? (isDark ? const Color(0xFF8294AC) : Colors.black54)
          : null,
    );
  }
  if (surface != null) {
    colorScheme = colorScheme.copyWith(surface: surface);
  }

  var theme = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: background,
    canvasColor: background,
    cardColor: surface,
  );

  // Container themes — derive from the effective surface colour.
  if (surface != null) {
    final appBarBg = isDark && custom.surfaceColor == null
        ? _darkAppBar
        : surface;
    theme = theme.copyWith(
      dialogBackgroundColor: surface,
      cardTheme: CardThemeData(color: surface),
      appBarTheme: AppBarTheme(
        backgroundColor: appBarBg,
        foregroundColor: hasTextOverride ? fg : null,
      ),
      navigationRailTheme: NavigationRailThemeData(backgroundColor: appBarBg),
    );
  }

  if (isDark) {
    theme = theme.copyWith(
      dividerColor: highContrast ? const Color(0xFF7C90AC) : _darkDivider,
    );
  }

  if (highContrast) {
    final dividerColor = isDark ? const Color(0xFF7C90AC) : Colors.black54;
    theme = theme.copyWith(
      dividerColor: dividerColor,
      dividerTheme: DividerThemeData(color: dividerColor, thickness: 1.2),
    );
  }

  if (hasTextOverride) {
    theme = theme.copyWith(
      textTheme: _boostTextTheme(theme.textTheme, fg, bold: highContrast),
      primaryTextTheme:
          _boostTextTheme(theme.primaryTextTheme, fg, bold: highContrast),
    );
  }

  return theme.copyWith(
    extensions: [
      AppColors.from(brightness: brightness, highContrast: highContrast),
    ],
  );
}

/// Re-colours (and optionally bolds) the standard text styles.
TextTheme _boostTextTheme(TextTheme base, Color color, {required bool bold}) {
  TextStyle? boost(TextStyle? style) => style?.copyWith(
        color: color,
        fontWeight: bold ? FontWeight.w600 : null,
      );

  return base.copyWith(
    displayLarge: boost(base.displayLarge),
    displayMedium: boost(base.displayMedium),
    displaySmall: boost(base.displaySmall),
    headlineLarge: boost(base.headlineLarge),
    headlineMedium: boost(base.headlineMedium),
    headlineSmall: boost(base.headlineSmall),
    titleLarge: boost(base.titleLarge),
    titleMedium: boost(base.titleMedium),
    titleSmall: boost(base.titleSmall),
    bodyLarge: boost(base.bodyLarge),
    bodyMedium: boost(base.bodyMedium),
    bodySmall: boost(base.bodySmall),
    labelLarge: boost(base.labelLarge),
    labelMedium: boost(base.labelMedium),
    labelSmall: boost(base.labelSmall),
  );
}
