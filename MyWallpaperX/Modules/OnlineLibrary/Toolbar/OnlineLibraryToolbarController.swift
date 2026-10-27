//
//  OnlineLibraryToolbarController.swift
//  MyWallpaperX — Modules/OnlineLibrary/Toolbar
//
//  Pixabay 专用工具栏控制器。
//  缩放度量由 Shared/WallpaperLibraryGridMetrics 计算，偏好与命令由 App 注入。
//  通知名 onlineLibraryModeDidChange 定义在 Shell/ContentViewSupport.swift
//

import AppKit
import Combine

private extension NSImage {
    static func olSymbol(
        _ name: String,
        pointSize: CGFloat,
        weight: NSFont.Weight = .regular,
        scale: NSImage.SymbolScale = .medium,
        accessibilityDescription: String? = nil
    ) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: accessibilityDescription) else { return nil }
        let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight, scale: scale)
        return base.withSymbolConfiguration(cfg)
    }
}

// MARK: - Item Identifiers（在线库专用，不与视频库 IDs 冲突）

extension NSToolbarItem.Identifier {
    static let olCategory = NSToolbarItem.Identifier("ToolbarOLCategory")
    static let olRefresh  = NSToolbarItem.Identifier("ToolbarOLRefresh")
    static let olZoom     = NSToolbarItem.Identifier("ToolbarOLZoom")
    static let olSearch   = NSToolbarItem.Identifier("ToolbarOLSearch")
    static let olOrder    = NSToolbarItem.Identifier("ToolbarOLOrder")
    static let olSettings = NSToolbarItem.Identifier("ToolbarOLSettings")  // API Key 设置

}

// MARK: - OnlineLibraryToolbarController

final class OnlineLibraryToolbarController: NSObject, NSSearchFieldDelegate {

    private enum Title {
        static let browser = "Pixabay 素材库"
    }

    weak var window:  NSWindow?

    /// 在线库 API Key 设置菜单。
    lazy var menuPopover = ToolbarMenuPopoverPresenter(
        fallbackAnchorProvider: { [weak self] in self?.window?.contentView }
    )

    /// 由主工具栏控制器注入，在线浏览页模式下用于同步左侧标题。
    var titleUpdateHandler: ((String) -> Void)?
    var makeZoomAction: ((Int) -> (() -> Void)?)?

    private(set) var isOnlineLibraryMode = false
    private var observers:    [NSObjectProtocol] = []
    private var subscriptions = Set<AnyCancellable>()
    /// 搜索防抖 Task，每次输入时取消上一次，延迟 400ms 后真正触发请求
    private var searchDebounceTask: Task<Void, Never>?

