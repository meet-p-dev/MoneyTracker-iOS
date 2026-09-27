import SwiftUI
import SwiftData

// Apple Pay taps (Tap & Settle): the "check" sheet, the Settings screen with setup, cards
// and recent taps, and the small pending row used on Home.

/// A tap in a list: its merchant, card or account, and what happened to it.
struct TapRow: View {
    let c: Capture
    let accounts: [Account]
    var body: some View {
        HStack(spacing: 12) {
            Monogram(name: c.title, cat: nil, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(c.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(TapText.badge(c)).font(.system(size: 10, weight: .semibold)).padding(.horizontal, 5).padding(.vertical, 1)
                        .background(TapText.tone(c).opacity(0.14), in: RoundedRectangle(cornerRadius: 6)).foregroundStyle(TapText.tone(c))
                }
                Text("\(accounts.first { $0.id == c.accountId }?.name ?? (c.card.isEmpty ? "Apple Pay" : c.card)) · \(Fmt.prettyDay(c.day)), \(c.at.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11)).foregroundStyle(Color.mtTxt2).lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(TapText.amount(c)).money(14).foregroundStyle(c.isOpen ? Color.mtTxt2 : Color.primary)
        }
        .contentShape(Rectangle())
    }
}

enum TapText {
    static func amount(_ c: Capture) -> String {
        if c.cents == 0 { return "no amount" }
        if !c.cur.isEmpty && c.cur != TapSettle.home { return "−" + c.amount.formatted(.currency(code: c.cur)) }
        return "−" + Fmt.money(c.amount)
    }
    static func badge(_ c: Capture) -> String {
        switch c.state {
        case "pending": c.accountId.isEmpty ? "link card" : "pending"
        case "check": "check"
        case "settled": "matched"
        case "orphan": "not booked"
        case "added", "kept": "added"
        default: "removed"
        }
    }
    static func tone(_ c: Capture) -> Color {
        switch c.state {
        case "pending": .mtAmber
        case "check", "orphan": .mtAcc
        case "settled", "added", "kept": .mtGreen
        default: .mtTxt3
        }
    }
    /// Taps that need you: a card to link, a match to confirm, an amount, or one the bank never booked.
    static func needsYou(_ caps: [Capture], _ accounts: [Account]) -> [Capture] {
        caps.filter { c in
            (c.isOpen && c.accountId.isEmpty) || c.state == "check" || c.state == "orphan" || TapSettle.needsAmount(c, accounts)
        }
    }
    /// Taps on bank-synced accounts the bank hasn't booked yet: shown next to the balance, never
    /// inside it. (A tap waiting for your check already has its bank row in the balance.)
    static func pending(_ caps: [Capture], _ accounts: [Account]) -> [Capture] {
        let feed = Set(accounts.filter(\.isSynced).map(\.id))
        return caps.filter { $0.state == "pending" && $0.cents > 0 && feed.contains($0.accountId) }
    }
}

// ── The check sheet ──
struct TapReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Account.sortIndex) private var accounts: [Account]
    @Query private var txs: [Txn]
    @Query(sort: \Capture.at, order: .reverse) private var caps: [Capture]
    @State private var amounts: [String: String] = [:]

