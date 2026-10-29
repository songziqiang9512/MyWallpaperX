import AppKit
import Combine

// ACTUAL_PRESENTATION_VALUE
// ACTUAL_DIRECTORY_ACTION
// ACTUAL_TINT_SURFACE
// The real Inspector container and hit testing are included. Only its animation
// constants, notification name and presentation payload are irrelevant leaves.
private let inspectorHostAnimationDuration: Double = 0.24
private let inspectorHostSlideInTiming = CAMediaTimingFunction(controlPoints: 0.22, 1.12, 0.32, 1)
private let inspectorHostSlideOutTiming = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.22, 1)
private protocol ToolbarGridScrollDismissalSurface: AnyObject {}
extension Notification.Name { static let inspectorHostCloseRequested = Self("chrome-fixture-inspector-close") }
// ACTUAL_INSPECTOR_HOST

@MainActor private final class ChromePresentation {
    var state = WallpaperLibraryPresentationState()
    var page: WallpaperLibraryPage { state.page }
    var queryState: WallpaperLibraryQueryState { state.query }
    var queries: [WallpaperLibraryQueryState] = []
    func setQueryState(_ query: WallpaperLibraryQueryState) -> Bool { state.query = query; queries.append(query); return true }
}
@MainActor private final class ChromeCatalog { var catalog = WallpaperLibraryCatalog() }
@MainActor private final class ChromeWorkspace {
    let presentation = ChromePresentation(), catalog = ChromeCatalog()
    var recoveryMessage: String?
    var relationships = UserCollectionsSnapshot(revision: 0, resetEpoch: UUID(), migrationManifestID: nil,
        playlists: [], members: [], favorites: [], recent: [], aliases: [], locators: [])
}
@MainActor private final class ChromeCommands {
    var canImport = true, canOrganize = true
    var imports = 0
    var displayedPlayRequests: [Bool] = []
    func importFiles() { imports += 1 }
    func playDisplayed(random: Bool = false) { displayedPlayRequests.append(random) }
}
@MainActor private final class OnlineImageLibrary {
    static let shared = OnlineImageLibrary()
    var refreshes = 0
    func refreshLocal() { refreshes += 1 }
}
@MainActor private final class ChromePixabay {
    var refreshes = 0
    func refreshDownloadedContent() { refreshes += 1 }
}
@MainActor private final class WallpaperLibraryWindowComposition {
    let workspace = ChromeWorkspace(), commands = ChromeCommands(), pixabay = ChromePixabay()
    let chrome: WallpaperLibraryPageChrome
    let grid: WallpaperLibraryGridController
    let directory: AppKitPlaylistDirectoryController
    let header = WallpaperPlaylistHeaderView()
    var allEntries: [WallpaperPlaylistDirectoryEntry] = []
    var covers: [UUID: WallpaperPlaylistArtwork] = [:]
    private var split: NSViewController { chrome }
    var navigations: [WallpaperLibraryPage] = [], pickers: [UUID] = []
    init(_ chrome: WallpaperLibraryPageChrome, grid: WallpaperLibraryGridController, directory: AppKitPlaylistDirectoryController) {
        self.chrome = chrome; self.grid = grid; self.directory = directory
    }
    func navigate(to page: WallpaperLibraryPage) { navigations.append(page) }
    func showPicker(for id: UUID) { pickers.append(id) }
    func apply(_ state: WallpaperLibraryPresentationState) {
        workspace.presentation.state = state
        updatePageChrome(state)
    }
    func applyHeader(_ state: WallpaperLibraryPresentationState) {
        workspace.presentation.state = state
        updateHeader(state)
    }
    // ACTUAL_INPUT_PERMISSION
    // ACTUAL_HEADER_UPDATE
    // ACTUAL_FEEDBACK
}
private final class ChromeCell: NSCollectionViewItem {
    override func loadView() { view = WallpaperCardInteractionView() }
}
private final class ChromeToolbar: NSObject, NSToolbarDelegate {
    let item = NSToolbarItem.Identifier("chrome-native-title")
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [item] }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [item] }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        item.view = NSTextField(labelWithString: "原生全页反馈")
        return item
    }
}

@main private enum WallpaperLibraryPageChromeHarness {
    @MainActor static func descendants<T: NSView>(_ root: NSView, _ type: T.Type) -> [T] {
        ((root as? T).map { [$0] } ?? []) + root.subviews.flatMap { descendants($0, type) }
    }
    @MainActor static func main() {
        initializeNativeAppHarness()
        let app = NSApplication.shared
        Task { @MainActor in
            do { try await run() }
            catch { fatalError("Chrome fixture: \(error)") }
            app.stop(nil)
            if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { app.postEvent(event, atStart: false) }
        }
        app.run()
    }

