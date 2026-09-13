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
                    Text("Money comes in at the top and flows down. Tap any box to go there.")
                        .font(.system(size: 14)).foregroundStyle(Color.mtTxt2).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 14)
                    node("building.columns.fill", .mtAcc, "Your bank", "Signed in to bank sync, your bank sends every booked transaction 3× a day. Nothing to type.") {
                        router.goWallet("accounts")
                    }
                    arrow("fills")
                    node("wallet.bifold.fill", .mtGreen, "Accounts", "Where money lives. Bank accounts come from your bank; cash and cards are the ones you add, each with a starting balance and date.") {
                        router.goWallet("accounts")
                    }
                    arrow("every move of money is a")
                    VStack(alignment: .leading, spacing: 10) {
                        header("list.bullet", .orange, "Transaction")
                        kind("arrow.up.right", .mtRed, "Expense", "you spent it — counts in spending")
                        kind("arrow.down.left", .mtGreen, "Income", "you earned it — counts as income")
                        kind("arrow.triangle.2.circlepath", .mtRecv, "Received", "money back — not income")
                        kind("arrow.left.arrow.right", .gray, "Sent out", "money out that isn't spending")
                        kind("arrow.left.arrow.right.circle", .mtAcc, "Transfer", "between your accounts — e.g. paying your card")
                        goButton { router.goActivity() }
                    }
                    .mtCard(padding: 16)
                    arrow("which feed")
                    node("chart.pie.fill", .purple, "Insights & budgets", "Spending by category and month, budget limits, a calendar. Every number opens the transactions behind it.") {
                        router.goInsights("spend")
                    }
                    arrow("")
                    node("creditcard.fill", .mtRecv, "Credit cards", "Card purchases add to what you owe. A bill paid from your bank is a Transfer into the card — it's matched automatically.") {
                        router.goWallet("accounts")
                    }
                    arrow("")
                    node("tray.full.fill", .mtAcc, "Review & learning", "Incoming money the app isn't sure about waits for one tap. It remembers your answer for that person next time.") {
                        router.tab = .home
                    }
                    arrow("and it all adds up on")
                    node("house.fill", .mtAcc, "Home", "Total balance = your accounts − what cards owe. Plus the one thing that needs you, what's safe to spend, and this month so far.") {
                        router.tab = .home
                    }
                    Divider().padding(.vertical, 20)
                    node("target", .pink, "Debts & goals", "Separate trackers in Wallet: money you owe people (with repayments) and what you're saving for.") {
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
            Text(name).font(.system(size: 14, weight: .semibold)) + Text(" — \(text)").font(.system(size: 14)).foregroundStyle(Color.mtTxt2)
        }
    }
    private func goButton(_ go: @escaping () -> Void) -> some View {
        Button { Haptic.tap(); go(); dismiss() } label: {
            Text("Go there →").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.mtAcc)
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
