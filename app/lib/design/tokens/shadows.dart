import 'package:flutter/widgets.dart';

/// Soft, color-tinted shadows (never grey/black). Mirrors DESIGN.md §5.2.
/// In night mode, elevation is conveyed by a lighter surface, not shadow —
/// use [none] there.
abstract final class AppShadows {
  static const Color _tint = Color(0xFF5265C6); // brand primary (light)

  static List<BoxShadow> get sm => [
        BoxShadow(
          color: _tint.withValues(alpha: 0.10),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get md => [
        BoxShadow(
          color: _tint.withValues(alpha: 0.12),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];

  static List<BoxShadow> get lg => [
        BoxShadow(
          color: _tint.withValues(alpha: 0.14),
          blurRadius: 40,
          offset: const Offset(0, 16),
        ),
      ];

  static const List<BoxShadow> none = [];
}
