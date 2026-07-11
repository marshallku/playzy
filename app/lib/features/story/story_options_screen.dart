import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../design/theme.dart';
import '../../design/widgets/primary_button.dart';
import '../../domain/story.dart';
import '../../domain/story_options.dart';

/// Shape tonight's story: who's in it (등장인물), the mood, how long, and where
/// (planning/40). Sits between the situation picker and generation; the profile
/// supplies the child + the enriched request is built here.
class StoryOptionsScreen extends ConsumerStatefulWidget {
  const StoryOptionsScreen({super.key, required this.situationIds});

  final List<String> situationIds;

  @override
  ConsumerState<StoryOptionsScreen> createState() => _StoryOptionsScreenState();
}

class _StoryOptionsScreenState extends ConsumerState<StoryOptionsScreen> {
  final List<_CharacterDraft> _characters = [];
  StoryMood _mood = StoryMood.cozy;
  StoryLength? _length; // null = age-appropriate default (planning/40)
  StorySetting? _setting; // null = let the AI choose

  @override
  void dispose() {
    for (final c in _characters) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canAddCharacter =>
      _characters.length < AppConstants.maxCharactersPerStory;

  void _addCharacter() {
    if (!_canAddCharacter) return;
    setState(() => _characters.add(_CharacterDraft()));
  }

  void _removeCharacter(int index) {
    setState(() => _characters.removeAt(index).dispose());
  }

  void _generate() {
    final profileState = ref.read(profileControllerProvider);
    final quotaState = ref.read(quotaStateProvider);
    // Guard against a tap before either resolves (the button is disabled until
    // then, but a race could still fire). Loading/error are NOT negative answers.
    if (profileState.isLoading ||
        profileState.hasError ||
        quotaState.isLoading ||
        quotaState.hasError) {
      return;
    }
    // Only an authoritative AsyncData(null) means "no profile" → onboarding.
    final profile = profileState.valueOrNull;
    if (profile == null) {
      context.go(Routes.profile);
      return;
    }
    // Only an authoritative canGenerate == false means the quota is used up.
    if (!(quotaState.valueOrNull?.canGenerate ?? false)) {
      context.push(Routes.paywall);
      return;
    }
    final characters = _characters
        .map(
            (d) => StoryCharacter(name: d.controller.text.trim(), kind: d.kind))
        .where((c) => c.name.isNotEmpty)
        .toList();
    final request = StoryRequest(
      childName: profile.name,
      ageBand: profile.ageBand.name,
      situationIds: widget.situationIds,
      interests: profile.interests,
      companionName: profile.companionName,
      characters: characters,
      mood: _mood,
      length: _length,
      setting: _setting,
    );
    context.push(Routes.generating, extra: request);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Build the request FROM these, so both must resolve before generate is
    // allowed. Watching also loads them here (not just on a prior screen), so a
    // direct route — or a widget test — behaves correctly. isLoading/hasError are
    // NOT treated as "no profile"/"no quota" (that would wrongly redirect/paywall).
    final profileAsync = ref.watch(profileControllerProvider);
    final quotaAsync = ref.watch(quotaStateProvider);
    final resolving = profileAsync.isLoading || quotaAsync.isLoading;
    // A load error (profile OR quota) is NOT a definitive "no profile"/"exhausted"
    // answer — disable generate and offer retry instead of misrouting.
    final loadFailed = profileAsync.hasError || quotaAsync.hasError;

    return Scaffold(
      appBar: AppBar(title: const Text('이야기 꾸미기')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.screenEdge),
                children: [
                  _header('등장인물 (선택)', colors),
                  Text(
                    '아이 외에 함께 나올 인물을 더할 수 있어요',
                    style: AppTypography.bodySm
                        .copyWith(color: colors.textTertiary),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  for (var i = 0; i < _characters.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _CharacterRow(
                        draft: _characters[i],
                        onKindChanged: (k) =>
                            setState(() => _characters[i].kind = k),
                        onRemove: () => _removeCharacter(i),
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _canAddCharacter ? _addCharacter : null,
                      icon: const Icon(Icons.add),
                      label: Text(
                        _canAddCharacter
                            ? '등장인물 추가'
                            : '최대 ${AppConstants.maxCharactersPerStory}명까지',
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  _header('분위기', colors),
                  const SizedBox(height: AppSpacing.sm),
                  DropdownButtonFormField<StoryMood>(
                    initialValue: _mood,
                    items: [
                      for (final m in StoryMood.values)
                        DropdownMenuItem(
                            value: m, child: Text('${m.label} 이야기')),
                    ],
                    onChanged: (m) =>
                        setState(() => _mood = m ?? StoryMood.cozy),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  _header('길이', colors),
                  Text(
                    '고르지 않으면 나이에 맞춰 정해요',
                    style: AppTypography.bodySm
                        .copyWith(color: colors.textTertiary),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    children: [
                      for (final l in StoryLength.values)
                        ChoiceChip(
                          label: Text(l.label),
                          selected: _length == l,
                          // Re-tapping the selected length clears it → age default.
                          onSelected: (_) =>
                              setState(() => _length = _length == l ? null : l),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  _header('장소 (선택)', colors),
                  const SizedBox(height: AppSpacing.sm),
                  DropdownButtonFormField<StorySetting?>(
                    initialValue: _setting,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('상관없어요')),
                      for (final s in StorySetting.values)
                        DropdownMenuItem(value: s, child: Text(s.label)),
                    ],
                    onChanged: (s) => setState(() => _setting = s),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.screenEdge),
              child: Column(
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
                        child: Text(
                          '정보를 불러오지 못했어요. 다시 시도',
                          style: AppTypography.bodySm.copyWith(color: colors.error),
                        ),
                      ),
                    ),
                  PrimaryButton(
                    label: '동화 만들기',
                    // Disabled until profile + quota resolve, or on a load error, so
                    // a slow/failed fetch never misroutes to onboarding/paywall.
                    onPressed: (resolving || loadFailed) ? null : _generate,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(String text, AppColors colors) =>
      Text(text, style: AppTypography.h3.copyWith(color: colors.textPrimary));
}

/// One editable character (name field + relationship). Owns its controller.
class _CharacterDraft {
  _CharacterDraft() : controller = TextEditingController();

  final TextEditingController controller;
  CharacterKind kind = CharacterKind.family;

  void dispose() => controller.dispose();
}

class _CharacterRow extends StatelessWidget {
  const _CharacterRow({
    required this.draft,
    required this.onKindChanged,
    required this.onRemove,
  });

  final _CharacterDraft draft;
  final ValueChanged<CharacterKind> onKindChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: TextField(
            controller: draft.controller,
            decoration: const InputDecoration(hintText: '이름'),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<CharacterKind>(
            initialValue: draft.kind,
            items: [
              for (final k in CharacterKind.values)
                DropdownMenuItem(value: k, child: Text(k.label)),
            ],
            onChanged: (k) => onKindChanged(k ?? CharacterKind.family),
          ),
        ),
        IconButton(
          onPressed: onRemove,
          icon: const Icon(Icons.close),
          tooltip: '삭제',
        ),
      ],
    );
  }
}
