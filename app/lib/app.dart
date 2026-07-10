import 'package:flutter/material.dart';

import 'design/theme.dart';

/// Root app. Theme follows the system with night as a first-class mode
/// (DESIGN.md §10). Routing is added in the routing work-unit (ADR 0004).
class PlayzyApp extends StatelessWidget {
  const PlayzyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Playzy',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: const _Placeholder(),
    );
  }
}

/// Temporary landing surface until the onboarding/home work-unit lands.
class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenEdge),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Playzy', style: AppTypography.display.copyWith(color: colors.primary)),
              const SizedBox(height: AppSpacing.md),
              Text(
                '아이를 위한 오늘 밤의 동화',
                style: AppTypography.body.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
