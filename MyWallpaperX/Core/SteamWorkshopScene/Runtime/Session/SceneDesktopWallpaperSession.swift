import AppKit
import CoreGraphics
import Foundation
import OSLog
import QuartzCore

final class SceneDesktopWallpaperSession {
    private static let performanceLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "MyWallpaperX",
        category: "ScenePerformance"
    )

    private final class HostWindow: NSWindow {
        override var canBecomeKey: Bool { SceneDesktopWallpaperHost.usesDebugEvidenceWindow }
        override var canBecomeMain: Bool { SceneDesktopWallpaperHost.usesDebugEvidenceWindow }
    }

    final class Surface {
        let window: NSWindow
        let metalView: SceneMetalView
        let scriptGeneration: UInt64
        var didSubmitSimulationFrame = false

        init(
            window: NSWindow,
            metalView: SceneMetalView,
            scriptGeneration: UInt64
        ) {
            self.window = window
            self.metalView = metalView
            self.scriptGeneration = scriptGeneration
        }
    }

    struct PendingDeferredLayerVisibilityUpdate {
        let generation: UInt64
        let replacements: [String: SceneUserPropertyValue]
        let changedPropertyKeys: Set<String>
        let layerIDs: Set<Int>
        let recordID: String?
    }

    let lifecycleID = UUID()
    var retiringSurfaces: [ObjectIdentifier: Surface] = [:]
    var isVisible = false
    var audioDemand = (spectrum: false, currentProcess: false)
    var onAudioDemandChanged: (() -> Void)?
    var onFirstFrameCompletion: ((CGDirectDisplayID, Bool) -> Void)?
    var drainCallbacks: [@MainActor (Bool) -> Void] = []
    let retiringSurfaceDrain = DispatchGroup()
    var surfaceDrainFailed = false
    var drainStarted = false
    var drainResult: Bool?
    var surfaces: [CGDirectDisplayID: Surface] = [:]
    var preparedSurfaceIDs: Set<CGDirectDisplayID> = []
    var launchContext: SceneDesktopWallpaperLaunchContext?
    private var activeSpaceObserver: NSObjectProtocol?
    var localPointerEventMonitor: Any?
    var globalPointerEventMonitor: Any?
    var frameTimer: Timer?
    var frameDriverDeadline: CFTimeInterval?
    var screenReconciliationWorkItem: DispatchWorkItem?
    var screenTopology: [SceneScreenTopology] = []
    /// 最近一次实际建成表面的拓扑快照；与权威目标集 screenTopology
    /// 分离，供屏拓扑协调判断"是否真的需要重建"。
    var rebuiltTopology: [SceneScreenTopology] = []
    var evaluationTransaction = SceneEvaluationTransaction()
    var sceneClock = SceneClock(hostTime: CACurrentMediaTime())
    var sharedLayerAlphaRuntime =
        SceneSharedLayerAlphaRuntime(program: .empty)
    var videoTextureSourceRegistry: SceneVideoTextureSourceRegistry?
    var soundPlaybackRegistry: SceneSoundPlaybackRegistry?
    var nextVideoProviderEpoch: UInt64 = 0
    var nextSoundPlaybackEpoch: UInt64 = 0
    var firstFramePresentationRegistration:
        SceneFirstFramePresentationRegistration?
    var nextDeferredPropertyGeneration: UInt64 = 0
    var pendingDeferredLayerVisibilityUpdate:
        PendingDeferredLayerVisibilityUpdate?
    var userPropertyTextureLoad: SceneUserPropertyTextureLoadResult = .empty
    var pendingUserTextureUpdates: [UInt64: PendingUserTextureUpdate] = [:]
    var latestUserTextureRevisions: [String: UInt64] = [:]
    var nextUserTextureGeneration: UInt64 = 1
    let userTexturePreparationQueue = DispatchQueue(
        label: "com.mywallpaperx.scene-user-textures",
        qos: .userInitiated
    )
    let textureDecodeCacheBudget: SceneTextureDecodeCacheBudget
#if DEBUG
    var debugRejectPreparedFrameOnce: UInt64? = ProcessInfo.processInfo.environment[
        "MWX_SCENE_DEBUG_REJECT_PREPARED_FRAME_ONCE"
    ].flatMap(UInt64.init)
    var debugPointerOverride: SceneSurfacePointerInput?
    var debugSurfaceReferenceFrames: [CGDirectDisplayID: NSRect] = [:]
    var debugDropDynamicValuesFrameIndex: UInt64?
    var debugDidDropDynamicValues = false
    var debugDidLogDynamicValuesRecovery = false
    var debugDynamicLayerVisibilitySignature: String?
