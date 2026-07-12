import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playzy/core/providers.dart';
import 'package:playzy/data/profile/profile_repository.dart';
import 'package:playzy/design/theme.dart';
import 'package:playzy/domain/story_options.dart';
import 'package:playzy/features/roster/roster_screen.dart';

Future<FakeProfileRepository> _pump(
  WidgetTester tester, {
  List<StoryCharacter>? roster,
}) async {
  final repo = FakeProfileRepository(roster: roster);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [profileRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(theme: AppTheme.light, home: const RosterScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('empty roster shows the empty state', (tester) async {
    await _pump(tester, roster: const []);
    expect(find.text('아직 저장한 인물이 없어요'), findsOneWidget);
  });

  testWidgets('adding a character persists it and shows it', (tester) async {
    final repo = await _pump(tester, roster: const []);

    await tester.enterText(find.byType(TextField).first, '뽀삐');
    await tester.tap(find.byTooltip('추가'));
    await tester.pumpAndSettle();

    expect(find.text('뽀삐'), findsOneWidget);
    expect((await repo.loadRoster()).single.name, '뽀삐');
  });

  testWidgets('deleting a character removes it', (tester) async {
    await _pump(tester, roster: const [
      StoryCharacter(name: '이모', kind: CharacterKind.family),
    ]);

    expect(find.text('이모'), findsOneWidget);
    await tester.tap(find.byTooltip('삭제'));
    await tester.pumpAndSettle();
    expect(find.text('이모'), findsNothing);
  });
}
