import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../design/theme.dart';
import '../../design/widgets/primary_button.dart';
import '../../domain/story.dart';
import '../../sdui/sdui_models.dart';
import '../../sdui/sdui_renderer.dart';

/// Pick tonight's situations. The catalog is rendered from a Server-Driven UI
/// document (ADR 0003) so it can grow without an app release; the provider
/// falls back to a bundled default offline.
class SituationPickerScreen extends ConsumerStatefulWidget {
  const SituationPickerScreen({super.key});

  @override
  ConsumerState<SituationPickerScreen> createState() => _SituationPickerScreenState();
}

class _SituationPickerScreenState extends ConsumerState<SituationPickerScreen> {
  final Set<String> _selected = {};

  void _toggle(SduiChip chip) {
    setState(() {
      if (_selected.contains(chip.id)) {
        _selected.remove(chip.id);
      } else if (_selected.length < AppConstants.maxSituationsPerStory) {
        _selected.add(chip.id);
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
    final catalog = ref.watch(situationCatalogProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('오늘의 이야기')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: catalog.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                // The provider already falls back to the bundled catalog, so an
                // error here is unexpected; show it rather than a blank screen.
                error: (e, _) => Center(
                  child: Text('목록을 불러오지 못했어요',
                      style: AppTypography.body.copyWith(color: colors.error)),
                ),
                data: (document) => SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.screenEdge),
                  child: SduiRenderer(
                    document: document,
                    selected: _selected,
                    onToggleChip: _toggle,
                    canSelectMore: _selected.length < AppConstants.maxSituationsPerStory,
                  ),
                ),
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
