/// Which identity provider a sign-in uses. The name matches the backend route
/// segment (`/v1/auth/<name>`).
enum AuthProviderKind { apple, google, kakao }

/// What a provider sign-in yields: the provider's OIDC id_token, already bound to
/// the server nonce (the facade hashes the raw nonce into the provider request).
class SocialCredential {
  const SocialCredential(this.idToken);
  final String idToken;
}

/// The native provider sign-in seam (Apple/Google/Kakao SDKs). Kept behind an
/// interface so the [AuthController] is unit-testable without the SDKs; the real
/// per-provider implementations (and their nonce hashing + iOS native config) land
/// in WU5b.
abstract interface class SocialSignIn {
  /// Runs the native sign-in for [kind], binding the id_token to [rawNonce]
  /// (the provider request carries sha256(rawNonce); the id_token's nonce claim
  /// must match). Throws on cancel/failure.
  Future<SocialCredential> signIn(AuthProviderKind kind, {required String rawNonce});
}

/// Placeholder until the real SDKs are wired (WU5b). It throws rather than silently
/// no-op'ing, so a login button can't appear to "work" without a real provider.
class UnsupportedSocialSignIn implements SocialSignIn {
  const UnsupportedSocialSignIn();

  @override
  Future<SocialCredential> signIn(AuthProviderKind kind, {required String rawNonce}) {
    throw UnimplementedError('${kind.name} sign-in is wired in WU5b');
  }
}
