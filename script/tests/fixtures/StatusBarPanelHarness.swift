import AppKit

// Boundary doubles supply input values and controllable asynchronous results.
// All layout, button wiring, snapshot projection and preview acceptance below
// execute the production files, without starting an engine or a system item.
struct VideoWallpaper: Codable, Equatable {
    let id: String
    var displayTitle: String
    var path = "/fixture/video.mp4"
    var thumbnailPath: String?
    var isFavorite = false
    var duration: Int?
}
struct SteamWorkshopDownloadRecord: Equatable {
    enum Kind { case video, web, scene }
    enum Status { case ready, queued }
    enum Dependency: Equatable { case ready, missing(String) }
    struct Browser: Equatable { let previewImageURL: URL? }
    let id: String
    var title: String
    let contentType: Kind
    var status = Status.ready
    var dependencyStatus = Dependency.ready
    var previewURL: URL? = URL(fileURLWithPath: "/fixture/cover.jpg")
    var browserItem: Browser?
    var updatedAt = Date(timeIntervalSince1970: 1)
}
enum WallpaperMediaKind { case image, video, web, scene, unknown }
struct WallpaperReference: Hashable {
    enum Provider { case videoLibrary, staticImageLibrary, steamWorkshop, pixabay, wallhaven, pixiv }
    let provider: Provider
    let sourceID: String
}
struct WallpaperContentItem: Equatable {
    struct Metadata: Equatable { var thumbnailPath: String?; var previewURL: URL?; var resourceRevision: String? }
    struct Locator: Equatable { var path: String? }
    var title: String
    let providerReference: WallpaperReference
    let kind: WallpaperMediaKind
    var reference: WallpaperReference { providerReference }
    var organizationItem: WallpaperOrganizationItem { .init(reference: reference) }
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
    var cpuUsageString = "12%"
    var gpuUsageString = "8%"
    var memUsedString = "12.4 GB"
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
    static var urls: [URL] = []
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
        FixtureImageLoads.urls.append(url)
    }
}
nonisolated func steamWorkshopPreviewImageIsUsable(_ image: NSImage) -> Bool { image.size.width > 4 && image.size.height > 4 }
final class AppKitThumbnailProvider {
    static var completions: [(NSImage?) -> Void] = []
    static var cancellations: [ThumbnailCacheRequestCancellation] = []
    static var wallpapers: [VideoWallpaper] = []
    init(wallpaperManager: WallpaperManager) {}
    func loadThumbnail(for item: VideoWallpaper, completion: @escaping (NSImage?) -> Void) -> ThumbnailCacheRequestCancellation {
        let cancellation = ThumbnailCacheRequestCancellation()
        Self.cancellations.append(cancellation)
        Self.completions.append(completion)
        Self.wallpapers.append(item)
        return cancellation
    }
}
final class SteamWorkshopPreviewState {
    enum Placeholder { case loading, unavailable }
    var image: NSImage?
    var placeholder = Placeholder.unavailable
    var onChange: (() -> Void)?
    static var requests = 0
    static weak var lastConfigured: SteamWorkshopPreviewState?
    func reset() { image = nil; placeholder = .unavailable; onChange?() }
    func configure(previewURL: URL?, fallbackImageURL: URL? = nil, fallbackVideoURL: URL?, refreshToken: Int, maxPixelSize: Int) {
        precondition(fallbackVideoURL == nil, "opening a panel must not generate a movie thumbnail")
        precondition(previewURL?.isFileURL != true && fallbackImageURL?.isFileURL != true,
                     "local version reads must not enter the main-thread remote consumer")
        Self.requests += 1
        Self.lastConfigured = self
        placeholder = .loading
    }
}

