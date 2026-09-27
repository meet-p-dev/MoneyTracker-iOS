import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Statement Drop — reads a bank's own export and plans what it changes. iOS only (no web
// twin). Plain Swift, so it compiles with swiftc and can be checked against real files.
//
//   Formats: CSV (Revolut, Sparkasse, DKB, ING, N26 and any bank with a date and an amount
//   column), camt.052/053 XML and MT940.
//   On an account you manage by hand the file is the truth: its rows come in as bank rows,
//   Apple Pay taps settle into them, rows you typed are matched instead of doubled.
//   On a bank-synced account the file is only a cross-check: nothing is added, so the
//   balance stays the bank's.
// ─────────────────────────────────────────────────────────────────────────────

struct StatementRow: Hashable {
    enum Status: String { case booked, pending, reverted }
    var day: String                 // booking date, local yyyy-MM-dd
    var cents: Int                  // signed: negative = money out
    var payee: String
    var purpose: String
    var cur: String = ""            // ISO code, "" = the file's currency
    var status: Status = .booked
    var ref: String = ""            // the bank's own reference, when the file has one
    var time: String = ""           // when the purchase happened, "yyyy-MM-ddTHH:mm", if the file says (Revolut)
    var balanceCents: Int? = nil    // running balance after this row, when the file has it
}

struct Statement {
    var rows: [StatementRow] = []
    var format = ""                 // "CSV" | "camt" | "MT940"
    var bank = ""
    var iban = ""
    var currency = ""
    var closing: (day: String, cents: Int)?
    var first: String? { rows.map(\.day).min() }
    var last: String? { rows.map(\.day).max() }
    /// Remembers which account a file belongs to.
    var accountKey: String { iban.isEmpty ? "bank:" + bank.lowercased() : "iban:" + iban.replacingOccurrences(of: " ", with: "").uppercased() }
}

struct StatementError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum StatementParser {
    /// - Parameter pdfText: turns a PDF into its text (PDFKit in the app; Core stays plain Swift).
    static func parse(_ data: Data, filename: String = "", pdfText: ((Data) -> String?)? = nil) throws -> Statement {
        let text = decode(data)
        let head = String(text.prefix(4000))
        var st: Statement
        if head.contains("<Document") || head.contains("BkToCstmr") {
            st = try Camt.parse(data)
        } else if head.contains(":20:") && text.contains(":61:") {
            st = try MT940.parse(text)
        } else if filename.lowercased().hasSuffix(".pdf") || data.starts(with: [0x25, 0x50, 0x44, 0x46]) {
            guard let text = pdfText?(data), !text.trimmed.isEmpty else {
                throw StatementError(message: "This PDF has no readable text (maybe a scan). Export a CSV from your bank instead.")
            }
            st = PDFStatement.parse(text)
        } else if data.starts(with: [0x50, 0x4B, 0x03, 0x04]) {
            st = try CSV.parse(rows: try XLSX.rows(data), format: "Excel")
        } else {
            st = try CSV.parse(text)
        }
        guard !st.rows.isEmpty else { throw StatementError(message: "No transactions found in this file.") }
        if st.currency.isEmpty { st.currency = st.rows.first { !$0.cur.isEmpty }?.cur ?? "" }
        return st
    }

    /// UTF-8 (with or without BOM), else Windows-1252 — German banks still export Latin-1.
    static func decode(_ data: Data) -> String {
        var d = data
        if d.starts(with: [0xEF, 0xBB, 0xBF]) { d = d.dropFirst(3) }
        if let s = String(data: d, encoding: .utf8) { return s }
        return String(data: d, encoding: .windowsCP1252) ?? String(decoding: d, as: UTF8.self)
    }

    // ── Dates and amounts ──

