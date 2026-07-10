import 'package:flutter/animation.dart';

/// Motion tokens — gentle, slow, wind-down. Mirrors DESIGN.md §7.
/// The reader page-turn uses [slow]; no bounce in the reader.
abstract final class AppMotion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration base = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 500);

  /// Very slow ambient drift (stars/clouds behind the reader).
  static const Duration ambient = Duration(seconds: 120);

  /// Default easing (Headspace-style ease-in-out).
  static const Cubic ease = Cubic(0.25, 0.1, 0.25, 1);
}
