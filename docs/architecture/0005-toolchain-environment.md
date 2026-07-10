# ADR 0005 — Flutter toolchain in this environment (Docker for CI/tests)

- **Status**: Superseded in part — native toolchain now works (see Update)
- **Date**: 2026-07-11

## Update (2026-07-11) — native toolchain RESOLVED; iOS verified

The hang below was **fixed**: re-signing every Mach-O in the Flutter cache with
an **ad-hoc signature** (`codesign --force --sign -` over
`bin/cache/**`), after removing quarantine, made the native Dart VM launch
normally. `dart --version`, `flutter --version`, `flutter test`, and
`flutter test integration_test -d <sim>` all run natively now.

Consequently **iOS was actually built and run**:

- `flutter build ios --simulator` → `✓ Built build/ios/iphonesimulator/Runner.app`.
- Installed + launched on an **iPhone 17 (iOS 26.5) simulator** via `simctl`;
  home screen captured (`docs/verification/ios/ios-01-home.png`).
- The **full journey integration test passes on the real simulator**
  (`integration_test/app_journey_test.dart` via `flutter test … -d <sim>`) —
  home → profile → picker → generate → night-mode reader.

Xcode 26.6 is present at `/Applications/Xcode.app`; it's selected without sudo
via `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (the active
`xcode-select` dir is Command Line Tools). Docker (below) remains valid for
Linux CI, but is no longer required on this host.

---

_Original context (kept for history):_

## Context

Flutter was installed on the dev host via `brew install --cask flutter`
(SDK at `/opt/homebrew/share/flutter`). Running **any** Dart/Flutter command
(`dart --version`, `flutter …`) **hangs indefinitely** on this macOS (Apple
Silicon) host.

### Root cause (diagnosed)

The Dart VM binaries are signed with a Developer ID. On first launch, the
kernel's code-signing path (AMFI / `amfid` / `syspolicyd`) validates the
binary. In this environment that validation **never returns** — the process
parks at `_dyld_start` before dyld loads a single library. Findings:

- Developer-ID-signed → hangs at `_dyld_start`.
- Ad-hoc re-signed (fully local, no network) → **also hangs**. So it is not a
  notarization/OCSP network stall; the userspace code-signing daemon itself is
  unresponsive for third-party binaries.
- Signature removed → binary runs far enough to be **SIGKILLed** (arm64
  requires a valid signature).

System binaries (`git`, `ps`, `brew`) are unaffected because they're in the
kernel trust cache and skip `amfid`.

Fixing this at the OS level needs privileges we don't have (disable
Gatekeeper/AMFI) or a working code-signing daemon. **We do not fight it.**

### Side effect on the host SDK

While diagnosing, the cache Mach-O binaries under
`/opt/homebrew/share/flutter/bin/cache` were re-signed **ad-hoc** (a valid arm64
resting state). They function normally on a machine where `amfid` works. To
restore pristine Developer-ID signatures: `brew reinstall --cask flutter`.

## Decision

**Run the Dart/Flutter toolchain inside a Linux Docker container**, which has no
macOS AMFI layer. Docker (Rancher Desktop) is available on the host.

- Image: `ghcr.io/cirruslabs/flutter:stable`.
- All `flutter pub get`, `flutter analyze`, `flutter test` runs go through the
  container against the mounted `app/` directory.
- A helper script `app/tool/flutter.sh` wraps the `docker run …` invocation so
  the command is one word locally.

### What the container can and cannot do

- ✅ `flutter pub get`, `flutter analyze`, `dart format`, `flutter test`
  (unit + widget tests) — the full logic/UI test surface.
- ✅ `flutter create --platforms=ios,android,web` — the iOS/Android/web project
  scaffolds (incl. `ios/Runner.xcodeproj`, org `im.toss`) were generated in the
  container and are committed. Scaffolding is host-agnostic.
- ❌ **iOS build / run** — requires macOS + Xcode, and the same host toolchain.
  iOS *building* is deferred to a machine with a working code-signing daemon
  (or a macOS CI runner). This does not block authoring or testing the Dart/
  Flutter code, nor the scaffold; it blocks only the final device build.

## Consequences

- The workflow's **testing step is honored** — tests run for real in the
  container, not skipped.
- iOS-specific build/run verification is environment-blocked and is called out
  wherever relevant (roadmap M4). Everything up to that point is fully testable.
- CI later should mirror this: Linux container for analyze/test, macOS runner
  for the iOS build.