@MainActor enum MyWallpaperXApplication { static var libraryWorkspace: Workspace? = Workspace() }
@MainActor final class RememberedRestoration {
    var rememberedReference: WallpaperReference?
    var calls = 0
    var accepted = true
    func resumeLastSelection(onFailure: @escaping () -> Void = {}) -> Bool { calls += 1; return accepted }
}
struct WallpaperOrganizationItem { let reference: WallpaperReference }
struct Favorite { let reference: WallpaperReference }
struct Relationships {
    var favorites: [Favorite] = []
    // Canonical resolver answers are a controlled boundary here; its actual
    // alias-chain algorithm is exercised by the relationship / query gates.
    var canonicalReferences: [WallpaperReference: WallpaperReference] = [:]
}
@MainActor enum WallpaperLibraryQuery {
    static func canonicalReferences(_ references: Set<WallpaperReference>, relationships: Relationships) throws -> [WallpaperReference: WallpaperReference] {
        Dictionary(uniqueKeysWithValues: references.map { ($0, relationships.canonicalReferences[$0] ?? $0) })
    }
}
enum UserCollectionsCommand { case setFavorite(WallpaperOrganizationItem, Bool, Date) }
@MainActor final class Collections {
    var snapshot = Relationships()
    var commands: [UserCollectionsCommand] = []
    var undoNames: [String?] = []
    var waiting: CheckedContinuation<Relationships, Error>?
    func perform(_ command: UserCollectionsCommand, undoName: String?) async throws -> Relationships {
        commands.append(command); undoNames.append(undoName)
        return try await withCheckedThrowingContinuation { waiting = $0 }
    }
    func finish(failing: Bool = false) {
        if failing { waiting?.resume(throwing: CocoaError(.fileWriteUnknown)) }
        else {
            if case let .setFavorite(item, enabled, _) = commands.last! {
                snapshot.favorites.removeAll { $0.reference == item.reference }
                if enabled { snapshot.favorites.append(.init(reference: item.reference)) }
            }
            waiting?.resume(returning: snapshot)
        }
        waiting = nil
    }
}
@MainActor final class Presentation {
    var canEditCollections = true
    var reportedErrors = 0
    func report(_ error: Error) { reportedErrors += 1 }
}
@MainActor final class Workspace {
    let restoration = RememberedRestoration()
    let presentation = Presentation()
    var collections: Collections? = Collections()
    var relationships: Relationships { collections?.snapshot ?? .init() }
    var resolutionReads = 0
    func content(for reference: WallpaperReference) throws -> WallpaperContentItem {
        resolutionReads += 1
        guard let item = items[reference] else { throw CocoaError(.fileReadNoSuchFile) }
        return item
    }
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
    var favoriteInFlight = false
    var refreshes = 0
    func scheduleRefresh() { refreshes += 1 }
    func closeThen(_ action: () -> Void) { action() }
    // PRODUCTION_CAPTURE
    // PRODUCTION_TOGGLE
    // PRODUCTION_MODE
    // PRODUCTION_FAVORITE
    func toggle() { togglePlayback() }
    func cycleMode() { cyclePlaybackMode() }
    func favorite() { toggleFavorite() }
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
        func solidImage(_ color: CGColor, size: NSSize) -> NSImage {
            let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(color); context.fill(NSRect(origin: .zero, size: size))
            return NSImage(cgImage: context.makeImage()!, size: size)
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
        let toggle = ToggleHarness()
        func snapshot() -> StatusBarPanelPresentation { toggle.capturePresentation() }
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

        workspace.items[reference] = .init(title: video.displayTitle, providerReference: reference, kind: .video)
        let collections = workspace.collections!
        precondition(snapshot().favoriteReference == reference && !snapshot().isFavorite && snapshot().canFavorite)
        let resolutionReads = workspace.resolutionReads
        toggle.favorite()
        toggle.favorite()
        precondition(toggle.favoriteInFlight && !snapshot().canFavorite && !snapshot().isFavorite,
                     "favorite admits one write and never invents an optimistic persisted state")
        pumpUntil { collections.waiting != nil }
        precondition(collections.commands.count == 1 && workspace.resolutionReads == resolutionReads + 1,
                     "rapid repeat does not resolve or queue a stale second target")
        manager.libraryPlaybackSequence.committed = .init(snapshot: .init(entries: []), reference: nextReference)
        collections.finish()
        pumpUntil { !toggle.favoriteInFlight }
        precondition(collections.snapshot.favorites.map(\.reference) == [reference],
                     "a switch during the write does not favorite the new unrelated wallpaper")
        precondition(!snapshot().isFavorite, "presentation follows the newly committed canonical reference")
        manager.libraryPlaybackSequence.committed = .init(snapshot: .init(entries: []), reference: reference)
        precondition(snapshot().isFavorite && snapshot().canFavorite)
        let alias = WallpaperReference(provider: .videoLibrary, sourceID: "old-video-identity")
        collections.snapshot.canonicalReferences[alias] = reference
        manager.libraryPlaybackSequence.committed = .init(snapshot: .init(entries: []), reference: alias)
        let readsBeforeAlias = workspace.catalogReads
        precondition(snapshot().favoriteReference == reference && snapshot().isFavorite
            && workspace.catalogReads == readsBeforeAlias, "identity publication refreshes the heart without resolving the whole catalog")
        manager.libraryPlaybackSequence.committed = .init(snapshot: .init(entries: []), reference: reference)
        collections.snapshot.favorites = []
        precondition(!snapshot().isFavorite, "external collection publication is the same source of truth")
        collections.snapshot.favorites = [.init(reference: reference)]
        toggle.favorite()
        pumpUntil { collections.waiting != nil }
        collections.finish()
        pumpUntil { !toggle.favoriteInFlight }
        precondition(collections.snapshot.favorites.isEmpty && collections.undoNames.last! == "取消特别喜爱")
        let reportedErrors = workspace.presentation.reportedErrors
        toggle.favorite()
        pumpUntil { collections.waiting != nil }
        collections.finish(failing: true)
        pumpUntil { !toggle.favoriteInFlight }
        precondition(!snapshot().isFavorite && snapshot().canFavorite
            && workspace.presentation.reportedErrors == reportedErrors + 1, "failed writes retain truth and restore the action")
        workspace.presentation.canEditCollections = false
        let beforeReadOnly = workspace.resolutionReads
        toggle.favorite()
        precondition(workspace.resolutionReads == beforeReadOnly && !snapshot().canFavorite,
                     "read-only relationship state cannot queue a favorite write")
        workspace.presentation.canEditCollections = true
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
            case .favorite: actions.append("favorite")
            case .quit: actions.append("quit")
            default: break
            }
        }
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 303, height: 458),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = controller.view
        let panel = controller.panel
        func layout(_ state: StatusBarPanelPresentation, appearance: NSAppearance.Name) {
            controller.apply(state, refreshToken: 0)
            window.setContentSize(NSSize(width: 303, height: state.preferredHeight))
            panel.appearance = NSAppearance(named: appearance)
            panel.applyMetrics(SystemStats())
            panel.layoutSubtreeIfNeeded()
            precondition(panel.bounds.width == 303 && panel.bounds.height == state.preferredHeight)
            precondition(!panel.hasAmbiguousLayout)
            for child in panel.subviews where !child.isHidden {
                precondition(panel.bounds.contains(child.frame), "visible child escaped: \(child) \(child.frame)")
            }
            precondition(panel.titleLabel.frame.maxX <= 288.64 && panel.quit.frame.maxY <= panel.bounds.height)
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
            (5..<8, ["早安，又是新一天", "把晨光带进桌面"]),
            (8..<12, ["今天也有好风景", "给今天一点新鲜感"]),
            (12..<14, ["歇一会儿，看看风景", "留片刻给好心情"]),
            (14..<18, ["午后适合换个风景", "偶尔走神也不错"]),
            (18..<23, ["把晚风留在桌面", "今晚，就慢一点吧"]),
            (23..<24, ["留一盏温柔的光", "让喜欢的画面陪你"])
        ]
        for hour in 0..<24 {
            let probe = StatusBarPanelView(frame: panel.frame)
            probe.prepareForPresentation(at: Date(timeIntervalSince1970: Double(hour * 3600)), calendar: calendar)
            let label = probe.subviews.compactMap { $0 as? NSTextField }
                .first { $0.accessibilityIdentifier() == "status-panel-greeting" }!
            let allowed = timeMessages.first { $0.0.contains(hour) }!.1 + ["给作者点个星标吧"]
            precondition(allowed.contains(label.stringValue), "local hour \(hour) uses only the approved copy: \(label.stringValue)")
        }
        precondition(abs(panel.cover.frame.width - 274.84) < 0.001
            && abs(panel.cover.frame.height - 155.2) < 0.001,
                     "cover retains its 88% insets and control budget in the native 303 by 472 point panel")
        precondition(panel.bounds.height == 472, "dynamic panel is 10% larger than the previous 80% size to the nearest native point")
        precondition(Set(panel.subviews.compactMap { ($0 as? NSTextField)?.stringValue }).isSuperset(of: ["CPU", "GPU", "内存"]),
            "metric titles keep the user-selected concise wording")
        precondition(panel.subviews.compactMap { $0 as? NSTextField }.contains { $0.toolTip == "系统全部 GPU 使用率" },
                     "GPU scope remains available in its tooltip with concise titles")
        precondition(panel.subviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "12.4 GB" && $0.toolTip?.contains("本应用") == true },
                     "process memory has no misleading system-total denominator")
        precondition(!panel.favorite.isHidden && panel.favorite.isEnabled && panel.favorite.state == .off)
        precondition(panel.favorite.frame.maxX < panel.mode.frame.minX, "favorite is immediately left of mode with its own hit area")
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
        collections.snapshot.favorites = [.init(reference: reference)]
        controller.apply(snapshot(), refreshToken: 0)
        panel.favorite.updateLayer()
        precondition(panel.favorite.state == .on && panel.favorite.contentTintColor == .systemRed,
                     "confirmed favorites use a red heart")
        precondition(AppKitThumbnailProvider.completions.count == 2, "favorite feedback does not reload the cover")
        collections.snapshot.favorites = []
        controller.apply(snapshot(), refreshToken: 0)
        panel.favorite.updateLayer()
        precondition(panel.favorite.state == .off && panel.favorite.contentTintColor == .labelColor)
        let readyImage = solidImage(CGColor(red: 0, green: 0, blue: 1, alpha: 1), size: NSSize(width: 40, height: 30))
        AppKitThumbnailProvider.completions[1](readyImage)
        precondition(panel.cover.subviews.compactMap { $0 as? NSImageView }.first!.image === readyImage,
                     "late derived thumbnail must fill the existing panel")
        panel.openMain.performClick(nil)
        panel.settings.performClick(nil)
        panel.mode.performClick(nil)
        panel.favorite.performClick(nil)
        panel.quit.performClick(nil)
        precondition(actions == ["home", "settings", "mode", "favorite", "quit"], "swapped controls keep their correct actions")
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
        window.setContentSize(NSSize(width: 303, height: 317))
        panel.layoutSubtreeIfNeeded()
        precondition(panel.quit.frame.maxY <= panel.bounds.height && !panel.compactProperties.isHidden && panel.cover.properties.isHidden,
                     "small visible area must preserve the footer and keep properties accessible beside the title")
        precondition(!panel.compactProperties.frame.intersects(panel.mode.frame)
            && !panel.compactProperties.frame.intersects(panel.favorite.frame), "compact properties, favorite and mode have separate hit areas")
        window.setContentSize(NSSize(width: 303, height: 472))
        panel.layoutSubtreeIfNeeded()
        let imageA = solidImage(CGColor(red: 1, green: 0, blue: 0, alpha: 1), size: NSSize(width: 10, height: 10))
        AppKitThumbnailProvider.completions[0](imageA)
        let imageView = panel.cover.subviews.compactMap { $0 as? NSImageView }.first!
        precondition(imageView.image === readyImage, "late video cover cannot replace the retained cover while Scene loads")
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
        precondition(imageView.image === readyImage, "a missing local candidate keeps the cover while its remote fallback loads")
        var remoteOnly = record
        remoteOnly.previewURL = URL(string: "https://example.invalid/remote-only.jpg")
        service.downloads = [remoteOnly]
        controller.apply(snapshot(), refreshToken: 0)
        pumpUntil { SteamWorkshopPreviewState.requests == 2 }
        let obsoleteRemote = SteamWorkshopPreviewState.lastConfigured!
        let obsoleteRemoteChange = obsoleteRemote.onChange!

        manager.switchSelections[committed.ticket.id] = .systemStill(URL(fileURLWithPath: "/fixture/静态壁纸.jpg"))
        layout(snapshot(), appearance: .darkAqua)
        obsoleteRemote.image = imageA; obsoleteRemoteChange()
        precondition(imageView.image === readyImage, "an obsolete remote request cannot replace the retained cover of the new source")
        precondition(!snapshot().content.isDynamic && panel.volume.isHidden && panel.playback.isHidden)
        precondition(!panel.next.frame.intersects(panel.mode.frame)
            && !panel.previous.frame.intersects(panel.favorite.frame), "still wallpaper actions do not overlap mode or favorite")
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

        let coverController = StatusBarPanelViewController()
        func applyCover(_ content: StatusBarPanelPresentation.Content, token: Int = 17) {
            coverController.apply(.init(content: content, isStandby: false, playbackMode: .loop,
                isPlaying: true, isUserPaused: false, isSystemPaused: false, isSwitching: false,
                isRotating: false, isMuted: false, volume: 50, canNavigate: false), refreshToken: token)
        }
        let firstVideoRead = AppKitThumbnailProvider.completions.count
        applyCover(.video(video))
        pumpUntil { AppKitThumbnailProvider.completions.count == firstVideoRead + 1 }
        let stableCover = coverController.panel.cover.subviews.compactMap { $0 as? NSImageView }.first!
        var editedVideo = video
        editedVideo.displayTitle = "改名后的壁纸"
        editedVideo.isFavorite = true
        editedVideo.duration = 42
        applyCover(.video(editedVideo))
        precondition(!AppKitThumbnailProvider.cancellations[firstVideoRead].cancelled,
                     "metadata echo must retain an in-flight video image consumer")
        AppKitThumbnailProvider.completions[firstVideoRead](readyImage)
        precondition(stableCover.image === readyImage && coverController.panel.titleLabel.stringValue == editedVideo.displayTitle,
                     "metadata updates the title while accepting the original resource request")
        editedVideo.displayTitle = "再次改名"
        applyCover(.video(editedVideo))
        precondition(stableCover.image === readyImage && AppKitThumbnailProvider.completions.count == firstVideoRead + 1,
                     "an already visible video cover cannot flash or reread for metadata")
        coverController.thumbnailBecameReady(at: editedVideo.path)
        pumpUntil { AppKitThumbnailProvider.completions.count == firstVideoRead + 2 }
        precondition(AppKitThumbnailProvider.wallpapers.last == editedVideo,
                     "same-resource metadata retains the latest snapshot for derived-image readiness")
        AppKitThumbnailProvider.completions.last!(readyImage)

        applyCover(.video(editedVideo), token: 18)
        precondition(stableCover.image === readyImage && AppKitThumbnailProvider.cancellations.last!.cancelled,
                     "an explicit refresh revokes the previous request while retaining the ready cover")
        pumpUntil { AppKitThumbnailProvider.completions.count == firstVideoRead + 3 }
        AppKitThumbnailProvider.completions.last!(readyImage)
        editedVideo.thumbnailPath = "/fixture/new-derived.jpg"
        applyCover(.video(editedVideo), token: 18)
        precondition(stableCover.image === readyImage)
        pumpUntil { AppKitThumbnailProvider.completions.count == firstVideoRead + 4 }
        precondition(AppKitThumbnailProvider.wallpapers.last?.thumbnailPath == editedVideo.thumbnailPath,
                     "a changed derived asset path must enter the actual thumbnail provider")
        let supersededDerivedRead = AppKitThumbnailProvider.completions.last!
        editedVideo.path = "/fixture/replaced-video.mp4"
        applyCover(.video(editedVideo), token: 18)
        pumpUntil { AppKitThumbnailProvider.completions.count == firstVideoRead + 5 }
        supersededDerivedRead(imageA)
        precondition(stableCover.image === readyImage && AppKitThumbnailProvider.wallpapers.last?.path == editedVideo.path,
                     "source-path changes cannot accept a prior derived asset's late result")
        AppKitThumbnailProvider.completions.last!(readyImage)
        coverController.releasePreview()

        let firstWorkshopRead = FixtureImageLoads.completions.count
        applyCover(.workshop(record))
        pumpUntil { FixtureImageLoads.completions.count == firstWorkshopRead + 1 }
        FixtureImageLoads.completions[firstWorkshopRead](readyImage)
        pumpUntil { stableCover.image === readyImage }
        var editedRecord = record
        editedRecord.title = "更新标题而非封面"
        editedRecord.dependencyStatus = .missing("optional metadata")
        applyCover(.workshop(editedRecord))
        precondition(stableCover.image === readyImage && !FixtureImageLoads.cancellations[firstWorkshopRead].cancelled
                     && FixtureImageLoads.completions.count == firstWorkshopRead + 1,
                     "workshop metadata cannot clear or reread an unchanged local preview")
        editedRecord.updatedAt = Date(timeIntervalSince1970: 2)
        applyCover(.workshop(editedRecord))
        precondition(stableCover.image === readyImage,
                     "a ready publication version change reloads while retaining the previous cover")
        pumpUntil { FixtureImageLoads.completions.count == firstWorkshopRead + 2 }
        FixtureImageLoads.completions.last!(readyImage)
        pumpUntil { stableCover.image === readyImage }
        editedRecord.browserItem = .init(previewImageURL: URL(string: "https://example.invalid/new-fallback.jpg"))
        applyCover(.workshop(editedRecord))
        precondition(stableCover.image === readyImage,
                     "a changed fallback retains the cover while replacing its request identity")
        pumpUntil { FixtureImageLoads.completions.count == firstWorkshopRead + 3 }
        FixtureImageLoads.completions[firstWorkshopRead](imageA)
        var oldWorkshopFlushed = false
        DispatchQueue.main.async { oldWorkshopFlushed = true }
        pumpUntil { oldWorkshopFlushed }
        precondition(stableCover.image === readyImage, "superseded local image callbacks cannot overwrite the retained cover")
        FixtureImageLoads.completions.last!(readyImage)
        pumpUntil { stableCover.image === readyImage }
        coverController.releasePreview()

        let rememberedReference = WallpaperReference(provider: .pixiv, sourceID: "remembered-image")
        var remembered = WallpaperContentItem(title: "上次的图片", providerReference: rememberedReference, kind: .image)
        remembered.metadata.thumbnailPath = "/fixture/remembered-thumb.jpg"
        remembered.metadata.previewURL = URL(string: "https://example.invalid/remembered.jpg")
        remembered.locator.path = "/fixture/remembered-original.jpg"
        let firstRememberedRead = FixtureImageLoads.completions.count
        applyCover(.remembered(rememberedReference, remembered))
        pumpUntil { FixtureImageLoads.completions.count == firstRememberedRead + 1 }
        precondition(FixtureImageLoads.urls.last?.path == remembered.metadata.thumbnailPath)
        remembered.title = "记忆图片改名"
        applyCover(.remembered(rememberedReference, remembered))
        precondition(!FixtureImageLoads.cancellations[firstRememberedRead].cancelled,
                     "remembered metadata must keep the current candidate request")
        FixtureImageLoads.completions.last!(nil)
        pumpUntil { FixtureImageLoads.completions.count == firstRememberedRead + 2 }
        precondition(FixtureImageLoads.urls.last?.path == remembered.locator.path,
                     "remembered images retain local-thumbnail then local-original fallback order")
        FixtureImageLoads.completions.last!(readyImage)
        pumpUntil { stableCover.image === readyImage }
        remembered.locator.path = "/fixture/changed-remembered-original.jpg"
        applyCover(.remembered(rememberedReference, remembered))
        precondition(stableCover.image === readyImage,
                     "a changed remembered candidate retains its ready cover while reloading")
        pumpUntil { FixtureImageLoads.completions.count == firstRememberedRead + 3 }
        FixtureImageLoads.completions.last!(readyImage)
        pumpUntil { stableCover.image === readyImage }
        remembered.metadata.resourceRevision = "published-image-v2"
        applyCover(.remembered(rememberedReference, remembered))
        precondition(stableCover.image === readyImage,
                     "an explicit source revision revokes the request without flashing the ready cover")
        pumpUntil { FixtureImageLoads.completions.count == firstRememberedRead + 4 }
        FixtureImageLoads.completions.last!(readyImage)
        pumpUntil { stableCover.image === readyImage }
        applyCover(.still(URL(fileURLWithPath: "/fixture/different-still.jpg")))
        precondition(stableCover.image === readyImage)
        pumpUntil { FixtureImageLoads.completions.count == firstRememberedRead + 5 }
        precondition(FixtureImageLoads.urls.last?.path == "/fixture/different-still.jpg")
        FixtureImageLoads.completions.last!(readyImage)
        pumpUntil { stableCover.image === readyImage }
        applyCover(.none)
        precondition(stableCover.image == nil, "no selection still clears the old image")
        var transientRecord = record
        transientRecord.status = .queued
        let firstTransientRead = FixtureImageLoads.completions.count
        applyCover(.workshop(transientRecord))
        pumpUntil { FixtureImageLoads.completions.count == firstTransientRead + 1 }
        transientRecord.updatedAt = Date(timeIntervalSince1970: 99)
        applyCover(.workshop(transientRecord))
        precondition(!FixtureImageLoads.cancellations[firstTransientRead].cancelled,
                     "transfer progress timestamps cannot replace the same image request")
        FixtureImageLoads.completions.last!(readyImage)
        pumpUntil { stableCover.image === readyImage }
        coverController.releasePreview()
        precondition(snapshot().content == .video(video), "the animation scenario uses the current real video presentation")
        layout(snapshot(), appearance: .aqua)
        let coverFrameBeforeFade = panel.cover.frame
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        precondition(window.isVisible && imageView.window === window && !panel.cover.isHiddenOrHasHiddenAncestor
                     && panel.cover.visibleRect.width > 0 && panel.cover.visibleRect.height > 0,
                     "the fade scenario has a real visible native cover in its current presentation")
        func imageViewCacheColor() -> NSColor? {
            guard let bitmap = imageView.bitmapImageRepForCachingDisplay(in: imageView.bounds) else { return nil }
            imageView.cacheDisplay(in: imageView.bounds, to: bitmap)
            return bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB)
        }
        func displayedCoverColor() -> NSColor? {
            let bounds = panel.cover.bounds
            guard bounds.width > 0, bounds.height > 0,
                  let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ceil(bounds.width)),
                    pixelsHigh: Int(ceil(bounds.height)), bitsPerSample: 8, samplesPerPixel: 4,
                    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: bitmap)?.cgContext else { return nil }
            context.clear(bounds)
            panel.cover.layer?.render(in: context)
            return bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB)
        }
        func coverDiagnostics(_ stage: String) {
            func rgba(_ color: NSColor?) -> [CGFloat] {
                guard let color else { return [] }
                return [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
            }
            let facts: [String: Any] = ["stage": stage, "windowVisible": window.isVisible,
                "windowFrame": NSStringFromRect(window.frame), "panelBounds": NSStringFromRect(panel.bounds),
                "coverFrame": NSStringFromRect(panel.cover.frame), "coverBounds": NSStringFromRect(panel.cover.bounds),
                "coverVisibleRect": NSStringFromRect(panel.cover.visibleRect), "coverHidden": panel.cover.isHiddenOrHasHiddenAncestor,
                "imageFrame": NSStringFromRect(imageView.frame), "imageBounds": NSStringFromRect(imageView.bounds),
                "imageVisibleRect": NSStringFromRect(imageView.visibleRect), "imageHidden": imageView.isHiddenOrHasHiddenAncestor,
                "imageIsBlue": imageView.image === readyImage, "imageIsRed": imageView.image === imageA,
                "imageSize": NSStringFromSize(imageView.image?.size ?? .zero),
                "coverLayerRGBA": rgba(displayedCoverColor()), "imageViewCacheRGBA": rgba(imageViewCacheColor()),
                "imageLayerContents": String(describing: imageView.layer?.contents),
                "imageLayerAnimations": imageView.layer?.animationKeys() ?? [], "appearance": imageView.effectiveAppearance.name.rawValue]
            FileHandle.standardError.write((try? JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys])) ?? Data())
            FileHandle.standardError.write(Data([10]))
        }
        panel.cover.setImage(readyImage)
        panel.cover.layoutSubtreeIfNeeded(); window.displayIfNeeded(); CATransaction.flush()
        let oldIsBlue = displayedCoverColor().map { $0.blueComponent > 0.9 && $0.redComponent < 0.1 && $0.alphaComponent > 0.9 } == true
        if !oldIsBlue { coverDiagnostics("old-blue-missing") }
        precondition(oldIsBlue,
                     "the old cover has actual displayed blue pixels before replacement")
        panel.cover.setImage(imageA)
        panel.cover.layoutSubtreeIfNeeded(); imageView.displayIfNeeded(); window.displayIfNeeded()
        let fade = imageView.layer?.animation(forKey: StatusBarPanelCoverView.transitionKey) as? CATransition
        precondition(imageView.image === imageA && panel.cover.frame == coverFrameBeforeFade,
                     "native crossfade preserves the selected compact cover geometry")
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && fade?.type != .fade { coverDiagnostics("fade-missing-after-display") }
        precondition(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || fade?.type == .fade,
                     "the image's AppKit backing layer keeps its fade after its new contents display")
        let pixelDeadline = Date().addingTimeInterval(3)
        var newIsRed = false
        repeat {
            newIsRed = displayedCoverColor().map { $0.redComponent > 0.9 && $0.blueComponent < 0.1 && $0.alphaComponent > 0.9 } == true
            if newIsRed { break }
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.005))
        } while Date() < pixelDeadline
        if !newIsRed { coverDiagnostics("new-red-missing") }
        precondition(newIsRed, "the new cover has actual displayed red pixels after replacement")
        panel.cover.setImage(nil)
        precondition(imageView.image == nil && imageView.layer?.animation(forKey: StatusBarPanelCoverView.transitionKey) == nil,
                     "explicit clear retires a pending cover animation")
        print("status-panel-checks-passed")
    }
}
