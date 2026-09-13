import SwiftUI
import SwiftData

// The Review inbox (web ReviewSheet): incoming bank money the classifier couldn't
// confidently call income. Each one stays OUT of your income (as neutral "Received")
// until you tap what it is. Your tap is remembered for that person, so the same friend
// or employer is handled automatically next time.
struct ReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortIndex) private var accounts: [Account]
    @Query private var cats: [TxCategory]
    @Query private var txs: [Txn]
    @State private var owner = LearningStore.shared.ownerName
    @State private var editTx: Txn?

    var body: some View {
        let rows = Ledger.build(accounts: accounts, txs: txs).reviewRows.sorted { $0.date > $1.date }
        return NavigationStack {
            List {
                Section {
                    TextField("e.g. Meet Patel", text: $owner)
                        .textInputAutocapitalization(.words)
                        .onChange(of: owner) { _, v in LearningStore.shared.setOwnerName(v) }
                } header: { Text("Your name") } footer: {
                    Text("Money you send between your own accounts (matching this name) won't be counted as income.")
                }
                if rows.isEmpty {
                    ContentUnavailableView("Nothing to review", systemImage: "checkmark.circle",
                        description: Text("Every incoming payment is sorted. New ones the app isn't sure about show up here for a quick tap."))
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        Text("**\(rows.count)** incoming payment\(rows.count == 1 ? "" : "s") not counted as income yet. Pick what each one is and the app will remember.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(rows) { r in Section { card(r) } }
                }
            }
            .navigationTitle("Review income")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $editTx) { TransactionForm(existing: $0) }
        }
    }

    private func card(_ r: Row) -> some View {
        let suggested = r.suggest.first.map { $0 == "salary" || $0 == "freelance" ? "income" : $0 }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.merchant.isEmpty ? "Bank transaction" : r.merchant).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text("\(Fmt.prettyDay(r.date)) · \(accounts.first { $0.id == r.accountId }?.name ?? "?")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("+" + Fmt.money(r.amount)).font(.subheadline.weight(.bold)).monospacedDigit().foregroundStyle(.teal)
            }
            if !r.notes.isEmpty { Text(r.notes).font(.caption).italic().foregroundStyle(.tertiary).lineLimit(1) }
            if !r.reason.isEmpty {
                Text(r.reason + (r.confidence.map { " · \(Int(($0 * 100).rounded()))% sure" } ?? ""))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                let ch = Classifier.reviewChoices
                GridRow { choice(r, ch[0], suggested); choice(r, ch[1], suggested) }
                GridRow { choice(r, ch[2], suggested); choice(r, ch[3], suggested) }
                GridRow { choice(r, ch[4], suggested).gridCellColumns(2) }
            }
            Button("Edit details instead →") { editTx = txs.first { $0.id == r.id } }
                .font(.caption.weight(.semibold)).buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func choice(_ r: Row, _ ch: (key: String, label: String, sub: String, cls: String), _ suggested: String?) -> some View {
        let on = ch.key == suggested
        return Button { pick(r, ch) } label: {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(ch.label).font(.footnote.weight(.bold))
                    if on { Text("SUGGESTED").font(.system(size: 8, weight: .bold)).opacity(0.8) }
                }
                Text(ch.sub).font(.caption2).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(on ? Color.teal.opacity(0.14) : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? Color.teal : .clear, lineWidth: 1.5))
            .foregroundStyle(on ? Color.teal : Color.primary)
        }
        .buttonStyle(.borderless)
    }

    /// web classifyReview: a per-row decision + one learning tap for that payee.
    private func pick(_ r: Row, _ ch: (key: String, label: String, sub: String, cls: String)) {
        let cls = Classifier.labelCls[ch.cls]!
        var category = cls.category
        if ch.key == "income" {
            let guessed = r.categoryId != "other" ? r.categoryId : r.rawCategoryId
            if ["salary", "freelance"].contains(guessed) { category = guessed }
        }
        withAnimation {
            LearningStore.shared.setDecision(Decision(type: cls.type, category: category), for: r.id)
        }
        let key = Classifier.counterpartyKey(r.merchant)
        let label = ch.key == "income" ? (category == "freelance" ? "freelance" : "salary") : ch.key
        LearningStore.shared.updatePayeeStats { Classifier.bumpPayeeStats($0, key: key, label: label) }
        Haptic.success()
    }
}
