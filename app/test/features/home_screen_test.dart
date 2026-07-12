import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playzy/app.dart';
import 'package:playzy/core/providers.dart';
import 'package:playzy/data/library/story_library.dart';
import 'package:playzy/data/profile/profile_repository.dart';
import 'package:playzy/domain/child_profile.dart';
import 'package:playzy/domain/story.dart';
import 'package:playzy/features/story/story_reader_screen.dart';

const _child = ChildProfile(id: 'c1', givenName: '하준', ageBand: AgeBand.toddler);

Story _story(String id, String title) =>
    Story(id: id, title: title, pages: const [StoryPage(text: '옛날 옛적에...')]);

Future<void> _pumpHome(WidgetTester tester, {required List<Story> library}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileRepositoryProvider
            .overrideWithValue(FakeProfileRepository(profile: _child)),
        deviceIdProvider.overrideWithValue('home-test'),
        storyLibraryProvider.overrideWithValue(FakeStoryLibrary(library)),
      ],
      child: const PlayzyApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('greets the child by name and offers the generate CTA', (tester) async {
    await _pumpHome(tester, library: const []);
    expect(find.text('하준의 밤'), findsOneWidget);
    expect(find.text('오늘의 동화 만들기'), findsOneWidget);
  });

  testWidgets('hides the recent shelf when the library is empty', (tester) async {
    await _pumpHome(tester, library: const []);
    expect(find.text('지난 이야기'), findsNothing);
  });

  testWidgets('shows recent stories and opens one in the reader', (tester) async {
    await _pumpHome(tester, library: [_story('s1', '하준의 우주 모험')]);

    expect(find.text('지난 이야기'), findsOneWidget);
    expect(find.text('하준의 우주 모험'), findsOneWidget);

    await tester.tap(find.text('하준의 우주 모험'));
    await tester.pumpAndSettle();
    expect(find.byType(StoryReaderScreen), findsOneWidget);
  });

  testWidgets('lists recent stories most-recent-first', (tester) async {
    await _pumpHome(tester, library: [_story('s2', '두 번째'), _story('s1', '첫 번째')]);
    final first = tester.getTopLeft(find.text('두 번째'));
    final second = tester.getTopLeft(find.text('첫 번째'));
    expect(first.dy, lessThan(second.dy)); // '두 번째' shelved above '첫 번째'
  });
}
