import 'package:flutter/material.dart';

import 'core/router.dart';
import 'design/theme.dart';

/// Root app. Theme follows the system with night as a first-class mode
/// (DESIGN.md §10). Navigation via go_router (ADR 0004).
class PlayzyApp extends StatelessWidget {
  const PlayzyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Playzy',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
    );
  }
}
