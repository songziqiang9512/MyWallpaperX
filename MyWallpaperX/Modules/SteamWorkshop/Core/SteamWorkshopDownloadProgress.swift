import Foundation

nonisolated struct SteamWorkshopDownloadProgressSnapshot: Equatable, Sendable {
    enum Phase: String, Equatable, Sendable {
        case connecting
        case preparing
        case transferring
        case validating
        case saving
        case waiting
        case failed

        init?(helperStage: String) {
            switch helperStage {
            case "resolving": self = .connecting
            case "manifest", "preparing", "downloading": self = .preparing
            case "chunks": self = .transferring
            case "validating": self = .validating
            default: return nil
            }
        }
    }

    let itemID: String
    let jobKey: String
    let attempt: Int
    let sequence: Int
    let phase: Phase
    let totalBytes: Int64?
    let verifiedBytes: Int64
    let failureMessage: String?

    var fraction: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(1, max(0, Double(verifiedBytes) / Double(totalBytes)))
    }

    var percent: Int? {
        fraction.map { Int(($0 * 100).rounded(.down)) }
    }

    func statusText(compact: Bool = false) -> String {
        switch phase {
        case .connecting:
            return "正在连接"
        case .preparing:
            return totalBytes == nil ? "正在获取文件信息" : "准备下载"
        case .transferring:
            guard let percent else { return "正在下载 · 大小未知" }
            if compact { return "\(percent)%" }
            return "\(percent)% · \(Self.bytes(verifiedBytes))/\(Self.bytes(totalBytes ?? 0))"
        case .validating:
            return "校验中" + (percent.map { " · \($0)%" } ?? "")
        case .saving:
            return "正在保存" + (percent.map { " · \($0)%" } ?? "")
        case .waiting:
            return "等待重连" + (percent.map { " · \($0)%" } ?? "")
        case .failed:
            return "失败 · 重试"
        }
    }

    private static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}

/// The helper owns counters and coalescing; this store owns the one App-side
/// item/attempt projection. It is intentionally not ObservableObject: only a
/// visible consumer of the matching item receives high-frequency updates.
@MainActor
final class SteamWorkshopDownloadProgressStore {
    typealias Snapshot = SteamWorkshopDownloadProgressSnapshot
    typealias Handler = (Snapshot?) -> Void

    private struct Observer {
        let itemID: String
        weak var owner: AnyObject?
        let requiresOwner: Bool
        let handler: Handler
    }

    private let maximumBytes: Int64 = 8 * 1024 * 1024 * 1024
    private var snapshotsByItemID: [String: Snapshot] = [:]
    private var observers: [UUID: Observer] = [:]

    func snapshot(for itemID: String) -> Snapshot? {
        snapshotsByItemID[itemID]
    }

    @discardableResult
    func addObserver(for itemID: String, handler: @escaping Handler) -> UUID {
        addObserver(for: itemID, owner: nil, requiresOwner: false, handler: handler)
    }

    @discardableResult
    func addObserver(for itemID: String, owner: AnyObject, handler: @escaping Handler) -> UUID {
        addObserver(for: itemID, owner: owner, requiresOwner: true, handler: handler)
    }

    private func addObserver(
        for itemID: String,
        owner: AnyObject?,
        requiresOwner: Bool,
        handler: @escaping Handler
    ) -> UUID {
        removeReleasedObservers()
        let id = UUID()
        observers[id] = Observer(itemID: itemID, owner: owner, requiresOwner: requiresOwner, handler: handler)
        handler(snapshotsByItemID[itemID])
        return id
    }

    func removeObserver(_ id: UUID) {
        observers[id] = nil
    }

    func begin(itemID: String, jobKey: String, attempt: Int) {
        guard !itemID.isEmpty, !jobKey.isEmpty, attempt > 0 else { return }
        publish(Snapshot(
            itemID: itemID,
            jobKey: jobKey,
            attempt: attempt,
            sequence: 0,
            phase: .connecting,
            totalBytes: nil,
            verifiedBytes: 0,
            failureMessage: nil
        ))
    }

    @discardableResult
    func receiveHelperEvent(
        itemID: String,
        jobKey: String,
        attempt: Int,
        sequence: Int,
        stage: String,
        totalBytes: Int64?,
        verifiedBytes: Int64?
    ) -> Bool {
        guard let current = snapshotsByItemID[itemID],
              current.jobKey == jobKey,
              current.attempt == attempt,
              current.phase != .saving,
              current.phase != .failed,
              sequence > current.sequence,
              let phase = Snapshot.Phase(helperStage: stage) else { return false }
        let resolvedTotal = totalBytes ?? current.totalBytes
        let resolvedVerified = verifiedBytes ?? current.verifiedBytes
        guard current.totalBytes == nil || totalBytes == nil || current.totalBytes == totalBytes,
              resolvedVerified >= current.verifiedBytes,
              resolvedVerified >= 0,
              resolvedTotal.map({ $0 > 0 && $0 <= maximumBytes && resolvedVerified <= $0 }) ?? true else {
            return false
        }
        publish(Snapshot(
            itemID: itemID,
            jobKey: jobKey,
            attempt: attempt,
            sequence: sequence,
            phase: phase,
            totalBytes: resolvedTotal,
            verifiedBytes: resolvedVerified,
            failureMessage: nil
        ))
        return true
    }

    func markSaving(itemID: String, jobKey: String) {
        transition(itemID: itemID, jobKey: jobKey, phase: .saving, failureMessage: nil)
    }

    func markWaiting(itemID: String, jobKey: String) {
        transition(itemID: itemID, jobKey: jobKey, phase: .waiting, failureMessage: nil)
    }

    func fail(itemID: String, jobKey: String, message: String) {
        transition(itemID: itemID, jobKey: jobKey, phase: .failed, failureMessage: message)
    }

    func clear(itemID: String, jobKey: String) {
        guard snapshotsByItemID[itemID]?.jobKey == jobKey else { return }
        snapshotsByItemID[itemID] = nil
        notify(itemID: itemID, snapshot: nil)
    }

    func removeAll() {
        let itemIDs = Array(snapshotsByItemID.keys)
        snapshotsByItemID.removeAll()
        itemIDs.forEach { notify(itemID: $0, snapshot: nil) }
    }

    private func transition(itemID: String, jobKey: String, phase: Snapshot.Phase, failureMessage: String?) {
        guard let current = snapshotsByItemID[itemID], current.jobKey == jobKey else { return }
        publish(Snapshot(
            itemID: current.itemID,
            jobKey: current.jobKey,
            attempt: current.attempt,
            // Sequence is the last accepted helper sequence. App-only phases
            // must not consume a helper sequence number that a resumed stream
            // may still legitimately publish.
            sequence: current.sequence,
            phase: phase,
            totalBytes: current.totalBytes,
            verifiedBytes: current.verifiedBytes,
            failureMessage: failureMessage
        ))
    }

    private func publish(_ snapshot: Snapshot) {
        snapshotsByItemID[snapshot.itemID] = snapshot
        notify(itemID: snapshot.itemID, snapshot: snapshot)
    }

    private func notify(itemID: String, snapshot: Snapshot?) {
        removeReleasedObservers()
        let handlers = observers.values
            .filter { $0.itemID == itemID }
            .map(\.handler)
        handlers.forEach { $0(snapshot) }
    }

    private func removeReleasedObservers() {
        observers = observers.filter { _, observer in
            !observer.requiresOwner || observer.owner != nil
        }
    }
}
