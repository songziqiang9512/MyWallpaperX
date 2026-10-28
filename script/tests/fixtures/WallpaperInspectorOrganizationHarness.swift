import AppKit
import Combine
import ImageIO
import QuartzCore

// Original UI, footer controls and downloaded cache run in this gate. The SIL
// cache, AV frame and alert leaves are controlled without using a real library.
struct SILWallpaper: Equatable {
    let id: String
    let title: String
    var path: String
    var tags: [String] = []
    var addedAt = Date()
    var lastUsed = Date.distantPast
    var fileSize: Int64? = nil
    var pixelWidth: Int? = nil
    var pixelHeight: Int? = nil
}
final class SILService {
    static let shared = SILService()
    var wallpapers: [SILWallpaper] = []
    var currentActiveWallpaperPath: String?
    var silTags: [String] = []
    var writes = 0
    func addSILTag(_ tag: String, toSelected ids: [String]) { writes += 1 }
}
final class CacheLeaf {
    struct Request {
        let key: String
        let cancellation: (any ThumbnailCacheLoadCancellation)?
        let cachesFailure: Bool
        let completion: (NSImage?) -> Void
    }
    var result: NSImage?
    var requests: [Request] = []
    var holdsCompletions = false
    var holdsNext = false
    var pending: [(String, (NSImage?) -> Void)] = []
    var requestedKeys: [String] = []
    var completionThreads: [Bool] = []
    func load(forKey key: String, cancellation: (any ThumbnailCacheLoadCancellation)? = nil,
              cachesFailure: Bool = true,
              loader: @escaping () -> NSImage?, completion: @escaping (NSImage?) -> Void) {
        let userCompletion = completion
        let completion: (NSImage?) -> Void = { [weak self] image in
            self?.completionThreads.append(Thread.isMainThread)
            userCompletion(image)
        }
        // ACTUAL_CACHE_IMAGE_DELIVERY
        requests.append(.init(key: key, cancellation: cancellation, cachesFailure: cachesFailure, completion: deliver))
        requestedKeys.append(key)
        if holdsNext { holdsNext = false; pending.append((key, deliver)); return }
        if !holdsCompletions { deliver(result) }
    }
    func deliverNext(_ image: NSImage?) {
        precondition(Thread.isMainThread && !pending.isEmpty)
        let (_, completion) = pending.removeFirst()
        completion(image)
    }
    func deliver(_ index: Int, image: NSImage?) {
        requests[index].completion(image)
    }
    func cachedImage(forKey: String) -> NSImage? { nil }
}
enum SILThumbnailStore { static let sharedCache = CacheLeaf() }
// The original store, live fingerprint and shared cache are compiled below.
// Only the AV frame leaf is controlled; canceled deliveries are not filtered
// by this leaf, so the real cache and real view must reject them.
nonisolated private final class DownloadedInspectorFrameProbe: @unchecked Sendable {
    static let shared = DownloadedInspectorFrameProbe()
    private let lock = NSLock()
    private var held: Set<String> = []
    private var pending: [String: [CheckedContinuation<NSImage?, Never>]] = [:]
    private var loads: [String: Int] = [:]
    private var defaultImage: NSImage?
    func useDefault(_ image: NSImage) { lock.lock(); defaultImage = image; lock.unlock() }
    func hold(_ path: String) { lock.lock(); held.insert(path); lock.unlock() }
    func count(_ path: String) -> Int { lock.lock(); defer { lock.unlock() }; return loads[path, default: 0] }
    func pendingCount(_ path: String) -> Int { lock.lock(); defer { lock.unlock() }; return pending[path]?.count ?? 0 }
    func image(_ path: String) async -> NSImage? {
        await withCheckedContinuation { continuation in
            lock.lock()
            loads[path, default: 0] += 1
            if held.contains(path) {
                pending[path, default: []].append(continuation)
                lock.unlock()
            } else {
                let image = defaultImage
                lock.unlock()
                continuation.resume(returning: image)
            }
        }
    }
    func release(_ path: String, image: NSImage?) {
        lock.lock()
        held.remove(path)
        let waiters = pending.removeValue(forKey: path) ?? []
        lock.unlock()
        waiters.forEach { $0.resume(returning: image) }
    }
}
nonisolated private final class PixabayThumbnailVideoGeneration: @unchecked Sendable {
    private let url: URL
    init(url: URL) { self.url = url }
    func image() async -> NSImage? { await DownloadedInspectorFrameProbe.shared.image(url.path) }
}
nonisolated final class DownloadedInspectorCacheProbe: @unchecked Sendable {
    struct Request {
        let key: String
        let priority: ThumbnailCacheRequestPriority
        let cancellation: (any ThumbnailCacheLoadCancellation)?
    }
    static let shared = DownloadedInspectorCacheProbe()
    private let lock = NSLock()
    private var storage: [Request] = []
    private var sourceCalls = 0
    private var fingerprintReads: [String: Int] = [:]
    private var mainFingerprintReads = 0
    private var completions: [ObjectIdentifier: (total: Int, images: Int)] = [:]
    var requests: [Request] { lock.lock(); defer { lock.unlock() }; return storage }
    var sourceCallCount: Int { lock.lock(); defer { lock.unlock() }; return sourceCalls }
    func sourceRegistered() { lock.lock(); sourceCalls += 1; lock.unlock() }
    func fingerprintRegistered(_ path: String) {
        lock.lock(); defer { lock.unlock() }
        fingerprintReads[path, default: 0] += 1
        if Thread.isMainThread { mainFingerprintReads += 1 }
    }
    func reads(_ path: String) -> Int { lock.lock(); defer { lock.unlock() }; return fingerprintReads[path, default: 0] }
    var mainReads: Int { lock.lock(); defer { lock.unlock() }; return mainFingerprintReads }
    func completed(_ cancellation: (any ThumbnailCacheLoadCancellation)?, image: NSImage?) {
        guard let cancellation = cancellation as? ThumbnailCacheRequestCancellation else { return }
        lock.lock(); defer { lock.unlock() }
        let id = ObjectIdentifier(cancellation), previous = completions[id] ?? (0, 0)
        completions[id] = (previous.total + 1, previous.images + (image == nil ? 0 : 1))
    }
    func completionCounts(_ cancellation: ThumbnailCacheRequestCancellation) -> (total: Int, images: Int) {
        lock.lock(); defer { lock.unlock() }; return completions[ObjectIdentifier(cancellation)] ?? (0, 0)
    }
    func registered(_ key: String, priority: ThumbnailCacheRequestPriority,
                    cancellation: (any ThumbnailCacheLoadCancellation)?) {
        lock.lock(); defer { lock.unlock() }
        storage.append(.init(key: key, priority: priority, cancellation: cancellation))
    }
}
// ACTUAL_DOWNLOADED_STORE
struct PixabayDownloadedEntry: Equatable {
    let id: Int
    let localURL: URL
    var isAvailable = true
    var fileSize = 12
    var duration: Int? = 2
    var resolutionString: String? = "8×8"
    var thumbnailSourceKey: String? = nil
    var creationDate: Date? = nil
    var modificationDate: Date? = nil
    var displayTitle: String { localURL.lastPathComponent }
    var metaLine: String { [duration.map(PixabayDownloadedAssetMetadata.formatDuration), resolutionString].compactMap { $0 }.joined(separator: "  ") }
}
struct PixabayDownloadedContentSnapshot { var entries: [PixabayDownloadedEntry] = [] }
final class PixabayService {
    static let shared = PixabayService()
    var downloadedContent = PixabayDownloadedContentSnapshot()
    var writes = 0
    var items: [PixabayVideoItem] = []
    @Published var downloadingIDs = Set<Int>()
    var downloadRequests: [Int] = []
    func setLocalFileAsWallpaper(id: Int) { writes += 1 }
    func download(item: PixabayVideoItem) { downloadRequests.append(item.id); downloadingIDs.insert(item.id) }
}
@MainActor final class OnlineImageThumbnailCache {
    enum Priority: Equatable { case visible, prefetch }
    struct Request { let url: URL; let maxPixelSize: Int; let priority: Priority }
    static let shared = OnlineImageThumbnailCache()
    var holds = false
    private(set) var requests: [Request] = []
    private var pending: [Int: CheckedContinuation<NSImage?, Never>] = [:]
    func image(for url: URL, maxPixelSize: Int, priority: Priority) async -> NSImage? {
        let index = requests.count; requests.append(.init(url: url, maxPixelSize: maxPixelSize, priority: priority))
        if !holds { return nil }
        return await withCheckedContinuation { pending[index] = $0 }
    }
    func complete(_ index: Int, _ image: NSImage?) { pending.removeValue(forKey: index)!.resume(returning: image) }
}
enum PixabayDownloadedAssetMetadata { static func formatDuration(_ seconds: Int) -> String { "\(seconds)s" } }
func makeAppAlert(title: String, message: String, buttons: [String], accessoryView: NSView?) -> NSAlert { NSAlert() }
func presentAppAlert(_ alert: NSAlert, in window: NSWindow?, completion: @escaping (NSApplication.ModalResponse) -> Void) {}
func appModalHostWindow() -> NSWindow? { nil }
extension Notification.Name { static let staticImageWallpaperReadyToApply = Notification.Name("staticImageWallpaperReadyToApply") }

