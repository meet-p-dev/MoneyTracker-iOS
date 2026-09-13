import SwiftUI
import SwiftData
struct ContentView: View {
    @State private var showAdd = false

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
            ActivityView()
                .tabItem { Label("Activity", systemImage: "list.bullet") }
            PeopleView()
                .tabItem { Label("People", systemImage: "person.2.fill") }
            GoalsView()
                .tabItem { Label("Goals", systemImage: "target") }
            AnalyticsView()
                .tabItem { Label("Analytics", systemImage: "chart.pie.fill") }
        }
        .tint(Color(hex: "#0a84ff"))
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Account.self, TxCategory.self, Txn.self, Goal.self,
                              RecurringTxn.self, Debt.self, Budget.self], inMemory: true)
}
