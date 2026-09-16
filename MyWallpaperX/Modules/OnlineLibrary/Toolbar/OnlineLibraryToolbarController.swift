//
//  OnlineLibraryToolbarController.swift
//  MyWallpaperX — Modules/OnlineLibrary/Toolbar
//
//  Pixabay 专用工具栏控制器。
//  依赖：Shared/UI/GridLayoutHelper、Shared/UI/UIInteractionAnimation
//  工具栏 zoom 按钮使用自有实现（架构备忘 §五：工具栏 zoom 不强制共享）
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

    static let olDownloadsTitle  = NSToolbarItem.Identifier("ToolbarOLDownloadsTitle")
    static let olDownloadsSelect = NSToolbarItem.Identifier("ToolbarOLDownloadsSelect")
    static let olDownloadsDelete = NSToolbarItem.Identifier("ToolbarOLDownloadsDelete")
    static let olDownloadsSort   = NSToolbarItem.Identifier("ToolbarOLDownloadsSort")
    static let olDownloadsReveal = NSToolbarItem.Identifier("ToolbarOLDownloadsReveal")
    static let olDownloadsSearch = NSToolbarItem.Identifier("ToolbarOLDownloadsSearch")
}

// MARK: - OnlineLibraryToolbarController

final class OnlineLibraryToolbarController: NSObject, NSSearchFieldDelegate {

    private enum Title {
        static let browser = "Pixabay 素材库"
        static let downloads = "Pixabay 下载"
    }

    weak var toolbar: NSToolbar?
    weak var window:  NSWindow?

    /// 在线库菜单按钮（API Key 设置/下载排序）的统一下拉面板。
    lazy var menuPopover = ToolbarMenuPopoverPresenter(
        fallbackAnchorProvider: { [weak self] in self?.window?.contentView }
    )

    /// 切换到在线模式前保存的本地工具栏布局，退出时恢复
    var localModeIdentifiers: [NSToolbarItem.Identifier] = []
    /// 由主工具栏控制器注入，在线浏览页模式下用于同步左侧标题。
    var titleUpdateHandler: ((String) -> Void)?

