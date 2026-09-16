//
//  SILToolbarController.swift
//  MyWallpaperX — Modules/StaticImageLibrary/Toolbar
//
//  设计原则：
//  - SIL 使用独立的 toolbar item identifier，不复用视频库 identifier
//  - switchMode 时通过 removeItem/insertItem 切换布局
//  - VideoLibraryToolbarController 的 delegate default 分支代理给 makeItem
//  - SILToolbarController 完全自治，不引用 VideoLibraryToolbarController
//
import AppKit
import Combine

// MARK: - SIL 专用 Identifier
extension NSToolbarItem.Identifier {
    static let silImport = NSToolbarItem.Identifier("ToolbarSILImport")
    static let silSelect = NSToolbarItem.Identifier("ToolbarSILSelect")
    static let silDelete = NSToolbarItem.Identifier("ToolbarSILDelete")
    static let silTag    = NSToolbarItem.Identifier("ToolbarSILTag")
    static let silSort   = NSToolbarItem.Identifier("ToolbarSILSort")
    static let silZoom   = NSToolbarItem.Identifier("ToolbarSILZoom")
    static let silSearch = NSToolbarItem.Identifier("ToolbarSILSearch")
}

// MARK: - SILToolbarController
final class SILToolbarController: NSObject, NSSearchFieldDelegate {
    weak var toolbar: NSToolbar?
    weak var window: NSWindow?
    var localModeIdentifiers: [NSToolbarItem.Identifier] = []
    private(set) var isSILMode = false
    private var observerTokens: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()
    /// 图片库排序按钮的统一下拉面板（箭头锚定按钮）。
    lazy var menuPopover = ToolbarMenuPopoverPresenter(
        fallbackAnchorProvider: { [weak self] in self?.window?.contentView }
    )

    private lazy var sortMenuButton: NSButton = {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        button.bezelStyle = .texturedRounded
        button.isBordered = true
        button.image = NSImage(systemSymbolName: "line.3.horizontal.decrease", accessibilityDescription: "排序")
        button.imageScaling = .scaleProportionallyDown
        button.target = self
        button.action = #selector(handleSort(_:))
        button.toolTip = "排序方式"
        return button
    }()

    /// 由 VideoLibraryToolbarController 注入，SIL 模式下用于更新工具栏标题标签
    var titleUpdateHandler: ((String) -> Void)?
    /// 当前显示的标签上下文，nil 表示「我的图片」全库
    var currentSILTag: String? = nil

    /// SIL 模式下工具栏布局
    let silIdentifiers: [NSToolbarItem.Identifier] = [
        .sidebarTrackingSeparator,
        NSToolbarItem.Identifier("ToolbarTitle"),
        .flexibleSpace,
        .silImport, .silSelect, .space,
        .silDelete, .silTag, .silSort,
        .space, .silZoom, .space, .silSearch
    ]

    init(toolbar: NSToolbar, window: NSWindow?) {
        self.toolbar = toolbar
        self.window = window
        super.init()
        installObservers()
    }

