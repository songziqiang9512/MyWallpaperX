import AppKit
import CoreGraphics
import Foundation

final class SceneDesktopWallpaperHost {
    static let shared = SceneDesktopWallpaperHost()

#if DEBUG
    struct DebugSnapshot {
        let surfaceCount: Int
        let windowNumbers: [Int]
    }
#endif

    private final class HostWindow: NSWindow {
        override var canBecomeKey: Bool { SceneDesktopWallpaperHost.usesDebugEvidenceWindow }
        override var canBecomeMain: Bool { SceneDesktopWallpaperHost.usesDebugEvidenceWindow }
    }

    private struct Surface {
        let screenID: CGDirectDisplayID
        let window: NSWindow
        let metalView: SceneMetalView
    }

    private struct LaunchContext {
        let renderDescriptor: SceneRenderDescriptor
        let cacheDirectory: URL
        let logURL: URL?
    }

    private var surfaces: [CGDirectDisplayID: Surface] = [:]
    private var launchContext: LaunchContext?
    private var observers: [NSObjectProtocol] = []
    private var mouseTrackingTimer: Timer?

    private init() {
        installObservers()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    @discardableResult
    func launch(
        renderDescriptor: SceneRenderDescriptor,
        cacheDirectory: URL,
        logURL: URL?
    ) -> Bool {
        launchContext = LaunchContext(
            renderDescriptor: renderDescriptor,
            cacheDirectory: cacheDirectory,
            logURL: logURL
        )
        return rebuildSurfaces()
    }

    func stop() {
        teardownSurfaces(clearContext: true)
    }

#if DEBUG
    func debugSnapshot() -> DebugSnapshot {
        DebugSnapshot(
            surfaceCount: surfaces.count,
            windowNumbers: surfaces.values.map { $0.window.windowNumber }.sorted()
        )
    }
#endif

    private func installObservers() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: .wallpaperRuntimeWillSwitch,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleRuntimeWillSwitch(notification)
            },
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleScreenConfigurationChanged()
            },
            center.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.reassertSurfaceVisibility()
            }
        ]
    }

    private func handleRuntimeWillSwitch(_ notification: Notification) {
        guard let kindRaw = notification.userInfo?["kind"] as? String,
              let kind = WallpaperRuntimeKind(rawValue: kindRaw) else {
            return
        }
        guard kind != .scene else { return }
        stop()
    }

    private func handleScreenConfigurationChanged() {
        guard launchContext != nil else { return }
        _ = rebuildSurfaces()
    }

    private func reassertSurfaceVisibility() {
        guard launchContext != nil else { return }
        for surface in surfaces.values {
            surface.window.level = Self.wallpaperWindowLevel
            if !surface.window.isVisible {
                surface.window.orderFrontRegardless()
            }
        }
        updateMouseLocations()
    }

    @discardableResult
    private func rebuildSurfaces() -> Bool {
        guard let launchContext else { return false }

        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            teardownSurfaces(clearContext: false)
            return false
        }

        teardownSurfaces(clearContext: false)

        var created = false
        var wroteLog = false
        for screen in screens {
            guard let screenID = Self.screenID(for: screen) else { continue }
            let frame = screen.frame
            guard let metalView = SceneMetalView(
                renderDescriptor: launchContext.renderDescriptor,
                frame: frame
            ) else {
                continue
            }
            if wroteLog {
                metalView.loadImageLayers(from: launchContext.cacheDirectory)
            } else {
                metalView.loadImageLayers(from: launchContext.cacheDirectory, logURL: launchContext.logURL)
                wroteLog = true
            }

            let window = HostWindow(
                contentRect: frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.isReleasedWhenClosed = false
            window.ignoresMouseEvents = true
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.hidesOnDeactivate = false
            window.sharingType = .readOnly
            window.level = Self.wallpaperWindowLevel
            window.collectionBehavior = Self.windowCollectionBehavior
            window.contentView = metalView
            if Self.usesDebugEvidenceWindow {
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderFrontRegardless()
            }
            metalView.startRendering()

            surfaces[screenID] = Surface(
                screenID: screenID,
                window: window,
                metalView: metalView
            )
            created = true
        }

        if !created {
            teardownSurfaces(clearContext: false)
            return false
        }

        startMouseTracking()
        return true
    }

    private func teardownSurfaces(clearContext: Bool) {
        mouseTrackingTimer?.invalidate()
        mouseTrackingTimer = nil
        for surface in surfaces.values {
            surface.metalView.stopRendering()
            surface.window.orderOut(nil)
            surface.window.close()
        }
        surfaces.removeAll()
        if clearContext {
            launchContext = nil
        }
    }

    private static func screenID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private static var wallpaperWindowLevel: NSWindow.Level {
        if usesDebugEvidenceWindow {
            return .floating
        }
        return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
    }

    private static var windowCollectionBehavior: NSWindow.CollectionBehavior {
        if usesDebugEvidenceWindow {
            return [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        }
        return [.canJoinAllSpaces, .stationary, .ignoresCycle]
    }

    private static var usesDebugEvidenceWindow: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--mwx-debug-scene-evidence-dir")
#else
        false
#endif
    }

    private func startMouseTracking() {
        mouseTrackingTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.updateMouseLocations()
        }
        RunLoop.main.add(timer, forMode: .common)
        mouseTrackingTimer = timer
    }

    private func updateMouseLocations() {
        let mouseLocation = NSEvent.mouseLocation
        for surface in surfaces.values {
            surface.metalView.updateMouseLocationInScreen(mouseLocation)
        }
    }
}
