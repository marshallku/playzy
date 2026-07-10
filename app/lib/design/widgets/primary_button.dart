import 'package:flutter/material.dart';

import '../theme.dart';

/// Primary CTA — big pill button per DESIGN.md §8. 52–56px tall, full-width by
/// default, tinted press feedback. Reads design tokens; no hardcoded values.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: expand ? double.infinity : null,
      height: AppSizes.buttonHeight,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.textOnBrand,
          disabledBackgroundColor: colors.bgSubtle,
          disabledForegroundColor: colors.textTertiary,
          shape: const StadiumBorder(),
          textStyle: AppTypography.button,
        ),
        child: Text(label),
      ),
    );
  }
}
