# M15: Startup monitoring and alert checks

## Scope

Add opt-in monitoring at app launch, an explicit test notification, and a visible recovered-session notice.
Preserve M14 changes and existing user files.

## Acceptance

- Startup monitoring defaults off and does not run before onboarding completes.
- Startup waits for supported headphones and can be canceled while waiting.
- Explicit Stop cancels pending startup and interruption resume for the current launch.
- Disabling the startup preference cancels pending startup without interrupting a session already started.
- The test notification refreshes authorization, respects sound/speech settings, and does not change posture state, session history, or nudge cooldowns.
- Successful notification scheduling is described as submission, not guaranteed display.
- Scheduling failure and denied permission provide actionable feedback.
- Recovered-session notices are dismissible without changing history and clear with history deletion.

## Verification

Local implementation and verification completed on 2026-10-01.
This batch and M14 are submitted together in [PR #25](https://github.com/navaneethbv/NoSlouch/pull/25) against `main`.

- `make test`: 191 tests passed, zero failures.
- `make lint` and `make build`: passed with no compiler warnings.
- `make dmg`: optimized arm64 build, hardened runtime, strict code-signature verification, and plist validation passed.
- `hdiutil verify`: valid image checksum.
- Mounted the DMG read-only, verified the bundled app signature, compared its executable byte-for-byte with the built app, and detached successfully.
- `graphify update .` and `git diff --check`: passed.
- Follow-up cleanup extracts shared test setup, simplifies notification callbacks, removes an unused parameter, and makes the releases URL a bundle setting.
- Re-ran all 191 tests, lint, release packaging, and mounted-artifact checks after this cleanup.
- M14's independent JSON/CSV recovery verification remains applicable; the persistence format is unchanged in M15.

New tests cover startup opt-in/setup gates, late headphone availability, pending-start cancellation, disabling the preference, denied motion permission, notification permission refresh, scheduling failure, duplicate-click suppression, recovery-notice dismissal, and test-notification content isolation.

## Limits

Native computer-use access was rejected with `Computer Use was not approved to use NoSlouch` despite session authorization.
Native layout, keyboard/VoiceOver behavior, audible notification delivery, and physical AirPods behavior remain unverified.
The test-notification success message means macOS accepted scheduling, not that a banner was visibly delivered.
This follows [Apple's scheduling completion semantics](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/add(_:withcompletionhandler:)).

The Mac has zero valid code-signing identities, so Developer ID signing, notarization, secure timestamp, and clean-machine Gatekeeper acceptance remain separate release gates.
The local DMG is ad-hoc signed, not a public notarized release.
The host emits a deprecation warning for `hdiutil`; mounted-artifact checks passed.

## Artifacts

- App: `NoSlouch.app`.
- DMG: `NoSlouch.dmg`.

- DMG SHA-256: `9f00d55b8d92f90d3d9994883495fa9446356c2ee93e00e7d79a71e7cb770673`.
- Executable SHA-256: `b3b7bddd4aa9e08259aed8941767d7abe6d1cd5160cfa2d04b0cb97ce3d994d2`.
