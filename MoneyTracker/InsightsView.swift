import SwiftUI
import SwiftData
import Charts

// Insights (web AnalyticsTab): Spending by month · Budgets · Calendar · Trends.
struct InsightsView: View {
    @Environment(Router.self) private var router
    @Query(sort: \Account.sortIndex) private var accounts: [Account]
    @Query private var cats: [TxCategory]
    @Query(sort: \Txn.date, order: .reverse) private var txs: [Txn]
    @Query private var budgets: [Budget]
    @State private var path: [String] = []
    @State private var calMonth = Fmt.monthKey()

    var body: some View {
        @Bindable var router = router
        let L = Ledger.build(accounts: accounts, txs: txs)
        return NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 12) {
                    Picker("View", selection: $router.insightsView) {
                        Text("Spending").tag("spend"); Text("Budgets").tag("budget")
                        Text("Calendar").tag("cal"); Text("Trends").tag("trends")
                    }
                    .pickerStyle(.segmented)
                    switch router.insightsView {
                    case "budget": BudgetsPanel(L: L, cats: cats, budgets: budgets)
                    case "cal": CalendarPanel(L: L, month: $calMonth)
                    case "trends": TrendsPanel(L: L)
                    default: spending(L)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
                .animation(MT.spring, value: router.insightsView)
            }
            .mtCanvas()
            .navigationTitle("Insights")
            .navigationDestination(for: String.self) { catId in
                CategoryDrill(catId: catId, L: L, cats: cats, month: router.spendMonth == "all" ? nil : router.spendMonth)
            }
            .onChange(of: router.drillCat) { _, id in openDrill(id) }
            .onAppear { openDrill(router.drillCat) }
        }
    }

    private func openDrill(_ id: String?) {
        guard let id else { return }
        router.insightsView = "spend"; path = [id]; router.drillCat = nil
    }

    private func monthLabel(_ k: String) -> String {
        if k == "all" { return "All time" }
        let cur = Fmt.monthKey(), last = Fmt.monthKey(Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date())
        if k == cur { return "This month" }
        if k == last { return "Last month" }
        return CardMath.date(k + "-01").formatted(.dateTime.month(.abbreviated).year(.twoDigits))
    }

    @ViewBuilder private func spending(_ L: Ledger) -> some View {
        let month = router.spendMonth == "all" ? nil : router.spendMonth
        let list = L.categoryTotals(month: month)
        let total = L.spendTotal(month: month)
        let cur = Fmt.monthKey()
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(["all"] + L.spendMonths, id: \.self) { k in
                    ChipButton(title: monthLabel(k), on: router.spendMonth == k) { withAnimation(MT.spring) { router.spendMonth = k } }
                }
            }
            .padding(.horizontal, 1)
        }
        .scrollClipDisabled()
        HStack(alignment: .firstTextBaseline) {
            Text(month == nil ? "Total spent" : "Spent · \(monthLabel(router.spendMonth))").font(.system(size: 13)).foregroundStyle(Color.mtTxt2)
            Spacer()
            Text(Fmt.money(total)).money(18)
        }
        .padding(.horizontal, 4)

        if month == nil || month == cur {
            let cs = L.creditSplit(month: cur)
            if cs.credit > 0 {
                let sum = max(cs.cash + cs.credit, 0.01)
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text("Cash vs credit").font(.system(size: 15, weight: .semibold)); Spacer(); Text("this month").font(.system(size: 12)).foregroundStyle(Color.mtTxt2) }
                    GeometryReader { g in
                        HStack(spacing: 0) {
                            Rectangle().fill(Color.mtGreen).frame(width: g.size.width * cs.cash / sum)
                            Rectangle().fill(Color.orange)
                        }
                        .clipShape(Capsule())
                    }
                    .frame(height: 10)
                    HStack(spacing: 16) {
                        legend("Cash", Fmt.money(cs.cash), .mtGreen)
                        legend("Credit", Fmt.money(cs.credit), .orange)
                    }
                    Text("\(Int((cs.credit / sum * 100).rounded()))% of what you spent this month was put on a card — money you still owe.")
                        .font(.system(size: 12)).foregroundStyle(Color.mtTxt2)
                }
                .mtCard(padding: 16)
            }
        }

        if list.isEmpty {
            EmptyCard(icon: "chart.pie", title: "No spending yet", message: "Once you spend, this shows where the money goes — by category, and inside each category by shop.")
        } else {
            Chart(list) { c in
                SectorMark(angle: .value("Spent", c.total), innerRadius: .ratio(0.64), angularInset: 1.5)
                    .cornerRadius(4).foregroundStyle(Color(hex: cats.first { $0.id == c.id }?.colorHex ?? "#9ca3af"))
            }
            .chartBackground { _ in
                VStack(spacing: 1) {
                    Text("Total").font(.caption).foregroundStyle(Color.mtTxt2)
                    Text(Fmt.money(total)).money(17)
                }
            }
            .frame(height: 190)
            .mtCard()
            let top = list.first?.total ?? 1
            ForEach(list) { c in
                let cat = cats.first { $0.id == c.id }
                NavigationLink(value: c.id) {
                    HStack(spacing: 13) {
                        CatTile(cat: cat, size: 48)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text(cat?.label ?? c.id).font(.system(size: 15, weight: .semibold)); Spacer(); Text(Fmt.money(c.total)).money(15) }
                            ProgressBar(value: c.total / top, color: Color(hex: cat?.colorHex ?? "#9ca3af"), height: 5)
                            Text("\(c.merchants.count) shop\(c.merchants.count == 1 ? "" : "s") · tap to explore").font(.system(size: 12)).foregroundStyle(Color.mtTxt3)
                        }
                    }
                    .foregroundStyle(.primary)
                    .mtCard()
                }
                .buttonStyle(.press)
            }
        }
    }

    private func legend(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) { Circle().fill(color).frame(width: 8, height: 8); Text(label).font(.system(size: 12)).foregroundStyle(Color.mtTxt2) }
            Text(value).money(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Tap a category → the shops inside it; tap a shop → those rows in Activity.
struct CategoryDrill: View {
    @Environment(Router.self) private var router
    let catId: String
    let L: Ledger
    let cats: [TxCategory]
    let month: String?
    var body: some View {
        let cat = cats.first { $0.id == catId }
        let c = L.categoryTotals(month: month).first { $0.id == catId }
        let shops = (c?.merchants ?? [:]).sorted { $0.value > $1.value }
        ScrollView {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    CatTile(cat: cat, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cat?.label ?? catId).font(.system(size: 17, weight: .bold))
                        Text("\(Fmt.money(c?.total ?? 0)) your share · \(shops.count) shop\(shops.count == 1 ? "" : "s")").font(.system(size: 13)).foregroundStyle(Color.mtTxt2)
                    }
                }
                .mtCard(padding: 16)
                VStack(spacing: 0) {
                    ForEach(Array(shops.enumerated()), id: \.element.key) { i, s in
                        if i > 0 { Divider().overlay(Color.mtBorder) }
                        Button { router.goActivity(search: s.key) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.key).font(.system(size: 15, weight: .semibold))
                                    Text("\(c?.counts[s.key] ?? 0) transactions").font(.system(size: 12)).foregroundStyle(Color.mtTxt2)
                                }
                                Spacer()
                                Text(Fmt.money(s.value)).money(16).foregroundStyle(Color.mtRed)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 13).contentShape(Rectangle())
                        }
                        .buttonStyle(.press).foregroundStyle(.primary)
                    }
                }
                .mtCard(padding: 0)
            }
            .padding(.horizontal, 16)
        }
        .mtCanvas()
        .navigationTitle(cat?.label ?? "Category")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct BudgetsPanel: View {
    @Environment(\.modelContext) private var ctx
    let L: Ledger
    let cats: [TxCategory]
    let budgets: [Budget]
    var body: some View {
        let key = Fmt.monthKey()
        let spent = Dictionary(grouping: L.rows.filter { $0.type == "expense" && $0.date.hasPrefix(key) }, by: \.categoryId).mapValues { $0.reduce(0) { $0 + $1.personal } }
        let total = budgets.reduce(0) { $0 + $1.limit }
        let tSpent = budgets.reduce(0) { $0 + (spent[$1.categoryId] ?? 0) }
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                RingView(value: total > 0 ? tSpent / total : 0, color: tSpent > total ? .mtRed : .mtAcc) {
                    Text(total > 0 ? "\(Int((tSpent / total * 100).rounded()))%" : "—").font(.system(size: 15, weight: .bold))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spent this month").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.mtTxt2)
                    Text(Fmt.money(tSpent)).money(22)
                    Text(total > 0 ? "of \(Fmt.money(total)) · \(Fmt.money(max(total - tSpent, 0))) left" : "No budgets yet — set a monthly limit below")
                        .font(.system(size: 13)).foregroundStyle(Color.mtTxt3)
                }
            }
            .mtCard(padding: 16)
            SectionLabel(text: "Monthly limit per category")
            ForEach(cats.filter { !["salary", "freelance", "transfer", "reimburse", "refund"].contains($0.id) }) { c in
                BudgetRow(cat: c, budget: budgets.first { $0.categoryId == c.id }, spent: spent[c.id] ?? 0)
            }
        }
    }
}

