// Compile the real DEBUG Startup runner and measurement with D22-shaped peers.
// These peers test orchestration and evidence only: no renderer, AV or admission.
import AppKit
import Foundation

@MainActor let NSApp = HarnessApplication()
@MainActor final class HarnessApplication {
    func terminate(_ sender: Any?) {
        print("selections=" + HarnessState.selections.joined(separator: ","))
        exit(0)
    }
}
enum WallpaperRuntimeKind { case scene, video }
struct PlaybackSwitchTicket: Equatable { let epoch: UInt64; let id: UUID; let runtime: WallpaperRuntimeKind }
enum WallpaperProvider { case steamWorkshop, videoLibrary }
struct WallpaperReference { let provider: WallpaperProvider; let sourceID: String }
enum WallpaperPlaybackSequence { struct Pending { let ticket: PlaybackSwitchTicket } }
enum WallpaperPlaybackCause { case userSelection, restore }
struct PlaybackSwitchState {
    struct Selection { let ticket: PlaybackSwitchTicket; let executionID: UUID? }
    struct Pending { let selection: Selection }
    var committed: Selection?, pending: Pending?
    var activity: UUID?
    var cancellations: [UUID: Bool] = [:], retirements: [UUID: Bool] = [:]
}
struct VideoWallpaper { let id = UUID().uuidString; let title: String; let path: String }
struct PlaybackPerformanceProfile {
    let maxFPS: Int
    init?(rawValue: Int) { guard rawValue == 30 else { return nil }; maxFPS = rawValue }
    static let current = PlaybackPerformanceProfile(rawValue: 30)!
}
struct HarnessSettings {
    var pauseWhenOtherAppFocused = true, pauseWhenOtherAppFullscreen = true
    var pauseWhenUnplugged = true, pauseWhenIdle = true, restorePlaybackOnLaunch = false
}
enum DebugScenePlaybackRunner {
    static func argumentValue(after flag: String) -> String? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: flag), a.indices.contains(i + 1) else { return nil }
        return a[i + 1]
    }
}
enum DebugSceneProductEntryPolicy {
    static func isStartupMeasurementRequested(arguments: [String]) -> Bool { true }
    static func protectedUserHomeURL() -> URL? { URL(fileURLWithPath: "/protected-home") }
    static func protectedWorkshopRootURL() -> URL? { URL(fileURLWithPath: "/protected-workshop") }
    static func isolatedExistingDirectory(rawPath: String, disjointFrom: URL) -> URL? {
        URL(fileURLWithPath: rawPath)
    }
}
@MainActor enum DebugSceneDaemonClientRunner { static let requiresProductCoordinator = true }
struct SteamWorkshopDownloadRecord {
    enum Status { case ready }; enum Content { case scene }; enum Dependency { case none }
    let id: String, title: String, description: String, tags: [String]
    let folderURL: URL, projectFileURL: URL
    let ownEntryHTMLURL: URL?, dependencyHostEntryHTMLURL: URL?, dependencyHostFolderURL: URL?
    let entryHTMLURL: URL?, resolvedWebRootURL: URL?, previewURL: URL?, sourceVideoURL: URL?, exportedVideoURL: URL?
    let updatedAt: Date, sizeText: String, status: Status, browserItem: String?
    let contentType: Content, dependencyItemID: String?, dependencyStatus: Dependency
}
struct SceneWallpaperLaunchState {
    enum Phase: String { case accepted, failed, cancelled }
    let recordID: String?, phase: Phase, requestID: UUID, message: String
}
struct SceneFramePresentation { let requestID: UUID; let recordID: String?; let uptimeMicros: UInt64 }
struct SceneDaemonClientFailure { let recordID: String?; let code: String; let message: String }
struct StartupObservation {
    enum Phase: String { case prepared, parentFinalized }
    let phase: Phase, ticketID: UUID, intentEpoch: UInt64, requestID: UUID, executionID: UUID
    let transportGeneration: UInt64, daemonPID: Int32?, uptimeMicros: UInt64
}
struct PrefixObservation {
    enum Phase: String { case preparationReceived }
    let phase: Phase, ticketID: UUID, intentEpoch: UInt64, requestID: UUID?
    let transportGeneration: UInt64, daemonPID: Int32?, uptimeMicros: UInt64
    let childStartupUptimes: [String: UInt64]?
}
struct SceneIntent { let recordID: String; let source: [String: String]? }
enum SceneDaemonProtocol {
    static func sourceObject(_ source: [String: String]) throws -> [String: Any] { source }
}
@MainActor final class SceneDaemonClient {
    static let shared = SceneDaemonClient()
    enum Command { case setPerformanceProfile(maxFPS: Int) }
    var debugStartupObserver: ((StartupObservation) -> Void)?
    var debugStartupPrefixObserver: ((PrefixObservation) -> Void)?
    var debugStartupWireObserver: ((UInt64, Int32?, UInt64, [String: Any]) -> Void)?
    var debugProcessIdentifier: Int32?, endpointReady = false, debugConfiguredMaximumFPS = 30
    final class Transport {
        final class ProcessIdentity { let processIdentifier: Int32 = 42 }
        let process = ProcessIdentity()
    }
    struct Control { let generation: UInt64; let requestID: UUID?; let transport = Transport() }
    var switchControls: [UUID: Control] = [:]
    var pendingSwitchTicket: PlaybackSwitchTicket?
    var activeIntent: SceneIntent?, pendingIntent: SceneIntent?
    var activeRequestID: UUID?, pendingRequestID: UUID?
    var activeResourceLifetime: UUID?, pendingResourceLifetime: UUID?
    var requestResourceLifetimes: [UUID: UUID] = [:]
    var retiringResourceLifetimes: [UInt64: [UUID]] = [:], retiringTransports: [UInt64: UUID] = [:]
    func handle(_ command: Command) -> Bool { true }
    func shutdown(completion: () -> Void) { completion() }
}
enum DebugWebPlaybackRunner { static let hasIsolatedStartupEnvironment = true }
@MainActor enum BundledVideoLibrary {
    static func videoURL(named: String) -> URL? { URL(fileURLWithPath: "/isolated/Video2.mp4") }
}
@MainActor final class DaemonPlaybackProcessRegistry {
    static let shared = DaemonPlaybackProcessRegistry()
    var liveProcessIdentifiers: [Int32] = []
}
@MainActor final class WallpaperEngine {
    static let shared = WallpaperEngine()
    final class Session { let process = Process() }
    final class Execution {
        let ticket: PlaybackSwitchTicket, id: UUID
        let activationID = UUID()
        var activated = true, finalized = true, retired = false, cancelling = false
        var sessions: [UInt32: Session] = [1: Session()]
        var visibleDisplays: Set<UInt32> = [1]
        var requests: [UInt32: Int] = [1: 7]
        var generations: [UInt32: UInt64] = [1: 2]
        init(ticket: PlaybackSwitchTicket, id: UUID) { self.ticket = ticket; self.id = id }
    }
    var activeVideoExecution: Execution?
}
@MainActor final class WallpaperManager {
    static let shared = WallpaperManager()
    var settings = HarnessSettings(), playbackSwitch = PlaybackSwitchState()
    var switchEndpoints: [UUID: Bool] = [:]
    var activeWallpaperRuntime: WallpaperRuntimeKind = .scene
    @discardableResult
    func requestDiagnosticPlayback(reference: WallpaperReference, runtime: WallpaperRuntimeKind,
                                   cause: WallpaperPlaybackCause = .userSelection,
                                   prepare: (WallpaperPlaybackSequence.Pending) -> Bool) -> PlaybackSwitchTicket? {
        precondition(cause == (runtime == .video ? .restore : .userSelection),
                     "Video interstitial must not record recent; Scene measures user selection")
        let ticket = HarnessState.ticket(runtime)
        playbackSwitch.pending = .init(selection: .init(ticket: ticket, executionID: nil))
        return prepare(.init(ticket: ticket)) ? ticket : nil
    }
    func setAsWallpaper(_ wallpaper: VideoWallpaper, libraryPending: WallpaperPlaybackSequence.Pending) {
        HarnessState.selections.append("video")
        let ticket = libraryPending.ticket, execution = UUID()
        playbackSwitch.pending = .init(selection: .init(ticket: ticket, executionID: execution))
        DispatchQueue.main.async {
            if HarnessState.scenario == "video-failure" {
                NotificationCenter.default.post(name: .wallpaperSwitchDidFail, object: nil,
                                                userInfo: ["message": "controlled-video-failure"])
                return
            }
            let client = SceneDaemonClient.shared
            let reuse = HarnessState.scenario != "baseline"
            if HarnessState.scenario != "retained-scene" { self.switchEndpoints.removeAll() }
            self.playbackSwitch.pending = nil
            self.playbackSwitch.committed = .init(ticket: ticket, executionID: execution)
            self.activeWallpaperRuntime = .video
            let video = WallpaperEngine.Execution(ticket: ticket, id: execution)
            WallpaperEngine.shared.activeVideoExecution = video
            if HarnessState.scenario == "partial-visible" {
                video.visibleDisplays = []
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                    NotificationCenter.default.post(name: .wallpaperSwitchDidFail, object: nil)
                }
            }
            let request = client.activeRequestID!
            if reuse {
                let foreign = HarnessState.scenario == "foreign-ack"
                let operation = UUID()
                client.switchControls[operation] = .init(generation: 1, requestID: request)
                let count = HarnessState.scenario == "wire-overflow" ? 65 : 1
                for _ in 0..<count {
                    client.debugStartupWireObserver?(foreign ? 99 : 1, 42, HarnessState.now(), [
                        "event": "switchControlResult", "requestID": (foreign ? UUID() : request).uuidString,
                        "operationID": operation.uuidString, "accepted": true, "requestRetired": true])
                }
                client.switchControls.removeValue(forKey: operation)
            } else {
                client.debugProcessIdentifier = nil
                DaemonPlaybackProcessRegistry.shared.liveProcessIdentifiers = []
            }
            client.activeIntent = nil; client.activeRequestID = nil
            client.activeResourceLifetime = nil; client.requestResourceLifetimes.removeAll()
        }
    }
}
@MainActor enum HarnessState {
    static let scenario = DebugScenePlaybackRunner.argumentValue(after: "--fixture-scenario") ?? "reuse"
    static var selections: [String] = [], epoch: UInt64 = 0, sceneCount = 0
    static func now() -> UInt64 { UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000) }
    static func ticket(_ kind: WallpaperRuntimeKind) -> PlaybackSwitchTicket {
        epoch += 1; return .init(epoch: epoch, id: UUID(), runtime: kind)
    }
}
@MainActor final class SteamWorkshopService {
    static let shared = SteamWorkshopService()
    func setAsWallpaper(_ record: SteamWorkshopDownloadRecord, libraryPending: WallpaperPlaybackSequence.Pending) -> Bool {
        HarnessState.selections.append("scene"); HarnessState.sceneCount += 1
        let client = SceneDaemonClient.shared, manager = WallpaperManager.shared
        let ticket = libraryPending.ticket, request = UUID(), execution = UUID()
        let second = HarnessState.sceneCount == 2, fresh = second && HarnessState.scenario == "baseline"
        let generation: UInt64 = fresh ? 2 : 1, pid: Int32 = fresh ? 43 : 42
        manager.playbackSwitch.pending = .init(selection: .init(ticket: ticket, executionID: execution))
        client.pendingSwitchTicket = ticket
        DispatchQueue.main.async {
            client.debugProcessIdentifier = pid; client.endpointReady = true
            client.activeRequestID = request
            client.activeIntent = .init(recordID: record.id, source: ["managed": "same-approved-source"])
            if second && HarnessState.scenario == "changed-source" {
                client.activeIntent = .init(recordID: record.id, source: ["managed": "changed-source"])
            }
            client.activeResourceLifetime = UUID(); client.requestResourceLifetimes[request] = UUID()
            DaemonPlaybackProcessRegistry.shared.liveProcessIdentifiers = [pid]
            NotificationCenter.default.post(name: .sceneWallpaperLaunchStateDidChange,
                object: SceneWallpaperLaunchState(recordID: record.id, phase: .accepted,
                    requestID: request, message: "accepted"))
            client.debugStartupObserver?(.init(phase: .prepared, ticketID: ticket.id,
                intentEpoch: ticket.epoch, requestID: request, executionID: execution,
                transportGeneration: generation, daemonPID: pid, uptimeMicros: HarnessState.now()))
            let presented = HarnessState.now()
            NotificationCenter.default.post(name: .sceneWallpaperFirstFrameDidPresent,
                object: SceneFramePresentation(requestID: request, recordID: record.id, uptimeMicros: presented))
            manager.playbackSwitch.pending = nil
            manager.playbackSwitch.committed = .init(ticket: ticket, executionID: execution)
            manager.switchEndpoints[execution] = true; manager.activeWallpaperRuntime = .scene
            client.debugStartupObserver?(.init(phase: .parentFinalized, ticketID: ticket.id,
                intentEpoch: ticket.epoch, requestID: request, executionID: execution,
                transportGeneration: generation, daemonPID: pid, uptimeMicros: HarnessState.now()))
        }
        return true
    }
}
extension Notification.Name {
    static let sceneWallpaperLaunchStateDidChange = Notification.Name("scene-state")
    static let sceneWallpaperFirstFrameDidPresent = Notification.Name("scene-presented")
    static let sceneDaemonClientDidFail = Notification.Name("scene-failed")
    static let wallpaperSwitchDidFail = Notification.Name("switch-failed")
}
@main enum Harness {
    @MainActor static func main() {
        let path = DebugScenePlaybackRunner.argumentValue(after: "--mwx-debug-scene-root")!
        _ = DebugSceneDaemonClientRunner.scheduleStartupIfRequested(rootURL: URL(fileURLWithPath: path))
        RunLoop.main.run()
        fatalError("runner must terminate")
    }
}
