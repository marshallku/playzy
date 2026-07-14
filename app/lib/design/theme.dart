import 'package:flutter/material.dart';

import 'tokens/borders.dart';
import 'tokens/colors.dart';
import 'tokens/radius.dart';
import 'tokens/spacing.dart';
import 'tokens/typography.dart';

export 'tokens/borders.dart';
export 'tokens/colors.dart';
export 'tokens/sizes.dart';
export 'tokens/motion.dart';
export 'tokens/radius.dart';
export 'tokens/shadows.dart';
export 'tokens/spacing.dart';
export 'tokens/typography.dart';

/// Night is expressed as [Brightness.dark]; light as [Brightness.light].
extension AppColorsX on BuildContext {
  /// Design-system colors for the current brightness (DESIGN.md §2, §10).
  AppColors get colors =>
      Theme.of(this).brightness == Brightness.dark ? AppColors.night : AppColors.light;
}

/// Assembles [ThemeData] from design tokens (DESIGN.md §12).
/// Components read tokens; they never hardcode hex/sizes.
abstract final class AppTheme {
  static ThemeData get light => _build(AppColors.light, Brightness.light);
  static ThemeData get dark => _build(AppColors.night, Brightness.dark);

  static ThemeData _build(AppColors c, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.primary,
      onPrimary: c.textOnBrand,
      secondary: c.secondary,
      // `secondary` (coral) is light-ish in BOTH modes, so its foreground must
      // be dark in both — `textPrimary` is dark in light mode but the moon-glow
      // cream in night, which would fail AA on the coral fill. Use the dark
      // navy there instead.
      onSecondary: brightness == Brightness.light ? c.textPrimary : c.bgBase,
      error: c.error,
      onError: c.textOnBrand,
      surface: c.bgSurface,
      onSurface: c.textPrimary,
    );

    final textTheme = _textTheme(c);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: c.bgBase,
      colorScheme: scheme,
      fontFamily: AppTypography.uiFamily,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: c.bgBase,
        foregroundColor: c.textPrimary,
        elevation: 0,
        centerTitle: true,
      ),
      chipTheme: ChipThemeData(
        // Selection chips (DESIGN.md §8): surface fill + 1.5px field border,
        // 14px radius; selected = primarySubtle fill + primary border + ✓.
        backgroundColor: c.bgSurface,
        selectedColor: c.primarySubtle,
        checkmarkColor: c.primary,
        side: WidgetStateBorderSide.resolveWith((states) => BorderSide(
              color: states.contains(WidgetState.selected) ? c.primary : c.borderField,
              width: AppBorders.field,
            )),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        // Static label color (AA-safe on both fills in both modes); the selected
        // state is also cued by fill + border + checkmark, never color alone.
        labelStyle: AppTypography.bodySm.copyWith(
          fontWeight: FontWeight.w600,
          color: c.textPrimary,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.bgSurface,
        // Placeholder hint = the muted tertiary tone (AA-safe: ≈5.2:1 on the
        // field fill). Without this, Material resolves hints via a derived
        // onSurfaceVariant, not our token (DESIGN.md §8).
        hintStyle: AppTypography.body.copyWith(color: c.textTertiary),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadius.input,
          borderSide: BorderSide(color: c.borderField, width: AppBorders.field),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.input,
          borderSide: BorderSide(color: c.borderField, width: AppBorders.field),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.input,
          borderSide: BorderSide(color: c.primary, width: AppBorders.focus),
        ),
      ),
    );
  }

  static TextTheme _textTheme(AppColors c) {
    final primary = c.textPrimary;
    final secondary = c.textSecondary;
    return TextTheme(
      displayLarge: AppTypography.display.copyWith(color: primary),
      headlineLarge: AppTypography.h1.copyWith(color: primary),
      headlineMedium: AppTypography.h2.copyWith(color: primary),
      titleLarge: AppTypography.h3.copyWith(color: primary),
      bodyLarge: AppTypography.body.copyWith(color: primary),
      bodyMedium: AppTypography.body.copyWith(color: primary),
      bodySmall: AppTypography.bodySm.copyWith(color: secondary),
      labelSmall: AppTypography.caption.copyWith(color: secondary),
      labelLarge: AppTypography.button.copyWith(color: primary),
    );
  }
}
