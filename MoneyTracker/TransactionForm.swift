import SwiftUI
import SwiftData

// Add / edit a transaction — mirrors the web app's TxSheet + doAddTx:
//  · five directions: Expense · Income · Received (in, not income) · Sent out (out, not
//    spending) · Transfer (between your accounts, e.g. paying your card);
//  · a BANK row keeps the bank's direction, amount, date and account — your edit re-labels
//    it and is remembered as a decision, so it can never silently move your balance;
//  · "My share" on an expense (what it really cost you).
struct TransactionForm: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortIndex) private var accounts: [Account]
    @Query private var cats: [TxCategory]
    @Query private var allTxs: [Txn]

    let existing: Txn?

    @State private var type = "expense"
    @State private var amount = ""
    @State private var merchant = ""
    @State private var categoryId = "other"
    @State private var accountId = ""
    @State private var toAccountId = ""
    @State private var notes = ""
    @State private var date = Date()
    @State private var share = ""
    @State private var effOld: Row?
    @State private var catTouched = false
    @State private var loaded = false

    private let kinds: [(id: String, label: String, icon: String)] = [
        ("expense", "Expense", "arrow.up.right"), ("income", "Income", "arrow.down.left"),
        ("credit", "Received", "arrow.triangle.2.circlepath"), ("debit", "Sent out", "arrow.left.arrow.right"),
        ("transfer", "Transfer", "arrow.left.arrow.right.circle"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                        GridRow { kindButton(kinds[0]); kindButton(kinds[1]) }
                        GridRow { kindButton(kinds[2]); kindButton(kinds[3]) }
                        GridRow { kindButton(kinds[4]).gridCellColumns(2) }
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                } footer: { Text(kindHelp) }

                Section {
                    HStack {
                        Text(sign + Fmt.currencySymbol).foregroundStyle(.secondary)
                        TextField("0" + Fmt.decimalSeparator + "00", text: $amount)
                            .keyboardType(.decimalPad)
                            .font(.title2.weight(.bold)).monospacedDigit()
                            .disabled(isBankRow)
                    }
                    TextField(type == "income" ? "Source (e.g. Salary)" : "Merchant / payee", text: $merchant)
                        .onChange(of: merchant) { _, m in
                            // Type a shop and its category fills itself in (what you taught > known shops);
                            // never overrides a category you picked yourself.
                            guard existing == nil, type == "expense", !catTouched,
                                  let c = Classifier.suggestCategory(merchant: m, payeeStats: LearningStore.shared.payeeStats) else { return }
                            categoryId = c
                        }
                } footer: {
                    if isBankRow { Text("This came from your bank, so the amount, date and account stay as the bank booked them. You can change what it is.") }
                }

                Section {
                    Picker(type == "transfer" ? "From account" : "Account", selection: $accountId) {
                        ForEach(accounts) { a in Text(a.name).tag(a.id) }
                    }
                    .disabled(isBankRow)
                    if type == "transfer" {
                        Picker("To account", selection: $toAccountId) {
                            Text("Select…").tag("")
                            ForEach(accounts.filter { $0.id != accountId }) { a in Text(a.name).tag(a.id) }
                        }
                    } else {
                        Picker("Category", selection: Binding(get: { categoryId }, set: { categoryId = $0; catTouched = true })) {
                            ForEach(cats) { c in Text(c.label).tag(c.id) }
                        }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date).disabled(isBankRow)
                }

                if type == "expense" {
                    Section {
                        HStack {
                            Text("My share")
                            Spacer()
                            TextField(amountValue.map { "Full \(Fmt.money($0))" } ?? "Full amount", text: $share)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        }
                    } footer: { Text("Paid for others too (rent, a group dinner)? Enter just your part — that's what counts as your spending.") }
                }

                Section { TextField("Notes", text: $notes, axis: .vertical) }

                let tips = headsUps
                if !tips.isEmpty {
                    Section { ForEach(tips, id: \.self) { Label($0, systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary) } }
                }
            }
            .navigationTitle(existing == nil ? "New Transaction" : "Edit Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!canSave) }
            }
            .onAppear(perform: load)
        }
        .presentationDetents([.large])
    }

    private func kindButton(_ k: (id: String, label: String, icon: String)) -> some View {
        let on = type == k.id
        return Button {
            withAnimation(.snappy) {
                type = k.id
                if k.id == "credit" && !["reimburse", "refund", "transfer"].contains(categoryId) { categoryId = "reimburse" }
                if k.id == "debit" && !["transfer", "debt"].contains(categoryId) { categoryId = "transfer" }
            }
            Haptic.tap()
        } label: {
            Label(k.label, systemImage: k.icon)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(on ? accent(k.id) : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(on ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
    private func accent(_ k: String) -> Color {
        switch k { case "expense": .red; case "income": .green; case "credit": .teal; case "debit": .gray; default: .blue }
    }
    private var sign: String { type == "expense" || type == "debit" ? "− " : type == "transfer" ? "" : "+ " }
    private var kindHelp: String {
        switch type {
        case "expense": "Money you spent — counts in your spending."
        case "income": "Money you earned — salary, freelance."
        case "credit": "Money in that isn't income — a friend paying you back, a refund."
        case "debit": "Money out that isn't spending — e.g. to your own account, paying someone back."
        default: "Moving money between your own accounts — e.g. paying your credit card from your bank."
        }
    }

    private var isBankRow: Bool { existing?.isSynced ?? false }
    private var amountValue: Double? { Fmt.amount(amount).flatMap { $0 > 0 ? $0 : nil } }
    private var canSave: Bool { amountValue != nil && !accountId.isEmpty && (type != "transfer" || !toAccountId.isEmpty) }

    private var headsUps: [String] {
        let day = Fmt.day.string(from: date)
        var out: [String] = []
        for id in [accountId, type == "transfer" ? toAccountId : ""] where !id.isEmpty {
            guard let a = accounts.first(where: { $0.id == id }) else { continue }
            if !a.ibDate.isEmpty && day < a.ibDate {
                out.append("Before \(a.name)'s starting date (\(Fmt.shortDay(a.ibDate))) — it stays in your history but won't change \(a.name)'s balance.")
            }
            if existing == nil && a.isSynced {
                out.append("\(a.name) syncs from your bank. If this happened there, it will appear by itself — adding it by hand counts it twice.")
            }
        }
        return out
    }

    private func load() {
        guard !loaded else { return }; loaded = true
        if let t = existing {
            // Prefill from the EFFECTIVE row (what you see), amounts from the raw row.
            let eff = Ledger.build(accounts: accounts, txs: allTxs).rows.first { $0.id == t.id }
            effOld = eff
            type = eff?.type ?? t.type; categoryId = eff?.categoryId ?? t.categoryId
            toAccountId = eff?.toAccountId ?? t.toAccountId
            amount = Fmt.editable(t.amount); merchant = t.merchant; accountId = t.accountId
            notes = t.notes; date = Fmt.parse(t.date)
            share = LearningStore.shared.share(t.id).map(Fmt.editable) ?? ""
            catTouched = true
        } else {
            catTouched = false
            accountId = UserDefaults.standard.string(forKey: "lastAccount").flatMap { id in accounts.first { $0.id == id }?.id }
                ?? accounts.first?.id ?? ""
            categoryId = UserDefaults.standard.string(forKey: "lastCategory") ?? "other"
        }
    }

    private func save() {
        guard let v = amountValue else { return }
        let dayStr = Fmt.day.string(from: date)
        let isTrf = type == "transfer"
        let cat = isTrf ? "transfer" : categoryId
        let txId: String
        if let t = existing {
            txId = t.id
            t.merchant = merchant; t.notes = notes; t.categoryId = cat
            if t.isSynced {
                // The bank owns the cash facts; remember what you say it IS as a decision.
                if let e = effOld, e.type != type || e.categoryId != cat || (isTrf && e.toAccountId != toAccountId) {
                    LearningStore.shared.setDecision(Decision(type: type, category: cat, toAccountId: isTrf ? toAccountId : nil), for: t.id)
                    // Teach this payee too, so the next row from them is sorted the same way.
                    if let label = Classifier.labelCls.first(where: { $0.value.type == type && $0.value.category == cat })?.key {
                        let key = Classifier.counterpartyKey(merchant)
                        LearningStore.shared.updatePayeeStats { Classifier.bumpPayeeStats($0, key: key, label: label) }
                    }
                }
            } else {
                t.type = type; t.amount = v; t.accountId = accountId
                t.toAccountId = isTrf ? toAccountId : ""; t.date = dayStr
            }
        } else {
            let t = Txn(type: type, amount: v, merchant: merchant, categoryId: cat, accountId: accountId,
                        toAccountId: isTrf ? toAccountId : "", notes: notes, date: dayStr)
            ctx.insert(t); txId = t.id
        }
        // Learn the shop's category (bank rows AND manual entries), for next time.
        if type == "expense" && cat != "other" {
            let key = Classifier.counterpartyKey(merchant)
            LearningStore.shared.updatePayeeStats { Classifier.setPayeeCat($0, key: key, cat: cat) }
        }
        let s = Fmt.amount(share)
        if type == "expense", let s, s >= 0, s < v { LearningStore.shared.setShare(s, for: txId) }
        else { LearningStore.shared.setShare(nil, for: txId) }
        UserDefaults.standard.set(accountId, forKey: "lastAccount")
        UserDefaults.standard.set(categoryId, forKey: "lastCategory")
        try? ctx.save()
        Haptic.success()
        dismiss()
    }
}
