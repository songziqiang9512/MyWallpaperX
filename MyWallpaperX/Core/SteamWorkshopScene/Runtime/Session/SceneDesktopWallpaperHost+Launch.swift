import Foundation
import QuartzCore
import Metal

extension SceneDesktopWallpaperHost {
    struct PreparedLaunch {
        let model: SceneRuntimeModel
        var context: SceneDesktopWallpaperLaunchContext
        let userPropertyTextureLoad: SceneUserPropertyTextureLoadResult
        let preparedSurfaces: [SceneDesktopWallpaperSession.PreparedSurface]
    }

    func requestLaunch(
        rootURL: URL,
        source: ScenePlaybackSource? = nil,
        propertyOverrides: [String: SceneUserPropertyValue] = [:],
        userPropertyTextureURLs: [String: URL] = [:],
        userShortcuts: ScenePlaybackShortcutConfiguration = .empty,
        requiredUserTextureKeys: Set<String> = [],
        logURL: URL? = nil,
        recordID: String? = nil,
        requestID: UUID = UUID(),
        completion: @escaping @MainActor (Result<SceneRuntimeModel, Error>) -> Void
    ) {
        rollbackUnconfirmedPromotion()
        cancelPendingLaunch()
        activeSession?.cancelPendingUserTextureUpdates()
        activeSession?.pendingSurfacePreparation?.cancellation.cancel()
        nextLaunchRequestGeneration &+= 1
        nextSceneScriptGeneration &+= 1
        let requestGeneration = nextLaunchRequestGeneration
        pendingLaunchCompletion = completion
        let complete: @MainActor (Result<SceneRuntimeModel, Error>) -> Void = { [weak self] result in
            guard let self, self.nextLaunchRequestGeneration == requestGeneration else { return }
            self.pendingLaunchCompletion = nil
            completion(result)
        }
        let scriptGeneration = nextSceneScriptGeneration
        let cancellation = SceneWallpaperLaunchCancellation()
        launchCancellation = cancellation
        publishLaunchState(.init(
            requestID: requestID,
            recordID: recordID,
            phase: .accepted,
            message: String(localized: "Scene wallpaper request accepted")
        ))

#if DEBUG
        if Self.usesDebugEvidenceWindow {
            screenTopology = SceneDesktopWallpaperSession.debugInitialSurfaceTopology(screenTopology)
        }
#endif
        let surfaceDisplayIDs = SceneDesktopWallpaperSession.surfaceScreens(topology: screenTopology).map(\.1)
        launchPreparationQueue.async { [weak self] in
            guard let self else { return }
            do {
                var prepared = try Self.prepareLaunch(
                    rootURL: rootURL,
                    source: source,
                    propertyOverrides: propertyOverrides,
                    userPropertyTextureURLs: userPropertyTextureURLs,
                    requiredUserTextureKeys: requiredUserTextureKeys,
                    logURL: logURL,
                    recordID: recordID,
                    sceneScriptGeneration: scriptGeneration,
                    textureDecodeCacheBudget: self.textureDecodeCacheBudget,
                    surfaceDisplayIDs: surfaceDisplayIDs,
                    cancellation: cancellation
                ) { [weak self] phase, message in
                    DispatchQueue.main.async {
                        guard let self,
                              self.nextLaunchRequestGeneration == requestGeneration else {
                            return
                        }
                        self.publishLaunchState(.init(
                            requestID: requestID,
                            recordID: recordID,
                            phase: phase,
                            message: message
                        ))
                    }
                }
                prepared.context.userShortcuts = userShortcuts
                prepared.context.userShortcutKeys = Set(prepared.model.project.userProperties.definitions
                    .filter { $0.kind == .userShortcut }.map(\.key))
                let model = prepared.model
                let context = prepared.context
                let userPropertyTextureLoad = prepared.userPropertyTextureLoad
                let preparedSurfaces = prepared.preparedSurfaces
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.nextLaunchRequestGeneration == requestGeneration else {
                        return
                    }
                    do {
                        try cancellation.check()
                        self.publishLaunchState(.init(
                            requestID: requestID,
                            recordID: recordID,
                            phase: .preparingSurfaces,
                            message: String(localized: "Preparing displays and Scene surfaces")
                        ))
                        try self.beginCandidate(
                            context,
                            preparedSurfaces: preparedSurfaces,
                            userPropertyTextureLoad: userPropertyTextureLoad,
                            firstPresentation: .init(requestID: requestID, recordID: recordID)
                        ) { [weak self] result in
                            guard let self, self.nextLaunchRequestGeneration == requestGeneration else { return }
                            switch result {
                            case .success:
                                self.launchCancellation = nil
                                let reachability: ScenePreparedCallbackPropertyReachability?
                                if let projectWitness = model.project.sourceWitness,
                                   let sceneWitness = model.sceneDocument.sourceWitness,
                                   let session = self.activeSession {
                                    reachability = .init(source: .init(
                                        rootPath: model.project.rootURL.resolvingSymlinksInPath().standardizedFileURL.path,
                                        projectWitness: projectWitness, sceneWitness: sceneWitness),
                                        scriptGeneration: scriptGeneration,
                                        propertyKeys: session.preparedCallbackPropertyKeys(
                                            definitions: model.project.userProperties.definitions))
                                } else { reachability = nil }
                                self.publishLaunchState(.init(requestID: requestID,
                                    recordID: recordID, phase: .launched, message: String(localized: "First Scene frame rendered and applied"),
                                    callbackPropertyReachability: reachability))
                                complete(.success(model))
                            case let .failure(error):
                                self.finishLaunchFailure(error, requestID: requestID,
                                    recordID: recordID, completion: complete)
                            }
                        }
                    } catch {
                        self.finishLaunchFailure(
                            error,
                            requestID: requestID,
                            recordID: recordID,
                            completion: complete
                        )
                    }
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.nextLaunchRequestGeneration == requestGeneration else {
                        return
                    }
                    self.finishLaunchFailure(
                        error,
                        requestID: requestID,
                        recordID: recordID,
                        completion: complete
                    )
                }
            }
        }
    }

    func cancelPendingLaunch(recordID: String? = nil) {
        guard let state = launchState,
              state.isInProgress,
              recordID == nil || state.recordID == recordID else {
            return
        }
        launchCancellation?.cancel()
        launchCancellation = nil
        nextLaunchRequestGeneration &+= 1
        discardCandidate()
        let completion = pendingLaunchCompletion
        pendingLaunchCompletion = nil
        DispatchQueue.main.async { completion?(.failure(SceneDesktopWallpaperHostLaunchError.cancelled)) }
        publishLaunchState(.init(
            requestID: state.requestID,
            recordID: state.recordID,
            phase: .cancelled,
            message: String(localized: "Scene wallpaper preparation canceled")
        ))
    }

    static func isLaunchCancellation(_ error: Error) -> Bool {
        guard let launchError = error as? SceneDesktopWallpaperHostLaunchError else {
            return false
        }
        if case .cancelled = launchError {
            return true
        }
        return false
    }
