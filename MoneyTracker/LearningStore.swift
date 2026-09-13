import Foundation
import Observation

// The web app's learning stores — mt-tx-decisions (what YOU said a bank row is),
// mt-payee-stats (per-payee learning for the classifier), mt-share-overrides ("My share")
// and mt-owner-name. Kept as JSON so backups and the cloud (mt_user_prefs) round-trip them
// exactly. Persisted to Application Support; every change is pushed to the cloud when
// you're signed in (CloudSync installs `onChange`).
@Observable
final class LearningStore {
    static let shared = LearningStore()

    private(set) var txDecisions: [String: JSONValue] = [:]
    private(set) var payeeStats: [String: JSONValue] = [:]
    private(set) var shareOverrides: [String: Double] = [:]
    private(set) var ownerName: String = ""
    @ObservationIgnored var onChange: (() -> Void)?

    private struct Snapshot: Codable {
        var txDecisions: [String: JSONValue]
        var payeeStats: [String: JSONValue]
        var shareOverrides: [String: Double]
        var ownerName: String
    }
    private static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("learning.json")
    }

    init() {
        guard let d = try? Data(contentsOf: Self.url),
              let s = try? JSONDecoder().decode(Snapshot.self, from: d) else { return }
        txDecisions = s.txDecisions; payeeStats = s.payeeStats; shareOverrides = s.shareOverrides; ownerName = s.ownerName
    }

    private func save(notify: Bool = true) {
        let s = Snapshot(txDecisions: txDecisions, payeeStats: payeeStats, shareOverrides: shareOverrides, ownerName: ownerName)
        try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(s) { try? d.write(to: Self.url, options: .atomic) }
        if notify { onChange?() }
    }

    func decision(_ id: String) -> Decision? { txDecisions[id].flatMap(Decision.init) }
    func setDecision(_ d: Decision?, for id: String) { txDecisions[id] = d?.json; save() }
    func share(_ id: String) -> Double? { shareOverrides[id] }
    func setShare(_ v: Double?, for id: String) {
        guard shareOverrides[id] != v else { return }
        shareOverrides[id] = v; save()
    }
    func setOwnerName(_ s: String) { ownerName = s; save() }
    func updatePayeeStats(_ f: ([String: JSONValue]) -> [String: JSONValue]) { payeeStats = f(payeeStats); save() }
    /// A deleted transaction takes its decision and "My share" with it.
    func forget(_ id: String) {
        guard txDecisions[id] != nil || shareOverrides[id] != nil else { return }
        txDecisions[id] = nil; shareOverrides[id] = nil; save()
    }
    func replaceAll(decisions: [String: JSONValue], payeeStats: [String: JSONValue], shares: [String: Double],
                    ownerName: String, notify: Bool = true) {
        txDecisions = decisions; self.payeeStats = payeeStats; shareOverrides = shares; self.ownerName = ownerName
        save(notify: notify)
    }
    func clear() { replaceAll(decisions: [:], payeeStats: [:], shares: [:], ownerName: "") }
}
