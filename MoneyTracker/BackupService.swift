import Foundation
import SwiftData

// Reads and writes the exact JSON the MoneyTrack web app exports (backup format "2.6",
// web V11.8) — so data moves between the two apps without loss, in both directions.
enum BackupService {

    // The built-in categories — same ids, labels, colors and symbols as the web app.
    static let builtInCats: [(id: String, label: String, icon: String, sym: String, color: String)] = [
        ("groceries", "Groceries", "🛒", "cart", "#4ade80"), ("dining", "Dining", "🍴", "food", "#fb923c"),
        ("subscr", "Subscriptions", "📱", "phone", "#a78bfa"), ("transport", "Transport", "🚗", "car", "#60a5fa"),
        ("shopping", "Shopping", "🏪", "bag", "#f472b6"), ("health", "Health", "🏥", "heart", "#34d399"),
        ("entertain", "Entertainment", "🎮", "play", "#fbbf24"), ("salary", "Salary", "💼", "brief", "#22c55e"),
        ("freelance", "Freelance", "💻", "laptop", "#0ea5e9"), ("rent", "Rent / Bills", "🏠", "house", "#ef4444"),
        ("transfer", "Transfer", "🔄", "swap", "#38bdf8"), ("reimburse", "Reimbursement", "🔁", "repeat", "#2dd4bf"),
        ("refund", "Refund", "↩️", "undo", "#22d3ee"), ("debt", "Debt / Loan", "🤝", "scale", "#f59e0b"),
        ("other", "Other", "📦", "box", "#9ca3af"),
    ]
    static func builtInSym(_ catId: String) -> String { builtInCats.first { $0.id == catId }?.sym ?? "" }

    // Goals saved with an emoji get the matching symbol (web lib/icons.jsx EMOJI_SYM).
    static let goalEmojiSym: [String: String] = [
        "🎯": "goal", "✈️": "plane", "🏠": "house", "🎓": "grad", "🚗": "car", "💻": "laptop",
        "🎮": "play", "💍": "gem", "🏖️": "beach", "🎁": "gift", "💊": "pill", "🐾": "paw",
    ]
    static func goalSym(forEmoji e: String) -> String { goalEmojiSym[e] ?? "goal" }

    // ── Restore (= replace, same as the web app) ──
    @discardableResult
    static func importBackup(_ data: Data, into ctx: ModelContext) throws -> Int {
        let b = try JSONDecoder().decode(WebBackup.self, from: data)
        try ctx.delete(model: Txn.self); try ctx.delete(model: Account.self)
        try ctx.delete(model: TxCategory.self); try ctx.delete(model: Goal.self)
        try ctx.delete(model: RecurringTxn.self); try ctx.delete(model: Debt.self)
        try ctx.delete(model: Budget.self)
        var n = 0

        for (i, w) in (b.accs ?? []).enumerated() {
            let a = Account(id: w.id, name: w.name ?? "Account", colorHex: w.color ?? "#3b82f6", sortIndex: i)
            a.apply(w.snap); a.lastAutopay = w.lastAutopay ?? ""
            ctx.insert(a); n += 1
        }
        let cats = b.cats ?? []
        for c in cats {
            ctx.insert(TxCategory(id: c.id, label: c.label ?? c.id, icon: c.icon ?? "📦",
                                  colorHex: c.color ?? "#9ca3af", sym: c.sym ?? builtInSym(c.id))); n += 1
        }
        for c in builtInCats where !cats.contains(where: { $0.id == c.id }) {
            ctx.insert(TxCategory(id: c.id, label: c.label, icon: c.icon, colorHex: c.color, sym: c.sym))
        }
        var shares = (b.shareOverrides ?? [:]).mapValues(\.value)
        for t in b.txs ?? [] {
            // A WG split becomes "My share" (web V9.9) — nothing is lost.
            let people = t.splitPeople?.value ?? 1
            if (t.isSplit?.value ?? false), people > 1, t.type == "expense", shares[t.id] == nil {
                shares[t.id] = t.amount.value / Double(people)
            }
            let x = Txn(id: t.id, type: t.type, amount: t.amount.value, merchant: t.merchant ?? "",
                        categoryId: t.category ?? "other", accountId: t.accountId ?? "",
                        toAccountId: t.toAccountId ?? "", notes: t.notes ?? "", date: String(t.date.prefix(10)))
            x.isBank = t.isBank
            ctx.insert(x); n += 1
        }
        for g in b.goals ?? [] {
            let icon = g.icon ?? "🎯"
            ctx.insert(Goal(id: g.id, name: g.name ?? "Goal", targetAmount: g.targetAmount?.value ?? 0,
                            savedAmount: g.savedAmount?.value ?? 0, icon: icon, colorHex: g.color ?? "#007aff",
                            sym: g.sym ?? goalSym(forEmoji: icon))); n += 1
        }
        for d in b.debts ?? [] {
            ctx.insert(Debt(id: d.id, personName: d.personName ?? "Someone", totalAmount: d.totalAmount?.value ?? 0,
                            paidBack: d.paidBack?.value ?? 0, settled: d.settled?.value ?? false,
                            date: d.date ?? Fmt.today(), details: d.description ?? "",
                            colorHex: d.color ?? "#e11d48", receivedInAccount: d.receivedInAccount ?? "")); n += 1
        }
        for (catId, limit) in b.budgets ?? [:] where limit.value > 0 {
            ctx.insert(Budget(categoryId: catId, limit: limit.value)); n += 1
        }
        if let cur = b.currency, Regions.all.contains(where: { $0.id == cur }) { Regions.currentId = cur }
        LearningStore.shared.replaceAll(decisions: b.txDecisions ?? [:], payeeStats: b.payeeStats ?? [:],
                                        shares: shares, ownerName: b.ownerName ?? "")
        try ctx.save()
        UserDefaults.standard.set(true, forKey: migrationKey)   // restored data is already current
        return n
    }

