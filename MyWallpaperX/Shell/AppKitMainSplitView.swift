//
//  AppKitMainSplitView.swift
//  MyWallpaperX
//

import AppKit
import Combine

private let inspectorHostSlideInTiming = CAMediaTimingFunction(controlPoints: 0.22, 1.12, 0.32, 1.0)
private let inspectorHostSlideOutTiming = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.22, 1.0)

final class AppKitMainSplitViewController: NSSplitViewController {
    private enum LayoutConstants {
        static let defaultSidebarWidth: CGFloat = 220
        static let splitAutosaveName = "MainSplitViewV2"
        static let splitAutosaveFramesKeyPrefix = "NSSplitView Subview Frames "
    }

    private lazy var sidebarController = AppKitSidebarViewController(
        wallpaperManager: wallpaperManager,
        selectedItemGetter: { [weak self] in self?.selectedItem ?? .category(.myWallpapers) },
        selectedItemSetter: { [weak self] item in self?.setSelectedItem(item) }
    )
    private lazy var detailHostController = AppKitDetailHostViewController(wallpaperManager: wallpaperManager)
    private let inspectorStore = InspectorHostStore()
    private lazy var inspectorController = InspectorHostViewController(store: inspectorStore)
    private lazy var detailContainerController = InspectorDetailContainerViewController(
        contentController: detailHostController,
        overlayController: inspectorController
    )
    private var hasConfiguredSplitItems = false
    private var sidebarMinWidth: CGFloat = 200
    private var sidebarMaxWidth: CGFloat = 320
    private var currentManagerIdentity: ObjectIdentifier?
    private var currentSelectedItem: SelectedItem?
    private var notificationObservers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()
    private weak var preservedFirstResponder: NSResponder?
    private var inspectorTransitionGeneration = 0
    private let wallpaperManager: WallpaperManager
    private var selectedItem: SelectedItem = .category(.myWallpapers)
    private var lastPostedModuleID: ModuleIdentifier = .videoLibrary
    private var isSyncingSelectionFromManager = false

    convenience init() {
        self.init(wallpaperManager: .shared)
    }

    init(wallpaperManager: WallpaperManager) {
        self.wallpaperManager = wallpaperManager
        super.init(nibName: nil, bundle: nil)
        selectedItem = SelectedItem(selectionContext: wallpaperManager.currentSelectionContext)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        update(wallpaperManager: wallpaperManager, selectedItem: selectedItem)
        syncSelectedItemFromManager()
        syncInitialModuleFocusIfNeeded()
        observeShellState()
    }

    func update(wallpaperManager: WallpaperManager, selectedItem: SelectedItem) {
        if !hasConfiguredSplitItems {
            configureSplitItems()
        }

        let managerIdentity = ObjectIdentifier(wallpaperManager)
        let selectedValue = selectedItem
        // 这里只在 manager 实例变化或首次绑定时重绑，避免选中态变化触发整棵侧边栏/详情树重建。
        let shouldRebindRootViews = currentManagerIdentity != managerIdentity || currentSelectedItem != selectedValue
        guard shouldRebindRootViews else { return }

        currentManagerIdentity = managerIdentity
        currentSelectedItem = selectedValue

        sidebarController.updateSelectedItem(selectedValue)
        detailHostController.update(selectedItem: selectedValue)
    }

    private func setSelectedItem(_ newValue: SelectedItem) {
        guard selectedItem != newValue else { return }
        prepareSteamBrowseSelection(newValue)
        selectedItem = newValue
        update(wallpaperManager: wallpaperManager, selectedItem: selectedItem)
        syncManagerSelection(from: newValue)
    }

    private func observeShellState() {
        guard cancellables.isEmpty else { return }

        wallpaperManager.$selectedCategory
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncSelectedItemFromManager() }
            .store(in: &cancellables)

