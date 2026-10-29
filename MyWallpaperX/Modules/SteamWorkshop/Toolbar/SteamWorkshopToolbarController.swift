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

    /// 筛选面板（分面复选）的 popover 容器，配置一次复用。
    let filterPanelPopover: NSPopover = {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        return popover
    }()
    private(set) lazy var filterScrollDismissal = ToolbarPopoverScrollDismissal(popover: filterPanelPopover)
    private(set) lazy var filterPanelController = SteamWorkshopFilterPanelController(service: .shared,
        apply: { [weak self] edit in self?.applyQueryEdit(edit) })

    private(set) var isSteamWorkshopMode = false
    private var observers: [NSObjectProtocol] = []
    /// One field owns one unsubmitted draft and deadline. Page exit cancels
    /// the deadline; returning to the same navigation can consume the draft.
    var searchDebounceWorkItem: DispatchWorkItem?
    var pendingSearchInput: (text: String, navigation: Int, account: String?)?
    private var cancellables = Set<AnyCancellable>()

    private let discoveryBrowserIdentifiers: [NSToolbarItem.Identifier] = [
        .sidebarTrackingSeparator,
        NSToolbarItem.Identifier("ToolbarTitle"),
        .flexibleSpace,
        .steamAccount, NSToolbarItem.Identifier("downloadTasks"),
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
        .steamAuthorBack,
        .space,
        .steamAccount, NSToolbarItem.Identifier("downloadTasks"),
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
        searchDebounceWorkItem?.cancel()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

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
                self?.searchDebounceWorkItem?.cancel()
                self?.searchDebounceWorkItem = nil
                if canSubmit { self?.submitPendingSearch() }
            }.store(in: &cancellables)
        }
        let modeObserver = NotificationCenter.default.addObserver(
            forName: .steamWorkshopModeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let enabled = notification.userInfo?["enabled"] as? Bool ?? false
            self?.switchMode(enabled: enabled)
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
                guard let self, self.isSteamWorkshopMode else { return }
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

    private func switchMode(enabled: Bool) {
        searchDebounceWorkItem?.cancel()
        searchDebounceWorkItem = nil
        guard enabled else {
            filterPanelPopover.close()
            isSteamWorkshopMode = false
            return
        }
        isSteamWorkshopMode = true
        submitPendingSearch()
        titleUpdateHandler?(SteamWorkshopService.shared.browserSectionTitle)
        syncBrowserContextControls()
        configureAuthItems()
        zoomToolbarItem.menuFormRepresentation = zoomControl.menuRepresentation()
    }

    /// 按钮展示当前值与下拉指示，菜单生命周期由 NSMenu 管理。
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
            guard let self, self.isSteamWorkshopMode else { return nil }
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
        WallpaperLibraryControlStyle.capsule(button)
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

    lazy var sortButton: NSButton = {
        let button = NSButton(title: "", target: self, action: #selector(handleSortAction(_:)))
        button.image = NSImage(systemSymbolName: WallpaperLibraryControlStyle.sortSymbol, accessibilityDescription: "排序")
        WallpaperLibraryControlStyle.capsule(button)
        return button
    }()

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
        button.image = NSImage(systemSymbolName: WallpaperLibraryControlStyle.filterSymbol, accessibilityDescription: "筛选")
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
        searchField.widthAnchor.constraint(equalToConstant: WallpaperLibraryControlStyle.toolbarSearchWidth).isActive = true
        item.preferredWidthForSearchField = WallpaperLibraryControlStyle.toolbarSearchWidth
        item.visibilityPriority = .high
        return item
    }()

    lazy var accountButton: NSButton = {
        let button = NSButton(title: "", target: self, action: #selector(handleAccountMenu))
        button.bezelStyle = .texturedRounded
        button.setButtonType(.momentaryPushIn)
        button.isBordered = true
        WallpaperLibraryControlStyle.toolbarAccountButton(button)
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

}
