import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/story.dart';
import '../features/child_profile/child_profile_screen.dart';
import '../features/home/home_screen.dart';
import '../features/paywall/paywall_screen.dart';
import '../features/situation_picker/situation_picker_screen.dart';
import '../features/story/generating_screen.dart';
import '../features/story/story_options_screen.dart';
import '../features/story/story_reader_screen.dart';

/// Route names — referenced by screens instead of raw path strings.
abstract final class Routes {
  static const home = '/';
  static const profile = '/profile';
  static const pick = '/pick';
  static const options = '/options';
  static const generating = '/generating';
  static const story = '/story';
  static const paywall = '/paywall';
}

/// The router is provided (not a global singleton) so each ProviderScope — the
/// app, and every test — gets a fresh instance with isolated navigation state.
final routerProvider = Provider<GoRouter>((ref) => createAppRouter());

GoRouter createAppRouter() => GoRouter(
      initialLocation: Routes.home,
      routes: [
        GoRoute(path: Routes.home, builder: (_, __) => const HomeScreen()),
        GoRoute(
            path: Routes.profile,
            builder: (_, __) => const ChildProfileScreen()),
        GoRoute(
            path: Routes.pick,
            builder: (_, __) => const SituationPickerScreen()),
        GoRoute(
          path: Routes.options,
          builder: (_, state) =>
              StoryOptionsScreen(situationIds: state.extra! as List<String>),
        ),
        GoRoute(
          path: Routes.generating,
          builder: (_, state) =>
              GeneratingScreen(request: state.extra! as StoryRequest),
        ),
        GoRoute(
          path: Routes.story,
          builder: (_, state) =>
              StoryReaderScreen(story: state.extra! as Story),
        ),
        GoRoute(
            path: Routes.paywall, builder: (_, __) => const PaywallScreen()),
      ],
    );
