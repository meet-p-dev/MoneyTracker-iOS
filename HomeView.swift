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

    private var monthKey: String { Fmt.monthKey() }
    private var totalBalance: Double { accounts.reduce(0) { $0 + Money.balance(of: $1, txs: txs) } }
    private var stats: (income: Double, spent: Double) { Money.monthStats(txs: txs, monthKey: monthKey) }

    private var daysLeft: Int {
        let cal = Calendar.current
        let dim = cal.range(of: .day, in: .month, for: Date())?.count ?? 30
        return max(dim - cal.component(.day, from: Date()) + 1, 1)
    }
    private var totalBudget: Double { budgets.reduce(0) { $0 + $1.limit } }
    private var budgetSpent: Double {
        let budgeted = Set(budgets.map(\.categoryId))
        return txs.filter { $0.type == "expense" && $0.date.hasPrefix(monthKey) && budgeted.contains($0.categoryId) }
            .reduce(0) { $0 + $1.personalAmount }
    }
    private var safePerDay: Double {
        if totalBudget > 0 { return max((totalBudget - budgetSpent) / Double(daysLeft), 0) }
        if stats.income > 0 { return max((stats.income - stats.spent) / Double(daysLeft), 0) }
        return 0
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    hero.listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
                Section {
                    HStack(spacing: 0) {
                        statCell("Safe / day", Fmt.money(safePerDay), sub: "\(daysLeft) d left", icon: "flame.fill")
                        Divider().padding(.vertical, 6)
                        statCell("Budget left", totalBudget > 0 ? Fmt.money(max(totalBudget - budgetSpent, 0)) : "Set up →",
                                 sub: totalBudget > 0 ? nil : "in Analytics", icon: "chart.pie.fill")
                    }
                }
                if !insights.isEmpty {
                    Section("Insights") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(insights, id: \.0) { ins in
                                    insightChip(ins)
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 0))
                    }
                }
                Section("Recent") {
                    ForEach(Array(txs.prefix(6))) { t in
                        TxRow(t: t, cats: cats, accounts: accounts)
                            .contentShape(Rectangle())
                            .onTapGesture { editTx = t }
                    }
                    if txs.isEmpty { Text("No transactions yet").foregroundStyle(.secondary) }
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
        }
    }

    private var hero: some View {
        VStack(spacing: 4) {
            Text("TOTAL BALANCE")
                .font(.caption2.weight(.semibold)).kerning(1.1)
                .foregroundStyle(.secondary)
            Text(Fmt.money(totalBalance))
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            NavigationLink(destination: AccountsView()) {
                Text("\(accounts.count) accounts ›")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            HStack(spacing: 28) {
                heroStat("INCOME", "+" + Fmt.money(stats.income), .green)
                heroStat("SPENT", "−" + Fmt.money(stats.spent), .primary)
                heroStat("NET", (stats.income - stats.spent >= 0 ? "+" : "") + Fmt.money(stats.income - stats.spent),
                         stats.income - stats.spent >= 0 ? .green : .red)
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
            Label(label, systemImage: icon)
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.body.weight(.bold)).monospacedDigit()
                if let sub { Text("· " + sub).font(.caption2).foregroundStyle(.tertiary) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private var insights: [(String, String, String, Color)] {
        var list: [(String, String, String, Color)] = []
        if stats.income > 0 {
            let r = Int(((stats.income - stats.spent) / stats.income * 100).rounded())
            list.append(("Savings rate", "\(r)%", r >= 20 ? "Great!" : "Aim for 20%+", r >= 20 ? .green : (r >= 0 ? .blue : .red)))
        }
        let day = Calendar.current.component(.day, from: Date())
        if stats.spent > 0 && day >= 5 {
            list.append(("Projected spend", Fmt.money(Money.projectedSpend(txs: txs, monthKey: monthKey)), "at typical pace", .blue))
        }
        if day > 0 && stats.spent > 0 {
            list.append(("Daily average", Fmt.money(stats.spent / Double(day)), "over \(day) days", .blue))
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

// Shared transaction row used by Home + Activity
struct TxRow: View {
    let t: Txn
    let cats: [TxCategory]
    let accounts: [Account]

    var body: some View {
        let cat = cats.first { $0.id == t.categoryId }
        let acc = accounts.first { $0.id == t.accountId }
        HStack(spacing: 12) {
            Text(cat?.icon ?? "📦")
                .font(.title3)
                .frame(width: 38, height: 38)
                .background(Color(hex: cat?.colorHex ?? "#9ca3af").opacity(0.18),
                            in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(t.merchant.isEmpty ? "Unknown" : t.merchant)
                        .font(.subheadline.weight(.semibold)).lineLimit(1)
                    if t.isSplit {
                        Text(t.splitSettled ? "✓" : "split")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.green.opacity(0.15), in: Capsule())
                            .foregroundStyle(.green)
                    }
                }
                Text("\(acc?.name ?? "?") · \(Fmt.prettyDay(t.date))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(prefix + Fmt.money(t.personalAmount))
                    .font(.subheadline.weight(.bold)).monospacedDigit()
                    .foregroundStyle(t.type == "income" ? .green : (t.type == "expense" ? .red : .secondary))
                if t.isSplit {
                    Text("of " + Fmt.money(t.amount)).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var prefix: String {
        switch t.type { case "income": "+"; case "expense": "−"; default: "⇄ " }
    }
}
