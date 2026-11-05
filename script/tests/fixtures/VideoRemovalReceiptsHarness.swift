import Foundation

// ACTUAL_RESULT_TYPES

// The barrier surrounds the original unlink body, not its result. It lets the
// main queue reset the source while an already-admitted operation is in flight.
final class PhysicalFileProbe: @unchecked Sendable {
    enum Stage: Equatable { case admission, unlink, synchronization }
    static let shared = PhysicalFileProbe()
    private let lock = NSLock()
    private var records: [(String, Bool, Stage)] = []
    private var heldPath: String?
    private var heldStage = Stage.synchronization
    private var didHold = false
    private var isPaused = false
    private var release: DispatchSemaphore?
    func begin(holding path: String? = nil, stage: Stage = .synchronization) -> DispatchSemaphore {
        let semaphore = DispatchSemaphore(value: 0)
        lock.lock(); records = []; heldPath = path.map(Self.fileIdentity); heldStage = stage
        didHold = false; isPaused = false; release = semaphore; lock.unlock()
        return semaphore
    }
    private func observe(_ url: URL, stage: Stage) {
        lock.lock()
        records.append((url.path, Thread.isMainThread, stage))
        let pause = heldPath == Self.fileIdentity(url.path) && heldStage == stage && !didHold
        if pause { didHold = true; isPaused = true }
        let semaphore = release
        lock.unlock()
        if pause {
            semaphore?.wait()
            lock.lock(); isPaused = false; lock.unlock()
        }
    }
    // Compare only this fixture's held filesystem leaf, not product identity.
    // A standardized URL may spell /private/tmp as /tmp; the existing parent
    // resolves equally both before and after the source itself is unlinked.
    private static func fileIdentity(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        return url.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(url.lastPathComponent).path
    }
    var isHolding: Bool { lock.lock(); defer { lock.unlock() }; return isPaused }
    var diagnostic: String {
        lock.lock(); defer { lock.unlock() }
        return "held=\(heldPath ?? "nil") stage=\(heldStage) paused=\(isPaused) reads=\(records)"
    }
    func beforeAdmission(_ url: URL) { observe(url, stage: .admission) }
    func beforeUnlink(_ url: URL) { observe(url, stage: .unlink) }
    func beforeSynchronization(_ url: URL) { observe(url, stage: .synchronization) }
    private func reads(at stage: Stage) -> [(String, Bool)] {
        lock.lock(); defer { lock.unlock() }
        return records.filter { $0.2 == stage }.map { ($0.0, $0.1) }
    }
    var reads: [(String, Bool)] { reads(at: .synchronization) }
    var admissionReads: [(String, Bool)] { reads(at: .admission) }
    var unlinkReads: [(String, Bool)] { reads(at: .unlink) }
}

private final class DerivedFileProbe {
    var reads: [String] = []
    func exists(_ path: String) -> Bool {
        reads.append(path)
        return FileManager.default.fileExists(atPath: path)
    }
}

// Only runtime effects are leaves. The production Stop body demonstrates that
// playback's epoch does not revoke a separately accepted source operation.
private final class WallpaperEngine {
    static let shared = WallpaperEngine()
    func adoptIntentEpoch(_ value: UInt64) {}
    func stopPlayback() {}
}
private final class SceneDaemonClient {
    static let shared = SceneDaemonClient()
    func stop() {}
}

