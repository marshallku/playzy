/// App-wide constants. Product values here mirror docs/planning decisions and
/// are the local-dev mirror of what the backend enforces in production.
abstract final class AppConstants {
  /// Free stories before the paywall (D2 — market standard is 3).
  static const int freeStoryLimit = 3;

  /// Entitlement that lifts the free-tier quota (ADR 0002).
  static const String proEntitlement = 'pro_monthly';

  /// Recommended number of situations to pick per story (docs/planning/10).
  static const int maxSituationsPerStory = 3;

  /// Extra characters a story can feature (등장인물). Mirrors the backend cap
  /// (`maxCharacters`) — the server is the real guard (planning/40).
  static const int maxCharactersPerStory = 5;

  /// How many saved characters the reusable roster (보관함) can hold. Larger than
  /// [maxCharactersPerStory] — the roster is a library; a single story still
  /// features at most [maxCharactersPerStory] of them.
  static const int maxRosterCharacters = 12;
}
