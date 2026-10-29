import Darwin
import Foundation

/// Only the platform-effect boundary is recorded. The socket/session/lifetime
/// owners are production; policy OR semantics belong to test_playback_policy.
@MainActor final class PlaybackPolicyController {
    static let shared = PlaybackPolicyController()
    enum Interruption { case screenSaver }
    private(set) var received: [Bool] = []
    func setInterruption(_ reason: Interruption, active: Bool) { received.append(active) }
}

/// Test-only receipts are written by the other process. The selector proves
/// distributed delivery independently of the product's block registration;
/// the two block counters distinguish sender filtering from RunLoop delivery.
@MainActor private final class ReadyReceipt: NSObject {
    private let root: URL
    private let destination: URL
    private let client: ScreenSaverActivityClient
    private var observers: [NSObjectProtocol] = []
    private var receivedObjects: [String] = []
    private var counts: [String: Int] = ["registered": 1, "selector": 0, "blockObject": 0,
                                       "blockAny": 0, "stopped": 0]
    var shouldExit = false

    init(root: URL, destination: URL) {
        self.root = ScreenSaverActivityWire.canonicalRoot(root)
        self.destination = destination
        client = ScreenSaverActivityClient(root: root)
        super.init()
        counts["pid"] = Int(getpid())
        let center = DistributedNotificationCenter.default()
        center.addObserver(self, selector: #selector(receiveReady), name: ScreenSaverActivityWire.appReady,
                           object: self.root.path, suspensionBehavior: .deliverImmediately)
        observers.append(center.addObserver(forName: ScreenSaverActivityWire.appReady,
            object: self.root.path, queue: .main) { [weak self] note in
                MainActor.assumeIsolated { self?.record("blockObject", object: note.object as? String) }
            })
        observers.append(center.addObserver(forName: ScreenSaverActivityWire.appReady,
            object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    self?.record("blockAny", object: note.object as? String)
                }
            })
        client.start()
        persist()
    }

    @objc private func receiveReady(_ note: Notification) { record("selector", object: note.object as? String) }

    private func record(_ key: String, object: String?) {
        counts[key, default: 0] += 1
        if let object { receivedObjects.append(object) }
        persist()
    }

    func stopClient() {
        client.stop()
        counts["stopped"] = 1
        persist()
    }

    func finish() {
        client.stop()
        let center = DistributedNotificationCenter.default()
        center.removeObserver(self)
        for observer in observers { center.removeObserver(observer) }
        observers.removeAll()
    }

    private func persist() {
        var payload = counts.mapValues { $0 as Any }
        payload["rootPath"] = root.path
        payload["rootStandardizedNow"] = root.standardizedFileURL.path
        payload["socketPath"] = ScreenSaverActivityWire.socketPath(root: root)
        payload["receivedObjects"] = receivedObjects
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return }
        try? data.write(to: destination, options: [.atomic])
    }
}

@main private enum ScreenSaverActivityChecks {
    private nonisolated struct Failure: Error { let description: String }

    @MainActor private static func spin(_ predicate: () -> Bool, timeout: TimeInterval = 5, line: Int = #line) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        if !predicate() { throw Failure(description: "activity state did not settle at fixture line \(line)") }
    }

    @MainActor private static func stays(_ predicate: () -> Bool, duration: TimeInterval = 0.2) -> Bool {
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            if !predicate() { return false }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return predicate()
    }