    // 在线浏览页工具栏布局
    // sidebar | title | flexibleSpace | 设置/刷新 | 分类 | 排序 | 缩放 | 搜索
    let onlineIdentifiers: [NSToolbarItem.Identifier] = [
        .sidebarTrackingSeparator,
        NSToolbarItem.Identifier("ToolbarTitle"),
        .flexibleSpace,
        .olSettings, .olRefresh,
        .space,
        .olCategory,
        .space,
        .olOrder,
        .space,
        .olZoom,
        .space,
        .olSearch
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
        // 模式切换（Shell 层发出）
        let modeObs = NotificationCenter.default.addObserver(
            forName: .onlineLibraryModeDidChange, object: nil, queue: .main
        ) { [weak self] note in
            let enabled = note.userInfo?["enabled"] as? Bool ?? false
            self?.switchMode(online: enabled)
        }
        observers.append(modeObs)
        let service = OnlineLibraryService.shared
        Publishers.CombineLatest3(service.$toolbarCategory.removeDuplicates(), service.$toolbarQuery.removeDuplicates(),
            service.$currentParams.map(\.order).removeDuplicates())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.isOnlineLibraryMode else { return }
                self.syncCategoryControl()
                self.syncSearchField()
                self.syncOrderControl()
            }.store(in: &subscriptions)
    }

    // MARK: - 模式切换

    private func switchMode(online: Bool) {
        let entering = online && !isOnlineLibraryMode
        isOnlineLibraryMode = online
        guard online else {
            searchDebounceTask?.cancel(); searchDebounceTask = nil
            menuPopover.close()
            return
        }
        let service = OnlineLibraryService.shared
        // Preserve a draft left before its debounce fired, but submit it only
        // when the user returns to this source, through the original query owner.
        if entering, service.hasLoadedOnce, service.toolbarQuery != service.currentParams.query {
            service.searchWithCurrentContext()
        }
        titleUpdateHandler?(Title.browser)
        syncCategoryControl()
        syncSearchField()
        syncOrderControl()
        updateCategoryScrollWidth()
        zoomToolbarItem.menuFormRepresentation = zoomControl.menuRepresentation()
    }

    // MARK: - Item Factory

    func makeItem(for identifier: NSToolbarItem.Identifier) -> NSToolbarItem? {
        switch identifier {
        case .olCategory: syncCategoryControl(); return categoryToolbarItem
        case .olRefresh:  return refreshToolbarItem
        case .olZoom:     return zoomToolbarItem
        case .olSearch:   syncSearchField(); return searchToolbarItem
        case .olOrder:    syncOrderControl(); return orderToolbarItem
        case .olSettings: return settingsToolbarItem
        default:          return nil
        }
    }

    lazy var zoomControl: WallpaperLibraryZoomControl = {
        let c = WallpaperLibraryZoomControl()
        c.makeAction = { [weak self] delta in
            guard let self, self.isOnlineLibraryMode else { return nil }
            return self.makeZoomAction?(delta)
        }
        return c
    }()

    lazy var zoomToolbarItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .olZoom)
        item.label        = "缩放"
        item.paletteLabel = "缩放"
        item.toolTip      = "调整 Pixabay 缩略图大小"
        item.autovalidates = false
        item.view = zoomControl
        item.visibilityPriority = .low
        return item
    }()

    // MARK: - 分类胶囊（主类存储属性）

    lazy var categoryControl: NSSegmentedControl = {
        let labels = OnlineLibraryCategory.allCases.map { $0.displayName }
        let c = NSSegmentedControl(
            labels: labels, trackingMode: .selectOne,
            target: self, action: #selector(handleCategoryAction(_:))
        )
        c.segmentStyle = .capsule
        c.selectedSegment = 0
        c.font = .systemFont(ofSize: 13)
        for i in 0..<labels.count { c.setWidth(0, forSegment: i) }
        return c
    }()

    /// OL-07：保存宽度约束引用，窗口尺寸变化时动态更新
    private var categoryWidthConstraint: NSLayoutConstraint?

    lazy var categoryScrollView: NSScrollView = {
        let sv = NSScrollView()
        sv.documentView = categoryControl
        sv.hasHorizontalScroller = false
        sv.hasVerticalScroller   = false
        sv.drawsBackground       = false
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.verticalScrollElasticity   = .none
        sv.horizontalScrollElasticity = .automatic
        sv.scrollerStyle = .overlay
        let widthConstraint = sv.widthAnchor.constraint(equalToConstant: categoryScrollWidth())
        NSLayoutConstraint.activate([
            sv.heightAnchor.constraint(equalToConstant: 28),
            widthConstraint
        ])
        categoryWidthConstraint = widthConstraint
        return sv
    }()

    lazy var categoryToolbarItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .olCategory)
        item.label        = "分类"
        item.paletteLabel = "在线分类"
        item.toolTip      = "选择分类"
        item.autovalidates = false
        item.view = categoryScrollView
        return item
    }()

    // MARK: - 排序（主类存储属性）

    lazy var orderControl: NSSegmentedControl = {
        let labels = OnlineLibraryOrder.allCases.map { $0.displayName }
        let c = NSSegmentedControl(
            labels: labels, trackingMode: .selectOne,
            target: self, action: #selector(handleOrderAction(_:))
        )
        c.segmentStyle = .texturedRounded
        c.selectedSegment = 0
        for i in 0..<labels.count { c.setWidth(44, forSegment: i) }
        c.toolTip = "排序方式"
        return c
    }()

    lazy var orderToolbarItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .olOrder)
        item.label        = "排序"
        item.paletteLabel = "排序"
        item.toolTip      = "排序方式"
        item.autovalidates = false
        item.view = orderControl
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
        let item = NSSearchToolbarItem(itemIdentifier: .olSearch)
        item.label = "搜索"
        item.paletteLabel = "搜索 Pixabay"
        item.toolTip = "探索 Pixabay"
        item.autovalidates = false
        item.searchField = searchField
        item.preferredWidthForSearchField = 240
        item.visibilityPriority = .high
        return item
    }()

    // MARK: - 刷新按钮（image-based，与视频库风格一致）

    lazy var refreshToolbarItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .olRefresh)
        item.label         = "刷新"
        item.paletteLabel  = "刷新"
        item.toolTip       = "刷新 Pixabay"
        item.autovalidates = false
        item.image         = NSImage.olSymbol("arrow.clockwise", pointSize: 13, weight: .regular, accessibilityDescription: "刷新")
        item.target        = self
        item.action        = #selector(handleRefreshAction)
        item.isBordered    = true
        return item
    }()

    // MARK: - API Key 设置按钮（view-based NSButton，无箭头，点击弹菜单）

    lazy var settingsButton: NSButton = {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        button.bezelStyle   = .texturedRounded
        button.isBordered   = true
        button.image        = NSImage.olSymbol("key.fill", pointSize: 13, weight: .regular, accessibilityDescription: "API Key")
        button.imageScaling = .scaleProportionallyDown
        button.target       = self
        button.action       = #selector(handleSettingsButtonAction)
        button.toolTip      = "Pixabay API Key 设置"
        return button
    }()

    lazy var settingsToolbarItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .olSettings)
        item.label         = "API Key"
        item.paletteLabel  = "API Key 设置"
        item.toolTip       = "更改 Pixabay API Key"
        item.autovalidates = false
        item.view          = settingsButton
        item.menuFormRepresentation = ToolbarMenuPopoverPresenter.menuRepresentation(title: "API Key", rows: settingsRows())
        item.visibilityPriority = .low
        return item
    }()
}

