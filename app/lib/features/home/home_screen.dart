import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../design/theme.dart';
import '../../design/widgets/primary_button.dart';

/// Landing: greet the parent, show free-tier status, route to setup or story.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final profile = ref.watch(profileControllerProvider);
    final count = ref.watch(generatedCountProvider).valueOrNull ?? 0;
    final hasPro = (ref.watch(entitlementsProvider).valueOrNull ?? const {})
        .contains(AppConstants.proEntitlement);
    final remaining = (AppConstants.freeStoryLimit - count).clamp(0, AppConstants.freeStoryLimit);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenEdge),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Text('Playzy', style: AppTypography.display.copyWith(color: colors.primary)),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '아이를 위한 오늘 밤의 동화',
                style: AppTypography.body.copyWith(color: colors.textSecondary),
              ),
              const Spacer(),
              profile.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('문제가 생겼어요: $e',
                    style: AppTypography.body.copyWith(color: colors.error)),
                data: (child) =>
                    _Cta(hasProfile: child != null, hasPro: hasPro, remaining: remaining),
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}

class _Cta extends StatelessWidget {
  const _Cta({required this.hasProfile, required this.hasPro, required this.remaining});

  final bool hasProfile;
  final bool hasPro;
  final int remaining;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!hasPro)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(
              '무료 동화 $remaining편 남았어요',
              style: AppTypography.bodySm.copyWith(color: colors.textSecondary),
            ),
          ),
        PrimaryButton(
          label: hasProfile ? '오늘의 동화 만들기' : '아이 정보 입력하고 시작하기',
          onPressed: () =>
              context.push(hasProfile ? Routes.pick : Routes.profile),
        ),
        if (hasProfile)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: TextButton(
              onPressed: () => context.push(Routes.profile),
              child: const Text('아이 정보 수정'),
            ),
          ),
      ],
    );
  }
}
