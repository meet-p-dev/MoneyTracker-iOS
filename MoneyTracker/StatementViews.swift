import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// Statement Drop: pick a bank's export, see what it changes, import.

/// A button that opens the file picker and then the import preview. It uses its own
/// document picker: a second SwiftUI `.fileImporter` on the same screen (Settings already has
/// one for backups) is silently ignored.
struct StatementImportButton: View {
    var label = "Import a bank statement"
    @State private var picking = false
    @State private var file: PickedFile?
    @State private var error: String?

    struct PickedFile: Identifiable { let id = UUID(); let data: Data; let name: String }

    var body: some View {
        Button { picking = true } label: { Label(label, systemImage: "doc.text") }
            .sheet(isPresented: $picking) {
                DocumentPicker(types: [.commaSeparatedText, .plainText, .xml, .data]) { url in
                    picking = false
                    guard let url else { return }
                    let ok = url.startAccessingSecurityScopedResource()
                    defer { if ok { url.stopAccessingSecurityScopedResource() } }
                    guard let d = try? Data(contentsOf: url) else { error = "This file couldn't be opened."; return }
                    let picked = PickedFile(data: d, name: url.lastPathComponent)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { file = picked }
                }
                .ignoresSafeArea()
            }
            .sheet(item: $file) { StatementImportView(data: $0.data, filename: $0.name) }
            .alert("Couldn't open the file", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    let types: [UTType]
    let onPick: (URL?) -> Void
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick) }
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL?) -> Void
        init(_ f: @escaping (URL?) -> Void) { onPick = f }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onPick(urls.first) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onPick(nil) }
    }
}

struct StatementImportView: View {
    let data: Data
    let filename: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Account.sortIndex) private var accounts: [Account]
    @State private var st: Statement?
    @State private var error: String?
    @State private var accountId = ""
    @State private var plan: StatementPlan?
    @State private var result: StatementImport.Result?
    @State private var fixed = false

    var body: some View {
        NavigationStack {
            Form {
                if let error {
                    Section { Text(error) }
                } else if let st {
                    fileSection(st)
                    if result == nil {
                        Section {
                            Picker("Account", selection: $accountId) {
                                Text("Choose").tag("")
                                ForEach(accounts) { a in Text(a.name).tag(a.id) }
                            }
                        } footer: { Text("Which account is this statement for?") }
                        if let plan { planSection(plan) }
                    }
                    if let result { resultSection(result) }
                }
            }
            .navigationTitle("Bank statement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { if result == nil { Button("Cancel") { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) { if result != nil { Button("Done") { dismiss() } } }
            }
            .onChange(of: accountId) { _, id in recompute(id) }
            .task {
                do {
                    let s = try StatementParser.parse(data, filename: filename)
                    st = s
                    accountId = StatementImport.rememberedAccount(s, accounts) ?? ""
                    recompute(accountId)
                } catch { self.error = error.localizedDescription }
            }
        }
    }

    private func recompute(_ id: String) {
        guard let st, !id.isEmpty else { plan = nil; return }
        plan = StatementImport.plan(st, accountId: id, ctx: ctx)
    }

    private func fileSection(_ st: Statement) -> some View {
        Section {
            LabeledContent("From", value: st.bank.isEmpty ? st.format : "\(st.bank) · \(st.format)")
            if let f = st.first, let l = st.last {
                LabeledContent("Dates", value: f == l ? Fmt.shortDay(f) : "\(Fmt.shortDay(f)) – \(Fmt.shortDay(l))")
            }
            LabeledContent("Rows", value: "\(st.rows.count)")
            if !st.iban.isEmpty { LabeledContent("Account number", value: "…" + st.iban.suffix(4)) }
        } header: { Text(filename) }
    }

    @ViewBuilder private func planSection(_ p: StatementPlan) -> some View {
        if p.foreign, let st {
            Section { Text("This file is in \(st.currency). For now only \(TapSettle.home) statements can be imported.") }
        } else if p.crossCheck {
            Section {
                if p.notInSync.isEmpty {
                    Label("Every row in the file is in your bank sync.", systemImage: "checkmark.circle").foregroundStyle(Color.mtGreen)
                } else {
                    ForEach(Array(p.notInSync.prefix(30).enumerated()), id: \.offset) { _, r in fileRow(r) }
                }
            } header: {
                Text(p.notInSync.isEmpty ? "Checked" : "In your file, not in your bank sync (\(p.notInSync.count))")
            } footer: {
                Text("This account syncs from your bank, so nothing is added. The file is only compared with it.")
            }
        } else {
            Section {
                line("New transactions", p.inserts.count)
                line("Apple Pay payments confirmed", p.tapMerges)
                line("Rows you added, confirmed", p.typedMerges)
                line("Transfers you already have", p.twins)
                line("Already imported", p.duplicates)
                line("Pending, skipped for now", p.pending)
                line("Reversed, skipped", p.reverted)
                line("Apple Pay payments not in the file", p.orphanTaps.count)
            } header: { Text("What changes") } footer: {
                Text("Rows from the file are your bank's own. Their amount and date replace a tap's or a row you typed.")
            }
            Section {
                Button {
                    guard let st else { return }
                    withAnimation { result = StatementImport.apply(st, p, accountId: accountId, ctx: ctx) }
                    Haptic.success()
                } label: {
                    Text(p.inserts.isEmpty && p.merges.isEmpty ? "Nothing new to import" : "Import").frame(maxWidth: .infinity).fontWeight(.semibold)
                }
                .disabled(p.inserts.isEmpty && p.merges.isEmpty && p.orphanTaps.isEmpty)
            }
        }
    }

    private func resultSection(_ r: StatementImport.Result) -> some View {
        Section {
            Label("\(r.added) added, \(r.confirmed) confirmed", systemImage: "checkmark.circle.fill").foregroundStyle(Color.mtGreen)
            if let c = r.closing {
                if r.matches || fixed {
                    Text("The balance on \(Fmt.shortDay(c.day)) matches the statement: \(Fmt.money(c.file)).").font(.subheadline)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("The statement says \(Fmt.money(c.file)) on \(Fmt.shortDay(c.day)). MoneyTrack shows \(Fmt.money(c.app)).")
                            .font(.subheadline)
                        Text("A difference of \(Fmt.money(c.file - c.app)). Often the starting balance, or rows from before the statement.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if accounts.first(where: { $0.id == accountId })?.isSynced == false {
                        Button("Change the starting balance to match") {
                            StatementImport.matchStartingBalance(accountId: accountId, file: c.file, app: c.app, ctx: ctx)
                            fixed = true; Haptic.success()
                        }
                    }
                }
            }
        } header: { Text("Imported") }
    }

    private func line(_ title: String, _ n: Int) -> some View {
        LabeledContent(title) { Text("\(n)").monospacedDigit().foregroundStyle(n == 0 ? Color.mtTxt3 : Color.primary) }
    }
    private func fileRow(_ r: StatementRow) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(r.payee.isEmpty ? "Bank transaction" : r.payee).font(.subheadline).lineLimit(1)
                Text(Fmt.shortDay(r.day)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text((r.cents < 0 ? "−" : "+") + Fmt.money(Double(abs(r.cents)) / 100)).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
    }
}
