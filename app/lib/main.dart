import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/auth_controller.dart';
import 'core/env.dart';
import 'core/providers.dart';
import 'data/auth/auth_api.dart';
import 'data/auth/auth_session.dart';
import 'data/auth/session_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final deviceId = await _getOrCreateDeviceId(prefs);
  // Resolve the stored session BEFORE the first frame so the app never issues an
  // anonymous request for a returning signed-in user (no auth-state race).
  final session = await _hydrateSession();
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        deviceIdProvider.overrideWithValue(deviceId),
        initialSessionProvider.overrideWithValue(session),
      ],
      child: const PlayzyApp(),
    ),
  );
}

/// Reads the persisted session and validates it: a real rejection (401) discards it,
/// but a transport/server/timeout failure keeps it (offline-friendly — a valid session
/// is never destroyed by a flaky launch). Returns null in offline/fake mode.
Future<AuthSession?> _hydrateSession() async {
  if (!Env.hasBackend) return null;
  final store = SecureSessionStore(const FlutterSecureStorage());
  final stored = await store.read();
  if (stored == null) return null;
  try {
    await HttpAuthApi(baseUrl: Env.apiBaseUrl)
        .fetchMe(stored.token)
        .timeout(const Duration(seconds: 5));
    return stored;
  } on UnauthorizedException {
    await store.clear();
    return null;
  } catch (_) {
    return stored; // transport / 5xx / timeout → keep optimistically
  }
}

const _deviceIdKey = 'device_id';

/// Reads the persisted per-install id, creating one on first launch. Awaits the
/// write so a fresh id is durably stored before the app relies on it.
Future<String> _getOrCreateDeviceId(SharedPreferences prefs) async {
  final existing = prefs.getString(_deviceIdKey);
  if (existing != null && existing.isNotEmpty) return existing;
  final rng = Random.secure();
  final id = List.generate(16, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  await prefs.setString(_deviceIdKey, id);
  return id;
}
