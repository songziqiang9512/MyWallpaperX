"""Actual setAsWallpaper intent/Task cancellation with real preparation IO.

UI, manager callback and notification receiver are controlled. The production
setAsWallpaper and intent advance methods, capture, parser and lease owner run.
"""
from __future__ import annotations
import unittest
from script.tests.test_web_author_preparation import CHECKS, CORE, WEB, harness_source, run_harness
from script.tests.test_steam_library_interactions import method

ENTRY_SUPPORT = r'''
@MainActor final class ImportedVideoAutoplayGate {
    static let shared = ImportedVideoAutoplayGate()
    func invalidate() {}
    func claim() -> Int { 1 }
}
struct ImportedVideoPlaybackRequest {
    let localURL: URL; let autoplayToken: Int; let resourceLifetime: PlaybackResourceLifetime?
    func post(name: Notification.Name) {}
}
enum AlertStyle { case warning }
enum AlertResponse { case alertSecondButtonReturn }
func makeAppAlert(title: String, message: String, style: AlertStyle, buttons: [String]) -> Int { 0 }
func presentAppAlert(_ value: Int, in window: Int, completion: (AlertResponse) -> Void) {}
func appModalHostWindow() -> Int { 0 }
nonisolated enum WallpaperEngine { enum WebRuntimeProfile { case standard, highCompatibility } }
extension Notification.Name {
    static let steamWorkshopWebWallpaperReadyToPlay = Notification.Name("isolated-web-ready")
    static let steamWorkshopVideoReadyToPlay = Notification.Name("isolated-video-ready")
}
// A lock-protected receiver merely retains the opaque delivered token. It does
// not read token state or turn it into a Sendable product value.
nonisolated final class ReadyReceiver: @unchecked Sendable {
    let lock = NSLock()
    private var deliveredIDs: [String] = []
    private var tokens: [PlaybackResourceLifetime] = []
    private var hostsByRecord: [String: Set<String>] = [:]
    func receive(_ n: Notification) {
        lock.withLock {
            let id = n.userInfo?["recordID"] as! String
            deliveredIDs.append(id)
            hostsByRecord[id] = n.userInfo?["allowedNetworkHosts"] as? Set<String> ?? []
            if let token = n.userInfo?["resourceLifetime"] as? PlaybackResourceLifetime { tokens.append(token) }
        }
    }
    var ids: [String] { lock.withLock { deliveredIDs } }
    func hosts(_ id: String) -> Set<String> { lock.withLock { hostsByRecord[id] ?? [] } }
    func releaseTokens() { lock.withLock { tokens.removeAll() } }
}
@main enum IntentHarness {
    @MainActor static func main() async throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: fm.currentDirectoryPath).resolvingSymlinksInPath()
        let service = SteamWorkshopService(); service.steamDownloadLibraryRootURL = root.appendingPathComponent("library")
        let folder = service.steamDownloadLibraryRootURL.appendingPathComponent(SteamWorkshopLibraryTransaction.versionsName)
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("content")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"file":"missing-declaration.html","preset":{"speed":1}}"#.utf8).write(to: folder.appendingPathComponent("project.json"))
        try Data("<html></html>".utf8).write(to: folder.appendingPathComponent("index.html"))
        let record = SteamWorkshopDownloadRecord(id: "A", folderURL: folder,
            projectFileURL: folder.appendingPathComponent("project.json"), entryURL: folder.appendingPathComponent("index.html"))
        let receiver = ReadyReceiver()
        let token = NotificationCenter.default.addObserver(forName: .steamWorkshopWebWallpaperReadyToPlay, object: nil, queue: nil) { notification in
            receiver.receive(notification)
        }
        defer { NotificationCenter.default.removeObserver(token) }
        var processCancels = 0
        service.prepareWebPlaybackProcess = {
            // Same synchronous callback as Manager.beginPlaybackIntent -> App
            // injection. The new request must sample its generation after this.
            service.advanceWebLaunchIntentGeneration()
            return (UUID(), { processCancels += 1 }, { true }, service.webLaunchIntentGeneration)
        }
        // Entry eligibility is genuinely production code and must not read a
        // project or invoke legacy source discovery on the actor.
        trace.reset(); service.builds = []
        check(service.canLaunchDownloadRecord(record) && service.cachedCanLaunchDownloadRecord(record), "real entry eligibility")
        check(trace.rows.isEmpty && service.builds.isEmpty, "synchronous front door has no author reads/source builder")
        let entry = record.entryURL!
        try fm.removeItem(at: entry)
        check(!service.canLaunchDownloadRecord(record) && service.cachedCanLaunchDownloadRecord(record),
            "card projects the published entry while actual launch rejects its current deletion")
        try fm.createDirectory(at: entry, withIntermediateDirectories: true)
        check(!service.canLaunchDownloadRecord(record), "directory cannot masquerade as entry")
        try fm.removeItem(at: entry); try Data("<script>fetch('https://cdn.intent.test/config.json')</script>".utf8).write(to: entry)
        check(service.canLaunchDownloadRecord(record), "restored regular entry re-enables admission")
        service.setAsWallpaper(record)
        await service.webLaunchPreparationTask!.value
        check(receiver.ids == ["A"] && service.webLaunchPreparationTask == nil, "new Web survives its own intent callback and releases only its handle")
        check(receiver.hosts("A") == ["cdn.intent.test"], "actual ready publication carries the prepared author hosts")
        let activeStorage = SteamWorkshopLibraryTransaction.storageIdentity(containing: folder, libraryRoot: service.steamDownloadLibraryRootURL)!
        check(service.steamLibraryVersionLeaseRegistry.protectedStorageIdentities().contains(activeStorage), "actual ready notification consumer retains captured-root token after producer exits")
        receiver.releaseTokens()
        check(service.steamLibraryVersionLeaseRegistry.protectedStorageIdentities().isEmpty, "consumer release ends transferred source lifetime")
        let before = service.webLaunchIntentGeneration
        var invalid = record; invalid.status = .queued
        service.setAsWallpaper(invalid)
        check(service.webLaunchIntentGeneration > before && service.webLaunchPreparationTask == nil, "invalid new request still advances/revokes at product entry")
        service.removeWebRuntimeCaches(for: record.id)
        trace.reset(); let oldGate = Gate(); trace.readGate = oldGate
        service.setAsWallpaper(record)
        let old = service.webLaunchPreparationTask!
        await oldGate.wait()
        let storage = SteamWorkshopLibraryTransaction.storageIdentity(containing: folder, libraryRoot: service.steamDownloadLibraryRootURL)!
        var next = record; next = SteamWorkshopDownloadRecord(id: "B", folderURL: folder,
            projectFileURL: record.projectFileURL, entryURL: record.entryURL)
        let nextGate = Gate(); trace.readGate = nextGate
        service.setAsWallpaper(next)
        let current = service.webLaunchPreparationTask!
        await nextGate.wait()
        check(old.isCancelled && service.steamLibraryVersionLeaseRegistry.protectedStorageIdentities().contains(storage), "new selection actually cancels stored old preparation while joined read owns lease")
        oldGate.release.signal(); await old.value
        check(service.webLaunchPreparationTask != nil && receiver.ids == ["A"], "old defer cannot clear new handle or emit stale ready")
        nextGate.release.signal(); await current.value
        check(receiver.ids == ["A", "B"] && service.webLaunchPreparationTask == nil, "only newest selection publishes real prepared output")
        receiver.releaseTokens()
        service.removeWebRuntimeCaches(for: next.id)
        trace.reset(); let crossGate = Gate(); trace.readGate = crossGate
        service.setAsWallpaper(next)
        let cross = service.webLaunchPreparationTask!
        await crossGate.wait()
        service.advanceWebLaunchIntentGeneration() // real callback target for non-Web intents/stop
        crossGate.release.signal(); await cross.value
        check(cross.isCancelled && receiver.ids == ["A", "B"], "non-Web/stop callback target cancels real IO and blocks ready")
        check(service.steamLibraryVersionLeaseRegistry.protectedStorageIdentities().isEmpty && processCancels >= 3,
            "renderer preparation and sole source lease release only after joins")
        NotificationCenter.default.removeObserver(token)
        service.removeWebRuntimeCaches(for: record.id)
        service.setAsWallpaper(record)
        await service.webLaunchPreparationTask!.value
        check(service.steamLibraryVersionLeaseRegistry.protectedStorageIdentities().isEmpty,
            "ready notification without a consumer releases the sole source token when producer exits")
        service.downloadError = nil
        try Data("<html>new declared entry</html>".utf8).write(to: folder.appendingPathComponent("other.html"))
        try Data(#"{"file":"other.html"}"#.utf8).write(to: record.projectFileURL!)
        service.setAsWallpaper(record)
        await service.webLaunchPreparationTask!.value
        check(service.downloadError == nil && service.steamLibraryVersionLeaseRegistry.protectedStorageIdentities().isEmpty,
            "changed declaration does not reject a selected readable entry or retain a source token")
        print("web-preparation-intent-pass")
    }
}
'''


