import AppKit
import Combine
import ObjectiveC
import QuartzCore

// The complete production menu handlers execute; opening an external browser
// is a recording leaf so this native gate never changes the user's browser.
@MainActor enum PixabayMenuWorkspace {
    static var openedURLs: [URL] = []
    static func open(_ url: URL) -> Bool { openedURLs.append(url); return true }
}

@MainActor private func pixabayPlaylistMenu(permitsAction: @escaping () -> Bool, perform: @escaping () -> Void) -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false
    menu.addItem(ActionMenuItem(title: "Fixture playlist", symbol: WallpaperLibrarySymbols.playlist) {
        guard permitsAction() else { return }
        perform()
    })
    return menu
}

@MainActor private func pixabayInvokeContextLeaf(_ item: NSMenuItem, _ facts: Facts) {
    let leaf = item.submenu?.items.first ?? item
    guard let action = leaf.action else {
        facts.expect("native-context-action-leaf-is-present-" + item.title, false)
        return
    }
    _ = NSApp.sendAction(action, to: leaf.target, from: leaf)
}

// Source publication and transport leaves only. The complete browser container,
// native diffable data source and production card execute in the case below.
@MainActor final class OnlineLibraryService: ObservableObject {
    @Published var items: [OnlineLibraryVideoItem] = []
    @Published var downloadingIDs: Set<Int> = []
    @Published var downloadedIDs: Set<Int> = []
    @Published var downloadProgressByID: [Int: Double] = [:]
    var hasMore = false
    var isLoading = false
    func refreshDownloadedContent() {}
    func loadNextPage() { preconditionFailure("native metadata case must not fetch HTTP pages") }
    func cancelThumbnailPrefetch() {}
    func prioritizeVisibleItemIDs(_ ids: [Int], maxPixelSize: Int) {}
    func thumbnailPrefetchNeedsRefresh() -> Bool { false }
}

@MainActor func pixabayBrowserContainerMetadata(_ facts: Facts) {
    let service = OnlineLibraryService()
    let original = browserModel(601, tags: "old title", duration: 11, thumbnail: "old-source")
    let neighbor = browserModel(602, tags: "unchanged neighbor", thumbnail: nil)
    service.items = [original, neighbor]
    var downloads: [OnlineLibraryVideoItem] = [], applications: [OnlineLibraryVideoItem] = []
    var configurations: [Int: Int] = [:]
    let grid = AppKitOLBrowserContainerView(service: service,
        onDownload: { downloads.append($0) }, onSetAsWallpaper: { applications.append($0) })
    grid.makeOrganization = { item in configurations[item.id, default: 0] += 1; return nil }
    let window = CardWindow(contentRect: NSRect(x: 120, y: 120, width: 900, height: 620),
        styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    window.toolbarStyle = .unified
    window.toolbar = NSToolbar(identifier: "online-metadata-native")
    window.isReleasedWhenClosed = false
    window.contentView = grid
    window.orderFrontRegardless(); window.makeKey()
    grid.layoutSubtreeIfNeeded()
    defer { window.orderOut(nil); window.close() }
    let path = IndexPath(item: 0, section: 0)
    guard waitUntil(2, { grid.collectionView.item(at: path) is AppKitOLBrowserItem }),
          let card = grid.collectionView.item(at: path) as? AppKitOLBrowserItem else {
        facts.expect("real-browser-source-publisher-mounts-a-native-card", false); return
    }
    facts.expect("real-browser-source-publisher-mounts-a-native-card", card.presentedItem == original
        && grid.dataSource.snapshot().itemIdentifiers == [601, 602] && card.view.window === window)
    let neighborConfigurations = configurations[602, default: 0]
    let updated = browserModel(601, tags: "new visible title", duration: 85, thumbnail: "new-source", bytes: 5_242_880)
    service.items = [updated, neighbor]
    _ = waitUntil { card.presentedItem == updated }
    facts.expect("same-ID-source-publication-updates-the-existing-native-card-metadata", grid.itemsByID[601] == updated
        && grid.collectionView.item(at: path) === card && card.presentedItem == updated
        && card.currentTitle == updated.displayTitle && card.currentThumbnailURL == updated.previewThumbnailURL)
    facts.expect("retained-neighbor-is-not-reconfigured-for-unrelated-metadata", configurations[602, default: 0] == neighborConfigurations)
    func invokeSourceActions() {
        guard let menu = card.buildContextMenu() else { return }
        for index in [0, 1, 3] {
            let item = menu.items[index]
            _ = NSApp.sendAction(item.action!, to: item.target, from: item)
        }
    }
    let opened = PixabayMenuWorkspace.openedURLs.count
    invokeSourceActions()
    facts.expect("new-native-menu-uses-the-updated-fixed-download-set-and-page-URL", downloads == [updated]
        && applications == [updated] && PixabayMenuWorkspace.openedURLs.count == opened + 1
        && PixabayMenuWorkspace.openedURLs.last == URL(string: updated.pageURL))
    let request = card.thumbnailRequestID, beforeEqual = configurations
    let frame = card.view.frame, origin = grid.scrollView.contentView.bounds.origin
    service.items = [updated, neighbor]
    pump(0.08)
    facts.expect("identical-source-echo-keeps-native-card-config-thumbnail-and-viewport", grid.collectionView.item(at: path) === card
        && configurations == beforeEqual && card.thumbnailRequestID == request
        && card.view.frame == frame && grid.scrollView.contentView.bounds.origin == origin)
    let overlap = browserModel(601, tags: "overlap title", duration: 95, thumbnail: "overlap-source")
    service.items = [overlap, neighbor, browserModel(603, thumbnail: nil)]
    _ = waitUntil { grid.dataSource.snapshot().itemIdentifiers == [601, 602, 603] && card.presentedItem == overlap }
    facts.expect("native-append-refreshes-changed-retained-metadata-with-unique-identifiers", grid.dataSource.snapshot().itemIdentifiers == [601, 602, 603]
        && (grid.collectionView.item(at: path) as? AppKitOLBrowserItem)?.presentedItem == overlap)
    let final = browserModel(601, tags: "latest publication", duration: 105, thumbnail: "latest-source")
    service.items = [updated, neighbor]
    service.items = [final, neighbor]
    _ = waitUntil { (grid.collectionView.item(at: path) as? AppKitOLBrowserItem)?.presentedItem == final }
    facts.expect("queued-native-source-publications-end-at-the-current-item-not-an-old-completion", grid.itemsByID[601] == final
        && (grid.collectionView.item(at: path) as? AppKitOLBrowserItem)?.presentedItem == final
        && grid.dataSource.snapshot().itemIdentifiers == [601, 602])
}

@MainActor private final class PixabayNativeAccentProbe: NSObject {
    @objc class func nonRedAccent() -> NSColor { NSColor(srgbRed: 0.15, green: 0.65, blue: 0.35, alpha: 1) }
    static func withNonRedAccent(_ body: () -> Bool) -> Bool {
        guard let getter = class_getClassMethod(NSColor.self, #selector(getter: NSColor.controlAccentColor)),
              let replacement = class_getClassMethod(Self.self, #selector(nonRedAccent)) else { return false }
        let original = method_getImplementation(getter)
        method_setImplementation(getter, method_getImplementation(replacement))
        defer { method_setImplementation(getter, original) }
        // Synchronous only. Never pump a RunLoop while the isolated process's
        // native color lookup leaf is replaced; no user preference is written.
        return body()
    }
}

// Actual shared grid + actual downloaded card. Only App actions are recording
// leaves; native selection, click recognition, hit testing and controls run whole.
@MainActor final class PixabayDownloadsClickOwner {
    let reference = WallpaperReference(provider: .pixabay, sourceID: "901")
    var selection = WallpaperLibrarySelectionState()
    var played: [Int] = [], inspected: [WallpaperReference] = []
    var selectionEvents = 0
    lazy var controller: WallpaperLibraryGridController = {
        let result = WallpaperLibraryGridController { [weak self] collection, path, _, state in
            let card = collection.makeItem(withIdentifier: AppKitOLDownloadsItem.reuseIdentifier, for: path) as! AppKitOLDownloadsItem
            card.onPrimaryAction = { [weak self] in self?.played.append($0) }
            card.configure(entry: downloadModel(901), isSelected: state.isSelected, isMultiSelectMode: state.isSelecting, isPlaying: true)
            return card
        }
        result.loadViewIfNeeded()
        result.collection.register(AppKitOLDownloadsItem.self, forItemWithIdentifier: AppKitOLDownloadsItem.reuseIdentifier)
        result.onSelection = { [weak self] refs, focus in
            guard let self else { return nil }
            if self.selection.references != refs || self.selection.focusedReference != focus { self.selection.sessionID = UUID() }
            self.selection.references = refs; self.selection.focusedReference = focus; self.selectionEvents += 1
            return self.selection.sessionID
        }
        result.onInspect = { [weak self] in self?.inspected.append($0.reference) }
        result.updateCell = { cell, _, state in
            (cell as? AppKitOLDownloadsItem)?.applySelectionState(state.isSelected, multiSelectMode: state.isSelecting)
        }
        return result
    }()
    func update(selecting: Bool = false) {
        selection.isSelecting = selecting
        let value = WallpaperContentItem(reference: reference, providerReference: reference,
            locator: .init(mediaKind: .video), title: "download 901", kind: .video,
            publishedAvailability: .available, capabilities: [.play, .organize, .inspect], metadata: .init(),
            acquisition: .idle, update: .idle, aliases: [])
        controller.update(page: .downloads, items: [value], selection: selection, preferredColumns: 5, permitsDragging: false, scrollAnchor: nil)
    }
}

@MainActor func pixabayNativeClickOwner(_ facts: Facts) {
    let owner = PixabayDownloadsClickOwner()
    let controller = owner.controller
    let window = NSWindow(contentViewController: controller)
    window.setFrame(NSRect(x: 14000, y: 14000, width: 320, height: 360), display: false)
    window.isReleasedWhenClosed = false
    owner.update()
    window.orderFrontRegardless(); window.makeKey()
    controller.view.layoutSubtreeIfNeeded(); pump(0.04)
    defer { window.orderOut(nil); window.close() }
    guard let card = controller.collection.item(at: IndexPath(item: 0, section: 0)) as? AppKitOLDownloadsItem else {
        facts.expect("real-click-card-is-registered", false); return
    }
    layout(card)
    guard let bar = card.controlBar else { facts.expect("click-bar-is-mounted", false); return }
    bar.layoutSubtreeIfNeeded()
    func click(_ point: NSPoint) {
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 2, clickCount: 1, pressure: 1)!
        let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime + 0.01, windowNumber: window.windowNumber,
            context: nil, eventNumber: 3, clickCount: 1, pressure: 0)!
        NSApp.postEvent(up, atStart: true); window.sendEvent(down); pump(0.02)
    }
    let button = bar.playButton
    let center = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
    let hitCenter = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: card.view.superview)
    facts.expect("real-window-primary-hit-is-native-button", card.view.hitTest(hitCenter) === button)
    click(center)
    facts.expect("native-button-click-plays-exactly-once-without-selecting-or-inspector", owner.played == [901]
        && owner.selection.references.isEmpty && owner.selectionEvents == 0 && owner.inspected.isEmpty)
    let beside = button.convert(NSPoint(x: button.bounds.minX - 4, y: button.bounds.midY), to: nil)
    let hitBeside = button.convert(NSPoint(x: button.bounds.minX - 4, y: button.bounds.midY), to: card.view.superview)
    facts.expect("old-expanded-button-neighbor-is-not-button", card.view.hitTest(hitBeside) !== button)
    click(beside)
    facts.expect("button-neighbor-only-selects-and-opens-details", owner.played == [901]
        && owner.selection.references == [owner.reference] && owner.selection.focusedReference == owner.reference
        && owner.inspected == [owner.reference])
    let cover = card.imageContainer.convert(NSPoint(x: 100, y: 140), to: nil)
    click(cover)
    facts.expect("cover-only-reopens-details-without-playing", owner.played == [901]
        && owner.inspected == [owner.reference, owner.reference])
    owner.update(selecting: true)
    click(cover)
    facts.expect("multi-selection-cover-toggles-without-playing-or-details", owner.selection.references.isEmpty
        && owner.played == [901] && owner.inspected == [owner.reference, owner.reference])
}