    deinit {
        observerTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func installObservers() {
        let modeObserver = NotificationCenter.default.addObserver(
            forName: .staticImageLibraryModeDidChange, object: nil, queue: .main
        ) { [weak self] n in
            guard let self else { return }
            let enabled = n.userInfo?["enabled"] as? Bool ?? false
            let tag = n.userInfo?["silTag"] as? String
            self.currentSILTag = enabled ? tag : nil
            // 同步到 SILService，供 MainWindowCoordinator 等全局调用方读取
            SILService.shared.currentContextTag = self.currentSILTag
            self.switchMode(sil: enabled)
            if enabled {
                let title = tag ?? "我的图片"
                self.titleUpdateHandler?(title)
            }
        }
        observerTokens.append(modeObserver)
        SILService.shared.$gridZoomOffset.receive(on: RunLoop.main)
            .sink { [weak self] _ in guard self?.isSILMode == true else { return }; self?.configureZoomItem() }
            .store(in: &cancellables)
        Publishers.MergeMany(
            SILService.shared.$selectedID.map { _ in () }.eraseToAnyPublisher(),
            SILService.shared.$selectedIDs.map { _ in () }.eraseToAnyPublisher(),
            SILService.shared.$isMultiSelectMode.map { _ in () }.eraseToAnyPublisher(),
            SILService.shared.$sortState.map { _ in () }.eraseToAnyPublisher(),
            SILService.shared.$wallpapers.map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in guard self?.isSILMode == true else { return }; self?.refreshButtonStates() }
        .store(in: &cancellables)
    }

    // MARK: - 模式切换

    func switchMode(sil: Bool) {
        guard isSILMode != sil else { return }
        isSILMode = sil
        if sil {
            configureZoomItem()
            refreshButtonStates()
        }
    }

    private let defaultVideoIdentifiers: [NSToolbarItem.Identifier] = [
        .sidebarTrackingSeparator,
        NSToolbarItem.Identifier("ToolbarTitle"),
        .flexibleSpace,
        NSToolbarItem.Identifier("ToolbarImport"),
        NSToolbarItem.Identifier("ToolbarSelect"),
        .space,
        NSToolbarItem.Identifier("ToolbarNavigation"),
        .space,
        NSToolbarItem.Identifier("ToolbarDelete"),
        NSToolbarItem.Identifier("ToolbarFavorite"),
        NSToolbarItem.Identifier("ToolbarTag"),
        NSToolbarItem.Identifier("ToolbarInfo"),
        NSToolbarItem.Identifier("ToolbarSort"),
        .space,
        NSToolbarItem.Identifier("ToolbarZoom"),
        .space,
        NSToolbarItem.Identifier("ToolbarSearch")
    ]

    // MARK: - Item 工厂（由 VideoLibraryToolbarController delegate 调用）

    func makeItem(for id: NSToolbarItem.Identifier) -> NSToolbarItem? {
        switch id {
        case .silImport:  return makeImportItem()
        case .silSelect:  return makeSelectItem()
        case .silDelete:  return makeDeleteItem()
        case .silTag:     return makeTagItem()
        case .silSort:    return makeSortItem()
        case .silZoom:    return makeZoomItem()
        case .silSearch:  return makeSearchItem()
        default:          return nil
        }
    }

    // MARK: - 缩放

    func focusSearch() {
        guard isSILMode else { return }
        window?.makeFirstResponder(searchField)
    }

    func performZoom(delta: Int) {
        guard isSILMode else { return }
        let w = (window?.contentView?.bounds.width ?? 800) - 220
        let cur = SILService.shared.gridZoomOffset
        let base = GridLayoutHelper.baseColumnCount(for: w)
        let next = max(3 - base, min(6 - base, cur + delta))
        guard next != cur else { return }
        // segment 0 = 减少列数（minus），segment 1 = 增加列数（plus）— 与视频库一致
        let segIdx = delta > 0 ? 1 : 0
        zoomControl.setSelected(true, forSegment: segIdx)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.zoomControl.setSelected(false, forSegment: segIdx)
        }
        SILService.shared.gridZoomOffset = next
        SILService.shared.saveZoomOffset()
        configureZoomItem()
    }

    func configureZoomItem() {
        let w = (window?.contentView?.bounds.width ?? 800) - 220
        let avail = GridLayoutHelper.zoomAvailability(currentOffset: SILService.shared.gridZoomOffset, for: w)
        // segment 0 = 减少列数（minus），segment 1 = 增加列数（plus）
        zoomControl.setEnabled(avail.canZoomOut, forSegment: 0)
        zoomControl.setEnabled(avail.canZoomIn,  forSegment: 1)
    }

    private lazy var zoomControl: NSSegmentedControl = {
        let c = NSSegmentedControl(
            images: [
                NSImage(systemSymbolName: "minus.magnifyingglass", accessibilityDescription: "缩小") ?? NSImage(),
                NSImage(systemSymbolName: "plus.magnifyingglass",  accessibilityDescription: "放大") ?? NSImage()
            ],
            trackingMode: .momentary, target: self, action: #selector(handleZoom(_:))
        )
        c.segmentStyle = .capsule
        c.setWidth(28, forSegment: 0)
        c.setWidth(28, forSegment: 1)
        c.toolTip = "调整缩略图大小"
        return c
    }()

