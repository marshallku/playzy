import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:playzy/app.dart';
import 'package:playzy/core/providers.dart';
import 'package:playzy/data/profile/profile_repository.dart';
import 'package:playzy/design/tokens/colors.dart';
import 'package:playzy/features/story/story_reader_screen.dart';

/// The same end-to-end journey as test/, but run ON a real device/simulator via
/// `flutter test integration_test/... -d <device>`. Deliberate pauses hold each
/// screen long enough for an external `simctl io screenshot` to capture it.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const hold = Duration(seconds: 3);

  testWidgets('iOS journey: cold start → finished story', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileRepositoryProvider.overrideWithValue(FakeProfileRepository()),
          deviceIdProvider.overrideWithValue('ios-e2e'),
        ],
        child: const PlayzyApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('아이 정보 입력하고 시작하기'), findsOneWidget);
    await Future<void>.delayed(hold); // capture home

    await tester.tap(find.text('아이 정보 입력하고 시작하기'));
    await tester.pumpAndSettle();
    await Future<void>.delayed(hold); // capture profile form

    await tester.enterText(find.byType(TextFormField).first, '하준');
    await tester.tap(find.text('공룡'));
    await tester.pumpAndSettle();
    // The form is a lazy ListView — on a real device the save button may be
    // below the fold and not yet built, so scroll until it exists, then tap.
    await tester.scrollUntilVisible(
      find.text('저장하기'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장하기'));
    await tester.pumpAndSettle();
    await Future<void>.delayed(const Duration(seconds: 2)); // home w/ profile

    await tester.tap(find.text('오늘의 동화 만들기'));
    await tester.pumpAndSettle();
    expect(find.text('오늘의 이야기'), findsOneWidget);
    await Future<void>.delayed(hold); // capture SDUI picker

    await tester.tap(find.text('🌙 잠자기'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('다음'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();

    // Story options (planning/40): add a character, pick a length, then generate.
    expect(find.text('이야기 꾸미기'), findsOneWidget);
    await Future<void>.delayed(hold); // capture options screen
    await tester.tap(find.text('등장인물 추가'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '뽀삐');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('짧게'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('짧게'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('동화 만들기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('동화 만들기'));
    await tester.pumpAndSettle();

    // Reader, in night mode, personalized.
    expect(find.byType(StoryReaderScreen), findsOneWidget);
    expect(find.textContaining('하준'), findsWidgets);
    final scaffold = tester.widget<Scaffold>(
      find.descendant(of: find.byType(StoryReaderScreen), matching: find.byType(Scaffold)),
    );
    expect(scaffold.backgroundColor, AppColors.night.bgBase);
    await Future<void>.delayed(const Duration(seconds: 4)); // capture reader
  });
}
