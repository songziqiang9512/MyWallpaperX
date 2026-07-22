import AppKit
import CoreGraphics
import Foundation
import QuartzCore

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
        let authoredEffectRenderPlans: [SceneAuthoredEffectRenderPlan]
        let userPropertyTextureURLs: [String: URL]
        let cacheDirectory: URL
        let logURL: URL?
        let recordID: String?
    }

    private var surfaces: [CGDirectDisplayID: Surface] = [:]
    private var launchContext: LaunchContext?
    private var observers: [NSObjectProtocol] = []
    private var frameTimer: Timer?
    private var sceneClock = SceneClock(hostTime: CACurrentMediaTime())

    var activeRecordID: String? { launchContext?.recordID }

    private init() {
        installObservers()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    @discardableResult
    func launch(
        renderDescriptor: SceneRenderDescriptor,
        authoredEffectRenderPlans: [SceneAuthoredEffectRenderPlan],
        userPropertyTextureURLs: [String: URL] = [:],
        cacheDirectory: URL,
        logURL: URL?,
        recordID: String? = nil
    ) -> Bool {
        launchContext = LaunchContext(
            renderDescriptor: renderDescriptor,
            authoredEffectRenderPlans: authoredEffectRenderPlans,
            userPropertyTextureURLs: userPropertyTextureURLs,
            cacheDirectory: cacheDirectory,
            logURL: logURL,
            recordID: recordID
        )
        return rebuildSurfaces(resetClock: true)
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

    @discardableResult
    func requestDebugSnapshot(
        windowNumber: Int,
        reason: String,
        outputDirectory: URL
    ) -> Bool {
        guard let surface = surfaces.values.first(where: {
            $0.window.windowNumber == windowNumber
        }) else { return false }
        surface.metalView.requestDebugSnapshot(
            reason: reason,
            outputDirectory: outputDirectory
        )
        return true
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
    private func rebuildSurfaces(resetClock: Bool = false) -> Bool {
        guard let launchContext else { return false }

        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            teardownSurfaces(clearContext: false)
            return false
        }

        let scopedURLs = launchContext.userPropertyTextureURLs.values.filter {
            $0.startAccessingSecurityScopedResource()
        }
        defer { scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() } }

        teardownSurfaces(clearContext: false)

        var created = false
        var wroteLog = false
        for screen in screens {
            guard let screenID = Self.screenID(for: screen) else { continue }
            let frame = screen.frame
            guard let metalView = SceneMetalView(
                renderDescriptor: launchContext.renderDescriptor,
                authoredEffectRenderPlans: launchContext.authoredEffectRenderPlans,
                userPropertyTextureURLs: launchContext.userPropertyTextureURLs,
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

        if resetClock {
            sceneClock.reset(hostTime: CACurrentMediaTime())
        }
        startFrameDriver()
        return true
    }

    private func teardownSurfaces(clearContext: Bool) {
        frameTimer?.invalidate()
        frameTimer = nil
        for surface in surfaces.values {
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

    private func startFrameDriver() {
        frameTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.renderFrame()
        }
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
        renderFrame()
    }

    private func renderFrame() {
        updateMouseLocations()
        let timing = sceneClock.advance(
            hostTime: CACurrentMediaTime(),
            wallDate: Date()
        )
        for surface in surfaces.values {
            surface.metalView.renderFrame(timing: timing)
        }
    }

    private func updateMouseLocations() {
        let mouseLocation = NSEvent.mouseLocation
        for surface in surfaces.values {
            surface.metalView.updateMouseLocationInScreen(mouseLocation)
        }
    }
}
