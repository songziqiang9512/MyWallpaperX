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
    var opensDetailsOnSingleClick: () -> Bool = { false }
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
    private var authorOrigins: [OnlineImageSource: (page: WallpaperLibraryPage, resetEpoch: UUID)] = [:]

    init(workspace: WallpaperLibraryWorkspace, commands: WallpaperLibraryCommands, inspector: WallpaperLibraryInspectorCoordinator) {
        self.workspace = workspace; self.commands = commands; self.inspector = inspector
        wallhaven = .init(source: .wallhaven, library: .shared)
        pixiv = .init(source: .pixiv, library: .shared)
        observedPixivScope = library.pixivScope
        inspector.onPreviewLoadingChange = { [weak self] in
            self?.browsers.values.forEach { $0.refreshPreviewLoading() }
        }
        library.$pixivSession.compactMap { $0 }.flatMap { $0.$state.removeDuplicates() }
            .receive(on: DispatchQueue.main).sink { [weak self] _ in
                guard let self else { return }
                let scope = library.pixivScope
                if scope != observedPixivScope {
                    observedPixivScope = scope; authorOrigins[.pixiv] = nil
                    inspector.revokeRemotePreview(source: .pixiv); pixiv.resetScope()
                    if isDisplayed, workspace.presentation.page == .pixiv { pixiv.enter() }
                }
                onChange?()
            }.store(in: &subscriptions)
        library.$wallhavenAccount.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.onChange?()
        }.store(in: &subscriptions)
        library.$wallhavenCredentialRevision.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard let self else { return }
            if inspector.inspectedReference?.provider == .wallhaven { inspector.closeInspector() }
            authorOrigins[.wallhaven] = nil; inspector.revokeRemotePreview(source: .wallhaven)
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

    var pixivAccountStatus: String {
        guard let state = library.pixivSession?.state else { return "未登录（匿名浏览）" }
        let accountName = state.identity.map { identity in
            let name = identity.displayName.flatMap { $0.isEmpty ? nil : $0 }
            return name.map { "\($0)（\(identity.userID)）" } ?? identity.userID
        }
        switch state.phase {
        case .anonymous: return "未登录（匿名浏览）"
        case .checking: return accountName.map { "已登录：\($0) · 正在更新账号信息…" } ?? "正在读取账号信息…"
        case .unknown: return accountName.map { "已登录：\($0) · 资料暂不可用" } ?? "会话状态待确认"
        case .authenticated: return accountName.map { "已登录：\($0)" } ?? "会话状态待确认"
        }
    }

    func accountStatus(for source: OnlineImageSource) -> [String] {
        guard source == .wallhaven else { return [pixivAccountStatus] }
        switch library.wallhavenAccount {
        case .unread: return ["尚未读取 API Key 状态"]
        case .unconfigured: return ["未配置 API Key · 可匿名浏览"]
        case .saved: return ["已保存 API Key", "收藏信息尚未读取"]
        case .loading: return ["已保存 API Key", "正在读取收藏信息…"]
        case .ready(let collections):
            return ["已保存 API Key", "已取得 \(collections.count) 个收藏集"]
                + collections.map { "\($0.label) · \($0.count) 张" }
        case .unavailable(let message): return ["已保存 API Key", "收藏信息暂不可用：" + message]
        }
    }

    func canRefreshAccount(_ source: OnlineImageSource) -> Bool {
        if source == .pixiv { return library.pixivSession?.state.phase != .checking }
        return library.wallhavenAccount.hasStoredKey != false && library.wallhavenAccount != .loading
    }

    var hasPixivIdentity: Bool { library.pixivSession?.state.identity != nil }
    var canLogoutPixiv: Bool { library.pixivSession.map { $0.state.phase != .anonymous } == true }

    func refreshAccountInformation(_ source: OnlineImageSource) {
        guard isDisplayed, workspace.presentation.page == page(for: source) else { return }
        if source == .wallhaven { library.refreshWallhavenAccount(); return }
        Task { [weak self] in
            guard let self else { return }
            _ = await library.preparePixiv()
            await library.pixivSession?.refreshAccountInformation()
        }
    }

    func openMyPixivWorks() {
        guard let identity = library.pixivSession?.state.identity else { return }
        openAuthor(.init(source: .pixiv, id: identity.userID, name: identity.displayName), from: .pixiv)
    }

    func openPixivProfile() {
        guard let identity = library.pixivSession?.state.identity,
              let url = URL(string: "https://www.pixiv.net/users/" + identity.userID) else { return }
        NSWorkspace.shared.open(url)
    }

    func browser(for page: WallpaperLibraryPage) -> OnlineImageBrowserController? {
        guard let session = session(for: page) else { return nil }
        let source = session.source
        if let browser = browsers[source] { return browser }
        let browser = OnlineImageBrowserController(session: session, library: library)
        browser.opensDetailsOnSingleClick = { [weak self] in self?.opensDetailsOnSingleClick() == true }
        browser.onInspect = { [weak self, weak browser] artwork in
            self?.inspector.inspectOnlineArtwork(artwork, onAuthor: { [weak self] author in
                self?.openAuthor(author, from: page)
            }, thumbnailPixelSize: browser?.thumbnailPixelSize ?? 800)
        }
        browser.onPreview = { [weak self] content in _ = self?.inspector.preview(content: content) }
        browser.isPreviewLoading = { [weak self] reference in self?.inspector.loadingPreviewReference == reference }
        browser.onEscape = { [weak self] in
            guard let self else { return }
            if inspector.previewReference != nil { inspector.closePreview() }
            else { inspector.closeInspector() }
        }
        browser.onSelectionChange = { [weak self, weak session, weak browser] content in
            guard let self else { return }
            let artwork = content.flatMap { content in
                session?.state.items.first { $0.firstAssetID.reference == content.providerReference }
            }
            inspector.syncSelection(content: content, artwork: artwork, onAuthor: { [weak self] author in
                self?.openAuthor(author, from: page)
            }, thumbnailPixelSize: browser?.thumbnailPixelSize ?? 800)
        }
        browser.onRestoreColumns = { [weak self] columns in
            guard let self else { return }
            var query = workspace.presentation.queryState; query.preferredColumns = columns
            _ = workspace.presentation.setQueryState(query)
        }
        browser.makePrimary = { [weak self] content in self?.commands.makePrimaryAction(for: content) }
        browser.isPlaying = { [weak self] in self?.isPlaying?($0) == true }
        browser.isSwitching = { [weak self] in self?.isSwitching?($0) == true }
        browser.makeMenu = { [weak self] content in self?.menu(content, source: source) }
        browser.onClipWidthChange = { [weak self] _ in self?.onClipWidthChange?() }
        var previousQuery = session.state.query
        browser.onStateChange = { [weak self] in
            guard let self else { return }
            if previousQuery != session.state.query {
                previousQuery = session.state.query
                if session.state.query.authorIdentifier == nil { authorOrigins[source] = nil }
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
            if !visible || page != self.page(for: source) { inspector.revokeRemotePreview(source: source) }
            browser.setPageVisible(visible && source == (page == .wallhaven ? .wallhaven : .pixiv))
        }
        if changed { onChange?() }
    }
    var selectedContent: WallpaperContentItem? { browser(for: workspace.presentation.page)?.selectedContent }
    func inspectSelected() {
        guard let content = selectedContent, let session = session(for: workspace.presentation.page),
              let artwork = session.state.items.first(where: { $0.firstAssetID.reference == content.providerReference }) else { return }
        inspector.inspectOnlineArtwork(artwork, onAuthor: { [weak self] author in
            guard let self else { return }
            self.openAuthor(author, from: self.workspace.presentation.page)
        }, thumbnailPixelSize: browsers[session.source]?.thumbnailPixelSize ?? 800)
    }
    func previewSelected() { if let content = selectedContent { _ = inspector.preview(content: content) } }
    func selectedPrimaryAction() -> (title: String, action: () -> Void)? {
        guard let content = selectedContent, isSwitching?(content.reference) != true else { return nil }
        if content.publishedAvailability.isPublishedLocally {
            let title = workspace.isPlaying(content.reference) ? "停止播放" : content.capabilities.contains(.play) ? "设为壁纸" : "重新下载"
            return commands.makePrimaryAction(for: content).map { (title, $0) }
        }
        guard content.capabilities.contains(.download), let session = session(for: workspace.presentation.page),
              let artwork = session.state.items.first(where: { $0.firstAssetID.reference == content.providerReference }),
              library.progress[artwork.firstAssetID] == nil else { return nil }
        return ("下载原图", { [weak self] in self?.library.downloadArtwork(artwork) })
    }
    func selectedOrganizationActions() -> WallpaperInspectorActions? {
        let page = workspace.presentation.page
        guard let browser = browser(for: page), let content = browser.selectedContent,
              content.publishedAvailability.isAvailable else { return nil }
        let primary = commands.makePrimaryAction(for: content), favorite = commands.makeFavoriteAction([content.reference])
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
    func hasReturnContext(for page: WallpaperLibraryPage) -> Bool {
        guard let session = session(for: page) else { return false }
        return session.hasReturnContext || authorOrigins[session.source]?.resetEpoch == workspace.relationships.resetEpoch
    }

    private func page(for source: OnlineImageSource) -> WallpaperLibraryPage { source == .wallhaven ? .wallhaven : .pixiv }

    func openAuthor(_ author: OnlineImageAuthor, from origin: WallpaperLibraryPage) {
        let target = page(for: author.source)
        if origin != target { authorOrigins[author.source] = (origin, workspace.relationships.resetEpoch) }
        inspector.closeInspector(); inspector.closePreview()
        _ = browser(for: target) // Capture this source's current scroll before entering its author query.
        session(for: target)?.openAuthor(author)
        if workspace.presentation.page != target { onNavigate?(target) }
        onChange?()
    }

    func goBack() {
        guard let session = session(for: workspace.presentation.page) else { return }
        let origin = authorOrigins.removeValue(forKey: session.source)
        session.goBack()
        if let origin, origin.resetEpoch == workspace.relationships.resetEpoch { onNavigate?(origin.page) }
        onChange?()
    }

    func close() {
        isDisplayed = false
        login?.close(); keyPanel?.close()
        browsers.values.forEach { $0.setPageVisible(false); $0.session.leave() }
    }

    func presentAccount(settings: Bool = false) {
        guard let window else { return }
        inspector.closePreview()
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
                authorOrigins[.pixiv] = nil; pixiv.resetScope()
                if isDisplayed, workspace.presentation.page == .pixiv { pixiv.enter() }
            }
            onChange?()
        }
    }

    private func presentKey(in window: NSWindow) {
        if keyPanel == nil {
            keyPanel = WallpaperAPIKeyPanelController(title: "Wallhaven API Key",
                message: "匿名即可浏览安全内容。填写自己的 API Key 后可按账号权限浏览；Key 保存在系统钥匙串中。",
                helpURL: URL(string: "https://wallhaven.cc/settings/account")!, hasStoredKey: library.wallhavenAccount.hasStoredKey) { [weak self] key in
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
        if content.publishedAvailability == .remote, content.capabilities.contains(.quickLook) {
            menu.addItem(ActionMenuItem(title: "临时预览", symbol: "eye") { [weak self] in _ = self?.inspector.preview(content: content) })
        }
        menu.addItem(ActionMenuItem(title: "打开原网页", symbol: "safari") { NSWorkspace.shared.open(artwork.sourceURL) })
        if let id = artwork.authorID {
            menu.addItem(ActionMenuItem(title: "查看作者作品", symbol: "person") { [weak self] in
                guard let self else { return }
                openAuthor(.init(source: source, id: id, name: artwork.author), from: page(for: source))
            })
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
