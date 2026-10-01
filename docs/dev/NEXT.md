# Current work

M14 implements tracking accuracy, recovery, guided calibration, diagnostics, profiles, measured-duration goals, and release hardening.
M15 adds opt-in startup monitoring, test notifications, and recovered-session notices.
See [M15 verification](milestones/M15-startup-alert-check/README.md) for the current combined build.
See [the M14 acceptance record](milestones/M14-tracking-recovery/README.md) for verification results and limitations.

M1 through M13 are implemented in the repository.
Earlier planning documents describe historical proposals, not an outstanding feature checklist.

## Release acceptance

- Exercise motion permission denial/recovery, real AirPods disconnect/reconnect, sleep/wake, and battery reporting on physical hardware.
- Verify installed notification actions and audible output with macOS notifications enabled.
- Produce a Developer ID signed and notarized DMG, then test Gatekeeper on a clean account or machine.
- Hosted checks and review policy apply only when a PR is submitted.

## Deliberate future decisions

Background auto-update and App Intents remain separate platform decisions.
The current update path opens the releases page from About.
The existing URL scheme supports automation without an Xcode-project migration.
Cloud sync and telemetry remain outside the product's architecture.
