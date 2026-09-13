import Foundation
import Security
import SwiftData
import Observation

// ─────────────────────────────────────────────────────────────────────────────
// Bank sync — the same account and data as the web app (lib/bankSync.js), over Supabase's
// plain REST API (no SDK). The project is shared with Heimat: MoneyTrack only reads and
// writes its own mt_* tables and its own row in app_users — never anything of Heimat's.
// Connecting a NEW bank needs the bank's own web login, so that stays in the web app;
// every bank already connected syncs here.
// ─────────────────────────────────────────────────────────────────────────────

enum Supa {
    static let url = "https://vqvycbzrkeeuuhgrkpbf.supabase.co"
    static let key = "sb_publishable__akzhxAikI6-fLLQexhbxQ_rTeWuaoJ"   // public by design; rows are protected by RLS
    static let resetRedirect = "https://meet-p-dev.github.io/refactored-octo-tribble/reset/"
    static let webApp = URL(string: "https://meet-p-dev.github.io/refactored-octo-tribble/")!
}

struct AuthSession: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Double
    var userId: String
    var email: String
}

/// Your sign-in lives in the iPhone Keychain, under MoneyTrack's own name — separate from
/// Heimat, so signing into one never signs you out of the other.
enum Keychain {
    private static let service = "com.patel.MoneyTracker.supabase"
    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    static func set(_ data: Data, _ account: String) {
        SecItemDelete(query(account) as CFDictionary)
        var q = query(account)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }
    static func get(_ account: String) -> Data? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }
    static func delete(_ account: String) { SecItemDelete(query(account) as CFDictionary) }
}

struct CloudError: LocalizedError {
    let kind: String
    let message: String
    var errorDescription: String? { message }
}

struct BankConnection: Decodable, Identifiable {
    let id: String
    let bank_name: String
    let status: String
    let last_synced_at: String?
    let last_sync_error: String?
    let valid_until: String?

    /// "Synced 2 h ago" from Postgres' "2026-09-13T12:00:21.873085+00:00".
    var lastSyncedText: String {
        guard let s = last_synced_at, s.count >= 19 else { return "Not synced yet" }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        guard let d = f.date(from: String(s.prefix(19))) else { return "Synced" }
        return "Synced " + d.formatted(.relative(presentation: .named))
    }
}

private struct CloudAccount: Decodable { let id: String; let name: String; let color: String?; let initial_balance: Flex }
private struct CloudTx: Decodable {
    let id: String; let account_id: String?; let type: String; let amount: Flex
    let merchant: String?; let category: String?; let notes: String?; let to_account_id: String?; let date: String
}
private struct PrefsRow: Decodable {
    let payee_stats: [String: JSONValue]?; let tx_decisions: [String: JSONValue]?
    let share_overrides: [String: JSONValue]?; let owner_name: String?
}

@Observable
final class CloudSync {
    static let shared = CloudSync()

    private(set) var session: AuthSession?
    private(set) var connections: [BankConnection] = []
    private(set) var syncing = false
    private(set) var lastSync: Date?
    private(set) var lastError: String?
    private(set) var lastAdded = 0
    var signedIn: Bool { session != nil }
    @ObservationIgnored private var pushTask: Task<Void, Never>?
    @ObservationIgnored private var prefsPulled = false

    init() {
        if let d = Keychain.get("mt-sb-auth"), let s = try? JSONDecoder().decode(AuthSession.self, from: d) { session = s }
        LearningStore.shared.onChange = { [weak self] in self?.schedulePrefsPush() }
    }