    // ── Export — the web app's own format, so the web app can restore it ──
    static func exportBackup(ctx: ModelContext) throws -> Data {
        let accs = try ctx.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortIndex)]))
        let cats = try ctx.fetch(FetchDescriptor<TxCategory>())
        let txs = try ctx.fetch(FetchDescriptor<Txn>())
        let goals = try ctx.fetch(FetchDescriptor<Goal>())
        let debts = try ctx.fetch(FetchDescriptor<Debt>())
        let buds = try ctx.fetch(FetchDescriptor<Budget>())
        let L = LearningStore.shared

        var out: [String: Any] = [:]
        out["accs"] = accs.map { a -> [String: Any] in
            var d: [String: Any] = ["id": a.id, "name": a.name, "color": a.colorHex, "ib": a.initialBalance, "kind": a.kind]
            if a.isCredit {
                d["creditLimit"] = a.creditLimit; d["statementDay"] = a.statementDay; d["dueDay"] = a.dueDay
                d["apr"] = a.apr; d["payFromId"] = a.payFromId; d["autopay"] = a.autopay; d["billPayee"] = a.billPayee
                if !a.lastAutopay.isEmpty { d["lastAutopay"] = a.lastAutopay }
            }
            if !a.ibDate.isEmpty { d["ibDate"] = a.ibDate }
            if a.isSynced { d["_bank"] = true }
            return d
        }
        out["cats"] = cats.map { ["id": $0.id, "label": $0.label, "icon": $0.icon, "sym": $0.sym, "color": $0.colorHex] }
        out["txs"] = txs.map { t -> [String: Any] in
            var d: [String: Any] = ["id": t.id, "type": t.type, "amount": t.amount, "merchant": t.merchant,
                                    "category": t.categoryId, "accountId": t.accountId, "toAccountId": t.toAccountId,
                                    "notes": t.notes, "date": t.date, "isSplit": false, "splitPeople": 1, "splitSettled": false]
            if t.isSynced { d["_bank"] = true }
            return d
        }
        out["goals"] = goals.map { ["id": $0.id, "name": $0.name, "targetAmount": $0.targetAmount,
                                    "savedAmount": $0.savedAmount, "icon": $0.icon, "sym": $0.sym, "color": $0.colorHex] }
        out["recurring"] = [Any]()
        out["debts"] = debts.map { ["id": $0.id, "personName": $0.personName, "totalAmount": $0.totalAmount,
                                    "paidBack": $0.paidBack, "settled": $0.settled, "date": $0.date,
                                    "description": $0.details, "color": $0.colorHex, "receivedInAccount": $0.receivedInAccount] }
        out["budgets"] = Dictionary(buds.map { ($0.categoryId, $0.limit) }, uniquingKeysWith: { a, _ in a })
        out["currency"] = Regions.currentId
        out["payeeStats"] = L.payeeStats.mapValues(\.any)
        out["txDecisions"] = L.txDecisions.mapValues(\.any)
        out["shareOverrides"] = L.shareOverrides
        out["ownerName"] = L.ownerName
        out["exportedAt"] = ISO8601DateFormatter().string(from: Date())
        out["version"] = "2.6"
        return try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
    }

    // First launch: categories only. No made-up accounts (web V11.3) — you add your own,
    // or restore your web backup, or (Phase 2) sign in and your bank accounts arrive.
    static func seedIfEmpty(ctx: ModelContext) {
        let count = (try? ctx.fetchCount(FetchDescriptor<TxCategory>())) ?? 0
        guard count == 0 else { return }
        for c in builtInCats { ctx.insert(TxCategory(id: c.id, label: c.label, icon: c.icon, colorHex: c.color, sym: c.sym)) }
        try? ctx.save()
    }

    // One-time upgrade of data saved by the old iOS app (web V8-era):
    //  · WG splits → "My share" · Recurring rules removed · new built-in categories + symbols.
    static let migrationKey = "mt-ios-migrated-v11.8"
    static func migrateIfNeeded(ctx: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        if let txs = try? ctx.fetch(FetchDescriptor<Txn>()) {
            for t in txs where t.isSplit {
                if t.splitPeople > 1, t.type == "expense", LearningStore.shared.share(t.id) == nil {
                    LearningStore.shared.setShare(t.amount / Double(t.splitPeople), for: t.id)
                }
                t.isSplit = false; t.splitPeople = 1
            }
        }
        try? ctx.delete(model: RecurringTxn.self)
        let existing = (try? ctx.fetch(FetchDescriptor<TxCategory>())) ?? []
        for c in builtInCats {
            if let e = existing.first(where: { $0.id == c.id }) { if e.sym.isEmpty { e.sym = c.sym } }
            else { ctx.insert(TxCategory(id: c.id, label: c.label, icon: c.icon, colorHex: c.color, sym: c.sym)) }
        }
        if let goals = try? ctx.fetch(FetchDescriptor<Goal>()) {
            for g in goals where g.sym.isEmpty { g.sym = goalSym(forEmoji: g.icon) }
        }
        try? ctx.save()
        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    /// Settings → Clear all data.
    static func wipe(ctx: ModelContext) {
        try? ctx.delete(model: Txn.self); try? ctx.delete(model: Account.self)
        try? ctx.delete(model: Goal.self); try? ctx.delete(model: RecurringTxn.self)
        try? ctx.delete(model: Debt.self); try? ctx.delete(model: Budget.self)
        LearningStore.shared.clear()
        try? ctx.save()
    }
}
