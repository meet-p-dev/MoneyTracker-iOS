import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// The effective-transaction layer — a port of the web app's `ctxs` (components/App.jsx)
// plus its balance math (balOf / getBal / totals). Plain Swift, no SwiftData or SwiftUI,
// so it compiles on its own and can be checked against a real backup to the cent.
//
// Raw rows are what the bank / you recorded. Effective rows re-label them:
//   • your decisions on BANK rows (type/category/destination) — but never reversing the
//     cash direction the bank booked (the V11.3 "€42" guard; outgoing transfers with a
//     destination are allowed, V11.7);
//   • bank debits that read like a credit-card bill become a transfer into that card;
//   • "My share" on an expense.
// Balances use the effective rows; a transfer out is still money out of the source.
// ─────────────────────────────────────────────────────────────────────────────

struct AccSnap: Identifiable, Hashable {
    var id: String
    var name: String
    var colorHex: String = "#3b82f6"
    var ib: Double = 0                 // starting balance (cards: negative when you owe)
    var kind: String = "cash"          // "cash" | "credit"
    var creditLimit: Double = 0
    var statementDay: Int = 1
    var dueDay: Int = 1
    var apr: Double = 0
    var payFromId: String = ""
    var autopay: Bool = false
    var billPayee: String = ""
    var ibDate: String = ""            // starting-balance date; "" = count everything
    var isBank: Bool = false           // synced from the bank (id "sb-…")
    var isCredit: Bool { kind == "credit" }
}

struct Row: Identifiable, Hashable {
    var id: String
    var type: String                   // income | credit | expense | debit | transfer
    var rawType: String
    var amount: Double
    var merchant: String
    var categoryId: String
    var rawCategoryId: String
    var accountId: String
    var toAccountId: String
    var notes: String
    var date: String                   // yyyy-MM-dd
    var isBank: Bool
    var share: Double? = nil           // "My share" of an expense
    var cardPay: Bool = false          // bank debit auto-matched as a card-bill payment
    var decided: Bool = false          // type/category come from your own decision
    var clamped: Bool = false          // your decision tried to reverse the direction
    var needsReview: Bool = false      // incoming money the classifier isn't sure about
    var reason: String = ""            // why the classifier decided what it did
    var confidence: Double? = nil
    var suggest: [String] = []         // the classifier's top guesses (labels)

    /// What this costs YOU: an expense's share if you set one, else the full amount.
    var personal: Double { type == "expense" ? (share ?? amount) : amount }
    var isIn: Bool { type == "income" || type == "credit" }
    var isOut: Bool { type == "expense" || type == "debit" }
}

/// One stored decision ({type, category, toAccountId?}) from the web's mt-tx-decisions.
struct Decision {
    var type: String
    var category: String?
    var toAccountId: String?
    init(type: String, category: String?, toAccountId: String? = nil) {
        self.type = type; self.category = category; self.toAccountId = toAccountId
    }
    init?(_ v: JSONValue) {
        guard let o = v.object, let t = o["type"]?.string else { return nil }
        type = t; category = o["category"]?.string
        let dest = o["toAccountId"]?.string ?? ""
        toAccountId = dest.isEmpty ? nil : dest
    }
    var json: JSONValue {
        var o: [String: JSONValue] = ["type": .string(type)]
        if let category { o["category"] = .string(category) }
        if let toAccountId { o["toAccountId"] = .string(toAccountId) }
        return .object(o)
    }
}

struct Ledger {
    let accounts: [AccSnap]
    let rows: [Row]
    let byId: [String: AccSnap]

    init(accounts: [AccSnap], raw: [Row], decisions: [String: JSONValue] = [:], shares: [String: Double] = [:],
         payeeStats: [String: JSONValue] = [:], ownerName: String = "") {
        var m: [String: AccSnap] = [:]
        for a in accounts { m[a.id] = a }
        self.accounts = accounts
        self.byId = m
        self.rows = Ledger.effective(raw: raw, accounts: accounts, byId: m, decisions: decisions, shares: shares,
                                     payeeStats: payeeStats, ownerName: ownerName)
    }

