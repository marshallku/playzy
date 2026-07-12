import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/providers.dart';
import '../../design/theme.dart';
import '../../domain/story_options.dart';

/// Manage the reusable character roster (보관함) — saved once, picked per story
/// (request #4). Add a name + relationship; delete with a tap. Backed by
/// [rosterControllerProvider].
class RosterScreen extends ConsumerStatefulWidget {
  const RosterScreen({super.key});

  @override
  ConsumerState<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends ConsumerState<RosterScreen> {
  final _nameController = TextEditingController();
  CharacterKind _kind = CharacterKind.family;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    await ref
        .read(rosterControllerProvider.notifier)
        .add(StoryCharacter(name: name, kind: _kind));
    _nameController.clear();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final roster = ref.watch(rosterControllerProvider).valueOrNull ?? const <StoryCharacter>[];
    final full = roster.length >= AppConstants.maxRosterCharacters;

    return Scaffold(
      appBar: AppBar(title: const Text('등장인물 보관함')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.screenEdge),
                children: [
                  Text(
                    '자주 등장하는 인물을 저장해 두고, 이야기마다 골라 넣을 수 있어요',
                    style: AppTypography.bodySm.copyWith(color: colors.textTertiary),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (roster.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                      child: Text(
                        '아직 저장한 인물이 없어요',
                        textAlign: TextAlign.center,
                        style: AppTypography.body.copyWith(color: colors.textTertiary),
                      ),
                    )
                  else
                    for (final c in roster)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _RosterTile(
                          character: c,
                          onRemove: () => ref
                              .read(rosterControllerProvider.notifier)
                              .remove(c),
                        ),
                      ),
                ],
              ),
            ),
            _AddArea(
              nameController: _nameController,
              kind: _kind,
              onKindChanged: (k) => setState(() => _kind = k),
              onAdd: full ? null : _add,
              full: full,
            ),
          ],
        ),
      ),
    );
  }
}

class _RosterTile extends StatelessWidget {
  const _RosterTile({required this.character, required this.onRemove});

  final StoryCharacter character;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(color: colors.bgSurface, borderRadius: AppRadius.card),
      child: Row(
        children: [
          Flexible(
            child: Text(
              character.name,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.body.copyWith(color: colors.textPrimary),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            character.kind.label,
            style: AppTypography.caption.copyWith(color: colors.textTertiary),
          ),
          const Spacer(),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close),
            tooltip: '삭제',
          ),
        ],
      ),
    );
  }
}

/// Name field + relationship + add button. Pinned below the list.
class _AddArea extends StatelessWidget {
  const _AddArea({
    required this.nameController,
    required this.kind,
    required this.onKindChanged,
    required this.onAdd,
    required this.full,
  });

  final TextEditingController nameController;
  final CharacterKind kind;
  final ValueChanged<CharacterKind> onKindChanged;
  final VoidCallback? onAdd;
  final bool full;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.screenEdge),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (full)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                '최대 ${AppConstants.maxRosterCharacters}명까지 저장할 수 있어요',
                style: AppTypography.caption.copyWith(color: colors.textTertiary),
              ),
            ),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: nameController,
                  enabled: !full,
                  decoration: const InputDecoration(hintText: '이름'),
                  onSubmitted: (_) => onAdd?.call(),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<CharacterKind>(
                  initialValue: kind,
                  items: [
                    for (final k in CharacterKind.values)
                      DropdownMenuItem(value: k, child: Text(k.label)),
                  ],
                  onChanged: full
                      ? null
                      : (k) => onKindChanged(k ?? CharacterKind.family),
                ),
              ),
              IconButton(
                onPressed: onAdd,
                icon: const Icon(Icons.add_circle),
                color: colors.primary,
                tooltip: '추가',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
