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
/// Outcome of settling a purchase into the credit balance.
enum _Settlement {
  /// Credits are already reflected (offline mirror or dev admin grant).
  applied,

  /// Purchase accepted; the verified webhook will credit the balance shortly.
  pending,

  /// Backend present but this build has no path to grant credits.
  unavailable,
}

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
      // Cancelled or a failure the gateway reported without throwing — leave the
      // paywall open, no error message (a cancel is expected user behavior).
      if (!result.success) return;

      if (grantCredits > 0) {
        final outcome = await _settle(grantCredits);
        if (outcome == _Settlement.unavailable) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('이 빌드에서는 결제가 아직 준비되지 않았어요.')),
            );
          }
          return;
        }
        if (outcome == _Settlement.pending && mounted) {
          // The purchase succeeded; the verified webhook credits the balance
          // moments later. Be honest rather than faking an immediate grant.
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('구매가 완료됐어요. 크레딧이 곧 반영돼요.')),
          );
        }
      }
      if (mounted && context.canPop()) context.pop();
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

  /// Settles a successful purchase into the authoritative balance per the app's
  /// [PaymentMode], so a real Apple purchase is only ever credited by the verified
  /// backend webhook — never a local grant (ADR 0002).
  Future<_Settlement> _settle(int amount) async {
    switch (ref.read(paymentModeProvider)) {
      case PaymentMode.offlineLocal:
        await ref.read(creditsProvider.notifier).add(amount);
        return _Settlement.applied;
      case PaymentMode.appleWebhook:
        // Refresh authoritative quota; it reflects once RevenueCat's webhook lands.
        ref.invalidate(quotaStateProvider);
        return _Settlement.pending;
      case PaymentMode.devAdmin:
        await ref
            .read(quotaApiProvider)!
            .grantCreditsDev(amount, Env.devAdminToken);
        ref.invalidate(quotaStateProvider);
        return _Settlement.applied;
      case PaymentMode.unavailable:
        return _Settlement.unavailable;
    }
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
