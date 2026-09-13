import Foundation

// The numbers behind Home, Insights and the card screen — ports of the web app's derived
// data in components/App.jsx (balSeries, catD, creditSplit, calData, chartD).
extension Ledger {
    /// Total balance per day for the last `days` days, using exactly the same per-account
    /// rules as `balance(of:)` (starting-balance dates, transfers per side), so the line
    /// always ends on your real total. Days before the window fold into the start value.
    func balanceSeries(days: Int = 60, today: String = Fmt.today()) -> [(date: String, value: Double)] {
        var deltas: [String: Double] = [:]
        for t in rows where t.amount != 0 && !t.date.isEmpty {
            if let from = byId[t.accountId], CardMath.countsFor(from, t.date) {
                if t.isIn { deltas[t.date, default: 0] += t.amount }
                else if t.isOut || t.type == "transfer" { deltas[t.date, default: 0] -= t.amount }
            }
            if t.type == "transfer", let to = byId[t.toAccountId], CardMath.countsFor(to, t.date) {
                deltas[t.date, default: 0] += t.amount
            }
        }
        let dates = deltas.keys.sorted()
        let start = CardMath.addDays(today, -(days - 1))
        var run = accounts.reduce(0) { $0 + $1.ib }
        var di = 0
        while di < dates.count && dates[di] < start { run += deltas[dates[di]] ?? 0; di += 1 }
        var out: [(date: String, value: Double)] = []
        for i in 0..<days {
            let k = CardMath.addDays(start, i)
            while di < dates.count && dates[di] <= k { run += deltas[dates[di]] ?? 0; di += 1 }
            out.append((k, (run * 100).rounded() / 100))
        }
        return out
    }

    struct CatTotal: Identifiable {
        let id: String
        var total: Double
        var merchants: [String: Double]
        var counts: [String: Int]
    }
    private func expenses(_ month: String?) -> [Row] {
        rows.filter { $0.type == "expense" && (month == nil || $0.date.hasPrefix(month!)) }
    }
    /// Your share of spending per category, biggest first (nil month = all time).
    func categoryTotals(month: String?) -> [CatTotal] {
        var m: [String: CatTotal] = [:]
        for t in expenses(month) {
            var c = m[t.categoryId] ?? CatTotal(id: t.categoryId, total: 0, merchants: [:], counts: [:])
            let name = t.merchant.isEmpty ? "Unknown" : t.merchant
            c.total += t.personal; c.merchants[name, default: 0] += t.personal; c.counts[name, default: 0] += 1
            m[t.categoryId] = c
        }
        return m.values.sorted { $0.total > $1.total }
    }
    func spendTotal(month: String?) -> Double { expenses(month).reduce(0) { $0 + $1.personal } }
    /// Months that have spending, newest first ("yyyy-MM").
    var spendMonths: [String] { Array(Set(rows.filter { $0.type == "expense" }.map { String($0.date.prefix(7)) })).sorted(by: >) }

    /// How much of a month's spending went on a card (money you still owe) vs cash.
    func creditSplit(month: String) -> (cash: Double, credit: Double) {
        let cardIds = Set(cards.map(\.id))
        var cash = 0.0, credit = 0.0
        for t in expenses(month) { if cardIds.contains(t.accountId) { credit += t.personal } else { cash += t.personal } }
        return (cash, credit)
    }
    /// Spending per day of a month — the calendar heatmap.
    func dailySpend(month: String) -> [String: Double] {
        var m: [String: Double] = [:]
        for t in expenses(month) { m[t.date, default: 0] += t.personal }
        return m
    }
    /// Income vs spending for the last `months` months, oldest first.
    func monthChart(months: Int = 6, today: String = Fmt.today()) -> [(key: String, income: Double, spent: Double)] {
        let (y, m, _) = CardMath.parts(today)
        return (0..<months).reversed().map { back in
            var yy = y, mm = m - back
            while mm < 1 { mm += 12; yy -= 1 }
            let key = String(format: "%04d-%02d", yy, mm)
            let s = monthStats(key)
            return (key, s.income, s.spent)
        }
    }
    func biggestExpense(month: String) -> Row? { expenses(month).max { $0.personal < $1.personal } }
}
