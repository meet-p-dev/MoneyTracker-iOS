import Foundation
import Compression

// A small reader for Excel (.xlsx) statements: an .xlsx is a ZIP of XML files. It returns the
// cells of the sheet with the most rows, as text, for the CSV column mapper. No formulas, no
// styles: numbers come back as plain numbers, dates as Excel serial numbers (see
// StatementParser.day).
enum XLSX {
    static func rows(_ data: Data) throws -> [[String]] {
        let files = try Zip.entries(data)
        let shared = files["xl/sharedStrings.xml"].map(Shared.parse) ?? []
        var best: [[String]] = []
        for name in files.keys.sorted() where name.hasPrefix("xl/worksheets/sheet") && name.hasSuffix(".xml") {
            let r = Sheet.parse(files[name]!, shared)
            if r.count > best.count { best = r }
        }
        guard !best.isEmpty else { throw StatementError(message: "This Excel file has no rows.") }
        return best
    }

    /// Excel numbers as text: amounts with two decimals, anything finer (a date with a time) as is.
    static func number(_ s: String) -> String {
        guard let v = Double(s) else { return s }
        let r = (v * 100).rounded() / 100
        return abs(v - r) < 1e-7 ? String(format: "%.2f", r) : s
    }

    private final class Shared: NSObject, XMLParserDelegate {
        var out: [String] = [], cur = "", text = "", inT = false
        static func parse(_ d: Data) -> [String] {
            let s = Shared(); let p = XMLParser(data: d); p.delegate = s; p.parse(); return s.out
        }
        func parser(_ p: XMLParser, didStartElement n: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            if n == "si" { cur = "" }
            if n == "t" { inT = true; text = "" }
        }
        func parser(_ p: XMLParser, foundCharacters s: String) { if inT { text += s } }
        func parser(_ p: XMLParser, didEndElement n: String, namespaceURI: String?, qualifiedName: String?) {
            if n == "t" { cur += text; inT = false }
            if n == "si" { out.append(cur) }
        }
    }

    private final class Sheet: NSObject, XMLParserDelegate {
        let shared: [String]
        var rows: [[String]] = [], row: [String] = []
        var col = 0, type = "", value = "", inV = false
        init(_ s: [String]) { shared = s }
        static func parse(_ d: Data, _ shared: [String]) -> [[String]] {
            let s = Sheet(shared); let p = XMLParser(data: d); p.delegate = s; p.parse(); return s.rows
        }
        /// "C12" → 2
        static func column(_ ref: String) -> Int {
            var n = 0
            for ch in ref.uppercased() { guard let a = ch.asciiValue, a >= 65, a <= 90 else { break }; n = n * 26 + Int(a - 64) }
            return max(n - 1, 0)
        }
        func parser(_ p: XMLParser, didStartElement n: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
            switch n {
            case "row": row = []
            case "c": col = a["r"].map(Sheet.column) ?? row.count; type = a["t"] ?? ""; value = ""
            case "v", "t": inV = true
            default: break
            }
        }
        func parser(_ p: XMLParser, foundCharacters s: String) { if inV { value += s } }
        func parser(_ p: XMLParser, didEndElement n: String, namespaceURI: String?, qualifiedName: String?) {
            switch n {
            case "v", "t": inV = false
            case "c":
                var text = value
                if type == "s", let i = Int(value), i < shared.count { text = shared[i] }
                else if type.isEmpty || type == "n" { text = XLSX.number(value) }
                while row.count < col { row.append("") }
                if row.count == col { row.append(text) } else if col < row.count { row[col] = text }
            case "row": if row.contains(where: { !$0.trimmed.isEmpty }) { rows.append(row) }
            default: break
            }
        }
    }
}

/// Just enough ZIP to open .xlsx files: the central directory, stored and deflated entries.
enum Zip {
    static func entries(_ data: Data) throws -> [String: Data] {
        let b = [UInt8](data)
        func u16(_ o: Int) -> Int { o + 1 < b.count ? Int(b[o]) | Int(b[o + 1]) << 8 : 0 }
        func u32(_ o: Int) -> Int { o + 3 < b.count ? u16(o) | u16(o + 2) << 16 : 0 }
        let bad = StatementError(message: "This Excel file couldn't be opened.")
        // End of central directory: the last "PK\u{5}\u{6}".
        guard b.count > 22, let eocd = stride(from: b.count - 22, through: max(0, b.count - 65_557), by: -1)
            .first(where: { u32($0) == 0x0605_4b50 }) else { throw bad }
        let count = u16(eocd + 10)
        var o = u32(eocd + 16)
        var out: [String: Data] = [:]
        for _ in 0..<count {
            guard u32(o) == 0x0201_4b50 else { throw bad }
            let method = u16(o + 10), csize = u32(o + 20), usize = u32(o + 24)
            let nlen = u16(o + 28), elen = u16(o + 30), clen = u16(o + 32), local = u32(o + 42)
            let name = String(decoding: b[(o + 46)..<min(o + 46 + nlen, b.count)], as: UTF8.self)
            o += 46 + nlen + elen + clen
            guard name.hasSuffix(".xml"), u32(local) == 0x0403_4b50 else { continue }
            let start = local + 30 + u16(local + 26) + u16(local + 28)
            guard start + csize <= b.count else { throw bad }
            let raw = Array(b[start..<(start + csize)])
            if method == 0 { out[name] = Data(raw) }
            else if method == 8, usize > 0, usize < 200_000_000 {
                var dst = [UInt8](repeating: 0, count: usize)
                let n = compression_decode_buffer(&dst, usize, raw, raw.count, nil, COMPRESSION_ZLIB)
                if n > 0 { out[name] = Data(dst[0..<n]) }
            }
        }
        return out
    }
}
