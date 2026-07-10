/// Spacing scale — 8pt grid with 4pt half-steps. Mirrors DESIGN.md §4.
/// Calm apps breathe: screen edge margin is [xl]–[xxl], not [lg].
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double x4l = 40;
  static const double x5l = 48;
  static const double x6l = 64;

  /// Default screen edge inset.
  static const double screenEdge = xl;
}
