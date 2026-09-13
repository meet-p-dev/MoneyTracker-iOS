import SwiftUI
import SwiftData

struct AccountsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Account.sortIndex) private var accounts: [Account]
    @Query(sort: \Txn.date, order: .reverse) private var txs: [Txn]
    @State private var editAcc: Account?
    @State private var showAdd = false
    @State private var fixIssue: Ledger.Issue?

    var body: some View {
        let L = Ledger.build(accounts: accounts, txs: txs)
        return List {
            if !L.issues.isEmpty {
                Section { ForEach(L.issues) { i in IssueBanner(issue: i) { fixIssue = i } } }
            }
            if accounts.isEmpty {
                ContentUnavailableView {
                    Label("No accounts yet", systemImage: "wallet.bifold")
                } description: {
                    Text("Add an account you track by hand — cash, a card — or restore your web backup in Settings.")
                } actions: {
                    Button("Add an account") { showAdd = true }.buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            }
            let cash = accounts.filter { !$0.isCredit }
            if !cash.isEmpty {
                Section {
                    ForEach(cash) { a in cashRow(a, L) }
                } header: { Text("Accounts") } footer: {
                    Text("Net worth \(Fmt.money(L.netWorth)) — your cash minus what the cards owe.")
                }
            }
            let cards = accounts.filter(\.isCredit)
            if !cards.isEmpty {
                Section("Credit cards") { ForEach(cards) { c in cardRow(c, L) } }
            }
        }
        .navigationTitle("Accounts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } }
        }
        .sheet(item: $editAcc) { AccountForm(existing: $0) }
        .sheet(isPresented: $showAdd) { AccountForm(existing: nil) }
        .sheet(item: $fixIssue) { i in AccountForm(existing: accounts.first { $0.id == i.acc.id }, hint: i) }
    }

    private func count(_ a: Account) -> Int { txs.filter { $0.accountId == a.id || $0.toAccountId == a.id }.count }

    private func cashRow(_ a: Account, _ L: Ledger) -> some View {
        let bal = L.balance(a.id)
        return HStack(spacing: 12) {
            Circle().fill(Color(hex: a.colorHex)).frame(width: 40, height: 40)
                .overlay(Text(String(a.name.prefix(1))).font(.headline).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(a.name).fontWeight(.semibold).lineLimit(1)
                    if a.isSynced { Image(systemName: "building.columns.fill").font(.caption2).foregroundStyle(.secondary) }
                }
                Text("\(count(a)) transactions · initial \(Fmt.money(a.initialBalance))\(a.ibDate.isEmpty ? "" : " on \(Fmt.shortDay(a.ibDate))")")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(Fmt.money(bal)).monospacedDigit().fontWeight(.bold).foregroundStyle(bal >= 0 ? Color.green : Color.red)
        }
        .contentShape(Rectangle())
        .onTapGesture { editAcc = a }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { ctx.delete(a); try? ctx.save() } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func cardRow(_ c: Account, _ L: Ledger) -> some View {
        let s = L.cardStats(c.snap)
        let due = s.amountDue <= 0 ? "No bill due"
            : s.overdue ? "Overdue · \(Fmt.money(s.amountDue))"
            : s.daysToDue == 0 ? "Due today · \(Fmt.money(s.amountDue))" : "Due in \(s.daysToDue)d · \(Fmt.money(s.amountDue))"
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "creditcard.fill").foregroundStyle(Color(hex: c.colorHex))
                Text(c.name).fontWeight(.semibold)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Fmt.money(s.currentBalance)).monospacedDigit().fontWeight(.bold)
                    Text("owed").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            if s.limit > 0 {
                ProgressView(value: min(max(s.util, 0), 1)).tint(s.util >= 0.7 ? .orange : .green)
            }
            HStack {
                Text("Statement \(Fmt.money(s.statementBalance)) · unbilled \(Fmt.money(s.unbilled))")
                Spacer()
                Text(due).foregroundStyle(s.overdue ? .red : s.dueSoon ? .orange : .secondary)
            }
            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { editAcc = c }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { ctx.delete(c); try? ctx.save() } label: { Label("Delete", systemImage: "trash") }
        }
    }
}

