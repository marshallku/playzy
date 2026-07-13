import 'package:flutter/material.dart';

import '../../design/theme.dart';
import '../../domain/story.dart';

/// The bedtime payoff. Night mode is independent of the app theme (DESIGN.md
/// §10) so a parent can read in the dark regardless of system setting. Font
/// size is user-scalable (§3.2). Auto-fading chrome (§7) is a fast-follow.
class StoryReaderScreen extends StatefulWidget {
  const StoryReaderScreen({super.key, required this.story});

  final Story story;

  @override
  State<StoryReaderScreen> createState() => _StoryReaderScreenState();
}

class _StoryReaderScreenState extends State<StoryReaderScreen> {
  final _pageController = PageController();
  double _fontSize = AppTypography.storyDefaultSize;
  bool _night = true; // bedtime default
  int _page = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reader palette is chosen locally, not from the app theme (§10).
    final colors = _night ? AppColors.night : AppColors.light;
    final pages = widget.story.pages;

    return Scaffold(
      backgroundColor: colors.bgBase,
      body: SafeArea(
        child: Column(
          children: [
            _ReaderBar(
              colors: colors,
              title: widget.story.title,
              night: _night,
              onToggleNight: () => setState(() => _night = !_night),
              onClose: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _StoryPageView(
                  text: pages[i].text,
                  fontSize: _fontSize,
                  color: colors.textPrimary,
                ),
              ),
            ),
            _PageDots(
              count: pages.length,
              index: _page,
              active: colors.primary,
              inactive: colors.textTertiary,
            ),
            _FontSlider(
              colors: colors,
              value: _fontSize,
              onChanged: (v) => setState(() => _fontSize = v),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderBar extends StatelessWidget {
  const _ReaderBar({
    required this.colors,
    required this.title,
    required this.night,
    required this.onToggleNight,
    required this.onClose,
  });

  final AppColors colors;
  final String title;
  final bool night;
  final VoidCallback onToggleNight;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            color: colors.textSecondary,
            icon: const Icon(Icons.close),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.h3.copyWith(color: colors.textPrimary),
            ),
          ),
          IconButton(
            // Moon-gold glows on the night canvas (≈12:1) but is illegible on
            // the light cream (≈1.5:1) — use the brand periwinkle there (≈4.7:1)
            // so the toggle clears the 3:1 UI-graphic bar in both reader modes.
            onPressed: onToggleNight,
            color: night ? colors.accent : colors.primary,
            tooltip: night ? '밝게 보기' : '어둡게 보기',
            icon: Icon(night ? Icons.dark_mode : Icons.light_mode),
          ),
        ],
      ),
    );
  }
}

class _StoryPageView extends StatelessWidget {
  const _StoryPageView({required this.text, required this.fontSize, required this.color});

  final String text;
  final double fontSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxl,
        vertical: AppSpacing.x4l,
      ),
      child: Text(
        // storyBody carries its own line-height multiplier (DESIGN.md §3.2);
        // overriding only fontSize keeps that ratio.
        text,
        style: AppTypography.storyBody.copyWith(fontSize: fontSize, color: color),
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({
    required this.count,
    required this.index,
    required this.active,
    required this.inactive,
  });

  final int count;
  final int index;
  final Color active;

  /// Inactive dots use the muted [inactive] tone (not a faded [active]) so they
  /// still clear the 3:1 UI-graphic bar — matching the reference, where inactive
  /// dots are `dark-muted`, not a translucent primary.
  final Color inactive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: AppMotion.fast,
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              width: i == index ? AppSizes.pageDotActive : AppSizes.pageDot,
              height: AppSizes.pageDot,
              decoration: BoxDecoration(
                color: i == index ? active : inactive,
                borderRadius: AppRadius.pillAll,
              ),
            ),
        ],
      ),
    );
  }
}

class _FontSlider extends StatelessWidget {
  const _FontSlider({required this.colors, required this.value, required this.onChanged});

  final AppColors colors;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Row(
        children: [
          // Small/large "가" glyphs cue the reading-size range (min → max).
          Text('가',
              style: AppTypography.bodySm.copyWith(color: colors.textSecondary)),
          Expanded(
            child: Slider(
              min: AppTypography.storyMinSize,
              max: AppTypography.storyMaxSize,
              activeColor: colors.primary,
              value: value,
              onChanged: onChanged,
            ),
          ),
          Text('가', style: AppTypography.h2.copyWith(color: colors.textSecondary)),
        ],
      ),
    );
  }
}
