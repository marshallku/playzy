import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playzy/design/tokens/colors.dart';

/// WCAG 2.1 relative luminance of an sRGB color.
double _luminance(Color c) {
  double channel(double v) {
    final s = v; // already 0..1
    return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  final r = channel(c.r);
  final g = channel(c.g);
  final b = channel(c.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// WCAG contrast ratio between two colors (1..21).
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  // Locks the accessibility contract in DESIGN.md §2.5 so a token tweak can't
  // silently break button-text contrast again.
  group('WCAG AA contrast', () {
    test('button text on light primary meets AA (>=4.5:1)', () {
      final ratio = _contrast(AppColors.light.textOnBrand, AppColors.light.primary);
      expect(ratio, greaterThanOrEqualTo(4.5), reason: 'ratio=$ratio');
    });

    test('night reader text on night base is legible (>=4.5:1)', () {
      final ratio = _contrast(AppColors.night.textPrimary, AppColors.night.bgBase);
      expect(ratio, greaterThanOrEqualTo(4.5), reason: 'ratio=$ratio');
    });

    test('light body text on base meets AA', () {
      final ratio = _contrast(AppColors.light.textPrimary, AppColors.light.bgBase);
      expect(ratio, greaterThanOrEqualTo(4.5), reason: 'ratio=$ratio');
    });

    // Hint/caption/error text renders at ≤14px (normal-size) across the funnel,
    // profile, roster and home screens. Text sits on BOTH the scaffold base AND
    // cards (bgSurface), so both pairs must clear AA — the reference mockup's
    // soft `#9C948A` (≈2.7:1) would not (DESIGN.md §2.5).
    for (final mode in ['light', 'night']) {
      final c = mode == 'light' ? AppColors.light : AppColors.night;
      for (final surface in ['base', 'surface']) {
        final bg = surface == 'base' ? c.bgBase : c.bgSurface;
        test('$mode secondary text on $surface meets AA', () {
          final ratio = _contrast(c.textSecondary, bg);
          expect(ratio, greaterThanOrEqualTo(4.5), reason: '$mode/$surface=$ratio');
        });
        test('$mode tertiary (hint) text on $surface meets AA', () {
          final ratio = _contrast(c.textTertiary, bg);
          expect(ratio, greaterThanOrEqualTo(4.5), reason: '$mode/$surface=$ratio');
        });
        test('$mode error text on $surface meets AA', () {
          final ratio = _contrast(c.error, bg);
          expect(ratio, greaterThanOrEqualTo(4.5), reason: '$mode/$surface=$ratio');
        });
      }
    }

    // ColorScheme foreground/background pairs the theme exposes to Material
    // widgets (e.g. text on a `secondary` fill) must also clear AA. `secondary`
    // is a light-ish coral in both modes, so `onSecondary` is dark in both.
    // The home quota card fills with `primarySubtle` (a tint) and renders its
    // caption in `textSecondary` — a text-on-tint pair that §2.5 requires be
    // checked; primarySubtle is the lightest night surface, so it's the binding
    // constraint for the supporting tone.
    for (final mode in ['light', 'night']) {
      final c = mode == 'light' ? AppColors.light : AppColors.night;
      test('$mode quota-card caption (secondary on primarySubtle) meets AA', () {
        final ratio = _contrast(c.textSecondary, c.primarySubtle);
        expect(ratio, greaterThanOrEqualTo(4.5), reason: '$mode=$ratio');
      });
    }

    // The funnel progress bar's filled (primary) vs track (bgSubtle) is a
    // meaningful non-text graphic → ≥3:1 in both modes (bgAlt failed at night).
    test('progress fill vs track clears 3:1 (both modes)', () {
      final light = _contrast(AppColors.light.primary, AppColors.light.bgSubtle);
      final night = _contrast(AppColors.night.primary, AppColors.night.bgSubtle);
      expect(light, greaterThanOrEqualTo(3.0), reason: 'light=$light');
      expect(night, greaterThanOrEqualTo(3.0), reason: 'night=$night');
    });

    // The reader night/light toggle is an essential UI graphic (≥3:1): moon-gold
    // on the night canvas, brand periwinkle on the light cream. Accent alone
    // would be ≈1.5:1 on cream, so the light reader uses primary instead.
    test('reader toggle icon clears the 3:1 UI-graphic bar in both modes', () {
      final night = _contrast(AppColors.night.accent, AppColors.night.bgBase);
      final light = _contrast(AppColors.light.primary, AppColors.light.bgBase);
      expect(night, greaterThanOrEqualTo(3.0), reason: 'night=$night');
      expect(light, greaterThanOrEqualTo(3.0), reason: 'light=$light');
    });

    // Reader page-indicator dots convey page position — a meaningful graphic
    // (≥3:1). Inactive dots use the muted tertiary tone (not a faded primary),
    // so they stay perceivable on the reader canvas in both palettes.
    test('inactive page dots clear the 3:1 UI-graphic bar (both modes)', () {
      final light = _contrast(AppColors.light.textTertiary, AppColors.light.bgBase);
      final night = _contrast(AppColors.night.textTertiary, AppColors.night.bgBase);
      expect(light, greaterThanOrEqualTo(3.0), reason: 'light=$light');
      expect(night, greaterThanOrEqualTo(3.0), reason: 'night=$night');
    });

    // Secondary button = primarySubtle fill + a label on that tint. The plain
    // brand.primary label is only 4.4:1 on the light tint, so the label token is
    // primaryPressed (light) / textPrimary (night) — both clear AA (§8).
    test('secondary-button label on primarySubtle meets AA (both modes)', () {
      final light = _contrast(
          AppColors.light.primaryPressed, AppColors.light.primarySubtle);
      final night =
          _contrast(AppColors.night.textPrimary, AppColors.night.primarySubtle);
      expect(light, greaterThanOrEqualTo(4.5), reason: 'light=$light');
      expect(night, greaterThanOrEqualTo(4.5), reason: 'night=$night');
    });

    test('onSecondary on the secondary fill meets AA (both modes)', () {
      final light =
          _contrast(AppColors.light.textPrimary, AppColors.light.secondary);
      final night =
          _contrast(AppColors.night.bgBase, AppColors.night.secondary);
      expect(light, greaterThanOrEqualTo(4.5), reason: 'light=$light');
      expect(night, greaterThanOrEqualTo(4.5), reason: 'night=$night');
    });
  });
}
