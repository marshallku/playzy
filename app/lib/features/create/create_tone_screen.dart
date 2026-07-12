import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router.dart';
import '../../design/theme.dart';
import '../../design/widgets/primary_button.dart';
import '../../domain/story.dart';
import '../../domain/story_options.dart';
import 'story_draft.dart';
import 'widgets/funnel_scaffold.dart';

/// Step 3/3 — the finishing touches: mood + length (no place — request #3). The
/// "동화 만들기" CTA builds the request from the draft + profile and starts
/// generation. Keeps the profile/quota resolving + retry guard (I6): a slow or
/// failed load never misroutes to onboarding/paywall.
class CreateToneScreen extends ConsumerWidget {
  const CreateToneScreen({super.key});

  void _generate(BuildContext context, WidgetRef ref) {
    final profileState = ref.read(profileControllerProvider);
    final quotaState = ref.read(quotaStateProvider);
    // Loading/error are NOT negative answers — bail (the button is disabled then,
    // but guard the race too).
    if (profileState.isLoading ||
        profileState.hasError ||
        quotaState.isLoading ||
        quotaState.hasError) {
      return;
    }
    final profile = profileState.valueOrNull;
    if (profile == null) {
      context.go(Routes.profile);
      return;
    }
    if (!(quotaState.valueOrNull?.canGenerate ?? false)) {
      context.push(Routes.paywall);
      return;
    }

    final draft = ref.read(storyDraftProvider);
    final topic = draft.topic.trim();
    final request = StoryRequest(
      childName: profile.givenName,
      ageBand: profile.ageBand.name,
      situationIds: draft.situationIds.toList(),
      topic: topic.isEmpty ? null : topic,
      interests: profile.interests,
      // Cast comes from the roster now — the legacy companionName is not re-sent.
      characters: draft.cast,
      mood: draft.mood,
      length: draft.length,
    );
    // Do NOT reset the draft here — a failed generation should keep the choices
    // (the draft resets on the next fresh Home entry, I7).
    context.push(Routes.generating, extra: request);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final draft = ref.watch(storyDraftProvider);
    final profileAsync = ref.watch(profileControllerProvider);
    final quotaAsync = ref.watch(quotaStateProvider);
    final resolving = profileAsync.isLoading || quotaAsync.isLoading;
    final loadFailed = profileAsync.hasError || quotaAsync.hasError;

    return FunnelScaffold(
      step: 3,
      title: '어떤 분위기로 들려줄까요?',
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loadFailed)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: TextButton(
                onPressed: () {
                  ref.invalidate(profileControllerProvider);
                  ref.invalidate(quotaStateProvider);
                },
                child: Text('정보를 불러오지 못했어요. 다시 시도',
                    style: AppTypography.bodySm.copyWith(color: colors.error)),
              ),
            ),
          PrimaryButton(
            label: '동화 만들기',
            onPressed:
                (resolving || loadFailed) ? null : () => _generate(context, ref),
          ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenEdge),
        children: [
          Text('분위기',
              style: AppTypography.h3.copyWith(color: colors.textPrimary)),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<StoryMood>(
            initialValue: draft.mood,
            items: [
              for (final m in StoryMood.values)
                DropdownMenuItem(value: m, child: Text('${m.label} 이야기')),
            ],
            onChanged: (m) =>
                ref.read(storyDraftProvider.notifier).setMood(m ?? StoryMood.cozy),
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text('길이', style: AppTypography.h3.copyWith(color: colors.textPrimary)),
          Text('고르지 않으면 나이에 맞춰 정해요',
              style: AppTypography.bodySm.copyWith(color: colors.textTertiary)),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final l in StoryLength.values)
                ChoiceChip(
                  label: Text(l.label),
                  selected: draft.length == l,
                  // Re-tapping the selected length clears it → age default.
                  onSelected: (_) =>
                      ref.read(storyDraftProvider.notifier).setLength(l),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
