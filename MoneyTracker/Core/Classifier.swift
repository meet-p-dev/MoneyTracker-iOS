import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Bank-transaction evidence engine — a line-for-line port of the web app's lib/classify.js.
//
// Every incoming bank payment is scored across its possible meanings (salary, freelance,
// refund, own transfer, reimbursement, loan, other):
//   score(label) = ln P(label | this payee's confirmed history) + Σ evidence weights
//   confidence   = softmax(scores)[best]
// It decides on its own only when the odds are decisive (≥ 70%); otherwise the payment is
// held as a neutral "Received" and shows up in the Review inbox. Outgoing payments: your
// own transfers are "Sent out" (not spending); known shops get their category.
// Your taps teach it per payee; nothing here is specific to one person.
// ─────────────────────────────────────────────────────────────────────────────

struct Cls: Hashable {
    var type: String
    var category: String
    var label: String
    var confidence: Double
    var needsReview: Bool
    var reason: String
    var suggest: [String] = []
    var toAccountId: String? = nil
    var clamped: Bool = false
    var decided: Bool = false
}

enum Classifier {
    static let labels = ["salary", "freelance", "refund", "transfer", "reimburse", "debt", "other"]
    static let labelCls: [String: (type: String, category: String)] = [
        "salary": ("income", "salary"), "freelance": ("income", "freelance"), "refund": ("credit", "refund"),
        "transfer": ("credit", "transfer"), "reimburse": ("credit", "reimburse"), "debt": ("credit", "debt"),
        "other": ("credit", "other"),
    ]
    static let autoThreshold = 0.70, provisional = 0.45, alpha = 0.5

    // Review-inbox choices, in display order. `label` feeds the learner.
    static let reviewChoices: [(key: String, label: String, sub: String, cls: String)] = [
        ("income", "Income", "Salary, freelance, real earnings", "salary"),
        ("reimburse", "Reimbursement", "Rent share, Splitwise, friend pays back", "reimburse"),
        ("transfer", "My transfer", "Between your own accounts", "transfer"),
        ("refund", "Refund", "Money returned for a purchase", "refund"),
        ("debt", "Loan / payback", "Borrowed money, or a loan repaid to you", "debt"),
    ]

