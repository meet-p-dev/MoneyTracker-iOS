import SwiftUI
import SwiftData

struct PeopleView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Debt.date, order: .reverse) private var debts: [Debt]
    @Query(sort: \Txn.date, order: .reverse) private var txs: [Txn]
    @Query(sort: \Account.sortIndex) private var accounts: [Account]
    @Query private var cats: [TxCategory]

    @State private var showAddDebt = false
    @State private var repayDebt: Debt?

    private var activeDebts: [Debt] { debts.filter { !$0.settled } }
    private var pendingSplits: [Txn] { txs.filter { $0.isSplit && !$0.splitSettled && $0.type == "expense" } }
    private var totalOwedToMe: Double {
        pendingSplits.reduce(0) { $0 + ($1.amount - $1.personalAmount) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !activeDebts.isEmpty {
                    Section("You owe · \(Fmt.money(activeDebts.reduce(0) { $0 + ($1.totalAmount - $1.paidBack) }))") {
                        ForEach(activeDebts) { d in debtRow(d) }
                    }
                }
                if !pendingSplits.isEmpty {
                    Section("Others owe you · \(Fmt.money(totalOwedToMe))") {
                        ForEach(pendingSplits) { t in splitRow(t) }
                    }
                }
                if !debts.filter(\.settled).isEmpty {
                    Section("Settled") {
                        ForEach(debts.filter(\.settled)) { d in
                            HStack {
                                Text(d.personName)
                                Spacer()
                                Text(Fmt.money(d.totalAmount)).foregroundStyle(.secondary).monospacedDigit()
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                    }
                }
                if debts.isEmpty && pendingSplits.isEmpty {
                    ContentUnavailableView("No debts or splits", systemImage: "person.2",
                                           description: Text("Borrowed money and WG splits show up here."))
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("People & Money")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddDebt = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAddDebt) { DebtForm() }
            .sheet(item: $repayDebt) { RepayForm(debt: $0) }
        }
    }

    private func debtRow(_ d: Debt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(Color(hex: d.colorHex)).frame(width: 36, height: 36)
                    .overlay(Text(String(d.personName.prefix(1))).font(.headline).foregroundStyle(.white))
                VStack(alignment: .leading) {
                    Text(d.personName).font(.subheadline.weight(.semibold))
                    Text("Borrowed \(Fmt.money(d.totalAmount)) · \(d.date)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(Fmt.money(d.totalAmount - d.paidBack))
                        .font(.subheadline.weight(.bold)).foregroundStyle(.red).monospacedDigit()
                    Text("left to pay").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            ProgressView(value: d.totalAmount > 0 ? d.paidBack / d.totalAmount : 0)
                .tint(Color(hex: d.colorHex))
            Button("Log repayment") { repayDebt = d }
                .buttonStyle(.borderedProminent).controlSize(.small)
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { ctx.delete(d); try? ctx.save() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func splitRow(_ t: Txn) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(t.merchant).font(.subheadline.weight(.semibold))
                Text("\(t.date) · \(t.splitPeople) people").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("+" + Fmt.money(t.amount - t.personalAmount))
                .font(.subheadline.weight(.bold)).foregroundStyle(.green).monospacedDigit()
            Button("Settle") {
                ctx.insert(Txn(type: "income", amount: t.amount - t.personalAmount,
                               merchant: "WG Settlement", categoryId: "other",
                               accountId: t.accountId, notes: "Settlement for \(t.merchant)",
                               date: Fmt.today()))
                t.splitSettled = true
                try? ctx.save(); Haptic.success()
            }
            .buttonStyle(.bordered).controlSize(.small)
        }
    }
}

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
                HStack { Text("€").foregroundStyle(.secondary)
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
                        guard let v = Double(amount.replacingOccurrences(of: ",", with: ".")), v > 0, !person.isEmpty else { return }
                        ctx.insert(Debt(personName: person, totalAmount: v, date: Fmt.today(),
                                        details: details, receivedInAccount: receivedIn))
                        if !receivedIn.isEmpty {
                            ctx.insert(Txn(type: "income", amount: v, merchant: "Borrowed from \(person)",
                                           categoryId: "other", accountId: receivedIn,
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
                HStack { Text("€").foregroundStyle(.secondary)
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
                        guard let req = Double(amount.replacingOccurrences(of: ",", with: ".")), req > 0,
                              !fromAccount.isEmpty else { return }
                        let v = min(req, debt.totalAmount - debt.paidBack)   // cap at remaining
                        ctx.insert(Txn(type: "expense", amount: v, merchant: "Repayment → \(debt.personName)",
                                       categoryId: "other", accountId: fromAccount,
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
