import SwiftUI
import SwiftData

@main
struct MoneyTrackerApp: App {
    let container: ModelContainer
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @State private var locked = false

    init() {
        container = AppData.container
        BackupService.seedIfEmpty(ctx: container.mainContext)
        BackupService.migrateIfNeeded(ctx: container.mainContext)
        _ = CloudSync.shared          // restores your sign-in and hooks learning → cloud
        MTTips.configure()            // Apple's tip bubbles (Settings → Show tips again resets them)
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
                    TapSettle.run(ctx: container.mainContext)
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
