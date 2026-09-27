"""Execute Workshop load/lease and Scene shutdown owners with isolated files and real child processes."""
import pathlib
import subprocess
import tempfile
import unittest
from script.tests.test_steam_library_transaction import SOURCES, CORE, ROOT
from script.tests.test_steam_library_interactions import method


class SteamPlaybackLifetimeTests(unittest.TestCase):
    def test_reload_lease_and_generation_scoped_shutdown(self):
        ipc = ROOT / 'MyWallpaperX/Core/SteamWorkshopScene/Runtime/IPC'
        client = (ipc / 'SceneDaemonClient.swift').read_text()
        events = (ipc / 'SceneDaemonClient+Events.swift').read_text()
        reclamation = (CORE / 'SteamWorkshopService+LibraryReclamation.swift').read_text()
        scene = CORE.parent / 'Scene/SteamWorkshopSceneService+ScenePlayback.swift'
        harness = r'''
import AppKit
struct SceneUserPropertyValue {}
struct ScenePlaybackTextureReference {}
struct ScenePlaybackLoadRequest {
    let rootURL: URL
    let recordID: String?
}
struct SceneWallpaperLaunchState {
    enum Phase: String { case accepted, launched, cancelled, failed, stopped }
    let requestID: UUID
    let recordID: String?
    let phase: Phase
    let message: String
}
enum SceneDaemonProtocol { static let version = 1 }
struct Backoff { mutating func reset() {} }
extension Notification.Name {
    static let sceneWallpaperLaunchStateDidChange = Notification.Name("launch")
    static let steamWorkshopSceneReadyToRender = Notification.Name("render")
}
@MainActor final class SceneDaemonClient {
    var transport: DaemonProcessTransport?
    var retiringTransports: [UInt64: DaemonProcessTransport] = [:]
    var sessionGeneration: UInt64 = 0
    var expectedTerminationGenerations: Set<UInt64> = []
    var restartWorkItem: DispatchWorkItem?
    var handshakeWorkItem: DispatchWorkItem?
    var pendingIntent: ScenePlaybackLoadRequest?
    var activeIntent: ScenePlaybackLoadRequest?
    var pendingRequestID: UUID?
    var activeRequestID: UUID?
    var activeRecordID: String?
    var pendingPropertyRevisions: [UInt64: String] = [:]
    var endpointReady = false
    var latestFrameStats: Int?
    var launchState: SceneWallpaperLaunchState?
    var restartBackoff = Backoff()
    struct RetainedResourceLifetime {
        let rootURL: URL
        let recordID: String?
        let lifetime: PlaybackResourceLifetime
    }
    var pendingResourceLifetime: RetainedResourceLifetime?
    var activeResourceLifetime: RetainedResourceLifetime?
    var retiringResourceLifetimes: [UInt64: [PlaybackResourceLifetime]] = [:]
    var shutdownCompletions: [(generations: Set<UInt64>, completion: () -> Void)] = []
    func revokeAudioSpectrumDemand(generation: UInt64) {}
    func scheduleRestart(reason: String) { fatalError("unexpected restart: " + reason) }
    func publishFailure(code: String, message: String) { fatalError(code + message) }
''' + '\n'.join(method(client, signature) for signature in (
            '    func hasIntent(', '    func retainResourceLifetime(',
            '    func shutdown(', '    func stop(postsLaunchState:',
        )) + '\n' + '\n'.join(method(events, signature) for signature in (
            '    private func handleLaunchState(', '    func handleTermination(',
            '    func finishShutdownIfPossible(',
        )) + r'''
    func startProcess() throws {
        sessionGeneration += 1
        let generation = sessionGeneration
        let process = DaemonProcessTransport(executableURL: URL(fileURLWithPath: "/bin/cat"), arguments: [])
        process.onTermination = { [weak self] status in
            self?.handleTermination(status: status, generation: generation)
        }
        try process.start()
        transport = process
    }
    func launchPending() {
        let id = UUID().uuidString
        handleLaunchState(["phase": "accepted", "requestID": id,
            "recordID": pendingIntent!.recordID!, "message": "accepted"])
        handleLaunchState(["phase": "launched", "requestID": id,
            "recordID": pendingIntent!.recordID!, "message": "launched"])
    }
}
enum ContentType { case scene }
struct SteamWorkshopDownloadRecord {
    let id: String
    let title: String
    let folderURL: URL
    let contentType = ContentType.scene
    let dependencyHostFolderURL: URL? = nil
}
@MainActor final class SteamWorkshopService {
    var removingDownloadIDs: Set<String> = []
    let steamLibraryVersionLeaseRegistry = SteamWorkshopLibraryVersionLeaseRegistry()
    let steamDownloadLibraryRootURL: URL
    var downloadError: String?
    var statusMessage = ""
    init(_ root: URL) { steamDownloadLibraryRootURL = root }
    func clearLaunchPending(matching id: String) {}
    func scenePropertyOverrides(for record: SteamWorkshopDownloadRecord) -> [String: SceneUserPropertyValue] { [:] }
    func withResolvedSceneTexturePropertyReferences(for record: SteamWorkshopDownloadRecord,
        completion: ([String: ScenePlaybackTextureReference]) -> Void) { completion([:]) }
''' + method(reclamation, '    func libraryVersionLifetime(') + r'''
}
@main struct Harness {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        typealias T = SteamWorkshopLibraryTransaction
        let prepared = SteamWorkshopLibraryCommit(version: 2, workshopId: "123456", jobId: "job",
            attempt: 1, directoryName: "123456-" + UUID().uuidString.lowercased(), manifestId: "123",
            contentDigest: String(repeating: "a", count: 64), contentType: "scene", entryPath: nil,
            committedAt: Date())
        let folder = try T.contentURL(for: prepared, libraryRoot: root)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(prepared).write(to: folder.appendingPathComponent(T.ownershipMarkerName))
        let service = SteamWorkshopService(root)
        let leases = service.steamLibraryVersionLeaseRegistry
        let identity = T.storageIdentity(for: prepared)!
        let record = SteamWorkshopDownloadRecord(id: "123456", title: "fixture", folderURL: folder)
        let daemon = SceneDaemonClient()
        var loads = 0
        let observer = NotificationCenter.default.addObserver(forName: .steamWorkshopSceneReadyToRender,
            object: nil, queue: nil) { note in
            MainActor.assumeIsolated {
                let request = note.userInfo!["request"] as! SteamWorkshopScenePlaybackRequest
                daemon.retainResourceLifetime(request.resourceLifetime, rootURL: request.rootURL, recordID: request.recordID)
                daemon.pendingIntent = ScenePlaybackLoadRequest(rootURL: request.rootURL, recordID: request.recordID)
                loads += 1
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        try daemon.startProcess()
        service.requestSceneRender(record)
        precondition(leases.protectedStorageIdentities() == [identity])
        daemon.launchPending()
        service.requestSceneRender(record) // same entry used by a texture-property reload
        daemon.launchPending()
        precondition(loads == 2 && leases.protectedStorageIdentities() == [identity])
        precondition(!leases.beginReclamation(identity), "reloaded Scene must still pin its files")
        service.removingDownloadIDs.insert(record.id)
        service.requestSceneRender(record)
        precondition(loads == 2 && service.downloadError != nil, "deletion fences reloading")

        var ended = false
        daemon.shutdown(postsLaunchState: true) { ended = true }
        precondition(!ended && leases.protectedStorageIdentities() == [identity],
            "shutdown request is not physical process completion")
        try daemon.startProcess() // a newer playback must not hold the older stop callback
        while !ended { await Task.yield() }
        precondition(daemon.transport?.isRunning == true)
        precondition(leases.protectedStorageIdentities().isEmpty)
        precondition(leases.beginReclamation(identity))
        leases.reclamationFailed(identity)

        // Stop a load that has not received accepted/launched yet.
        service.removingDownloadIDs.remove(record.id)
        service.requestSceneRender(record)
        precondition(daemon.hasIntent(for: record.id) && daemon.activeRecordID == nil)
        var pendingEnded = false
        daemon.shutdown(postsLaunchState: true) { pendingEnded = true }
        precondition(leases.protectedStorageIdentities() == [identity])
        while !pendingEnded { await Task.yield() }
        precondition(leases.protectedStorageIdentities().isEmpty && !daemon.hasIntent(for: record.id))
        var idleEnded = false
        daemon.shutdown { idleEnded = true }
        while !idleEnded { await Task.yield() }
        precondition(daemon.retiringTransports.isEmpty && daemon.transport == nil)
        print("PASS: reload, deletion fence, pending stop, physical exit, newer generation")
    }
}
'''
        with tempfile.TemporaryDirectory(prefix='mwx-playback-lifetime-', dir='/private/tmp') as temp:
            folder = pathlib.Path(temp)
            source = folder / 'Harness.swift'
            source.write_text(harness)
            binary = folder / 'test'
            subprocess.run(['xcrun', 'swiftc', '-parse-as-library', *map(str, SOURCES),
                            str(scene), str(source), '-o', str(binary)], check=True, timeout=120)
            result = subprocess.run([str(binary), str(folder / 'library')], capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('PASS:', result.stdout)
