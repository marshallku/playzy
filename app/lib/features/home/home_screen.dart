import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router.dart';
import '../../design/theme.dart';
import '../../design/widgets/primary_button.dart';
import '../../domain/quota_state.dart';

/// Landing: greet the parent, show free-tier status, route to setup or story.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final profile = ref.watch(profileControllerProvider);
    // Single source of allowance — backend-authoritative or local mirror. Null
    // while loading/errored so we never synthesize a "3 free" that isn't real.
    final quota = ref.watch(quotaStateProvider).valueOrNull;

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
                data: (child) => _Cta(hasProfile: child != null, quota: quota),
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
  const _Cta({required this.hasProfile, required this.quota});

  final bool hasProfile;
  final QuotaState? quota; // null while the allowance is loading/unavailable

  /// Null while quota is unknown — we show nothing rather than a fake count.
  String? get _allowanceLabel {
    final q = quota;
    if (q == null) return null;
    if (q.credits > 0) return '이용권 ${q.credits}편 남았어요';
    return '무료 동화 ${q.freeRemaining}편 남았어요';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = _allowanceLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(
              label,
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
