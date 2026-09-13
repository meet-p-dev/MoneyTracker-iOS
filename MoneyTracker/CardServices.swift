import Foundation
import SwiftData

// Credit-card actions shared by the card screen and the app shell (web App.jsx payBill +
// the auto-pay effect).
struct TxPrefill {
    var type = "transfer"
    var amount: Double
    var merchant: String
    var accountId: String
    var toAccountId: String
    var notes: String
}

enum CardAutopay {
    /// On/after the due date, log the statement payment once per cycle — but only from an
    /// account you manage by hand. From a bank-synced account the real payment arrives with
    /// bank sync (logging it too would count it twice).
    static func run(ctx: ModelContext) {
        guard let accs = try? ctx.fetch(FetchDescriptor<Account>()),
              let txs = try? ctx.fetch(FetchDescriptor<Txn>()) else { return }
        let today = Fmt.today()
        let L = Ledger.build(accounts: accs, txs: txs)
        var fired = false
        for c in accs where c.isCredit && c.autopay && !c.payFromId.isEmpty {
            guard let from = accs.first(where: { $0.id == c.payFromId }), !from.isSynced else { continue }
            let s = L.cardStats(c.snap, ref: today)
            guard s.amountDue > 0, s.daysToDue <= 0, c.lastAutopay != s.close else { continue }
            ctx.insert(Txn(type: "transfer", amount: (s.amountDue * 100).rounded() / 100, merchant: "\(c.name) bill",
                           categoryId: "transfer", accountId: c.payFromId, toAccountId: c.id, notes: "Auto-paid", date: today))
            c.lastAutopay = s.close
            fired = true
        }
        if fired { try? ctx.save() }
    }
}

enum PayBill {
    enum Outcome { case prefill(TxPrefill), payInBank(String) }
    /// What "Pay Bill" should do: open a prefilled transfer from a hand-managed account, or
    /// — when the money comes from a bank-synced account — tell you to pay in your bank app.
    static func outcome(card: Account, accounts: [Account], stats: CardMath.Stats) -> Outcome {
        if let pf = accounts.first(where: { $0.id == card.payFromId }), pf.isSynced {
            return .payInBank("Pay it from \(pf.name) in your bank app — it appears here after the next sync.")
        }
        let from = card.payFromId.isEmpty ? (accounts.first { !$0.isCredit && !$0.isSynced && $0.id != card.id }?.id ?? "") : card.payFromId
        if from.isEmpty && accounts.contains(where: \.isSynced) {
            return .payInBank("Pay it in your bank app — it appears here after the next sync.")
        }
        return .prefill(TxPrefill(amount: (stats.amountDue * 100).rounded() / 100, merchant: "\(card.name) bill",
                                  accountId: from, toAccountId: card.id, notes: "Statement of \(stats.close)"))
    }
}
