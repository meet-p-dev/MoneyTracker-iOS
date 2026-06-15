import SwiftUI
import SwiftData

struct AccountsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Account.sortIndex) private var accounts: [Account]
    @Query(sort: \Txn.date, order: .reverse) private var txs: [Txn]
    @State private var editAcc: Account?
    @State private var showAdd = false

    var body: some View {
        List {
            ForEach(accounts) { a in
                let bal = Money.balance(of: a, txs: txs)
                HStack(spacing: 12) {
                    Circle().fill(Color(hex: a.colorHex)).frame(width: 40, height: 40)
                        .overlay(Text(String(a.name.prefix(1))).font(.headline).foregroundStyle(.white))
                    VStack(alignment: .leading) {
                        Text(a.name).fontWeight(.semibold)
                        Text("\(txs.filter { $0.accountId == a.id || $0.toAccountId == a.id }.count) transactions")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Fmt.money(bal)).monospacedDigit().fontWeight(.bold)
                        .foregroundStyle(bal >= 0 ? Color.green : Color.red)
                }
                .contentShape(Rectangle())
                .onTapGesture { editAcc = a }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { ctx.delete(a); try? ctx.save() } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Accounts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $editAcc) { AccountForm(existing: $0) }
        .sheet(isPresented: $showAdd) { AccountForm(existing: nil) }
    }
}

struct AccountForm: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var all: [Account]
    let existing: Account?
    @State private var name = ""
    @State private var initial = ""
    @State private var color = Color(hex: "#3b82f6")

    var body: some View {
        NavigationStack {
            Form {
                TextField("Account name", text: $name)
                HStack { Text("€").foregroundStyle(.secondary)
                    TextField("Initial balance", text: $initial).keyboardType(.numbersAndPunctuation) }
                ColorPicker("Color", selection: $color, supportsOpacity: false)
            }
            .navigationTitle(existing == nil ? "New Account" : "Edit Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard !name.isEmpty else { return }
                        let ib = Double(initial.replacingOccurrences(of: ",", with: ".")) ?? 0
                        let hex = color.toHex()
                        if let a = existing {
                            a.name = name; a.initialBalance = ib; a.colorHex = hex
                        } else {
                            ctx.insert(Account(name: name, colorHex: hex, initialBalance: ib,
                                               sortIndex: (all.map(\.sortIndex).max() ?? 0) + 1))
                        }
                        try? ctx.save(); dismiss()
                    }
                }
            }
            .onAppear {
                if let a = existing {
                    name = a.name; initial = String(a.initialBalance); color = Color(hex: a.colorHex)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

extension Color {
    func toHex() -> String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
