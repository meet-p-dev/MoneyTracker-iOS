import SwiftUI
import TipKit

// Apple's own tip bubbles, pointing at the real buttons the first time you see them.
// Each shows once; Settings → "Show tips again" brings them all back.
nonisolated struct AddTip: Tip {
    var title: Text { Text("Add anything here") }
    var message: Text? { Text("Spending, income, money you got back, or a transfer between your accounts — from any screen.") }
    var image: Image? { Image(systemName: "plus.circle.fill") }
}
nonisolated struct BalanceTip: Tip {
    var title: Text { Text("This is your total") }
    var message: Text? { Text("What's in your accounts minus what your cards owe. Tap it to see each account, or ⓘ to see the maths.") }
    var image: Image? { Image(systemName: "sum") }
}
nonisolated struct ReceivedTip: Tip {
    var title: Text { Text("Income or Received?") }
    var message: Text? { Text("Income is money you earned. Received is money coming back — refunds, a friend paying you back — so it doesn't inflate your income.") }
    var image: Image? { Image(systemName: "arrow.triangle.2.circlepath") }
}
nonisolated struct InsightsTip: Tip {
    var title: Text { Text("Every number opens up") }
    var message: Text? { Text("Tap a slice, a category, a budget, a bar or a day to see the transactions behind it.") }
    var image: Image? { Image(systemName: "hand.tap") }
}
nonisolated struct CalendarTip: Tip {
    var title: Text { Text("Tap any day") }
    var message: Text? { Text("See exactly what you spent — and received — that day.") }
    var image: Image? { Image(systemName: "calendar") }
}
nonisolated struct CardTip: Tip {
    var title: Text { Text("Your card, explained") }
    var message: Text? { Text("Tap the card for the bill, when it's due and how to pay it.") }
    var image: Image? { Image(systemName: "creditcard") }
}

enum MTTips {
    /// Called once at launch. "Show tips again" in Settings sets a flag that resets them here.
    static func configure() {
        if UserDefaults.standard.bool(forKey: "mt-reset-tips") {
            try? Tips.resetDatastore()
            UserDefaults.standard.set(false, forKey: "mt-reset-tips")
        }
        try? Tips.configure([.displayFrequency(.immediate)])
    }
}
