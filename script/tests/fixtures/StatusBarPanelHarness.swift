import AppKit

// Boundary doubles supply input values and controllable asynchronous results.
// All layout, button wiring, snapshot projection and preview acceptance below
// execute the production files, without starting an engine or a system item.
struct VideoWallpaper: Codable, Equatable {
    let id: String
    let displayTitle: String
    var path = "/fixture/video.mp4"
}
struct SteamWorkshopDownloadRecord: Equatable {
    enum Kind { case video, web, scene }
    enum Status { case ready, queued }
    enum Dependency: Equatable { case ready, missing(String) }
    struct Browser: Equatable { let previewImageURL: URL? }
    let id: String
    let title: String
    let contentType: Kind
    var status = Status.ready
    var dependencyStatus = Dependency.ready
    var previewURL: URL? = URL(fileURLWithPath: "/fixture/cover.jpg")
    var browserItem: Browser?
}
enum WallpaperMediaKind { case image, video, web, scene, unknown }
struct WallpaperReference: Hashable {
    enum Provider { case videoLibrary, staticImageLibrary, steamWorkshop, pixabay }
    let provider: Provider
    let sourceID: String
}
struct WallpaperContentItem: Equatable {
    struct Metadata: Equatable { var thumbnailPath: String?; var previewURL: URL? }
    struct Locator: Equatable { var path: String? }
    let title: String
    let providerReference: WallpaperReference
    let kind: WallpaperMediaKind
    var reference: WallpaperReference { providerReference }
    var metadata = Metadata()
    var locator = Locator()
}
final class WallpaperManager {
    static let shared = WallpaperManager()
    enum PlaybackMode { case loop, sequential, random }
    var mode = PlaybackMode.loop
    func playbackMode() -> PlaybackMode { mode }
    func setLoopPlaybackEnabled(_ enabled: Bool) { mode = .loop }
    func setSequentialPlaybackEnabled(_ enabled: Bool) { mode = .sequential }
    func setRandomPlaybackEnabled(_ enabled: Bool) { mode = .random }
    struct Ticket { let id: UUID }
    struct Selection { let ticket: Ticket }
    struct Transaction { var committed: Selection?; var pending: Selection? }
    enum RuntimeSwitchSelection { case video(VideoWallpaper), web(String?), scene(String?), systemStill(URL) }
    struct Settings { var volume = 50.0 }
    struct Entry { let reference: WallpaperReference; let isPlayable: Bool }
    struct Snapshot { let entries: [Entry] }
    struct Session { let snapshot: Snapshot; let reference: WallpaperReference }
    struct Sequence { var committed: Session?; var pending: Bool? }
    var libraryPlaybackSequence = Sequence()
    var libraryRotationEligible = false
    var playbackSwitch = Transaction()
    var switchSelections: [UUID: RuntimeSwitchSelection] = [:]
    var wallpapers: [VideoWallpaper] = []
    var settings = Settings()
    var isPlaying = true
    var thumbnailGenerationCallbacks: [(String?) -> Void] = []
    func shouldRetryThumbnailGeneration(for path: String) -> Bool { true }
    func isThumbnailGenerationInFlight(for path: String) -> Bool { false }
    func generateThumbnail(for url: URL, completion: @escaping (String?) -> Void) { thumbnailGenerationCallbacks.append(completion) }
    func normalizedPath(_ path: String) -> String { URL(fileURLWithPath: path).standardizedFileURL.path }
}
final class SteamWorkshopService {
    static let shared = SteamWorkshopService()
    var downloads: [SteamWorkshopDownloadRecord] = []
    var launchPendingRecordID: String?
    var directedRecords: [String: SteamWorkshopDownloadRecord] = [:]
    var launches: [String] = []
    func installedRecordForLaunchReplay(itemID: String) -> SteamWorkshopDownloadRecord? { directedRecords[itemID] }
    func setAsWallpaper(_ item: SteamWorkshopDownloadRecord) { launches.append(item.id) }
}
enum WallpaperEngineCommand { case pause, resume }
final class PlaybackCommandMultiplexer {
    static let shared = PlaybackCommandMultiplexer()
    var isAnyEnginePlaying = true
    var isUserPaused = false
    var isSystemPaused = false
    func dispatch(_ command: WallpaperEngineCommand) {
        isUserPaused = command == .pause
        isAnyEnginePlaying = !isUserPaused && !isSystemPaused
    }
}
final class PlaybackMuteState { static let shared = PlaybackMuteState(); var isMuted = false }
struct SystemStats {
    var memUsed = UInt64(12.4 * 1_073_741_824)
    var memTotal: UInt64 = 24 * 1_073_741_824
    var cpuUsageString = "12%"
    var gpuUsageString = "8%"
    var memUsedString = "12.4 GB"
    var memTotalString = "24 GB"
    var netUpString = "24 KB/s"
    var netDownString = "168 KB/s"
}
final class ThumbnailCacheRequestCancellation { var cancelled = false; func cancel() { cancelled = true } }
nonisolated enum VideoLibraryThumbnailStore {
    static let sharedCache: Bool = {
        precondition(!Thread.isMainThread, "cache initialization must not block opening")
        return true
    }()
}
nonisolated final class SteamWorkshopPreviewLoadCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func cancel() { lock.lock(); value = true; lock.unlock() }
}
@MainActor enum FixtureImageLoads {
    static var completions: [(NSImage?) -> Void] = []
    static var cancellations: [SteamWorkshopPreviewLoadCancellation] = []
}
nonisolated enum SteamWorkshopPreviewImageCache {
    static let shared: FixtureImageCache = {
        precondition(!Thread.isMainThread, "cache initialization must not block opening")
        return FixtureImageCache()
    }()
}
nonisolated final class FixtureImageCache: @unchecked Sendable {}
nonisolated func steamWorkshopLoadPreviewImage(from url: URL, maxPixelSize: Int,
    cancellation: SteamWorkshopPreviewLoadCancellation, completion: @escaping (NSImage?) -> Void) {
    precondition(!Thread.isMainThread, "local revision lookup must not block opening")
    precondition(maxPixelSize == 800 && url.isFileURL)
    DispatchQueue.main.async {
        FixtureImageLoads.completions.append(completion)
        FixtureImageLoads.cancellations.append(cancellation)
    }
}
nonisolated func steamWorkshopPreviewImageIsUsable(_ image: NSImage) -> Bool { image.size.width > 4 && image.size.height > 4 }
final class AppKitThumbnailProvider {
    static var completions: [(NSImage?) -> Void] = []
    static var cancellations: [ThumbnailCacheRequestCancellation] = []
    init(wallpaperManager: WallpaperManager) {}
    func loadThumbnail(for item: VideoWallpaper, completion: @escaping (NSImage?) -> Void) -> ThumbnailCacheRequestCancellation {
        let cancellation = ThumbnailCacheRequestCancellation()
        Self.cancellations.append(cancellation)
        Self.completions.append(completion)
        return cancellation
    }
}
final class SteamWorkshopPreviewState {
    var image: NSImage?
    var onChange: (() -> Void)?
    static var requests = 0
    func reset() { image = nil; onChange?() }
    func configure(previewURL: URL?, fallbackImageURL: URL? = nil, fallbackVideoURL: URL?, refreshToken: Int, maxPixelSize: Int) {
        precondition(fallbackVideoURL == nil, "opening a panel must not generate a movie thumbnail")
        precondition(previewURL?.isFileURL != true && fallbackImageURL?.isFileURL != true,
                     "local version reads must not enter the main-thread remote consumer")
        Self.requests += 1
    }
}

