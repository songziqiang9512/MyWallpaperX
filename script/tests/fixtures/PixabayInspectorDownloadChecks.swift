import AppKit
import Combine

struct PixabayDownloadedEntry: Equatable {
    let id: Int
    let localURL: URL
    var isAvailable = true
    var fileSize = 12
    var duration: Int? = 2
    var resolutionString: String? = "8×8"
    var displaySize: CGSize? = nil
    var nominalFrameRateText: String? = nil
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
    var selectedDownloadTiers: [PixabayDownloadTier] = []
    var downloadedIDs: Set<Int> { Set(downloadedContent.entries.filter(\.isAvailable).map(\.id)) }
    func setLocalFileAsWallpaper(id: Int) { writes += 1 }
    func download(item: PixabayVideoItem, tier: PixabayDownloadTier? = nil) {
        downloadRequests.append(item.id)
        if let tier { selectedDownloadTiers.append(tier) }
        downloadingIDs.insert(item.id)
    }
}

enum PixabayDownloadedAssetMetadata { static func formatDuration(_ seconds: Int) -> String { "\(seconds)s" } }
private var observeInspectorAlert: ((NSAlert, NSWindow?, (NSApplication.ModalResponse) -> Void) -> Void)?
func makeAppAlert(title: String, message: String, buttons: [String], accessoryView: NSView?) -> NSAlert {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.accessoryView = accessoryView
    buttons.forEach { alert.addButton(withTitle: $0) }
    return alert
}
func presentAppAlert(_ alert: NSAlert, in window: NSWindow?, completion: @escaping (NSApplication.ModalResponse) -> Void) {
    observeInspectorAlert?(alert, window, completion)
}
func appModalHostWindow() -> NSWindow? { nil }

