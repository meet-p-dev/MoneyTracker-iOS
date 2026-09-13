import SwiftUI
import SwiftData

// The app shell: iOS 26's floating Liquid Glass tab bar with the web app's five places.
// The middle "+" isn't a screen — tapping it opens the add sheet from wherever you are.
struct ContentView: View {
    @Environment(\.modelContext) private var ctx
    @State private var router = Router()

    var body: some View {
        TabView(selection: $router.tab) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) { HomeView() }
            Tab("Activity", systemImage: "list.bullet", value: AppTab.activity) { ActivityView() }
            Tab("Add", systemImage: "plus.circle.fill", value: AppTab.add) { Color.mtBg }
            Tab("Insights", systemImage: "chart.pie.fill", value: AppTab.insights) { InsightsView() }
            Tab("Wallet", systemImage: "wallet.bifold.fill", value: AppTab.wallet) { WalletView() }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(.mtAcc)
        .environment(router)
        .onChange(of: router.tab) { old, new in
            guard new == .add else { return }
            router.tab = old == .add ? .home : old
            router.showAdd = true
            Haptic.tap()
        }
        .sheet(isPresented: $router.showAdd) { TransactionForm(existing: nil).environment(router) }
        .task { CardAutopay.run(ctx: ctx) }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Account.self, TxCategory.self, Txn.self, Goal.self,
                              RecurringTxn.self, Debt.self, Budget.self], inMemory: true)
}
