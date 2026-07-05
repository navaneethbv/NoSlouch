# Release runbook (F4)

How a NoSlouch build gets into users' hands, and the decisions behind it.

## Distribution decisions (made 2026-07-04)

1. **Channel: Developer-ID-signed, notarized DMG.** Not the Mac App Store.
   - The App Store requires the App Sandbox, and `AirPodsBatteryMonitor`
     shells out to `system_profiler`, which the sandbox forbids (**NB-6**).
     Choosing the DMG channel *resolves NB-6 by decision*: the battery widget
     stays, and the constraint is documented here and in the monitor's source.
   - The `com.apple.developer.coremotion.headphone-motion-data` entitlement
     only embeds for real (non-ad-hoc) signing, so a Developer ID certificate
     is the gating dependency for live AirPods motion in any distributed build.
2. **Auto-update: deferred.** The only realistic non-Apple path is Sparkle,
   which would be this project's **first third-party dependency** — that needs
   explicit principal-engineer sign-off (STANDARDS §2.6). Until then, releases
   are manual DMG downloads.

## Prerequisites (once)

1. An Apple Developer Program membership with a **Developer ID Application**
   certificate in the login keychain.
2. A provisioning setup that includes the headphone-motion entitlement for
   `com.noslouch.app` (Apple grants this restricted entitlement per-identifier).
3. Notary credentials stored once:
   `xcrun notarytool store-credentials noslouch-notary --apple-id <id> --team-id <team>`

## Cutting a release

```bash
# 1. Bump CFBundleShortVersionString / CFBundleVersion in Resources/Info.plist.
# 2. Green gate:
make lint && make build && make test
# 3. Signed, notarized, stapled DMG:
make notarize SIGN_IDENTITY='Developer ID Application: <name> (<team>)'
# 4. Sanity-check on a clean machine/account: Gatekeeper accepts the DMG,
#    AirPods motion works (entitlement embedded), battery widget populates.
```

`make dmg` alone (ad-hoc signing) is fine for local testing but ships neither
the motion entitlement nor a Gatekeeper-acceptable signature.

## Known caveats to re-verify on each release

- Battery widget parses `system_profiler -json` — best-effort; hidden when the
  data is missing.
- Notification banner actions (B3) and the `noslouch://` URL scheme need the
  real bundle; both should get a manual pass from the installed app.
- The repo's iCloud-synced location can corrupt `.build/build.db` and reuse
  stale binaries — build releases with a scratch path outside `~/Desktop`
  (e.g. `swift build --scratch-path /tmp/noslouch-release`) or from a
  non-iCloud checkout.
