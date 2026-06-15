import SwiftUI
import SwiftData

struct TransactionForm: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortIndex) private var accounts: [Account]
    @Query private var cats: [TxCategory]

    let existing: Txn?

    @State private var type = "expense"
    @State private var amount = ""
    @State private var merchant = ""
    @State private var categoryId = "other"
    @State private var accountId = ""
    @State private var toAccountId = ""
    @State private var notes = ""
    @State private var date = Date()
    @State private var isSplit = false
    @State private var splitPeople = 2

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $type) {
                    Text("💸 Expense").tag("expense")
                    Text("💰 Income").tag("income")
                    Text("🔄 Transfer").tag("transfer")
                }
                .pickerStyle(.segmented)

                Section {
                    HStack {
                        Text("€").foregroundStyle(.secondary)
                        TextField("0,00", text: $amount)
                            .keyboardType(.decimalPad)
                            .font(.title2.weight(.bold)).monospacedDigit()
                    }
                    TextField(type == "income" ? "Source (e.g. Salary)" : "Merchant", text: $merchant)
                }

                Section {
                    Picker(type == "transfer" ? "From account" : "Account", selection: $accountId) {
                        ForEach(accounts) { a in Text(a.name).tag(a.id) }
                    }
                    if type == "transfer" {
                        Picker("To account", selection: $toAccountId) {
                            Text("Select…").tag("")
                            ForEach(accounts.filter { $0.id != accountId }) { a in Text(a.name).tag(a.id) }
                        }
                    } else {
                        Picker("Category", selection: $categoryId) {
                            ForEach(cats) { c in Text("\(c.icon) \(c.label)").tag(c.id) }
                        }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                if type == "expense" {
                    Section {
                        Toggle("Split with others (WG)", isOn: $isSplit)
                        if isSplit {
                            Stepper("People: \(splitPeople)", value: $splitPeople, in: 2...12)
                            if let v = parsedAmount {
                                Text("Your share: \(Fmt.money(v / Double(splitPeople)))")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section { TextField("Notes", text: $notes, axis: .vertical) }
            }
            .navigationTitle(existing == nil ? "New Transaction" : "Edit Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
            .onAppear(perform: load)
        }
        .presentationDetents([.large])
    }

    private var parsedAmount: Double? {
        Double(amount.replacingOccurrences(of: ",", with: ".")).flatMap { $0 > 0 ? $0 : nil }
    }
    private var canSave: Bool {
        parsedAmount != nil && !accountId.isEmpty && (type != "transfer" || !toAccountId.isEmpty)
    }

    private func load() {
        if let t = existing {
            type = t.type; amount = String(t.amount).replacingOccurrences(of: ".", with: ",")
            merchant = t.merchant; categoryId = t.categoryId; accountId = t.accountId
            toAccountId = t.toAccountId; notes = t.notes; date = Fmt.parse(t.date)
            isSplit = t.isSplit; splitPeople = max(t.splitPeople, 2)
        } else if accountId.isEmpty {
            accountId = UserDefaults.standard.string(forKey: "lastAccount") ?? accounts.first?.id ?? ""
            categoryId = UserDefaults.standard.string(forKey: "lastCategory") ?? "other"
        }
    }

    private func save() {
        guard let v = parsedAmount else { return }
        let dateStr = Fmt.day.string(from: date)
        if let t = existing {
            t.type = type; t.amount = v; t.merchant = merchant; t.categoryId = categoryId
            t.accountId = accountId; t.toAccountId = type == "transfer" ? toAccountId : ""
            t.notes = notes; t.date = dateStr
            t.isSplit = type == "expense" && isSplit
            t.splitPeople = t.isSplit ? splitPeople : 1
        } else {
            ctx.insert(Txn(type: type, amount: v, merchant: merchant, categoryId: categoryId,
                           accountId: accountId, toAccountId: type == "transfer" ? toAccountId : "",
                           notes: notes, date: dateStr,
                           isSplit: type == "expense" && isSplit,
                           splitPeople: type == "expense" && isSplit ? splitPeople : 1))
        }
        UserDefaults.standard.set(accountId, forKey: "lastAccount")
        UserDefaults.standard.set(categoryId, forKey: "lastCategory")
        try? ctx.save()
        Haptic.success()
        dismiss()
    }
}
