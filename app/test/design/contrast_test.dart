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
  });
}