    private(set) var isOnlineLibraryMode = false
    private var isOnlineDownloadsMode = false
    private var observers:    [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()
    /// 搜索防抖 Task，每次输入时取消上一次，延迟 400ms 后真正触发请求
    private var searchDebounceTask: Task<Void, Never>?

    // 在线浏览页工具栏布局
    // sidebar | title | flexibleSpace | 设置 | space | 刷新 | space | 分类 | space | 排序 | space | 缩放 | space | 搜索
    let onlineIdentifiers: [NSToolbarItem.Identifier] = [
        .sidebarTrackingSeparator,
        NSToolbarItem.Identifier("ToolbarTitle"),
        .flexibleSpace,
        .olSettings,
        .space,
        .olRefresh,
        .space,
        .olCategory,
        .space,
        .olOrder,
        .space,
        .olZoom,
        .space,
        .olSearch
    ]

    // 在线「已下载项」工具栏布局（对齐视频库：去掉收藏/标签）
    // sidebar | title | flexibleSpace | 选择 | space | 删除 | 信息 | 查看文件 | 排序 | space | 缩放 | space | 搜索
    let downloadsIdentifiers: [NSToolbarItem.Identifier] = [
        .sidebarTrackingSeparator,
        .olDownloadsTitle,
        .flexibleSpace,
        .olDownloadsSelect,
        .space,
        .olDownloadsDelete,
        .olDownloadsReveal,
        .olDownloadsSort,
        .space,
        .olZoom,
        .space,
        .olDownloadsSearch
    ]

    // MARK: - Init

    init(toolbar: NSToolbar, window: NSWindow?) {
        self.toolbar = toolbar
        self.window  = window
        super.init()
        installObservers()
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Observers

    private func installObservers() {
        // 模式切换（Shell 层发出）
        let modeObs = NotificationCenter.default.addObserver(
            forName: .onlineLibraryModeDidChange, object: nil, queue: .main
        ) { [weak self] note in
            let enabled = note.userInfo?["enabled"] as? Bool ?? false
            let isDownloads = note.userInfo?["isDownloads"] as? Bool ?? false
            self?.switchMode(online: enabled, isDownloads: isDownloads)
        }
        observers.append(modeObs)

        // zoomOffset 变化 → 刷新按钮可用状态
        OnlineLibraryService.shared.$zoomOffset
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.configureZoomItem() }
            .store(in: &cancellables)
    }

    // MARK: - 模式切换

    private func switchMode(online: Bool, isDownloads: Bool) {
        if !online {
            isOnlineLibraryMode = false
            isOnlineDownloadsMode = false
            return
        }

        isOnlineLibraryMode = true
        isOnlineDownloadsMode = isDownloads

        if isDownloads {
            configureDownloadsTitleItem()
            configureDownloadsSelectionItem()
                configureDownloadsRevealItem()
            configureDownloadsSortItem()
        } else {
            titleUpdateHandler?(Title.browser)
            syncCategoryControl()
            syncSearchField()
            syncOrderControl()
            updateCategoryScrollWidth()  // OL-07：切入在线模式时同步分类栏宽度
        }
        configureZoomItem()
    }

    /// 已下载项工具栏状态统一刷新（选择态变化后由 bridge 动作触发）
    func refreshDownloadsToolbarState() {
        guard isOnlineLibraryMode && isOnlineDownloadsMode else { return }
        configureDownloadsSelectionItem()
        configureDownloadsRevealItem()
        configureZoomItem()
    }

    // MARK: - Item Factory（供 VideoLibraryToolbarController.toolbar(_:itemFor:) 代理调用）

    func makeItem(for identifier: NSToolbarItem.Identifier) -> NSToolbarItem? {
        switch identifier {
        case .olCategory: return categoryToolbarItem
        case .olRefresh:  return refreshToolbarItem
        case .olZoom:     return zoomToolbarItem
        case .olSearch:   return searchToolbarItem
        case .olOrder:    return orderToolbarItem
        case .olSettings: return settingsToolbarItem
        case .olDownloadsTitle:  return downloadsTitleItem
        case .olDownloadsSelect: return downloadsSelectItem
        case .olDownloadsDelete: return downloadsDeleteItem
        case .olDownloadsSort:   return downloadsSortItem
        case .olDownloadsReveal: return downloadsRevealItem
        case .olDownloadsSearch: return downloadsSearchItem
        default:          return nil
        }
    }

    lazy var downloadsTitleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Pixabay 下载")
        label.font = .systemFont(ofSize: 16, weight: .bold)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.alignment = .left
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    lazy var downloadsTitleContainer: NSView = {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 180, height: 28))
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(downloadsTitleLabel)
        NSLayoutConstraint.activate([
            downloadsTitleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            downloadsTitleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            downloadsTitleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.widthAnchor.constraint(equalToConstant: 180),
            container.heightAnchor.constraint(equalToConstant: 28)
        ])
        return container
    }()

    lazy var downloadsTitleItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .olDownloadsTitle)
        item.label = "当前目录"
        item.paletteLabel = "当前目录"
        item.autovalidates = false
        item.isBordered = false
        item.view = downloadsTitleContainer
        return item
    }()

    lazy var downloadsSelectItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .olDownloadsSelect)
        item.label = "选择"
        item.paletteLabel = "选择"
        item.autovalidates = false
        item.target = self
        item.action = #selector(handleDownloadsSelectAction)
        return item
    }()

    lazy var downloadsDeleteItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .olDownloadsDelete)
        item.label = "删除"
        item.paletteLabel = "删除"
        item.toolTip = "删除选中壁纸"
        item.autovalidates = false
        item.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "删除")
        item.target = self
        item.action = #selector(handleDownloadsDeleteAction)
        return item
    }()

    lazy var downloadsRevealItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .olDownloadsReveal)
        item.label = "查看文件"
        item.paletteLabel = "查看文件"
        item.toolTip = "在访达中显示"
        item.autovalidates = false
        item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "在访达中显示")
        item.target = self
        item.action = #selector(handleDownloadsRevealAction)
        return item
    }()

    lazy var downloadsSortMenuButton: NSButton = {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        button.bezelStyle = .texturedRounded
        button.isBordered = true
        button.image = NSImage(systemSymbolName: "line.3.horizontal.decrease", accessibilityDescription: "排序")
        button.imageScaling = .scaleProportionallyDown
        button.target = self
        button.action = #selector(handleDownloadsSortAction(_:))
        button.toolTip = "排序方式"
        return button
    }()

    lazy var downloadsSortItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .olDownloadsSort)
        item.label = "排序"
        item.paletteLabel = "排序"
        item.toolTip = "排序方式"
        item.autovalidates = false
        item.view = downloadsSortMenuButton
        return item
    }()

    private var downloadsSortState: SortState = {
        let raw = UserDefaults.standard.string(forKey: "OLDownloadsSortMode") ?? ""
        let mode = WallpaperSortMode(rawValue: raw) ?? .none
        let ascending = UserDefaults.standard.object(forKey: "OLDownloadsSortAscending") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "OLDownloadsSortAscending")
        return SortState(mode: mode, ascending: ascending)
    }()

    lazy var downloadsSearchField: NSSearchField = {
        let field = NSSearchField(frame: .zero)
        field.placeholderString = "搜索"
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.target = self
        field.action = #selector(handleDownloadsSearchChanged(_:))
        field.translatesAutoresizingMaskIntoConstraints = false
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }()

    lazy var downloadsSearchContainerView: NSView = {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 165, height: 28))
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(downloadsSearchField)
        NSLayoutConstraint.activate([
            downloadsSearchField.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            downloadsSearchField.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            downloadsSearchField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.widthAnchor.constraint(equalToConstant: 165),
            container.heightAnchor.constraint(equalToConstant: 28)
        ])
        return container
    }()

    lazy var downloadsSearchItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .olDownloadsSearch)
        item.label = "搜索下载项"
        item.paletteLabel = "搜索下载项"
        item.toolTip = "搜索 Pixabay 下载"
        item.autovalidates = false
        item.view = downloadsSearchContainerView
        return item
    }()

    lazy var zoomControl: NSSegmentedControl = {
        // segment 0 = 缩小(minus)，segment 1 = 放大(plus)
        let c = NSSegmentedControl(
            images: [
                NSImage(systemSymbolName: "minus.magnifyingglass", accessibilityDescription: "缩小") ?? NSImage(),
                NSImage(systemSymbolName: "plus.magnifyingglass", accessibilityDescription: "放大") ?? NSImage()
            ],
            trackingMode: .momentary, target: self,
            action: #selector(handleZoomAction(_:))
        )
        c.segmentStyle = .texturedRounded
        c.setWidth(28, forSegment: 0)
        c.setWidth(28, forSegment: 1)
        c.toolTip = "调整 Pixabay 缩略图大小"
        return c
    }()

    lazy var zoomToolbarItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .olZoom)
        item.label        = "缩放"
        item.paletteLabel = "缩放"
        item.toolTip      = "调整 Pixabay 缩略图大小"
        item.autovalidates = false
        item.view = zoomControl
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
        field.placeholderString = "搜索"
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.translatesAutoresizingMaskIntoConstraints = false
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }()

    lazy var searchContainerView: NSView = {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 165, height: 28))
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(searchField)
        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            searchField.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            searchField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.widthAnchor.constraint(equalToConstant: 165),
            container.heightAnchor.constraint(equalToConstant: 28)
        ])
        return container
    }()

    lazy var searchToolbarItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .olSearch)
        item.label = "搜索"
        item.paletteLabel = "搜索 Pixabay"
        item.toolTip = "探索 Pixabay"
        item.autovalidates = false
        item.view = searchContainerView
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
        return item
    }()
}

