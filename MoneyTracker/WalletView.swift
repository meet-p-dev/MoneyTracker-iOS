import SwiftUI
import SwiftData
import TipKit

// Wallet — everything you HAVE (web V11): Accounts & cards · Debts · Goals · Categories.
struct WalletView: View {
    @Environment(Router.self) private var router
    @State private var showAddAccount = false
    @State private var showAddDebt = false
    @State private var showAddGoal = false
    @State private var showAddCategory = false

    var body: some View {
        @Bindable var router = router
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Picker("Section", selection: $router.walletSection) {
                        Text("Accounts").tag("accounts"); Text("Debts").tag("debts")
                        Text("Goals").tag("goals"); Text("Categories").tag("categories")
                    }
                    .pickerStyle(.segmented)
                    switch router.walletSection {
                    case "debts": DebtsSection(onAdd: { showAddDebt = true })
                    case "goals": GoalsSection(onAdd: { showAddGoal = true })
                    case "categories": CategoriesSection()
                    default: AccountsSection(onAdd: { showAddAccount = true })
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
                .animation(MT.spring, value: router.walletSection)
            }
            .mtCanvas()
            .navigationTitle("Wallet")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { add() } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAddAccount) { AccountForm(existing: nil) }
            .sheet(isPresented: $showAddDebt) { DebtForm() }
            .sheet(isPresented: $showAddGoal) { GoalForm(existing: nil) }
            .sheet(isPresented: $showAddCategory) { CategoryForm(existing: nil) }
        }
    }
    private func add() {
        switch router.walletSection {
        case "debts": showAddDebt = true
        case "goals": showAddGoal = true
        case "categories": showAddCategory = true
        default: showAddAccount = true
        }
    }
}

// ── Accounts & credit cards ──
struct AccountsSection: View {
    @Environment(\.modelContext) private var ctx
    @Environment(Router.self) private var router
    @Query(sort: \Account.sortIndex) private var accounts: [Account]
    @Query(sort: \Txn.date, order: .reverse) private var txs: [Txn]
    @State private var editAcc: Account?
    @State private var fixIssue: Ledger.Issue?
    @State private var showBankSync = false
    @State private var cardSheet: Account?
    let onAdd: () -> Void

    var body: some View {
        let L = Ledger.build(accounts: accounts, txs: txs)
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Net \(Fmt.money(L.netWorth))").money(15, .semibold)
                if L.creditOwed > 0 { Text("\(Fmt.money(L.assets)) cash − \(Fmt.money(L.creditOwed)) credit").font(.system(size: 12)).monospacedDigit().foregroundStyle(Color.mtTxt3) }
            }
            .padding(.horizontal, 4)
            ForEach(L.issues) { i in IssueBanner(issue: i) { fixIssue = i }.mtCard() }
            if accounts.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "wallet.bifold").font(.system(size: 34)).foregroundStyle(Color.mtTxt3)
                    Text("No accounts yet").font(.system(size: 17, weight: .bold))
                    Text("Connect a bank and your real accounts and transactions arrive on their own, updated 3× a day. Or add one by hand for cash and anything without a bank feed.")
                        .font(.system(size: 13.5)).foregroundStyle(Color.mtTxt2).multilineTextAlignment(.center)
                    Button("Connect a bank") { showBankSync = true }.buttonStyle(.glassProminent).padding(.top, 6)
                    Button("Add an account manually", action: onAdd).buttonStyle(.glass)
                }
                .frame(maxWidth: .infinity).padding(22).mtCard(padding: 0)
            }
            let cash = accounts.filter { !$0.isCredit }
            ForEach(cash) { a in cashRow(a, L) }
            let cards = accounts.filter(\.isCredit)
            if !cards.isEmpty {
                SectionLabel(text: "Credit cards")
                ForEach(cards) { c in
                    Button { cardSheet = c } label: { CardTile(card: c, s: L.cardStats(c.snap)) }
                        .buttonStyle(.press)
                        .contextMenu {
                            Button { editAcc = c } label: { Label("Card settings", systemImage: "slider.horizontal.3") }
                            Button(role: .destructive) { ctx.delete(c); try? ctx.save() } label: { Label("Delete card", systemImage: "trash") }
                        }
                }
            }
        }
        .sheet(item: $editAcc) { AccountForm(existing: $0) }
        .sheet(item: $fixIssue) { i in AccountForm(existing: accounts.first { $0.id == i.acc.id }, hint: i) }
        .sheet(item: $cardSheet) { CardDetailView(card: $0) }
        .sheet(isPresented: $showBankSync) { NavigationStack { BankSyncView() } }
        .onAppear { openRequestedCard() }
        .onChange(of: router.openCardId) { _, _ in openRequestedCard() }
    }

    private func openRequestedCard() {
        guard let id = router.openCardId else { return }
        cardSheet = accounts.first { $0.id == id }
        router.openCardId = nil
    }

    private func cashRow(_ a: Account, _ L: Ledger) -> some View {
        let bal = L.balance(a.id)
        let n = txs.filter { $0.accountId == a.id || $0.toAccountId == a.id }.count
        let col = Color(hex: a.colorHex)
        return Button { router.goActivity(acc: a.id) } label: {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [col, col.opacity(0.78)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 50, height: 50)
                    .overlay(Text(String(a.name.prefix(1)).uppercased()).font(.system(size: 22, weight: .bold)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(a.name).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                        if a.isSynced { Image(systemName: "building.columns.fill").font(.system(size: 10)).foregroundStyle(Color.mtTxt3) }
                    }
                    Text("\(n) transaction\(n == 1 ? "" : "s") · initial \(Fmt.money(a.initialBalance))\(a.ibDate.isEmpty ? "" : " on \(Fmt.shortDay(a.ibDate))")")
                        .font(.system(size: 12)).foregroundStyle(Color.mtTxt2).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(Fmt.money(bal)).money(18).foregroundStyle(bal >= 0 ? Color.mtGreen : Color.mtRed)
            }
            .foregroundStyle(.primary)
            .mtCard()
        }
        .buttonStyle(.press)
        .contextMenu {
            Button { editAcc = a } label: { Label("Edit account", systemImage: "pencil") }
            Button { router.goActivity(acc: a.id) } label: { Label("Show transactions", systemImage: "list.bullet") }
            Button(role: .destructive) { ctx.delete(a); try? ctx.save() } label: { Label("Delete account", systemImage: "trash") }
        }
    }
}

