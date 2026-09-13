import SwiftUI
import SwiftData

// Activity (web ActivityTab): search, the five direction chips, a live summary line
// ("12 transactions · 342,10 € spent"), category/account filters, then every row by day.
struct ActivityView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(Router.self) private var router
    @Query(sort: \Account.sortIndex) private var accounts: [Account]
    @Query private var cats: [TxCategory]
    @Query(sort: \Txn.date, order: .reverse) private var txs: [Txn]
    @State private var editTx: Txn?

    private let kinds: [(String, String)] = [("", "All"), ("income", "Income"), ("credit", "Received"), ("expense", "Spent"), ("transfer", "Transfers")]

    var body: some View {
        @Bindable var router = router
        let rows = Ledger.build(accounts: accounts, txs: txs).rows.filter { t in
            if !router.activitySearch.isEmpty && !t.merchant.localizedCaseInsensitiveContains(router.activitySearch)
                && !t.notes.localizedCaseInsensitiveContains(router.activitySearch) { return false }
            if !router.activityType.isEmpty && t.type != router.activityType { return false }
            if !router.activityCat.isEmpty && t.categoryId != router.activityCat { return false }
            if !router.activityAcc.isEmpty && t.accountId != router.activityAcc && t.toAccountId != router.activityAcc { return false }
            return true
        }
        let groups = Dictionary(grouping: rows, by: \.date)
        let days = groups.keys.sorted(by: >)

        return NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(kinds, id: \.0) { k in
                                ChipButton(title: k.1, on: router.activityType == k.0, tint: k.0 == "credit" ? .mtRecv : .mtAcc) {
                                    withAnimation(MT.spring) { router.activityType = k.0 }
                                }
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 2)
                    }
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear).listRowSeparator(.hidden)
                    if !rows.isEmpty {
                        (Text("\(rows.count) transaction\(rows.count == 1 ? "" : "s") · ") + Text(Fmt.money(summary(rows).sum)).bold().foregroundStyle(.primary) + Text(" \(summary(rows).verb)"))
                            .font(.system(size: 13)).foregroundStyle(Color.mtTxt2)
                            .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                            .listRowSeparator(.hidden)
                    }
                }
                ForEach(days, id: \.self) { date in
                    let items = groups[date] ?? []
                    Section {
                        ForEach(items) { r in
                            Button { editTx = txs.first { $0.id == r.id } } label: {
                                TxRowView(r: r, cats: cats, accounts: accounts, detailed: true)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.mtCard)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { delete(r.id) } label: { Label("Delete", systemImage: "trash") }
                                Button { editTx = txs.first { $0.id == r.id } } label: { Label("Edit", systemImage: "pencil") }.tint(.mtAcc)
                            }
                        }
                    } header: {
                        HStack {
                            Text(Fmt.prettyDay(date))
                            Spacer()
                            let spent = items.filter { $0.type == "expense" }.reduce(0) { $0 + $1.personal }
                            if spent > 0 { Text("−" + Fmt.money(spent)).monospacedDigit() }
                        }
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.mtTxt2).textCase(nil)
                    }
                }
                if rows.isEmpty {
                    Section {
                        EmptyCard(icon: "tray", title: txs.isEmpty ? "No transactions yet" : "Nothing matches",
                                  message: txs.isEmpty ? "Tap + to add one, or sign in to bank sync in Settings and they arrive by themselves."
                                                       : "Try another filter or search.")
                    }
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
            }
            .listSectionSpacing(12)
            .scrollContentBackground(.hidden)
            .mtCanvas()
            .searchable(text: $router.activitySearch, prompt: "Search merchant…")
            .refreshable { await CloudSync.shared.sync(ctx: ctx) }
            .navigationTitle("Activity")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Category", selection: $router.activityCat) {
                            Text("All categories").tag("")
                            ForEach(cats) { c in Text(c.label).tag(c.id) }
                        }
                        Picker("Account", selection: $router.activityAcc) {
                            Text("All accounts").tag("")
                            ForEach(accounts) { a in Text(a.name).tag(a.id) }
                        }
                        if !router.activityCat.isEmpty || !router.activityAcc.isEmpty {
                            Button("Clear filters", role: .destructive) { router.activityCat = ""; router.activityAcc = "" }
                        }
                    } label: {
                        Image(systemName: router.activityCat.isEmpty && router.activityAcc.isEmpty
                              ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
            }
            .sheet(item: $editTx) { TransactionForm(existing: $0) }
        }
    }

    /// web filtSummary: the verb follows the active filter.
    private func summary(_ rows: [Row]) -> (sum: Double, verb: String) {
        switch router.activityType {
        case "income": return (rows.reduce(0) { $0 + $1.amount }, "in")
        case "credit": return (rows.reduce(0) { $0 + $1.amount }, "received")
        case "transfer": return (rows.reduce(0) { $0 + $1.amount }, "moved")
        case "expense": return (rows.reduce(0) { $0 + $1.personal }, "spent")
        default: return (rows.filter { $0.type == "expense" }.reduce(0) { $0 + $1.personal }, "spent")
        }
    }

    private func delete(_ id: String) {
        guard let t = txs.first(where: { $0.id == id }) else { return }
        ctx.delete(t); LearningStore.shared.forget(id)
        try? ctx.save(); Haptic.warning()
    }
}
