# Phase 02: Callback thread-safety cleanup

**Milestone:** M7 — Pending Suggestions
**Status:** done
**Depends on:** Phase 01
**Estimated diff:** ~20 lines
**Tags:** language=swift, kind=refactor, size=s

## Goal

Consolidate all outbound callbacks of `AirPodsMotionProvider` onto the main thread/queue and resolve any potential data races on `lastReadingAt` between the background motion updates and main-thread `stop()` resets.

## Architecture references

Read before starting:

- `CLAUDE.md` — "Motion callbacks arrive on a background `OperationQueue` inside `AirPodsMotionProvider` and are dispatched to the main thread by the ViewModel before any state mutation."

## Spec

1. **Dispatch outbound callbacks in `AirPodsMotionProvider` onto `DispatchQueue.main.async`**:
   - Wrap the invocation of `onReading`, `onError`, and `onConnectionChanged` in `DispatchQueue.main.async`.
   - Perform the `lastReadingAt` throttle check and mutation exclusively on the main queue to resolve potential data races with `stop()` (which resets it to `nil`).

2. **Wrap connection status updates**:
   - In `CMHeadphoneMotionManagerDelegate` methods (`headphoneMotionManagerDidConnect` and `headphoneMotionManagerDidDisconnect`), wrap the `onConnectionChanged` calls in `DispatchQueue.main.async`.

## Verification

- Ensure all formatting is strict and builds compile cleanly.
- Ensure all unit tests run and pass.
