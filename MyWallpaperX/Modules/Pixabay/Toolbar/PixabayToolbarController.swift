//
//  PixabayToolbarController.swift
//  MyWallpaperX — Modules/Pixabay/Toolbar
//
//  Pixabay 专用工具栏控制器。
//  缩放度量由 Shared/WallpaperLibraryGridMetrics 计算，偏好与命令由 App 注入。
//  通知名 pixabayModeDidChange 定义在 Shell/ContentViewSupport.swift
//

import AppKit
import Combine

// MARK: - Item Identifiers（Pixabay专用，不与视频库 IDs 冲突）

extension NSToolbarItem.Identifier {
    static let pixabayFilter   = NSToolbarItem.Identifier("ToolbarPixabayFilter")
    static let pixabayZoom     = NSToolbarItem.Identifier("ToolbarPixabayZoom")
    static let pixabaySearch   = NSToolbarItem.Identifier("ToolbarPixabaySearch")
    static let pixabayOrder    = NSToolbarItem.Identifier("ToolbarPixabayOrder")
    static let pixabaySettings = NSToolbarItem.Identifier("ToolbarPixabaySettings")  // API Key 设置

}

// MARK: - PixabayToolbarController

final class PixabayToolbarController: NSObject, NSSearchFieldDelegate {

    private enum Title {
        static let browser = "Pixabay 素材库"
    }

    weak var window:  NSWindow?

    private let filterPopover: NSPopover = { let value = NSPopover(); value.behavior = .transient; return value }()
    private lazy var filterScrollDismissal = ToolbarPopoverScrollDismissal(popover: filterPopover)

    /// 由主工具栏控制器注入，在线浏览页模式下用于同步左侧标题。
    var titleUpdateHandler: ((String) -> Void)?
    var makeZoomAction: ((Int) -> (() -> Void)?)?

    private(set) var isPixabayMode = false
    private var observers:    [NSObjectProtocol] = []
    private var subscriptions = Set<AnyCancellable>()
    /// 搜索防抖 Task，每次输入时取消上一次，延迟 400ms 后真正触发请求
    private var searchDebounceTask: Task<Void, Never>?
    private var pendingSearchAPIKey: String?

    // 在线浏览页工具栏布局
    // sidebar | title | flexibleSpace | 设置/下载管理 | 分类 | 排序 | 缩放 | 搜索
    let pixabayIdentifiers: [NSToolbarItem.Identifier] = [
        .sidebarTrackingSeparator,
        NSToolbarItem.Identifier("ToolbarTitle"),
        .flexibleSpace,
        .pixabaySettings, NSToolbarItem.Identifier("downloadTasks"),
        .space,
        .pixabayFilter,
        .space,
        .pixabayOrder,
        .space,
        .pixabayZoom,
        .space,
        .pixabaySearch
    ]

    // MARK: - Init

    init(window: NSWindow?) {
        self.window  = window
        super.init()
        installObservers()
    }

