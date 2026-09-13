import SwiftUI
import SwiftData
import Charts

// One credit card, explained (web CardSheet): what you owe and how much room is left, the
// three numbers people confuse (statement / unbilled / available), when it's due and how
// to pay it, this cycle's pace, interest, bill history and what you put on it.
struct CardDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortIndex) private var accounts: [Account]
    @Query(sort: \Txn.date, order: .reverse) private var txs: [Txn]
    @Query private var cats: [TxCategory]
    let card: Account
    @State private var editCard = false
    @State private var payPrefill: TxPrefill?
    @State private var bankNote: String?

    var body: some View {
        let L = Ledger.build(accounts: accounts, txs: txs)
        let s = L.cardStats(card.snap)
        let col = Color(hex: card.colorHex)
        let payFrom = accounts.first { $0.id == card.payFromId }
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    HStack(spacing: 16) {
                        RingView(value: s.util, size: 78, stroke: 8, color: .white, track: .white.opacity(0.28)) {
                            Text("\(Int((s.util * 100).rounded()))%").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                            Text("USED").font(.system(size: 9, weight: .semibold)).kerning(0.4).foregroundStyle(.white.opacity(0.8))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("CURRENT BALANCE").font(.system(size: 11, weight: .semibold)).kerning(0.8).foregroundStyle(.white.opacity(0.75))
                            Text(Fmt.money(s.currentBalance)).font(.system(size: 29, weight: .bold)).kerning(-0.8).monospacedDigit().foregroundStyle(.white)
                            Text("\(Fmt.money(max(s.available, 0))) available of \(Fmt.money(s.limit))").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 16)
                    .background(LinearGradient(colors: [col, col.opacity(0.73)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: MT.card, style: .continuous))

                    if s.overLimit {
                        Label("Over the limit by \(Fmt.money(s.currentBalance - s.limit))", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.mtRed).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12).background(Color.mtRed.opacity(0.12), in: RoundedRectangle(cornerRadius: MT.inner))
                    }
                    HStack(spacing: 8) {
                        stat("Statement", Fmt.money(s.amountDue), s.amountDue > 0 ? .mtRed : .mtGreen)
                        stat("Unbilled", Fmt.money(s.unbilled), .primary)
                        stat("Available", Fmt.money(max(s.available, 0)), s.util >= 0.7 ? .mtAmber : .mtGreen)
                    }
                    Text("Statement is what's owed from the bill that closed \(Fmt.shortDay(s.close)). Unbilled is what you've charged since — it lands on the next bill, closing \(Fmt.shortDay(s.nextClose)).")
                        .font(.system(size: 12)).foregroundStyle(Color.mtTxt2).frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 10) {
                        Image(systemName: "clock.fill").foregroundStyle(s.overdue ? Color.mtRed : s.dueSoon ? .orange : Color.mtTxt2)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(dueText(s)).font(.system(size: 14, weight: .semibold)).foregroundStyle(s.overdue ? Color.mtRed : s.dueSoon ? .orange : Color.mtTxt2)
                            Text(payFrom?.isSynced == true ? "Paid from \(payFrom!.name) — picked up by bank sync"
                                 : card.autopay && payFrom != nil ? "Auto-pay on from \(payFrom!.name)"
                                 : payFrom != nil ? "Pays from \(payFrom!.name)" : "Utilisation: \(CardMath.utilLabel(s.util))")
                                .font(.system(size: 12)).foregroundStyle(Color.mtTxt2)
                        }
                        Spacer()
                    }
                    .padding(13).background(Color.mtCardH, in: RoundedRectangle(cornerRadius: MT.inner, style: .continuous))

                    if s.amountDue > 0 {
                        Button { pay(s) } label: { Text("Pay Bill · \(Fmt.money(s.amountDue))").font(.system(size: 16, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 6) }
                            .buttonStyle(.glassProminent)
                    }
                    if let bankNote {
                        Label(bankNote, systemImage: "building.columns").font(.system(size: 13)).foregroundStyle(Color.mtTxt2)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.mtCardH, in: RoundedRectangle(cornerRadius: MT.inner))
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        HStack { Text("This cycle").font(.system(size: 14, weight: .semibold)); Spacer(); Text("day \(s.cycleElapsed) of \(s.cycleLen)").font(.system(size: 12)).foregroundStyle(Color.mtTxt2) }
                        ProgressBar(value: Double(s.cycleElapsed) / Double(max(s.cycleLen, 1)), color: .mtAcc, height: 7)
                        Group {
                            if s.unbilled > 0 { Text("You've charged ") + Text(Fmt.money(s.unbilled)).bold() + Text(" so far. At this pace the next bill lands around ") + Text(Fmt.money(s.projectedCycle)).bold() + Text(".") }
                            else { Text("Nothing charged this cycle yet.") }
                        }
                        .font(.system(size: 13)).foregroundStyle(Color.mtTxt2)
                    }
                    .padding(13).background(Color.mtCardH, in: RoundedRectangle(cornerRadius: MT.inner, style: .continuous))

                    if s.interestEst > 0 {
                        HStack(spacing: 10) {
                            Image(systemName: "flame.fill").foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("~\(Fmt.money(s.interestEst)) interest if you don't clear it").font(.system(size: 14, weight: .semibold))
                                Text("One month of \(Fmt.editable(s.apr))% APR on \(Fmt.money(s.amountDue))").font(.system(size: 12)).foregroundStyle(Color.mtTxt2)
                            }
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: MT.inner))
                    }

                    let hist = CardMath.billHistory(card.snap, L.rows)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Charged per bill · last 12").font(.system(size: 14, weight: .semibold))
                        Chart(Array(hist.enumerated()), id: \.offset) { i, h in
                            BarMark(x: .value("Bill", "\(i)"), y: .value("Charged", h.charged)).cornerRadius(4)
                                .foregroundStyle(i == hist.count - 1 ? col : col.opacity(0.4))
                        }
                        .chartXAxis { AxisMarks { v in AxisValueLabel { if let i = v.as(String.self).flatMap(Int.init), hist.indices.contains(i) { Text(String(hist[i].label.prefix(1))) } } } }
                        .chartYAxis(.hidden).frame(height: 80)
                        (Text("Last closed bill: ") + Text(Fmt.money(hist.last?.charged ?? 0)).bold()).font(.system(size: 12)).foregroundStyle(Color.mtTxt2)
                    }
                    .padding(13).background(Color.mtCardH, in: RoundedRectangle(cornerRadius: MT.inner, style: .continuous))

                    mix(L)

                    Button { editCard = true } label: { Text("Card settings").frame(maxWidth: .infinity).padding(.vertical, 4) }.buttonStyle(.glass)
                }
                .padding(16)
            }
            .mtCanvas()
            .navigationTitle(card.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $editCard) { AccountForm(existing: card) }
            .sheet(item: Binding(get: { payPrefill.map { PrefillBox(p: $0) } }, set: { payPrefill = $0?.p })) { box in TransactionForm(existing: nil, prefill: box.p) }
        }
    }

    private struct PrefillBox: Identifiable { let id = UUID(); let p: TxPrefill }

    private func pay(_ s: CardMath.Stats) {
        switch PayBill.outcome(card: card, accounts: accounts, stats: s) {
        case .prefill(let p): payPrefill = p
        case .payInBank(let note): withAnimation(MT.spring) { bankNote = note }; Haptic.warning()
        }
    }

    private func dueText(_ s: CardMath.Stats) -> String {
        if s.amountDue <= 0 { return s.statementBalance > 0 ? "Statement cleared — nothing due" : "Nothing billed yet" }
        if s.overdue { return "Overdue by \(abs(s.daysToDue)) day\(abs(s.daysToDue) == 1 ? "" : "s")" }
        if s.daysToDue == 0 { return "Due today" }
        return "Due in \(s.daysToDue) day\(s.daysToDue == 1 ? "" : "s") · \(Fmt.shortDay(s.due))"
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased()).font(.system(size: 10.5, weight: .semibold)).kerning(0.5).foregroundStyle(Color.mtTxt3)
            Text(value).money(15).foregroundStyle(color).minimumScaleFactor(0.7).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(Color.mtCardH, in: RoundedRectangle(cornerRadius: MT.inner, style: .continuous))
    }

    @ViewBuilder private func mix(_ L: Ledger) -> some View {
        let byCat = Dictionary(grouping: L.rows.filter { $0.accountId == card.id && $0.type == "expense" }, by: \.categoryId)
            .mapValues { $0.reduce(0) { $0 + $1.amount } }.sorted { $0.value > $1.value }.prefix(5)
        if let top = byCat.first?.value, top > 0 {
            VStack(alignment: .leading, spacing: 9) {
                Text("What you put on this card").font(.system(size: 14, weight: .semibold))
                ForEach(Array(byCat), id: \.key) { k, v in
                    let cat = cats.first { $0.id == k }
                    HStack(spacing: 9) {
                        CatGlyph(cat: cat, size: 14).frame(width: 20)
                        VStack(spacing: 3) {
                            HStack { Text(cat?.label ?? k).font(.system(size: 13, weight: .medium)); Spacer(); Text(Fmt.money(v)).money(13, .semibold) }
                            ProgressBar(value: v / top, color: Color(hex: cat?.colorHex ?? "#9ca3af"), height: 5)
                        }
                    }
                }
            }
            .padding(13).background(Color.mtCardH, in: RoundedRectangle(cornerRadius: MT.inner, style: .continuous))
        }
    }
}
