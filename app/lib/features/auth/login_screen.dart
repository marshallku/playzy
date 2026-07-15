import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth_controller.dart';
import '../../data/auth/auth_api.dart';
import '../../data/auth/social_sign_in.dart';
import '../../design/theme.dart';

/// Sign-in screen (WU5). Three provider buttons drive the already-tested
/// [AuthController]; the native credential fetch lives behind [socialSignInProvider]
/// (wired per-provider in WU5b). A sign-in that isn't yet wired surfaces as a visible
/// error here rather than a silent no-op.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  // One in-flight sign-in at a time: disables every button so a second provider
  // can't be tapped mid-flow (the controller also serializes, but the UI shouldn't
  // invite it).
  bool _busy = false;

  Future<void> _signIn(AuthProviderKind kind) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authControllerProvider.notifier).signIn(kind);
      if (!mounted) return;
      Navigator.of(context).maybePop();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('로그인에 실패했어요: ${_message(e)}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('로그인')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenEdge),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Text('여러 기기에서 동화를 이어보려면\n로그인해 주세요',
                  style: AppTypography.h2.copyWith(color: colors.textPrimary)),
              const SizedBox(height: AppSpacing.sm),
              Text('아이 정보와 이용권이 계정에 안전하게 저장돼요.',
                  style:
                      AppTypography.body.copyWith(color: colors.textSecondary)),
              const SizedBox(height: AppSpacing.x4l),
              _ProviderButton(
                label: 'Apple로 계속하기',
                onPressed: _busy ? null : () => _signIn(AuthProviderKind.apple),
              ),
              const SizedBox(height: AppSpacing.md),
              _ProviderButton(
                label: 'Google로 계속하기',
                onPressed:
                    _busy ? null : () => _signIn(AuthProviderKind.google),
              ),
              const SizedBox(height: AppSpacing.md),
              _ProviderButton(
                label: '카카오로 계속하기',
                onPressed: _busy ? null : () => _signIn(AuthProviderKind.kakao),
              ),
              const SizedBox(height: AppSpacing.xl),
              if (_busy)
                Center(child: CircularProgressIndicator(color: colors.primary)),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  String _message(Object e) =>
      e is AuthException ? e.message : '잠시 후 다시 시도해 주세요';
}

/// A full-width outlined provider button. Deliberately provider-neutral styling for
/// the v1 shell; brand marks/colors land with the real SDK integration (WU5b).
class _ProviderButton extends StatelessWidget {
  const _ProviderButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        child: Text(label,
            style: AppTypography.body.copyWith(color: colors.textPrimary)),
      ),
    );
  }
}
