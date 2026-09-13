import SwiftUI
import SwiftData

// Settings → Bank sync. Signed out: sign in with the SAME email and password as the web
// app (a first sign-in creates the account). Signed in: your connected banks, sync now,
// connect a new bank (opens the web app — the bank's login needs it), sign out.
struct BankSyncView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.openURL) private var openURL
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var err: String?
    @State private var info: String?
    @State private var confirmSignOut = false
    private var cloud: CloudSync { .shared }

    var body: some View {
        Form {
            if let s = cloud.session { signedIn(s) } else { signInForm }
        }
        .navigationTitle("Bank sync")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var signInForm: some View {
        Section {
            Label {
                Text("Sign in with your MoneyTrack account to get the same bank transactions as in the web app. They update three times a day.")
            } icon: { Image(systemName: "building.columns.fill").foregroundStyle(.tint) }
            .font(.footnote)
        }
        Section {
            TextField("Email", text: $email)
                .textContentType(.username).keyboardType(.emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            SecureField("Password", text: $password).textContentType(.password)
        } footer: {
            if let err { Text(err).foregroundStyle(.red) }
            else if let info { Text(info) }
            else { Text("New here? Choose a password and your account is created.") }
        }
        Section {
            Button { signIn() } label: {
                HStack { Text("Sign in").fontWeight(.semibold); Spacer(); if busy { ProgressView() } }
            }
            .disabled(busy || email.trimmed.isEmpty || password.count < 6)
            Button("Forgot password?") { reset() }.disabled(busy)
        }
    }

    @ViewBuilder private func signedIn(_ s: AuthSession) -> some View {
        Section { LabeledContent("Signed in as", value: s.email) }
        Section {
            if cloud.connections.isEmpty {
                Text("No bank connected yet.").foregroundStyle(.secondary)
            }
            ForEach(cloud.connections) { c in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(c.bank_name).fontWeight(.semibold)
                        Spacer()
                        Text(c.status == "active" ? "Active" : c.status.capitalized)
                            .font(.caption.weight(.semibold)).foregroundStyle(c.status == "active" ? .green : .orange)
                    }
                    Text(c.lastSyncedText).font(.caption).foregroundStyle(.secondary)
                    if let e = c.last_sync_error, !e.isEmpty { Text(e).font(.caption2).foregroundStyle(.red).lineLimit(2) }
                }
            }
        } header: { Text("Connected banks") }
        Section {
            Button { Task { await cloud.sync(ctx: ctx) } } label: {
                HStack {
                    Label("Sync now", systemImage: "arrow.clockwise")
                    Spacer()
                    if cloud.syncing { ProgressView() }
                    else if let l = cloud.lastSync { Text(l.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.secondary) }
                }
            }
            .disabled(cloud.syncing)
            Button { openURL(Supa.webApp) } label: { Label("Connect a new bank", systemImage: "plus.circle") }
        } footer: {
            Text("Connecting a bank uses your bank's own login page, which runs in the MoneyTrack web app. Once it's connected, its transactions come here by themselves.")
        }
        if let e = cloud.lastError { Section { Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.footnote) } }
        Section {
            Button("Sign out", role: .destructive) { confirmSignOut = true }
        } footer: { Text("Your data stays on this iPhone; syncing just stops until you sign in again.") }
            .confirmationDialog("Sign out of bank sync?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { cloud.signOut() }
            }
    }

    private func signIn() {
        busy = true; err = nil; info = nil
        Task {
            defer { busy = false }
            do {
                try await cloud.signIn(email: email, password: password)
                password = ""
                await cloud.pullPrefs()
                await cloud.sync(ctx: ctx)
                Haptic.success()
            } catch { err = error.localizedDescription; Haptic.warning() }
        }
    }

    private func reset() {
        busy = true; err = nil; info = nil
        Task {
            defer { busy = false }
            do {
                try await cloud.sendPasswordReset(email: email)
                info = "If that email has an account, a reset link is on its way. Open it, set a new password, then sign in here."
            } catch { err = error.localizedDescription }
        }
    }
}
