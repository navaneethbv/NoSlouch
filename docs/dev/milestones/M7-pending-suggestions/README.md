# M7 — Pending Suggestions (polish + remaining features)

**Goal:** Complete the countdown, callback-thread consistency, and hourly history improvements.
The completed suggestion list has been removed; the phase records below retain its implementation criteria.

**Status:** done

**Depends on:** M6 (meetings, breaks, dashboard aesthetics) — merged via PR #12.

**Exit criteria:**
- The snooze/auto-pause status text shows live remaining time, not a static label. (done)
- `AirPodsMotionProvider` dispatches all outbound callbacks on the main queue (consistency with the other monitors). (done)
- The History window offers an intraday (hourly) view of slouch activity, backed by hourly data the store now retains. (done)

## Architecture references

- `docs/architecture.md` — coordinator/provider/notifier split.
- `CLAUDE.md` — snooze vs auto-pause semantics, the reading clock (`lastReadingAt`), the two-tier settings rule, and `PostureHistoryStore` daily aggregation.

## Phases

| #  | Phase                                                                              | Status |
|----|------------------------------------------------------------------------------------|--------|
| 01 | snooze/pause countdown ([phase-01-snooze-pause-countdown.md](phase-01-snooze-pause-countdown.md)) | done   |
| 02 | callback thread-safety cleanup ([phase-02-callback-thread-safety.md](phase-02-callback-thread-safety.md)) | done |
| 03 | intraday posture heatmap ([phase-03-intraday-heatmap.md](phase-03-intraday-heatmap.md)) | done |

All phases are complete.

## Later delivery

The previously deferred battery monitor and guarded auto-drift calibration are implemented.
Battery information is read through `system_profiler`; this does not require the private BluetoothManager framework proposed in the original discussion.
Use [current work](../../NEXT.md) and [M14 acceptance](../M14-tracking-recovery/README.md) for remaining hardware and release gates.

## Notes

Milestone numbering continues the `README.md` feature-milestone sequence (M1–M6 are documented there; M6 shipped in PR #12). The formal `docs/dev/milestones/` tree previously only contained M1; M2–M6 were built outside the phase-doc flow. M7 resumes the formal architect/executor flow.

### Review verdict — phase-01 — 2026-06-30

- **Verdict:** approved (implemented directly after executor bounces)
- **Bounces:** 2 — qwen3.6:35b-mlx hard-failed twice (`IdenticalToolCallRepetition`
  after a malformed `...` edit; then `StuckGateFeedback` with no edit on the
  whole-function-replace spec).
- **Executor:** Claude Code (direct), per project-owner decision.
- **Scope deviations:** none.
- **Calibration:** first data points for `qwen3.6:35b-mlx` on this repo — it could
  not complete a trivial 2-line Swift change. One occurrence is data; watch
  whether this recurs before concluding the model is unsuitable as executor. Also
  surfaced an environment bug: the MCP server's launch CWD was the parent of the
  project, so `--config ./rexymcp.toml` missed and the server defaulted to
  `localhost:1234`; worked around with a config shim at the server CWD. The clean
  fix is to open the workspace at the project root (the inner `NoSlouch/NoSlouch`).

<!-- Retrospective written here at milestone close. -->
