# Architecture (iOS)

All sources live in `MoneyTracker/`. The folder groups are synchronized, so new files are
included automatically.

## Core/ — plain Swift, no UI (testable with `swiftc`)
| File | Port of (web) | What |
|------|---------------|------|
| `Ledger.swift` | `components/App.jsx` derived data | Effective rows (decisions, card-bill auto-match, My share), balances, `cardStats`, net worth, month stats, projections, starting-balance issues, review rows |
| `Insights.swift` | Insights tab maths | Category totals by month, cash vs credit, daily spend, month chart, biggest expense |
| `Classifier.swift` | `lib/classify.js` | Bank-credit evidence engine, payee priors, learning |
| `CardMath.swift` | `lib/credit.js` | Statement cycles, due dates, `countsFor`/`ibDate`, card-bill detection |
| `Merchants.swift` | `lib/merchants.js` | Shared merchant list (organisations only) |
| `JSRegex.swift` | — | JavaScript-style `\b` on top of ICU regex |
| `BackupCodec.swift` | `doExport`/`doImport` | Backup format 2.6 |
| `Fmt.swift`, `JSONValue.swift` | `lib/utils.js` | Regions, money formatting, amount parsing, JSON values |
| `Fusion.swift` | — (iOS only) | Tap & Settle matcher: links an Apple Pay tap to the bank row that books it later. Gates, log-odds score, one-to-one assignment, orphans, learning |

## Data & services
- `Models.swift`: SwiftData models plus `Ledger.build(accounts:txs:learning:)`.
- `LearningStore.swift`: the four learning stores (decisions, payee stats, My share, owner name).
- `CloudSync.swift`: Supabase sign-in (Keychain), bank data sync with self-healing, prefs pull/push.
- `BackupService.swift`: built-in categories, backup import/export, first-run seed,
  migration (`mt-ios-migrated-v11.8`), wipe.
- `CardServices.swift`: card auto-pay (manual pay-from accounts only), Pay Bill outcome.
- `TapSettle.swift`: Apple Pay taps (`Capture` model). Intake, a matching pass after every
  bank sync and app launch, your answers (confirm, reject, undo, not charged, paid another
  way), card-to-account links, and the "What Wallet sent" log. Local only: `fusion.json` and
  `wallet-log.json` in Application Support, never synced.
- `WalletIntent.swift`: the "Log Apple Pay payment" App Intent (background, no dialog) that a
  Shortcuts Wallet automation calls. Uses `AppData.container`, shared with the app.

### Tap & Settle rules
- A tap never changes a bank row's amount, date, direction or account. It only lends a
  category you picked. Captures never enter `Ledger` or the Classifier.
- Bank-synced account: the tap waits as "pending" (shown next to the balance, not in it).
  Hand-managed account: it becomes a normal expense (`Txn.source = "tap"`, id `tap-…`).
- Replay test: `swiftc Core/*.swift main.swift` against the July bank export (19 time-stamped
  card rows): 19/19 settle, 0 false merges, a declined tap becomes an orphan.

## UI
- `ContentView.swift`: the TabView shell, the glass tab bar overlay, sheets (add, profile,
  tour) and auto-pay on launch.
- `UI/GlassTabBar.swift`: Home · Activity · big + · Insights · Wallet.
- `UI/Router.swift`: tab and deep-link state (Income → Activity, category → Insights,
  card → Wallet…).
- `UI/Theme.swift`, `UI/Components.swift`: tokens, cards, rows, charts, monograms.
- `UI/TxListSheet.swift`: "the transactions behind this number".
- `UI/ExplainSheet.swift`: the ⓘ explanations.
- `UI/Tips.swift`: the two TipKit tips.
- `TapViews.swift`: the Apple Pay check sheet ("Same purchase?", link a card, add an amount,
  not booked), Settings → Apple Pay payments, and the pending row on Home.
- Screens:
  - `HomeView`, `ActivityView`, `InsightsView` (with `CategoryDrill`), `WalletView`,
    `CardDetailView`
  - `TransactionForm`, `AccountsView` (AccountForm), `PeopleView` (debt forms),
    `GoalsView` (goal form)
  - `ReviewSheet`, `BankSyncView`, `SettingsView`, `ProfileView`, `TourView`,
    `HowItWorksView`, `LockView`
- `Helpers.swift`: colours, haptics, SF Symbol mapping, category/goal glyphs.