// MARK: - Zoom presentation (the page owns its preferred columns)

extension OnlineLibraryToolbarController {

    /// OL-07：根据窗口宽度动态计算分类栏合适宽度
    private func categoryScrollWidth() -> CGFloat {
        let windowWidth = window?.contentView?.bounds.width ?? 800
        // 工具栏中其他固定控件占用约 380pt，剩余空间的 35% 分配给分类栏，限定在 [150, 460] 区间
        let available = max(0, windowWidth - 380) * 0.35
        return min(460, max(150, available))
    }

    /// 根据当前窗口尺寸同步分类栏宽度。
    func updateCategoryScrollWidth() {
        guard isOnlineLibraryMode else { return }
        categoryWidthConstraint?.constant = categoryScrollWidth()
    }

    func configureZoom(preferredColumns: Int, clipWidth: CGFloat) {
        zoomControl.update(preferredColumns: preferredColumns, clipWidth: clipWidth, canDispatch: makeZoomAction != nil)
        zoomToolbarItem.isEnabled = zoomControl.isEnabled
        zoomToolbarItem.menuFormRepresentation = zoomControl.menuRepresentation()
    }

    /// 外部（快捷键）触发搜索框聚焦
    func focusSearch() {
        guard isOnlineLibraryMode else { return }
        searchToolbarItem.beginSearchInteraction()
    }
}

// MARK: - Actions

extension OnlineLibraryToolbarController {

    @objc private func handleCategoryAction(_ sender: NSSegmentedControl) {
        let categories = OnlineLibraryCategory.allCases
        guard categories.indices.contains(sender.selectedSegment) else { return }
        chooseCategory(categories[sender.selectedSegment])
    }

    private func chooseCategory(_ category: OnlineLibraryCategory) {
        guard isOnlineLibraryMode else { return }
        searchDebounceTask?.cancel(); searchDebounceTask = nil
        OnlineLibraryService.shared.toolbarCategory = category
        OnlineLibraryService.shared.searchWithCurrentContext(category: category)
        syncCategoryControl()
    }

    @objc private func handleOrderAction(_ sender: NSSegmentedControl) {
        let orders = OnlineLibraryOrder.allCases
        guard orders.indices.contains(sender.selectedSegment) else { return }
        chooseOrder(orders[sender.selectedSegment])
    }