// MARK: - Zoom Logic（使用 Shared/GridLayoutHelper）

extension OnlineLibraryToolbarController {

    private func gridWidth() -> CGFloat {
        (window?.contentView?.bounds.width ?? 800) - 220
    }

    /// OL-07：根据窗口宽度动态计算分类栏合适宽度
    private func categoryScrollWidth() -> CGFloat {
        let windowWidth = window?.contentView?.bounds.width ?? 800
        // 工具栏中其他固定控件占用约 380pt，剩余空间的 35% 分配给分类栏，限定在 [150, 460] 区间
        let available = max(0, windowWidth - 380) * 0.35
        return min(460, max(150, available))
    }

    /// OL-07：外部触发宽度更新（窗口 resize 时由 VideoLibraryToolbarController 调用）
    func updateCategoryScrollWidth() {
        guard isOnlineLibraryMode else { return }
        categoryWidthConstraint?.constant = categoryScrollWidth()
    }

    func configureZoomItem() {
        let avail = GridLayoutHelper.zoomAvailability(
            currentOffset: OnlineLibraryService.shared.zoomOffset,
            for: gridWidth(), minCols: 3, maxCols: 6
        )
        let hasItems = isOnlineDownloadsMode ? OnlineDownloadsBridge.shared.hasAnyItems : true
        // segment 0 = 减少列数(minus)，segment 1 = 增加列数(plus)，与 SIL 一致
        zoomControl.setEnabled(hasItems && avail.canZoomOut, forSegment: 0)
        zoomControl.setEnabled(hasItems && avail.canZoomIn,  forSegment: 1)
    }

