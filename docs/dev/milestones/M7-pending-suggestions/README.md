# M7 — Pending Suggestions (polish + remaining features)

**Goal:** Clear the still-open items tracked in `suggestion.md` that are well-scoped and low-risk, deferring the two that need a product/design decision.

**Status:** in-progress

**Depends on:** M6 (meetings, breaks, dashboard aesthetics) — merged via PR #12.

**Exit criteria:**
- The snooze/auto-pause status text shows live remaining time, not a static label.
- `AirPodsMotionProvider` dispatches all outbound callbacks on the main queue (consistency with the other monitors).
- The History window offers an intraday (hourly) view of slouch activity, backed by hourly data the store now retains.

## Architecture references

- `docs/architecture.md` — coordinator/provider/notifier split.
- `CLAUDE.md` — snooze vs auto-pause semantics, the reading clock (`lastReadingAt`), the two-tier settings rule, and `PostureHistoryStore` daily aggregation.

## Phases

| #  | Phase                                                                              | Status |
|----|------------------------------------------------------------------------------------|--------|
| 01 | snooze/pause countdown ([phase-01-snooze-pause-countdown.md](phase-01-snooze-pause-countdown.md)) | todo   |
| 02 | callback thread-safety cleanup ([phase-02-callback-thread-safety.md](phase-02-callback-thread-safety.md)) | planned |
| 03 | intraday posture heatmap ([phase-03-intraday-heatmap.md](phase-03-intraday-heatmap.md)) | planned |

Phases 02 and 03 are named here for sequencing but their docs are drafted on demand (`/rexymcp:architect next`) after the preceding phase is approved, per the no-auto-advance rule.

## Deferred — need a design decision before they become phases

These two `suggestion.md` items are intentionally NOT scheduled as executor phases yet:

- **AirPods battery monitor.** There is no supported public API for AirPods battery; the only routes are `IOKit`/`IORegistry` spelunking or the private `BluetoothManager` framework. Both break the project's dependency-free, public-API-only stance and carry distribution/notarization risk. Dispatching this to a local LLM would very likely produce non-compiling or rejectable code. Needs an explicit decision: accept the private-API risk, attempt a best-effort IORegistry read, or drop it.
- **Auto-drift / self-calibration.** Safety-sensitive: a naive slow-moving baseline average can drift toward a slouched posture and mask real slouching, defeating the app. Needs a design decision (suggest-recalibration prompt vs bounded auto-adapt, and the guard conditions) before it can be specced tightly enough to dispatch.

## Notes

Milestone numbering continues the `README.md` feature-milestone sequence (M1–M6 are documented there; M6 shipped in PR #12). The formal `docs/dev/milestones/` tree previously only contained M1; M2–M6 were built outside the phase-doc flow. M7 resumes the formal architect/executor flow.

<!-- Retrospective written here at milestone close. -->
