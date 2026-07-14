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
    required this.borderField,
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

  /// Input/chip outline — a touch stronger/warmer than [borderHairline]
  /// (DESIGN.md §2.1, ref `--field-border`). Rendered at [AppBorders.field].
  final Color borderField;

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

  /// Light theme — warm cream base, periwinkle brand, coral + moon accents.
  /// Never pure black/white. Text tones are darkened from the reference mockup's
  /// `--muted` where needed so 14px hints still meet WCAG AA (DESIGN.md §2.5).
  static const AppColors light = AppColors(
    bgBase: Color(0xFFFBF1E6), // cream — the phone-screen background
    bgSurface: Color(0xFFFFFCF7), // cards / fields
    bgSubtle: Color(0xFFF4EADA), // grouped/inset areas
    bgAlt: Color(0xFFEADFCF), // disabled-button fill (progress track = bgSubtle)
    borderHairline: Color(0xFFECE0D0), // 1px separators (ref --line)
    borderField: Color(0xFFE7DAC8), // input/chip outline (ref --field-border)
    // #5265C6 ≈ 5.2:1 with white — passes WCAG AA for button text (DESIGN.md
    // §2.5). Final hue is designer-owned (D4) but MUST keep ≥4.5:1 with onBrand.
    primary: Color(0xFF5265C6),
    primaryPressed: Color(0xFF43539F),
    primarySubtle: Color(0xFFE7ECF9),
    secondary: Color(0xFFEC9086), // coral warmth accent
    accent: Color(0xFFF3C64B), // moon yellow — 10% pops, stars/moon-glow
    textPrimary: Color(0xFF2C2A31), // ink
    textSecondary: Color(0xFF4A4750), // ink-soft
    // Darkened from the ref's #9C948A (which is only ~2.7:1 on cream) so hint
    // text at 14px clears AA (≈4.75:1). See DESIGN.md §2.5.
    textTertiary: Color(0xFF736A60),
    textOnBrand: Color(0xFFFFFFFF),
    success: Color(0xFF7CBF9E),
    warning: Color(0xFFF2C14E),
    // Error is rendered as body/hint TEXT on the cream base (funnel + home), so
    // it must clear AA there: the soft #E88B8B (~2.2:1) doesn't; this deep coral
    // -red is ≈5.0:1 and still harmonizes with `secondary` (DESIGN.md §2.5).
    error: Color(0xFFB0453E),
    info: Color(0xFF8FB8DE),
  );

  /// Night theme — the hero bedtime scenario. Deep navy, moon-glow warm text.
  /// [textPrimary] is a warm moon-glow cream (never bright white). Supporting
  /// text is a cool slate; both tertiary/secondary clear AA on [bgBase] (§2.5).
  static const AppColors night = AppColors(
    bgBase: Color(0xFF1A2236),
    bgSurface: Color(0xFF232C44),
    bgSubtle: Color(0xFF2A3550),
    bgAlt: Color(0xFF4A4E69),
    borderHairline: Color(0xFF313A54),
    borderField: Color(0xFF313A54),
    primary: Color(0xFF8091E4),
    primaryPressed: Color(0xFF7C93E8),
    primarySubtle: Color(0xFF2E3F63),
    secondary: Color(0xFFE8A79D),
    accent: Color(0xFFFFE082),
    textPrimary: Color(0xFFE9E2D3), // warm moon-glow cream
    // Supporting tones must clear AA on the LIGHTEST night surface — which is
    // the tinted primarySubtle (#2E3F63), where the home quota-card caption
    // renders textSecondary — not just bgBase/bgSurface.
    textSecondary: Color(0xFFA6ADC0), // ≈4.7:1 on primarySubtle, 6.2 on bgSurface
    textTertiary: Color(0xFF979FB2), // ≈5.2:1 on bgSurface (AA for hint text)
    textOnBrand: Color(0xFF1A2236),
    success: Color(0xFF8FD1AE),
    warning: Color(0xFFF5D06F),
    error: Color(0xFFF0A3A3),
    info: Color(0xFFA5C8E8),
  );
}
