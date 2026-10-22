import AppKit
import Combine

@MainActor protocol ModuleFocusable { func requestFocus() }
enum ModuleIdentifier: String { case steamWorkshop }
extension Notification.Name { static let moduleDidBecomeActive = Notification.Name("moduleActive") }
enum InspectorHostActions { @MainActor static func postClose() {} }
struct SteamWorkshopBrowserItem: Equatable { let id: String; var title = "Wallpaper" }
struct SteamWorkshopDownloadRecord {}
enum SteamWorkshopItemMenu {
    @MainActor static func make(item: SteamWorkshopBrowserItem, service: SteamWorkshopService) -> NSMenu { NSMenu() }
}
@MainActor final class SteamWorkshopService {
    @Published var displayedBrowserItems: [SteamWorkshopBrowserItem] = []
    @Published var zoomOffset = 0
    @Published var activeDownloadItemIDs: Set<String> = []
    @Published var downloads: [SteamWorkshopDownloadRecord] = []
    @Published var launchPendingRecordID: String?
    @Published var previewReloadToken = 0
    @Published var isRefreshingBrowserFeed = false
    @Published var isLoadingMoreBrowserItems = false
    @Published var hasMoreBrowserItems = false
    @Published var browserLoadMoreFailureMessage: String?
    @Published var pendingBrowserScrollRestoreOffset: CGFloat?
    var selectedBrowserItem: SteamWorkshopBrowserItem?
    var allowsAutomaticBrowserContinuation = false
    func latestDownloadRecord(for id: String) -> SteamWorkshopDownloadRecord? { nil }
    func downloadRecord(for id: String) -> SteamWorkshopDownloadRecord? { nil }
    let downloadProgressStore = NSObject()
    func isDownloading(itemID: String) -> Bool { false }
    func isDownloaded(itemID: String) -> Bool { false }
    var continuationCalls = 0
    var lastScrollOffset: CGFloat = 0
    func loadMoreBrowserItemsIfNeeded() { continuationCalls += 1 }
    func retryLoadingMoreBrowserItems() {}
    func consumePendingBrowserScrollRestoreOffset() { pendingBrowserScrollRestoreOffset = nil }
    func updateBrowserScrollMetrics(offsetY: CGFloat, contentHeight: CGFloat, viewportHeight: CGFloat) { lastScrollOffset = offsetY }
    func refresh() {}
}
@MainActor final class SteamWorkshopPreviewPrefetchController {
    struct Candidate {
        let id: String
        let item: SteamWorkshopBrowserItem
        let record: SteamWorkshopDownloadRecord?
        var startsIfMissing = true
    }
    var replacements = 0
    func replace(with candidates: [Candidate], maxPixelSize: Int) { replacements += 1 }
    func cancelAll() {}
}
@MainActor final class AppKitSteamWorkshopBrowserItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("SteamProbeCard")
    enum Context { case browser }
    var id = ""
    var keyboardFocused = false
    override func loadView() {
        let label = NSTextField(labelWithString: "")
        label.alignment = .center
        label.wantsLayer = true
        label.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.5).cgColor
        view = label
    }
    func configure(displayContext: Context, item: SteamWorkshopBrowserItem,
                   downloadRecord: SteamWorkshopDownloadRecord?, downloadProgressStore: NSObject,
                   isDownloading: Bool, isDownloaded: Bool, isKeyboardFocused: Bool,
                   onOpen: @escaping () -> Void, onDownload: @escaping () -> Void,
                   onSetAsWallpaper: @escaping () -> Void, onCancelDownload: @escaping () -> Void) {
        id = item.id; keyboardFocused = isKeyboardFocused; (view as! NSTextField).stringValue = item.id
    }
    func configureMetadataOnly(displayContext: Context, item: SteamWorkshopBrowserItem,
                   downloadRecord: SteamWorkshopDownloadRecord?, downloadProgressStore: NSObject,
                   isDownloading: Bool, isDownloaded: Bool, isKeyboardFocused: Bool,
                   onOpen: @escaping () -> Void, onDownload: @escaping () -> Void,
                   onSetAsWallpaper: @escaping () -> Void, onCancelDownload: @escaping () -> Void) {
        id = item.id; keyboardFocused = isKeyboardFocused; (view as! NSTextField).stringValue = item.id
    }
    func setKeyboardFocus(_ value: Bool) { keyboardFocused = value }
    func forceReloadPreview() {}
    func setPreviewVisible(_ value: Bool) {}
}

