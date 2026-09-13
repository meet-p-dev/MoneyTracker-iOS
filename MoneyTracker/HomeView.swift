import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: \Account.sortIndex) private var accounts: [Account]
    @Query private var cats: [TxCategory]
    @Query(sort: \Txn.date, order: .reverse) private var txs: [Txn]
    @Query private var budgets: [Budget]
    @State private var showSettings = false
    @State private var showAdd = false
    @State private var editTx: Txn?
    @State private var fixIssue: Ledger.Issue?

    private var monthKey: String { Fmt.monthKey() }
    private var daysLeft: Int {
        let cal = Calendar.current
        let dim = cal.range(of: .day, in: .month, for: Date())?.count ?? 30
        return max(dim - cal.component(.day, from: Date()) + 1, 1)
    }

    var body: some View {
        let L = Ledger.build(accounts: accounts, txs: txs)
        let stats = L.monthStats(monthKey)
        let totalBudget = budgets.reduce(0) { $0 + $1.limit }
        let budgeted = Set(budgets.map(\.categoryId))
        let budgetSpent = L.rows.filter { $0.type == "expense" && $0.date.hasPrefix(monthKey) && budgeted.contains($0.categoryId) }
            .reduce(0) { $0 + $1.personal }
        let safe = totalBudget > 0 ? max((totalBudget - budgetSpent) / Double(daysLeft), 0)
                 : stats.income > 0 ? max((stats.income - stats.spent) / Double(daysLeft), 0) : 0
        let recent = L.rows.sorted { $0.date > $1.date }.prefix(6)

        return NavigationStack {
            List {
                Section { hero(L, stats).listRowBackground(Color.clear).listRowSeparator(.hidden) }
                if !L.issues.isEmpty {
                    Section {
                        ForEach(L.issues) { i in IssueBanner(issue: i) { fixIssue = i } }
                    }
                }
                Section {
                    HStack(spacing: 0) {
                        statCell("Safe / day", Fmt.money(safe), sub: "\(daysLeft) d left", icon: "flame.fill")
                        Divider().padding(.vertical, 6)
                        statCell("Budget left", totalBudget > 0 ? Fmt.money(max(totalBudget - budgetSpent, 0)) : "Set up →",
                                 sub: totalBudget > 0 ? nil : "in Analytics", icon: "chart.pie.fill")
                    }
                }
                let ins = insights(L, stats)
                if !ins.isEmpty {
                    Section("Insights") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) { ForEach(ins, id: \.0) { insightChip($0) } }
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 0))
                    }
                }
                Section("Recent") {
                    ForEach(Array(recent)) { r in
                        TxRow(r: r, cats: cats, accounts: accounts)
                            .contentShape(Rectangle())
                            .onTapGesture { editTx = txs.first { $0.id == r.id } }
                    }
                    if txs.isEmpty {
                        Text(accounts.isEmpty ? "Add an account first — or restore your web backup in Settings."
                                              : "No transactions yet").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("MoneyTrack")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus.circle.fill") }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showAdd) { TransactionForm(existing: nil) }
            .sheet(item: $editTx) { TransactionForm(existing: $0) }
            .sheet(item: $fixIssue) { i in AccountForm(existing: accounts.first { $0.id == i.acc.id }, hint: i) }
        }
    }

    private func hero(_ L: Ledger, _ stats: (income: Double, spent: Double)) -> some View {
        let net = stats.income - stats.spent
        return VStack(spacing: 4) {
            Text("TOTAL BALANCE").font(.caption2.weight(.semibold)).kerning(1.1).foregroundStyle(.secondary)
            Text(Fmt.money(L.netWorth))
                .font(.system(size: 38, weight: .bold, design: .rounded)).monospacedDigit()
                .contentTransition(.numericText())
            NavigationLink(destination: AccountsView()) {
                Text("\(accounts.count) account\(accounts.count == 1 ? "" : "s") ›").font(.caption.weight(.semibold)).foregroundStyle(.tint)
            }
            if L.creditOwed > 0 {
                Text("\(Fmt.money(L.assets)) cash − \(Fmt.money(L.creditOwed)) credit")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            HStack(spacing: 28) {
                heroStat("INCOME", "+" + Fmt.money(stats.income), .green)
                heroStat("SPENT", "−" + Fmt.money(stats.spent), .primary)
                heroStat("NET", (net >= 0 ? "+" : "") + Fmt.money(net), net >= 0 ? .green : .red)
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func heroStat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 10, weight: .semibold)).kerning(0.6).foregroundStyle(.secondary)
            Text(value).font(.footnote.weight(.bold)).monospacedDigit().foregroundStyle(color)
        }
    }

    private func statCell(_ label: String, _ value: String, sub: String?, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: icon).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.body.weight(.bold)).monospacedDigit()
                if let sub { Text("· " + sub).font(.caption2).foregroundStyle(.tertiary) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func insights(_ L: Ledger, _ stats: (income: Double, spent: Double)) -> [(String, String, String, Color)] {
        var list: [(String, String, String, Color)] = []
        if stats.income > 0 {
            let r = Int(((stats.income - stats.spent) / stats.income * 100).rounded())
            list.append(("Savings rate", "\(r)%", r >= 20 ? "Great!" : "Aim for 20%+", r >= 20 ? .green : (r >= 0 ? .blue : .red)))
        }
        let day = Calendar.current.component(.day, from: Date())
        if stats.spent > 0 && day >= 5 {
            list.append(("Projected spend", Fmt.money(L.projectedSpend(monthKey)), "at typical pace", .blue))
        }
        if stats.spent > 0 {
            list.append(("Daily average", Fmt.money(stats.spent / Double(max(day, 1))), "over \(day) days", .blue))
        }
        return list
    }

    private func insightChip(_ ins: (String, String, String, Color)) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ins.0).font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text(ins.1).font(.footnote.weight(.bold)).foregroundStyle(ins.3)
                Text(ins.2).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

// Shared transaction row (Home + Activity). Shows the EFFECTIVE row: a bank debit that
// paid your card reads "Card bill", money in that isn't income reads as Received (teal).
struct TxRow: View {
    let r: Row
    let cats: [TxCategory]
    let accounts: [Account]

    var body: some View {
        let cat = cats.first { $0.id == r.categoryId }
        HStack(spacing: 12) {
            CatGlyph(cat: cat)
                .frame(width: 38, height: 38)
                .background(Color(hex: cat?.colorHex ?? "#9ca3af").opacity(0.16), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 1) {
                Text(r.merchant.isEmpty ? "Unknown" : r.merchant).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(prefix + Fmt.money(r.personal)).font(.subheadline.weight(.bold)).monospacedDigit().foregroundStyle(color)
                if r.type == "expense", let s = r.share, s != r.amount {
                    Text("of " + Fmt.money(r.amount)).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func name(_ id: String) -> String { accounts.first { $0.id == id }?.name ?? "?" }
    private var subtitle: String {
        let day = Fmt.prettyDay(r.date)
        if r.cardPay { return "Card bill → \(name(r.toAccountId)) · \(day)" }
        if r.type == "transfer" { return "\(name(r.accountId)) → \(name(r.toAccountId)) · \(day)" }
        return "\(name(r.accountId)) · \(day)"
    }
    private var prefix: String {
        switch r.type { case "income", "credit": "+"; case "expense", "debit": "−"; default: "⇄ " }
    }
    private var color: Color {
        switch r.type { case "income": .green; case "credit": .teal; case "expense": .red; default: .secondary }
    }
}
