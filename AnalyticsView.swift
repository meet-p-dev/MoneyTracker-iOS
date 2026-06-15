import SwiftUI
import SwiftData
import Charts

struct AnalyticsView: View {
    @Query private var cats: [TxCategory]
    @Query(sort: \Txn.date, order: .reverse) private var txs: [Txn]
    @Query private var budgets: [Budget]
    @State private var view = "spend"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("View", selection: $view) {
                        Text("Spending").tag("spend")
                        Text("Budgets").tag("budgets")
                        Text("Trends").tag("trends")
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
                }
                switch view {
                case "budgets": BudgetsSection(cats: cats, txs: txs, budgets: budgets)
                case "trends": TrendsSection(txs: txs)
                default: SpendingSection(cats: cats, txs: txs)
                }
            }
            .navigationTitle("Analytics")
        }
    }
}

// ── Spending: donut + per-category breakdown ──
struct SpendingSection: View {
    let cats: [TxCategory]
    let txs: [Txn]

    private var monthKey: String { Fmt.monthKey() }
    private var byCat: [(cat: TxCategory, total: Double)] {
        cats.compactMap { c in
            let total = txs.filter { $0.type == "expense" && $0.categoryId == c.id && $0.date.hasPrefix(monthKey) }
                .reduce(0) { $0 + $1.personalAmount }
            return total > 0 ? (c, total) : nil
        }
        .sorted { $0.total > $1.total }
    }

    var body: some View {
        Section("This month by category") {
            if byCat.isEmpty {
                Text("No spending yet").foregroundStyle(.secondary)
            } else {
                Chart(byCat, id: \.cat.id) { item in
                    SectorMark(angle: .value("Spent", item.total),
                               innerRadius: .ratio(0.62), angularInset: 1.5)
                        .cornerRadius(4)
                        .foregroundStyle(Color(hex: item.cat.colorHex))
                }
                .frame(height: 200)
                .chartBackground { _ in
                    VStack {
                        Text("Total").font(.caption).foregroundStyle(.secondary)
                        Text(Fmt.money(byCat.reduce(0) { $0 + $1.total }))
                            .font(.headline).monospacedDigit()
                    }
                }
                .padding(.vertical, 6)

                ForEach(byCat, id: \.cat.id) { item in
                    NavigationLink {
                        CategoryDetail(cat: item.cat, txs: txs, monthKey: monthKey)
                    } label: {
                        HStack {
                            Text("\(item.cat.icon) \(item.cat.label)")
                            Spacer()
                            Text(Fmt.money(item.total)).monospacedDigit().fontWeight(.semibold)
                        }
                    }
                }
            }
        }
    }
}

// drill-down: merchants within a category (your "tap → see what's inside" rule)
struct CategoryDetail: View {
    let cat: TxCategory
    let txs: [Txn]
    let monthKey: String

    private var byMerchant: [(String, Double, Int)] {
        let rel = txs.filter { $0.type == "expense" && $0.categoryId == cat.id && $0.date.hasPrefix(monthKey) }
        let g = Dictionary(grouping: rel) { $0.merchant.isEmpty ? "Unknown" : $0.merchant }
        return g.map { ($0.key, $0.value.reduce(0) { $0 + $1.personalAmount }, $0.value.count) }
            .sorted { $0.1 > $1.1 }
    }

    var body: some View {
        List {
            ForEach(byMerchant, id: \.0) { m in
                HStack {
                    VStack(alignment: .leading) {
                        Text(m.0).fontWeight(.semibold)
                        Text("\(m.2) transaction\(m.2 > 1 ? "s" : "")").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Fmt.money(m.1)).monospacedDigit().fontWeight(.bold)
                }
            }
        }
        .navigationTitle("\(cat.icon) \(cat.label)")
    }
}

// ── Budgets: editable limits with progress ──
struct BudgetsSection: View {
    @Environment(\.modelContext) private var ctx
    let cats: [TxCategory]
    let txs: [Txn]
    let budgets: [Budget]

    private var monthKey: String { Fmt.monthKey() }

    private func spent(_ catId: String) -> Double {
        txs.filter { $0.type == "expense" && $0.categoryId == catId && $0.date.hasPrefix(monthKey) }
            .reduce(0) { $0 + $1.personalAmount }
    }

    var body: some View {
        let totalLimit = budgets.reduce(0) { $0 + $1.limit }
        let totalSpent = budgets.reduce(0) { $0 + spent($1.categoryId) }

        if totalLimit > 0 {
            Section {
                Gauge(value: min(totalSpent / totalLimit, 1)) {
                    Text("Spent this month")
                } currentValueLabel: {
                    Text(Fmt.money(totalSpent)).monospacedDigit()
                }
                .tint(totalSpent > totalLimit ? .red : .blue)
                LabeledContent("Left", value: Fmt.money(max(totalLimit - totalSpent, 0)))
            }
        }
        Section("Monthly limit per category") {
            ForEach(cats.filter { c in !["salary", "freelance"].contains(c.id) }) { c in
                let b = budgets.first { $0.categoryId == c.id }
                let sp = spent(c.id)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(c.icon) \(c.label)")
                        Spacer()
                        TextField("—", value: Binding(
                            get: { b?.limit ?? 0 },
                            set: { newVal in
                                if let b {
                                    if newVal > 0 { b.limit = newVal } else { ctx.delete(b) }
                                } else if newVal > 0 {
                                    ctx.insert(Budget(categoryId: c.id, limit: newVal))
                                }
                                try? ctx.save()
                            }), format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                    }
                    if let b, b.limit > 0 {
                        ProgressView(value: min(sp / b.limit, 1))
                            .tint(sp > b.limit ? .red : Color(hex: c.colorHex))
                        Text("\(Fmt.money(sp)) of \(Fmt.money(b.limit))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

// ── Trends: 6-month income vs spending bars ──
struct TrendsSection: View {
    let txs: [Txn]

    private var months: [(label: String, key: String, income: Double, spent: Double)] {
        let cal = Calendar.current
        return (0..<6).reversed().map { back in
            let d = cal.date(byAdding: .month, value: -back, to: Date())!
            let key = Fmt.monthKey(d)
            let s = Money.monthStats(txs: txs, monthKey: key)
            return (d.formatted(.dateTime.month(.abbreviated)), key, s.income, s.spent)
        }
    }

    var body: some View {
        Section("Income vs expenses · last 6 months") {
            Chart {
                ForEach(months, id: \.key) { m in
                    BarMark(x: .value("Month", m.label), y: .value("Amount", m.income), width: 12)
                        .position(by: .value("Kind", "Income"))
                        .foregroundStyle(.green)
                    BarMark(x: .value("Month", m.label), y: .value("Amount", m.spent), width: 12)
                        .position(by: .value("Kind", "Spent"))
                        .foregroundStyle(.red.opacity(0.85))
                }
            }
            .chartLegend(position: .top)
            .frame(height: 220)
            .padding(.vertical, 6)
        }
    }
}