    /// 外部（快捷键）触发搜索框聚焦
    func focusSearch() {
        guard isOnlineLibraryMode else { return }
        if isOnlineDownloadsMode {
            window?.makeFirstResponder(downloadsSearchField)
        } else {
            window?.makeFirstResponder(searchField)
        }
    }

    /// 外部（快捷键）触发缩放
    func performZoom(delta: Int) {
        guard isOnlineLibraryMode else { return }
        let width = gridWidth()
        let base  = GridLayoutHelper.baseColumnCount(for: width)
        let minOff = 3 - base;  let maxOff = 6 - base
        let current   = OnlineLibraryService.shared.zoomOffset
        let newOffset = max(minOff, min(maxOff, current + delta))
        guard newOffset != current else { return }
        // segment 0 = 减少列数(minus)，segment 1 = 增加列数(plus)，与 SIL 一致
        let seg = delta > 0 ? 1 : 0
        zoomControl.setSelected(true, forSegment: seg)
        DispatchQueue.main.asyncAfter(deadline: .now() + UIInteractionAnimation.minimumPressVisualDuration) { [weak self] in
            self?.zoomControl.setSelected(false, forSegment: seg)
        }
        OnlineLibraryService.shared.zoomOffset = newOffset
        configureZoomItem()
    }

    @objc private func handleZoomAction(_ sender: NSSegmentedControl) {
        // segment 0 = 减少列数(minus)，segment 1 = 增加列数(plus)，与 SIL 一致
        let delta  = sender.selectedSegment == 0 ? -1 : 1
        let width  = gridWidth()
        let base   = GridLayoutHelper.baseColumnCount(for: width)
        let minOff = 3 - base;  let maxOff = 6 - base
        let current   = OnlineLibraryService.shared.zoomOffset
        let newOffset = max(minOff, min(maxOff, current + delta))
        guard newOffset != current else { return }
        OnlineLibraryService.shared.zoomOffset = newOffset
        configureZoomItem()
    }
}

// MARK: - Actions

extension OnlineLibraryToolbarController {

    @objc private func handleCategoryAction(_ sender: NSSegmentedControl) {
        let categories = OnlineLibraryCategory.allCases
        guard sender.selectedSegment < categories.count else { return }
        let category = categories[sender.selectedSegment]
        OnlineLibraryService.shared.toolbarCategory = category
        OnlineLibraryService.shared.searchWithCurrentContext(category: category)
    }

