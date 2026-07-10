/// Border/stroke widths. Kept as named tokens so the theme carries no magic
/// stroke values (DESIGN.md §12 convention).
abstract final class AppBorders {
  static const double hairline = 1;

  /// Focus ring on inputs — a soft, primary-tinted 2px ring (no harsh outline).
  static const double focus = 2;
}
