import Foundation

// Bank notifications → a payment. iOS 27's Shortcuts "Notification" automation hands MoneyTrack
// the title, subtitle and body of a banking app's push (Sparkasse Kartenwecker/Umsatzwecker,
// Revolut, the Wallet app). Banks don't document their wording, so this reads it generally:
// the amount with its currency, the direction from the words around it, and the shop or person.
// A notification without an amount (security codes, "statement ready", Sparkasse Privatmodus)
// is not a payment. Plain Swift, tested with swiftc.
struct ParsedNote: Equatable {
    var cents: Int
    var cur: String?          // ISO code; nil = not stated
    var dir: String           // "out" | "in"
    var merchant: String
}

enum NoteParser {
    private static let num = #"\d{1,3}(?:[.,' ]\d{3})*(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?"#
    // "€12.50", "-12,50 €", "12,50 EUR", "EUR 12,50", "US$3.20", "£4", "CHF 9.90"
    private static let reMoney = try! NSRegularExpression(pattern:
        #"([+\-−]?)\s*(€|EUR|US\$|\$|£|GBP|CHF|USD|PLN|CZK|HUF|SEK|NOK|DKK)\s?("# + num + #")|([+\-−]?)\s*("# + num + #")\s?(€|EUR|USD|GBP|CHF|PLN|CZK|HUF|SEK|NOK|DKK)"#)
    private static let reIgnore = try! NSRegularExpression(pattern:
        #"(?i)\b(kontostand|saldo|balance|limit|tan|code|passwort|password|anmeldung|login|freigabe|statement is ready|kontoauszug)\b"#)
    private static let reIn = try! NSRegularExpression(pattern:
        #"(?i)\b(gutschrift|gutgeschrieben|eingang|zahlungseingang|erhalten|received|credited|refund|refunded|erstattung|erstattet|rückzahlung|aufgeladen|top-?up|added to|gehalt|salary)\b"#)
    private static let reOut = try! NSRegularExpression(pattern:
        #"(?i)\b(lastschrift|abbuchung|abgebucht|belastung|belastet|kartenzahlung|kartenumsatz|bezahlt|paid|spent|payment|zahlung|debited|sent|gesendet|überwiesen|ueberwiesen|abhebung|withdrawal|withdrew|purchase|einkauf)\b"#)
    private static let reParty = try! NSRegularExpression(pattern:
        #"(?i)\b(?:bei|at|an|to|von|from|für|for|in)\s+([^\n|.,;:!?]{2,40})"#)

    private static func has(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }
    private static func sub(_ s: String, _ r: NSRange) -> String { Range(r, in: s).map { String(s[$0]) } ?? "" }

    static func currency(_ token: String) -> String? {
        switch token.uppercased() {
        case "€", "EUR": return "EUR"
        case "£", "GBP": return "GBP"
        case "US$", "USD": return "USD"
        case "$": return nil
        default: return token.count == 3 ? token.uppercased() : nil
        }
    }

    static func parse(app: String, title: String, subtitle: String, body: String) -> ParsedNote? {
        let parts = [title, subtitle, body].map { $0.trimmed }.filter { !$0.isEmpty }
        let text = parts.joined(separator: " | ")
        guard !text.isEmpty else { return nil }
        // The first amount that carries a currency.
        guard let m = reMoney.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        let before = String(text[..<(Range(m.range, in: text)?.lowerBound ?? text.startIndex)])
        let firstForm = m.range(at: 3).location != NSNotFound
        let sign = sub(text, m.range(at: firstForm ? 1 : 4))
        let numText = sub(text, m.range(at: firstForm ? 3 : 5)).replacingOccurrences(of: " ", with: "")
        let curText = sub(text, m.range(at: firstForm ? 2 : 6))
        guard let v = Fmt.amount(numText), v > 0 else { return nil }
        // A balance or security message isn't a payment, unless it also says what happened.
        if has(reIgnore, text) && !has(reIn, text) && !has(reOut, text) { return nil }
        if has(reIgnore, before) && !has(reOut, before) && !has(reIn, before) { return nil }

        var dir = "out"
        if sign == "+" { dir = "in" }
        else if sign == "-" || sign == "−" { dir = "out" }
        else if has(reIn, text) && !(has(reOut, text) && !has(reIn, text)) { dir = "in" }

        // Who: Wallet's own notifications put the shop in the subtitle; banks name it after
        // "bei / at / an / to / von / from"; otherwise the title without the amount.
        var merchant = ""
        if app.lowercased() == "wallet" && !subtitle.trimmed.isEmpty { merchant = subtitle.trimmed }
        if merchant.isEmpty {
            let rest = String(text[(Range(m.range, in: text)?.upperBound ?? text.endIndex)...])
            for s in [rest, text] {
                if let p = reParty.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) {
                    let name = sub(s, p.range(at: 1)).trimmed
                    if name.rangeOfCharacter(from: .letters) != nil && reMoney.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) == nil {
                        merchant = name; break
                    }
                }
            }
        }
        if merchant.isEmpty {
            merchant = (subtitle.trimmed.isEmpty ? title : subtitle).trimmed
        }
        return ParsedNote(cents: Int((v * 100).rounded()), cur: currency(curText), dir: dir, merchant: String(merchant.prefix(60)))
    }
}