    @objc private func handleOrderAction(_ sender: NSSegmentedControl) {
        let orders = OnlineLibraryOrder.allCases
        guard sender.selectedSegment < orders.count else { return }
        let order = orders[sender.selectedSegment]
        OnlineLibraryService.shared.searchWithCurrentContext(order: order)
    }

    @objc private func handleRefreshAction() {
        OnlineLibraryService.shared.refresh()
    }

    @objc private func handleSettingsButtonAction(_ sender: NSButton) {
        menuPopover.toggle(anchor: sender) { [weak self] in
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
    }

    @objc private func handleChangeAPIKey() {
        NotificationCenter.default.post(name: .olShowAPIKeySettings, object: nil)
    }

    @objc private func handleClearAPIKey() {
        NotificationCenter.default.post(name: .olClearAPIKey, object: nil)
    }

    @objc private func handleDownloadsSelectAction() {
        OnlineDownloadsBridge.shared.toggleMultiSelect()
        configureDownloadsSelectionItem()
        configureDownloadsRevealItem()
    }

    @objc private func handleDownloadsDeleteAction() {
        guard let window else {
            OnlineDownloadsBridge.shared.deleteSelected()
            configureDownloadsSelectionItem()
                configureDownloadsRevealItem()
            return
        }
        let count = OnlineDownloadsBridge.shared.selectedCount
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = count > 1 ? "删除 \(count) 个视频？" : "删除该视频？"
        alert.informativeText = count > 1
            ? "将从已下载列表中删除这 \(count) 个视频文件，此操作不可撤销。"
            : "将从已下载列表中删除该视频文件，此操作不可撤销。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            OnlineDownloadsBridge.shared.deleteSelected()
            self?.configureDownloadsSelectionItem()
            self?.configureDownloadsRevealItem()
        }
    }

    @objc private func handleDownloadsRevealAction() {
        OnlineDownloadsBridge.shared.revealInFinder()
    }

    @objc private func handleDownloadsSearchChanged(_ sender: NSSearchField) {
        NotificationCenter.default.post(
            name: .olDownloadsSearchQueryChanged,
            object: nil,
            userInfo: ["query": sender.stringValue]
        )
    }

    @objc private func handleDownloadsSortAction(_ sender: NSButton) {
        menuPopover.toggle(anchor: sender) { [weak self] in
            guard let self else { return [] }
            let state = self.downloadsSortState
            var rows: [ToolbarMenuPopoverPresenter.Row] = WallpaperSortMode.allCases.map { mode in
                ToolbarMenuPopoverPresenter.Row(
                    title: mode.displayName,
                    kind: .check,
                    isChecked: state.mode == mode,
                    handler: { [weak self] in self?.applyDownloadsSortMode(mode) }
                )
            }
            rows.append(.separator())
            rows.append(ToolbarMenuPopoverPresenter.Row(
                title: "升序",
                kind: .check,
                isChecked: state.ascending,
                handler: { [weak self] in self?.applyDownloadsSortDirection(true) }
            ))
            rows.append(ToolbarMenuPopoverPresenter.Row(
                title: "降序",
                kind: .check,
                isChecked: !state.ascending,
                handler: { [weak self] in self?.applyDownloadsSortDirection(false) }
            ))
            return rows
        }
    }

    private func applyDownloadsSortMode(_ mode: WallpaperSortMode) {
        downloadsSortState.mode = mode
        if mode == .none { downloadsSortState.ascending = true }
        NotificationCenter.default.post(name: .olDownloadsSortDidChange, object: nil, userInfo: [
            "mode": mode.rawValue,
            "ascending": downloadsSortState.ascending
        ])
        configureDownloadsSortItem()
    }

