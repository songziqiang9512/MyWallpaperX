//
//  SteamWorkshopToolbarController.swift
//  MyWallpaperX
//

import AppKit
import Combine

final class SteamWorkshopToolbarController: NSObject, NSSearchFieldDelegate {
    enum Title {
        static let browser = "Steam 创意工坊"
        static let downloads = "Steam 下载"
    }

    weak var toolbar: NSToolbar?
    weak var window: NSWindow?
    var localModeIdentifiers: [NSToolbarItem.Identifier] = []
    var titleUpdateHandler: ((String) -> Void)?

    /// 普通菜单按钮（账号/下载筛选/下载排序）的统一 popover 呈现器。
    /// 普通菜单按钮（账号/下载筛选/下载排序）的统一 popover 呈现器。
    private(set) lazy var menuPopover = ToolbarMenuPopoverPresenter(
        fallbackAnchorProvider: { [weak self] in self?.window?.contentView }
    )
    /// 筛选面板（分面复选）的 popover 容器，配置一次复用。
    let filterPanelPopover: NSPopover = {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        return popover
    }()
    private(set) lazy var filterPanelController = SteamWorkshopFilterPanelController(service: .shared)

    private(set) var isSteamWorkshopMode = false
    private(set) var isDownloadsMode = false
    private var observers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()
    private var existingDownloadTasksPopoverController: SteamWorkshopDownloadTasksPopoverController?

    private let discoveryBrowserIdentifiers: [NSToolbarItem.Identifier] = [
        .sidebarTrackingSeparator,
        NSToolbarItem.Identifier("ToolbarTitle"),
        .flexibleSpace,
        .steamAccount,
        .space,
        .steamDownloadTasks,
        .space,
        .steamSort,
        .space,
        .steamTrendingWindow,
        .space,
        .steamFilter,
        .space,
        .steamZoom,
        .space,
        .steamSearch
    ]

    private let authorWorkshopBrowserIdentifiers: [NSToolbarItem.Identifier] = [
        .sidebarTrackingSeparator,
        NSToolbarItem.Identifier("ToolbarTitle"),
        .flexibleSpace,
        .steamAuthorBack,
        .space,
        .steamAccount,
        .space,
        .steamDownloadTasks,
        .space,
        .steamZoom,
        .space,
        .steamSearch
    ]

    var browserIdentifiers: [NSToolbarItem.Identifier] {
        if SteamWorkshopService.shared.isBrowsingAuthorWorkshop {
            return authorWorkshopBrowserIdentifiers
        }
        return SteamWorkshopService.shared.source.isPersonal
            ? personalBrowserIdentifiers
            : discoveryBrowserIdentifiers
    }

    init(toolbar: NSToolbar, window: NSWindow?) {
        self.toolbar = toolbar
        self.window = window
        super.init()
        installObservers()
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func installObservers() {
        let modeObserver = NotificationCenter.default.addObserver(
            forName: .steamWorkshopModeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let enabled = notification.userInfo?["enabled"] as? Bool ?? false
            let isDownloads = notification.userInfo?["isDownloads"] as? Bool ?? false
            self?.switchMode(enabled: enabled, isDownloads: isDownloads)
        }
        observers.append(modeObserver)

        let browseContextObserver = NotificationCenter.default.addObserver(
            forName: .steamWorkshopBrowseContextDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncBrowserContextControls()
        }
        observers.append(browseContextObserver)

        SteamWorkshopService.shared.$zoomOffset
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.configureZoomItem()
            }
            .store(in: &cancellables)

        // SK2.2：账号按钮随新登录路线状态刷新。
        SteamWorkshopService.shared.steamAuth.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.configureAuthItems()
            }
            .store(in: &cancellables)

