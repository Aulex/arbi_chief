import 'package:flutter/material.dart';

/// Centralised application themes.
///
/// Both the light and dark themes support a [highContrast] "outdoor" variant
/// that boosts text contrast and divider strength for use in bright sunlight.

const _seedColor = Color(0xFF3F51B5); // Indigo

// Dark navy palette (kept consistent with the original dark theme).
const _darkScaffold = Color(0xFF0D1B2A);
const _darkSurface = Color(0xFF1B2838);
const _darkAppBar = Color(0xFF152238);
const _darkDivider = Color(0xFF2A3A4E);
const _darkText = Color(0xFFE0E6F0);

/// Builds the application light theme.
ThemeData buildLightTheme({bool highContrast = false}) =>
    _buildTheme(brightness: Brightness.light, highContrast: highContrast);

/// Builds the application dark theme.
ThemeData buildDarkTheme({bool highContrast = false}) =>
    _buildTheme(brightness: Brightness.dark, highContrast: highContrast);

ThemeData _buildTheme({
  required Brightness brightness,
  required bool highContrast,
}) {
  final isDark = brightness == Brightness.dark;

  var colorScheme = ColorScheme.fromSeed(
    seedColor: _seedColor,
    brightness: brightness,
  );

  if (highContrast) {
    final fg = isDark ? Colors.white : Colors.black;
    final fgVariant =
        isDark ? const Color(0xFFD6DEEA) : const Color(0xFF1A1A1A);
    colorScheme = colorScheme.copyWith(
      onSurface: fg,
      onSurfaceVariant: fgVariant,
      outline: isDark ? const Color(0xFFB6C2D4) : Colors.black,
      outlineVariant: isDark ? const Color(0xFF8294AC) : Colors.black54,
    );
  }

  var theme = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
  );

  if (isDark) {
    theme = theme.copyWith(
      scaffoldBackgroundColor: _darkScaffold,
      canvasColor: _darkScaffold,
      cardColor: _darkSurface,
      dialogBackgroundColor: _darkSurface,
      dividerColor: highContrast ? const Color(0xFF7C90AC) : _darkDivider,
      appBarTheme: const AppBarTheme(
        backgroundColor: _darkAppBar,
        foregroundColor: _darkText,
      ),
      cardTheme: const CardThemeData(color: _darkSurface),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: _darkAppBar,
      ),
    );
  }

  if (highContrast) {
    final fg = isDark ? Colors.white : Colors.black;
    final dividerColor = isDark ? const Color(0xFF7C90AC) : Colors.black54;
    theme = theme.copyWith(
      textTheme: _boostTextTheme(theme.textTheme, fg),
      dividerColor: dividerColor,
      dividerTheme: DividerThemeData(color: dividerColor, thickness: 1.2),
    );
  }

  return theme;
}

/// Re-colours and bolds the standard text styles for high-contrast mode.
TextTheme _boostTextTheme(TextTheme base, Color color) {
  TextStyle? boost(TextStyle? style) =>
      style?.copyWith(color: color, fontWeight: FontWeight.w600);

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