    private func applyDownloadsSortDirection(_ ascending: Bool) {
        downloadsSortState.ascending = ascending
        NotificationCenter.default.post(name: .olDownloadsSortDidChange, object: nil, userInfo: [
            "mode": downloadsSortState.mode.rawValue,
            "ascending": ascending
        ])
        configureDownloadsSortItem()
    }

    // NSSearchFieldDelegate：与视频库实现对齐，用 delegate 替代 target/action
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField else { return }
        let query = field.stringValue.trimmingCharacters(in: .whitespaces)
        OnlineLibraryService.shared.toolbarQuery = query
        // 防抖：取消上次延迟任务，400ms 内无新输入才真正发起请求
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            OnlineLibraryService.shared.searchWithCurrentContext(query: query)
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        // 搜索框失焦时取消防抖任务，避免退出后仍触发请求
        // 注意：不在此处取消搜索，只取消延迟任务
        _ = obj // 无需额外处理
    }

    /// 切换到在线模式时同步控件状态，避免重建后选中项丢失
    private func syncCategoryControl() {
        let categories = OnlineLibraryCategory.allCases
        let idx = categories.firstIndex(of: OnlineLibraryService.shared.toolbarCategory) ?? 0
        categoryControl.selectedSegment = idx
    }

    private func syncSearchField() {
        searchField.stringValue = OnlineLibraryService.shared.toolbarQuery
    }

    private func syncOrderControl() {
        let orders = OnlineLibraryOrder.allCases
        let idx = orders.firstIndex(of: OnlineLibraryService.shared.currentParams.order) ?? 0
        orderControl.selectedSegment = idx
    }

    private func configureDownloadsTitleItem() {
        downloadsTitleLabel.stringValue = Title.downloads
        downloadsTitleItem.toolTip = Title.downloads
    }

    private func configureDownloadsSelectionItem() {
        let isMultiSelect = OnlineDownloadsBridge.shared.isMultiSelectMode
        downloadsSelectItem.image = NSImage(
            systemSymbolName: isMultiSelect ? "checkmark.circle.fill" : "checkmark.circle",
            accessibilityDescription: "选择"
        )
        downloadsSelectItem.toolTip = isMultiSelect ? "退出选择模式" : "进入选择模式"
    }

    private func configureDownloadsRevealItem() {
        downloadsRevealItem.isEnabled = OnlineDownloadsBridge.shared.hasAnySelection
    }

    private func configureDownloadsSortItem() {
        downloadsSortMenuButton.contentTintColor = downloadsSortState.mode == .none ? nil : .controlAccentColor
    }
}

// MARK: - Refresh Item（OL-08：lazy var，与其他控件风格一致，定义在主类 extension 外见主类声明区）
// refreshToolbarItem 已移至主类声明区 lazy var，此 extension 保留注释供索引

// MARK: - 工具栏 Allowed Identifiers（P6）

extension OnlineLibraryToolbarController {
    /// 在线模式工具栏允许出现的所有标识符，供 Shell 层 NSToolbarDelegate 的
    /// toolbarAllowedItemIdentifiers(_:) 代理方法调用，
    /// 使工具栏自定义面板能正确枚举 OL 专属控件。
    var allowedItemIdentifiers: [NSToolbarItem.Identifier] {
        [
            .olCategory,
            .olRefresh,
            .olZoom,
            .olSearch,
            .olOrder,
            .olSettings,
            .olDownloadsTitle,
            .olDownloadsSelect,
            .olDownloadsDelete,
                .olDownloadsSort,
            .olDownloadsReveal,
            .olDownloadsSearch,
            .space,
            .flexibleSpace
        ]
    }
}

// MARK: - 模块内通知名

extension Notification.Name {
    /// 工具栏「API Key」按钮 → 更改面板
    static let olShowAPIKeySettings = Notification.Name("OnlineLibraryShowAPIKeySettings")
    /// 工具栏「清空 API Key」→ 返回登录界面
    static let olClearAPIKey        = Notification.Name("OnlineLibraryClearAPIKey")
} 
