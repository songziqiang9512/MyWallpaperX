import AppKit

private let inspectorHostSlideInTiming = CAMediaTimingFunction(controlPoints: 0.22, 1.12, 0.32, 1.0)
private let inspectorHostSlideOutTiming = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.22, 1.0)

/// Layout and the existing Inspector host only. Page, selection and source
/// services are injected by App composition, never inferred from module flags.
final class AppKitMainSplitViewController: NSSplitViewController {
    private enum LayoutConstants {
        static let defaultSidebarWidth: CGFloat = 220
        static let splitAutosaveName = "MainSplitViewV2"
        static let splitAutosaveFramesKeyPrefix = "NSSplitView Subview Frames "
    }
    private let sidebarController: NSViewController
    private let sidebarTintHost: AppKitListTintSurface
    private let detailHostController: NSViewController
    private let permitsNoticeInteraction: ((NSPoint) -> Bool)?
    private let inspectorStore = InspectorHostStore()
    private lazy var inspectorController = InspectorHostViewController(store: inspectorStore)
    private lazy var detailContainerController = InspectorDetailContainerViewController(
        contentController: detailHostController, overlayController: inspectorController,
        permitsNoticeInteraction: permitsNoticeInteraction)
    private let listBackgroundTint = AppKitListBackgroundTint()
    private let sidebarMinWidth: CGFloat = 200
    private let sidebarMaxWidth: CGFloat = 320
    private var notificationObservers: [NSObjectProtocol] = []
    private weak var preservedFirstResponder: NSResponder?
    private var inspectorTransitionGeneration = 0
    var onRestoreContentFocus: (() -> Void)?

    init(sidebar: NSViewController, content: NSViewController, sidebarTintHost: AppKitListTintSurface,
         permitsNoticeInteraction: ((NSPoint) -> Bool)? = nil) {
        sidebarController = sidebar
        self.sidebarTintHost = sidebarTintHost
        detailHostController = content
        self.permitsNoticeInteraction = permitsNoticeInteraction
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit { notificationObservers.forEach(NotificationCenter.default.removeObserver) }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureSplitItems()
    }

    func bindTint(_ source: ListThumbnailTintSource?) {
        loadViewIfNeeded()
        listBackgroundTint.bind(source)
    }

    func setUsesThumbnailTint(_ enabled: Bool) {
        loadViewIfNeeded()
        listBackgroundTint.setUsesThumbnailTint(enabled)
    }

    private func configureSplitItems() {
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
        listBackgroundTint.install(sidebar: sidebarTintHost, main: detailContainerController.backgroundView)

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
        let wasPresented = inspectorStore.isPresented && detailContainerController.isOverlayPresented
        inspectorTransitionGeneration += 1

        if inspectorStore.currentRequest == nil {
            preservedFirstResponder = view.window?.firstResponder
        }

        inspectorStore.present(request)
        if wasPresented {
            detailContainerController.updatePresentedPanelWidth(request.preferredWidth)
        } else {
            applyInspectorVisibility(isVisible: true, panelWidth: request.preferredWidth)
        }
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
        // 视图侧 hide completion 与 store 侧共用同一 transition generation：
        // 动画在途时 generation 前进即视为过期，防止重新打开被过期 completion 藏掉。
        let transitionGeneration = inspectorTransitionGeneration
        detailContainerController.setOverlayVisible(
            isVisible,
            panelWidth: panelWidth,
            panelOffset: panelWidth + 48,
            completion: completion,
            isCancelled: { [weak self] in
                self?.inspectorTransitionGeneration != transitionGeneration
            }
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

        onRestoreContentFocus?()
    }
}

private final class InspectorDetailContainerViewController: NSViewController {
    let backgroundView = AppKitListTintSurface()
    private let contentController: NSViewController
    private let overlayController: NSViewController
    private let overlayView = InspectorOverlayPassthroughView()
    private let overlayAnimationHostView = NSView()
    private var didInstallOverlay = false
    private var overlayTrailingConstraint: NSLayoutConstraint?
    private var overlayWidthConstraint: NSLayoutConstraint?

    var isOverlayPresented: Bool { !overlayView.isHidden && overlayView.isActive }

    init(contentController: NSViewController, overlayController: NSViewController,
         permitsNoticeInteraction: ((NSPoint) -> Bool)? = nil) {
        self.contentController = contentController
        self.overlayController = overlayController
        super.init(nibName: nil, bundle: nil)
        overlayView.permitsNoticeInteraction = permitsNoticeInteraction
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        let containerView = backgroundView
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
        completion: (() -> Void)? = nil,
        isCancelled: (() -> Bool)? = nil
    ) {
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
            // NSAnimationContext 的 completionHandler 无法中途取消：若隐藏动画期间
            // transition generation 已前进（如窗口内重新打开 inspector），这份过期
            // completion 不得再隐藏视图并清零宽度，否则面板与 store 状态脱节。
            if let isCancelled, isCancelled() {
                return
            }
            self.overlayView.isHidden = true
            self.overlayController.view.isHidden = true
            self.overlayAnimationHostView.isHidden = true
            overlayWidthConstraint.constant = 0
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

    /// Content tokens may change while the existing host remains on screen.
    /// Updating width must not restart its entrance or reset an in-flight slide.
    func updatePresentedPanelWidth(_ panelWidth: CGFloat) {
        overlayWidthConstraint?.constant = max(0, panelWidth + 24)
        view.needsLayout = true
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

private final class InspectorOverlayPassthroughView: NSView, ToolbarGridScrollDismissalSurface {
    var isActive = false
    var permitsNoticeInteraction: ((NSPoint) -> Bool)?

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
        if hitView === self, NSApp.currentEvent?.type != .scrollWheel, let superview,
           permitsNoticeInteraction?(superview.convert(point, to: nil)) == true { return nil }
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