private struct BudgetRow: View {
    @Environment(\.modelContext) private var ctx
    let cat: TxCategory
    let budget: Budget?
    let spent: Double
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        let limit = budget?.limit ?? 0
        let over = limit > 0 && spent > limit
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                CatTile(cat: cat, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(cat.label).font(.system(size: 15, weight: .semibold))
                    Text(limit > 0 ? "\(Fmt.money(spent)) of \(Fmt.money(limit))\(over ? " · over!" : "")" : "\(Fmt.money(spent)) spent")
                        .font(.system(size: 12)).foregroundStyle(over ? Color.mtRed : Color.mtTxt2)
                }
                Spacer()
                HStack(spacing: 3) {
                    Text(Fmt.currencySymbol).foregroundStyle(Color.mtTxt3)
                    TextField("—", text: $text).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($focused)
                        .frame(width: 64).monospacedDigit()
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Color.mtBg, in: RoundedRectangle(cornerRadius: MT.inner, style: .continuous))
            }
            if limit > 0 { ProgressBar(value: spent / limit, color: over ? .mtRed : spent / limit > 0.85 ? .mtAmber : Color(hex: cat.colorHex)) }
        }
        .mtCard(padding: 13)
        .onAppear { text = limit > 0 ? Fmt.editable(limit) : "" }
        .onChange(of: focused) { _, f in if !f { commit() } }
        .onSubmit(commit)
    }
    private func commit() {
        let v = Fmt.amount(text) ?? 0
        if let b = budget { if v > 0 { b.limit = v } else { ctx.delete(b) } }
        else if v > 0 { ctx.insert(Budget(categoryId: cat.id, limit: v)) }
        try? ctx.save()
    }
}

