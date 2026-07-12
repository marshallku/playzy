import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../design/theme.dart';
import '../../design/widgets/primary_button.dart';
import '../../domain/child_profile.dart';

/// A small preset so setup is a few taps, not free typing (bedtime, one-handed).
const _presetInterests = ['공룡', '자동차', '동물', '공주', '로봇', '우주', '바다', '그림'];

/// Child profile setup/edit. Fields kept minimal (docs/planning/10).
class ChildProfileScreen extends ConsumerStatefulWidget {
  const ChildProfileScreen({super.key});

  @override
  ConsumerState<ChildProfileScreen> createState() => _ChildProfileScreenState();
}

class _ChildProfileScreenState extends ConsumerState<ChildProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _familyNameController = TextEditingController();
  final _givenNameController = TextEditingController();
  AgeBand _ageBand = AgeBand.toddler;
  final Set<String> _interests = {};
  bool _hydrated = false;

  @override
  void dispose() {
    _familyNameController.dispose();
    _givenNameController.dispose();
    super.dispose();
  }

  void _hydrate(ChildProfile profile) {
    if (_hydrated) return;
    _hydrated = true;
    _familyNameController.text = profile.familyName ?? '';
    _givenNameController.text = profile.givenName;
    _ageBand = profile.ageBand;
    _interests.addAll(profile.interests);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final family = _familyNameController.text.trim();
    try {
      // Await the AUTHORITATIVE existing profile (not valueOrNull) so a save
      // fired before load completes can't drop the legacy companionName the
      // roster still needs to migrate (codex C2/C1).
      final existing = await ref.read(profileControllerProvider.future);
      final profile = ChildProfile(
        id: existing?.id ?? 'child-1',
        givenName: _givenNameController.text.trim(),
        familyName: family.isEmpty ? null : family,
        ageBand: _ageBand,
        interests: _interests.toList(),
        // Preserve the legacy companion so the roster migration can still read it
        // (it's no longer edited here — it lives in the character roster now).
        companionName: existing?.companionName,
      );
      await ref.read(profileControllerProvider.notifier).save(profile);
      if (mounted && context.canPop()) context.pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('저장하지 못했어요. 다시 시도해 주세요.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // watch (not read) so the form hydrates once the profile finishes loading —
    // opening /profile before load must not overwrite an existing child.
    ref.watch(profileControllerProvider).whenData((p) {
      if (p != null) _hydrate(p);
    });

    return Scaffold(
      appBar: AppBar(title: const Text('아이 정보')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.screenEdge),
            children: [
              Text('이름', style: AppTypography.h3.copyWith(color: colors.textPrimary)),
              const SizedBox(height: AppSpacing.xs),
              Text('이야기에는 이름만 다정하게 불러요',
                  style: AppTypography.bodySm.copyWith(color: colors.textTertiary)),
              const SizedBox(height: AppSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _familyNameController,
                      decoration: const InputDecoration(
                          labelText: '성 (선택)', hintText: '예: 김'),
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _givenNameController,
                      decoration: const InputDecoration(
                          labelText: '이름', hintText: '예: 하준'),
                      textInputAction: TextInputAction.next,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? '이름을 입력해 주세요' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxl),
              Text('나이', style: AppTypography.h3.copyWith(color: colors.textPrimary)),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  for (final band in AgeBand.values)
                    ChoiceChip(
                      label: Text(band.label),
                      selected: _ageBand == band,
                      onSelected: (_) => setState(() => _ageBand = band),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxl),
              Text('좋아하는 것', style: AppTypography.h3.copyWith(color: colors.textPrimary)),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final interest in _presetInterests)
                    FilterChip(
                      label: Text(interest),
                      selected: _interests.contains(interest),
                      onSelected: (on) => setState(() {
                        on ? _interests.add(interest) : _interests.remove(interest);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.x4l),
              PrimaryButton(label: '저장하기', onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}
