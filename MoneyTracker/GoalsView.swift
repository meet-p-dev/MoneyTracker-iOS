import SwiftUI
import SwiftData

struct GoalsView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var goals: [Goal]
    @State private var editGoal: Goal?
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(goals) { g in
                    goalCard(g)
                        .contentShape(Rectangle())
                        .onTapGesture { editGoal = g }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { ctx.delete(g); try? ctx.save() } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                if goals.isEmpty {
                    ContentUnavailableView("No goals yet", systemImage: "target",
                                           description: Text("Set a savings goal to track progress."))
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Savings Goals")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(item: $editGoal) { GoalForm(existing: $0) }
            .sheet(isPresented: $showAdd) { GoalForm(existing: nil) }
        }
    }

    private func goalCard(_ g: Goal) -> some View {
        let pct = g.targetAmount > 0 ? min(g.savedAmount / g.targetAmount, 1) : 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                GoalGlyph(goal: g, size: 20)
                    .frame(width: 44, height: 44)
                    .background(Color(hex: g.colorHex).opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading) {
                    Text(g.name).font(.subheadline.weight(.bold))
                    Text(pct >= 1 ? "Goal reached! 🎉" : Fmt.money(g.targetAmount - g.savedAmount) + " to go")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(Fmt.money(g.savedAmount))
                        .font(.subheadline.weight(.bold)).monospacedDigit()
                        .foregroundStyle(Color(hex: g.colorHex))
                    Text("of " + Fmt.money(g.targetAmount)).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            ProgressView(value: pct).tint(Color(hex: g.colorHex))
            Text("\(Int((pct * 100).rounded()))% saved").font(.caption.weight(.semibold))
                .foregroundStyle(Color(hex: g.colorHex))
        }
        .padding(.vertical, 4)
    }
}

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
