import SwiftUI
import UIKit

// Money/date formatting lives in Core/Fmt.swift; balance math in Core/Ledger.swift.

extension Color {
    init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
    func toHex() -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

enum Haptic {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

// Web symbol keys (lib/icons.jsx) → SF Symbols, so built-in categories and goals look the
// same in both apps. Custom categories keep their emoji.
enum Symbols {
    static let sf: [String: String] = [
        "cart": "cart.fill", "food": "fork.knife", "phone": "iphone", "car": "car.fill", "bag": "bag.fill",
        "heart": "heart.fill", "play": "gamecontroller.fill", "brief": "briefcase.fill", "laptop": "laptopcomputer",
        "house": "house.fill", "swap": "arrow.left.arrow.right", "repeat": "arrow.triangle.2.circlepath",
        "undo": "arrow.uturn.backward", "scale": "scalemass.fill", "box": "shippingbox.fill",
        "goal": "target", "plane": "airplane", "grad": "graduationcap.fill", "gem": "diamond.fill",
        "beach": "beach.umbrella.fill", "gift": "gift.fill", "pill": "pills.fill", "paw": "pawprint.fill",
        "wallet": "wallet.bifold.fill", "card": "creditcard.fill",
    ]
    static let goalKeys = ["goal", "plane", "house", "grad", "car", "laptop", "play", "gem", "beach", "gift", "pill", "paw"]
    static func name(_ key: String) -> String? { sf[key] }
}

struct CatGlyph: View {
    let cat: TxCategory?
    var size: CGFloat = 16
    var body: some View {
        let key = (cat?.sym.isEmpty ?? true) ? BackupService.builtInSym(cat?.id ?? "") : (cat?.sym ?? "")
        if let n = Symbols.name(key) {
            Image(systemName: n).font(.system(size: size, weight: .semibold))
                .foregroundStyle(Color(hex: cat?.colorHex ?? "#9ca3af"))
        } else {
            Text(cat?.icon ?? "📦").font(.system(size: size + 2))
        }
    }
}

struct GoalGlyph: View {
    let goal: Goal
    var size: CGFloat = 20
    var body: some View {
        let key = goal.sym.isEmpty ? BackupService.goalSym(forEmoji: goal.icon) : goal.sym
        if let n = Symbols.name(key) {
            Image(systemName: n).font(.system(size: size, weight: .semibold)).foregroundStyle(Color(hex: goal.colorHex))
        } else {
            Text(goal.icon).font(.system(size: size + 2))
        }
    }
}

/// Amber "this account counts old entries twice" row with a Fix button (web V11.8).
struct IssueBanner: View {
    let issue: Ledger.Issue
    let onFix: () -> Void
    var body: some View {
        let card = issue.acc.isCredit
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(issue.acc.name) counts \(issue.n) old \(issue.n == 1 ? "entry" : "entries") twice")
                    .font(.subheadline.weight(.semibold))
                Text(card ? "Should owe \(Fmt.money(max(-issue.fixed, 0))), not \(Fmt.money(max(-issue.now, 0)))"
                          : "Should be \(Fmt.money(issue.fixed)), not \(Fmt.money(issue.now))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Fix", action: onFix).buttonStyle(.borderedProminent).tint(.orange).controlSize(.small)
        }
    }
}