    deinit {
        searchDebounceTask?.cancel()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Observers

    private func installObservers() {
        if let window {
            let changes = [window.publisher(for: \.isVisible, options: [.new]).map { _ in true }.eraseToAnyPublisher()]
                + [NSWindow.willMiniaturizeNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification].map {
                    NotificationCenter.default.publisher(for: $0, object: window)
                        .map { $0.name != NSWindow.willMiniaturizeNotification }.eraseToAnyPublisher()
                } + [NSApplication.didHideNotification, NSApplication.didUnhideNotification].map {
                    NotificationCenter.default.publisher(for: $0, object: NSApp).map { _ in true }.eraseToAnyPublisher()
                }
            Publishers.MergeMany(changes).receive(on: DispatchQueue.main).sink { [weak self] canSubmit in
                self?.searchDebounceTask?.cancel()
                self?.searchDebounceTask = nil
                if canSubmit { self?.submitPendingSearch() }
            }.store(in: &subscriptions)
        }
        // 模式切换（Shell 层发出）
        let modeObs = NotificationCenter.default.addObserver(
            forName: .pixabayModeDidChange, object: nil, queue: .main
        ) { [weak self] note in
            let enabled = note.userInfo?["enabled"] as? Bool ?? false
            self?.switchMode(pixabay: enabled)
        }
        observers.append(modeObs)
        let service = PixabayService.shared
        service.$currentParams.removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.isPixabayMode else { return }
                self.syncFilterControl()
                self.syncOrderMenu()
            }.store(in: &subscriptions)
        service.$toolbarQuery.removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.isPixabayMode else { return }
                self.syncSearchField()
            }.store(in: &subscriptions)
    }

    // MARK: - 模式切换

    private func switchMode(pixabay: Bool) {
        isPixabayMode = pixabay
        guard pixabay else {
            searchDebounceTask?.cancel(); searchDebounceTask = nil
            filterPopover.performClose(nil)
            return
        }
        // Preserve a draft left before its debounce fired, but submit it only
        // when the user returns to this source, through the original query owner.
        submitPendingSearch()
        titleUpdateHandler?(Title.browser)
        syncFilterControl()
        syncSearchField()
        syncOrderMenu()
        zoomToolbarItem.menuFormRepresentation = zoomControl.menuRepresentation()
    }

    // MARK: - Item Factory

    func makeItem(for identifier: NSToolbarItem.Identifier) -> NSToolbarItem? {
        switch identifier {
        case .pixabayFilter:   syncFilterControl(); return filterToolbarItem
        case .pixabayZoom:     return zoomToolbarItem
        case .pixabaySearch:   syncSearchField(); return searchToolbarItem
        case .pixabayOrder:    syncOrderMenu(); return orderToolbarItem
        case .pixabaySettings: return settingsToolbarItem
        default:          return nil
        }
    }

    lazy var zoomControl: WallpaperLibraryZoomControl = {
        let c = WallpaperLibraryZoomControl()
        c.makeAction = { [weak self] delta in
            guard let self, self.isPixabayMode else { return nil }
            return self.makeZoomAction?(delta)
        }
        return c
    }()

    lazy var zoomToolbarItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .pixabayZoom)
        item.label        = "缩放"
        item.paletteLabel = "缩放"
        item.toolTip      = "调整 Pixabay 缩略图大小"
        item.autovalidates = false
        item.view = zoomControl
        item.visibilityPriority = .low
        return item
    }()

    lazy var filterToolbarItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .pixabayFilter)
        item.label = "筛选"; item.paletteLabel = "筛选"; item.toolTip = "筛选 Pixabay"
        item.autovalidates = false
        let button = NSButton(title: "筛选", target: self, action: #selector(handleFilterAction))
        button.image = NSImage(systemSymbolName: WallpaperLibraryControlStyle.filterSymbol, accessibilityDescription: "筛选")
        button.imagePosition = .imageLeading
        WallpaperLibraryControlStyle.capsule(button)
        item.view = button
        return item
    }()

    // MARK: - 排序（主类存储属性）

    lazy var orderToolbarItem: NSMenuToolbarItem = {
        let item = NSMenuToolbarItem(itemIdentifier: .pixabayOrder)
        item.label = "排序"
        item.paletteLabel = "排序"
        item.image = NSImage(systemSymbolName: WallpaperLibraryControlStyle.sortSymbol, accessibilityDescription: "排序")
        item.showsIndicator = false
        item.isBordered = true
        item.autovalidates = false
        return item
    }()

    // MARK: - 搜索框（NSSearchToolbarItem，与视频库实现对齐）

    lazy var searchField: NSSearchField = {
        let field = NSSearchField(frame: .zero)
        field.delegate = self
        field.placeholderString = "在Pixabay中查找"
        field.setAccessibilityLabel(field.placeholderString)
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.translatesAutoresizingMaskIntoConstraints = false
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }()

    lazy var searchToolbarItem: NSSearchToolbarItem = {
        let item = NSSearchToolbarItem(itemIdentifier: .pixabaySearch)
        item.label = "搜索"
        item.paletteLabel = "搜索 Pixabay"
        item.toolTip = "探索 Pixabay"
        item.autovalidates = false
        item.searchField = searchField
        searchField.widthAnchor.constraint(equalToConstant: WallpaperLibraryControlStyle.toolbarSearchWidth).isActive = true
        item.preferredWidthForSearchField = WallpaperLibraryControlStyle.toolbarSearchWidth
        item.visibilityPriority = .high
        return item
    }()

    // MARK: - API Key 设置按钮（view-based NSButton，无箭头，点击弹菜单）

    lazy var settingsButton: NSButton = {
        let button = NSButton(title: "", target: self, action: #selector(handleSettingsButtonAction))
        button.bezelStyle = .texturedRounded
        button.isBordered = true
        WallpaperLibraryControlStyle.toolbarAccountButton(button)
        button.image = NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: "API Key")
        button.toolTip = "Pixabay API Key 设置"
        return button
    }()

    lazy var settingsToolbarItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .pixabaySettings)
        item.label         = "API Key"
        item.paletteLabel  = "API Key 设置"
        item.toolTip       = "更改 Pixabay API Key"
        item.autovalidates = false
        item.view          = settingsButton
        item.menuFormRepresentation = ToolbarMenu.menuRepresentation(title: "API Key", rows: settingsRows())
        item.visibilityPriority = .low
        return item
    }()
}

