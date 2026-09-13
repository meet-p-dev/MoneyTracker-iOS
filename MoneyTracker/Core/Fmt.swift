import Foundation

extension String { var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) } }

// The same 10 currency & region presets as the web app (lib/constants.js CURRENCIES).
// The chosen id is stored under "mt-currency" — the web app's key — and travels in backups.
struct Region: Identifiable, Hashable {
    let id: String, country: String, flag: String, loc: String, cur: String, sym: String
}

enum Regions {
    static let all: [Region] = [
        Region(id: "de-DE", country: "Germany", flag: "🇩🇪", loc: "de-DE", cur: "EUR", sym: "€"),
        Region(id: "fr-FR", country: "France", flag: "🇫🇷", loc: "fr-FR", cur: "EUR", sym: "€"),
        Region(id: "en-IE", country: "Ireland", flag: "🇮🇪", loc: "en-IE", cur: "EUR", sym: "€"),
        Region(id: "en-GB", country: "United Kingdom", flag: "🇬🇧", loc: "en-GB", cur: "GBP", sym: "£"),
        Region(id: "en-US", country: "United States", flag: "🇺🇸", loc: "en-US", cur: "USD", sym: "$"),
        Region(id: "en-CA", country: "Canada", flag: "🇨🇦", loc: "en-CA", cur: "CAD", sym: "$"),
        Region(id: "en-AU", country: "Australia", flag: "🇦🇺", loc: "en-AU", cur: "AUD", sym: "$"),
        Region(id: "de-CH", country: "Switzerland", flag: "🇨🇭", loc: "de-CH", cur: "CHF", sym: "CHF"),
        Region(id: "en-IN", country: "India", flag: "🇮🇳", loc: "en-IN", cur: "INR", sym: "₹"),
        Region(id: "ja-JP", country: "Japan", flag: "🇯🇵", loc: "ja-JP", cur: "JPY", sym: "¥"),
    ]
    static var currentId: String {
        get { UserDefaults.standard.string(forKey: "mt-currency") ?? "de-DE" }
        set { UserDefaults.standard.set(newValue, forKey: "mt-currency") }
    }
    static var current: Region { all.first { $0.id == currentId } ?? all[0] }
}

// Dates are "yyyy-MM-dd" strings in LOCAL time everywhere — identical to the web app, so
// backups round-trip exactly and a calendar date never shifts by a day (no UTC here).
enum Fmt {
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
    static func shortDay(_ s: String) -> String { parse(s).formatted(.dateTime.day().month(.abbreviated)) }

    private static var formatters: [String: NumberFormatter] = [:]
    private static func locale(_ r: Region) -> Locale { Locale(identifier: r.loc.replacingOccurrences(of: "-", with: "_")) }

    /// Money in the region chosen in Settings — "1.234,56 €" (Germany), "$1,234.56" (US)…
    static func money(_ v: Double) -> String {
        let r = Regions.current
        let f: NumberFormatter
        if let cached = formatters[r.id] { f = cached } else {
            f = NumberFormatter(); f.numberStyle = .currency; f.locale = locale(r); f.currencyCode = r.cur
            formatters[r.id] = f
        }
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
    }
    static var currencySymbol: String { Regions.current.sym }
    static var decimalSeparator: String { locale(Regions.current).decimalSeparator ?? "." }

    /// What a person typed → a canonical number. Accepts "48,53", "48.53", "1.234,56" and
    /// "1,234.56": when both marks appear the LAST one is the decimal; a single mark with at
    /// most two digits after it is a decimal too, otherwise it's a thousands separator.
    static func amount(_ input: String) -> Double? {
        var s = input.trimmed.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\u{00A0}", with: "")
        if s.isEmpty { return nil }
        let lastComma = s.lastIndex(of: ","), lastDot = s.lastIndex(of: ".")
        if let c = lastComma, let d = lastDot {
            if c > d { s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
            else { s = s.replacingOccurrences(of: ",", with: "") }
        } else if let mark = lastComma ?? lastDot {
            let ch = s[mark]
            let count = s.filter { $0 == ch }.count
            let after = s.distance(from: s.index(after: mark), to: s.endIndex)
            if count == 1 && after <= 2 { s = s.replacingOccurrences(of: String(ch), with: ".") }
            else { s = s.replacingOccurrences(of: String(ch), with: "") }
        }
        return Double(s)
    }
    /// A canonical amount shown for editing in the user's own decimal style.
    static func editable(_ v: Double) -> String {
        let plain = v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
        return plain.replacingOccurrences(of: ".", with: decimalSeparator)
    }
}
