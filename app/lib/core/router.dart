import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/story.dart';
import '../features/child_profile/child_profile_screen.dart';
import '../features/create/create_cast_screen.dart';
import '../features/create/create_tone_screen.dart';
import '../features/create/create_topic_screen.dart';
import '../features/home/home_screen.dart';
import '../features/paywall/paywall_screen.dart';
import '../features/roster/roster_screen.dart';
import '../features/story/generating_screen.dart';
import '../features/story/story_reader_screen.dart';

/// Route names — referenced by screens instead of raw path strings.
abstract final class Routes {
  static const home = '/';
  static const profile = '/profile';
  static const roster = '/roster';
  // The 3-step create funnel (topic → cast → tone). State lives in
  // storyDraftProvider, so back-swipe between steps preserves choices.
  static const createTopic = '/create/topic';
  static const createCast = '/create/cast';
  static const createTone = '/create/tone';
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
            path: Routes.roster,
            builder: (_, __) => const RosterScreen()),
        GoRoute(
            path: Routes.createTopic,
            builder: (_, __) => const CreateTopicScreen()),
        GoRoute(
            path: Routes.createCast,
            builder: (_, __) => const CreateCastScreen()),
        GoRoute(
            path: Routes.createTone,
            builder: (_, __) => const CreateToneScreen()),
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
