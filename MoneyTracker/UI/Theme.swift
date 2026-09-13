import SwiftUI
import UIKit

// The web app's design tokens (lib/constants.js LT/DK) as adaptive colors, plus the V11
// shape system: 20 for cards, 12 for things inside them, capsules for pills. Content sits
// on solid cards like the web app; Liquid Glass is used where iOS 26 uses it — the tab bar,
// toolbars, sheets and floating buttons.
extension Color {
    init(light: String, dark: String) {
        let l = UIColor(Color(hex: light)), d = UIColor(Color(hex: dark))
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? d : l })
    }
    static let mtBg = Color(light: "#f4f2ee", dark: "#000000")
    static let mtCard = Color(light: "#ffffff", dark: "#161618")
    static let mtCardH = Color(light: "#f6f4f0", dark: "#232326")
    static let mtBorder = Color(light: "#e7e4dd", dark: "#2e2e32")
    static let mtTxt2 = Color(light: "#6b7280", dark: "#8e8e93")
    static let mtTxt3 = Color(light: "#aeaeb2", dark: "#55555a")
    static let mtAcc = Color(light: "#007aff", dark: "#0a84ff")
    static let mtGreen = Color(light: "#34c759", dark: "#30d158")
    static let mtAmber = Color(light: "#ff9f0a", dark: "#ffd60a")
    static let mtRed = Color(light: "#ff3b30", dark: "#ff453a")
    static let mtRecv = Color(light: "#0d9488", dark: "#2dd4bf")
}

enum MT {
    static let card: CGFloat = 20
    static let inner: CGFloat = 12
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.82)
}

struct CardSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var padding: CGFloat?
    func body(content: Content) -> some View {
        content
            .padding(padding ?? 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.mtCard, in: RoundedRectangle(cornerRadius: MT.card, style: .continuous))
            .shadow(color: scheme == .dark ? .clear : Color.black.opacity(0.05), radius: 10, x: 0, y: 3)
    }
}

extension View {
    /// A web-style card: solid surface, 20pt continuous corners, soft shadow in light mode.
    func mtCard(padding: CGFloat? = 14) -> some View { modifier(CardSurface(padding: padding)) }
    /// The screen canvas behind the cards.
    func mtCanvas() -> some View { background(Color.mtBg.ignoresSafeArea()) }
}

/// Pressable rows and tiles: a quick spring shrink, like the web's .mt-tap.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
extension ButtonStyle where Self == PressStyle { static var press: PressStyle { PressStyle() } }

/// The small uppercase caption above a section (web .mt-label), with an optional action.
struct SectionLabel: View {
    let text: String
    var action: String? = nil
    var onAction: (() -> Void)? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text.uppercased()).font(.system(size: 11, weight: .semibold)).kerning(1.1).foregroundStyle(Color.mtTxt3)
            Spacer()
            if let action, let onAction {
                Button(action, action: onAction).font(.caption.weight(.semibold)).foregroundStyle(Color.mtAcc)
            }
        }
        .padding(.horizontal, 4).padding(.top, 8)
    }
}

/// Money in the web's style: tabular digits so columns line up.
extension Text {
    func money(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Text {
        self.font(.system(size: size, weight: weight)).monospacedDigit()
    }
}
