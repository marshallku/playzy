import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:playzy/core/providers.dart';
import 'package:playzy/data/profile/profile_repository.dart';
import 'package:playzy/design/theme.dart';
import 'package:playzy/domain/child_profile.dart';
import 'package:playzy/features/child_profile/child_profile_screen.dart';

GoRouter _router() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('home'))),
        GoRoute(path: '/profile', builder: (_, __) => const ChildProfileScreen()),
      ],
    );

void main() {
  Future<GoRouter> pumpProfile(WidgetTester tester, ProfileRepository repo) async {
    final router = _router();
    await tester.pumpWidget(ProviderScope(
      overrides: [profileRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ));
    router.push('/profile');
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('shows a validation error when the name is empty', (tester) async {
    await pumpProfile(tester, FakeProfileRepository());

    await tester.tap(find.text('저장하기'));
    await tester.pump();

    expect(find.text('이름을 입력해 주세요'), findsOneWidget);
  });

  testWidgets('hydrates the form from an existing profile (no overwrite)', (tester) async {
    final repo = FakeProfileRepository(
      profile: const ChildProfile(id: 'child-1', givenName: '서연', ageBand: AgeBand.preschool),
    );
    await pumpProfile(tester, repo);

    // The existing name is shown, not an empty default.
    expect(find.text('서연'), findsOneWidget);
  });

  testWidgets('saves a profile and pops when the form is valid', (tester) async {
    final repo = FakeProfileRepository();
    await pumpProfile(tester, repo);

    // Field order: 성(family) first, 이름(given) second — enter the given name.
    await tester.enterText(find.byType(TextFormField).at(1), '하준');
    await tester.tap(find.text('공룡'));
    await tester.pump();
    await tester.tap(find.text('저장하기'));
    await tester.pumpAndSettle();

    final saved = await repo.loadProfile();
    expect(saved?.givenName, '하준');
    expect(saved?.interests, contains('공룡'));
    // Popped back to home after saving.
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('a failed save does not pop and surfaces an error', (tester) async {
    await pumpProfile(tester, _ThrowingProfileRepository());

    await tester.enterText(find.byType(TextFormField).at(1), '하준');
    await tester.tap(find.text('저장하기'));
    await tester.pumpAndSettle();

    // Still on the form (not popped to home), with an error shown.
    expect(find.text('home'), findsNothing);
    expect(find.text('저장하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
  });
}

/// Save always fails — verifies the screen treats failure as failure.
class _ThrowingProfileRepository extends FakeProfileRepository {
  @override
  Future<void> saveProfile(ChildProfile profile) async =>
      throw Exception('disk full');
}
