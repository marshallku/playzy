import 'package:flutter/widgets.dart';

/// Corner-radius scale. Mirrors DESIGN.md §5.1. Kids apps use large soft radii;
/// primary buttons use [pill]; selection chips use [chip] (14).
abstract final class AppRadius {
  static const double sm = 12;
  static const double chip = 14; // selection chips (DESIGN.md §8, ref 14px)
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double pill = 999;

  /// DESIGN.md §5.1 `radius.circle` (50%) maps to Flutter's [BoxShape.circle]
  /// for avatars / icon buttons — use `shape: BoxShape.circle`, not a radius.
  static const BoxShape circle = BoxShape.circle;

  static const Radius smR = Radius.circular(sm);
  static const Radius mdR = Radius.circular(md);
  static const Radius lgR = Radius.circular(lg);
  static const Radius xlR = Radius.circular(xl);

  static const BorderRadius card = BorderRadius.all(lgR);
  static const BorderRadius input = BorderRadius.all(mdR);
  static const BorderRadius sheet = BorderRadius.vertical(top: xlR);
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));
}
