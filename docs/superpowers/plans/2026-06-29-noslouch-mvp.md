# NoSlouch MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the smallest working NoSlouch macOS menu-bar app with tested posture analysis, tested persistence, and a thin hardware-backed app shell.

**Architecture:** Pure Swift modules own posture analysis and persistence so they can be tested without AirPods. The SwiftUI app shell wires Core Motion, CoreAudio, notifications, and UserDefaults-backed state. App-shell behavior stays minimal and is verified by build and launch smoke tests.

**Tech Stack:** Swift Package Manager, Swift 5.9+ language mode, SwiftUI, CoreMotion, CoreAudio, AppKit, AVFAudio, UserNotifications, XCTest.

## Global Constraints

- Minimum deployment target: macOS 14.0.
- `Package.swift` must declare `.macOS(.v14)`.
- No third-party dependencies.
- Use Apple frameworks only.
- The app bundle identifier is `com.noslouch.app`.
- The app must run as an LSUIElement menu-bar app with no Dock icon.
- `Resources/Info.plist` must include `NSMotionUsageDescription`.
- `NoSlouch.entitlements` must exist, but ad-hoc signing must not force restricted entitlements by default.
- `make build`, `make test`, `make bundle`, and `make run` are the supported commands.
- `build.sh` is not part of the MVP.
- Keep UI wiring thin and keep testable behavior in pure Swift types.
- Use TDD for `PostureAnalyzer`, `PostureHistoryStore`, and `AppSettings`.

---

### Task 1: Swift Package And Build Shell

**Files:**
- Create: `.gitignore`
- Create: `Package.swift`
- Create: `Makefile`
- Create: `Resources/Info.plist`
- Create: `Resources/AppIcon.icns`
- Create: `NoSlouch.entitlements`
- Create: `Sources/NoSlouch/NoSlouchApp.swift`

**Interfaces:**
- Produces executable target: `NoSlouch`
- Produces test target: `NoSlouchTests`
- Produces commands: `make build`, `make test`, `make bundle`, `make run`, `make clean`
- Produces minimal menu-bar entry point so SwiftPM accepts the executable target

- [ ] **Step 1: Add package and ignore rules**

Create `.gitignore`:

```gitignore
.build/
DerivedData/
NoSlouch.app/
*.xcuserdata/
.DS_Store
.superpowers/
```

Create `Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NoSlouch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "NoSlouch", targets: ["NoSlouch"])
    ],
    targets: [
        .executableTarget(
            name: "NoSlouch",
            path: "Sources/NoSlouch"
        ),
        .testTarget(
            name: "NoSlouchTests",
            dependencies: ["NoSlouch"],
            path: "Tests/NoSlouchTests"
        )
    ]
)
```

- [ ] **Step 2: Add bundle resources**

Create `Resources/Info.plist` with `LSUIElement`, bundle id `com.noslouch.app`, and `NSMotionUsageDescription`.

Create `NoSlouch.entitlements` with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.coremotion.headphone-motion-data</key>
    <true/>
</dict>
</plist>
```

Create a placeholder `Resources/AppIcon.icns`. It can be empty for the first build if `iconutil` assets are not available.

- [ ] **Step 3: Add minimal app entry point**

Create `Sources/NoSlouch/NoSlouchApp.swift` with a `MenuBarExtra` containing the app name and a Quit button. The fuller view model and controls are added in Task 4.

- [ ] **Step 4: Add Makefile**

Create `Makefile` with:

```makefile
APP_NAME := NoSlouch
BUNDLE := $(APP_NAME).app
EXECUTABLE := .build/debug/$(APP_NAME)
SIGN_IDENTITY ?= -

.PHONY: build test bundle run clean

build:
	swift build --disable-sandbox

test:
	swift test --disable-sandbox

