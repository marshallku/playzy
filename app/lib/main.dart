import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final deviceId = await _getOrCreateDeviceId(prefs);
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        deviceIdProvider.overrideWithValue(deviceId),
      ],
      child: const PlayzyApp(),
    ),
  );
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
