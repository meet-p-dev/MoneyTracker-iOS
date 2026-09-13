import Foundation

// The web app's text patterns were written — and tuned on real bank data — against
// JavaScript regex rules. Two differences from Apple's (ICU) engine matter:
//  · JS `\b` is ASCII-only (a "word" char is [A-Za-z0-9_]); ICU's is Unicode-aware. So JS
//    never sees a boundary before "Ü" in "Überweisung", while ICU does.
// To classify exactly like the web app, `\b` is rewritten into the JS definition.
enum JSRegex {
    static let boundary = "(?:(?<=[A-Za-z0-9_])(?![A-Za-z0-9_])|(?<![A-Za-z0-9_])(?=[A-Za-z0-9_]))"
    static func make(_ pattern: String, caseInsensitive: Bool = true) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern.replacingOccurrences(of: #"\b"#, with: boundary),
                                 options: caseInsensitive ? [.caseInsensitive] : [])
    }
    static func test(_ r: NSRegularExpression, _ s: String) -> Bool {
        r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }
}
