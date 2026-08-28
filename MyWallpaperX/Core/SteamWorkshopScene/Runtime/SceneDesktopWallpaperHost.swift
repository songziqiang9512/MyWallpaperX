import AppKit
import CoreGraphics
import Foundation
import OSLog
import QuartzCore

final class SceneDesktopWallpaperHost {
    static let shared = SceneDesktopWallpaperHost()
    private static let performanceLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "MyWallpaperX",
        category: "ScenePerformance"
    )

#if DEBUG
    struct DebugSnapshot {
        let surfaceCount: Int
        let windowNumbers: [Int]
        let isPlaybackPaused: Bool
        let isFrameDriverActive: Bool
    }

#endif

    private final class HostWindow: NSWindow {
        override var canBecomeKey: Bool { SceneDesktopWallpaperHost.usesDebugEvidenceWindow }
        override var canBecomeMain: Bool { SceneDesktopWallpaperHost.usesDebugEvidenceWindow }
    }

    final class Surface {
        let window: NSWindow
        let metalView: SceneMetalView
        var evaluationTransaction = SceneSurfaceEvaluationTransaction()
        var launchOriginTransitionRuntime: SceneLaunchOriginTransitionRuntime

        init(
            window: NSWindow,
            metalView: SceneMetalView,
            launchOriginTransitionProgram: SceneLaunchOriginTransitionProgram
        ) {
            self.window = window
            self.metalView = metalView
            launchOriginTransitionRuntime = .init(
                program: launchOriginTransitionProgram
            )
        }
    }

    var surfaces: [CGDirectDisplayID: Surface] = [:]
    var launchContext: SceneDesktopWallpaperLaunchContext?
    private var observers: [NSObjectProtocol] = []
    var frameTimer: Timer?
    var frameDriverDeadline: CFTimeInterval?
    var screenReconciliationWorkItem: DispatchWorkItem?
    var screenTopology: [SceneScreenTopology] = []
    var sceneClock = SceneClock(hostTime: CACurrentMediaTime())
    var mediaColorTransitionRuntime =
        SceneMediaColorTransitionRuntime(program: .empty)
    var sharedLayerAlphaRuntime =
        SceneSharedLayerAlphaRuntime(program: .empty)
    var videoTextureSourceRegistry: SceneVideoTextureSourceRegistry?
    var nextVideoProviderEpoch: UInt64 = 0
    var nextSceneScriptGeneration: UInt64 = 0
    let launchPreparationQueue = DispatchQueue(
        label: "com.mywallpaperx.scene-launch-preparation",
        qos: .userInitiated
    )
    var launchCancellation: SceneWallpaperLaunchCancellation?
    var nextLaunchRequestGeneration: UInt64 = 0
    var launchState: SceneWallpaperLaunchState?
#if DEBUG
    var debugPointerOverride: SceneSurfacePointerState?
    var debugSurfaceReferenceFrames: [CGDirectDisplayID: NSRect] = [:]
    var debugDropDynamicValuesFrameIndex: UInt64?
    var debugDidDropDynamicValues = false
    var debugDidLogDynamicValuesRecovery = false
