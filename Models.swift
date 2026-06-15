import Foundation
import SwiftData

// String ids + "yyyy-MM-dd" date strings everywhere — identical to the PWA data,
// so backup import/export is lossless in both directions.

@Model
final class Account {
    @Attribute(.unique) var id: String
    var name: String
    var colorHex: String
    var initialBalance: Double
    var sortIndex: Int

    init(id: String = UUID().uuidString, name: String, colorHex: String, initialBalance: Double = 0, sortIndex: Int = 0) {
        self.id = id; self.name = name; self.colorHex = colorHex
        self.initialBalance = initialBalance; self.sortIndex = sortIndex
    }
}

@Model
final class TxCategory {
    @Attribute(.unique) var id: String
    var label: String
    var icon: String
    var colorHex: String

    init(id: String = UUID().uuidString, label: String, icon: String, colorHex: String) {
        self.id = id; self.label = label; self.icon = icon; self.colorHex = colorHex
    }
}

@Model
final class Txn {
    @Attribute(.unique) var id: String
    var type: String          // "expense" | "income" | "transfer"
    var amount: Double
    var merchant: String
    var categoryId: String
    var accountId: String
    var toAccountId: String   // transfers only
    var notes: String
    var date: String          // "yyyy-MM-dd"
    var isSplit: Bool
    var splitPeople: Int
    var splitSettled: Bool

    init(id: String = UUID().uuidString, type: String, amount: Double, merchant: String,
         categoryId: String, accountId: String, toAccountId: String = "", notes: String = "",
         date: String, isSplit: Bool = false, splitPeople: Int = 1, splitSettled: Bool = false) {
        self.id = id; self.type = type; self.amount = amount; self.merchant = merchant
        self.categoryId = categoryId; self.accountId = accountId; self.toAccountId = toAccountId
        self.notes = notes; self.date = date; self.isSplit = isSplit
        self.splitPeople = splitPeople; self.splitSettled = splitSettled
    }

    // your share of a split expense — mirrors personalAmt() in the PWA
    var personalAmount: Double {
        isSplit && splitPeople > 1 ? amount / Double(splitPeople) : amount
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

    init(id: String = UUID().uuidString, name: String, targetAmount: Double, savedAmount: Double = 0,
         icon: String = "🎯", colorHex: String = "#007aff") {
        self.id = id; self.name = name; self.targetAmount = targetAmount
        self.savedAmount = savedAmount; self.icon = icon; self.colorHex = colorHex
    }
}

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
    var lastTriggered: String  // "yyyy-MM-dd" or ""
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