#if DEBUG
    /// The evidence runner awaits the same request/first-frame transaction as
    /// the daemon. There is no synchronous activation bypass.
    func launch(
        rootURL: URL,
        source: ScenePlaybackSource? = nil,
        propertyOverrides: [String: SceneUserPropertyValue] = [:],
        userPropertyTextureURLs: [String: URL] = [:],
        requiredUserTextureKeys: Set<String> = [],
        logURL: URL? = nil,
        recordID: String? = nil
    ) async throws -> SceneRuntimeModel {
        try await withCheckedThrowingContinuation { continuation in
            requestLaunch(rootURL: rootURL, source: source, propertyOverrides: propertyOverrides,
                userPropertyTextureURLs: userPropertyTextureURLs,
                requiredUserTextureKeys: requiredUserTextureKeys, logURL: logURL,
                recordID: recordID) { continuation.resume(with: $0) }
        }
    }
#endif
    private static func prepareLaunch(
        rootURL: URL,
        source: ScenePlaybackSource?,
        propertyOverrides: [String: SceneUserPropertyValue],
        userPropertyTextureURLs: [String: URL],
        requiredUserTextureKeys: Set<String>,
        logURL: URL?,
        recordID: String?,
        sceneScriptGeneration: UInt64,
        textureDecodeCacheBudget: SceneTextureDecodeCacheBudget,
        surfaceDisplayIDs: [CGDirectDisplayID],
        cancellation: SceneWallpaperLaunchCancellation?,
        progress: ((SceneWallpaperLaunchState.Phase, String) -> Void)?
    ) throws -> PreparedLaunch {
        try cancellation?.check()
#if DEBUG
        let prepareEntry = CACurrentMediaTime()
        func logPrepareStage(_ name: String) {
        NSLog(
                "MWX LAUNCH-STAGE: stage=%@ elapsedMs=%.0f",
                name,
                (CACurrentMediaTime() - prepareEntry) * 1000
            )
        }
#endif
        progress?(.preparingModel, String(localized: "Reading resources and parsing the scene"))
        var preparedStaticModels: [String: SceneMdlStaticModel.PreparedSource] = [:]
        var preparedParticleDefinitions: [String: SceneParticleAssetGraphLoader.PreparedDefinition] = [:]
        let model = try SceneRuntimeModelBuilder().build(
            rootURL: rootURL,
            source: source,
            propertyOverrides: propertyOverrides,
            checkCancellation: { try cancellation?.check() },
            preparedStaticModel: { preparedStaticModels[$0] = $1 },
            preparedParticleDefinition: { preparedParticleDefinitions[$0] = $1 }
        )
#if DEBUG
        let modelBuildMs = (CACurrentMediaTime() - prepareEntry) * 1_000
#endif
        try cancellation?.check()
        progress?(.preparingPrograms, String(localized: "Preparing materials, scripts and render plan"))
        let privateMediaCacheDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/MyWallpaperX/SteamWorkshopScene", isDirectory: true)
        var runtimeInput = model.runtimeInput
        var authoredRenderDescriptor = model.authoredRenderDescriptor
        guard let device = MTLCreateSystemDefaultDevice()
        else { throw SceneDesktopWallpaperHostLaunchError.noSurface }
        let textureUploadCommandQueue = SceneTextureUploadCommandQueue()
        let propertyLayerVisibilityTargets = runtimeInput.propertyBindingProgram.liveLayerVisibilityTargets
        let deferredBaseImageLayerIDs = Self.deferredEffectlessBaseImageLayerIDs(
            in: runtimeInput.renderDescriptor,
            bindingProgram: runtimeInput.propertyBindingProgram,
            effectivePropertyValues: runtimeInput.effectivePropertyValues
        )
        let deviceResourcesPreparation = ScenePreparedDeviceResourcesTask(
            descriptor: runtimeInput.renderDescriptor,
            resourceView: model.resourceView,
            device: device,
            sceneGeneration: sceneScriptGeneration,
            cacheDirectory: privateMediaCacheDirectory,
            effectivePropertyValues: runtimeInput.effectivePropertyValues,
            deferredBaseImageLayerIDs: deferredBaseImageLayerIDs,
            imageGeometryModels: model.assetCatalog.models,
            preparedStaticModels: preparedStaticModels,
            textureUploadCommandQueue: textureUploadCommandQueue,
            textureDecodeCacheBudget: textureDecodeCacheBudget,
            cancellationCheck: { try cancellation?.check() }
        )
        preparedStaticModels.removeAll()
        deviceResourcesPreparation.start()
        defer {
            deviceResourcesPreparation.cancel()
            _ = try? deviceResourcesPreparation.value()
        }
        let preparedImageGeometry = try deviceResourcesPreparation.preparedImageGeometry()
        runtimeInput = runtimeInput.applyingPreparedImageGeometry(preparedImageGeometry)
        authoredRenderDescriptor = authoredRenderDescriptor
            .applyingPreparedImageGeometry(preparedImageGeometry)
#if DEBUG
        logPrepareStage("prepare-setup")
#endif
        let timelineProgram = SceneTimelineTargetCompiler.compile(
            descriptor: runtimeInput.renderDescriptor
        )
#if DEBUG
        SceneTimelineFrameEvidence.recordProgram(timelineProgram,
            evidenceWindow: SceneDesktopWallpaperHost.usesDebugEvidenceWindow)
#endif
        let propertyVectorNonPassTargets = model.propertyVectorProjection.nonPassTargets
        let propertyVectorPassCandidateTargets = model.propertyVectorProjection.passTargets
        let propertyVectorScriptTargets = propertyVectorNonPassTargets
            .union(propertyVectorPassCandidateTargets)
        let timelineDefinitions = Set(timelineProgram.bindings.map(\.definition))
        let timelineTargets = Set(timelineDefinitions.map(\.target))
        let propertyBindingDefinitions = runtimeInput.propertyBindingProgram.definitions
        let userPropertyProducers = Set(
            runtimeInput.propertyBindingProgram.instructions.map {
                SceneDynamicUserPropertyProducer(
                    propertyKey: $0.propertyKey,
                    target: $0.target,
                    valueType: $0.valueType
                )
            }
        )
        let propertyBindingTargets = Set(userPropertyProducers.map(\.target))
        typealias VisibilityOwner = SceneResolvedMaterialExecutionCapabilityAdmission.DynamicEffectVisibilityOwner
        // Script/Timeline owners only register candidates; effects keep authored value.
        var frameDrivenEffectVisibilityOwners = Set<VisibilityOwner>()
        let initiallyInactiveMediaOwners =
            SceneInitialMediaEffectVisibilityProjection.initiallyInactiveOwners(
                scriptBindings: model.sceneDocument.scriptBindings,
                sourceEvidence: model.sceneDocument.scriptSourceEvidence
            )
        for binding in timelineProgram.bindings {
            guard case let .effectVisibility(layerID, effectIndex) =
                    binding.definition.target else { continue }
            frameDrivenEffectVisibilityOwners.insert(.init(
                layerID: layerID,
                effectIndex: effectIndex
            ))
        }
        for binding in model.sceneDocument.scriptBindings {
            guard binding.owner.kind == .effect,
                  binding.targetKey == "visible",
                  let layerID = binding.owner.objectID,
                  let effectIndex = binding.owner.effectIndex,
                  !initiallyInactiveMediaOwners.contains(.init(
                      layerID: layerID,
                      effectIndex: effectIndex
                  )) else { continue }
            frameDrivenEffectVisibilityOwners.insert(.init(
                layerID: layerID,
                effectIndex: effectIndex
            ))
        }
        let executablePropertyFallbackTargets =
            SceneEffectStageAuthoredFallbackOwnerPartition.executableTargets(
                definitions: propertyBindingDefinitions
            )
        let vectorPropertyInputTargets = Set(userPropertyProducers.filter {
            model.propertyVectorProjection.consumesUserProperty(
                key: $0.propertyKey, target: $0.target, valueType: $0.valueType
            )
        }.map(\.target))
        var vectorProducerConflicts: [String] =
            model.propertyVectorProjection.duplicateTargets.isEmpty
                ? [] : ["property-vector/duplicate"]
        if !propertyVectorScriptTargets.intersection(propertyBindingTargets)
            .subtracting(vectorPropertyInputTargets).isEmpty {
            vectorProducerConflicts.append("property-vector/property")
        }
        if !propertyVectorScriptTargets.intersection(timelineTargets)
            .subtracting(model.propertyVectorProjection.animationTargets).isEmpty {
            vectorProducerConflicts.append("property-vector/timeline")
        }
        guard vectorProducerConflicts.isEmpty else {
            throw SceneDesktopWallpaperHostLaunchError
                .conflictingBoundedSceneScriptTargets(
                    " phases=\(vectorProducerConflicts.joined(separator: ","))"
                )
        }
        var soundPlaybackProgram = try SceneSoundPlaybackProgram.compile(
            document: model.sceneDocument,
            resourceView: model.resourceView,
            privateCacheDirectory: privateMediaCacheDirectory,
            checkCancellation: { try cancellation?.check() }
        )
        let sceneScriptScalarDefinitions = SceneScriptScalarProgram.projectedDefinitions(
            descriptor: authoredRenderDescriptor,
            scriptBindings: model.sceneDocument.scriptBindings,
            timelineTargets: timelineTargets,
            excludedTargets: propertyVectorScriptTargets
        )
        let sceneScriptScalarTargets = Set(sceneScriptScalarDefinitions.map(\.target))
        let sceneScriptStringExcludedTargets = propertyVectorScriptTargets
            .union(sceneScriptScalarTargets)
        let sceneScriptStringTargets = SceneScriptStringProgram.projectedTargets(
            descriptor: runtimeInput.renderDescriptor,
            scriptBindings: model.sceneDocument.scriptBindings,
            excludedTargets: sceneScriptStringExcludedTargets
        )
        guard let sceneScriptVectorMediaRoute =
                SceneScriptVectorMediaRouteState.resolve(
                    ProcessInfo.processInfo.environment[
                        SceneScriptVectorMediaRouteState.environmentKey
                    ]
                ) else {
            throw SceneDesktopWallpaperHostLaunchError
                .invalidBoundedSceneScriptProgramAt("vector-media-route")
        }
        let provisionalSceneScriptValueTargets = propertyVectorScriptTargets
            .union(sceneScriptScalarTargets)
            .union(sceneScriptStringTargets)
            .union(runtimeInput.scriptOwnedEffectVisibilityTargets)
        let hasScriptLayerAccess = !model.sceneDocument.scriptBindings.isEmpty
        let dynamicLayerVisibilityOwnerTargets =
            SceneDynamicLayerVisibilityRouteAdmission.targets(
                in: runtimeInput.renderDescriptor,
                candidates: propertyVectorScriptTargets
                    .union(propertyLayerVisibilityTargets),
                hasScriptLayerAccess: hasScriptLayerAccess
            )
        let projectedLayerVisibilityRootLayerIDs =
            SceneDynamicLayerVisibilityRouteAdmission.preparationLayerIDs(
                in: runtimeInput.renderDescriptor,
                candidates: dynamicLayerVisibilityOwnerTargets
            )
        let particleVisibilityRequirements =
            SceneDynamicLayerVisibilityRouteAdmission.particleRequirements(
                in: runtimeInput.renderDescriptor,
                candidates: dynamicLayerVisibilityOwnerTargets
            )
        let preparedParticleVisibilityLayerIDs = Set(
            particleVisibilityRequirements.values.joined()
        )
        let preparedParticleAssets: SceneParticleAssetGraph
        do {
            defer { preparedParticleDefinitions.removeAll() }
            preparedParticleAssets = try SceneParticleRuntime.prepareAssets(
                descriptor: runtimeInput.renderDescriptor, resourceView: model.resourceView,
                preparedParticleVisibilityLayerIDs: preparedParticleVisibilityLayerIDs,
                preparedDefinitions: preparedParticleDefinitions,
                checkCancellation: { try cancellation?.check() }
            )
        }
        let resolvedMaterialVisibleExecutionRootLayerIDs = SceneLayerVisibility
            .visibleLayerIDs(in: runtimeInput.renderDescriptor)
                .union(projectedLayerVisibilityRootLayerIDs)
#if DEBUG
        logPrepareStage("prepare-programs")
#endif
        let resolvedMaterialAdmissionCandidates =
            SceneResolvedMaterialExecutionCapabilityAdmission.compile(
                descriptor: runtimeInput.renderDescriptor,
                authoredPlans: runtimeInput.authoredEffectRenderPlans,
                dynamicEffectVisibilityOwners:
                    frameDrivenEffectVisibilityOwners,
                dynamicLayerVisibilityOwnerTargets:
                    dynamicLayerVisibilityOwnerTargets,
                startupInactiveEffectVisibilityTargets:
                    runtimeInput.startupInactiveEffectVisibilityTargets,
                scriptOwnedStartupInactiveEffectVisibilityTargets:
                    runtimeInput.scriptOwnedEffectVisibilityTargets,
                conditionSchemaEvidence:
                    SceneGraphConditionSchemaEvidenceCompiler.compile(
                        descriptor: runtimeInput.renderDescriptor,
                        authoredPlans: runtimeInput.authoredEffectRenderPlans,
                        shaderContracts: runtimeInput.shaderContracts
                    )
            )
#if DEBUG
        logPrepareStage("prepare-admission")
#endif
        let materialPropertyTargets = Set(runtimeInput.propertyBindingProgram.instructions.map(\.target))
        let provenMaterialBindings = model.propertyVectorProjection.materialBindings
        let loweredMaterialModelPaths = Set(provenMaterialBindings.filter(\.canLowerToCompositor).map(\.modelPath))
        let resolvedMaterialCatalog = try SceneResolvedMaterialRuntimeCatalog(
            descriptor: runtimeInput.renderDescriptor,
            admissionCandidates: resolvedMaterialAdmissionCandidates,
            shaderContracts: runtimeInput.shaderContracts,
            userPropertyProducers: userPropertyProducers,
            provenSceneScriptValueTargets: provisionalSceneScriptValueTargets,
            materialInstancesByLayerID: model.sceneDocument.materialInstancesByLayerID,
            loweredSourceMaterialModelPaths: loweredMaterialModelPaths,
            provenSourceMaterialBindings: provenMaterialBindings,
            cancellationCheck: { try cancellation?.check() }
        )
#if DEBUG
        logPrepareStage("prepare-catalog")
#endif
        try cancellation?.check()
        progress?(.preparingResources, String(localized: "Loading textures and preflighting Metal resources"))
#if DEBUG
        let resourcesStageStart = CACurrentMediaTime()
        NSLog(
            "MWX LAUNCH-STAGE: stage=model-build elapsedMs=%.0f preludeMs=%.0f",
            modelBuildMs,
            (resourcesStageStart - prepareEntry) * 1000
        )
#endif
        var baseMaterialProviderBindings = SceneBaseMaterialProviderBindingCompiler.compile(
                descriptor: runtimeInput.renderDescriptor,
                materialInstancesByLayerID:
                    model.sceneDocument.materialInstancesByLayerID,
                scriptBindings: model.sceneDocument.scriptBindings,
                materialPropertyTargets: materialPropertyTargets,
                materialColorTargets: model.propertyVectorProjection.dynamicImageMaterialColorTargets
                    .filter { loweredMaterialModelPaths.contains($0.key) },
                provenBindings: provenMaterialBindings
            )
        let modelMaterialPlan = try ScenePreparedStaticModelResources.compileMaterialPlan(
            descriptor: runtimeInput.renderDescriptor, resourceView: model.resourceView,
            cancellationCheck: { try cancellation?.check() })
        let lightingDemands = Set(baseMaterialProviderBindings.lightingProfileByLayerID.values
            .flatMap { [$0.normalAsset, $0.mapAsset].compactMap { $0 } })
        let materialAssetDemands = resolvedMaterialCatalog.assetDemands
        let materialAssetCatalog = try SceneMaterialAssetTextureCatalog(
            demands: materialAssetDemands.union(lightingDemands)
                .union(baseMaterialProviderBindings.assetDemands).union(modelMaterialPlan.assetDemands),
            resourceView: model.resourceView,
            descriptor: runtimeInput.renderDescriptor,
            conditionalDemands: materialAssetDemands,
            matchesCondition: { $0.matches(runtimeInput.effectivePropertyValues) },
            textureUploadCommandQueue: textureUploadCommandQueue,
            textureDecodeCacheBudget: textureDecodeCacheBudget,
            device: device, checkCancellation: { try cancellation?.check() }
        )
#if DEBUG
        NSLog("MWX LAUNCH-STAGE: stage=catalog-decode elapsedMs=%.0f", (CACurrentMediaTime() - resourcesStageStart) * 1000)
#endif
        let stockNoiseTextures = try SceneStockNoiseTextureStore(
            assetStates: materialAssetCatalog.launchStates,
            systemDemands: resolvedMaterialCatalog.systemProviderDemands
                .union(baseMaterialProviderBindings.orderedSystemProviderDemands),
            device: device,
            uploadCommandQueue: textureUploadCommandQueue,
            cancellationCheck: { try cancellation?.check() }
        )
        let provisionalMaterialExecutionCapabilities =
            try SceneResolvedMaterialExecutionCapabilityCatalog(
                admissionCandidates: resolvedMaterialAdmissionCandidates,
                materialCatalog: resolvedMaterialCatalog,
                dynamicProducers: .init(
                    userProperties: userPropertyProducers,
                    authoredFallbackTargets:
                        executablePropertyFallbackTargets,
                    timelineDefinitions: timelineDefinitions,
                    sceneScriptTargets: provisionalSceneScriptValueTargets
                ),
                assetFormatFacts: materialAssetCatalog.launchFormatFacts,
                assetStates: materialAssetCatalog.launchStates,
                systemProviderStates: stockNoiseTextures.states,
                dynamicVisibleRootLayerIDs:
                    projectedLayerVisibilityRootLayerIDs,
                backbufferFormat: runtimeInput.renderDescriptor.colorTargetFormat,
                cancellationCheck: { try cancellation?.check() }
            )
#if DEBUG
        NSLog("MWX LAUNCH-STAGE: stage=capability-catalog elapsedMs=%.0f", (CACurrentMediaTime() - resourcesStageStart) * 1000)
#endif
        let admittedVectorPassTargets =
            provisionalMaterialExecutionCapabilities.sceneScriptConsumerTargets
                .intersection(propertyVectorPassCandidateTargets)
        let resolvedMaterialExecutionCapabilities =
            provisionalMaterialExecutionCapabilities
        let sourceMaterialCandidateConsumerLayerIDs = resolvedMaterialCatalog
            .sourceMaterialCandidateConsumerLayerIDs(in: runtimeInput.renderDescriptor)
        let imageModulationConsumerTargets = Self.imageLayerModulationConsumerTargets(
            in: runtimeInput.renderDescriptor,
            resolvedMaterialExecutionCapabilities: resolvedMaterialExecutionCapabilities,
            sourceMaterialCandidateConsumerLayerIDs: sourceMaterialCandidateConsumerLayerIDs
        )
        let namedSoundPropertyKeys = SceneScriptScalarProgram.projectedVolumePropertyKeys(
            descriptor: authoredRenderDescriptor,
            scriptBindings: model.sceneDocument.scriptBindings,
            timelineTargets: timelineTargets)
        let soundPropertyDefinitions = Dictionary(
            grouping: model.project.userProperties.definitions, by: \.key)
        let resolvedPropertyVolumes = soundPropertyDefinitions.reduce(into: [String: Double]()) { values, entry in
            guard entry.value.count == 1, entry.value[0].kind == .slider,
                  case let .number(volume)? = runtimeInput.effectivePropertyValues[entry.key],
                  volume.isFinite else { return }
            values[entry.key] = volume
        }
        let soundVolumeConsumerTargets = soundPlaybackProgram
            .sceneScriptVolumeConsumerTargets(for: sceneScriptScalarDefinitions,
                namedPropertyKeys: namedSoundPropertyKeys,
                resolvedPropertyVolumes: resolvedPropertyVolumes)
        // Structural candidates need an actual prepared consumer. Partition
        // them before planning/evaluating modules; construction and fallback
        // use the same exclusions.
        let scalarExcludedTargets = propertyVectorScriptTargets.union(
            sceneScriptScalarTargets.filter { target in
                switch target {
                case .layer(_, .brightness):
                    return !imageModulationConsumerTargets.contains(target)
                case .layer(_, .volume):
                    return !soundVolumeConsumerTargets.contains(target)
                default:
                    return false
                }
            }
        )
        let firstSurfaceRuntimePreparation =
            ScenePreparedFirstSurfaceRuntimeTask(
                catalog: resolvedMaterialCatalog,
                capabilities: resolvedMaterialExecutionCapabilities,
                assets: materialAssetCatalog,
                device: device,
                visibleExecutionRootLayerIDs:
                    resolvedMaterialVisibleExecutionRootLayerIDs,
                capturesExecutionObservations: Self.usesExecutionObservationCapture,
                cancellationCheck: { try cancellation?.check() }
            )
        firstSurfaceRuntimePreparation.start()
        defer {
            firstSurfaceRuntimePreparation.cancel()
            _ = try? firstSurfaceRuntimePreparation.value()
        }
#if DEBUG
        NSLog("MWX LAUNCH-STAGE: stage=first-surface-start elapsedMs=%.0f", (CACurrentMediaTime() - resourcesStageStart) * 1000)
#endif
        try cancellation?.check()
        let sceneScriptStorageSession = recordID.map {
            SceneScriptLocalStorageSession(recordID: $0, defersPersistence: true)
        }
        let timelinePlaybackRuntime = SceneTimelinePlaybackRuntime(program: timelineProgram)
        let timelineAnimationTargets = timelineProgram.bindings.map {
            (target: $0.target, name: $0.animation.options.name ?? "")
        }
        let timelinePlaybackOwners: [SceneDynamicTarget: SceneDynamicTarget] = Dictionary(
            uniqueKeysWithValues: timelineProgram.bindings.compactMap {
            $0.target == $0.playbackOwnerTarget ? nil : ($0.target, $0.playbackOwnerTarget)
        })
        let compileSceneScriptPrograms: (
            Set<SceneDynamicTarget>, Set<SceneDynamicTarget>
        ) throws -> SceneScriptQuickJSProgramCandidate = {
            vectorPassTargets, excludedVectorTargets in
            try SceneScriptQuickJSProgramCandidate.compile(
                authoredDescriptor: authoredRenderDescriptor,
                runtimeDescriptor: runtimeInput.renderDescriptor,
                scriptBindings: model.sceneDocument.scriptBindings,
                vectorProjection: model.propertyVectorProjection.excludingTargets(
                    excludedVectorTargets
                ), routeExcludedTargets: excludedVectorTargets,
                userPropertyDefinitions: model.project.userProperties.definitions,
                timelineTargets: timelineTargets,
                namedAnimations: timelineAnimationTargets,
                timelinePlaybackOwners: timelinePlaybackOwners,
                timelineRateLookup: timelinePlaybackRuntime.rate(for:),
                scalarExcludedTargets: scalarExcludedTargets,
                stringExcludedTargets: sceneScriptStringExcludedTargets,
                admittedVectorPassTargets: vectorPassTargets,
                generation: sceneScriptGeneration,
                storageSession: sceneScriptStorageSession,
                cancellationCheck: { try cancellation?.check() }
            )
        }
        guard let routedPrograms = try SceneScriptVectorMediaRouteCandidate.compile(
            initialPassTargets: admittedVectorPassTargets,
            route: sceneScriptVectorMediaRoute,
            cancellationCheck: { try cancellation?.check() },
            builder: compileSceneScriptPrograms
        ) else {
            throw SceneDesktopWallpaperHostLaunchError
                .invalidBoundedSceneScriptProgramAt("media-route-fixed-point")
        }
#if DEBUG
        NSLog("MWX LAUNCH-STAGE: stage=quickjs-compile elapsedMs=%.0f", (CACurrentMediaTime() - resourcesStageStart) * 1000)
#endif
        let committedPrograms = routedPrograms.programs
        let committedVectorPassTargets = routedPrograms.admittedPassTargets
        let propertyVectorMediaTargets = routedPrograms.mediaOwnerTargets
        guard committedPrograms.constructionReport.isComplete else {
            throw SceneDesktopWallpaperHostLaunchError
                .invalidBoundedSceneScriptProgramAt(
                    "scenescript-family-candidate-publication"
                )
        }
        let assetLaunchStates = materialAssetCatalog.launchStates
        deviceResourcesPreparation.completeResourcePlanning(.init(
            dynamicImageModelPaths: committedPrograms.domain?.dynamicImageRequestedModelPaths ?? [],
            modelMaterialPlan: modelMaterialPlan,
            modelAlbedoStates: modelMaterialPlan.assetDemands.reduce(into: [:]) {
                $0[$1] = assetLaunchStates[$1]
            }
        ))
        guard let fallbackCatalog = SceneScriptFallbackCatalog(
            authoredDescriptor: authoredRenderDescriptor,
            runtimeDescriptor: runtimeInput.renderDescriptor,
            scriptBindings: model.sceneDocument.scriptBindings,
            vectorProjection: model.propertyVectorProjection,
            constructionReport: committedPrograms.constructionReport,
            timelineTargets: timelineTargets,
            scalarExcludedTargets: scalarExcludedTargets,
            stringExcludedTargets: sceneScriptStringExcludedTargets,
            routeDisabledTargets: sceneScriptVectorMediaRoute == .disableGeneric
                ? propertyVectorMediaTargets : []
        ) else {
            throw SceneDesktopWallpaperHostLaunchError
                .invalidBoundedSceneScriptProgramAt("scenescript-fallback-catalog")
        }
        let sceneScriptFallbackDefinitions = fallbackCatalog.definitions
        let propertyVectorScriptProgram = committedPrograms.vectorProgram
        let sceneScriptCursorProgram = committedPrograms.cursorProgram
        let sceneScriptScalarProgram = committedPrograms.scalarProgram
        soundPlaybackProgram = soundPlaybackProgram.assigningSceneScriptVolumes(
            soundVolumeConsumerTargets.intersection(Set(sceneScriptScalarProgram.definitions.map(\.target))))
        let sceneScriptStringProgram = committedPrograms.stringProgram
        let passCompilation = committedPrograms.vectorPassCompilation
        let rejectedVectorPassTargets = passCompilation.failedTargets
        guard passCompilation.requestedTargets == committedVectorPassTargets,
              passCompilation.instantiatedTargets.isDisjoint(
                  with: rejectedVectorPassTargets
              ),
              passCompilation.instantiatedTargets.union(
                  rejectedVectorPassTargets
              ) == committedVectorPassTargets else {
            throw SceneDesktopWallpaperHostLaunchError
                .invalidBoundedSceneScriptProgramAt(
                    "property-vector-candidate-publication"
                )
        }
        let constructedPropertyVectorTargets = Set(
            propertyVectorScriptProgram.definitions.map(\.target)
        )
        guard constructedPropertyVectorTargets.count
                == propertyVectorScriptProgram.definitions.count,
              constructedPropertyVectorTargets.isDisjoint(
                  with: Set(sceneScriptScalarProgram.definitions.map(\.target))
              ),
              constructedPropertyVectorTargets.isDisjoint(
                  with: Set(sceneScriptStringProgram.definitions.map(\.target))
              ),
              fallbackCatalog.targets.isDisjoint(
                  with: constructedPropertyVectorTargets
                      .union(sceneScriptScalarProgram.definitions.map(\.target))
                      .union(sceneScriptStringProgram.definitions.map(\.target))
              ) else {
            throw SceneDesktopWallpaperHostLaunchError
                .invalidBoundedSceneScriptProgramAt(
                    "property-vector-final-ownership"
                )
        }
        let resolvedMaterialSubjects = resolvedMaterialExecutionCapabilities
            .runtimeDispositionOwnerships.flatMap(\.subjects)
        let verifiedXRayStockIdentityKeys =
            SceneXRayStockIdentityVerifier.verifiedStockIdentityEffectKeys(
                descriptor: runtimeInput.renderDescriptor,
                shaderContracts: runtimeInput.shaderContracts
            )
        let effectAdmissionCatalog = SceneEffectAdmissionCatalog(
            descriptor: runtimeInput.renderDescriptor,
            authoredPlans: runtimeInput.authoredEffectRenderPlans,
            resolvedMaterialSubjects: resolvedMaterialSubjects,
            startupInactiveEffectVisibilityTargets:
                runtimeInput.startupInactiveEffectVisibilityTargets,
            verifiedXRayStageKeys: verifiedXRayStockIdentityKeys
        )
        let sceneScriptOwnerLayerIDs = Set(
            propertyVectorScriptProgram.bindings.compactMap { $0.owner.layerID }
                + (
                sceneScriptScalarProgram.definitions
                    + sceneScriptStringProgram.definitions
            ).compactMap {
                SceneScriptLayerMutationBridge.layerID(for: $0.target)
            }
        )
        let preparedDeviceResources = try deviceResourcesPreparation.value()
        preparedDeviceResources.baseImages.addConditionalAssets(materialAssetCatalog.takeConditionalAssets())
        let userTextureDemands = resolvedMaterialCatalog.userPropertyDemands
            .union(baseMaterialProviderBindings.userPropertyDemands)
            .union(preparedDeviceResources.staticModels.userPropertyDemands)
            .union(runtimeInput.renderDescriptor.texturePropertyKeys.compactMap {
                SceneUserPropertyTextureIdentity(propertyKey: $0, purpose: .premultipliedColor)
            })
        let userPropertyTextureLoad: SceneUserPropertyTextureLoadResult = {
            let scopedURLs = userPropertyTextureURLs.values.filter {
                $0.startAccessingSecurityScopedResource()
            }
            defer { scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() } }
            return SceneUserPropertyTextureLoader().load(
                urlsByPropertyKey: userPropertyTextureURLs,
                requestedIdentities: userTextureDemands.union(requiredUserTextureKeys.compactMap {
                    SceneUserPropertyTextureIdentity(propertyKey: $0, purpose: .premultipliedColor)
                }),
                textureUploadCommandQueue: textureUploadCommandQueue,
                textureDecodeCacheBudget: textureDecodeCacheBudget,
                device: device,
                videoCacheDirectory: privateMediaCacheDirectory,
                isCancelled: {
                    do { try cancellation?.check(); return false }
                    catch { return true }
                }
            )
        }()
        try cancellation?.check()
        guard userPropertyTextureLoad.satisfiesPreparedProperties(
            requiredUserTextureKeys, selectedKeys: Set(userPropertyTextureURLs.keys),
            demands: userTextureDemands
        ), userPropertyTextureURLs.allSatisfy({ key, url in
            !SceneUserPropertyTextureLoader.isVideo(url: url)
                || userPropertyTextureLoad.videoDeclarations[key] != nil
        }) else { throw SceneDesktopWallpaperHostLaunchError.requiredUserTextureUnavailable }
