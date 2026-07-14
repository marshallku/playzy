import 'package:flutter_test/flutter_test.dart';
import 'package:playzy/design/tokens/typography.dart';

void main() {
  // Locks the font-role wiring in DESIGN.md §3.1 so the story serif and the
  // brand wordmark can't silently regress to the UI face.
  group('AppTypography families', () {
    test('story text uses the bundled Gowun Batang serif', () {
      expect(AppTypography.storyBody.fontFamily, 'GowunBatang');
      expect(AppTypography.storyTitle.fontFamily, 'GowunBatang');
    });

    test('brand wordmark uses Fredoka (and nothing else does)', () {
      expect(AppTypography.brand.fontFamily, 'Fredoka');
      // Korean display is Pretendard-heavy, NOT the wordmark face.
      expect(AppTypography.display.fontFamily, 'Pretendard');
    });

    test('story body keeps a generous read-aloud line-height', () {
      expect(AppTypography.storyBody.height, greaterThanOrEqualTo(1.8));
    });
  });
}
