import 'package:flutter/widgets.dart';

/// Type scale. Mirrors DESIGN.md §3.2. Three bundled families (all OFL-1.1):
/// [uiFamily] Pretendard drives UI + Korean display; [storyFamily] Gowun Batang
/// is the warm Korean serif for story reading; [brandFamily] Fredoka is used
/// ONLY for the "Playzy" wordmark ([brand]). See `assets/fonts/NOTICE.md`.
abstract final class AppTypography {
  static const String uiFamily = 'Pretendard';
  static const String storyFamily = 'GowunBatang';
  static const String brandFamily = 'Fredoka';

  // Reader font-size bounds (DESIGN.md §3.2). storyBody is scalable 18→28.
  static const double storyMinSize = 18;
  static const double storyMaxSize = 28;
  static const double storyDefaultSize = 20;

  /// The "Playzy" wordmark — Fredoka, brand-only (never body/paragraphs).
  static const TextStyle brand = TextStyle(
    fontFamily: brandFamily,
    fontSize: 34,
    height: 40 / 34,
    fontWeight: FontWeight.w700,
  );

  /// Korean display (e.g. "동주의 밤") — Pretendard heavy, not the wordmark face.
  static const TextStyle display = TextStyle(
    fontFamily: uiFamily,
    fontSize: 34,
    height: 40 / 34,
    fontWeight: FontWeight.w800,
  );
  static const TextStyle h1 = TextStyle(
    fontSize: 28,
    height: 36 / 28,
    fontWeight: FontWeight.w700,
  );
  static const TextStyle h2 = TextStyle(
    fontSize: 22,
    height: 30 / 22,
    fontWeight: FontWeight.w700,
  );
  static const TextStyle h3 = TextStyle(
    fontSize: 18,
    height: 26 / 18,
    fontWeight: FontWeight.w700,
  );
  // Body stays weight 400: the reference swatch shows 500, but this audience
  // benefits from paragraph legibility over weight (DESIGN.md §1 principle 6),
  // so 400 is an intentional, documented deviation.
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
    fontWeight: FontWeight.w700,
  );

  /// Story reading body — Gowun Batang serif, generous 1.85 line-height for
  /// read-aloud (DESIGN.md §3.2). Size is overridden at runtime by the reader
  /// slider; overriding only fontSize keeps this ratio.
  static const TextStyle storyBody = TextStyle(
    fontFamily: storyFamily,
    fontSize: storyDefaultSize,
    height: 1.85,
    fontWeight: FontWeight.w400,
  );
  static const TextStyle storyTitle = TextStyle(
    fontFamily: storyFamily,
    fontSize: 26,
    height: 34 / 26,
    fontWeight: FontWeight.w700,
  );
}
