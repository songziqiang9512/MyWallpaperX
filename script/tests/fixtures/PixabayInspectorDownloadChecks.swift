import AppKit
import Combine

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

        let malformed = PixabayVideoFile(url: "http://[", width: 3840, height: 2160, size: 8192, thumbnail: "")
        let singleItem = PixabayVideoItem(id: 68, pageURL: "", tags: "One file", duration: 21, user: "",
            videos: .init(large: malformed, medium: large, small: nil, tiny: nil))
        precondition(singleItem.videoDownload() == nil && singleItem.videoDownloadOptions.map(\.tier) == [.medium])
        let singleView = PixabayDownloadsInspectorView(itemID: 68, service: pixabay, remoteItem: singleItem)
        window.contentView = singleView
        observeInspectorAlert = { _, _, _ in preconditionFailure("one actual file must download without a prompt") }
        precondition(downloadButton(in: singleView)!.accessibilityPerformPress())
        precondition(pixabay.downloadRequests == [67, 68] && pixabay.selectedDownloadTiers == [.small, .medium])
        print("pixabay-remote-download-quality-pass")
    }

    private static func downloadButton(in view: NSView) -> InspectorFooterButton? {
        if let button = view as? InspectorFooterButton, button.action == NSSelectorFromString("setAsWallpaper") {
            return button
        }
        return view.subviews.lazy.compactMap { downloadButton(in: $0) }.first
    }
}