    private lazy var searchField: NSSearchField = {
        let field = NSSearchField(frame: .zero)
        field.delegate = self
        field.placeholderString = "搜索"
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.target = self
        field.action = #selector(handleSearch(_:))
        field.translatesAutoresizingMaskIntoConstraints = false
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }()

    private lazy var searchContainerView: NSView = {
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

    @objc private func handleZoom(_ s: NSSegmentedControl) {
        // segment 0 = 减少列数（minus），segment 1 = 增加列数（plus）
        performZoom(delta: s.selectedSegment == 0 ? -1 : 1)
    }

    // MARK: - 状态刷新

    private func refreshButtonStates() {
        guard isSILMode, let toolbar else { return }
        let svc = SILService.shared
        let ids = svc.effectiveSelectedIDs
        let isMulti = svc.isMultiSelectMode
        for item in toolbar.items {
            switch item.itemIdentifier {
            case .silDelete:
                item.isEnabled = !ids.isEmpty
            case .silTag:
                item.isEnabled = !ids.isEmpty && !SILService.shared.silTags.isEmpty
            case .silSelect:
                item.image = NSImage(systemSymbolName: isMulti ? "checkmark.circle.fill" : "checkmark.circle", accessibilityDescription: nil)
                item.toolTip = isMulti ? "退出选择模式" : "进入选择模式"
                item.isEnabled = true
            case .silImport:
                item.image = NSImage(systemSymbolName: isMulti ? "checkmark.circle" : "plus.circle", accessibilityDescription: nil)
                item.toolTip = isMulti ? "全选 / 取消全选" : "导入图片壁纸"
                item.isEnabled = true
            case .silSort:
                let hasSort = svc.sortState.mode != .none
                sortMenuButton.contentTintColor = hasSort ? .controlAccentColor : nil
                item.isEnabled = true
            default: break
            }
        }
        configureZoomItem()
    }
}

// MARK: - Item 工厂（private）
private extension SILToolbarController {
    func makeImportItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: .silImport)
        item.label = "导入"; item.paletteLabel = "导入图片"
        item.toolTip = "导入图片壁纸"; item.autovalidates = false
        item.isBordered = true
        item.image = NSImage(systemSymbolName: "plus.circle", accessibilityDescription: "导入")
        item.target = self; item.action = #selector(handleImport)
        return item
    }
    func makeSelectItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: .silSelect)
        item.label = "选择"; item.paletteLabel = "选择模式"
        item.toolTip = "进入选择模式"; item.autovalidates = false
        item.isBordered = true
        item.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "选择")
        item.target = self; item.action = #selector(handleSelect)
        return item
    }
    func makeDeleteItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: .silDelete)
        item.label = "移除"; item.paletteLabel = "移除图片"
        item.toolTip = "从列表移除选中图片"; item.autovalidates = false
        item.isBordered = true
        item.isEnabled = false
        item.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "移除")
        item.target = self; item.action = #selector(handleDelete)
        return item
    }
    func makeTagItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: .silTag)
        item.label = "标签"; item.paletteLabel = "添加图片标签"
        item.toolTip = "添加图片标签"; item.autovalidates = false
        item.isBordered = true
        item.isEnabled = false
        item.image = NSImage(systemSymbolName: "tag", accessibilityDescription: "标签")
        item.target = self; item.action = #selector(handleTag)
        return item
    }
    func makeSortItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: .silSort)
        item.label = "排序"; item.paletteLabel = "排序"
        item.toolTip = "排序方式"; item.autovalidates = false
        item.view = sortMenuButton
        return item
    }
    func makeZoomItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: .silZoom)
        item.label = "缩放"; item.paletteLabel = "缩放"
        item.toolTip = "调整缩略图大小"; item.autovalidates = false
        item.view = zoomControl
        return item
    }
    func makeSearchItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: .silSearch)
        item.label = "搜索"
        item.paletteLabel = "搜索图片"
        item.toolTip = "搜索图片壁纸"
        item.autovalidates = false
        item.view = searchContainerView
        return item
    }
}

