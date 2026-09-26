# Next

**Active phase:** tracking and history reliability, prepared for PR review.

The M8 through M12 work shipped in PR #19.
The previous notes describing local, uncommitted batches are historical and no longer describe the repository.
The current batch is documented in [M13 reliability](milestones/M13-reliability/README.md).

## Current batch

- Reject non-finite and out-of-order motion readings before they affect calibration, charts, or accounting.
- Reset accounting and detector timers at away transitions and honor initial microphone/away states.
- Preserve distinct history buckets during a repeated daylight-saving hour.
- Add confirmed history deletion, including recovery backups and the active session.
- Show CSV export errors and disable export when saved history is empty.

## Remaining verification and release gates

- Native History window interaction, keyboard focus, and export error presentation need a manual pass because native UI automation is unavailable in this environment.
- Real AirPods motion, battery reporting, notification actions, and Gatekeeper need physical-device/release testing.
- Developer ID signing and notarization remain separate from this source-code PR.
- GitHub requires one approving review before a normal merge to `main`.

## Follow-up work

- History still distributes a session's measured posture time proportionally across its wall-clock span.
  Exact attribution around away periods requires recording interval-level data rather than session totals.
- Today's live score currently includes the whole active session, including a session begun before midnight.
- Sparkle auto-update and an Xcode-project migration remain deliberate architectural decisions.
- Calibration profiles and focus sessions remain optional backlog items, not prerequisites for this reliability batch.
