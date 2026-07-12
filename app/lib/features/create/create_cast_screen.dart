import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../design/theme.dart';
import '../../design/widgets/primary_button.dart';
import '../../domain/story_options.dart';
import 'story_draft.dart';
import 'widgets/funnel_scaffold.dart';

/// Step 2/3 — who's in the story. Pick from the reusable roster (보관함, request
/// #4); a new person can be added inline (saved to the roster AND selected).
/// Optional — a story can star just the child. At most
/// [AppConstants.maxCharactersPerStory] ride along per story.
class CreateCastScreen extends ConsumerWidget {
  const CreateCastScreen({super.key});

  Future<void> _addNew(BuildContext context, WidgetRef ref) async {
    final character = await showDialog<StoryCharacter>(
      context: context,
      builder: (_) => const _AddCharacterDialog(),
    );
    if (character == null) return;
    // Save to the roster for reuse, then select it for tonight (respecting the
    // per-story cap).
    await ref.read(rosterControllerProvider.notifier).add(character);
    ref
        .read(storyDraftProvider.notifier)
        .toggleCast(character, max: AppConstants.maxCharactersPerStory);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final draft = ref.watch(storyDraftProvider);
    final roster =
        ref.watch(rosterControllerProvider).valueOrNull ?? const <StoryCharacter>[];
    final atCap = draft.cast.length >= AppConstants.maxCharactersPerStory;
    final rosterFull = roster.length >= AppConstants.maxRosterCharacters;
    // "새 인물 추가" promises save AND select — only offer it when both can happen
    // (roster has room to save, story has room to select) — codex WU4 C2.
    final canAddNew = !atCap && !rosterFull;

    return FunnelScaffold(
      step: 2,
      title: '함께할 친구를 골라요',
      footer: PrimaryButton(
        label: '다음',
        onPressed: () => context.push(Routes.createTone),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenEdge),
        children: [
          Text(
            atCap
                ? '한 이야기에는 최대 ${AppConstants.maxCharactersPerStory}명까지 함께해요'
                : '보관함에서 고르거나, 새 인물을 더할 수 있어요 (선택)',
            style: AppTypography.bodySm.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (roster.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Text('아직 저장한 인물이 없어요. 새 인물을 더해 보세요',
                  style: AppTypography.body.copyWith(color: colors.textTertiary)),
            )
          else
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final c in roster)
                  FilterChip(
                    label: Text('${c.name} · ${c.kind.label}'),
                    selected: draft.isCast(c),
                    // Once at the per-story cap, unselected chips are disabled.
                    onSelected: (!draft.isCast(c) && atCap)
                        ? null
                        : (_) => ref.read(storyDraftProvider.notifier).toggleCast(
                            c,
                            max: AppConstants.maxCharactersPerStory),
                  ),
              ],
            ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: canAddNew ? () => _addNew(context, ref) : null,
              icon: const Icon(Icons.add),
              label: Text(rosterFull && !atCap ? '보관함이 가득 찼어요' : '새 인물 추가'),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => context.push(Routes.roster),
              child: const Text('보관함 관리'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddCharacterDialog extends StatefulWidget {
  const _AddCharacterDialog();

  @override
  State<_AddCharacterDialog> createState() => _AddCharacterDialogState();
}

class _AddCharacterDialogState extends State<_AddCharacterDialog> {
  final _controller = TextEditingController();
  CharacterKind _kind = CharacterKind.family;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(StoryCharacter(name: name, kind: _kind));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('새 인물'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: '이름'),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<CharacterKind>(
            initialValue: _kind,
            items: [
              for (final k in CharacterKind.values)
                DropdownMenuItem(value: k, child: Text(k.label)),
            ],
            onChanged: (k) => setState(() => _kind = k ?? CharacterKind.family),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton(onPressed: _submit, child: const Text('추가')),
      ],
    );
  }
}
