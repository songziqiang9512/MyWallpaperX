import AppKit
import CoreGraphics
import Foundation
import OSLog
import QuartzCore

final class SceneDesktopWallpaperSession {
#if DEBUG
    private static let performanceLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "MyWallpaperX",
        category: "ScenePerformance"
    )

#endif
    final class HostWindow: NSWindow {
        override var canBecomeKey: Bool {
            SceneDesktopWallpaperHost.usesDebugEvidenceWindow && !SceneDesktopWallpaperHost.usesBackgroundEvidenceWindow
        }
        override var canBecomeMain: Bool {
            SceneDesktopWallpaperHost.usesDebugEvidenceWindow && !SceneDesktopWallpaperHost.usesBackgroundEvidenceWindow
        }
    }

    final class Surface {
        let window: NSWindow
        let metalView: SceneMetalView
        let scriptGeneration: UInt64
        var particlePlayback: SceneParticlePlaybackState?
        var puppetPlaybackStates: [Int: ScenePuppetPlaybackState] = [:]
        var dynamicPuppetTopologyRevision: UInt64?
        var dynamicPuppetLayerIDs: Set<Int> = []
#if DEBUG
        var recordedPuppetPoseLayerIDs: Set<Int> = []
#endif
        var simulationFrame: SceneMetalView.SimulationFrame?
        var didSubmitSimulationFrame = false
        var pendingPausedFrame: SceneMetalRenderer.PreparedFrame?
        var lastSubmittedPresentationSources: Set<UUID> = []
        var videoSwitchDeadline: TimeInterval?
        var qualityStatus = SurfaceQualityStatus()

        init(
            window: NSWindow,
            metalView: SceneMetalView,
            scriptGeneration: UInt64,
            particlePlayback: SceneParticlePlaybackState? = nil
        ) {
            self.window = window
            self.metalView = metalView
            self.scriptGeneration = scriptGeneration
            self.particlePlayback = particlePlayback
        }
    }

    struct PendingDeferredLayerVisibilityUpdate {
        let generation: UInt64
        let replacements: [String: SceneUserPropertyValue]
        let changedPropertyKeys: Set<String>
        let layerIDs: Set<Int>
        let hasConditionalAtlases: Bool
        let recordID: String?
    }

    let lifecycleID = UUID()
    var retiringSurfaces: [ObjectIdentifier: Surface] = [:]
    var isVisible = false
    var isOutputActive = true
    var audioDemand = (spectrum: false, currentProcess: false)
    var onAudioDemandChanged: (() -> Void)?
    var onDisplayQualityChanged: (() -> Void)?
    var onFirstFrameCompletion: ((CGDirectDisplayID, Bool) -> Void)?
    var initialPresentationCohort = SceneInitialPresentationCohort()
    var drainCallbacks: [@MainActor (Bool) -> Void] = []
    let retiringSurfaceDrain = DispatchGroup()
    var surfaceDrainFailed = false
    var drainStarted = false
    var drainResult: Bool?
    var surfaces: [CGDirectDisplayID: Surface] = [:] {
        didSet { onDisplayQualityChanged?() }
    }
    var preparedSurfaceIDs: Set<CGDirectDisplayID> = []
    var launchContext: SceneDesktopWallpaperLaunchContext?
    var sceneScriptPuppetPoseSurface: ObjectIdentifier?
    private var activeSpaceObserver: NSObjectProtocol?
    var localPointerEventMonitor: Any?
    let userShortcutOpener: (URL) -> Bool
    var userShortcutInput = SceneUserShortcutInputState()
    var userShortcutURLs: [String: URL] = [:]
    var userShortcutScopedKeys: Set<String> = []
    var globalPointerEventMonitor: Any?
    var frameTimer: Timer?
    var frameDriverDeadline: CFTimeInterval?
    var pendingParticleFrameInterval: TimeInterval = 0
    var pausedFrameRetryDeadline: CFTimeInterval?
    var screenReconciliationWorkItem: DispatchWorkItem?
    var screenTopology: [SceneScreenTopology] = []
    var evaluationTransaction = SceneEvaluationTransaction()
    var sceneClock = SceneClock(hostTime: CACurrentMediaTime())
    var videoTextureSourceRegistry: SceneVideoTextureSourceRegistry?
    var soundPlaybackRegistry: SceneSoundPlaybackRegistry?
    var nextVideoProviderEpoch: UInt64 = 0
    var nextSoundPlaybackEpoch: UInt64 = 0
    var firstFramePresentationRegistration:
        SceneFirstFramePresentationRegistration?
    var launchRequestID: UUID?
    var nextDeferredPropertyGeneration: UInt64 = 0
    var pendingDeferredLayerVisibilityUpdate:
        PendingDeferredLayerVisibilityUpdate?
    var userPropertyTextureLoad: SceneUserPropertyTextureLoadResult = .empty
    var dynamicTextTextures: SceneDynamicTextTextureStore?
    var mediaThumbnailTextures: SceneMediaThumbnailTextureStore?
    var pendingProviderUpdate: (
        dynamicValues: SceneDynamicSnapshot,
        dynamicLayers: [SceneRenderDescriptor.Layer],
        destroyedAuthoredLayerIDs: Set<Int>,
        dynamicTextFieldsByLayerID: [Int: Set<SceneDynamicTextField>],
        mediaInput: SceneMediaThumbnailInbox.Snapshot
    )?
    var pendingUserTextureUpdates: [UInt64: PendingUserTextureUpdate] = [:]
    var latestUserTextureRevisions: [String: UInt64] = [:]
    var nextUserTextureGeneration: UInt64 = 1
    var initialVideoPreparation: Task<Void, Never>?
    let userTexturePreparationQueue = DispatchQueue(
        label: "com.mywallpaperx.scene-user-textures",
        qos: .userInitiated
    )
    let textureDecodeCacheBudget: SceneTextureDecodeCacheBudget
    let surfacePreparationQueue: DispatchQueue
    var pendingSurfacePreparation: PendingSurfacePreparation?
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

    private(set) var animationFrameRate: AnimationFrameRate = .standard
    private var displayCadenceLimit = SceneScreenTopology.conservativeCadenceLimit
    private(set) var scenePostProcessing: ScenePostProcessingMode
    let allowsProjectedSpotVolume: Bool
    let shadowsDisabled: Bool
    let allowsSceneReflection: Bool
    var fitsCanvas = false {
        didSet {
            guard fitsCanvas != oldValue else { return }
            for surface in surfaces.values {
                surface.metalView.fitsCanvas = fitsCanvas
            }
        }
    }

    var effectiveAnimationFPS: Double { min(Double(animationFrameRate.rawValue), displayCadenceLimit) }

    func applyAnimationFrameRate(_ frameRate: AnimationFrameRate, displayLimit: Double) {
        let previousFPS = effectiveAnimationFPS
        animationFrameRate = frameRate
        displayCadenceLimit = displayLimit
        let nextFPS = effectiveAnimationFPS
        guard nextFPS != previousFPS else { return }
        if nextFPS > previousFPS, frameTimer != nil, !sceneClock.isPaused {
            pendingParticleFrameInterval = max(pendingParticleFrameInterval, 1 / previousFPS)
        }
        retuneFrameDriver()
    }

    func applyScenePostProcessing(_ mode: ScenePostProcessingMode) {
        guard mode != scenePostProcessing,
              mode.preparationMode == scenePostProcessing.preparationMode else { return }
        scenePostProcessing = mode
        let requestsDisplayHDR = mode.requestsDisplayHDR
        var redraw = false
        for surface in surfaces.values {
            if surface.metalView.setDisplayHDRRequested(requestsDisplayHDR),
               invalidatePausedDisplayOutput(for: surface) {
                redraw = true
            }
        }
        if redraw { startFrameDriver() }
    }

    func invalidatePausedDisplayOutput(for surface: Surface) -> Bool {
        guard isVisible, sceneClock.isPaused else { return false }
        surface.didSubmitSimulationFrame = false
        return true
    }

    /// A host is process-local runtime state. SceneDaemonRuntime owns the
    /// product instance; the explicit DEBUG evidence runner owns its own.
    init(textureDecodeCacheBudget: SceneTextureDecodeCacheBudget,
         surfacePreparationQueue: DispatchQueue,
         scenePostProcessing: ScenePostProcessingMode,
         shadowsDisabled: Bool = false, allowsProjectedSpotVolume: Bool = true,
         allowsSceneReflection: Bool = true,
         userShortcutOpener: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        self.userShortcutOpener = userShortcutOpener
        self.textureDecodeCacheBudget = textureDecodeCacheBudget
        self.surfacePreparationQueue = surfacePreparationQueue
        self.scenePostProcessing = scenePostProcessing
        self.allowsProjectedSpotVolume = allowsProjectedSpotVolume
        self.shadowsDisabled = shadowsDisabled
        self.allowsSceneReflection = allowsSceneReflection
        installObservers()
    }

    deinit {
        releaseUserShortcutScopes()
        removePointerEventMonitors()
        if let activeSpaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(
                activeSpaceObserver
            )
        }
    }

    func activate(
        _ context: SceneDesktopWallpaperLaunchContext,
        preparedSurfaces: [PreparedSurface],
        userPropertyTextureLoad: SceneUserPropertyTextureLoadResult
    ) throws {
        // Preparation has completed and relinquished the shared VM domain.
        // Rebase QuickJS's stack guard before any main-thread provider/VM call.
        context.propertyVectorScriptProgram.domain?.adoptCurrentThread()
        precondition(launchContext == nil, "a session owns exactly one launch")
        nextVideoProviderEpoch &+= 1
        videoTextureSourceRegistry = SceneVideoTextureSourceRegistry(
            epoch: nextVideoProviderEpoch,
            capturesLifecycleObservations: context.capturesExecutionObservations
        )
        sceneScriptPuppetPoseSurface = nil
        launchContext = context
        mediaThumbnailTextures = SceneMediaThumbnailTextureStore(
            device: context.preparedDeviceResources.device,
            textureUploadCommandQueue: context.preparedDeviceResources.baseImages.textureLoader.uploadCommandQueue,
            onPublication: { [weak self] store in self?.enqueueMediaThumbnailPublication(store) }
        )
        installUserShortcuts(context.userShortcuts)
        self.userPropertyTextureLoad = userPropertyTextureLoad
        evaluationTransaction = .init()
#if DEBUG
        let activateStageStart = CACurrentMediaTime()
        debugDynamicLayerVisibilitySignature = nil
#endif
        // Sound sources must be installed before video preparation releases
        // the first script frame.
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
        updateAudioSpectrumDemand(context, hasParticleAudioConsumer: nil)
        guard installInitialSurfaces(preparedSurfaces) else {
            stop()
            throw SceneDesktopWallpaperHostLaunchError.noSurface
        }
#if DEBUG
        NSLog("MWX LAUNCH-STAGE: stage=activate-surfaces elapsedMs=%.0f", (CACurrentMediaTime() - activateStageStart) * 1000)
#endif
        installPointerEventMonitorsIfNeeded()
#if DEBUG
        NSLog(
            "MWX LAUNCH-STAGE: stage=activate-end elapsedMs=%.0f",
            (CACurrentMediaTime() - activateStageStart) * 1000
        )
#endif
    }

    func promote(firstPresentation: SceneFirstFramePresentationRegistration?) {
        let heldInitialFrame = initialPresentationCohort.isHeld
        initialPresentationCohort.reset()
        isVisible = true
        reconcileSystemMediaDemand(requestID: firstPresentation?.requestID)
        firstFramePresentationRegistration = firstPresentation
        for surface in surfaces.values {
            surface.metalView.registerFirstPresentation { [weak firstPresentation] drawable in
                firstPresentation?.arm(on: drawable) ?? false
            }
            surface.window.alphaValue = 1
            Self.orderSurfaceWindow(surface.window)
        }
        soundPlaybackRegistry?.setMuted(!isOutputActive || PlaybackMuteState.shared.isMuted)
        if isOutputActive, !sceneClock.isPaused { soundPlaybackRegistry?.resume() }
        installPointerEventMonitorsIfNeeded()
        // A paused candidate already rendered its frame while transparent.
        // Present it once visibly without rerunning its simulation.
        surfaces.values.forEach { $0.didSubmitSimulationFrame = false }
        if sceneClock.isPaused, let mediaThumbnailTextures {
            _ = refreshPausedMediaPublications(mediaThumbnailTextures.snapshot())
        }
        if sceneClock.isPaused || heldInitialFrame { startFrameDriver() }
    }

    func reconcileSystemMediaDemand(requestID: UUID? = nil) {
        let retired = launchContext?.sceneScriptDynamicLayerRuntime.snapshot().destroyedAuthoredLayerIDs ?? []
        var usesSystemMedia = launchContext?.requiresSystemMedia(excludingLayerIDs: retired) == true
#if DEBUG
        if (SceneDesktopWallpaperHost.usesDebugEvidenceWindow
            || ProcessInfo.processInfo.arguments.contains("--mwx-debug-scene-root")),
           ProcessInfo.processInfo.environment["MWX_SCENE_DEBUG_SYSTEM_MEDIA"] != "1" {
            usesSystemMedia = false
        }
#endif
        if usesSystemMedia, isVisible, isOutputActive, let requestID = requestID ?? launchRequestID {
            SceneSystemMediaDemandRegistry.shared.acquire(lifecycleID, requestID: requestID)
        } else {
            SceneSystemMediaDemandRegistry.shared.release(lifecycleID)
        }
    }

    /// Keep the previous frame/resources available until the parent accepts the
    /// replacement's real presentation. A revoked candidate can restore it.
    func suspendPresentationForHandoff() {
        isVisible = false
        surfaces.values.forEach { $0.window.alphaValue = 0 }
        soundPlaybackRegistry?.setMuted(true)
        setPlaybackPaused(true)
        removePointerEventMonitors()
        SceneSystemMediaDemandRegistry.shared.release(lifecycleID)
    }

    func setOutputActive(_ active: Bool, playbackPaused: Bool) {
        isOutputActive = active
        setPlaybackPaused(playbackPaused || !active)
        soundPlaybackRegistry?.setMuted(!active || !isVisible || PlaybackMuteState.shared.isMuted)
        if active, isVisible {
            installPointerEventMonitorsIfNeeded()
        } else {
            removePointerEventMonitors()
        }
        reconcileSystemMediaDemand()
    }


    func stop() {
        teardownSurfaces(clearContext: true, reason: .surfaceStop)
    }
