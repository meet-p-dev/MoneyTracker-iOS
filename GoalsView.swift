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
                Text(g.icon).font(.title2)
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
    @State private var icon = "🎯"
    private let icons = ["🎯","✈️","🏠","🎓","🚗","💻","🎮","💍","🏖️","🎁","💊","🐾"]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Goal name", text: $name)
                HStack { Text("€").foregroundStyle(.secondary)
                    TextField("Target amount", text: $target).keyboardType(.decimalPad) }
                HStack { Text("€").foregroundStyle(.secondary)
                    TextField("Already saved", text: $saved).keyboardType(.decimalPad) }
                Picker("Icon", selection: $icon) {
                    ForEach(icons, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
            }
            .navigationTitle(existing == nil ? "New Goal" : "Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let t = Double(target.replacingOccurrences(of: ",", with: ".")), t > 0, !name.isEmpty else { return }
                        let s = Double(saved.replacingOccurrences(of: ",", with: ".")) ?? 0
                        if let g = existing {
                            g.name = name; g.targetAmount = t; g.savedAmount = s; g.icon = icon
                        } else {
                            ctx.insert(Goal(name: name, targetAmount: t, savedAmount: s, icon: icon))
                        }
                        try? ctx.save(); Haptic.success(); dismiss()
                    }
                }
            }
            .onAppear {
                if let g = existing {
                    name = g.name; target = String(g.targetAmount); saved = String(g.savedAmount); icon = g.icon
                }
            }
        }
        .presentationDetents([.medium])
    }
}
