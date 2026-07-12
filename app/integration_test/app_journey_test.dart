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

    // Field order: 성(family) first, 이름(given) second — enter the given name.
    await tester.enterText(find.byType(TextFormField).at(1), '하준');
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

    // Funnel 1/3 (topic): type a seed AND pick a chip (both are kept), continue.
    expect(find.text('오늘은 어떤 이야기를 들려줄까요?'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '오늘 이가 새로 났어요');
    await tester.pumpAndSettle();
    await tester.tap(find.text('🌙 잠자기'));
    await tester.pumpAndSettle();
    await Future<void>.delayed(hold); // capture topic step
    await tester.ensureVisible(find.text('다음'));
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();

    // Funnel 2/3 (cast): add a new character (saved to roster + selected).
    expect(find.text('함께할 친구를 골라요'), findsOneWidget);
    await tester.tap(find.text('새 인물 추가'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '뽀삐');
    await tester.tap(find.text('추가'));
    await tester.pumpAndSettle();
    await Future<void>.delayed(hold); // capture cast step
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();

    // Funnel 3/3 (tone): pick a length, then generate.
    expect(find.text('어떤 분위기로 들려줄까요?'), findsOneWidget);
    await tester.ensureVisible(find.text('짧게'));
    await tester.tap(find.text('짧게'));
    await tester.pumpAndSettle();
    await Future<void>.delayed(hold); // capture tone step
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
