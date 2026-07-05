# Next

**Active phase:** none — the M7→M12 roadmap is fully implemented.

Everything through the M10–12 closeout (automation URL scheme, About/icon,
`make dmg`/`make notarize` release path) exists as **local, uncommitted**
working-tree changes on branch `m8-hardening` (M8 is committed on that branch,
unmerged; M9 and M10–12 are uncommitted on top, all mirrored to the workspace
`New changes/` folder). See `docs/dev/milestones/M9-engagement/` and
`docs/dev/milestones/M10-12-closeout/`.

## Outstanding (all deliberate, none blocking)

- **Merge/commit decision** — M8 branch → main; commit M9 + M10-12 batches
  (currently no-commit by instruction).
- **Real-device manual passes** — battery JSON on real AirPods, onboarding on
  a fresh account, B3 banner buttons, `noslouch://` from Shortcuts, About
  window, Gatekeeper on the DMG.
- **Developer ID certificate** — the only gate left for a real release
  (`docs/dev/RELEASE.md`).
- **Sparkle auto-update** — deferred; first third-party dependency, needs
  sign-off.
- **Xcode-project migration** — unlocks App Intents/Siri (E2 full) and
  WidgetKit (E1); a build-infra decision, not a feature.

Backlog beyond the roadmap: `docs/dev/improvements.md` §11 round-2 features
(K1 calibration profiles, H2 focus sessions, D4 guided stretches, J4 session
replay, K4 overlay, J3 HealthKit) and `docs/dev/CLEANUP_AND_IDEAS.md` Part 2
(time-of-day adaptive sensitivity, sit/stand awareness).
