import AppKit

/// Native viewport/window observation shared by the two playlist artwork
/// consumers. It never requests pixels or decides which playlists are visible.
@MainActor final class WallpaperArtworkDemandObservation {
    private weak var view: NSView?
    private let changed: () -> Void
    private var boundsObserver: NSObjectProtocol?
    private var windowObservers: [NSObjectProtocol] = []
    private var windowVisibility: NSKeyValueObservation?
    var onScroll: (() -> Void)?

    init(view: NSView, clipView: NSClipView, changed: @escaping () -> Void) {
        self.view = view
        self.changed = changed
        clipView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
            object: clipView, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.changed(); self?.onScroll?() }
            }
        windowDidChange()
    }

    var isVisible: Bool {
        guard let view else { return false }
        return view.window?.isVisible == true && view.window?.isMiniaturized == false && !view.isHiddenOrHasHiddenAncestor
    }

    func windowDidChange() {
        windowVisibility?.invalidate()
        windowVisibility = nil
        windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
        windowObservers = []
        if let window = view?.window {
            windowVisibility = window.observe(\.isVisible, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.changed() }
            }
            for name in [NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
                windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.changed() }
                })
            }
        }
        changed()
    }

    isolated deinit {
        windowVisibility?.invalidate()
        if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
        windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}
