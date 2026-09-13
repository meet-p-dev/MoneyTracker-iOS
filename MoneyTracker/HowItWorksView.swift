import SwiftUI

// "How MoneyTrack works" — the whole app on one screen: where money comes from, what the
// app does with it, and where you see the result. Every box takes you there.
struct HowItWorksView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    Text("How money moves through the app. Tap a section to open it.")
                        .font(.system(size: 14)).foregroundStyle(Color.mtTxt2).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 14)
                    node("building.columns.fill", .mtAcc, "Your bank", "With bank sync on, new transactions arrive three times a day.") {
                        router.goWallet("accounts")
                    }
                    arrow("")
                    node("wallet.bifold.fill", .mtGreen, "Accounts", "Bank accounts come from bank sync. Cash and cards you add yourself, with a starting balance and date.") {
                        router.goWallet("accounts")
                    }
                    arrow("")
                    VStack(alignment: .leading, spacing: 10) {
                        header("list.bullet", .orange, "Transaction")
                        kind("arrow.up.right", .mtRed, "Expense", "counts as spending")
                        kind("arrow.down.left", .mtGreen, "Income", "salary and other earnings")
                        kind("arrow.triangle.2.circlepath", .mtRecv, "Received", "refunds and paybacks")
                        kind("arrow.left.arrow.right", .gray, "Sent out", "money out that isn't spending")
                        kind("arrow.left.arrow.right.circle", .mtAcc, "Transfer", "between your own accounts")
                        goButton { router.goActivity() }
                    }
                    .mtCard(padding: 16)
                    arrow("")
                    node("chart.pie.fill", .purple, "Insights & budgets", "Spending by category and month, budgets and a calendar. Tap a number to see its transactions.") {
                        router.goInsights("spend")
                    }
                    arrow("")
                    node("creditcard.fill", .mtRecv, "Credit cards", "Card purchases add to what you owe. Paying the bill from your bank is a transfer to the card, and the app matches it for you.") {
                        router.goWallet("accounts")
                    }
                    arrow("")
                    node("tray.full.fill", .mtAcc, "Review & learning", "When the app isn't sure what incoming money is, it asks once and remembers the answer for that payee.") {
                        router.tab = .home
                    }
                    arrow("")
                    node("house.fill", .mtAcc, "Home", "Your accounts minus what your cards owe, plus anything that needs attention and your month so far.") {
                        router.tab = .home
                    }
                    Divider().padding(.vertical, 20)
                    node("target", .pink, "Debts & goals", "Money you owe people and what you're saving for, both in Wallet.") {
                        router.goWallet("goals")
                    }
                }
                .padding(16)
            }
            .mtCanvas()
            .navigationTitle("How MoneyTrack works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func header(_ icon: String, _ tint: Color, _ title: String) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: MT.inner, style: .continuous).fill(tint.opacity(0.15)).frame(width: 42, height: 42)
                .overlay(Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(tint))
            Text(title).font(.system(size: 17, weight: .bold))
        }
    }
    private func node(_ icon: String, _ tint: Color, _ title: String, _ text: String, go: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header(icon, tint, title)
            Text(text).font(.system(size: 14)).foregroundStyle(Color.mtTxt2)
            goButton(go)
        }
        .mtCard(padding: 16)
    }
    private func kind(_ icon: String, _ tint: Color, _ name: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Circle().fill(tint.opacity(0.16)).frame(width: 28, height: 28)
                .overlay(Image(systemName: icon).font(.system(size: 12, weight: .bold)).foregroundStyle(tint))
            Text(name).font(.system(size: 14, weight: .semibold)) + Text("  \(text)").font(.system(size: 14)).foregroundStyle(Color.mtTxt2)
        }
    }
    private func goButton(_ go: @escaping () -> Void) -> some View {
        Button { Haptic.tap(); go(); router.showProfile = false; dismiss() } label: {
            Text("Open").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.mtAcc)
        }
        .buttonStyle(.plain)
    }
    private func arrow(_ label: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: "arrow.down").font(.system(size: 15, weight: .bold)).foregroundStyle(Color.mtTxt3)
            if !label.isEmpty { Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.mtTxt3) }
        }
        .padding(.vertical, 8)
    }
}
