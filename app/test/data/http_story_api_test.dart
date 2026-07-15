import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:playzy/data/story/http_story_api.dart';
import 'package:playzy/data/story/story_api.dart';
import 'package:playzy/domain/story.dart';

const _request = StoryRequest(
  childName: '하준',
  ageBand: 'toddler',
  situationIds: ['bedtime'],
);

void main() {
  group('HttpStoryApi', () {
    test('posts the request and parses the story on 200', () async {
      late http.Request captured;
      final api = HttpStoryApi(
        authHeaders: const {'X-Device-Id': 'test-device'},
        baseUrl: 'https://api.test',
        client: MockClient((req) async {
          captured = req;
          return http.Response(
            jsonEncode({
              'id': 's1',
              'title': '하준 이야기',
              'pages': [
                {'text': '한 페이지'},
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final story = await api.generateStory(_request);

      expect(captured.url.toString(), 'https://api.test/v1/stories');
      expect(captured.method, 'POST');
      expect(captured.headers['X-Device-Id'], 'test-device');
      expect(jsonDecode(captured.body)['childName'], '하준');
      expect(story.title, '하준 이야기');
      expect(story.pages.single.text, '한 페이지');
    });

    test('normalizes a trailing slash in the base URL (no //)', () async {
      late Uri url;
      final api = HttpStoryApi(
        authHeaders: const {'X-Device-Id': 'test-device'},
        baseUrl: 'https://api.test/',
        client: MockClient((req) async {
          url = req.url;
          return http.Response(
            jsonEncode({'id': 's', 'title': 't', 'pages': <dynamic>[]}),
            200,
          );
        }),
      );
      await api.generateStory(_request);
      expect(url.toString(), 'https://api.test/v1/stories');
    });

    test('throws StoryApiException on a non-200 status', () async {
      final api = HttpStoryApi(
        authHeaders: const {'X-Device-Id': 'test-device'},
        baseUrl: 'https://api.test',
        client: MockClient((_) async => http.Response('boom', 500)),
      );
      expect(() => api.generateStory(_request), throwsA(isA<StoryApiException>()));
    });

    test('maps HTTP 402 to StoryQuotaException (paywall)', () async {
      final api = HttpStoryApi(
        authHeaders: const {'X-Device-Id': 'test-device'},
        baseUrl: 'https://api.test',
        client: MockClient((_) async => http.Response('quota', 402)),
      );
      expect(() => api.generateStory(_request), throwsA(isA<StoryQuotaException>()));
    });

    test('throws StoryApiException on malformed JSON', () async {
      final api = HttpStoryApi(
        authHeaders: const {'X-Device-Id': 'test-device'},
        baseUrl: 'https://api.test',
        client: MockClient((_) async => http.Response('not json', 200)),
      );
      expect(() => api.generateStory(_request), throwsA(isA<StoryApiException>()));
    });

    test('wraps transport errors as StoryApiException', () async {
      final api = HttpStoryApi(
        authHeaders: const {'X-Device-Id': 'test-device'},
        baseUrl: 'https://api.test',
        client: MockClient((_) async => throw Exception('offline')),
      );
      expect(() => api.generateStory(_request), throwsA(isA<StoryApiException>()));
    });
  });
}
