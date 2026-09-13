import SwiftUI
import SwiftData
import Charts
import TipKit

// Insights (web AnalyticsTab): Spending by month · Budgets · Calendar · Trends.
// Every number opens up: a donut slice, a category, cash vs credit, a budget, a month bar
// or a calendar day shows the transactions behind it.
struct InsightsView: View {
    @Environment(Router.self) private var router
    @Query(sort: \Account.sortIndex) private var accounts: [Account]
    @Query private var cats: [TxCategory]
    @Query(sort: \Txn.date, order: .reverse) private var txs: [Txn]
    @Query private var budgets: [Budget]
    @State private var path: [String] = []
    @State private var calMonth = Fmt.monthKey()
    @State private var selDay: String?
    @State private var angle: Double?
    @State private var trendLabel: String?
    @State private var txSel: TxSelection?
    @State private var editTx: Txn?
    private let insightsTip = InsightsTip()
    private let calendarTip = CalendarTip()

    var body: some View {
        @Bindable var router = router
        let L = Ledger.build(accounts: accounts, txs: txs)
        return NavigationStack(path: $path) {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    Picker("View", selection: $router.insightsView) {
                        Text("Spending").tag("spend"); Text("Budgets").tag("budget")
                        Text("Calendar").tag("cal"); Text("Trends").tag("trends")
                    }
                    .pickerStyle(.segmented)
                    switch router.insightsView {
                    case "budget": budgetsPanel(L)
                    case "cal": calendarPanel(L)
                    case "trends": trendsPanel(L)
                    default: spending(L)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
                .animation(MT.spring, value: router.insightsView)
            }
            .onChange(of: selDay) { _, d in
                guard d != nil else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { withAnimation(MT.spring) { proxy.scrollTo("dayList", anchor: .top) } }
            }
            .onChange(of: trendLabel) { _, l in
                guard l != nil else { return }
                withAnimation(MT.spring) { proxy.scrollTo("trendDetail", anchor: .bottom) }
            }
            }
            .mtCanvas()
            .navigationTitle("Insights")
            .navigationDestination(for: String.self) { catId in
                CategoryDrill(catId: catId, month: router.spendMonth == "all" ? nil : router.spendMonth)
            }
            .onChange(of: router.drillCat) { _, id in openDrill(id) }
            .onAppear { openDrill(router.drillCat) }
            .sheet(item: $txSel) { TxListSheet(sel: $0) }
            .sheet(item: $editTx) { TransactionForm(existing: $0) }
        }
    }

    private func openDrill(_ id: String?) {
        guard let id else { return }
        router.insightsView = "spend"; path = [id]; router.drillCat = nil
    }
    private func show(_ title: String, _ subtitle: String, _ rows: [Row]) {
        Haptic.tap()
        txSel = TxSelection(title: title, subtitle: subtitle, ids: Set(rows.map(\.id)))
    }

    private func monthLabel(_ k: String) -> String {
        if k == "all" { return "All time" }
        let cur = Fmt.monthKey(), last = Fmt.monthKey(Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date())
        if k == cur { return "This month" }
        if k == last { return "Last month" }
        return CardMath.date(k + "-01").formatted(.dateTime.month(.abbreviated).year(.twoDigits))
    }

    // ── Spending ──
    @ViewBuilder private func spending(_ L: Ledger) -> some View {
        let month = router.spendMonth == "all" ? nil : router.spendMonth
        let list = L.categoryTotals(month: month)
        let total = L.spendTotal(month: month)
        let cur = Fmt.monthKey()
        let expenses = L.rows.filter { $0.type == "expense" && (month == nil || $0.date.hasPrefix(month!)) }
        TipView(insightsTip)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(["all"] + L.spendMonths, id: \.self) { k in
                    ChipButton(title: monthLabel(k), on: router.spendMonth == k) { withAnimation(MT.spring) { router.spendMonth = k; angle = nil } }
                }
            }
            .padding(.horizontal, 1)
        }
        .scrollClipDisabled()
        Button { show("Spending", month == nil ? "All time" : monthLabel(router.spendMonth), expenses) } label: {
            HStack(alignment: .firstTextBaseline) {
                Text(month == nil ? "Total spent" : "Spent · \(monthLabel(router.spendMonth))").font(.system(size: 13)).foregroundStyle(Color.mtTxt2)
                Spacer()
                Text(Fmt.money(total)).money(18).foregroundStyle(.primary)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.mtTxt3)
            }
            .padding(.horizontal, 4)
        }
        .buttonStyle(.press)

        if month == nil || month == cur {
            let monthRows = L.rows.filter { $0.type == "expense" && $0.date.hasPrefix(cur) }
            let cardIds = Set(L.cards.map(\.id))
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
                    HStack(spacing: 10) {
                        legend("Cash", Fmt.money(cs.cash), .mtGreen) { show("Paid with cash", "This month · from your accounts", monthRows.filter { !cardIds.contains($0.accountId) }) }
                        legend("Credit", Fmt.money(cs.credit), .orange) { show("Put on a card", "This month · money you still owe", monthRows.filter { cardIds.contains($0.accountId) }) }
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
            let sel = selectedCategory(list)
            VStack(spacing: 10) {
                Chart(list) { c in
                    SectorMark(angle: .value("Spent", c.total), innerRadius: .ratio(0.64), angularInset: 1.5)
                        .cornerRadius(4)
                        .foregroundStyle(Color(hex: cats.first { $0.id == c.id }?.colorHex ?? "#9ca3af"))
                        .opacity(sel == nil || sel?.id == c.id ? 1 : 0.35)
                }
                .chartOverlay { proxy in
                    // Tap a slice: turn the tap's angle (clockwise from 12 o'clock) into a point on
                    // the running total, which is what the donut's slices are laid out along.
                    GeometryReader { geo in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onTapGesture { loc in
                                guard let plot = proxy.plotFrame else { return }
                                let f = geo[plot]
                                let dx = loc.x - f.midX, dy = loc.y - f.midY
                                var t = atan2(dx, -dy); if t < 0 { t += 2 * .pi }
                                let v = t / (2 * .pi) * total
                                let hit = hitCategory(list, v)
                                Haptic.tap()
                                withAnimation(MT.spring) { angle = hit?.id == sel?.id ? nil : v }
                            }
                    }
                }
                .chartBackground { _ in
                    VStack(spacing: 1) {
                        Text(sel.map { s in cats.first(where: { $0.id == s.id })?.label ?? s.id } ?? "Total").font(.caption).foregroundStyle(Color.mtTxt2).lineLimit(1)
                        Text(Fmt.money(sel?.total ?? total)).money(17)
                    }
                }
                .frame(height: 190)
                if let sel {
                    Button { show(cats.first { $0.id == sel.id }?.label ?? sel.id, month == nil ? "All time" : monthLabel(router.spendMonth), expenses.filter { $0.categoryId == sel.id }) } label: {
                        Label("See \(expenses.filter { $0.categoryId == sel.id }.count) transactions", systemImage: "list.bullet").font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.glass)
                } else {
                    Text("Tap a slice").font(.system(size: 11)).foregroundStyle(Color.mtTxt3)
                }
            }
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
                            Text("\(c.merchants.count) shop\(c.merchants.count == 1 ? "" : "s") · tap to see them").font(.system(size: 12)).foregroundStyle(Color.mtTxt3)
                        }
                    }
                    .foregroundStyle(.primary)
                    .mtCard()
                }
                .buttonStyle(.press)
            }
        }
    }

    /// The donut reports an angle along the cumulative total; map it back to a category.
    private func selectedCategory(_ list: [Ledger.CatTotal]) -> Ledger.CatTotal? {
        guard let a = angle else { return nil }
        return hitCategory(list, a)
    }
    private func hitCategory(_ list: [Ledger.CatTotal], _ a: Double) -> Ledger.CatTotal? {
        var cum = 0.0
        for c in list { cum += c.total; if a <= cum { return c } }
        return list.last
    }

    private func legend(_ label: String, _ value: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle().fill(color).frame(width: 8, height: 8)
                    Text(label).font(.system(size: 12)).foregroundStyle(Color.mtTxt2)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.mtTxt3)
                }
                Text(value).money(16).foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10).background(Color.mtCardH, in: RoundedRectangle(cornerRadius: MT.inner, style: .continuous))
        }
        .buttonStyle(.press)
    }

    // ── Budgets ──
    @ViewBuilder private func budgetsPanel(_ L: Ledger) -> some View {
        let key = Fmt.monthKey()
        let monthRows = L.rows.filter { $0.type == "expense" && $0.date.hasPrefix(key) }
        let spent = Dictionary(grouping: monthRows, by: \.categoryId).mapValues { $0.reduce(0) { $0 + $1.personal } }
        let total = budgets.reduce(0) { $0 + $1.limit }
        let budgeted = Set(budgets.map(\.categoryId))
        let tSpent = budgets.reduce(0) { $0 + (spent[$1.categoryId] ?? 0) }
        Button { show("Budgeted spending", "This month · categories with a limit", monthRows.filter { budgeted.contains($0.categoryId) }) } label: {
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
                Spacer()
            }
            .foregroundStyle(.primary)
            .mtCard(padding: 16)
        }
        .buttonStyle(.press)
        SectionLabel(text: "Monthly limit per category · tap one for its spending")
        ForEach(cats.filter { !["salary", "freelance", "transfer", "reimburse", "refund"].contains($0.id) }) { c in
            BudgetRow(cat: c, budget: budgets.first { $0.categoryId == c.id }, spent: spent[c.id] ?? 0) {
                show(c.label, "This month", monthRows.filter { $0.categoryId == c.id })
            }
        }
    }

    // ── Calendar: tap a day for its transactions ──
    @ViewBuilder private func calendarPanel(_ L: Ledger) -> some View {
        let (y, m, _) = CardMath.parts(calMonth + "-01")
        let dim = CardMath.daysIn(y, m)
        let startDow = (Calendar.current.component(.weekday, from: CardMath.date(calMonth + "-01")) + 5) % 7   // Monday first
        let data = L.dailySpend(month: calMonth)
        let maxDay = max(data.values.max() ?? 1, 1)
        let total = data.values.reduce(0, +)
        let busiest = data.max { $0.value < $1.value }
        let cur = Fmt.monthKey()
        TipView(calendarTip)
        HStack {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.glass)
            Spacer()
            Text(CardMath.date(calMonth + "-01").formatted(.dateTime.month(.wide).year())).font(.system(size: 16, weight: .bold))
            Spacer()
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.glass).disabled(calMonth >= cur)
        }
        VStack(spacing: 7) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { Text($0.element).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.mtTxt3) }
                ForEach(0..<(startDow + dim), id: \.self) { i in
                    if i < startDow { Color.clear.aspectRatio(1, contentMode: .fit) }
                    else {
                        let d = i - startDow + 1
                        let key = String(format: "%@-%02d", calMonth, d)
                        let sp = data[key] ?? 0
                        let a = sp > 0 ? 0.2 + 0.8 * sp / maxDay : 0
                        let picked = selDay == key
                        Button { Haptic.tap(); withAnimation(MT.spring) { selDay = picked ? nil : key } } label: {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(sp > 0 ? Color.mtRed.opacity(a) : Color.mtBg)
                                .aspectRatio(1, contentMode: .fit)
                                .overlay(Text("\(d)").font(.system(size: 12, weight: .semibold)).foregroundStyle(a > 0.5 ? .white : Color.mtTxt2))
                                .overlay(RoundedRectangle(cornerRadius: 9).stroke(picked ? Color.primary : key == Fmt.today() ? Color.mtAcc : .clear, lineWidth: picked ? 2.5 : 2))
                                .scaleEffect(picked ? 1.08 : 1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(Fmt.prettyDay(key)), spent \(Fmt.money(sp))")
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

        if let day = selDay {
            let rows = L.rows.filter { $0.date == day }
            let spentDay = rows.filter { $0.type == "expense" }.reduce(0) { $0 + $1.personal }
            Color.clear.frame(height: 0).id("dayList")
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: Fmt.prettyDay(day))
                Spacer()
                if spentDay > 0 { Text("−" + Fmt.money(spentDay)).money(13, .semibold).foregroundStyle(Color.mtRed).padding(.trailing, 4) }
            }
            if rows.isEmpty {
                Text("Nothing on this day.").font(.system(size: 14)).foregroundStyle(Color.mtTxt3).frame(maxWidth: .infinity, alignment: .leading).mtCard()
            } else {
                TxRowsCard(rows: rows, cats: cats, accounts: accounts) { r in editTx = txs.first { $0.id == r.id } }
            }
        }

        HStack(spacing: 11) {
            Button { show("Spending", CardMath.date(calMonth + "-01").formatted(.dateTime.month(.wide).year()), L.rows.filter { $0.type == "expense" && $0.date.hasPrefix(calMonth) }) } label: {
                VStack(alignment: .leading, spacing: 3) { Text("Month total").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.mtTxt2); Text(Fmt.money(total)).money(20).foregroundStyle(Color.mtRed) }.mtCard()
            }
            .buttonStyle(.press)
            VStack(alignment: .leading, spacing: 3) { Text("Active days").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.mtTxt2); (Text("\(data.values.filter { $0 > 0 }.count)").money(20) + Text(" / \(dim)").font(.system(size: 13)).foregroundStyle(Color.mtTxt3)) }.mtCard()
        }
        if let b = busiest, b.value > 0 {
            Button { withAnimation(MT.spring) { selDay = b.key } } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) { Text("Busiest day").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.mtTxt2); Text(Fmt.prettyDay(b.key)).font(.system(size: 15, weight: .semibold)) }
                    Spacer()
                    Text(Fmt.money(b.value)).money(18).foregroundStyle(Color.mtRed)
                }
                .foregroundStyle(.primary)
                .mtCard(padding: 16)
            }
            .buttonStyle(.press)
        }
    }

    private func shiftMonth(_ delta: Int) {
        let (y, m, _) = CardMath.parts(calMonth + "-01")
        var yy = y, mm = m + delta
        if mm < 1 { mm = 12; yy -= 1 }; if mm > 12 { mm = 1; yy += 1 }
        let nk = String(format: "%04d-%02d", yy, mm)
        if nk <= Fmt.monthKey() { withAnimation(MT.spring) { calMonth = nk; selDay = nil } }
    }

    // ── Trends: tap a month for its income and spending ──
    @ViewBuilder private func trendsPanel(_ L: Ledger) -> some View {
        let data = L.monthChart(months: 6)
        SectionLabel(text: "Income vs expenses · last 6 months · tap a month")
        IncomeSpendChart(data: data, height: 220, selection: $trendLabel).mtCard()
        if let lbl = trendLabel, let m = data.first(where: { IncomeSpendChart.label($0.key) == lbl }) {
            let rows = L.rows.filter { $0.date.hasPrefix(m.key) }
            let title = CardMath.date(m.key + "-01").formatted(.dateTime.month(.wide).year())
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.system(size: 15, weight: .semibold))
                HStack(spacing: 10) {
                    legend("Income", Fmt.money(m.income), .mtGreen) { show("Income", title, rows.filter { $0.type == "income" }) }
                    legend("Spent", Fmt.money(m.spent), .mtRed) { show("Spending", title, rows.filter { $0.type == "expense" }) }
                }
                Text("Net \(m.income - m.spent >= 0 ? "+" : "")\(Fmt.money(m.income - m.spent))").money(13, .semibold).foregroundStyle(m.income - m.spent >= 0 ? Color.mtGreen : Color.mtRed)
            }
            .mtCard(padding: 16)
            .id("trendDetail")
        } else {
            Text("Tap a month in the chart to see what came in and went out.").font(.system(size: 13)).foregroundStyle(Color.mtTxt3).padding(.horizontal, 4)
        }
    }
}

