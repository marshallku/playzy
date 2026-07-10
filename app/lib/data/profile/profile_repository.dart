import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/child_profile.dart';

/// Local persistence for the child profile + the free-tier generation count.
/// One child for MVP (docs/planning/10). An interface so tests use a fake and
/// the store can later sync to the backend without touching callers.
abstract interface class ProfileRepository {
  Future<ChildProfile?> loadProfile();
  Future<void> saveProfile(ChildProfile profile);

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
  FakeProfileRepository({ChildProfile? profile, int count = 0, int credits = 0})
      : _profile = profile,
        _count = count,
        _credits = credits;

  ChildProfile? _profile;
  int _count;
  int _credits;

  @override
  Future<ChildProfile?> loadProfile() async => _profile;

  @override
  Future<void> saveProfile(ChildProfile profile) async => _profile = profile;

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
