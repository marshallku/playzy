# Verification — build, tests, and a real end-to-end run

Evidence that the app is actually built, tested, and works — not just that it
compiles.

## Automated (run every change)

| Check | How | Result |
| --- | --- | --- |
| App unit + widget tests | `flutter test` (Docker, ADR 0005) | **86 passing** |
| App **end-to-end journey** | `flutter test test/app_journey_test.dart` | **passing** — drives the REAL app (router + providers + every screen) cold-start → finished story |
| Static analysis | `flutter analyze` | clean |
| Backend tests | `go test ./...` | **31 passing** |
| Backend vet/format | `go vet` / `gofmt` | clean |
| **Real web build** | `flutter build web --release` | ✓ Built `build/web` |

## iOS — actually built and run in the simulator

The native toolchain hang (ADR 0005) was resolved (ad-hoc re-sign of the Flutter
cache), so iOS was built and run for real:

| Check | How | Result |
| --- | --- | --- |
| iOS **build** | `flutter build ios --simulator` | ✓ Built `Runner.app` (Xcode 26.6) |
| Run in **simulator** | `simctl install/launch` on iPhone 17 (iOS 26.5) | app runs — [ios/ios-01-home.png](ios/ios-01-home.png) |
| iOS **e2e journey** | `flutter test integration_test/app_journey_test.dart -d <sim>` | **All tests passed** — full flow incl. night-mode reader, on the real simulator |

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # no sudo
xcrun simctl boot "iPhone 17"
flutter build ios --simulator --debug
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
xcrun simctl launch booted im.toss.playzy
xcrun simctl io booted screenshot ios/ios-01-home.png
flutter test integration_test/app_journey_test.dart -d "iPhone 17"
```

The `integration_test` version of the journey adds device-robust scrolling
(`scrollUntilVisible`) so it drives the flow on a real tall device, not just the
default test window.

## Manual e2e — the app actually running, captured

The `flutter build web` output was served and driven through the whole user
journey in a real (headless Chromium) browser. Screenshots below are the actual
rendered app on fake backends (no server needed).

| # | Screen | What it proves |
| --- | --- | --- |
| [01](01-home.png) | Home (fresh install) | Design system live: cream bg, periwinkle brand, Pretendard Korean, "무료 동화 3편 남았어요" from the quota provider |
| [02](02-profile.png) | Child profile form | Name field, age-band chips (2–3세 selected), interest chips, companion field, save CTA |
| [03](03-profile-filled.png) | Profile filled | Real keyboard input ("하준") + chip selection ("공룡") |
| [04](04-home-with-profile.png) | Home w/ profile | Saved & persisted → CTA becomes "오늘의 동화 만들기" + edit link |
| [05](05-situation-picker.png) | Situation picker (SDUI) | The SDUI renderer drawing the catalog: parenting + theme sections, emoji chips, "동화 만들기" disabled until a pick |
| [05b](05b-picker-selected.png) | Picker w/ selection | "잠자기" selected → generate button enables |
| [07](07-story-reader.png) | Story reader | **Night mode** payoff: personalized title "하준의 bedtime 이야기", page "옛날 옛적, 하준(이)가 살고 있었어요.", page dots, font slider |

## How to reproduce

```bash
# tests + build (in the Docker toolchain)
./app/tool/flutter.sh test
docker run --rm -v "$PWD/app:/app" -w /app ghcr.io/cirruslabs/flutter:stable \
  flutter build web --release

# serve + drive (host)
python3 -m http.server 8099 --directory app/build/web &
#   then a headless browser over http://localhost:8099 (see the flow above)
```

Note: the app renders with CanvasKit (canvas, not DOM), so the capture drives by
pointer coordinates. The behavioral guarantee is the `app_journey_test.dart`
integration test; these screenshots are the visual confirmation.