    var body: some View {
        let L = Ledger.build(accounts: accounts, txs: txs)
        let unlinked = Dictionary(grouping: caps.filter { $0.isOpen && $0.accountId.isEmpty }, by: \.card)
        let checks = caps.filter { $0.state == "check" }
        let noAmount = caps.filter { TapSettle.needsAmount($0, accounts) }
        let orphans = caps.filter { $0.state == "orphan" }
        return NavigationStack {
            List {
                if unlinked.isEmpty && checks.isEmpty && noAmount.isEmpty && orphans.isEmpty {
                    ContentUnavailableView("Nothing to check", systemImage: "checkmark.circle",
                        description: Text("Apple Pay payments that need a quick answer show up here."))
                        .listRowBackground(Color.clear)
                }
                if !unlinked.isEmpty {
                    Section {
                        ForEach(unlinked.keys.sorted(), id: \.self) { card in
                            let n = unlinked[card]?.count ?? 0
                            Menu {
                                ForEach(accounts) { a in Button(a.name) { TapSettle.link(card: card, to: a.id, ctx: ctx); Haptic.success() } }
                            } label: {
                                LabeledContent {
                                    Text("Choose").foregroundStyle(Color.mtAcc)
                                } label: {
                                    Text(card.isEmpty ? "Card without a name" : card).font(.subheadline.weight(.semibold))
                                    Text("\(n) payment\(n == 1 ? "" : "s") waiting").font(.caption)
                                }
                            }
                        }
                    } header: { Text("Which account is this card?") } footer: {
                        Text("Asked once per card. Payments from a card on an account you manage by hand become expenses right away.")
                    }
                }
                if !checks.isEmpty {
                    Section {
                        ForEach(checks) { c in check(c, L.rows.first { $0.id == c.linkId }) }
                    } header: { Text("Same purchase?") } footer: {
                        Text("The bank's row always keeps its own amount and date.")
                    }
                }
                if !noAmount.isEmpty {
                    Section("Add the amount") {
                        ForEach(noAmount) { c in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.title).font(.subheadline.weight(.semibold))
                                    Text(c.cents == 0 ? "Wallet sent no amount" : "Paid \(TapText.amount(c)). What did it cost in \(TapSettle.home)?")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                TextField(Fmt.currencySymbol, text: Binding(get: { amounts[c.id] ?? "" }, set: { amounts[c.id] = $0 }))
                                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                                Button("Save") {
                                    if let v = Fmt.amount(amounts[c.id] ?? "") { TapSettle.setAmount(c, v, ctx: ctx); Haptic.success() }
                                }
                                .buttonStyle(.borderless).disabled(Fmt.amount(amounts[c.id] ?? "") == nil)
                            }
                        }
                    }
                }
                if !orphans.isEmpty {
                    Section {
                        ForEach(orphans) { c in orphan(c, L) }
                    } header: { Text("Not in your bank data") } footer: {
                        Text("Your bank has synced past these days, but never booked them. Often a declined or cancelled payment.")
                    }
                }
            }
            .navigationTitle("Apple Pay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func check(_ c: Capture, _ r: Row?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            side("Apple Pay", c.title, TapText.amount(c), "\(Fmt.prettyDay(c.day)), \(c.at.formatted(date: .omitted, time: .shortened))")
            if let r {
                side("Bank", r.merchant.isEmpty ? "Bank transaction" : r.merchant, "−" + Fmt.money(r.amount),
                     "\(Fmt.prettyDay(r.date)) · \(accounts.first { $0.id == r.accountId }?.name ?? "")")
            }
            if !c.reason.isEmpty { Text(c.reason).font(.caption2).foregroundStyle(.secondary) }
            HStack(spacing: 8) {
                Button { withAnimation { TapSettle.confirm(c, ctx: ctx) }; Haptic.success() } label: {
                    Text("Yes, same").font(.footnote.weight(.bold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(Color.mtAcc.opacity(0.14), in: RoundedRectangle(cornerRadius: MT.inner)).foregroundStyle(Color.mtAcc)
                }
                Button { withAnimation { TapSettle.reject(c, ctx: ctx) } } label: {
                    Text("No, different").font(.footnote.weight(.bold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: MT.inner)).foregroundStyle(.primary)
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func side(_ label: String, _ title: String, _ amount: String, _ sub: String) -> some View {
        HStack(spacing: 10) {
            Text(label.uppercased()).font(.system(size: 9, weight: .bold)).kerning(0.6).foregroundStyle(Color.mtTxt3).frame(width: 62, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(amount).font(.subheadline.weight(.bold)).monospacedDigit()
        }
    }

    private func orphan(_ c: Capture, _ L: Ledger) -> some View {
        let rows = TapSettle.pickable(c, L, caps)
        let hand = accounts.filter { !$0.isSynced }
        return VStack(alignment: .leading, spacing: 10) {
            TapRow(c: c, accounts: accounts)
            HStack(spacing: 8) {
                Button("Not charged") { withAnimation { TapSettle.dismiss(c, ctx: ctx) } }
                if !rows.isEmpty {
                    Menu("Pick the bank row") {
                        ForEach(rows) { r in
                            Button("\(r.merchant.isEmpty ? "Bank" : r.merchant) · −\(Fmt.money(r.amount)) · \(Fmt.shortDay(r.date))") {
                                withAnimation { TapSettle.confirm(c, bankId: r.id, ctx: ctx) }; Haptic.success()
                            }
                        }
                    }
                }
                if !hand.isEmpty && c.cents > 0 {
                    Menu("Paid another way") {
                        ForEach(hand) { a in Button(a.name) { withAnimation { TapSettle.keep(c, on: a, ctx: ctx) }; Haptic.success() } }
                    }
                }
            }
            .font(.footnote.weight(.semibold))
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

// ── Settings → Apple Pay ──
struct ApplePayView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Account.sortIndex) private var accounts: [Account]
    @Query(sort: \Capture.at, order: .reverse) private var caps: [Capture]
    @State private var cardMap = TapSettle.memory.cardMap
    @State private var log = TapSettle.readLog()
    @State private var showCheck = false
    @State private var confirmClear = false
    #if DEBUG
    @State private var testMerchant = "REWE"
    @State private var testAmount = "12,50"
    @State private var testCard = "Test card"
    #endif

    var body: some View {
        let needs = TapText.needsYou(caps, accounts).count
        let cards = Set(cardMap.keys).union(caps.map(\.card)).sorted()
        return Form {
            Section {
                Text("Pay with Apple Pay and the payment appears here by itself. On a bank-synced account it waits as Pending until your bank books it, then the bank's row takes over. On an account you manage by hand it becomes an expense right away.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if needs > 0 {
                    Button { showCheck = true } label: {
                        LabeledContent { Text("\(needs)").foregroundStyle(Color.mtAcc) } label: { Label("Check payments", systemImage: "tray.full") }
                    }
                }
            }
            Section {
                step(1, "Open Shortcuts, go to Automation and tap +.")
                step(2, "Choose Wallet. Pick your payment cards and choose Run Immediately.")
                step(3, "Add the action \"Log Apple Pay payment\" from MoneyTrack.")
                step(4, "Fill its fields from the Shortcut Input: Merchant, Amount, Card, and Name. Set each one directly, not through another shortcut.")
                step(5, "Pay once. The payment shows up below.")
                Link(destination: URL(string: "shortcuts://")!) { Label("Open Shortcuts", systemImage: "arrow.up.forward.app") }
            } header: { Text("Set it up once") } footer: {
                Text("Only in-store Apple Pay payments are caught. Online payments, the physical card, direct debits and income come from your bank sync or you add them yourself.")
            }
            if !cards.isEmpty {
                Section {
                    ForEach(cards, id: \.self) { card in
                        Menu {
                            ForEach(accounts) { a in
                                Button(a.name) { TapSettle.link(card: card, to: a.id, ctx: ctx); cardMap = TapSettle.memory.cardMap }
                            }
                            if cardMap[card] != nil {
                                Button("Unlink", role: .destructive) { TapSettle.unlink(card: card); cardMap = TapSettle.memory.cardMap }
                            }
                        } label: {
                            LabeledContent(card.isEmpty ? "Card without a name" : card) {
                                Text(accounts.first { $0.id == cardMap[card] }?.name ?? "Not linked")
                                    .foregroundStyle(cardMap[card] == nil ? Color.mtAmber : Color.secondary)
                            }
                        }
                    }
                } header: { Text("Your cards") } footer: { Text("Card names stay on this iPhone.") }
            }
            Section("Recent payments") {
                if caps.isEmpty {
                    Text("No Apple Pay payments yet.").foregroundStyle(.secondary)
                }
                ForEach(caps.prefix(30)) { c in
                    VStack(alignment: .leading, spacing: 4) {
                        TapRow(c: c, accounts: accounts)
                        if !c.reason.isEmpty { Text(c.reason).font(.caption2).foregroundStyle(.secondary) }
                    }
                    .swipeActions {
                        if c.state == "settled" {
                            Button("Undo") { withAnimation { TapSettle.undo(c, ctx: ctx) } }.tint(.orange)
                        } else if c.state == "added" || c.state == "kept" {
                            Button("Remove", role: .destructive) { withAnimation { TapSettle.undo(c, ctx: ctx) } }
                        } else if c.isOpen || c.state == "orphan" {
                            Button("Not charged", role: .destructive) { withAnimation { TapSettle.dismiss(c, ctx: ctx) } }
                        }
                    }
                }
            }
            Section {
                if log.isEmpty {
                    Text("Empty. Each payment adds a line here.").foregroundStyle(.secondary)
                }
                ForEach(log) { e in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(e.at.formatted(date: .abbreviated, time: .shortened)) · \(e.result)").font(.caption.weight(.semibold))
                        Text("Card: \(e.card.isEmpty ? "–" : e.card)   Merchant: \(e.merchant.isEmpty ? "–" : e.merchant)").font(.caption2)
                        Text("Amount: \(e.typed.isEmpty ? "–" : e.typed)   Text: \(e.text.isEmpty ? "–" : e.text)   Name: \(e.name.isEmpty ? "–" : e.name)").font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
                if !log.isEmpty { Button("Clear the log", role: .destructive) { confirmClear = true } }
            } header: { Text("What Wallet sent") } footer: {
                Text("Exactly what each payment passed to MoneyTrack. Useful to check a card works. Stays on this iPhone.")
            }
            #if DEBUG
            Section("Test a payment (debug builds only)") {
                TextField("Merchant", text: $testMerchant)
                TextField("Amount", text: $testAmount).keyboardType(.decimalPad)
                TextField("Card", text: $testCard)
                Button("Log it") {
                    TapSettle.intake(ctx: ctx, merchant: testMerchant, name: nil, card: testCard, amount: nil, code: nil,
                                     text: testAmount + " " + Fmt.currencySymbol)
                    log = TapSettle.readLog(); cardMap = TapSettle.memory.cardMap
                }
                Button("Add a demo bank account with 3 bank rows") { demoBank() }
                Button("Remove the demo bank account", role: .destructive) {
                    for a in accounts where a.id == "sb-demo" { ctx.delete(a) }
                    for t in (try? ctx.fetch(FetchDescriptor<Txn>())) ?? [] where t.id.hasPrefix("sb-demo-") { ctx.delete(t) }
                    try? ctx.save(); TapSettle.run(ctx: ctx)
                }
            }
            #endif
        }
        .navigationTitle("Apple Pay")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCheck) { TapReviewSheet() }
        .confirmationDialog("Clear the log?", isPresented: $confirmClear) {
            Button("Clear", role: .destructive) { TapSettle.clearLog(); log = [] }
        }
        .onAppear { log = TapSettle.readLog(); cardMap = TapSettle.memory.cardMap; TapSettle.run(ctx: ctx) }
    }

    #if DEBUG
    /// Fake bank data for the simulator (it can't sign in to bank sync): rows booked the way a
    /// German bank books card payments, with the till's time in the text.
    private func demoBank() {
        guard !accounts.contains(where: { $0.id == "sb-demo" }) else { return }
        let a = Account(id: "sb-demo", name: "Demo Bank", colorHex: "#e11d48", initialBalance: 500, sortIndex: 99)
        a.isBank = true
        ctx.insert(a)
        let now = Date()
        let rows: [(String, Double, Int, String)] = [
            ("REWE SAGT DANKE", 12.50, 0, "Debitk.15 2026-12"),
            ("Adyen N.V.", 23.99, -60, "Debitk.15 2026-12"),
            ("Stadtwerke", 45.00, 0, "SEPA-BASISLASTSCHRIFT MREF+12345"),
        ]
        for (i, r) in rows.enumerated() {
            let till = now.addingTimeInterval(Double(r.2 * 60))
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd'T'HH:mm"
            let stamp = f.string(from: till)
            let t = Txn(id: "sb-demo-\(i)", type: "expense", amount: r.1, merchant: r.0, categoryId: "other", accountId: a.id,
                        notes: i < 2 ? "\(stamp)      \(r.3)" : r.3, date: Fmt.today())
            t.isBank = true
            ctx.insert(t)
        }
        try? ctx.save()
        TapSettle.run(ctx: ctx)
    }
    #endif

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)").font(.caption.weight(.bold)).frame(width: 20, height: 20)
                .background(Color.mtAcc.opacity(0.14), in: Circle()).foregroundStyle(Color.mtAcc)
            Text(text).font(.subheadline)
        }
    }
}