        wallpaperManager.$selectedTag
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncSelectedItemFromManager()
                self?.syncQuickLookPreviewIfNeeded()
            }
            .store(in: &cancellables)

        wallpaperManager.$selectedWallpaperId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncQuickLookPreviewIfNeeded() }
            .store(in: &cancellables)

        wallpaperManager.$selectedWallpaperIds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncQuickLookPreviewIfNeeded() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .wallpaperManagerDidResetToFreshInstallState)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleFreshInstallReset() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .appOpenSettingsRequested)
            .receive(on: DispatchQueue.main)
            .sink { _ in SettingsWindowController.shared.showWindow() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .appKitSelectItemRequested)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in self?.handleSelectItemRequest(notification) }
            .store(in: &cancellables)
    }

    private func handleSelectItemRequest(_ notification: Notification) {
        guard let selectedItem = notification.userInfo?["selectedItem"] as? String else { return }
        switch selectedItem {
        case "steamWorkshop":
            setSelectedItem(.steamWorkshop)
        case "steamSubscribed": setSelectedItem(.steamSubscribed)
        case "steamDownloads":
            setSelectedItem(.steamDownloads)
        case "onlineLibrary":
            setSelectedItem(.onlineLibrary)
        case "onlineDownloads":
            setSelectedItem(.onlineDownloads)
        case "staticImageLibrary":
            setSelectedItem(.staticImageLibrary)
        default:
            break
        }
    }

    private func syncSelectedItemFromManager() {
        guard !isSyncingSelectionFromManager else { return }
        let managerSelection = SelectedItem(selectionContext: wallpaperManager.currentSelectionContext)
        guard selectedItem != managerSelection else { return }
        isSyncingSelectionFromManager = true
        selectedItem = managerSelection
        update(wallpaperManager: wallpaperManager, selectedItem: selectedItem)
        isSyncingSelectionFromManager = false
    }

    private func syncManagerSelection(from item: SelectedItem) {
        if item.isInStaticImageLibraryContext {
            SILService.shared.clearSelectionState()
        }
        item.apply(to: wallpaperManager)

        let isSIL = item == .staticImageLibrary || { if case .silTag = item { return true }; return false }()
        let isOnline = item == .onlineLibrary || item == .onlineDownloads
        let isSteam = item == .steamWorkshop || item == .steamSubscribed || item == .steamDownloads
        let newModule = moduleIdentifier(for: item)

        if lastPostedModuleID != newModule {
            NotificationCenter.default.post(name: .inspectorHostCloseRequested, object: nil)
            lastPostedModuleID = newModule
            let silUserInfo = makeStaticImageLibraryModeUserInfo(for: item, enabled: isSIL)
            let onlineUserInfo: [String: Any] = [
                "enabled": isOnline,
                "isDownloads": item == .onlineDownloads
            ]
            let steamUserInfo: [String: Any] = [
                "enabled": isSteam,
                "isDownloads": item == .steamDownloads
            ]
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .staticImageLibraryModeDidChange,
                    object: nil,
                    userInfo: silUserInfo
                )
                NotificationCenter.default.post(
                    name: .onlineLibraryModeDidChange,
                    object: nil,
                    userInfo: onlineUserInfo
                )
                NotificationCenter.default.post(
                    name: .steamWorkshopModeDidChange,
                    object: nil,
                    userInfo: steamUserInfo
                )
            }
        } else if isSIL {
            let silUserInfo = makeStaticImageLibraryModeUserInfo(for: item, enabled: true)
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .staticImageLibraryModeDidChange,
                    object: nil,
                    userInfo: silUserInfo
                )
            }
        } else if isOnline {
            let onlineUserInfo: [String: Any] = [
                "enabled": true,
                "isDownloads": item == .onlineDownloads
            ]
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .onlineLibraryModeDidChange,
                    object: nil,
                    userInfo: onlineUserInfo
                )
            }
        } else if isSteam {
            let steamUserInfo: [String: Any] = [
                "enabled": true,
                "isDownloads": item == .steamDownloads
            ]
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .steamWorkshopModeDidChange,
                    object: nil,
                    userInfo: steamUserInfo
                )
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            NotificationCenter.default.post(
                name: .moduleDidBecomeActive,
                object: nil,
                userInfo: ["module": newModule.rawValue]
            )
        }
    }

    private func makeStaticImageLibraryModeUserInfo(
        for item: SelectedItem,
        enabled: Bool
    ) -> [String: Any] {
        var userInfo: [String: Any] = ["enabled": enabled]
        if case .silTag(let tag) = item {
            userInfo["silTag"] = tag
        }
        return userInfo
    }

    private func syncQuickLookPreviewIfNeeded() {
        QuickLookPreviewController.shared.syncVisiblePreview(for: wallpaperManager.selectedWallpaperForQuickLook)
    }

    private func syncInitialModuleFocusIfNeeded() {
        let module = moduleIdentifier(for: selectedItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            NotificationCenter.default.post(
                name: .moduleDidBecomeActive,
                object: nil,
                userInfo: ["module": module.rawValue]
            )
        }
    }

    private func handleFreshInstallReset() {
        selectedItem = .category(.myWallpapers)
        lastPostedModuleID = .videoLibrary
        update(wallpaperManager: wallpaperManager, selectedItem: selectedItem)
        NotificationCenter.default.post(name: .inspectorHostCloseRequested, object: nil)
        syncQuickLookPreviewIfNeeded()
    }

    private func configureSplitItems() {
        hasConfiguredSplitItems = true
        guard splitViewItems.isEmpty else { return }

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarController)
        sidebarItem.minimumThickness = sidebarMinWidth
        sidebarItem.maximumThickness = sidebarMaxWidth
        sidebarItem.preferredThicknessFraction = 0.22
        sidebarItem.canCollapse = false
        sidebarItem.isCollapsed = false
        sidebarItem.allowsFullHeightLayout = true

        let detailItem = NSSplitViewItem(viewController: detailContainerController)
        detailItem.allowsFullHeightLayout = false

        addSplitViewItem(sidebarItem)
        addSplitViewItem(detailItem)
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autosaveName = LayoutConstants.splitAutosaveName
        configureInspectorHostIfNeeded()
        configureInspectorNotificationObserversIfNeeded()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.splitView.subviews.count >= 2 else { return }
            if self.splitViewItems.count > 0 {
                self.splitViewItems[0].isCollapsed = false
            }
            self.applyInitialSidebarWidthIfNeeded()
        }
    }

    private func applyInitialSidebarWidthIfNeeded() {
        let autosaveFramesKey = LayoutConstants.splitAutosaveFramesKeyPrefix + LayoutConstants.splitAutosaveName
        let hasAutosavedFrames = UserDefaults.standard.object(forKey: autosaveFramesKey) != nil
        guard !hasAutosavedFrames else { return }
        splitView.setPosition(LayoutConstants.defaultSidebarWidth, ofDividerAt: 0)
    }

    private func configureInspectorHostIfNeeded() {
        detailContainerController.installOverlayIfNeeded()
        applyInspectorVisibility(isVisible: false, panelWidth: 0)
    }

    private func configureInspectorNotificationObserversIfNeeded() {
        guard notificationObservers.isEmpty else { return }

        let center = NotificationCenter.default
        notificationObservers.append(
            center.addObserver(
                forName: .inspectorHostOpenRequested,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleInspectorOpen(notification)
            }
        )
        notificationObservers.append(
            center.addObserver(
                forName: .inspectorHostCloseRequested,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleInspectorClose(notification)
            }
        )
        notificationObservers.append(
            center.addObserver(
                forName: .inspectorHostMountContentRequested,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleInspectorMountContent(notification)
            }
        )
    }

    private func handleInspectorOpen(_ notification: Notification) {
        guard let request = InspectorHostRequest(userInfo: notification.userInfo) else { return }
        inspectorTransitionGeneration += 1

        if inspectorStore.currentRequest == nil {
            preservedFirstResponder = view.window?.firstResponder
        }

        inspectorStore.present(request)
        applyInspectorVisibility(isVisible: true, panelWidth: request.preferredWidth)
        NotificationCenter.default.post(
            name: .inspectorHostDidPresent,
            object: nil,
            userInfo: request.userInfo
        )
    }

    private func handleInspectorClose(_ notification: Notification) {
        guard let currentRequest = inspectorStore.currentRequest else { return }

        let dismissRequest = InspectorHostDismissRequest(userInfo: notification.userInfo)
        if let dismissRequest, !dismissRequest.matches(currentRequest.token) {
            return
        }

        inspectorTransitionGeneration += 1
        let transitionGeneration = inspectorTransitionGeneration
        applyInspectorVisibility(isVisible: false, panelWidth: currentRequest.preferredWidth) { [weak self] in
            guard let self else { return }
            guard self.inspectorTransitionGeneration == transitionGeneration else { return }
            self.inspectorStore.finalizeDismiss()
            NotificationCenter.default.post(
                name: .inspectorHostDidClose,
                object: nil,
                userInfo: currentRequest.userInfo
            )
            self.restoreFirstResponder(afterClosing: currentRequest)
        }
    }

    private func handleInspectorMountContent(_ notification: Notification) {
        guard let request = InspectorHostMountRequest(userInfo: notification.userInfo) else { return }
        inspectorStore.mountContent(request)
    }

    private func applyInspectorVisibility(
        isVisible: Bool,
        panelWidth: CGFloat,
        completion: (() -> Void)? = nil
    ) {
        detailContainerController.setOverlayVisible(
            isVisible,
            panelWidth: panelWidth,
            panelOffset: panelWidth + 48,
            completion: completion
        )
    }

    private func restoreFirstResponder(afterClosing request: InspectorHostRequest) {
        defer { preservedFirstResponder = nil }

        guard let window = view.window else { return }
        if let responder = preservedFirstResponder {
            switch responder {
            case let responderView as NSView where responderView.window === window:
                window.makeFirstResponder(responderView)
                return
            case let textView as NSTextView where textView.window === window:
                window.makeFirstResponder(textView)
                return
            default:
                break
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            NotificationCenter.default.post(
                name: .moduleDidBecomeActive,
                object: nil,
                userInfo: ["module": request.token.module.rawValue]
            )
        }
    }
}

