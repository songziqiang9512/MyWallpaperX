//
//  AppKitDetailHostViewController.swift
//  MyWallpaperX
//

import AppKit
import Combine

final class AppKitDetailHostViewController: NSViewController {
    private let wallpaperManager: WallpaperManager
    private var hostedController: NSViewController?
    private var currentSelectedItem: SelectedItem?
    private var currentVideoGridView: AppKitLibraryGridContainerView?
    private var currentSILGridView: SILGridContainerView?
    private var currentSILTag: String?
    private var lastVideoInspectorCardID: String?
    private var lastSILInspectorCardID: String?
    private var lastOnlineDownloadsInspectorCardID: String?
    private var cancellables = Set<AnyCancellable>()

    init(wallpaperManager: WallpaperManager) {
        self.wallpaperManager = wallpaperManager
        super.init(nibName: nil, bundle: nil)
        observeVideoLibraryState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        let rootView = NSView()
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.clear.cgColor
        view = rootView
    }

    func update(selectedItem: SelectedItem) {
        guard currentSelectedItem != selectedItem else { return }
        closeOnlineDownloadsInspectorIfNeeded(leavingFor: selectedItem)
        currentSelectedItem = selectedItem
        currentVideoGridView = nil
        currentSILGridView = nil
        currentSILTag = nil

        let controller = makeHostedController(for: selectedItem)
        replaceHostedController(with: controller)
    }

    private func observeVideoLibraryState() {
        wallpaperManager.$wallpapers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateCurrentVideoGridIfNeeded() }
            .store(in: &cancellables)

