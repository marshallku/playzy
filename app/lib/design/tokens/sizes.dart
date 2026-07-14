/// Component sizes as named tokens (DESIGN.md §8, §9) so widgets carry no
/// magic dimensions.
abstract final class AppSizes {
  /// Primary button height (DESIGN.md §8 — 52–56px).
  static const double buttonHeight = 54;

  /// Minimum tap target (DESIGN.md §9).
  static const double touchMin = 44;

  /// Night-reader controls, used one-handed in the dark (DESIGN.md §9).
  static const double nightControlMin = 80;

  /// Reader page-indicator dots.
  static const double pageDot = 8;
  static const double pageDotActive = 20;

  /// Funnel progress-bar track thickness.
  static const double progressTrack = 6;
}
