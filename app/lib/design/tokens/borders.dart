/// Border/stroke widths. Kept as named tokens so the theme carries no magic
/// stroke values (DESIGN.md §12 convention).
abstract final class AppBorders {
  static const double hairline = 1;

  /// Input/chip outline — 1.5px, a hair stronger than [hairline] (DESIGN.md
  /// §8, ref `--field-border` at 1.5px). Pairs with [AppColors.borderField].
  static const double field = 1.5;

  /// Focus ring on inputs — a soft, primary-tinted 2px ring (no harsh outline).
  static const double focus = 2;
}
