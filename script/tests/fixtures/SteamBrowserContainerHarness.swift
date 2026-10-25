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
    struct OrganizationPresentation: Equatable { let value: Int; var isPlaying = false }
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("SteamProbeCard")
    enum Context { case browser }
    var id = ""
    var keyboardFocused = false
    var organization: OrganizationPresentation?
    var playing = false
    override func loadView() {
        let label = NSTextField(labelWithString: "")
        label.alignment = .center
        label.wantsLayer = true
        label.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.5).cgColor
        view = label
    }
    func configure(displayContext: Context, isPlaying: Bool = false, item: SteamWorkshopBrowserItem,
                   downloadRecord: SteamWorkshopDownloadRecord?, downloadProgressStore: NSObject,
                   isDownloading: Bool, isDownloaded: Bool, isKeyboardFocused: Bool, organization: OrganizationPresentation? = nil,
                   makeMenu: (() -> NSMenu?)? = nil,
                   onOpen: @escaping () -> Void, onDownload: @escaping () -> Void,
                   onSetAsWallpaper: @escaping () -> Void, onCancelDownload: @escaping () -> Void) {
        id = item.id; keyboardFocused = isKeyboardFocused; (view as! NSTextField).stringValue = item.id
        self.organization = organization
        playing = isPlaying
    }
    func configureMetadataOnly(displayContext: Context, isPlaying: Bool = false, item: SteamWorkshopBrowserItem,
                   downloadRecord: SteamWorkshopDownloadRecord?, downloadProgressStore: NSObject,
                   isDownloading: Bool, isDownloaded: Bool, isKeyboardFocused: Bool, organization: OrganizationPresentation? = nil,
                   makeMenu: (() -> NSMenu?)? = nil,
                   onOpen: @escaping () -> Void, onDownload: @escaping () -> Void,
                   onSetAsWallpaper: @escaping () -> Void, onCancelDownload: @escaping () -> Void) {
        id = item.id; keyboardFocused = isKeyboardFocused; (view as! NSTextField).stringValue = item.id
        self.organization = organization
        playing = isPlaying
    }
    func setKeyboardFocus(_ value: Bool) { keyboardFocused = value }
    func forceReloadPreview() {}
    func setPreviewVisible(_ value: Bool) {}
}

@MainActor private final class SteamInsetToolbar: NSObject, NSToolbarDelegate {
    private let titleID = NSToolbarItem.Identifier("steam-insets-title")
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [titleID, .flexibleSpace] }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = "Steam 原生顶部回归"
        item.view = NSTextField(labelWithString: item.label)
        return item
    }
}

/// Controlled native clip geometry for the metrics boundary only. It is not
/// evidence that hardware coarse-wheel events produce elastic overscroll.
private final class SteamTopGapClip: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect { proposedBounds }
}

