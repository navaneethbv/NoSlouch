# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
make build        # swift build --disable-sandbox
make test         # swift test --disable-sandbox
make lint         # swift format lint --recursive --strict
make format       # swift format format --recursive --in-place (auto-fix)
make bundle       # build + assemble NoSlouch.app with ad-hoc codesign
make run          # bundle + open the app
make clean        # remove .build/ and NoSlouch.app
```

Run a single test class or method:

```bash
swift test --disable-sandbox --filter PostureAnalyzerTests
swift test --disable-sandbox --filter PostureAnalyzerTests/testSustainedDropBecomesBad
```

The `--disable-sandbox` flag is required on every `swift build` and `swift test` invocation in this repo.

## Architecture

NoSlouch is a dependency-free macOS 14+ menu-bar app (`MenuBarExtra`, no Dock icon). The entry point is `NoSlouchApp.swift`. All coordination flows through `PostureViewModel`, which is the single `@StateObject` owned by the app.

**Data flow:**

```
AirPodsMotionProvider  ──onReading──►  PostureViewModel  ──pitch──►  PostureAnalyzer
                                              │                           │
AudioOutputMonitor  ──onChange──►            │          ◄──PostureState──┘
                                             │
                                    PostureNotifier  (nudge / sound / speech)
                                    PostureHistoryStore  (session → daily aggregate)
                                    AppSettings  (UserDefaults)
```

**Key design decisions:**

- `HeadMotionProvider` and `AudioOutputMonitoring` are protocols. The real implementations (`AirPodsMotionProvider`, `AudioOutputMonitor`) require hardware. All ViewModel tests use fakes injected via the init.
- `PostureAnalyzer` is a pure Swift `struct` (no imports). It is the highest unit-test priority module.
- `AudioOutputMonitor` dispatches its CoreAudio listener on `DispatchQueue.main`. All reads and writes of `airPodsActive` happen on the main thread; the ViewModel reads it from the main thread only.
- **Cooldown is owned by `PostureViewModel`** (`lastBadNudgeAt`, `nudgesPausedUntil`). `PostureNotifier.nudge()` does not rate-limit itself; it fires on every call.
- Motion callbacks arrive on a background `OperationQueue` inside `AirPodsMotionProvider` and are dispatched to the main thread by the ViewModel before any state mutation.
- Sessions under 5 seconds are discarded. History is capped at 90 days in `PostureHistoryStore`.

**Entitlements:** `com.apple.developer.coremotion.headphone-motion-data` is in `NoSlouch.entitlements`. The Makefile only passes the entitlements file for non-ad-hoc signing (`SIGN_IDENTITY != -`). Ad-hoc local builds work but the restricted entitlement is not embedded; a Developer ID certificate is required to get live AirPods motion data in a signed release build.

## Testing notes

- `PostureAnalyzerTests`, `PostureHistoryStoreTests`, `AppSettingsTests` cover pure logic with no hardware dependency.
- `PostureViewModelTests` uses `FakeHeadMotionProvider`, `FakeAudioOutputMonitor`, and `FakePostureNotifier` (all defined at the bottom of that file). `FakePostureNotifier.nudge()` increments a counter unconditionally; cooldown behavior is tested through the ViewModel, not the fake.
- Use `drainMainQueue()` (defined in the test file) after `motionProvider.emit()` calls to let the ViewModel's main-thread dispatch settle before asserting.
- Tests use isolated `UserDefaults` suites (UUID-named) created and torn down per test to avoid cross-test contamination.

## rexyMCP workflow

This project uses the rexyMCP architect/executor workflow; the contract lives in
REXYMCP.md, imported below.

@REXYMCP.md
