import SwiftUI
import SwiftData

// Wallet → Goals lives in WalletView.swift; this is its add / edit sheet.

struct GoalForm: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let existing: Goal?

    @State private var name = ""
    @State private var target = ""
    @State private var saved = ""
    @State private var sym = "goal"

    var body: some View {
        NavigationStack {
            Form {
                TextField("Goal name", text: $name)
                HStack { Text(Fmt.currencySymbol).foregroundStyle(.secondary)
                    TextField("Target amount", text: $target).keyboardType(.decimalPad) }
                HStack { Text(Fmt.currencySymbol).foregroundStyle(.secondary)
                    TextField("Already saved", text: $saved).keyboardType(.decimalPad) }
                Picker("Symbol", selection: $sym) {
                    ForEach(Symbols.goalKeys, id: \.self) { k in Image(systemName: Symbols.name(k) ?? "target").tag(k) }
                }
                .pickerStyle(.menu)
            }
            .navigationTitle(existing == nil ? "New Goal" : "Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let t = Fmt.amount(target), t > 0, !name.isEmpty else { return }
                        let s = Fmt.amount(saved) ?? 0
                        if let g = existing {
                            g.name = name; g.targetAmount = t; g.savedAmount = s; g.sym = sym
                        } else {
                            ctx.insert(Goal(name: name, targetAmount: t, savedAmount: s, sym: sym))
                        }
                        try? ctx.save(); Haptic.success(); dismiss()
                    }
                }
            }
            .onAppear {
                if let g = existing {
                    name = g.name; target = Fmt.editable(g.targetAmount); saved = Fmt.editable(g.savedAmount); sym = g.sym.isEmpty ? BackupService.goalSym(forEmoji: g.icon) : g.sym
                }
            }
        }
        .presentationDetents([.medium])
    }
}