@MainActor func pixabaySquareControls(_ facts: Facts) {
    let browserHost = CardHost(.browser)
    let downloadsHost = CardHost(.downloads)
    defer { browserHost.finish(); downloadsHost.finish() }
    guard let browser = browserHost.first() as? AppKitOLBrowserItem,
          let download = downloadsHost.first() as? AppKitOLDownloadsItem else {
        facts.expect("registered-both-real-cards", false); return
    }
    browser.prepareForReuse()
    browser.view.frame.size = NSSize(width: 240, height: 242)
    var downloaded: [Int] = [], played: [Int] = [], favorite: [Int] = []
    let model = browserModel(501, tags: String(repeating: "Long source title ", count: 8), thumbnail: nil)
    func updateBrowser(downloading: Bool = false, ready: Bool = false, progress: Double? = nil) {
        browser.configure(item: model, isDownloading: downloading, isDownloaded: ready, downloadProgress: progress,
            onDownload: { downloaded.append(model.id) }, onSetAsWallpaper: { played.append(model.id) })
        layout(browser)
    }
    updateBrowser()
    browser.applyHoverVisibility(true, animated: false)
    let bar = browser.controlBar
    bar.layoutSubtreeIfNeeded()
    func hit(_ card: NSCollectionViewItem, button: NSButton) -> Bool {
        let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: card.view.superview)
        return card.view.hitTest(point) === button
    }
    facts.expect("remote-primary-is-a-reachable-download-not-play-or-cancel", hit(browser, button: bar.playButton)
        && bar.playButton.accessibilityLabel() == "下载到本地" && bar.favoriteButton.isHidden)
    bar.playButton.performClick(nil)
    facts.expect("remote-primary-only-downloads", downloaded == [501] && played.isEmpty)
    let titleView = bar.titleView, mask = titleView.layer?.mask
    updateBrowser(downloading: true, progress: 0.45)
    browser.applyHoverVisibility(false, animated: false)
    facts.expect("download-progress-is-visible-without-hover-and-cannot-cancel", bar.superview != nil
        && !bar.isHidden && bar.alphaValue == 1 && !bar.playButton.isEnabled && bar.playButton.title == "45%"
        && bar.playButton.accessibilityLabel() == "下载中")
    updateBrowser(downloading: true, progress: 0.61)
    facts.expect("progress-updates-retain-real-title-and-fade-owner", bar.titleView === titleView
        && titleView.layer?.mask === mask && bar.playButton.title == "61%")
    let allowsMotion = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    browser.thumbnailView.image = image(12)
    updateBrowser(downloading: true)
    browser.applyHoverVisibility(true, animated: false)
    bar.layoutSubtreeIfNeeded()
    facts.expect("visible-browser-runs-long-title-and-indeterminate-progress", (titleView.activeMarqueeAnimation != nil) == allowsMotion
        && (bar.glass.activeIndeterminateAnimation != nil) == allowsMotion)
    browser.endDisplayingThumbnail()
    facts.expect("offscreen-browser-revokes-all-repeating-bar-animation", titleView.activeMarqueeAnimation == nil
        && bar.glass.activeIndeterminateAnimation == nil)
    updateBrowser(downloading: true)
    facts.expect("offscreen-progress-tick-cannot-restart-bar-animation", titleView.activeMarqueeAnimation == nil
        && bar.glass.activeIndeterminateAnimation == nil)
    let thumbnailRequestsBeforeRedisplay = OLThumbnailCache.shared.history.count
    browser.beginDisplayingThumbnail()
    facts.expect("ready-browser-redisplay-resumes-animation-before-thumbnail-early-return", browser.thumbnailView.image != nil
        && OLThumbnailCache.shared.history.count == thumbnailRequestsBeforeRedisplay
        && (titleView.activeMarqueeAnimation != nil) == allowsMotion
        && (bar.glass.activeIndeterminateAnimation != nil) == allowsMotion)
    updateBrowser(ready: true)
    pump(0.9)
    browser.applyHoverVisibility(true, animated: false)
    facts.expect("publication-completion-never-autoplays", played.isEmpty && !bar.playButton.isHidden
        && bar.playButton.accessibilityLabel() == "设为壁纸" && bar.favoriteButton.isHidden)
    bar.playButton.performClick(nil)
    facts.expect("published-browser-primary-uses-existing-play-command", played == [501])
    browser.updateOrganization(.init(state: .init(isPlaying: false, isFavorite: false, canPerformPrimary: true,
        canFavorite: true, canOrganize: true, playlistNames: []), onPrimary: {},
        onToggleFavorite: { favorite.append(model.id) }, onChoosePlaylist: { _ in }), for: model.id)
    bar.favoriteButton.performClick(nil)
    facts.expect("bound-favorite-is-reachable-without-status-overlay-blocking", hit(browser, button: bar.favoriteButton)
        && !bar.favoriteButton.isHidden && favorite == [501])
    let noPlaylistFactory = browser.buildContextMenu()?.items.last
    facts.expect("browser-does-not-invent-an-action-without-a-native-playlist-menu-factory", noPlaylistFactory?.title == "添加到播放列表"
        && noPlaylistFactory?.isEnabled == false && noPlaylistFactory?.submenu == nil && noPlaylistFactory?.action == nil)
    browser.thumbnailView.image = NSImage(size: NSSize(width: 400, height: 200))
    browser.layoutThumbnail()
    facts.expect("browser-thumbnail-is-square-centered-crop-without-stretch", browser.imageContainer.frame.size == NSSize(width: 240, height: 240)
        && browser.thumbnailView.frame == NSRect(x: -120, y: 0, width: 480, height: 240))
    browser.applyHoverVisibility(false, animated: true)
    browser.applyHoverVisibility(true, animated: true)
    pump(0.4)
    facts.expect("browser-late-fade-cannot-detach-reentered-bar", bar.superview != nil && !bar.isHidden && bar.alphaValue == 1)
    var browserStopCalls = 0
    func browserPlayback(_ switching: Bool, playing: Bool) -> WallpaperInspectorActions {
        .init(state: .init(isPlaying: playing, isSwitching: switching, isFavorite: false, canPerformPrimary: !switching,
            canFavorite: true, canOrganize: true, playlistNames: []), onPrimary: { browserStopCalls += 1 },
            onToggleFavorite: { favorite.append(model.id) }, onChoosePlaylist: { _ in })
    }
    let pendingBrowserRequest = browser.thumbnailRequestID, pendingBrowserLoads = OLThumbnailCache.shared.history.count
    func browserPlaybackDetails() -> String {
        let fields: [String] = [
            "state=\(bar.primaryState)", "hidden=\(bar.isHidden)", "mounted=\(bar.superview != nil)",
            "alpha=\(bar.alphaValue)", "buttonHidden=\(bar.playButton.isHidden)",
            "enabled=\(bar.playButton.isEnabled)", "AX=\(bar.playButton.accessibilityLabel() ?? "nil")",
            "imagePosition=\(bar.playButton.imagePosition.rawValue)", "title=\(String(reflecting: bar.playButton.title))",
            "played=\(played)", "downloaded=\(downloaded)",
            "request=\(browser.thumbnailRequestID) expected=\(pendingBrowserRequest)",
            "loads=\(OLThumbnailCache.shared.history.count) expected=\(pendingBrowserLoads)",
            "completionHidden=\(browser.completionBadgeView.isHidden)",
            "completionAnimating=\(browser.isCompletionAnimating)", "sourceDownloading=\(browser.isDownloadingState)"
        ]
        return fields.joined(separator: ", ")
    }
    updateBrowser(downloading: true, progress: 0.61)
    facts.expect("pending-transition-starts-with-the-real-percentage-only-download-button", bar.playButton.imagePosition == .noImage
        && bar.playButton.title == "61%" && !bar.playButton.isEnabled)
    browser.applyHoverVisibility(false, animated: false)
    browser.updateOrganization(browserPlayback(true, playing: true), for: model.id)
    bar.playButton.performClick(nil)
    facts.expect("browser-Core-pending-pins-shared-hourglass-and-blocks-repeat-without-thumbnail-work", bar.primaryState == .switching
        && !bar.isHidden && bar.superview != nil && bar.alphaValue == 1 && !bar.playButton.isEnabled
        && bar.playButton.accessibilityLabel() == "正在切换壁纸" && bar.playButton.imagePosition == .imageOnly
        && bar.playButton.title.isEmpty && played == [501] && downloaded == [501]
        && browser.thumbnailRequestID == pendingBrowserRequest && OLThumbnailCache.shared.history.count == pendingBrowserLoads,
        browserPlaybackDetails())
    browser.updateOrganization(browserPlayback(false, playing: true), for: model.id)
    facts.expect("browser-success-pins-native-stop-after-organization-only-echo", bar.primaryState == .playing
        && !bar.isHidden && bar.superview != nil && bar.playButton.isEnabled && bar.playButton.accessibilityLabel() == "停止播放"
        && bar.playButton.imagePosition == .imageOnly && bar.playButton.title.isEmpty, browserPlaybackDetails())
    bar.playButton.performClick(nil)
    facts.expect("browser-successful-Stop-uses-fixed-Core-action-without-reapplying-or-downloading", browserStopCalls == 1
        && played == [501] && downloaded == [501])
    browser.configure(item: model, isDownloading: false, isDownloaded: true, downloadProgress: nil,
        organization: browserPlayback(false, playing: true), onDownload: { downloaded.append(model.id) },
        onSetAsWallpaper: { played.append(model.id) })
    facts.expect("late-download-completion-echo-cannot-cover-or-restore-percentage-over-Core-Stop", bar.primaryState == .playing
        && bar.playButton.imagePosition == .imageOnly && bar.playButton.title.isEmpty && !bar.playButton.isHidden
        && browser.completionBadgeView.isHidden && bar.playButton.isEnabled, browserPlaybackDetails())
    pump(0.9)
    browser.updateOrganization(browserPlayback(false, playing: false), for: model.id)
    facts.expect("browser-cancelled-or-stopped-pending-returns-to-original-idle-without-hover", bar.primaryState == .apply
        && bar.isHidden && bar.superview == nil)
    browser.updateOrganization(browserPlayback(true, playing: false), for: model.id)
    browser.prepareForReuse()
    bar.playButton.performClick(nil)
    bar.favoriteButton.performClick(nil)
    facts.expect("browser-reuse-revokes-old-actions", played == [501] && downloaded == [501] && favorite == [501]
        && browser.organization == nil && bar.superview == nil && bar.primaryState == .apply)

    var chosen: [Int] = [], injectedPrimaryCalls = 0
    func organization(_ id: Int, favorite isFavorite: Bool, canFavorite: Bool = true, canOrganize: Bool = true) -> WallpaperInspectorActions {
        var actions = WallpaperInspectorActions(state: .init(isPlaying: false, isFavorite: isFavorite, canPerformPrimary: true,
            canFavorite: canFavorite, canOrganize: canOrganize, playlistNames: []),
            onPrimary: { injectedPrimaryCalls += 1 }, onToggleFavorite: { favorite.append(id) }, onChoosePlaylist: { _ in chosen.append(id) })
        actions.makePlaylistMenu = { permitsAction in
            pixabayPlaylistMenu(permitsAction: permitsAction) { chosen.append(id) }
        }
        return actions
    }
    func invoke(_ menuItem: NSMenuItem) { pixabayInvokeContextLeaf(menuItem, facts) }
    updateBrowser(ready: true)
    browser.applyHoverVisibility(true, animated: false)
    let originalRequestID = browser.thumbnailRequestID, originalImage = browser.thumbnailView.image
    let originalRequestCount = OLThumbnailCache.shared.history.count
    browser.updateOrganization(organization(501, favorite: true), for: 501)
    facts.expect("organization-echo-updates-heart-without-reconfiguring-thumbnail", bar.isFavorite && !bar.favoriteButton.isHidden
        && bar.favoriteButton.isEnabled && browser.thumbnailRequestID == originalRequestID
        && browser.thumbnailView.image === originalImage && OLThumbnailCache.shared.history.count == originalRequestCount)
    let readyMenu = browser.buildContextMenu()!
    facts.expect("downloaded-browser-menu-appends-organization-and-retains-original-actions", readyMenu.items.map(\.title) == [
        "下载到本地", "设为壁纸", "", "在 Pixabay 上查看", "", "取消特别喜爱", "添加到播放列表"])
    let playlistParent = readyMenu.items[6], playlistLeaf = readyMenu.items[6].submenu?.items.first
    let stockParent = NSMenuItem(title: "Native submenu control", action: nil, keyEquivalent: "")
    stockParent.submenu = NSMenu()
    let stockMenu = NSMenu()
    stockMenu.autoenablesItems = false
    stockMenu.addItem(stockParent)
    let submenuDetails = "parent.action=\(String(describing: playlistParent.action)) target=\(String(describing: playlistParent.target)) enabled=\(playlistParent.isEnabled) type=\(type(of: playlistParent)) count=\(String(describing: playlistParent.submenu?.items.count)) leaf.action=\(String(describing: playlistLeaf?.action)) leaf.target=\(String(describing: playlistLeaf?.target)) leaf.type=\(playlistLeaf.map { String(describing: type(of: $0)) } ?? "nil") stock.action=\(String(describing: stockParent.action)) stock.target=\(String(describing: stockParent.target)) stock.type=\(type(of: stockParent))"
    facts.expect("native-submenu-control-really-installs-its-own-target-and-action", stockParent.action != nil
        && stockParent.target === stockParent.submenu, submenuDetails)
    facts.expect("browser-playlist-parent-is-a-native-submenu-with-a-real-action-leaf", playlistParent.action == stockParent.action
        && playlistParent.target === playlistParent.submenu && type(of: playlistParent) == type(of: stockParent)
        && playlistParent.isEnabled && playlistParent.submenu?.items.count == 1
        && playlistLeaf is ActionMenuItem && playlistLeaf?.action != nil, submenuDetails)
    invoke(readyMenu.items[6])
    let beforePrimary = played.count
    bar.playButton.performClick(nil)
    facts.expect("organization-never-replaces-original-download-and-set-primary", chosen == [501]
        && played.count == beforePrimary + 1 && played.last == 501 && injectedPrimaryCalls == 0)
    browser.updateOrganization(organization(501, favorite: false, canFavorite: false, canOrganize: true), for: 501)
    let independentlyEnabled = browser.buildContextMenu()!, favoritesBeforeDisabled = favorite.count
    invoke(independentlyEnabled.items[5]); invoke(readyMenu.items[5]); invoke(independentlyEnabled.items[6])
    facts.expect("favorite-and-playlist-capabilities-remain-independent", !independentlyEnabled.items[5].isEnabled
        && independentlyEnabled.items[6].isEnabled && !bar.favoriteButton.isEnabled
        && favorite.count == favoritesBeforeDisabled && chosen == [501, 501])

    let replacement = browserModel(502, thumbnail: nil)
    browser.configure(item: replacement, isDownloading: false, isDownloaded: true, downloadProgress: nil,
        organization: organization(502, favorite: false), onDownload: { downloaded.append(502) }, onSetAsWallpaper: { played.append(502) })
    let beforeStaleFavorite = favorite.count, beforeStalePlaylist = chosen.count
    invoke(readyMenu.items[5]); invoke(readyMenu.items[6])
    facts.expect("held-organization-menu-cannot-retarget-a-reused-card", favorite.count == beforeStaleFavorite && chosen.count == beforeStalePlaylist)
    browser.updateOrganization(organization(501, favorite: true), for: 501)
    bar.favoriteButton.performClick(nil)
    facts.expect("old-diffable-row-organization-echo-cannot-attach-another-id-action", favorite.last == 502 && !bar.isFavorite)
    let replacementMenu = browser.buildContextMenu()!, beforeRevokedFavorite = favorite.count
    browser.updateOrganization(nil, for: 502)
    invoke(replacementMenu.items[5]); invoke(replacementMenu.items[6])
    facts.expect("withdrawn-local-organization-revokes-heart-and-held-menu", bar.favoriteButton.isHidden
        && favorite.count == beforeRevokedFavorite && chosen.count == beforeStalePlaylist
        && browser.buildContextMenu()!.items.map(\.title) == ["下载到本地", "设为壁纸", "", "在 Pixabay 上查看"])
    browser.configure(item: replacement, isDownloading: false, isDownloaded: false, downloadProgress: nil,
        organization: organization(502, favorite: true, canOrganize: false), onDownload: { downloaded.append(502) }, onSetAsWallpaper: { played.append(502) })
    let beforeOfflineDownload = downloaded.count, beforeOfflineFavorite = favorite.count
    bar.favoriteButton.performClick(nil)
    let offlineMenu = browser.buildContextMenu()!
    invoke(replacementMenu.items[6])
    facts.expect("local-unavailable-favorite-can-be-removed-without-downloading-or-adding-members", !bar.favoriteButton.isHidden
        && bar.favoriteButton.isEnabled && favorite.count == beforeOfflineFavorite + 1 && favorite.last == 502
        && downloaded.count == beforeOfflineDownload && !offlineMenu.items[6].isEnabled && chosen.count == beforeStalePlaylist)
    browser.prepareForReuse()
    let beforeReusedActions = favorite.count
    invoke(offlineMenu.items[5]); invoke(offlineMenu.items[6])
    facts.expect("reuse-revokes-captured-organization-menu-actions", browser.organization == nil && favorite.count == beforeReusedActions
        && chosen.count == beforeStalePlaylist)
    pixabayFixedContextMenuActions(browser, facts)

    download.prepareForReuse()
    download.view.frame.size = NSSize(width: 240, height: 242)
    let entry = downloadModel(801, name: "local video.mp4")
    let beforeLocalRequest = OLDownloadedThumbnailStore.sharedCache.history.count
    download.configure(entry: entry, isSelected: false, isMultiSelectMode: false, isPlaying: true)
    precondition(waitUntil { OLDownloadedThumbnailStore.sharedCache.history.count == beforeLocalRequest + 1 })
    layout(download)
    var localPlayed: [Int] = [], localFavorite: [Int] = []
    download.onPrimaryAction = { localPlayed.append($0) }
    guard let localBar = download.controlBar else { facts.expect("playing-download-shows-bar", false); return }
    localBar.layoutSubtreeIfNeeded()
    facts.expect("download-primary-is-reachable-and-preserves-actual-play-semantics", hit(download, button: localBar.playButton)
        && localBar.playButton.accessibilityLabel() == "设为壁纸" && localBar.playButton.contentTintColor == .controlAccentColor
        && localBar.favoriteButton.isHidden)
    localBar.playButton.performClick(nil)
    facts.expect("download-primary-emits-stable-current-ID", localPlayed == [801])
    download.onToggleFavorite = { localFavorite.append($0) }
    localBar.favoriteButton.performClick(nil)
    facts.expect("download-bound-favorite-is-reachable-and-emits-current-ID", !localBar.favoriteButton.isHidden
        && hit(download, button: localBar.favoriteButton) && localFavorite == [801])
    let organizationRequest = download.thumbnailRequestID
    let organizationLoads = OLDownloadedThumbnailStore.sharedCache.history.count
    download.applyOrganizationState(isFavorite: true, primaryShowsStop: true)
    facts.expect("download-organization-icons-use-real-stop-without-thumbnail-work", localBar.isFavorite && localBar.primaryState == .playing
        && localBar.playButton.accessibilityLabel() == "停止播放" && localBar.playButton.contentTintColor == .controlAccentColor
        && download.thumbnailRequestID == organizationRequest
        && OLDownloadedThumbnailStore.sharedCache.history.count == organizationLoads)
    let stopMetrics = WallpaperCardBarMetrics(cardWidth: download.imageContainer.bounds.width)
    let stopSymbol = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: nil)!
        .withSymbolConfiguration(.init(pointSize: max(11, stopMetrics.iconButtonSize * 0.56), weight: .medium))!
    facts.expect("download-organization-keeps-actual-stop-image-and-tooltip", localBar.playButton.toolTip == "停止播放"
        && stopSymbol.tiffRepresentation != nil && localBar.playButton.image?.tiffRepresentation == stopSymbol.tiffRepresentation)
    download.applyHoverVisibility(false, animated: false)
    download.applySwitchingState(isSwitching: true)
    download.onPrimaryAction = { localPlayed.append($0) }
    localBar.playButton.performClick(nil)
    facts.expect("download-Core-pending-pins-hourglass-and-rejects-repeat-without-thumbnail-work", localBar.primaryState == .switching
        && !localBar.isHidden && localBar.alphaValue == 1 && localBar.superview != nil && !localBar.playButton.isEnabled
        && localBar.playButton.accessibilityLabel() == "正在切换壁纸" && localPlayed == [801]
        && download.thumbnailRequestID == organizationRequest && OLDownloadedThumbnailStore.sharedCache.history.count == organizationLoads)
    download.applyPlayingState(isPlaying: false)
    facts.expect("download-pending-wins-over-playing-echo", localBar.primaryState == .switching && !localBar.playButton.isEnabled)
    download.applyPlayingState(isPlaying: true)
    download.applySwitchingState(isSwitching: false)
    facts.expect("download-pending-completion-restores-native-stop", localBar.primaryState == .playing && localBar.playButton.isEnabled)
    let nonRedChrome = PixabayNativeAccentProbe.withNonRedAccent {
        download.applyOrganizationState(isFavorite: false, primaryShowsStop: false)
        download.applyOrganizationState(isFavorite: true, primaryShowsStop: true)
        var matched = false
        download.view.effectiveAppearance.performAsCurrentDrawingAppearance {
            guard let expected = NSColor.controlAccentColor.usingColorSpace(.deviceRGB),
                  let heart = localBar.favoriteButton.contentTintColor?.usingColorSpace(.deviceRGB),
                  let stop = localBar.playButton.contentTintColor?.usingColorSpace(.deviceRGB),
                  let red = NSColor.systemRed.usingColorSpace(.deviceRGB) else { return }
            func same(_ value: NSColor, _ other: NSColor) -> Bool {
                abs(value.redComponent - other.redComponent) < 0.0001
                    && abs(value.greenComponent - other.greenComponent) < 0.0001
                    && abs(value.blueComponent - other.blueComponent) < 0.0001
                    && abs(value.alphaComponent - other.alphaComponent) < 0.0001
            }
            matched = !same(expected, red) && same(heart, expected) && same(stop, expected)
                && localBar.favoriteButton.toolTip == "取消特别喜爱" && localBar.playButton.toolTip == "停止播放"
        }
        return matched
    }
    facts.expect("real-card-heart-and-Stop-resolve-the-native-non-red-accent-without-system-preference-writes", nonRedChrome)
    download.applyOrganizationState(isFavorite: false, primaryShowsStop: false)
    download.applySelectionState(true, multiSelectMode: true)
    localBar.playButton.performClick(nil)
    localBar.favoriteButton.performClick(nil)
    facts.expect("download-multiselect-suppresses-stale-actions", localBar.superview == nil
        && localPlayed == [801] && localFavorite == [801])
    download.configure(entry: downloadModel(802, name: String(repeating: "long current download title ", count: 8) + ".mp4"),
        isSelected: false, isMultiSelectMode: false, isPlaying: true)
    localBar.playButton.performClick(nil)
    localBar.favoriteButton.performClick(nil)
    facts.expect("download-reconfigure-cannot-reuse-old-target", localPlayed == [801,802] && localFavorite == [801,802])
    download.thumbnailView.image = NSImage(size: NSSize(width: 200, height: 400))
    download.layoutThumbnail()
    facts.expect("download-thumbnail-preserves-portrait-aspect-ratio", download.thumbnailView.frame == NSRect(x: 0, y: -120, width: 240, height: 480))
    download.isHovering = true
    download.applyHoverVisibility(true, animated: false)
    localBar.layoutSubtreeIfNeeded()
    facts.expect("visible-download-long-title-marquee-runs", (localBar.titleView.activeMarqueeAnimation != nil) == allowsMotion)
    download.endDisplayingThumbnail()
    facts.expect("offscreen-download-stops-repeating-title-animation", localBar.titleView.activeMarqueeAnimation == nil)
    download.applyPlayingState(isPlaying: false)
    download.applyPlayingState(isPlaying: true)
    facts.expect("offscreen-playing-tick-cannot-restart-title-animation", localBar.titleView.activeMarqueeAnimation == nil)
    let localRequestsBeforeRedisplay = OLDownloadedThumbnailStore.sharedCache.history.count
    download.beginDisplayingThumbnail()
    facts.expect("ready-download-redisplay-resumes-marquee-before-thumbnail-early-return", download.thumbnailView.image != nil
        && OLDownloadedThumbnailStore.sharedCache.history.count == localRequestsBeforeRedisplay
        && (localBar.titleView.activeMarqueeAnimation != nil) == allowsMotion)
    download.view.appearance = NSAppearance(named: .aqua)
    download.refreshTheme()
    let border = NSColor(cgColor: download.hoverOutlineView.layer!.borderColor!)!.usingColorSpace(.deviceRGB)!
    facts.expect("light-appearance-keeps-white-outline", border.redComponent > 0.99 && border.greenComponent > 0.99 && border.blueComponent > 0.99)
    download.applySwitchingState(isSwitching: true)
    download.prepareForReuse()
    localBar.playButton.performClick(nil)
    localBar.favoriteButton.performClick(nil)
    facts.expect("download-reuse-revokes-fixed-ID-actions", download.onPrimaryAction == nil && download.onToggleFavorite == nil
        && localPlayed == [801,802] && localFavorite == [801,802] && !download.isSwitching && localBar.primaryState == .apply)
    var negativePlayed: [Int] = [], negativeFavorite: [Int] = []
    download.onPrimaryAction = { negativePlayed.append($0) }
    download.onToggleFavorite = { negativeFavorite.append($0) }
    download.configure(entry: downloadModel(-1, name: "online_-1.mp4"), isSelected: false, isMultiSelectMode: false, isPlaying: true)
    localBar.playButton.performClick(nil); localBar.favoriteButton.performClick(nil)
    facts.expect("legacy-negative-download-ID-remains-a-valid-native-action-target", negativePlayed == [-1] && negativeFavorite == [-1])
    download.prepareForReuse()
}