        wallpaperManager.$recentlyUsedWallpapers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateCurrentVideoGridIfNeeded() }
            .store(in: &cancellables)

        wallpaperManager.$searchQuery
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateCurrentVideoGridIfNeeded() }
            .store(in: &cancellables)

        wallpaperManager.$perSelectionSortStates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateCurrentVideoGridIfNeeded() }
            .store(in: &cancellables)

        wallpaperManager.$inspectedWallpaperID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncVideoInspectorIfNeeded() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .inspectorHostDidPresent)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in self?.mountVideoInspectorContentIfNeeded(notification) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .inspectorHostDidClose)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in self?.clearVideoInspectorIfNeeded(notification) }
            .store(in: &cancellables)

        SILService.shared.$wallpapers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateCurrentSILGridIfNeeded() }
            .store(in: &cancellables)

        SILService.shared.$selectedID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateCurrentSILGridSelectionStateIfNeeded()
                self?.syncSILInspectorIfNeeded()
            }
            .store(in: &cancellables)

        SILService.shared.$selectedIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateCurrentSILGridSelectionStateIfNeeded() }
            .store(in: &cancellables)

        SILService.shared.$isMultiSelectMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateCurrentSILGridSelectionStateIfNeeded() }
            .store(in: &cancellables)

        SILService.shared.$gridZoomOffset
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.currentSILGridView?.invalidateLayout() }
            .store(in: &cancellables)

        SILService.shared.$sortState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateCurrentSILGridIfNeeded() }
            .store(in: &cancellables)

        SILService.shared.$searchQuery
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateCurrentSILGridIfNeeded() }
            .store(in: &cancellables)

        SILService.shared.$inspectedWallpaperID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncSILInspectorIfNeeded() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .inspectorHostDidPresent)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in self?.mountSILInspectorContentIfNeeded(notification) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .inspectorHostDidClose)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in self?.clearSILInspectorIfNeeded(notification) }
            .store(in: &cancellables)

        OnlineLibraryService.shared.$inspectedDownloadedItemID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncOnlineDownloadsInspectorIfNeeded() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .inspectorHostDidPresent)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in self?.mountOnlineDownloadsInspectorContentIfNeeded(notification) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .inspectorHostDidClose)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in self?.clearOnlineDownloadsInspectorIfNeeded(notification) }
            .store(in: &cancellables)
    }

    private func makeHostedController(for selectedItem: SelectedItem) -> NSViewController {
        let selection = selectedItem.selectionContext

        switch selectedItem {
        case .onlineLibrary:
            return StaticViewController(contentView: OnlineLibraryBrowserView())
        case .onlineDownloads:
            return StaticViewController(contentView: AppKitOLDownloadsContainerView())
        case .steamWorkshop, .steamSubscribed:
            return StaticViewController(contentView: AppKitSteamWorkshopBrowserView())
        case .steamDownloads:
            return StaticViewController(contentView: AppKitSteamWorkshopDownloadsView())
        case .staticImageLibrary:
            let container = makeSILGridContainer(silTag: nil)
            return StaticViewController(contentView: container)
        case .silTag(let tag):
            let container = makeSILGridContainer(silTag: tag)
            return StaticViewController(contentView: container)
        default:
            let container = AppKitLibraryGridContainerView(
                wallpaperManager: wallpaperManager,
                animatesReorder: selection == .category(.recentlyUsed),
                animatesInsertDelete: selection != .category(.recentlyUsed)
            )
            currentVideoGridView = container
            updateVideoGrid(container, for: selection)
            return StaticViewController(contentView: container)
        }
    }

    private func makeSILGridContainer(silTag: String?) -> SILGridContainerView {
        let container = SILGridContainerView()
        currentSILGridView = container
        currentSILTag = silTag
        container.currentSILTag = silTag
        updateSILGrid(container, silTag: silTag)
        return container
    }

    private func updateCurrentVideoGridIfNeeded() {
        guard let currentSelectedItem,
              currentSelectedItem.isInVideoLibraryContext,
              let currentVideoGridView else {
            return
        }
        updateVideoGrid(currentVideoGridView, for: currentSelectedItem.selectionContext)
    }

    private func updateVideoGrid(
        _ gridView: AppKitLibraryGridContainerView,
        for selection: WallpaperSelectionContext
    ) {
        gridView.update(
            wallpapers: wallpaperManager.sortedWallpapers(
                selection.sourceWallpapers(from: wallpaperManager),
                selectionKey: selection.scrollPersistenceKey
            )
        )
    }

    private func syncVideoInspectorIfNeeded() {
        guard currentSelectedItem?.isInVideoLibraryContext == true else { return }
        guard let wallpaper = wallpaperManager.selectedWallpaperForInspector else {
            if let cardID = lastVideoInspectorCardID {
                InspectorHostActions.postClose(module: .videoLibrary, cardID: cardID)
                lastVideoInspectorCardID = nil
            }
            return
        }

        lastVideoInspectorCardID = wallpaper.id
        InspectorHostActions.postOpen(
            module: .videoLibrary,
            presentation: .infoPanel(
                cardID: wallpaper.id,
                title: wallpaper.displayTitle,
                subtitle: wallpaperManager.currentSelectionContext.displayTitle,
                preferredWidth: 368,
                focusPolicy: .preserveCurrentResponder
            )
        )
    }

    private func mountVideoInspectorContentIfNeeded(_ notification: Notification) {
        guard currentSelectedItem?.isInVideoLibraryContext == true,
              let request = InspectorHostRequest(userInfo: notification.userInfo),
              request.token.module == .videoLibrary,
              let wallpaper = wallpaperManager.selectedWallpaperForInspector,
              wallpaper.id == request.token.cardID else {
            return
        }

        let hostedView = VideoLibraryInspectorView(wallpaper: wallpaper, wallpaperManager: wallpaperManager)
        InspectorHostActions.postMount(
            module: .videoLibrary,
            cardID: wallpaper.id,
            hostedView: hostedView
        )
    }

    private func clearVideoInspectorIfNeeded(_ notification: Notification) {
        guard let request = InspectorHostRequest(userInfo: notification.userInfo),
              request.token.module == .videoLibrary else {
            return
        }
        if lastVideoInspectorCardID == request.token.cardID {
            lastVideoInspectorCardID = nil
        }
        if wallpaperManager.inspectedWallpaperID == request.token.cardID {
            wallpaperManager.dismissSelectedWallpaperInspector()
        }
    }

    private func updateCurrentSILGridIfNeeded() {
        guard currentSelectedItem?.isInStaticImageLibraryContext == true,
              let currentSILGridView else {
            return
        }
        updateSILGrid(currentSILGridView, silTag: currentSILTag)
    }

    private func updateCurrentSILGridSelectionStateIfNeeded() {
        guard currentSelectedItem?.isInStaticImageLibraryContext == true,
              let currentSILGridView else {
            return
        }
        currentSILGridView.scheduleSelectionVisualUpdate()
        currentSILGridView.refreshVisibleItemsIfNeeded(isMultiSelectMode: SILService.shared.isMultiSelectMode)
    }

    private func updateSILGrid(_ gridView: SILGridContainerView, silTag: String?) {
        gridView.currentSILTag = silTag
        let wallpapers = silTag.map { tag in
            SILService.shared.sortedWallpapers.filter { $0.tags.contains(tag) }
        } ?? SILService.shared.sortedWallpapers
        gridView.update(wallpapers: wallpapers)
        gridView.invalidateLayout()
        gridView.scheduleSelectionVisualUpdate()
        gridView.refreshVisibleItemsIfNeeded(isMultiSelectMode: SILService.shared.isMultiSelectMode)
    }

    private func syncSILInspectorIfNeeded() {
        guard currentSelectedItem?.isInStaticImageLibraryContext == true else { return }
        guard let wallpaper = SILService.shared.selectedWallpaperForInspector else {
            if let cardID = lastSILInspectorCardID {
                InspectorHostActions.postClose(module: .staticImageLibrary, cardID: cardID)
                lastSILInspectorCardID = nil
            }
            return
        }

        lastSILInspectorCardID = wallpaper.id
        InspectorHostActions.postOpen(
            module: .staticImageLibrary,
            presentation: .infoPanel(
                cardID: wallpaper.id,
                title: wallpaper.title,
                subtitle: currentSILTag ?? "我的图片",
                preferredWidth: 356,
                focusPolicy: .preserveCurrentResponder
            )
        )
    }

    private func mountSILInspectorContentIfNeeded(_ notification: Notification) {
        guard currentSelectedItem?.isInStaticImageLibraryContext == true,
              let request = InspectorHostRequest(userInfo: notification.userInfo),
              request.token.module == .staticImageLibrary,
              let wallpaper = SILService.shared.selectedWallpaperForInspector,
              wallpaper.id == request.token.cardID else {
            return
        }

        let hostedView = SILInspectorView(wallpaper: wallpaper)
        InspectorHostActions.postMount(
            module: .staticImageLibrary,
            cardID: wallpaper.id,
            hostedView: hostedView
        )
    }

    private func clearSILInspectorIfNeeded(_ notification: Notification) {
        guard let request = InspectorHostRequest(userInfo: notification.userInfo),
              request.token.module == .staticImageLibrary else {
            return
        }
        if lastSILInspectorCardID == request.token.cardID {
            lastSILInspectorCardID = nil
        }
        if SILService.shared.inspectedWallpaperID == request.token.cardID {
            SILService.shared.dismissSelectedWallpaperInspector()
        }
    }

    private func syncOnlineDownloadsInspectorIfNeeded() {
        guard currentSelectedItem == .onlineDownloads else { return }
        guard let itemID = OnlineLibraryService.shared.selectedDownloadedItemIDForInspector else {
            if let cardID = lastOnlineDownloadsInspectorCardID {
                InspectorHostActions.postClose(module: .onlineLibrary, cardID: cardID)
                lastOnlineDownloadsInspectorCardID = nil
            }
            return
        }

        let cardID = onlineDownloadsInspectorCardID(for: itemID)
        lastOnlineDownloadsInspectorCardID = cardID
        InspectorHostActions.postOpen(
            module: .onlineLibrary,
            presentation: .infoPanel(
                cardID: cardID,
                title: "online_\(itemID).mp4",
                subtitle: "在线图库已下载项",
                preferredWidth: 356,
                focusPolicy: .preserveCurrentResponder
            )
        )
    }

    private func mountOnlineDownloadsInspectorContentIfNeeded(_ notification: Notification) {
        guard currentSelectedItem == .onlineDownloads,
              let request = InspectorHostRequest(userInfo: notification.userInfo),
              request.token.module == .onlineLibrary,
              let itemID = OnlineLibraryService.shared.selectedDownloadedItemIDForInspector,
              request.token.cardID == onlineDownloadsInspectorCardID(for: itemID) else {
            return
        }

        let hostedView = OnlineLibraryDownloadsInspectorView(itemID: itemID)
        InspectorHostActions.postMount(
            module: .onlineLibrary,
            cardID: request.token.cardID,
            hostedView: hostedView
        )
    }

    private func clearOnlineDownloadsInspectorIfNeeded(_ notification: Notification) {
        guard let request = InspectorHostRequest(userInfo: notification.userInfo),
              request.token.module == .onlineLibrary else {
            return
        }
        if lastOnlineDownloadsInspectorCardID == request.token.cardID {
            lastOnlineDownloadsInspectorCardID = nil
        }
        if let itemID = OnlineLibraryService.shared.selectedDownloadedItemIDForInspector,
           request.token.cardID == onlineDownloadsInspectorCardID(for: itemID) {
            OnlineLibraryService.shared.dismissSelectedDownloadedInspector()
        }
    }

    private func onlineDownloadsInspectorCardID(for itemID: Int) -> String {
        "online-download-\(itemID)"
    }

    private func closeOnlineDownloadsInspectorIfNeeded(leavingFor selectedItem: SelectedItem) {
        guard currentSelectedItem == .onlineDownloads,
              selectedItem != .onlineDownloads else {
            return
        }
        InspectorHostActions.postClose(module: .onlineLibrary)
        OnlineLibraryService.shared.dismissSelectedDownloadedInspector()
        lastOnlineDownloadsInspectorCardID = nil
    }

    private func replaceHostedController(with controller: NSViewController) {
        let previousController = hostedController
        previousController?.view.removeFromSuperview()
        previousController?.removeFromParent()

        hostedController = controller
        addChild(controller)
        let hostedView = controller.view
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostedView)
        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: view.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}

private final class StaticViewController: NSViewController {
    private let contentView: NSView

    init(contentView: NSView) {
        self.contentView = contentView
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = contentView
    }
}