@MainActor enum MyWallpaperXApplication { static var libraryWorkspace: Workspace? = Workspace() }
@MainActor final class RememberedRestoration {
    var rememberedReference: WallpaperReference?
    var calls = 0
    var accepted = true
    func resumeLastSelection(onFailure: @escaping () -> Void = {}) -> Bool { calls += 1; return accepted }
}
@MainActor final class Workspace {
    let restoration = RememberedRestoration()
    var items: [WallpaperReference: WallpaperContentItem] = [:]
    var catalogReads = 0
    struct Catalog { let videos: [WallpaperContentItem]; let images: [WallpaperContentItem]; let downloads: [WallpaperContentItem] }
    struct CatalogController { let catalog: Catalog }
    var catalog: CatalogController {
        catalogReads += 1
        let values = Array(items.values)
        return .init(catalog: .init(videos: values, images: values, downloads: values))
    }
}
@MainActor enum MainWindowCoordinator {
    static var activations = 0
    static func activateMainWindow() { activations += 1 }
}
@MainActor final class ToggleHarness {
    let wallpaperManager = WallpaperManager.shared
    func closeThen(_ action: () -> Void) { action() }
    // PRODUCTION_CAPTURE
    // PRODUCTION_TOGGLE
    // PRODUCTION_MODE
    func toggle() { togglePlayback() }
    func cycleMode() { cyclePlaybackMode() }
}