/// A credit card that looks like one (web V11): its color, what you owe, the due chip,
/// and how much of the limit you use.
struct CardTile: View {
    let card: Account
    let s: CardMath.Stats
    var body: some View {
        let col = Color(hex: card.colorHex)
        let chip: (String, Color) = s.amountDue <= 0 ? ("No bill due", .white.opacity(0.85))
            : s.overdue ? ("Overdue · \(Fmt.money(s.amountDue))", Color(hex: "#ffb4ad"))
            : (s.daysToDue == 0 ? "Due today · \(Fmt.money(s.amountDue))" : "Due in \(s.daysToDue)d · \(Fmt.money(s.amountDue))", Color(hex: "#ffe27a"))
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(card.name).font(.system(size: 16, weight: .bold)).lineLimit(1)
                    Text("Credit card").font(.system(size: 11)).opacity(0.75)
                }
                Spacer()
                Image(systemName: "creditcard.fill").font(.system(size: 18)).opacity(0.85)
            }
            .padding(.bottom, 16)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("OWED").font(.system(size: 10.5, weight: .semibold)).kerning(1).opacity(0.75)
                    Text(Fmt.money(s.currentBalance)).font(.system(size: 26, weight: .bold)).kerning(-0.6).monospacedDigit()
                }
                Spacer()
                Text(chip.0).font(.system(size: 11.5, weight: .semibold)).monospacedDigit().foregroundStyle(chip.1)
                    .padding(.horizontal, 11).padding(.vertical, 5).background(.black.opacity(0.28), in: Capsule())
            }
            .padding(.bottom, 12)
            ProgressBar(value: s.util, color: .white, height: 5, track: .white.opacity(0.22)).padding(.bottom, 6)
            HStack {
                Text("\(Fmt.money(s.currentBalance)) of \(Fmt.money(s.limit))")
                Spacer()
                Text("\(Fmt.money(max(s.available, 0))) left").fontWeight(.semibold)
            }
            .font(.system(size: 11.5)).monospacedDigit().opacity(0.85)
        }
        .foregroundStyle(.white)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: MT.card, style: .continuous)
                .fill(LinearGradient(colors: [col, col.opacity(0.62)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(alignment: .topTrailing) { Circle().fill(.white.opacity(0.09)).frame(width: 200, height: 200).offset(x: 50, y: -70) }
                .clipShape(RoundedRectangle(cornerRadius: MT.card, style: .continuous))
                .shadow(color: col.opacity(0.3), radius: 14, y: 8)
        }
    }
}