private final class WallpaperManager {
    var protectedSystemDesktopURLs = Set<URL>()
    let deletionQueue = DispatchQueue(label: "mwx.tests.video-removal", qos: .utility)
    let probe = DerivedFileProbe()
    private var storedWallpapers: [VideoWallpaper] = []
    var wallpaperReads = 0
    var normalizationCalls = 0
    var wallpapers: [VideoWallpaper] {
        get { wallpaperReads += 1; return storedWallpapers }
        set { storedWallpapers = newValue }
    }
    var playbackSwitch = PlaybackSwitchTransaction()
    var switchSelections: [UUID: RuntimeSwitchSelection] = [:]
    var currentWallpaper: VideoWallpaper?
    var pendingWallpaper: VideoWallpaper?
    var wallpaperIndexSaveEpoch: UInt64 = 0
    var playbackIntentEpoch: UInt64 = 0
    var allowsLibraryMutation = true
    var preservesLegacyMigrationInputs = false
    var lastWorkshopPlaybackRecordID: String?
    var switchDeadline: DispatchWorkItem?
    var pendingSystemWallpaperSyncWorkItem: DispatchWorkItem?
    var isPlaying = true
    var libraryPlaybackStopped: (() -> Void)?
    var saves: [Bool] = []
    var autoRemovedTitles: [[String]] = []
    func saveWallpapers() { saves.append(Thread.isMainThread) }
    func pathExists(_ path: String) -> Bool { probe.exists(path) }
    func thumbnailOutputURL(forKey key: String) -> URL { URL(fileURLWithPath: key).appendingPathExtension("generated-thumb") }
    func staticFrameOutputURL(forKey key: String) -> URL { URL(fileURLWithPath: key).appendingPathExtension("generated-frame") }
    func cacheKey(forNormalizedPath path: String) -> String { path }
    func clearThumbnailGenerationFailure(for path: String) {}
    func removeThumbnailInFlight(for path: String) {}
    func finishStaticFrameSchedule(for path: String) {}
    func persistCurrentWallpaperSnapshot() {}
    func stopAutoSwitchTimer() {}
    func presentAutoRemovedMissingIndexedFilesAlert(titles: [String]) { autoRemovedTitles.append(titles) }
    func beginPlaybackIntent() -> UInt64 { playbackIntentEpoch &+= 1; return playbackIntentEpoch }
    func resetIndex(_ replacement: [VideoWallpaper]) { wallpaperIndexSaveEpoch &+= 1; wallpapers = replacement }
    func holdQueue() -> (DispatchSemaphore, DispatchSemaphore) {
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        enqueueDeletionTask { entered.signal(); release.wait() }
        return (entered, release)
    }
    // ACTUAL_REMOVAL_METHODS
}

private final class SILService {
    struct Row {
        static var idReads = 0
        private let rawID: String
        var id: String { Self.idReads += 1; return rawID }
        let path: String
        init(id: String, path: String) { rawID = id; self.path = path }
    }
    private var storedWallpapers: [Row] = []
    var wallpaperReads = 0
    var wallpapers: [Row] {
        get { wallpaperReads += 1; return storedWallpapers }
        set { storedWallpapers = newValue }
    }
    var allowsLibraryMutation = true
    var metadataLoadGeneration: UInt64 = 0
    private static func normalizedPath(_ path: String) -> String { URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path }
    // ACTUAL_IMAGE_SOURCE_DELETE
}