    private static let reRefund = JSRegex.make(#"\b(refund|return|erstattung|r[uü]ckzahlung|reversal|chargeback|gutschrift|storno|rueckerstattung)\b"#)
    private static let reSalary = JSRegex.make(#"\b(gehalt|lohn|salary|payroll|bez[uü]ge|besoldung|entgelt|arbeitgeber|wage|wages)\b"#)
    private static let reSalaryW = JSRegex.make(#"\b(schicht|shift|zenjob|minijob)\b"#)
    private static let reFreelance = JSRegex.make(#"\b(honorar|freelance|invoice|auftrag|freiberuf|payout|upwork|fiverr)\b"#)
    private static let reRent = JSRegex.make(#"\b(rent|miete|kaltmiete|warmmiete|nebenkosten|wg)\b"#)
    private static let reSettle = JSRegex.make(#"\b(splitwise|settle|settlement|ausgleich|anteil|share)\b"#)
    private static let reLoan = JSRegex.make(#"\b(loan|leihe|geliehen|borrow|darlehen|kredit|zur[uü]ck|payback|pay back)\b"#)
    private static let reP2P = JSRegex.make(#"\b(paypal|revolut|wise|tikkie|instant transfer|echtzeit|[uü]berweisung|sent from|request money)\b"#)
    private static let reOrg = JSRegex.make(#"\b(gmbh|ag|se\b|kg\b|ug\b|ohg|mbh|ltd|inc\b|co\b|corp|bank|sparkasse|volksbank|amazon|zalando|adyen|stripe|klarna|sumup|mollie|logistik|fulfillment|payments?|service|versicherung|energie|stadtwerke|telekom|vodafone|krankenkasse)\b"#)
    private static let rePSP = JSRegex.make(#"\b(adyen|paypal|klarna|stripe|sumup|mollie|zalando payments|worldpay|checkout)\b"#)
    private static let rePersonChars = try! NSRegularExpression(pattern: #"^[\p{L}.\-' ]+$"#)
    private static let reSpaces = try! NSRegularExpression(pattern: #"\s+"#)

    static func counterpartyKey(_ merchant: String) -> String {
        let s = merchant.lowercased()
        let name = reSpaces.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: " ").trimmed
        return name.isEmpty ? "" : "name:" + name
    }

    static func looksLikePerson(_ name: String) -> Bool {
        let n = name.trimmed
        if n.isEmpty || JSRegex.test(reOrg, n) { return false }
        let words = n.split(whereSeparator: \.isWhitespace)
        return words.count >= 2 && words.count <= 4 && JSRegex.test(rePersonChars, n)
    }

    static func isOwnName(_ name: String, _ tokens: [String]) -> Bool {
        let m = name.lowercased()
        if m.isEmpty || tokens.isEmpty { return false }
        return tokens.filter { $0.count >= 3 && m.contains($0) }.count >= 2
    }

    /// Your own name tokens: the owner name + any personal name that appears on BOTH a
    /// bank credit and a bank debit (money flowing both ways ⇒ your own other account).
    static func ownTokens(_ rows: [Row], ownerName: String) -> [String] {
        var set: [String] = []
        func add(_ w: String) { if w.count >= 3 && !set.contains(w) { set.append(w) } }
        ownerName.lowercased().split(whereSeparator: \.isWhitespace).forEach { add(String($0)) }
        var credited: [String] = []; var debited = Set<String>()
        for t in rows where t.isBank && looksLikePerson(t.merchant) {
            let n = t.merchant.lowercased().trimmed
            if t.rawType == "income" { if !credited.contains(n) { credited.append(n) } }
            else if t.rawType == "expense" { debited.insert(n) }
        }
        for n in credited where debited.contains(n) { n.split(whereSeparator: \.isWhitespace).forEach { add(String($0)) } }
        return set
    }

    static func epochDay(_ d: String) -> Int { Int(floor(CardMath.date(d).timeIntervalSince1970 / 86400)) }

    static func softmax(_ s: [String: Double]) -> [String: Double] {
        let mx = s.values.max() ?? 0
        var e: [String: Double] = [:]; var z = 0.0
        for l in labels { let v = exp((s[l] ?? -9) - mx); e[l] = v; z += v }
        for l in labels { e[l] = (e[l] ?? 0) / z }
        return e
    }

    /// A stored decision re-labels a bank row but never reverses the direction the bank
    /// booked (the "€42" guard); an outgoing transfer WITH a destination is allowed.
    static func applyDecision(_ d: Decision, dir: String) -> Cls {
        let allowed = dir == "in" ? ["income", "credit"] : ["expense", "debit"]
        let outTransfer = dir == "out" && d.type == "transfer" && d.toAccountId != nil
        let kept = (outTransfer || allowed.contains(d.type)) ? d.type : allowed[1]
        let clamped = kept != d.type
        return Cls(type: kept, category: d.category ?? "", label: "", confidence: 1, needsReview: false,
                   reason: clamped ? "you set this — kept as money \(dir) (your bank booked it that way)" : "you set this",
                   toAccountId: outTransfer ? d.toAccountId : nil, clamped: clamped, decided: true)
    }

    /// Classify every BANK row against the whole ledger. Non-bank rows are never touched.
    static func classifyAll(_ txs: [Row], ownerName: String, payeeStats: [String: JSONValue], decisions: [String: JSONValue]) -> [String: Cls] {
        var out: [String: Cls] = [:]
        let own = ownTokens(txs, ownerName: ownerName)
        let bank = txs.filter(\.isBank)

        var debitAmts: [Int: [Row]] = [:]
        var byPayee: [String: [Row]] = [:]
        for t in bank {
            let k = counterpartyKey(t.merchant)
            if !k.isEmpty { byPayee[k, default: []].append(t) }
            if t.rawType == "expense" { debitAmts[Int((t.amount * 100).rounded()), default: []].append(t) }
        }
        // Mirror transfers: a credit in one account + a debit in another, same amount ±1%, ≤ 3 days apart.
        var mirrored = Set<String>()
        let credits = bank.filter { $0.rawType == "income" }
        let debits = bank.filter { $0.rawType == "expense" }
        for cr in credits {
            let a = cr.amount; if a < 1 { continue }
            let cd = epochDay(cr.date)
            if let hit = debits.first(where: { db in
                db.accountId != cr.accountId && abs(db.amount - a) <= a * 0.01 && abs(epochDay(db.date) - cd) <= 3 && !mirrored.contains(db.id)
            }) { mirrored.insert(cr.id); mirrored.insert(hit.id) }
        }
        // Monthly recurrence: ≥ 2 rows from the payee roughly a month apart.
        var recurring = Set<String>()
        for (k, list) in byPayee {
            let days = list.map { epochDay($0.date) }.sorted()
            if days.count >= 2 {
                for i in 1..<days.count where days[i] - days[i - 1] >= 24 && days[i] - days[i - 1] <= 38 { recurring.insert(k); break }
            }
        }

        // ── Score each credit ──
        for t in credits {
            if let dv = decisions[t.id], let d = Decision(dv) { out[t.id] = applyDecision(d, dir: "in"); continue }
            let key = counterpartyKey(t.merchant)
            let text = "\(t.merchant) \(t.notes)"
            let person = looksLikePerson(t.merchant)
            let amt = t.amount
            var why: [String] = []

            let counts = (key.isEmpty ? nil : payeeStats[key]?["counts"]?.object)?.compactMapValues(\.number) ?? [:]
            let n = counts.values.reduce(0, +)
            var s: [String: Double] = [:]
            for l in labels { s[l] = log(((counts[l] ?? 0) + alpha) / (n + alpha * Double(labels.count))) }
            if n > 0, let top = counts.sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }).first {
                why.append("you've marked \(t.merchant) as \(top.key) before")
            }
            func add(_ l: String, _ w: Double) { s[l, default: 0] += w }

            if isOwnName(t.merchant, own) { add("transfer", 4); why.append("counterparty is you — own-account transfer") }
            if mirrored.contains(t.id) { add("transfer", 3); why.append("mirrors a debit from your other account (same amount, same days)") }
            if JSRegex.test(reRefund, text) { add("refund", 3); why.append("refund wording in the description") }
            let cents = Int((amt * 100).rounded())
            let td = epochDay(t.date)
            let pastDebits = (debitAmts[cents] ?? []).filter { let d = td - epochDay($0.date); return d >= 0 && d <= 90 }
            if pastDebits.contains(where: { counterpartyKey($0.merchant) == key }) { add("refund", 3); why.append("matches your earlier payment of the same amount to \(t.merchant)") }
            else if !pastDebits.isEmpty && JSRegex.test(rePSP, text) { add("refund", 2); why.append("payment processor credit matching an earlier charge") }

            if JSRegex.test(reSalary, text) { add("salary", 4); why.append("salary wording (Lohn/Gehalt)") }
            if JSRegex.test(reSalaryW, text) { add("salary", 1.5) }
            if JSRegex.test(reFreelance, text) { add("freelance", 3); why.append("invoice/freelance wording") }
            if person && JSRegex.test(reRent, text) { add("reimburse", 3); why.append("rent wording from a person — collected share, not income") }
            if JSRegex.test(reSettle, text) { add("reimburse", 2.5); why.append("settlement wording (Splitwise/settle)") }
            if JSRegex.test(reLoan, text) { add("debt", 2.5); why.append("loan wording") }
            if person { add("reimburse", 1); add("salary", -1.5); add("freelance", -1.5) }
            if person && amt >= 800 && !JSRegex.test(reRent, text) { add("debt", 2); add("salary", -2); why.append("large amount (€\(Int(amt.rounded()))) from a person — could be a loan") }
            if JSRegex.test(reP2P, text) { add("transfer", 1); add("reimburse", 1) }
            if person && amt >= 20 && abs(amt - (amt / 5).rounded() * 5) < 0.001 { add("reimburse", 0.5); add("transfer", 0.5); add("salary", -1) }
            if recurring.contains(key) { if person { add("reimburse", 1) } else { add("salary", 1) } }
            if !person && !JSRegex.test(reSalary, text) && !JSRegex.test(reRefund, text) && pastDebits.isEmpty { add("other", 0.5) }

            let p = softmax(s)
            let ranked = labels.enumerated().sorted { a, b in
                let pa = p[a.element] ?? 0, pb = p[b.element] ?? 0
                return pa != pb ? pa > pb : a.offset < b.offset
            }.map(\.element)
            let best = ranked[0], conf = p[best] ?? 0, top3 = Array(ranked.prefix(3))
            let bc = labelCls[best]!
            if conf >= autoThreshold {
                out[t.id] = Cls(type: bc.type, category: bc.category, label: best, confidence: conf, needsReview: false, reason: why.first ?? "pattern match", suggest: top3)
            } else if conf >= provisional && bc.type == "credit" {
                out[t.id] = Cls(type: bc.type, category: bc.category, label: best, confidence: conf, needsReview: true, reason: (why.first ?? "unclear") + " — please confirm", suggest: top3)
            } else {
                out[t.id] = Cls(type: "credit", category: "other", label: "other", confidence: conf, needsReview: true, reason: "not sure what this incoming money is — please confirm", suggest: top3)
            }
        }

        // ── Debits: own-transfer detection, then categorisation of real spend ──
        for t in debits {
            if let dv = decisions[t.id], let d = Decision(dv) { out[t.id] = applyDecision(d, dir: "out"); continue }
            if isOwnName(t.merchant, own) || mirrored.contains(t.id) {
                out[t.id] = Cls(type: "debit", category: "transfer", label: "transfer", confidence: 0.95, needsReview: false, reason: "transfer to your own account")
                continue
            }
            let key = counterpartyKey(t.merchant)
            if !key.isEmpty, let taught = payeeStats[key]?["cat"]?.string, !taught.isEmpty {
                out[t.id] = Cls(type: "expense", category: taught, label: "expense", confidence: 1, needsReview: false, reason: "you categorise \(t.merchant) as this")
                continue
            }
            if t.rawCategoryId.isEmpty || t.rawCategoryId == "other", let cat = Merchants.category(t.merchant) {
                out[t.id] = Cls(type: "expense", category: cat, label: "expense", confidence: 0.8, needsReview: false, reason: "\(t.merchant) is a known merchant")
            }
        }
        return out
    }

    // ── Learning (same JSON shape as the web's mt-payee-stats, so it syncs both ways) ──
    /// One tap = weight 3: it dominates the smoothed prior; mixed histories stay mixed.
    static func bumpPayeeStats(_ stats: [String: JSONValue], key: String, label: String, w: Double = 3) -> [String: JSONValue] {
        guard !key.isEmpty, labels.contains(label) else { return stats }
        var cur = stats[key]?.object ?? [:]
        var counts = cur["counts"]?.object ?? [:]
        counts[label] = .number((counts[label]?.number ?? 0) + w)
        cur["counts"] = .object(counts)
        var out = stats; out[key] = .object(cur); return out
    }
    /// Remember the expense category you picked for a payee, for every future row from them.
    static func setPayeeCat(_ stats: [String: JSONValue], key: String, cat: String) -> [String: JSONValue] {
        guard !key.isEmpty, !cat.isEmpty else { return stats }
        var cur = stats[key]?.object ?? [:]
        cur["cat"] = .string(cat)
        var out = stats; out[key] = .object(cur); return out
    }
    /// Category suggestion while typing a shop name: what you taught > the shipped list.
    static func suggestCategory(merchant: String, payeeStats: [String: JSONValue]) -> String? {
        let m = merchant.trimmed
        guard m.count >= 3 else { return nil }
        if let taught = payeeStats[counterpartyKey(m)]?["cat"]?.string, !taught.isEmpty { return taught }
        return Merchants.category(m)
    }
}
