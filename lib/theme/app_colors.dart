import 'package:flutter/material.dart';

/// Semantic colours for data-dense widgets (cross-tables, standings banners).
///
/// Exposed as a [ThemeExtension] so any widget can resolve theme-aware colours
/// via `Theme.of(context).extension<AppColors>()` without threading flags
/// through constructors. The values already account for light/dark mode and
/// the outdoor (high-contrast) preference.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color resultWinBg;
  final Color resultWinFg;
  final Color resultLossBg;
  final Color resultLossFg;
  final Color resultDrawBg;
  final Color resultDrawFg;
  final Color resultSpecialBg;
  final Color resultSpecialFg;
  final Color bannerBg;
  final Color bannerBorder;
  final Color bannerText;
  final Color tableHeaderBg;
  final Color tableBorder;
  final Color separatorCell;
  final Color diagonalCell;
  final Color hoverHighlight;
  final Color mutedText;
  final Color disabledCell;

  const AppColors({
    required this.resultWinBg,
    required this.resultWinFg,
    required this.resultLossBg,
    required this.resultLossFg,
    required this.resultDrawBg,
    required this.resultDrawFg,
    required this.resultSpecialBg,
    required this.resultSpecialFg,
    required this.bannerBg,
    required this.bannerBorder,
    required this.bannerText,
    required this.tableHeaderBg,
    required this.tableBorder,
    required this.separatorCell,
    required this.diagonalCell,
    required this.hoverHighlight,
    required this.mutedText,
    required this.disabledCell,
  });

  /// Builds the palette for the given [brightness], optionally boosted for
  /// outdoor / bright-sunlight use via [highContrast].
  factory AppColors.from({
    required Brightness brightness,
    required bool highContrast,
  }) {
    final isDark = brightness == Brightness.dark;
    if (isDark) {
      return highContrast ? _darkHighContrast : _dark;
    }
    return highContrast ? _lightHighContrast : _light;
  }

  static const _light = AppColors(
    resultWinBg: Color(0xFFE8F5E9),
    resultWinFg: Color(0xFF2E7D32),
    resultLossBg: Color(0xFFFFEBEE),
    resultLossFg: Color(0xFFC62828),
    resultDrawBg: Color(0xFFFFF8E1),
    resultDrawFg: Color(0xFFEF6C00),
    resultSpecialBg: Color(0xFFFFE0B2),
    resultSpecialFg: Color(0xFFE65100),
    bannerBg: Color(0xFFE8EAF6),
    bannerBorder: Color(0xFFC5CAE9),
    bannerText: Color(0xFF424242),
    tableHeaderBg: Color(0xFFF5F5F5),
    tableBorder: Color(0xFFE0E0E0),
    separatorCell: Color(0xFFBDBDBD),
    diagonalCell: Color(0xFFE0E0E0),
    hoverHighlight: Color(0xFFE8EAF6),
    mutedText: Color(0xFF757575),
    disabledCell: Color(0xFFEEEEEE),
  );

  static const _lightHighContrast = AppColors(
    resultWinBg: Color(0xFFB6E0BA),
    resultWinFg: Color(0xFF0F4D17),
    resultLossBg: Color(0xFFF7BFC4),
    resultLossFg: Color(0xFF8E0000),
    resultDrawBg: Color(0xFFFFE08A),
    resultDrawFg: Color(0xFF8A4500),
    resultSpecialBg: Color(0xFFFFC97A),
    resultSpecialFg: Color(0xFF7A2E00),
    bannerBg: Color(0xFFD6DAF0),
    bannerBorder: Color(0xFF3F51B5),
    bannerText: Color(0xFF000000),
    tableHeaderBg: Color(0xFFDADADA),
    tableBorder: Color(0xFF6E6E6E),
    separatorCell: Color(0xFF8A8A8A),
    diagonalCell: Color(0xFFB5B5B5),
    hoverHighlight: Color(0xFFC5CAE9),
    mutedText: Color(0xFF1A1A1A),
    disabledCell: Color(0xFFD6D6D6),
  );

  static const _dark = AppColors(
    resultWinBg: Color(0xFF1E3A2A),
    resultWinFg: Color(0xFF81C784),
    resultLossBg: Color(0xFF3A1E22),
    resultLossFg: Color(0xFFE57373),
    resultDrawBg: Color(0xFF3A331E),
    resultDrawFg: Color(0xFFFFD54F),
    resultSpecialBg: Color(0xFF3E2C16),
    resultSpecialFg: Color(0xFFFFB74D),
    bannerBg: Color(0xFF1B2838),
    bannerBorder: Color(0xFF2A3A4E),
    bannerText: Color(0xFFC8D2E0),
    tableHeaderBg: Color(0xFF1B2838),
    tableBorder: Color(0xFF2A3A4E),
    separatorCell: Color(0xFF33445C),
    diagonalCell: Color(0xFF2A3A4E),
    hoverHighlight: Color(0xFF243447),
    mutedText: Color(0xFF9FB0C4),
    disabledCell: Color(0xFF152238),
  );

  static const _darkHighContrast = AppColors(
    resultWinBg: Color(0xFF2C6344),
    resultWinFg: Color(0xFFB6F0BD),
    resultLossBg: Color(0xFF6E3036),
    resultLossFg: Color(0xFFFFC2C2),
    resultDrawBg: Color(0xFF66582C),
    resultDrawFg: Color(0xFFFFE9A6),
    resultSpecialBg: Color(0xFF6E4E22),
    resultSpecialFg: Color(0xFFFFD9A6),
    bannerBg: Color(0xFF24344A),
    bannerBorder: Color(0xFF7C90AC),
    bannerText: Color(0xFFFFFFFF),
    tableHeaderBg: Color(0xFF24344A),
    tableBorder: Color(0xFF6E8199),
    separatorCell: Color(0xFF5A6E8A),
    diagonalCell: Color(0xFF3A4D66),
    hoverHighlight: Color(0xFF31465E),
    mutedText: Color(0xFFD6DEEA),
    disabledCell: Color(0xFF1B2838),
  );

  @override
  AppColors copyWith({
    Color? resultWinBg,
    Color? resultWinFg,
    Color? resultLossBg,
    Color? resultLossFg,
    Color? resultDrawBg,
    Color? resultDrawFg,
    Color? resultSpecialBg,
    Color? resultSpecialFg,
    Color? bannerBg,
    Color? bannerBorder,
    Color? bannerText,
    Color? tableHeaderBg,
    Color? tableBorder,
    Color? separatorCell,
    Color? diagonalCell,
    Color? hoverHighlight,
    Color? mutedText,
    Color? disabledCell,
  }) {
    return AppColors(
      resultWinBg: resultWinBg ?? this.resultWinBg,
      resultWinFg: resultWinFg ?? this.resultWinFg,
      resultLossBg: resultLossBg ?? this.resultLossBg,
      resultLossFg: resultLossFg ?? this.resultLossFg,
      resultDrawBg: resultDrawBg ?? this.resultDrawBg,
      resultDrawFg: resultDrawFg ?? this.resultDrawFg,
      resultSpecialBg: resultSpecialBg ?? this.resultSpecialBg,
      resultSpecialFg: resultSpecialFg ?? this.resultSpecialFg,
      bannerBg: bannerBg ?? this.bannerBg,
      bannerBorder: bannerBorder ?? this.bannerBorder,
      bannerText: bannerText ?? this.bannerText,
      tableHeaderBg: tableHeaderBg ?? this.tableHeaderBg,
      tableBorder: tableBorder ?? this.tableBorder,
      separatorCell: separatorCell ?? this.separatorCell,
      diagonalCell: diagonalCell ?? this.diagonalCell,
      hoverHighlight: hoverHighlight ?? this.hoverHighlight,
      mutedText: mutedText ?? this.mutedText,
      disabledCell: disabledCell ?? this.disabledCell,
    );
  }

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      resultWinBg: c(resultWinBg, other.resultWinBg),
      resultWinFg: c(resultWinFg, other.resultWinFg),
      resultLossBg: c(resultLossBg, other.resultLossBg),
      resultLossFg: c(resultLossFg, other.resultLossFg),
      resultDrawBg: c(resultDrawBg, other.resultDrawBg),
      resultDrawFg: c(resultDrawFg, other.resultDrawFg),
      resultSpecialBg: c(resultSpecialBg, other.resultSpecialBg),
      resultSpecialFg: c(resultSpecialFg, other.resultSpecialFg),
      bannerBg: c(bannerBg, other.bannerBg),
      bannerBorder: c(bannerBorder, other.bannerBorder),
      bannerText: c(bannerText, other.bannerText),
      tableHeaderBg: c(tableHeaderBg, other.tableHeaderBg),
      tableBorder: c(tableBorder, other.tableBorder),
      separatorCell: c(separatorCell, other.separatorCell),
      diagonalCell: c(diagonalCell, other.diagonalCell),
      hoverHighlight: c(hoverHighlight, other.hoverHighlight),
      mutedText: c(mutedText, other.mutedText),
      disabledCell: c(disabledCell, other.disabledCell),
    );
  }
}

/// Convenience access to [AppColors] from any [BuildContext].
extension AppColorsContext on BuildContext {
  AppColors get appColors =>
      Theme.of(this).extension<AppColors>() ??
      AppColors.from(
        brightness: Theme.of(this).brightness,
        highContrast: false,
      );
}