    @MainActor static func run() async throws {
        var checks: [String: Bool] = [:]
        let reuse = NSUserInterfaceItemIdentifier("chrome-cell")
        let grid = WallpaperLibraryGridController { collection, path, _, _ in collection.makeItem(withIdentifier: reuse, for: path) }
        grid.loadViewIfNeeded(); grid.collection.register(ChromeCell.self, forItemWithIdentifier: reuse)
        let detail = AppKitDetailHostViewController(), directory = AppKitPlaylistDirectoryController()
        let chrome = WallpaperLibraryPageChrome(content: detail)
        let probe = WallpaperLibraryWindowComposition(chrome, grid: grid, directory: directory)
        probe.workspace.catalog.catalog.loadedProviders = Set(WallpaperProvider.allCases)
        let inspector = NSViewController(); inspector.view = NSView()
        let container = InspectorDetailContainerViewController(contentController: chrome, overlayController: inspector,
            permitsNoticeInteraction: { [weak chrome] in chrome?.permitsNoticeInteraction(at: $0) ?? false },
            onNoticeOcclusionChange: { [weak chrome] in chrome?.setNoticeTrailingOcclusion($0) })
        let window = NSWindow(contentRect: NSRect(x: 200, y: 160, width: 1000, height: 700),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = container
        let toolbarDelegate = ChromeToolbar(), toolbar = NSToolbar(identifier: "chrome-native-toolbar")
        toolbar.delegate = toolbarDelegate; window.toolbar = toolbar; window.toolbarStyle = .unified
        NSApp.activate(); window.makeKeyAndOrderFront(nil)
        defer { withExtendedLifetime(toolbarDelegate) {}; window.orderOut(nil); window.close() }
        func settle() {
            for _ in 0..<3 {
                window.contentView?.layoutSubtreeIfNeeded()
                let until = Date().addingTimeInterval(0.03)
                repeat { RunLoop.main.run(until: Date().addingTimeInterval(0.002)) } while Date() < until
            }
        }
        func label(_ text: String) -> NSTextField? { descendants(chrome.view, NSTextField.self).first { $0.stringValue == text && !$0.isHiddenOrHasHiddenAncestor } }
        func button(_ title: String) -> NSButton? { descendants(chrome.view, NSButton.self).first { $0.title == title && !$0.isHiddenOrHasHiddenAncestor } }
        func send(_ button: NSButton) { if let action = button.action { NSApp.sendAction(action, to: button.target, from: button) } }
        func click(_ point: NSPoint) async throws -> Int {
            let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime + 0.01, windowNumber: window.windowNumber,
                context: nil, eventNumber: 2, clickCount: 1, pressure: 0)!
            var dispatchedUps = 0
            let upMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { event in
                MainActor.assumeIsolated {
                    if event.windowNumber == window.windowNumber, event.eventNumber == up.eventNumber { dispatchedUps += 1 }
                }
                return event
            }
            defer { if let upMonitor { NSEvent.removeMonitor(upMonitor) } }
            NSApp.postEvent(down, atStart: false)
            NSApp.postEvent(up, atStart: false)
            // Let the outer NSApp.run dispatch both events in order, including
            // its currentEvent and the button's original native tracking loop.
            try await Task.sleep(nanoseconds: 15_000_000)
            window.contentView?.layoutSubtreeIfNeeded()
            return dispatchedUps
        }
        func state(_ page: WallpaperLibraryPage) -> WallpaperLibraryPresentationState {
            var result = WallpaperLibraryPresentationState(); result.page = page; return result
        }
        func reference(_ index: Int) -> WallpaperReference { .init(provider: .videoLibrary, sourceID: "chrome-\(index)") }
        let values = (0..<80).map { index in
            WallpaperContentItem(reference: reference(index), providerReference: reference(index), locator: .init(mediaKind: .video),
                title: "封面 \(index)", kind: .video, publishedAvailability: .available, capabilities: [.play, .organize],
                metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
        }
        detail.present(grid)
        probe.apply(state(.videos))
        grid.update(page: .videos, items: values, selection: .init(), preferredColumns: 5,
            permitsDragging: false, scrollAnchor: nil)
        settle()
        let activationDeadline = Date().addingTimeInterval(5)
        while !NSApp.isActive || !window.isKeyWindow {
            precondition(Date() < activationDeadline, "Chrome fixture did not become active")
            settle()
        }
        checks["chrome-has-one-detail-host-and-real-unified-toolbar"] = detail.parent === chrome
            && grid.parent === detail && chrome.parent === container && grid.scrollView.contentInsets.top > 0

        let recovery = "恢复只读，原文件保持不变", operationError = "加入播放列表失败"
        probe.workspace.recoveryMessage = recovery
        var local = state(.videos); local.lastError = operationError; local.query.search = "unmatched"
        probe.apply(local); settle()
        checks["independent-recovery-and-operation-error-are-both-visible-and-accessible"] = label(recovery)?.accessibilityLabel() == recovery
            && label(operationError)?.accessibilityLabel() == operationError
        let oldClear = button("清除筛选")!
        send(oldClear)
        checks["current-empty-filter-action-routes-through-the-original-query-owner"] = probe.workspace.presentation.queries.count == 1
            && probe.workspace.presentation.queryState.search.isEmpty && probe.commands.imports == 0
        probe.workspace.presentation.state.page = .images
        send(oldClear)
        checks["current-button-with-a-late-page-change-cannot-target-the-new-page"] = probe.workspace.presentation.queries.count == 1
        probe.workspace.presentation.state.page = .videos
        probe.workspace.relationships = .init(revision: 0, resetEpoch: UUID(), migrationManifestID: nil,
            playlists: [], members: [], favorites: [], recent: [], aliases: [], locators: [])
        send(oldClear)
        checks["current-button-with-a-late-reset-cannot-run-the-old-action"] = probe.workspace.presentation.queries.count == 1
        probe.apply(state(.images)); settle(); send(oldClear)
        checks["removed-empty-button-cannot-run-an-action-at-the-same-new-index"] = probe.workspace.presentation.queries.count == 1
            && probe.commands.imports == 0 && button("导入图片") == nil
        probe.commands.canImport = false; probe.commands.canOrganize = false
        probe.apply(state(.videos)); settle()
        checks["readonly-local-empty-state-does-not-offer-a-fake-import"] = button("导入视频") == nil

        var searchedDirectory = state(.playlists); searchedDirectory.query.search = "没有这张列表"
        probe.workspace.catalog.catalog.loadedProviders = []
        directory.update(entries: [], covers: [:], preferredColumns: 5, permitsReordering: false, canEdit: false)
        detail.present(directory); probe.apply(searchedDirectory); settle()
        let directoryCollection = descendants(directory.view, NSCollectionView.self).first!
        checks["directory-zero-search-results-keep-the-fixed-create-cell-and-a-real-clear-action"] =
            directoryCollection.numberOfItems(inSection: 0) == 1 && label("没有符合条件的播放列表") != nil && button("清除搜索") != nil
            && label("正在载入壁纸…") == nil
        let emptyLabel = label("没有符合条件的播放列表")!
        let emptyStack = emptyLabel.superview!
        let emptyFrame = emptyStack.convert(emptyStack.bounds, to: nil)
        let bodySafe = detail.view.convert(detail.view.safeAreaRect, to: nil)
        checks["directory-zero-results-center-in-the-actual-body-below-both-notices"] = abs(emptyFrame.midY - bodySafe.midY) < 1
        let beforeDirectoryClear = probe.workspace.presentation.queries.count
        send(button("清除搜索")!)
        checks["directory-clear-search-preserves-the-page-and-uses-query-input"] = probe.workspace.presentation.page == .playlists
            && probe.workspace.presentation.queryState.search.isEmpty && probe.workspace.presentation.queries.count == beforeDirectoryClear + 1

        probe.workspace.catalog.catalog.loadedProviders = Set(WallpaperProvider.allCases)
        detail.present(grid); probe.apply(state(.playlist(UUID()))); settle()
        checks["empty-playlist-center-explains-header-add-without-a-duplicate-button"] = button("添加壁纸") == nil
            && label("从顶部添加壁纸，开始建立这个播放列表") != nil && probe.pickers.isEmpty

        for page in [WallpaperLibraryPage.workshop, .pixabay] {
            let source = NSViewController(); source.view = NSView()
            let sourceError = NSTextField(labelWithString: "来源自己的错误")
            source.view.addSubview(sourceError)
            detail.present(source)
            var remote = state(page); remote.lastError = operationError
            probe.apply(remote); settle()
            checks["remote-\(page)-keeps-source-feedback-and-both-cross-page-notices"] = source.parent === detail
                && sourceError.superview === source.view && label(recovery) != nil && label(operationError) != nil
                && label("正在载入壁纸…") == nil && descendants(chrome.view, NSButton.self).filter { !$0.isHiddenOrHasHiddenAncestor }.isEmpty
        }

        detail.present(grid)
        var populated = state(.downloads)
        populated.queryResult = .init(items: values, unfilteredCount: values.count)
        let warmFailure = "无法读取已下载 Pixabay 内容：权限不足"
        let coldFailure = "无法读取已下载 Pixabay 内容：首次扫描失败"
        probe.workspace.catalog.catalog.sourceScanStatuses[.pixabay] = .init(phase: .failed(message: warmFailure), hasSuccessfulScan: true)
        probe.apply(populated)
        grid.update(page: .downloads, items: values, selection: .init(), preferredColumns: 5, permitsDragging: false, scrollAnchor: nil)
        settle()
        let retry = button("重试载入")!
        checks["warm-scan-failure-keeps-real-cards-and-visible-retry-outside-empty-state"] = grid.collection.numberOfItems(inSection: 0) == values.count
            && label("刷新失败，保留现有内容。" + warmFailure) != nil && !retry.isHiddenOrHasHiddenAncestor
        send(retry)
        checks["scan-retry-delegates-once-to-the-original-source-owner"] = probe.pixabay.refreshes == 1
        probe.workspace.relationships = .init(revision: 0, resetEpoch: UUID(), migrationManifestID: nil,
            playlists: [], members: [], favorites: [], recent: [], aliases: [], locators: [])
        send(retry)
        checks["scan-retry-keeps-the-reset-epoch-captured-when-rendered"] = probe.pixabay.refreshes == 1
        probe.workspace.catalog.catalog.sourceScanStatuses[.pixabay] = .init(phase: .failed(message: coldFailure), hasSuccessfulScan: false)
        probe.workspace.catalog.catalog.loadedProviders.remove(.pixabay)
        probe.apply(state(.downloads)); settle()
        checks["first-scan-failure-does-not-pretend-to-be-permanent-loading-or-a-successful-empty-library"] =
            label(coldFailure) != nil && label("暂时没有可显示的壁纸") != nil && label("正在载入壁纸…") == nil
        probe.apply(state(.videos)); settle()
        checks["an-unrelated-online-scan-failure-does-not-leak-into-local-video-feedback"] =
            label(coldFailure) == nil && button("重试载入") == nil
        probe.apply(state(.pixabay)); settle()
        checks["remote-pixabay-does-not-replace-its-original-search-feedback-with-local-scan-feedback"] =
            label(coldFailure) == nil && label("暂时没有可显示的壁纸") == nil && button("重试载入") == nil
        probe.workspace.catalog.catalog.sourceScanStatuses[.pixabay] = .init(phase: .ready(warnings: ["同号文件已按来源规则合并"]), hasSuccessfulScan: true)
        probe.apply(populated); settle()
        checks["ready-scan-warnings-are-visible-with-cards-without-a-fake-retry"] = label("Pixabay 已下载内容：同号文件已按来源规则合并") != nil
            && button("重试载入") == nil
        probe.workspace.catalog.catalog.sourceScanStatuses[.pixabay] = .init(phase: .loading, hasSuccessfulScan: true)
        probe.apply(populated); settle()
        checks["warm-loading-notice-preserves-published-card-inputs"] = label("正在刷新 Pixabay 已下载的壁纸…") != nil
            && grid.collection.numberOfItems(inSection: 0) == values.count

        // Keep only a real notice and retry while inspecting; the actual native
        // Inspector overlay, not a lookalike view, must pass this button through.
        probe.workspace.recoveryMessage = nil
        probe.workspace.catalog.catalog.sourceScanStatuses[.pixabay] = .init(phase: .failed(message: coldFailure), hasSuccessfulScan: false)
        probe.apply(populated); settle()
        let activeRetry = button("重试载入")!
        checks["first-failure-with-entry-only-publication-keeps-real-local-cards"] =
            grid.collection.numberOfItems(inSection: 0) == values.count && label(coldFailure) != nil
        window.setContentSize(NSSize(width: 680, height: 700)); settle()
        container.setOverlayVisible(true, panelWidth: 360, panelOffset: 0, animated: false)
        settle()
        let retryPoint = activeRetry.convert(NSPoint(x: activeRetry.bounds.midX, y: activeRetry.bounds.midY), to: nil)
        let hit = container.view.hitTest(container.view.superview!.convert(retryPoint, from: nil))
        checks["real-open-inspector-keeps-the-current-notice-button-hittable"] = hit === activeRetry
            && chrome.permitsNoticeInteraction(at: retryPoint)
        let retryRect = activeRetry.convert(activeRetry.bounds, to: nil)
        let panelRect = inspector.view.convert(inspector.view.bounds, to: nil)
        checks["narrow-detail-width-keeps-the-whole-notice-action-clear-of-the-inspector-panel"] =
            activeRetry.bounds.width > 0 && retryRect.maxX < panelRect.minX && window.contentLayoutRect.contains(retryRect)
        let panelPoint = inspector.view.convert(NSPoint(x: inspector.view.bounds.midX, y: inspector.view.bounds.midY), to: nil)
        let panelHit = container.view.hitTest(container.view.superview!.convert(panelPoint, from: nil))
        checks["notice-passthrough-does-not-take-inspector-panel-controls-or-blank-dimming"] =
            panelHit.map { $0 === inspector.view || $0.isDescendant(of: inspector.view) } == true
            && !chrome.permitsNoticeInteraction(at: panelPoint)
        let beforeRetry = probe.pixabay.refreshes
        var closeRequests = 0
        let closeObserver = NotificationCenter.default.addObserver(forName: .inspectorHostCloseRequested, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { closeRequests += 1 }
        }
        defer { NotificationCenter.default.removeObserver(closeObserver) }
        // Settle already-enqueued delivery before the first native tracking
        // operation. These are single clicks, without retries or focus changes.
        try await Task.sleep(nanoseconds: 15_000_000)
        FileHandle.standardError.write(Data("Chrome retry before: refreshes=\(probe.pixabay.refreshes), expectedBase=\(beforeRetry), closes=\(closeRequests), responder=\(String(describing: window.firstResponder))\n".utf8))
        let retryUps = try await click(retryPoint)
        FileHandle.standardError.write(Data("Chrome retry after: refreshes=\(probe.pixabay.refreshes), closes=\(closeRequests), dispatchedUps=\(retryUps)\n".utf8))
        checks["open-inspector-native-notice-click-executes-once-without-closing-inspector"] =
            probe.pixabay.refreshes == beforeRetry + 1 && closeRequests == 0
        let blank = detail.view.convert(NSPoint(x: 40, y: detail.view.bounds.midY), to: nil)
        let blankHit = container.view.hitTest(container.view.superview!.convert(blank, from: nil))
        checks["ordinary-content-blank-keeps-the-original-inspector-dimming-hit"] = blankHit is InspectorOverlayPassthroughView
            && !chrome.permitsNoticeInteraction(at: blank)
        let blankUps = try await click(blank)
        FileHandle.standardError.write(Data("Chrome blank after: refreshes=\(probe.pixabay.refreshes), closes=\(closeRequests), dispatchedUps=\(blankUps)\n".utf8))
        checks["ordinary-content-blank-click-still-sends-only-the-original-inspector-close"] = closeRequests == 1
            && probe.pixabay.refreshes == beforeRetry + 1
        let inspectorWheel = NSEvent(cgEvent: CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -24, wheel2: 0, wheel3: 0)!)!
        (blankHit as! InspectorOverlayPassthroughView).scrollWheel(with: inspectorWheel)
        FileHandle.standardError.write(Data("Chrome wheel after: refreshes=\(probe.pixabay.refreshes), closes=\(closeRequests)\n".utf8))
        checks["original-inspector-wheel-handler-still-closes-without-running-a-notice-action"] = closeRequests == 2
            && probe.pixabay.refreshes == beforeRetry + 1
        activeRetry.isEnabled = false
        checks["disabled-notice-button-does-not-cross-the-inspector-surface"] = !chrome.permitsNoticeInteraction(at: retryPoint)
        activeRetry.isEnabled = true
        probe.apply(state(.videos)); settle(); send(activeRetry)
        FileHandle.standardError.write(Data("Chrome removed notice after: refreshes=\(probe.pixabay.refreshes), closes=\(closeRequests), permits=\(chrome.permitsNoticeInteraction(at: retryPoint))\n".utf8))
        checks["removed-notice-button-cannot-run-or-retain-a-passthrough-region"] = probe.pixabay.refreshes == beforeRetry + 1
            && !chrome.permitsNoticeInteraction(at: retryPoint)
        container.setOverlayVisible(false, panelWidth: 0, panelOffset: 0, animated: false)
        window.setContentSize(NSSize(width: 1000, height: 700)); settle()

        probe.workspace.catalog.catalog.sourceScanStatuses.removeValue(forKey: .pixabay)
        probe.workspace.catalog.catalog.loadedProviders = Set(WallpaperProvider.allCases)
        var filled = state(.videos); filled.queryResult = .init(items: values, unfilteredCount: values.count)
        probe.apply(filled); settle()
        grid.update(page: .videos, items: values, selection: .init(), preferredColumns: 5, permitsDragging: false, scrollAnchor: nil, scrollAtTop: true)
        grid.scrollToTop(animated: false); settle()
        let flow = grid.collection.collectionViewLayout as! NSCollectionViewFlowLayout
        func firstCardTop() -> CGFloat? { grid.collection.item(at: IndexPath(item: 0, section: 0)).map { $0.view.convert($0.view.bounds, to: nil).maxY } }
        checks["without-notices-the-first-card-retains-eight-points-below-native-toolbar"] = firstCardTop().map { abs($0 - (window.contentLayoutRect.maxY - 8)) < 1 } == true
        let firstCardWithoutNotice = firstCardTop()
        probe.workspace.recoveryMessage = recovery; probe.apply(filled); settle()
        grid.scrollToTop(animated: false); settle()
        checks["bottom-capsule-preserves-first-card-safe-inset-and-the-same-grid-top"] = firstCardTop().map {
            abs($0 - (window.contentLayoutRect.maxY - 8)) < 1 && $0 == firstCardWithoutNotice
        } == true
        let capsule = descendants(chrome.view, WallpaperGridNoticeView.self).first!
        let capsuleFrame = capsule.convert(capsule.bounds, to: nil)
        checks["transient-glass-capsule-is-centered-at-grid-bottom-without-changing-body-geometry"] =
            abs(capsuleFrame.midX - detail.view.convert(detail.view.bounds, to: nil).midX) < 1
            && abs(capsuleFrame.minY - (chrome.view.convert(chrome.view.safeAreaRect, to: nil).minY + 20)) < 1
        let frame = flow.layoutAttributesForItem(at: IndexPath(item: 24, section: 0))!.frame
        grid.scrollView.contentView.scroll(to: NSPoint(x: 0, y: frame.minY + 13 - grid.scrollView.contentInsets.top)); settle()
        let viewportBefore = grid.scrollView.gridViewportRect
        let attributes = flow.layoutAttributesForElements(in: viewportBefore).filter { $0.representedElementCategory == .item && $0.frame.intersects(viewportBefore) }
        let anchor = attributes.min { $0.frame.minY == $1.frame.minY ? $0.frame.minX < $1.frame.minX : $0.frame.minY < $1.frame.minY }!
        guard let anchorPath = anchor.indexPath else { preconditionFailure("Visible native anchor has no item index path") }
        let anchorReference = values[anchorPath.item].reference
        let offset = anchor.frame.minY - viewportBefore.minY
        probe.workspace.recoveryMessage = nil; probe.apply(filled); settle()
        let after = flow.layoutAttributesForItem(at: anchorPath)!.frame.minY - grid.scrollView.gridViewportRect.minY
        checks["notice-removal-preserves-the-real-middle-reference-and-relative-offset"] = grid.items[anchorPath.item].reference == anchorReference
            && abs(after - offset) < 1
        probe.workspace.recoveryMessage = recovery; probe.apply(filled); settle()
        let restoredOffset = flow.layoutAttributesForItem(at: anchorPath)!.frame.minY - grid.scrollView.gridViewportRect.minY
        checks["notice-reappearance-preserves-the-same-middle-anchor-without-a-second-owner"] = abs(restoredOffset - offset) < 1
        probe.workspace.recoveryMessage = nil
        probe.apply(filled); settle()
        let countFrame = grid.collection.frame, countOrigin = grid.scrollView.contentView.bounds.origin
        let countInsets = grid.scrollView.contentInsets
        for page in [WallpaperLibraryPage.videos, .images, .downloads, .recent, .favorites] {
            var partial = state(page)
            partial.queryResult = .init(items: Array(values.prefix(2)), unfilteredCount: 80)
            probe.apply(partial)
            checks["pull-count-\(page)-uses-existing-visible-and-total-result"] = grid.scrollView.pullCountText == "显示 2 / 共 80 张壁纸"
                && grid.scrollView.accessibilityHelp() == grid.scrollView.pullCountText
                && label("显示 2 / 共 80 张壁纸") == nil
        }
        checks["count-projection-does-not-resize-scroll-document-insets-or-middle-anchor"] = grid.collection.frame == countFrame
            && grid.scrollView.contentView.bounds.origin == countOrigin
            && grid.scrollView.contentInsets.top == countInsets.top && grid.scrollView.contentInsets.bottom == countInsets.bottom
        probe.workspace.catalog.catalog.loadedProviders = []
        probe.apply(state(.videos))
        checks["initial-local-source-count-is-unknown-until-its-existing-readiness"] = grid.scrollView.pullCountText == nil
        probe.workspace.catalog.catalog.loadedProviders.insert(.videoLibrary)
        probe.apply(state(.videos))
        checks["successful-empty-local-source-has-accessible-zero-without-visible-label"] = grid.scrollView.pullCountText == "共 0 张壁纸"
            && grid.scrollView.accessibilityHelp() == "共 0 张壁纸" && label("共 0 张壁纸") == nil
        var partialDownloads = state(.downloads)
        partialDownloads.queryResult = .init(items: Array(values.prefix(3)), unfilteredCount: 3)
        probe.workspace.catalog.catalog.loadedProviders = [.steamWorkshop]
        probe.apply(partialDownloads)
        checks["one-ready-download-provider-reports-loaded-items-without-claiming-a-complete-total"] = grid.scrollView.pullCountText == "已加载 3 张壁纸"
        partialDownloads.query.providers = [.steamWorkshop]
        partialDownloads.queryResult = .init(items: Array(values.prefix(1)), unfilteredCount: 3)
        probe.apply(partialDownloads)
        checks["provider-filter-does-not-misclassify-an-unfiltered-partial-download-total-as-complete"] = grid.scrollView.pullCountText == "显示 1 / 已加载 3 张壁纸"
        probe.workspace.catalog.catalog.sourceScanStatuses[.pixabay] = .init(phase: .failed(message: coldFailure), hasSuccessfulScan: false)
        partialDownloads.query.providers = []
        partialDownloads.queryResult = .init(items: Array(values.prefix(3)), unfilteredCount: 3)
        probe.apply(partialDownloads)
        checks["first-failed-other-provider-keeps-the-count-explicitly-partial"] = grid.scrollView.pullCountText == "已加载 3 张壁纸"
        probe.apply(state(.downloads))
        checks["zero-items-with-an-unknown-or-first-failed-provider-has-no-fabricated-total"] = grid.scrollView.pullCountText == nil
        probe.workspace.catalog.catalog.loadedProviders.insert(.pixabay)
        probe.workspace.catalog.catalog.sourceScanStatuses.removeValue(forKey: .pixabay)
        partialDownloads.query.providers = [.steamWorkshop]
        partialDownloads.queryResult = .init(items: Array(values.prefix(1)), unfilteredCount: 3)
        probe.apply(partialDownloads)
        checks["older-two-download-providers-do-not-claim-the-new-image-scan-is-ready"] = grid.scrollView.pullCountText == "显示 1 / 已加载 3 张壁纸"
        probe.workspace.catalog.catalog.loadedProviders.formUnion([.wallhaven, .pixiv])
        probe.apply(partialDownloads)
        checks["all-ready-download-providers-can-report-the-complete-unfiltered-total"] = grid.scrollView.pullCountText == "显示 1 / 共 3 张壁纸"
        probe.apply(state(.downloads))
        checks["all-successful-empty-download-providers-have-known-zero"] = grid.scrollView.pullCountText == "共 0 张壁纸"
        var adultOnly = state(.downloads)
        adultOnly.query = .init(providers: [.steamWorkshop, .pixiv], kinds: [.image, .scene], statuses: [.playable, .unavailable], sort: .name, preferredColumns: 4, showsAdultContent: false)
        probe.apply(adultOnly); settle()
        checks["all-adult-downloads-hidden-by-filter-have-a-recoverable-filtered-empty-state"] = label("没有符合条件的壁纸") != nil
            && label("下载的壁纸将显示在这里") == nil && button("清除筛选") != nil
        let beforeAdultClear = probe.workspace.presentation.queries.count
        send(button("清除筛选")!)
        checks["explicit-clear-restores-download-adult-default-and-preserves-sort-density"] = probe.workspace.presentation.queries.count == beforeAdultClear + 1
            && probe.workspace.presentation.queryState.showsAdultContent && probe.workspace.presentation.queryState.statuses.isEmpty
            && probe.workspace.presentation.queryState.providers.isEmpty && probe.workspace.presentation.queryState.kinds.isEmpty
            && probe.workspace.presentation.queryState.sort == .name && probe.workspace.presentation.queryState.preferredColumns == 4
        var unrelatedAdultFlag = state(.favorites); unrelatedAdultFlag.query.showsAdultContent = false
        probe.apply(unrelatedAdultFlag); settle()
        checks["download-only-adult-flag-does-not-filter-an-unrelated-relationship-empty-state"] = label("标记为特别喜爱的壁纸将显示在这里") != nil
            && button("清除筛选") == nil
        let manifestError = "Controlled shared image manifest failure"
        let imageFailure = WallpaperSourceScanStatus(phase: .failed(message: manifestError), hasSuccessfulScan: false)
        probe.workspace.catalog.catalog.sourceScanStatuses[.wallhaven] = imageFailure
        probe.workspace.catalog.catalog.sourceScanStatuses[.pixiv] = imageFailure
        probe.apply(state(.downloads)); settle()
        let imageRetries = descendants(chrome.view, NSButton.self).filter { $0.title == "重试载入在线图片" }
        let imageRefreshes = OnlineImageLibrary.shared.refreshes
        imageRetries.first?.performClick(nil)
        checks["shared-image-manifest-failure-uses-one-notice-and-the-local-refresh-owner"] = imageRetries.count == 1
            && descendants(chrome.view, NSTextField.self).filter { $0.stringValue == manifestError }.count == 1
            && OnlineImageLibrary.shared.refreshes == imageRefreshes + 1
        probe.workspace.catalog.catalog.sourceScanStatuses.removeValue(forKey: .wallhaven)
        probe.workspace.catalog.catalog.sourceScanStatuses.removeValue(forKey: .pixiv)
        probe.workspace.catalog.catalog.loadedProviders = []
        for page in [WallpaperLibraryPage.recent, .favorites] {
            var relation = state(page)
            relation.queryResult = .init(items: Array(values.prefix(2)), unfilteredCount: 3)
            probe.apply(relation)
            checks["relation-count-\(page)-remains-known-before-source-hydration"] = grid.scrollView.pullCountText == "显示 2 / 共 3 张壁纸"
        }
        let previousRelationCount = grid.scrollView.pullCountText
        var playlistCount = state(.playlist(UUID()))
        playlistCount.queryResult = .init(items: Array(values.prefix(2)), unfilteredCount: 3)
        probe.apply(playlistCount)
        checks["playlist-header-count-scope-clears-the-previous-page-pull-count"] = previousRelationCount == "显示 2 / 共 3 张壁纸"
            && grid.scrollView.pullCountText == nil && grid.scrollView.accessibilityHelp() == nil
            && label("显示 2 / 共 3 张壁纸") == nil
        let lists = (0..<3).map { WallpaperPlaylist(name: "计数 \($0)", sidebarRank: $0) }
        probe.workspace.relationships = .init(revision: 1, resetEpoch: UUID(), migrationManifestID: nil,
            playlists: lists, members: [], favorites: [], recent: [], aliases: [], locators: [])
        var filteredDirectory = state(.playlists)
        filteredDirectory.directoryEntries = [.init(id: lists[0].id, name: lists[0].name, count: 0, coverReference: nil)]
        probe.apply(filteredDirectory)
        let directoryScroll = descendants(directory.view, WallpaperGridScrollView.self).first!
        checks["directory-count-uses-actual-playlist-snapshot-and-filtered-entries"] = directoryScroll.pullCountText == "显示 1 / 共 3 个播放列表"
            && directoryScroll.accessibilityHelp() == directoryScroll.pullCountText && label("显示 1 / 共 3 个播放列表") == nil

        probe.workspace.catalog.catalog.loadedProviders = Set(WallpaperProvider.allCases)
        probe.commands.canImport = true
        detail.present(grid)
        grid.update(page: .videos, items: [], selection: .init(), preferredColumns: 5,
            permitsDragging: false, scrollAnchor: nil, scrollAtTop: true)
        probe.apply(state(.videos)); settle()
        let importLabel = label("导入视频，建立你的壁纸资料库")!
        let importStack = importLabel.superview as! NSStackView
        let importIcon = importStack.arrangedSubviews.compactMap { $0 as? NSImageView }.first!
        let iconRect = importIcon.convert(importIcon.bounds, to: nil)
        let labelRect = importLabel.convert(importLabel.bounds, to: nil)
        let lower = iconRect.midY < labelRect.midY ? iconRect : labelRect
        let upper = iconRect.midY < labelRect.midY ? labelRect : iconRect
        precondition(upper.minY > lower.maxY, "Empty-state icon and label must have a real gap")
        func nativeHit(_ point: NSPoint) -> NSView? {
            guard let content = window.contentView, let parent = content.superview else { return nil }
            return content.hitTest(parent.convert(point, from: nil))
        }
        func wheel(cgPhase: Int64) -> NSEvent {
            let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                wheel1: -24, wheel2: 0, wheel3: 0)!
            // CGScrollPhase began/ended are 1/4, unlike NSEvent.Phase raw values.
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: cgPhase)
            return NSEvent(cgEvent: event)!
        }
        let began = wheel(cgPhase: 1), ended = wheel(cgPhase: 4)
        precondition(began.scrollingDeltaY != 0 && began.phase == .began && ended.phase == .ended,
            "Empty-state wheel fixture needs real nonzero scroll phases")
        try await Task.sleep(nanoseconds: 160_000_000)
        let passivePoints: [(String, NSPoint)] = [
            ("icon", NSPoint(x: iconRect.midX, y: iconRect.midY)),
            ("label", NSPoint(x: labelRect.midX, y: labelRect.midY)),
            ("gap", NSPoint(x: labelRect.midX, y: (lower.maxY + upper.minY) * 0.5))
        ]
        let importsBeforeWheel = probe.commands.imports
        for (name, point) in passivePoints {
            let target = nativeHit(point)
            let reachesScroll = target.map { $0 === grid.scrollView || $0.isDescendant(of: grid.scrollView) } == true
            checks["empty-\(name)-window-hit-passes-through-to-the-real-empty-grid"] = reachesScroll
                && grid.collection.numberOfItems(inSection: 0) == 0 && window.contentLayoutRect.contains(point)
            let wasIdle = !grid.scrollView.isGridScrolling
            // Dispatch once from the actual window hit into the original
            // responder chain. This is a native view-route/component check,
            // not a claim that the event came from a hardware wheel.
            target?.scrollWheel(with: began)
            let reachedWheel = grid.scrollView.isGridScrolling
            target?.scrollWheel(with: ended)
            try await Task.sleep(nanoseconds: 160_000_000)
            checks["empty-\(name)-hit-reaches-original-wheel-and-settlement-without-an-action"] =
                wasIdle && reachedWheel && !grid.scrollView.isGridScrolling && probe.commands.imports == importsBeforeWheel
        }
        checks["local-empty-state-has-only-icon-and-copy-without-duplicate-import-or-browse-actions"] =
            button("导入视频") == nil && button("浏览创意工坊") == nil && button("浏览 Pixabay") == nil
            && descendants(chrome.view, NSButton.self).filter { !$0.isHiddenOrHasHiddenAncestor }.isEmpty
        var filteredForModal = state(.videos); filteredForModal.query.search = "unmatched"
        probe.apply(filteredForModal); settle()
        let initialClearButton = button("清除筛选")!
        let clearPoint = initialClearButton.convert(NSPoint(x: initialClearButton.bounds.midX, y: initialClearButton.bounds.midY), to: nil)
        checks["empty-filter-control-keeps-its-native-hit-target"] = nativeHit(clearPoint) === initialClearButton
        let beforeNativeClear = probe.workspace.presentation.queries.count
        _ = try await click(clearPoint)
        checks["empty-filter-control-native-click-clears-the-original-query-exactly-once"] =
            probe.workspace.presentation.queries.count == beforeNativeClear + 1 && probe.workspace.presentation.queryState.search.isEmpty
            && probe.commands.imports == importsBeforeWheel
        probe.apply(filteredForModal); settle()
        let clearButton = button("清除筛选")!
        func makeInputModal() -> WallpaperLibraryModalPanel {
            let panel = WallpaperLibraryModalPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 240),
                styleMask: [.borderless], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.contentView = WallpaperPanelSurface(frame: NSRect(x: 0, y: 0, width: 360, height: 240))
            return panel
        }
        let clearModal = makeInputModal()
        let clearModalPresented = WallpaperLibrarySheetPresentation.present(clearModal, in: window)
        settle()
        checks["chrome-retained-filter-test-uses-the-current-page-and-real-owned-sheet"] = clearModalPresented
            && clearModal.sheetParent === window && clearModal.isKeyWindow && clearModal.isAccessibilityModal()
            && probe.workspace.presentation.page == .videos && clearButton.isEnabled && clearButton.window === window
            && !WallpaperLibrarySheetPresentation.permitsInput(in: window)
        let beforeBlockedClear = probe.workspace.presentation.queries.count
        clearButton.performClick(nil)
        _ = clearButton.accessibilityPerformPress()
        try await Task.sleep(nanoseconds: 160_000_000)
        checks["owned-sheet-revokes-current-retained-chrome-filter-button-and-accessibility-action"] =
            probe.workspace.presentation.queries.count == beforeBlockedClear && clearModal.isVisible && clearModal.sheetParent === window
        clearModal.close()
        try await Task.sleep(nanoseconds: 160_000_000)
        let beforeRestoredClear = probe.workspace.presentation.queries.count
        _ = clearButton.accessibilityPerformPress()
        try await Task.sleep(nanoseconds: 160_000_000)
        // Native AX's return value is not the business result: observe the
        // actual query write and its exact value through the original owner.
        checks["owned-sheet-close-restores-the-same-chrome-filter-action-exactly-once"] =
            clearModal.sheetParent == nil && !clearModal.isVisible && !clearModal.isAccessibilityModal() && window.isKeyWindow
            && WallpaperLibrarySheetPresentation.permitsInput(in: window)
            && probe.workspace.presentation.queries.count == beforeRestoredClear + 1
            && probe.workspace.presentation.queryState.search.isEmpty && probe.commands.imports == importsBeforeWheel

        let headerPlaylist = lists[0]
        probe.allEntries = [.init(id: headerPlaylist.id, name: headerPlaylist.name,
            count: values.count, coverReference: nil)]
        var headerState = state(.playlist(headerPlaylist.id))
        headerState.queryResult = .init(items: values, unfilteredCount: values.count)
        probe.applyHeader(headerState)
        grid.update(page: headerState.page, items: values, selection: .init(), preferredColumns: 5,
            permitsDragging: false, scrollAnchor: nil, scrollAtTop: true,
            header: (probe.header, { probe.header.preferredHeight(forWidth: $0) }))
        settle()
        let headerButtons = descendants(probe.header, NSButton.self)
        let retainedPlay = headerButtons.first { $0.tag == 0 }!
        let retainedRandom = headerButtons.first { $0.tag == 1 }!
        retainedPlay.performClick(nil); retainedRandom.performClick(nil)
        checks["actual-composition-header-factory-keeps-native-play-and-random-actions"] =
            probe.commands.displayedPlayRequests == [false, true] && headerButtons.count == 3
            && headerButtons.allSatisfy { $0.bounds.height == 28 }
        let modal = makeInputModal()
        func traceHeaderAction(_ stage: String, playAX: Bool? = nil, randomAX: Bool? = nil) {
            var receipt: [String: Any] = ["stage": stage, "requests": probe.commands.displayedPlayRequests,
                "modalParentMatches": modal.sheetParent === window, "modalVisible": modal.isVisible,
                "modalKey": modal.isKeyWindow, "windowKey": window.isKeyWindow,
                "modalAccessibilityModal": modal.isAccessibilityModal(),
                "windowVisible": window.isVisible, "keyWindowNumber": NSApp.keyWindow?.windowNumber ?? -1,
                "hasSheet": window.attachedSheet != nil, "modalWindowNumber": NSApp.modalWindow?.windowNumber ?? -1,
                "hostPermitsInput": WallpaperLibrarySheetPresentation.permitsInput(in: window),
                "playEnabled": retainedPlay.isEnabled, "randomEnabled": retainedRandom.isEnabled,
                "playMounted": retainedPlay.window === window, "randomMounted": retainedRandom.window === window,
                "playHighlighted": retainedPlay.cell?.isHighlighted == true,
                "randomHighlighted": retainedRandom.cell?.isHighlighted == true]
            if let playAX { receipt["playAX"] = playAX }
            if let randomAX { receipt["randomAX"] = randomAX }
            FileHandle.standardError.write(Data("chrome-header-action ".utf8)
                + (try! JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys])) + Data("\n".utf8))
        }
        let presented = WallpaperLibrarySheetPresentation.present(modal, in: window)
        settle()
        checks["header-held-action-test-uses-the-real-owned-modal-input-domain"] = presented
            && modal.sheetParent === window && modal.isKeyWindow && modal.isVisible && window.attachedSheet === modal
            && modal.isAccessibilityModal()
            && !WallpaperLibrarySheetPresentation.permitsInput(in: window)
            && WallpaperLibrarySheetPresentation.permitsInput(in: modal)
        let beforeBlockedHeader = probe.commands.displayedPlayRequests
        retainedPlay.performClick(nil); retainedRandom.performClick(nil)
        checks["owned-sheet-blocks-retained-real-header-play-and-random-buttons"] =
            retainedPlay.isEnabled && retainedRandom.isEnabled && retainedPlay.window === window && retainedRandom.window === window
            && probe.commands.displayedPlayRequests == beforeBlockedHeader
        let blockedPlayAX = retainedPlay.accessibilityPerformPress(), blockedRandomAX = retainedRandom.accessibilityPerformPress()
        traceHeaderAction("owned-sheet-held-immediate", playAX: blockedPlayAX, randomAX: blockedRandomAX)
        try await Task.sleep(nanoseconds: 160_000_000)
        traceHeaderAction("owned-sheet-held-after-one-native-queue-turn", playAX: blockedPlayAX, randomAX: blockedRandomAX)
        checks["owned-sheet-blocks-retained-real-header-accessibility-presses"] =
            probe.commands.displayedPlayRequests == beforeBlockedHeader && modal.isKeyWindow
            && modal.isVisible && modal.sheetParent === window
        traceHeaderAction("before-close")
        modal.close(); settle()
        traceHeaderAction("after-close-nested-settle-before-performClick")
        retainedPlay.performClick(nil); retainedRandom.performClick(nil)
        traceHeaderAction("after-restored-performClick-before-AX")
        let playAX = retainedPlay.accessibilityPerformPress(), randomAX = retainedRandom.accessibilityPerformPress()
        traceHeaderAction("after-restored-AX-immediate", playAX: playAX, randomAX: randomAX)
        try await Task.sleep(nanoseconds: 160_000_000)
        traceHeaderAction("after-restored-one-native-queue-turn", playAX: playAX, randomAX: randomAX)
        checks["owned-sheet-close-restores-the-same-header-buttons-and-accessibility-actions"] =
            modal.sheetParent == nil && !modal.isVisible && !modal.isAccessibilityModal() && window.isKeyWindow
            && WallpaperLibrarySheetPresentation.permitsInput(in: window)
            && probe.commands.displayedPlayRequests == [false, true, false, true, false, true]
        for page in [WallpaperLibraryPage.videos, .images, .downloads, .recent, .favorites, .playlist(headerPlaylist.id), .playlists] {
            probe.apply(state(page)); settle()
            checks["local-page-has-no-refresh-request-" + page.persistenceKey] = grid.scrollView.onRefresh == nil
                && descendants(directory.view, WallpaperGridScrollView.self).allSatisfy { $0.onRefresh == nil }
            #if compiler(>=6.4)
            if #available(macOS 27.0, *) {
                checks["local-page-has-no-native-refresh-controller-" + page.persistenceKey] = grid.scrollView.refreshController == nil
                    && descendants(directory.view, WallpaperGridScrollView.self).allSatisfy { $0.refreshController == nil }
            }
            #endif
        }
        do {
            let grid = WallpaperLibraryGridController { collection, path, _, _ in collection.makeItem(withIdentifier: reuse, for: path) }
            grid.loadViewIfNeeded(); grid.collection.register(ChromeCell.self, forItemWithIdentifier: reuse)
            let window = NSWindow(contentRect: NSRect(x: 220, y: 170, width: 900, height: 650),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentViewController = grid
            window.makeKeyAndOrderFront(nil)
            defer { window.orderOut(nil); window.close() }
            func settle() {
                window.contentView?.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }
            func show(_ page: WallpaperLibraryPage, _ items: [WallpaperContentItem], _ selection: WallpaperLibrarySelectionState) {
                grid.update(page: page, items: items, selection: selection, preferredColumns: 5,
                    permitsDragging: false, scrollAnchor: nil)
                let deadline = Date().addingTimeInterval(3)
                while Date() < deadline && (grid.selection.sessionID != selection.sessionID || grid.items != items
                    || grid.collection.numberOfItems(inSection: 0) != items.count) { settle() }
                precondition(grid.selection.sessionID == selection.sessionID && grid.items == items
                    && grid.collection.numberOfItems(inSection: 0) == items.count, "Selection fixture did not finish the native grid update")
            }
            show(.videos, values, .init()); settle()
            // Real collection/menu validation must permit Cmd+A before selection
            // mode begins. Only the App command's accepted selection is a leaf.
            let previousMenu = NSApp.mainMenu, menu = NSMenu(), editMenu = NSMenu()
            let editEntry = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
            editEntry.submenu = editMenu; menu.addItem(editEntry)
            let all = NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
            all.target = nil; all.keyEquivalentModifierMask = .command; editMenu.addItem(all)
            NSApp.mainMenu = menu
            var allCommands = 0
            grid.onSelectAll = {
                allCommands += 1
                var selected = WallpaperLibrarySelectionState()
                selected.references = Set(values.map(\.reference)); selected.focusedReference = values.first?.reference
                selected.isSelecting = true
                show(.videos, values, selected)
            }
            precondition(window.makeFirstResponder(grid.collection))
            editMenu.update()
            checks["ordinary-real-grid-validates-native-select-all-before-selection-mode"] = all.isEnabled
                && !grid.collection.allowsMultipleSelection && !grid.selection.isSelecting
            let selectAllKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0)!
            if !menu.performKeyEquivalent(with: selectAllKey) { NSApp.sendEvent(selectAllKey) }
            settle()
            checks["ordinary-real-grid-native-command-a-enters-selection-and-selects-current-projection-once"] = allCommands == 1
                && grid.selection.isSelecting && grid.selection.references == Set(values.map(\.reference))
                && grid.collection.selectionIndexPaths.count == values.count && grid.collection.allowsMultipleSelection
            show(.videos, [], .init())
            settle(); editMenu.update()
            grid.collection.selectAll(nil)
            checks["empty-real-grid-disables-select-all-and-refuses-a-held-native-action"] = !all.isEnabled && allCommands == 1
            show(.videos, values, .init())
            settle()
            let blockingPanel = WallpaperLibraryModalPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 150),
                styleMask: [.borderless], backing: .buffered, defer: false)
            blockingPanel.isReleasedWhenClosed = false
            precondition(WallpaperLibrarySheetPresentation.present(blockingPanel, in: window))
            settle()
            grid.collection.selectAll(nil)
            checks["native-child-sheet-revokes-the-background-grid-select-all"] = !grid.collection.validateMenuItem(all)
                && allCommands == 1 && !grid.selection.isSelecting
            blockingPanel.close(); settle()
            let restoredKeyDeadline = Date().addingTimeInterval(3)
            while !window.isKeyWindow && Date() < restoredKeyDeadline { settle() }
            precondition(window.isKeyWindow, "Selection fixture host did not regain native sheet input")
            grid.onSelectAll = nil
            var pickerSelection = WallpaperLibrarySelectionState(); pickerSelection.isSelecting = true
            var pickerSelections: [Set<WallpaperReference>] = []
            grid.onSelection = { refs, _ in pickerSelections.append(refs); return UUID() }
            show(.playlist(UUID()), values, pickerSelection)
            settle(); precondition(window.makeFirstResponder(grid.collection)); editMenu.update()
            if !menu.performKeyEquivalent(with: selectAllKey) { NSApp.sendEvent(selectAllKey) }
            settle()
            checks["picker-style-selection-grid-keeps-default-native-command-a-without-an-app-command"] = all.isEnabled
                && pickerSelections == [Set(values.map(\.reference))] && grid.selection.references == Set(values.map(\.reference))
            show(.wallhaven, values, .init())
            settle(); editMenu.update(); grid.collection.selectAll(nil)
            checks["online-grid-without-a-selection-command-keeps-native-select-all-disabled"] = !all.isEnabled
                && pickerSelections.count == 1 && grid.selection.references.isEmpty
            grid.onSelection = nil; NSApp.mainMenu = previousMenu
            show(.videos, values, .init())
            settle()
        }
        print(String(data: try! JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
