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

    private final class Surface {
        let window: NSWindow
        let metalView: SceneMetalView
        var evaluationTransaction = SceneSurfaceEvaluationTransaction()

        init(window: NSWindow, metalView: SceneMetalView) {
            self.window = window
            self.metalView = metalView
        }
    }

    private struct LaunchContext {
        let interpretationFile: SceneInterpretationFile
        let authoredEffectCatalog: SceneAuthoredEffectExecutionCatalog
        var liveState: ScenePropertyLiveUpdateState
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
#if DEBUG
    private var debugPointerOverride: SceneSurfacePointerState?
#endif

    var activeRecordID: String? { launchContext?.recordID }

    private init() {
        installObservers()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    @discardableResult
    func launch(
        interpretationFile: SceneInterpretationFile,
        userPropertyTextureURLs: [String: URL] = [:],
        cacheDirectory: URL,
        logURL: URL?,
        recordID: String? = nil
    ) -> Bool {
        let authoredEffectCatalog = SceneAuthoredEffectExecutionCatalog(
            descriptor: interpretationFile.renderDescriptor,
            authoredPlans: interpretationFile.authoredEffectRenderPlans,
            shaderContracts: interpretationFile.shaderContracts
        )
        launchContext = LaunchContext(
            interpretationFile: interpretationFile,
            authoredEffectCatalog: authoredEffectCatalog,
            liveState: ScenePropertyLiveUpdateState(
                program: interpretationFile.propertyBindingProgram,
                effectiveValues: interpretationFile.effectivePropertyValues,
                activeConsumerTargets: Self.activeLiveConsumerTargets(
                    in: interpretationFile.renderDescriptor,
                    authoredEffectCatalog: authoredEffectCatalog
                )
            ),
            userPropertyTextureURLs: userPropertyTextureURLs,
            cacheDirectory: cacheDirectory,
            logURL: logURL,
            recordID: recordID
        )
        SceneAudioSpectrumInbox.shared.setDemand(
            Self.requiresAudioSpectrum(in: authoredEffectCatalog)
        )
        return rebuildSurfaces(resetClock: true)
    }

    @discardableResult
    func applyUserPropertyValue(
        _ value: SceneUserPropertyValue,
        forPropertyKey propertyKey: String,
        recordID: String?
    ) -> Bool {
        applyUserPropertyValues(
            [propertyKey: value],
            changedPropertyKeys: [propertyKey],
            recordID: recordID
        )
    }

    @discardableResult
    func applyUserPropertyValues(
        _ replacements: [String: SceneUserPropertyValue],
        changedPropertyKeys: Set<String>,
        recordID: String?
    ) -> Bool {
        guard var context = launchContext,
              context.recordID == recordID,
              context.liveState.apply(
                  replacements: replacements,
                  changedPropertyKeys: changedPropertyKeys
              ) else {
            return false
        }
        launchContext = context
        return true
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

    func setDebugPointerOverride(_ state: SceneSurfacePointerState?) {
        debugPointerOverride = state
        updateMouseLocations()
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
                renderDescriptor: launchContext.interpretationFile.renderDescriptor,
                authoredEffectCatalog: launchContext.authoredEffectCatalog,
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
            SceneAudioSpectrumInbox.shared.setDemand(false)
            launchContext = nil
#if DEBUG
            debugPointerOverride = nil
#endif
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
        guard let launchContext else { return }
        updateMouseLocations()
        let timing = sceneClock.advance(
            hostTime: CACurrentMediaTime(),
            wallDate: Date()
        )
        let definitions = launchContext.interpretationFile.propertyBindingProgram.definitions
        // host-shared：所有 surface 共用同一帧频谱，与 property 输入同级。
        let audioSpectrum = SceneAudioSpectrumInbox.shared.latest()
        for surface in surfaces.values {
            let dynamicValues = surface.evaluationTransaction.evaluate(
                frameIndex: timing.frameIndex,
                definitions: definitions,
                userValues: launchContext.liveState.userValues
            ).snapshot
            surface.metalView.renderFrame(
                timing: timing,
                dynamicValues: dynamicValues,
                audioSpectrum: audioSpectrum
            )
        }
    }

    private func updateMouseLocations() {
#if DEBUG
        if let debugPointerOverride {
            for surface in surfaces.values {
                surface.metalView.applyPointerState(debugPointerOverride)
            }
            return
        }
#endif
        let mouseLocation = NSEvent.mouseLocation
        for surface in surfaces.values {
            surface.metalView.updateMouseLocationInScreen(mouseLocation)
        }
    }
}
