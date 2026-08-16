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
    }

    struct DebugAudioScaledValueBindingSnapshot: Encodable {
        let layerID: Int
        let target: String
        let effectiveValue: [Double]
        let liveParticleCount: Int?
    }

    struct DebugAudioScaledValueSnapshot: Encodable {
        let schemaVersion = 1
        let frameIndex: UInt64
        let audioGeneration: UInt64
        let audioWasSilent: Bool
        let bindings: [DebugAudioScaledValueBindingSnapshot]
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
        var hoverOriginTransitionRuntime: SceneHoverOriginTransitionRuntime

        init(
            window: NSWindow,
            metalView: SceneMetalView,
            launchOriginTransitionProgram: SceneLaunchOriginTransitionProgram,
            hoverOriginTransitionProgram: SceneHoverOriginTransitionProgram
        ) {
            self.window = window
            self.metalView = metalView
            launchOriginTransitionRuntime = .init(
                program: launchOriginTransitionProgram
            )
            hoverOriginTransitionRuntime = .init(
                program: hoverOriginTransitionProgram
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
    var mediaPlaybackPlaceholderFadeRuntime =
        SceneMediaPlaybackPlaceholderFadeRuntime(program: .empty)
    var mediaColorTransitionRuntime =
        SceneMediaColorTransitionRuntime(program: .empty)
    var sharedLayerAlphaRuntime =
        SceneSharedLayerAlphaRuntime(program: .empty)
    var audioScaledValueRuntime =
        SceneAudioScaledValueRuntime(program: .empty)
    var videoTextureSourceRegistry: SceneVideoTextureSourceRegistry?
    var nextVideoProviderEpoch: UInt64 = 0
#if DEBUG
    var debugPointerOverride: SceneSurfacePointerState?
    var debugDropDynamicValuesFrameIndex: UInt64?
    var debugDidDropDynamicValues = false
    var debugDidLogDynamicValuesRecovery = false
    var debugAudioScaledValueValues: [SceneDynamicTarget: SceneDynamicValue] = [:]
    var debugAudioScaledValueFrameIndex: UInt64 = 0
    var debugAudioScaledValueGeneration: UInt64 = 0
    var debugAudioScaledValueWasSilent = true
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
        launchContext = context
#if DEBUG
        debugAudioScaledValueValues = [:]
        debugAudioScaledValueFrameIndex = 0
        debugAudioScaledValueGeneration = 0
        debugAudioScaledValueWasSilent = true
#endif
        mediaPlaybackPlaceholderFadeRuntime = .init(
            program: context.mediaPlaybackPlaceholderFadeProgram
        )
        mediaColorTransitionRuntime = .init(
            program: context.mediaColorTransitionProgram
        )
        sharedLayerAlphaRuntime = .init(
            program: context.sharedLayerAlphaProgram
        )
        audioScaledValueRuntime = .init(
            program: context.audioScaledValueProgram
        )
        SceneAudioSpectrumInbox.shared.setDemand(Self.requiresAudioSpectrum(
            resolvedMaterialExecutionCapabilities:
                context.resolvedMaterialExecutionCapabilities,
            hasParticleAudioConsumer:
                !context.audioScaledValueProgram.bindings.isEmpty
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
        teardownSurfaces(clearContext: true, reason: .surfaceStop)
    }

#if DEBUG
    func debugSnapshot() -> DebugSnapshot {
        DebugSnapshot(
            surfaceCount: surfaces.count,
            windowNumbers: surfaces.values.map { $0.window.windowNumber }.sorted()
        )
    }

    func debugAudioScaledValueSnapshot() -> DebugAudioScaledValueSnapshot {
        let liveCounts = surfaces.values.reduce(into: [Int: Int]()) { result, surface in
            guard let batches = surface.metalView.particlePlayback?.batches else { return }
            for batch in batches {
                result[batch.layerID, default: 0] += batch.instances.count
            }
        }
        let bindings = launchContext?.audioScaledValueProgram.bindings.compactMap {
            binding -> DebugAudioScaledValueBindingSnapshot? in
            let layerID: Int
            let target: String
            let liveParticleCount: Int?
            switch binding.definition.target {
            case let .particle(id, .rate):
                layerID = id
                target = "particle.rate"
                liveParticleCount = liveCounts[id, default: 0]
            case let .layer(id, .scale):
                layerID = id
                target = "layer.scale"
                liveParticleCount = nil
            default:
                return nil
            }
            guard let value = debugAudioScaledValueValues[
                binding.definition.target
            ] else { return nil }
            let components: [Double]
            switch value {
            case let .scalar(scalar):
                components = [scalar]
            case let .vector3(x, y, z):
                components = [x, y, z]
            default:
                return nil
            }
            return DebugAudioScaledValueBindingSnapshot(
                layerID: layerID,
                target: target,
                effectiveValue: components,
                liveParticleCount: liveParticleCount
            )
        }.sorted {
            if $0.layerID != $1.layerID { return $0.layerID < $1.layerID }
            return $0.target < $1.target
        } ?? []
        return DebugAudioScaledValueSnapshot(
            frameIndex: debugAudioScaledValueFrameIndex,
            audioGeneration: debugAudioScaledValueGeneration,
            audioWasSilent: debugAudioScaledValueWasSilent,
            bindings: bindings
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

        let initialAudioScaledValueValues =
            SceneAudioScaledValueRuntime.initialValues(
                program: launchContext.audioScaledValueProgram
            )
        let initialParticleDynamicValues = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 0,
            generation: 0,
            definitions: launchContext.audioScaledValueProgram.definitions,
            userValues: [:],
            timelineValues: [:],
            sceneScriptValues: initialAudioScaledValueValues
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
                Self.appendTimeOfDayEffectScriptReport(
                    to: launchContext.logURL,
                    program: launchContext.timeOfDayEffectScriptProgram
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
                    launchContext.launchOriginTransitionProgram,
                hoverOriginTransitionProgram:
                    launchContext.hoverOriginTransitionProgram
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