@MainActor func pixabayFixedContextMenuActions(_ browser: AppKitOLBrowserItem, _ facts: Facts) {
    browser.prepareForReuse()
    var downloads: [String] = [], applications: [String] = [], favorites: [String] = [], lists: [String] = []
    func organization(_ label: String) -> WallpaperInspectorActions {
        var actions = WallpaperInspectorActions(state: .init(isPlaying: false, isFavorite: false, canPerformPrimary: true,
            canFavorite: true, canOrganize: true, playlistNames: []), onPrimary: {},
            onToggleFavorite: { favorites.append(label) }, onChoosePlaylist: { _ in lists.append(label) })
        actions.makePlaylistMenu = { permitsAction in
            pixabayPlaylistMenu(permitsAction: permitsAction) { lists.append(label) }
        }
        return actions
    }
    func configure(_ item: OnlineLibraryVideoItem, _ label: String, downloading: Bool = false, progress: Double? = nil) {
        browser.configure(item: item, isDownloading: downloading, isDownloaded: false, downloadProgress: progress,
            organization: organization(label), onDownload: { downloads.append(label) }, onSetAsWallpaper: { applications.append(label) })
        layout(browser)
    }
    func invoke(_ menu: NSMenu) {
        for index in [0, 1, 3, 5, 6] {
            pixabayInvokeContextLeaf(menu.items[index], facts)
        }
    }
    let original = browserModel(701, tags: "original", duration: 61, thumbnail: nil)
    configure(original, "original")
    let held = browser.buildContextMenu()!, binding = browser.contextMenuBindingID
    let thumbnail = browser.thumbnailRequestID, openedBefore = PixabayMenuWorkspace.openedURLs.count
    let metadataEcho = browserModel(701, tags: "updated metadata", duration: 90, thumbnail: nil)
    configure(metadataEcho, "same-ID progress", downloading: true, progress: 0.4)
    browser.updateOrganization(organization("same-ID relation"), for: 701)
    invoke(held)
    facts.expect("held-browser-menu-keeps-original-actions-through-same-ID-progress-metadata-and-relationship-echo",
        downloads == ["original"] && applications == ["original"] && favorites == ["original"] && lists == ["original"]
        && browser.contextMenuBindingID == binding && browser.thumbnailRequestID == thumbnail
        && PixabayMenuWorkspace.openedURLs.count == openedBefore + 1
        && PixabayMenuWorkspace.openedURLs.last == URL(string: original.pageURL))

    configure(browserModel(702, thumbnail: nil), "B")
    configure(original, "A returned")
    let beforeReturned = PixabayMenuWorkspace.openedURLs.count
    invoke(held)
    facts.expect("held-browser-source-and-organization-menu-cannot-revive-after-A-B-A",
        downloads == ["original"] && applications == ["original"] && favorites == ["original"] && lists == ["original"]
        && PixabayMenuWorkspace.openedURLs.count == beforeReturned)
    let returned = browser.buildContextMenu()!
    invoke(returned)
    facts.expect("new-browser-menu-after-rebinding-keeps-source-and-organization-actions-reachable",
        downloads == ["original", "A returned"] && applications == downloads && favorites == downloads && lists == downloads
        && PixabayMenuWorkspace.openedURLs.count == beforeReturned + 1)

    browser.prepareForReuse()
    configure(original, "same-ID native reuse")
    let beforeReuse = PixabayMenuWorkspace.openedURLs.count
    invoke(returned)
    facts.expect("prepareForReuse-revokes-held-menu-even-when-next-ID-is-identical",
        downloads == ["original", "A returned"] && applications == downloads && favorites == downloads && lists == downloads
        && PixabayMenuWorkspace.openedURLs.count == beforeReuse)
    let retired = browser.buildContextMenu()!
    browser.endDisplayingThumbnail()
    browser.beginDisplayingThumbnail()
    configure(metadataEcho, "visible again")
    invoke(retired)
    facts.expect("original-display-retirement-revokes-held-menu-after-same-ID-reentry",
        downloads == ["original", "A returned"] && applications == downloads && favorites == downloads && lists == downloads
        && PixabayMenuWorkspace.openedURLs.count == beforeReuse)
    invoke(browser.buildContextMenu()!)
    facts.expect("redisplayed-browser-new-menu-remains-operable-without-thumbnail-or-API-gates",
        downloads == ["original", "A returned", "visible again"] && applications == downloads && favorites == downloads && lists == downloads
        && PixabayMenuWorkspace.openedURLs.count == beforeReuse + 1
        && PixabayMenuWorkspace.openedURLs.last == URL(string: metadataEcho.pageURL))
    browser.prepareForReuse()
}

