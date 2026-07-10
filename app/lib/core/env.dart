/// Build-time configuration. The backend base URL is injected via
/// `--dart-define=PLAYZY_API_BASE_URL=https://...`. When empty (the default),
/// the app runs on fake backends (ADR 0001) so it works with no server.
abstract final class Env {
  static const String apiBaseUrl =
      String.fromEnvironment('PLAYZY_API_BASE_URL', defaultValue: '');

  /// True once a real backend URL is configured — flips the app from fakes to
  /// the HTTP clients (see core/providers.dart).
  static bool get hasBackend => apiBaseUrl.isNotEmpty;
}