bundle: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	cp $(EXECUTABLE) $(BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns $(BUNDLE)/Contents/Resources/AppIcon.icns; fi
	if [ "$(SIGN_IDENTITY)" = "-" ]; then \
		codesign --force --sign - $(BUNDLE); \
	else \
		codesign --force --sign "$(SIGN_IDENTITY)" --entitlements NoSlouch.entitlements $(BUNDLE); \
	fi

run: bundle
	open $(BUNDLE)

clean:
	rm -rf .build $(BUNDLE)
```

- [ ] **Step 5: Verify scaffold**

Run: `swift package describe`

Expected: package graph prints successfully. A warning about an empty test target is acceptable until Task 2 adds the first tests.

- [ ] **Step 6: Commit**

```bash
git add .gitignore Package.swift Makefile Resources/Info.plist Resources/AppIcon.icns NoSlouch.entitlements Sources/NoSlouch/NoSlouchApp.swift
git commit -m "Add Swift package build scaffold"
```

### Task 2: Posture Analyzer

**Files:**
- Create: `Sources/NoSlouch/Posture/PostureState.swift`
- Create: `Sources/NoSlouch/Posture/PostureCalibration.swift`
- Create: `Sources/NoSlouch/Posture/PostureAnalyzer.swift`
- Create: `Tests/NoSlouchTests/PostureAnalyzerTests.swift`

**Interfaces:**
- Produces: `public enum PostureState: Equatable { case unknown, good, bad }`
- Produces: `public struct PostureCalibration: Equatable { public var baselinePitch: Double }`
- Produces: `public struct PostureAnalyzer`
- Produces initializer: `PostureAnalyzer(thresholdDegrees: Double, holdSeconds: TimeInterval, recoverSeconds: TimeInterval, smoothingAlpha: Double = 0.2, invertedPitch: Bool = false)`
- Produces methods: `mutating func calibrate(pitch: Double)`, `mutating func update(pitch: Double, at timestamp: Date) -> PostureState`
- Produces properties: `state`, `calibration`, `smoothedPitch`

- [ ] **Step 1: Write failing analyzer tests**

Create `Tests/NoSlouchTests/PostureAnalyzerTests.swift` with tests for:

```swift
func testStartsUnknownBeforeCalibration()
func testCalibrationStartsGood()
func testSustainedDropBecomesBad()
func testBriefDropDoesNotBecomeBad()
func testRecoveryReturnsToGood()
func testInvertedPitchUsesOppositeDrop()
```

- [ ] **Step 2: Run tests to verify RED**

Run: `swift test --disable-sandbox --filter PostureAnalyzerTests`

Expected: FAIL because posture types do not exist.

- [ ] **Step 3: Add minimal posture types**

Create the three posture files. Keep implementation pure Swift, deterministic, and free of Apple framework imports.

- [ ] **Step 4: Run tests to verify GREEN**

Run: `swift test --disable-sandbox --filter PostureAnalyzerTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/NoSlouch/Posture Tests/NoSlouchTests/PostureAnalyzerTests.swift
git commit -m "Add tested posture analyzer"
```

### Task 3: Persistence

**Files:**
- Create: `Sources/NoSlouch/Persistence/AppSettings.swift`
- Create: `Sources/NoSlouch/Persistence/PostureSession.swift`
- Create: `Sources/NoSlouch/Persistence/PostureHistoryStore.swift`
- Create: `Tests/NoSlouchTests/AppSettingsTests.swift`
- Create: `Tests/NoSlouchTests/PostureHistoryStoreTests.swift`

**Interfaces:**
- Produces: `public struct AppSettings: Equatable`
- Produces: `public struct PostureSession: Equatable`
- Produces: `public struct DayPostureStat: Codable, Equatable, Identifiable`
- Produces: `public final class PostureHistoryStore`
- Settings default values: threshold `12.0`, hold `3.0`, recover `1.5`, cooldown `60.0`, sound enabled `true`, speech enabled `false`, inverted pitch `false`.
- History ignores sessions shorter than five seconds and stores at most 90 days.

- [ ] **Step 1: Write failing persistence tests**

Create tests for:

```swift
func testSettingsLoadDefaults()
func testSettingsPersistChangedValues()
func testSettingsIgnoreInvalidStoredValues()
func testHistoryAggregatesSessionsByDay()
func testHistoryIgnoresShortSessions()
func testHistoryEvictsEntriesOlderThanNinetyDays()
func testHistoryFallsBackWhenStoredDataIsMalformed()
```

- [ ] **Step 2: Run tests to verify RED**

Run: `swift test --disable-sandbox --filter 'AppSettingsTests|PostureHistoryStoreTests'`

Expected: FAIL because persistence types do not exist.

- [ ] **Step 3: Add minimal persistence implementation**

Use `UserDefaults` injection in initializers so tests can use isolated suites. Encode history as JSON `Data` in UserDefaults.

- [ ] **Step 4: Run tests to verify GREEN**

Run: `swift test --disable-sandbox --filter AppSettingsTests`

Run: `swift test --disable-sandbox --filter PostureHistoryStoreTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/NoSlouch/Persistence Tests/NoSlouchTests/AppSettingsTests.swift Tests/NoSlouchTests/PostureHistoryStoreTests.swift
git commit -m "Add tested persistence"
```

### Task 4: Minimal App Shell

**Files:**
- Modify: `Sources/NoSlouch/NoSlouchApp.swift`
- Create: `Sources/NoSlouch/MenuBarView.swift`
- Create: `Sources/NoSlouch/PostureViewModel.swift`
- Create: `Sources/NoSlouch/Motion/HeadMotionReading.swift`
- Create: `Sources/NoSlouch/Motion/HeadMotionProvider.swift`
- Create: `Sources/NoSlouch/Motion/AirPodsMotionProvider.swift`
- Create: `Sources/NoSlouch/Motion/AudioOutputMonitor.swift`
- Create: `Sources/NoSlouch/Alerts/PostureNotifier.swift`

**Interfaces:**
- Consumes: `PostureAnalyzer`, `AppSettings`, `PostureHistoryStore`, `PostureSession`
- Produces: launchable menu-bar app
- Produces protocol: `HeadMotionProvider`
- Produces adapter: `AirPodsMotionProvider`
- Produces adapter: `AudioOutputMonitor` using CoreAudio, not `AVAudioSession`

- [ ] **Step 1: Add app shell files**

Create the thin SwiftUI app, view model, motion provider protocol, Core Motion provider, CoreAudio output monitor, and notifier. Keep UI minimal: state label, Start or Stop button, Calibrate button, threshold setting, and Quit button.

- [ ] **Step 2: Build**

Run: `make build`

Expected: build succeeds.

- [ ] **Step 3: Bundle**

Run: `make bundle`

Expected: `NoSlouch.app` exists and is ad-hoc signed without restricted entitlements by default.

- [ ] **Step 4: Smoke launch**

Run: `make run`

Run: `pgrep -x NoSlouch`

Expected: a process id prints.

- [ ] **Step 5: Commit**

```bash
git add Sources/NoSlouch Makefile Resources/Info.plist NoSlouch.entitlements
git commit -m "Add minimal menu bar app shell"
```

### Task 5: Final Verification

**Files:**
- Modify only if verification exposes a defect.

- [ ] **Step 1: Run full tests**

Run: `make test`

Expected: PASS.

- [ ] **Step 2: Run clean build and bundle**

Run: `make clean`

Run: `make bundle`

Expected: build and bundle succeed.

- [ ] **Step 3: Launch smoke test**

Run: `make run`

Run: `pgrep -x NoSlouch`

Expected: a process id prints.

- [ ] **Step 4: Commit fixes if needed**

If fixes were required:

```bash
git add <changed-files>
git commit -m "Fix NoSlouch MVP verification issues"
```