// MARK: - Zoom presentation (the page owns its preferred columns)

extension PixabayToolbarController {

    func configureZoom(preferredColumns: Int, clipWidth: CGFloat) {
        zoomControl.update(preferredColumns: preferredColumns, clipWidth: clipWidth, canDispatch: makeZoomAction != nil)
        zoomToolbarItem.isEnabled = zoomControl.isEnabled
        zoomToolbarItem.menuFormRepresentation = zoomControl.menuRepresentation()
    }

    /// 外部（快捷键）触发搜索框聚焦
    func focusSearch() {
        guard isPixabayMode else { return }
        searchToolbarItem.beginSearchInteraction()
    }
}

// MARK: - Actions

extension PixabayToolbarController {

    @objc private func handleFilterAction() {
        guard isPixabayMode, WallpaperLibrarySheetPresentation.permitsInput(in: window),
              let toolbar = filterToolbarItem.toolbar, toolbar === window?.toolbar,
              let content = window?.contentView else { return }
        if filterPopover.isShown { filterPopover.performClose(nil); return }
        let panel = makeFilterPanel()
        filterPopover.contentViewController = panel; panel.loadViewIfNeeded()
        filterPopover.contentSize = panel.preferredContentSize
        filterScrollDismissal.watch(relativeTo: content)
        filterPopover.show(relativeTo: filterToolbarItem)
    }

    private func makeFilterPanel() -> WallpaperFilterPanelController {
        let service = PixabayService.shared
        return PixabayFilterPanel.make(service: service) { [weak self] change in
            guard let self, isPixabayMode, WallpaperLibrarySheetPresentation.permitsInput(in: window) else { return }
            searchDebounceTask?.cancel(); searchDebounceTask = nil
            pendingSearchAPIKey = nil
            var query = service.currentParams
            query.query = service.toolbarQuery; query.page = 1
            change(&query)
            guard query != service.currentParams else { return }
            service.toolbarCategory = query.category
            service.search(params: query)
            syncFilterControl()
        }
    }

    private func chooseOrder(_ order: PixabayOrder) {
        guard isPixabayMode else { return }
        searchDebounceTask?.cancel(); searchDebounceTask = nil
        pendingSearchAPIKey = nil
        PixabayService.shared.searchWithCurrentContext(order: order)
        syncOrderMenu()
    }

    @objc private func handleSettingsButtonAction(_ sender: NSButton) {
        guard isPixabayMode, WallpaperLibrarySheetPresentation.permitsInput(in: window) else { return }
        filterPopover.performClose(nil)
        ToolbarMenu.popUp(anchor: sender, rows: settingsRows())
    }

