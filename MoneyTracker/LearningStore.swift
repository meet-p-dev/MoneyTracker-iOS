import Foundation
import Observation

// The web app's learning stores — mt-tx-decisions (what YOU said a bank row is),
// mt-payee-stats (per-payee learning, used by the classifier in Phase 2),
// mt-share-overrides ("My share") and mt-owner-name. Kept as JSON so backups — and later
// the cloud sync — round-trip them exactly. Persisted to Application Support.
@Observable
final class LearningStore {
    static let shared = LearningStore()

    private(set) var txDecisions: [String: JSONValue] = [:]
    private(set) var payeeStats: [String: JSONValue] = [:]
    private(set) var shareOverrides: [String: Double] = [:]
    private(set) var ownerName: String = ""

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

    private func save() {
        let s = Snapshot(txDecisions: txDecisions, payeeStats: payeeStats, shareOverrides: shareOverrides, ownerName: ownerName)
        try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(s) { try? d.write(to: Self.url, options: .atomic) }
    }

    func decision(_ id: String) -> Decision? { txDecisions[id].flatMap(Decision.init) }
    func setDecision(_ d: Decision?, for id: String) { txDecisions[id] = d?.json; save() }
    func share(_ id: String) -> Double? { shareOverrides[id] }
    func setShare(_ v: Double?, for id: String) { shareOverrides[id] = v; save() }
    func setOwnerName(_ s: String) { ownerName = s; save() }
    /// A deleted transaction takes its decision and "My share" with it.
    func forget(_ id: String) {
        guard txDecisions[id] != nil || shareOverrides[id] != nil else { return }
        txDecisions[id] = nil; shareOverrides[id] = nil; save()
    }
    func replaceAll(decisions: [String: JSONValue], payeeStats: [String: JSONValue], shares: [String: Double], ownerName: String) {
        txDecisions = decisions; self.payeeStats = payeeStats; shareOverrides = shares; self.ownerName = ownerName
        save()
    }
    func clear() { replaceAll(decisions: [:], payeeStats: [:], shares: [:], ownerName: "") }
}
