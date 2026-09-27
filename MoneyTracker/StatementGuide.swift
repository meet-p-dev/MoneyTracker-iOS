import SwiftUI
import SwiftData
import UserNotifications

// "Your banks": pick the banks you use, see the way each one gets into MoneyTrack (Apple Pay
// taps every day, the bank's statement once a week) with the exact steps, and an optional
// weekly reminder. Menu names in banking apps change now and then, so the steps say where to
// look rather than promise every word.

struct BankGuide: Identifiable, Hashable {
    let id: String
    let name: String
    let file: String            // what to download
    let steps: [String]
}

enum BankGuides {
    static let all: [BankGuide] = [
        BankGuide(id: "sparkasse", name: "Sparkasse", file: "CSV-CAMT, CAMT or MT940", steps: [
            "Open your Sparkasse online banking in the browser.",
            "Go to Umsätze and pick the last 30 days.",
            "Tap Export and choose CSV-CAMT (or CAMT).",
            "Open the file and share it to MoneyTrack.",
        ]),
        BankGuide(id: "volksbank", name: "Volksbank / Raiffeisenbank", file: "CSV or CAMT", steps: [
            "Open VR online banking in the browser.",
            "Go to Umsätze, pick the last 30 days and choose Export.",
            "Pick CSV or CAMT, then share the file to MoneyTrack.",
        ]),
        BankGuide(id: "revolut", name: "Revolut", file: "Excel or CSV", steps: [
            "In the Revolut app, open your euro account.",
            "Tap ⋯ (More), then Statement.",
            "Choose Excel and the last 30 days, then Get statement.",
            "Share it to MoneyTrack.",
        ]),
        BankGuide(id: "n26", name: "N26", file: "CSV", steps: [
            "In the N26 app or at app.n26.com, open Downloads.",
            "Export your transactions for the last 30 days as CSV.",
            "Share the file to MoneyTrack.",
        ]),
        BankGuide(id: "dkb", name: "DKB", file: "CSV", steps: [
            "Open DKB banking in the browser.",
            "Go to Umsätze, pick the last 30 days and tap the download button (CSV).",
            "Open the file and share it to MoneyTrack.",
        ]),
        BankGuide(id: "ing", name: "ING", file: "CSV", steps: [
            "Open ING Banking in the browser.",
            "Go to Umsätze, pick the last 30 days and choose Export → CSV.",
            "Open the file and share it to MoneyTrack.",
        ]),
        BankGuide(id: "comdirect", name: "comdirect / Commerzbank", file: "CSV", steps: [
            "Open online banking in the browser.",
            "Go to Umsätze, pick the last 30 days and export as CSV.",
            "Share the file to MoneyTrack.",
        ]),
        BankGuide(id: "c24", name: "C24", file: "CSV", steps: [
            "Open C24 banking and go to your transactions.",
            "Export the last 30 days as CSV.",
            "Share the file to MoneyTrack.",
        ]),
        BankGuide(id: "traderepublic", name: "Trade Republic", file: "CSV or PDF", steps: [
            "In the app, look in Profile for a transaction export (CSV).",
            "If there is none, download the latest statement (PDF).",
            "Share it to MoneyTrack.",
        ]),
        BankGuide(id: "advanzia", name: "Advanzia (credit card)", file: "PDF", steps: [
            "Log in to the Advanzia customer area.",
            "Open your statements (Kontoauszüge) and download the latest PDF.",
            "Share the PDF to MoneyTrack.",
        ]),
        BankGuide(id: "other", name: "Another bank", file: "CSV, camt, MT940, Excel or PDF", steps: [
            "In online banking, look for Export, Download or Kontoauszug.",
            "Any of CSV, camt, MT940, Excel or PDF works. CSV is the most reliable.",
            "Share the file to MoneyTrack.",
        ]),
    ]
    private static let key = "mt-my-banks"
    static var mine: [String] {
        get { UserDefaults.standard.stringArray(forKey: key) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: key); StatementReminder.refresh() }
    }
}