#endif

    var activeRecordID: String? { launchContext?.recordID }
    var isPlaybackActive: Bool {
        launchContext != nil && !sceneClock.isPaused
    }

    /// 性能预算档（M0.7）：帧节奏与预算束随命令热切换，不重启壁纸。
    private(set) var performanceProfile: PlaybackPerformanceProfile = .current

    func applyPerformanceProfile(_ profile: PlaybackPerformanceProfile) {
        performanceProfile = profile
        textureDecodeCacheBudget.updateMaximumBytes(
            profile.sceneTextureDecodeCacheByteBudget
        )
    }

    /// A host is process-local runtime state. SceneDaemonRuntime owns the
    /// product instance; the explicit DEBUG evidence runner owns its own.
    init(textureDecodeCacheBudget: SceneTextureDecodeCacheBudget) {
        self.textureDecodeCacheBudget = textureDecodeCacheBudget
        installObservers()
    }

    deinit {
        removePointerEventMonitors()
        if let activeSpaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(
                activeSpaceObserver
            )
        }
    }

    func activate(
        _ context: SceneDesktopWallpaperLaunchContext
    ) throws {
        // Preparation has completed and relinquished the shared VM domain.
        // Rebase QuickJS's stack guard before any main-thread provider/VM call.
        context.propertyVectorScriptProgram.domain?.adoptCurrentThread()
        precondition(launchContext == nil, "a session owns exactly one launch")
        let teardownReason: SceneGraphExecutionResetReason = .surfaceStop
        nextVideoProviderEpoch &+= 1
        videoTextureSourceRegistry = SceneVideoTextureSourceRegistry(
            epoch: nextVideoProviderEpoch,
            capturesLifecycleObservations: context.capturesExecutionObservations
        )
        launchContext = context
        userPropertyTextureLoad = context.userPropertyTextureLoad
        evaluationTransaction = .init()
        let activateStageStart = CACurrentMediaTime()
#if DEBUG
        debugDynamicLayerVisibilitySignature = nil
#endif
        sharedLayerAlphaRuntime = .init(
            program: context.sharedLayerAlphaProgram
        )
        guard rebuildSurfacesReconcilingAudioDemand(
            context,
            rebuild: {
                rebuildSurfaces(
                    resetClock: true,
                    teardownReason: teardownReason
                )
            },
            revokeLaunch: { stop() }
        ) else {
            throw SceneDesktopWallpaperHostLaunchError.noSurface
        }
        NSLog("MWX LAUNCH-STAGE: stage=activate-surfaces elapsedMs=%.0f", (CACurrentMediaTime() - activateStageStart) * 1000)
        nextSoundPlaybackEpoch &+= 1
        let soundPlaybackRegistry = SceneSoundPlaybackRegistry(
            program: context.soundPlaybackProgram,
            epoch: nextSoundPlaybackEpoch
        )
        self.soundPlaybackRegistry = soundPlaybackRegistry
        // 新注册表继承公共静音意图（M0.2）。
        if !isVisible || PlaybackMuteState.shared.isMuted {
            soundPlaybackRegistry.setMuted(true)
        }
        soundPlaybackRegistry.setMasterVolume(
            Double(PlaybackVolumeState.shared.normalizedVolume)
        )
        soundPlaybackRegistry.start(
            paused: !isVisible || sceneClock.isPaused,
            userValues: context.liveState.userValues
        )
        installPointerEventMonitorsIfNeeded()
        NSLog(
            "MWX LAUNCH-STAGE: stage=activate-end elapsedMs=%.0f",
            (CACurrentMediaTime() - activateStageStart) * 1000
        )
    }

    func promote(firstPresentation: SceneFirstFramePresentationRegistration?) {
        isVisible = true
        var usesSystemMedia = launchContext?.requiresSystemMedia == true
#if DEBUG
        if (SceneDesktopWallpaperHost.usesDebugEvidenceWindow
            || ProcessInfo.processInfo.arguments.contains("--mwx-debug-scene-root")),
           ProcessInfo.processInfo.environment["MWX_SCENE_DEBUG_SYSTEM_MEDIA"] != "1" {
            usesSystemMedia = false
        }
#endif
        if usesSystemMedia { SceneSystemMediaProvider.shared.acquire(lifecycleID) }
        firstFramePresentationRegistration = firstPresentation
        for surface in surfaces.values {
            surface.metalView.registerFirstPresentation { [weak firstPresentation] drawable in
                firstPresentation?.arm(on: drawable) ?? false
            }
            surface.window.alphaValue = 1
            surface.window.orderFrontRegardless()
        }
        soundPlaybackRegistry?.setMuted(PlaybackMuteState.shared.isMuted)
        if !sceneClock.isPaused { soundPlaybackRegistry?.resume() }
        installPointerEventMonitorsIfNeeded()
        // A paused candidate already rendered its frame while transparent.
        // Present it once visibly without rerunning its simulation.
        surfaces.values.forEach { $0.didSubmitSimulationFrame = false }
        if sceneClock.isPaused { startFrameDriver() }
    }


    func stop() {
        teardownSurfaces(clearContext: true, reason: .surfaceStop)
    }

