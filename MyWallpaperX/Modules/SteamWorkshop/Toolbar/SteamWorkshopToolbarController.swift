//
//  SteamWorkshopToolbarController.swift
//  MyWallpaperX
//

import AppKit
import Combine

final class SteamWorkshopToolbarController: NSObject, NSSearchFieldDelegate {

    weak var toolbar: NSToolbar?
    weak var window: NSWindow?
    var titleUpdateHandler: ((String) -> Void)?
    var makeZoomAction: ((Int) -> (() -> Void)?)?

    /// 账号和浏览菜单共用的 popover 呈现器。
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
    private(set) lazy var filterScrollDismissal = ToolbarPopoverScrollDismissal(popover: filterPanelPopover)
    private(set) lazy var filterPanelController = SteamWorkshopFilterPanelController(service: .shared)

    private(set) var isSteamWorkshopMode = false
    private(set) var isDownloadsMode = false
    private var observers: [NSObjectProtocol] = []
    /// Per-field search debounce state (used by controlTextDidChange in
    /// +Actions): one keystroke must not trigger one helper round-trip each.
    var searchDebounceWorkItems: [ObjectIdentifier: DispatchWorkItem] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var existingDownloadTasksPopoverController: SteamWorkshopDownloadTasksPopoverController?

    private let discoveryBrowserIdentifiers: [NSToolbarItem.Identifier] = [
        .sidebarTrackingSeparator,
        NSToolbarItem.Identifier("ToolbarTitle"),
        .flexibleSpace,
        .steamAccount, .steamDownloadTasks,
        .space,
        .steamTrendingWindow,
        .space,
        .steamSort, .steamFilter,
        .space,
        .steamZoom,
        .space,
        .steamSearch
    ]

    private let authorWorkshopBrowserIdentifiers: [NSToolbarItem.Identifier] = [
        .sidebarTrackingSeparator,
        NSToolbarItem.Identifier("ToolbarTitle"),
        .flexibleSpace,
        .steamAccount, .steamDownloadTasks,
        .space,
        .steamAuthorBack,
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
            .map { $0.hasPrefix("需要登录") }
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

        if !isDownloads {
            titleUpdateHandler?(SteamWorkshopService.shared.browserSectionTitle)
            syncBrowserContextControls()
        }
        configureAuthItems()
        configureDownloadTasksItem()
        zoomToolbarItem.menuFormRepresentation = zoomControl.menuRepresentation()
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

    lazy var zoomControl: WallpaperLibraryZoomControl = {
        let control = WallpaperLibraryZoomControl()
        control.makeAction = { [weak self] delta in
            guard let self, self.isSteamWorkshopMode, !self.isDownloadsMode else { return nil }
            return self.makeZoomAction?(delta)
        }
        return control
    }()

    lazy var zoomToolbarItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .steamZoom)
        item.label = "缩放"
        item.paletteLabel = "缩放"
        item.toolTip = "调整条目卡片大小"
        item.autovalidates = false
        item.view = zoomControl
        item.visibilityPriority = .low
        return item
    }()

    lazy var authorBackButton: NSButton = {
        let button = NSButton(title: "返回", target: self, action: #selector(handleBackToDiscovery))
        button.bezelStyle = .rounded
        button.image = NSImage(systemSymbolName: "chevron.backward", accessibilityDescription: "返回")
        button.imagePosition = .imageLeading
        return button
    }()

    lazy var authorBackToolbarItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .steamAuthorBack)
        item.label = "返回"
        item.paletteLabel = "返回"
        item.toolTip = "返回上一级工坊浏览"
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
        item.toolTip = "切换创意工坊浏览来源"
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

    lazy var searchToolbarItem: NSSearchToolbarItem = {
        let item = NSSearchToolbarItem(itemIdentifier: .steamSearch)
        item.label = "搜索创意工坊"
        item.paletteLabel = "搜索创意工坊"
        item.toolTip = "搜索创意工坊"
        item.autovalidates = false
        item.searchField = searchField
        item.preferredWidthForSearchField = 240
        item.visibilityPriority = .high
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
