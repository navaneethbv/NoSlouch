# NoSlouch

A dependency-free macOS 14+ menu-bar app for desk posture and ergonomics. It reads AirPods head-motion data to detect slouching and nudges you to sit up, reminds you to take stretch breaks, and stays quiet while you are on a call.

## Features

- Detects slouching via AirPods headphone motion (CoreMotion pitch angle)
- Dynamic menu-bar icon that reflects posture state (upright / slouching / snoozed)
- Visual posture-deviation gauge in the popover, with a baseline-to-limit progress bar
- Customizable alert threshold, hold time, and recovery time
- Audible nudges with a named system-sound picker and preview, plus optional speech alerts
- Snooze nudges for 15 / 30 / 60 minutes, independent of the automatic pause
- **Mute in meetings**: automatically pauses all alerts while your microphone is active (uses CoreAudio hardware state, so no microphone-permission prompt)
- **Stretch break reminders** after a configurable amount of monitored time (deferred while muted in a meeting)
- Live 60-second deviation chart with a gradient fill that tracks posture state
- Session stat cards: upright time, slouch count, today's upright score, and session count
- Posture history window: 30-day upright-share bar chart and per-day rows
- Launch at login toggle
- 90-day session history stored locally
- No external dependencies; pure Swift

## Requirements

- macOS 14.0+
- AirPods (3rd gen / Pro / Max) or Beats Fit Pro for live head-motion data
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

```mermaid
flowchart LR
    subgraph inputs ["Data Sources"]
        AMP["AirPodsMotionProvider"]
        AOM["AudioOutputMonitor"]
        MIC["MicrophoneMonitor"]
    end
    subgraph core ["Coordinator"]
        PVM["PostureViewModel"]
    end
    subgraph logic ["Logic"]
        PA["SlouchEngine"]
    end
    subgraph output ["Notifier"]
        PN["PostureNotifier"]
    end
    subgraph persistence ["Persistence"]
        PHS["PostureHistoryStore"]
        AS["AppSettings"]
    end
    subgraph os ["OS Outputs"]
        NC["Notification Center"]
        NS["NSSound"]
        AVS["AVSpeech"]
    end

    AMP -->|"onReading"| PVM
    AOM -->|"onChange (output device)"| PVM
    MIC -->|"onChange (mic active)"| PVM
    PVM -->|"feed pitch"| PA
    PA -->|"state + drop"| PVM
    PVM -->|"nudge / break"| PN
    PVM -->|"write session"| PHS
    PVM <-->|"read / write"| AS
    PN -->|"alert"| NC
    PN -->|"play"| NS
    PN -->|"speak"| AVS
```

Key components:

| File | Role |
|---|---|
| `SlouchEngine.swift` | Pure struct; maps pitch samples to `SlouchState` (unknown/good/bad) |
| `PostureViewModel.swift` | Coordinates all subsystems; owns cooldown, snooze, mute, break, and session-stat logic |
| `PostureNotifier.swift` | Fires posture nudges and break reminders (notification, sound, speech) on every call |
| `AudioOutputMonitor.swift` | Tracks the active audio output device and exposes its name (is an AirPod the output?) |
| `MicrophoneMonitor.swift` | Tracks default-input "running" state to drive mute-in-meetings (no mic permission needed) |
| `AirPodsMotionProvider.swift` | Streams headphone motion data from CoreMotion |
| `AppSettings.swift` | Persists user preferences to UserDefaults |
| `PostureHistoryStore.swift` | Aggregates sessions into daily records; 90-day cap |
| `PostureSession.swift` | Model for a single session (bad/good seconds, slouch events) |
| `PostureChartView.swift` | 60-second sliding deviation chart (gradient area + line) using Swift Charts |
| `HistoryView.swift` | History window: 30-day upright-share bar chart and per-day rows |
| `MenuBarView.swift` | Popover UI: status, deviation gauge, stat cards, chart, snooze, mute indicator, actions |
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

### M5 - History, dynamic icon, snooze, daily score (done)

- Posture History window (`HistoryView`): a 30-day upright-share bar chart plus per-day rows, backed by the existing `PostureHistoryStore`.
- Dynamic menu-bar icon: the `MenuBarExtra` symbol reflects posture state (upright / slouching / snoozed-or-paused).
- Snooze nudges for 15/30/60 minutes from the menu, independent of the automatic 3-strikes pause and not cleared by good posture.
- Today's upright score ("Today: N% upright · M slouches") shown in the menu whether or not a session is active.
- Robustness fixes: no notification prompt on launch (status is refreshed, not requested), the active session is flushed on app termination, and the paused-status text is derived from the pause-duration constant.

### M6 - Meetings, breaks, and dashboard aesthetics (done)

- Mute in meetings: `MicrophoneMonitor` watches the default input's hardware "running" state and, when on, suppresses all alerts while the mic is active. Bad-posture nudges return early; break reminders are deferred (not dropped) until the mic frees up.
- Stretch break reminders: a configurable interval (`breakReminderMinutes`) of accumulated monitored time triggers a "time to stretch" reminder.
- Dashboard aesthetics: a posture-deviation gauge, a grid of session stat cards, and a gradient `AreaMark` under the live chart that follows posture state.
- Settings: toggles for mute-in-meetings and break reminders, plus a break-interval stepper.

## Testing

```bash
make test
swift test --disable-sandbox --filter SlouchEngineTests
swift test --disable-sandbox --filter SlouchEngineTests/testSustainedDropBecomesBad
```

Tests use fakes for hardware dependencies (`FakeHeadMotionProvider`, `FakeAudioOutputMonitor`, `FakeMicrophoneMonitor`, `FakePostureNotifier`) and isolated UUID-named `UserDefaults` suites to prevent cross-test contamination.

## License

See [LICENSE](LICENSE).
