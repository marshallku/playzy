# WU5b — native social sign-in: turnkey runbook

Everything on the Playzy side is already built and tested: the backend OIDC verifiers
(Apple/Google/Kakao), the `AuthController`, and the login/account UI (commit `9600baf`).
The ONLY missing piece is the native credential fetch behind the `SocialSignIn` seam
(`app/lib/data/auth/social_sign_in.dart`). This doc is the exact, ordered checklist to
finish it once the user-blocked inputs (client IDs, CocoaPods) are available.

Blocked on (see `71-user-action-items.md`): provider **client IDs**, iOS **native config**,
and **CocoaPods** installed on the build machine.

---

## 0. One-time machine prereq
```bash
brew install cocoapods   # currently missing → pod-based plugins can't build
```

## 1. Add the SDK packages (`app/pubspec.yaml`)
```yaml
dependencies:
  sign_in_with_apple: ^6.1.0        # Apple
  google_sign_in: ^6.2.1            # Google
  kakao_flutter_sdk_user: ^1.9.0    # Kakao
  crypto: ^3.0.3                    # sha256 for the nonce binding
```
```bash
cd app && flutter pub get
# analyze works without pods; a device/sim build needs: cd ios && pod install
```

## 2. The nonce binding (already contracted)
The backend issues a **rawNonce** (`POST /v1/auth/nonce`). Each provider request must carry
**`sha256hex(rawNonce)`** as its nonce; the returned id_token's `nonce` claim then equals that
hash. The backend's `nonceHashMatches` does a constant-time sha256-hex compare — so the facade
just computes the hash and passes it in. (Apple takes the hashed nonce directly; Google/Kakao
accept a `nonce` param.)

```dart
String _hashedNonce(String rawNonce) =>
    sha256.convert(utf8.encode(rawNonce)).toString(); // hex
```

## 3. Implement `SocialSignIn` per provider
Create `app/lib/data/auth/native_social_sign_in.dart` implementing the existing interface.
Dispatch by `AuthProviderKind`; each returns `SocialCredential(idToken)`:
- **Apple**: `SignInWithApple.getAppleIDCredential(scopes: [], nonce: hashed)` → `credential.identityToken`.
- **Google**: `GoogleSignIn(clientId/serverClientId).signIn()` → `authentication.idToken`
  (pass the hashed nonce per the google_sign_in nonce API for your version).
- **Kakao**: `UserApi.instance.loginWithKakaoAccount(nonce: hashed)` → OIDC id_token.
Throw on cancel/failure (the UI already surfaces it as a SnackBar).

Then swap the provider override in `app/lib/core/auth_controller.dart`:
```dart
final socialSignInProvider =
    Provider<SocialSignIn>((ref) => NativeSocialSignIn(/* client ids from config */));
```

## 4. Native iOS config (`app/ios/`)
- **Apple**: enable the *Sign in with Apple* capability (Xcode → Signing & Capabilities;
  adds `Runner.entitlements`).
- **Google**: add the **reversed iOS client ID** as a URL scheme in `Info.plist`
  (`CFBundleURLTypes`); pass the client id to `GoogleSignIn`.
- **Kakao**: `KakaoSdk.init(nativeAppKey: ...)` in `main()`; `Info.plist` →
  `LSApplicationQueriesSchemes` (`kakaokompassauth`, `kakaolink`) and a
  `CFBundleURLSchemes` entry `kakao{NATIVE_APP_KEY}`.

## 5. Backend audiences (already wired — just set the env)
Set the OIDC audiences the backend validates against (each empty → that route is 404):
`APPLE_CLIENT_ID`, `GOOGLE_CLIENT_ID`, `KAKAO_CLIENT_ID`, plus `PLAYZY_SESSION_SECRET`.

## 6. Verify
- `flutter analyze` + `flutter test` (Dart-side; no pods) stay green.
- On a **real device** (App Attest / Apple sign-in need a device, not the sim): run each
  provider end-to-end → confirm a session is stored and story/quota calls carry `Bearer`.

## 7. Then (separate, still deferred): the paywall login-gate
Once native login actually works, enable "login-then-purchase" on the paywall (currently
intentionally OFF so anonymous purchase isn't broken). Gate the purchase CTA on
`authController.isSignedIn`; route to `/login` first. Add a widget test.