        SteamWorkshopService.shared.steamAuth.$steamId
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.configureAuthItems()
                self?.configureDownloadTasksItem()
            }
            .store(in: &cancellables)

        SteamWorkshopService.shared.downloadJobStore.$jobs
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.configureDownloadTasksItem()
            }
            .store(in: &cancellables)

        SteamWorkshopService.shared.steamAuth.$expired
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.configureAuthItems()
            }
            .store(in: &cancellables)

        SteamWorkshopService.shared.$statusMessage
            .map { $0.hasPrefix("需要登录 Steam") }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.configureAuthItems()
            }
            .store(in: &cancellables)

        SteamWorkshopService.shared.$source
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncSortPopup()
                self?.syncPersonalListPopup()
                self?.syncTrendingWindowPopup()
            }
            .store(in: &cancellables)

        SteamWorkshopService.shared.$browserContentMode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.configureFilterItem()
                self?.syncSearchField()
            }
            .store(in: &cancellables)

        SteamWorkshopService.shared.$trendingWindow
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncTrendingWindowPopup()
            }
            .store(in: &cancellables)

        SteamWorkshopService.shared.$browserSectionTitle
            .receive(on: RunLoop.main)
            .sink { [weak self] title in
                guard let self, self.isSteamWorkshopMode, !self.isDownloadsMode else { return }
                self.titleUpdateHandler?(title)
            }
            .store(in: &cancellables)

        SteamWorkshopService.shared.$isBrowsingAuthorWorkshop
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncBrowserContextControls()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            SteamWorkshopService.shared.$selectedDownloadID,
            SteamWorkshopService.shared.$downloads
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _ in
            self?.configureDownloadsDeleteItem()
        }
        .store(in: &cancellables)

        SteamWorkshopService.shared.$isDownloadsMultiSelectMode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.configureDownloadsSelectItem()
                self?.configureDownloadsDeleteItem()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            SteamWorkshopService.shared.$downloadsSortMode,
            SteamWorkshopService.shared.$downloadsSortAscending
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _ in
            self?.configureDownloadsSortItem()
        }
        .store(in: &cancellables)

        SteamWorkshopService.shared.$downloadsDisplayMode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.configureDownloadsFilterItem()
            }
            .store(in: &cancellables)

        SteamWorkshopService.shared.$facetFilters
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.configureFilterItem()
            }
            .store(in: &cancellables)
    }

    private func switchMode(enabled: Bool, isDownloads: Bool) {
        guard enabled else {
            existingDownloadTasksPopoverController?.close()
            menuPopover.close()
            filterPanelPopover.close()
            isSteamWorkshopMode = false
            isDownloadsMode = false
            return
        }
        isSteamWorkshopMode = true
        isDownloadsMode = isDownloads

        if isDownloads {
            configureDownloadsTitleItem()
            configureAuthItems()
            configureDownloadsSelectItem()
            configureDownloadsDeleteItem()
            configureDownloadsFilterItem()
            configureDownloadsSortItem()
            syncDownloadsSearchField()
        } else {
            titleUpdateHandler?(SteamWorkshopService.shared.browserSectionTitle)
            syncBrowserContextControls()
            configureAuthItems()
        }
        configureDownloadTasksItem()
        configureZoomItem()
    }

    /// 选择类控件统一为「当前值 + 下拉三角面板」按钮（与其他工具栏菜单
    /// 同一箭头 popover 呈现），不再使用原生 NSPopUpButton 菜单。
    private func makePullDownButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .medium))
        button.imagePosition = .imageTrailing
        return button
    }

    lazy var personalListButton = makePullDownButton(
        title: SteamWorkshopSource.mySubscriptions.displayName,
        action: #selector(handlePersonalListAction(_:))
    )

    lazy var personalListToolbarItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .steamPersonalList)
        item.label = "列表"
        item.paletteLabel = "个人列表"
        item.toolTip = "切换 Steam 个人列表"
        item.autovalidates = false
        item.view = personalListButton
        return item
    }()

    lazy var downloadsTitleLabel: NSTextField = {
        let label = NSTextField(labelWithString: Title.downloads)
        label.font = .systemFont(ofSize: 16, weight: .bold)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
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
        let item = NSToolbarItem(itemIdentifier: .steamDownloadsTitle)
        item.label = "当前目录"
        item.paletteLabel = "当前目录"
        item.autovalidates = false
        item.isBordered = false
        item.view = downloadsTitleContainer
        return item
    }()

    lazy var downloadsDeleteItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .steamDownloadsDelete)
        item.label = "删除"
        item.paletteLabel = "删除"
        item.toolTip = "删除当前选中的下载项"
        item.autovalidates = false
        item.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "删除")
        item.target = self
        item.action = #selector(handleDeleteSelectedDownload)
        return item
    }()

    lazy var downloadsSelectItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .steamDownloadsSelect)
        item.label = "选择"
        item.paletteLabel = "选择"
        item.toolTip = "进入选择模式"
        item.autovalidates = false
        item.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "选择")
        item.target = self
        item.action = #selector(handleToggleDownloadsSelectMode)
        return item
    }()

    lazy var downloadsSearchField: NSSearchField = {
        let field = NSSearchField(frame: .zero)
        field.delegate = self
        field.placeholderString = "搜索"
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.recentsAutosaveName = nil
        field.maximumRecents = 0
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
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
        let item = NSToolbarItem(itemIdentifier: .steamDownloadsSearch)
        item.label = "搜索下载项"
        item.paletteLabel = "搜索下载项"
        item.toolTip = "搜索下载项"
        item.autovalidates = false
        item.view = downloadsSearchContainerView
        return item
    }()

    lazy var downloadsFilterButton: NSButton = {
        let button = NSButton(title: "全部", target: self, action: #selector(handleDownloadsFilterAction(_:)))
        button.bezelStyle = .rounded
        button.image = NSImage(systemSymbolName: "line.3.horizontal.decrease.circle", accessibilityDescription: "筛选下载项")
        button.imagePosition = .imageLeading
        button.toolTip = "筛选下载项类型"
        return button
    }()

    lazy var downloadsFilterItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .steamDownloadsFilter)
        item.label = "筛选"
        item.paletteLabel = "筛选"
        item.toolTip = "筛选下载项类型"
        item.autovalidates = false
        item.view = downloadsFilterButton
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
        let item = NSToolbarItem(itemIdentifier: .steamDownloadsSort)
        item.label = "排序"
        item.paletteLabel = "排序"
        item.toolTip = "排序方式"
        item.autovalidates = false
        item.view = downloadsSortMenuButton
        return item
    }()

    lazy var zoomControl: NSSegmentedControl = {
        let control = NSSegmentedControl(
            images: [
                NSImage(systemSymbolName: "minus.magnifyingglass", accessibilityDescription: "缩小") ?? NSImage(),
                NSImage(systemSymbolName: "plus.magnifyingglass", accessibilityDescription: "放大") ?? NSImage()
            ],
            trackingMode: .momentary,
            target: self,
            action: #selector(handleZoomAction(_:))
        )
        control.segmentStyle = .capsule
        control.setWidth(28, forSegment: 0)
        control.setWidth(28, forSegment: 1)
        return control
    }()

    lazy var zoomToolbarItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .steamZoom)
        item.label = "缩放"
        item.paletteLabel = "缩放"
        item.toolTip = "调整 Steam 条目卡片大小"
        item.autovalidates = false
        item.view = zoomControl
        return item
    }()

    lazy var authorBackButton: NSButton = {
        let button = NSButton(title: "返回总榜", target: self, action: #selector(handleBackToDiscovery))
        button.bezelStyle = .rounded
        button.image = NSImage(systemSymbolName: "chevron.backward", accessibilityDescription: "返回总榜")
        button.imagePosition = .imageLeading
        return button
    }()

    lazy var authorBackToolbarItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .steamAuthorBack)
        item.label = "返回总榜"
        item.paletteLabel = "返回总榜"
        item.toolTip = "从作者工坊返回 Steam 创意工坊总榜"
        item.autovalidates = false
        item.view = authorBackButton
        return item
    }()

    lazy var sortButton = makePullDownButton(
        title: SteamWorkshopSource.featured.displayName,
        action: #selector(handleSortAction(_:))
    )

    lazy var sortToolbarItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .steamSort)
        item.label = "浏览来源"
        item.paletteLabel = "浏览来源"
        item.toolTip = "切换 Steam 创意工坊浏览来源"
        item.autovalidates = false
        item.view = sortButton
        return item
    }()

    lazy var trendingWindowButton = makePullDownButton(
        title: SteamWorkshopTrendingWindow.week.displayName,
        action: #selector(handleTrendingWindowAction(_:))
    )

    lazy var trendingWindowToolbarItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .steamTrendingWindow)
        item.label = "时间段"
        item.paletteLabel = "时间段"
        item.toolTip = "切换最热门榜单的时间范围"
        item.autovalidates = false
        item.view = trendingWindowButton
        return item
    }()

    lazy var filterButton: NSButton = {
        let button = NSButton(title: "筛选", target: self, action: #selector(handleFilterMenu))
        button.bezelStyle = .rounded
        button.image = NSImage(systemSymbolName: "line.3.horizontal.decrease.circle", accessibilityDescription: "筛选")
        button.imagePosition = .imageLeading
        return button
    }()

    lazy var filterToolbarItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .steamFilter)
        item.label = "筛选"
        item.paletteLabel = "筛选"
        item.toolTip = "选择类型、年龄分级和分辨率筛选规则"
        item.autovalidates = false
        item.view = filterButton
        return item
    }()

    lazy var searchField: NSSearchField = {
        let field = NSSearchField(frame: .zero)
        field.delegate = self
        field.placeholderString = "搜索"
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.recentsAutosaveName = nil
        field.maximumRecents = 0
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.translatesAutoresizingMaskIntoConstraints = false
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }()

    lazy var searchContainerView: NSView = {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 180, height: 28))
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(searchField)
        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            searchField.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            searchField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.widthAnchor.constraint(equalToConstant: 180),
            container.heightAnchor.constraint(equalToConstant: 28)
        ])
        return container
    }()

    lazy var searchToolbarItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .steamSearch)
        item.label = "搜索 Steam 视频"
        item.paletteLabel = "搜索 Steam 视频"
        item.toolTip = "搜索 Steam 视频"
        item.autovalidates = false
        item.view = searchContainerView
        return item
    }()

    lazy var accountButton: NSButton = {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        button.bezelStyle = .texturedRounded
        button.setButtonType(.momentaryPushIn)
        button.isBordered = true
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.target = self
        button.action = #selector(handleAccountMenu)
        return button
    }()

    lazy var accountToolbarItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .steamAccount)
        item.label = "账号"
        item.paletteLabel = "Steam 账号"
        item.toolTip = "打开 Steam 登录页"
        item.autovalidates = false
        item.view = accountButton
        return item
    }()

    /// 与账号按钮同构的普通图标按钮（无角标）。
    lazy var downloadTasksButton: NSButton = {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        button.bezelStyle = .texturedRounded
        button.setButtonType(.momentaryPushIn)
        button.isBordered = true
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.image = NSImage(systemSymbolName: "arrow.down.to.line", accessibilityDescription: "下载任务")
        button.target = self
        button.action = #selector(handleDownloadTasks)
        return button
    }()

    lazy var downloadTasksToolbarItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .steamDownloadTasks)
        item.label = "下载任务"
        item.paletteLabel = "下载任务"
        item.toolTip = "查看下载任务"
        item.autovalidates = false
        item.view = downloadTasksButton
        let overflowItem = NSMenuItem(
            title: "下载任务",
            action: #selector(handleDownloadTasks),
            keyEquivalent: ""
        )
        overflowItem.target = self
        item.menuFormRepresentation = overflowItem
        return item
    }()

    var downloadTasksPopoverController: SteamWorkshopDownloadTasksPopoverController {
        if let existingDownloadTasksPopoverController {
            return existingDownloadTasksPopoverController
        }
        let controller = SteamWorkshopDownloadTasksPopoverController(service: .shared)
        existingDownloadTasksPopoverController = controller
        return controller
    }

}