    private static func effective(raw: [Row], accounts: [AccSnap], byId: [String: AccSnap],
                                  decisions: [String: JSONValue], shares: [String: Double],
                                  payeeStats: [String: JSONValue], ownerName: String) -> [Row] {
        let res = Classifier.classifyAll(raw, ownerName: ownerName, payeeStats: payeeStats, decisions: decisions)
        let cards = accounts.filter(\.isCredit)
        let payCards = cards.filter { !$0.billPayee.trimmed.isEmpty }.map { ($0.id, $0.billPayee.trimmed.lowercased()) }
        func matchCard(_ t: Row, ownTransfer: Bool) -> String? {
            if cards.isEmpty { return nil }
            if cards.contains(where: { $0.id == t.accountId }) { return nil }   // never re-map a charge on the card itself
            let hay = "\(t.merchant) \(t.notes)".lowercased()
            if let p = payCards.first(where: { $0.0 != t.accountId && hay.contains($0.1) }) { return p.0 }
            if !t.isBank { return nil }                                        // keyword detection: synced rows only
            if !CardMath.looksLikeCardBill(hay, ownTransfer: ownTransfer) { return nil }
            if let named = cards.first(where: { let n = $0.name.trimmed.lowercased(); return n.count >= 3 && hay.contains(n) }) {
                return named.id
            }
            return cards.count == 1 ? cards[0].id : nil
        }
        return raw.map { t in
            var r = t
            r.rawType = t.type; r.rawCategoryId = t.categoryId
            let c = res[t.id]
            if let c {
                r.type = c.type
                if !c.category.isEmpty { r.categoryId = c.category }
                r.needsReview = c.needsReview; r.reason = c.reason; r.confidence = c.confidence; r.suggest = c.suggest
                r.decided = c.decided; r.clamped = c.clamped
                // Your "Transfer → card/account" on a bank debit: only a destination that still
                // exists and isn't the same account counts; otherwise it's plain money out.
                if c.type == "transfer" {
                    if let dest = c.toAccountId, dest != t.accountId, byId[dest] != nil { r.toAccountId = dest }
                    else { r.type = "debit" }
                }
            }
            // Your own choice beats auto-matching (a transfer decision WITHOUT a destination
            // — saved by web V11.3–11.6 — still gets its card filled in).
            let dec = decisions[t.id].flatMap(Decision.init)
            let userPicked = dec.map { $0.type != "transfer" || $0.toAccountId != nil } ?? false
            if !userPicked && (t.type == "expense" || t.type == "debit"),
               let cardId = matchCard(t, ownTransfer: c?.type == "debit" && c?.category == "transfer") {
                r.type = "transfer"; r.toAccountId = cardId; r.categoryId = "transfer"; r.cardPay = true; r.needsReview = false
            }
            if let s = shares[t.id] { r.share = s }
            return r
        }
    }

    func account(_ id: String) -> AccSnap? { byId[id] }
    /// Incoming bank money the classifier couldn't confidently call — the Review inbox.
    var reviewRows: [Row] { rows.filter(\.needsReview) }
    var cards: [AccSnap] { accounts.filter(\.isCredit) }
    var cashAccounts: [AccSnap] { accounts.filter { !$0.isCredit } }

    /// Starting balance + every row that counts for this account (see CardMath.countsFor).
    func balance(of a: AccSnap) -> Double {
        var b = a.ib
        for t in rows where CardMath.countsFor(a, t.date) {
            if t.isIn && t.accountId == a.id { b += t.amount }
            if (t.isOut || t.type == "transfer") && t.accountId == a.id { b -= t.amount }
            if t.type == "transfer" && t.toAccountId == a.id { b += t.amount }
        }
        return b
    }
    func balance(_ id: String) -> Double { byId[id].map(balance(of:)) ?? 0 }
    func cardStats(_ c: AccSnap, ref: String = Fmt.today()) -> CardMath.Stats { CardMath.stats(c, rows, ref: ref) }

    /// Cash only. `netWorth` = assets − what the cards owe (cards carry a negative balance).
    var assets: Double { cashAccounts.reduce(0) { $0 + balance(of: $1) } }
    var creditOwed: Double { cards.reduce(0) { $0 + max(cardStats($1).currentBalance, 0) } }
    var netWorth: Double { accounts.reduce(0) { $0 + balance(of: $1) } }

    func monthStats(_ key: String) -> (income: Double, spent: Double) {
        let m = rows.filter { $0.date.hasPrefix(key) }
        return (m.filter { $0.type == "income" }.reduce(0) { $0 + $1.amount },
                m.filter { $0.type == "expense" }.reduce(0) { $0 + $1.personal })
    }

    /// Spent so far + the median day × days left (one big one-off doesn't explode it).
    func projectedSpend(_ key: String) -> Double {
        let cal = Calendar.current, now = Date()
        let dayOfMonth = cal.component(.day, from: now)
        let daysInMonth = cal.range(of: .day, in: .month, for: now)?.count ?? 30
        let exp = rows.filter { $0.type == "expense" && $0.date.hasPrefix(key) }
        var byDay: [String: Double] = [:]
        for t in exp { byDay[t.date, default: 0] += t.personal }
        let totals = byDay.values.sorted()
        let median = totals.isEmpty ? 0 : totals[totals.count / 2]
        return exp.reduce(0) { $0 + $1.personal } + median * Double(daysInMonth - dayOfMonth)
    }

    /// Hand-managed accounts that are probably counting rows from BEFORE their starting
    /// balance (web V11.8 ibIssues). Offered as a fix; nothing changes until you save it.
    struct Issue: Identifiable {
        var id: String { acc.id }
        let acc: AccSnap, date: String, n: Int, now: Double, fixed: Double
    }
    var issues: [Issue] {
        accounts.filter { !$0.isBank && $0.ibDate.isEmpty }.compactMap { a in
            guard let date = CardMath.suggestStartDate(a, rows) else { return nil }
            let old = rows.filter { $0.date < date && ($0.accountId == a.id || ($0.type == "transfer" && $0.toAccountId == a.id)) }
            guard !old.isEmpty else { return nil }
            var fixedAcc = a; fixedAcc.ibDate = date
            let now = balance(of: a), fixed = balance(of: fixedAcc)
            guard abs(fixed - now) >= 0.005 else { return nil }
            return Issue(acc: a, date: date, n: old.count, now: (now * 100).rounded() / 100, fixed: (fixed * 100).rounded() / 100)
        }
    }
}
