import SwiftUI
import SwiftData

@main
struct MoneyTrackerApp: App {
    let container: ModelContainer
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @State private var locked = false

    init() {
        do {
            container = try ModelContainer(for: Account.self, TxCategory.self, Txn.self,
                                           Goal.self, RecurringTxn.self, Debt.self, Budget.self)
            BackupService.seedIfEmpty(ctx: container.mainContext)
            BackupService.migrateIfNeeded(ctx: container.mainContext)
            _ = CloudSync.shared          // restores your sign-in and hooks learning → cloud
        } catch {
            fatalError("Could not create SwiftData container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                if locked { LockView(locked: $locked) }
            }
            .onAppear {
                locked = appLockEnabled
                Task { await CloudSync.shared.launchSync(ctx: container.mainContext) }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    Task { await CloudSync.shared.launchSync(ctx: container.mainContext) }
                case .background:
                    if appLockEnabled { locked = true }
                default: break
                }
            }
        }
        .modelContainer(container)
    }
}