#endif

    var activeRecordID: String? { launchContext?.recordID }
    var isPlaybackActive: Bool {
        launchContext != nil && !sceneClock.isPaused
    }

    private init() {
        installObservers()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func activate(_ context: SceneDesktopWallpaperLaunchContext) throws {
        let teardownReason: SceneGraphExecutionResetReason = launchContext == nil
            ? .surfaceStop
            : .sceneSwitch
        screenReconciliationWorkItem?.cancel()
        screenReconciliationWorkItem = nil
        videoTextureSourceRegistry?.stop()
        nextVideoProviderEpoch &+= 1
        videoTextureSourceRegistry = SceneVideoTextureSourceRegistry(
            epoch: nextVideoProviderEpoch
        )
        launchContext?.sceneScriptScalarProgram.invalidate()
        launchContext?.sceneScriptStringProgram.invalidate()
        launchContext?.sceneScriptCursorProgram.invalidate()
        launchContext?.propertyVectorScriptProgram.invalidate()
        launchContext = context
        mediaColorTransitionRuntime = .init(
            program: context.mediaColorTransitionProgram
        )
        sharedLayerAlphaRuntime = .init(
            program: context.sharedLayerAlphaProgram
        )
        SceneAudioSpectrumInbox.shared.setDemand(Self.requiresAudioSpectrum(
            resolvedMaterialExecutionCapabilities:
                context.resolvedMaterialExecutionCapabilities,
            hasParticleAudioConsumer:
                context.propertyVectorScriptProgram.hasAudioConsumers
                || context.sceneScriptScalarProgram.hasAudioConsumers
                || context.sceneScriptStringProgram.hasAudioConsumers
        ))
        guard rebuildSurfaces(
            resetClock: true,
            teardownReason: teardownReason
        ) else {
            stop()
            throw SceneDesktopWallpaperHostLaunchError.noSurface
        }
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
        cancelPendingLaunch()
        teardownSurfaces(clearContext: true, reason: .surfaceStop)
    }

#if DEBUG
    func debugSnapshot() -> DebugSnapshot {
        DebugSnapshot(
            surfaceCount: surfaces.count,
            windowNumbers: surfaces.values.map { $0.window.windowNumber }.sorted(),
            isPlaybackPaused: sceneClock.isPaused,
            isFrameDriverActive: frameTimer?.isValid == true
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

    @discardableResult
    func debugResizeSurfaces(scale: CGFloat) -> Bool {
        guard Self.usesDebugEvidenceWindow,
              scale.isFinite,
              scale > 0,
              scale <= 1,
              !surfaces.isEmpty else { return false }
        for (screenID, surface) in surfaces {
            let reference = debugSurfaceReferenceFrames[screenID]
                ?? surface.window.frame
            debugSurfaceReferenceFrames[screenID] = reference
            let size = CGSize(
                width: max(1, reference.width * scale),
                height: max(1, reference.height * scale)
            )
            let frame = NSRect(
                x: reference.midX - size.width / 2,
                y: reference.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
            surface.window.setFrame(frame, display: true, animate: false)
        }
        return true
    }

    @discardableResult
    func debugInvalidateResolvedMaterialRuntimes(
        reason: SceneGraphExecutionResetReason
    ) -> Bool {
        guard Self.usesDebugEvidenceWindow,
              !surfaces.isEmpty else { return false }
        surfaces.values.forEach {
            $0.metalView.invalidateResolvedMaterialRuntime(reason: reason)
        }
        return true
    }

    @discardableResult
    func setDebugDropDynamicValuesFrameIndex(_ frameIndex: UInt64?) -> Bool {
        guard Self.usesDebugEvidenceWindow else { return false }
        debugDropDynamicValuesFrameIndex = frameIndex
        debugDidDropDynamicValues = false
        debugDidLogDynamicValuesRecovery = false
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
                self?.scheduleScreenConfigurationReconciliation()
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
        teardownSurfaces(clearContext: true, reason: .sceneSwitch)
    }

    private func scheduleScreenConfigurationReconciliation() {
        guard launchContext != nil else { return }
        screenReconciliationWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.launchContext != nil else { return }
            let currentTopology = SceneScreenTopology.capture()
            guard currentTopology != self.screenTopology else {
                Self.performanceLogger.debug(
                    "Ignored unchanged Scene screen topology; surfaces=\(self.surfaces.count)"
                )
                self.reassertSurfaceVisibility()
                return
            }
            Self.performanceLogger.info(
                "Rebuilding Scene surfaces after screen topology change; old=\(self.screenTopology.count) new=\(currentTopology.count)"
            )
            _ = self.rebuildSurfaces()
        }
        screenReconciliationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
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
    private func rebuildSurfaces(
        resetClock: Bool = false,
        teardownReason: SceneGraphExecutionResetReason = .surfaceStop
    ) -> Bool {
        guard let launchContext, let videoTextureSourceRegistry else { return false }

        let rebuildHostTime = CACurrentMediaTime()
        videoTextureSourceRegistry.beginSurfaceRebuild(
            sceneTime: sceneClock.currentSceneTime(hostTime: rebuildHostTime),
            hostTime: rebuildHostTime
        )
        defer { videoTextureSourceRegistry.completeSurfaceRebuild() }

        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            teardownSurfaces(clearContext: false, reason: teardownReason)
            return false
        }

        let scopedURLs = launchContext.userPropertyTextureURLs.values.filter {
            $0.startAccessingSecurityScopedResource()
        }
        defer { scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() } }

        teardownSurfaces(clearContext: false, reason: teardownReason)

        let initialParticleDynamicValues = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 0,
            generation: 0,
            definitions: launchContext.sceneScriptScalarProgram.definitions,
            userValues: [:],
            timelineValues: [:],
            sceneScriptValues: [:]
        ).snapshot

        var created = false
        var wroteLog = false
        for screen in screens {
            guard let screenID = Self.screenID(for: screen) else { continue }
            let frame = screen.frame
            guard let metalView = SceneMetalView(
                renderDescriptor: launchContext.runtimeInput.renderDescriptor,
                effectAdmissionCatalog: launchContext.effectAdmissionCatalog,
                mediaThumbnailBindings: launchContext.mediaThumbnailBindings,
                pipelineRepository: launchContext.pipelineRepository,
                resolvedMaterialRuntime: launchContext.makeResolvedMaterialRuntime(),
                userPropertyTextureURLs: launchContext.userPropertyTextureURLs,
                frame: frame
            ) else {
                continue
            }
            if wroteLog {
                metalView.loadImageLayers(
                    from: launchContext.cacheDirectory,
                    resourceView: launchContext.resourceView,
                    videoSourceRegistry: videoTextureSourceRegistry,
                    spriteTextureLoader: launchContext.spriteTextureLoader,
                    initialDynamicValues: initialParticleDynamicValues
                )
            } else {
                metalView.loadImageLayers(
                    from: launchContext.cacheDirectory,
                    resourceView: launchContext.resourceView,
                    videoSourceRegistry: videoTextureSourceRegistry,
                    spriteTextureLoader: launchContext.spriteTextureLoader,
                    initialDynamicValues: initialParticleDynamicValues,
                    logURL: launchContext.logURL
                )
                launchContext.appendResolvedMaterialStartupReport()
                Self.appendTimelineReport(
                    to: launchContext.logURL,
                    program: launchContext.timelineProgram
                )
                Self.appendTextScriptReport(
                    to: launchContext.logURL,
                    program: launchContext.textScriptProgram
                )
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
                metalView: metalView,
                launchOriginTransitionProgram:
                    launchContext.launchOriginTransitionProgram
            )
            created = true
        }

        if !created {
            teardownSurfaces(clearContext: false, reason: teardownReason)
            return false
        }

        if resetClock {
            let hostTime = CACurrentMediaTime()
            let remainsPaused = sceneClock.isPaused
            sceneClock.reset(hostTime: hostTime)
            if remainsPaused {
                sceneClock.pause(hostTime: hostTime)
            }
        }
        updateAudioSpectrumDemand(launchContext, hasParticleAudioConsumer: surfaces.values.contains { $0.metalView.hasParticleAudioConsumer })
        screenTopology = SceneScreenTopology.capture()
        startFrameDriver()
        return true
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

    static var usesDebugEvidenceWindow: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--mwx-debug-scene-evidence-dir")
#else
        false
#endif
    }

}