    private func settingsRows() -> [ToolbarMenu.Row] {
        [
            ToolbarMenu.Row(
                title: "更改 API Key",
                kind: .action,
                handler: { [weak self] in self?.handleChangeAPIKey() }
            ),
            .separator(),
            ToolbarMenu.Row(
                title: "清空并返回登录界面",
                kind: .action,
                handler: { [weak self] in self?.handleClearAPIKey() }
            )
        ]
    }

    @objc private func handleChangeAPIKey() {
        guard isPixabayMode else { return }
        NotificationCenter.default.post(name: .pixabayShowAPIKeySettings, object: nil)
    }

    @objc private func handleClearAPIKey() {
        guard isPixabayMode else { return }
        NotificationCenter.default.post(name: .pixabayClearAPIKey, object: nil)
    }

    // NSSearchFieldDelegate：与视频库实现对齐，用 delegate 替代 target/action
    func controlTextDidChange(_ obj: Notification) {
        guard isPixabayMode, let field = obj.object as? NSSearchField, field === searchField else { return }
        let query = field.stringValue.trimmingCharacters(in: .whitespaces)
        let service = PixabayService.shared
        service.toolbarQuery = query
        let apiKey = service.apiKey
        pendingSearchAPIKey = apiKey
        // 防抖：取消上次延迟任务，400ms 内无新输入才真正发起请求
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            // Clearing or replacing a key revokes an input that was queued
            // under the previous source context, without a second query owner.
            guard let self, !Task.isCancelled else { return }
            self.searchDebounceTask = nil
            guard service.toolbarQuery == query else { return }
            self.submitPendingSearch()
        }
    }

    private func submitPendingSearch() {
        guard isPixabayMode, window?.isVisible == true, window?.isMiniaturized == false, !NSApp.isHidden else { return }
        let service = PixabayService.shared
        let key = service.apiKey
        if let pendingSearchAPIKey, pendingSearchAPIKey != key {
            self.pendingSearchAPIKey = nil
            if !key.trimmingCharacters(in: .whitespaces).isEmpty { service.toolbarQuery = service.currentParams.query }
            return
        }
        guard !key.trimmingCharacters(in: .whitespaces).isEmpty,
              pendingSearchAPIKey != nil || service.hasLoadedOnce else { return }
        pendingSearchAPIKey = nil
        if service.toolbarQuery != service.currentParams.query { service.searchWithCurrentContext() }
    }

    /// 切换到在线模式时同步控件状态，避免重建后选中项丢失
    private func syncFilterControl() {
        filterToolbarItem.menuFormRepresentation = ActionMenuItem(title: "筛选", symbol: WallpaperLibraryControlStyle.filterSymbol) { [weak self] in
            self?.handleFilterAction()
        }
        if filterPopover.isShown { (filterPopover.contentViewController as? WallpaperFilterPanelController)?.synchronize() }
    }

    private func syncSearchField() {
        let query = PixabayService.shared.toolbarQuery
        // A source echo must not remove the separator currently being typed
        // between words or reset the field editor's insertion point.
        if searchField.stringValue.trimmingCharacters(in: .whitespaces) != query {
            searchField.stringValue = query
        }
    }

    private func syncOrderMenu() {
        let current = PixabayService.shared.currentParams.order
        let menu = NSMenu()
        for order in PixabayOrder.allCases {
            let item = ActionMenuItem(title: order.displayName, symbol: "") { [weak self] in self?.chooseOrder(order) }
            item.state = order == current ? .on : .off
            menu.addItem(item)
        }
        orderToolbarItem.menu = menu
        orderToolbarItem.toolTip = "排序：\(current.displayName)"
    }

}

// MARK: - 模块内通知名

extension Notification.Name {
    /// 工具栏「API Key」按钮 → 更改面板
    static let pixabayShowAPIKeySettings = Notification.Name("PixabayShowAPIKeySettings")
    /// 工具栏「清空 API Key」→ 返回登录界面
    static let pixabayClearAPIKey        = Notification.Name("PixabayClearAPIKey")
}
