# M13: Tracking and history reliability

**Scope:** a focused maintenance batch authorized by the repository improvement request.
**Status:** implemented; local verification complete except native visual interaction, hosted checks pending.

## Behavior and acceptance

- Invalid sensor values cannot enter calibration or advance accounting.
- Duplicate and backward timestamps during monitoring cannot change posture, calibration samples, or totals.
- Returning from away starts a fresh accounting interval and clears detector hold/recovery timers.
- Initial microphone and away states are honored without waiting for a change callback.
- Repeated daylight-saving hours remain distinct after persistence and reload.
- Clear History requires confirmation and stops monitoring, discards the active session, and removes daily/hourly history plus corrupt-data recovery backups.
  Settings and calibration remain intact.
  Subsequent stop/quit cannot restore the deleted session.
- Failed CSV exports present the operating system's error instead of only a beep.

No dependencies, persisted formats, release settings, or external APIs are added.
The existing history keys and legacy migration remain compatible.
Calendar bucketing uses the containing hour interval described in [Apple's Calendar documentation](https://developer.apple.com/documentation/foundation/calendar/dateinterval(of:for:)).

## Verification

Four regression reproductions failed before the fixes with 13 assertions covering invalid samples, reversed timestamps, away transitions, and the repeated hour.
Local verification: all 161 tests pass, `make lint` and `git diff --check` pass, and `make bundle` succeeds.
The app passes `codesign --verify --deep --strict` and its Info.plist passes `plutil -lint`.
The bundle is ad-hoc signed, not notarized or released.
The eight new tests cover sensor validation, reading order, away gaps, initial provider states, DST persistence/reload, and history deletion/reload.
`graphify update .` completed successfully; generated outputs remain ignored.

Native UI automation could not run: the tool returned `MCP tool call requires approval, but approval policy is never`.
A manual pass remains for confirmation cancellation/deletion, keyboard focus, History layout, and CSV export error presentation.
Hardware tests use injected providers and do not establish real AirPods connectivity.

## Update log

- 2026-09-26: implemented the scoped fixes and deletion workflow; added regression and reload coverage.
