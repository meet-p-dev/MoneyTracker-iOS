import Foundation
import SwiftData
import UniformTypeIdentifiers

// Statement Drop, the app side. Core/Statement.swift reads the file and plans the change;
// this applies it. Files never leave the phone.
enum StatementImport {
    private static let mapKey = "mt-statement-accounts"     // file's IBAN or bank → accountId
    static let fileTypes: [UTType] = [.commaSeparatedText, .tabSeparatedText, .plainText, .xml, .pdf,
                                      UTType("org.openxmlformats.spreadsheetml.sheet") ?? .data,
                                      UTType("com.patel.moneytracker.mt940") ?? .data, .data]

    static func rememberedAccount(_ st: Statement, _ accounts: [Account]) -> String? {
        let map = UserDefaults.standard.dictionary(forKey: mapKey) as? [String: String] ?? [:]
        if let id = map[st.accountKey], accounts.contains(where: { $0.id == id }) { return id }
        // A first guess by name: "Revolut" file → the account called Revolut.
        let bank = st.bank.lowercased()
        if bank.count >= 3, let a = accounts.first(where: { $0.name.lowercased().contains(bank) }) { return a.id }
        return nil
    }
    private static func remember(_ st: Statement, _ accountId: String) {
        var map = UserDefaults.standard.dictionary(forKey: mapKey) as? [String: String] ?? [:]
        map[st.accountKey] = accountId
        UserDefaults.standard.set(map, forKey: mapKey)
    }

    static func plan(_ st: Statement, accountId: String, ctx: ModelContext) -> StatementPlan? {
        let accounts = (try? ctx.fetch(FetchDescriptor<Account>())) ?? []
        guard let acc = accounts.first(where: { $0.id == accountId }) else { return nil }
        let txs = (try? ctx.fetch(FetchDescriptor<Txn>())) ?? []
        let caps = (try? ctx.fetch(FetchDescriptor<Capture>())) ?? []
        let L = Ledger.build(accounts: accounts, txs: txs)
        let mine = txs.filter { $0.accountId == accountId }
        let stored = Set(mine.map(\.fp).filter { !$0.isEmpty })
        let typedIds = Set(mine.filter { !$0.isSynced && $0.source.isEmpty }.map(\.id))
        let typed = L.rows.filter { typedIds.contains($0.id) }
        let tapTxns = Set(mine.filter { $0.source == "tap" }.map(\.id))
        let taps = caps.filter { $0.state == "added" && tapTxns.contains($0.linkId) }.map { c -> (Evidence, String) in
            var e = c.evidence; e.accountId = accountId; return (e, c.linkId)
        }
        return StatementPlan.make(st, account: acc.snap, rows: L.rows, stored: stored, typed: typed, taps: taps,
                                  memory: TapSettle.memory, home: TapSettle.home)
    }

    struct Result {
        var added = 0, confirmed = 0
        var closing: (day: String, file: Double, app: Double)?
        var matches: Bool { closing.map { abs($0.file - $0.app) < 0.005 } ?? true }
    }

    static func apply(_ st: Statement, _ plan: StatementPlan, accountId: String, ctx: ModelContext) -> Result {
        var res = Result()
        let txs = (try? ctx.fetch(FetchDescriptor<Txn>())) ?? []
        let byId = Dictionary(uniqueKeysWithValues: txs.map { ($0.id, $0) })
        for i in plan.inserts where byId[i.id] == nil {
            let r = i.row
            let text = "\(r.payee) \(r.purpose)"
            let t = Txn(id: i.id, type: r.cents < 0 ? "expense" : "income", amount: Double(abs(r.cents)) / 100,
                        merchant: String((r.payee.isEmpty ? r.purpose : r.payee).prefix(60)),
                        categoryId: r.cents < 0 ? (Merchants.category(text) ?? "other") : "other", accountId: accountId,
                        notes: [r.purpose, r.time].filter { !$0.isEmpty }.joined(separator: " "), date: r.day)
            t.isBank = true; t.source = "file"; t.fp = i.fp
            ctx.insert(t); res.added += 1
        }
        for m in plan.merges {
            guard let t = byId[m.txnId] else { continue }
            // The bank's row wins: its amount and date replace what the tap or you typed.
            t.amount = Double(abs(m.row.cents)) / 100; t.date = m.row.day
            t.isBank = true; t.source = "file"; t.fp = m.fp
            if t.notes.trimmed.isEmpty { t.notes = m.row.purpose }
            if let cid = m.captureId { TapSettle.settledByFile(captureId: cid, txn: t, kind: m.kind, lag: m.lag, reason: m.reason, ctx: ctx) }
            res.confirmed += 1
        }
        TapSettle.markOrphans(plan.orphanTaps, ctx: ctx)
        remember(st, accountId)
        try? ctx.save()
        TapSettle.run(ctx: ctx)
        // Check the balance against the statement's own closing balance.
        let accounts = (try? ctx.fetch(FetchDescriptor<Account>())) ?? []
        // Cards: only a PDF statement says for sure that its closing balance is what you owe.
        if let c = st.closing, let a = accounts.first(where: { $0.id == accountId }), !a.isCredit || st.format == "PDF" {
            let L = Ledger.build(accounts: accounts, txs: (try? ctx.fetch(FetchDescriptor<Txn>())) ?? [])
            res.closing = (c.day, Double(c.cents) / 100, (L.balance(of: a.snap, on: c.day) * 100).rounded() / 100)
            setCheckpoint(accountId, day: c.day, cents: c.cents)
        }
        return res
    }

    // ── The last statement balance per account, checked again on Home ──
    private static let cpKey = "mt-statement-checkpoints"
    static func checkpoints() -> [String: (day: String, cents: Int)] {
        let raw = UserDefaults.standard.dictionary(forKey: cpKey) as? [String: String] ?? [:]
        return raw.compactMapValues { v in
            let p = v.split(separator: "|")
            guard p.count == 2, let c = Int(p[1]) else { return nil }
            return (String(p[0]), c)
        }
    }
    private static func setCheckpoint(_ accountId: String, day: String, cents: Int) {
        var raw = UserDefaults.standard.dictionary(forKey: cpKey) as? [String: String] ?? [:]
        if let old = raw[accountId], old.split(separator: "|").first.map(String.init) ?? "" > day { return }   // keep the newest
        raw[accountId] = "\(day)|\(cents)"
        UserDefaults.standard.set(raw, forKey: cpKey)
    }
    /// Accounts whose balance no longer matches their last statement.
    static func drift(_ L: Ledger) -> [(acc: AccSnap, day: String, file: Double, app: Double)] {
        checkpoints().compactMap { id, cp in
            guard let a = L.account(id), !a.isBank else { return nil }
            let app = (L.balance(of: a, on: cp.day) * 100).rounded() / 100, file = Double(cp.cents) / 100
            return abs(app - file) >= 0.005 ? (a, cp.day, file, app) : nil
        }.sorted { $0.acc.name < $1.acc.name }
    }

    /// A balance in words: "78,85 € owed" on a card (its balance is negative when you owe).
    static func label(_ v: Double, credit: Bool) -> String {
        credit ? "\(Fmt.money(abs(v))) \(v <= 0 ? "owed" : "in credit")" : Fmt.money(v)
    }

    /// Makes the starting balance agree with the statement (hand-managed accounts only).
    static func matchStartingBalance(accountId: String, file: Double, app: Double, ctx: ModelContext) {
        guard let a = try? ctx.fetch(FetchDescriptor<Account>()).first(where: { $0.id == accountId }), !a.isSynced else { return }
        a.initialBalance += file - app
        try? ctx.save()
    }
}