// ── Debts ──
struct DebtsSection: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Debt.date, order: .reverse) private var debts: [Debt]
    @Query(sort: \Account.sortIndex) private var accounts: [Account]
    @State private var repay: Debt?
    let onAdd: () -> Void
    var body: some View {
        let active = debts.filter { !$0.settled }
        let settled = debts.filter(\.settled)
        VStack(alignment: .leading, spacing: 12) {
            Text(active.isEmpty ? "Track what you owe friends" : "You owe \(Fmt.money(active.reduce(0) { $0 + ($1.totalAmount - $1.paidBack) }))")
                .font(.system(size: 13)).foregroundStyle(Color.mtTxt2).padding(.horizontal, 4)
            if active.isEmpty {
                EmptyCard(icon: "person.2", title: "No debts logged", message: "Borrowed money from someone? Add it here and log repayments as you go.", actionTitle: "Add a debt", action: onAdd)
            }
            ForEach(active) { d in debtCard(d) }
            if !settled.isEmpty {
                SectionLabel(text: "Fully paid ✓")
                ForEach(settled) { d in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: MT.inner).fill(Color(hex: d.colorHex)).frame(width: 40, height: 40)
                            .overlay(Text(String(d.personName.prefix(1)).uppercased()).font(.system(size: 18, weight: .bold)).foregroundStyle(.white))
                        VStack(alignment: .leading) { Text(d.personName).font(.system(size: 15, weight: .semibold)); Text("\(Fmt.money(d.totalAmount)) · paid back").font(.system(size: 12)).foregroundStyle(Color.mtTxt2) }
                        Spacer()
                    }
                    .opacity(0.6).mtCard(padding: 12)
                    .contextMenu { Button(role: .destructive) { ctx.delete(d); try? ctx.save() } label: { Label("Delete", systemImage: "trash") } }
                }
            }
        }
        .sheet(item: $repay) { RepayForm(debt: $0) }
    }
    private func debtCard(_ d: Debt) -> some View {
        let pct = d.totalAmount > 0 ? min(d.paidBack / d.totalAmount, 1) : 0
        let acc = accounts.first { $0.id == d.receivedInAccount }?.name
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: MT.card, style: .continuous).fill(Color(hex: d.colorHex)).frame(width: 52, height: 52)
                    .overlay(Text(String(d.personName.prefix(1)).uppercased()).font(.system(size: 24, weight: .bold)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 1) {
                    Text(d.personName).font(.system(size: 17, weight: .bold))
                    Text("Borrowed \(Fmt.money(d.totalAmount)) · \(Fmt.shortDay(d.date))").font(.system(size: 12)).foregroundStyle(Color.mtTxt2)
                    if let acc { Text("→ \(acc)").font(.system(size: 12)).foregroundStyle(Color.mtTxt3) }
                    if !d.details.isEmpty { Text(d.details).font(.system(size: 12)).foregroundStyle(Color.mtTxt3) }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(Fmt.money(d.totalAmount - d.paidBack)).money(20).foregroundStyle(Color.mtRed)
                    Text("left to pay").font(.system(size: 11)).foregroundStyle(Color.mtTxt3)
                }
            }
            ProgressBar(value: pct, color: Color(hex: d.colorHex), height: 7)
            Text("\(Int((pct * 100).rounded()))% paid · \(Fmt.money(d.paidBack)) of \(Fmt.money(d.totalAmount))").font(.system(size: 12)).foregroundStyle(Color.mtTxt3)
            Button { repay = d } label: { Text("Log repayment").frame(maxWidth: .infinity) }.buttonStyle(.glassProminent)
        }
        .mtCard(padding: 16)
        .contextMenu { Button(role: .destructive) { ctx.delete(d); try? ctx.save() } label: { Label("Delete debt", systemImage: "trash") } }
    }
}

// ── Goals ──
struct GoalsSection: View {
    @Environment(\.modelContext) private var ctx
    @Query private var goals: [Goal]
    @State private var edit: Goal?
    let onAdd: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            if goals.isEmpty {
                EmptyCard(icon: "target", title: "No goals yet", message: "Saving for a trip, a laptop, a deposit? Set a goal and watch it fill up.", actionTitle: "Add a goal", action: onAdd)
            }
            ForEach(goals) { g in
                let pct = g.targetAmount > 0 ? min(g.savedAmount / g.targetAmount, 1) : 0
                let col = Color(hex: g.colorHex)
                Button { edit = g } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: MT.card, style: .continuous).fill(col.opacity(0.15)).frame(width: 54, height: 54).overlay(GoalGlyph(goal: g, size: 24))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(g.name).font(.system(size: 17, weight: .bold))
                                Text(pct >= 1 ? "Goal reached!" : "\(Fmt.money(g.targetAmount - g.savedAmount)) to go").font(.system(size: 13)).foregroundStyle(Color.mtTxt2)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 0) {
                                Text(Fmt.money(g.savedAmount)).money(18).foregroundStyle(col)
                                Text("of \(Fmt.money(g.targetAmount))").font(.system(size: 12)).foregroundStyle(Color.mtTxt3)
                            }
                        }
                        ProgressBar(value: pct, color: col, height: 8)
                        Text("\(Int((pct * 100).rounded()))% saved").font(.system(size: 13, weight: .semibold)).foregroundStyle(col)
                    }
                    .foregroundStyle(.primary)
                    .mtCard(padding: 16)
                    .overlay(alignment: .topTrailing) {
                        if pct >= 1 {
                            Text("REACHED").font(.system(size: 11, weight: .bold)).foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Color.mtGreen, in: UnevenRoundedRectangle(bottomLeadingRadius: 10, topTrailingRadius: MT.card))
                        }
                    }
                }
                .buttonStyle(.press)
                .contextMenu { Button(role: .destructive) { ctx.delete(g); try? ctx.save() } label: { Label("Delete goal", systemImage: "trash") } }
            }
        }
        .sheet(item: $edit) { GoalForm(existing: $0) }
    }
}

