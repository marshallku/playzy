import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../design/theme.dart';
import '../../design/widgets/primary_button.dart';
import '../../domain/situation.dart';
import '../../domain/story.dart';

/// Pick tonight's situations. M1 renders the bundled default catalog natively;
/// M2 swaps this body for the SDUI renderer fed by the backend (ADR 0003).
class SituationPickerScreen extends ConsumerStatefulWidget {
  const SituationPickerScreen({super.key});

  @override
  ConsumerState<SituationPickerScreen> createState() => _SituationPickerScreenState();
}

class _SituationPickerScreenState extends ConsumerState<SituationPickerScreen> {
  final Set<String> _selected = {};

  void _toggle(Situation s) {
    setState(() {
      if (_selected.contains(s.id)) {
        _selected.remove(s.id);
      } else if (_selected.length < AppConstants.maxSituationsPerStory) {
        _selected.add(s.id);
      }
    });
  }

  void _generate() {
    final profile = ref.read(profileControllerProvider).valueOrNull;
    if (profile == null) {
      context.go(Routes.profile);
      return;
    }
    if (!ref.read(canGenerateProvider)) {
      context.push(Routes.paywall);
      return;
    }
    final request = StoryRequest(
      childName: profile.name,
      ageBand: profile.ageBand.name,
      situationIds: _selected.toList(),
      interests: profile.interests,
      companionName: profile.companionName,
    );
    context.push(Routes.generating, extra: request);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final parenting = kDefaultSituations.where((s) => s.kind == SituationKind.parenting);
    final themes = kDefaultSituations.where((s) => s.kind == SituationKind.theme);

    return Scaffold(
      appBar: AppBar(title: const Text('오늘의 이야기')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.screenEdge),
                children: [
                  const _SectionTitle('요즘 이런 상황이 있나요?'),
                  _Chips(situations: parenting, selected: _selected, onToggle: _toggle),
                  const SizedBox(height: AppSpacing.xxl),
                  const _SectionTitle('어떤 모험을 떠날까요?'),
                  _Chips(situations: themes, selected: _selected, onToggle: _toggle),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.screenEdge),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '최대 ${AppConstants.maxSituationsPerStory}개까지 골라 주세요',
                    style: AppTypography.caption.copyWith(color: colors.textTertiary),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  PrimaryButton(
                    label: '동화 만들기',
                    onPressed: _selected.isEmpty ? null : _generate,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Text(text, style: AppTypography.h2.copyWith(color: context.colors.textPrimary)),
    );
  }
}

class _Chips extends StatelessWidget {
  const _Chips({required this.situations, required this.selected, required this.onToggle});

  final Iterable<Situation> situations;
  final Set<String> selected;
  final void Function(Situation) onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final s in situations)
          FilterChip(
            label: Text('${s.emoji ?? ''} ${s.label}'.trim()),
            selected: selected.contains(s.id),
            onSelected: (_) => onToggle(s),
          ),
      ],
    );
  }
}