    private func chooseOrder(_ order: OnlineLibraryOrder) {
        guard isOnlineLibraryMode else { return }
        searchDebounceTask?.cancel(); searchDebounceTask = nil
        OnlineLibraryService.shared.searchWithCurrentContext(order: order)
        syncOrderControl()
    }

    @objc private func handleRefreshAction() {
        guard isOnlineLibraryMode else { return }
        OnlineLibraryService.shared.refresh()
    }

    @objc private func handleSettingsButtonAction(_ sender: NSButton) {
        menuPopover.toggle(anchor: sender) { [weak self] in self?.settingsRows() ?? [] }
    }

    private func settingsRows() -> [ToolbarMenuPopoverPresenter.Row] {
        [
            ToolbarMenuPopoverPresenter.Row(
                title: "更改 API Key",
                kind: .action,
                handler: { [weak self] in self?.handleChangeAPIKey() }
            ),
            .separator(),
            ToolbarMenuPopoverPresenter.Row(
                title: "清空并返回登录界面",
                kind: .action,
                handler: { [weak self] in self?.handleClearAPIKey() }
            )
        ]
    }

    @objc private func handleChangeAPIKey() {
        guard isOnlineLibraryMode else { return }
        NotificationCenter.default.post(name: .olShowAPIKeySettings, object: nil)
    }

    @objc private func handleClearAPIKey() {
        guard isOnlineLibraryMode else { return }
        NotificationCenter.default.post(name: .olClearAPIKey, object: nil)
    }

    // NSSearchFieldDelegate：与视频库实现对齐，用 delegate 替代 target/action
    func controlTextDidChange(_ obj: Notification) {
        guard isOnlineLibraryMode, let field = obj.object as? NSSearchField, field === searchField else { return }
        let query = field.stringValue.trimmingCharacters(in: .whitespaces)
        let service = OnlineLibraryService.shared
        service.toolbarQuery = query
        let apiKey = service.apiKey
        // 防抖：取消上次延迟任务，400ms 内无新输入才真正发起请求
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            // Clearing or replacing a key revokes an input that was queued
            // under the previous source context, without a second query owner.
            guard !Task.isCancelled, service.toolbarQuery == query, service.apiKey == apiKey,
                  !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            service.searchWithCurrentContext(query: query)
        }
    }

    /// 切换到在线模式时同步控件状态，避免重建后选中项丢失
    private func syncCategoryControl() {
        let categories = OnlineLibraryCategory.allCases
        let idx = categories.firstIndex(of: OnlineLibraryService.shared.toolbarCategory) ?? 0
        categoryControl.selectedSegment = idx
        categoryToolbarItem.menuFormRepresentation = ToolbarMenuPopoverPresenter.menuRepresentation(title: "分类",
            rows: categories.map { category in
                .init(title: category.displayName, kind: .check, isChecked: category == OnlineLibraryService.shared.toolbarCategory,
                    handler: { [weak self] in self?.chooseCategory(category) })
            })
    }

    private func syncSearchField() {
        let query = OnlineLibraryService.shared.toolbarQuery
        // A source echo must not remove the separator currently being typed
        // between words or reset the field editor's insertion point.
        if searchField.stringValue.trimmingCharacters(in: .whitespaces) != query {
            searchField.stringValue = query
        }
    }

    private func syncOrderControl() {
        let orders = OnlineLibraryOrder.allCases
        let idx = orders.firstIndex(of: OnlineLibraryService.shared.currentParams.order) ?? 0
        orderControl.selectedSegment = idx
        orderToolbarItem.menuFormRepresentation = ToolbarMenuPopoverPresenter.menuRepresentation(title: "排序",
            rows: orders.map { order in
                .init(title: order.displayName, kind: .check, isChecked: order == OnlineLibraryService.shared.currentParams.order,
                    handler: { [weak self] in self?.chooseOrder(order) })
            })
    }

}

// MARK: - 模块内通知名

extension Notification.Name {
    /// 工具栏「API Key」按钮 → 更改面板
    static let olShowAPIKeySettings = Notification.Name("OnlineLibraryShowAPIKeySettings")
    /// 工具栏「清空 API Key」→ 返回登录界面
    static let olClearAPIKey        = Notification.Name("OnlineLibraryClearAPIKey")
} 
