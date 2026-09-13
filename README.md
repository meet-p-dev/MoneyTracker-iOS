# MoneyTracker (iOS)

Native SwiftUI + SwiftData version of the MoneyTrack personal-finance app.

Open `MoneyTracker.xcodeproj` (scheme `MoneyTracker`, bundle id `com.patel.MoneyTracker`).
Sources live in `MoneyTracker/`.

Reads and writes the exact JSON backup of the MoneyTrack web app (Settings → Restore),
so data moves between the two without loss. Separate from the MoneyTrack web app and
from Heimat — its own repo.
