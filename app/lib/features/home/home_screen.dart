import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router.dart';
import '../../design/theme.dart';
import '../../design/widgets/primary_button.dart';
import '../../domain/child_profile.dart';
import '../../domain/quota_state.dart';
import '../../domain/story.dart';
import '../create/story_draft.dart';

/// Landing: greet the parent, surface tonight's allowance, offer the generate
/// CTA, and shelf past stories to re-read (planning/40).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileControllerProvider);
    // Backend-authoritative or local mirror; null while loading/errored so we
    // never synthesize an allowance that isn't real.
    final quota = ref.watch(quotaStateProvider).valueOrNull;
    // Recent tales, most-recent-first (empty while loading or if none saved).
    final recent = ref.watch(recentStoriesProvider).valueOrNull ?? const <Story>[];

    return Scaffold(
      body: SafeArea(
        child: profile.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _CenteredMessage('문제가 생겼어요: $e', isError: true),
          data: (child) => ListView(
            padding: const EdgeInsets.all(AppSpacing.screenEdge),
            children: [
              const SizedBox(height: AppSpacing.xxl),
              _Greeting(child: child),
              const SizedBox(height: AppSpacing.xxl),
              if (quota != null) ...[
                _QuotaCard(quota: quota),
                const SizedBox(height: AppSpacing.lg),
              ],
              PrimaryButton(
                label: child != null ? '오늘의 동화 만들기' : '아이 정보 입력하고 시작하기',
                onPressed: () {
                  if (child == null) {
                    context.push(Routes.profile);
                    return;
                  }
                  // The ONE reset point (fresh entry): start every story from a
                  // clean draft, so a prior run's choices never leak in (C5).
                  ref.read(storyDraftProvider.notifier).reset();
                  context.push(Routes.createTopic);
                },
              ),
              if (child != null)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => context.push(Routes.profile),
                      child: const Text('아이 정보 수정'),
                    ),
                    TextButton(
                      onPressed: () => context.push(Routes.roster),
                      child: const Text('등장인물 보관함'),
                    ),
                  ],
                ),
              if (child != null && recent.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.x4l),
                _RecentStories(stories: recent),
              ],
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.child});

  final ChildProfile? child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final child = this.child; // local so the null-check smart-casts below
    if (child == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Playzy', style: AppTypography.brand.copyWith(color: colors.primary)),
          const SizedBox(height: AppSpacing.sm),
          Text('아이를 위한 오늘 밤의 동화',
              style: AppTypography.body.copyWith(color: colors.textSecondary)),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${child.givenName}의 밤',
            style: AppTypography.display.copyWith(color: colors.primary)),
        const SizedBox(height: AppSpacing.sm),
        Text('오늘은 어떤 이야기를 들려줄까요?',
            style: AppTypography.body.copyWith(color: colors.textSecondary)),
      ],
    );
  }
}

/// Tonight's allowance as a card (free tier or purchased credits).
class _QuotaCard extends StatelessWidget {
  const _QuotaCard({required this.quota});

  final QuotaState quota;

  String get _label => quota.credits > 0
      ? '이용권 ${quota.credits}편 남았어요'
      : '무료 동화 ${quota.freeRemaining}편 남았어요';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.primarySubtle,
        borderRadius: AppRadius.card,
      ),
      child: Row(
        children: [
          const Text('🌙', style: AppTypography.h2),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_label,
                    style: AppTypography.h3.copyWith(color: colors.textPrimary)),
                const SizedBox(height: AppSpacing.xs),
                Text('잠들기 전 포근한 이야기 한 편',
                    style: AppTypography.caption.copyWith(color: colors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shelf of past stories to re-read. Hidden by the caller when empty.
class _RecentStories extends StatelessWidget {
  const _RecentStories({required this.stories});

  final List<Story> stories;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('지난 이야기',
            style: AppTypography.h3.copyWith(color: colors.textPrimary)),
        const SizedBox(height: AppSpacing.md),
        for (final story in stories)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _StoryCard(story: story),
          ),
      ],
    );
  }
}

class _StoryCard extends StatelessWidget {
  const _StoryCard({required this.story});

  final Story story;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final preview = story.pages.isNotEmpty ? story.pages.first.text : '';
    return Material(
      color: colors.bgSurface,
      borderRadius: AppRadius.card,
      child: InkWell(
        borderRadius: AppRadius.card,
        onTap: () => context.push(Routes.story, extra: story),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              const Text('📖', style: AppTypography.h3),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(story.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.body.copyWith(color: colors.textPrimary)),
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption.copyWith(color: colors.textSecondary)),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage(this.text, {this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenEdge),
        child: Text(text,
            textAlign: TextAlign.center,
            style: AppTypography.body
                .copyWith(color: isError ? colors.error : colors.textSecondary)),
      ),
    );
  }
}
