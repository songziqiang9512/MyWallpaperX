import AppKit
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
nonisolated private final class OLThumbnailVideoGeneration: @unchecked Sendable {
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
struct OLDownloadedEntry: Equatable {
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
    var metaLine: String { [duration.map(OnlineLibraryDownloadedAssetMetadata.formatDuration), resolutionString].compactMap { $0 }.joined(separator: "  ") }
}
struct OnlineLibraryDownloadedContentSnapshot { var entries: [OLDownloadedEntry] = [] }
final class OnlineLibraryService {
    static let shared = OnlineLibraryService()
    var downloadedContent = OnlineLibraryDownloadedContentSnapshot()
    var writes = 0
    func setLocalFileAsWallpaper(id: Int) { writes += 1 }
}
enum OnlineLibraryDownloadedAssetMetadata { static func formatDuration(_ seconds: Int) -> String { "\(seconds)s" } }
func makeAppAlert(title: String, message: String, buttons: [String], accessoryView: NSView?) -> NSAlert { NSAlert() }
func presentAppAlert(_ alert: NSAlert, in window: NSWindow?, completion: @escaping (NSApplication.ModalResponse) -> Void) {}
func appModalHostWindow() -> NSWindow? { nil }
extension Notification.Name { static let staticImageWallpaperReadyToApply = Notification.Name("staticImageWallpaperReadyToApply") }

@main struct WallpaperInspectorOrganizationHarness {
    @MainActor static func views(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(views) }
    @MainActor static func button(_ root: NSView, _ selector: String) -> InspectorFooterButton? {
        views(root).compactMap { $0 as? InspectorFooterButton }.first { $0.action == NSSelectorFromString(selector) }
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
        let images = SILService(), online = OnlineLibraryService()
        let image = SILWallpaper(id: "fixed-image", title: "Image", path: file.path, tags: ["Old SIL Tag"])
        images.wallpapers = [image]
        online.downloadedContent.entries = [.init(id: 7, localURL: file)]
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
        let onlineView = OnlineLibraryDownloadsInspectorView(itemID: 7, service: online, libraryActions: actions())
        let onlineInitialPreview = views(onlineView).first { $0 is OnlineLibraryDownloadsPreviewSurfaceView }!
        let onlineWasCold = views(onlineInitialPreview).compactMap { $0 as? NSImageView }.contains { !$0.isHidden }
        func mount(_ view: NSView) {
            let module: ModuleIdentifier = view is SILInspectorView ? .staticImageLibrary : .onlineLibrary
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
        mount(onlineView)
        let onlinePreview = views(onlineView).first { $0 is OnlineLibraryDownloadsPreviewSurfaceView }!
        let onlineFrame = onlinePreview.convert(onlinePreview.bounds, to: host)
        checks["real-pixabay-presents-prepared-file-metadata-on-its-first-layout"] = views(onlineView).contains { ($0 as? NSTextField)?.stringValue == "local.png" }
        precondition(waitUntil { views(onlinePreview).compactMap { $0 as? NSImageView }.allSatisfy(\.isHidden) })
        pump(); host.layoutSubtreeIfNeeded()
        checks["real-pixabay-has-no-second-loading-layout-or-preview-replacement"] = onlinePreview === views(onlineView).first { $0 is OnlineLibraryDownloadsPreviewSurfaceView }
            && onlineFrame == onlinePreview.convert(onlinePreview.bounds, to: host)
        checks["real-shell-short-pixabay-content-starts-at-the-same-unfaded-top"] = topAligned(onlineView, preview: onlinePreview, short: true)
        window.setContentSize(NSSize(width: 800, height: 420)); host.layoutSubtreeIfNeeded(); pump()
        checks["real-shell-long-pixabay-content-does-not-recenter-on-resize"] = topAligned(onlineView, preview: onlinePreview, short: false)
        window.setContentSize(NSSize(width: 800, height: 900)); host.layoutSubtreeIfNeeded()
        checks["image-membership-shows-new-store-names-and-no-old-tag"] = views(imageView).contains { ($0 as? NSTextField)?.stringValue == "New Mixed List" }
            && !views(imageView).contains { ($0 as? NSTextField)?.stringValue == "Old SIL Tag" }
        let imagePrimary = button(imageView, "setAsDesktopWallpaper")!, imageMembers = button(imageView, "presentTagPicker")!
        checks["image-list-action-is-enabled-with-zero-legacy-tags"] = imageMembers.isEnabled && imageMembers.accessibilityLabel() == "添加到列表"
        _ = imageMembers.accessibilityPerformPress(); _ = imagePrimary.accessibilityPerformPress()
        checks["image-native-buttons-dispatch-injected-fixed-actions-only"] = member == 1 && primary == 1 && images.writes == 0 && SILService.shared.writes == 0
        checks["image-required-command-does-not-also-publish-legacy-apply-notification"] = legacyApplyNotifications == 0
        imageView.updateLibraryActions(actions(canOrganize: false))
        checks["image-readonly-native-list-button-refuses-press"] = !imageMembers.isEnabled && !imageMembers.accessibilityPerformPress() && member == 1
        imageView.updateLibraryActions(actions(canOrganize: false, playing: true, canPlay: false))
        checks["image-applied-state-does-not-invent-stop-for-unavailable-source"] = !imagePrimary.isEnabled && !imagePrimary.accessibilityPerformPress() && primary == 1
            && views(imageView).contains { ($0 as? NSTextField)?.stringValue == "已应用" }
        _ = imageView.perform(NSSelectorFromString("setAsDesktopWallpaper"))
        _ = imageView.perform(NSSelectorFromString("presentTagPicker"))
        checks["direct-selector-cannot-bypass-readonly-state-or-revive-legacy-owner"] = primary == 1 && member == 1
            && images.writes == 0 && SILService.shared.writes == 0 && legacyApplyNotifications == 0
        let onlineButtons = views(onlineView).compactMap { $0 as? InspectorFooterButton }
        checks["pixabay-retains-original-two-button-footer"] = onlineButtons.count == 2
        let onlinePrimary = button(onlineView, "setAsWallpaper")!
        checks["pixabay-details-read-injected-source-not-shared-empty-source"] = onlinePrimary.isEnabled
        _ = onlinePrimary.accessibilityPerformPress()
        checks["pixabay-primary-uses-new-fixed-action-without-source-selection-write"] = primary == 2 && online.writes == 0 && OnlineLibraryService.shared.writes == 0
        onlineView.updateLibraryActions(actions(canPlay: false))
        checks["pixabay-unavailable-primary-refuses-native-press"] = button(onlineView, "setAsWallpaper")?.isEnabled == false
        checks["both-original-inspector-scrollbars-remain-hidden"] = [imageView, onlineView].allSatisfy { root in
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
        mount(onlineView)
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
        let downloadedCache = OLDownloadedThumbnailStore.sharedCache
        let expectedImages = [0: solid(.red), 1: SILThumbnailStore.sharedCache.result!, 2: solid(.blue)]
        func drawnColor(_ preview: NSView, channel: Int) -> Bool {
            guard let image = expectedImages[channel] else { return false }
            return previewMatches(preview, image: image)
        }
        mount(onlineView)
        precondition(waitUntil { drawnColor(onlinePreview, channel: 1) })
        let onlineKey = OLDownloadedThumbnailStore.cacheKey(for: file)
        checks["pixabay-cold-visible-demand-fills-only-the-existing-preview"] = onlineWasCold
            && onlineInitialPreview === onlinePreview && onlinePreview.bounds.height == 156
            && demands.requests.contains { $0.key == onlineKey && $0.priority == .visible }
            && frames.count(file.path) == 1
        let titleBeforeEcho = views(onlineView).first { ($0 as? NSTextField)?.stringValue == "local.png" }
        let footerBeforeEcho = button(onlineView, "setAsWallpaper")
        let demandCountBeforeEcho = demands.sourceCallCount
        onlineView.updateLibraryActions(actions(names: ["Renamed Mixed List"]))
        checks["pixabay-action-and-relationship-echoes-keep-document-and-image-demand"] =
            titleBeforeEcho === views(onlineView).first { ($0 as? NSTextField)?.stringValue == "local.png" }
            && footerBeforeEcho === button(onlineView, "setAsWallpaper")
            && demands.sourceCallCount == demandCountBeforeEcho && drawnColor(onlinePreview, channel: 1)
        online.downloadedContent.entries[0].resolutionString = "80×40"
        online.downloadedContent.entries[0].duration = 5
        online.downloadedContent.entries[0].creationDate = Date(timeIntervalSince1970: 1_700_000_000)
        onlineView.updateLibraryActions(actions(names: ["Renamed Mixed List"]))
        checks["pixabay-same-id-metadata-refreshes-without-reloading-preview"] =
            views(onlineView).contains { ($0 as? NSTextField)?.stringValue == "80×40" }
            && views(onlineView).contains { ($0 as? NSTextField)?.stringValue.contains("5s") == true }
            && onlinePreview === views(onlineView).first { $0 is OnlineLibraryDownloadsPreviewSurfaceView }
            && demands.sourceCallCount == demandCountBeforeEcho && drawnColor(onlinePreview, channel: 1)

        func attach(_ view: NSView) {
            host.addSubview(view)
            view.frame = NSRect(x: 0, y: 0, width: 368, height: 640)
            view.layoutSubtreeIfNeeded()
        }
        let closedFile = file.deletingLastPathComponent().appendingPathComponent("closed.mp4")
        try Data(repeating: 1, count: 19).write(to: closedFile)
        let closedKey = OLDownloadedThumbnailStore.cacheKey(for: closedFile)
        online.downloadedContent.entries.append(.init(id: 8, localURL: closedFile))
        frames.hold(closedFile.path)
        let closedView = OnlineLibraryDownloadsInspectorView(itemID: 8, service: online, libraryActions: actions())
        let closedPreview = views(closedView).first { $0 is OnlineLibraryDownloadsPreviewSurfaceView }!
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
            && closedPreview === views(closedView).first { $0 is OnlineLibraryDownloadsPreviewSurfaceView }
        closedView.removeFromSuperview()

        let sharedFile = file.deletingLastPathComponent().appendingPathComponent("shared.mp4")
        try Data(repeating: 2, count: 29).write(to: sharedFile)
        let sharedKey = OLDownloadedThumbnailStore.cacheKey(for: sharedFile)
        online.downloadedContent.entries.append(.init(id: 9, localURL: sharedFile))
        frames.hold(sharedFile.path)
        let withdrawn = OnlineLibraryDownloadsInspectorView(itemID: 9, service: online, libraryActions: actions())
        let remaining = OnlineLibraryDownloadsInspectorView(itemID: 9, service: online, libraryActions: actions())
        attach(withdrawn); attach(remaining)
        precondition(waitUntil { demands.requests.filter { $0.key == sharedKey }.count == 2 && frames.pendingCount(sharedFile.path) == 1 })
        withdrawn.removeFromSuperview()
        frames.release(sharedFile.path, image: solid(.blue))
        let remainingPreview = views(remaining).first { $0 is OnlineLibraryDownloadsPreviewSurfaceView }!
        let withdrawnPreview = views(withdrawn).first { $0 is OnlineLibraryDownloadsPreviewSurfaceView }!
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
        let sourceKey = OLDownloadedThumbnailStore.cacheKey(for: newSource)
        let previousSourceLease = demands.requests.last { $0.key == onlineKey }?.cancellation
        frames.hold(newSource.path)
        online.downloadedContent.entries[0] = .init(id: 7, localURL: newSource, fileSize: 37, thumbnailSourceKey: sourceKey)
        onlineView.updateLibraryActions(actions())
        precondition(waitUntil { frames.pendingCount(newSource.path) == 1 })
        checks["pixabay-source-replacement-cancels-old-consumer-and-retains-current-image-while-loading"] =
            previousSourceLease?.cancelled == true && drawnColor(onlinePreview, channel: 1)
            && onlinePreview === views(onlineView).first { $0 is OnlineLibraryDownloadsPreviewSurfaceView }
        frames.release(newSource.path, image: solid(.blue))
        precondition(waitUntil { drawnColor(onlinePreview, channel: 2) })
        let currentTitle = views(onlineView).first { ($0 as? NSTextField)?.stringValue == "new-source.mp4" }
        let currentDemandCount = demands.sourceCallCount
        onlineView.updateLibraryActions(actions())
        checks["pixabay-current-source-fills-in-place-and-ignores-unchanged-publication"] =
            drawnColor(onlinePreview, channel: 2) && onlinePreview.bounds.height == 156
            && currentTitle === views(onlineView).first { ($0 as? NSTextField)?.stringValue == "new-source.mp4" }
            && demands.sourceCallCount == currentDemandCount && frames.count(newSource.path) == 1
        let priorRevisionLease = demands.requests.last { $0.key == sourceKey }?.cancellation
        try Data(repeating: 4, count: 53).write(to: newSource, options: .atomic)
        let revisedKey = OLDownloadedThumbnailStore.cacheKey(for: newSource)
        frames.hold(newSource.path)
        online.downloadedContent.entries[0] = .init(id: 7, localURL: newSource, fileSize: 53, thumbnailSourceKey: revisedKey)
        onlineView.updateLibraryActions(actions())
        precondition(waitUntil { frames.pendingCount(newSource.path) == 1 })
        let keepsOldDuringRevision = drawnColor(onlinePreview, channel: 2) && priorRevisionLease?.cancelled == true
        frames.release(newSource.path, image: expectedImages[0])
        precondition(waitUntil { drawnColor(onlinePreview, channel: 0) })
        checks["pixabay-same-path-new-fingerprint-fills-current-image-without-changing-preview-object"] = keepsOldDuringRevision
            && sourceKey != revisedKey && frames.count(newSource.path) == 2
            && onlinePreview === views(onlineView).first { $0 is OnlineLibraryDownloadsPreviewSurfaceView }

        // The actual card must create the shared producer first. Keeping only
        // a fake visible cache consumer would miss its former direct loader.
        func card(_ entry: OLDownloadedEntry) -> AppKitOLDownloadsItem {
            let value = AppKitOLDownloadsItem()
            value.view.frame = NSRect(x: 0, y: 0, width: 230, height: 230)
            host.addSubview(value.view)
            value.configure(entry: entry, isSelected: false, isMultiSelectMode: false, isPlaying: false)
            value.view.layoutSubtreeIfNeeded()
            return value
        }
        let activeSource = file.deletingLastPathComponent().appendingPathComponent("active-first.mp4")
        try Data(repeating: 21, count: 211).write(to: activeSource)
        let activeOldKey = OLDownloadedThumbnailStore.cacheKey(for: activeSource)
        let activeEntry = OLDownloadedEntry(id: 43, localURL: activeSource, fileSize: 211, thumbnailSourceKey: activeOldKey)
        online.downloadedContent.entries.append(activeEntry)
        frames.hold(activeSource.path)
        let activeCard = card(activeEntry)
        let activeCardLease = activeCard.thumbnailCancellation!
        precondition(waitUntil { frames.pendingCount(activeSource.path) == 1 })
        let activeInspector = OnlineLibraryDownloadsInspectorView(itemID: 43, service: online, libraryActions: actions())
        let activePreview = views(activeInspector).first { $0 is OnlineLibraryDownloadsPreviewSurfaceView }!
        attach(activeInspector)
        let activeNear = ThumbnailCacheRequestCancellation()
        var activeNearTerminals = 0
        var activeNearImage: NSImage?
        OLDownloadedThumbnailStore.loadThumbnail(activeEntry, priority: .prefetch, cancellation: activeNear) { _, image in
            activeNearTerminals += 1; activeNearImage = image
        }
        precondition(waitUntil { demands.requests.filter { $0.key == activeOldKey }.count == 3 })
        let activeInspectorLease = demands.requests.filter { $0.key == activeOldKey && $0.priority == .visible }.last!.cancellation as! ThumbnailCacheRequestCancellation
        try Data(repeating: 22, count: 229).write(to: activeSource, options: .atomic)
        let activeCurrentKey = OLDownloadedThumbnailStore.cacheKey(for: activeSource)
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
        let queuedKey = OLDownloadedThumbnailStore.cacheKey(for: queuedSource)
        let queuedEntry = OLDownloadedEntry(id: 41, localURL: queuedSource, fileSize: 101, thumbnailSourceKey: queuedKey)
        online.downloadedContent.entries.append(queuedEntry)
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
        let sharedInspector = OnlineLibraryDownloadsInspectorView(itemID: 41, service: online, libraryActions: actions())
        let sharedPreview = views(sharedInspector).first { $0 is OnlineLibraryDownloadsPreviewSurfaceView }!
        attach(sharedInspector)
        let queuedNear = ThumbnailCacheRequestCancellation()
        var queuedNearDelivered = false
        var queuedNearImage: NSImage?
        OLDownloadedThumbnailStore.loadThumbnail(queuedEntry, priority: .prefetch, cancellation: queuedNear) { _, image in
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
        precondition(OLDownloadedThumbnailStore.cacheKey(for: queuedSource) == queuedKey)
        frames.hold(queuedSource.path)
        let restoredCard = card(queuedEntry)
        precondition(waitUntil { frames.pendingCount(queuedSource.path) == 1 })
        attach(sharedInspector)
        let restoredNear = ThumbnailCacheRequestCancellation()
        var restoredNearDelivered = false
        OLDownloadedThumbnailStore.loadThumbnail(queuedEntry, priority: .prefetch, cancellation: restoredNear) { _, _ in restoredNearDelivered = true }
        precondition(waitUntil { demands.requests.filter { $0.key == queuedKey }.count == 6 })
        let restoredCardLease = restoredCard.thumbnailCancellation
        restoredCard.endDisplayingThumbnail(); restoredNear.cancel()
        frames.release(queuedSource.path, image: expectedImages[2])
        precondition(waitUntil { drawnColor(sharedPreview, channel: 2) })
        checks["pixabay-real-card-inspector-and-near-share-one-producer-and-survive-card-exit"] =
            frames.count(queuedSource.path) == 1 && restoredCardLease?.cancelled == true && !restoredNearDelivered
            && restoredCard.thumbnailView.image == nil && downloadedCache.cachedImage(forKey: queuedKey) != nil
            && sharedPreview === views(sharedInspector).first { $0 is OnlineLibraryDownloadsPreviewSurfaceView }
        visibleFirst.view.removeFromSuperview(); restoredCard.view.removeFromSuperview(); sharedInspector.removeFromSuperview()

        let warmSource = file.deletingLastPathComponent().appendingPathComponent("warm-old-hint.mp4")
        try Data(repeating: 13, count: 131).write(to: warmSource)
        let warmOldKey = OLDownloadedThumbnailStore.cacheKey(for: warmSource)
        let warmEntry = OLDownloadedEntry(id: 42, localURL: warmSource, fileSize: 131, thumbnailSourceKey: warmOldKey)
        online.downloadedContent.entries.append(warmEntry)
        let warmup = ThumbnailCacheRequestCancellation()
        var warmupImage: NSImage?
        OLDownloadedThumbnailStore.loadThumbnail(warmEntry, priority: .prefetch, cancellation: warmup) { _, image in warmupImage = image }
        precondition(waitUntil { warmupImage != nil })
        try Data(repeating: 14, count: 149).write(to: warmSource, options: .atomic)
        let warmCurrentKey = OLDownloadedThumbnailStore.cacheKey(for: warmSource)
        precondition(warmCurrentKey != warmOldKey && downloadedCache.cachedImage(forKey: warmOldKey) != nil)
        frames.hold(warmSource.path)
        let currentCard = card(warmEntry)
        let currentInspector = OnlineLibraryDownloadsInspectorView(itemID: 42, service: online, libraryActions: actions())
        let currentPreview = views(currentInspector).first { $0 is OnlineLibraryDownloadsPreviewSurfaceView }!
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
        let warmCurrentInspector = OnlineLibraryDownloadsInspectorView(itemID: 42, service: online, libraryActions: actions())
        attach(warmCurrentInspector)
        let warmCurrentPreview = views(warmCurrentInspector).first { $0 is OnlineLibraryDownloadsPreviewSurfaceView }!
        precondition(waitUntil { drawnColor(warmCurrentPreview, channel: 2) })
        checks["pixabay-current-warm-card-remount-and-action-echo-preserve-pixels-without-av"] = keptCurrentPixels
            && frames.count(warmSource.path) == warmFrameCount && demands.reads(warmSource.path) == warmReads + 2
        checks["pixabay-real-card-admission-resolves-one-live-key-off-main"] = oneBackgroundAdmission
            && demands.mainReads == warmMainReads
        currentCard.endDisplayingThumbnail(); warmCurrentCard.endDisplayingThumbnail()
        currentCard.view.removeFromSuperview(); warmCurrentCard.view.removeFromSuperview()
        currentInspector.removeFromSuperview(); warmCurrentInspector.removeFromSuperview()
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