@main private enum VideoRemovalReceiptsChecks {
    static func wait(_ reason: String, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(4)
        while !condition() {
            if Date() >= deadline {
                FileHandle.standardError.write(Data((PhysicalFileProbe.shared.diagnostic + "\n").utf8))
                preconditionFailure(reason)
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.002))
        }
    }
    static func pump() { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    static func file(_ url: URL, _ bytes: [UInt8] = [17, 23]) throws { try Data(bytes).write(to: url) }
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        var checks: [String: Bool] = [:]
        var work: [String: Int] = [:]
        var imageWork: [String: Int] = [:]
        func row(_ group: String, _ id: String) throws -> VideoWallpaper {
            let directory = root.appendingPathComponent(group)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let name = id.utf8.elementsEqual("e\u{301}".utf8) ? "nfd.mp4" : "nfc-" + id + ".mp4"
            let url = directory.appendingPathComponent(name)
            let value = VideoWallpaper(id: id, title: id, path: url.path,
                thumbnailPath: url.appendingPathExtension("captured-thumb").path,
                staticFramePath: url.appendingPathExtension("captured-frame").path)
            try file(url)
            for path in derived(value) { try file(URL(fileURLWithPath: path), [31]) }
            return value
        }
        func intact(_ value: VideoWallpaper) -> Bool { (try? Data(contentsOf: URL(fileURLWithPath: value.path))) == Data([17, 23]) }
        func derivedPresent(_ value: VideoWallpaper) -> Bool { derived(value).allSatisfy { FileManager.default.fileExists(atPath: $0) } }
        func drain(_ manager: WallpaperManager) {
            var completed = false
            manager.enqueueDeletionTask { DispatchQueue.main.async { completed = true } }
            wait("deletion queue did not drain") { completed }; pump()
        }
        do {
            let manager = WallpaperManager(), first = try row("normal", "one"), other = try row("normal", "two")
            manager.wallpapers = [first, other]
            _ = PhysicalFileProbe.shared.begin()
            var receipts: [WallpaperSourceDeletionResult] = []
            manager.deleteSourceFiles([first]) { receipts.append($0) }
            wait("physical source delete did not finish") { receipts.count == 1 }; drain(manager)
            checks["explicit-file-delete-has-real-receipt-and-keeps-source-facts-derived-and-neighbor"] = receipts[0].items.first?.succeeded == true
                && receipts[0].items.first?.sourceFileDeleted == true && !FileManager.default.fileExists(atPath: first.path)
                && intact(other) && derivedPresent(first) && manager.wallpapers == [first, other] && manager.saves.isEmpty
            checks["final-unlink-runs-in-original-main-admission-and-durability-stays-off-main"] = PhysicalFileProbe.shared.reads.count == 1
                && PhysicalFileProbe.shared.reads.allSatisfy { !$0.1 } && PhysicalFileProbe.shared.unlinkReads.count == 1
                && PhysicalFileProbe.shared.unlinkReads.allSatisfy { $0.1 } && receipts.count == 1
        }
        do {
            let manager = WallpaperManager(), original = try row("queued", "old")
            manager.wallpapers = [original]
            let hold = manager.holdQueue(); precondition(hold.0.wait(timeout: .now() + 3) == .success)
            _ = PhysicalFileProbe.shared.begin()
            var receipts: [WallpaperSourceDeletionResult] = []
            manager.deleteSourceFiles([original]) { receipts.append($0) }
            let replacement = VideoWallpaper(id: original.id, title: "Reset replacement", path: original.path)
            manager.resetIndex([replacement]); hold.1.signal()
            wait("queued reset callback missing") { receipts.count == 1 }; drain(manager)
            checks["queued-reset-revokes-before-io-with-one-failed-receipt"] = manager.wallpapers == [replacement]
                && PhysicalFileProbe.shared.reads.isEmpty && PhysicalFileProbe.shared.unlinkReads.isEmpty
                && manager.saves.isEmpty && derivedPresent(original) && intact(original)
                && receipts.count == 1 && receipts[0].items.first?.succeeded == false && receipts[0].items.first?.sourceFileDeleted == false
        }
        do {
            let manager = WallpaperManager(), first = try row("inflight", "first"), next = try row("inflight", "next")
            manager.wallpapers = [first, next]
            let release = PhysicalFileProbe.shared.begin(holding: first.path)
            var receipts: [WallpaperSourceDeletionResult] = []
            manager.deleteSourceFiles([first, next]) { receipts.append($0) }
            wait("inflight operation never reached held real durability boundary") {
                PhysicalFileProbe.shared.isHolding && PhysicalFileProbe.shared.reads.count == 1
            }
            var mainRan = false
            DispatchQueue.main.async { mainRan = true }
            wait("main queue blocked behind source IO") { mainRan }
            checks["main-queue-remains-responsive-during-blocked-source-io"] = mainRan && receipts.isEmpty
            let replacement = VideoWallpaper(id: "reset-new", title: "New source", path: next.path)
            manager.resetIndex([replacement]); manager.currentWallpaper = replacement; manager.pendingWallpaper = replacement
            release.signal()
            wait("inflight reset receipt missing") { receipts.count == 1 }; drain(manager)
            checks["inflight-reset-keeps-new-index-current-pending-and-revokes-next-io"] = manager.wallpapers == [replacement]
                && manager.currentWallpaper == replacement && manager.pendingWallpaper == replacement && manager.saves.isEmpty
                && intact(next) && derivedPresent(next) && PhysicalFileProbe.shared.reads.count == 1
                && receipts[0].items.filter(\.succeeded).count == 1 && receipts[0].items.filter { !$0.succeeded }.count == 1
            checks["already-admitted-first-unlink-reports-real-disk-effect-without-rollback-claim"] = !FileManager.default.fileExists(atPath: first.path)
                && derivedPresent(first) && receipts[0].items.first?.sourceFileDeleted == true && receipts.count == 1
        }
        do {
            let manager = WallpaperManager(), original = try row("sync-failure", "one")
            manager.wallpapers = [original]
            let release = PhysicalFileProbe.shared.begin(holding: original.path)
            var result: WallpaperSourceDeletionResult?
            manager.deleteSourceFiles([original]) { result = $0 }
            wait("sync failure never reached real durability boundary") { PhysicalFileProbe.shared.isHolding && !PhysicalFileProbe.shared.reads.isEmpty }
            let directory = URL(fileURLWithPath: original.path).deletingLastPathComponent()
            let moved = directory.appendingPathExtension("moved")
            try FileManager.default.moveItem(at: directory, to: moved)
            release.signal(); wait("post-unlink sync failure did not report") { result != nil }
            checks["actual-directory-ack-failure-reports-deleted-file-but-no-logical-success"] = result?.items.first?.succeeded == false
                && result?.items.first?.sourceFileDeleted == true && result?.items.first?.failureMessage?.isEmpty == false
                && !FileManager.default.fileExists(atPath: moved.appendingPathComponent(URL(fileURLWithPath: original.path).lastPathComponent).path)
                && manager.wallpapers == [original] && manager.saves.isEmpty
        }
        do {
            let manager = WallpaperManager(), original = try row("replacement-id", "old")
            manager.wallpapers = [original]
            let hold = manager.holdQueue(); precondition(hold.0.wait(timeout: .now() + 3) == .success)
            var receipts: [WallpaperSourceDeletionResult] = []
            manager.deleteSourceFiles([original]) { receipts.append($0) }
            let replacement = VideoWallpaper(id: "new-ID", title: "Same path new source", path: original.path)
            manager.wallpapers = [replacement]; hold.1.signal()
            wait("new-id callback missing") { receipts.count == 1 }
            checks["queued-command-cannot-delete-same-path-new-id-source"] = manager.wallpapers == [replacement]
                && intact(original) && receipts[0].items.first?.succeeded == false
        }
        do {
            let manager = WallpaperManager(), original = try row("stop", "one")
            manager.wallpapers = [original]
            let hold = manager.holdQueue(); precondition(hold.0.wait(timeout: .now() + 3) == .success)
            let indexEpoch = manager.wallpaperIndexSaveEpoch
            var receipts: [WallpaperSourceDeletionResult] = []
            manager.deleteSourceFiles([original]) { receipts.append($0) }
            manager.stopCurrentPlayback(); hold.1.signal()
            wait("ordinary Stop revoked source operation") { receipts.count == 1 }
            checks["ordinary-stop-does-not-revoke-source-epoch-or-file-receipt"] = manager.wallpaperIndexSaveEpoch == indexEpoch
                && manager.playbackIntentEpoch == 1 && !manager.isPlaying && receipts[0].items.first?.succeeded == true
                && !FileManager.default.fileExists(atPath: original.path) && manager.wallpapers == [original]
        }
        do {
            let manager = WallpaperManager(), nfc = try row("opaque", "\u{e9}"), nfd = try row("opaque", "e\u{301}")
            manager.wallpapers = [nfc, nfd]
            var receipts: [WallpaperSourceDeletionResult] = []
            manager.deleteSourceFiles([nfd]) { receipts.append($0) }
            wait("opaque deletion never completed") { receipts.count == 1 }
            checks["physical-selection-distinguishes-opaque-unicode-and-preserves-neighbor-bytes"] = intact(nfc)
                && !FileManager.default.fileExists(atPath: nfd.path) && receipts[0].items.count == 1
                && receipts[0].items[0].reference.sourceID.utf8.elementsEqual(nfd.id.utf8) && manager.wallpapers.count == 2
            manager.deleteSourceFiles([nfc]) { receipts.append($0) }
            wait("second opaque deletion never completed") { receipts.count == 2 }
            checks["both-opaque-source-files-are-independently-removable-with-index-facts-kept"] = !FileManager.default.fileExists(atPath: nfc.path)
                && receipts.allSatisfy { $0.items.first?.succeeded == true } && manager.wallpapers.count == 2
        }
        do {
            let manager = WallpaperManager(), original = try row("readonly", "one")
            manager.wallpapers = [original]; manager.allowsLibraryMutation = false
            _ = PhysicalFileProbe.shared.begin()
            var receipts: [WallpaperSourceDeletionResult] = []
            manager.deleteSourceFiles([original]) { receipts.append($0) }; drain(manager)
            checks["recovery-readonly-refuses-before-queue-or-unlink"] = manager.wallpapers == [original] && intact(original)
                && derivedPresent(original) && PhysicalFileProbe.shared.reads.isEmpty && receipts.count == 1
                && receipts[0].items.first?.succeeded == false && manager.saves.isEmpty
        }
        do {
            let manager = WallpaperManager(), original = try row("busy", "one")
            manager.wallpapers = [original]
            let (ticket, _) = manager.playbackSwitch.begin(.video)
            manager.switchSelections[ticket.id] = .video(original)
            var result: WallpaperSourceDeletionResult?
            manager.deleteSourceFiles([original]) { result = $0 }
            checks["original-pending-runtime-refuses-delete-without-stopping-ticket"] = result?.items.first?.succeeded == false
                && manager.playbackSwitch.pending?.selection.ticket == ticket && intact(original)
        }
        do {
            let manager = WallpaperManager(), original = try row("late-busy", "one")
            manager.wallpapers = [original]
            let release = PhysicalFileProbe.shared.begin(holding: original.path, stage: .admission)
            var result: WallpaperSourceDeletionResult?
            manager.deleteSourceFiles([original]) { result = $0 }
            wait("late-busy deletion never reached final admission boundary") { PhysicalFileProbe.shared.isHolding && !PhysicalFileProbe.shared.admissionReads.isEmpty }
            let (ticket, _) = manager.playbackSwitch.begin(.video)
            manager.switchSelections[ticket.id] = .video(original)
            release.signal(); wait("late-busy completion missing") { result != nil }
            checks["video-new-pending-before-final-admission-prevents-unlink-without-a-second-owner"] = result?.items.first?.succeeded == false
                && intact(original) && PhysicalFileProbe.shared.unlinkReads.isEmpty
                && manager.playbackSwitch.pending?.selection.ticket == ticket
        }
        do {
            let original = try row("late-image-busy", "one")
            let images = SILService(); images.wallpapers = [.init(id: original.id, path: original.path)]
            let release = PhysicalFileProbe.shared.begin(holding: original.path, stage: .admission)
            var busy = false, result: WallpaperSourceDeletionResult?
            images.deleteSourceFiles(ids: [original.id], isInUse: { _ in busy }) { result = $0 }
            wait("late image deletion never reached final admission boundary") { PhysicalFileProbe.shared.isHolding && !PhysicalFileProbe.shared.admissionReads.isEmpty }
            busy = true
            release.signal(); wait("late image busy completion missing") { result != nil }
            checks["image-new-runtime-claim-before-final-admission-prevents-unlink"] = result?.items.first?.succeeded == false
                && intact(original) && PhysicalFileProbe.shared.unlinkReads.isEmpty && images.wallpapers.count == 1
        }
        do {
            let manager = WallpaperManager(), original = try row("replacement-file", "one")
            manager.wallpapers = [original]
            let hold = manager.holdQueue(); precondition(hold.0.wait(timeout: .now() + 3) == .success)
            var result: WallpaperSourceDeletionResult?
            manager.deleteSourceFiles([original]) { result = $0 }
            try Data([88]).write(to: URL(fileURLWithPath: original.path), options: .atomic)
            hold.1.signal(); wait("replacement-inode callback missing") { result != nil }
            checks["new-inode-at-the-same-source-path-is-not-unlinked"] = result?.items.first?.succeeded == false
                && (try? Data(contentsOf: URL(fileURLWithPath: original.path))) == Data([88])
        }
        do {
            let nfc = try row("image", "\u{e9}"), nfd = try row("image", "e\u{301}")
            let images = SILService(); images.wallpapers = [.init(id: nfc.id, path: nfc.path), .init(id: nfd.id, path: nfd.path)]
            var result: WallpaperSourceDeletionResult?
            images.deleteSourceFiles(ids: [nfd.id], isInUse: { _ in true }) { result = $0 }
            checks["image-delete-obeys-injected-original-runtime-busy-fact"] = result?.items.first?.succeeded == false && intact(nfd)
            result = nil
            images.deleteSourceFiles(ids: [nfd.id], isInUse: { _ in false }) { result = $0 }
            wait("image physical delete did not finish") { result != nil }
            checks["image-opaque-id-target-has-real-receipt-and-keeps-neighbor-and-index"] = result?.items.first?.succeeded == true
                && result?.items.first?.reference.sourceID.utf8.elementsEqual(nfd.id.utf8) == true
                && !FileManager.default.fileExists(atPath: nfd.path) && intact(nfc) && images.wallpapers.count == 2
            result = nil
            images.deleteSourceFiles(ids: [nfc.id], isInUse: { _ in false }) { result = $0 }
            wait("second image source delete did not finish") { result != nil }
            checks["image-source-array-preserves-both-opaque-identities-through-owner"] = result?.items.first?.succeeded == true
                && !FileManager.default.fileExists(atPath: nfc.path) && images.wallpapers.count == 2
        }
        do {
            let target = try row("symlink", "target")
            let link = URL(fileURLWithPath: target.path).deletingLastPathComponent().appendingPathComponent("link.mp4")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: target.path))
            let manager = WallpaperManager(), linked = VideoWallpaper(id: "link", title: "link", path: link.path)
            manager.wallpapers = [linked]
            var video: WallpaperSourceDeletionResult?
            manager.deleteSourceFiles([linked]) { video = $0 }
            let images = SILService(); images.wallpapers = [.init(id: "image-link", path: link.path)]
            var image: WallpaperSourceDeletionResult?
            images.deleteSourceFiles(ids: ["image-link"], isInUse: { _ in false }) { image = $0 }
            checks["both-real-local-owners-refuse-symlink-before-unlinking-target"] = video?.items.first?.succeeded == false
                && image?.items.first?.succeeded == false && intact(target)
                && (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil
        }
        do {
            let manager = WallpaperManager(), missing = try row("purge", "missing"), neighbor = try row("purge", "neighbor")
            try FileManager.default.removeItem(atPath: missing.path)
            manager.wallpapers = [missing, neighbor]
            manager.preservesLegacyMigrationInputs = true
            manager.purgeMissingIndexedWallpapersFromLibrary([missing], notifyUser: true)
            checks["recovery-blocks-automatic-purge-before-derived-or-index-writes"] = manager.wallpapers == [missing, neighbor]
                && derivedPresent(missing) && manager.probe.reads.isEmpty && manager.saves.isEmpty && manager.autoRemovedTitles.isEmpty
            manager.preservesLegacyMigrationInputs = false
            manager.purgeMissingIndexedWallpapersFromLibrary([missing], notifyUser: true)
            checks["real-missing-source-purge-keeps-neighbor-and-cleans-only-derived-index-facts"] = manager.wallpapers == [neighbor]
                && intact(neighbor) && derivedPresent(neighbor) && derived(missing).allSatisfy { !FileManager.default.fileExists(atPath: $0) }
                && manager.saves == [true] && manager.autoRemovedTitles == [[missing.displayTitle]]
        }
        do {
            let manager = WallpaperManager(), nfc = try row("purge-opaque", "\u{e9}"), nfd = try row("purge-opaque", "e\u{301}")
            let replacement = VideoWallpaper(id: "new-ID", title: "same path replacement", path: nfd.path)
            manager.wallpapers = [nfc, nfd, replacement]
            manager.applyLibraryRemoval(paths: [manager.normalizedPath(nfd.path)], removedIDs: [Data(nfd.id.utf8)])
            checks["actual-purge-commit-matches-both-raw-id-and-path-without-removing-replacement"] = manager.wallpapers.count == 2
                && manager.wallpapers[0].id.utf8.elementsEqual(nfc.id.utf8) && manager.wallpapers[1].id == replacement.id
                && intact(nfc) && intact(nfd)
        }
        do {
            let manager = WallpaperManager()
            let rows = try (0..<16).map { try row("reverse-batch", "row-\($0)") }
            manager.wallpapers = rows
            let targets = Array(manager.wallpapers.reversed()) + [rows[3], rows[0]]
            manager.normalizationCalls = 0
            let busy = manager.isLocalSourceFileInUse(rows[0].path)
            work["busyConsumerNormalizations"] = manager.normalizationCalls
            checks["actual-busy-consumer-normalizes-its-one-raw-input"] = !busy && manager.normalizationCalls == 1
            let hold = manager.holdQueue(); precondition(hold.0.wait(timeout: .now() + 3) == .success)
            _ = PhysicalFileProbe.shared.begin()
            manager.wallpaperReads = 0; manager.normalizationCalls = 0
            var receipts: [WallpaperSourceDeletionResult] = []
            manager.deleteSourceFiles(targets) { receipts.append($0) }
            let preparationReads = manager.wallpaperReads, preparationNormalizations = manager.normalizationCalls
            work["preparationReads"] = preparationReads
            work["preparationNormalizations"] = preparationNormalizations
            checks["batch-preparation-retains-all-files-until-the-original-queue-runs"] = receipts.isEmpty && rows.allSatisfy(intact)
            hold.1.signal(); wait("reversed batch receipt missing") { receipts.count == 1 }; drain(manager)
            let finalReads = manager.wallpaperReads - preparationReads
            work["finalNormalizations"] = manager.normalizationCalls - preparationNormalizations
            checks["reverse-current-row-batch-deduplicates-targets-and-returns-one-complete-receipt"] = receipts.count == 1
                && receipts[0].items.map(\.reference.sourceID) == rows.reversed().map(\.id)
                && receipts[0].items.allSatisfy { $0.succeeded && $0.sourceFileDeleted }
                && rows.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) && derivedPresent($0) }
                && manager.wallpapers == rows && manager.saves.isEmpty
            checks["batch-final-admission-reloads-current-rows-before-each-real-unlink"] = finalReads == rows.count
                && PhysicalFileProbe.shared.unlinkReads.count == rows.count
                && PhysicalFileProbe.shared.unlinkReads.allSatisfy { $0.1 }
                && PhysicalFileProbe.shared.reads.count == rows.count && PhysicalFileProbe.shared.reads.allSatisfy { !$0.1 }
        }
        do {
            let manager = WallpaperManager(), stale = try row("direct-stale", "old"), neighbor = try row("direct-stale", "neighbor")
            manager.wallpapers = [neighbor]
            let hold = manager.holdQueue(); precondition(hold.0.wait(timeout: .now() + 3) == .success)
            _ = PhysicalFileProbe.shared.begin()
            var receipts: [WallpaperSourceDeletionResult] = []
            manager.deleteSourceFiles([stale]) { receipts.append($0) }
            hold.1.signal(); wait("stale direct input did not settle") { receipts.count == 1 }; drain(manager)
            checks["stale-direct-input-eventually-refuses-with-one-receipt-and-preserves-every-file"] = receipts.count == 1
                && receipts[0].items.count == 1 && receipts[0].items[0].reference == .init(provider: .videoLibrary, sourceID: stale.id)
                && !receipts[0].items[0].succeeded && !receipts[0].items[0].sourceFileDeleted
                && intact(stale) && intact(neighbor) && derivedPresent(stale) && derivedPresent(neighbor)
                && PhysicalFileProbe.shared.unlinkReads.isEmpty && manager.wallpapers == [neighbor] && manager.saves.isEmpty
        }
        do {
            let rows = try (0..<16).map { try row("image-batch", "row-\($0)") }
                + [row("image-batch", "\u{e9}"), row("image-batch", "e\u{301}")]
            let images = SILService(); images.wallpapers = rows.map { .init(id: $0.id, path: $0.path) }
            _ = PhysicalFileProbe.shared.begin()
            var prepared: [String] = [], result: WallpaperSourceDeletionResult?
            images.wallpaperReads = 0; SILService.Row.idReads = 0
            images.deleteSourceFiles(ids: rows.reversed().map(\.id) + [rows[3].id, rows[0].id], isInUse: {
                prepared.append($0.path); return false
            }) { result = $0 }
            imageWork["batchArrayReads"] = images.wallpaperReads; imageWork["batchIDReads"] = SILService.Row.idReads
            let order = prepared
            checks["image-batch-preparation-keeps-sources-and-delays-final-admission"] = result == nil && rows.allSatisfy(intact)
            wait("image batch completion missing") { result != nil }
            checks["image-batch-deduplicates-raw-ids-and-retains-original-set-preparation-order"] = result?.items.count == rows.count
                && result?.items.map(\.sourceURL.path) == order && result?.items.allSatisfy { $0.succeeded && $0.sourceFileDeleted } == true
                && rows.allSatisfy { value in result!.items.contains { $0.reference.sourceID.utf8.elementsEqual(value.id.utf8) }
                    && !FileManager.default.fileExists(atPath: value.path) && derivedPresent(value) }
        }
        for busy in [false, true] {
            let first = try row("image-first-\(busy)", "first"), fallback = try row("image-first-\(busy)", "fallback")
            if !busy { try FileManager.default.removeItem(atPath: first.path) }
            let images = SILService(); images.wallpapers = [.init(id: first.id, path: first.path), .init(id: first.id, path: fallback.path)]
            var result: WallpaperSourceDeletionResult?
            images.wallpaperReads = 0; SILService.Row.idReads = 0
            images.deleteSourceFiles(ids: [first.id, first.id], isInUse: { _ in busy }) { result = $0 }
            imageWork["firstArrayReads"] = images.wallpaperReads; imageWork["firstIDReads"] = SILService.Row.idReads
            checks["image-first-duplicate-\(busy ? "busy" : "missing")-never-falls-back"] = result?.items.count == 1
                && result?.items.first?.sourceURL == URL(fileURLWithPath: first.path).standardizedFileURL
                && result?.items.first?.succeeded == false && intact(fallback) && (!busy || intact(first))
        }
        for ids in [[], ["unknown"]] {
            let source = try row("image-empty-\(ids.count)", "one"), images = SILService()
            images.wallpapers = [.init(id: source.id, path: source.path)]
            var result: WallpaperSourceDeletionResult?, busyCalls = 0
            images.wallpaperReads = 0; SILService.Row.idReads = 0
            images.deleteSourceFiles(ids: ids, isInUse: { _ in busyCalls += 1; return false }) { result = $0 }
            if ids.isEmpty { imageWork["emptyArrayReads"] = images.wallpaperReads; imageWork["emptyIDReads"] = SILService.Row.idReads }
            checks["image-empty-or-unknown-\(ids.count)-skips-file-preparation"] = result?.items.isEmpty == true && busyCalls == 0 && intact(source)
        }
        do {
            let source = try row("image-generation", "one"), images = SILService()
            images.wallpapers = [.init(id: source.id, path: source.path)]
            let release = PhysicalFileProbe.shared.begin(holding: source.path, stage: .admission)
            var result: WallpaperSourceDeletionResult?
            images.deleteSourceFiles(ids: [source.id], isInUse: { _ in false }) { result = $0 }
            wait("image generation boundary missing") { PhysicalFileProbe.shared.isHolding }
            images.metadataLoadGeneration &+= 1
            release.signal(); wait("image generation receipt missing") { result != nil }
            checks["image-generation-revocation-before-final-admission-keeps-source"] = result?.items.first?.succeeded == false
                && intact(source) && PhysicalFileProbe.shared.unlinkReads.isEmpty
        }
        do {
            let rows = try [row("image-mutating-callback", "one"), row("image-mutating-callback", "two")], images = SILService()
            images.wallpapers = rows.map { .init(id: $0.id, path: $0.path) }
            _ = PhysicalFileProbe.shared.begin()
            var result: WallpaperSourceDeletionResult?
            images.deleteSourceFiles(ids: rows.map(\.id), isInUse: { _ in images.wallpapers = []; return false }) { result = $0 }
            wait("mutating image callback receipt missing") { result != nil }
            checks["image-nonproduct-mutating-callback-cannot-unlink-stale-prepared-source"] = result?.items.isEmpty == false
                && result?.items.allSatisfy { !$0.succeeded && !$0.sourceFileDeleted } == true
                && rows.allSatisfy(intact) && images.wallpapers.isEmpty && PhysicalFileProbe.shared.unlinkReads.isEmpty
            FileHandle.standardError.write(Data("Image callback receipts: \(result!.items.count)\n".utf8))
        }
        FileHandle.standardError.write(Data("Image removal work: \(String(data: try JSONEncoder().encode(imageWork), encoding: .utf8)!)\n".utf8))
        FileHandle.standardError.write(Data("Video removal work: \(String(data: try JSONEncoder().encode(work), encoding: .utf8)!)\n".utf8))
        print(String(data: try JSONEncoder().encode(checks), encoding: .utf8)!)
    }

    static func derived(_ value: VideoWallpaper) -> [String] {
        let url = URL(fileURLWithPath: value.path)
        return [value.thumbnailPath!, value.staticFramePath!, url.appendingPathExtension("generated-thumb").path,
                url.appendingPathExtension("generated-frame").path]
    }
}
