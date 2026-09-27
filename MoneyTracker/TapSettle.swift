import Foundation
import SwiftData

// Tap & Settle, the app side. Core/Fusion.swift does the matching; this file feeds it from
// SwiftData and applies what it decides:
//   • a tap from a card on an account you manage by hand becomes a normal expense at once;
//   • a tap on a bank-synced account waits as "Pending" and settles into the bank's row when
//     it arrives (the bank's amount and date win; only a category you picked carries over);
//   • when the matcher isn't sure, it asks once ("Same purchase?");
//   • a tap the bank never booked, once the feed is complete past it, is an orphan.
// Everything here stays on this iPhone: taps, card names and what the matcher learns.
enum TapSettle {
    // ── Memory (local only) ──
    private static var dir: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0] }
    private static var memURL: URL { dir.appendingPathComponent("fusion.json") }
    private static var logURL: URL { dir.appendingPathComponent("wallet-log.json") }
    private(set) static var memory: FusionMemory = {
        guard let d = try? Data(contentsOf: memURL), let m = try? JSONDecoder().decode(FusionMemory.self, from: d) else { return FusionMemory() }
        return m
    }()
    private static func saveMemory() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(memory) { try? d.write(to: memURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
    }
    static func resetMemory() {
        memory = FusionMemory(); saveMemory()
        try? FileManager.default.removeItem(at: logURL)
        UserDefaults.standard.removeObject(forKey: coverageKey)
    }

    static var home: String { Regions.current.cur }

    // ── How far the bank feed is complete ──
    private static let coverageKey = "mt-bank-covered-through"
    static var coveredThrough: String? { UserDefaults.standard.string(forKey: coverageKey) }
    /// After a successful sync: the oldest bank connection's last sync, minus one day.
    static func noteSync(_ connections: [BankConnection]) {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let g = ISO8601DateFormatter()
        let dates = connections.compactMap { c in c.last_synced_at.flatMap { f.date(from: $0) ?? g.date(from: $0) } }
        guard let oldest = dates.min() else { return }
        UserDefaults.standard.set(CardMath.addDays(Fmt.day.string(from: oldest), -1), forKey: coverageKey)
    }

    // ── What Wallet sent (the last 30 taps), so you can see it per card ──
    struct LogEntry: Codable, Identifiable {
        var id = UUID()
        var at: Date
        var merchant: String, name: String, card: String
        var typed: String, text: String
        var result: String
    }
    static func readLog() -> [LogEntry] {
        guard let d = try? Data(contentsOf: logURL), let l = try? JSONDecoder().decode([LogEntry].self, from: d) else { return [] }
        return l
    }
    private static func appendLog(_ e: LogEntry) {
        let l = Array(([e] + readLog()).prefix(30))
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(l) { try? d.write(to: logURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
    }
    static func clearLog() { try? FileManager.default.removeItem(at: logURL) }

    // ── A tap arrives ──
    @discardableResult
    static func intake(ctx: ModelContext, merchant: String?, name: String?, card: String?,
                       amount: Decimal?, code: String?, text: String?, at: Date = Date()) -> Capture {
        let parsed = Fusion.parseAmount(typed: amount, code: code, text: text)
        let cents = parsed.cents ?? 0
        let m = (merchant ?? "").trimmed, n = (name ?? "").trimmed, c = (card ?? "").trimmed
        let typed = amount.map { "\($0) \(code ?? "")".trimmed } ?? ""
        // The same tap fired twice (Wallet can repeat the automation).
        let cutoff = at.addingTimeInterval(-120)
        let recent = (try? ctx.fetch(FetchDescriptor<Capture>(predicate: #Predicate { $0.at > cutoff }))) ?? []
        if let dup = recent.first(where: { $0.card == c && $0.cents == cents && $0.merchant == m }) {
            appendLog(LogEntry(at: at, merchant: m, name: n, card: c, typed: typed, text: text ?? "", result: "Same tap again, ignored"))
            return dup
        }
        let accounts = (try? ctx.fetch(FetchDescriptor<Account>())) ?? []
        let mapped = memory.cardMap[c].flatMap { id in accounts.contains { $0.id == id } ? id : nil } ?? ""
        let cap = Capture(at: at, cents: cents, cur: parsed.cur ?? "", merchant: m, name: n, card: c, accountId: mapped)
        cap.raw = "merchant=\(m) | name=\(n) | card=\(c) | amount=\(typed) | text=\(text ?? "")"
        ctx.insert(cap)
        run(ctx: ctx)
        let result: String
        switch cap.state {
        case "added": result = "Added as an expense"
        case "settled": result = "Matched a bank row"
        case "check": result = "Waiting for your check"
        default: result = cents == 0 ? "No amount from Wallet" : mapped.isEmpty ? "Card not linked yet" : "Pending"
        }
        appendLog(LogEntry(at: at, merchant: m, name: n, card: c, typed: typed, text: text ?? "", result: result))
        return cap
    }

    /// Needs an amount you type: Wallet sent none, or it's a foreign currency on a hand-managed account.
    static func needsAmount(_ c: Capture, _ accounts: [Account]) -> Bool {
        guard c.state == "pending", !c.accountId.isEmpty, let a = accounts.first(where: { $0.id == c.accountId }), !a.isSynced else { return false }
        return c.cents == 0 || (!c.cur.isEmpty && c.cur != home)
    }

    private static func promoteIfHandManaged(_ c: Capture, _ accounts: [Account], _ ctx: ModelContext) {
        guard c.state == "pending", !needsAmount(c, accounts), c.cents > 0,
              let a = accounts.first(where: { $0.id == c.accountId }), !a.isSynced else { return }
        let cat = c.categoryId.isEmpty ? (Merchants.category(c.title) ?? "other") : c.categoryId
        let t = Txn(id: "tap-" + c.id, type: "expense", amount: c.amount, merchant: c.title, categoryId: cat,
                    accountId: a.id, date: c.day)
        t.source = "tap"
        ctx.insert(t)
        c.state = "added"; c.linkId = t.id; c.reason = "Added to \(a.name)"
    }

    // ── One matching pass ──
    static func run(ctx: ModelContext) {
        guard let caps = try? ctx.fetch(FetchDescriptor<Capture>()), !caps.isEmpty else { return }
        let accounts = (try? ctx.fetch(FetchDescriptor<Account>())) ?? []
        let txs = (try? ctx.fetch(FetchDescriptor<Txn>())) ?? []
        let L = Ledger.build(accounts: accounts, txs: txs)
        let rowById = Dictionary(L.rows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let feed = Set(accounts.filter(\.isSynced).map(\.id))

        for c in caps {
            // A link to a bank row that is gone (the bank dropped it) re-opens the tap.
            if (c.state == "settled" || c.state == "check") && rowById[c.linkId] == nil { reopen(c) }
            // An account deleted since: the card needs linking again.
            if !c.accountId.isEmpty && !accounts.contains(where: { $0.id == c.accountId }) && c.isOpen { c.accountId = "" }
            promoteIfHandManaged(c, accounts, ctx)
        }
        let open = caps.filter { $0.isOpen && ($0.accountId.isEmpty || feed.contains($0.accountId)) }
        let taken = Set(caps.filter { $0.state == "settled" }.map(\.linkId))
        var coverage: [String: String] = [:]
        if let cov = coveredThrough { for a in feed where a.hasPrefix("sb-") { coverage[a] = cov } }
        let out = Fusion.run(evidence: open.map(\.evidence), rows: L.rows, taken: taken, feedAccounts: feed,
                             coverage: coverage, memory: memory, home: home)
        let byId = Dictionary(uniqueKeysWithValues: caps.map { ($0.id, $0) })
        let asked = Set(out.ask.map(\.evidenceId))
        for c in open where c.state == "check" && !asked.contains(c.id) { reopen(c) }
        for l in out.settle {
            guard let c = byId[l.evidenceId], let r = rowById[l.bankId] else { continue }
            settle(c, r, p: l.p, reason: l.reason, kind: l.kind, lag: l.lag)
        }
        for l in out.ask {
            guard let c = byId[l.evidenceId] else { continue }
            c.state = "check"; c.linkId = l.bankId; c.p = l.p; c.reason = l.reason
        }
        for id in out.orphans { byId[id]?.state = "orphan" }
        saveMemory()
        try? ctx.save()
    }

    private static func reopen(_ c: Capture) { c.state = "pending"; c.linkId = ""; c.p = 0; c.reason = "" }

    private static func settle(_ c: Capture, _ r: Row, p: Double, reason: String, kind: Fusion.Kind, lag: Int) {
        c.state = "settled"; c.linkId = r.id; c.p = p; c.reason = reason
        if !c.categoryId.isEmpty && LearningStore.shared.decision(r.id) == nil {
            LearningStore.shared.setDecision(Decision(type: "expense", category: c.categoryId), for: r.id)
            c.wroteDecision = true
        }
        if c.accountId.isEmpty { c.accountId = r.accountId }
        if !c.card.isEmpty && memory.cardMap[c.card] == nil { memory.cardMap[c.card] = r.accountId }
        Fusion.learn(&memory, c.evidence, r, kind: kind, lag: lag, home: home)
    }

    // ── Your answers ──
    private static func row(_ id: String, _ ctx: ModelContext) -> Row? {
        let accounts = (try? ctx.fetch(FetchDescriptor<Account>())) ?? []
        let txs = (try? ctx.fetch(FetchDescriptor<Txn>())) ?? []
        return Ledger.build(accounts: accounts, txs: txs).rows.first { $0.id == id }
    }
    private static func kind(_ c: Capture, _ r: Row) -> Fusion.Kind {
        let ct = Fusion.cents(r.amount)
        if c.cents == 0 { return .unknown }
        if !c.cur.isEmpty && c.cur != home && ct != c.cents { return .fx }
        if abs(ct - c.cents) <= 1 { return .exact }
        return ct > c.cents && Double(ct) <= 1.25 * Double(c.cents) + 100 ? .tip : .hold
    }

    /// "Yes, same purchase" — or you picked the bank row yourself.
    static func confirm(_ c: Capture, bankId: String? = nil, ctx: ModelContext) {
        let id = bankId ?? c.linkId
        guard let r = row(id, ctx) else { return }
        settle(c, r, p: 1, reason: "You confirmed it", kind: kind(c, r), lag: CardMath.daysBetween(c.day, r.date))
        saveMemory(); try? ctx.save()
        run(ctx: ctx)
    }
    /// "No, different" — never propose this pair again.
    static func reject(_ c: Capture, ctx: ModelContext) {
        if !c.linkId.isEmpty { memory.banned.insert("\(c.id)|\(c.linkId)") }
        reopen(c); saveMemory(); try? ctx.save()
        run(ctx: ctx)
    }
    /// Undo a settle: the tap is pending again and won't pair with that row by itself.
    static func undo(_ c: Capture, ctx: ModelContext) {
        if c.state == "settled" {
            if c.wroteDecision { LearningStore.shared.setDecision(nil, for: c.linkId); c.wroteDecision = false }
            memory.banned.insert("\(c.id)|\(c.linkId)")
            reopen(c)
        } else if c.state == "added" || c.state == "kept" {
            if let t = try? ctx.fetch(FetchDescriptor<Txn>()).first(where: { $0.id == c.linkId }) {
                LearningStore.shared.forget(t.id); ctx.delete(t)
            }
            c.state = "dismissed"; c.linkId = ""; c.reason = "Removed"
        }
        saveMemory(); try? ctx.save()
        run(ctx: ctx)
    }
    /// "Not charged" (declined, cancelled) — out of every total.
    static func dismiss(_ c: Capture, ctx: ModelContext) {
        c.state = "dismissed"; c.linkId = ""; c.reason = "Not charged"
        try? ctx.save()
    }
    /// "Paid another way": the tap becomes an expense on an account you manage by hand.
    static func keep(_ c: Capture, on account: Account, ctx: ModelContext) {
        guard !account.isSynced, c.cents > 0 else { return }
        let cat = c.categoryId.isEmpty ? (Merchants.category(c.title) ?? "other") : c.categoryId
        let t = Txn(id: "tap-" + c.id, type: "expense", amount: c.amount, merchant: c.title, categoryId: cat,
                    accountId: account.id, date: c.day)
        t.source = "tap"
        ctx.insert(t)
        c.state = "kept"; c.linkId = t.id; c.reason = "Added to \(account.name)"
        try? ctx.save()
    }
    /// A typed amount for a tap Wallet sent without one (or in a foreign currency).
    static func setAmount(_ c: Capture, _ v: Double, ctx: ModelContext) {
        guard v > 0 else { return }
        c.cents = Fusion.cents(v); c.cur = home
        run(ctx: ctx)
    }
    /// Link a Wallet card to an account; its waiting taps follow.
    static func link(card: String, to accountId: String, ctx: ModelContext) {
        memory.cardMap[card] = accountId
        for c in (try? ctx.fetch(FetchDescriptor<Capture>())) ?? [] where c.card == card && c.isOpen && c.accountId.isEmpty {
            c.accountId = accountId
        }
        saveMemory()
        run(ctx: ctx)
    }
    static func unlink(card: String) { memory.cardMap[card] = nil; saveMemory() }

    /// Bank rows you could pick for a tap yourself: money out on its account, not linked yet,
    /// within 10 days, closest amount first.
    static func pickable(_ c: Capture, _ L: Ledger, _ caps: [Capture]) -> [Row] {
        let taken = Set(caps.filter { $0.state == "settled" }.map(\.linkId))
        return Fusion.bankRows(L.rows)
            .filter { !taken.contains($0.id) && (c.accountId.isEmpty || $0.accountId == c.accountId)
                && abs(CardMath.daysBetween(c.day, $0.date)) <= 10 }
            .sorted { abs(Fusion.cents($0.amount) - c.cents) < abs(Fusion.cents($1.amount) - c.cents) }
            .prefix(8).map { $0 }
    }
}