struct CalendarPanel: View {
    let L: Ledger
    @Binding var month: String
    var body: some View {
        let (y, m, _) = CardMath.parts(month + "-01")
        let dim = CardMath.daysIn(y, m)
        let startDow = (Calendar.current.component(.weekday, from: CardMath.date(month + "-01")) + 5) % 7   // Monday first
        let data = L.dailySpend(month: month)
        let maxDay = max(data.values.max() ?? 1, 1)
        let total = data.values.reduce(0, +)
        let busiest = data.max { $0.value < $1.value }
        let cur = Fmt.monthKey()
        VStack(spacing: 12) {
            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.glass)
                Spacer()
                Text(CardMath.date(month + "-01").formatted(.dateTime.month(.wide).year())).font(.system(size: 16, weight: .bold))
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.glass).disabled(month >= cur)
            }
            VStack(spacing: 7) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                    ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { Text($0.element).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.mtTxt3) }
                    ForEach(0..<(startDow + dim), id: \.self) { i in
                        if i < startDow { Color.clear.aspectRatio(1, contentMode: .fit) }
                        else {
                            let d = i - startDow + 1
                            let key = String(format: "%@-%02d", month, d)
                            let sp = data[key] ?? 0
                            let a = sp > 0 ? 0.2 + 0.8 * sp / maxDay : 0
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(sp > 0 ? Color.mtRed.opacity(a) : Color.mtBg)
                                .aspectRatio(1, contentMode: .fit)
                                .overlay(Text("\(d)").font(.system(size: 12, weight: .semibold)).foregroundStyle(a > 0.5 ? .white : Color.mtTxt2))
                                .overlay(RoundedRectangle(cornerRadius: 9).stroke(key == Fmt.today() ? Color.mtAcc : .clear, lineWidth: 2))
                        }
                    }
                }
                HStack(spacing: 6) {
                    Spacer()
                    Text("Less").font(.system(size: 10)).foregroundStyle(Color.mtTxt3)
                    ForEach([0.2, 0.45, 0.7, 1.0], id: \.self) { RoundedRectangle(cornerRadius: 4).fill(Color.mtRed.opacity($0)).frame(width: 12, height: 12) }
                    Text("More").font(.system(size: 10)).foregroundStyle(Color.mtTxt3)
                }
                .padding(.top, 4)
            }
            .mtCard()
            HStack(spacing: 11) {
                VStack(alignment: .leading, spacing: 3) { Text("Month total").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.mtTxt2); Text(Fmt.money(total)).money(20).foregroundStyle(Color.mtRed) }.mtCard()
                VStack(alignment: .leading, spacing: 3) { Text("Active days").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.mtTxt2); (Text("\(data.values.filter { $0 > 0 }.count)").money(20) + Text(" / \(dim)").font(.system(size: 13)).foregroundStyle(Color.mtTxt3)) }.mtCard()
            }
            if let b = busiest, b.value > 0 {
                HStack {
                    VStack(alignment: .leading, spacing: 2) { Text("Busiest day").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.mtTxt2); Text(Fmt.prettyDay(b.key)).font(.system(size: 15, weight: .semibold)) }
                    Spacer()
                    Text(Fmt.money(b.value)).money(18).foregroundStyle(Color.mtRed)
                }
                .mtCard(padding: 16)
            }
        }
    }
    private func shift(_ delta: Int) {
        let (y, m, _) = CardMath.parts(month + "-01")
        var yy = y, mm = m + delta
        if mm < 1 { mm = 12; yy -= 1 }; if mm > 12 { mm = 1; yy += 1 }
        let nk = String(format: "%04d-%02d", yy, mm)
        if nk <= Fmt.monthKey() { withAnimation(MT.spring) { month = nk } }
    }
}

struct TrendsPanel: View {
    let L: Ledger
    var body: some View {
        VStack(spacing: 12) {
            SectionLabel(text: "Income vs expenses · last 6 months")
            IncomeSpendChart(data: L.monthChart(months: 6), height: 220).mtCard()
            SectionLabel(text: "Balance · 90 days")
            BalanceChartView(series: L.balanceSeries(days: 90)).mtCard()
        }
    }
}
