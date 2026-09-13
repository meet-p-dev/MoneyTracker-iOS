import SwiftUI
import SwiftData

// Home — a "Today" view (web HomeTab): the balance as the hero, the ONE most important
// thing right now, how the money moved, and where it went. Everything leads somewhere.
struct HomeView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(Router.self) private var router
    @Query(sort: \Account.sortIndex) private var accounts: [Account]
    @Query private var cats: [TxCategory]
    @Query(sort: \Txn.date, order: .reverse) private var txs: [Txn]
    @Query private var budgets: [Budget]
    @Query private var goals: [Goal]
    @Query(sort: \Debt.date, order: .reverse) private var debts: [Debt]
    @AppStorage("mt-debt-banner-seen") private var debtBannerSeen = false
    @State private var showSettings = false
    @State private var editTx: Txn?
    @State private var fixIssue: Ledger.Issue?
    @State private var showReview = false
    @State private var moreAlerts = false

    private var monthKey: String { Fmt.monthKey() }
    private var daysLeft: Int {
        let cal = Calendar.current
        let dim = cal.range(of: .day, in: .month, for: Date())?.count ?? 30
        return max(dim - cal.component(.day, from: Date()) + 1, 1)
    }

    var body: some View {
        let L = Ledger.build(accounts: accounts, txs: txs)
        return NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    hero(L)
                    attention(L)
                    balanceCard(L)
                    safeBudgetCard(L)
                    insightsRow(L)
                    SectionLabel(text: "Income vs expenses")
                    IncomeSpendChart(data: L.monthChart(months: 6)).mtCard()
                    recentCard(L)
                    goalsCard
                    topCategories(L)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .mtCanvas()
            .refreshable { await CloudSync.shared.sync(ctx: ctx) }
            .navigationTitle("MoneyTrack")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(item: $editTx) { TransactionForm(existing: $0) }
            .sheet(item: $fixIssue) { i in AccountForm(existing: accounts.first { $0.id == i.acc.id }, hint: i) }
            .sheet(isPresented: $showReview) { ReviewSheet() }
        }
    }

    // ── Hero: total balance, cash − credit, this month in / out ──
    private func hero(_ L: Ledger) -> some View {
        let s = L.monthStats(monthKey)
        let net = s.income - s.spent
        let mon = Date().formatted(.dateTime.month(.abbreviated)).uppercased()
        return VStack(spacing: 3) {
            Button { router.goWallet("accounts") } label: {
                VStack(spacing: 3) {
                    Text("TOTAL BALANCE").font(.system(size: 11, weight: .semibold)).kerning(1.1).foregroundStyle(Color.mtTxt3)
                    Text(Fmt.money(L.netWorth))
                        .font(.system(size: 44, weight: .bold)).kerning(-1.2).monospacedDigit()
                        .contentTransition(.numericText()).animation(MT.spring, value: L.netWorth)
                        .minimumScaleFactor(0.6).lineLimit(1).foregroundStyle(.primary)
                    Text("\(accounts.count) account\(accounts.count == 1 ? "" : "s") ›").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.mtAcc)
                    if L.creditOwed > 0 {
                        Text("\(Fmt.money(L.assets)) cash − \(Fmt.money(L.creditOwed)) credit").font(.system(size: 11.5)).monospacedDigit().foregroundStyle(Color.mtTxt3)
                    }
                }
            }
            .buttonStyle(.press)
            if CloudSync.shared.signedIn {
                HStack(spacing: 5) {
                    Circle().fill(CloudSync.shared.syncing ? Color.mtAmber : Color.mtGreen).frame(width: 6, height: 6)
                    Text(CloudSync.shared.syncing ? "Syncing…" : "Bank sync on · 3×/day")
                }
                .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color.mtTxt2)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.mtCard, in: Capsule()).overlay(Capsule().stroke(Color.mtBorder))
                .padding(.top, 5)
            }
            HStack(spacing: 28) {
                heroStat("INCOME", "+" + Fmt.money(s.income), .mtGreen) { router.goActivity(type: "income") }
                heroStat("SPENT", "−" + Fmt.money(s.spent), .primary) { router.goActivity(type: "expense") }
                heroStat("NET · \(mon)", (net >= 0 ? "+" : "") + Fmt.money(net), net >= 0 ? .mtGreen : .mtRed) { router.goInsights("spend") }
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4).padding(.bottom, 6)
    }

    private func heroStat(_ label: String, _ value: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: { Haptic.tap(); action() }) {
            VStack(spacing: 1) {
                Text(label).font(.system(size: 10, weight: .semibold)).kerning(0.6).foregroundStyle(Color.mtTxt3)
                Text(value).money(14).foregroundStyle(color)
            }
        }
        .buttonStyle(.press)
    }

    // ── The attention stack: the ONE most important thing + "+N more" (web order) ──
    private func alerts(_ L: Ledger) -> [Attention] {
        var list: [Attention] = []
        if accounts.isEmpty {
            list.append(Attention(id: "noaccs", tone: .mtAcc, icon: "wallet.bifold.fill", title: "Add your first account",
                                  sub: "Connect a bank for real transactions, or add one by hand", cta: "Set up") { router.goWallet("accounts") })
        }
        for i in L.issues {
            let card = i.acc.isCredit
            list.append(Attention(id: "ib-\(i.acc.id)", tone: .mtAmber, icon: card ? "creditcard.fill" : "wallet.bifold.fill",
                                  title: "\(i.acc.name) counts \(i.n) old \(i.n == 1 ? "entry" : "entries") twice",
                                  sub: card ? "Should owe \(Fmt.money(max(-i.fixed, 0))), not \(Fmt.money(max(-i.now, 0)))" : "Should be \(Fmt.money(i.fixed)), not \(Fmt.money(i.now))",
                                  cta: "Fix") { fixIssue = i })
        }
        let stats = L.cards.map { ($0, L.cardStats($0)) }
        let overdue = stats.filter { $0.1.overdue }
        if let f = overdue.first {
            list.append(Attention(id: "overdue", tone: .mtRed, icon: "creditcard.fill",
                                  title: "Card bill overdue · \(Fmt.money(overdue.reduce(0) { $0 + $1.1.amountDue }))",
                                  sub: overdue.count == 1 ? "\(f.0.name) · \(abs(f.1.daysToDue))d late — tap to pay" : "\(overdue.count) cards late — tap to pay",
                                  cta: "Pay") { router.goWallet("accounts", card: f.0.id) })
        }
        let review = L.reviewRows.count
        if review > 0 {
            list.append(Attention(id: "review", tone: .mtAcc, icon: "tray.full.fill", title: "\(review) transaction\(review == 1 ? "" : "s") to review",
                                  sub: "Confirm which incoming money is really income", cta: "Review") { showReview = true })
        }
        let upcoming = stats.filter { $0.1.dueSoon && !$0.1.overdue }
        if let u = upcoming.first {
            list.append(Attention(id: "due", tone: .mtAmber, icon: "creditcard.fill",
                                  title: "Card bill due · \(Fmt.money(upcoming.reduce(0) { $0 + $1.1.amountDue }))",
                                  sub: upcoming.count == 1 ? "\(u.0.name) · \(u.1.daysToDue == 0 ? "today" : "in \(u.1.daysToDue) day\(u.1.daysToDue == 1 ? "" : "s")")" : "\(upcoming.count) cards due soon",
                                  cta: "Pay") { router.goWallet("accounts", card: u.0.id) })
        }
        let spent = Dictionary(grouping: L.rows.filter { $0.type == "expense" && $0.date.hasPrefix(monthKey) }, by: \.categoryId).mapValues { $0.reduce(0) { $0 + $1.personal } }
        let over = budgets.filter { $0.limit > 0 && (spent[$0.categoryId] ?? 0) > $0.limit }
        if !over.isEmpty {
            let names = over.compactMap { b in cats.first { $0.id == b.categoryId }?.label }.joined(separator: ", ")
            list.append(Attention(id: "budget", tone: .mtRed, icon: "chart.pie.fill", title: "Over budget in \(over.count) categor\(over.count == 1 ? "y" : "ies")",
                                  sub: names, cta: "View") { router.goInsights("budget") })
        }
        let active = debts.filter { !$0.settled }
        if !active.isEmpty && !debtBannerSeen {
            list.append(Attention(id: "debts", tone: .mtRed, icon: "person.2.fill",
                                  title: "You owe \(Fmt.money(active.reduce(0) { $0 + ($1.totalAmount - $1.paidBack) }))",
                                  sub: "\(active.count) active debt\(active.count == 1 ? "" : "s") — tap to view", cta: "View") {
                debtBannerSeen = true; router.goWallet("debts")
            })
        }
        return list
    }

    @ViewBuilder private func attention(_ L: Ledger) -> some View {
        let list = alerts(L)
        if let first = list.first {
            VStack(spacing: 8) {
                AttentionRow(a: first, big: true)
                if list.count > 1 {
                    if moreAlerts {
                        ForEach(list.dropFirst()) { AttentionRow(a: $0) }
                        Button("Show less") { withAnimation(MT.spring) { moreAlerts = false } }
                            .font(.caption.weight(.semibold)).foregroundStyle(Color.mtTxt3)
                    } else {
                        Button { withAnimation(MT.spring) { moreAlerts = true } } label: {
                            Text("+\(list.count - 1) more").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.mtTxt2)
                                .padding(.horizontal, 14).padding(.vertical, 5)
                                .background(Color.mtCard, in: Capsule()).overlay(Capsule().stroke(Color.mtBorder))
                        }
                        .buttonStyle(.press)
                    }
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    @ViewBuilder private func balanceCard(_ L: Ledger) -> some View {
        let series = L.balanceSeries(days: 60)
        if series.count > 1 && !accounts.isEmpty {
            let delta = (series.last?.value ?? 0) - (series.first?.value ?? 0)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("BALANCE · 60 DAYS").font(.system(size: 11, weight: .semibold)).kerning(1.1).foregroundStyle(Color.mtTxt3)
                    Spacer()
                    Text((delta >= 0 ? "+" : "") + Fmt.money(delta)).money(12.5).foregroundStyle(delta >= 0 ? Color.mtGreen : Color.mtRed)
                }
                BalanceChartView(series: series)
            }
            .mtCard()
        }
    }

    private func safeBudgetCard(_ L: Ledger) -> some View {
        let s = L.monthStats(monthKey)
        let total = budgets.reduce(0) { $0 + $1.limit }
        let budgeted = Set(budgets.map(\.categoryId))
        let bSpent = L.rows.filter { $0.type == "expense" && $0.date.hasPrefix(monthKey) && budgeted.contains($0.categoryId) }.reduce(0) { $0 + $1.personal }
        let safe = total > 0 ? max((total - bSpent) / Double(daysLeft), 0) : s.income > 0 ? max((s.income - s.spent) / Double(daysLeft), 0) : 0
        return HStack(spacing: 0) {
            Button { router.goInsights("budget") } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Safe / day", systemImage: "flame.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.mtTxt2)
                        .symbolRenderingMode(.palette).foregroundStyle(Color.mtTxt2, Color.mtAcc)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(Fmt.money(safe)).money(18).kerning(-0.4).foregroundStyle(safe > 0 ? Color.primary : Color.mtTxt3)
                        Text("· \(daysLeft) d left").font(.system(size: 10)).foregroundStyle(Color.mtTxt3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 15).padding(.vertical, 13)
            }
            .buttonStyle(.press)
            Rectangle().fill(Color.mtBorder).frame(width: 1).padding(.vertical, 12)
            Button { router.goInsights("budget") } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Budget left", systemImage: "chart.pie.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.mtTxt2)
                    if total > 0 {
                        Text(Fmt.money(max(total - bSpent, 0))).money(18).kerning(-0.4).foregroundStyle(bSpent > total ? Color.mtRed : Color.primary)
                        ProgressBar(value: bSpent / total, color: bSpent > total ? .mtRed : .mtGreen, height: 3)
                    } else {
                        Text("Set up →").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.mtAcc)
                        Text("Track monthly limits").font(.system(size: 10)).foregroundStyle(Color.mtTxt3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 15).padding(.vertical, 13)
            }
            .buttonStyle(.press)
        }
        .mtCard(padding: 0)
    }

    @ViewBuilder private func insightsRow(_ L: Ledger) -> some View {
        let list = insights(L)
        if !list.isEmpty {
            SectionLabel(text: "Insights")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(list, id: \.label) { ins in
                        Button { router.goInsights("spend") } label: {
                            HStack(spacing: 9) {
                                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(ins.tone.opacity(0.14)).frame(width: 30, height: 30)
                                    .overlay(Image(systemName: ins.icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(ins.tone))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(ins.label).font(.system(size: 10)).foregroundStyle(Color.mtTxt3)
                                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                                        Text(ins.value).money(14).foregroundStyle(ins.tone)
                                        Text(ins.sub).font(.system(size: 10)).foregroundStyle(Color.mtTxt3).lineLimit(1)
                                    }
                                }
                            }
                            .padding(.horizontal, 13).padding(.vertical, 10)
                            .background(Color.mtCard, in: RoundedRectangle(cornerRadius: MT.inner, style: .continuous))
                        }
                        .buttonStyle(.press)
                    }
                }
                .padding(.horizontal, 1)
            }
            .scrollClipDisabled()
        }
    }

    private struct Insight { let label: String; let value: String; let sub: String; let tone: Color; let icon: String }
    private func insights(_ L: Ledger) -> [Insight] {
        let s = L.monthStats(monthKey)
        let day = Calendar.current.component(.day, from: Date())
        let lastKey = Fmt.monthKey(Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date())
        let last = L.monthStats(lastKey).spent
        var out: [Insight] = []
        if s.income > 0 {
            let r = Int(((s.income - s.spent) / s.income * 100).rounded())
            out.append(Insight(label: "Savings rate", value: "\(r)%", sub: r >= 20 ? "Great!" : "Aim for 20%+", tone: r >= 20 ? .mtGreen : (r >= 0 ? .mtAcc : .mtRed), icon: "leaf.fill"))
        }
        if s.spent > 0 && day >= 5 { out.append(Insight(label: "Projected spend", value: Fmt.money(L.projectedSpend(monthKey)), sub: "at typical pace", tone: .mtAcc, icon: "chart.line.uptrend.xyaxis")) }
        if last > 0 {
            let d = Int(((s.spent - last) / last * 100).rounded())
            out.append(Insight(label: "vs last month", value: (d > 0 ? "+" : "") + "\(d)%", sub: d <= 0 ? "less spending" : "more spending", tone: d <= 0 ? .mtGreen : .mtRed, icon: d <= 0 ? "sparkles" : "exclamationmark.circle"))
        }
        if s.spent > 0 { out.append(Insight(label: "Daily average", value: Fmt.money(s.spent / Double(max(day, 1))), sub: "over \(day) days", tone: .mtAcc, icon: "calendar")) }
        if let big = L.biggestExpense(month: monthKey) { out.append(Insight(label: "Biggest expense", value: Fmt.money(big.personal), sub: big.merchant.isEmpty ? "—" : big.merchant, tone: .mtRed, icon: "flame.fill")) }
        return out
    }

    private func recentCard(_ L: Ledger) -> some View {
        let recent = L.rows.sorted { $0.date > $1.date }.prefix(6)
        return VStack(spacing: 0) {
            SectionLabel(text: "Recent", action: "See all") { router.goActivity() }.padding(.bottom, 8)
            VStack(spacing: 0) {
                if recent.isEmpty {
                    Text(accounts.isEmpty ? "Add an account first — or restore your web backup in Settings." : "No transactions yet")
                        .font(.system(size: 14)).foregroundStyle(Color.mtTxt3).frame(maxWidth: .infinity, alignment: .leading).padding(15)
                }
                ForEach(Array(recent.enumerated()), id: \.element.id) { i, r in
                    if i > 0 { Divider().overlay(Color.mtBorder).padding(.leading, 64) }
                    Button { editTx = txs.first { $0.id == r.id } } label: {
                        TxRowView(r: r, cats: cats, accounts: accounts).padding(.horizontal, 15).padding(.vertical, 10)
                    }
                    .buttonStyle(.press)
                }
            }
            .mtCard(padding: 0)
        }
    }

    @ViewBuilder private var goalsCard: some View {
        if !goals.isEmpty {
            VStack(spacing: 0) {
                SectionLabel(text: "Savings goals", action: "See all") { router.goWallet("goals") }.padding(.bottom, 8)
                Button { router.goWallet("goals") } label: {
                    VStack(spacing: 12) {
                        ForEach(goals.prefix(2)) { g in
                            let pct = g.targetAmount > 0 ? min(g.savedAmount / g.targetAmount, 1) : 0
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Label { Text(g.name) } icon: { GoalGlyph(goal: g, size: 14) }.font(.system(size: 14))
                                    Spacer()
                                    Text(Fmt.money(g.savedAmount)).money(14, .semibold) + Text(" / \(Fmt.money(g.targetAmount))").font(.system(size: 14)).foregroundStyle(Color.mtTxt3)
                                }
                                ProgressBar(value: pct, color: Color(hex: g.colorHex))
                                Text("\(Int((pct * 100).rounded()))% · \(Fmt.money(max(g.targetAmount - g.savedAmount, 0))) to go").font(.system(size: 11)).foregroundStyle(Color.mtTxt3)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                    .mtCard()
                }
                .buttonStyle(.press)
            }
        }
    }

    private func topCategories(_ L: Ledger) -> some View {
        let month = router.spendMonth == "all" ? nil : router.spendMonth
        let list = Array(L.categoryTotals(month: month).prefix(5))
        let top = list.first?.total ?? 1
        return VStack(spacing: 0) {
            SectionLabel(text: "Top categories").padding(.bottom, 8)
            VStack(spacing: 12) {
                if list.isEmpty { Text("No spending yet").font(.system(size: 14)).foregroundStyle(Color.mtTxt3).frame(maxWidth: .infinity, alignment: .leading) }
                ForEach(list) { c in
                    let cat = cats.first { $0.id == c.id }
                    Button { router.goInsights("spend", drill: c.id) } label: {
                        VStack(spacing: 5) {
                            HStack {
                                Label { Text(cat?.label ?? c.id).foregroundStyle(Color.mtTxt2) } icon: { CatGlyph(cat: cat, size: 13) }.font(.system(size: 13))
                                Spacer()
                                Text(Fmt.money(c.total)).money(13, .semibold)
                            }
                            ProgressBar(value: c.total / top, color: Color(hex: cat?.colorHex ?? "#9ca3af"), height: 4)
                        }
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.press)
                }
            }
            .mtCard()
        }
    }
}