#if DEBUG
    func debugSnapshot(captureSurfaceState: Bool = false) -> SceneDesktopWallpaperHost.DebugSnapshot {
        let committed = evaluationTransaction.committedSnapshot
        let committedTopology = captureSurfaceState
            ? launchContext?.sceneScriptDynamicLayerRuntime.snapshot() : nil
        return SceneDesktopWallpaperHost.DebugSnapshot(
            surfaceCount: surfaces.count,
            windowNumbers: surfaces.values.map { $0.window.windowNumber }.sorted(),
            sessionID: lifecycleID,
            requestID: launchRequestID,
            sceneTime: sceneClock.currentSceneTime(hostTime: CACurrentMediaTime()),
            committedFrameIndex: committed?.frameIndex,
            committedGeneration: committed?.generation,
            committedTopologyRevision: committedTopology?.topologyRevision,
            committedDestroyedLayerIDs: committedTopology?.destroyedAuthoredLayerIDs.sorted() ?? [],
            surfacesByDisplay: captureSurfaceState ? debugSurfaceSnapshots() : [:],
            spriteAnimationLayerIDsByDisplay: surfaces.mapValues { $0.metalView.spriteAnimationLayerIDs.sorted() },
            isPlaybackPaused: sceneClock.isPaused,
            isFrameDriverActive: frameTimer?.isValid == true
        )
    }

    private func debugSurfaceSnapshots() -> [CGDirectDisplayID: SceneDesktopWallpaperHost.DebugSurfaceSnapshot] {
        typealias Snapshot = SceneDesktopWallpaperHost.DebugSurfaceSnapshot
        let targetFrames = Dictionary(uniqueKeysWithValues: Self.surfaceScreens(topology: screenTopology).map {
            ($0.1, $0.0.frame)
        })
        return Dictionary(uniqueKeysWithValues: surfaces.map { displayID, surface in
            let view = surface.metalView
            let frame = surface.simulationFrame
            let graph = view.renderer.imageCompositor.resolvedMaterialRuntime?.submissions
            return (displayID, Snapshot(
                surfaceIdentity: String(UInt(bitPattern: ObjectIdentifier(surface))),
                viewIdentity: String(UInt(bitPattern: ObjectIdentifier(view))),
                rendererTextureRegistryIdentity: String(UInt(bitPattern: ObjectIdentifier(view.renderer.textureRegistry))),
                graphRuntimeIdentity: graph?.runtimeInstanceIdentity,
                windowNumber: surface.window.windowNumber,
                windowFrame: Snapshot.rectangle(surface.window.frame),
                viewBounds: Snapshot.rectangle(view.bounds),
                drawableSize: [Double(view.metalLayer.drawableSize.width), Double(view.metalLayer.drawableSize.height)],
                contentsScale: Double(view.metalLayer.contentsScale),
                targetFrame: targetFrames[displayID].map(Snapshot.rectangle),
                simulationFrameIndex: frame?.timing.frameIndex,
                dynamicGeneration: frame?.context.dynamicValues.generation,
                sceneTime: frame?.timing.sceneTime,
                topologyRevision: frame?.topology.topologyRevision,
                destroyedLayerIDs: frame?.topology.destroyedAuthoredLayerIDs.sorted() ?? [],
                spriteTimes: frame?.spriteTimes ?? [:],
                particleStateIdentity: surface.particlePlayback?.lifecycleIdentity.uuidString,
                particleLayers: surface.particlePlayback?.debugLayerSnapshots() ?? []
            ))
        })
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
        let admission = surface.metalView.requestDebugSnapshot(
            reason: reason,
            outputDirectory: outputDirectory, kind: kind
        )
        if case .accepted = admission, sceneClock.isPaused {
            surface.didSubmitSimulationFrame = false
            startFrameDriver()
        }
        return admission
    }

    /// DEBUG evidence: the current particle load report lines, captured at
    /// request time so bursty/short-lifetime child systems are represented by
    /// their live state instead of the launch-time zero-particle summary.
    func debugParticleLoadReportLines() -> [String] {
        surfaces.values.sorted { $0.window.windowNumber < $1.window.windowNumber }
            .compactMap { $0.particlePlayback?.loadReportLines(descriptor: $0.metalView.renderer.renderDescriptor) }
            .flatMap { $0 }
    }

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

    func debugRetainSurfaces(_ count: Int) -> Bool {
        guard SceneDesktopWallpaperHost.usesDebugEvidenceWindow, let context = launchContext else { return false }
        let topology = screenTopology.isEmpty ? SceneScreenTopology.capture() : screenTopology
        let screens = Self.surfaceScreens(topology: topology).filter { surfaces[$0.1] != nil }
        guard count > 0, count < surfaces.count, count <= screens.count else { return false }
        let selected = Array(screens.prefix(count))
        let retainedIDs = Set(selected.map(\.1))
        screenTopology = topology.filter { retainedIDs.contains($0.displayID) }
        reconcileSurfaceScreens(selected, context: context)
        return surfaces.count == count
    }

    func debugSelectSurfaces(indices: [Int]) -> Bool {
        guard SceneDesktopWallpaperHost.usesDebugEvidenceWindow, let context = launchContext else { return false }
        let pool = Self.debugSurfacePool()
        guard !indices.isEmpty, Set(indices).count == indices.count,
              indices.allSatisfy({ pool.indices.contains($0) }) else { return false }
        screenTopology = indices.map { pool[$0] }
        reconcileSurfaceScreens(Self.surfaceScreens(topology: screenTopology), context: context)
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
        // 主 App 裁决目标屏；实际几何在协调时取对应 live screen。
        screenTopology = topology
        scheduleScreenConfigurationReconciliation(topology)
    }

    private func scheduleScreenConfigurationReconciliation(
        _ topology: [SceneScreenTopology]
    ) {
        guard launchContext != nil else { return }
        screenReconciliationWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let launchContext = self.launchContext else { return }
            self.reconcileSurfaceScreens(Self.surfaceScreens(topology: topology), context: launchContext)
        }
        screenReconciliationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    func reassertSurfaceVisibility() {
        guard isVisible else { return }
        guard launchContext != nil else { return }
        for surface in surfaces.values {
            surface.window.level = Self.wallpaperWindowLevel
            if !surface.window.isVisible {
                Self.orderSurfaceWindow(surface.window)
            }
        }
        updateMouseLocations()
    }

    func textTexturePublicationDidChange(_ store: SceneDynamicTextTextureStore) {
        guard dynamicTextTextures === store, !initialPresentationCohort.isHeld else { return }
        for surface in surfaces.values { surface.didSubmitSimulationFrame = false }
        if sceneClock.isPaused || awaitsInitialPresentation { startFrameDriver() }
    }

    func enqueueMediaThumbnailPublication(_ store: SceneMediaThumbnailTextureStore) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.mediaThumbnailTextures === store,
                  !self.initialPresentationCohort.isHeld, self.sceneClock.isPaused,
                  self.refreshPausedMediaPublications(store.snapshot()) else { return }
            self.startFrameDriver()
        }
    }

    static func screenID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    nonisolated static func sceneScriptStorageScreenIdentity(
        _ displayID: CGDirectDisplayID
    ) -> String? {
        let vendor = CGDisplayVendorNumber(displayID)
        let model = CGDisplayModelNumber(displayID)
        let serial = CGDisplaySerialNumber(displayID)
        guard vendor != 0, model != 0, serial != 0 else { return nil }
        return "display-v1-\(vendor)-\(model)-\(serial)"
    }

    static var wallpaperWindowLevel: NSWindow.Level {
        if SceneDesktopWallpaperHost.usesBackgroundEvidenceWindow { return .normal }
        if SceneDesktopWallpaperHost.usesDebugEvidenceWindow {
            return .floating
        }
        return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
    }

    static func orderSurfaceWindow(_ window: NSWindow, makesKey: Bool = false) {
        if SceneDesktopWallpaperHost.usesBackgroundEvidenceWindow {
            window.orderBack(nil)
        } else if makesKey {
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFrontRegardless()
        }
    }

    static var windowCollectionBehavior: NSWindow.CollectionBehavior {
        if SceneDesktopWallpaperHost.usesDebugEvidenceWindow {
            return [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        }
        return [.canJoinAllSpaces, .stationary, .ignoresCycle]
    }


}
