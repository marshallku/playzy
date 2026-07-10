import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playzy/design/theme.dart';
import 'package:playzy/sdui/sdui_models.dart';
import 'package:playzy/sdui/sdui_renderer.dart';

void main() {
  Widget harness({
    required SduiDocument document,
    required Set<String> selected,
    required void Function(SduiChip) onToggle,
    bool canSelectMore = true,
  }) =>
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SduiRenderer(
            document: document,
            selected: selected,
            onToggleChip: onToggle,
            canSelectMore: canSelectMore,
          ),
        ),
      );

  const doc = SduiDocument(
    schemaVersion: 1,
    components: [
      SduiSection(title: '섹션 제목'),
      SduiChipGroup(chips: [
        SduiChip(id: 'a', label: '가나', emoji: '🌙'),
        SduiChip(id: 'b', label: '다라'),
      ]),
      SduiUnknown(type: 'future_widget'),
    ],
  );

  testWidgets('renders sections and chips; skips unknown components', (tester) async {
    await tester.pumpWidget(harness(document: doc, selected: {}, onToggle: (_) {}));

    expect(find.text('섹션 제목'), findsOneWidget);
    expect(find.text('🌙 가나'), findsOneWidget);
    expect(find.text('다라'), findsOneWidget);
    // Unknown component contributes no visible widget.
    expect(find.text('future_widget'), findsNothing);
  });

  testWidgets('tapping a chip calls onToggle with its chip', (tester) async {
    SduiChip? toggled;
    await tester.pumpWidget(harness(document: doc, selected: {}, onToggle: (c) => toggled = c));

    await tester.tap(find.text('🌙 가나'));
    expect(toggled?.id, 'a');
  });

  testWidgets('unselected chips are disabled once the max is reached', (tester) async {
    var toggles = 0;
    await tester.pumpWidget(harness(
      document: doc,
      selected: {'a'}, // 'a' selected; 'b' unselected
      onToggle: (_) => toggles++,
      canSelectMore: false,
    ));

    // Tapping the unselected 'b' does nothing (disabled).
    await tester.tap(find.text('다라'));
    expect(toggles, 0);
    // The already-selected 'a' can still be toggled off.
    await tester.tap(find.text('🌙 가나'));
    expect(toggles, 1);
  });

  testWidgets('a newer-than-supported schema renders nothing', (tester) async {
    const future = SduiDocument(
      schemaVersion: 999,
      components: [SduiSection(title: '보이면 안 됨')],
    );
    await tester.pumpWidget(harness(document: future, selected: {}, onToggle: (_) {}));
    expect(find.text('보이면 안 됨'), findsNothing);
  });
}