    private static let reISO = try! NSRegularExpression(pattern: #"^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{2}))?"#)
    private static let reDE = try! NSRegularExpression(pattern: #"^(\d{1,2})\.(\d{1,2})\.(\d{2,4})(?:,? (\d{1,2}):(\d{2}))?"#)
    private static let reSlash = try! NSRegularExpression(pattern: #"^(\d{1,2})/(\d{1,2})/(\d{4})"#)
    private static let reSlashISO = try! NSRegularExpression(pattern: #"^(\d{4})/(\d{1,2})/(\d{1,2})"#)

    /// "02.05.26", "02.05.2026", "2026-05-02 19:32:11", "02/05/2026" → ("2026-05-02", "19:32").
    static func day(_ s: String) -> (day: String, time: String)? {
        let t = s.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        func groups(_ re: NSRegularExpression) -> [Int?]? {
            guard let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) else { return nil }
            return (1..<m.numberOfRanges).map { i in Range(m.range(at: i), in: t).flatMap { Int(t[$0]) } }
        }
        var y = 0, mo = 0, d = 0, h: Int?, mi: Int?
        // Excel stores dates as days since 30 Dec 1899 (the fraction is the time of day).
        if let serial = Double(t), serial > 20000, serial < 80000, t.allSatisfy({ $0.isNumber || $0 == "." }) {
            var c = DateComponents(); c.year = 1899; c.month = 12; c.day = 30
            let cal = Calendar(identifier: .gregorian)
            guard let base = cal.date(from: c) else { return nil }
            let whole = Int(serial), mins = Int(((serial - Double(whole)) * 1440).rounded())
            guard let dd = cal.date(byAdding: .day, value: whole, to: base) else { return nil }
            let p = cal.dateComponents([.year, .month, .day], from: dd)
            return (CardMath.ymd(p.year!, p.month!, p.day!), mins > 0 ? String(format: "%02d:%02d", mins / 60, mins % 60) : "")
        }
        if let g = groups(reISO) { y = g[0]!; mo = g[1]!; d = g[2]!; h = g[3]; mi = g[4] }
        else if let g = groups(reDE) { d = g[0]!; mo = g[1]!; y = g[2]!; h = g[3]; mi = g[4] }
        else if let g = groups(reSlashISO) { y = g[0]!; mo = g[1]!; d = g[2]! }
        else if let g = groups(reSlash) { d = g[0]!; mo = g[1]!; y = g[2]! }
        else { return nil }
        if y < 100 { y += 2000 }
        guard (1...12).contains(mo), (1...31).contains(d), y > 1990 else { return nil }
        let time = (h != nil && mi != nil) ? String(format: "%02d:%02d", h!, mi!) : ""
        return (CardMath.ymd(y, mo, d), time)
    }

    /// "-17,63", "1.234,56 €", "17,63-", "−3.20", "(12.00)", "12,50 S" → signed cents.
    static func cents(_ s: String) -> Int? {
        var t = s.trimmed.replacingOccurrences(of: "\u{2212}", with: "-").replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "'", with: "")
        var neg = false
        if t.hasSuffix(" S") || t.hasSuffix(" D") { neg = true; t = String(t.dropLast(2)) }
        else if t.hasSuffix(" H") || t.hasSuffix(" C") { t = String(t.dropLast(2)) }
        t = t.trimmed
        if t.hasPrefix("(") && t.hasSuffix(")") { neg = true; t = String(t.dropFirst().dropLast()) }
        let body = t.filter { $0.isNumber || $0 == "," || $0 == "." || $0 == "-" || $0 == "+" }
        var num = body
        if num.hasPrefix("-") { neg.toggle(); num.removeFirst() } else if num.hasPrefix("+") { num.removeFirst() }
        if num.hasSuffix("-") { neg.toggle(); num.removeLast() }
        num = num.filter { $0.isNumber || $0 == "," || $0 == "." }
        guard !num.isEmpty, num.contains(where: \.isNumber), let v = Fmt.amount(num) else { return nil }
        let c = Int((v * 100).rounded())
        return neg ? -c : c
    }

    static func norm(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "ä", with: "ae").replacingOccurrences(of: "ö", with: "oe")
            .replacingOccurrences(of: "ü", with: "ue").replacingOccurrences(of: "ß", with: "ss")
            .replacingOccurrences(of: "€", with: " eur ")
            .map { $0.isLetter || $0.isNumber ? $0 : " " }
            .reduce(into: "") { $0.append($1) }
            .split(separator: " ").joined(separator: " ")
    }
}

// ── CSV ──
enum CSV {
    enum Role: CaseIterable { case date, started, value, amount, debit, credit, payee, payeeIn, payeeOut, purpose, kind, currency, status, fee, balance, account }
    // Exact header names first; then a header that starts with one of these.
    static let names: [Role: [String]] = [
        .date: ["buchungstag", "buchungsdatum", "buchung", "booking date", "date", "datum", "completed date", "transaction date", "transaktionsdatum", "belegdatum"],
        .started: ["started date"],
        .value: ["valutadatum", "wertstellung", "wertstellungsdatum", "value date", "valuta"],
        .amount: ["betrag", "amount", "betrag eur", "amount eur", "umsatz", "betrag in eur", "transaction amount", "umsatz in eur", "betrag euro"],
        .debit: ["soll", "belastung", "debit", "ausgang", "abgang"],
        .credit: ["haben", "gutschrift", "credit", "eingang", "zugang"],
        .payee: ["beguenstigter zahlungspflichtiger", "auftraggeber empfaenger", "partner name", "payee", "name", "empfaenger",
                 "counterparty", "gegenpartei", "zahlungsempfaenger", "description", "beschreibung", "merchant", "haendler", "name zahlungsbeteiligter"],
        .payeeIn: ["zahlungspflichtige r", "zahlungspflichtiger"],
        .payeeOut: ["zahlungsempfaenger in"],
        .purpose: ["verwendungszweck", "payment reference", "reference", "purpose", "remittance information", "buchungsdetails", "memo", "notes"],
        .kind: ["buchungstext", "umsatztyp", "transaction type", "type", "art", "umsatzart"],
        .currency: ["waehrung", "currency", "whrg"],
        .status: ["status", "state", "info"],
        .fee: ["fee", "gebuehr", "gebuehren"],
        .balance: ["saldo", "balance", "kontostand", "saldo nach buchung"],
        .account: ["auftragskonto", "iban auftragskonto"],
    ]