// MARK: - Actions
extension SILToolbarController {
    @objc func handleImport() {
        let svc = SILService.shared
        if svc.isMultiSelectMode {
            let all = Set(svc.sortedWallpapers.map(\.id))
            if svc.selectedIDs == all && !all.isEmpty { svc.deselectAll() } else { svc.selectAll() }
            refreshButtonStates()
        } else {
            svc.importFromPanel(presentingIn: window)
        }
    }
    @objc func handleSelect() {
        let svc = SILService.shared
        if svc.isMultiSelectMode { svc.exitMultiSelectMode() } else { svc.enterMultiSelectMode() }
        refreshButtonStates()
    }
    @objc func handleDelete() {
        let ids = SILService.shared.effectiveSelectedIDs; guard !ids.isEmpty else { return }
        let isTagContext = currentSILTag != nil
        let message = isTagContext
            ? "将从标签「\(currentSILTag!)」中移除选中的 \(ids.count) 张图片（不删除「我的图片」总库中的记录）。"
            : "将从列表中移除选中的 \(ids.count) 张图片（不删除原文件）。"
        let alert = makeAppAlert(title: "移除图片壁纸",
            message: message,
            style: .warning, buttons: ["移除", "取消"])
        presentAppAlert(alert, in: window) { [weak self] r in
            guard r == .alertFirstButtonReturn else { return }
            if let tag = self?.currentSILTag {
                SILService.shared.removeFromSILTag(tag, ids: ids)
            } else {
                SILService.shared.remove(ids: ids)
            }
        }
    }
    @objc func handleTag() {
        let svc = SILService.shared
        let ids = svc.effectiveSelectedIDs
        guard !ids.isEmpty else { return }
        let tags = svc.silTags
        guard !tags.isEmpty else {
            let alert = makeAppAlert(title: "无可用标签", message: "请先在侧边栏右键新建图片标签。", buttons: ["好"])
            presentAppAlert(alert, in: window)
            return
        }
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        picker.addItems(withTitles: tags)
        picker.selectItem(at: 0)
        let alert = makeAppAlert(
            title: "添加图片标签",
            message: "请选择要添加的标签",
            buttons: ["确定", "取消"],
            accessoryView: picker
        )
        presentAppAlert(alert, in: window) { r in
            guard r == .alertFirstButtonReturn,
                  let tag = picker.titleOfSelectedItem, !tag.isEmpty else { return }
            SILService.shared.addSILTag(tag, toSelected: ids)
        }
    }
    @objc func handleSort(_ sender: NSButton) {
        let svc = SILService.shared
        menuPopover.toggle(anchor: sender) { [weak self] in
            guard let self else { return [] }
            // 排除「最近使用」，图片库未实际记录 lastUsed
            let visibleModes = SILSortMode.allCases.filter { $0 != .lastUsed }
            var rows: [ToolbarMenuPopoverPresenter.Row] = visibleModes.map { mode in
                ToolbarMenuPopoverPresenter.Row(
                    title: mode.displayName,
                    kind: .action,
                    isChecked: svc.sortState.mode == mode,
                    handler: { [weak self] in self?.applySortMode(mode) }
                )
            }
            rows.append(.separator())
            rows.append(ToolbarMenuPopoverPresenter.Row(
                title: "升序",
                kind: .action,
                isChecked: svc.sortState.ascending,
                handler: { [weak self] in self?.applySortDirection(true) }
            ))
            rows.append(ToolbarMenuPopoverPresenter.Row(
                title: "降序",
                kind: .action,
                isChecked: !svc.sortState.ascending,
                handler: { [weak self] in self?.applySortDirection(false) }
            ))
            return rows
        }
    }
    private func applySortMode(_ mode: SILSortMode) {
        SILService.shared.sortState.mode = mode
        SILService.shared.saveSortState()
        refreshButtonStates()
    }
    private func applySortDirection(_ ascending: Bool) {
        SILService.shared.sortState.ascending = ascending
        SILService.shared.saveSortState()
    }
    @objc private func handleSearch(_ sender: NSSearchField) {
        SILService.shared.searchQuery = sender.stringValue.trimmingCharacters(in: .whitespaces)
    }
}