@main struct WallpaperInspectorOrganizationHarness {
    @MainActor static func views(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(views) }
    @MainActor static func button(_ root: NSView, _ selector: String) -> InspectorFooterButton? {
        views(root).compactMap { $0 as? InspectorFooterButton }.first { $0.action == NSSelectorFromString(selector) }
    }
    @MainActor static func footerTitle(_ control: InspectorFooterButton?) -> String? {
        control.flatMap { views($0).compactMap { ($0 as? NSTextField)?.stringValue }.first }
    }
    @MainActor static func pump() { RunLoop.main.run(until: Date().addingTimeInterval(0.04)) }
    @MainActor static func waitUntil(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(4)
        repeat { if condition() { return true }; pump() } while Date() < deadline
        return condition()
    }
    @MainActor static func main() throws {
        let runtimeHome = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"]!).resolvingSymlinksInPath().path
        let cacheRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.resolvingSymlinksInPath().path
        precondition(cacheRoot.hasPrefix(runtimeHome + "/"), "shared cache must remain in isolated HOME: \(cacheRoot)")
        _ = NSApplication.shared
        if CommandLine.arguments.count > 2, CommandLine.arguments[2] == "preview-delivery" {
            NSApplication.shared.setActivationPolicy(.prohibited)
            try previewDelivery(URL(fileURLWithPath: CommandLine.arguments[1]))
            return
        }
        let file = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("local.png")
        try Data("local".utf8).write(to: file)
        let images = SILService(), pixabay = PixabayService()
        let image = SILWallpaper(id: "fixed-image", title: "Image", path: file.path, tags: ["Old SIL Tag"])
        images.wallpapers = [image]
        pixabay.downloadedContent.entries = [.init(id: 7, localURL: file)]
        var primary = 0, member = 0, favorites = 0
        var legacyApplyNotifications = 0
        let legacyApplyObserver = NotificationCenter.default.addObserver(forName: .staticImageWallpaperReadyToApply, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { legacyApplyNotifications += 1 }
        }
        defer { NotificationCenter.default.removeObserver(legacyApplyObserver) }
        func actions(canOrganize: Bool = true, playing: Bool = false, canPlay: Bool = true,
                     names: [String] = ["New Mixed List"]) -> WallpaperInspectorActions {
            .init(state: .init(isPlaying: playing, isFavorite: false, canPerformPrimary: canPlay, canFavorite: canOrganize, canOrganize: canOrganize, playlistNames: names),
                onPrimary: { primary += 1 }, onToggleFavorite: { favorites += 1 }, onChoosePlaylist: { _ in member += 1 })
        }
        SILThumbnailStore.sharedCache.result = NSImage(size: NSSize(width: 16, height: 8), flipped: false) { rect in
            NSColor(calibratedRed: 0.05, green: 0.9, blue: 0.1, alpha: 1).setFill(); rect.fill(); return true
        }
        DownloadedInspectorFrameProbe.shared.useDefault(SILThumbnailStore.sharedCache.result!)
        let window = NSWindow(contentRect: NSRect(x: 80, y: 40, width: 800, height: 900),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.toolbar = NSToolbar(identifier: "actual-inspector-layout")
        window.toolbarStyle = .unified
        let hostStore = InspectorHostStore()
        let hostController = InspectorHostViewController(store: hostStore)
        window.contentViewController = hostController
        let host = hostController.view
        // AppKit adopts the controller's initial fitting size on installation.
        // Establish the intended native viewport before starting source loads.
        window.setContentSize(NSSize(width: 800, height: 900))
        window.orderFront(nil)
        defer { window.close() }
        let layoutDeadline = Date().addingTimeInterval(2)
        var previousGeometry: [NSRect]?
        var nativeWindowReady = false
        repeat {
            host.layoutSubtreeIfNeeded()
            pump()
            // AppKit may constrain the requested height to the visible screen.
            // Observe its actual unobscured viewport and two settled native
            // turns; the later actualShort check still proves spare body room.
            let layout = host.convert(window.contentLayoutRect, from: nil)
            let geometry = [window.frame, window.contentLayoutRect, host.bounds]
            nativeWindowReady = previousGeometry == geometry && window.isVisible && host.window === window
                && layout.width >= InspectorHostRequest.defaultPreferredWidth && layout.height > 0
                && host.bounds.contains(layout)
            previousGeometry = geometry
        } while !nativeWindowReady && Date() < layoutDeadline
        let imageView = SILInspectorView(wallpaper: image, service: images, libraryActions: actions())
        let pixabayView = PixabayDownloadsInspectorView(itemID: 7, service: pixabay, libraryActions: actions())
        let pixabayInitialPreview = views(pixabayView).first { $0 is PixabayDownloadsPreviewSurfaceView }!
        let pixabayWasCold = views(pixabayInitialPreview).compactMap { $0 as? NSImageView }.contains { !$0.isHidden }
        func mount(_ view: NSView) {
            let module: ModuleIdentifier = view is SILInspectorView ? .staticImageLibrary : .pixabay
            let request = InspectorHostRequest(token: .init(module: module, cardID: "fixed-layout"), title: "详情", chromeStyle: .infoPanel)
            hostStore.present(request)
            hostStore.mountContent(InspectorHostMountRequest(userInfo: [
                InspectorHostUserInfoKey.module: module.rawValue,
                InspectorHostUserInfoKey.cardID: request.token.cardID,
                InspectorHostUserInfoKey.hostedView: view])!)
            host.layoutSubtreeIfNeeded()
        }
        func topAligned(_ view: NSView, preview: NSView, short: Bool) -> Bool {
            guard let scroll = views(view).compactMap({ $0 as? InspectorFadingScrollView }).first,
                  let document = scroll.documentView, let content = document.subviews.first as? NSStackView,
                  let mask = scroll.layer?.mask as? CAGradientLayer,
                  let colors = mask.colors as? [CGColor], colors.count == 4 else { return false }
            let viewport = document.convert(scroll.contentView.bounds, from: scroll.contentView)
            let firstImage = preview.convert(preview.bounds, to: document)
            let pixel = 1 / window.backingScaleFactor
            let actualShort = content.frame.height < viewport.height - pixel
            let diagnostics: [String] = ["inspector-top", "source=\(type(of: view))", "short=\(actualShort)",
                "document=\(document.bounds)", "viewport=\(viewport)", "content=\(content.frame)",
                "preview=\(firstImage)", "safeArea=\(host.safeAreaLayoutGuide.frame)", "sourceFrame=\(view.convert(view.bounds, to: host))"]
            FileHandle.standardError.write(Data((diagnostics.joined(separator: " ") + "\n").utf8))
            return document.isFlipped && actualShort == short && viewport.contains(firstImage)
                && abs(firstImage.minY - viewport.minY - 8) <= pixel
                && document.bounds.height >= scroll.contentView.bounds.height - pixel
                && colors.first?.alpha == 1 && colors[1].alpha == 1
                && preview.bounds.height == 156
                && views(view).compactMap({ $0 as? InspectorFooterButton }).allSatisfy({ !$0.isDescendant(of: scroll) })
        }
        mount(imageView)
        let imagePreview = views(imageView).first { $0 is SILInspectorPreviewSurfaceView }!
        let imageFrame = imagePreview.convert(imagePreview.bounds, to: host)
        pump(); host.layoutSubtreeIfNeeded()
        var checks: [String: Bool] = [:]
        checks["real-shell-window-has-a-settled-native-viewport-before-source-loads"] = nativeWindowReady
        checks["real-image-completion-retains-preview-object-and-native-frame"] = imagePreview === views(imageView).first { $0 is SILInspectorPreviewSurfaceView }
            && imageFrame == imagePreview.convert(imagePreview.bounds, to: host)
        let bitmap = imagePreview.bitmapImageRepForCachingDisplay(in: imagePreview.bounds)!
        imagePreview.cacheDisplay(in: imagePreview.bounds, to: bitmap)
        let pixel = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)!
        func rgba(_ color: NSColor?) -> String {
            guard let value = color?.usingColorSpace(.deviceRGB) else { return "unresolved" }
            return "\(value.redComponent),\(value.greenComponent),\(value.blueComponent),\(value.alphaComponent)"
        }
        let suppliedCGImage = SILThumbnailStore.sharedCache.result?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let suppliedBitmap = suppliedCGImage.map { NSBitmapImageRep(cgImage: $0) }
        let suppliedPixel = suppliedBitmap.flatMap { $0.colorAt(x: $0.pixelsWide / 2, y: $0.pixelsHigh / 2) }
        let actualRGB = pixel.usingColorSpace(.deviceRGB)
        let suppliedRGB = suppliedPixel?.usingColorSpace(.deviceRGB)
        let suppliedIsOpaqueGreen: Bool
        let previewMatchesSupplied: Bool
        if let suppliedRGB {
            suppliedIsOpaqueGreen = suppliedRGB.greenComponent > suppliedRGB.redComponent
                && suppliedRGB.greenComponent > suppliedRGB.blueComponent && suppliedRGB.alphaComponent == 1
        } else {
            suppliedIsOpaqueGreen = false
        }
        if let actualRGB, let suppliedRGB {
            let quantizationStep = 1.0 / 255.0
            previewMatchesSupplied = abs(actualRGB.redComponent - suppliedRGB.redComponent) <= quantizationStep
                && abs(actualRGB.greenComponent - suppliedRGB.greenComponent) <= quantizationStep
                && abs(actualRGB.blueComponent - suppliedRGB.blueComponent) <= quantizationStep
                && abs(actualRGB.alphaComponent - suppliedRGB.alphaComponent) <= quantizationStep
        } else {
            previewMatchesSupplied = false
        }
        let placeholderStates = views(imagePreview).compactMap { $0 as? NSImageView }.map {
            "hidden=\($0.isHidden),ancestorHidden=\($0.isHiddenOrHasHiddenAncestor),frame=\($0.frame)"
        }
        let imageDiagnostics: [String] = [
            "real-image-success-diagnostic",
            "previewFrame=\(imagePreview.frame)", "bounds=\(imagePreview.bounds)",
            "bitmap=\(bitmap.pixelsWide)x\(bitmap.pixelsHigh)", "pixelRGBA=\(rgba(pixel))",
            "suppliedRGBA=\(rgba(suppliedPixel))", "placeholders=\(placeholderStates)"
        ]
        FileHandle.standardError.write(Data((imageDiagnostics.joined(separator: " ") + "\n").utf8))
        checks["controlled-image-source-has-opaque-green-pixels"] = suppliedIsOpaqueGreen
        checks["real-image-success-draws-the-new-image-and-hides-placeholder"] = suppliedIsOpaqueGreen && previewMatchesSupplied
            && views(imagePreview).compactMap { $0 as? NSImageView }.allSatisfy(\.isHidden)
        checks["real-shell-short-image-content-starts-eight-points-below-unfaded-top"] = topAligned(imageView, preview: imagePreview, short: true)
        window.setContentSize(NSSize(width: 800, height: 460)); host.layoutSubtreeIfNeeded(); pump()
        checks["real-shell-long-image-content-keeps-top-preview-and-footer-outside-mask"] = topAligned(imageView, preview: imagePreview, short: false)
            && imagePreview === views(imageView).first { $0 is SILInspectorPreviewSurfaceView }
        window.setContentSize(NSSize(width: 800, height: 900)); host.layoutSubtreeIfNeeded()
        mount(pixabayView)
        let pixabayPreview = views(pixabayView).first { $0 is PixabayDownloadsPreviewSurfaceView }!
        let pixabayFrame = pixabayPreview.convert(pixabayPreview.bounds, to: host)
        checks["real-pixabay-presents-prepared-file-metadata-on-its-first-layout"] = views(pixabayView).contains { ($0 as? NSTextField)?.stringValue == "local.png" }
        precondition(waitUntil { views(pixabayPreview).compactMap { $0 as? NSImageView }.allSatisfy(\.isHidden) })
        pump(); host.layoutSubtreeIfNeeded()
        checks["real-pixabay-has-no-second-loading-layout-or-preview-replacement"] = pixabayPreview === views(pixabayView).first { $0 is PixabayDownloadsPreviewSurfaceView }
            && pixabayFrame == pixabayPreview.convert(pixabayPreview.bounds, to: host)
        checks["real-shell-short-pixabay-content-starts-at-the-same-unfaded-top"] = topAligned(pixabayView, preview: pixabayPreview, short: true)
        window.setContentSize(NSSize(width: 800, height: 420)); host.layoutSubtreeIfNeeded(); pump()
        checks["real-shell-long-pixabay-content-does-not-recenter-on-resize"] = topAligned(pixabayView, preview: pixabayPreview, short: false)
        window.setContentSize(NSSize(width: 800, height: 900)); host.layoutSubtreeIfNeeded()
        checks["image-membership-shows-new-store-names-and-no-old-tag"] = views(imageView).contains { ($0 as? NSTextField)?.stringValue == "New Mixed List" }
            && !views(imageView).contains { ($0 as? NSTextField)?.stringValue == "Old SIL Tag" }
        let imagePrimary = button(imageView, "setAsDesktopWallpaper")!, imageMembers = button(imageView, "presentTagPicker")!
        checks["image-list-action-is-enabled-with-zero-legacy-tags"] = imageMembers.isEnabled && imageMembers.accessibilityLabel() == "添加到列表"
        _ = imageMembers.accessibilityPerformPress(); _ = imagePrimary.accessibilityPerformPress()
        checks["image-native-buttons-dispatch-injected-fixed-actions-only"] = member == 1 && primary == 1 && images.writes == 0 && SILService.shared.writes == 0
        checks["image-required-command-does-not-also-publish-legacy-apply-notification"] = legacyApplyNotifications == 0
        let imagePlayback = try playingImagePrimary(.init(provider: .staticImageLibrary, sourceID: image.id))
        let imageStop = imagePlayback.commands.makePrimaryAction(for: imagePlayback.content)!
        let playingActions = WallpaperInspectorActions(state: actions(playing: true).state,
            onPrimary: imageStop, onToggleFavorite: {}, onChoosePlaylist: { _ in })
        imageView.updateLibraryActions(playingActions)
        _ = imagePrimary.accessibilityPerformPress()
        let stopIcon = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 14, weight: .semibold))!
        checks["healthy-playing-image-shows-and-executes-stop-without-applying-again"] = imagePrimary.isEnabled
            && imagePrimary.accessibilityLabel() == "停止播放" && imagePrimary.toolTip == "停止播放"
            && views(imagePrimary).compactMap { ($0 as? NSImageView)?.image?.tiffRepresentation }.contains(stopIcon.tiffRepresentation!)
            && imagePlayback.commands.manager.stops == 1 && imagePlayback.commands.manager.playbackSwitch.committed == nil
            && imagePlayback.commands.manager.libraryPlaybackSequence.committed == nil
            && imagePlayback.commands.workspace.applications.isEmpty && primary == 1 && legacyApplyNotifications == 0
        let replacementActions = WallpaperInspectorActions(state: actions().state,
            onPrimary: imagePlayback.commands.makePrimaryAction(for: imagePlayback.content)!, onToggleFavorite: {}, onChoosePlaylist: { _ in })
        imageView.updateLibraryActions(replacementActions)
        _ = imagePrimary.accessibilityPerformPress()
        checks["reused-image-detail-restores-apply-presentation-and-replaces-stop-closure"] = button(imageView, "setAsDesktopWallpaper") === imagePrimary
            && imagePrimary.accessibilityLabel() == "设为壁纸" && imagePrimary.toolTip == "设为壁纸"
            && imagePlayback.commands.workspace.applications.map(\.0) == [imagePlayback.content.reference]
            && imagePlayback.commands.manager.stops == 1 && primary == 1
        imageStop()
        checks["retired-image-detail-stop-cannot-stop-or-apply-after-view-reuse"] = imagePlayback.commands.manager.stops == 1
            && imagePlayback.commands.workspace.applications.count == 1
        imageView.updateLibraryActions(actions(canOrganize: false))
        checks["image-readonly-native-list-button-refuses-press"] = !imageMembers.isEnabled && !imageMembers.accessibilityPerformPress() && member == 1
        imageView.updateLibraryActions(actions(canOrganize: false, playing: true, canPlay: false))
        checks["unavailable-image-keeps-primary-disabled-without-dispatching-stop-or-apply"] = !imagePrimary.isEnabled
            && !imagePrimary.accessibilityPerformPress() && primary == 1 && imagePlayback.commands.manager.stops == 1
            && imagePlayback.commands.workspace.applications.count == 1
            && imagePrimary.accessibilityLabel() == "停止播放"
        _ = imageView.perform(NSSelectorFromString("setAsDesktopWallpaper"))
        _ = imageView.perform(NSSelectorFromString("presentTagPicker"))
        checks["direct-selector-cannot-bypass-readonly-state-or-revive-legacy-owner"] = primary == 1 && member == 1
            && images.writes == 0 && SILService.shared.writes == 0 && legacyApplyNotifications == 0
        let pixabayButtons = views(pixabayView).compactMap { $0 as? InspectorFooterButton }
        checks["pixabay-retains-original-two-button-footer"] = pixabayButtons.count == 2
        let pixabayPrimary = button(pixabayView, "setAsWallpaper")!
        checks["pixabay-details-read-injected-source-not-shared-empty-source"] = pixabayPrimary.isEnabled
        _ = pixabayPrimary.accessibilityPerformPress()
        checks["pixabay-primary-uses-new-fixed-action-without-source-selection-write"] = primary == 2 && pixabay.writes == 0 && PixabayService.shared.writes == 0
        pixabayView.updateLibraryActions(actions(canPlay: false))
        checks["pixabay-unavailable-primary-refuses-native-press"] = button(pixabayView, "setAsWallpaper")?.isEnabled == false
        checks["both-original-inspector-scrollbars-remain-hidden"] = [imageView, pixabayView].allSatisfy { root in
            views(root).compactMap { $0 as? NSScrollView }.allSatisfy { !$0.hasVerticalScroller && !$0.hasHorizontalScroller }
        }
        checks["pixabay-organization-controls-are-not-added-to-original-footer"] = favorites == 0 && member == 1

        mount(imageView); pump(); host.layoutSubtreeIfNeeded()
        let cache = SILThumbnailStore.sharedCache
        checks["image-inspector-keeps-negative-cache-read-and-write-disabled"] = cache.requests.allSatisfy { !$0.cachesFailure }
        let requestsBeforeMetadata = cache.requests.count
        images.wallpapers[0].pixelWidth = 1024
        images.wallpapers[0].pixelHeight = 768
        images.wallpapers[0].lastUsed = Date(timeIntervalSince1970: 1_700_000_000)
        imageView.updateLibraryActions(actions(canOrganize: false))
        host.layoutSubtreeIfNeeded()
        let updatedTitle = views(imageView).first { ($0 as? NSTextField)?.stringValue == "Image" }
        checks["image-same-reference-late-dimensions-and-last-used-refresh-in-place"] =
            views(imageView).contains { ($0 as? NSTextField)?.stringValue == "1024 × 768" }
            && views(imageView).contains { ($0 as? NSTextField)?.stringValue == "最近使用" }
            && imagePreview === views(imageView).first { $0 is SILInspectorPreviewSurfaceView }
            && cache.requests.count == requestsBeforeMetadata
        imageView.updateLibraryActions(actions(canOrganize: false))
        checks["image-metadata-and-action-echoes-do-not-reload-preview-or-rebuild-unchanged-content"] =
            updatedTitle === views(imageView).first { ($0 as? NSTextField)?.stringValue == "Image" }
            && cache.requests.count == requestsBeforeMetadata

        let previousLease = cache.requests.last?.cancellation
        mount(pixabayView)
        imageView.updateLibraryActions(actions(canOrganize: false))
        checks["image-unmount-cancels-its-consumer-without-reacquiring-offscreen"] =
            previousLease?.cancelled == true && cache.requests.count == requestsBeforeMetadata
        mount(imageView)
        checks["image-remount-reacquires-one-lease-and-keeps-the-current-preview"] =
            cache.requests.count == requestsBeforeMetadata + 1 && cache.requests.last?.cancellation?.cancelled == false
            && imagePreview === views(imageView).first { $0 is SILInspectorPreviewSurfaceView }
            && views(imagePreview).compactMap { $0 as? NSImageView }.allSatisfy(\.isHidden)

        let replacement = file.deletingLastPathComponent().appendingPathComponent("relocated.png")
        try Data("replacement".utf8).write(to: replacement)
        let relocatedLease = cache.requests.last?.cancellation
        images.wallpapers[0].path = replacement.path
        imageView.updateLibraryActions(actions(canOrganize: false))
        checks["image-source-change-reloads-only-the-new-path"] = relocatedLease?.cancelled == true
            && cache.requests.count == requestsBeforeMetadata + 2 && cache.requests.last?.key == replacement.path
            && imagePreview === views(imageView).first { $0 is SILInspectorPreviewSurfaceView }
        pump(); host.layoutSubtreeIfNeeded()
        cache.holdsCompletions = true
        images.wallpapers[0].path = file.path
        imageView.updateLibraryActions(actions(canOrganize: false))
        let oldA = cache.requests.count - 1
        images.wallpapers[0].path = replacement.path
        imageView.updateLibraryActions(actions(canOrganize: false))
        let middleB = cache.requests.count - 1
        images.wallpapers[0].path = file.path
        imageView.updateLibraryActions(actions(canOrganize: false))
        let currentA = cache.requests.count - 1
        func solid(_ color: NSColor) -> NSImage {
            NSImage(size: NSSize(width: 16, height: 8), flipped: false) { rect in
                color.setFill(); rect.fill(); return true
            }
        }
        func previewMatches(_ preview: NSView, image: NSImage) -> Bool {
            preview.layoutSubtreeIfNeeded()
            guard let pixels = preview.bitmapImageRepForCachingDisplay(in: preview.bounds) else { return false }
            preview.cacheDisplay(in: preview.bounds, to: pixels)
            guard let color = pixels.colorAt(x: pixels.pixelsWide / 2, y: pixels.pixelsHigh / 2)?.usingColorSpace(.deviceRGB) else { return false }
            guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
            let supplied = NSBitmapImageRep(cgImage: source)
            guard let expected = supplied.colorAt(x: supplied.pixelsWide / 2, y: supplied.pixelsHigh / 2)?.usingColorSpace(.deviceRGB) else { return false }
            // AppKit color-manages calibrated source components. Compare all
            // displayed channels to the actual source in the same color space,
            // allowing only native 8-bit quantization.
            return zip([color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent],
                       [expected.redComponent, expected.greenComponent, expected.blueComponent, expected.alphaComponent])
                .allSatisfy { components in abs(components.0 - components.1) <= 1.0 / 255.0 }
        }
        let redImage = solid(NSColor(calibratedRed: 0.9, green: 0.05, blue: 0.1, alpha: 1))
        func previewIsRed() -> Bool {
            host.layoutSubtreeIfNeeded()
            return previewMatches(imagePreview, image: redImage)
        }
        cache.deliver(currentA, image: redImage)
        pump()
        checks["image-a-b-a-current-request-delivers-real-red-preview"] = previewIsRed()
            && cache.requests[oldA].key == file.path && cache.requests[currentA].key == file.path
            && cache.requests[middleB].key == replacement.path
            && cache.requests[oldA].cancellation?.cancelled == true
            && cache.requests[middleB].cancellation?.cancelled == true
            && cache.requests[currentA].cancellation?.cancelled == false
        let callbacksBeforeOldDeliveries = cache.completionThreads.count
        cache.deliver(oldA, image: solid(.blue))
        cache.deliver(middleB, image: nil)
        pump()
        checks["image-a-b-a-old-same-path-and-other-source-late-deliveries-cannot-overwrite-current-pixels"] = previewIsRed()
            && imagePreview === views(imageView).first { $0 is SILInspectorPreviewSurfaceView }
            && views(imagePreview).compactMap { $0 as? NSImageView }.allSatisfy(\.isHidden)
            && cache.completionThreads.count == callbacksBeforeOldDeliveries

        let frames = DownloadedInspectorFrameProbe.shared
        let demands = DownloadedInspectorCacheProbe.shared
        let downloadedCache = PixabayDownloadedThumbnailStore.sharedCache
        let expectedImages = [0: solid(.red), 1: SILThumbnailStore.sharedCache.result!, 2: solid(.blue)]
        func drawnColor(_ preview: NSView, channel: Int) -> Bool {
            guard let image = expectedImages[channel] else { return false }
            return previewMatches(preview, image: image)
        }
        mount(pixabayView)
        precondition(waitUntil { drawnColor(pixabayPreview, channel: 1) })
        let pixabayKey = PixabayDownloadedThumbnailStore.cacheKey(for: file)
        checks["pixabay-cold-visible-demand-fills-only-the-existing-preview"] = pixabayWasCold
            && pixabayInitialPreview === pixabayPreview && pixabayPreview.bounds.height == 156
            && demands.requests.contains { $0.key == pixabayKey && $0.priority == .visible }
            && frames.count(file.path) == 1
        let titleBeforeEcho = views(pixabayView).first { ($0 as? NSTextField)?.stringValue == "local.png" }
        let footerBeforeEcho = button(pixabayView, "setAsWallpaper")
        let demandCountBeforeEcho = demands.sourceCallCount
        pixabayView.updateLibraryActions(actions(names: ["Renamed Mixed List"]))
        checks["pixabay-action-and-relationship-echoes-keep-document-and-image-demand"] =
            titleBeforeEcho === views(pixabayView).first { ($0 as? NSTextField)?.stringValue == "local.png" }
            && footerBeforeEcho === button(pixabayView, "setAsWallpaper")
            && demands.sourceCallCount == demandCountBeforeEcho && drawnColor(pixabayPreview, channel: 1)
        pixabay.downloadedContent.entries[0].resolutionString = "80×40"
        pixabay.downloadedContent.entries[0].duration = 5
        pixabay.downloadedContent.entries[0].creationDate = Date(timeIntervalSince1970: 1_700_000_000)
        pixabayView.updateLibraryActions(actions(names: ["Renamed Mixed List"]))
        checks["pixabay-same-id-metadata-refreshes-without-reloading-preview"] =
            views(pixabayView).contains { ($0 as? NSTextField)?.stringValue == "80×40" }
            && views(pixabayView).contains { ($0 as? NSTextField)?.stringValue.contains("5s") == true }
            && pixabayPreview === views(pixabayView).first { $0 is PixabayDownloadsPreviewSurfaceView }
            && demands.sourceCallCount == demandCountBeforeEcho && drawnColor(pixabayPreview, channel: 1)

        func attach(_ view: NSView) {
            host.addSubview(view)
            view.frame = NSRect(x: 0, y: 0, width: 368, height: 640)
            view.layoutSubtreeIfNeeded()
        }
        let closedFile = file.deletingLastPathComponent().appendingPathComponent("closed.mp4")
        try Data(repeating: 1, count: 19).write(to: closedFile)
        let closedKey = PixabayDownloadedThumbnailStore.cacheKey(for: closedFile)
        pixabay.downloadedContent.entries.append(.init(id: 8, localURL: closedFile))
        frames.hold(closedFile.path)
        let closedView = PixabayDownloadsInspectorView(itemID: 8, service: pixabay, libraryActions: actions())
        let closedPreview = views(closedView).first { $0 is PixabayDownloadsPreviewSurfaceView }!
        attach(closedView)
        precondition(waitUntil { frames.pendingCount(closedFile.path) == 1 })
        let closedLease = demands.requests.last { $0.key == closedKey }?.cancellation
        closedView.removeFromSuperview()
        frames.release(closedFile.path, image: solid(.blue))
        var oldGenerationDrained = false
        downloadedCache.loadImageAsync(forKey: "after-close-\(UUID().uuidString)", loader: { nil }) { _ in oldGenerationDrained = true }
        precondition(waitUntil { oldGenerationDrained })
        let rejectedClosedResult = closedLease?.cancelled == true && downloadedCache.cachedImage(forKey: closedKey) == nil
            && views(closedPreview).compactMap { $0 as? NSImageView }.contains { !$0.isHidden }
        attach(closedView)
        precondition(waitUntil { drawnColor(closedPreview, channel: 1) })
        checks["pixabay-closed-consumer-rejects-late-frame-and-remounts-once"] = rejectedClosedResult
            && frames.count(closedFile.path) == 2
            && demands.requests.filter { $0.key == closedKey }.count == 2
            && closedPreview === views(closedView).first { $0 is PixabayDownloadsPreviewSurfaceView }
        closedView.removeFromSuperview()

        let sharedFile = file.deletingLastPathComponent().appendingPathComponent("shared.mp4")
        try Data(repeating: 2, count: 29).write(to: sharedFile)
        let sharedKey = PixabayDownloadedThumbnailStore.cacheKey(for: sharedFile)
        pixabay.downloadedContent.entries.append(.init(id: 9, localURL: sharedFile))
        frames.hold(sharedFile.path)
        let withdrawn = PixabayDownloadsInspectorView(itemID: 9, service: pixabay, libraryActions: actions())
        let remaining = PixabayDownloadsInspectorView(itemID: 9, service: pixabay, libraryActions: actions())
        attach(withdrawn); attach(remaining)
        precondition(waitUntil { demands.requests.filter { $0.key == sharedKey }.count == 2 && frames.pendingCount(sharedFile.path) == 1 })
        withdrawn.removeFromSuperview()
        frames.release(sharedFile.path, image: solid(.blue))
        let remainingPreview = views(remaining).first { $0 is PixabayDownloadsPreviewSurfaceView }!
        let withdrawnPreview = views(withdrawn).first { $0 is PixabayDownloadsPreviewSurfaceView }!
        precondition(waitUntil { drawnColor(remainingPreview, channel: 2) })
        let sharedLeases = demands.requests.filter { $0.key == sharedKey }
        let sharedRemained = frames.count(sharedFile.path) == 1
            && sharedLeases.filter { $0.cancellation?.cancelled == true }.count == 1
            && views(withdrawnPreview).compactMap { $0 as? NSImageView }.contains { !$0.isHidden }
        attach(withdrawn)
        precondition(waitUntil { drawnColor(withdrawnPreview, channel: 2) })
        checks["pixabay-shared-producer-survives-one-inspector-leaving"] = sharedRemained
            && frames.count(sharedFile.path) == 1 && demands.requests.filter { $0.key == sharedKey }.count == 3
        withdrawn.removeFromSuperview(); remaining.removeFromSuperview()

        let newSource = file.deletingLastPathComponent().appendingPathComponent("new-source.mp4")
        try Data(repeating: 3, count: 37).write(to: newSource)
        let sourceKey = PixabayDownloadedThumbnailStore.cacheKey(for: newSource)
        let previousSourceLease = demands.requests.last { $0.key == pixabayKey }?.cancellation
        frames.hold(newSource.path)
        pixabay.downloadedContent.entries[0] = .init(id: 7, localURL: newSource, fileSize: 37, thumbnailSourceKey: sourceKey)
        pixabayView.updateLibraryActions(actions())
        precondition(waitUntil { frames.pendingCount(newSource.path) == 1 })
        checks["pixabay-source-replacement-cancels-old-consumer-and-retains-current-image-while-loading"] =
            previousSourceLease?.cancelled == true && drawnColor(pixabayPreview, channel: 1)
            && pixabayPreview === views(pixabayView).first { $0 is PixabayDownloadsPreviewSurfaceView }
        frames.release(newSource.path, image: solid(.blue))
        precondition(waitUntil { drawnColor(pixabayPreview, channel: 2) })
        let currentTitle = views(pixabayView).first { ($0 as? NSTextField)?.stringValue == "new-source.mp4" }
        let currentDemandCount = demands.sourceCallCount
        pixabayView.updateLibraryActions(actions())
        checks["pixabay-current-source-fills-in-place-and-ignores-unchanged-publication"] =
            drawnColor(pixabayPreview, channel: 2) && pixabayPreview.bounds.height == 156
            && currentTitle === views(pixabayView).first { ($0 as? NSTextField)?.stringValue == "new-source.mp4" }
            && demands.sourceCallCount == currentDemandCount && frames.count(newSource.path) == 1
        let priorRevisionLease = demands.requests.last { $0.key == sourceKey }?.cancellation
        try Data(repeating: 4, count: 53).write(to: newSource, options: .atomic)
        let revisedKey = PixabayDownloadedThumbnailStore.cacheKey(for: newSource)
        frames.hold(newSource.path)
        pixabay.downloadedContent.entries[0] = .init(id: 7, localURL: newSource, fileSize: 53, thumbnailSourceKey: revisedKey)
        pixabayView.updateLibraryActions(actions())
        precondition(waitUntil { frames.pendingCount(newSource.path) == 1 })
        let keepsOldDuringRevision = drawnColor(pixabayPreview, channel: 2) && priorRevisionLease?.cancelled == true
        frames.release(newSource.path, image: expectedImages[0])
        precondition(waitUntil { drawnColor(pixabayPreview, channel: 0) })
        checks["pixabay-same-path-new-fingerprint-fills-current-image-without-changing-preview-object"] = keepsOldDuringRevision
            && sourceKey != revisedKey && frames.count(newSource.path) == 2
            && pixabayPreview === views(pixabayView).first { $0 is PixabayDownloadsPreviewSurfaceView }

        // The actual card must create the shared producer first. Keeping only
        // a fake visible cache consumer would miss its former direct loader.
        func card(_ entry: PixabayDownloadedEntry) -> AppKitPixabayDownloadsItem {
            let value = AppKitPixabayDownloadsItem()
            value.view.frame = NSRect(x: 0, y: 0, width: 230, height: 230)
            host.addSubview(value.view)
            value.configure(entry: entry, isSelected: false, isMultiSelectMode: false, isPlaying: false)
            value.view.layoutSubtreeIfNeeded()
            return value
        }
        let activeSource = file.deletingLastPathComponent().appendingPathComponent("active-first.mp4")
        try Data(repeating: 21, count: 211).write(to: activeSource)
        let activeOldKey = PixabayDownloadedThumbnailStore.cacheKey(for: activeSource)
        let activeEntry = PixabayDownloadedEntry(id: 43, localURL: activeSource, fileSize: 211, thumbnailSourceKey: activeOldKey)
        pixabay.downloadedContent.entries.append(activeEntry)
        frames.hold(activeSource.path)
        let activeCard = card(activeEntry)
        let activeCardLease = activeCard.thumbnailCancellation!
        precondition(waitUntil { frames.pendingCount(activeSource.path) == 1 })
        let activeInspector = PixabayDownloadsInspectorView(itemID: 43, service: pixabay, libraryActions: actions())
        let activePreview = views(activeInspector).first { $0 is PixabayDownloadsPreviewSurfaceView }!
        attach(activeInspector)
        let activeNear = ThumbnailCacheRequestCancellation()
        var activeNearTerminals = 0
        var activeNearImage: NSImage?
        PixabayDownloadedThumbnailStore.loadThumbnail(activeEntry, priority: .prefetch, cancellation: activeNear) { _, image in
            activeNearTerminals += 1; activeNearImage = image
        }
        precondition(waitUntil { demands.requests.filter { $0.key == activeOldKey }.count == 3 })
        let activeInspectorLease = demands.requests.filter { $0.key == activeOldKey && $0.priority == .visible }.last!.cancellation as! ThumbnailCacheRequestCancellation
        try Data(repeating: 22, count: 229).write(to: activeSource, options: .atomic)
        let activeCurrentKey = PixabayDownloadedThumbnailStore.cacheKey(for: activeSource)
        frames.release(activeSource.path, image: expectedImages[0])
        precondition(waitUntil { activeNearTerminals == 1 && activeCard.thumbnailCancellation == nil
            && demands.completionCounts(activeInspectorLease).total == 1 })
        // No scroll, beginDisplaying or other retry is allowed before this
        // assertion: the original nil callback must retire the loading UI.
        checks["pixabay-active-first-card-and-inspector-finish-once-with-nil-after-source-change"] =
            !activeCardLease.cancelled && !activeInspectorLease.cancelled && !activeNear.cancelled
            && demands.completionCounts(activeCardLease).total == 1 && demands.completionCounts(activeCardLease).images == 0
            && demands.completionCounts(activeInspectorLease).images == 0 && activeNearImage == nil
            && activeCard.thumbnailView.image == nil && !activeCard.placeholderLabel.isHidden
            && activeCard.placeholderLabel.stringValue == "无法生成预览" && activeCard.thumbnailLoadingWork == nil
            && views(activePreview).compactMap { $0 as? NSImageView }.contains { !$0.isHidden }
            && !downloadedCache.hasCachedResult(forKey: activeOldKey) && frames.count(activeSource.path) == 1
        activeCard.beginDisplayingThumbnail()
        precondition(waitUntil { activeCard.thumbnailView.image === expectedImages[1] })
        checks["pixabay-next-actual-card-demand-reads-current-source-after-uncached-nil"] =
            activeCurrentKey != activeOldKey && downloadedCache.hasCachedResult(forKey: activeCurrentKey)
            && frames.count(activeSource.path) == 2 && activeNearTerminals == 1
            && demands.completionCounts(activeCardLease).total == 1
            && demands.requests.filter { $0.key == activeCurrentKey }.count == 1
        activeNear.cancel(); activeCard.endDisplayingThumbnail()
        activeCard.view.removeFromSuperview(); activeInspector.removeFromSuperview()
        let queuedSource = file.deletingLastPathComponent().appendingPathComponent("visible-first.mp4")
        let preservedSource = queuedSource.appendingPathExtension("original")
        try Data(repeating: 11, count: 101).write(to: queuedSource)
        let queuedKey = PixabayDownloadedThumbnailStore.cacheKey(for: queuedSource)
        let queuedEntry = PixabayDownloadedEntry(id: 41, localURL: queuedSource, fileSize: 101, thumbnailSourceKey: queuedKey)
        pixabay.downloadedContent.entries.append(queuedEntry)
        let blockerPath = queuedSource.path + "-generation-blocker"
        frames.hold(blockerPath)
        var blockerCompleted = false
        downloadedCache.loadImageAsync(forKey: blockerPath, loader: { await frames.image(blockerPath) }) { _ in blockerCompleted = true }
        precondition(waitUntil { frames.pendingCount(blockerPath) == 1 })
        let readsBeforeCard = demands.reads(queuedSource.path), mainReadsBeforeCard = demands.mainReads
        let visibleFirst = card(queuedEntry)
        let visibleFirstLease = visibleFirst.thumbnailCancellation
        precondition(waitUntil { demands.requests.filter { $0.key == queuedKey }.count == 1 })
        let oneBackgroundAdmission = demands.reads(queuedSource.path) == readsBeforeCard + 1 && demands.mainReads == mainReadsBeforeCard
        let sharedInspector = PixabayDownloadsInspectorView(itemID: 41, service: pixabay, libraryActions: actions())
        let sharedPreview = views(sharedInspector).first { $0 is PixabayDownloadsPreviewSurfaceView }!
        attach(sharedInspector)
        let queuedNear = ThumbnailCacheRequestCancellation()
        var queuedNearDelivered = false
        var queuedNearImage: NSImage?
        PixabayDownloadedThumbnailStore.loadThumbnail(queuedEntry, priority: .prefetch, cancellation: queuedNear) { _, image in
            queuedNearDelivered = true; queuedNearImage = image
        }
        precondition(waitUntil { demands.requests.filter { $0.key == queuedKey }.count == 3 })
        let inspectorLease = demands.requests.filter { $0.key == queuedKey && $0.priority == .visible }.last?.cancellation
        visibleFirst.endDisplayingThumbnail()
        try FileManager.default.moveItem(at: queuedSource, to: preservedSource)
        try Data(repeating: 12, count: 119).write(to: queuedSource)
        frames.release(blockerPath, image: nil)
        precondition(waitUntil { blockerCompleted && queuedNearDelivered })
        checks["pixabay-real-visible-first-queued-replacement-rejects-before-generation"] =
            visibleFirstLease?.cancelled == true && inspectorLease?.cancelled == false && !queuedNear.cancelled
            && queuedNearImage == nil && frames.count(queuedSource.path) == 0
            && !downloadedCache.hasCachedResult(forKey: queuedKey) && visibleFirst.thumbnailView.image == nil
            && views(sharedPreview).compactMap { $0 as? NSImageView }.contains { !$0.isHidden }
        queuedNear.cancel()
        sharedInspector.removeFromSuperview()
        // Restore the original inode so path/size/mtime is exactly the old A
        // identity. A false negative cache would prevent this real frame call.
        try FileManager.default.removeItem(at: queuedSource)
        try FileManager.default.moveItem(at: preservedSource, to: queuedSource)
        precondition(PixabayDownloadedThumbnailStore.cacheKey(for: queuedSource) == queuedKey)
        frames.hold(queuedSource.path)
        let restoredCard = card(queuedEntry)
        precondition(waitUntil { frames.pendingCount(queuedSource.path) == 1 })
        attach(sharedInspector)
        let restoredNear = ThumbnailCacheRequestCancellation()
        var restoredNearDelivered = false
        PixabayDownloadedThumbnailStore.loadThumbnail(queuedEntry, priority: .prefetch, cancellation: restoredNear) { _, _ in restoredNearDelivered = true }
        precondition(waitUntil { demands.requests.filter { $0.key == queuedKey }.count == 6 })
        let restoredCardLease = restoredCard.thumbnailCancellation
        restoredCard.endDisplayingThumbnail(); restoredNear.cancel()
        frames.release(queuedSource.path, image: expectedImages[2])
        precondition(waitUntil { drawnColor(sharedPreview, channel: 2) })
        checks["pixabay-real-card-inspector-and-near-share-one-producer-and-survive-card-exit"] =
            frames.count(queuedSource.path) == 1 && restoredCardLease?.cancelled == true && !restoredNearDelivered
            && restoredCard.thumbnailView.image == nil && downloadedCache.cachedImage(forKey: queuedKey) != nil
            && sharedPreview === views(sharedInspector).first { $0 is PixabayDownloadsPreviewSurfaceView }
        visibleFirst.view.removeFromSuperview(); restoredCard.view.removeFromSuperview(); sharedInspector.removeFromSuperview()

        let warmSource = file.deletingLastPathComponent().appendingPathComponent("warm-old-hint.mp4")
        try Data(repeating: 13, count: 131).write(to: warmSource)
        let warmOldKey = PixabayDownloadedThumbnailStore.cacheKey(for: warmSource)
        let warmEntry = PixabayDownloadedEntry(id: 42, localURL: warmSource, fileSize: 131, thumbnailSourceKey: warmOldKey)
        pixabay.downloadedContent.entries.append(warmEntry)
        let warmup = ThumbnailCacheRequestCancellation()
        var warmupImage: NSImage?
        PixabayDownloadedThumbnailStore.loadThumbnail(warmEntry, priority: .prefetch, cancellation: warmup) { _, image in warmupImage = image }
        precondition(waitUntil { warmupImage != nil })
        try Data(repeating: 14, count: 149).write(to: warmSource, options: .atomic)
        let warmCurrentKey = PixabayDownloadedThumbnailStore.cacheKey(for: warmSource)
        precondition(warmCurrentKey != warmOldKey && downloadedCache.cachedImage(forKey: warmOldKey) != nil)
        frames.hold(warmSource.path)
        let currentCard = card(warmEntry)
        let currentInspector = PixabayDownloadsInspectorView(itemID: 42, service: pixabay, libraryActions: actions())
        let currentPreview = views(currentInspector).first { $0 is PixabayDownloadsPreviewSurfaceView }!
        attach(currentInspector)
        precondition(waitUntil { demands.requests.filter { $0.key == warmCurrentKey }.count == 2 && frames.pendingCount(warmSource.path) == 1 })
        let rejectsWarmHint = currentCard.thumbnailView.image == nil
            && views(currentPreview).compactMap { $0 as? NSImageView }.contains { !$0.isHidden }
        frames.release(warmSource.path, image: expectedImages[2])
        precondition(waitUntil { currentCard.thumbnailView.image === expectedImages[2] && drawnColor(currentPreview, channel: 2) })
        checks["pixabay-real-card-and-inspector-ignore-a-warm-old-scan-hint"] = rejectsWarmHint
            && frames.count(warmSource.path) == 2 && downloadedCache.cachedImage(forKey: warmCurrentKey) != nil
        let currentImage = currentCard.thumbnailView.image
        let callsBeforeEcho = demands.sourceCallCount, readsBeforeEcho = demands.reads(warmSource.path)
        currentCard.configure(entry: warmEntry, isSelected: true, isMultiSelectMode: false, isPlaying: true)
        currentCard.endDisplayingThumbnail(); currentCard.view.removeFromSuperview()
        host.addSubview(currentCard.view); currentCard.beginDisplayingThumbnail()
        let keptCurrentPixels = currentCard.thumbnailView.image === currentImage
            && demands.sourceCallCount == callsBeforeEcho && demands.reads(warmSource.path) == readsBeforeEcho
        let warmFrameCount = frames.count(warmSource.path), warmMainReads = demands.mainReads
        let warmReads = demands.reads(warmSource.path)
        let warmCurrentCard = card(warmEntry)
        precondition(waitUntil { warmCurrentCard.thumbnailView.image === currentImage })
        let warmCurrentInspector = PixabayDownloadsInspectorView(itemID: 42, service: pixabay, libraryActions: actions())
        attach(warmCurrentInspector)
        let warmCurrentPreview = views(warmCurrentInspector).first { $0 is PixabayDownloadsPreviewSurfaceView }!
        precondition(waitUntil { drawnColor(warmCurrentPreview, channel: 2) })
        checks["pixabay-current-warm-card-remount-and-action-echo-preserve-pixels-without-av"] = keptCurrentPixels
            && frames.count(warmSource.path) == warmFrameCount && demands.reads(warmSource.path) == warmReads + 2
        checks["pixabay-real-card-admission-resolves-one-live-key-off-main"] = oneBackgroundAdmission
            && demands.mainReads == warmMainReads
        currentCard.endDisplayingThumbnail(); warmCurrentCard.endDisplayingThumbnail()
        currentCard.view.removeFromSuperview(); warmCurrentCard.view.removeFromSuperview()
        currentInspector.removeFromSuperview(); warmCurrentInspector.removeFromSuperview()
        let remoteCache = OnlineImageThumbnailCache.shared; remoteCache.holds = true
        func remoteModel(_ suffix: String, duration: Int = 12) -> PixabayVideoItem {
            let file = PixabayVideoFile(url: "https://cdn.pixabay.com/remote.mp4", width: 1920, height: 1080, size: 4096,
                thumbnail: "https://cdn.pixabay.com/remote-\(suffix).jpg")
            return .init(id: 66, pageURL: "https://pixabay.com/videos/id-66/", tags: "Remote \(suffix)", duration: duration, user: "Owned author",
                videos: .init(large: file, medium: file, small: nil, tiny: nil))
        }
        let remoteItem = remoteModel("A"), remoteStart = remoteCache.requests.count
        let remoteView = PixabayDownloadsInspectorView(itemID: 66, service: pixabay, libraryActions: actions(), remoteItem: remoteItem)
        mount(remoteView)
        precondition(waitUntil { remoteCache.requests.count == remoteStart + 1 })
        let remotePreview = views(remoteView).first { $0 is PixabayDownloadsPreviewSurfaceView }!
        checks["pixabay-remote-details-use-the-accepted-model-and-one-visible-800px-demand"] = pixabay.items.isEmpty
            && remoteCache.requests[remoteStart].url == remoteItem.previewThumbnailURL && remoteCache.requests[remoteStart].maxPixelSize == 800
            && remoteCache.requests[remoteStart].priority == .visible && remotePreview.bounds.height == 156
            && views(remoteView).contains { ($0 as? NSTextField)?.stringValue == remoteItem.displayTitle }
        remoteCache.complete(remoteStart, expectedImages[1])
        precondition(waitUntil { drawnColor(remotePreview, channel: 1) })
        let remoteFooter = button(remoteView, "setAsWallpaper")!
        let beforeRemoteEcho = remoteCache.requests.count
        remoteView.updateLibraryActions(actions(names: ["Updated relation"]))
        checks["remote-detail-relationship-echo-keeps-preview-and-does-not-reload"] = remoteCache.requests.count == beforeRemoteEcho
            && remotePreview === views(remoteView).first { $0 is PixabayDownloadsPreviewSurfaceView } && drawnColor(remotePreview, channel: 1)
        precondition(remoteFooter.accessibilityPerformPress())
        precondition(waitUntil { footerTitle(remoteFooter) == "正在下载" })
        checks["remote-details-download-admits-one-real-action-and-shows-busy-immediately"] = pixabay.downloadRequests == [66]
            && !remoteFooter.isEnabled && remoteCache.requests.count == beforeRemoteEcho
        pixabay.downloadingIDs.remove(66)
        precondition(waitUntil { footerTitle(remoteFooter) == "下载视频" && remoteFooter.isEnabled })
        let updatedRemote = remoteModel("B", duration: 21)
        remoteView.updateLibraryActions(actions(), remoteItem: updatedRemote)
        precondition(waitUntil { remoteCache.requests.count == beforeRemoteEcho + 1 })
        let detachedRequest = beforeRemoteEcho
        mount(imageView)
        remoteCache.complete(detachedRequest, expectedImages[2]); RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        let closedRemoteRetainedItsSurface = remotePreview.window == nil && remoteCache.requests.count == detachedRequest + 1
            && views(remotePreview).compactMap { $0 as? NSImageView }.allSatisfy(\.isHidden)
            && remotePreview === views(remoteView).first { $0 is PixabayDownloadsPreviewSurfaceView }
        mount(remoteView)
        precondition(waitUntil { remoteCache.requests.count == detachedRequest + 2 })
        // The new request remains held: no source/cache can restore green or
        // hide an old blue overwrite before this real mounted paint check.
        checks["closed-remote-detail-rejects-a-late-image-without-clearing-current-valid-pixels"] = closedRemoteRetainedItsSurface
            && remotePreview.window === window && remotePreview === views(remoteView).first { $0 is PixabayDownloadsPreviewSurfaceView }
            && drawnColor(remotePreview, channel: 1) && !drawnColor(remotePreview, channel: 2)
            && views(remotePreview).compactMap { $0 as? NSImageView }.allSatisfy(\.isHidden)
        remoteCache.complete(detachedRequest + 1, expectedImages[2])
        precondition(waitUntil { drawnColor(remotePreview, channel: 2) })
        checks["remote-detail-remount-restores-one-demand-and-keeps-its-original-preview-surface"] =
            remotePreview === views(remoteView).first { $0 is PixabayDownloadsPreviewSurfaceView } && remotePreview.bounds.height == 156
            && views(remoteView).contains { ($0 as? NSTextField)?.stringValue == updatedRemote.displayTitle }
        pixabay.downloadingIDs.insert(66); precondition(waitUntil { footerTitle(remoteFooter) == "正在下载" })
        pixabay.downloadedContent.entries.append(.init(id: 66, localURL: file))
        pixabay.downloadingIDs.remove(66)
        precondition(waitUntil { footerTitle(button(remoteView, "revealInFinder")) == "查看文件" })
        checks["remote-download-completion-switches-the-existing-detail-to-local-metadata-and-actions"] = footerTitle(remoteFooter) == "设为壁纸"
            && views(remoteView).contains { ($0 as? NSTextField)?.stringValue == file.lastPathComponent }
            && remotePreview === views(remoteView).first { $0 is PixabayDownloadsPreviewSurfaceView }
        mount(imageView)
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}

