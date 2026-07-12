import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:playzy/core/constants.dart';
import 'package:playzy/core/providers.dart';
import 'package:playzy/core/router.dart';
import 'package:playzy/data/profile/profile_repository.dart';
import 'package:playzy/design/theme.dart';
import 'package:playzy/domain/story_options.dart';
import 'package:playzy/features/create/create_cast_screen.dart';
import 'package:playzy/features/create/create_topic_screen.dart';
import 'package:playzy/features/create/story_draft.dart';

/// Pumps a single funnel screen with a router that also owns the next-step
/// routes, so navigation and the shared draft are exercised for real.
Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget screen, {
  FakeProfileRepository? repo,
}) async {
  final container = ProviderContainer(overrides: [
    if (repo != null) profileRepositoryProvider.overrideWithValue(repo),
  ]);
  addTearDown(container.dispose);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => screen),
    GoRoute(path: Routes.createCast, builder: (_, __) => const CreateCastScreen()),
    GoRoute(path: Routes.createTone, builder: (_, __) => const Scaffold(body: Text('tone'))),
    GoRoute(path: Routes.roster, builder: (_, __) => const Scaffold(body: Text('roster'))),
  ]);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('topic step: 다음 is disabled until a subject is given', (tester) async {
    final c = await _pump(tester, const CreateTopicScreen());

    // No topic, no chip → the CTA is disabled.
    final next = tester.widget<FilledButton>(
      find.ancestor(of: find.text('다음'), matching: find.byType(FilledButton)),
    );
    expect(next.onPressed, isNull);

    // Typing a seed enables it and writes it to the shared draft.
    await tester.enterText(find.byType(TextField).first, '오늘 이가 났어요');
    await tester.pump();
    expect(c.read(storyDraftProvider).topic, '오늘 이가 났어요');
    final next2 = tester.widget<FilledButton>(
      find.ancestor(of: find.text('다음'), matching: find.byType(FilledButton)),
    );
    expect(next2.onPressed, isNotNull);
  });

  testWidgets('topic step: a chip alone is a valid subject and advances', (tester) async {
    await _pump(tester, const CreateTopicScreen());
    await tester.tap(find.text('🌙 잠자기'));
    await tester.pump();
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();
    // Advanced to the cast step.
    expect(find.text('함께할 친구를 골라요'), findsOneWidget);
  });

  testWidgets('cast step: selection is capped at maxCharactersPerStory', (tester) async {
    final roster = [
      for (var i = 0; i < AppConstants.maxCharactersPerStory + 2; i++)
        StoryCharacter(name: '인물$i', kind: CharacterKind.friend),
    ];
    final c = await _pump(tester, const CreateCastScreen(),
        repo: FakeProfileRepository(roster: roster));

    for (final ch in roster) {
      final chip = find.widgetWithText(FilterChip, '${ch.name} · ${ch.kind.label}');
      await tester.tap(chip);
      await tester.pump();
    }
    // Only the cap is selected; extra taps are ignored (disabled chips).
    expect(c.read(storyDraftProvider).cast.length, AppConstants.maxCharactersPerStory);
  });
}
