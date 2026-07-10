import 'package:flutter/material.dart';

import '../design/theme.dart';
import 'sdui_models.dart';

/// Renders an [SduiDocument] as design-system widgets (ADR 0003 Tier A). The
/// vocabulary is fixed and small, so rendering stays on-brand and safe; unknown
/// components render as nothing (forward compatibility). Selection is owned by
/// the caller — the renderer is stateless.
class SduiRenderer extends StatelessWidget {
  const SduiRenderer({
    super.key,
    required this.document,
    required this.selected,
    required this.onToggleChip,
    required this.canSelectMore,
  });

  final SduiDocument document;
  final Set<String> selected;
  final void Function(SduiChip chip) onToggleChip;

  /// Whether another (currently unselected) chip may be selected.
  final bool canSelectMore;

  @override
  Widget build(BuildContext context) {
    // A document from a newer schema than we support falls back to nothing;
    // callers pair this with a bundled default (offline safety).
    if (document.schemaVersion > SduiDocument.supportedVersion) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: document.components.map(_component).toList(),
    );
  }

  Widget _component(SduiComponent c) {
    return switch (c) {
      SduiSection(:final title) => _SduiSectionView(title: title),
      SduiChipGroup(:final chips) => _SduiChipGroupView(
          chips: chips,
          selected: selected,
          onToggle: onToggleChip,
          canSelectMore: canSelectMore,
        ),
      SduiBanner(:final text) => _SduiBannerView(text: text),
      SduiSpacer(:final size) => SizedBox(height: _spacing(size)),
      SduiUnknown() => const SizedBox.shrink(),
    };
  }

  double _spacing(SduiSpace size) => switch (size) {
        SduiSpace.sm => AppSpacing.sm,
        SduiSpace.md => AppSpacing.md,
        SduiSpace.lg => AppSpacing.lg,
        SduiSpace.xl => AppSpacing.xl,
        SduiSpace.xxl => AppSpacing.xxl,
      };
}

class _SduiSectionView extends StatelessWidget {
  const _SduiSectionView({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md, top: AppSpacing.sm),
      child: Text(title, style: AppTypography.h2.copyWith(color: context.colors.textPrimary)),
    );
  }
}

class _SduiChipGroupView extends StatelessWidget {
  const _SduiChipGroupView({
    required this.chips,
    required this.selected,
    required this.onToggle,
    required this.canSelectMore,
  });

  final List<SduiChip> chips;
  final Set<String> selected;
  final void Function(SduiChip) onToggle;
  final bool canSelectMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final chip in chips)
            FilterChip(
              label: Text('${chip.emoji ?? ''} ${chip.label}'.trim()),
              selected: selected.contains(chip.id),
              // Disable unselected chips once the max is reached.
              onSelected: (!selected.contains(chip.id) && !canSelectMore)
                  ? null
                  : (_) => onToggle(chip),
            ),
        ],
      ),
    );
  }
}

class _SduiBannerView extends StatelessWidget {
  const _SduiBannerView({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.primarySubtle,
        borderRadius: AppRadius.card,
      ),
      child: Text(text, style: AppTypography.bodySm.copyWith(color: colors.textPrimary)),
    );
  }
}
