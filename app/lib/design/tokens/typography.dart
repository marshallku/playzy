import 'package:flutter/widgets.dart';

/// Type scale. Mirrors DESIGN.md §3.2. Story text is large and scalable.
/// [uiFamily] Pretendard is bundled (OFL). [displayFamily] Gmarket Sans is not
/// yet licensed for bundling, so it falls back to Pretendard for now
/// (docs/planning/90 — fonts).
abstract final class AppTypography {
  static const String uiFamily = 'Pretendard';
  static const String displayFamily = uiFamily; // TODO: 'GmarketSans' once licensed

  // Reader font-size bounds (DESIGN.md §3.2). storyBody is scalable 18→28.
  static const double storyMinSize = 18;
  static const double storyMaxSize = 28;
  static const double storyDefaultSize = 20;

  static const TextStyle display = TextStyle(
    fontFamily: displayFamily,
    fontSize: 34,
    height: 40 / 34,
    fontWeight: FontWeight.w700,
  );
  static const TextStyle h1 = TextStyle(
    fontSize: 28,
    height: 36 / 28,
    fontWeight: FontWeight.w700,
  );
  static const TextStyle h2 = TextStyle(
    fontSize: 22,
    height: 30 / 22,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle h3 = TextStyle(
    fontSize: 18,
    height: 26 / 18,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle body = TextStyle(
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
  );
  static const TextStyle bodySm = TextStyle(
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
  );
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w500,
  );
  static const TextStyle button = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );

  /// Story reading body. Size is overridden at runtime by the reader slider.
  static const TextStyle storyBody = TextStyle(
    fontSize: storyDefaultSize,
    height: 32 / 20,
    fontWeight: FontWeight.w400,
  );
  static const TextStyle storyTitle = TextStyle(
    fontSize: 26,
    height: 34 / 26,
    fontWeight: FontWeight.w700,
  );
}
