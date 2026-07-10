import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playzy/app.dart';
import 'package:playzy/core/providers.dart';
import 'package:playzy/data/profile/profile_repository.dart';
import 'package:playzy/design/tokens/colors.dart';
import 'package:playzy/features/story/story_reader_screen.dart';

/// End-to-end journey through the REAL app (router + providers + every screen)
/// on fake backends: onboarding → child profile → situation picker →
/// generation → bedtime reader. This exercises the whole flow, not one screen.
void main() {
  testWidgets('parent goes from cold start to a finished story', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Offline mode: local mirror + fakes (no backend).
          profileRepositoryProvider.overrideWithValue(FakeProfileRepository()),
          deviceIdProvider.overrideWithValue('e2e-device'),
        ],
        child: const PlayzyApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 1) Home, no profile yet → the setup CTA is shown.
    expect(find.text('Playzy'), findsOneWidget);
    expect(find.text('아이 정보 입력하고 시작하기'), findsOneWidget);
    await tester.tap(find.text('아이 정보 입력하고 시작하기'));
    await tester.pumpAndSettle();

    // 2) Child profile form → fill name + an interest, save.
    expect(find.text('아이 정보'), findsWidgets);
    await tester.enterText(find.byType(TextFormField).first, '하준');
    await tester.tap(find.text('공룡'));
    await tester.pump();
    await tester.tap(find.text('저장하기'));
    await tester.pumpAndSettle();

    // 3) Back home → now the generate CTA is shown.
    expect(find.text('오늘의 동화 만들기'), findsOneWidget);
    await tester.tap(find.text('오늘의 동화 만들기'));
    await tester.pumpAndSettle();

    // 4) Situation picker → choose a situation, then generate.
    expect(find.text('오늘의 이야기'), findsOneWidget);
    await tester.tap(find.text('🌙 잠자기'));
    await tester.pump();
    await tester.tap(find.text('동화 만들기'));
    await tester.pumpAndSettle();

    // 5) Generation completes → the reader shows a titled, non-empty story
    //    starring the child (FakeStoryApi weaves the name in)...
    expect(find.byType(StoryReaderScreen), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget); // reader font-size control
    expect(find.textContaining('하준'), findsWidgets);

    // ...and it opens in NIGHT mode (the bedtime default, DESIGN.md §10):
    // the reader Scaffold paints the night base color regardless of app theme.
    final readerScaffold = tester.widget<Scaffold>(
      find.descendant(of: find.byType(StoryReaderScreen), matching: find.byType(Scaffold)),
    );
    expect(readerScaffold.backgroundColor, AppColors.night.bgBase);
  });

  testWidgets('a fresh install advertises the free story count on home', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileRepositoryProvider.overrideWithValue(FakeProfileRepository()),
          deviceIdProvider.overrideWithValue('e2e-device'),
        ],
        child: const PlayzyApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Fresh install → 3 free stories advertised.
    expect(find.text('무료 동화 3편 남았어요'), findsOneWidget);
  });
}