@MainActor enum PixabayInspectorDownloadChecks {
    static func run() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 600),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close(); observeInspectorAlert = nil }
        let pixabay = PixabayService()
        let resolutionLabel = String(localized: "Resolution")
        var mismatches: [String] = []
        func checkRemoteFacts(_ view: NSView, item: PixabayVideoItem, resolution: String?, size: String?) {
            let fields = labels(in: view)
            let secondary = [size, item.durationString].compactMap { $0 }.joined(separator: "  ·  ")
            let resolutionMatches = fields.contains(resolutionLabel) == (resolution != nil)
                && (resolution.map(fields.contains) ?? true)
            if !resolutionMatches || !fields.contains(secondary) {
                mismatches.append("\(item.displayTitle): expected resolution \(resolution ?? "omitted") and \(secondary), saw \(fields)")
            }
        }
        let large = PixabayVideoFile(url: "https://cdn.pixabay.com/large.mp4", width: 1920, height: 1080,
            size: 4096, thumbnail: "")
        let small = PixabayVideoFile(url: "https://cdn.pixabay.com/small.mp4", width: 640, height: 360,
            size: 2048, thumbnail: "")
        let qualityItem = PixabayVideoItem(id: 67, pageURL: "", tags: "Choose remote quality", duration: 21, user: "",
            videos: .init(large: large, medium: large, small: small, tiny: nil))
        let qualityView = PixabayDownloadsInspectorView(itemID: 67, service: pixabay, remoteItem: qualityItem)
        window.contentView = qualityView
        let qualityFooter = downloadButton(in: qualityView)!
        var observedChoices = false
        observeInspectorAlert = { alert, hostWindow, respond in
            let popup = alert.accessoryView as? NSPopUpButton
            observedChoices = hostWindow === window && alert.informativeText == qualityItem.displayTitle
                && popup?.indexOfSelectedItem == 0 && popup?.numberOfItems == 2
                && popup?.itemTitle(at: 0).contains("1920 × 1080") == true
                && popup?.itemTitle(at: 1).contains("640 × 360") == true
            respond(.alertSecondButtonReturn)
        }
        precondition(qualityFooter.accessibilityPerformPress())
        precondition(observedChoices && pixabay.downloadRequests.isEmpty, "the duplicate URL is hidden and Cancel starts no task")
        observeInspectorAlert = { alert, _, respond in
            (alert.accessoryView as? NSPopUpButton)?.selectItem(at: 1)
            respond(.alertFirstButtonReturn)
        }
        precondition(qualityFooter.accessibilityPerformPress())
        let deadline = Date().addingTimeInterval(4)
        while qualityFooter.isEnabled && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        }
        precondition(pixabay.downloadRequests == [67] && pixabay.selectedDownloadTiers == [.small] && !qualityFooter.isEnabled)

        let medium = PixabayVideoFile(url: "https://cdn.pixabay.com/medium.mp4", width: 1280, height: 720,
            size: 31_457_280, thumbnail: "")
        let malformed = PixabayVideoFile(url: "http://[", width: 3840, height: 2160, size: 8192, thumbnail: "")
        let singleItem = PixabayVideoItem(id: 68, pageURL: "", tags: "One file", duration: 21, user: "",
            videos: .init(large: malformed, medium: medium, small: nil, tiny: nil))
        precondition(singleItem.videoDownload() == nil && singleItem.videoDownloadOptions.map(\.tier) == [.medium])
        let singleView = PixabayDownloadsInspectorView(itemID: 68, service: pixabay, remoteItem: singleItem)
        window.contentView = singleView
        checkRemoteFacts(singleView, item: singleItem, resolution: "1280×720", size: "30.0MB")
        observeInspectorAlert = { _, _, _ in preconditionFailure("one actual file must download without a prompt") }
        precondition(downloadButton(in: singleView)!.accessibilityPerformPress())
        precondition(pixabay.downloadRequests == [67, 68] && pixabay.selectedDownloadTiers == [.small, .medium])

        let emptyLarge = PixabayVideoFile(url: "", width: 1920, height: 1080, size: 0, thumbnail: "")
        let defaultItem = PixabayVideoItem(id: 71, pageURL: "", tags: "Empty Large", duration: 21, user: "",
            videos: .init(large: emptyLarge, medium: medium, small: small, tiny: nil))
        let defaultView = PixabayDownloadsInspectorView(itemID: 71, service: pixabay, remoteItem: defaultItem)
        window.contentView = defaultView
        checkRemoteFacts(defaultView, item: defaultItem, resolution: "1280×720", size: "30.0MB")
        var observedDefault = false
        observeInspectorAlert = { alert, hostWindow, respond in
            let popup = alert.accessoryView as? NSPopUpButton
            observedDefault = hostWindow === window && popup?.numberOfItems == 2 && popup?.indexOfSelectedItem == 0
                && popup?.itemTitle(at: 0).contains("1280 × 720") == true
                && popup?.itemTitle(at: 1).contains("640 × 360") == true
            respond(.alertFirstButtonReturn)
        }
        precondition(downloadButton(in: defaultView)!.accessibilityPerformPress())
        precondition(observedDefault && pixabay.downloadRequests == [67, 68, 71]
            && pixabay.selectedDownloadTiers == [.small, .medium, .medium], "the unmodified popup requests Medium")

        let unmeasuredMedium = PixabayVideoFile(url: medium.url, width: medium.width, height: medium.height,
            size: 0, thumbnail: "")
        let noBytes = PixabayVideoItem(id: 72, pageURL: "", tags: "Medium without bytes", duration: 21, user: "",
            videos: .init(large: emptyLarge, medium: unmeasuredMedium, small: small, tiny: nil))
        let noBytesView = PixabayDownloadsInspectorView(itemID: 72, service: pixabay, remoteItem: noBytes)
        checkRemoteFacts(noBytesView, item: noBytes, resolution: "1280×720", size: nil)

        let unknownDimensions = PixabayVideoFile(url: medium.url, width: 0, height: 0, size: medium.size, thumbnail: "")
        let noDimensions = PixabayVideoItem(id: 73, pageURL: "", tags: "Medium without dimensions", duration: 21, user: "",
            videos: .init(large: emptyLarge, medium: unknownDimensions, small: small, tiny: nil))
        let noDimensionsView = PixabayDownloadsInspectorView(itemID: 73, service: pixabay, remoteItem: noDimensions)
        checkRemoteFacts(noDimensionsView, item: noDimensions, resolution: nil, size: "30.0MB")

        pixabay.downloadedContent.entries = [
            .init(id: 71, localURL: URL(fileURLWithPath: "/fixture/online_71.mp4"), nominalFrameRateText: "24 FPS"),
            .init(id: 70, localURL: URL(fileURLWithPath: "/fixture/online_70.mp4")),
        ]
        let known = PixabayDownloadsInspectorView(itemID: 71, service: pixabay, remoteItem: defaultItem)
        let unknown = PixabayDownloadsInspectorView(itemID: 70, service: pixabay, remoteItem: nil)
        let label = String(localized: "Nominal Frame Rate")
        let knownFields = labels(in: known)
        let localSize = ByteCountFormatter.string(fromByteCount: 12, countStyle: .file)
        precondition(knownFields.contains(label) && knownFields.contains("24 FPS") && knownFields.contains("8×8")
            && knownFields.contains("\(localSize)  ·  2s  ·  MP4") && !knownFields.contains("1280×720"))
        precondition(!labels(in: unknown).contains(label))
        precondition(mismatches.isEmpty, mismatches.joined(separator: "\n"))
        print("pixabay-remote-download-quality-pass")
    }

    private static func downloadButton(in view: NSView) -> InspectorFooterButton? {
        if let button = view as? InspectorFooterButton, button.action == NSSelectorFromString("setAsWallpaper") {
            return button
        }
        return view.subviews.lazy.compactMap { downloadButton(in: $0) }.first
    }

    private static func labels(in view: NSView) -> [String] {
        if let label = view as? NSTextField { return [label.stringValue] }
        return view.subviews.flatMap { labels(in: $0) }
    }
}
