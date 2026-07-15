import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_session.dart';

/// Persists the signed-in [AuthSession] as one logical record. The token is a
/// bearer secret, so it lives in the platform keychain, never shared_preferences.
abstract interface class SessionStore {
  Future<AuthSession?> read();
  Future<void> write(AuthSession session);
  Future<void> clear();
}

class SecureSessionStore implements SessionStore {
  SecureSessionStore(this._storage);

  final FlutterSecureStorage _storage;
  static const _key = 'playzy_session_v1';

  @override
  Future<AuthSession?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final session = AuthSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (session == null) {
        // Malformed/partial record — drop it so we start cleanly anonymous.
        await clear();
      }
      return session;
    } catch (_) {
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(AuthSession session) =>
      _storage.write(key: _key, value: jsonEncode(session.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
