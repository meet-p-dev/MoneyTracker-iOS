import SwiftUI
import SwiftData

// Wallet → Debts lives in WalletView.swift; these are its add / repay sheets.

struct DebtForm: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortIndex) private var accounts: [Account]
    @State private var person = ""
    @State private var amount = ""
    @State private var details = ""
    @State private var receivedIn = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Person's name", text: $person)
                HStack { Text(Fmt.currencySymbol).foregroundStyle(.secondary)
                    TextField("Amount borrowed", text: $amount).keyboardType(.decimalPad) }
                Picker("Received into account", selection: $receivedIn) {
                    Text("None (cash / outside)").tag("")
                    ForEach(accounts) { a in Text(a.name).tag(a.id) }
                }
                TextField("What for?", text: $details)
            }
            .navigationTitle("New Debt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let v = Fmt.amount(amount), v > 0, !person.isEmpty else { return }
                        ctx.insert(Debt(personName: person, totalAmount: v, date: Fmt.today(),
                                        details: details, receivedInAccount: receivedIn))
                        if !receivedIn.isEmpty {
                            ctx.insert(Txn(type: "income", amount: v, merchant: "Borrowed from \(person)",
                                           categoryId: "debt", accountId: receivedIn,
                                           notes: "Debt: \(details.isEmpty ? person : details)", date: Fmt.today()))
                        }
                        try? ctx.save(); Haptic.success(); dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct RepayForm: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortIndex) private var accounts: [Account]
    let debt: Debt
    @State private var amount = ""
    @State private var fromAccount = ""

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("Open", value: Fmt.money(debt.totalAmount - debt.paidBack))
                HStack { Text(Fmt.currencySymbol).foregroundStyle(.secondary)
                    TextField("Repayment amount", text: $amount).keyboardType(.decimalPad) }
                Picker("From account", selection: $fromAccount) {
                    Text("Select…").tag("")
                    ForEach(accounts) { a in Text(a.name).tag(a.id) }
                }
            }
            .navigationTitle("Repay \(debt.personName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        guard let req = Fmt.amount(amount), req > 0,
                              !fromAccount.isEmpty else { return }
                        let v = min(req, debt.totalAmount - debt.paidBack)   // cap at remaining
                        ctx.insert(Txn(type: "expense", amount: v, merchant: "Repayment → \(debt.personName)",
                                       categoryId: "debt", accountId: fromAccount,
                                       notes: "Debt repayment", date: Fmt.today()))
                        debt.paidBack += v
                        if debt.paidBack >= debt.totalAmount { debt.settled = true }
                        try? ctx.save(); Haptic.success(); dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
