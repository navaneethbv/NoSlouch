# NoSlouch

A macOS menu-bar app that uses AirPods head-motion data to detect forward-head posture and nudge you when you slouch.

## Requirements

- macOS 14.0 or later
- Xcode 15 or later (for building from source)
- AirPods or Beats Fit Pro set as your Mac's audio output device
- An Apple Developer account with the `com.apple.developer.coremotion.headphone-motion-data` entitlement for live motion data (see note below)

## Quick start

```bash
git clone https://github.com/navaneethbv/NoSlouch.git
cd NoSlouch
make run
```

`make run` builds the app, assembles the bundle, signs it ad-hoc, and opens it. The menu-bar icon appears immediately.

## Using the app

1. Put on your AirPods and set them as your Mac's audio output (the app checks this and will prompt you if they are not active).
2. Click the menu-bar icon and press **Start**.
3. Sit upright and press **Calibrate** to record your baseline head position.
4. The app monitors your pitch angle in real time. If you hold a forward-head angle above the threshold for more than a few seconds, it plays a sound and sends a notification.
5. Press **Stop** when done. Each session is saved to daily history.

**Threshold** and **Reminder interval** can be adjusted with the steppers in the menu. **Invert pitch** is for users who wear AirPods with the stems pointing up.

After three ignored nudges in a row, reminders pause for 10 minutes automatically.

## A note on the motion entitlement

`CMHeadphoneMotionManager` requires the `com.apple.developer.coremotion.headphone-motion-data` entitlement to return data. Ad-hoc signed builds (the default with `make run`) do not embed this entitlement because macOS will kill an ad-hoc binary that declares a restricted entitlement.

To get live AirPods motion data, sign the bundle with a Developer ID certificate:

```bash
make bundle SIGN_IDENTITY="Developer ID Application: Your Name (XXXXXXXXXX)"
open NoSlouch.app
```

Without a valid signing identity, the app still launches and all UI controls work, but the motion provider will report no readings.

## Development

```bash
make build      # compile only
make test       # run all unit tests
make lint       # check formatting (swift-format)
make format     # auto-fix formatting in place
make bundle     # build + assemble NoSlouch.app
make clean      # remove .build/ and NoSlouch.app
```

Run a single test suite:

```bash
swift test --disable-sandbox --filter PostureAnalyzerTests
```

All testable logic (posture analysis, persistence, settings, view model behavior) runs without AirPods or hardware access. The `Tests/` directory uses injected fakes for motion and audio monitoring.
