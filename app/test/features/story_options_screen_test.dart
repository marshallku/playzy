import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:playzy/core/providers.dart';
import 'package:playzy/data/profile/profile_repository.dart';
import 'package:playzy/design/theme.dart';
import 'package:playzy/domain/child_profile.dart';
import 'package:playzy/domain/story.dart';
import 'package:playzy/domain/story_options.dart';
import 'package:playzy/features/story/story_options_screen.dart';

/// Pumps the options screen with a profile, capturing the request handed to the
/// (stubbed) generating route so we can assert what the screen builds.
Future<StoryRequest?> _pumpOptions(WidgetTester tester,
    {required List<String> situationIds}) async {
  StoryRequest? captured;
  final router = GoRouter(
    initialLocation: '/options',
    routes: [
      GoRoute(
        path: '/options',
        builder: (_, __) => StoryOptionsScreen(situationIds: situationIds),
      ),
      GoRoute(
        path: '/generating',
        builder: (_, state) {
          captured = state.extra as StoryRequest;
          return const Scaffold(body: Text('generating'));
        },
      ),
      GoRoute(
          path: '/paywall',
          builder: (_, __) => const Scaffold(body: Text('paywall'))),
      GoRoute(
          path: '/profile',
          builder: (_, __) => const Scaffold(body: Text('profile'))),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileRepositoryProvider.overrideWithValue(
          FakeProfileRepository(
            profile: const ChildProfile(
                id: 'c1', name: '하준', ageBand: AgeBand.toddler),
          ),
        ),
        deviceIdProvider.overrideWithValue('test-device'),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return captured;
}

// Reads the captured request out of the closure after generation.
void main() {
  testWidgets(
      'builds a request with default mood and no explicit length/setting',
      (tester) async {
    late StoryRequest captured;
    final router = GoRouter(
      initialLocation: '/options',
      routes: [
        GoRoute(
          path: '/options',
          builder: (_, __) =>
              const StoryOptionsScreen(situationIds: ['bedtime']),
        ),
        GoRoute(
          path: '/generating',
          builder: (_, state) {
            captured = state.extra as StoryRequest;
            return const Scaffold(body: Text('generating'));
          },
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileRepositoryProvider.overrideWithValue(
            FakeProfileRepository(
              profile: const ChildProfile(
                  id: 'c1', name: '하준', ageBand: AgeBand.toddler),
            ),
          ),
          deviceIdProvider.overrideWithValue('test-device'),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('동화 만들기'));
    await tester.pumpAndSettle();

    expect(captured.situationIds, ['bedtime']);
    expect(captured.mood, StoryMood.cozy);
    expect(
        captured.length, isNull); // nothing picked → age default (planning/40)
    expect(captured.setting, isNull);
    expect(captured.characters, isEmpty);
  });

  testWidgets('captures added character, chosen length, and mood',
      (tester) async {
    late StoryRequest captured;
    final router = GoRouter(
      initialLocation: '/options',
      routes: [
        GoRoute(
          path: '/options',
          builder: (_, __) =>
              const StoryOptionsScreen(situationIds: ['forest']),
        ),
        GoRoute(
          path: '/generating',
          builder: (_, state) {
            captured = state.extra as StoryRequest;
            return const Scaffold(body: Text('generating'));
          },
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileRepositoryProvider.overrideWithValue(
            FakeProfileRepository(
              profile: const ChildProfile(
                  id: 'c1', name: '서연', ageBand: AgeBand.preschool),
            ),
          ),
          deviceIdProvider.overrideWithValue('test-device'),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('등장인물 추가'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '뽀삐');
    await tester.pump();

    await tester.ensureVisible(find.text('길게'));
    await tester.tap(find.text('길게'));
    await tester.pump();

    await tester.tap(find.text('동화 만들기'));
    await tester.pumpAndSettle();

    expect(captured.characters.single.name, '뽀삐');
    expect(
        captured.characters.single.kind, CharacterKind.family); // default kind
    expect(captured.length, StoryLength.long);
    expect(captured.mood, StoryMood.cozy);
  });

  testWidgets('caps character rows at the max', (tester) async {
    // Tall surface so every row + the add button stay on-screen (no scroll flake).
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpOptions(tester, situationIds: ['bedtime']);
    for (var i = 0; i < 7; i++) {
      final addBtn = find.text('등장인물 추가');
      if (addBtn.evaluate().isEmpty) break; // button relabels at the cap
      await tester.tap(addBtn);
      await tester.pumpAndSettle();
    }
    // 5 rows max → the add button is replaced by the cap label.
    expect(find.byType(TextField), findsNWidgets(5));
    expect(find.textContaining('최대 5명'), findsOneWidget);
  });

  testWidgets('quota error disables generate and offers retry, never paywall',
      (tester) async {
    // C2: a failed/unresolved quota is NOT "exhausted" — the screen must not
    // send an eligible user to the paywall.
    final router = GoRouter(
      initialLocation: '/options',
      routes: [
        GoRoute(
          path: '/options',
          builder: (_, __) =>
              const StoryOptionsScreen(situationIds: ['bedtime']),
        ),
        GoRoute(
            path: '/generating',
            builder: (_, __) => const Scaffold(body: Text('generating'))),
        GoRoute(
            path: '/paywall',
            builder: (_, __) => const Scaffold(body: Text('PAYWALL'))),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileRepositoryProvider.overrideWithValue(
            FakeProfileRepository(
              profile: const ChildProfile(
                  id: 'c1', name: '하준', ageBand: AgeBand.toddler),
            ),
          ),
          deviceIdProvider.overrideWithValue('test-device'),
          quotaStateProvider
              .overrideWith((ref) => Future.error(Exception('boom'))),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('다시 시도'), findsOneWidget);
    // The generate button is disabled; tapping it must not navigate to paywall.
    await tester.tap(find.text('동화 만들기'));
    await tester.pumpAndSettle();
    expect(find.text('PAYWALL'), findsNothing);
    expect(find.text('이야기 꾸미기'), findsOneWidget); // still on options
  });
}