#if DEBUG
        NSLog("MWX LAUNCH-STAGE: stage=device-join elapsedMs=%.0f", (CACurrentMediaTime() - resourcesStageStart) * 1000)
#endif
        let firstSurfaceRuntime = try firstSurfaceRuntimePreparation.value()
        let preparedSourceMaterialTargets = firstSurfaceRuntime.sourceMaterials.values.reduce(
            into: Set<SceneDynamicTarget>()
        ) { $0.formUnion($1.declaredDynamicTargets) }
        let preparedFirstSurfaceRuntime = ScenePreparedFirstSurfaceRuntime(firstSurfaceRuntime)
        let resourceCatalog = SceneDesktopWallpaperLaunchFrameSchema.preparedResourceCatalog(
            descriptor: runtimeInput.renderDescriptor,
            baseImages: preparedDeviceResources.baseImages, models: model.assetCatalog.models,
            sourceMaterialModelPaths: Set(firstSurfaceRuntime.sourceMaterialPrototypeByModel.keys)
                .union(loweredMaterialModelPaths))
        let preparedResourceLayerTemplates = resourceCatalog.templates
        baseMaterialProviderBindings = baseMaterialProviderBindings
            .preparingDynamicImageMaterials(resourceCatalog.lightingProfiles)
        try propertyVectorScriptProgram.domain?.configurePreparedResourceLayerCatalog(preparedResourceLayerTemplates)
