import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router.dart';
import '../../data/story/story_api.dart';
import '../../design/theme.dart';
import '../../design/widgets/primary_button.dart';
import '../../domain/story.dart';

/// The "story is being written" moment. A gentle Lottie/Rive animation belongs
/// here (DESIGN.md §7 — flagged as a designer asset); M1 uses a calm indicator.
class GeneratingScreen extends ConsumerStatefulWidget {
  const GeneratingScreen({super.key, required this.request});

  final StoryRequest request;

  @override
  ConsumerState<GeneratingScreen> createState() => _GeneratingScreenState();
}

class _GeneratingScreenState extends ConsumerState<GeneratingScreen> {
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _generate());
  }

  Future<void> _generate() async {
    setState(() => _error = null);
    try {
      final story = await ref.read(storyControllerProvider.notifier).generate(widget.request);
      if (mounted) context.pushReplacement(Routes.story, extra: story);
    } on QuotaExceededException {
      // Quota hit (e.g. a race past the picker's check) → send to the paywall.
      if (mounted) context.pushReplacement(Routes.paywall);
    } on StoryApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.screenEdge),
            child: _error == null ? _loading(colors) : _errorView(colors),
          ),
        ),
      ),
    );
  }

  Widget _loading(AppColors colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(color: colors.primary),
        const SizedBox(height: AppSpacing.xxl),
        Text(
          '${widget.request.childName}만의 동화를 짓고 있어요...',
          textAlign: TextAlign.center,
          style: AppTypography.h3.copyWith(color: colors.textPrimary),
        ),
      ],
    );
  }

  Widget _errorView(AppColors colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('동화를 만들지 못했어요',
            style: AppTypography.h3.copyWith(color: colors.textPrimary)),
        const SizedBox(height: AppSpacing.sm),
        Text('$_error',
            textAlign: TextAlign.center,
            style: AppTypography.bodySm.copyWith(color: colors.textSecondary)),
        const SizedBox(height: AppSpacing.xxl),
        PrimaryButton(label: '다시 시도', onPressed: _generate),
        TextButton(onPressed: () => context.pop(), child: const Text('돌아가기')),
      ],
    );
  }
}