    private nonisolated static func listenerReleased(_ root: URL) -> Bool {
        guard !FileManager.default.fileExists(atPath: ScreenSaverActivityWire.socketPath(root: root)) else { return false }
        let descriptor = Darwin.open(root.appendingPathComponent("lifecycle.lock").path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { return true }
        let available = flock(descriptor, LOCK_EX | LOCK_NB) == 0
        if available { flock(descriptor, LOCK_UN) }
        Darwin.close(descriptor)
        return available
    }

    private nonisolated static func listenerAccepting(_ root: URL) -> Bool {
        guard let handle = try? ScreenSaverActivityWire.makeSocket() else { return false }
        defer { try? handle.close() }
        return (try? ScreenSaverActivityWire.withAddress(root: root) {
            Darwin.connect(handle.fileDescriptor, $0, $1) == 0
        }) == true
    }

    private nonisolated static func receipt(_ url: URL) -> [String: Int] {
        guard let data = try? Data(contentsOf: url),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return value.compactMapValues { $0 as? Int }
    }

    private nonisolated static func receiptDescription(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? "missing receipt: \(url.path)"
    }

    @MainActor static func main() throws {
        let arguments = CommandLine.arguments
        if arguments.count == 4, arguments[1] == "--persistent-client" {
            let ready = ReadyReceipt(root: URL(fileURLWithPath: arguments[2]),
                                     destination: URL(fileURLWithPath: arguments[3]))
            let input = FileHandle.standardInput
            input.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { handle.readabilityHandler = nil }
                DispatchQueue.main.async {
                    if data.isEmpty { ready.shouldExit = true }
                    else if data.contains(0x53) { ready.stopClient() }
                }
            }
            defer { input.readabilityHandler = nil; ready.finish() }
            while !ready.shouldExit { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
            return
        }
        if arguments.count == 3, arguments[1] == "--crash-client" {
            let client = ScreenSaverActivityClient(root: URL(fileURLWithPath: arguments[2]))
            client.start()
            // Parent owns and kills exactly this child; no product App or view.
            withExtendedLifetime(client) {
                while true { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
            }
        }
        let cases = URL(fileURLWithPath: arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: cases, withIntermediateDirectories: true)
        var checks: [String: Bool] = [:]

        do {
            let root = cases.appendingPathComponent("dual")
            let monitor = ScreenSaverActivityMonitor(root: root)
            let first = ScreenSaverActivityClient(root: root)
            let second = ScreenSaverActivityClient(root: root)
            defer { first.stop(); second.stop(); monitor.stop() }
            // This case checks two views sharing a socket. Cross-process
            // readiness/restart is exercised separately below.
            monitor.start()
            try spin { listenerAccepting(root) }
            first.start(); second.start()
            try spin { monitor.isActive }
            checks["TwoViewsJoinTheSameLiveActivityListener"] = monitor.isActive
            first.stop()
            checks["StoppingOneClientRetainsTheOtherClientsLease"] = stays { monitor.isActive }
            second.stop()
            try spin { !monitor.isActive }
            checks["StoppingTheLastClientReleasesOnlyItsScreenSaverReason"] = PlaybackPolicyController.shared.received.last == false
            monitor.stop()
            try spin { listenerReleased(root) }
        }

        do {
            let root = cases.appendingPathComponent("restart")
            let firstObject = ScreenSaverActivityWire.canonicalRoot(root).path
            let firstMonitor = ScreenSaverActivityMonitor(root: root)
            let receiptURL = cases.appendingPathComponent("restart-receipts.json")
            let control = Pipe()
            let child = Process()
            child.executableURL = URL(fileURLWithPath: arguments[0])
            child.arguments = ["--persistent-client", root.path, receiptURL.path]
            child.standardInput = control
            child.standardOutput = FileHandle.nullDevice
            child.standardError = FileHandle.standardError
            try child.run()
            defer {
                try? control.fileHandleForWriting.close()
                if child.isRunning { Darwin.kill(child.processIdentifier, SIGKILL) }
                child.waitUntilExit()
                firstMonitor.stop()
            }
            try spin { receipt(receiptURL)["registered"] == 1 }
            checks["ClientRunsInAnIndependentProcess"] = receipt(receiptURL)["pid"] == Int(child.processIdentifier)
                && child.processIdentifier != getpid()
            checks["ClientStartsWhileTheActivityRootDoesNotYetExist"] = !FileManager.default.fileExists(atPath: root.path)
            firstMonitor.start()
            do { try spin { firstMonitor.isActive } }
            catch {
                throw Failure(description: "cross-process initial connection failed: "
                    + "childRunning=\(child.isRunning) firstObject=\(firstObject) "
                    + "receipts=\(receiptDescription(receiptURL)); \(error)")
            }
            checks["ClientStartedBeforeMonitorJoinsTheReadyListener"] = firstMonitor.isActive
            checks["NotificationRootIdentitySurvivesDirectoryCreation"] = ScreenSaverActivityWire.canonicalRoot(root).path == firstObject
            firstMonitor.stop()
            try spin { listenerReleased(root) }
            let beforeRestart = receipt(receiptURL)["selector", default: 0]
            let restartObject = ScreenSaverActivityWire.canonicalRoot(root).path
            let restarted = ScreenSaverActivityMonitor(root: root)
            defer { restarted.stop() }
            // The original child/client remains alive. No second client.start
            // call may hide a missing cross-process readiness reconnection.
            restarted.start()
            do {
                try spin {
                    restarted.isActive && receipt(receiptURL)["selector", default: 0] > beforeRestart
                }
            } catch {
                throw Failure(description: "cross-process restart failed: active=\(restarted.isActive) "
                    + "childRunning=\(child.isRunning) firstObject=\(firstObject) restartObject=\(restartObject) "
                    + "receipts=\(receiptDescription(receiptURL)); \(error)")
            }
            checks["AppReadyArrivesInTheExistingClientProcess"] = receipt(receiptURL)["selector", default: 0] > beforeRestart
            checks["AppReadyReconnectsAnAlreadyActiveClientAfterMonitorRestart"] = restarted.isActive
            // Queue a ready event across processes and revoke the client via
            // its stdin. A subsequent delivered ready must not revive it.
            DistributedNotificationCenter.default().postNotificationName(ScreenSaverActivityWire.appReady,
                object: firstObject, userInfo: nil, deliverImmediately: true)
            try control.fileHandleForWriting.write(contentsOf: Data([0x53]))
            try spin { !restarted.isActive && receipt(receiptURL)["stopped"] == 1 }
            checks["ReconnectedClientStopDoesNotLeaveAnOldConnectionActive"] = !restarted.isActive
            let before = receipt(receiptURL)["selector", default: 0]
            DistributedNotificationCenter.default().postNotificationName(ScreenSaverActivityWire.appReady,
                object: firstObject, userInfo: nil, deliverImmediately: true)
            try spin { receipt(receiptURL)["selector", default: 0] > before }
            checks["StoppedClientCannotBeRevivedByQueuedOrLaterReadyEvents"] = stays { !restarted.isActive }
            let delivered = try JSONSerialization.data(withJSONObject: receipt(receiptURL), options: [.sortedKeys])
            FileHandle.standardError.write(Data("activity-ready-receipts: ".utf8) + delivered + Data([0x0a]))
            restarted.stop()
            try spin { listenerReleased(root) }
        }

        do {
            let root = cases.appendingPathComponent("crash")
            let monitor = ScreenSaverActivityMonitor(root: root)
            defer { monitor.stop() }
            monitor.start()
            try spin { listenerAccepting(root) }
            let child = Process()
            child.executableURL = URL(fileURLWithPath: arguments[0])
            child.arguments = ["--crash-client", root.path]
            child.standardOutput = FileHandle.nullDevice
            child.standardError = FileHandle.nullDevice
            try child.run()
            defer {
                if child.isRunning { Darwin.kill(child.processIdentifier, SIGKILL) }
                child.waitUntilExit()
            }
            try spin { monitor.isActive }
            let remaining = ScreenSaverActivityClient(root: root)
            defer { remaining.stop() }
            remaining.start()
            _ = stays { monitor.isActive }
            Darwin.kill(child.processIdentifier, SIGKILL)
            checks["ClientCrashDoesNotReleaseAnotherProcessesLiveConnection"] = stays { monitor.isActive }
            remaining.stop()
            try spin { !monitor.isActive }
            checks["CrashedClientEOFReleasesItsOriginalConnection"] = !monitor.isActive
                && PlaybackPolicyController.shared.received.last == false
            let next = ScreenSaverActivityClient(root: root)
            defer { next.stop() }
            next.start()
            try spin { monitor.isActive }
            next.stop()
            try spin { !monitor.isActive }
            checks["ListenerRemainsUsableAfterAClientCrash"] = !monitor.isActive
            monitor.stop()
            try spin { listenerReleased(root) }
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), as: UTF8.self))
    }
}
