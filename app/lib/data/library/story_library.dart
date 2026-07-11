import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/story.dart';

/// Bounded retention shared by every [StoryLibrary] so the fake matches
/// production behavior (planning/40, C5).
const int kStoryLibraryMax = 30;

/// Local persistence for generated stories so a parent can re-read past tales
/// (planning/40). One interface so tests use a fake and the store can later sync
/// to the backend without touching callers. Saving is best-effort by contract:
/// a failure here must never fail generation or re-charge quota (C3).
abstract interface class StoryLibrary {
  /// Most-recent-first. Tolerant: a corrupt/legacy entry is skipped, never
  /// failing the whole list (C5).
  Future<List<Story>> recent();

  /// Persist a story at the front, de-duplicating by id (move-to-front), and
  /// bounding retention.
  Future<void> save(Story story);
}

/// [SharedPreferences]-backed store. Each story is one JSON string in a string
/// list, so one malformed entry can't corrupt the rest (per-entry recovery, C5).
class PrefsStoryLibrary implements StoryLibrary {
  PrefsStoryLibrary(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'story_library';

  @override
  Future<List<Story>> recent() async {
    final raw = _prefs.getStringList(_key) ?? const [];
    final out = <Story>[];
    for (final entry in raw) {
      try {
        out.add(Story.fromJson(jsonDecode(entry) as Map<String, dynamic>));
      } catch (_) {
        // Skip a corrupt/legacy entry rather than failing the whole library.
      }
    }
    return out;
  }

  @override
  Future<void> save(Story story) async {
    final raw = _prefs.getStringList(_key) ?? const [];
    // Drop any existing entry with this id, then prepend (move-to-front).
    final kept = raw.where((e) => !_hasId(e, story.id)).toList();
    kept.insert(0, jsonEncode(story.toJson()));
    if (kept.length > kStoryLibraryMax) {
      kept.removeRange(kStoryLibraryMax, kept.length);
    }
    // setStringList reports success; a false result means nothing persisted, so
    // surface it (the caller's best-effort catch then skips the refresh, C3/I1).
    final ok = await _prefs.setStringList(_key, kept);
    if (!ok) throw Exception('failed to persist story library');
  }

  bool _hasId(String entry, String id) {
    try {
      return (jsonDecode(entry) as Map<String, dynamic>)['id'] == id;
    } catch (_) {
      return false; // unparseable → not this id (recent() will drop it anyway)
    }
  }
}

/// In-memory implementation for tests and offline development.
class FakeStoryLibrary implements StoryLibrary {
  FakeStoryLibrary([List<Story> initial = const []]) : _stories = [...initial];

  final List<Story> _stories;

  @override
  Future<List<Story>> recent() async => List.unmodifiable(_stories);

  @override
  Future<void> save(Story story) async {
    _stories.removeWhere((s) => s.id == story.id);
    _stories.insert(0, story);
    // Mirror production's bounded retention so tests can't diverge (I2).
    if (_stories.length > kStoryLibraryMax) {
      _stories.removeRange(kStoryLibraryMax, _stories.length);
    }
  }
}
