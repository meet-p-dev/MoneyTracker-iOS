import SwiftUI
import SwiftData

// The app shell: the four places in a TabView (each keeps its own scroll and navigation),
// the app's own Liquid Glass tab bar with the big "+", the welcome tour for a brand-new
// install, and card auto-pay.
struct ContentView: View {
    @Environment(\.modelContext) private var ctx
    @State private var router = Router()
    @AppStorage("mt-ios-tour-seen") private var tourSeen = false
    @Query private var accounts: [Account]
    @Query private var txs: [Txn]
    @State private var tourAction: TourAction?
    @State private var openedFile: StatementImportButton.PickedFile?

    var body: some View {
        TabView(selection: $router.tab) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) { HomeView().mtTabContent() }
            Tab("Activity", systemImage: "list.bullet", value: AppTab.activity) { ActivityView().mtTabContent() }
            Tab("Insights", systemImage: "chart.pie.fill", value: AppTab.insights) { InsightsView().mtTabContent() }
            Tab("Wallet", systemImage: "wallet.bifold.fill", value: AppTab.wallet) { WalletView().mtTabContent() }
        }
        .overlay(alignment: .bottom) { GlassTabBar(router: router).ignoresSafeArea(.keyboard, edges: .bottom) }
        .tint(.mtAcc)
        .sheet(isPresented: $router.showAdd) { TransactionForm(existing: nil) }
        .sheet(isPresented: $router.showProfile) { ProfileView().environment(router) }
        .fullScreenCover(isPresented: $router.showTour) {
            TourView { action in
                tourSeen = true
                router.showTour = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { tourAction = action }
            }
        }
        .sheet(item: $tourAction) { a in
            switch a {
            case .bank: NavigationStack { BankSyncView() }
            case .account: AccountForm(existing: nil)
            case .backup: SettingsView()
            case .howItWorks: HowItWorksView()
            }
        }
        // A statement shared from a banking app or Files ("Open in MoneyTrack").
        .onOpenURL { url in
            guard url.isFileURL else { return }
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            if let d = try? Data(contentsOf: url) { openedFile = .init(data: d, name: url.lastPathComponent) }
        }
        .sheet(item: $openedFile) { StatementImportView(data: $0.data, filename: $0.name) }
        .onAppear { if !tourSeen && accounts.isEmpty && txs.isEmpty { router.showTour = true } }
        .task { CardAutopay.run(ctx: ctx) }
        .environment(router)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Account.self, TxCategory.self, Txn.self, Goal.self,
                              RecurringTxn.self, Debt.self, Budget.self, Capture.self], inMemory: true)
}
