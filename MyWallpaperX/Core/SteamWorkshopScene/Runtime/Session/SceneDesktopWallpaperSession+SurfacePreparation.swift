import AppKit
import QuartzCore

extension SceneDesktopWallpaperSession {
    struct PreparedSurface {
        let displayID: CGDirectDisplayID
        let playback: SceneParticlePlaybackState
        let materialRuntime: SceneResolvedMaterialRuntimeBridge
    }

    final class PendingSurfacePreparation {
        let displayIDs: Set<CGDirectDisplayID>
        let cancellation = SceneWallpaperLaunchCancellation()
#if DEBUG
        let identity = UUID()
#endif
        init(displayIDs: Set<CGDirectDisplayID>) { self.displayIDs = displayIDs }
#if DEBUG
        func log(_ state: String, installed: Int = 0) {
            NSLog("MWX DEBUG SCENE: phase=surface-preparation job=%@ state=%@ displays=%@ mainThread=%@ installed=%d",
                identity.uuidString, state, displayIDs.sorted().map(String.init).joined(separator: ","),
                Thread.isMainThread ? "true" : "false", installed)
        }
#endif
    }

    @discardableResult
    func reconcileSurfaceScreens(
        _ surfaceScreens: [(NSScreen, CGDirectDisplayID)],
        context: SceneDesktopWallpaperLaunchContext,
        publishMembership: Bool = true
    ) -> Bool {
        guard !surfaceScreens.isEmpty else {
            stop()
            return false
        }
        let targetIDs = Set(surfaceScreens.map(\.1))
        if let pending = pendingSurfacePreparation, pending.displayIDs.isDisjoint(with: targetIDs) {
            pending.cancellation.cancel()
        }
        let removedIDs = Set(surfaces.keys).subtracting(targetIDs)
        if !removedIDs.isEmpty {
            context.sceneScriptCursorProgram.retireSurfaceInputs(removedIDs)
            for displayID in removedIDs {
                let surface = surfaces.removeValue(forKey: displayID)!
                teardownSurface(surface, reason: .surfaceStop)
#if DEBUG
                debugSurfaceReferenceFrames.removeValue(forKey: displayID)
#endif
            }
        }
        for (screen, displayID) in surfaceScreens {
            guard let surface = surfaces[displayID] else { continue }
            if surface.window.frame != screen.frame {
                surface.window.setFrame(screen.frame, display: true, animate: false)
            }
            surface.metalView.updateDrawableSize()
            surface.metalView.refreshDisplayOutputForScreenChange()
        }
        prepareAddedSurfaces(surfaceScreens.filter { surfaces[$0.1] == nil }, context: context)
        if publishMembership, !removedIDs.isEmpty { updatePreparedSurfaceMembership(context) }
        reassertSurfaceVisibility()
        return !removedIDs.isEmpty
    }

    private func prepareAddedSurfaces(
        _ screens: [(NSScreen, CGDirectDisplayID)], context: SceneDesktopWallpaperLaunchContext
    ) {
        guard pendingSurfacePreparation == nil, !screens.isEmpty,
              let values = evaluationTransaction.committedSnapshot else { return }
        let topology = context.sceneScriptDynamicLayerRuntime.snapshot()
        let audio = presentation.listensToAudio ? SceneAudioSpectrumInbox.shared.prepareFrame().snapshot : .silent
        let input = context.makeSurfacePreparationInput(dynamicValues: values, topology: topology,
            audioInput: .init(left: audio.left, right: audio.right, generation: audio.generation),
            sceneTime: sceneClock.currentSceneTime(hostTime: CACurrentMediaTime()))
        let work = PendingSurfacePreparation(displayIDs: Set(screens.map(\.1)))
        pendingSurfacePreparation = work
        retiringSurfaceDrain.enter()
#if DEBUG
        work.log("queued")
#endif
        let displayIDs = screens.map(\.1)
        surfacePreparationQueue.async { [self] in
#if DEBUG
            work.log("started")
#endif
            let result = Result { try input.prepare(displayIDs: displayIDs, cancellation: work.cancellation) }
#if DEBUG
            work.log("worker-returned")
#endif
            let deliver: @MainActor @Sendable () -> Void = {
                self.finishSurfacePreparation(work, input: input, result: result)
            }
#if DEBUG
            RunLoop.main.perform(inModes: [.common, .modalPanel]) {
                MainActor.assumeIsolated { deliver() }
            }
#else
            DispatchQueue.main.async { deliver() }
#endif
        }
    }

