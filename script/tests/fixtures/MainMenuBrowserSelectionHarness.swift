import AppKit

// Actual Composition factories and fixed-selection consumption run with the
// actual menu/Delegate. Only module commands and renderer facts are leaves;
// their real primary behavior is covered by the existing keyboard gates.
@MainActor final class MainMenuBrowserWorkspace {
    struct Relationships { var resetEpoch = UUID() }
    let presentation: WallpaperLibraryPresentation
    var relationships = Relationships()
    var playing: WallpaperReference?
    init(_ presentation: WallpaperLibraryPresentation) { self.presentation = presentation }
    func isPlaying(_ reference: WallpaperReference) -> Bool { playing == reference }
}
struct MainMenuSteamItem { let id: String }
struct MainMenuPixabayItem { let id: Int }
@MainActor final class MainMenuBrowserModule<Item> {
    var selectedItem: Item?
    var canPerformSelectedPrimaryAction = false
    var onPrimary: (() -> Void)?
    var primaryCalls = 0, inspections = 0
    var selectedPrimaryAction: (() -> Void)? {
        guard selectedItem != nil, canPerformSelectedPrimaryAction else { return nil }
        let primary = onPrimary
        return { [weak self] in self?.primaryCalls += 1; primary?() }
    }
    @discardableResult func performSelectedPrimaryAction() -> Bool {
        guard selectedItem != nil, canPerformSelectedPrimaryAction else { return false }
        primaryCalls += 1; onPrimary?(); return true
    }
    @discardableResult func inspectSelectedItem() -> Bool {
        guard selectedItem != nil else { return false }
        inspections += 1; return true
    }
}
@MainActor final class MainMenuBrowserSteam {
    final class Progress {
        enum Phase { case downloading, failed }
        struct Snapshot { var phase: Phase }
        var snapshots: [String: Snapshot] = [:]
        func snapshot(for id: String) -> Snapshot? { snapshots[id] }
    }
    var navigationVersion = 0
    let downloadProgressStore = Progress()
}
@MainActor final class MainMenuOnlineImages {
    let presentation: WallpaperLibraryPresentation
    private var content: WallpaperContentItem?
    var selectedContent: WallpaperContentItem? {
        get { presentation.page == .wallhaven || presentation.page == .pixiv ? content : nil }
        set { content = newValue }
    }
    var primary: (title: String, action: () -> Void)?
    var inspections = 0, previews = 0
    init(_ presentation: WallpaperLibraryPresentation) { self.presentation = presentation }
    func selectedPrimaryAction() -> (title: String, action: () -> Void)? { selectedContent == nil ? nil : primary }
    func inspectSelected() { inspections += 1 }
    func previewSelected() { previews += 1 }
}
@MainActor final class MainMenuBrowserComposition {
    let workspace: MainMenuBrowserWorkspace
    let steam = MainMenuBrowserSteam()
    let steamBrowserContent = MainMenuBrowserModule<MainMenuSteamItem>()
    let pixabayBrowserContent = MainMenuBrowserModule<MainMenuPixabayItem>()
    let onlineImages: MainMenuOnlineImages
    var downloadedContent: [WallpaperReference: WallpaperContentItem] = [:]
    var isVisible = true, permitsInput = true
    init(presentation: WallpaperLibraryPresentation) {
        workspace = .init(presentation); onlineImages = .init(presentation)
    }
    // ACTUAL_BROWSER_MENU_FACTORIES
}

