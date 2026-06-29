# NoSlouch

A dependency-free macOS 14+ menu-bar app that monitors your posture using AirPods head-motion data and nudges you when you slouch.

## Features

- Detects slouching via AirPods headphone motion (CoreMotion pitch angle)
- Menu-bar status indicator with real-time posture state
- Customizable alert threshold, hold time, and recovery time
- Audible nudges with named system sound picker and preview
- Speech alerts (optional)
- Per-session stats: bad seconds, good seconds, and slouch event count
- 60-second live deviation chart in the popover
- Device name shown in connection status (e.g. "AirPods Pro connected")
- Launch at login toggle
- 90-day session history stored locally
- No external dependencies; pure Swift

## Requirements

- macOS 14.0+
- AirPods (or AirPods Pro/Max) for live motion data
- Developer ID certificate for signed builds with the `com.apple.developer.coremotion.headphone-motion-data` entitlement; ad-hoc builds work for local development but cannot receive AirPods motion data

## Build and run

```bash
make run          # build + bundle + open the app
make bundle       # build + assemble NoSlouch.app with ad-hoc codesign
make build        # swift build only
make test         # run the test suite
make lint         # check formatting
make format       # auto-fix formatting
make clean        # remove .build/ and NoSlouch.app
```

All `swift build` and `swift test` calls require `--disable-sandbox`, which the Makefile applies automatically.

## Architecture

The entry point is `NoSlouchApp.swift`. All coordination flows through `PostureViewModel`, the single `@StateObject` owned by the app.

```
AirPodsMotionProvider  --onReading-->  PostureViewModel  --pitch-->  PostureAnalyzer
                                              |                           |
AudioOutputMonitor  --onChange-->            |          <--PostureState--+
                                             |
                                    PostureNotifier  (nudge / sound / speech)
                                    PostureHistoryStore  (session -> daily aggregate)
                                    AppSettings  (UserDefaults)
```

Key components:

| File | Role |
|---|---|
| `PostureAnalyzer.swift` | Pure struct; computes posture state from pitch samples |
| `PostureViewModel.swift` | Coordinates all subsystems; owns cooldown logic and session stats |
| `PostureNotifier.swift` | Fires nudges (notification, sound, speech) on every call |
| `AudioOutputMonitor.swift` | Tracks active audio output device and exposes its name |
| `AirPodsMotionProvider.swift` | Streams headphone motion data from CoreMotion |
| `AppSettings.swift` | Persists user preferences to UserDefaults |
| `PostureHistoryStore.swift` | Aggregates sessions into daily records; 90-day cap |
| `PostureSession.swift` | Model for a single session (bad/good seconds, slouch events) |
| `PostureChartView.swift` | 60-second sliding deviation chart using Swift Charts |
| `MenuBarView.swift` | Popover UI: status, stats, chart, primary actions |
| `SettingsView.swift` | Settings window (Cmd+,): all AppSettings fields |

## Milestones

### M1 - Settings/Preferences UI (done)

Dedicated Settings window (Cmd+,) exposing all `AppSettings` fields. The menu-bar popover was slimmed to status and primary actions only.

### M2 - UX improvements (done)

- Deviation value in notification body: "Your head dropped N below your baseline."
- Device name in connection status: shows "AirPods Pro connected" instead of generic "Ready".
- Launch at login via `SMAppService`.

### M3 - Richer session stats (done)

Per-session `goodSeconds` and `slouchEvents` tracked alongside `badSeconds`. All three are shown as live tile stats in the popover and persisted to `PostureHistoryStore`.

### M4 - Live chart and sound picker (done)

- 60-second sliding pitch/deviation chart rendered with `Charts.LineMark` and a dashed `RuleMark` at the alert threshold.
- Named system sound picker (Funk, Glass, Ping, etc.) with a preview button, replacing the plain sound on/off toggle.

## Testing

```bash
make test
swift test --disable-sandbox --filter PostureAnalyzerTests
swift test --disable-sandbox --filter PostureViewModelTests/testSustainedDropBecomesBad
```

Tests use fakes for hardware dependencies (`FakeHeadMotionProvider`, `FakeAudioOutputMonitor`, `FakePostureNotifier`) and isolated UUID-named `UserDefaults` suites to prevent cross-test contamination.

## License

See [LICENSE](LICENSE).