    static func mapHeader(_ cells: [String]) -> [Role: Int] {
        let n = cells.map { StatementParser.norm($0) }
        var map: [Role: Int] = [:], used = Set<Int>()
        for exact in [true, false] {
            for role in Role.allCases where map[role] == nil {
                for name in names[role] ?? [] {
                    if let i = n.indices.first(where: { !used.contains($0) && (exact ? n[$0] == name : n[$0].hasPrefix(name + " ")) }) {
                        map[role] = i; used.insert(i); break
                    }
                }
            }
        }
        // ING has two "Währung" columns: the one right after the amount belongs to it.
        if let a = map[.amount], a + 1 < n.count, ["waehrung", "currency"].contains(n[a + 1]) { map[.currency] = a + 1 }
        return map
    }

    static func split(_ text: String, _ sep: Character) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], cell = "", quoted = false
        var it = Array(text).makeIterator()
        var pending: Character? = nil
        while let c = pending ?? it.next() {
            pending = nil
            if quoted {
                if c == "\"" {
                    if let n = it.next() { if n == "\"" { cell.append("\"") } else { quoted = false; pending = n } }
                    else { quoted = false }
                } else { cell.append(c) }
            } else if c == "\"" { quoted = true }
            else if c == sep { row.append(cell); cell = "" }
            else if c == "\n" || c == "\r\n" || c == "\r" {
                row.append(cell); cell = ""
                if row.contains(where: { !$0.trimmed.isEmpty }) { rows.append(row) }
                row = []
            } else { cell.append(c) }
        }
        row.append(cell)
        if row.contains(where: { !$0.trimmed.isEmpty }) { rows.append(row) }
        return rows
    }

    /// The header row: the first of the top 40 rows that names a date and an amount column.
    static func header(_ rows: [[String]]) -> (index: Int, map: [Role: Int])? {
        for (i, r) in rows.prefix(40).enumerated() {
            let m = mapHeader(r)
            if (m[.date] != nil || m[.started] != nil) && (m[.amount] != nil || (m[.debit] != nil && m[.credit] != nil)) { return (i, m) }
        }
        return nil
    }

    static func parse(_ text: String) throws -> Statement {
        // The delimiter that splits the header into the most known columns wins.
        var best: (rows: [[String]], h: Int, map: [Role: Int])?
        for sep in [";", ",", "\t"] as [Character] {
            let rows = split(text, sep)
            if let h = header(rows), h.map.count > (best?.map.count ?? 0) { best = (rows, h.index, h.map) }
        }
        guard let b = best else { throw StatementError(message: "Couldn't find the date and amount columns in this file.") }
        return parse(rows: b.rows, header: b.h, map: b.map, format: "CSV")
    }

    /// Rows of cells from a spreadsheet (Excel) or a split CSV.
    static func parse(rows: [[String]], format: String) throws -> Statement {
        guard let h = header(rows) else { throw StatementError(message: "Couldn't find the date and amount columns in this file.") }
        return parse(rows: rows, header: h.index, map: h.map, format: format)
    }

    private static func parse(rows: [[String]], header h: Int, map: [Role: Int], format: String) -> Statement {
        let b = (rows: rows, map: map)
        let header = b.rows[h]
        let normHeader = header.map { StatementParser.norm($0) }
        var st = Statement(format: format)
        st.bank = guessBank(normHeader)
        // Metadata lines above the header (ING, DKB) often carry the IBAN.
        for r in b.rows[..<h] {
            for c in r {
                let v = c.replacingOccurrences(of: " ", with: "").trimmed
                if st.iban.isEmpty, (15...34).contains(v.count), v.prefix(2).allSatisfy({ $0.isUppercase && $0.isLetter }),
                   v.dropFirst(2).prefix(2).allSatisfy(\.isNumber), v.allSatisfy({ $0.isLetter || $0.isNumber }) { st.iban = v }
            }
        }
        let m = b.map
        func cell(_ r: [String], _ role: Role) -> String { m[role].flatMap { $0 < r.count ? r[$0].trimmed : nil } ?? "" }
        for r in b.rows[(h + 1)...] {
            guard r.count >= max(2, header.count / 2) else { continue }
            let dateText = cell(r, .date).isEmpty ? cell(r, .started) : cell(r, .date)
            guard let d = StatementParser.day(dateText) ?? StatementParser.day(cell(r, .value)) else { continue }
            var c: Int?
            if m[.amount] != nil { c = StatementParser.cents(cell(r, .amount)) }
            else {
                let deb = StatementParser.cents(cell(r, .debit)).map { -abs($0) } ?? 0
                let cre = StatementParser.cents(cell(r, .credit)).map { abs($0) } ?? 0
                c = deb != 0 ? deb : cre != 0 ? cre : nil
            }
            guard let cents = c, cents != 0 else { continue }
            var payee = cell(r, .payee)
            if payee.isEmpty { payee = cents < 0 ? cell(r, .payeeOut) : cell(r, .payeeIn) }
            if payee.isEmpty { payee = cents < 0 ? cell(r, .payeeIn) : cell(r, .payeeOut) }
            let kind = cell(r, .kind)
            var purpose = cell(r, .purpose)
            if !kind.isEmpty && !purpose.lowercased().contains(kind.lowercased()) { purpose = purpose.isEmpty ? kind : "\(kind) \(purpose)" }
            var row = StatementRow(day: d.day, cents: cents, payee: payee, purpose: purpose)
            row.cur = cell(r, .currency).uppercased()
            if let s = StatementParser.day(cell(r, .started)), !s.time.isEmpty { row.time = "\(s.day)T\(s.time)" }
            else if !d.time.isEmpty { row.time = "\(d.day)T\(d.time)" }
            let status = StatementParser.norm(cell(r, .status))
            if ["pending", "vorgemerkt", "offen", "in bearbeitung"].contains(where: { status.contains($0) }) { row.status = .pending }
            else if ["revert", "declin", "fail", "storn", "abgelehnt", "cancel"].contains(where: { status.contains($0) }) { row.status = .reverted }
            row.balanceCents = StatementParser.cents(cell(r, .balance))
            if st.iban.isEmpty { let a = cell(r, .account).replacingOccurrences(of: " ", with: ""); if a.count >= 15 { st.iban = a } }
            st.rows.append(row)
            // Revolut books its fee as part of the payment; it becomes its own row.
            if let fee = StatementParser.cents(cell(r, .fee)), fee != 0 {
                var f = row
                f.cents = -abs(fee); f.payee = "\(st.bank.isEmpty ? "Bank" : st.bank) fee"; f.purpose = "Fee: \(payee)"; f.balanceCents = nil
                st.rows.append(f)
            }
        }
        // Closing balance: the running balance of the latest booked row, when the file has one.
        if let lastRow = st.rows.filter({ $0.status == .booked && $0.balanceCents != nil }).max(by: { ($0.day, $0.time) < ($1.day, $1.time) }),
           let bal = lastRow.balanceCents {
            // Files listed newest first carry the latest balance in their first row for that day.
            let sameDay = st.rows.filter { $0.day == lastRow.day && $0.balanceCents != nil && $0.status == .booked }
            let newestFirst = (st.rows.first?.day ?? "") > (st.rows.last?.day ?? "")
            st.closing = (lastRow.day, (newestFirst ? sameDay.first : sameDay.last)?.balanceCents ?? bal)
        }
        return st
    }

    static func guessBank(_ h: [String]) -> String {
        if h.contains("started date") && h.contains("product") { return "Revolut" }
        if h.contains("beguenstigter zahlungspflichtiger") { return "Sparkasse" }
        if h.contains("zahlungspflichtige r") || h.contains("zahlungsempfaenger in") { return "DKB" }
        if h.contains("auftraggeber empfaenger") { return "ING" }
        if h.contains("partner name") || h.contains("payee") && h.contains("amount eur") { return "N26" }
        return ""
    }
}