private final class InspectorDetailContainerViewController: NSViewController {
    private let contentController: NSViewController
    private let overlayController: NSViewController
    private let overlayView = InspectorOverlayPassthroughView()
    private let overlayAnimationHostView = NSView()
    private var didInstallOverlay = false
    private var pendingOverlayHideWorkItem: DispatchWorkItem?
    private var overlayTrailingConstraint: NSLayoutConstraint?
    private var overlayWidthConstraint: NSLayoutConstraint?

    init(contentController: NSViewController, overlayController: NSViewController) {
        self.contentController = contentController
        self.overlayController = overlayController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        let containerView = NSView()
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor
        view = containerView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        installContentIfNeeded()
        installOverlayIfNeeded()
        setOverlayVisible(false, panelWidth: 0, panelOffset: 0, animated: false)
    }

    func installOverlayIfNeeded() {
        guard !didInstallOverlay else { return }
        didInstallOverlay = true

        addChild(overlayController)
        let inspectorView = overlayController.view
        inspectorView.translatesAutoresizingMaskIntoConstraints = false
        inspectorView.wantsLayer = true
        inspectorView.layer?.backgroundColor = NSColor.clear.cgColor

        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.wantsLayer = true
        overlayView.layer?.backgroundColor = NSColor.clear.cgColor

        overlayAnimationHostView.translatesAutoresizingMaskIntoConstraints = false
        overlayAnimationHostView.wantsLayer = true
        overlayAnimationHostView.layer?.backgroundColor = NSColor.clear.cgColor

        view.addSubview(overlayView)
        overlayView.addSubview(overlayAnimationHostView)
        overlayAnimationHostView.addSubview(inspectorView)

        let trailingConstraint = overlayAnimationHostView.trailingAnchor.constraint(equalTo: overlayView.trailingAnchor)
        let widthConstraint = overlayAnimationHostView.widthAnchor.constraint(equalToConstant: 0)
        overlayTrailingConstraint = trailingConstraint
        overlayWidthConstraint = widthConstraint

        NSLayoutConstraint.activate([
            overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: view.topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            widthConstraint,
            overlayAnimationHostView.topAnchor.constraint(equalTo: overlayView.topAnchor),
            overlayAnimationHostView.bottomAnchor.constraint(equalTo: overlayView.bottomAnchor),
            trailingConstraint,
            inspectorView.leadingAnchor.constraint(equalTo: overlayAnimationHostView.leadingAnchor),
            inspectorView.trailingAnchor.constraint(equalTo: overlayAnimationHostView.trailingAnchor),
            inspectorView.topAnchor.constraint(equalTo: overlayAnimationHostView.topAnchor),
            inspectorView.bottomAnchor.constraint(equalTo: overlayAnimationHostView.bottomAnchor)
        ])
    }