    // ── Auth (GoTrue) ──
    private func authRequest(_ path: String, body: [String: Any], bearer: String? = nil) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: Supa.url + path)!)
        req.httpMethod = "POST"
        req.setValue(Supa.key, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer { req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data, resp: URLResponse
        do { (data, resp) = try await URLSession.shared.data(for: req) }
        catch { throw CloudError(kind: "network", message: "Can't reach the server — check your connection.") }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
        if (200..<300).contains(status) { return json }
        let msg = (json["msg"] as? String) ?? (json["error_description"] as? String) ?? (json["message"] as? String)
            ?? (json["error"] as? String) ?? "HTTP \(status)"
        throw CloudError(kind: status == 429 ? "rate" : "http\(status)", message: msg)
    }

    private func adopt(_ j: [String: Any]) throws {
        guard let at = j["access_token"] as? String, let rt = j["refresh_token"] as? String,
              let user = j["user"] as? [String: Any], let uid = user["id"] as? String else {
            throw CloudError(kind: "other", message: "Unexpected answer from the server — try again.")
        }
        let expIn = (j["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        let expAt = (j["expires_at"] as? NSNumber)?.doubleValue ?? (Date().timeIntervalSince1970 + expIn)
        let s = AuthSession(accessToken: at, refreshToken: rt, expiresAt: expAt, userId: uid, email: user["email"] as? String ?? "")
        session = s
        if let d = try? JSONEncoder().encode(s) { Keychain.set(d, "mt-sb-auth") }
    }

    /// Email + password — one call handles sign-in AND a first sign-up, with honest errors
    /// (same rules as the web app): a wrong password on an existing account says exactly that.
    func signIn(email: String, password: String) async throws {
        let email = email.trimmed
        do {
            try adopt(try await authRequest("/auth/v1/token?grant_type=password", body: ["email": email, "password": password]))
        } catch let e as CloudError {
            let m = e.message.lowercased()
            if e.kind == "network" { throw e }
            if e.kind == "rate" || m.contains("rate limit") || m.contains("too many") || m.contains("for security purposes") {
                throw CloudError(kind: "rate", message: "Too many attempts. Wait about a minute, then try again.")
            }
            if m.contains("not confirmed") {
                throw CloudError(kind: "unconfirmed", message: "This email isn't confirmed yet — check your inbox for the confirmation link.")
            }
            guard m.contains("invalid login credentials") || m.contains("invalid credentials") || e.kind == "http400" else {
                throw CloudError(kind: "other", message: e.message)
            }
            // Ambiguous: a wrong password, or a brand-new account. A sign-up attempt tells them apart.
            let j: [String: Any]
            do { j = try await authRequest("/auth/v1/signup", body: ["email": email, "password": password]) }
            catch let e2 as CloudError {
                let m2 = e2.message.lowercased()
                if m2.contains("already registered") || m2.contains("already exists") { throw CloudError(kind: "wrongpw", message: "Incorrect password for this account.") }
                if e2.kind == "rate" || m2.contains("rate limit") || m2.contains("too many") { throw CloudError(kind: "rate", message: "Too many attempts. Wait about a minute, then try again.") }
                if m2.contains("password") { throw CloudError(kind: "weakpw", message: e2.message) }
                throw CloudError(kind: "other", message: e2.message)
            }
            guard j["access_token"] != nil else {
                throw CloudError(kind: "unconfirmed", message: "Account created — check your email to confirm it, then sign in.")
            }
            try adopt(j)
        }
        prefsPulled = false
        await touchAppUser()
    }

    func signOut() {
        if let s = session { let t = s.accessToken; Task { _ = try? await authRequest("/auth/v1/logout", body: [:], bearer: t) } }
        session = nil; connections = []; lastSync = nil; lastError = nil; prefsPulled = false
        Keychain.delete("mt-sb-auth")
    }

    func sendPasswordReset(email: String) async throws {
        let e = email.trimmed
        guard !e.isEmpty else { throw CloudError(kind: "other", message: "Enter your email first, then tap reset.") }
        let redirect = Supa.resetRedirect.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? Supa.resetRedirect
        do { _ = try await authRequest("/auth/v1/recover?redirect_to=\(redirect)", body: ["email": e]) }
        catch let err as CloudError {
            if err.kind == "rate" { throw CloudError(kind: "rate", message: "Too many requests — wait a minute and try again.") }
            if err.kind == "network" { throw err }
            throw CloudError(kind: "other", message: "The email couldn't be sent — try again in a few minutes.")
        }
    }

    /// A valid session, refreshed shortly before it expires.
    private func token() async throws -> AuthSession {
        guard let s = session else { throw CloudError(kind: "signedout", message: "Please sign in again.") }
        if s.expiresAt - Date().timeIntervalSince1970 > 60 { return s }
        do {
            try adopt(try await authRequest("/auth/v1/token?grant_type=refresh_token", body: ["refresh_token": s.refreshToken]))
            return session ?? s
        } catch let e as CloudError where e.kind != "network" {
            signOut()
            throw CloudError(kind: "signedout", message: "Your sign-in expired — please sign in again.")
        }
    }

    // ── PostgREST (row-level security keeps every row yours) ──
    private func rest(_ path: String, method: String = "GET", json: Any? = nil, prefer: String? = nil) async throws -> Data {
        let s = try await token()
        var req = URLRequest(url: URL(string: Supa.url + "/rest/v1/" + path)!)
        req.httpMethod = method
        req.setValue(Supa.key, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(s.accessToken)", forHTTPHeaderField: "Authorization")
        if let json {
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let prefer { req.setValue(prefer, forHTTPHeaderField: "Prefer") }
        let data: Data, resp: URLResponse
        do { (data, resp) = try await URLSession.shared.data(for: req) }
        catch { throw CloudError(kind: "network", message: "Can't reach the server — check your connection.") }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw CloudError(kind: "http\(status)", message: "Sync failed (\(status)). Pull down to try again.")
        }
        return data
    }
    private func get<T: Decodable>(_ path: String) async throws -> [T] {
        try JSONDecoder().decode([T].self, from: try await rest(path))
    }

    /// Records this account as a MoneyTrack account (app_users) — bookkeeping only, never blocks.
    private func touchAppUser() async {
        guard let s = session, !s.email.isEmpty else { return }
        _ = try? await rest("app_users?on_conflict=user_id,app", method: "POST",
                            json: ["user_id": s.userId, "app": "moneytrack", "last_seen_at": ISO8601DateFormatter().string(from: Date())],
                            prefer: "resolution=merge-duplicates,return=minimal")
    }

    // ── Sync ──
    /// On launch / when the app comes back: pull your learning once, then the bank data
    /// (at most once a minute unless you pull to refresh).
    func launchSync(ctx: ModelContext) async {
        guard signedIn else { return }
        if !prefsPulled { await pullPrefs() }
        await sync(ctx: ctx, force: false)
    }

    func sync(ctx: ModelContext, force: Bool = true) async {
        guard signedIn, !syncing else { return }
        if !force, let l = lastSync, Date().timeIntervalSince(l) < 60 { return }
        syncing = true
        defer { syncing = false }
        do {
            let accs: [CloudAccount] = try await get("mt_accounts?select=id,name,color,initial_balance")
            let txs: [CloudTx] = try await get("mt_transactions?select=id,account_id,type,amount,merchant,category,notes,to_account_id,date&order=date.desc")
            let conns: [BankConnection] = try await get("mt_bank_connections?select=id,bank_name,status,last_synced_at,last_sync_error,valid_until&order=created_at.desc")
            lastAdded = try merge(ctx: ctx, accs: accs, txs: txs)
            connections = conns; lastSync = Date(); lastError = nil
        } catch {
            lastError = (error as? CloudError)?.message ?? error.localizedDescription
        }
    }

    /// Same reconcile as the web app's refreshBank (V11.3):
    ///  · bank accounts mirror the cloud (name, color, starting balance); your own accounts are untouched;
    ///  · a bank transaction gone from the cloud is dropped; a new one is added;
    ///  · one that already exists keeps YOUR labelling (category, merchant, notes) but has the bank's
    ///    cash facts re-applied — direction, amount, date, account — so a balance can never drift.
    @discardableResult
    private func merge(ctx: ModelContext, accs: [CloudAccount], txs: [CloudTx]) throws -> Int {
        let local = try ctx.fetch(FetchDescriptor<Account>())
        let cloudAccIds = Set(accs.map { "sb-" + $0.id })
        for a in local where a.id.hasPrefix("sb-") && !cloudAccIds.contains(a.id) { ctx.delete(a) }
        var nextSort = (local.map(\.sortIndex).max() ?? 0) + 1
        for c in accs {
            let id = "sb-" + c.id
            if let a = local.first(where: { $0.id == id }) {
                a.name = c.name; if let col = c.color { a.colorHex = col }
                a.initialBalance = c.initial_balance.value; a.isBank = true
            } else {
                let a = Account(id: id, name: c.name, colorHex: c.color ?? "#3b82f6", initialBalance: c.initial_balance.value, sortIndex: nextSort)
                nextSort += 1; a.isBank = true; ctx.insert(a)
            }
        }
        let localTx = try ctx.fetch(FetchDescriptor<Txn>())
        var byId: [String: Txn] = [:]
        for t in localTx { byId[t.id] = t }
        let cloudIds = Set(txs.map { "sb-" + $0.id })
        for t in localTx where t.id.hasPrefix("sb-") && !cloudIds.contains(t.id) { ctx.delete(t) }
        var added = 0
        for c in txs {
            let id = "sb-" + c.id
            let acc = c.account_id.map { "sb-" + $0 } ?? ""
            let to = c.to_account_id.map { "sb-" + $0 } ?? ""
            let date = String(c.date.prefix(10))
            if let t = byId[id] {
                if t.type != c.type || abs(t.amount - c.amount.value) > 0.001 || t.date != date || t.accountId != acc {
                    t.type = c.type; t.amount = c.amount.value; t.date = date; t.accountId = acc; t.toAccountId = to
                }
                t.isBank = true
            } else {
                let t = Txn(id: id, type: c.type, amount: c.amount.value, merchant: c.merchant ?? "",
                            categoryId: c.category ?? "other", accountId: acc, toAccountId: to, notes: c.notes ?? "", date: date)
                t.isBank = true; ctx.insert(t); added += 1
            }
        }
        try ctx.save()
        return added
    }

    // ── Learning ↔ mt_user_prefs (the web's syncPrefsFromCloud / savePrefs) ──
    /// Cloud wins if it has data (this device joins your synced learning); otherwise the
    /// cloud is seeded from this device.
    func pullPrefs() async {
        guard let s = session else { return }
        do {
            let rows: [PrefsRow] = try await get("mt_user_prefs?select=payee_stats,tx_decisions,share_overrides,owner_name&user_id=eq.\(s.userId)")
            if let r = rows.first, !(r.payee_stats ?? [:]).isEmpty || !(r.tx_decisions ?? [:]).isEmpty
                || !(r.share_overrides ?? [:]).isEmpty || !(r.owner_name ?? "").isEmpty {
                LearningStore.shared.replaceAll(decisions: r.tx_decisions ?? [:], payeeStats: r.payee_stats ?? [:],
                                                shares: (r.share_overrides ?? [:]).compactMapValues(\.number),
                                                ownerName: r.owner_name ?? "", notify: false)
            } else {
                await pushPrefs()
            }
            prefsPulled = true
        } catch {
            lastError = (error as? CloudError)?.message ?? error.localizedDescription
        }
    }

    func pushPrefs() async {
        guard let s = session else { return }
        let L = LearningStore.shared
        let row: [String: Any] = [
            "user_id": s.userId, "payee_stats": L.payeeStats.mapValues(\.any), "tx_decisions": L.txDecisions.mapValues(\.any),
            "share_overrides": L.shareOverrides, "owner_name": L.ownerName,
            "updated_at": ISO8601DateFormatter().string(from: Date()),
        ]
        _ = try? await rest("mt_user_prefs?on_conflict=user_id", method: "POST", json: row, prefer: "resolution=merge-duplicates,return=minimal")
    }

    /// A burst of taps writes once.
    func schedulePrefsPush() {
        guard signedIn else { return }
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            await self?.pushPrefs()
        }
    }

    /// Editing a bank account's balance/name/color saves it to the cloud, so every device agrees.
    func updateBankAccount(id: String, ib: Double, name: String, color: String) {
        guard signedIn, id.hasPrefix("sb-") else { return }
        let real = String(id.dropFirst(3))
        Task { _ = try? await rest("mt_accounts?id=eq.\(real)", method: "PATCH",
                                   json: ["initial_balance": ib, "name": name, "color": color], prefer: "return=minimal") }
    }
}
