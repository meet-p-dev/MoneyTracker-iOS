# MoneyTracker iOS — rules for any session in this repo

**Read first:** `~/Documents/Moneytracker/core.md` (purpose + hard rules for BOTH apps),
then `~/Documents/Moneytracker/update.md` and `~/Documents/Moneytracker/todo.md`. Those
shared docs live in the web repo (GitHub `meet-p-dev/refactored-octo-tribble`, branch
`source`). Add today's work to `update.md` there after each session.

## What this is
The native iPhone version of MoneyTrack: SwiftUI + SwiftData, iOS 26 SDK (Xcode 26),
deployment target 26.5. It has feature parity with web V11.8. Bundle id
`com.patel.MoneyTracker`, team `Q3BTHLU74C`. GitHub: `meet-p-dev/MoneyTracker-iOS`
(private), branch `main`. The file map is in `docs/architecture.md`.

## Build, run, verify
- Simulator build:
  `xcodebuild -scheme MoneyTracker -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
- Screenshots: `xcrun simctl io <udid> screenshot out.png` (the simulator tool's own
  screenshot can fail). Right after launch, a TipKit popover swallows the first tap.
- The user's iPhone:
  `xcodebuild -scheme MoneyTracker -destination 'generic/platform=iOS' -allowProvisioningUpdates -derivedDataPath <dir> build`,
  then `xcrun devicectl device install app --device <id> <dir>/Build/Products/Debug-iphoneos/MoneyTracker.app`.
  Get `<id>` from `xcrun devicectl list devices`.
- `Core/` is plain Swift (no SwiftUI). To check maths, compile it with `swiftc` plus a
  `main.swift` harness in a scratch folder and compare against a real web backup and the
  web's JS (`node`). Never commit the backup or its output.

## Rules (on top of core.md)
- **The web app is the reference for numbers.** `Core/Classifier.swift`, `CardMath.swift`,
  `Merchants.swift` and `Ledger.swift` are line-for-line ports of the web's `lib/*.js`. Change
  them together and re-verify. `Core/JSRegex.swift` emulates JavaScript's ASCII `\b`, so
  keep patterns identical to the web's.
- **Cloud:** only `mt_*` tables and `app_users` with `app='moneytrack'`. Never Heimat's tables.
- **Design:**
  - Glass is only for chrome (tab bar, floating buttons). Content cards stay solid.
  - Use the tokens in `UI/Theme.swift` (radii 20/12, the web's colours).
  - Plain short copy, no em-dash sentences, no sparkles, glows or extra tips.
  - No balance-over-time charts and no Recurring (both removed on the user's request).
- **Project settings:** `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`. The folder groups are
  synchronized, so any new `.swift` file under `MoneyTracker/` is included automatically.
  Plain-Swift types used off the main actor need `nonisolated`.
- The user signs in to bank sync themselves. Never type their password.
- Commit and push only when asked (`git push` → `origin main`).
- Legal pages are hosted by the web app (`/refactored-octo-tribble/legal/privacy.html` and
  `terms.html`) and linked in Settings → Legal.
