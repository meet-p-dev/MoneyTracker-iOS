import Foundation
import SwiftData

// String ids + "yyyy-MM-dd" date strings everywhere — identical to the web app's data, so
// backup import/export is lossless in both directions. Properties added since the first
// version carry default values, so existing installs migrate automatically.

@Model
final class Account {
    @Attribute(.unique) var id: String
    var name: String
    var colorHex: String
    var initialBalance: Double          // web `ib` — cards are negative when you owe
    var sortIndex: Int
    // web V9.4–V11.8: credit cards, starting-balance date, bank-synced flag
    var kind: String = "cash"           // "cash" | "credit"
    var creditLimit: Double = 0
    var statementDay: Int = 1
    var dueDay: Int = 1
    var apr: Double = 0
    var payFromId: String = ""
    var autopay: Bool = false
    var billPayee: String = ""
    var ibDate: String = ""             // "" = count every transaction
    var lastAutopay: String = ""
    var isBank: Bool = false

    init(id: String = UUID().uuidString, name: String, colorHex: String, initialBalance: Double = 0, sortIndex: Int = 0) {
        self.id = id; self.name = name; self.colorHex = colorHex
        self.initialBalance = initialBalance; self.sortIndex = sortIndex
    }

    var isCredit: Bool { kind == "credit" }
    var isSynced: Bool { isBank || id.hasPrefix("sb-") }
    var snap: AccSnap {
        AccSnap(id: id, name: name, colorHex: colorHex, ib: initialBalance, kind: kind, creditLimit: creditLimit,
                statementDay: statementDay, dueDay: dueDay, apr: apr, payFromId: payFromId, autopay: autopay,
                billPayee: billPayee, ibDate: ibDate, isBank: isSynced)
    }
    func apply(_ s: AccSnap) {
        name = s.name; colorHex = s.colorHex; initialBalance = s.ib; kind = s.kind
        creditLimit = s.creditLimit; statementDay = s.statementDay; dueDay = s.dueDay; apr = s.apr
        payFromId = s.payFromId; autopay = s.autopay; billPayee = s.billPayee; ibDate = s.ibDate; isBank = s.isBank
    }
}

@Model
final class TxCategory {
    @Attribute(.unique) var id: String
    var label: String
    var icon: String                    // emoji — custom categories, and fallback
    var colorHex: String
    var sym: String = ""                // web symbol key (built-in categories)

    init(id: String = UUID().uuidString, label: String, icon: String, colorHex: String, sym: String = "") {
        self.id = id; self.label = label; self.icon = icon; self.colorHex = colorHex; self.sym = sym
    }
}

@Model
final class Txn {
    @Attribute(.unique) var id: String
    var type: String          // income | credit (Received) | expense | debit (Sent out) | transfer
    var amount: Double
    var merchant: String
    var categoryId: String
    var accountId: String
    var toAccountId: String   // transfers only
    var notes: String
    var date: String          // "yyyy-MM-dd"
    // Legacy WG-split fields: converted to "My share" on first launch, kept for old stores.
    var isSplit: Bool
    var splitPeople: Int
    var splitSettled: Bool
    var isBank: Bool = false  // synced from the bank (web `_bank`)

    init(id: String = UUID().uuidString, type: String, amount: Double, merchant: String,
         categoryId: String, accountId: String, toAccountId: String = "", notes: String = "",
         date: String, isSplit: Bool = false, splitPeople: Int = 1, splitSettled: Bool = false) {
        self.id = id; self.type = type; self.amount = amount; self.merchant = merchant
        self.categoryId = categoryId; self.accountId = accountId; self.toAccountId = toAccountId
        self.notes = notes; self.date = date; self.isSplit = isSplit
        self.splitPeople = splitPeople; self.splitSettled = splitSettled
    }

    var isSynced: Bool { isBank || id.hasPrefix("sb-") }
    var row: Row {
        Row(id: id, type: type, rawType: type, amount: amount, merchant: merchant, categoryId: categoryId,
            rawCategoryId: categoryId, accountId: accountId, toAccountId: toAccountId, notes: notes,
            date: date, isBank: isSynced)
    }
}

@Model
final class Goal {
    @Attribute(.unique) var id: String
    var name: String
    var targetAmount: Double
    var savedAmount: Double
    var icon: String
    var colorHex: String
    var sym: String = ""                // web symbol key; emoji goals are upgraded on display

    init(id: String = UUID().uuidString, name: String, targetAmount: Double, savedAmount: Double = 0,
         icon: String = "🎯", colorHex: String = "#007aff", sym: String = "goal") {
        self.id = id; self.name = name; self.targetAmount = targetAmount
        self.savedAmount = savedAmount; self.icon = icon; self.colorHex = colorHex; self.sym = sym
    }
}

// Retired (web V9.5): bank sync imports the real recurring payments. Kept only so existing
// stores open; its rows are deleted by the one-time migration.
@Model
final class RecurringTxn {
    @Attribute(.unique) var id: String
    var merchant: String
    var amount: Double
    var type: String
    var categoryId: String
    var accountId: String
    var dayOfMonth: Int
    var active: Bool
    var lastTriggered: String
    var notes: String

    init(id: String = UUID().uuidString, merchant: String, amount: Double, type: String = "expense",
         categoryId: String, accountId: String, dayOfMonth: Int, active: Bool = true,
         lastTriggered: String = "", notes: String = "") {
        self.id = id; self.merchant = merchant; self.amount = amount; self.type = type
        self.categoryId = categoryId; self.accountId = accountId; self.dayOfMonth = dayOfMonth
        self.active = active; self.lastTriggered = lastTriggered; self.notes = notes
    }
}

@Model
final class Debt {
    @Attribute(.unique) var id: String
    var personName: String
    var totalAmount: Double
    var paidBack: Double
    var settled: Bool
    var date: String
    var details: String
    var colorHex: String
    var receivedInAccount: String

    init(id: String = UUID().uuidString, personName: String, totalAmount: Double, paidBack: Double = 0,
         settled: Bool = false, date: String, details: String = "", colorHex: String = "#e11d48",
         receivedInAccount: String = "") {
        self.id = id; self.personName = personName; self.totalAmount = totalAmount
        self.paidBack = paidBack; self.settled = settled; self.date = date
        self.details = details; self.colorHex = colorHex; self.receivedInAccount = receivedInAccount
    }
}

@Model
final class Budget {
    @Attribute(.unique) var categoryId: String
    var limit: Double

    init(categoryId: String, limit: Double) {
        self.categoryId = categoryId; self.limit = limit
    }
}

extension Ledger {
    /// The effective ledger for the current data + your learning (decisions, My share).
    static func build(accounts: [Account], txs: [Txn], learning: LearningStore = .shared) -> Ledger {
        Ledger(accounts: accounts.map(\.snap), raw: txs.map(\.row),
               decisions: learning.txDecisions, shares: learning.shareOverrides,
               payeeStats: learning.payeeStats, ownerName: learning.ownerName)
    }
}
