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
        Page(icon: "chart.bar.fill", tint: .mtAcc, title: "Welcome to MoneyTrack",
             body: "Keep track of your balance, spending and budgets in one place."),
        Page(icon: "wallet.bifold.fill", tint: .mtGreen, title: "Accounts",
             body: "Connect your bank to import your accounts and transactions three times a day. Add cash and cards yourself."),
        Page(icon: "arrow.left.arrow.right", tint: .orange, title: "Transactions",
             body: "Each transaction has one of five types:",
             bullets: [("arrow.up.right", "Expense: money you spent", .mtRed), ("arrow.down.left", "Income: money you earned", .mtGreen),
                       ("arrow.triangle.2.circlepath", "Received: refunds and paybacks", .mtRecv),
                       ("arrow.left.arrow.right", "Sent out: money out that isn't spending", .gray),
                       ("arrow.left.arrow.right.circle", "Transfer: between your own accounts", .mtAcc)]),
        Page(icon: "chart.pie.fill", tint: .purple, title: "Insights",
             body: "Spending by category and month, budgets and a calendar. Tap any number to see its transactions."),
        Page(icon: "creditcard.fill", tint: .mtRecv, title: "Wallet",
             body: "Credit cards with their bills and due dates, money you owe, and savings goals."),
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
                    Text("Continue").font(.system(size: 17, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 8)
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
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(p.tint)
                .frame(width: 64, height: 64)
                .overlay(Image(systemName: p.icon).font(.system(size: 28, weight: .semibold)).foregroundStyle(.white))
            Text(p.title).font(.system(size: 28, weight: .bold)).kerning(-0.4)
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
            Text("How do you want to start?").font(.system(size: 28, weight: .bold)).kerning(-0.4)
            Text("You can change any of this later.").font(.system(size: 16)).foregroundStyle(Color.mtTxt2).padding(.bottom, 6)
            choice("building.columns.fill", .mtAcc, "Connect my bank", "Import transactions automatically") { onFinish(.bank) }
            choice("wallet.bifold.fill", .mtGreen, "Add an account", "Cash, a card or anything else") { onFinish(.account) }
            choice("square.and.arrow.down.fill", .purple, "Restore a backup", "Bring over data from the web app") { onFinish(.backup) }
            choice("questionmark.circle.fill", .orange, "How MoneyTrack works", "A quick overview") { onFinish(.howItWorks) }
            Button("Skip for now") { onFinish(nil) }.font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity).padding(.top, 6)
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