    private func finishSurfacePreparation(
        _ work: PendingSurfacePreparation, input: SceneSurfacePreparationInput,
        result: Result<[PreparedSurface], Error>
    ) {
        let screens = launchContext.map { _ in Self.surfaceScreens(topology: screenTopology) } ?? []
        let removed = launchContext.map {
            reconcileSurfaceScreens(screens, context: $0, publishMembership: false)
        } ?? false
        var created = 0
        switch result {
        case let .success(prepared):
            if !work.cancellation.isCancelled, let context = launchContext,
               let values = evaluationTransaction.committedSnapshot {
                created = installPreparedSurfaces(prepared,
                    screens: screens.filter { surfaces[$0.1] == nil },
                    context: context, dynamicValues: values)
            } else {
                for surface in prepared { _ = surface.playback.teardown(reason: "preparationCancelled") }
            }
        case let .failure(error):
#if DEBUG
            NSLog("MWX Scene: phase=surface-preparation-failed error=%@", String(describing: error))
#endif
            break
        }
        if let context = launchContext, removed || created > 0 { updatePreparedSurfaceMembership(context) }
#if DEBUG
        work.log("adopted-or-discarded", installed: created)
#endif
        // The same loader may be reused only after its worker products have
        // been consumed or discarded on main, including installation uploads.
        input.baseImages.textureLoader.evictDecodedCaches()
        pendingSurfacePreparation = nil
        retiringSurfaceDrain.leave()
#if DEBUG
        work.log("resources-finished", installed: created)
#endif
        guard let context = launchContext else { return }
        let next = screens.filter {
            surfaces[$0.1] == nil && (work.cancellation.isCancelled || !work.displayIDs.contains($0.1))
        }
        prepareAddedSurfaces(next, context: context)
        if surfaces.isEmpty, pendingSurfacePreparation == nil {
            stop()
        } else if created > 0, sceneClock.isPaused || frameTimer == nil {
            startFrameDriver()
        }
    }

    func installInitialSurfaces(_ preparedSurfaces: [PreparedSurface]) -> Bool {
        guard let launchContext, let videoTextureSourceRegistry else { return false }
        let domain = launchContext.propertyVectorScriptProgram.domain
        let committedTopology = launchContext.sceneScriptDynamicLayerRuntime.snapshot()
        do {
            try videoTextureSourceRegistry.prepareDynamicVideoSources(
                resources: launchContext.preparedDeviceResources.baseImages.dynamicImageResources,
                modelPaths: domain?.preparedVideoModelPaths ?? [],
                device: launchContext.preparedDeviceResources.device)
        } catch { return false }
        videoTextureSourceRegistry.bindPreparedVideoConsumers(Dictionary(uniqueKeysWithValues:
            committedTopology.dynamicLayers.compactMap { layer in
                layer.imagePath.map { (layer.id, $0) }
            }))
        let surfaceScreens = Self.surfaceScreens(topology: screenTopology)
        let count = installPreparedSurfaces(preparedSurfaces, screens: surfaceScreens,
            context: launchContext, dynamicValues: nil)
        launchContext.preparedDeviceResources.baseImages.textureLoader.evictDecodedCaches()
        guard count > 0, count == surfaceScreens.count else {
            teardownSurfaces(clearContext: false, reason: .surfaceStop)
            return false
        }
        updatePreparedSurfaceMembership(launchContext)
        videoTextureSourceRegistry.retire(layerIDs: committedTopology.destroyedAuthoredLayerIDs)
        return prepareInitialVideos()
    }

    private func materialVideoVisibilityTargets(
        for sources: [SceneAssetTextureIdentity: SceneVideoTextureSource],
        context: SceneDesktopWallpaperLaunchContext
    ) -> [SceneAssetTextureIdentity: SceneDynamicTarget] {
        guard !sources.isEmpty else { return [:] }
        let bindings = context.baseMaterialProviderBindings
        var independent = bindings.assetDemands
            .union(context.preparedDeviceResources.staticModels.albedoAssetDemands)
        for profile in Array(bindings.lightingProfileByLayerID.values)
            + Array(bindings.dynamicLightingProfilesByModelPath.values) {
            if let normal = profile.normalAsset { independent.insert(normal) }
            if let map = profile.mapAsset { independent.insert(map) }
        }
        var result: [SceneAssetTextureIdentity: SceneDynamicTarget] = [:]
        let groups = Dictionary(grouping: sources, by: { ObjectIdentifier($0.value) })
        for aliases in groups.values where aliases.count == 1 {
            let identity = aliases[0].key
            guard !independent.contains(identity),
                  case let .effect(effect)? = context.resolvedMaterialCatalog.assetDemandOwners[identity]
            else { continue }
            result[identity] = context.resolvedMaterialExecutionCapabilities
                .materialVideoVisibilityTarget(for: effect)
        }
        return result
    }

