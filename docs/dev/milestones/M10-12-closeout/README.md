# M10–M12 closeout — automation, polish, release path

**Status:** complete as LOCAL, UNCOMMITTED working-tree changes (no commits by
instruction; mirrored to the workspace `New changes/` folder).

The original M10 items (F1 onboarding, F2 guided calibration, A1 tilt, A2
drift) all shipped in the PR #16 batch; M11's C1/B3/E3 shipped in M9. This
closeout implements what actually remained of the M7→M12 roadmap.

## Shipped

- **E2 — automation via `noslouch://` URL scheme.** Registered in
  `Resources/Info.plist`; pure `URLCommand.parse`
  (`Sources/NoSlouch/URLCommandRouter.swift`) handles
  `start` / `stop` / `calibrate` / `resume` / `snooze?minutes=N` (default 15,
  non-positive rejected); `PostureViewModel.handle(_:)` applies them; delivery
  via `onOpenURL` on the menu-bar label. Works from Shortcuts ("Open URL"),
  Raycast, or `open "noslouch://snooze?minutes=30"`.
  *App Intents/Siri phrasing is deliberately out of scope*: `swift build`
  cannot run the App Intents metadata extractor, so that needs the same
  Xcode-project migration as WidgetKit (E1).
- **F3 — About window + icon fix.** `AboutView` (name, tagline, bundle
  version, automation cheat-sheet, privacy line) behind an "About NoSlouch"
  button; found and fixed the missing `CFBundleIconFile` — `AppIcon.icns` was
  copied into the bundle but never referenced, so the app had no icon.
- **F4 — release path.** `make dmg` (bundle → `dist/` layout with an
  `/Applications` symlink → UDZO image) and `make notarize` (guarded on
  `SIGN_IDENTITY`, notarytool keychain profile, staples on success);
  `docs/dev/RELEASE.md` is the runbook.
- **NB-6 — resolved by decision.** Distribution channel is a
  Developer-ID-signed, notarized DMG, *not* the Mac App Store — so the App
  Sandbox never applies and the `system_profiler` battery widget stays.
  Documented in RELEASE.md.
- **BUG-2 — closed.** `airPodsActive` → `isHeadphoneOutput` across the
  protocol, monitor, ViewModel, and all tests (83 occurrences); the functional
  half (motion-availability guard) had already shipped in PR #16.
- **Sparkle auto-update — deferred, on record.** It would be the first
  third-party dependency; needs explicit sign-off per STANDARDS §2.6.

## Verification (2026-07-04)

`make lint` exit 0; zero build warnings; **153 tests, 0 failures** (+7: URL
router ×6, ViewModel URL-command drive ×1), via
`--scratch-path /tmp/noslouch-scratch`. The dmg recipe was exercised
end-to-end (ad-hoc): `NoSlouch.dmg` created; the bundled Info.plist verifiably
carries `CFBundleURLTypes` (`noslouch`) and `CFBundleIconFile` (`AppIcon`).
Needs manual passes on a real install: URL commands from Shortcuts, About
window, B3 banner buttons; `make notarize` is untestable here (no Developer ID
certificate on this machine).