// Tap a category → its shops and every transaction; tap a shop to narrow the list.
struct CategoryDrill: View {
    @Query(sort: \Account.sortIndex) private var accounts: [Account]
    @Query private var cats: [TxCategory]
    @Query(sort: \Txn.date, order: .reverse) private var txs: [Txn]
    let catId: String
    let month: String?
    @State private var shop: String?
    @State private var editTx: Txn?

    var body: some View {
        let L = Ledger.build(accounts: accounts, txs: txs)
        let cat = cats.first { $0.id == catId }
        let c = L.categoryTotals(month: month).first { $0.id == catId }
        let shops = (c?.merchants ?? [:]).sorted { $0.value > $1.value }
        let rows = L.rows.filter { $0.type == "expense" && $0.categoryId == catId && (month == nil || $0.date.hasPrefix(month!))
            && (shop == nil || ($0.merchant.isEmpty ? "Unknown" : $0.merchant) == shop) }.sorted { $0.date > $1.date }
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    CatTile(cat: cat, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cat?.label ?? catId).font(.system(size: 17, weight: .bold))
                        Text("\(Fmt.money(c?.total ?? 0)) your share · \(shops.count) shop\(shops.count == 1 ? "" : "s")").font(.system(size: 13)).foregroundStyle(Color.mtTxt2)
                    }
                }
                .mtCard(padding: 16)
                SectionLabel(text: "Shops · tap one to filter")
                VStack(spacing: 0) {
                    ForEach(Array(shops.enumerated()), id: \.element.key) { i, s in
                        if i > 0 { Divider().overlay(Color.mtBorder) }
                        Button { Haptic.tap(); withAnimation(MT.spring) { shop = shop == s.key ? nil : s.key } } label: {
                            HStack {
                                Image(systemName: shop == s.key ? "checkmark.circle.fill" : "circle").foregroundStyle(shop == s.key ? Color.mtAcc : Color.mtTxt3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.key).font(.system(size: 15, weight: .semibold))
                                    Text("\(c?.counts[s.key] ?? 0) transaction\((c?.counts[s.key] ?? 0) == 1 ? "" : "s")").font(.system(size: 12)).foregroundStyle(Color.mtTxt2)
                                }
                                Spacer()
                                Text(Fmt.money(s.value)).money(16).foregroundStyle(Color.mtRed)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12).contentShape(Rectangle())
                        }
                        .buttonStyle(.press).foregroundStyle(.primary)
                    }
                }
                .mtCard(padding: 0)
                SectionLabel(text: shop == nil ? "All transactions" : "Transactions · \(shop!)")
                TxRowsCard(rows: rows, cats: cats, accounts: accounts) { r in editTx = txs.first { $0.id == r.id } }
            }
            .padding(.horizontal, 16).padding(.bottom, 16)
        }
        .mtCanvas()
        .navigationTitle(cat?.label ?? "Category")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editTx) { TransactionForm(existing: $0) }
    }
}

private struct BudgetRow: View {
    @Environment(\.modelContext) private var ctx
    let cat: TxCategory
    let budget: Budget?
    let spent: Double
    let onShow: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        let limit = budget?.limit ?? 0
        let over = limit > 0 && spent > limit
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button(action: onShow) {
                    HStack(spacing: 12) {
                        CatTile(cat: cat, size: 40)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(cat.label).font(.system(size: 15, weight: .semibold))
                            Text(limit > 0 ? "\(Fmt.money(spent)) of \(Fmt.money(limit))\(over ? " · over!" : "")" : "\(Fmt.money(spent)) spent")
                                .font(.system(size: 12)).foregroundStyle(over ? Color.mtRed : Color.mtTxt2)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.primary).contentShape(Rectangle())
                }
                .buttonStyle(.press)
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
