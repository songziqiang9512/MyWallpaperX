import AppKit
import Combine

/// App-owned assembly for two shared image browsers. Services retain source and publication ownership.
@MainActor final class WallpaperLibraryOnlineImages {
    let wallhaven: OnlineImageBrowserSession
    let pixiv: OnlineImageBrowserSession
    private let workspace: WallpaperLibraryWorkspace
    private let commands: WallpaperLibraryCommands
    private let inspector: WallpaperLibraryInspectorCoordinator
    private let library = OnlineImageLibrary.shared
    private var browsers: [OnlineImageSource: OnlineImageBrowserController] = [:]
    private var subscriptions = Set<AnyCancellable>()
    private var observedPixivScope: String?
    private var login: PixivLoginPanelController?
    private var keyPanel: WallpaperAPIKeyPanelController?
    var isPlaying: ((WallpaperReference) -> Bool)?
    var isSwitching: ((WallpaperReference) -> Bool)?
    weak var window: NSWindow?
    var onChange: (() -> Void)?
    var onClipWidthChange: (() -> Void)?
    var onNavigate: ((WallpaperLibraryPage) -> Void)?
    private var isDisplayed = false
    private var authorOrigin: (page: WallpaperLibraryPage, resetEpoch: UUID)?

    init(workspace: WallpaperLibraryWorkspace, commands: WallpaperLibraryCommands, inspector: WallpaperLibraryInspectorCoordinator) {
        self.workspace = workspace; self.commands = commands; self.inspector = inspector
        wallhaven = .init(source: .wallhaven, library: .shared)
        pixiv = .init(source: .pixiv, library: .shared)
        observedPixivScope = library.pixivScope
        library.$pixivSession.compactMap { $0 }.flatMap { $0.$state.map(\.scopeID).removeDuplicates() }
            .receive(on: DispatchQueue.main).sink { [weak self] _ in
                guard let self else { return }
                let scope = library.pixivScope
                guard scope != observedPixivScope else { return }
                observedPixivScope = scope; authorOrigin = nil; pixiv.resetScope()
                if isDisplayed, workspace.presentation.page == .pixiv { pixiv.enter() }
            }.store(in: &subscriptions)
        library.$wallhavenCredentialRevision.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard let self else { return }
            if inspector.inspectedReference?.provider == .wallhaven { inspector.closeInspector() }
            wallhaven.resetScope()
            if isDisplayed, workspace.presentation.page == .wallhaven { wallhaven.enter() }
        }.store(in: &subscriptions)
        library.$errorMessage.compactMap { $0 }.receive(on: DispatchQueue.main).sink { [weak self] message in
            guard let self else { return }
            workspace.presentation.report(OnlineImageError.message(message)); library.errorMessage = nil
        }.store(in: &subscriptions)
    }

    func session(for page: WallpaperLibraryPage) -> OnlineImageBrowserSession? {
        switch page { case .wallhaven: wallhaven; case .pixiv: pixiv; default: nil }
    }

    func browser(for page: WallpaperLibraryPage) -> OnlineImageBrowserController? {
        guard let session = session(for: page) else { return nil }
        let source = session.source
        if let browser = browsers[source] { return browser }
        let browser = OnlineImageBrowserController(session: session, library: library)
        browser.onInspect = { [weak self] artwork in
            self?.inspector.inspectOnlineArtwork(artwork, onAuthor: source == .pixiv ? { [weak self] id in
                self?.openAuthor(id, from: .pixiv)
            } : nil)
        }
        browser.onPreview = { [weak self] content in _ = self?.inspector.preview(content: content) }
        browser.onSelectionChange = { [weak self, weak session] content in
            guard let self else { return }
            let artwork = content.flatMap { content in
                session?.state.items.first { $0.firstAssetID.reference == content.providerReference }
            }
            inspector.syncSelection(content: content, artwork: artwork, onAuthor: source == .pixiv ? { [weak self] id in
                self?.openAuthor(id, from: .pixiv)
            } : nil)
        }
        browser.onRestoreColumns = { [weak self] columns in
            guard let self else { return }
            var query = workspace.presentation.queryState; query.preferredColumns = columns
            _ = workspace.presentation.setQueryState(query)
        }
        browser.makePrimary = { [weak self] content in self?.commands.makePrimaryAction(for: content) }
        browser.makeFavorite = { [weak self] content in self?.commands.makeFavoriteAction([content.reference]) }
        browser.isFavorite = { [weak self] in self?.workspace.isFavorite($0) == true }
        browser.isPlaying = { [weak self] in self?.isPlaying?($0) == true }
        browser.isSwitching = { [weak self] in self?.isSwitching?($0) == true }
        browser.makeMenu = { [weak self] content in self?.menu(content, source: source) }
        browser.onClipWidthChange = { [weak self] _ in self?.onClipWidthChange?() }
        var previousQuery = session.state.query
        browser.onStateChange = { [weak self] in
            guard let self else { return }
            if previousQuery != session.state.query {
                previousQuery = session.state.query
                if case .pixiv(let query) = session.state.query, query.authorID == nil { authorOrigin = nil }
                if workspace.presentation.page == page { inspector.closeInspector(); inspector.closePreview() }
            }
            onChange?()
        }
        browsers[source] = browser
        return browser
    }

    func refreshOrganization() { browsers.values.forEach { $0.refreshOrganization() } }
    func setVisible(_ visible: Bool, page: WallpaperLibraryPage) {
        let changed = isDisplayed != visible; isDisplayed = visible
        for (source, browser) in browsers {
            browser.setPageVisible(visible && source == (page == .wallhaven ? .wallhaven : .pixiv))
        }
        if changed { onChange?() }
    }
    var selectedContent: WallpaperContentItem? { browser(for: workspace.presentation.page)?.selectedContent }
    func inspectSelected() {
        guard let content = selectedContent, let session = session(for: workspace.presentation.page),
              let artwork = session.state.items.first(where: { $0.firstAssetID.reference == content.providerReference }) else { return }
        inspector.inspectOnlineArtwork(artwork, onAuthor: session.source == .pixiv ? { [weak self] id in
            self?.openAuthor(id, from: .pixiv)
        } : nil)
    }
    func previewSelected() { if let content = selectedContent { _ = inspector.preview(content: content) } }
    func selectedOrganizationActions() -> WallpaperInspectorActions? {
        let page = workspace.presentation.page
        guard let browser = browser(for: page), let content = browser.selectedContent,
              content.publishedAvailability.isAvailable else { return nil }
        let primary = commands.makeApplyAction(for: content), favorite = commands.makeFavoriteAction([content.reference])
        let epoch = workspace.relationships.resetEpoch, reference = content.reference
        func accepts() -> Bool {
            isDisplayed && WallpaperLibrarySheetPresentation.permitsInput(in: window)
                && workspace.presentation.page == page && workspace.relationships.resetEpoch == epoch
                && browser.selectedContent?.reference == reference
        }
        return .init(state: .init(isPlaying: isPlaying?(reference) == true, isSwitching: isSwitching?(reference) == true, isFavorite: workspace.isFavorite(reference),
            canPerformPrimary: primary != nil && isSwitching?(reference) != true, canFavorite: favorite != nil,
            canOrganize: commands.canOrganize && content.capabilities.contains(.organize), playlistNames: []),
            onPrimary: { if accepts() { primary?() } }, onToggleFavorite: { if accepts() { favorite?() } },
            onChoosePlaylist: { [weak commands] anchor in if accepts() { commands?.choosePlaylist([reference], anchor: anchor) } })
    }
    func refreshCurrent() { session(for: workspace.presentation.page)?.refresh() }
    func hasReturnContext(for page: WallpaperLibraryPage) -> Bool {
        session(for: page)?.hasReturnContext == true
            || (page == .pixiv && authorOrigin?.resetEpoch == workspace.relationships.resetEpoch)
    }

    func openAuthor(_ id: String, from page: WallpaperLibraryPage) {
        if page != .pixiv { authorOrigin = (page, workspace.relationships.resetEpoch) }
        inspector.closeInspector(); inspector.closePreview()
        _ = browser(for: .pixiv) // Capture any browse scroll before entering its author query.
        pixiv.openAuthor(id)
        if workspace.presentation.page != .pixiv { onNavigate?(.pixiv) }
        onChange?()
    }

    func goBack() {
        let origin = authorOrigin.flatMap { $0.resetEpoch == workspace.relationships.resetEpoch ? $0.page : nil }
        if workspace.presentation.page == .pixiv {
            authorOrigin = nil
            pixiv.goBack()
            if let origin { onNavigate?(origin) }
        } else { session(for: workspace.presentation.page)?.goBack() }
        onChange?()
    }

    func close() {
        isDisplayed = false
        login?.close(); keyPanel?.close()
        browsers.values.forEach { $0.setPageVisible(false); $0.session.leave() }
    }

    func presentAccount(settings: Bool = false) {
        guard let window else { return }
        if workspace.presentation.page == .wallhaven { presentKey(in: window); return }
        Task { [weak self, weak window] in
            guard let self, let window else { return }
            _ = await library.preparePixiv()
            guard isDisplayed, window.isVisible, workspace.presentation.page == .pixiv,
                  let session = library.pixivSession else { return }
            if login == nil { login = PixivLoginPanelController(session: session) }
            guard let controller = login else { return }
            controller.present(in: window, settings: settings) { [weak self, weak controller] in
                guard let self, let controller, login === controller else { return }
                login = nil
                onChange?()
            }
        }
    }

    func logout() {
        login?.close(); login = nil
        Task { [weak self] in
            guard let self else { return }
            let previous = library.pixivScope
            await library.logoutPixiv()
            if previous == library.pixivScope {
                authorOrigin = nil; pixiv.resetScope()
                if isDisplayed, workspace.presentation.page == .pixiv { pixiv.enter() }
            }
            onChange?()
        }
    }

    private func presentKey(in window: NSWindow) {
        if keyPanel == nil {
            keyPanel = WallpaperAPIKeyPanelController(title: "Wallhaven API Key",
                message: "匿名即可浏览安全内容。填写自己的 API Key 后可按账号权限浏览；Key 保存在系统钥匙串中。",
                helpURL: URL(string: "https://wallhaven.cc/settings/account")!) { [weak self] key in
                    guard let self else { return }
                    try await library.setWallhavenKey(key)
                }
        }
        guard let controller = keyPanel else { return }
        controller.present(in: window) { [weak self, weak controller] in
            guard let self, let controller, keyPanel === controller else { return }
            keyPanel = nil
            onChange?()
        }
    }

    private func menu(_ content: WallpaperContentItem, source: OnlineImageSource) -> NSMenu? {
        let session = source == .wallhaven ? wallhaven : pixiv
        guard let artwork = session.state.items.first(where: { $0.firstAssetID.reference == content.providerReference }) else { return nil }
        let menu = content.publishedAvailability.isPublishedLocally
            ? commands.contextMenu(for: [content], includeRecoverySourcePage: false) ?? NSMenu() : NSMenu()
        menu.autoenablesItems = false
        let downloading = library.progress[artwork.firstAssetID] != nil
        if content.publishedAvailability == .remote, content.capabilities.contains(.download) {
            let download = ActionMenuItem(title: "下载原图", symbol: "arrow.down") { [weak self] in self?.downloadFirst(artwork) }
            let apply = ActionMenuItem(title: "下载并设为壁纸", symbol: "play.fill") { [weak self] in self?.downloadFirst(artwork, apply: true) }
            download.isEnabled = !downloading; apply.isEnabled = !downloading
            menu.addItem(download); menu.addItem(apply)
        }
        if downloading, !content.publishedAvailability.isPublishedLocally {
            menu.addItem(ActionMenuItem(title: "取消下载", symbol: "xmark") { [weak self] in self?.library.cancel(artwork.firstAssetID) })
        }
        menu.addItem(ActionMenuItem(title: "打开原网页", symbol: "safari") { NSWorkspace.shared.open(artwork.sourceURL) })
        if source == .pixiv, let id = artwork.authorID {
            menu.addItem(ActionMenuItem(title: "查看作者作品", symbol: "person") { [weak self] in self?.openAuthor(id, from: .pixiv) })
        }
        menu.requireAppActionPermission { [weak self] in
            guard let self, isDisplayed, workspace.presentation.page == (source == .wallhaven ? .wallhaven : .pixiv) else { return false }
            return WallpaperLibrarySheetPresentation.permitsInput(in: window)
        }
        return menu
    }

    private func downloadFirst(_ artwork: OnlineImageArtwork, apply: Bool = false) {
        library.downloadArtwork(artwork, apply: apply)
    }
}