@MainActor func runMainMenuBrowserSelectionChecks(controller: MainWindowController, delegate: AppDelegate,
    image: WallpaperContentItem, item: (MainMenuCommand) -> NSMenuItem, send: (MainMenuCommand) -> Bool) -> [String: Bool] {
    var checks: [String: Bool] = [:]
    let commands = controller.libraryCommands, browser = controller.browser
    controller.libraryPresentation.page = .images; commands.selection = [image]
    let applies = commands.applies, stops = commands.stops
    _ = delegate.validateMenuItem(item(.applyWallpaper))
    controller.libraryPresentation.selectionState.isSelecting = true
    _ = send(.applyWallpaper)
    checks["local-selection-mode-rejects-even-held-single-item-return"] = !delegate.validateMenuItem(item(.applyWallpaper))
        && commands.applies == applies && commands.stops == stops
    controller.libraryPresentation.selectionState.isSelecting = false
    commands.workspace.playing = image.reference
    let stopping = delegate.validateMenuItem(item(.applyWallpaper)) && item(.applyWallpaper).title == "停止播放"
    _ = send(.applyWallpaper)
    checks["local-menu-return-shares-fixed-stop-primary"] = stopping && commands.stops == stops + 1 && commands.applies == applies
    commands.workspace.playing = nil
    for action in [MainMenuCommand.applyWallpaper, .info, .preview, .addToPlaylist, .deleteSelected, .revealOrRefresh] { _ = delegate.validateMenuItem(item(action)) }
    let localCounts = [commands.applies, commands.infos, commands.previews, commands.adds, commands.deletes, commands.reveals]
    commands.selection = []
    for action in [MainMenuCommand.applyWallpaper, .info, .preview, .addToPlaylist, .deleteSelected, .revealOrRefresh] { _ = send(action) }
    checks["held-local-primary-info-preview-playlist-delete-reveal-refuse-a-new-selection-session"] =
        [commands.applies, commands.infos, commands.previews, commands.adds, commands.deletes, commands.reveals] == localCounts
    commands.selection = [image]
    var imagePrimaries = 0
    for page in [WallpaperLibraryPage.workshop, .pixabay, .wallhaven, .pixiv] {
        controller.libraryPresentation.page = page
        let provider: WallpaperProvider = page == .workshop ? .steamWorkshop : page == .pixabay ? .pixabay : page == .wallhaven ? .wallhaven : .pixiv
        let reference = WallpaperReference(provider: provider, sourceID: "71")
        let content = WallpaperContentItem(reference: reference, providerReference: reference, locator: .init(mediaKind: .image),
            title: "Current remote card", kind: .image, publishedAvailability: .remote, capabilities: [.download, .inspect, .quickLook],
            metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
        browser.steamBrowserContent.selectedItem = .init(id: "71")
        browser.pixabayBrowserContent.selectedItem = .init(id: 71)
        browser.steamBrowserContent.canPerformSelectedPrimaryAction = true
        browser.pixabayBrowserContent.canPerformSelectedPrimaryAction = true
        browser.onlineImages.selectedContent = content
        browser.onlineImages.primary = ("下载原图", { imagePrimaries += 1 })
        let before = [browser.steamBrowserContent.primaryCalls, browser.pixabayBrowserContent.primaryCalls, imagePrimaries]
        let infoBefore = [browser.steamBrowserContent.inspections, browser.pixabayBrowserContent.inspections, browser.onlineImages.inspections]
        let previewBefore = browser.onlineImages.previews
        let enabled = delegate.validateMenuItem(item(.applyWallpaper)) && delegate.validateMenuItem(item(.info))
        let title = item(.applyWallpaper).title
        let previewEnabled = delegate.validateMenuItem(item(.preview))
        _ = send(.applyWallpaper); _ = send(.info); _ = send(.preview)
        let after = [browser.steamBrowserContent.primaryCalls, browser.pixabayBrowserContent.primaryCalls, imagePrimaries]
        let infoAfter = [browser.steamBrowserContent.inspections, browser.pixabayBrowserContent.inspections, browser.onlineImages.inspections]
        let index = page == .workshop ? 0 : page == .pixabay ? 1 : 2
        checks["remote-return-download-and-info-use-current-module-\(page.persistenceKey)"] = enabled && after[index] == before[index] + 1
            && infoAfter[index] == infoBefore[index] + 1
            && title == (page == .workshop ? "下载壁纸" : page == .pixabay ? "下载视频" : "下载原图")
            && commands.applies == localCounts[0] && commands.infos == localCounts[1]
        checks["space-only-consumes-existing-online-image-preview-\(page.persistenceKey)"] = previewEnabled == (index == 2)
            && browser.onlineImages.previews == previewBefore + (index == 2 ? 1 : 0)
            && commands.previews == localCounts[2]
        for action in [MainMenuCommand.applyWallpaper, .info, .preview] { _ = delegate.validateMenuItem(item(action)) }
        let heldCounts = [browser.steamBrowserContent.primaryCalls, browser.pixabayBrowserContent.primaryCalls, imagePrimaries,
            browser.steamBrowserContent.inspections, browser.pixabayBrowserContent.inspections, browser.onlineImages.inspections, browser.onlineImages.previews]
        browser.steamBrowserContent.selectedItem = .init(id: "72")
        browser.pixabayBrowserContent.selectedItem = .init(id: 72)
        browser.onlineImages.selectedContent = nil
        for action in [MainMenuCommand.applyWallpaper, .info, .preview] { _ = send(action) }
        checks["held-remote-primary-info-preview-cannot-retarget-current-card-\(page.persistenceKey)"] = heldCounts ==
            [browser.steamBrowserContent.primaryCalls, browser.pixabayBrowserContent.primaryCalls, imagePrimaries,
             browser.steamBrowserContent.inspections, browser.pixabayBrowserContent.inspections, browser.onlineImages.inspections, browser.onlineImages.previews]
        browser.steamBrowserContent.selectedItem = nil; browser.pixabayBrowserContent.selectedItem = nil
        checks["empty-remote-selection-cannot-borrow-local-primary-or-info-\(page.persistenceKey)"] =
            !delegate.validateMenuItem(item(.applyWallpaper)) && !delegate.validateMenuItem(item(.info))
    }
    controller.libraryPresentation.page = .workshop
    browser.steamBrowserContent.selectedItem = .init(id: "71")
    _ = delegate.validateMenuItem(item(.applyWallpaper)); _ = delegate.validateMenuItem(item(.info))
    let primary = browser.steamBrowserContent.primaryCalls, inspections = browser.steamBrowserContent.inspections
    browser.steam.navigationVersion += 1
    _ = send(.applyWallpaper); _ = send(.info)
    checks["held-steam-menu-same-id-cannot-cross-author-or-personal-navigation"] = browser.steamBrowserContent.primaryCalls == primary
        && browser.steamBrowserContent.inspections == inspections
    for revoke in [0, 1, 2, 3] {
        _ = delegate.validateMenuItem(item(.applyWallpaper))
        switch revoke {
        case 0: browser.isVisible = false
        case 1: browser.permitsInput = false
        case 2: browser.workspace.relationships.resetEpoch = UUID()
        default: controller.libraryPresentation.page = .pixabay
        }
        _ = send(.applyWallpaper)
        checks["held-browser-primary-revokes-visibility-modal-reset-page-\(revoke)"] = browser.steamBrowserContent.primaryCalls == primary
        browser.isVisible = true; browser.permitsInput = true; controller.libraryPresentation.page = .workshop
    }
    browser.steamBrowserContent.canPerformSelectedPrimaryAction = false
    checks["busy-module-primary-menu-disabled-without-falling-through-to-local"] = !delegate.validateMenuItem(item(.applyWallpaper))
    _ = send(.applyWallpaper)
    checks["busy-direct-return-cannot-reenter-module-or-borrow-local-selection"] = browser.steamBrowserContent.primaryCalls == primary && commands.applies == localCounts[0]
    browser.steamBrowserContent.canPerformSelectedPrimaryAction = true
    let steamReference = WallpaperReference(provider: .steamWorkshop, sourceID: "71")
    browser.workspace.playing = steamReference
    checks["steam-menu-primary-title-tracks-existing-stop-capability"] = delegate.validateMenuItem(item(.applyWallpaper)) && item(.applyWallpaper).title == "停止播放"
    browser.workspace.playing = nil
    browser.steam.downloadProgressStore.snapshots["71"] = .init(phase: .failed)
    checks["steam-menu-failed-update-title-preserves-retry"] = delegate.validateMenuItem(item(.applyWallpaper)) && item(.applyWallpaper).title == "重试下载"
    browser.steam.downloadProgressStore.snapshots = [:]
    for page in [WallpaperLibraryPage.workshop, .pixabay] {
        controller.libraryPresentation.page = page
        let reference = WallpaperReference(provider: page == .workshop ? .steamWorkshop : .pixabay, sourceID: "71")
        var playing = true, lateStops = 0, plays = 0, downloads = 0
        let stop = { if playing { lateStops += 1; playing = false } }
        let play = { plays += 1 }
        browser.steamBrowserContent.selectedItem = .init(id: "71")
        browser.pixabayBrowserContent.selectedItem = .init(id: 71)
        browser.pixabayBrowserContent.canPerformSelectedPrimaryAction = true
        browser.steamBrowserContent.onPrimary = stop; browser.pixabayBrowserContent.onPrimary = stop
        browser.downloadedContent[reference] = .init(reference: reference, providerReference: reference, locator: .init(mediaKind: .video),
            title: "Playing download", kind: .video, publishedAvailability: .available, capabilities: [.play],
            metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
        browser.workspace.playing = reference
        let heldStop = delegate.validateMenuItem(item(.applyWallpaper)) && item(.applyWallpaper).title == "停止播放"
        playing = false; browser.workspace.playing = nil
        browser.steamBrowserContent.onPrimary = play; browser.pixabayBrowserContent.onPrimary = play
        _ = send(.applyWallpaper)
        checks["held-stop-menu-keeps-original-primary-instead-of-replaying-\(page.persistenceKey)"] = heldStop && lateStops == 0 && plays == 0
        _ = delegate.validateMenuItem(item(.applyWallpaper)); _ = send(.applyWallpaper)
        checks["fresh-validation-can-use-the-new-primary-\(page.persistenceKey)"] = plays == 1 && item(.applyWallpaper).title == "设为壁纸"
        browser.downloadedContent.removeValue(forKey: reference)
        browser.steamBrowserContent.onPrimary = { downloads += 1 }
        browser.pixabayBrowserContent.onPrimary = { downloads += 1 }
        let heldDownload = delegate.validateMenuItem(item(.applyWallpaper))
        browser.downloadedContent[reference] = .init(reference: reference, providerReference: reference, locator: .init(mediaKind: .video),
            title: "Finished download", kind: .video, publishedAvailability: .available, capabilities: [.play],
            metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
        browser.steamBrowserContent.onPrimary = play; browser.pixabayBrowserContent.onPrimary = play
        _ = send(.applyWallpaper)
        checks["held-download-menu-cannot-apply-a-just-finished-item-\(page.persistenceKey)"] = heldDownload && downloads == 1 && plays == 1
        if page == .workshop { _ = browser.steamBrowserContent.performSelectedPrimaryAction() }
        else { _ = browser.pixabayBrowserContent.performSelectedPrimaryAction() }
        checks["fresh-return-still-uses-current-primary-\(page.persistenceKey)"] = plays == 2
    }
    return checks
}