// ── camt.052 / camt.053 (ISO 20022 XML) ──
final class Camt: NSObject, XMLParserDelegate {
    private var st = Statement(format: "camt")
    private var path: [String] = []
    private var text = ""
    private var entry: [String: String] = [:]
    private var entryUstrd: [String] = []
    private var inEntry = false
    private var amountCcy = ""
    private var bal: [String: String] = [:]
    private var inBal = false

    static func parse(_ data: Data) throws -> Statement {
        let c = Camt()
        let p = XMLParser(data: data)
        p.delegate = c
        guard p.parse() else { throw StatementError(message: "This XML file couldn't be read.") }
        return c.st
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        path.append(name); text = ""
        if name == "Ntry" { inEntry = true; entry = [:]; entryUstrd = [] }
        if name == "Bal" { inBal = true; bal = [:] }
        if name == "Amt" { amountCcy = attributes["Ccy"] ?? "" }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let v = text.trimmed
        let p = path.joined(separator: "/")
        if inEntry {
            let parent = path.count >= 2 ? path[path.count - 2] : ""
            switch name {
            case "Amt" where parent == "Ntry": entry["amt"] = v; entry["ccy"] = amountCcy
            case "CdtDbtInd" where parent == "Ntry": entry["dir"] = v
            case "Cd" where p.hasSuffix("Sts/Cd"): entry["sts"] = v
            case "Sts" where !v.isEmpty: entry["sts"] = v
            case "Dt" where p.contains("BookgDt"): entry["book"] = v
            case "DtTm" where p.contains("BookgDt"): entry["book"] = v
            case "Dt" where p.contains("ValDt"): entry["val"] = v
            case "AcctSvcrRef" where !v.isEmpty: entry["ref"] = v
            case "NtryRef" where entry["ref"] == nil && !v.isEmpty: entry["ref"] = v
            case "Nm" where p.contains("RltdPties/Cdtr"): entry["cdtr"] = entry["cdtr"] ?? v
            case "Nm" where p.contains("RltdPties/Dbtr"): entry["dbtr"] = entry["dbtr"] ?? v
            case "Ustrd": entryUstrd.append(v)
            case "AddtlNtryInf": entry["info"] = v
            case "Ntry":
                inEntry = false
                finishEntry()
            default: break
            }
        } else if inBal {
            switch name {
            case "Cd" where p.contains("Tp"): bal["tp"] = v
            case "Amt": bal["amt"] = v
            case "CdtDbtInd": bal["dir"] = v
            case "Dt" where !v.isEmpty: bal["dt"] = v
            case "Bal":
                inBal = false
                if ["CLBD", "CLAV"].contains(bal["tp"] ?? ""), st.closing == nil || bal["tp"] == "CLBD",
                   let a = bal["amt"].flatMap(StatementParser.cents), let d = bal["dt"].flatMap(StatementParser.day) {
                    st.closing = (d.day, bal["dir"] == "DBIT" ? -abs(a) : abs(a))
                }
            default: break
            }
        } else if name == "IBAN" && p.contains("Acct/Id") && st.iban.isEmpty {
            st.iban = v
        } else if name == "Ccy" && p.contains("Acct") && st.currency.isEmpty {
            st.currency = v
        } else if name == "Nm" && p.contains("Svcr") && st.bank.isEmpty {
            st.bank = v
        }
        path.removeLast()
        text = ""
    }

