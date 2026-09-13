import SwiftUI
import TipKit

// Two one-time pointers: the + button and the balance. Settings → "Show tips again" resets them.
nonisolated struct AddTip: Tip {
    var title: Text { Text("Add a transaction") }
    var message: Text? { Text("Log an expense, income or transfer from any screen.") }
}
nonisolated struct BalanceTip: Tip {
    var title: Text { Text("Total balance") }
    var message: Text? { Text("Your accounts minus what your cards owe. Tap to see each account.") }
}

enum MTTips {
    static func configure() {
        if UserDefaults.standard.bool(forKey: "mt-reset-tips") {
            try? Tips.resetDatastore()
            UserDefaults.standard.set(false, forKey: "mt-reset-tips")
        }
        try? Tips.configure([.displayFrequency(.immediate)])
    }
}
