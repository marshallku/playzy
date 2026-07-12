import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../design/theme.dart';
import '../../design/widgets/primary_button.dart';
import '../../sdui/sdui_renderer.dart';
import 'story_draft.dart';
import 'widgets/funnel_scaffold.dart';

/// Step 1/3 — what tonight's story is about. A free-text seed (오늘의 이야기) AND
/// the situation/theme chips (kept, not replaced — Q1). Either one is enough to
/// continue; both enrich the story.
class CreateTopicScreen extends ConsumerStatefulWidget {
  const CreateTopicScreen({super.key});

  @override
  ConsumerState<CreateTopicScreen> createState() => _CreateTopicScreenState();
}

class _CreateTopicScreenState extends ConsumerState<CreateTopicScreen> {
  late final TextEditingController _topicController;

  @override
  void initState() {
    super.initState();
    // Seed from the draft so returning to this step (back-swipe) restores text.
    _topicController = TextEditingController(text: ref.read(storyDraftProvider).topic);
  }

  @override
  void dispose() {
    _topicController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final draft = ref.watch(storyDraftProvider);
    final catalog = ref.watch(situationCatalogProvider);
    final canSelectMore =
        draft.situationIds.length < AppConstants.maxSituationsPerStory;

    return FunnelScaffold(
      step: 1,
      title: '오늘은 어떤 이야기를 들려줄까요?',
      footer: PrimaryButton(
        label: '다음',
        onPressed: draft.hasSubject
            ? () => context.push(Routes.createCast)
            : null,
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenEdge),
        children: [
          TextField(
            controller: _topicController,
            minLines: 2,
            maxLines: 3,
            maxLength: 100,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              hintText: '예: 오늘 어린이집에서 친구랑 다퉜어요',
              alignLabelWithHint: true,
            ),
            onChanged: (v) => ref.read(storyDraftProvider.notifier).setTopic(v),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('원하는 소재를 자유롭게 적거나, 아래에서 골라도 돼요',
              style: AppTypography.bodySm.copyWith(color: colors.textTertiary)),
          const SizedBox(height: AppSpacing.xl),
          catalog.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('목록을 불러오지 못했어요',
                style: AppTypography.body.copyWith(color: colors.error)),
            data: (document) => SduiRenderer(
              document: document,
              selected: draft.situationIds,
              canSelectMore: canSelectMore,
              onToggleChip: (chip) => ref
                  .read(storyDraftProvider.notifier)
                  .toggleSituation(chip.id,
                      max: AppConstants.maxSituationsPerStory),
            ),
          ),
        ],
      ),
    );
  }
}