    private func finishEntry() {
        guard let a = entry["amt"].flatMap({ Fmt.amount($0) }), let d = (entry["book"] ?? entry["val"]).flatMap(StatementParser.day) else { return }
        let out = entry["dir"] == "DBIT"
        let cents = Int((abs(a) * 100).rounded()) * (out ? -1 : 1)
        var r = StatementRow(day: d.day, cents: cents, payee: (out ? entry["cdtr"] : entry["dbtr"]) ?? "",
                             purpose: (entryUstrd.isEmpty ? [entry["info"] ?? ""] : entryUstrd).joined(separator: " ").trimmed)
        r.cur = entry["ccy"] ?? ""
        r.ref = entry["ref"] ?? ""
        let s = (entry["sts"] ?? "BOOK").uppercased()
        r.status = s == "PDNG" ? .pending : s == "BOOK" ? .booked : .booked
        if r.payee.isEmpty { r.payee = entry["info"] ?? "" }
        st.rows.append(r)
    }
}

// ── MT940 (SWIFT) ──
enum MT940 {
    private static let re61 = try! NSRegularExpression(pattern: #"^(\d{6})(\d{4})?(RC|RD|C|D)([A-Z])?([\d,]+)N([A-Z0-9]{3})([^/]*)(?://(.*))?"#)

    static func parse(_ text: String) throws -> Statement {
        var st = Statement(format: "MT940")
        // Join continuation lines to the tag they belong to.
        var fields: [(tag: String, value: String)] = []
        for raw in text.components(separatedBy: .newlines) {
            let l = raw.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix(":"), let end = l.dropFirst().firstIndex(of: ":") {
                fields.append((String(l[l.index(after: l.startIndex)..<end]), String(l[l.index(after: end)...])))
            } else if !l.isEmpty && l != "-" && !fields.isEmpty {
                fields[fields.count - 1].value += "\n" + l
            }
        }
        var current: StatementRow?
        func flush() { if let c = current { st.rows.append(c) }; current = nil }
        for f in fields {
            switch f.tag {
            case "25": st.iban = f.value.components(separatedBy: "/").last?.trimmed ?? ""
            case "61":
                flush()
                let v = f.value.replacingOccurrences(of: "\n", with: "")
                guard let m = re61.firstMatch(in: v, range: NSRange(v.startIndex..., in: v)) else { continue }
                func g(_ i: Int) -> String { Range(m.range(at: i), in: v).map { String(v[$0]) } ?? "" }
                let ds = g(1)
                guard let y = Int(ds.prefix(2)), let mo = Int(ds.dropFirst(2).prefix(2)), let d = Int(ds.suffix(2)),
                      let a = Fmt.amount(g(5)) else { continue }
                var day = CardMath.ymd(2000 + y, mo, d)
                if !g(2).isEmpty, let bm = Int(g(2).prefix(2)), let bd = Int(g(2).suffix(2)) {
                    // Booking date (MMDD) can fall into the next or previous year.
                    var by = 2000 + y
                    if bm == 1 && mo == 12 { by += 1 } else if bm == 12 && mo == 1 { by -= 1 }
                    day = CardMath.ymd(by, bm, bd)
                }
                let dir = g(3)
                let out = dir == "D" || dir == "RC"
                var r = StatementRow(day: day, cents: Int((a * 100).rounded()) * (out ? -1 : 1), payee: "", purpose: "")
                let ref = g(8).trimmed
                r.ref = ref.isEmpty || ref == "NONREF" ? "" : ref
                current = r
            case "86":
                guard current != nil else { continue }
                let (payee, purpose) = details86(f.value)
                current?.payee = payee; current?.purpose = purpose
            case "62F", "62M", "64":
                flush()
                if f.tag != "62M" || st.closing == nil {
                    let v = f.value
                    if v.count > 10, let y = Int(v.dropFirst().prefix(2)), let mo = Int(v.dropFirst(3).prefix(2)), let d = Int(v.dropFirst(5).prefix(2)),
                       let a = Fmt.amount(String(v.dropFirst(10))) {
                        if f.tag != "64" || st.closing == nil {
                            st.closing = (CardMath.ymd(2000 + y, mo, d), Int((a * 100).rounded()) * (v.hasPrefix("D") ? -1 : 1))
                        }
                        if st.currency.isEmpty { st.currency = String(v.dropFirst(7).prefix(3)) }
                    }
                }
            default: break
            }
        }
        flush()
        return st
    }

    /// German structured :86: ("166?00KARTENZAHLUNG?20…?32Name") → (payee, purpose).
    static func details86(_ raw: String) -> (String, String) {
        let v = raw.replacingOccurrences(of: "\n", with: "")
        guard v.contains("?") else { return ("", v.trimmed) }
        var fields: [String: String] = [:]
        for part in v.components(separatedBy: "?").dropFirst() where part.count >= 2 {
            let k = String(part.prefix(2))
            fields[k, default: ""] += String(part.dropFirst(2))
        }
        let payee = [fields["32"], fields["33"]].compactMap { $0 }.joined().trimmed
        // ?20–?29 and ?60–?63 are fixed-width pieces of one text, split mid-word: join them as they are.
        let purpose = ((20...29).compactMap { fields[String($0)] } + (60...63).compactMap { fields[String($0)] }).joined()
        let kind = fields["00"] ?? ""
        let text = [kind, purpose].filter { !$0.isEmpty }.joined(separator: " ").trimmed
        return (payee, text)
    }
}

// ── The plan: what importing this file into one account changes ──
struct StatementPlan {
    struct Insert { let id: String; let fp: String; let row: StatementRow }
    struct Merge { let txnId: String; let fp: String; let row: StatementRow; let captureId: String?; let reason: String; let kind: Fusion.Kind; let lag: Int }
    var inserts: [Insert] = []
    var merges: [Merge] = []            // Apple Pay taps and rows you typed that the file confirms
    var duplicates = 0                  // already imported
    var twins = 0                       // transfers you already have (e.g. a card bill paid from Sparkasse)
    var pending = 0, reverted = 0
    var orphanTaps: [String] = []       // Apple Pay taps inside the file's dates that it doesn't contain
    var notInSync: [StatementRow] = []  // bank-synced account: rows the sync doesn't have
    var crossCheck = false
    var foreign = false                 // the file's currency isn't yours
    var tapMerges: Int { merges.filter { $0.captureId != nil }.count }
    var typedMerges: Int { merges.filter { $0.captureId == nil }.count }

