import Foundation

// Credit-card cycle math — a line-for-line port of the web app's lib/credit.js, over
// "yyyy-MM-dd" LOCAL date strings, so both apps agree to the cent. Months are 1-based here.
enum CardMath {
    private static var cal: Calendar { Calendar.current }

    static func ymd(_ y: Int, _ m: Int, _ d: Int) -> String { String(format: "%04d-%02d-%02d", y, m, d) }
    static func parts(_ s: String) -> (y: Int, m: Int, d: Int) {
        let p = s.split(separator: "-").compactMap { Int($0) }
        return p.count == 3 ? (p[0], p[1], p[2]) : (1970, 1, 1)
    }
    static func date(_ s: String) -> Date {
        let p = parts(s)
        return cal.date(from: DateComponents(year: p.y, month: p.m, day: p.d)) ?? Date()
    }
    static func daysIn(_ y: Int, _ m: Int) -> Int {
        let d = cal.date(from: DateComponents(year: y, month: m, day: 1)) ?? Date()
        return cal.range(of: .day, in: .month, for: d)?.count ?? 30
    }
    /// A statement day of 31 falls back to the 30th/28th in shorter months.
    static func clampDay(_ y: Int, _ m: Int, _ day: Int) -> Int { min(max(day, 1), daysIn(y, m)) }
    static func prevMonth(_ y: Int, _ m: Int) -> (Int, Int) { m == 1 ? (y - 1, 12) : (y, m - 1) }
    static func nextMonth(_ y: Int, _ m: Int) -> (Int, Int) { m == 12 ? (y + 1, 1) : (y, m + 1) }

