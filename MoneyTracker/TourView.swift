import SwiftUI

// The welcome tour: the whole idea of the app in five screens, then one question —
// how do you want to start? Shown on a brand-new install; Settings can replay it.
enum TourAction: String, Identifiable {
    case bank, account, backup, howItWorks
    var id: String { rawValue }
}

struct TourView: View {
    let onFinish: (TourAction?) -> Void
    @State private var page = 0

    private struct Page { let icon: String; let tint: Color; let title: String; let body: String; var bullets: [(String, String, Color)] = [] }
    private let pages: [Page] = [
        Page(icon: "sparkles", tint: .mtAcc, title: "Welcome to MoneyTrack",
             body: "See where your money is, where it goes, and how much is safe to spend — all in one place."),
        Page(icon: "wallet.bifold.fill", tint: .mtGreen, title: "Accounts hold your money",
             body: "Connect your bank and its accounts arrive with every transaction, updated 3× a day. Cash, cards and anything else you add by hand."),
        Page(icon: "arrow.left.arrow.right", tint: .orange, title: "Transactions move it",
             body: "Every move of money is one of five kinds:",
             bullets: [("arrow.up.right", "Expense — you spent it", .mtRed), ("arrow.down.left", "Income — you earned it", .mtGreen),
                       ("arrow.triangle.2.circlepath", "Received — money back (refunds, friends)", .mtRecv),
                       ("arrow.left.arrow.right", "Sent out — money out that isn't spending", .gray),
                       ("arrow.left.arrow.right.circle", "Transfer — between your own accounts, like paying your card", .mtAcc)]),
        Page(icon: "chart.pie.fill", tint: .purple, title: "Insights show where it goes",
             body: "Spending by category and month, budgets, and a calendar. Tap any number to see the transactions behind it."),
        Page(icon: "creditcard.fill", tint: .mtRecv, title: "Wallet keeps the rest",
             body: "Credit cards with their bill and due date, money you owe people, and your savings goals."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if page < pages.count { Button("Skip") { onFinish(nil) }.font(.system(size: 16, weight: .semibold)).padding(.horizontal, 20).padding(.top, 8) }
            }
            .frame(height: 44)
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in pageView(pages[i]).tag(i) }
                setupPage.tag(pages.count)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            HStack(spacing: 7) {
                ForEach(0...pages.count, id: \.self) { i in
                    Capsule().fill(i == page ? Color.mtAcc : Color.mtBorder).frame(width: i == page ? 22 : 7, height: 7)
                }
            }
            .animation(MT.spring, value: page)
            .padding(.vertical, 16)
            if page < pages.count {
                Button { withAnimation(MT.spring) { page += 1 } } label: {
                    Text(page == 0 ? "Show me around" : "Next").font(.system(size: 17, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .padding(.horizontal, 24).padding(.bottom, 20)
            } else {
                Color.clear.frame(height: 20)
            }
        }
        .mtCanvas()
    }

    private func pageView(_ p: Page) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 20)
            Circle().fill(LinearGradient(colors: [p.tint.opacity(0.9), p.tint], startPoint: .top, endPoint: .bottom))
                .frame(width: 96, height: 96)
                .overlay(Image(systemName: p.icon).font(.system(size: 42, weight: .semibold)).foregroundStyle(.white).symbolEffect(.bounce, value: page))
                .shadow(color: p.tint.opacity(0.35), radius: 18, y: 8)
            Text(p.title).font(.system(size: 30, weight: .heavy)).kerning(-0.6)
            Text(p.body).font(.system(size: 17)).foregroundStyle(Color.mtTxt2)
            if !p.bullets.isEmpty {
                VStack(alignment: .leading, spacing: 11) {
                    ForEach(p.bullets, id: \.1) { b in
                        HStack(spacing: 12) {
                            Circle().fill(b.2.opacity(0.16)).frame(width: 34, height: 34)
                                .overlay(Image(systemName: b.0).font(.system(size: 14, weight: .bold)).foregroundStyle(b.2))
                            Text(b.1).font(.system(size: 15))
                        }
                    }
                }
                .mtCard(padding: 16)
            }
            Spacer(minLength: 20)
        }
        .padding(.horizontal, 26)
    }

    private var setupPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer(minLength: 10)
            Text("How do you want to start?").font(.system(size: 28, weight: .heavy)).kerning(-0.5)
            Text("You can change any of this later.").font(.system(size: 16)).foregroundStyle(Color.mtTxt2).padding(.bottom, 6)
            choice("building.columns.fill", .mtAcc, "Connect my bank", "Your real accounts and transactions, 3× a day") { onFinish(.bank) }
            choice("wallet.bifold.fill", .mtGreen, "Add an account by hand", "Cash, a card, anything without a bank feed") { onFinish(.account) }
            choice("square.and.arrow.down.fill", .purple, "Restore a backup", "Bring your data from the web app") { onFinish(.backup) }
            choice("point.3.connected.trianglepath.dotted", .orange, "See how it all connects", "A one-screen map of the app") { onFinish(.howItWorks) }
            Button("I'll look around first") { onFinish(nil) }.font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity).padding(.top, 6)
            Spacer(minLength: 10)
        }
        .padding(.horizontal, 24)
    }

    private func choice(_ icon: String, _ tint: Color, _ title: String, _ sub: String, action: @escaping () -> Void) -> some View {
        Button(action: { Haptic.tap(); action() }) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: MT.inner, style: .continuous).fill(tint.opacity(0.15)).frame(width: 46, height: 46)
                    .overlay(Image(systemName: icon).font(.system(size: 19, weight: .semibold)).foregroundStyle(tint))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16, weight: .semibold))
                    Text(sub).font(.system(size: 13)).foregroundStyle(Color.mtTxt2)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.mtTxt3)
            }
            .foregroundStyle(.primary)
            .mtCard()
        }
        .buttonStyle(.press)
    }
}
