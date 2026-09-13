# MoneyTracker (iOS)

The native iPhone version of MoneyTrack (SwiftUI + SwiftData, iOS 26). It has the same
features and the same numbers as the web app, V11.8.

Open `MoneyTracker.xcodeproj` (scheme `MoneyTracker`, bundle id `com.patel.MoneyTracker`).
Sources live in `MoneyTracker/`. See `docs/architecture.md`.

- **Bank sync:** the same account as the web app. Bank data and learning sync through the cloud.
- **Hand-entered data:** moved with the web app's JSON backup (Settings → Restore), both ways.
- **Docs for both apps** (purpose, rules, recent work, to-do): `core.md`, `update.md` and
  `todo.md` in the web repo (`~/Documents/Moneytracker`, GitHub
  `meet-p-dev/refactored-octo-tribble`, branch `source`). Rules for this repo: `CLAUDE.md`.
- **Legal:** [Privacy policy](https://meet-p-dev.github.io/refactored-octo-tribble/legal/privacy.html) ·
  [Terms of use](https://meet-p-dev.github.io/refactored-octo-tribble/legal/terms.html).
  They're hosted by the web app and cover both apps.

Separate from Heimat, which is its own product and repo.
