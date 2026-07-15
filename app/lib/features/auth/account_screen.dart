import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth_controller.dart';
import '../../core/router.dart';
import '../../data/auth/auth_api.dart';
import '../../design/theme.dart';
import '../../design/widgets/primary_button.dart';

/// Account screen (WU5): the entry to sign out / delete an account. Signed-out shows a
/// login CTA. It never renders the opaque account id — that's meaningless to a user and
/// only a privacy surface. Destructive actions confirm first and surface failures.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String failLabel) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } catch (e) {
      messenger
          .showSnackBar(SnackBar(content: Text('$failLabel: ${_message(e)}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('계정을 삭제할까요?'),
        content: const Text('계정과 저장된 아이 정보·이용권이 모두 삭제돼요. 되돌릴 수 없어요.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('취소')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('삭제')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => ref.read(authControllerProvider.notifier).deleteAccount(),
      '계정 삭제에 실패했어요',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final signedIn = ref.watch(authControllerProvider).isSignedIn;
    return Scaffold(
      appBar: AppBar(title: const Text('계정')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenEdge),
          child: signedIn ? _signedIn(colors) : _signedOut(colors),
        ),
      ),
    );
  }

  Widget _signedIn(AppColors colors) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.xl),
          Text('로그인되어 있어요',
              style: AppTypography.h2.copyWith(color: colors.textPrimary)),
          const SizedBox(height: AppSpacing.sm),
          Text('아이 정보와 이용권이 이 계정에 동기화돼요.',
              style: AppTypography.body.copyWith(color: colors.textSecondary)),
          const Spacer(),
          if (_busy)
            Center(child: CircularProgressIndicator(color: colors.primary))
          else ...[
            OutlinedButton(
              onPressed: () => _run(
                () => ref.read(authControllerProvider.notifier).signOut(),
                '로그아웃에 실패했어요',
              ),
              child: const Text('로그아웃'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextButton(
              onPressed: _confirmDelete,
              child: Text('계정 삭제', style: TextStyle(color: colors.error)),
            ),
          ],
          const SizedBox(height: AppSpacing.xxl),
        ],
      );

  Widget _signedOut(AppColors colors) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Text('로그인하고 여러 기기에서\n동화를 이어보세요',
              style: AppTypography.h2.copyWith(color: colors.textPrimary)),
          const SizedBox(height: AppSpacing.sm),
          Text('로그인 없이도 무료 동화는 계속 만들 수 있어요.',
              style: AppTypography.body.copyWith(color: colors.textSecondary)),
          const Spacer(),
          PrimaryButton(
            label: '로그인',
            onPressed: () => context.push(Routes.login),
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      );

  String _message(Object e) =>
      e is AuthException ? e.message : '잠시 후 다시 시도해 주세요';
}