extension WallpaperInspectorOrganizationHarness {
    @MainActor static func previewDelivery(_ root: URL) throws {
        let file = root.appendingPathComponent("preview-source.png"), otherFile = root.appendingPathComponent("other-source.png")
        try Data("owned metadata locator".utf8).write(to: file)
        try Data("owned neighbor locator".utf8).write(to: otherFile)
        let source = SILWallpaper(id: "preview-fixed-id", title: "Original", path: file.path, tags: [])
        let other = SILWallpaper(id: "neighbor-id", title: "Neighbor", path: otherFile.path, tags: [])
        let service = SILService(); service.wallpapers = [source]
        let cache = SILThumbnailStore.sharedCache
        cache.requestedKeys = []; cache.completionThreads = []
        cache.result = NSImage(size: .init(width: 16, height: 8), flipped: false) { rect in
            NSColor.green.setFill(); rect.fill(); return true
        }
        var primaryCalls = 0
        func actions(enabled: Bool, label: String) -> WallpaperInspectorActions {
            .init(state: .init(isPlaying: false, isFavorite: false, canPerformPrimary: enabled,
                canFavorite: true, canOrganize: true, playlistNames: [label]),
                onPrimary: { primaryCalls += 1 }, onToggleFavorite: {}, onChoosePlaylist: { _ in })
        }
        func preview(_ root: NSView) -> SILInspectorPreviewSurfaceView {
            views(root).compactMap { $0 as? SILInspectorPreviewSurfaceView }.first!
        }
        func ready(_ root: NSView) -> Bool {
            let placeholders = views(preview(root)).compactMap { $0 as? NSImageView }
            return !placeholders.isEmpty && placeholders.allSatisfy(\.isHidden)
        }
        let warm = SILInspectorView(wallpaper: source, service: service, libraryActions: actions(enabled: true, label: "Warm"))
        let warmAtReturn = ready(warm)
        pump()
        var checks = ["warmAfterPump": ready(warm)]
        cache.holdsNext = true
        let delayed = SILInspectorView(wallpaper: source, service: service, libraryActions: actions(enabled: true, label: "Old"))
        let originalPreview = preview(delayed)
        checks["delayedHasPlaceholderBeforeDelivery"] = !ready(delayed) && cache.pending.count == 1
        service.wallpapers = [other]
        delayed.updateLibraryActions(actions(enabled: false, label: "Changed while pending"))
        checks["actionUpdateUsesFixedSource"] = views(delayed).contains { ($0 as? NSTextField)?.stringValue == "Original" }
            && !views(delayed).contains { ($0 as? NSTextField)?.stringValue == "Neighbor" }
        cache.deliverNext(cache.result)
        let delayedAtReturn = ready(delayed)
        pump()
        let primary = button(delayed, "setAsDesktopWallpaper")!
        checks["delayedResultRetainsPreviewAndLatestAction"] = ready(delayed) && preview(delayed) === originalPreview
            && !primary.isEnabled && !primary.accessibilityPerformPress() && primaryCalls == 0
            && views(delayed).contains { ($0 as? NSTextField)?.stringValue == "Changed while pending" }
        cache.holdsNext = true
        weak var weakReleased: SILInspectorView?
        autoreleasepool {
            var released: SILInspectorView? = SILInspectorView(wallpaper: source, service: service,
                libraryActions: actions(enabled: true, label: "Released"))
            weakReleased = released
            released = nil
        }
        pump()
        checks["pendingCallbackDoesNotRetainView"] = weakReleased == nil && cache.pending.count == 1
        let releasedRequest = cache.requests.last!
        let callbacksBeforeReleasedDelivery = cache.completionThreads.count
        cache.deliverNext(cache.result)
        pump()
        let releasedCallbackSuppressed = releasedRequest.cancellation?.cancelled == true
            && callbacksBeforeReleasedDelivery == 2 && cache.completionThreads.count == callbacksBeforeReleasedDelivery
            && cache.pending.isEmpty
        checks["cancelledReleasedRequestDoesNotInvokeCallback"] = releasedCallbackSuppressed
        checks["releasedViewCompletionIsNoop"] = weakReleased == nil && cache.pending.isEmpty && primaryCalls == 0
        checks["callbacksUseCapturedSourceAndMainDelivery"] = cache.requestedKeys == [file.path, file.path, file.path]
            && cache.completionThreads == [true, true]
        let report: [String: Any] = ["functional": ["checks": checks, "requestedKeys": cache.requestedKeys,
            "completionThreads": cache.completionThreads, "primaryCalls": primaryCalls],
            "work": ["warmReadyAtInitReturn": warmAtReturn ? 1 : 0,
                "delayedReadyAtDeliveryReturn": delayedAtReturn ? 1 : 0,
                "deliveredCallbacks": cache.completionThreads.count,
                "suppressedCallbacks": releasedCallbackSuppressed ? 1 : 0]]
        print(String(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