    func setOverlayVisible(
        _ isVisible: Bool,
        panelWidth: CGFloat,
        panelOffset: CGFloat,
        animated: Bool = true,
        completion: (() -> Void)? = nil
    ) {
        pendingOverlayHideWorkItem?.cancel()
        pendingOverlayHideWorkItem = nil

        guard let overlayTrailingConstraint, let overlayWidthConstraint else {
            completion?()
            return
        }

        let hostWidth = max(0, panelWidth + 24)

        if isVisible {
            overlayView.isHidden = false
            overlayController.view.isHidden = false
            overlayAnimationHostView.isHidden = false
            overlayView.isActive = true
            overlayWidthConstraint.constant = hostWidth
            overlayTrailingConstraint.constant = panelOffset
            view.needsLayout = true

            let animations = {
                overlayTrailingConstraint.animator().constant = 0
                self.view.needsLayout = true
            }

            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = inspectorHostAnimationDuration
                    context.timingFunction = inspectorHostSlideInTiming
                    animations()
                } completionHandler: {
                    completion?()
                }
            } else {
                overlayTrailingConstraint.constant = 0
                view.needsLayout = true
                completion?()
            }
            return
        }

        overlayView.isActive = false
        let finishHide = { [weak self] in
            guard let self else { return }
            self.overlayView.isHidden = true
            self.overlayController.view.isHidden = true
            self.overlayAnimationHostView.isHidden = true
            overlayWidthConstraint.constant = 0
            self.pendingOverlayHideWorkItem = nil
            completion?()
        }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = inspectorHostAnimationDuration
                context.timingFunction = inspectorHostSlideOutTiming
                overlayTrailingConstraint.animator().constant = panelOffset
                view.needsLayout = true
            } completionHandler: {
                finishHide()
            }
        } else {
            overlayTrailingConstraint.constant = panelOffset
            view.needsLayout = true
            finishHide()
        }
    }

    private func installContentIfNeeded() {
        guard contentController.parent == nil else { return }
        addChild(contentController)
        let contentView = contentController.view
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentView)

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: view.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}

private final class InspectorOverlayPassthroughView: NSView {
    var isActive = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isActive else { return nil }
        let hitView = super.hitTest(point)
        return hitView === self ? self : hitView
    }

    override func mouseDown(with event: NSEvent) {
        guard isActive else {
            super.mouseDown(with: event)
            return
        }

        NotificationCenter.default.post(name: .inspectorHostCloseRequested, object: nil)
    }

    override func scrollWheel(with event: NSEvent) {
        guard isActive else {
            super.scrollWheel(with: event)
            return
        }

        // Hit-tested inspector children receive their own scrollWheel events.
        // If the gesture lands on the dimming overlay, close the inspector but
        // do not forward this same wheel event to the grid behind it.
        NotificationCenter.default.post(name: .inspectorHostCloseRequested, object: nil)
    }
}
