import Foundation

// Decodes the web app's backup JSON (Settings → Export) exactly — every field of web V11.8
// (format "2.6"). Numbers are accepted as numbers or strings (form inputs), and any field
// may be missing (older backups), so every property is optional.

struct Flex: Codable {
    let value: Double
    init(_ v: Double) { value = v }
    init(from d: Decoder) throws {
        let c = try d.singleValueContainer()
        if let v = try? c.decode(Double.self) { value = v }
        else if let s = try? c.decode(String.self) { value = Fmt.amount(s) ?? 0 }
        else { value = 0 }
    }
    func encode(to e: Encoder) throws { var c = e.singleValueContainer(); try c.encode(value) }
}
struct FlexInt: Codable {
    let value: Int
    init(from d: Decoder) throws {
        let c = try d.singleValueContainer()
        if let v = try? c.decode(Int.self) { value = v }
        else if let v = try? c.decode(Double.self) { value = Int(v) }
        else if let s = try? c.decode(String.self) { value = Int(s) ?? 0 }
        else { value = 0 }
    }
    func encode(to e: Encoder) throws { var c = e.singleValueContainer(); try c.encode(value) }
}
struct FlexBool: Codable {
    let value: Bool
    init(from d: Decoder) throws {
        let c = try d.singleValueContainer()
        if let v = try? c.decode(Bool.self) { value = v }
        else if let v = try? c.decode(Double.self) { value = v != 0 }
        else if let s = try? c.decode(String.self) { value = s == "true" || s == "1" }
        else { value = false }
    }
    func encode(to e: Encoder) throws { var c = e.singleValueContainer(); try c.encode(value) }
}

struct WebBackup: Decodable {
    var accs: [WAccount]?
    var cats: [WCategory]?
    var txs: [WTxn]?
    var goals: [WGoal]?
    var debts: [WDebt]?
    var budgets: [String: Flex]?
    var currency: String?
    var payeeStats: [String: JSONValue]?
    var txDecisions: [String: JSONValue]?
    var shareOverrides: [String: Flex]?
    var ownerName: String?
    var exportedAt: String?
    var version: String?
}

struct WAccount: Decodable {
    var id: String; var name: String?; var color: String?; var ib: Flex?
    var kind: String?; var creditLimit: Flex?; var statementDay: FlexInt?; var dueDay: FlexInt?; var apr: Flex?
    var payFromId: String?; var autopay: FlexBool?; var billPayee: String?; var ibDate: String?; var lastAutopay: String?
    var bank: FlexBool?
    enum CodingKeys: String, CodingKey {
        case id, name, color, ib, kind, creditLimit, statementDay, dueDay, apr, payFromId, autopay, billPayee, ibDate, lastAutopay
        case bank = "_bank"
    }
    var snap: AccSnap {
        AccSnap(id: id, name: name ?? "Account", colorHex: color ?? "#3b82f6", ib: ib?.value ?? 0,
                kind: kind == "credit" ? "credit" : "cash", creditLimit: creditLimit?.value ?? 0,
                statementDay: statementDay?.value ?? 1, dueDay: dueDay?.value ?? 1, apr: apr?.value ?? 0,
                payFromId: payFromId ?? "", autopay: autopay?.value ?? false, billPayee: billPayee ?? "",
                ibDate: ibDate ?? "", isBank: bank?.value ?? id.hasPrefix("sb-"))
    }
}
struct WCategory: Decodable { var id: String; var label: String?; var icon: String?; var sym: String?; var color: String? }
struct WTxn: Decodable {
    var id: String; var type: String; var amount: Flex; var merchant: String?; var category: String?
    var accountId: String?; var toAccountId: String?; var notes: String?; var date: String
    var isSplit: FlexBool?; var splitPeople: FlexInt?; var splitSettled: FlexBool?; var bank: FlexBool?
    enum CodingKeys: String, CodingKey {
        case id, type, amount, merchant, category, accountId, toAccountId, notes, date, isSplit, splitPeople, splitSettled
        case bank = "_bank"
    }
    var isBank: Bool { bank?.value ?? id.hasPrefix("sb-") }
    var row: Row {
        Row(id: id, type: type, rawType: type, amount: amount.value, merchant: merchant ?? "",
            categoryId: category ?? "other", rawCategoryId: category ?? "other",
            accountId: accountId ?? "", toAccountId: toAccountId ?? "", notes: notes ?? "",
            date: String(date.prefix(10)), isBank: isBank)
    }
}
struct WGoal: Decodable { var id: String; var name: String?; var targetAmount: Flex?; var savedAmount: Flex?; var icon: String?; var sym: String?; var color: String? }
struct WDebt: Decodable {
    var id: String; var personName: String?; var totalAmount: Flex?; var paidBack: Flex?; var settled: FlexBool?
    var date: String?; var description: String?; var color: String?; var receivedInAccount: String?
}
