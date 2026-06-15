import SwiftUI
import UIKit

enum Fmt {
    static let eur: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "de_DE")
        f.currencyCode = "EUR"
        return f
    }()

    static func money(_ v: Double) -> String {
        eur.string(from: NSNumber(value: v)) ?? "\(v) €"
    }

    static let day: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    static func today() -> String { day.string(from: Date()) }
    static func monthKey(_ date: Date = Date()) -> String { String(day.string(from: date).prefix(7)) }

    static func parse(_ s: String) -> Date { day.date(from: s) ?? Date() }

    static func prettyDay(_ s: String) -> String {
        let d = parse(s)
        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(.dateTime.day().month(.wide))
    }
}

extension Color {
    init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}

enum Haptic {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

// Balance & stats math shared by views — mirrors the PWA logic exactly.
enum Money {
    static func balance(of account: Account, txs: [Txn]) -> Double {
        var bal = account.initialBalance
        for t in txs {
            switch t.type {
            case "income"  where t.accountId == account.id: bal += t.amount
            case "expense" where t.accountId == account.id: bal -= t.amount
            case "transfer":
                if t.accountId == account.id { bal -= t.amount }
                if t.toAccountId == account.id { bal += t.amount }
            default: break
            }
        }
        return bal
    }

    static func monthStats(txs: [Txn], monthKey: String) -> (income: Double, spent: Double) {
        let m = txs.filter { $0.date.hasPrefix(monthKey) }
        let inc = m.filter { $0.type == "income" }.reduce(0) { $0 + $1.amount }
        let spt = m.filter { $0.type == "expense" }.reduce(0) { $0 + $1.personalAmount }
        return (inc, spt)
    }

    // median-of-daily-totals projection (same fix as PWA V8.1)
    static func projectedSpend(txs: [Txn], monthKey: String) -> Double {
        let cal = Calendar.current
        let now = Date()
        let dayOfMonth = cal.component(.day, from: now)
        let daysInMonth = cal.range(of: .day, in: .month, for: now)?.count ?? 30
        let exp = txs.filter { $0.type == "expense" && $0.date.hasPrefix(monthKey) }
        let spent = exp.reduce(0) { $0 + $1.personalAmount }
        var byDay: [String: Double] = [:]
        for t in exp { byDay[t.date, default: 0] += t.personalAmount }
        let totals = byDay.values.sorted()
        let median = totals.isEmpty ? 0 : totals[totals.count / 2]
        return spent + median * Double(daysInMonth - dayOfMonth)
    }
}