// Add / edit an account or credit card — mirrors the web app's AccSheet + doAddAcc.
struct AccountForm: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortIndex) private var all: [Account]
    @Query private var txs: [Txn]
    let existing: Account?
    var hint: Ledger.Issue? = nil

    @State private var kind = "cash"
    @State private var name = ""
    @State private var color = Color(hex: "#3b82f6")
    @State private var balMode = "start"          // cash: "start" | "today"
    @State private var ib = ""
    @State private var today = ""
    @State private var owed = ""
    @State private var hasDate = true
    @State private var startDate = Date()
    @State private var limit = ""
    @State private var statementDay = 1
    @State private var dueDay = 15
    @State private var apr = ""
    @State private var payFromId = ""
    @State private var autopay = false
    @State private var billPayee = ""
    @State private var showHint = false
    @State private var loaded = false

    private var isCard: Bool { kind == "credit" }
    private var isBank: Bool { existing?.isSynced ?? false }
    private var payFromBank: Bool { all.first { $0.id == payFromId }?.isSynced ?? false }

    var body: some View {
        NavigationStack {
            Form {
                if !isBank {
                    Picker("Type", selection: $kind) {
                        Text("Cash / Bank").tag("cash")
                        Text("Credit Card").tag("credit")
                    }
                    .pickerStyle(.segmented)
                }
                Section { TextField(isCard ? "Card name (e.g. Advanzia)" : "Account name", text: $name) }

                if isCard { cardSections } else { cashSection }

                Section { ColorPicker("Color", selection: $color, supportsOpacity: false) }
            }
            .navigationTitle(existing == nil ? (isCard ? "New Card" : "New Account") : (isCard ? "Edit Card" : "Edit Account"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(name.trimmed.isEmpty) }
            }
            .onAppear(perform: load)
        }
    }

    @ViewBuilder private var hintBox: some View {
        if showHint, let h = hint {
            VStack(alignment: .leading, spacing: 4) {
                Label("Suggested: \(Fmt.shortDay(h.date))", systemImage: "wand.and.stars").font(.subheadline.weight(.semibold))
                Text("\(h.n) older \(h.n == 1 ? "entry is" : "entries are") already inside the amount above but \(h.n == 1 ? "was" : "were") counted again. With this date: \(isCard ? "owes \(Fmt.money(max(-h.fixed, 0))) (was \(Fmt.money(max(-h.now, 0))))" : "\(Fmt.money(h.fixed)) (was \(Fmt.money(h.now)))"). Save to apply.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .listRowBackground(Color.orange.opacity(0.12))
        }
    }

    @ViewBuilder private var cashSection: some View {
        Section {
            Picker("Set it by", selection: $balMode) {
                Text("Starting balance").tag("start")
                Text("Balance today").tag("today")
            }
            .pickerStyle(.segmented)
            if balMode == "today" {
                amountField("Balance today", $today)
            } else {
                amountField("Starting balance", $ib)
                if !isBank {
                    Toggle("Count from a date", isOn: $hasDate.animation())
                    if hasDate { DatePicker("Balance on", selection: $startDate, displayedComponents: .date) }
                }
            }
            hintBox
        } header: { Text("Balance") } footer: {
            Text(balMode == "today"
                 ? "What this account shows right now — the starting balance is worked out from your transactions, so every past day is right too."
                 : isBank ? "Balance before the first synced transaction."
                 : "What the account had on that date. Anything older is already included — it stays in your history but won't change the balance again.")
        }
    }

    @ViewBuilder private var cardSections: some View {
        Section {
            amountField("Credit limit", $limit)
            amountField("Balance owed", $owed)
            Toggle("Owed on a date", isOn: $hasDate.animation())
            if hasDate { DatePicker("Owed on", selection: $startDate, displayedComponents: .date) }
            hintBox
        } header: { Text("Balance") } footer: {
            Text("Easiest: copy your last statement — its balance, and the day after it closed. Earlier bill payments from your bank are then already included, so they aren't counted again.")
        }
        Section {
            Stepper("Statement day: \(statementDay)", value: $statementDay, in: 1...31)
            Stepper("Due day: \(dueDay)", value: $dueDay, in: 1...31)
            amountField("APR % (optional)", $apr)
        } footer: { Text("The bill closes on the statement day; anything you spend after it rolls onto next month's bill.") }
        Section {
            Picker("Pay bill from", selection: $payFromId) {
                Text("Ask me each time").tag("")
                ForEach(all.filter { !$0.isCredit && $0.id != existing?.id }) { a in Text(a.name).tag(a.id) }
            }
            if payFromBank {
                Label("Bill payments from this bank come in with your bank sync and count on this card automatically.", systemImage: "building.columns")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Toggle("Auto-pay the bill on the due date", isOn: $autopay).disabled(payFromId.isEmpty)
            }
            TextField("Auto-match text (optional)", text: $billPayee)
        } footer: {
            Text("Card-bill payments from your bank are recognised automatically (\"Kreditkartenabrechnung\", \"creditcard bill\", the card's name…). Only add text here if your bank words it differently.")
        }
    }

    private func amountField(_ label: String, _ text: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0" + Fmt.decimalSeparator + "00", text: text).keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing).monospacedDigit()
        }
    }

    private func load() {
        guard !loaded else { return }; loaded = true
        guard let a = existing else { hasDate = true; startDate = Date(); return }
        kind = a.kind; name = a.name; color = Color(hex: a.colorHex)
        ib = Fmt.editable(a.initialBalance); owed = Fmt.editable(abs(a.initialBalance))
        limit = a.creditLimit > 0 ? Fmt.editable(a.creditLimit) : ""
        statementDay = max(a.statementDay, 1); dueDay = max(a.dueDay, 1)
        apr = a.apr > 0 ? Fmt.editable(a.apr) : ""
        payFromId = a.payFromId; autopay = a.autopay; billPayee = a.billPayee
        let L = Ledger.build(accounts: all, txs: txs)
        today = Fmt.editable((L.balance(a.id) * 100).rounded() / 100)
        balMode = a.isSynced ? "today" : "start"
        if let h = hint, a.ibDate.isEmpty {
            hasDate = true; startDate = Fmt.parse(h.date); showHint = true
        } else {
            hasDate = !a.ibDate.isEmpty; startDate = a.ibDate.isEmpty ? Date() : Fmt.parse(a.ibDate)
        }
    }

    private func save() {
        let a = existing ?? Account(name: name.trimmed, colorHex: color.toHex(),
                                    sortIndex: (all.map(\.sortIndex).max() ?? 0) + 1)
        var s = a.snap
        s.name = name.trimmed; s.colorHex = color.toHex(); s.kind = kind
        let date = hasDate && !isBank ? Fmt.day.string(from: startDate) : ""
        if isCard {
            s.ib = -abs(Fmt.amount(owed) ?? 0)
            s.creditLimit = Fmt.amount(limit) ?? 0
            s.statementDay = statementDay; s.dueDay = dueDay; s.apr = Fmt.amount(apr) ?? 0
            s.payFromId = payFromId; s.billPayee = billPayee.trimmed
            s.autopay = autopay && !payFromId.isEmpty && !payFromBank
            s.ibDate = date
        } else if balMode == "today" {
            // newIb = oldIb + (target − current): the computed balance becomes what you typed.
            let target = Fmt.amount(today) ?? 0
            if let e = existing {
                let current = Ledger.build(accounts: all, txs: txs).balance(e.id)
                s.ib = ((e.initialBalance + (target - current)) * 100).rounded() / 100
            } else { s.ib = target; s.ibDate = Fmt.today() }
        } else {
            s.ib = Fmt.amount(ib) ?? 0
            s.ibDate = date
        }
        a.apply(s)
        if existing == nil { ctx.insert(a) }
        // A bank account's balance/name/color live in your account, so every device agrees.
        if a.isSynced { CloudSync.shared.updateBankAccount(id: a.id, ib: s.ib, name: s.name, color: s.colorHex) }
        try? ctx.save(); Haptic.success(); dismiss()
    }
}
