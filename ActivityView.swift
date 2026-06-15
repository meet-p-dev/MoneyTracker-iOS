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

    private var filtered: [Txn] {
        txs.filter { t in
            if !search.isEmpty && !t.merchant.localizedCaseInsensitiveContains(search) { return false }
            if !fType.isEmpty && t.type != fType { return false }
            if !fCat.isEmpty && t.categoryId != fCat { return false }
            if !fAcc.isEmpty && t.accountId != fAcc { return false }
            return true
        }
    }

    private var grouped: [(String, [Txn])] {
        let g = Dictionary(grouping: filtered, by: \.date)
        return g.keys.sorted(by: >).map { ($0, g[$0]!) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Type", selection: $fType) {
                        Text("All").tag("")
                        Text("Income").tag("income")
                        Text("Expenses").tag("expense")
                        Text("Transfers").tag("transfer")
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
                }
                ForEach(grouped, id: \.0) { date, items in
                    Section {
                        ForEach(items) { t in
                            TxRow(t: t, cats: cats, accounts: accounts)
                                .contentShape(Rectangle())
                                .onTapGesture { editTx = t }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        ctx.delete(t); try? ctx.save(); Haptic.warning()
                                    } label: { Label("Delete", systemImage: "trash") }
                                    Button { editTx = t } label: { Label("Edit", systemImage: "pencil") }
                                        .tint(.blue)
                                }
                        }
                    } header: {
                        HStack {
                            Text(Fmt.prettyDay(date))
                            Spacer()
                            let daySpend = items.filter { $0.type == "expense" }.reduce(0) { $0 + $1.personalAmount }
                            if daySpend > 0 { Text("−" + Fmt.money(daySpend)).monospacedDigit() }
                        }
                    }
                }
                if filtered.isEmpty {
                    ContentUnavailableView("No transactions found", systemImage: "tray")
                        .listRowBackground(Color.clear)
                }
            }
            .searchable(text: $search, prompt: "Search merchant…")
            .navigationTitle("Activity")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Category", selection: $fCat) {
                            Text("All categories").tag("")
                            ForEach(cats) { c in Text("\(c.icon) \(c.label)").tag(c.id) }
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
}