#if DEBUG
        NSLog("MWX LAUNCH-STAGE: stage=first-surface-join elapsedMs=%.0f", (CACurrentMediaTime() - resourcesStageStart) * 1000)
#endif
        let frameSchema = SceneDesktopWallpaperLaunchFrameSchema(
            runtimeInput: runtimeInput,
            propertyVectorScriptProgram: propertyVectorScriptProgram,
            sceneScriptFallbackDefinitions: sceneScriptFallbackDefinitions,
            sceneScriptScalarProgram: sceneScriptScalarProgram,
            sceneScriptStringProgram: sceneScriptStringProgram,
            sceneScriptOwnerLayerIDs: sceneScriptOwnerLayerIDs,
            preparedResourceLayerTemplates: preparedResourceLayerTemplates,
            utilitySourceRoutes: SceneUtilityLayerSourceRoute.preparedResolutions(
                in: runtimeInput.renderDescriptor,
                resolvedMaterialLayerIDs: firstSurfaceRuntime.executionLayerIDs
            ),
            preparedSoundVolumes: Dictionary(uniqueKeysWithValues:
                soundPlaybackProgram.bindings.map { ($0.layerID, $0.authoredVolume) }),
            timelineProgram: timelineProgram
        )
        try cancellation?.check()
        let context = SceneDesktopWallpaperLaunchContext(
            runtimeInput: runtimeInput,
            preparedParticleAssets: preparedParticleAssets,
            particleLayerIDs: Set(runtimeInput.renderDescriptor.layers
                .filter { $0.contentKind == "particle" }.map(\.id)),
            particleVisibilityRequirements: particleVisibilityRequirements,
            effectAdmissionCatalog: effectAdmissionCatalog,
            resolvedMaterialCatalog: resolvedMaterialCatalog,
            resolvedMaterialExecutionCapabilities:
                resolvedMaterialExecutionCapabilities,
            materialAssetCatalog: materialAssetCatalog,
            stockNoiseTextures: stockNoiseTextures,
            preparedDeviceResources: preparedDeviceResources,
            preparedFirstSurfaceRuntime: preparedFirstSurfaceRuntime,
            timelineProgram: timelineProgram,
            timelinePlaybackRuntime: timelinePlaybackRuntime,
            textureAnimationPlaybackRuntime:
                SceneTextureAnimationPlaybackRuntime(),
            puppetAnimationPlaybackRuntime: ScenePuppetAnimationPlaybackRuntime(),
            sceneScriptCursorProgram: sceneScriptCursorProgram,
            propertyVectorScriptProgram: propertyVectorScriptProgram,
            propertyVectorPassCandidateTargets:
                propertyVectorPassCandidateTargets,
            propertyVectorPassConsumerTargets:
                admittedVectorPassTargets,
            propertyVectorPassFailedTargets:
                rejectedVectorPassTargets,
            propertyVectorMediaTargets: propertyVectorMediaTargets,
            sceneScriptFallbackDefinitions: sceneScriptFallbackDefinitions,
            sceneScriptVectorMediaRoute: sceneScriptVectorMediaRoute,
            sceneScriptScalarProgram: sceneScriptScalarProgram,
            sceneScriptSourceEvidence: model.sceneDocument.scriptSourceEvidence,
            sceneScriptStringProgram: sceneScriptStringProgram,
            sceneScriptDynamicLayerRuntime: frameSchema.dynamicLayerRuntime,
            sceneScriptStorageSession: sceneScriptStorageSession,
            frameSchema: frameSchema,
            baseMaterialProviderBindings: baseMaterialProviderBindings,
            soundPlaybackProgram: soundPlaybackProgram,
            liveState: Self.makeLivePropertyState(
                runtimeInput: runtimeInput,
                resolvedMaterialExecutionCapabilities:
                    resolvedMaterialExecutionCapabilities,
                soundPlaybackProgram: soundPlaybackProgram,
                preparedStaticModelLayerIDs: Set(
                    preparedDeviceResources.staticModels.preparedLayerIDs
                ),
                preparedImageMaterialTargets: Set(baseMaterialProviderBindings.lightingProfileByLayerID.values
                    .compactMap(\.emissionPropertyTarget))
                    .union(baseMaterialProviderBindings.sourceMaterialAlphaPropertyTargets)
                    .union(baseMaterialProviderBindings.materialColorTargets.values)
                    .union(preparedSourceMaterialTargets),
                preparedDirectModelAnimationVisibilityTargets:
                    preparedDeviceResources.staticModels.preparedDirectModelAnimationVisibilityTargets,
                sourceMaterialCandidateConsumerLayerIDs:
                    sourceMaterialCandidateConsumerLayerIDs,
                preparedParticleVisibilityLayerIDs:
                    preparedParticleVisibilityLayerIDs,
                propertyVectorScriptProgram: propertyVectorScriptProgram,
                sceneScriptScalarProgram: sceneScriptScalarProgram,
                sceneScriptStringProgram: sceneScriptStringProgram,
                propertyDefinitions: model.project.userProperties.definitions,
                conditionalAtlasPropertyKeys: preparedDeviceResources.baseImages.conditionalPropertyKeys
            ),
            privateMediaCacheDirectory: privateMediaCacheDirectory,
            resourceView: model.resourceView,
            logURL: logURL,
            recordID: recordID,
            capturesExecutionObservations: Self.usesExecutionObservationCapture
        )
        try context.configurePreparedPuppetBones()
