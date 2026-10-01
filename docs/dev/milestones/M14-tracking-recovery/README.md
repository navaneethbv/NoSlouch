# M14: Accurate tracking, recovery, and release readiness

## Scope

Fix sensor gaps, stale calibration, time attribution, sound settings, crash recovery, retention, and release packaging.
Add connection diagnostics, guided calibration, opt-in automatic resume, measured-duration goals, calibration profiles, and a manual release-check entry point.
Extract interval accounting and reminder scheduling into independently testable components.
Consolidate stale architecture and roadmap guidance.

## Acceptance

- Reject sensor gaps over two seconds from measured time and reset hold/recovery state.
- Require fresh connected readings for calibration and stable samples for the guided flow.
- Attribute measured intervals and events to their actual hours and days, including DST.
- Persist a single recovery snapshot at most every 15 seconds during tracking and on interruptions.
- Recover checkpoints once, retain 90 calendar days, and clear all history/recovery formats together.
- Require 20 measured minutes by default for daily grades/goals and sustained-day achievements.
- Resume only with explicit opt-in and an interrupted monitoring intent; explicit Stop cancels that intent.
- Build optimized, hardened-runtime release artifacts and validate signatures.
- Run lint, build, tests, bundle verification, and available native UI checks.

## Verification

Implementation completed locally on 2026-10-01.
M14 and M15 are prepared together on `feature/tracking-recovery-startup`.
The results below describe the M14 verification snapshot; see M15 for current combined verification and PR delivery.

- `make test`: 182 tests passed, zero failures.
- `make lint`: passed.
- `make build`: passed with no compiler warnings.
- `make release-bundle` and `make dmg`: passed, using an optimized arm64 build.
- `make verify-bundle`: strict signature validation, hardened-runtime flag check, and plist validation passed.
- `hdiutil verify NoSlouch.dmg`: checksum valid.
- Mounted the DMG read-only, verified the bundled app signature, compared its executable byte-for-byte against the built app, and detached it successfully.
- An independent Swift harness wrote and reloaded the recovery file; Python then validated JSON, CSV, midnight attribution, no duplicate totals, and owner-only `0600` file permissions.
- `git diff --check`: passed.
- `graphify update .`: AST graph updated without API use.

The baseline had 161 passing tests.
The new coverage includes short/long sensor gaps, stale calibration, guided stability/timeout, reconnect intent, midnight and DST, checkpoint reload/commit/clear, sparse calendar retention, write failure, minimum-duration goals, reminder deferral, profiles, and settings round trips.
Legacy reminder tests explicitly inject their coarse sampling policy and clocks; production uses the two-second limit.

## Artifacts

The current combined app and DMG are documented in [M15 verification](../M15-startup-alert-check/README.md).
The independent persistence artifacts remain at `/private/tmp/noslouch-artifact-review/history.json` and `history.csv`.

## Verification limits

The native computer-use tool rejected the app with `Computer Use was not approved to use NoSlouch` despite session authorization.
Native screen layout, keyboard/VoiceOver behavior, notification actions/audio, and physical AirPods behavior are therefore unverified.
No alternate UI-control mechanism was used to bypass that rejection.

`security find-identity -v -p codesigning` reported zero valid identities.
Developer ID signing, notarization, secure-timestamp verification, and clean-machine Gatekeeper acceptance remain blocked by that missing identity and release environment.
The locally verified artifact is ad-hoc signed and must not be presented as a notarized release.
The host emits a deprecation warning for `hdiutil`; the image was nevertheless independently mounted and verified.

The manual update link is implemented; a background updater remains a separate architecture decision.
Legacy history retains its historical estimates, while new measurements have exact interval attribution.
Checkpoints bound normal crash loss to the time since the latest successful save, normally up to 15 seconds.