/// A weekly local notification ("Bring in this week's statements"). No push service.
enum StatementReminder {
    private static let key = "mt-statement-reminder", id = "mt-statement-weekly", oldId = "mt-statement-monthly"
    static var on: Bool { UserDefaults.standard.bool(forKey: key) }

    static func set(_ on: Bool, done: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        guard on else {
            UserDefaults.standard.set(false, forKey: key)
            center.removePendingNotificationRequests(withIdentifiers: [id, oldId])
            done(false); return
        }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                UserDefaults.standard.set(granted, forKey: key)
                if granted { schedule() }
                done(granted)
            }
        }
    }
    static func refresh() { if on { schedule() } }
    private static func schedule() {
        let names = BankGuides.all.filter { BankGuides.mine.contains($0.id) && $0.id != "other" }.map(\.name)
        let c = UNMutableNotificationContent()
        c.title = "Bank statements"
        c.body = names.isEmpty ? "Bring in this week's statements. It takes a minute per bank."
            : "Bring in this week's statements from \(names.formatted(.list(type: .and)))."
        var when = DateComponents(); when.weekday = 1; when.hour = 18          // Sunday, 18:00
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [oldId])
        let req = UNNotificationRequest(identifier: id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true))
        UNUserNotificationCenter.current().add(req)
    }
}

struct StatementGuideView: View {
    var modal = false                  // opened as a sheet (Home), not pushed (Settings)
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortIndex) private var accounts: [Account]
    @State private var mine = Set(BankGuides.mine)
    @State private var reminder = StatementReminder.on
    @State private var reminderNote: String?
    @State private var open: String?

    var body: some View {
        Form {
            Section {
                ForEach(BankGuides.all) { b in
                    Button {
                        if mine.contains(b.id) { mine.remove(b.id) } else { mine.insert(b.id) }
                        BankGuides.mine = Array(mine)
                    } label: {
                        HStack {
                            Text(b.name).foregroundStyle(Color.primary)
                            Spacer()
                            if mine.contains(b.id) { Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(Color.mtAcc) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: { Text("Which banks do you use?") }

            if !mine.isEmpty {
                Section {
                    Label("Pay with Apple Pay and in-store payments come in by themselves. With iOS 27, your banking app's notifications can bring in direct debits and online payments too.", systemImage: "wave.3.right")
                        .font(.subheadline)
                    NavigationLink("Set up Apple Pay payments") { ApplePayView() }
                    NavigationLink("Bank notifications (iOS 27)") { NotificationCaptureView() }
                } header: { Text("Every day") }

                Section {
                    ForEach(BankGuides.all.filter { mine.contains($0.id) }) { b in
                        DisclosureGroup(isExpanded: Binding(get: { open == b.id }, set: { open = $0 ? b.id : nil })) {
                            if let synced = syncedAccount(b) {
                                Text("\(synced.name) already syncs from your bank. A statement is only compared with it.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            ForEach(Array(b.steps.enumerated()), id: \.offset) { i, s in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("\(i + 1).").font(.footnote.weight(.bold)).foregroundStyle(Color.mtAcc)
                                    Text(s).font(.footnote)
                                }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(b.name)
                                Text(b.file).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    StatementImportButton()
                } header: { Text("Once a week") } footer: {
                    Text("The statement brings in what Apple Pay can't see (online payments, direct debits, income) and confirms the taps with your bank's own amounts. Overlapping dates are fine: nothing is added twice. Menu names can differ a little between app versions.")
                }

                Section {
                    Toggle("Remind me once a week", isOn: Binding(get: { reminder }, set: { v in
                        StatementReminder.set(v) { ok in
                            reminder = ok
                            reminderNote = v && !ok ? "Notifications are off for MoneyTrack. Turn them on in the iPhone's Settings." : nil
                        }
                    }))
                } footer: { Text(reminderNote ?? "Sundays at 18:00. Only on this iPhone.") }
            }
        }
        .navigationTitle("Your banks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if modal { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } } }
    }

    private func syncedAccount(_ b: BankGuide) -> Account? {
        let word = b.name.lowercased().split(separator: " ").first.map(String.init) ?? ""
        return accounts.first { $0.isSynced && word.count >= 3 && $0.name.lowercased().contains(word) }
    }
}
