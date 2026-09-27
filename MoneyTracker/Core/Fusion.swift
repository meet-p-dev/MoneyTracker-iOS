import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Tap & Settle — MoneyTrack's own matcher. It has no web twin: it only links a quick
// "evidence" row (an Apple Pay tap) to the bank row that books the same purchase later.
//
//   • The bank owns the numbers. A settle never changes a bank row's amount, date,
//     direction or account; the tap only lends its meaning (a category you picked).
//   • Evidence never enters Ledger or the Classifier, so every balance stays the bank's.
//   • Plain Swift, no SwiftData or SwiftUI, so it compiles with swiftc and can be replayed
//     against a real backup.
//
// Pipeline per run: gates (a pair failing one is never scored) → a log-odds score in the
// Classifier's style → one-to-one assignment → settle / ask / wait → orphans once the
// bank feed is complete well past the tap.
// ─────────────────────────────────────────────────────────────────────────────

/// One piece of evidence (a Wallet tap) as the matcher sees it.
struct Evidence: Hashable {
    var id: String
    var at: Date?               // when the automation ran (can lag the real tap)
    var day: String             // local yyyy-MM-dd of `at`
    var cents: Int?             // nil = Wallet sent no usable amount
    var cur: String?            // ISO code; nil = unknown
    var merchant: String
    var card: String
    var accountId: String?      // nil = card not linked to an account yet
}

/// What the matcher learns. Local only (never synced): card names can contain personal names.
struct FusionMemory: Codable, Equatable {
    var aliases: [String: [String]] = [:]   // tap merchant head → bank payee heads
    var banned: Set<String> = []            // "tapId|bankId" pairs you said are different
    var lags: [String: [Int]] = [:]         // accountId → days from tap to booking (last 50)
    var tipHeads: Set<String> = []          // merchants where the bank amount can be higher (tips)
    var varyHeads: Set<String> = []         // merchants with pre-authorised holds
    var fx: [String: Double] = [:]          // foreign currency → home currency per unit
    var cardMap: [String: String] = [:]     // Wallet card name → accountId
}

enum Fusion {
    // ── Amounts ──

    /// Wallet's amount → (cents, ISO currency). The typed Currency Amount wins; the text form
    /// ("12,50 €", "CHF 12.50", "US$3.20") is the fallback. A lone "$" stays unknown.
    static func parseAmount(typed: Decimal?, code: String?, text: String?) -> (cents: Int?, cur: String?) {
        if let t = typed, t > 0 {
            return (cents(NSDecimalNumber(decimal: t).doubleValue), clean(code))
        }
        guard let s = text?.trimmed, !s.isEmpty else { return (nil, nil) }
        let cur = currency(in: s) ?? clean(code)
        let digits = String(s.filter { $0.isNumber || $0 == "," || $0 == "." })
        guard let v = Fmt.amount(digits), abs(v) > 0 else { return (nil, cur) }
        return (cents(abs(v)), cur)
    }
    static func cents(_ v: Double) -> Int { Int((v * 100).rounded()) }
    private static func clean(_ code: String?) -> String? {
        guard let c = code?.trimmed.uppercased(), c.count == 3, c.allSatisfy(\.isLetter) else { return nil }
        return c
    }
    private static let symbols: [(String, String)] = [
        ("US$", "USD"), ("€", "EUR"), ("£", "GBP"), ("CHF", "CHF"), ("Fr.", "CHF"), ("zł", "PLN"),
        ("Kč", "CZK"), ("¥", "JPY"), ("₹", "INR"), ("₺", "TRY"), ("Ft", "HUF"),
    ]
    private static let isoRe = try! NSRegularExpression(pattern: #"\b([A-Z]{3})\b"#)
    static func currency(in s: String) -> String? {
        for (sym, iso) in symbols where s.contains(sym) { return iso }
        if let m = isoRe.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), let r = Range(m.range(at: 1), in: s) {
            return String(s[r])
        }
        return nil
    }

    // ── Merchant key ──