@main enum Checks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        func pumpUntil(_ condition: () -> Bool) {
            let deadline = Date().addingTimeInterval(3)
            while !condition() && Date() < deadline {
                _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.005))
            }
            precondition(condition(), "asynchronous preview did not complete")
        }
        let manager = WallpaperManager.shared
        let service = SteamWorkshopService.shared
        let commands = PlaybackCommandMultiplexer.shared
        let video = VideoWallpaper(id: "video-a", displayTitle: String(repeating: "一段很长的壁纸名称", count: 12))
        manager.wallpapers = [video]
        let committed = WallpaperManager.Selection(ticket: .init(id: UUID()))
        let candidate = WallpaperManager.Selection(ticket: .init(id: UUID()))
        manager.switchSelections[committed.ticket.id] = .video(video)
        manager.switchSelections[candidate.ticket.id] = .web("candidate")
        manager.playbackSwitch.committed = committed
        manager.playbackSwitch.pending = candidate
        let reference = WallpaperReference(provider: .videoLibrary, sourceID: video.id)
        let nextReference = WallpaperReference(provider: .steamWorkshop, sourceID: "next")
        manager.libraryPlaybackSequence.committed = .init(snapshot: .init(entries: [.init(reference: reference, isPlayable: true)]), reference: reference)
        let workspace = MyWallpaperXApplication.libraryWorkspace!
        func snapshot() -> StatusBarPanelPresentation {
            .capture(manager: manager, service: service, rememberedReference: workspace.restoration.rememberedReference,
                     rememberedContent: workspace.restoration.rememberedReference.flatMap { workspace.items[$0] })
        }
        precondition(snapshot().content == .video(video), "pending must not replace the confirmed cover")
        precondition(snapshot().isSwitching && !snapshot().canNavigate, "one current rotation item is a no-op")
        manager.playbackSwitch.pending = nil
        commands.isSystemPaused = true
        precondition(snapshot().status.contains("系统已暂停") && snapshot().canTogglePlayback)
        commands.isUserPaused = true
        precondition(snapshot().canTogglePlayback, "user intent may resume without removing the system pause")
        commands.isSystemPaused = false
        commands.isAnyEnginePlaying = false
        precondition(snapshot().status.contains("已暂停"))
        commands.isUserPaused = false
        commands.isAnyEnginePlaying = true
        let toggle = ToggleHarness()
        toggle.toggle()
        precondition(commands.isUserPaused && !manager.isPlaying, "manual pause must persist across exit")
        precondition(workspace.catalogReads == 0, "active playback controls never rebuild a standby catalog projection")
        commands.isSystemPaused = true
        toggle.toggle()
        precondition(!commands.isUserPaused && !manager.isPlaying && !commands.isAnyEnginePlaying,
                     "resuming intent persists while system policy remains paused")
        toggle.toggle()
        precondition(commands.isUserPaused && !manager.isPlaying, "a user may pause independently during a system pause")
        commands.isUserPaused = false
        commands.isSystemPaused = false
        commands.isAnyEnginePlaying = true
        PlaybackMuteState.shared.isMuted = true
        precondition(snapshot().isMuted && snapshot().volume == 50, "mute preserves gain")

        let controller = StatusBarPanelViewController()
        controller.apply(snapshot(), refreshToken: 0)
        precondition(AppKitThumbnailProvider.completions.isEmpty, "opening only enqueues cache preparation")
        pumpUntil { AppKitThumbnailProvider.completions.count == 1 }
        var actions: [String] = []
        controller.onAction = { action in
            switch action {
            case .previous: actions.append("previous")
            case .next: actions.append("next")
            case .playback: actions.append("playback")
            case .mute: actions.append("mute")
            case .volume(let value): actions.append("volume:\(Int(value))")
            case .settings: actions.append("settings")
            case .openMain: actions.append("home")
            case .mode: actions.append("mode")
            case .quit: actions.append("quit")
            default: break
            }
        }
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 344, height: 520),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = controller.view
        let panel = controller.panel
        func layout(_ state: StatusBarPanelPresentation, appearance: NSAppearance.Name) {
            controller.apply(state, refreshToken: 0)
            window.setContentSize(NSSize(width: 344, height: state.preferredHeight))
            panel.appearance = NSAppearance(named: appearance)
            panel.applyMetrics(SystemStats())
            panel.layoutSubtreeIfNeeded()
            precondition(panel.bounds.width == 344 && panel.bounds.height == state.preferredHeight)
            precondition(!panel.hasAmbiguousLayout)
            for child in panel.subviews where !child.isHidden {
                precondition(panel.bounds.contains(child.frame), "visible child escaped: \(child) \(child.frame)")
            }
            precondition(panel.titleLabel.frame.maxX <= 328 && panel.quit.frame.maxY <= panel.bounds.height)
        }
        layout(snapshot(), appearance: .darkAqua)
        let greeting = panel.subviews.compactMap { $0 as? NSTextField }
            .first { $0.accessibilityIdentifier() == "status-panel-greeting" }!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let selectedAt = Date(timeIntervalSince1970: 14 * 3600 + 30 * 60)
        let selectedInstant = ContinuousClock.now
        panel.prepareForPresentation(at: selectedAt, calendar: calendar, instant: selectedInstant)
        let firstGreeting = greeting.stringValue
        for elapsed in [1.0, 1800, 3599] {
            panel.prepareForPresentation(at: selectedAt.addingTimeInterval(elapsed), calendar: calendar,
                                         instant: selectedInstant.advanced(by: .seconds(elapsed)))
            controller.apply(snapshot(), refreshToken: 0)
            panel.applyMetrics(SystemStats())
            precondition(greeting.stringValue == firstGreeting, "opening, metrics and playback updates retain the greeting for a full hour")
        }
        panel.prepareForPresentation(at: selectedAt.addingTimeInterval(-86400), calendar: calendar,
                                     instant: selectedInstant.advanced(by: .seconds(3599)))
        precondition(greeting.stringValue == firstGreeting, "wall-clock changes cannot shorten the retention period")
        panel.prepareForPresentation(at: selectedAt.addingTimeInterval(3600), calendar: calendar,
                                     instant: selectedInstant.advanced(by: .seconds(3600)))
        precondition(greeting.stringValue != firstGreeting, "an expired greeting is replaced without an immediate repeat")
        let timeMessages = [
            (0..<5, ["留一盏温柔的光", "让喜欢的画面陪你"]),
            (5..<8, ["早安又是新一天", "把晨光带进桌面"]),
            (8..<12, ["今天也有好风景", "给今天一点新鲜感"]),
            (12..<14, ["歇一会儿看看风景", "留片刻给好心情"]),
            (14..<18, ["午后适合换个风景", "偶尔走神也不错"]),
            (18..<23, ["把晚风留在桌面", "今晚就慢一点吧"]),
            (23..<24, ["留一盏温柔的光", "让喜欢的画面陪你"])
        ]
        for hour in 0..<24 {
            let probe = StatusBarPanelView(frame: panel.frame)
            probe.prepareForPresentation(at: Date(timeIntervalSince1970: Double(hour * 3600)), calendar: calendar)
            let label = probe.subviews.compactMap { $0 as? NSTextField }
                .first { $0.accessibilityIdentifier() == "status-panel-greeting" }!
            let allowed = timeMessages.first { $0.0.contains(hour) }!.1 + ["给作者点个星标吧"]
            precondition(allowed.contains(label.stringValue), "local hour uses only the approved copy")
        }
        precondition(panel.cover.frame.size == NSSize(width: 312, height: 176))
        precondition(panel.openMain.frame.maxY < panel.cover.frame.minY && panel.settings.frame.minY > panel.volume.frame.maxY)
        precondition(!panel.settings.isBordered && panel.settings.title == "打开设置")
        precondition(panel.volume.doubleValue == 0 && snapshot().volume == 50 && panel.subviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "0%" }, "muting moves the visible slider to zero without changing stored gain")
        PlaybackMuteState.shared.isMuted = false
        controller.apply(snapshot(), refreshToken: 0)
        pumpUntil { AppKitThumbnailProvider.completions.count == 1 }
        precondition(panel.volume.doubleValue == 50, "unmuting restores the retained slider position")
        manager.settings.volume = 73
        PlaybackMuteState.shared.isMuted = true
        controller.apply(snapshot(), refreshToken: 0)
        precondition(panel.volume.doubleValue == 0 && snapshot().volume == 73)
        PlaybackMuteState.shared.isMuted = false
        controller.apply(snapshot(), refreshToken: 0)
        precondition(panel.volume.doubleValue == 73)
        manager.settings.volume = 50
        precondition(panel.playback.frame.midX == panel.bounds.midX)
        precondition(panel.cover.properties.isHidden && !panel.volume.isHidden)
        controller.apply(snapshot(), refreshToken: 0)
        precondition(AppKitThumbnailProvider.completions.count == 1, "metric ticks cannot reload an unchanged cover")
        controller.thumbnailBecameReady(at: "/fixture/another.mp4")
        precondition(AppKitThumbnailProvider.completions.count == 1, "another video's ready cannot reload this cover")
        controller.thumbnailBecameReady(at: video.path)
        pumpUntil { AppKitThumbnailProvider.completions.count == 2 }
        precondition(AppKitThumbnailProvider.completions.count == 2)
        let readyImage = NSImage(size: NSSize(width: 40, height: 30))
        AppKitThumbnailProvider.completions[1](readyImage)
        precondition(panel.cover.subviews.compactMap { $0 as? NSImageView }.first!.image === readyImage,
                     "late derived thumbnail must fill the existing panel")
        panel.openMain.performClick(nil)
        panel.settings.performClick(nil)
        panel.mode.performClick(nil)
        panel.quit.performClick(nil)
        precondition(actions == ["home", "settings", "mode", "quit"], "swapped controls keep their correct actions")
        actions.removeAll()
        panel.playback.performClick(nil)
        panel.mute.performClick(nil)
        panel.volume.doubleValue = 25
        _ = panel.volume.sendAction(panel.volume.action, to: panel.volume.target)
        precondition(actions == ["playback", "mute", "volume:25"])

        let record = SteamWorkshopDownloadRecord(id: "scene", title: "午后时光", contentType: .scene)
        service.downloads = [record]
        manager.switchSelections[committed.ticket.id] = .scene("scene")
        layout(snapshot(), appearance: .aqua)
        pumpUntil { FixtureImageLoads.completions.count == 1 }
        precondition(!panel.cover.properties.isHidden)
        manager.libraryPlaybackSequence.committed = .init(snapshot: .init(entries: [
            .init(reference: reference, isPlayable: true), .init(reference: nextReference, isPlayable: true)]), reference: reference)
        precondition(snapshot().canNavigate, "navigation reads the committed sequence instead of scanning private sources")
        window.setContentSize(NSSize(width: 344, height: 360))
        panel.layoutSubtreeIfNeeded()
        precondition(panel.quit.frame.maxY <= panel.bounds.height && !panel.compactProperties.isHidden && panel.cover.properties.isHidden,
                     "small visible area must preserve the footer and keep properties accessible beside the title")
        precondition(!panel.compactProperties.frame.intersects(panel.mode.frame), "compact properties and mode have separate hit areas")
        window.setContentSize(NSSize(width: 344, height: 536))
        panel.layoutSubtreeIfNeeded()
        let imageA = NSImage(size: NSSize(width: 10, height: 10))
        AppKitThumbnailProvider.completions[0](imageA)
        let imageView = panel.cover.subviews.compactMap { $0 as? NSImageView }.first!
        precondition(imageView.image == nil, "late video cover cannot replace Scene")
        precondition(AppKitThumbnailProvider.cancellations[0].cancelled)
        controller.releasePreview()
        controller.thumbnailBecameReady(at: video.path)
        precondition(AppKitThumbnailProvider.completions.count == 2, "closed panel releases ready demand")
        AppKitThumbnailProvider.completions[0](imageA)
        precondition(imageView.image == nil, "closed panel cannot accept stale images")
        controller.apply(snapshot(), refreshToken: 0)
        pumpUntil { FixtureImageLoads.completions.count == 2 }
        precondition(FixtureImageLoads.cancellations[0].cancelled, "reopen gets a fresh consumer")
        FixtureImageLoads.completions[0](readyImage)
        var flushed = false
        DispatchQueue.main.async { flushed = true }
        pumpUntil { flushed }
        precondition(imageView.image == nil, "a closed local preview cannot replace the new consumer")
        FixtureImageLoads.completions[1](readyImage)
        pumpUntil { imageView.image === readyImage }
        var withRemoteFallback = record
        withRemoteFallback.browserItem = .init(previewImageURL: URL(string: "https://example.invalid/cover.jpg"))
        service.downloads = [withRemoteFallback]
        controller.apply(snapshot(), refreshToken: 0)
        pumpUntil { FixtureImageLoads.completions.count == 3 }
        FixtureImageLoads.completions[2](nil)
        pumpUntil { SteamWorkshopPreviewState.requests == 1 }
        precondition(imageView.image == nil, "a missing local cover falls through to the original remote consumer")
        var remoteOnly = record
        remoteOnly.previewURL = URL(string: "https://example.invalid/remote-only.jpg")
        service.downloads = [remoteOnly]
        controller.apply(snapshot(), refreshToken: 0)
        pumpUntil { SteamWorkshopPreviewState.requests == 2 }

        manager.switchSelections[committed.ticket.id] = .systemStill(URL(fileURLWithPath: "/fixture/静态壁纸.jpg"))
        layout(snapshot(), appearance: .darkAqua)
        precondition(!snapshot().content.isDynamic && panel.volume.isHidden && panel.playback.isHidden)
        manager.playbackSwitch.committed = nil
        layout(snapshot(), appearance: .aqua)
        precondition(snapshot().content == .none)
        manager.wallpapers = []; service.downloads = []
        manager.libraryPlaybackSequence.committed = nil
        layout(snapshot(), appearance: .darkAqua)
        precondition(!snapshot().canNavigate && !panel.previous.isEnabled && !panel.next.isEnabled)
        controller.releasePreview()
        manager.wallpapers = [video]
        workspace.restoration.rememberedReference = reference
        workspace.items[reference] = .init(title: video.displayTitle, providerReference: reference, kind: .video)
        layout(snapshot(), appearance: .darkAqua)
        precondition(snapshot().isStandby && snapshot().canTogglePlayback && snapshot().status.contains("点按恢复"))
        toggle.toggle()
        precondition(workspace.restoration.calls == 1, "standby delegates to the canonical restoration owner")
        service.launchPendingRecordID = "preparing"
        toggle.toggle()
        precondition(workspace.restoration.calls == 1 && !snapshot().canTogglePlayback)
        service.launchPendingRecordID = nil
        workspace.restoration.accepted = false
        toggle.toggle()
        precondition(MainWindowCoordinator.activations == 1, "a rejected manual restore brings its existing error into view")
        workspace.restoration.accepted = true
        toggle.cycleMode(); precondition(manager.mode == .sequential)
        toggle.cycleMode(); precondition(manager.mode == .random)
        toggle.cycleMode(); precondition(manager.mode == .loop)
        workspace.restoration.rememberedReference = nil
        manager.playbackSwitch.committed = committed
        manager.switchSelections[committed.ticket.id] = .systemStill(URL(fileURLWithPath: "/image.jpg"))
        manager.libraryRotationEligible = true
        layout(snapshot(), appearance: .aqua)
        precondition(snapshot().canTogglePlayback && !panel.playback.isHidden && panel.volume.isHidden)
        commands.isUserPaused = false
        toggle.toggle()
        precondition(commands.isUserPaused && snapshot().playbackHelp == "继续轮换")
        manager.libraryRotationEligible = false
        precondition(!snapshot().canTogglePlayback)
        manager.playbackSwitch.committed = committed
        manager.switchSelections[committed.ticket.id] = .video(video)
        controller.releasePreview()
        controller.apply(snapshot(), refreshToken: 0)
        let readsBeforeMiss = AppKitThumbnailProvider.completions.count
        pumpUntil { AppKitThumbnailProvider.completions.count > readsBeforeMiss }
        let cacheMiss = AppKitThumbnailProvider.completions.last!
        let generationsBefore = manager.thumbnailGenerationCallbacks.count
        cacheMiss(nil)
        precondition(manager.thumbnailGenerationCallbacks.count == generationsBefore + 1, "status-only video replay generates a missing thumbnail on demand")
        manager.thumbnailGenerationCallbacks.last!("/generated.jpg")
        let readsBeforeGenerated = AppKitThumbnailProvider.completions.count
        pumpUntil { AppKitThumbnailProvider.completions.count > readsBeforeGenerated }
        let generatedRead = AppKitThumbnailProvider.completions.last!
        generatedRead(readyImage)
        precondition(imageView.image === readyImage)
        generatedRead(nil)
        precondition(manager.thumbnailGenerationCallbacks.count == generationsBefore + 1, "a failed derived image read must not recurse into generation")
        controller.releasePreview()
        controller.apply(snapshot(), refreshToken: 0)
        let readsBeforeDelayed = AppKitThumbnailProvider.completions.count
        pumpUntil { AppKitThumbnailProvider.completions.count > readsBeforeDelayed }
        AppKitThumbnailProvider.completions.last!(nil)
        let delayedGeneration = manager.thumbnailGenerationCallbacks.last!
        controller.releasePreview()
        let readsBeforeClose = AppKitThumbnailProvider.completions.count
        delayedGeneration("/generated-after-close.jpg")
        precondition(AppKitThumbnailProvider.completions.count == readsBeforeClose && imageView.image == nil,
                     "late generation cannot reacquire a closed panel's image consumer")
        print("status-panel-checks-passed")
    }
}
