import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router.dart';
import '../../../design/theme.dart';

/// Total steps in the create funnel — the denominator of the progress bar.
const int kFunnelSteps = 3;

/// Shared chrome for a funnel step: a progress bar + "n / N" header, an easy
/// cancel (X → Home, so a mid-funnel exit is one tap), and a pinned footer CTA.
/// Native back-swipe/back still pops to the previous step (choices persist in
/// the draft), so this only owns forward progress + cancel.
class FunnelScaffold extends ConsumerWidget {
  const FunnelScaffold({
    super.key,
    required this.step,
    required this.title,
    required this.child,
    required this.footer,
  });

  /// 1-based step index.
  final int step;
  final String title;
  final Widget child;
  final Widget footer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    return Scaffold(
      appBar: AppBar(
        // Cancel is always one tap — go (not push) Home so the whole funnel
        // stack is dropped; the next fresh entry resets the draft.
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: '그만두기',
          onPressed: () => context.go(Routes.home),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenEdge, 0, AppSpacing.screenEdge, AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: AppRadius.pillAll,
                          child: LinearProgressIndicator(
                            value: step / kFunnelSteps,
                            minHeight: AppSizes.progressTrack,
                            // bgSubtle track keeps the primary fill ≥3:1 in
                            // BOTH modes (bgAlt is too light at night, 2.74:1).
                            backgroundColor: colors.bgSubtle,
                            color: colors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Text('$step / $kFunnelSteps',
                          style: AppTypography.caption
                              .copyWith(color: colors.textTertiary)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(title,
                      style: AppTypography.h2.copyWith(color: colors.textPrimary)),
                ],
              ),
            ),
            Expanded(child: child),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.screenEdge),
              child: footer,
            ),
          ],
        ),
      ),
    );
  }
}
