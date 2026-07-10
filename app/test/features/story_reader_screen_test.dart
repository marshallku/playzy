import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playzy/design/theme.dart';
import 'package:playzy/features/story/story_reader_screen.dart';
import 'package:playzy/domain/story.dart';

const _story = Story(
  id: 's1',
  title: '하준이의 모험',
  pages: [
    StoryPage(text: '첫 번째 페이지예요.'),
    StoryPage(text: '두 번째 페이지예요.'),
  ],
);

void main() {
  Widget harness() =>
      MaterialApp(theme: AppTheme.light, home: const StoryReaderScreen(story: _story));

  testWidgets('renders the title and first page', (tester) async {
    await tester.pumpWidget(harness());
    expect(find.text('하준이의 모험'), findsOneWidget);
    expect(find.text('첫 번째 페이지예요.'), findsOneWidget);
  });

  testWidgets('defaults to night mode and toggles to light', (tester) async {
    await tester.pumpWidget(harness());
    // Night default → shows the "go light" (dark_mode) icon.
    expect(find.byIcon(Icons.dark_mode), findsOneWidget);

    await tester.tap(find.byIcon(Icons.dark_mode));
    await tester.pump();
    expect(find.byIcon(Icons.light_mode), findsOneWidget);
  });

  testWidgets('font-size slider spans the documented reading range', (tester) async {
    await tester.pumpWidget(harness());
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.min, AppTypography.storyMinSize);
    expect(slider.max, AppTypography.storyMaxSize);
    expect(slider.value, AppTypography.storyDefaultSize);
  });
}