// ── Categories ──
struct CategoriesSection: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \TxCategory.label) private var cats: [TxCategory]
    @State private var edit: TxCategory?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(cats.count) categories · long-press to delete").font(.system(size: 13)).foregroundStyle(Color.mtTxt2).padding(.horizontal, 4)
            ForEach(cats) { c in
                Button { edit = c } label: {
                    HStack(spacing: 12) {
                        CatTile(cat: c, size: 44)
                        VStack(alignment: .leading) { Text(c.label).font(.system(size: 16, weight: .semibold)); Text(c.id).font(.system(size: 12)).foregroundStyle(Color.mtTxt2) }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.mtTxt3)
                    }
                    .foregroundStyle(.primary).mtCard()
                }
                .buttonStyle(.press)
                .contextMenu { Button(role: .destructive) { ctx.delete(c); try? ctx.save() } label: { Label("Delete category", systemImage: "trash") } }
            }
        }
        .sheet(item: $edit) { CategoryForm(existing: $0) }
    }
}

/// Add / edit a category: a name, a symbol and a color (web CatSheet).
struct CategoryForm: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var cats: [TxCategory]
    let existing: TxCategory?
    var onCreate: ((String) -> Void)? = nil
    @State private var label = ""
    @State private var sym = "box"
    @State private var color = "#9ca3af"
    static let palette = ["#ef4444", "#f97316", "#f59e0b", "#84cc16", "#22c55e", "#14b8a6", "#06b6d4", "#3b82f6", "#6366f1", "#8b5cf6", "#d946ef", "#ec4899", "#9ca3af"]
    static let symbols = ["cart", "food", "phone", "car", "bag", "heart", "play", "brief", "laptop", "house", "swap", "repeat", "undo", "scale", "box", "goal", "plane", "grad", "gem", "beach", "gift", "pill", "paw", "card"]

    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("e.g. Gym, Coffee…", text: $label) }
                Section("Symbol") { SymbolGrid(selection: $sym, color: Color(hex: color)) }
                Section("Color") { ColorDots(selection: $color, palette: Self.palette) }
            }
            .navigationTitle(existing == nil ? "New Category" : "Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(label.trimmed.isEmpty) }
            }
            .onAppear { if let c = existing { label = c.label; sym = c.sym.isEmpty ? BackupService.builtInSym(c.id) : c.sym; color = c.colorHex } }
        }
        .presentationDetents([.medium, .large])
    }
    private func save() {
        if let c = existing { c.label = label.trimmed; c.sym = sym; c.colorHex = color }
        else {
            // Unique id from the name (a second "Dining" must not collide with the first).
            let base = label.trimmed.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).joined().prefix(20)
            var id = base.isEmpty ? "cat" : String(base); var n = 2
            while cats.contains(where: { $0.id == id }) { id = "\(base)\(n)"; n += 1 }
            ctx.insert(TxCategory(id: id, label: label.trimmed, icon: "📦", colorHex: color, sym: sym))
            onCreate?(id)
        }
        try? ctx.save(); Haptic.success(); dismiss()
    }
}

struct SymbolGrid: View {
    @Binding var selection: String
    var color: Color
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
            ForEach(CategoryForm.symbols, id: \.self) { k in
                Button { selection = k; Haptic.tap() } label: {
                    RoundedRectangle(cornerRadius: MT.inner, style: .continuous)
                        .fill(selection == k ? color.opacity(0.2) : Color.mtBg).frame(height: 42)
                        .overlay(Image(systemName: Symbols.name(k) ?? "square").font(.system(size: 17, weight: .semibold)).foregroundStyle(selection == k ? color : Color.mtTxt2))
                        .overlay(RoundedRectangle(cornerRadius: MT.inner).stroke(selection == k ? color : .clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ColorDots: View {
    @Binding var selection: String
    let palette: [String]
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 10) {
            ForEach(palette, id: \.self) { h in
                Button { selection = h; Haptic.tap() } label: {
                    Circle().fill(Color(hex: h)).frame(width: 30, height: 30)
                        .overlay(Circle().stroke(Color.primary.opacity(selection == h ? 0.8 : 0), lineWidth: 2).padding(-3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }
}