class WebPreparationIntentTests(unittest.TestCase):
    def test_real_selection_task_and_callback_generation(self):
        source = harness_source().removesuffix(CHECKS)
        source = source.replace('    var webEntryURL: URL?', '    var title: String { id }\n    var videoURL: URL? { nil }\n    var webEntryURL: URL?', 1)
        fields = r'''
    var webLaunchIntentGeneration: UInt64 = 0
    var webLaunchPreparationTask: Task<Void, Never>?
    var cancelWebProcessPreparation: (() -> Void)?
    var prepareWebPlaybackProcess: (() -> (requestID: UUID, cancel: () -> Void, isCurrent: () -> Bool, intentEpoch: UInt64))?
    var statusMessage = ""
    var downloadError: String?
    func markLaunchPending(recordID: String) {}
    func clearLaunchPending(matching id: String) {}
    func scheduleLaunchPendingFallbackClear(recordID: String) {}
    func requestSceneRender(_ record: SteamWorkshopDownloadRecord) {}
    func requestMissingDependencyDownload(for record: SteamWorkshopDownloadRecord) {}
'''
        source = source.replace('    var removingDownloadIDs = Set<String>()', fields + '\n    var removingDownloadIDs = Set<String>()', 1)
        core = (CORE / 'SteamWorkshopService.swift').read_text()
        playback = (WEB / 'SteamWorkshopService+WebPlayback.swift').read_text()
        risk = (WEB / 'SteamWorkshopWebResolvedRuntimeRiskFlags.swift').read_text()
        source += '\nextension SteamWorkshopService {\n' + '@discardableResult\n' + method(core, 'func advanceWebLaunchIntentGeneration(') + '\n' + method(playback, 'func setAsWallpaper(') + '\n' + method(risk, 'func recommendedWebRuntimeProfile(for descriptor:') + '\n}\n'
        run_harness(self, source + ENTRY_SUPPORT, 'web-preparation-intent-pass')


if __name__ == '__main__': unittest.main()