@main struct GridHarness {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let service = SteamWorkshopService()
        let window = NSWindow(contentRect: NSRect(x: 14000, y: 14000, width: 1150, height: 680),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        var grid: AppKitSteamWorkshopBrowserContainerView!
        func mount() {
            grid = AppKitSteamWorkshopBrowserContainerView(service: service, onOpen: {_ in}, onDownload: {_ in},
                                                         onSetAsWallpaper: {_ in}, onCancelDownload: {_ in})
            window.contentView = grid
        }
        mount(); window.orderFront(nil)
        func settle() {
            let until = Date().addingTimeInterval(2)
            repeat {
                RunLoop.main.run(until: Date().addingTimeInterval(0.003))
                window.contentView?.layoutSubtreeIfNeeded()
            } while (grid.isApplyingSnapshot || grid.isItemsApplyScheduled || grid.pendingItems != nil
                     || grid.pendingLayoutItemSizeUpdate) && Date() < until
            window.displayIfNeeded()
        }
        let all = (1...150).map { SteamWorkshopBrowserItem(id: String(format: "%03d", $0)) }
        var failures: [String] = []
        var checks = 0
        func verify(_ phase: String) {
            settle()
            let collection = grid.collectionView
            let visible = grid.scrollView.contentView.bounds
            let attributes = grid.flowLayout.layoutAttributesForElements(in: visible).filter {
                $0.representedElementCategory == .item && $0.indexPath?.section == 0 && $0.frame.intersects(visible)
            }
            if attributes.isEmpty && !grid.orderedIDs.isEmpty { failures.append("\(phase): missing visible attributes") }
            if grid.orderedIDs != service.displayedBrowserItems.map(\.id) { failures.append("\(phase): ordered identities") }
            for attr in attributes {
                let expected = grid.dataSource.itemIdentifier(for: attr.indexPath!)!
                guard let cell = collection.item(at: attr.indexPath!) as? AppKitSteamWorkshopBrowserItem else {
                    failures.append("\(phase): empty slot \(attr.indexPath!)"); continue
                }
                if cell.id != expected { failures.append("\(phase): identity \(cell.id) vs \(expected)") }
                if abs(cell.view.frame.minX - attr.frame.minX) > 1 || abs(cell.view.frame.minY - attr.frame.minY) > 1 {
                    failures.append("\(phase): displaced \(expected): \(cell.view.frame) vs \(attr.frame)")
                }
            }
            if grid.footerState != .hidden,
               let footer = grid.flowLayout.layoutAttributesForItem(at: IndexPath(item: 0, section: 1)) {
                let expected = SteamWorkshopBrowserFooterSupport.size(for: grid.footerState,
                    boundsWidth: collection.bounds.width, sectionInset: grid.flowLayout.sectionInset)
                if abs(footer.frame.height - expected.height) > 1 { failures.append("\(phase): stale footer height") }
            }
            checks += 1
        }
        service.displayedBrowserItems = Array(all.prefix(60)); verify("initial")
        for n in 0..<30 {
            service.isLoadingMoreBrowserItems = n % 3 == 0
            service.hasMoreBrowserItems = n % 4 != 0
            service.displayedBrowserItems = n % 2 == 0 ? Array(all.reversed()) : all
            window.setContentSize(NSSize(width: [1150, 820, 1400, 620][n % 4], height: 680))
            grid.requestFocus()
            verify("sort-resize-\(n)")
            grid.scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: CGFloat(n % 5) * 210))
            verify("scroll-\(n)")
            if n % 3 == 0 {
                window.contentView = nil; mount()
                service.displayedBrowserItems = Array(all.prefix(90)); verify("remount-\(n)")
            }
        }
        // Change geometry while an actual native snapshot is still applying.
        window.setContentSize(NSSize(width: 2800, height: 680))
        service.zoomOffset = -3
        service.displayedBrowserItems = all
        verify("before-inflight")
        let reduced = Array(all.dropFirst())
        service.displayedBrowserItems = reduced
        grid.commitItems(reduced)
        if !grid.isApplyingSnapshot { failures.append("no in-flight snapshot observed") }
        window.setContentSize(NSSize(width: 620, height: 680))
        service.zoomOffset = 2
        verify("resize-during-snapshot")
        service.isLoadingMoreBrowserItems = false
        service.hasMoreBrowserItems = true
        service.browserLoadMoreFailureMessage = "retry"
        verify("failed-footer-52")
        service.browserLoadMoreFailureMessage = nil
        verify("ready-footer-40")

        let detached = grid!
        window.contentView = nil
        service.pendingBrowserScrollRestoreOffset = 420
        detached.restorePendingScrollOffsetIfReady()
        detached.updateBrowserScrollMetrics()
        if service.pendingBrowserScrollRestoreOffset != 420 { failures.append("detached view consumed restore") }
        mount(); verify("restore-after-remount")
        if service.pendingBrowserScrollRestoreOffset != nil || abs(service.lastScrollOffset - 420) > 1 {
            failures.append("mounted grid failed scroll restoration")
        }
        service.allowsAutomaticBrowserContinuation = true
        let before = service.continuationCalls
        // Set directly in the same main turn: the publisher has not restored it yet.
        service.pendingBrowserScrollRestoreOffset = 420
        grid.checkLoadMore()
        if service.continuationCalls != before { failures.append("continuation before restore") }
        settle()
        grid.scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: grid.collectionView.bounds.height - 680))
        grid.checkLoadMore()
        if service.continuationCalls <= before { failures.append("continuation failed after restore") }
        service.allowsAutomaticBrowserContinuation = false
        grid.focusItem(at: 140); verify("offscreen-keyboard-focus")
        let focusPath = IndexPath(item: 140, section: 0)
        if (grid.collectionView.item(at: focusPath) as? AppKitSteamWorkshopBrowserItem)?.keyboardFocused != true {
            failures.append("offscreen keyboard focus missing on display")
        }
        if let directory = ProcessInfo.processInfo.environment["MWX_STEAM_GRID_PROOF_DIR"] {
            grid.scrollView.contentView.setBoundsOrigin(.zero)
            settle()
            grid.displayIfNeeded()
            if let bitmap = grid.bitmapImageRepForCachingDisplay(in: grid.bounds) {
                grid.cacheDisplay(in: grid.bounds, to: bitmap)
                try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory).appendingPathComponent("native-grid.png"))
            }
        }
        let prefetchBeforeOrderOut = grid.previewPrefetch.replacements
        window.orderOut(nil)
        grid.prioritizeVisibleItemsForHydration()
        grid.prefetchCurrentViewport()
        if grid.previewPrefetchWorkItem != nil || grid.previewPrefetch.replacements != prefetchBeforeOrderOut {
            failures.append("ordered-out window admitted prefetch")
        }
        print("checks", checks, "failures", failures.count)
        failures.prefix(20).forEach { print($0) }
        precondition(failures.isEmpty)
        window.close()
    }
}
