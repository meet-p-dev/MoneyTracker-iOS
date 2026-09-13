import SwiftUI
import SwiftData

struct ActivityView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Account.sortIndex) private var accounts: [Account]
    @Query private var cats: [TxCategory]
    @Query(sort: \Txn.date, order: .reverse) private var txs: [Txn]

    @State private var search = ""
    @State private var fType = ""
    @State private var fCat = ""
    @State private var fAcc = ""
    @State private var editTx: Txn?
    @State private var showAdd = false

    var body: some View {
        let rows = Ledger.build(accounts: accounts, txs: txs).rows.filter { t in
            if !search.isEmpty && !t.merchant.localizedCaseInsensitiveContains(search) { return false }
            if !fType.isEmpty && t.type != fType { return false }
            if !fCat.isEmpty && t.categoryId != fCat { return false }
            if !fAcc.isEmpty && t.accountId != fAcc && t.toAccountId != fAcc { return false }
            return true
        }
        let groups = Dictionary(grouping: rows, by: \.date)
        let days = groups.keys.sorted(by: >)

        return NavigationStack {
            List {
                Section {
                    Picker("Type", selection: $fType) {
                        Text("All").tag("")
                        Text("Income").tag("income")
                        Text("Received").tag("credit")
                        Text("Spent").tag("expense")
                        Text("Transfers").tag("transfer")
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
                }
                ForEach(days, id: \.self) { date in
                    let items = groups[date] ?? []
                    Section {
                        ForEach(items) { r in
                            TxRow(r: r, cats: cats, accounts: accounts)
                                .contentShape(Rectangle())
                                .onTapGesture { editTx = txs.first { $0.id == r.id } }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { delete(r.id) } label: { Label("Delete", systemImage: "trash") }
                                    Button { editTx = txs.first { $0.id == r.id } } label: { Label("Edit", systemImage: "pencil") }
                                        .tint(.blue)
                                }
                        }
                    } header: {
                        HStack {
                            Text(Fmt.prettyDay(date))
                            Spacer()
                            let spent = items.filter { $0.type == "expense" }.reduce(0) { $0 + $1.personal }
                            if spent > 0 { Text("−" + Fmt.money(spent)).monospacedDigit() }
                        }
                    }
                }
                if rows.isEmpty {
                    ContentUnavailableView("No transactions found", systemImage: "tray")
                        .listRowBackground(Color.clear)
                }
            }
            .searchable(text: $search, prompt: "Search merchant…")
            .refreshable { await CloudSync.shared.sync(ctx: ctx) }
            .navigationTitle("Activity")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Category", selection: $fCat) {
                            Text("All categories").tag("")
                            ForEach(cats) { c in Text(c.label).tag(c.id) }
                        }
                        Picker("Account", selection: $fAcc) {
                            Text("All accounts").tag("")
                            ForEach(accounts) { a in Text(a.name).tag(a.id) }
                        }
                    } label: {
                        Image(systemName: (fCat.isEmpty && fAcc.isEmpty) ? "line.3.horizontal.decrease.circle"
                                                                         : "line.3.horizontal.decrease.circle.fill")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(item: $editTx) { TransactionForm(existing: $0) }
            .sheet(isPresented: $showAdd) { TransactionForm(existing: nil) }
        }
    }

    private func delete(_ id: String) {
        guard let t = txs.first(where: { $0.id == id }) else { return }
        ctx.delete(t); LearningStore.shared.forget(id)
        try? ctx.save(); Haptic.warning()
    }
}
