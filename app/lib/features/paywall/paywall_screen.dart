import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/env.dart';
import '../../core/providers.dart';
import '../../data/payment/payment_gateway.dart';
import '../../design/theme.dart';
import '../../design/widgets/primary_button.dart';

/// Paywall. M1 is a native stub against [FakePaymentGateway]. In production the
/// presentation moves to a WebView experiment surface (ADR 0003 Tier B) while
/// the transaction stays native IAP (ADR 0002). Entitlement is read from the
/// backend, never trusted from a client callback.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  bool _busy = false;

  Future<void> _buy(
    Future<PurchaseResult> Function(PaymentGateway) action, {
    int grantCredits = 0,
  }) async {
    setState(() => _busy = true);
    try {
      final gateway = ref.read(paymentGatewayProvider);
      final result = await action(gateway);
      if (result.success && grantCredits > 0) {
        final applied = await _grantCredits(grantCredits);
        if (!applied) {
          // Backend mode with no dev/webhook path — don't pretend it worked.
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('이 빌드에서는 결제가 아직 준비되지 않았어요.')),
            );
          }
          return;
        }
      }
      if (mounted && result.success && context.canPop()) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('결제를 완료하지 못했어요. 다시 시도해 주세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Grants purchased credits where the quota actually lives. Returns whether
  /// credits were actually applied:
  /// - backend mode → the server (dev admin path), then refresh. Returns false
  ///   when no dev token is set (real builds grant via a verified webhook).
  /// - offline mode → the local credit mirror (always applied).
  Future<bool> _grantCredits(int amount) async {
    final quotaApi = ref.read(quotaApiProvider);
    if (quotaApi != null) {
      if (!Env.hasDevAdminToken) return false;
      await quotaApi.grantCreditsDev(amount, Env.devAdminToken);
      ref.invalidate(quotaStateProvider);
      return true;
    }
    await ref.read(creditsProvider.notifier).add(amount);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('무료 동화를 다 읽었어요')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenEdge),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Text(
                '아이만을 위한\n새로운 동화를 이어가요',
                style: AppTypography.h1.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                '무료 ${AppConstants.freeStoryLimit}편을 모두 읽으셨어요. '
                '동화 10편을 담은 이용권으로 계속 함께해요.',
                style: AppTypography.body.copyWith(color: colors.textSecondary),
              ),
              const Spacer(),
              // Credit packs only (D1) — Apple IAP consumable. No subscription.
              if (_busy)
                Center(child: CircularProgressIndicator(color: colors.primary))
              else
                PrimaryButton(
                  label: '동화 10편 이용권 · 4,900원',
                  onPressed: () => _buy(
                    (g) async {
                      final products = await g.getProducts(['credits_10']);
                      return g.purchase(products.single);
                    },
                    grantCredits: 10,
                  ),
                ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}
