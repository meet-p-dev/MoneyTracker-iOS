import Foundation

// PDF statements (Advanzia and banks that only give a PDF). The app turns the PDF into text
// with PDFKit; this reads that text. A transaction is a line that starts with a date (or two)
// and ends with an amount. Built without a real Advanzia file yet: tune it with one.
//
// Signs: on a bank statement "-" is money out. On a credit-card statement it's the other way
// round: a plain amount is a charge and "-" is a payment or refund into the card.
enum PDFStatement {
    private static let amt = #"[+-]?\d{1,3}(?:[.']\d{3})*,\d{2}|[+-]?\d+,\d{2}|[+-]?\d{1,3}(?:,\d{3})*\.\d{2}"#
    private static let reLine = try! NSRegularExpression(
        pattern: #"^(\d{1,2}\.\d{1,2}\.(?:\d{2,4})?)\s+(?:(\d{1,2}\.\d{1,2}\.(?:\d{2,4})?)\s+)?(.+)$"#)
    private static let reAmt = try! NSRegularExpression(pattern: "(" + amt + #")\s*(-|\+|S|H|CR|DR)?(?=\s|$)"#)
    private static let reTail = try! NSRegularExpression(pattern: "(" + amt + #")\s*(-|\+|S|H|CR|DR)?\s*(EUR|€)?\s*$"#)
    private static let reFullDate = try! NSRegularExpression(pattern: #"\b(\d{1,2})\.(\d{1,2})\.(\d{4})\b"#)
    private static let reIBAN = try! NSRegularExpression(pattern: #"\b([A-Z]{2}\d{2}(?: ?[A-Z0-9]{4}){3,7}(?: ?[A-Z0-9]{1,4})?)\b"#)
    private static let reCard = try! NSRegularExpression(pattern: #"(?i)(kreditkarte|credit card|mastercard|visa|advanzia|karteninhaber|kartenabrechnung|gebührenfrei)"#)
    private static let reCredit = try! NSRegularExpression(pattern: #"(?i)\b(zahlung|gutschrift|erstattung|rückzahlung|rueckzahlung|payment|refund|einzahlung|überweisung eingang|zahlungseingang)"#)
    private static let reSkip = try! NSRegularExpression(pattern: #"(?i)\b(saldo|übertrag|uebertrag|kontostand|summe|zwischensumme|total|seite|page)\b"#)
    private static let reClosing = try! NSRegularExpression(pattern: #"(?i)(neuer saldo|neuer kontostand|endsaldo|saldo neu|new balance|closing balance|kontostand am)"#)
    private static let reCur = try! NSRegularExpression(pattern: #"\b(USD|GBP|CHF|PLN|CZK|HUF|SEK|NOK|DKK|TRY|JPY|INR|AUD|CAD)\b"#)

    private static func has(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }
    private static func matches(_ re: NSRegularExpression, _ s: String) -> [NSTextCheckingResult] {
        re.matches(in: s, range: NSRange(s.startIndex..., in: s))
    }
    private static func sub(_ s: String, _ r: NSRange) -> String { Range(r, in: s).map { String(s[$0]) } ?? "" }

    static func parse(_ text: String) -> Statement {
        var st = Statement(format: "PDF")
        let lines = text.components(separatedBy: .newlines).map { $0.trimmed }.filter { !$0.isEmpty }
        let isCard = has(reCard, text)
        if text.lowercased().contains("advanzia") { st.bank = "Advanzia" }
        if let m = matches(reIBAN, text).first { st.iban = sub(text, m.range(at: 1)).replacingOccurrences(of: " ", with: "") }
        // The statement's year, for dates printed as "03.09.".
        let full = matches(reFullDate, text).compactMap { m -> (Int, Int)? in
            guard let mo = Int(sub(text, m.range(at: 2))), let y = Int(sub(text, m.range(at: 3))), (1...12).contains(mo) else { return nil }
            return (y, mo)
        }
        let latest = full.max { ($0.0, $0.1) < ($1.0, $1.1) } ?? (Calendar.current.component(.year, from: Date()), 12)
        func day(_ s: String) -> String? {
            let parts = s.split(separator: ".").map(String.init)
            guard parts.count >= 2, let d = Int(parts[0]), let mo = Int(parts[1]), (1...12).contains(mo), (1...31).contains(d) else { return nil }
            var y = parts.count > 2 ? Int(parts[2]) ?? latest.0 : latest.0
            if y < 100 { y += 2000 }
            if parts.count < 3 || parts[2].isEmpty, mo > latest.1 + 1 { y -= 1 }   // December rows in a January statement
            return CardMath.ymd(y, mo, d)
        }
        func signed(_ token: String, _ mark: String, _ desc: String) -> Int? {
            guard let c = StatementParser.cents(token) else { return nil }
            let explicitMinus = token.hasPrefix("-") || mark == "-" || mark == "S" || mark == "DR"
            let explicitPlus = token.hasPrefix("+") || mark == "+" || mark == "H" || mark == "CR"
            let v = abs(c)
            if isCard {
                if explicitMinus { return v }                 // payment or refund into the card
                if explicitPlus { return -v }
                return has(reCredit, desc) ? v : -v
            }
            if explicitMinus { return -v }
            if explicitPlus { return v }
            return has(reCredit, desc) ? v : -v
        }
        var lastDay: String?
        for l in lines {
            if has(reClosing, l), let t = matches(reTail, l).last {
                if let c = StatementParser.cents(sub(l, t.range(at: 1))) {
                    let owed = isCard ? -abs(c) : c
                    let d = matches(reFullDate, l).last.flatMap { day(sub(l, $0.range)) } ?? lastDay
                    if let d { st.closing = (d, owed) }
                }
                continue
            }
            guard let m = reLine.firstMatch(in: l, range: NSRange(l.startIndex..., in: l)),
                  let d1 = day(sub(l, m.range(at: 1))) else { continue }
            let d2 = m.range(at: 2).location != NSNotFound ? day(sub(l, m.range(at: 2))) : nil
            let rest = sub(l, m.range(at: 3))
            guard !has(reSkip, rest), reTail.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)) != nil else { continue }
            let amts = matches(reAmt, rest)
            guard let first = amts.first else { continue }
            let desc = String(rest[..<(Range(first.range, in: rest)?.lowerBound ?? rest.endIndex)]).trimmed
            guard !desc.isEmpty else { continue }
            // Two amounts: "12,00 USD 11,05" is foreign money and its euro value; otherwise amount then balance.
            var pick = first, balance: NSTextCheckingResult?
            if amts.count >= 2 {
                if has(reCur, rest) { pick = amts.last! } else { balance = amts.last }
            }
            let token = sub(rest, pick.range(at: 1))
            let mark = pick.range(at: 2).location != NSNotFound ? sub(rest, pick.range(at: 2)) : ""
            guard let cents = signed(token, mark, desc) else { continue }
            var r = StatementRow(day: d2 ?? d1, cents: cents, payee: desc, purpose: amts.count >= 2 && has(reCur, rest) ? rest : "")
            if let b = balance { r.balanceCents = StatementParser.cents(sub(rest, b.range(at: 1))) }
            st.rows.append(r)
            lastDay = max(lastDay ?? "", r.day)
        }
        if st.closing == nil, let b = st.rows.last(where: { $0.balanceCents != nil }) { st.closing = (b.day, b.balanceCents!) }
        return st
    }
}
