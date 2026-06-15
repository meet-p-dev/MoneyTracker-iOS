import Foundation
import SwiftData

// Reads/writes the exact JSON your PWA exports (Settings → Export backup),
// so you can move your data into the native app — and back out — losslessly.

enum BackupService {

    struct PWABackup: Codable {
        var accs: [PWAAccount]?
        var cats: [PWACategory]?
        var txs: [PWATxn]?
        var goals: [PWAGoal]?
        var recurring: [PWARecurring]?
        var debts: [PWADebt]?
        var budgets: [String: Double]?
        var exportedAt: String?
        var version: String?
    }

    // PWA stores numbers sometimes as strings (form inputs) — decode both.
    struct Flex: Codable {
        let value: Double
        init(from d: Decoder) throws {
            let c = try d.singleValueContainer()
            if let v = try? c.decode(Double.self) { value = v }
            else if let s = try? c.decode(String.self) { value = Double(s) ?? 0 }
            else { value = 0 }
        }
        func encode(to e: Encoder) throws { var c = e.singleValueContainer(); try c.encode(value) }
    }
    struct FlexInt: Codable {
        let value: Int
        init(from d: Decoder) throws {
            let c = try d.singleValueContainer()
            if let v = try? c.decode(Int.self) { value = v }
            else if let s = try? c.decode(String.self) { value = Int(s) ?? 0 }
            else if let v = try? c.decode(Double.self) { value = Int(v) }
            else { value = 0 }
        }
        func encode(to e: Encoder) throws { var c = e.singleValueContainer(); try c.encode(value) }
    }

    struct PWAAccount: Codable { var id: String; var name: String; var color: String; var ib: Flex? }
    struct PWACategory: Codable { var id: String; var label: String; var icon: String; var color: String }
    struct PWATxn: Codable {
        var id: String; var type: String; var amount: Flex; var merchant: String?
        var category: String?; var accountId: String?; var toAccountId: String?
        var notes: String?; var date: String
        var isSplit: Bool?; var splitPeople: FlexInt?; var splitSettled: Bool?
    }
    struct PWAGoal: Codable {
        var id: String; var name: String; var targetAmount: Flex; var savedAmount: Flex?
        var icon: String?; var color: String?
    }
    struct PWARecurring: Codable {
        var id: String; var merchant: String; var amount: Flex; var type: String?
        var category: String?; var accountId: String?; var dayOfMonth: FlexInt
        var active: Bool?; var lastTriggered: String?; var notes: String?
    }
    struct PWADebt: Codable {
        var id: String; var personName: String; var totalAmount: Flex; var paidBack: Flex?
        var settled: Bool?; var date: String?; var description: String?
        var color: String?; var receivedInAccount: String?
    }

    @discardableResult
    static func importBackup(_ data: Data, into ctx: ModelContext) throws -> Int {
        let b = try JSONDecoder().decode(PWABackup.self, from: data)
        var count = 0

        // wipe existing rows so import = restore (same as the PWA behaviour)
        try ctx.delete(model: Txn.self); try ctx.delete(model: Account.self)
        try ctx.delete(model: TxCategory.self); try ctx.delete(model: Goal.self)
        try ctx.delete(model: RecurringTxn.self); try ctx.delete(model: Debt.self)
        try ctx.delete(model: Budget.self)

        for (i, a) in (b.accs ?? []).enumerated() {
            ctx.insert(Account(id: a.id, name: a.name, colorHex: a.color, initialBalance: a.ib?.value ?? 0, sortIndex: i)); count += 1
        }
        for c in b.cats ?? [] {
            ctx.insert(TxCategory(id: c.id, label: c.label, icon: c.icon, colorHex: c.color)); count += 1
        }
        for t in b.txs ?? [] {
            ctx.insert(Txn(id: t.id, type: t.type, amount: t.amount.value, merchant: t.merchant ?? "",
                           categoryId: t.category ?? "other", accountId: t.accountId ?? "",
                           toAccountId: t.toAccountId ?? "", notes: t.notes ?? "", date: t.date,
                           isSplit: t.isSplit ?? false, splitPeople: max(t.splitPeople?.value ?? 1, 1),
                           splitSettled: t.splitSettled ?? false)); count += 1
        }
        for g in b.goals ?? [] {
            ctx.insert(Goal(id: g.id, name: g.name, targetAmount: g.targetAmount.value,
                            savedAmount: g.savedAmount?.value ?? 0, icon: g.icon ?? "🎯",
                            colorHex: g.color ?? "#007aff")); count += 1
        }
        for r in b.recurring ?? [] {
            ctx.insert(RecurringTxn(id: r.id, merchant: r.merchant, amount: r.amount.value,
                                    type: r.type ?? "expense", categoryId: r.category ?? "other",
                                    accountId: r.accountId ?? "", dayOfMonth: r.dayOfMonth.value,
                                    active: r.active ?? true, lastTriggered: r.lastTriggered ?? "",
                                    notes: r.notes ?? "")); count += 1
        }
        for d in b.debts ?? [] {
            ctx.insert(Debt(id: d.id, personName: d.personName, totalAmount: d.totalAmount.value,
                            paidBack: d.paidBack?.value ?? 0, settled: d.settled ?? false,
                            date: d.date ?? Fmt.today(), details: d.description ?? "",
                            colorHex: d.color ?? "#e11d48", receivedInAccount: d.receivedInAccount ?? "")); count += 1
        }
        for (catId, limit) in b.budgets ?? [:] where limit > 0 {
            ctx.insert(Budget(categoryId: catId, limit: limit)); count += 1
        }
        try ctx.save()
        return count
    }

