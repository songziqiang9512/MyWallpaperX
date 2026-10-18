import Foundation
import Combine

struct VideoWallpaper { let path: String }
struct SteamWorkshopDownloadRecord {
    enum ContentType { case unknown, video, web, scene }
    let id: String
    let contentType: ContentType
    var videoURL: URL? { contentType == .video ? URL(fileURLWithPath: "/\(id)") : nil }
    var exportedVideoURL: URL? { nil }
    var sourceVideoURL: URL? { nil }
}
final class ImportedVideoAutoplayGate {
    static let shared = ImportedVideoAutoplayGate()
    func invalidate() {}
}
final class PlaybackCommandMultiplexer {
    static let shared = PlaybackCommandMultiplexer()
    var isPlaybackPaused = false
}
@MainActor final class WallpaperEngine {
    static let shared = WallpaperEngine()
    var currentContentPath: String?
    var currentPlaybackContentKind: SteamWorkshopDownloadRecord.ContentType?
    var currentWebRecordID: String?
    func replayDeferredVideoEndIfNeeded() {}
    func cancelSwitch(ticket: PlaybackSwitchTicket, completion: () -> Void) { completion() }
    func adoptIntentEpoch(_ epoch: UInt64) {}
    func stopPlayback() {
        currentContentPath = nil
        currentPlaybackContentKind = nil
        currentWebRecordID = nil
    }
}
@MainActor final class SceneDaemonClient {
    static let shared = SceneDaemonClient()
    var activeRecordID: String?
    func cancelSwitch(ticket: PlaybackSwitchTicket, completion: () -> Void) { completion() }
    func stop() { activeRecordID = nil }
}
@MainActor final class WallpaperManager: ObservableObject {
    enum RuntimeSwitchSelection {
        case video(VideoWallpaper), web(String?), scene(String?), systemStill(URL)
    }
    struct Settings { var syncSystemWallpaper = false }
    static var shared: WallpaperManager!
    @Published var currentWallpaper: VideoWallpaper?
    @Published var pendingWallpaper: VideoWallpaper?
    @Published var lastWorkshopPlaybackRecordID: String?
    @Published var activeWallpaperRuntime = WallpaperRuntimeKind.video
    @Published var isPlaying = false
    var effectiveCurrentWallpaper: VideoWallpaper? { pendingWallpaper ?? currentWallpaper }
    var playbackSwitch = PlaybackSwitchTransaction()
    var switchEndpoints: [UUID: PlaybackSwitchEndpoint] = [:]
    var switchSelections: [UUID: RuntimeSwitchSelection] = [:]
    var switchEffectQueue: [PlaybackSwitchTransaction.Effect] = []
    var drainingSwitchEffects = false
    var switchDeadline: DispatchWorkItem?
    var pendingSystemWallpaperSyncWorkItem: DispatchWorkItem?
    var settings = Settings()
    func scheduleSwitchDeadline(_ ticket: PlaybackSwitchTicket) {}
    func refreshAutoSwitchTimerIfNeeded(forceRestart: Bool = false) {}
    func stopAutoSwitchTimer() {}
    func persistCurrentWallpaperSnapshot() {}
    func syncSystemWallpaper(with wallpaper: VideoWallpaper) {}
    func scheduleRuntimeFrameSystemWallpaperSync(kind: WallpaperRuntimeKind, recordID: String) {}
    func switchFailed(_ ticket: PlaybackSwitchTicket, reason: String) {
        runSwitchEffects(playbackSwitch.failed(ticket, reason: reason))
    }
    // MANAGER_METHODS
}
extension Notification.Name {
    static let sceneWallpaperLaunchStateDidChange = Notification.Name("scene-launch")
    static let wallpaperSwitchDidFail = Notification.Name("switch-failed")
}
@MainActor final class SteamWorkshopService {
    var downloads: [SteamWorkshopDownloadRecord] = []
    func isActiveWebRecord(_ record: SteamWorkshopDownloadRecord) -> Bool {
        WallpaperEngine.shared.currentPlaybackContentKind == .web
            && WallpaperEngine.shared.currentWebRecordID == record.id
    }
    // PLAYING_ACCESSOR
}
@MainActor final class GridObserver {
    let service: SteamWorkshopService
    var cancellables = Set<AnyCancellable>()
    var visiblePlaying: Set<String> = []
    var refreshes = 0
    var synchronousReads: [Set<String>] = []
    var renderedStates: [Set<String>] = []
    init(_ service: SteamWorkshopService) {
        self.service = service
        // GRID_SUBSCRIPTION
        WallpaperManager.shared.objectWillChange
            .sink { [weak self] _ in
                guard let self else { return }
                self.synchronousReads.append(Set(self.service.downloads
                    .filter { self.service.isRecordCurrentlyPlaying($0) }.map(\.id)))
            }
            .store(in: &cancellables)
    }
    func refreshVisibleDownloadItems() {
        refreshes += 1
        visiblePlaying = Set(service.downloads.filter { service.isRecordCurrentlyPlaying($0) }.map(\.id))
        renderedStates.append(visiblePlaying)
    }
}
@MainActor final class Endpoint {
    let id = UUID()
    let ticket: PlaybackSwitchTicket
    let record: SteamWorkshopDownloadRecord
    var retirement: (() -> Void)?
    var delayedRetirement = true
    var finalized = false
    init(_ record: SteamWorkshopDownloadRecord, _ ticket: PlaybackSwitchTicket) {
        self.record = record
        self.ticket = ticket
    }
    var endpoint: PlaybackSwitchEndpoint {
        .init(id: id, activate: {}, finalize: { [self] in
            finalized = true
            WallpaperEngine.shared.stopPlayback()
            SceneDaemonClient.shared.stop()
            if record.contentType == .scene { SceneDaemonClient.shared.activeRecordID = record.id }
            else {
                WallpaperEngine.shared.currentContentPath = "/\(record.id)"
                WallpaperEngine.shared.currentPlaybackContentKind = record.contentType
                WallpaperEngine.shared.currentWebRecordID = record.contentType == .web ? record.id : nil
            }
        }, cancel: { $0() }, setOutputActive: { _, done in done(true) }, retire: { [self] done in
            if delayedRetirement { retirement = done }
            else { done() }
        })
    }
    func finishRetirement() {
        let callback = retirement
        retirement = nil
        if SceneDaemonClient.shared.activeRecordID == record.id { SceneDaemonClient.shared.stop() }
        if WallpaperEngine.shared.currentContentPath == "/\(record.id)" { WallpaperEngine.shared.stopPlayback() }
        callback?()
    }
}
@main enum Harness {
    @MainActor static func main() async throws {
        var cases = 0
        func drain() async throws { try await Task.sleep(nanoseconds: 25_000_000) }
        for source in [WallpaperRuntimeKind.video, .web, .scene] {
            for target in [WallpaperRuntimeKind.video, .web, .scene] {
                WallpaperEngine.shared.stopPlayback()
                SceneDaemonClient.shared.stop()
                let manager = WallpaperManager()
                WallpaperManager.shared = manager
                let service = SteamWorkshopService()
                let a = SteamWorkshopDownloadRecord(id: "A", contentType: .init(source))
                let b = SteamWorkshopDownloadRecord(id: "B", contentType: .init(target))
                let c = SteamWorkshopDownloadRecord(id: "C", contentType: .init(target))
                service.downloads = [a, b, c]
                // The same grid owns All/search/type-filter views, regardless
                // of which records are visible or whether selection is enabled.
                let grid = GridObserver(service)
                let secondGrid = GridObserver(service)
                func begin(_ record: SteamWorkshopDownloadRecord, _ kind: WallpaperRuntimeKind) -> Endpoint {
                    manager.beginPlaybackIntent(runtime: kind)
                    let ticket = manager.playbackSwitch.pending!.selection.ticket
                    switch kind {
                    case .video: manager.switchSelections[ticket.id] = .video(.init(path: "/\(record.id)"))
                    case .web: manager.switchSelections[ticket.id] = .web(record.id)
                    case .scene: manager.switchSelections[ticket.id] = .scene(record.id)
                    case .systemStill: fatalError()
                    }
                    let endpoint = Endpoint(record, ticket)
                    manager.switchEndpoints[endpoint.id] = endpoint.endpoint
                    manager.runSwitchEffects(manager.playbackSwitch.prepared(ticket, executionID: endpoint.id))
                    return endpoint
                }
                func visible(_ value: Endpoint) {
                    manager.runSwitchEffects(manager.playbackSwitch.visible(value.ticket, executionID: value.id))
                }
                let first = begin(a, source)
                visible(first)
                try await drain()
                precondition(grid.visiblePlaying == ["A"], "initial finalized selection was not published")
                let next = begin(b, target)
                visible(next)
                try await drain()
                precondition(manager.playbackSwitch.committed?.ticket == next.ticket && !next.finalized)
                precondition(grid.visiblePlaying == ["A"], "candidate changed the actual execution projection")
                let reads = grid.refreshes
                let synchronousReads = grid.synchronousReads.count
                first.finishRetirement()
                precondition(Array(grid.synchronousReads.dropFirst(synchronousReads)) == [["B"]],
                    "handoff published an incomplete execution projection")
                try await drain()
                precondition(next.finalized)
                precondition(grid.visiblePlaying == ["B"] && secondGrid.visiblePlaying == ["B"],
                    "delayed finalize left the previous card playing: \(source)->\(target)")
                precondition(grid.refreshes == reads + 1, "finalization must trigger one distinct playing update")

                // A failed candidate and stale visibility must retain B.
                let rejected = begin(a, source)
                manager.switchFailed(rejected.ticket, reason: "injected candidate failure")
                visible(rejected)
                try await drain()
                precondition(grid.visiblePlaying == ["B"] && !rejected.finalized)
                // B -> stale A -> C: the newer request is the only finalizer.
                let stale = begin(a, source)
                let latest = begin(c, target)
                visible(stale)
                visible(latest)
                try await drain()
                precondition(!stale.finalized && !latest.finalized && grid.visiblePlaying == ["B"])
                next.finishRetirement()
                try await drain()
                precondition(latest.finalized && grid.visiblePlaying == ["C"])
                latest.delayedRetirement = false
                manager.stopCurrentPlayback()
                try await drain()
                precondition(grid.visiblePlaying.isEmpty && secondGrid.visiblePlaying.isEmpty,
                    "Stop retained a stale playing card")

                // A terminal output loss also clears native facts only when
                // its exact retirement completes, without a new finalizer.
                let lost = begin(a, source)
                visible(lost)
                try await drain()
                precondition(grid.visiblePlaying == ["A"])
                manager.runSwitchEffects(manager.playbackSwitch.lost(lost.ticket, reason: "injected output loss"))
                try await drain()
                precondition(manager.playbackSwitch.committed == nil && grid.visiblePlaying == ["A"])
                lost.finishRetirement()
                try await drain()
                precondition(grid.visiblePlaying.isEmpty && secondGrid.visiblePlaying.isEmpty,
                    "terminal retirement left a stale playing card: \(source)")

                // A visible successor waiting behind an output-loss barrier
                // commits/finalizes in that same completion. The queued UI
                // subscriber must not render a transient empty playing set.
                let retiring = begin(a, source)
                visible(retiring)
                try await drain()
                let waiting = begin(b, target)
                manager.runSwitchEffects(manager.playbackSwitch.lost(retiring.ticket, reason: "loss with newer selection"))
                visible(waiting)
                try await drain()
                precondition(!waiting.finalized && grid.visiblePlaying == ["A"])
                let rendered = grid.renderedStates.count
                retiring.finishRetirement()
                precondition(waiting.finalized && grid.synchronousReads.last == ["B"])
                try await drain()
                precondition(Array(grid.renderedStates.dropFirst(rendered)) == [["B"]],
                    "retirement rendered an empty or stale intermediate card state")
                waiting.delayedRetirement = false
                manager.stopCurrentPlayback()
                try await drain()
                precondition(grid.visiblePlaying.isEmpty)
                cases += 1
            }
        }
        print("playback publication passed: \(cases) engine pairs, delayed handoff, failure, supersession, Stop and output loss")
    }
}
extension SteamWorkshopDownloadRecord.ContentType {
    init(_ kind: WallpaperRuntimeKind) {
        switch kind { case .video: self = .video; case .web: self = .web; case .scene: self = .scene; case .systemStill: self = .unknown }
    }
}
