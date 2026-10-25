import AppKit
import ImageIO

// Original UI and native footer controls run in this gate; source media/cache
// and alert leaves record demand without touching a real library or decoder.
struct SILWallpaper {
    let id: String
    let title: String
    let path: String
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
    var result: NSImage?
    func load(forKey: String, loader: @escaping () -> NSImage?, completion: @escaping (NSImage?) -> Void) { completion(result) }
    func cachedImage(forKey: String) -> NSImage? { nil }
}
enum SILThumbnailStore { static let sharedCache = CacheLeaf() }
enum OLDownloadedThumbnailStore { static let sharedCache = CacheLeaf() }
struct OLDownloadedEntry {
    let id: Int
    let localURL: URL
    var isAvailable = true
    var fileSize = 12
    var duration: Int? = 2
    var resolutionString: String? = "8×8"
    var thumbnailSourceKey: String? = nil
    var creationDate: Date? = nil
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
    @MainActor static func main() throws {
        _ = NSApplication.shared
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
        func actions(canOrganize: Bool = true, playing: Bool = false, canPlay: Bool = true) -> WallpaperInspectorActions {
            .init(state: .init(isPlaying: playing, isFavorite: false, canPerformPrimary: canPlay, canFavorite: canOrganize, canOrganize: canOrganize, playlistNames: ["New Mixed List"]),
                onPrimary: { primary += 1 }, onToggleFavorite: { favorites += 1 }, onChoosePlaylist: { _ in member += 1 })
        }
        SILThumbnailStore.sharedCache.result = NSImage(size: NSSize(width: 16, height: 8), flipped: false) { rect in
            NSColor(calibratedRed: 0.05, green: 0.9, blue: 0.1, alpha: 1).setFill(); rect.fill(); return true
        }
        let imageView = SILInspectorView(wallpaper: image, service: images, libraryActions: actions())
        let onlineView = OnlineLibraryDownloadsInspectorView(itemID: 7, service: online, libraryActions: actions())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 368, height: 640), styleMask: [.titled], backing: .buffered, defer: false)
        let host = NSView(); window.contentView = host
        func mount(_ view: NSView) {
            host.subviews.forEach { $0.removeFromSuperview() }
            host.addSubview(view)
            NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: host.leadingAnchor), view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                view.topAnchor.constraint(equalTo: host.topAnchor), view.bottomAnchor.constraint(equalTo: host.bottomAnchor)])
            host.layoutSubtreeIfNeeded()
        }
        mount(imageView)
        let imagePreview = views(imageView).first { $0 is SILInspectorPreviewSurfaceView }!
        let imageFrame = imagePreview.convert(imagePreview.bounds, to: host)
        pump(); host.layoutSubtreeIfNeeded()
        var checks: [String: Bool] = [:]
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
        mount(onlineView)
        let onlinePreview = views(onlineView).first { $0 is OnlineLibraryDownloadsPreviewSurfaceView }!
        let onlineFrame = onlinePreview.convert(onlinePreview.bounds, to: host)
        checks["real-pixabay-presents-prepared-file-metadata-on-its-first-layout"] = views(onlineView).contains { ($0 as? NSTextField)?.stringValue == "local.png" }
        pump(); host.layoutSubtreeIfNeeded()
        checks["real-pixabay-has-no-second-loading-layout-or-preview-replacement"] = onlinePreview === views(onlineView).first { $0 is OnlineLibraryDownloadsPreviewSurfaceView }
            && onlineFrame == onlinePreview.convert(onlinePreview.bounds, to: host)
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
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
