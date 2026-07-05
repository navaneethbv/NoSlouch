# M8 — Data Integrity & Hardening

**Status:** phase-01 complete (pending review)

The 2026-07-01 post-PR-#16 review (`docs/dev/improvements.md` §10.6, NB-11 …
NB-30) found that the analytics shipped in PR #16 (streaks, grades, digest,
hourly chart) sit on data that several bugs corrupt, plus one HIGH-severity
deadlock. M8 fixes the foundation before any new features build on it.

| Phase | Scope | Status |
|---|---|---|
| phase-01 | The full NB-11 … NB-30 hardening batch | complete |

Deliberately NOT addressed in M8 (unchanged from the review):

- **NB-6** — `system_profiler` shell-out is incompatible with App Sandbox.
  Inherent to the approach; documented in `AirPodsBatteryMonitor.swift`. Decide
  at distribution time (F4).
- **BUG-2 (naming half)** — `airPodsActive` is still true for any Bluetooth
  output. The functional half (motion-availability guard) shipped in PR #16;
  the rename is cosmetic and left for a cleanup pass.