    private static let cutMarks = ["//", " sagt danke", " dankt"]
    private static let prefixes = ["sumup *", "sq *", "zettle_", "izettle", "paypal *", "pp*", "vr pay", "kartenzahlung",
                                   "debitk.", "girocard", "visa", "mastercard", "apple pay"]
    private static let dropTokens: Set<String> = ["gmbh", "ag", "se", "kg", "ohg", "ug", "mbh", "co", "ltd", "inc", "llc",
                                                  "bv", "nv", "eg", "markt", "filiale", "danke", "sagt"]
    private static let pspRe = try! NSRegularExpression(pattern: #"\b(paypal|sumup|klarna|adyen|stripe|mollie|zettle)\b"#)

    /// Lowercase, fold umlauts and accents, drop payment-terminal noise, legal forms and numbers.
    static func norm(_ s: String) -> String {
        var t = s.lowercased()
            .replacingOccurrences(of: "ä", with: "ae").replacingOccurrences(of: "ö", with: "oe")
            .replacingOccurrences(of: "ü", with: "ue").replacingOccurrences(of: "ß", with: "ss")
        t = t.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        for m in cutMarks { if let r = t.range(of: m) { t = String(t[..<r.lowerBound]) } }
        var changed = true
        while changed {
            changed = false
            t = t.trimmed
            for p in prefixes where t.hasPrefix(p) { t = String(t.dropFirst(p.count)); changed = true }
        }
        return t
    }
    static func tokens(_ s: String) -> [String] {
        norm(s).split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { tok in
            tok.filter(\.isLetter).count >= 3 && tok.filter(\.isNumber).count < 3 && !dropTokens.contains(tok)
        }
    }
    static func head(_ s: String) -> String { tokens(s).first ?? "" }

    /// How alike a tap's merchant and a bank row's text are, 0…1.
    static func similarity(tap: String, bank: String, bankHead: String, memory: FusionMemory) -> Double {
        let ta = tokens(tap), tb = tokens(bank)
        let ha = ta.first ?? "", hb = bankHead
        if ha.isEmpty || tb.isEmpty { return 0 }
        if let al = memory.aliases[ha], al.contains(hb) { return 1 }
        let A = Set(ta), B = Set(tb)
        var m = Double(A.intersection(B).count) / Double(A.union(B).count)
        if !hb.isEmpty && ha == hb { m = max(m, 0.8) }
        if ha.count >= 4 && hb.count >= 4 && (ha.hasPrefix(hb) || hb.hasPrefix(ha)) { m = max(m, 0.6) }
        if !hb.isEmpty { let dice = trigramDice(ha, hb); if dice >= 0.7 { m = max(m, 0.8 * dice) } }
        if has(pspRe, bank.lowercased()) && !has(pspRe, tap.lowercased()) { m = max(m, 0.5) }
        return min(m, 1)
    }
    static func trigramDice(_ a: String, _ b: String) -> Double {
        func grams(_ s: String) -> [String] {
            let c = Array("  " + s + " ")
            return c.count < 3 ? [] : (0...(c.count - 3)).map { String(c[$0..<$0 + 3]) }
        }
        let ga = grams(a), gb = grams(b)
        if ga.isEmpty || gb.isEmpty { return 0 }
        var pool = gb, common = 0
        for g in ga { if let i = pool.firstIndex(of: g) { pool.remove(at: i); common += 1 } }
        return 2 * Double(common) / Double(ga.count + gb.count)
    }

    // ── What a bank row tells us ──

    private static let cardRe = try! NSRegularExpression(pattern: #"\b(girocard|debitk|kartenzahlung|visa|mastercard|apple ?pay|google ?pay|card_payment)\b"#)
    private static let notCardRe = try! NSRegularExpression(pattern: #"\b(mref|cred|lastschrift|dauerauftrag|ueberweisung|überweisung|sepa-?basis)\b"#)
    private static let timeRe = try! NSRegularExpression(pattern: #"(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2})"#)
    private static let tipRe = try! NSRegularExpression(pattern: #"\b(taxi|cab|uber|free ?now|bolt|friseur|salon|bar|kneipe|lieferando|wolt|pizzeria|ristorante|osteria|trattoria|taverna|restaurant|gaststaette|gasthaus|brauhaus|biergarten|cafe|bistro|imbiss|kebab|sushi|burger)\b"#)
    private static let holdRe = try! NSRegularExpression(pattern: #"\b(tankstelle|aral|shell|esso|total|jet|agip|omv|hotel|hostel|sixt|europcar|hertz|avis|ladestation|ionity|enbw|tesla|charging|parkhaus)\b"#)
    private static func has(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    /// +1 if the bank text says card payment, −1 if it is plainly a debit order or transfer.
    static func cardEvidence(_ text: String) -> Int {
        let t = text.lowercased()
        if has(cardRe, t) { return 1 }
        if has(notCardRe, t) { return -1 }
        return 0
    }
    /// German card bookings carry the terminal's local time: "2026-05-02T19:32".
    static func terminalTime(_ text: String) -> Date? {
        guard let m = timeRe.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let d = Range(m.range(at: 1), in: text), let h = Range(m.range(at: 2), in: text),
              let mi = Range(m.range(at: 3), in: text),
              let base = Fmt.day.date(from: String(text[d])), let hh = Int(text[h]), let mm = Int(text[mi]) else { return nil }
        return base.addingTimeInterval(Double(hh * 3600 + mm * 60))
    }

    // ── Candidates ──

    enum Kind: String { case exact, tip, hold, fx, unknown }

    struct Candidate {
        let evidenceId: String
        let bankId: String
        let s: Double
        let lag: Int
        let askOnly: Bool
        let kind: Kind
        let reason: String
        let twinKey: String     // bank rows with the same key are interchangeable
    }

    struct Link {
        let evidenceId: String
        let bankId: String
        let p: Double
        let lag: Int
        let kind: Kind
        let reason: String
    }

    struct Outcome {
        var settle: [Link] = []
        var ask: [Link] = []
        var orphans: [String] = []
    }

    static let baseline = 4.5           // log-odds of "the bank hasn't booked it yet"
    static let settleP = 0.85, askP = 0.55, settleMargin = 1.0

    /// The window after a tap in which its booking may appear.
    static func maxLag(_ acc: String?, _ memory: FusionMemory) -> Int {
        guard let acc, let l = memory.lags[acc], l.count >= 5 else { return 7 }
        let sorted = l.sorted()
        let p95 = sorted[min(sorted.count - 1, Int((Double(sorted.count) * 0.95).rounded(.down)))]
        return min(max(p95 + 2, 4), 14)
    }
    static func medianLag(_ acc: String?, _ memory: FusionMemory) -> Int {
        guard let acc, let l = memory.lags[acc], !l.isEmpty else { return 1 }
        return l.sorted()[l.count / 2]
    }

    /// Bank rows a tap can settle against: synced money out that isn't a card bill.
    static func bankRows(_ rows: [Row]) -> [Row] {
        rows.filter { r in
            r.isBank && (r.type == "expense" || r.type == "debit") && !r.cardPay
                && !CardMath.looksLikeCardBill("\(r.merchant) \(r.notes)".lowercased())
        }
    }

    /// Every pair that passes the gates, scored.
    static func candidates(_ e: Evidence, _ bank: [Row], feedAccounts: Set<String>, memory: FusionMemory,
                           home: String) -> [Candidate] {
        let hi = maxLag(e.accountId, memory), med = medianLag(e.accountId, memory)
        let tapHead = head(e.merchant)
        var out: [Candidate] = []
        for t in bank {
            // G1 account
            let unmapped = e.accountId == nil
            if let a = e.accountId { if t.accountId != a { continue } }
            else if !feedAccounts.contains(t.accountId) { continue }
            if memory.banned.contains("\(e.id)|\(t.id)") { continue }
            // G3 date
            let d = CardMath.daysBetween(e.day, t.date)
            if d < -1 || d > hi { continue }
            // G4 amount
            let bankText = "\(t.merchant) \(t.notes)"
            let bHead = head(t.merchant.isEmpty ? t.notes : t.merchant)
            let m = similarity(tap: e.merchant, bank: bankText, bankHead: bHead, memory: memory)
            let ct = cents(t.amount)
            var kind = Kind.unknown, amountTerm = 0.0, askOnly = unmapped
            if let ce = e.cents {
                let foreign = (e.cur ?? home) != home
                if foreign && ct != ce {
                    guard let rate = memory.fx[e.cur ?? ""] else {
                        if m < 0.8 { continue }
                        kind = .fx; askOnly = true
                        out.append(make(e, t, m, amountTerm, kind, d, med, askOnly, unmapped, bankText))
                        continue
                    }
                    let r = Double(ct) / (Double(ce) * rate)
                    if abs(r - 1) > 0.06 || m < 0.6 { continue }
                    kind = .fx; amountTerm = abs(r - 1) <= 0.03 ? 2.5 : 1.5
                } else if abs(ct - ce) <= 1 {
                    kind = .exact; amountTerm = ct == ce ? 4.0 : 3.5
                } else if isTipProne(tapHead, e.merchant, t, memory), ct > ce, Double(ct) <= 1.25 * Double(ce) + 100 {
                    kind = .tip; amountTerm = memory.tipHeads.contains(tapHead) ? 3.0 : 2.0
                } else if isHoldProne(tapHead, e.merchant, t, memory), ct > 0, ct <= max(ce, 25_000), m >= 0.8 {
                    kind = .hold; amountTerm = 1.0
                } else { continue }
                if e.cur == nil { askOnly = true }
            } else {
                // A tap without an amount: only a strong name match, soon after, and you confirm it.
                if m < 0.8 || d > 3 { continue }
                askOnly = true
            }
            out.append(make(e, t, m, amountTerm, kind, d, med, askOnly, unmapped, bankText))
        }
        return out
    }

    private static func make(_ e: Evidence, _ t: Row, _ m: Double, _ amountTerm: Double, _ kind: Kind, _ d: Int, _ med: Int,
                             _ askOnly: Bool, _ unmapped: Bool, _ bankText: String) -> Candidate {
        var s = 3.0 * m + amountTerm
        var why: [String] = []
        switch kind {
        case .exact: why.append("same amount")
        case .tip: why.append("bank amount a little higher (tip)")
        case .hold: why.append("amount changed after a hold")
        case .fx: why.append("foreign currency")
        case .unknown: why.append("no amount from Wallet")
        }
        if m >= 0.8 { why.append("same shop") } else if m >= 0.5 { why.append("similar name") }
        if let at = e.at, let tt = terminalTime(bankText) {
            let delta = at.timeIntervalSince(tt) / 60     // minutes; positive = our capture came later
            if abs(delta) <= 10 { s += 3.0; why.append("same time at the till") }
            else if abs(delta) <= 60 { s += 1.5; why.append("within an hour") }
            else if delta < -180 { s -= 2.0 }              // the till time is hours AFTER the tap: another purchase
        }
        let c = cardEvidence(bankText)
        s += Double(c)
        if c > 0 { why.append("card payment") }
        s -= 0.6 * Double(max(0, abs(d - med) - 1))
        if unmapped { s -= 0.5 }
        why.append(d <= 0 ? "same day" : "\(d) day\(d == 1 ? "" : "s") later")
        let twin = "\(t.accountId)|\(cents(t.amount))|\(t.date)|\(head(t.merchant.isEmpty ? t.notes : t.merchant))"
        return Candidate(evidenceId: e.id, bankId: t.id, s: s, lag: d, askOnly: askOnly, kind: kind,
                         reason: why.joined(separator: ", ").capitalizedFirst, twinKey: twin)
    }

    private static func isTipProne(_ h: String, _ tap: String, _ t: Row, _ mem: FusionMemory) -> Bool {
        if mem.tipHeads.contains(h) { return true }
        if Merchants.category(tap) == "dining" || Merchants.category(t.merchant) == "dining" { return true }
        return has(tipRe, tap.lowercased()) || t.categoryId == "dining"
    }
    private static func isHoldProne(_ h: String, _ tap: String, _ t: Row, _ mem: FusionMemory) -> Bool {
        mem.varyHeads.contains(h) || has(holdRe, tap.lowercased()) || has(holdRe, t.merchant.lowercased())
    }

    // ── One run ──

    /// - Parameters:
    ///   - taken: bank ids already settled with a tap (never offered twice).
    ///   - feedAccounts: accounts whose rows come from a bank feed.
    ///   - coverage: accountId → last local day the feed is complete through.
    static func run(evidence: [Evidence], rows: [Row], taken: Set<String>, feedAccounts: Set<String>,
                    coverage: [String: String], memory: FusionMemory, home: String) -> Outcome {
        let bank = bankRows(rows).filter { !taken.contains($0.id) }
        let evidence = evidence.sorted { ($0.at ?? .distantPast, $0.id) < ($1.at ?? .distantPast, $1.id) }
        var cands: [String: [Candidate]] = [:]
        var all: [Candidate] = []
        for e in evidence {
            let c = candidates(e, bank, feedAccounts: feedAccounts, memory: memory, home: home)
            cands[e.id] = c; all += c
        }
        let order = Dictionary(uniqueKeysWithValues: evidence.enumerated().map { ($1.id, $0) })
        let bankOrder = Dictionary(bank.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        all.sort { a, b in
            if a.s != b.s { return a.s > b.s }
            if abs(a.lag) != abs(b.lag) { return abs(a.lag) < abs(b.lag) }
            if order[a.evidenceId]! != order[b.evidenceId]! { return order[a.evidenceId]! < order[b.evidenceId]! }
            return (bankRowDate(bank, a.bankId), bankOrder[a.bankId] ?? 0) < (bankRowDate(bank, b.bankId), bankOrder[b.bankId] ?? 0)
        }
        var usedE = Set<String>(), usedB = Set<String>()
        var out = Outcome()
        for c in all where !usedE.contains(c.evidenceId) && !usedB.contains(c.bankId) {
            // Rivals: this tap's other free bank rows, counting interchangeable twins once.
            let others = (cands[c.evidenceId] ?? []).filter { $0.bankId != c.bankId && !usedB.contains($0.bankId) && $0.twinKey != c.twinKey }
            var seen = Set<String>(), rivalS: [Double] = []
            for o in others.sorted(by: { $0.s > $1.s }) where seen.insert(o.twinKey).inserted { rivalS.append(o.s) }
            let p = exp(c.s) / (exp(baseline) + exp(c.s) + rivalS.reduce(0) { $0 + exp($1) })
            let margin = c.s - (rivalS.first ?? -.infinity)
            let link = Link(evidenceId: c.evidenceId, bankId: c.bankId, p: p, lag: c.lag, kind: c.kind, reason: c.reason)
            if p >= settleP && margin >= settleMargin && !c.askOnly {
                out.settle.append(link); usedE.insert(c.evidenceId); usedB.insert(c.bankId)
            } else if p >= askP {
                out.ask.append(link); usedE.insert(c.evidenceId); usedB.insert(c.bankId)
            }
        }
        // Orphans: the feed is complete well past the tap and nothing matched.
        for e in evidence where !usedE.contains(e.id) {
            guard let a = e.accountId, feedAccounts.contains(a), let cov = coverage[a] else { continue }
            if CardMath.daysBetween(e.day, cov) > maxLag(a, memory) + 2 { out.orphans.append(e.id) }
        }
        return out
    }
    private static func bankRowDate(_ bank: [Row], _ id: String) -> String { bank.first { $0.id == id }?.date ?? "" }

    // ── Learning (after a settle or your "Yes") ──

    static func learn(_ mem: inout FusionMemory, _ e: Evidence, _ t: Row, kind: Kind, lag: Int, home: String) {
        let hA = head(e.merchant), hB = head(t.merchant.isEmpty ? t.notes : t.merchant)
        if !hA.isEmpty && !hB.isEmpty && hA != hB {
            var al = mem.aliases[hA] ?? []
            if !al.contains(hB) { al.append(hB); mem.aliases[hA] = Array(al.suffix(5)) }
        }
        if let a = e.accountId {
            mem.lags[a] = Array(((mem.lags[a] ?? []) + [max(lag, 0)]).suffix(50))
        }
        if kind == .tip && !hA.isEmpty { mem.tipHeads.insert(hA) }
        if kind == .hold && !hA.isEmpty { mem.varyHeads.insert(hA) }
        if let ce = e.cents, ce > 0, let cur = e.cur, cur != home {
            let rate = Double(cents(t.amount)) / Double(ce)
            mem.fx[cur] = mem.fx[cur].map { 0.7 * $0 + 0.3 * rate } ?? rate
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
