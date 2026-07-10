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
  final _nameController = TextEditingController();
  final _companionController = TextEditingController();
  AgeBand _ageBand = AgeBand.toddler;
  final Set<String> _interests = {};
  bool _hydrated = false;

  @override
  void dispose() {
    _nameController.dispose();
    _companionController.dispose();
    super.dispose();
  }

  void _hydrate(ChildProfile profile) {
    if (_hydrated) return;
    _hydrated = true;
    _nameController.text = profile.name;
    _companionController.text = profile.companionName ?? '';
    _ageBand = profile.ageBand;
    _interests.addAll(profile.interests);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final existing = ref.read(profileControllerProvider).valueOrNull;
    final companion = _companionController.text.trim();
    final profile = ChildProfile(
      id: existing?.id ?? 'child-1',
      name: _nameController.text.trim(),
      ageBand: _ageBand,
      interests: _interests.toList(),
      companionName: companion.isEmpty ? null : companion,
    );
    try {
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
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(hintText: '아이 이름'),
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '이름을 입력해 주세요' : null,
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
              const SizedBox(height: AppSpacing.xxl),
              Text('함께하는 친구 (선택)',
                  style: AppTypography.h3.copyWith(color: colors.textPrimary)),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _companionController,
                decoration: const InputDecoration(hintText: '예: 누나, 강아지 콩이'),
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