@MainActor final class PixabayLayoutItems: NSObject, NSCollectionViewDataSource {
    var count = 31
    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { count }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        collectionView.makeItem(withIdentifier: .init("square"), for: indexPath)
    }
}
@MainActor final class PixabayLayoutCell: NSCollectionViewItem { override func loadView() { view = NSView() } }

@MainActor func pixabaySquareLayout(_ facts: Facts) {
    let data = PixabayLayoutItems()
    let collection = NSCollectionView()
    let flow = NSCollectionViewFlowLayout()
    collection.dataSource = data
    collection.collectionViewLayout = flow
    collection.register(PixabayLayoutCell.self, forItemWithIdentifier: .init("square"))
    let window = NSWindow(contentRect: NSRect(x: 14000, y: 14000, width: 1000, height: 600),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = collection
    window.orderFrontRegardless()
    defer { window.orderOut(nil); window.close() }
    for width: CGFloat in [620,1000,2800,1000] {
        for columns in 3...6 {
            window.setContentSize(NSSize(width: width, height: 600))
            let metrics = WallpaperLibraryGridMetrics(clipWidth: width, preferredColumns: columns)
            flow.sectionInset = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
            flow.minimumInteritemSpacing = WallpaperLibraryGridMetrics.horizontalSpacing
            flow.minimumLineSpacing = WallpaperLibraryGridMetrics.verticalSpacing
            let itemSize = NSSize(width: metrics.coverSide, height: metrics.coverSide)
            flow.itemSize = itemSize
            collection.reloadData()
            collection.layoutSubtreeIfNeeded()
            flow.prepare()
            let frames = (0..<data.count).map { flow.layoutAttributesForItem(at: IndexPath(item: $0, section: 0))!.frame }
            let label = "width-\(width)-columns-\(columns)"
            facts.expect(label+"-shared-square-preview-and-cell", itemSize.height == itemSize.width
                && frames.allSatisfy { $0.size == itemSize })
            facts.expect(label+"-row-major-native-columns", frames.prefix(metrics.columns).allSatisfy { $0.minY == frames[0].minY }
                && frames[metrics.columns].minY == frames[0].maxY+10)
            facts.expect(label+"-inset-spacing-and-viewport-boundary", frames[0].minX == 8 && frames[0].minY == 8
                && frames[metrics.columns-1].maxX <= width-8
                && (1..<metrics.columns).allSatisfy { frames[$0].minX-frames[$0-1].maxX >= 8 })
            let rect = NSRect(x: 0, y: frames[metrics.columns].minY+1, width: width, height: 20)
            let visible = flow.layoutAttributesForElements(in: rect).filter { $0.representedElementCategory == .item }
            facts.expect(label+"-native-rect-query-complete", Set(visible.compactMap(\.indexPath))
                == Set(frames.indices.filter { frames[$0].intersects(rect) }.map { IndexPath(item: $0, section: 0) }))
        }
    }
}

@MainActor func browserLayout(_ facts: Facts) {
    let host = CardHost(.browser)
    defer { host.finish() }
    guard let card = host.first() as? AppKitOLBrowserItem else { facts.expect("registered-browser", false); return }
    card.view.frame.size = NSSize(width: 230, height: 232)
    let original = browserModel(4, tags: String(repeating: "very long original title ", count: 8), thumbnail: "layout")
    let cacheBefore = Set(OLThumbnailCache.shared.pending.keys)
    configure(card, original, downloaded: true)
    layout(card)
    let ready = waitUntil { !Set(OLThumbnailCache.shared.pending.keys).subtracting(cacheBefore).isEmpty }
    facts.expect("cache-request-reaches-real-card", ready)
    guard let ticket = Set(OLThumbnailCache.shared.pending.keys).subtracting(cacheBefore).first else { return }
    let decoded = image(5)
    OLThumbnailCache.shared.deliver(ticket, image: decoded)
    facts.expect("cache-hit-published", waitUntil { card.thumbnailView.image === decoded })
    let mask = card.controlBar.titleView.layer?.mask
    facts.expect("long-title-actually-has-mask", mask != nil)
    for _ in 0..<5 { card.viewDidLayout() }
    facts.expect("identical-layout-preserves-mask-object", mask != nil && card.controlBar.titleView.layer?.mask === mask)
    let oldDurationWidth = card.durationBadgeView.frame.width
    let generation = card.thumbnailRequestID
    let requestCount = OLThumbnailCache.shared.history.count
    let changed = browserModel(4, tags: String(repeating: "replacement title ", count: 10), duration: 3661,
        thumbnail: "layout", bytes: 219_152_384, width: 3840)
    card.controlBar.toolTip = "Obsolete metadata hover"
    card.controlBar.titleView.toolTip = "Obsolete title hover"
    card.view.toolTip = "Obsolete card hover"
    card.isSelected = true
    configure(card, changed, downloaded: true)
    layout(card)
    facts.expect("same-ID-title-updates", card.currentTitle == changed.displayTitle
        && card.controlBar.titleView.text == changed.displayTitle)
    facts.expect("same-ID-metadata-updates", card.currentMetadata.contains("3840×1080")
        && card.currentMetadata.contains("61m1s") && card.currentPageURL == changed.pageURL)
    facts.expect("same-ID-metadata-updates-accessibility-and-clears-obsolete-hover-copy", card.controlBar.toolTip == nil
        && card.controlBar.titleView.toolTip == nil && card.view.toolTip == nil
        && card.controlBar.titleView.accessibilityLabel() == changed.displayTitle
        && card.controlBar.titleView.accessibilityHelp() == card.currentMetadata
        && card.currentMetadata.contains("3840×1080") && card.currentMetadata.contains("61m1s"))
    facts.expect("same-size-duration-reflows", card.durationBadgeView.frame.width > oldDurationWidth)
    facts.expect("metadata-change-keeps-image-request", card.thumbnailRequestID == generation
        && OLThumbnailCache.shared.history.count == requestCount && card.thumbnailView.image === decoded)
    facts.expect("content-change-preserves-selection-and-downloaded", card.isSelected && card.isDownloadedState
        && !card.downloadedBadge.isHidden)
    let changedMask = card.controlBar.titleView.layer?.mask
    facts.expect("changed-text-keeps-valid-fade-mask", changedMask != nil
        && changedMask?.frame == card.controlBar.titleView.bounds)
    card.viewDidLayout()
    facts.expect("changed-layout-is-cached", changedMask != nil && card.controlBar.titleView.layer?.mask === changedMask)
    let oldPixels = card.requestedPixelLimit
    card.view.frame.size = NSSize(width: 420, height: 422)
    layout(card)
    facts.expect("resize-updates-real-square-container", close(card.imageContainer.frame.width, 420)
        && close(card.imageContainer.frame.height, 420) && close(card.imageContainer.frame.maxY, 422))
    facts.expect("larger-card-requests-larger-thumbnail", card.requestedPixelLimit > oldPixels)
    card.prepareForReuse()
    configure(card, browserModel(5, tags: "short", duration: 2, thumbnail: nil))
    layout(card)
    facts.expect("reuse-at-identical-size-rebuilds-content-layout", card.lastLayoutInputs?.size == card.view.bounds.size
        && card.currentTitle == "short" && card.controlBar.titleView.text == "short"
        && card.controlBar.titleView.activeMarqueeAnimation == nil
        && (card.durationBadgeTextLayer.string as? String) == "2s")
    facts.expect("reuse-placeholder-fills-resized-image", !card.placeholderView.isHidden
        && card.placeholderView.frame == card.imageContainer.bounds)
}

@MainActor func downloadsLayout(_ facts: Facts) {
    let host = CardHost(.downloads)
    defer { host.finish() }
    guard let card = host.first() as? AppKitOLDownloadsItem else { facts.expect("registered-downloads", false); return }
    let transport = OLDownloadedThumbnailStore.sharedCache
    card.prepareForReuse()
    card.view.frame.size = NSSize(width: 230, height: 232)
    facts.expect("idle-card-does-not-create-glass-play-badge", card.controlBar == nil)
    let original = downloadModel(7, name: String(repeating: "long original title ", count: 6) + ".mp4")
    let beforeOriginal = transport.history.count
    card.configure(entry: original, isSelected: true, isMultiSelectMode: true, isPlaying: true)
    precondition(waitUntil { transport.history.count == beforeOriginal + 1 })
    let first = transport.history.last!.0
    layout(card)
    facts.expect("multi-select-playing-keeps-hidden-badge-unbuilt", card.controlBar == nil)
    card.applySelectionState(false, multiSelectMode: false)
    guard let firstBadge = card.controlBar else { facts.expect("playing-first-shows-badge", false); return }
    facts.expect("playing-first-shows-badge", !firstBadge.isHidden && firstBadge.alphaValue == 1
        && firstBadge.superview != nil && firstBadge.playButton.contentTintColor == .controlAccentColor
        && firstBadge.primaryState == .apply && firstBadge.playButton.accessibilityLabel() == "设为壁纸")
    let hitPoint = firstBadge.playButton.convert(NSPoint(x: firstBadge.playButton.bounds.midX,
        y: firstBadge.playButton.bounds.midY), to: card.view.superview)
    facts.expect("lazy-badge-has-current-frame-and-native-hit-target", firstBadge.frame.width > 20
        && card.view.hitTest(hitPoint) === firstBadge.playButton)
    card.applySelectionState(true, multiSelectMode: true)
    facts.expect("multi-select-hides-and-disables-badge-target", firstBadge.isHidden
        && card.view.hitTest(hitPoint) !== firstBadge.playButton)
    let mask = card.controlBar?.titleView.layer?.mask
    facts.expect("long-title-actually-has-mask", mask != nil)
    for _ in 0..<5 { card.viewDidLayout() }
    facts.expect("identical-layout-preserves-mask-object", mask != nil && card.controlBar?.titleView.layer?.mask === mask)
    let decoded = image(6)
    transport.deliver(first, image: decoded)
    let generation = card.thumbnailRequestID, requests = transport.history.count
    let metadataOnly = downloadModel(7, name: original.localURL.lastPathComponent, duration: 3661, resolution: "3840×2160")
    firstBadge.toolTip = "Obsolete metadata hover"
    firstBadge.titleView.toolTip = "Obsolete title hover"
    card.view.toolTip = "Obsolete card hover"
    card.configure(entry: metadataOnly, isSelected: true, isMultiSelectMode: true, isPlaying: true)
    layout(card)
    facts.expect("same-ID-metadata-updates", card.currentMetadata.contains("61m1s") && card.currentMetadata.contains("3840×2160"))
    facts.expect("same-ID-real-title-and-accessible-metadata-update-without-hover-copy", firstBadge.titleView.text == metadataOnly.displayTitle
        && firstBadge.toolTip == nil && firstBadge.titleView.toolTip == nil && card.view.toolTip == nil
        && firstBadge.titleView.accessibilityLabel() == metadataOnly.displayTitle
        && firstBadge.titleView.accessibilityHelp() == card.currentMetadata
        && card.currentMetadata.contains("61m1s") && card.currentMetadata.contains("3840×2160"))
    facts.expect("metadata-only-keeps-image-request", card.thumbnailRequestID == generation
        && transport.history.count == requests && card.thumbnailView.image === decoded)
    facts.expect("metadata-keeps-selection-playing-presentation", card.isSelectedState && card.isMultiSelectMode
        && card.isPlaying && firstBadge.playButton.contentTintColor == .controlAccentColor && firstBadge.isHidden && !card.multiSelectBadge.isHidden
        && !card.multiSelectBadgeIcon.isHidden && close(card.imageContainer.layer?.borderWidth ?? 0, 2)
        && close(card.selectionTintView.alphaValue, 0.2))
    let unchangedMask = card.controlBar?.titleView.layer?.mask
    card.configure(entry: metadataOnly, isSelected: false, isMultiSelectMode: false, isPlaying: false)
    card.viewDidLayout()
    facts.expect("equal-content-still-applies-selection-playing", !card.isSelectedState && !card.isMultiSelectMode
        && !card.isPlaying && firstBadge.playButton.contentTintColor == .labelColor && card.multiSelectBadge.isHidden)
    facts.expect("equal-content-keeps-mask-object", unchangedMask != nil && card.controlBar?.titleView.layer?.mask === unchangedMask)
    let renamed = downloadModel(7, name: String(repeating: "replacement title ", count: 7) + ".mp4", duration: 3661)
    card.configure(entry: renamed, isSelected: true, isMultiSelectMode: true, isPlaying: true)
    precondition(waitUntil { transport.history.count == requests + 1 })
    layout(card)
    facts.expect("same-ID-local-title-updates-at-same-size", card.currentTitle == renamed.displayTitle
        && firstBadge.titleView.text == renamed.displayTitle && firstBadge.titleView.toolTip == nil
        && firstBadge.titleView.accessibilityLabel() == renamed.displayTitle && firstBadge.titleView.accessibilityHelp() == card.currentMetadata
        && card.thumbnailRequestID != generation && transport.history.count == requests + 1)
    let beforeFailureFrame = card.placeholderLabel.frame
    let renameRequest = transport.history.last!.0
    transport.deliver(renameRequest, image: nil)
    layout(card)
    let failureFrame = card.placeholderLabel.frame
    facts.expect("same-size-failure-placeholder-reflows", card.placeholderLabel.stringValue == "无法生成预览"
        && !card.placeholderLabel.isHidden && failureFrame.width != beforeFailureFrame.width)
    facts.expect("failure-placeholder-is-centered", abs(failureFrame.midX - card.imageContainer.bounds.midX) <= 0.5
        && abs(failureFrame.midY - card.imageContainer.bounds.midY) <= 0.5)
    let failedGeneration = card.thumbnailRequestID
    let changedBytes = downloadModel(7, name: renamed.localURL.lastPathComponent, bytes: 2_097_152, duration: 3661)
    card.configure(entry: changedBytes, isSelected: true, isMultiSelectMode: true, isPlaying: true)
    facts.expect("same-ID-file-size-change-invalidates-thumbnail", card.thumbnailRequestID != failedGeneration
        && card.placeholderLabel.stringValue == "加载中...")
    card.view.frame.size = NSSize(width: 360, height: 362)
    layout(card)
    facts.expect("resize-updates-real-square-container", close(card.imageContainer.frame.width, 360)
        && close(card.imageContainer.frame.height, 360) && close(card.imageContainer.frame.maxY, 362))
    card.prepareForReuse()
    facts.expect("reuse-retains-one-badge-without-new-allocation", card.controlBar === firstBadge)
    facts.expect("prepare-clears-selection-playing", !card.isSelectedState && !card.isPlaying
        && firstBadge.playButton.contentTintColor == .labelColor && firstBadge.isHidden)
    card.configure(entry: original, isSelected: true, isMultiSelectMode: true, isPlaying: true)
    layout(card)
    facts.expect("same-size-after-reuse-rebuilds-layout", card.lastLayoutInputs?.size == card.view.bounds.size
        && card.controlBar?.titleView.layer?.mask != nil && card.currentTitle == original.displayTitle
        && card.controlBar?.titleView.text == original.displayTitle
        && card.placeholderLabel.stringValue == "加载中...")
    facts.expect("reused-selection-playing-applied", card.isSelectedState && card.isPlaying
        && firstBadge.playButton.contentTintColor == .controlAccentColor && firstBadge.isHidden
        && !card.multiSelectBadge.isHidden && !card.multiSelectBadgeIcon.isHidden)
}
