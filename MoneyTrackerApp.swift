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
                BackupService.triggerRecurring(ctx: container.mainContext)
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background:
                    if appLockEnabled { locked = true }
                case .active:
                    BackupService.triggerRecurring(ctx: container.mainContext)
                default: break
                }
            }
        }
        .modelContainer(container)
    }
}