#if DEBUG
    func debugSnapshot() -> SceneDesktopWallpaperHost.DebugSnapshot {
        SceneDesktopWallpaperHost.DebugSnapshot(
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
        outputDirectory: URL,
        kind: SceneDebugFrameCapture.RequestClass
    ) -> SceneDebugFrameCapture.Admission {
        guard let surface = surfaces.values.first(where: {
            $0.window.windowNumber == windowNumber
        }) else {
            SceneDebugFrameCapture.reportRejected(reason: reason, stage: "surface-lookup")
            return .rejected("surface-lookup")
        }
        return surface.metalView.requestDebugSnapshot(
            reason: reason,
            outputDirectory: outputDirectory, kind: kind
        )
    }

    /// DEBUG evidence: the current particle load report lines, captured at
    /// request time so bursty/short-lifetime child systems are represented by
    /// their live state instead of the launch-time zero-particle summary.
    #if DEBUG
    func debugParticleLoadReportLines() -> [String] {
        surfaces.values.sorted { $0.window.windowNumber < $1.window.windowNumber }
            .compactMap { $0.metalView.debugParticleLoadReportLines() }
            .flatMap { $0 }
    }
    #endif

    func setDebugPointerOverride(_ input: SceneSurfacePointerInput?) {
        debugPointerOverride = input
        updateMouseLocations()
    }

    @discardableResult
    func debugResizeSurfaces(scale: CGFloat) -> Bool {
        guard SceneDesktopWallpaperHost.usesDebugEvidenceWindow,
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
        guard SceneDesktopWallpaperHost.usesDebugEvidenceWindow,
              !surfaces.isEmpty else { return false }
        surfaces.values.forEach {
            $0.metalView.invalidateResolvedMaterialRuntime(reason: reason)
        }
        return true
    }

    @discardableResult
    func setDebugDropDynamicValuesFrameIndex(_ frameIndex: UInt64?) -> Bool {
        guard SceneDesktopWallpaperHost.usesDebugEvidenceWindow else { return false }
        debugDropDynamicValuesFrameIndex = frameIndex
        debugDidDropDynamicValues = false
        debugDidLogDynamicValuesRecovery = false
        return true
    }
#endif

    private func installObservers() {
        activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reassertSurfaceVisibility()
        }
    }

    func applyDisplayConfiguration(_ topology: [SceneScreenTopology]) {
        guard !topology.isEmpty else { return }
        // 先落权威目标集：主 App 裁决的显示集（多屏开=全部、关=首屏）
        // 是 rebuildSurfaces 的表面来源，不能只当变更触发器。
        screenTopology = topology
        scheduleScreenConfigurationReconciliation(topology)
    }

    private func scheduleScreenConfigurationReconciliation(
        _ topology: [SceneScreenTopology]
    ) {
        guard launchContext != nil else { return }
        screenReconciliationWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.launchContext != nil else { return }
            guard topology != self.rebuiltTopology else {
                Self.performanceLogger.debug(
                    "Ignored unchanged Scene screen topology; surfaces=\(self.surfaces.count)"
                )
                self.reassertSurfaceVisibility()
                return
            }
            Self.performanceLogger.info(
                "Rebuilding Scene surfaces after screen topology change; old=\(self.rebuiltTopology.count) new=\(topology.count)"
            )
            guard let launchContext = self.launchContext else { return }
            _ = self.rebuildSurfacesReconcilingAudioDemand(
                launchContext,
                rebuild: { self.rebuildSurfaces() },
                revokeLaunch: { self.stop() }
            )
        }
        screenReconciliationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    private func reassertSurfaceVisibility() {
        guard isVisible else { return }
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

        // The pushed topology owns the visible display set (multi-display on
        // = all screens; off = the first screen). Entries resolve back to
        // their live NSScreen; screens that no longer exist are skipped.
        // NSScreen capture stays as the pre-push fallback.
        let allScreens = NSScreen.screens
        let targetTopology = screenTopology.isEmpty
            ? SceneScreenTopology.capture(screens: allScreens)
            : screenTopology
        let liveScreensByID = Dictionary(
            uniqueKeysWithValues: allScreens.compactMap { screen in
                Self.screenID(for: screen).map { ($0, screen) }
            }
        )
        var surfaceScreens = targetTopology.compactMap { entry -> (NSScreen, CGDirectDisplayID)? in
            liveScreensByID[entry.displayID].map { ($0, entry.displayID) }
        }
        guard !surfaceScreens.isEmpty else {
            teardownSurfaces(clearContext: false, reason: teardownReason)
            return false
        }

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
#if DEBUG
        // Bounded evidence-only surfaces use actual independent views, drawables,
        // graph runtimes and resource pools on the available physical screen.
        if SceneDesktopWallpaperHost.usesDebugEvidenceWindow,
           let requested = ProcessInfo.processInfo.environment[
               "MWX_SCENE_DEBUG_SURFACE_COUNT"
           ].flatMap(Int.init), (2...4).contains(requested),
           let first = surfaceScreens.first {
            while surfaceScreens.count < requested {
                let identity = CGDirectDisplayID.max - UInt32(surfaceScreens.count)
                guard !surfaceScreens.contains(where: { $0.1 == identity }) else { break }
                surfaceScreens.append((first.0, identity))
            }
        }
#endif
        for (screen, screenID) in surfaceScreens {
            let frame = screen.frame
            guard let metalView = SceneMetalView(
                renderDescriptor: launchContext.runtimeInput.renderDescriptor,
                effectAdmissionCatalog: launchContext.effectAdmissionCatalog,
                baseMaterialProviderBindings:
                    launchContext.baseMaterialProviderBindings,
                stockNoiseTextures: launchContext.stockNoiseTextures,
                staticModelResources:
                    launchContext.preparedDeviceResources.staticModels,
                hasDynamicBloom: launchContext.runtimeInput.propertyBindingProgram
                    .instructions.contains { $0.target == .scene(.bloomEnabled) },
                instantiatedSceneScriptTargets: Set(
                    launchContext.sceneScriptScalarProgram.definitions.map(
                        \.target
                    )
                ),
                scriptSourceEvidence:
                    launchContext.sceneScriptSourceEvidence,
                pipelineRepository:
                    launchContext.preparedDeviceResources.pipelineRepository,
                imageLayerPipeline:
                    launchContext.preparedDeviceResources.imageLayerPipeline,
                resolvedMaterialRuntime: launchContext.makeResolvedMaterialRuntime(),
                textureAnimationPlaybackRuntime:
                    launchContext.textureAnimationPlaybackRuntime,
                textureUploadCommandQueue: launchContext.preparedDeviceResources
                    .baseImages.textureLoader.uploadCommandQueue,
                textureDecodeCacheBudget: launchContext.preparedDeviceResources
                    .baseImages.textureLoader.decodeCacheBudget,
                userPropertyTextureLoad: userPropertyTextureLoad,
                dynamicTextFieldsByLayerID:
                    launchContext.frameSchema.dynamicTextFieldsByLayerID,
                presentationStreamID: UInt64(screenID),
                firstFramePresentationRegistration: {
                    [weak firstFramePresentationRegistration] drawable in
                    firstFramePresentationRegistration?.arm(on: drawable) ?? false
                },
                frame: frame
            ) else {
                continue
            }
#if DEBUG
            if SceneDesktopWallpaperHost.usesDebugEvidenceWindow, screenID == surfaceScreens.last?.1,
               let raw = ProcessInfo.processInfo.environment["MWX_SCENE_DEBUG_DRAWABLE_UNAVAILABLE_FRAMES"],
               let count = UInt64(raw), (1...120).contains(count) {
                metalView.debugDrawableUnavailableFrameCount = count
            }
#endif
            if wroteLog {
                metalView.loadImageLayers(
                    from: launchContext.cacheDirectory,
                    resourceView: launchContext.resourceView,
                    videoSourceRegistry: videoTextureSourceRegistry,
                    preparedBaseImages:
                        launchContext.preparedDeviceResources.baseImages,
                    spriteTextureLoader:
                        launchContext.preparedDeviceResources.spriteTextureLoader,
                    preparedParticleVisibilityLayerIDs:
                        launchContext.preparedParticleVisibilityLayerIDs,
                    initialPlayback: launchContext.sceneScriptDynamicLayerRuntime.snapshot().particlePlayback,
                    initialDynamicValues: initialParticleDynamicValues
                )
            } else {
                metalView.loadImageLayers(
                    from: launchContext.cacheDirectory,
                    resourceView: launchContext.resourceView,
                    videoSourceRegistry: videoTextureSourceRegistry,
                    preparedBaseImages:
                        launchContext.preparedDeviceResources.baseImages,
                    spriteTextureLoader:
                        launchContext.preparedDeviceResources.spriteTextureLoader,
                    preparedParticleVisibilityLayerIDs:
                        launchContext.preparedParticleVisibilityLayerIDs,
                    initialPlayback: launchContext.sceneScriptDynamicLayerRuntime.snapshot().particlePlayback,
                    initialDynamicValues: initialParticleDynamicValues,
                    logURL: launchContext.logURL
                )
                launchContext.appendResolvedMaterialStartupReport()
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
            window.alphaValue = isVisible ? 1 : 0
            window.level = Self.wallpaperWindowLevel
            window.collectionBehavior = Self.windowCollectionBehavior
            window.contentView = metalView
            if SceneDesktopWallpaperHost.usesDebugEvidenceWindow {
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderFrontRegardless()
            }
            surfaces[screenID] = Surface(
                window: window,
                metalView: metalView,
                scriptGeneration: launchContext.propertyVectorScriptProgram.generation
            )
            if let surface = surfaces[screenID] {
                metalView.onRenderInvalidated = { [weak self, weak surface] reason in
                    DispatchQueue.main.async { [weak self, weak surface] in
                        guard let self, let surface, self.surfaces[screenID] === surface else { return }
                        if reason == .mediaPublication {
                            guard self.sceneClock.isPaused,
                                  self.refreshPausedMediaPublications() else { return }
                        } else {
                            surface.didSubmitSimulationFrame = false
                        }
                        if self.sceneClock.isPaused { self.startFrameDriver() }
                    }
                }
            }
            created = true
        }

        if !created || surfaces.count != surfaceScreens.count {
            teardownSurfaces(clearContext: false, reason: teardownReason)
            return false
        }

        preparedSurfaceIDs = Set(surfaceScreens.map(\.1))
        if resetClock {
            let hostTime = CACurrentMediaTime()
            let remainsPaused = sceneClock.isPaused
            sceneClock.reset(hostTime: hostTime)
            if remainsPaused {
                sceneClock.pause(hostTime: hostTime)
            }
        }
        updateAudioSpectrumDemand(launchContext, hasParticleAudioConsumer: surfaces.values.contains { $0.metalView.hasParticleAudioConsumer })
        rebuiltTopology = targetTopology
        let storageScreenIdentity = surfaces.count == 1
            ? surfaces.keys.first.flatMap(Self.sceneScriptStorageScreenIdentity)
            : nil
        do {
            try launchContext.propertyVectorScriptProgram.domain?
                .setStorageScreenIdentity(storageScreenIdentity)
        } catch {
            NSLog(
                "MWX SceneScript VM: localStorage screen identity unavailable failure=%@ fallback=global-only",
                String(describing: error)
            )
        }
        startFrameDriver()
        return true
    }

    private static func screenID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private static func sceneScriptStorageScreenIdentity(
        _ displayID: CGDirectDisplayID
    ) -> String? {
        let vendor = CGDisplayVendorNumber(displayID)
        let model = CGDisplayModelNumber(displayID)
        let serial = CGDisplaySerialNumber(displayID)
        guard vendor != 0, model != 0, serial != 0 else { return nil }
        return "display-v1-\(vendor)-\(model)-\(serial)"
    }

    private static var wallpaperWindowLevel: NSWindow.Level {
        if SceneDesktopWallpaperHost.usesDebugEvidenceWindow {
            return .floating
        }
        return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
    }

    private static var windowCollectionBehavior: NSWindow.CollectionBehavior {
        if SceneDesktopWallpaperHost.usesDebugEvidenceWindow {
            return [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        }
        return [.canJoinAllSpaces, .stationary, .ignoresCycle]
    }


}
