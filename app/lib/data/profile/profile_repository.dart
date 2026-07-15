import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/child_profile.dart';
import '../../domain/story_options.dart';

/// Local persistence for the child profile + the free-tier generation count.
/// One child for MVP (docs/planning/10). An interface so tests use a fake and
/// the store can later sync to the backend without touching callers.
abstract interface class ProfileRepository {
  Future<ChildProfile?> loadProfile();
  Future<void> saveProfile(ChildProfile profile);

  /// The reusable character roster (보관함) — saved once, picked per story. On
  /// first read after upgrade it is seeded from the profile's legacy
  /// `companionName` so that default isn't lost when the profile screen stops
  /// editing it.
  Future<List<StoryCharacter>> loadRoster();
  Future<void> saveRoster(List<StoryCharacter> roster);

  /// Clears the account-synced documents (profile + roster) from local storage. Used
  /// on sign-out so a different user on this device can't inherit the previous user's
  /// profile/roster via sync-seeding (WU6). Quota mirrors are unaffected.
  Future<void> clearSyncedDocs();

  /// Free-tier counter — how many stories this device has generated. In
  /// production the authoritative count is backend-enforced (ADR 0002); this
  /// local mirror gates the UI offline.
  Future<int> generatedCount();
  Future<void> incrementGeneratedCount();
  Future<void> decrementGeneratedCount();

  /// Paid credit balance (extra stories beyond the free tier). Backend-owned in
  /// production (ADR 0002); mirrored locally for offline gating.
  Future<int> credits();
  Future<void> addCredits(int amount);
  Future<void> consumeCredit();
}

/// [SharedPreferences]-backed implementation.
class PrefsProfileRepository implements ProfileRepository {
  PrefsProfileRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _profileKey = 'child_profile';
  static const _rosterKey = 'character_roster';
  static const _countKey = 'generated_count';
  static const _creditsKey = 'credits';

  @override
  Future<ChildProfile?> loadProfile() async {
    final raw = _prefs.getString(_profileKey);
    if (raw == null) return null;
    return ChildProfile.decode(raw);
  }

  @override
  Future<void> saveProfile(ChildProfile profile) async {
    await _prefs.setString(_profileKey, profile.encode());
  }

  @override
  Future<List<StoryCharacter>> loadRoster() async {
    final raw = _prefs.getString(_rosterKey);
    if (raw != null) return _decodeRoster(raw);
    // First read after upgrade: seed once from the legacy profile companion, then
    // persist — EVEN WHEN EMPTY — so "migrated (possibly empty)" is distinct from
    // "never migrated" and a later profile change can't re-trigger seeding
    // (codex WU3 C2). Idempotent on the roster key's presence.
    final seeded = _seedFromLegacyCompanion();
    // Best-effort: if the write fails we simply re-seed next load (the source
    // companion is unchanged), rather than returning a phantom-persisted roster.
    try {
      await _prefs.setString(_rosterKey, _encodeRoster(seeded));
    } catch (_) {/* re-seed next load */}
    return seeded;
  }

  @override
  Future<void> saveRoster(List<StoryCharacter> roster) async {
    await _prefs.setString(_rosterKey, _encodeRoster(roster));
  }

  List<StoryCharacter> _seedFromLegacyCompanion() {
    final raw = _prefs.getString(_profileKey);
    if (raw == null) return const [];
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final companion = (json['companionName'] as String?)?.trim();
      if (companion == null || companion.isEmpty) return const [];
      return [StoryCharacter(name: companion, kind: CharacterKind.friend)];
    } catch (_) {
      return const [];
    }
  }

  String _encodeRoster(List<StoryCharacter> roster) =>
      jsonEncode(roster.map((c) => c.toJson()).toList());

  /// Decodes per-entry: a corrupt/legacy entry is skipped, never failing the
  /// whole load (mirrors the StoryLibrary robustness rule, planning/40 C5).
  List<StoryCharacter> _decodeRoster(String raw) {
    final out = <StoryCharacter>[];
    try {
      for (final e in jsonDecode(raw) as List<dynamic>) {
        try {
          if (e is Map<String, dynamic>) out.add(StoryCharacter.fromJson(e));
        } catch (_) {/* skip corrupt entry */}
      }
    } catch (_) {/* corrupt list → empty */}
    return out;
  }

  @override
  Future<void> clearSyncedDocs() async {
    // remove() returns false on a write failure; treat it as fatal so a caller that
    // relies on the clear for cross-account safety can't proceed on a silent failure.
    final removedProfile = await _prefs.remove(_profileKey);
    final removedRoster = await _prefs.remove(_rosterKey);
    if (!removedProfile || !removedRoster) {
      throw Exception('failed to clear synced profile/roster');
    }
  }

  @override
  Future<int> generatedCount() async => _prefs.getInt(_countKey) ?? 0;

  @override
  Future<void> incrementGeneratedCount() async {
    await _prefs.setInt(_countKey, (await generatedCount()) + 1);
  }

  @override
  Future<void> decrementGeneratedCount() async {
    final current = await generatedCount();
    if (current > 0) await _prefs.setInt(_countKey, current - 1);
  }

  @override
  Future<int> credits() async => _prefs.getInt(_creditsKey) ?? 0;

  @override
  Future<void> addCredits(int amount) async {
    await _prefs.setInt(_creditsKey, (await credits()) + amount);
  }

  @override
  Future<void> consumeCredit() async {
    final current = await credits();
    if (current > 0) await _prefs.setInt(_creditsKey, current - 1);
  }
}

/// In-memory implementation for tests and offline development.
class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository({
    ChildProfile? profile,
    int count = 0,
    int credits = 0,
    List<StoryCharacter>? roster,
  })  : _profile = profile,
        _count = count,
        _credits = credits,
        _roster = roster == null ? null : List.of(roster);

  ChildProfile? _profile;
  int _count;
  int _credits;

  /// null = never set (mirrors the prefs roster-key absence, so the legacy
  /// companion seed fires exactly once).
  List<StoryCharacter>? _roster;

  @override
  Future<ChildProfile?> loadProfile() async => _profile;

  @override
  Future<void> saveProfile(ChildProfile profile) async => _profile = profile;

  @override
  Future<List<StoryCharacter>> loadRoster() async {
    if (_roster != null) return List.of(_roster!);
    // First read: seed once from the legacy companion, then remember it — even
    // when empty — so an emptied roster is never re-seeded and a later profile
    // change can't re-trigger seeding (matches the prefs implementation, C2).
    final companion = _profile?.companionName?.trim();
    final seeded = (companion != null && companion.isNotEmpty)
        ? [StoryCharacter(name: companion, kind: CharacterKind.friend)]
        : <StoryCharacter>[];
    _roster = List.of(seeded);
    return List.of(seeded);
  }

  @override
  Future<void> saveRoster(List<StoryCharacter> roster) async => _roster = List.of(roster);

  @override
  Future<void> clearSyncedDocs() async {
    _profile = null;
    _roster = null;
  }

  @override
  Future<int> generatedCount() async => _count;

  @override
  Future<void> incrementGeneratedCount() async => _count++;

  @override
  Future<void> decrementGeneratedCount() async {
    if (_count > 0) _count--;
  }

  @override
  Future<int> credits() async => _credits;

  @override
  Future<void> addCredits(int amount) async => _credits += amount;

  @override
  Future<void> consumeCredit() async {
    if (_credits > 0) _credits--;
  }
}
