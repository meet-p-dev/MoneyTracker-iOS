import SwiftUI
import SwiftData

/// "Show me the transactions behind this number" — every tappable figure in Insights.
struct TxSelection: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let ids: Set<String>
}

struct TxListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortIndex) private var accounts: [Account]
    @Query private var cats: [TxCategory]
    @Query(sort: \Txn.date, order: .reverse) private var txs: [Txn]
    let sel: TxSelection
    @State private var editTx: Txn?

    var body: some View {
        let rows = Ledger.build(accounts: accounts, txs: txs).rows.filter { sel.ids.contains($0.id) }.sorted { $0.date > $1.date }
        let spent = rows.filter { $0.type == "expense" }.reduce(0) { $0 + $1.personal }
        let inflow = rows.filter(\.isIn).reduce(0) { $0 + $1.amount }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sel.subtitle).font(.system(size: 13)).foregroundStyle(Color.mtTxt2)
                        HStack(spacing: 14) {
                            Text("\(rows.count) transaction\(rows.count == 1 ? "" : "s")").font(.system(size: 15, weight: .semibold))
                            if spent > 0 { Text("spent \(Fmt.money(spent))").money(15, .semibold).foregroundStyle(Color.mtRed) }
                            if inflow > 0 { Text("in \(Fmt.money(inflow))").money(15, .semibold).foregroundStyle(Color.mtGreen) }
                        }
                    }
                    .mtCard()
                    TxRowsCard(rows: rows, cats: cats, accounts: accounts) { r in editTx = txs.first { $0.id == r.id } }
                }
                .padding(16)
            }
            .mtCanvas()
            .navigationTitle(sel.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $editTx) { TransactionForm(existing: $0) }
        }
        .presentationDetents([.medium, .large])
    }
}

/// A card of transaction rows (tap one to open it).
struct TxRowsCard: View {
    let rows: [Row]
    let cats: [TxCategory]
    let accounts: [Account]
    let onTap: (Row) -> Void
    var body: some View {
        VStack(spacing: 0) {
            if rows.isEmpty {
                Text("No transactions").font(.system(size: 14)).foregroundStyle(Color.mtTxt3)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(15)
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                if i > 0 { Divider().overlay(Color.mtBorder).padding(.leading, 71) }
                Button { onTap(r) } label: {
                    TxRowView(r: r, cats: cats, accounts: accounts, detailed: true).padding(.horizontal, 15).padding(.vertical, 11)
                }
                .buttonStyle(.press)
            }
        }
        .mtCard(padding: 0)
    }
}