@main struct GridHarness {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let service = SteamWorkshopService()
        var window = NSWindow(contentRect: NSRect(x: 14000, y: 14000, width: 1150, height: 680),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        var grid: AppKitSteamWorkshopBrowserContainerView!
        var widthReports: [CGFloat] = []
        func mount() {
            grid = AppKitSteamWorkshopBrowserContainerView(service: service, onOpen: {_ in}, onDownload: {_ in},
                                                         onSetAsWallpaper: {_ in}, onCancelDownload: {_ in})
            grid.onClipWidthChange = { widthReports.append($0) }
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
            let metrics = WallpaperLibraryGridMetrics(clipWidth: visible.width, preferredColumns: grid.preferredColumns)
            if grid.currentColumnCount != metrics.columns || grid.flowLayout.itemSize != NSSize(width: metrics.coverSide, height: metrics.coverSide) {
                failures.append("\(phase): source grid differs from shared column/card geometry")
            }
            if grid.flowLayout.minimumInteritemSpacing != 8 || grid.flowLayout.minimumLineSpacing != 10 {
                failures.append("\(phase): source grid spacing differs from shared geometry")
            }
            if widthReports.last != visible.width { failures.append("\(phase): actual clip width not delivered") }
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
        if grid.currentColumnCount != 5 { failures.append("default source grid must request five columns") }
        let reportsBeforeSameLayout = widthReports.count
        grid.needsLayout = true; settle()
        if widthReports.count != reportsBeforeSameLayout { failures.append("same clip width must not republish") }
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
        grid.preferredColumns = 3
        service.displayedBrowserItems = all
        verify("before-inflight")
        let reduced = Array(all.dropFirst())
        service.displayedBrowserItems = reduced
        grid.commitItems(reduced)
        if !grid.isApplyingSnapshot { failures.append("no in-flight snapshot observed") }
        window.setContentSize(NSSize(width: 620, height: 680))
        grid.preferredColumns = 6
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
        grid.makeOrganization = { _ in .init(value: 7, isPlaying: true) }
        let originalCards = grid.collectionView.visibleItems().compactMap { $0 as? AppKitSteamWorkshopBrowserItem }
        if originalCards.isEmpty || !originalCards.allSatisfy({ $0.organization?.value == 7 && $0.playing }) {
            failures.append("injected organization did not reach current original cards")
        }
        grid.makeOrganization = { _ in .init(value: 8) }
        grid.refreshLibraryActions()
        if !originalCards.allSatisfy({ $0.organization?.value == 8 && !$0.playing }) || !originalCards.allSatisfy({ old in grid.collectionView.visibleItems().contains(where: { $0 === old }) }) {
            failures.append("organization refresh replaced native cards or missed new actions")
        }
        grid.makeOrganization = nil
        if !originalCards.allSatisfy({ $0.organization == nil }) { failures.append("removed organization factory retained old actions") }
        FileHandle.standardError.write(Data("SteamOriginalChecks \(checks) failures=\(failures.count)\n".utf8))
        // Preserve the original 77 checks above. These use the actual full-size
        // window and automatic native insets, never a fabricated toolbar height.
        var insetFacts: [String: Bool] = [:]
        var safeViewport: NSRect {
            let scroll: NSScrollView = grid.scrollView
            return (scroll as! WallpaperGridScrollView).gridViewportRect
        }
        func insetCheck(_ name: String, _ value: Bool) {
            insetFacts[name] = value
            if !value { failures.append(name) }
        }
        window.contentView = nil
        window.close()
        service.displayedBrowserItems = all
        service.pendingBrowserScrollRestoreOffset = 0
        window = NSWindow(contentRect: NSRect(x: 14000, y: 14000, width: 1150, height: 680),
            styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unified
        let toolbarDelegate = SteamInsetToolbar()
        let toolbar = NSToolbar(identifier: "steam-native-insets")
        toolbar.delegate = toolbarDelegate
        window.toolbar = toolbar
        window.setContentSize(NSSize(width: 1150, height: 680))
        mount(); window.orderFrontRegardless(); settle()
        func firstCardIsBelowToolbar() -> Bool {
            guard let cell = grid.collectionView.item(at: IndexPath(item: 0, section: 0)) else { return false }
            return abs(cell.view.convert(cell.view.bounds, to: nil).maxY - (window.contentLayoutRect.maxY - 8)) < 1
        }
        let nativeInset = grid.scrollView.contentInsets.top
        insetCheck("realToolbarHasUsableCurrentFeedViewport", safeViewport.width > 1 && safeViewport.height > 0
            && grid.orderedIDs == all.map(\.id))
        FileHandle.standardError.write(Data("SteamInsetGeometry root=\(grid.bounds) clip=\(grid.scrollView.contentView.bounds) viewport=\(safeViewport) document=\(grid.collectionView.frame) ids=\(grid.orderedIDs.count) pending=\(String(describing: service.pendingBrowserScrollRestoreOffset)) applying=\(grid.isApplyingSnapshot) layout=\(grid.pendingLayoutItemSizeUpdate)\n".utf8))
        insetCheck("realToolbarProducesAutomaticInset", nativeInset > 0 && grid.scrollView.automaticallyAdjustsContentInsets)
        insetCheck("logicalZeroAfterLateMountKeepsEightPointSafeTop", firstCardIsBelowToolbar()
            && abs(safeViewport.minY) < 1 && service.pendingBrowserScrollRestoreOffset == nil)
        grid.scrollView.contentView.setBoundsOrigin(.zero)
        grid.updateBrowserScrollMetrics()
        insetCheck("rawClipZeroRecordsLogicalInsetInsteadOfTop", abs(service.lastScrollOffset - nativeInset) < 1)
        service.pendingBrowserScrollRestoreOffset = 420; settle()
        insetCheck("logicalMiddleRoundTripsWithToolbar", abs(service.lastScrollOffset - 420) < 1
            && abs(safeViewport.minY - 420) < 1)
        let savedLogical = service.lastScrollOffset
        toolbar.isVisible = false; settle()
        insetCheck("fixtureChangesActualNativeInset", abs(grid.scrollView.contentInsets.top - nativeInset) > 1)
        service.pendingBrowserScrollRestoreOffset = savedLogical; settle()
        insetCheck("sameSourceSnapshotRestoresAcrossDifferentInsets", abs(safeViewport.minY - 420) < 1
            && abs(service.lastScrollOffset - 420) < 1)
        toolbar.isVisible = true; settle()
        grid.focusItem(at: 140); settle()
        grid.focusItem(at: 0); settle()
        if let frame = grid.flowLayout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))?.frame {
            insetCheck("keyboardFirstCardIsNotCoveredByToolbar", safeViewport.contains(frame))
        } else { insetCheck("keyboardFirstCardIsNotCoveredByToolbar", false) }
        service.allowsAutomaticBrowserContinuation = false
        let viewport = safeViewport
        let threshold = max(720, grid.scrollView.contentView.bounds.height * 2.5)
        let outside = grid.collectionView.frame.height - viewport.height - threshold - 2
        grid.scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: outside - grid.scrollView.contentInsets.top)); settle()
        let outsideCalls = service.continuationCalls
        service.allowsAutomaticBrowserContinuation = true
        grid.checkLoadMore()
        insetCheck("paginationUsesUncoveredViewportBeforeThreshold", service.continuationCalls == outsideCalls)
        service.allowsAutomaticBrowserContinuation = false
        grid.scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: outside + 4 - grid.scrollView.contentInsets.top)); settle()
        let insideCalls = service.continuationCalls
        service.allowsAutomaticBrowserContinuation = true
        grid.checkLoadMore()
        insetCheck("paginationUsesUncoveredViewportInsideThreshold", service.continuationCalls == insideCalls + 1)
        service.allowsAutomaticBrowserContinuation = false
        // Controlled bottom inset is a separate boundary case after proving
        // real automatic toolbar geometry above. Product never sets insets.
        grid.scrollView.automaticallyAdjustsContentInsets = false
        grid.scrollView.contentInsets = NSEdgeInsets(top: 37, left: 0, bottom: 19, right: 0)
        service.pendingBrowserScrollRestoreOffset = 1_000_000; settle()
        let bottom = max(-37, grid.collectionView.bounds.height - grid.scrollView.contentView.bounds.height + 19)
        insetCheck("restoreClampsToNativeBottomIncludingBottomInset", abs(grid.scrollView.contentView.bounds.minY - bottom) < 1)
        service.pendingBrowserScrollRestoreOffset = 0; settle()
        insetCheck("restoreClampsToNativeTopWithDifferentInsets", abs(grid.scrollView.contentView.bounds.minY + 37) < 1)
        let resizeHost = NSView(frame: window.contentView!.bounds)
        window.contentView = resizeHost
        resizeHost.addSubview(grid)
        grid.frame = NSRect(x: 0, y: 0, width: 0, height: resizeHost.bounds.height)
        grid.layoutSubtreeIfNeeded()
        insetCheck("zeroWidthFixtureReallyHasNoUsableViewport", safeViewport.width <= 1)
        service.pendingBrowserScrollRestoreOffset = 300
        grid.restorePendingScrollOffsetIfReady()
        insetCheck("zeroWidthDoesNotConsumePending", service.pendingBrowserScrollRestoreOffset == 300)
        grid.frame = resizeHost.bounds
        grid.needsLayout = true; settle()
        FileHandle.standardError.write(Data("SteamInsetRecoveredGeometry host=\(resizeHost.bounds) root=\(grid.bounds) scroll=\(grid.scrollView.frame) clip=\(grid.scrollView.contentView.bounds) viewport=\(safeViewport) document=\(grid.collectionView.frame) pending=\(String(describing: service.pendingBrowserScrollRestoreOffset)) flags=\(grid.isItemsApplyScheduled)/\(grid.isApplyingSnapshot)/\(grid.pendingLayoutItemSizeUpdate) window=\(grid.window != nil)\n".utf8))
        insetCheck("sameFeedLayoutRetriesPendingAfterZeroWidth", service.pendingBrowserScrollRestoreOffset == nil
            && abs(safeViewport.minY - 300) < 1)
        grid.scrollView.automaticallyAdjustsContentInsets = true
        grid.needsLayout = true; settle()
        service.pendingBrowserScrollRestoreOffset = 0; settle()
        insetCheck("originalIDsAndFooterSurviveRestoration", grid.orderedIDs == all.map(\.id) && grid.footerState != .hidden)
        let originalClip = grid.scrollView.contentView, preservedInsets = grid.scrollView.contentInsets
        let gapClip = SteamTopGapClip(frame: originalClip.frame)
        grid.scrollView.contentView = gapClip
        grid.scrollView.documentView = grid.collectionView
        grid.scrollView.automaticallyAdjustsContentInsets = false
        grid.scrollView.contentInsets = preservedInsets
        gapClip.setBoundsOrigin(NSPoint(x: 0, y: -preservedInsets.top - 64))
        let actualGapViewport = grid.scrollView.gridViewportRect
        grid.updateBrowserScrollMetrics()
        insetCheck("controlledNativeTopGapNeverPublishesNegativeLogicalScrollAnchor", preservedInsets.top > 0
            && actualGapViewport.minY < -24 && service.lastScrollOffset == 0
            && grid.scrollView.contentView.bounds.minY < grid.scrollView.gridDocumentTopY)
        grid.scrollView.contentView = originalClip
        grid.scrollView.documentView = grid.collectionView
        grid.scrollView.automaticallyAdjustsContentInsets = true
        withExtendedLifetime(toolbarDelegate) {}
        FileHandle.standardError.write(Data(("SteamInsetFacts " + String(data: try! JSONSerialization.data(withJSONObject: insetFacts, options: [.sortedKeys]), encoding: .utf8)! + "\n").utf8))
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