#if DEBUG
        let particlePreparationStart = CACurrentMediaTime()
        let framesBeforeParticlePreparation = ScenePerformanceCounterHub.shared.snapshot()[.framesRendered] ?? 0
#endif
        let initialValues = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 0, generation: 0, index: context.dynamicDefinitionIndex,
            userValues: context.liveState.userValues,
            timelineValues: context.timelinePlaybackRuntime.values(sceneTime: 0),
            sceneScriptValues: [:]).snapshot
        let topology = context.sceneScriptDynamicLayerRuntime.snapshot()
        let audio = SceneAudioSpectrumInbox.shared.prepareFrame().snapshot
        let preparedSurfaces = try context.makeSurfacePreparationInput(
            dynamicValues: initialValues, topology: topology,
            audioInput: .init(left: audio.left, right: audio.right, generation: audio.generation)
        ).prepare(displayIDs: surfaceDisplayIDs, cancellation: cancellation)
#if DEBUG
        let preparedFrameCount = (ScenePerformanceCounterHub.shared.snapshot()[.framesRendered] ?? 0)
            - framesBeforeParticlePreparation
        NSLog("MWX LAUNCH-STAGE: stage=particle-prewarm elapsedMs=%.3f surfaces=%d concurrentRenderedFrames=%llu",
              (CACurrentMediaTime() - particlePreparationStart) * 1000,
              preparedSurfaces.count, preparedFrameCount)
#endif
        try cancellation?.check()
#if DEBUG
        NSLog("MWX LAUNCH-STAGE: stage=prepare-end elapsedMs=%.0f", (CACurrentMediaTime() - resourcesStageStart) * 1000)
#endif
        return PreparedLaunch(model: model, context: context,
                              userPropertyTextureLoad: userPropertyTextureLoad,
                              preparedSurfaces: preparedSurfaces)
    }

    private func finishLaunchFailure(
        _ error: Error,
        requestID: UUID,
        recordID: String?,
        completion: @MainActor (Result<SceneRuntimeModel, Error>) -> Void
    ) {
        launchCancellation = nil
        let cancelled = Self.isLaunchCancellation(error)
        publishLaunchState(.init(
            requestID: requestID,
            recordID: recordID,
            phase: cancelled ? .cancelled : .failed,
            message: cancelled ? String(localized: "Scene wallpaper preparation canceled") : String(localized: "Scene Wallpaper Preparation Failed")
        ))
        completion(.failure(error))
    }
}
