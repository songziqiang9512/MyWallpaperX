import AppKit

/// The existing main content root; lifecycle hooks add no view or drawing layer.
final class AppKitListTintSurface: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?
    var onAppearanceChange: (() -> Void)?
    var ignoresHitTesting = false
    override func hitTest(_ point: NSPoint) -> NSView? {
        ignoresHitTesting ? nil : super.hitTest(point)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }
}

/// One projection owner per main window. All controls retain their system accent.
@MainActor final class AppKitListBackgroundTint {
    typealias Sampler = (CGImage, @escaping (ListThumbnailTintColor?) -> Void) -> (() -> Void)
    struct DisplayOptions {
        var allowsTint: Bool
        var reduceMotion: Bool
    }
    static let animationKey = "listThumbnailTint"
    static let animationDuration: TimeInterval = 0.75
    private weak var sidebar: AppKitListTintSurface?
    private weak var main: AppKitListTintSurface?
    private let sample: Sampler
    private let displayOptions: () -> DisplayOptions
    private var source: ListThumbnailTintSource?
    private var stopObservingSource: (() -> Void)?
    private var cancelLoad: (() -> Void)?
    private var cancelSample: (() -> Void)?
    private var generation = 0
    private var cache: [UUID: ListThumbnailTintColor] = [:]
    private var cacheOrder: [UUID] = []
    private var color: ListThumbnailTintColor?
    private weak var window: NSWindow?
    private var visibility: NSKeyValueObservation?
    private var windowObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var isActive = false
    private var usesThumbnailTint = true
    var onProjectionChange: ((NSColor, Bool) -> Void)?

    init(sample: Sampler? = nil, displayOptions: (() -> DisplayOptions)? = nil) {
        self.sample = sample ?? Self.sampleThumbnail
        self.displayOptions = displayOptions ?? {
            let workspace = NSWorkspace.shared
            return DisplayOptions(allowsTint: !workspace.accessibilityDisplayShouldReduceTransparency
                && !workspace.accessibilityDisplayShouldIncreaseContrast,
                reduceMotion: workspace.accessibilityDisplayShouldReduceMotion)
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                     NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncVisibility(); self?.project() }
            })
        }
    }

    isolated deinit {
        stopObservingSource?()
        cancelLoad?()
        cancelSample?()
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    func install(sidebar sidebarHost: AppKitListTintSurface, main mainHost: AppKitListTintSurface) {
        sidebar = sidebarHost
        main = mainHost
        // Sidebar composition supplies one passive surface below its original
        // scroll view. Native scroll backing layers own their own background.
        // Installing this projection adds no view or material to either host.
        sidebarHost.wantsLayer = true
        mainHost.wantsLayer = true
        sidebarHost.onAppearanceChange = { [weak self] in self?.project(animated: false) }
        mainHost.onWindowChange = { [weak self] in self?.bindWindow($0) }
        mainHost.onAppearanceChange = { [weak self] in self?.project(animated: false) }
        bindWindow(mainHost.window)
    }

    func bind(_ next: ListThumbnailTintSource?) {
        guard source !== next else { return }
        stopObservingSource?()
        source = next
        stopObservingSource = next?.observe { [weak self] in self?.refresh() }
        refresh() // The first snapshot may have been published before mounting.
    }

    func setUsesThumbnailTint(_ enabled: Bool) {
        guard usesThumbnailTint != enabled else { return }
        usesThumbnailTint = enabled
        syncVisibility()
        if !enabled { project(animated: false) }
    }

    private func bindWindow(_ next: NSWindow?) {
        guard window !== next else { return }
        visibility = nil
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers.removeAll()
        window = next
        if let next {
            visibility = next.observe(\.isVisible, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.syncVisibility() }
            }
            for name in [NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
                windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: next, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.syncVisibility() }
                })
            }
        }
        syncVisibility()
    }

    private func syncVisibility() {
        let active = window?.isVisible == true && window?.isMiniaturized == false && !NSApp.isHidden
            && usesThumbnailTint && displayOptions().allowsTint
        guard active != isActive else { return }
        isActive = active
        refresh()
    }

    private func refresh() {
        generation += 1
        cancelLoad?(); cancelLoad = nil
        cancelSample?(); cancelSample = nil
        color = nil
        project()
        guard isActive, let source, let request = source.request else { return }
        if let cached = cache[request.revision] { color = cached; project(); return }
        let expected = generation
        let lease = request.load { [weak self, weak source] image in
            guard let self, self.generation == expected, self.source === source,
                  source?.request?.revision == request.revision else { return }
            guard let image, let pixels = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            self.cancelSample?()
            let sampling = self.sample(pixels) { [weak self, weak source] result in
                guard let self, self.generation == expected, self.source === source,
                      source?.request?.revision == request.revision else { return }
                if let result {
                    self.cache[request.revision] = result
                    self.cacheOrder.removeAll { $0 == request.revision }
                    self.cacheOrder.append(request.revision)
                    if self.cacheOrder.count > 24 { self.cache.removeValue(forKey: self.cacheOrder.removeFirst()) }
                }
                self.color = result
                self.project()
            }
            if self.generation == expected { self.cancelSample = sampling } else { sampling() }
        }
        // A cache hit can complete synchronously and reenter bind/refresh.
        if generation == expected { cancelLoad = lease } else { lease() }
    }

    private func project(animated: Bool = true) {
        let options = displayOptions()
        let tint: NSColor
        if let color, options.allowsTint {
            tint = NSColor(name: nil) { appearance in
                let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: dark ? 0.12 : 0.09)
            }
        } else {
            tint = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0)
        }
        let animate = animated && isActive && !options.reduceMotion
        onProjectionChange?(tint, animate)
        let hosts: [NSView?] = [sidebar, main]
        for view in hosts.compactMap({ $0 }) {
            guard let layer = view.layer else { continue }
            Self.apply(tint, to: layer, appearance: view.effectiveAppearance, animated: animate)
        }
    }

    /// The Settings consumer shares only this stateless native color transition.
    static func apply(_ tint: NSColor?, to layer: CALayer, appearance: NSAppearance, animated: Bool) {
        var resolved: CGColor?
        appearance.performAsCurrentDrawingAppearance {
            resolved = tint.flatMap { ($0.usingColorSpace(.sRGB) ?? $0).cgColor }
        }
        if layer.backgroundColor == resolved {
            if !animated { layer.removeAnimation(forKey: animationKey) }
            return
        }
        // Retarget from the visible color, rather than either model endpoint.
        let previous = layer.presentation()?.backgroundColor ?? layer.backgroundColor
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.backgroundColor = resolved
        CATransaction.commit()
        if animated, previous != resolved {
            let transition = CABasicAnimation(keyPath: "backgroundColor")
            transition.fromValue = previous
            transition.toValue = resolved
            transition.duration = animationDuration
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(transition, forKey: animationKey)
        } else {
            layer.removeAnimation(forKey: animationKey)
        }
    }

    private static func sampleThumbnail(_ pixels: CGImage, completion: @escaping (ListThumbnailTintColor?) -> Void) -> () -> Void {
        let task = Task {
            let worker = Task.detached(priority: .utility) {
                guard !Task.isCancelled else { return nil as ListThumbnailTintColor? }
                return ListThumbnailTintSampler.average(pixels)
            }
            let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard !Task.isCancelled else { return }
            completion(result)
        }
        return { task.cancel() }
    }
}
