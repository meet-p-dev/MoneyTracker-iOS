import SwiftUI
import SwiftData

// Who's using the app: the name (also what the classifier looks for to spot your own
// transfers), the bank-sync account, a few numbers, and the way into Settings.
enum Profile {
    static var name: String { LearningStore.shared.ownerName.trimmed }
    static var email: String { CloudSync.shared.session?.email ?? "" }
    static var displayName: String {
        if !name.isEmpty { return name }
        return email.split(separator: "@").first.map(String.init) ?? ""
    }
    static var initials: String {
        let words = displayName.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "_" })
        return words.prefix(2).compactMap(\.first).map { String($0).uppercased() }.joined()
    }
}

struct ProfileAvatar: View {
    var size: CGFloat = 34
    var body: some View {
        let initials = Profile.initials
        Circle()
            .fill(initials.isEmpty ? Color.mtTxt3 : Color(hex: MonogramPalette.color(Profile.displayName)))
            .frame(width: size, height: size)
            .overlay {
                if initials.isEmpty {
                    Image(systemName: "person.fill").font(.system(size: size * 0.45, weight: .medium)).foregroundStyle(.white)
                } else {
                    Text(initials).font(.system(size: size * 0.38, weight: .semibold)).foregroundStyle(.white)
                }
            }
    }
}

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [Account]
    @Query private var txs: [Txn]
    @State private var name = LearningStore.shared.ownerName
    @State private var showHow = false

    var body: some View {
        let firstDate = Ledger.build(accounts: accounts, txs: txs).rows.map(\.date).filter { !$0.isEmpty }.min()
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 8) {
                        ProfileAvatar(size: 72)
                        Text(Profile.displayName.isEmpty ? "Add your name" : Profile.displayName)
                            .font(.system(size: 22, weight: .semibold))
                        if !Profile.email.isEmpty {
                            Text(Profile.email).font(.system(size: 15)).foregroundStyle(Color.mtTxt2)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
                Section {
                    TextField("As it appears on your bank statements", text: $name)
                        .textContentType(.name)
                        .submitLabel(.done)
                        .onSubmit(save)
                } header: {
                    Text("Name")
                } footer: {
                    Text("Used to recognise transfers between your own accounts.")
                }
                Section("Your data") {
                    LabeledContent("Accounts", value: "\(accounts.count)")
                    LabeledContent("Transactions", value: "\(txs.count)")
                    if let firstDate { LabeledContent("First transaction", value: CardMath.date(firstDate).formatted(date: .abbreviated, time: .omitted)) }
                }
                Section {
                    NavigationLink { BankSyncView() } label: {
                        LabeledContent {
                            Text(CloudSync.shared.signedIn ? "On" : "Off")
                        } label: { Label("Bank sync", systemImage: "building.columns") }
                    }
                    NavigationLink { SettingsView(embedded: true) } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    Button { showHow = true } label: {
                        Label("How MoneyTrack works", systemImage: "questionmark.circle")
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { save(); dismiss() } }
            }
            .sheet(isPresented: $showHow) { HowItWorksView() }
            .onDisappear(perform: save)
        }
    }

    private func save() {
        let n = name.trimmed
        if n != LearningStore.shared.ownerName { LearningStore.shared.setOwnerName(n) }
    }
}
