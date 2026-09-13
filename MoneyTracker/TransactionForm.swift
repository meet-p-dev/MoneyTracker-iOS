import SwiftUI
import SwiftData

// Add / edit a transaction — the web app's TxSheet, with Apple's feel:
//  · five directions: Expense · Income · Received (in, not income) · Sent out (out, not
//    spending) · Transfer (between your accounts, e.g. paying your card);
//  · the amount is the hero; quick +1 … +50 buttons; recent shops; account and category chips;
//  · a BANK row keeps the bank's direction, amount, date and account — your edit re-labels it
//    and is remembered as a decision, so it can never silently move your balance;
//  · "My share" on an expense (what it really cost you).
struct TransactionForm: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortIndex) private var accounts: [Account]
    @Query private var catsRaw: [TxCategory]
    @Query(sort: \Txn.date, order: .reverse) private var allTxs: [Txn]

    let existing: Txn?
    var prefill: TxPrefill? = nil

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
    @State private var showNewCat = false
    @FocusState private var amountFocused: Bool

    private let kinds: [(id: String, label: String, icon: String)] = [
        ("expense", "Expense", "arrow.up.right"), ("income", "Income", "arrow.down.left"),
        ("credit", "Received", "arrow.triangle.2.circlepath"), ("debit", "Sent out", "arrow.left.arrow.right"),
        ("transfer", "Transfer", "arrow.left.arrow.right.circle"),
    ]

    /// Built-in categories in the web app's order, then your own alphabetically.
    private var cats: [TxCategory] {
        let order = Dictionary(uniqueKeysWithValues: BackupService.builtInCats.enumerated().map { ($1.id, $0) })
        return catsRaw.sorted { a, b in
            switch (order[a.id], order[b.id]) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.label < b.label
            }
        }
    }
    private var recentMerchants: [String] {
        var seen = Set<String>(), out: [String] = []
        for t in allTxs where !t.merchant.trimmed.isEmpty && t.type == "expense" {
            let m = t.merchant.trimmed
            if seen.insert(m.lowercased()).inserted { out.append(m) }
            if out.count == 8 { break }
        }
        return out
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    typeGrid
                    heroAmount
                    if !isBankRow { quickAmounts }
                    merchantField
                    accountChips
                    if type == "transfer" { toAccountChips } else { categoryChips }
                    dateAndShare
                    field("Notes (optional)") {
                        TextField("Any notes…", text: $notes, axis: .vertical).lineLimit(1...4)
                    }
                    let tips = headsUps
                    if !tips.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(tips, id: \.self) { Label($0, systemImage: "info.circle").font(.system(size: 12.5)).foregroundStyle(Color.mtTxt2) }
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.mtCard, in: RoundedRectangle(cornerRadius: MT.inner, style: .continuous))
                    }
                    if isBankRow {
                        Text("This came from your bank, so the amount, date and account stay as the bank booked them. You can change what it is.")
                            .font(.system(size: 12)).foregroundStyle(Color.mtTxt2)
                    }
                    Button(action: save) {
                        Text(existing == nil ? "Add Transaction" : "Save Changes").font(.system(size: 16, weight: .bold))
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent).tint(accent(type)).disabled(!canSave)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .mtCanvas()
            .navigationTitle(existing == nil ? "New Transaction" : "Edit Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!canSave) }
            }
            .onAppear(perform: load)
            .sheet(isPresented: $showNewCat) {
                CategoryForm(existing: nil) { id in categoryId = id; catTouched = true }
            }
        }
        .presentationDetents([.large])
    }

    // ── Pieces ──
    private var typeGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow { kindButton(kinds[0]); kindButton(kinds[1]) }
                GridRow { kindButton(kinds[2]); kindButton(kinds[3]) }
                GridRow { kindButton(kinds[4]).gridCellColumns(2) }
            }
            Text(kindHelp).font(.system(size: 12)).foregroundStyle(Color.mtTxt2).padding(.horizontal, 2)
                .contentTransition(.opacity).animation(.snappy, value: type)
        }
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
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(on ? accent(k.id) : Color.mtCard, in: RoundedRectangle(cornerRadius: MT.inner, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: MT.inner, style: .continuous).stroke(on ? accent(k.id) : Color.mtBorder, lineWidth: 1.5))
                .foregroundStyle(on ? Color.white : Color.mtTxt2)
        }
        .buttonStyle(.press)
    }

    private var heroAmount: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text((type == "expense" || type == "debit" ? "−" : type == "transfer" ? "" : "+") + Fmt.currencySymbol)
                .font(.system(size: 24, weight: .semibold)).foregroundStyle(Color.mtTxt3)
            TextField("0", text: $amount)
                .font(.system(size: 44, weight: .bold)).kerning(-1).monospacedDigit()
                .foregroundStyle(accent(type))
                .keyboardType(.decimalPad).focused($amountFocused)
                .multilineTextAlignment(.center).fixedSize()
                .disabled(isBankRow)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { if !isBankRow { amountFocused = true } }
        .animation(.snappy, value: type)
    }

    private var quickAmounts: some View {
        HStack(spacing: 7) {
            ForEach([1, 5, 10, 20, 50], id: \.self) { v in
                Button {
                    let cur = Fmt.amount(amount) ?? 0
                    amount = Fmt.editable(((cur + Double(v)) * 100).rounded() / 100); Haptic.tap()
                } label: {
                    Text("+\(v)").font(.system(size: 14, weight: .semibold)).monospacedDigit().frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(Color.mtCard, in: Capsule()).overlay(Capsule().stroke(Color.mtBorder, lineWidth: 1.5))
                }
                .buttonStyle(.press).foregroundStyle(.primary)
            }
            Button { amount = ""; Haptic.tap() } label: {
                Text("C").font(.system(size: 14, weight: .bold)).padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Color.mtCard, in: Capsule()).overlay(Capsule().stroke(Color.mtBorder, lineWidth: 1.5))
            }
            .buttonStyle(.press).foregroundStyle(Color.mtRed)
        }
    }

    private var merchantField: some View {
        VStack(alignment: .leading, spacing: 8) {
            field(type == "income" ? "Source" : "Merchant / payee") {
                TextField(type == "income" ? "e.g. Salary, ZenJob…" : "e.g. Kaufland, Apple Music…", text: $merchant)
                    .textInputAutocapitalization(.words)
                    .onChange(of: merchant) { _, m in
                        // Type a shop and its category fills itself in (what you taught > known shops);
                        // never overrides a category you picked yourself.
                        guard existing == nil, type == "expense", !catTouched,
                              let c = Classifier.suggestCategory(merchant: m, payeeStats: LearningStore.shared.payeeStats) else { return }
                        withAnimation(.snappy) { categoryId = c }
                    }
            }
            if existing == nil && !recentMerchants.isEmpty {
                chipScroll {
                    ForEach(recentMerchants, id: \.self) { m in
                        ChipButton(title: m, on: false) { merchant = m }
                    }
                }
            }
        }
    }

    private var accountChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            label(type == "transfer" ? "From account" : "Account")
            chipScroll {
                ForEach(accounts) { a in
                    ChipButton(title: a.name, dot: Color(hex: a.colorHex), on: accountId == a.id) { accountId = a.id }
                        .disabled(isBankRow && accountId != a.id)
                }
            }
        }
    }

    private var toAccountChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("To account")
            chipScroll {
                // The account the money leaves can't also be where it arrives.
                ForEach(accounts.filter { $0.id != accountId }) { a in
                    ChipButton(title: a.name, dot: Color(hex: a.colorHex), on: toAccountId == a.id) { toAccountId = a.id }
                }
            }
        }
    }

    private var categoryChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("Category")
            ScrollViewReader { proxy in
                chipScroll {
                    ForEach(cats) { c in
                        let sym = catSymbol(c)
                        ChipButton(title: sym == nil ? "\(c.icon) \(c.label)" : c.label, systemImage: sym,
                                   on: categoryId == c.id, tint: Color(hex: c.colorHex)) {
                            categoryId = c.id; catTouched = true
                        }
                        .id(c.id)
                    }
                    ChipButton(title: "New", systemImage: "plus", on: false) { showNewCat = true }
                }
                .onAppear { proxy.scrollTo(categoryId, anchor: .center) }
                .onChange(of: categoryId) { _, id in withAnimation { proxy.scrollTo(id, anchor: .center) } }
            }
        }
    }

    private var dateAndShare: some View {
        HStack(alignment: .top, spacing: 10) {
            field("Date") {
                DatePicker("", selection: $date, displayedComponents: .date).labelsHidden().disabled(isBankRow)
            }
            if type == "expense" {
                field("My share (optional)") {
                    TextField(amountValue.map { "Full \(Fmt.money($0))" } ?? "Full amount", text: $share).keyboardType(.decimalPad)
                }
            }
        }
    }

    private func label(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 11, weight: .semibold)).kerning(1.1).foregroundStyle(Color.mtTxt3).padding(.horizontal, 2)
    }
    private func field<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            label(title)
            content()
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.mtCard, in: RoundedRectangle(cornerRadius: MT.inner, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: MT.inner, style: .continuous).stroke(Color.mtBorder, lineWidth: 1))
        }
    }
    private func chipScroll<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) { content() }.padding(.horizontal, 16).padding(.vertical, 2)
        }
        .padding(.horizontal, -16)
    }

    private func accent(_ k: String) -> Color {
        switch k { case "expense": .mtRed; case "income": .mtGreen; case "credit": .mtRecv; case "debit": .gray; default: .mtAcc }
    }
    private var kindHelp: String {
        switch type {
        case "expense": "Money you spent."
        case "income": "Money you earned, like salary."
        case "credit": "Money back, like a refund or a friend paying you back."
        case "debit": "Money out that isn't spending, like paying someone back."
        default: "Between your own accounts, like paying your credit card."
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
                out.append("Before \(a.name)'s starting date (\(Fmt.shortDay(a.ibDate))). It won't change \(a.name)'s balance.")
            }
            if existing == nil && a.isSynced {
                out.append("\(a.name) syncs from your bank. If this happened there, it will show up on its own. Adding it here counts it twice.")
            }
        }
        return out
    }

    // ── Load / save (unchanged rules from Phase 1–2) ──
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
        } else if let p = prefill {
            type = p.type; amount = Fmt.editable(p.amount); merchant = p.merchant; categoryId = "transfer"
            accountId = p.accountId; toAccountId = p.toAccountId; notes = p.notes; catTouched = true
        } else {
            catTouched = false
            accountId = UserDefaults.standard.string(forKey: "lastAccount").flatMap { id in accounts.first { $0.id == id }?.id }
                ?? accounts.first?.id ?? ""
            categoryId = UserDefaults.standard.string(forKey: "lastCategory") ?? "other"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { amountFocused = true }
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
