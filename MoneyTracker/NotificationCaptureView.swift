import SwiftUI
import SwiftData

// Settings → Bank notifications (iOS 27): the setup for the Notification automation, the
// payments caught from notifications, and exactly what each notification said.
struct NotificationCaptureView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Account.sortIndex) private var accounts: [Account]
    @Query(sort: \Capture.at, order: .reverse) private var caps: [Capture]
    @State private var cardMap = TapSettle.memory.cardMap
    @State private var log: [TapSettle.LogEntry] = []
    #if DEBUG
    @State private var testApp = "Revolut"
    @State private var testBody = "Paid €12.50 at Lidl"
    #endif

    var body: some View {
        let notes = caps.filter { $0.src == "note" }
        let apps = Set(notes.map(\.card)).union(cardMap.keys.filter { k in notes.contains { $0.card == k } }).sorted()
        return Form {
            Section {
                Text("Banking apps notify you about card payments, direct debits and money coming in. With iOS 27, a Shortcuts automation can pass those notifications to MoneyTrack, so payments Apple Pay can't see show up too.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section {
                step(1, "In your banking app, turn on notifications for payments. Sparkasse: Kartenwecker and Umsatzwecker, with Privatmodus off (it hides the amount). Revolut: payment notifications.")
                step(2, "Open Shortcuts, go to Automation, tap + and choose Notification. Pick the banking app. Choose Run Immediately if it's offered.")
                step(3, "Add the action \"Log a bank notification\" from MoneyTrack.")
                step(4, "Fill its fields from the Shortcut Input: App, Title, Subtitle and Body.")
                step(5, "Repeat for each banking app. Payments show up below.")
                Link(destination: URL(string: "shortcuts://")!) { Label("Open Shortcuts", systemImage: "arrow.up.forward.app") }
            } header: { Text("Set it up once") } footer: {
                Text("Needs iOS 27. If iOS asks you before every run, the automation is more work than it saves: leave it off.")
            }
            if !apps.isEmpty {
                Section {
                    ForEach(apps, id: \.self) { app in
                        Menu {
                            ForEach(accounts) { a in
                                Button(a.name) { TapSettle.link(card: app, to: a.id, ctx: ctx); cardMap = TapSettle.memory.cardMap }
                            }
                        } label: {
                            LabeledContent(app.isEmpty ? "Unknown app" : app) {
                                Text(accounts.first { $0.id == cardMap[app] }?.name ?? "Not linked")
                                    .foregroundStyle(cardMap[app] == nil ? Color.mtAmber : Color.secondary)
                            }
                        }
                    }
                } header: { Text("Your apps") } footer: { Text("Which account each app's notifications are about.") }
            }
            Section("Recent payments") {
                if notes.isEmpty { Text("None yet.").foregroundStyle(.secondary) }
                ForEach(notes.prefix(30)) { c in
                    VStack(alignment: .leading, spacing: 4) {
                        TapRow(c: c, accounts: accounts)
                        if !c.reason.isEmpty { Text(c.reason).font(.caption2).foregroundStyle(.secondary) }
                    }
                    .swipeActions {
                        if c.isOpen || c.state == "orphan" || c.state == "added" {
                            Button("Not a payment", role: .destructive) { withAnimation { TapSettle.dismiss(c, ctx: ctx) } }
                        }
                    }
                }
            }
            Section {
                if log.isEmpty { Text("Empty. Each notification adds a line here.").foregroundStyle(.secondary) }
                ForEach(log) { e in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(e.at.formatted(date: .abbreviated, time: .shortened)) · \(e.card) · \(e.result)").font(.caption.weight(.semibold))
                        Text([e.merchant, e.name, e.text].filter { !$0.isEmpty }.joined(separator: " | ")).font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
            } header: { Text("What the notifications said") } footer: {
                Text("Shows whether your bank's wording is read correctly. Stays on this iPhone.")
            }
            #if DEBUG
            Section("Test a notification (debug builds only)") {
                TextField("App", text: $testApp)
                TextField("Body", text: $testBody)
                Button("Log it") {
                    TapSettle.intakeNote(ctx: ctx, app: testApp, title: testApp, subtitle: nil, body: testBody)
                    reload()
                }
            }
            #endif
        }
        .navigationTitle("Bank notifications")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
    }

    private func reload() {
        log = TapSettle.readLog().filter { $0.src == "note" }
        cardMap = TapSettle.memory.cardMap
    }
    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)").font(.caption.weight(.bold)).frame(width: 20, height: 20)
                .background(Color.mtAcc.opacity(0.14), in: Circle()).foregroundStyle(Color.mtAcc)
            Text(text).font(.subheadline)
        }
    }
}
