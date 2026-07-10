import 'package:flutter/widgets.dart';

/// Semantic color tokens. Mirrors DESIGN.md §2. Names are roles, not hues,
/// so re-theming is a value swap. Every role has a light and a night value.
@immutable
class AppColors {
  const AppColors({
    required this.bgBase,
    required this.bgSurface,
    required this.bgSubtle,
    required this.bgAlt,
    required this.borderHairline,
    required this.primary,
    required this.primaryPressed,
    required this.primarySubtle,
    required this.secondary,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textOnBrand,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
  });

  final Color bgBase;
  final Color bgSurface;
  final Color bgSubtle;
  final Color bgAlt;
  final Color borderHairline;

  final Color primary;
  final Color primaryPressed;
  final Color primarySubtle;
  final Color secondary;
  final Color accent;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textOnBrand;

  final Color success;
  final Color warning;
  final Color error;
  final Color info;

  /// Light theme — warm cream base, periwinkle brand. Never pure black/white.
  static const AppColors light = AppColors(
    bgBase: Color(0xFFFFF8F0),
    bgSurface: Color(0xFFFEFCF8),
    bgSubtle: Color(0xFFF5EEE4),
    bgAlt: Color(0xFFEFE7DB),
    borderHairline: Color(0xFFEAE0D3),
    // #4E6FBC ≈ 4.9:1 with white — passes WCAG AA for button text (DESIGN.md
    // §2.5). Deeper than the research's #6A89CC (which fails AA); final hue is
    // designer-owned (D4) but MUST keep ≥4.5:1 with onPrimary text.
    primary: Color(0xFF4E6FBC),
    primaryPressed: Color(0xFF3F5EA8),
    primarySubtle: Color(0xFFE9EFFA),
    secondary: Color(0xFFF6B6B6),
    accent: Color(0xFFF8C291),
    textPrimary: Color(0xFF2E3A4D),
    textSecondary: Color(0xFF6B7688),
    textTertiary: Color(0xFF9AA3B2),
    textOnBrand: Color(0xFFFFFFFF),
    success: Color(0xFF7CBF9E),
    warning: Color(0xFFF2C14E),
    error: Color(0xFFE88B8B),
    info: Color(0xFF8FB8DE),
  );

  /// Night theme — the hero bedtime scenario. Deep navy, moon-glow warm text.
  /// textPrimary is the moon-glow cream at 90% opacity (never bright white).
  static const AppColors night = AppColors(
    bgBase: Color(0xFF1B2838),
    bgSurface: Color(0xFF24334A),
    bgSubtle: Color(0xFF2C3E50),
    bgAlt: Color(0xFF4A4E69),
    borderHairline: Color(0xFF33445E),
    primary: Color(0xFF91A7E8),
    primaryPressed: Color(0xFF7C93E8),
    primarySubtle: Color(0xFF2E3F63),
    secondary: Color(0xFFE29A9A),
    accent: Color(0xFFFFE082),
    textPrimary: Color(0xE6E8D5B7),
    textSecondary: Color(0xFFB7A98F),
    textTertiary: Color(0xFF8A7F6B),
    textOnBrand: Color(0xFF1B2838),
    success: Color(0xFF8FD1AE),
    warning: Color(0xFFF5D06F),
    error: Color(0xFFF0A3A3),
    info: Color(0xFFA5C8E8),
  );
}
