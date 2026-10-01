# Release runbook

NoSlouch distributes outside the Mac App Store as a Developer ID signed, notarized DMG.
The battery monitor uses `system_profiler`; the app does not enable App Sandbox.
Updates are manual downloads from the About window's Check for Updates link.

## Build and local verification

```sh
make lint
make build
make test
make release-bundle
make dmg
```

`make bundle` uses a debug build for development.
`make release-bundle` and `make dmg` use `--configuration release` and `/tmp/noslouch-release-build`, avoiding the iCloud-synced checkout's build database.
Both signing paths enable hardened runtime.
Ad-hoc builds validate local structure and signatures but do not prove live motion, trusted distribution, or notarization.
Do not distribute them as notarized releases.

## Signed release

Have a Developer ID Application certificate available for `com.noslouch.app`.
The existing `NoSlouch.entitlements` configuration is retained; verify its validity with the signing setup and physical hardware before distribution.
Apple documents `NSMotionUsageDescription` and availability checks for [headphone motion](https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager).
Do not infer motion support or entitlement requirements from an ad-hoc signature check alone.
Store notary credentials in Keychain with `xcrun notarytool store-credentials noslouch-notary`.
Keep passwords and signing credentials out of the repository and logs.
Bump the version and build in `Resources/Info.plist` for an actual release.

```sh
make notarize SIGN_IDENTITY='Developer ID Application: <name> (<team>)'
```

The signed path enables hardened runtime, embeds the entitlement, and requests a secure timestamp.
The target submits the DMG, staples and validates the ticket, and assesses the application with Gatekeeper.
Inspect the notary log if submission fails.
Verify the final app's entitlement, timestamp, and architectures using `codesign --display --entitlements - --verbose=4 NoSlouch.app` and `lipo -archs NoSlouch.app/Contents/MacOS/NoSlouch`.
The current build targets the build machine's architecture; publish architecture-specific artifacts or deliberately configure a universal build.

## Installed-app acceptance

- Test first-run setup, denied motion access, permission recovery, stable calibration, and unstable-calibration rejection.
- Test startup monitoring with headphones initially absent, permission denied, and the pending start canceled.
- Submit a test notification from Settings, check scheduling feedback, and verify that posture statistics are unchanged.
- After recovering an interrupted session, dismiss the recovery notice and confirm history is retained.
- Test AirPods removal, reconnect, output-route change, Mac sleep/wake, explicit Stop, and both resume settings.
- Verify sound off, selected sound, speech, escalation, quiet hours, meeting mute, snooze, and notification actions.
- Verify history across midnight and after away periods; export and inspect CSV independently.
- Verify recovery after force quitting with disposable data, and confirm Clear History remains empty after relaunch.
- Verify keyboard navigation, VoiceOver names, scrolling, and window readability.
- Verify battery reporting and run Gatekeeper on a clean account or machine.

## Data compatibility

History now uses an atomic versioned file in Application Support.
The app writes legacy UserDefaults mirrors so older builds can read measured totals after a rollback.
An older build does not maintain the new canonical snapshot, so export before downgrading and do not expect sessions recorded by the older app to merge automatically on re-upgrade.
Legacy estimates remain estimates; exact attribution applies to newly measured intervals.
