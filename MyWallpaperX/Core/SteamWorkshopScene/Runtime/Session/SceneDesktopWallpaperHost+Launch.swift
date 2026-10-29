import Foundation
import QuartzCore
import Metal

extension SceneDesktopWallpaperHost {
    struct PreparedLaunch {
        let model: SceneRuntimeModel
        var context: SceneDesktopWallpaperLaunchContext
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
            message: "已接受 Scene 壁纸请求"
        ))

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
                            message: "正在准备显示器与 Scene 表面"
                        ))
                        try self.beginCandidate(
                            prepared.context,
                            firstPresentation: .init(requestID: requestID, recordID: recordID)
                        ) { [weak self] result in
                            guard let self, self.nextLaunchRequestGeneration == requestGeneration else { return }
                            switch result {
                            case .success:
                                self.launchCancellation = nil
                                let reachability: ScenePreparedCallbackPropertyReachability?
                                if let projectWitness = prepared.model.project.sourceWitness,
                                   let sceneWitness = prepared.model.sceneDocument.sourceWitness,
                                   let session = self.activeSession {
                                    reachability = .init(source: .init(
                                        rootPath: prepared.model.project.rootURL.resolvingSymlinksInPath().standardizedFileURL.path,
                                        projectWitness: projectWitness, sceneWitness: sceneWitness),
                                        scriptGeneration: scriptGeneration,
                                        propertyKeys: session.preparedCallbackPropertyKeys(
                                            definitions: prepared.model.project.userProperties.definitions))
                                } else { reachability = nil }
                                self.publishLaunchState(.init(requestID: requestID,
                                    recordID: recordID, phase: .launched, message: "Scene 首帧已完成并切换",
                                    callbackPropertyReachability: reachability))
                                complete(.success(prepared.model))
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
            message: "已取消 Scene 壁纸准备"
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
        progress?(.preparingModel, "正在读取资源并解析场景")
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
        progress?(.preparingPrograms, "正在准备材质、脚本与渲染计划")
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
            awaitsScriptResourcePlanning: true,
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
        let propertyBindingTargets = Set(propertyBindingDefinitions.map(\.target))
        let userPropertyProducers = Set(
            runtimeInput.propertyBindingProgram.instructions.map {
                SceneDynamicUserPropertyProducer(
                    propertyKey: $0.propertyKey,
                    target: $0.target,
                    valueType: $0.valueType
                )
            }
        )
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
        let boundedProducerTargets: [(
            String, Set<SceneDynamicTarget>, Int, Set<SceneDynamicTarget>,
            Set<SceneDynamicTarget>
        )] = [
            ("property-vector", propertyVectorScriptTargets,
             propertyVectorScriptTargets.count,
             model.propertyVectorProjection.animationTargets, vectorPropertyInputTargets),
            ("shared-alpha", Set(model.sharedLayerAlphaProgram.definitions.map(\.target)),
             model.sharedLayerAlphaProgram.definitions.count, [], []),
        ]
        var boundedSceneScriptTargets: Set<SceneDynamicTarget> = []
        var boundedProducerConflicts: [String] =
            model.propertyVectorProjection.duplicateTargets.isEmpty
                ? [] : ["property-vector/duplicate"]
        for (name, targets, definitionCount, allowedTimelineTargets, allowedPropertyInputs)
            in boundedProducerTargets {
            if targets.count != definitionCount {
                boundedProducerConflicts.append("\(name)/duplicate")
            }
            if !targets.isDisjoint(with: propertyBindingTargets) &&
                !targets.intersection(propertyBindingTargets)
                    .subtracting(allowedPropertyInputs).isEmpty {
                boundedProducerConflicts.append("\(name)/property")
            }
            let unownedTimelineOverlap = targets.intersection(timelineTargets)
                .subtracting(allowedTimelineTargets)
            if !unownedTimelineOverlap.isEmpty {
                boundedProducerConflicts.append("\(name)/timeline")
            }
            if !targets.isDisjoint(with: boundedSceneScriptTargets) {
                boundedProducerConflicts.append("\(name)/bounded-peer")
            }
            boundedSceneScriptTargets.formUnion(targets)
        }
        guard boundedProducerConflicts.isEmpty else {
            throw SceneDesktopWallpaperHostLaunchError
                .conflictingBoundedSceneScriptTargets(
                    " phases=\(boundedProducerConflicts.joined(separator: ","))"
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
            excludedTargets: boundedSceneScriptTargets
        )
        let sceneScriptScalarTargets = Set(sceneScriptScalarDefinitions.map(\.target))
        guard sceneScriptScalarTargets.isDisjoint(
            with: boundedSceneScriptTargets
        ) else {
            throw SceneDesktopWallpaperHostLaunchError
                .invalidBoundedSceneScriptProgramAt("scalar-target-ownership")
        }
        let sceneScriptStringExcludedTargets = boundedSceneScriptTargets
            .union(sceneScriptScalarTargets)
        let sceneScriptStringTargets = SceneScriptStringProgram.projectedTargets(
            descriptor: runtimeInput.renderDescriptor,
            scriptBindings: model.sceneDocument.scriptBindings,
            excludedTargets: sceneScriptStringExcludedTargets
        )
        guard sceneScriptStringTargets.isDisjoint(with: boundedSceneScriptTargets),
              sceneScriptStringTargets.isDisjoint(with: sceneScriptScalarTargets) else {
            throw SceneDesktopWallpaperHostLaunchError
                .invalidBoundedSceneScriptProgramAt("string-target-ownership")
        }
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
        let textScriptProgram = SceneTextScriptCompiler.compile(
            descriptor: runtimeInput.renderDescriptor,
            excludedTargets: sceneScriptStringTargets,
            preparationLayerIDs: projectedLayerVisibilityRootLayerIDs
        )
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
        let resolvedMaterialCatalog = SceneResolvedMaterialRuntimeCatalog(
            descriptor: runtimeInput.renderDescriptor,
            admissionCandidates: resolvedMaterialAdmissionCandidates,
            shaderContracts: runtimeInput.shaderContracts,
            userPropertyProducers: userPropertyProducers,
            propertyDefinitions: propertyBindingDefinitions,
            timelineDefinitions: timelineDefinitions,
            provenSceneScriptValueTargets: provisionalSceneScriptValueTargets,
            materialInstancesByLayerID: model.sceneDocument.materialInstancesByLayerID,
            loweredSourceMaterialModelPaths: loweredMaterialModelPaths,
            provenSourceMaterialBindings: provenMaterialBindings
        )
#if DEBUG
        logPrepareStage("prepare-catalog")
#endif
        try cancellation?.check()
        progress?(.preparingResources, "正在加载纹理并预检 Metal 资源")
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
        let lightingDemands = Set(baseMaterialProviderBindings.lightingProfileByLayerID.values
            .flatMap { [$0.normalAsset, $0.mapAsset].compactMap { $0 } })
        let materialAssetCatalog = try SceneMaterialAssetTextureCatalog(
            demands: resolvedMaterialCatalog.assetDemands.union(lightingDemands)
                .union(baseMaterialProviderBindings.assetDemands),
            resourceView: model.resourceView,
            descriptor: runtimeInput.renderDescriptor,
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
        let scalarExcludedTargets = boundedSceneScriptTargets.union(
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
                namedAnimations: timelineProgram.bindings.compactMap { binding in
                    binding.animation.options.name.map { (binding.target, $0) }
                },
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
        deviceResourcesPreparation.completeScriptResourcePlanning(
            committedPrograms.domain?.dynamicImageRequestedModelPaths ?? []
        )
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
        let userTextureDemands = resolvedMaterialCatalog.userPropertyDemands
            .union(baseMaterialProviderBindings.userPropertyDemands)
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
        let preparedSourceMaterialTargets: Set<SceneDynamicTarget> = Set(firstSurfaceRuntime.sourceMaterials.values
            .flatMap { material in
                material.template.uniformDeclarations.compactMap { declaration in
                    if case let .dynamic(value) = declaration.value { return value.target }
                    return nil
                }
            })
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
            sharedLayerAlphaProgram: model.sharedLayerAlphaProgram,
            propertyVectorScriptProgram: propertyVectorScriptProgram,
            sceneScriptFallbackDefinitions: sceneScriptFallbackDefinitions,
            sceneScriptScalarProgram: sceneScriptScalarProgram,
            sceneScriptStringProgram: sceneScriptStringProgram,
            sceneScriptOwnerLayerIDs: sceneScriptOwnerLayerIDs,
            preparedResourceLayerTemplates: preparedResourceLayerTemplates,
            timelineProgram: timelineProgram,
            textScriptProgram: textScriptProgram
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
            timelinePlaybackRuntime: SceneTimelinePlaybackRuntime(
                program: timelineProgram
            ),
            textureAnimationPlaybackRuntime:
                SceneTextureAnimationPlaybackRuntime(),
            puppetAnimationPlaybackRuntime: ScenePuppetAnimationPlaybackRuntime(),
            textScriptProgram: textScriptProgram,
            sharedLayerAlphaProgram: model.sharedLayerAlphaProgram,
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
                propertyDefinitions: model.project.userProperties.definitions
            ),
            userPropertyTextureLoad: userPropertyTextureLoad,
            privateMediaCacheDirectory: privateMediaCacheDirectory,
            resourceView: model.resourceView,
            logURL: logURL,
            recordID: recordID,
            capturesExecutionObservations: Self.usesExecutionObservationCapture
        )
        try context.configurePreparedPuppetBones()
        try cancellation?.check()
#if DEBUG
        NSLog("MWX LAUNCH-STAGE: stage=prepare-end elapsedMs=%.0f", (CACurrentMediaTime() - resourcesStageStart) * 1000)
#endif
        return PreparedLaunch(model: model, context: context)
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
            message: cancelled ? "已取消 Scene 壁纸准备" : "Scene 壁纸准备失败"
        ))
        completion(.failure(error))
    }
}
