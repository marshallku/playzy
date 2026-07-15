import 'dart:convert';

import '../../domain/child_profile.dart';
import '../../domain/story_options.dart';
import 'profile_repository.dart';
import 'profile_sync_api.dart';

/// Syncs the local ChildProfile + character roster with the account-scoped backend
/// documents (WU6). Reconcile runs on login: the ACCOUNT wins when it already has a
/// document (adopt it locally so the user's data follows them across devices);
/// otherwise the local copy seeds the account. Subsequent local edits push up. The
/// local store remains the offline/anonymous cache.
class ProfileSync {
  ProfileSync(this._api, this._repo);

  final ProfileSyncApi _api;
  final ProfileRepository _repo;

  static const _profile = 'profile';
  static const _roster = 'roster';

  /// [shouldContinue] is checked AFTER the (slow) network GET and BEFORE any local
  /// write, so a sign-out that races the reconcile can't have this stale GET write the
  /// former account's data back onto the device (cross-account leakage). Defaults to
  /// always-continue for callers with no session-transition concern (e.g. tests).
  Future<void> reconcile([bool Function()? shouldContinue]) async {
    final guard = shouldContinue ?? () => true;
    await _reconcileProfile(guard);
    await _reconcileRoster(guard);
  }

  Future<void> _reconcileProfile(bool Function() guard) async {
    final remote = await _api.getDoc(_profile);
    if (!guard()) return;
    if (remote != null) {
      await _repo.saveProfile(ChildProfile.decode(remote));
      return;
    }
    final local = await _repo.loadProfile();
    if (local != null) await _api.putDoc(_profile, local.encode());
  }

  Future<void> _reconcileRoster(bool Function() guard) async {
    final remote = await _api.getDoc(_roster);
    if (!guard()) return;
    if (remote != null) {
      await _repo.saveRoster(_decodeRoster(remote));
      return;
    }
    final local = await _repo.loadRoster();
    if (local.isNotEmpty) await _api.putDoc(_roster, _encodeRoster(local));
  }

  Future<void> pushProfile(ChildProfile profile) => _api.putDoc(_profile, profile.encode());

  Future<void> pushRoster(List<StoryCharacter> roster) => _api.putDoc(_roster, _encodeRoster(roster));

  static String _encodeRoster(List<StoryCharacter> roster) =>
      jsonEncode(roster.map((c) => c.toJson()).toList());

  static List<StoryCharacter> _decodeRoster(String doc) => (jsonDecode(doc) as List)
      .map((e) => StoryCharacter.fromJson(e as Map<String, dynamic>))
      .toList();
}
