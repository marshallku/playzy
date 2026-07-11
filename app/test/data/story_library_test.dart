import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:playzy/data/library/story_library.dart';
import 'package:playzy/domain/story.dart';
import 'package:shared_preferences/shared_preferences.dart';

Story _story(String id, {String title = '이야기'}) =>
    Story(id: id, title: title, pages: const [StoryPage(text: '옛날 옛적에...')]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PrefsStoryLibrary', () {
    late SharedPreferences prefs;
    late PrefsStoryLibrary lib;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      lib = PrefsStoryLibrary(prefs);
    });

    test('save then recent returns the story', () async {
      await lib.save(_story('a'));
      expect((await lib.recent()).map((s) => s.id), ['a']);
    });

    test('recent is most-recent-first', () async {
      await lib.save(_story('a'));
      await lib.save(_story('b'));
      expect((await lib.recent()).map((s) => s.id), ['b', 'a']);
    });

    test('dedupes by id, moving the re-saved story to the front', () async {
      await lib.save(_story('a'));
      await lib.save(_story('b'));
      await lib.save(_story('a', title: '다시 읽기'));
      final r = await lib.recent();
      expect(r.map((s) => s.id), ['a', 'b']); // one 'a', now first
      expect(r.first.title, '다시 읽기');
    });

    test('bounds retention at 30 (oldest dropped)', () async {
      for (var i = 0; i < 35; i++) {
        await lib.save(_story('s$i'));
      }
      final r = await lib.recent();
      expect(r.length, 30);
      expect(r.first.id, 's34'); // newest kept
      expect(r.any((s) => s.id == 's0'), isFalse); // oldest evicted
    });

    test('skips a corrupt entry instead of failing the whole load (C5)', () async {
      await prefs.setStringList('story_library', [
        'not-json',
        jsonEncode(_story('ok').toJson()),
      ]);
      expect((await PrefsStoryLibrary(prefs).recent()).map((s) => s.id), ['ok']);
    });

    test('empty store returns an empty list', () async {
      expect(await lib.recent(), isEmpty);
    });
  });

  group('FakeStoryLibrary', () {
    test('save + dedupe + most-recent-first', () async {
      final lib = FakeStoryLibrary();
      await lib.save(_story('a'));
      await lib.save(_story('b'));
      await lib.save(_story('a'));
      expect((await lib.recent()).map((s) => s.id), ['a', 'b']);
    });
  });
}