    private func installPreparedSurfaces(
        _ preparedSurfaces: [PreparedSurface],
        screens surfaceScreens: [(NSScreen, CGDirectDisplayID)],
        context launchContext: SceneDesktopWallpaperLaunchContext,
        dynamicValues: SceneDynamicSnapshot?
    ) -> Int {
        let videoTextureSourceRegistry = self.videoTextureSourceRegistry!
        var created = 0
        var wroteLog = dynamicValues != nil
        var assetVideoSources: [SceneAssetTextureIdentity: SceneVideoTextureSource] = [:]
        let committedTopology = launchContext.sceneScriptDynamicLayerRuntime.snapshot()
        let userVideoSources = videoTextureSourceRegistry.userPropertySources(
            declarations: userPropertyTextureLoad.videoDeclarations,
            device: launchContext.preparedDeviceResources.device
        )
        for (identity, declaration) in launchContext.materialAssetCatalog.videoDeclarations {
            do { if let source = try videoTextureSourceRegistry.source(
                declaration: declaration, owner: .asset,
                cacheDirectory: launchContext.privateMediaCacheDirectory,
                device: launchContext.preparedDeviceResources.device,
                loader: launchContext.preparedDeviceResources.baseImages.textureLoader
            ) {
                assetVideoSources[identity] = source
            } } catch { continue }
        }
        let materialVideoVisibility = materialVideoVisibilityTargets(
            for: assetVideoSources, context: launchContext
        )
        let screensByID = Dictionary(uniqueKeysWithValues: surfaceScreens.map { ($0.1, $0.0) })
        for prepared in preparedSurfaces {
            let screenID = prepared.displayID
            guard let screen = screensByID[screenID] else {
                _ = prepared.playback.teardown(reason: "displayNoLongerDesired")
                continue
            }
            let frame = Self.initialSurfaceFrame(for: screen)
#if DEBUG
            if frame != screen.frame { debugSurfaceReferenceFrames[screenID] = screen.frame }
#endif
            let framing = effectiveFraming
            let materialRuntime = prepared.materialRuntime
            materialRuntime.installAssetVideoSources(assetVideoSources,
                declaredIdentities: Set(launchContext.materialAssetCatalog.videoDeclarations.keys),
                visibilityTargets: materialVideoVisibility)
            guard let metalView = SceneMetalView(
                renderDescriptor: launchContext.runtimeInput.renderDescriptor,
                utilitySourceRoutes: launchContext.frameSchema.utilitySourceRoutes,
                verifiedXRayStageKeys: launchContext.effectAdmissionCatalog.verifiedXRayStageKeys,
                baseMaterialProviderBindings:
                    launchContext.baseMaterialProviderBindings,
                stockNoiseTextures: launchContext.stockNoiseTextures,
                staticModelResources:
                    launchContext.preparedDeviceResources.staticModels,
                allowsProjectedSpotVolume: allowsProjectedSpotVolume,
                allowsSceneReflection: allowsSceneReflection,
                hasDynamicBloom: launchContext.runtimeInput.propertyBindingProgram
                    .instructions.contains { $0.target == .scene(.bloomEnabled) },
                instantiatedSceneScriptTargets: Set(
                    (launchContext.sceneScriptScalarProgram.definitions
                        + launchContext.propertyVectorScriptProgram.definitions).map(\.target)
                ),
                scriptSourceEvidence:
                    launchContext.sceneScriptSourceEvidence,
                pipelineRepository:
                    launchContext.preparedDeviceResources.pipelineRepository,
                imageLayerPipeline:
                    launchContext.preparedDeviceResources.imageLayerPipeline,
                resolvedMaterialRuntime: materialRuntime,
                userPropertyTextureLoad: userPropertyTextureLoad,
                userPropertyVideoSources: userVideoSources,
                hdrDisplayRequested: scenePostProcessing.requestsDisplayHDR,
                presentationStreamID: UInt64(screenID),
                firstFramePresentationRegistration: {
                    [weak firstFramePresentationRegistration] drawable in
                    firstFramePresentationRegistration?.arm(on: drawable) ?? false
                },
                frame: frame,
                cameraAdjustment: framing,
                flippedHorizontally: presentation.flippedHorizontally,
                allowsMouseParallax: presentation.allowsMouseParallax
            ) else {
                _ = prepared.playback.teardown(reason: "surfaceUnavailable")
                continue
            }
            let surfaceLogURL = wroteLog ? nil : launchContext.logURL
#if DEBUG
            let dispositionCatalog = SceneEffectRuntimeDispositionCatalog(
                descriptor: launchContext.runtimeInput.renderDescriptor,
                admissionCatalog: launchContext.effectAdmissionCatalog,
                resolvedMaterialSubjects: materialRuntime.runtimeDispositionSubjects
            )
            let effectReportLines = surfaceLogURL == nil ? []
                : launchContext.effectAdmissionCatalog.reportLines + dispositionCatalog.reportLines
            metalView.renderer.installResolvedMaterialExecutionEvidence(
                reportLines: effectReportLines,
                resolvedMaterialLayerIDs: surfaceLogURL == nil ? []
                    : launchContext.effectAdmissionCatalog.resolvedMaterialExecutionLayerIDs,
                subjects: dispositionCatalog.resolvedMaterialExecutionEvidenceSubjects
            )
#endif
            let window = HostWindow(
                contentRect: frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            let surface = Surface(window: window, metalView: metalView,
                scriptGeneration: launchContext.propertyVectorScriptProgram.generation)
            var textLoadMessages: [String] = []
            if dynamicTextTextures == nil {
#if DEBUG
                let recordsTextDiagnostics = launchContext.logURL != nil
                let textEffectSummary: (SceneRenderDescriptor.Layer) -> String? = {
                    [telemetry = metalView.renderer.effectExecutionTelemetry] in
                    telemetry.effectRuntimeSummary(for: $0.id)
                }
#else
                let recordsTextDiagnostics = false
                let textEffectSummary: (SceneRenderDescriptor.Layer) -> String? = { _ in nil }
#endif
                let textLoad = SceneTextTextureLoader.load(
                    descriptor: launchContext.runtimeInput.renderDescriptor,
                    resourceView: launchContext.resourceView,
                    device: launchContext.preparedDeviceResources.device,
                    recordsDiagnostics: recordsTextDiagnostics,
                    effectSummary: textEffectSummary
                )
                dynamicTextTextures = SceneDynamicTextTextureStore(
                    descriptor: launchContext.runtimeInput.renderDescriptor,
                    resourceView: launchContext.resourceView,
                    device: launchContext.preparedDeviceResources.device,
                    initialRasters: textLoad.rasters,
                    dynamicTextFieldsByLayerID: launchContext.frameSchema.dynamicTextFieldsByLayerID,
                    onPublication: { [weak self] store in
                        DispatchQueue.main.async { [weak self] in self?.textTexturePublicationDidChange(store) }
                    }
                )
                textLoadMessages = textLoad.messages
            }
#if DEBUG
            if SceneDesktopWallpaperHost.usesDebugEvidenceWindow, screenID == surfaceScreens.last?.1,
               let raw = ProcessInfo.processInfo.environment["MWX_SCENE_DEBUG_DRAWABLE_UNAVAILABLE_FRAMES"],
               let count = UInt64(raw), (1...120).contains(count) {
                metalView.debugDrawableUnavailableFrameCount = count
            }
#endif
            metalView.loadImageLayers(
                privateMediaCacheDirectory: launchContext.privateMediaCacheDirectory,
                resourceView: launchContext.resourceView,
                videoSourceRegistry: videoTextureSourceRegistry,
                preparedBaseImages: launchContext.preparedDeviceResources.baseImages,
                spriteTextureLoader: launchContext.preparedDeviceResources.spriteTextureLoader,
                textureAnimationPlaybackRuntime: launchContext.textureAnimationPlaybackRuntime,
                destroyedAuthoredLayerIDs: committedTopology.destroyedAuthoredLayerIDs,
                preparePuppet: { layer, pose, atlas in
                    surface.instantiatePuppetGeometry(for: layer, pose: pose,
                        atlasTexture: atlas, preparedResources: launchContext.preparedDeviceResources,
                        playbackRuntime: launchContext.puppetAnimationPlaybackRuntime)
                },
                textLoadMessages: textLoadMessages,
                logURL: surfaceLogURL
            )
            surface.installDirectModelAnimations(
                playbackRuntime: launchContext.puppetAnimationPlaybackRuntime,
                destroyedAuthoredLayerIDs: committedTopology.destroyedAuthoredLayerIDs)
            let candidateParticles = prepared.playback
            if dynamicValues != nil {
                candidateParticles.retire(layerIDs: committedTopology.destroyedAuthoredLayerIDs)
                candidateParticles.adoptPlayback(committedTopology.particlePlayback)
            }
            let particleVariants = candidateParticles.pipelineVariants
            if particleVariants.required.isEmpty {
                surface.particlePlayback = candidateParticles
            } else if let pipeline = SceneParticleMetalPipeline(
                device: metalView.metalDevice,
                pixelFormat: metalView.renderer.renderDescriptor.colorTargetFormat.metalPixelFormat,
                requiredVariants: particleVariants.required, sceneDepthVariants: particleVariants.sceneDepth,
                rasterSampleCount: launchContext.rasterSamples.device
            ) {
                metalView.particlePipeline = pipeline
                surface.particlePlayback = candidateParticles
            } else {
                _ = candidateParticles.teardown(reason: "pipelineUnavailable")
                surface.particlePlayback = nil
            }
#if DEBUG
            var particleReport = SceneStartupReportBuffer(enabled: surfaceLogURL != nil)
            if let particlePlayback = surface.particlePlayback {
                particleReport.append(contentsOf: particlePlayback.loadReportLines(
                    descriptor: metalView.renderer.renderDescriptor))
            } else {
                particleReport.append("particle runtime: pipeline unavailable")
            }
            particleReport.write(to: surfaceLogURL, appending: true)
            if !wroteLog { launchContext.appendResolvedMaterialStartupReport() }
#endif
            wroteLog = true

            window.isReleasedWhenClosed = false
            window.animationBehavior = .none
            window.ignoresMouseEvents = !SceneDesktopWallpaperHost.usesDebugEvidenceWindow
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.hidesOnDeactivate = false
            window.sharingType = .readOnly
            window.alphaValue = isVisible ? 1 : 0
            window.level = Self.wallpaperWindowLevel
            window.collectionBehavior = Self.windowCollectionBehavior
            window.contentView = metalView
            Self.orderSurfaceWindow(window, makesKey: SceneDesktopWallpaperHost.usesDebugEvidenceWindow)
            if let dynamicValues {
                prepareSurfaceFrame(surface, context: launchContext,
                    dynamicValues: dynamicValues, topology: committedTopology)
            }
            surfaces[screenID] = surface
            metalView.onRenderInvalidated = { [weak self, weak surface] in
                DispatchQueue.main.async { [weak self, weak surface] in
                    guard let self, let surface, self.surfaces[screenID] === surface else { return }
                    if self.initialPresentationCohort.isHeld {
                        let delivered = self.initialPresentationCohort.hasDelivered
                        self.initialPresentationCohort.invalidate()
                        if delivered {
                            // Parent may already hold the promotion token.
                            self.onFirstFrameCompletion?(screenID, false)
                            return
                        }
                    }
                    self.promoteAutomaticTextures(for: surface)
                    surface.didSubmitSimulationFrame = false
                    if self.sceneClock.isPaused || self.awaitsInitialPresentation { self.startFrameDriver() }
                }
            }
            metalView.onDisplayOutputChanged = { [weak self, weak surface] in
                DispatchQueue.main.async { [weak self, weak surface] in
                    guard let self, let surface, self.surfaces[screenID] === surface,
                          self.invalidatePausedDisplayOutput(for: surface) else { return }
                    self.startFrameDriver()
                }
            }
            promoteAutomaticTextures(for: surface)
            created += 1
        }

        return created
    }

    static func initialSurfaceFrame(for screen: NSScreen) -> CGRect {
        let frame = screen.frame
#if DEBUG
        if SceneDesktopWallpaperHost.usesDebugEvidenceWindow,
           let raw = ProcessInfo.processInfo.environment["MWX_SCENE_DEBUG_INITIAL_WINDOW_SCALE"],
           let scale = Double(raw), scale > 0, scale < 1 {
            let width = frame.width * scale, height = frame.height * scale
            return CGRect(x: frame.midX - width / 2, y: frame.midY - height / 2, width: width, height: height)
        }
#endif
        return frame
    }

    func promoteAutomaticTextures(for surface: Surface? = nil) {
        guard let images = launchContext?.preparedDeviceResources.baseImages else { return }
        let density = surface.map { surface in
            let view = surface.metalView
            return view.cameraAdjustment.automaticMipDensity(
                camera: view.renderer.renderDescriptor.camera, drawable: view.metalLayer.drawableSize)
        }
        images.promoteAutomaticMips(to: density) { [weak self, weak images] updates in
            guard let self, let images, self.launchContext?.preparedDeviceResources.baseImages === images else { return }
            let redrawFrozenColor = self.sceneClock.isPaused
            for surface in self.surfaces.values {
                let view = surface.metalView
                guard view.replacePreparedBaseImages(updates) else { continue }
                if redrawFrozenColor, view.keepsSceneColorHistory {
                    view.invalidateResolvedMaterialRuntime(reason: .allocationReprepare, notifyRender: false)
                }
                surface.didSubmitSimulationFrame = false
            }
            if self.sceneClock.isPaused || self.awaitsInitialPresentation { self.startFrameDriver() }
        }
    }

    private func prepareSurfaceFrame(
        _ surface: Surface, context: SceneDesktopWallpaperLaunchContext,
        dynamicValues: SceneDynamicSnapshot, topology: SceneScriptLayerTopologySnapshot
    ) {
        let hostTime = CACurrentMediaTime()
        let timing = SceneFrameTiming(frameIndex: dynamicValues.frameIndex,
            hostTime: hostTime, sceneTime: sceneClock.currentSceneTime(hostTime: hostTime),
            rawFrameTime: 0, simulationFrameTime: 0, droppedFrameTime: 0, wallDate: Date())
#if DEBUG
        if let debugPointerOverride {
            surface.metalView.applyPointerInput(debugPointerOverride, timestamp: hostTime)
        } else {
            surface.metalView.updateMouseLocationInScreen(NSEvent.mouseLocation)
        }
#else
        surface.metalView.updateMouseLocationInScreen(NSEvent.mouseLocation)
#endif
        surface.synchronizeDynamicPuppets(topology,
            preparedResources: context.preparedDeviceResources,
            playbackRuntime: context.puppetAnimationPlaybackRuntime)
        let animationFrame = context.puppetAnimationPlaybackRuntime.advance(
            frameIndex: timing.frameIndex, sceneTime: timing.sceneTime, dynamicValues: dynamicValues)
        let projection = surface.metalView.renderer.resolveFrameTopology(layerTopology: topology)
        _ = surface.prepareSceneScriptPuppetPoseFrame(timing: timing, puppetAnimationFrame: animationFrame,
            dynamicValues: dynamicValues, descriptor: projection.descriptor,
            layersByID: projection.layersByID, staticWorldFrames: projection.staticWorldFrames,
            dynamicLayerIDs: projection.dynamicLayerIDs)
        let media = SceneMediaThumbnailInbox.shared.latest()
        surface.updateSimulation(timing: timing, dynamicValues: dynamicValues,
            puppetAnimationFrame: animationFrame,
            spriteTimes: context.textureAnimationPlaybackRuntime.playbackTimes(
                layerIDs: surface.metalView.spriteAnimationLayerIDs, sceneTime: timing.sceneTime),
            layerTopology: topology, mediaThumbnail: mediaThumbnailTextures!.snapshot(),
            mediaInputGeneration: media.generation,
            audioSpectrum: presentation.listensToAudio ? SceneAudioSpectrumInbox.shared.prepareFrame().snapshot : .silent)
    }

    func updatePreparedSurfaceMembership(_ launchContext: SceneDesktopWallpaperLaunchContext) {
        preparedSurfaceIDs = Set(surfaces.keys)
        updateAudioSpectrumDemand(launchContext, hasParticleAudioConsumer: surfaces.values.contains { $0.particlePlayback?.hasAudioConsumer == true })
        let storageScreenIdentity = surfaces.count == 1
            ? surfaces.keys.first.flatMap(Self.sceneScriptStorageScreenIdentity)
            : nil
        do {
            try launchContext.propertyVectorScriptProgram.domain?
                .setStorageScreenIdentity(storageScreenIdentity)
        } catch {
#if DEBUG
            NSLog(
                "MWX SceneScript VM: localStorage screen identity unavailable failure=%@ fallback=global-only",
                String(describing: error)
            )
#endif
        }
    }

}
