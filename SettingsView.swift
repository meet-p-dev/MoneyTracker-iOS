import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @State private var showImporter = false
    @State private var exportURL: URL?
    @State private var importResult: String?
    @State private var confirmWipe = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Data backup") {
                    Button {
                        do {
                            let data = try BackupService.exportBackup(ctx: ctx)
                            let url = FileManager.default.temporaryDirectory
                                .appendingPathComponent("moneytrack-backup-\(Fmt.today()).json")
                            try data.write(to: url)
                            exportURL = url
                        } catch { importResult = "Export failed: \(error.localizedDescription)" }
                    } label: {
                        Label("Export backup (JSON)", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        showImporter = true
                    } label: {
                        Label("Restore backup / import from PWA", systemImage: "square.and.arrow.down")
                    }
                    if let importResult {
                        Text(importResult).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Security") {
                    Toggle(isOn: $appLockEnabled) {
                        Label("App Lock (Face ID)", systemImage: "faceid")
                    }
                }
                Section("Danger zone") {
                    Button(role: .destructive) { confirmWipe = true } label: {
                        Label("Clear all data", systemImage: "trash")
                    }
                }
                Section {
                    LabeledContent("Version", value: "3.0 (native)")
                }
            }
            .navigationTitle("Settings & Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    do {
                        guard url.startAccessingSecurityScopedResource() else {
                            importResult = "Could not read the file."; return
                        }
                        defer { url.stopAccessingSecurityScopedResource() }
                        let data = try Data(contentsOf: url)
                        let n = try BackupService.importBackup(data, into: ctx)
                        importResult = "Imported \(n) records ✓"
                        Haptic.success()
                    } catch {
                        importResult = "Import failed: \(error.localizedDescription)"
                    }
                case .failure(let err):
                    importResult = err.localizedDescription
                }
            }
            .sheet(item: $exportURL) { url in
                ShareSheet(url: url)
            }
            .confirmationDialog("Delete ALL data? This cannot be undone.",
                                isPresented: $confirmWipe, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) {
                    try? ctx.delete(model: Txn.self); try? ctx.delete(model: Goal.self)
                    try? ctx.delete(model: RecurringTxn.self); try? ctx.delete(model: Debt.self)
                    try? ctx.delete(model: Budget.self)
                    try? ctx.save()
                    importResult = "All data cleared"
                }
            }
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
