/// Build-time configuration. The backend base URL is injected via
/// `--dart-define=PLAYZY_API_BASE_URL=https://...`. When empty (the default),
/// the app runs on fake backends (ADR 0001) so it works with no server.
abstract final class Env {
  static const String apiBaseUrl =
      String.fromEnvironment('PLAYZY_API_BASE_URL', defaultValue: '');

  /// True once a real backend URL is configured — flips the app from fakes to
  /// the HTTP clients (see core/providers.dart).
  static bool get hasBackend => apiBaseUrl.isNotEmpty;

  /// DEV ONLY: admin token that lets the app grant itself server-side credits
  /// via the backend's admin-gated endpoint, so the full paid flow can be
  /// exercised end-to-end against a local backend. Empty in real builds — then
  /// credits are granted only by a verified purchase webhook (ADR 0002).
  static const String devAdminToken =
      String.fromEnvironment('PLAYZY_DEV_ADMIN_TOKEN', defaultValue: '');

  static bool get hasDevAdminToken => devAdminToken.isNotEmpty;

  /// RevenueCat iOS public SDK key, injected via
  /// `--dart-define=PLAYZY_REVENUECAT_IOS_KEY=appl_...`. When set (and a backend is
  /// configured), the iOS build uses the real Apple-IAP gateway; otherwise it falls
  /// back to the fake so the app still runs in dev/test/Android (ADR 0002).
  static const String revenueCatIosKey =
      String.fromEnvironment('PLAYZY_REVENUECAT_IOS_KEY', defaultValue: '');

  static bool get hasRevenueCat => revenueCatIosKey.isNotEmpty;
}
