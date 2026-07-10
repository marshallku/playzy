import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
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
      // Mirror the backend: a successful consumable purchase adds to the local
      // credit balance (ADR 0002). Subscriptions flow through the entitlement
      // stream and need no local grant.
      if (result.success && grantCredits > 0) {
        await ref.read(creditsProvider.notifier).add(grantCredits);
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
                '매일 밤, 아이만을 위한\n새로운 동화를 만들어요',
                style: AppTypography.h1.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                '무료 ${AppConstants.freeStoryLimit}편을 모두 읽으셨어요. 계속 함께해요.',
                style: AppTypography.body.copyWith(color: colors.textSecondary),
              ),
              const Spacer(),
              if (_busy)
                Center(child: CircularProgressIndicator(color: colors.primary))
              else ...[
                PrimaryButton(
                  label: '월 5,900원 구독하기',
                  onPressed: () => _buy((g) async {
                    final products = await g.getProducts([AppConstants.proEntitlement]);
                    return g.subscribe(products.single);
                  }),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: () => _buy(
                    (g) async {
                      final products = await g.getProducts(['credits_10']);
                      return g.purchase(products.single);
                    },
                    grantCredits: 10,
                  ),
                  child: const Text('동화 10편 4,900원'),
                ),
              ],
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}
