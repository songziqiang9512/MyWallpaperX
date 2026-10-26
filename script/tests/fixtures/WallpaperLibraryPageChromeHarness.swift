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
@MainActor private final class ChromeOnline {
    var refreshes = 0
    func refreshDownloadedContent() { refreshes += 1 }
}
@MainActor private final class WallpaperLibraryWindowComposition {
    let workspace = ChromeWorkspace(), commands = ChromeCommands(), online = ChromeOnline()
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
            permitsNoticeInteraction: { [weak chrome] in chrome?.permitsNoticeInteraction(at: $0) ?? false })
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
        var local = state(.videos); local.lastError = operationError
        probe.apply(local); settle()
        checks["independent-recovery-and-operation-error-are-both-visible-and-accessible"] = label(recovery)?.accessibilityLabel() == recovery
            && label(operationError)?.accessibilityLabel() == operationError
        let oldImport = button("导入视频")!
        send(oldImport)
        checks["current-empty-action-routes-through-the-original-command"] = probe.commands.imports == 1
        probe.workspace.presentation.state.page = .images
        send(oldImport)
        checks["current-button-with-a-late-page-change-cannot-target-the-new-page"] = probe.commands.imports == 1
        probe.workspace.presentation.state.page = .videos
        probe.workspace.relationships = .init(revision: 0, resetEpoch: UUID(), migrationManifestID: nil,
            playlists: [], members: [], favorites: [], recent: [], aliases: [], locators: [])
        send(oldImport)
        checks["current-button-with-a-late-reset-cannot-run-the-old-action"] = probe.commands.imports == 1
        probe.apply(state(.images)); settle(); send(oldImport)
        checks["removed-empty-button-cannot-run-an-action-at-the-same-new-index"] = probe.commands.imports == 1
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
        send(button("清除搜索")!)
        checks["directory-clear-search-preserves-the-page-and-uses-query-input"] = probe.workspace.presentation.page == .playlists
            && probe.workspace.presentation.queryState.search.isEmpty && probe.workspace.presentation.queries.count == 1

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
        checks["scan-retry-delegates-once-to-the-original-source-owner"] = probe.online.refreshes == 1
        probe.workspace.relationships = .init(revision: 0, resetEpoch: UUID(), migrationManifestID: nil,
            playlists: [], members: [], favorites: [], recent: [], aliases: [], locators: [])
        send(retry)
        checks["scan-retry-keeps-the-reset-epoch-captured-when-rendered"] = probe.online.refreshes == 1
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
        let beforeRetry = probe.online.refreshes
        var closeRequests = 0
        let closeObserver = NotificationCenter.default.addObserver(forName: .inspectorHostCloseRequested, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { closeRequests += 1 }
        }
        defer { NotificationCenter.default.removeObserver(closeObserver) }
        // Settle already-enqueued delivery before the first native tracking
        // operation. These are single clicks, without retries or focus changes.
        try await Task.sleep(nanoseconds: 15_000_000)
        FileHandle.standardError.write(Data("Chrome retry before: refreshes=\(probe.online.refreshes), expectedBase=\(beforeRetry), closes=\(closeRequests), responder=\(String(describing: window.firstResponder))\n".utf8))
        let retryUps = try await click(retryPoint)
        FileHandle.standardError.write(Data("Chrome retry after: refreshes=\(probe.online.refreshes), closes=\(closeRequests), dispatchedUps=\(retryUps)\n".utf8))
        checks["open-inspector-native-notice-click-executes-once-without-closing-inspector"] =
            probe.online.refreshes == beforeRetry + 1 && closeRequests == 0
        let blank = detail.view.convert(NSPoint(x: 40, y: detail.view.bounds.midY), to: nil)
        let blankHit = container.view.hitTest(container.view.superview!.convert(blank, from: nil))
        checks["ordinary-content-blank-keeps-the-original-inspector-dimming-hit"] = blankHit is InspectorOverlayPassthroughView
            && !chrome.permitsNoticeInteraction(at: blank)
        let blankUps = try await click(blank)
        FileHandle.standardError.write(Data("Chrome blank after: refreshes=\(probe.online.refreshes), closes=\(closeRequests), dispatchedUps=\(blankUps)\n".utf8))
        checks["ordinary-content-blank-click-still-sends-only-the-original-inspector-close"] = closeRequests == 1
            && probe.online.refreshes == beforeRetry + 1
        let inspectorWheel = NSEvent(cgEvent: CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -24, wheel2: 0, wheel3: 0)!)!
        (blankHit as! InspectorOverlayPassthroughView).scrollWheel(with: inspectorWheel)
        FileHandle.standardError.write(Data("Chrome wheel after: refreshes=\(probe.online.refreshes), closes=\(closeRequests)\n".utf8))
        checks["original-inspector-wheel-handler-still-closes-without-running-a-notice-action"] = closeRequests == 2
            && probe.online.refreshes == beforeRetry + 1
        activeRetry.isEnabled = false
        checks["disabled-notice-button-does-not-cross-the-inspector-surface"] = !chrome.permitsNoticeInteraction(at: retryPoint)
        activeRetry.isEnabled = true
        probe.apply(state(.videos)); settle(); send(activeRetry)
        FileHandle.standardError.write(Data("Chrome removed notice after: refreshes=\(probe.online.refreshes), closes=\(closeRequests), permits=\(chrome.permitsNoticeInteraction(at: retryPoint))\n".utf8))
        checks["removed-notice-button-cannot-run-or-retain-a-passthrough-region"] = probe.online.refreshes == beforeRetry + 1
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
        probe.workspace.recoveryMessage = recovery; probe.apply(filled); settle()
        grid.scrollToTop(animated: false); settle()
        let bodyTop = detail.view.convert(detail.view.bounds, to: nil).maxY
        checks["notice-bottom-to-first-card-has-one-eight-point-content-inset"] = firstCardTop().map { abs(bodyTop - $0 - 8) < 1 } == true
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
        partialDownloads.query.provider = .steamWorkshop
        partialDownloads.queryResult = .init(items: Array(values.prefix(1)), unfilteredCount: 3)
        probe.apply(partialDownloads)
        checks["provider-filter-does-not-misclassify-an-unfiltered-partial-download-total-as-complete"] = grid.scrollView.pullCountText == "显示 1 / 已加载 3 张壁纸"
        probe.workspace.catalog.catalog.sourceScanStatuses[.pixabay] = .init(phase: .failed(message: coldFailure), hasSuccessfulScan: false)
        partialDownloads.query.provider = nil
        partialDownloads.queryResult = .init(items: Array(values.prefix(3)), unfilteredCount: 3)
        probe.apply(partialDownloads)
        checks["first-failed-other-provider-keeps-the-count-explicitly-partial"] = grid.scrollView.pullCountText == "已加载 3 张壁纸"
        probe.apply(state(.downloads))
        checks["zero-items-with-an-unknown-or-first-failed-provider-has-no-fabricated-total"] = grid.scrollView.pullCountText == nil
        probe.workspace.catalog.catalog.loadedProviders.insert(.pixabay)
        probe.workspace.catalog.catalog.sourceScanStatuses.removeValue(forKey: .pixabay)
        partialDownloads.query.provider = .steamWorkshop
        partialDownloads.queryResult = .init(items: Array(values.prefix(1)), unfilteredCount: 3)
        probe.apply(partialDownloads)
        checks["both-ready-download-providers-can-report-the-complete-unfiltered-total"] = grid.scrollView.pullCountText == "显示 1 / 共 3 张壁纸"
        probe.apply(state(.downloads))
        checks["both-successful-empty-download-providers-have-known-zero"] = grid.scrollView.pullCountText == "共 0 张壁纸"
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
        let importButton = button("导入视频")!
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
        let importPoint = importButton.convert(NSPoint(x: importButton.bounds.midX, y: importButton.bounds.midY), to: nil)
        checks["empty-import-control-keeps-its-native-hit-target"] = nativeHit(importPoint) === importButton
        let beforeImportClick = probe.commands.imports
        func traceImportClick(_ stage: String, deliveredUps: Int) {
            let receipt: [String: Any] = ["stage": stage, "beforeImports": beforeImportClick,
                "afterImports": probe.commands.imports, "importsBeforeWheel": importsBeforeWheel, "deliveredUps": deliveredUps,
                "buttonEnabled": importButton.isEnabled, "buttonHidden": importButton.isHiddenOrHasHiddenAncestor,
                "buttonHighlighted": importButton.cell?.isHighlighted == true, "buttonFrame": String(describing: importButton.frame),
                "point": String(describing: importPoint), "hitIsButton": nativeHit(importPoint) === importButton,
                "superview": String(describing: importButton.superview.map { type(of: $0) }),
                "buttonWindowMatches": importButton.window === window, "superWindowMatches": importButton.superview?.window === window,
                "buttonIsInChrome": importButton.isDescendant(of: chrome.view), "windowVisible": window.isVisible,
                "windowKey": window.isKeyWindow, "windowMain": window.isMainWindow, "appActive": NSApp.isActive,
                "modalWindowNumber": NSApp.modalWindow?.windowNumber ?? -1, "hasSheet": window.attachedSheet != nil,
                "presentationPage": String(describing: probe.workspace.presentation.page),
                "presentationItems": probe.workspace.presentation.state.queryResult.items.count,
                "canImport": probe.commands.canImport, "rootWindowMatches": container.view.window === window,
                "chromeWindowMatches": chrome.view.window === window, "detailHasGrid": grid.parent === detail,
                "action": String(describing: importButton.action), "target": String(describing: importButton.target)]
            FileHandle.standardError.write(Data("chrome-empty-import-click ".utf8)
                + (try! JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys])) + Data("\n".utf8))
        }
        traceImportClick("before", deliveredUps: 0)
        let importUps = try await click(importPoint)
        traceImportClick("after-immediate", deliveredUps: importUps)
        checks["empty-import-control-still-clicks-the-original-command-exactly-once"] =
            probe.commands.imports == importsBeforeWheel + 1
        try await Task.sleep(nanoseconds: 160_000_000)
        traceImportClick("after-one-native-queue-turn", deliveredUps: importUps)

        func makeInputModal() -> WallpaperLibraryModalPanel {
            let panel = WallpaperLibraryModalPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 240),
                styleMask: [.borderless], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.contentView = WallpaperLibrarySheetSurface(frame: NSRect(x: 0, y: 0, width: 360, height: 240))
            return panel
        }
        let importModal = makeInputModal()
        let importModalPresented = WallpaperLibrarySheetPresentation.present(importModal, in: window)
        settle()
        checks["chrome-retained-import-test-uses-the-current-page-and-real-owned-child"] = importModalPresented
            && importModal.parent === window && importModal.isKeyWindow
            && importModal.isAccessibilityModal()
            && probe.workspace.presentation.page == .videos && importButton.isEnabled && importButton.window === window
            && !WallpaperLibrarySheetPresentation.permitsInput(in: window)
        let beforeBlockedImport = probe.commands.imports
        importButton.performClick(nil)
        let blockedImportAX = importButton.accessibilityPerformPress()
        traceImportClick("owned-child-held-immediate-AX-\(blockedImportAX)", deliveredUps: importUps)
        try await Task.sleep(nanoseconds: 160_000_000)
        traceImportClick("owned-child-held-after-one-native-queue-turn", deliveredUps: importUps)
        checks["owned-child-revokes-current-retained-chrome-import-button-and-accessibility-action"] =
            probe.commands.imports == beforeBlockedImport && importModal.isVisible && importModal.parent === window
        importModal.close()
        try await Task.sleep(nanoseconds: 160_000_000)
        let beforeRestoredImport = probe.commands.imports
        let restoredImportAX = importButton.accessibilityPerformPress()
        traceImportClick("owned-child-closed-restored-import-immediate-AX-\(restoredImportAX)", deliveredUps: importUps)
        try await Task.sleep(nanoseconds: 160_000_000)
        traceImportClick("owned-child-closed-restored-import-after-one-native-queue-turn", deliveredUps: importUps)
        // The native AX method can return false even when it dispatches its
        // action; the actual command count, not that return value, is decisive.
        checks["owned-child-close-restores-the-same-chrome-import-action-exactly-once"] =
            importModal.parent == nil && !importModal.isVisible && !importModal.isAccessibilityModal() && window.isKeyWindow
            && WallpaperLibrarySheetPresentation.permitsInput(in: window)
            && probe.commands.imports == beforeRestoredImport + 1

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
                "modalParentMatches": modal.parent === window, "modalVisible": modal.isVisible,
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
            && modal.parent === window && modal.isKeyWindow && modal.isVisible && window.attachedSheet == nil
            && modal.isAccessibilityModal()
            && !WallpaperLibrarySheetPresentation.permitsInput(in: window)
            && WallpaperLibrarySheetPresentation.permitsInput(in: modal)
        let beforeBlockedHeader = probe.commands.displayedPlayRequests
        retainedPlay.performClick(nil); retainedRandom.performClick(nil)
        checks["owned-child-blocks-retained-real-header-play-and-random-buttons"] =
            retainedPlay.isEnabled && retainedRandom.isEnabled && retainedPlay.window === window && retainedRandom.window === window
            && probe.commands.displayedPlayRequests == beforeBlockedHeader
        let blockedPlayAX = retainedPlay.accessibilityPerformPress(), blockedRandomAX = retainedRandom.accessibilityPerformPress()
        traceHeaderAction("owned-child-held-immediate", playAX: blockedPlayAX, randomAX: blockedRandomAX)
        try await Task.sleep(nanoseconds: 160_000_000)
        traceHeaderAction("owned-child-held-after-one-native-queue-turn", playAX: blockedPlayAX, randomAX: blockedRandomAX)
        checks["owned-child-blocks-retained-real-header-accessibility-presses"] =
            probe.commands.displayedPlayRequests == beforeBlockedHeader && modal.isKeyWindow
            && modal.isVisible && modal.parent === window
        traceHeaderAction("before-close")
        modal.close(); settle()
        traceHeaderAction("after-close-nested-settle-before-performClick")
        retainedPlay.performClick(nil); retainedRandom.performClick(nil)
        traceHeaderAction("after-restored-performClick-before-AX")
        let playAX = retainedPlay.accessibilityPerformPress(), randomAX = retainedRandom.accessibilityPerformPress()
        traceHeaderAction("after-restored-AX-immediate", playAX: playAX, randomAX: randomAX)
        try await Task.sleep(nanoseconds: 160_000_000)
        traceHeaderAction("after-restored-one-native-queue-turn", playAX: playAX, randomAX: randomAX)
        checks["owned-child-close-restores-the-same-header-buttons-and-accessibility-actions"] =
            modal.parent == nil && !modal.isVisible && !modal.isAccessibilityModal() && window.isKeyWindow
            && WallpaperLibrarySheetPresentation.permitsInput(in: window)
            && probe.commands.displayedPlayRequests == [false, true, false, true, false, true]
        print(String(data: try! JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