    /// Whole days from a to b (negative if b is before a).
    static func daysBetween(_ a: String, _ b: String) -> Int {
        cal.dateComponents([.day], from: date(a), to: date(b)).day ?? 0
    }
    static func addDays(_ s: String, _ n: Int) -> String {
        let d = cal.date(byAdding: .day, value: n, to: date(s)) ?? date(s)
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return ymd(c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    /// The most recent statement close ON or BEFORE ref.
    static func lastStatementDate(_ stmtDay: Int, _ ref: String) -> String {
        let (y, m, d) = parts(ref)
        let thisMonth = clampDay(y, m, stmtDay)
        if d >= thisMonth { return ymd(y, m, thisMonth) }
        let (py, pm) = prevMonth(y, m)
        return ymd(py, pm, clampDay(py, pm, stmtDay))
    }
    static func prevStatementDate(_ stmtDay: Int, _ ref: String) -> String {
        let (y, m, _) = parts(lastStatementDate(stmtDay, ref))
        let (py, pm) = prevMonth(y, m)
        return ymd(py, pm, clampDay(py, pm, stmtDay))
    }
    static func nextStatementDate(_ stmtDay: Int, _ ref: String) -> String {
        let (y, m, _) = parts(lastStatementDate(stmtDay, ref))
        let (ny, nm) = nextMonth(y, m)
        return ymd(ny, nm, clampDay(ny, nm, stmtDay))
    }
    /// Due day after the close day → same month; otherwise the next month.
    static func dueDateFor(_ close: String, _ dueDay: Int) -> String {
        let (y, m, d) = parts(close)
        let same = clampDay(y, m, dueDay)
        if same > d { return ymd(y, m, same) }
        let (ny, nm) = nextMonth(y, m)
        return ymd(ny, nm, clampDay(ny, nm, dueDay))
    }

    // ── Starting-balance date (web V11.8) ── rows before it are already inside ib.
    static func countsFor(_ acc: AccSnap, _ date: String) -> Bool { acc.ibDate.isEmpty || date >= acc.ibDate }

    /// Offered (never applied silently): cards → the day after the last statement that closed
    /// before your first purchase on the card; other accounts → the first row entered on it.
    static func suggestStartDate(_ acc: AccSnap, _ rows: [Row]) -> String? {
        guard let first = rows.filter({ $0.accountId == acc.id && !$0.date.isEmpty }).map(\.date).min() else { return nil }
        if acc.isCredit && acc.statementDay > 0 {
            var close = lastStatementDate(acc.statementDay, first)
            if close >= first { close = prevStatementDate(acc.statementDay, first) }
            return addDays(close, 1)
        }
        return first
    }

    /// Signed effect of one row on the card's balance (negative = deeper in debt; full amounts).
    static func delta(_ t: Row, _ cardId: String) -> Double {
        if t.accountId == cardId {
            switch t.type {
            case "expense", "debit", "transfer": return -t.amount   // charge / money off / cash advance
            case "income", "credit": return t.amount               // refund / statement credit
            default: return 0
            }
        }
        if t.toAccountId == cardId && t.type == "transfer" { return t.amount }   // bill payment
        return 0
    }
    static func isPayment(_ t: Row, _ cardId: String) -> Bool { t.type == "transfer" && t.toAccountId == cardId }

    struct Stats {
        let limit: Double, apr: Double
        let close: String, nextClose: String, due: String
        let currentBalance: Double, statementBalance: Double, amountDue: Double
        let unbilled: Double, paidSinceStatement: Double, available: Double, util: Double
        let overLimit: Bool
        let cycleLen: Int, cycleElapsed: Int, cycleLeft: Int, projectedCycle: Double
        let daysToDue: Int, dueSoon: Bool, overdue: Bool, interestEst: Double, paidInFull: Bool
    }

    static func stats(_ card: AccSnap, _ rows: [Row], ref: String = Fmt.today()) -> Stats {
        let stmtDay = max(card.statementDay, 1), dueDay = max(card.dueDay, 1)
        let close = lastStatementDate(stmtDay, ref)
        let nextClose = nextStatementDate(stmtDay, ref)
        let due = dueDateFor(close, dueDay)
        let mine = rows.filter { ($0.accountId == card.id || $0.toAccountId == card.id) && countsFor(card, $0.date) }
        func balAsOf(_ cut: String) -> Double { mine.filter { $0.date <= cut }.reduce(card.ib) { $0 + delta($1, card.id) } }
        let currentBalance = -balAsOf(ref)
        let statementBalance = -balAsOf(close)
        let paidSince = mine.filter { $0.date > close && isPayment($0, card.id) }.reduce(0) { $0 + $1.amount }
        let amountDue = max(statementBalance - paidSince, 0)
        let unbilled = -mine.filter { $0.date > close && !isPayment($0, card.id) }.reduce(0) { $0 + delta($1, card.id) }
        let available = card.creditLimit - currentBalance
        let util = card.creditLimit > 0 ? currentBalance / card.creditLimit : 0
        let cycleLen = max(daysBetween(close, nextClose), 1)
        let cycleElapsed = min(max(daysBetween(close, ref), 0), cycleLen)
        let projected = cycleElapsed > 0 ? unbilled / Double(cycleElapsed) * Double(cycleLen) : unbilled
        let daysToDue = daysBetween(ref, due)
        let interest = card.apr > 0 && amountDue > 0 ? amountDue * (card.apr / 100 / 12) : 0
        return Stats(limit: card.creditLimit, apr: card.apr, close: close, nextClose: nextClose, due: due,
                     currentBalance: currentBalance, statementBalance: statementBalance, amountDue: amountDue,
                     unbilled: unbilled, paidSinceStatement: paidSince, available: available, util: util,
                     overLimit: card.creditLimit > 0 && currentBalance > card.creditLimit,
                     cycleLen: cycleLen, cycleElapsed: cycleElapsed, cycleLeft: max(cycleLen - cycleElapsed, 0),
                     projectedCycle: projected, daysToDue: daysToDue,
                     dueSoon: amountDue > 0 && daysToDue <= 7, overdue: amountDue > 0 && daysToDue < 0,
                     interestEst: interest, paidInFull: amountDue <= 0 && statementBalance > 0)
    }

    /// Charges per statement period, oldest → newest (bill-history chart).
    static func billHistory(_ card: AccSnap, _ rows: [Row], n: Int = 12, ref: String = Fmt.today()) -> [(close: String, charged: Double, label: String)] {
        let stmtDay = max(card.statementDay, 1)
        let mf = DateFormatter(); mf.dateFormat = "MMM"
        var out: [(close: String, charged: Double, label: String)] = []
        var close = lastStatementDate(stmtDay, ref)
        for _ in 0..<n {
            let start = prevStatementDate(stmtDay, close)
            let charged = rows.filter { $0.accountId == card.id && $0.type == "expense" && $0.date > start && $0.date <= close }
                .reduce(0) { $0 + $1.amount }
            out.insert((close, charged, mf.string(from: date(close))), at: 0)
            close = start
        }
        return out
    }

    static func utilLabel(_ u: Double) -> String { u >= 0.9 ? "Very high" : u >= 0.7 ? "High" : u >= 0.3 ? "Moderate" : "Healthy" }

    // ── Credit-card bill detection (web V11.7) ──
    // 1 unmistakable bill phrase → yes · 2 debit-card purchase wording → no · 3 a card-only
    // issuer → yes · 4 a network name only WITH a bill word, or when it's money to yourself.
    private static func re(_ p: String) -> NSRegularExpression { JSRegex.make(p) }
    private static let reStrong = re(#"\b(kreditkarten?|kreditkarten(abrechnung|rechnung|konto|ausgleich|saldo|zahlung)|credit ?cards?|kk[- ]?abrechnung|kartenabrechnung|card ?bill|card statement|cc ?bill)\b"#)
    private static let reNot = re(#"\b(debit ?mastercard|mastercard ?debit|visa ?debit|debit ?card|debitkarte|girocard|kartenzahlung|kartenumsatz|apple ?pay|google ?pay)\b"#)
    private static let reIssuer = re(#"\b(advanzia|gebührenfrei|gebuehrenfrei|awa ?7|barclaycard|american express|hanseatic|tf ?bank)\b"#)
    private static let reNetwork = re(#"\b(master ?card|mc|visa|amex)\b"#)
    private static let reBillWord = re(#"\b(abrechnung|rechnung|bill|statement|saldo|ausgleich|tilgung|r[uü]ckzahlung|rueckzahlung|repayment|payoff)\b"#)
    private static func hit(_ r: NSRegularExpression, _ s: String) -> Bool {
        r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }
    static func looksLikeCardBill(_ text: String, ownTransfer: Bool = false) -> Bool {
        let s = text
        if s.trimmed.isEmpty { return false }
        if hit(reStrong, s) { return true }
        if hit(reNot, s) { return false }
        if hit(reIssuer, s) { return true }
        if hit(reNetwork, s) { return hit(reBillWord, s) || ownTransfer }
        return false
    }
}