    /// One file row's identity: its bank reference if it has one, else the tuple, plus the
    /// occurrence number so two real 3,20 € coffees on the same day stay two rows.
    static func fingerprints(_ rows: [StatementRow]) -> [String] {
        var seen: [String: Int] = [:]
        return rows.map { r in
            let base = r.ref.isEmpty
                ? "\(r.day)|\(r.cents)|\(StatementParser.norm(r.payee))|\(String(StatementParser.norm(r.purpose).prefix(40)))|\(r.time)"
                : "ref:\(r.ref)|\(r.cents)"
            let n = seen[base, default: 0]; seen[base] = n + 1
            return "\(base)#\(n)"
        }
    }
    static func hash(_ s: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return String(h, radix: 16)
    }

    /// - Parameters:
    ///   - rows: the effective ledger (all accounts).
    ///   - stored: fingerprints already imported into this account.
    ///   - typed: rows on this account you typed yourself (not bank, not taps).
    ///   - taps: Apple Pay taps that became expenses on this account, with their transaction ids.
    static func make(_ st: Statement, account a: AccSnap, rows: [Row], stored: Set<String>, typed: [Row],
                     taps: [(Evidence, String)], memory: FusionMemory, home: String) -> StatementPlan {
        var plan = StatementPlan()
        plan.foreign = !st.currency.isEmpty && st.currency != home
        let fps = fingerprints(st.rows)
        var live: [(StatementRow, String)] = []
        for (r, fp) in zip(st.rows, fps) {
            if r.status == .pending { plan.pending += 1; continue }
            if r.status == .reverted { plan.reverted += 1; continue }
            if stored.contains(fp) { plan.duplicates += 1; continue }
            live.append((r, fp))
        }
        // Bank-synced account: compare only. The bank sync owns this balance.
        if a.isBank {
            plan.crossCheck = true
            var bank = rows.filter { $0.isBank && $0.accountId == a.id }
            for (r, _) in live {
                let want = abs(r.cents), out = r.cents < 0
                if let i = bank.indices.filter({ Fusion.cents(bank[$0].amount) == want && (bank[$0].isOut || bank[$0].type == "transfer") == out
                    && abs(CardMath.daysBetween(bank[$0].date, r.day)) <= 3 })
                    .min(by: { abs(CardMath.daysBetween(bank[$0].date, r.day)) < abs(CardMath.daysBetween(bank[$1].date, r.day)) }) {
                    bank.remove(at: i)
                } else { plan.notInSync.append(r) }
            }
            return plan
        }
        // Transfers you already have: a card bill paid from another account shows up on the
        // card's statement too ("Zahlung erhalten"). Link it, don't add it.
        var transfers = rows.filter { $0.type == "transfer" && ($0.toAccountId == a.id || $0.accountId == a.id) }
        live = live.filter { (r, _) in
            let inbound = r.cents > 0
            if let i = transfers.indices.first(where: { t in
                Fusion.cents(transfers[t].amount) == abs(r.cents)
                    && (inbound ? transfers[t].toAccountId == a.id : transfers[t].accountId == a.id)
                    && abs(CardMath.daysBetween(transfers[t].date, r.day)) <= 7 }) {
                transfers.remove(at: i); plan.twins += 1; return false
            }
            return true
        }
        // Apple Pay taps settle into the file's rows (tips, holds and FX allowed).
        let outRows: [Row] = live.enumerated().compactMap { i, x in
            let (r, _) = x
            guard r.cents < 0 else { return nil }
            return Row(id: "f\(i)", type: "expense", rawType: "expense", amount: Double(-r.cents) / 100, merchant: r.payee,
                       categoryId: "other", rawCategoryId: "other", accountId: a.id, toAccountId: "",
                       notes: [r.purpose, r.time].filter { !$0.isEmpty }.joined(separator: " "),
                       date: r.day, isBank: true)
        }
        var used = Set<Int>()
        if let first = st.first, let last = st.last {
            let inRange = taps.filter { $0.0.day >= CardMath.addDays(first, -1) }
            let ev = inRange.map { e, _ in var x = e; x.accountId = a.id; return x }
            let o = Fusion.run(evidence: ev, rows: outRows, taken: [], feedAccounts: [a.id], coverage: [a.id: last], memory: memory, home: home)
            let txnOf = Dictionary(uniqueKeysWithValues: inRange.map { ($0.0.id, $0.1) })
            for l in o.settle + o.ask {
                guard let i = Int(l.bankId.dropFirst()), let txn = txnOf[l.evidenceId] else { continue }
                used.insert(i)
                plan.merges.append(Merge(txnId: txn, fp: live[i].1, row: live[i].0, captureId: l.evidenceId, reason: l.reason, kind: l.kind, lag: l.lag))
            }
            plan.orphanTaps = o.orphans
        }
        // Rows you typed: the same amount and direction within 4 days.
        var pool = typed.filter { $0.accountId == a.id && ($0.isOut || $0.isIn) }
        for (i, x) in live.enumerated() where !used.contains(i) {
            let (r, fp) = x
            let out = r.cents < 0
            if let j = pool.indices.filter({ Fusion.cents(pool[$0].amount) == abs(r.cents) && pool[$0].isOut == out
                && abs(CardMath.daysBetween(pool[$0].date, r.day)) <= 4 })
                .min(by: { abs(CardMath.daysBetween(pool[$0].date, r.day)) < abs(CardMath.daysBetween(pool[$1].date, r.day)) }) {
                plan.merges.append(Merge(txnId: pool[j].id, fp: fp, row: r, captureId: nil, reason: "Matches a row you added", kind: .exact,
                                         lag: CardMath.daysBetween(pool[j].date, r.day)))
                pool.remove(at: j); used.insert(i)
                continue
            }
            plan.inserts.append(Insert(id: "st-" + hash("\(a.id)|\(fp)"), fp: fp, row: r))
        }
        return plan
    }
}

extension Ledger {
    /// Balance of an account at the end of a day (for checking against a statement).
    func balance(of a: AccSnap, on day: String) -> Double {
        var b = a.ib
        for t in rows where t.date <= day && CardMath.countsFor(a, t.date) {
            if t.isIn && t.accountId == a.id { b += t.amount }
            if (t.isOut || t.type == "transfer") && t.accountId == a.id { b -= t.amount }
            if t.type == "transfer" && t.toAccountId == a.id { b += t.amount }
        }
        return b
    }
}
