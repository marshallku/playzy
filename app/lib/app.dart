import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router.dart';
import 'design/theme.dart';

/// Root app. Theme follows the system with night as a first-class mode
/// (DESIGN.md §10). Navigation via a provided go_router (ADR 0004) so each
/// scope gets an isolated router.
class PlayzyApp extends ConsumerWidget {
  const PlayzyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Playzy',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
