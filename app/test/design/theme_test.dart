import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playzy/design/theme.dart';

void main() {
  group('AppTheme', () {
    test('light and dark themes carry the right brightness', () {
      expect(AppTheme.light.brightness, Brightness.light);
      expect(AppTheme.dark.brightness, Brightness.dark);
    });

    test('scaffold background uses the base token (never pure white/black)', () {
      expect(AppTheme.light.scaffoldBackgroundColor, AppColors.light.bgBase);
      expect(AppTheme.dark.scaffoldBackgroundColor, AppColors.night.bgBase);
      expect(AppColors.light.bgBase, isNot(const Color(0xFFFFFFFF)));
      expect(AppColors.night.bgBase, isNot(const Color(0xFF000000)));
    });

    testWidgets('context.colors resolves night tokens under a dark theme',
        (tester) async {
      late AppColors resolved;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(builder: (context) {
            resolved = context.colors;
            return const SizedBox();
          }),
        ),
      );
      expect(resolved.bgBase, AppColors.night.bgBase);
      expect(resolved.primary, AppColors.night.primary);
    });
  });
}
