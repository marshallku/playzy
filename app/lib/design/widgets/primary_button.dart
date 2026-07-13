import 'package:flutter/material.dart';

import '../theme.dart';

/// Primary CTA — big pill button per DESIGN.md §8. 52–56px tall, full-width by
/// default. Rests on a soft primary-tinted shadow (light only); on press it
/// dips to scale 0.97 + `shadow.sm`. Reads design tokens; no hardcoded values.
class PrimaryButton extends StatefulWidget {
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
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = widget.onPressed != null;
    final isNight = Theme.of(context).brightness == Brightness.dark;
    // The CTA floats on a soft primary-tinted shadow (§8) — but only when
    // enabled and in light mode: a disabled button must not float, and night
    // conveys elevation without dark shadows (§5.2). On press it dips to sm.
    // Gate the pressed visuals on `enabled` too: if the button is disabled
    // mid-press (onPressed → null between pointer down and up), it must not stay
    // scaled/dipped even if `_pressed` is briefly stale.
    final pressed = enabled && _pressed;
    final floats = enabled && !isNight;
    final shadow = !floats
        ? AppShadows.none
        : (pressed ? AppShadows.sm : AppShadows.md);

    void setPressed(bool value) {
      // Never START a press on a disabled button, but always allow the reset to
      // false so a disable-mid-press can't strand `_pressed` at true.
      if (value && !enabled) return;
      if (_pressed == value) return;
      setState(() => _pressed = value);
    }

    return Listener(
      // Listener observes pointer up/down without competing for the tap, so the
      // FilledButton still fires onPressed normally.
      onPointerDown: (_) => setPressed(true),
      onPointerUp: (_) => setPressed(false),
      onPointerCancel: (_) => setPressed(false),
      child: AnimatedScale(
        scale: pressed ? 0.97 : 1.0,
        duration: AppMotion.fast,
        curve: AppMotion.ease,
        child: SizedBox(
          width: widget.expand ? double.infinity : null,
          height: AppSizes.buttonHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: AppRadius.pillAll,
              boxShadow: shadow,
            ),
            child: FilledButton(
              onPressed: widget.onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.textOnBrand,
                disabledBackgroundColor: colors.bgAlt,
                disabledForegroundColor: colors.textTertiary,
                shape: const StadiumBorder(),
                textStyle: AppTypography.button,
              ),
              child: Text(widget.label),
            ),
          ),
        ),
      ),
    );
  }
}