    static func exportBackup(ctx: ModelContext) throws -> Data {
        let accs = try ctx.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortIndex)]))
        let cats = try ctx.fetch(FetchDescriptor<TxCategory>())
        let txs = try ctx.fetch(FetchDescriptor<Txn>())
        let goals = try ctx.fetch(FetchDescriptor<Goal>())
        let recs = try ctx.fetch(FetchDescriptor<RecurringTxn>())
        let debts = try ctx.fetch(FetchDescriptor<Debt>())
        let buds = try ctx.fetch(FetchDescriptor<Budget>())

        var out: [String: Any] = [:]
        out["accs"] = accs.map { ["id": $0.id, "name": $0.name, "color": $0.colorHex, "ib": $0.initialBalance] }
        out["cats"] = cats.map { ["id": $0.id, "label": $0.label, "icon": $0.icon, "color": $0.colorHex] }
        out["txs"] = txs.map { ["id": $0.id, "type": $0.type, "amount": $0.amount, "merchant": $0.merchant,
                               "category": $0.categoryId, "accountId": $0.accountId, "toAccountId": $0.toAccountId,
                               "notes": $0.notes, "date": $0.date, "isSplit": $0.isSplit,
                               "splitPeople": $0.splitPeople, "splitSettled": $0.splitSettled] }
        out["goals"] = goals.map { ["id": $0.id, "name": $0.name, "targetAmount": $0.targetAmount,
                                   "savedAmount": $0.savedAmount, "icon": $0.icon, "color": $0.colorHex] }
        out["recurring"] = recs.map { ["id": $0.id, "merchant": $0.merchant, "amount": $0.amount, "type": $0.type,
                                      "category": $0.categoryId, "accountId": $0.accountId, "dayOfMonth": $0.dayOfMonth,
                                      "active": $0.active, "lastTriggered": $0.lastTriggered, "notes": $0.notes] }
        out["debts"] = debts.map { ["id": $0.id, "personName": $0.personName, "totalAmount": $0.totalAmount,
                                   "paidBack": $0.paidBack, "settled": $0.settled, "date": $0.date,
                                   "description": $0.details, "color": $0.colorHex,
                                   "receivedInAccount": $0.receivedInAccount] }
        out["budgets"] = Dictionary(uniqueKeysWithValues: buds.map { ($0.categoryId, $0.limit) })
        out["exportedAt"] = ISO8601DateFormatter().string(from: Date())
        out["version"] = "3.0-native"
        return try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
    }

    // First-launch defaults — same accounts & categories as the PWA.
    static func seedIfEmpty(ctx: ModelContext) {
        let count = (try? ctx.fetchCount(FetchDescriptor<Account>())) ?? 0
        guard count == 0 else { return }
        let defAccs: [(String, String, String)] = [
            ("sparkasse", "Sparkasse", "#e11d48"), ("revolut", "Revolut", "#6d28d9"),
            ("revolut-savings", "Revolut Savings", "#7c3aed"), ("paypal", "PayPal", "#1d4ed8"),
            ("friend-loan", "Friend (Loan)", "#059669")
        ]
        for (i, a) in defAccs.enumerated() {
            ctx.insert(Account(id: a.0, name: a.1, colorHex: a.2, sortIndex: i))
        }
        let defCats: [(String, String, String, String)] = [
            ("groceries", "Groceries", "🛒", "#4ade80"), ("dining", "Dining", "🍴", "#fb923c"),
            ("subscr", "Subscriptions", "📱", "#a78bfa"), ("transport", "Transport", "🚗", "#60a5fa"),
            ("shopping", "Shopping", "🏪", "#f472b6"), ("health", "Health", "🏥", "#34d399"),
            ("entertain", "Entertainment", "🎮", "#fbbf24"), ("salary", "Salary", "💼", "#22c55e"),
            ("freelance", "Freelance", "💻", "#0ea5e9"), ("rent", "Rent / Bills", "🏠", "#ef4444"),
            ("other", "Other", "📦", "#9ca3af")
        ]
        for c in defCats {
            ctx.insert(TxCategory(id: c.0, label: c.1, icon: c.2, colorHex: c.3))
        }
        try? ctx.save()
    }

    // Recurring auto-trigger — local dates only (the PWA's timezone bug, avoided).
    static func triggerRecurring(ctx: ModelContext) {
        let today = Fmt.today()
        let day = Calendar.current.component(.day, from: Date())
        guard let recs = try? ctx.fetch(FetchDescriptor<RecurringTxn>()) else { return }
        var fired = false
        for r in recs where r.active && r.dayOfMonth == day && r.lastTriggered != today {
            ctx.insert(Txn(type: r.type, amount: r.amount, merchant: r.merchant,
                           categoryId: r.categoryId, accountId: r.accountId,
                           notes: r.notes, date: today))
            r.lastTriggered = today
            fired = true
        }
        if fired { try? ctx.save() }
    }
}
