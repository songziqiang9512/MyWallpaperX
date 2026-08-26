import Foundation
import Metal

struct SceneDesktopWallpaperLaunchContext {
    let runtimeInput: SceneRuntimeInput
    let effectAdmissionCatalog: SceneEffectAdmissionCatalog
    let resolvedMaterialCatalog: SceneResolvedMaterialRuntimeCatalog
    let resolvedMaterialExecutionCapabilities:
        SceneResolvedMaterialExecutionCapabilityCatalog
    let materialAssetCatalog: SceneMaterialAssetTextureCatalog
    let pipelineRepository: SceneImageEffectPipelineRepository
    let spriteTextureLoader: SceneMultiImageSpriteTextureLoader
    let timelineProgram: SceneTimelineProgram
    let textScriptProgram: SceneTextScriptProgram
    let timeOfDayEffectScriptProgram: SceneTimeOfDayEffectScriptProgram
    let timeOfDayEffectScriptAdmissionDiagnostic: String?
    let mediaPlaybackPlaceholderFadeProgram:
        SceneMediaPlaybackPlaceholderFadeProgram
    let mediaColorTransitionProgram: SceneMediaColorTransitionProgram
    let sharedLayerAlphaProgram: SceneSharedLayerAlphaProgram
    let launchOriginTransitionProgram: SceneLaunchOriginTransitionProgram
    let hoverOriginTransitionProgram: SceneHoverOriginTransitionProgram
    let audioScaledValueProgram: SceneAudioScaledValueProgram
    let propertyVectorScriptProgram: ScenePropertyVectorScriptProgram
    let sceneScriptScalarProgram: SceneScriptScalarProgram
    let mediaThumbnailBindings: SceneMediaThumbnailBindingProgram
    var liveState: ScenePropertyLiveUpdateState
    let userPropertyTextureURLs: [String: URL]
    let cacheDirectory: URL
    let resourceView: SceneResourceView
    let logURL: URL?
    let recordID: String?

    var resolvedMaterialStartupReportLines: [String] {
        resolvedMaterialCatalog.reportLines
            + resolvedMaterialExecutionCapabilities.reportLines
            + materialAssetCatalog.reportLines + [
            "scene script VM: schema=quickjs-ng-scalar-v1"
                + " bindings=\(sceneScriptScalarProgram.bindings.count)"
                + " targets=\(sceneScriptScalarProgram.definitions.count)"
                + " fallback=bounded-swift-prefer-generic",
            "resolved material system providers: schema=r3-system-provider-v1"
                + " demands=\(resolvedMaterialCatalog.systemProviderDemands.count)"
                + " missingState=unavailable"
                + " reason=snapshot-lifecycle-unproven",
            "scene media placeholder fade: schema=bounded-playback-fade-v1"
                + " bindings=\(mediaPlaybackPlaceholderFadeProgram.bindings.count)"
                + " input=typed-inbox liveProvider=unavailable initialMode=stopped",
            "scene media color transition: schema=bounded-thumbnail-palette-v2"
                + " bindings=\(mediaColorTransitionProgram.bindings.count)"
                + " input=typed-inbox liveProvider=unavailable",
            "scene shared layer alpha: schema=bounded-shared-alpha-v1"
                + " flags=\(sharedLayerAlphaProgram.initialFlags.keys.sorted())"
                + " bindings=\(sharedLayerAlphaProgram.bindings.count)"
                + " layerIDs=\(sharedLayerAlphaProgram.layerIDs)"
                + " interaction=unavailable",
            "scene launch origin transition: schema=bounded-shared-origin-v1"
                + " cohorts=\(launchOriginTransitionProgram.cohorts.count)"
                + " bindings=\(launchOriginTransitionProgram.bindings.count)"
                + " scalarBindings=\(launchOriginTransitionProgram.scalarBindings.count)"
                + " layerIDs=\(launchOriginTransitionProgram.layerIDs)"
                + " interaction=cursor-click",
            "scene hover origin transition: schema=bounded-hover-origin-v1"
                + " cohorts=\(hoverOriginTransitionProgram.cohorts.count)"
                + " owners=\(hoverOriginTransitionProgram.ownerLayerIDs)"
                + " bindings=\(hoverOriginTransitionProgram.bindings.count)"
                + " layerIDs=\(hoverOriginTransitionProgram.layerIDs)"
                + " interaction=cursor-enter-leave",
            "scene audio scaled value: schema=bounded-audio-scaled-value-v1"
                + " bindings=\(audioScaledValueProgram.bindings.count)"
                + " rejectedParticleLayerIDs="
                + "\(audioScaledValueProgram.rejectedParticleLayerIDs)"
                + " rejectedScaleLayerIDs="
                + "\(audioScaledValueProgram.rejectedScaleLayerIDs)"
                + " resolution=16",
            "scene property vector scripts: schema=bounded-property-vector-v1"
                + " bindings=\(propertyVectorScriptProgram.bindings.count)"
                + " scaleLayerIDs="
                + "\(Array(propertyVectorScriptProgram.admittedScaleLayerIDs).sorted())"
        ]
    }

    func makeResolvedMaterialRuntime() -> SceneResolvedMaterialRuntimeBridge {
        .init(
            catalog: resolvedMaterialCatalog,
            capabilities: resolvedMaterialExecutionCapabilities,
            assets: materialAssetCatalog,
            device: pipelineRepository.device
        )
    }

    func appendResolvedMaterialStartupReport() {
        guard let logURL,
              let existing = try? String(contentsOf: logURL, encoding: .utf8) else {
            return
        }
        let separator = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
        let lines = resolvedMaterialStartupReportLines
        try? (existing + separator + lines.joined(separator: "\n") + "\n")
            .write(to: logURL, atomically: true, encoding: .utf8)
    }
}

enum SceneDesktopWallpaperHostLaunchError: LocalizedError {
    case missingPackageCache
    case conflictingBoundedSceneScriptTargets(String)
    case invalidBoundedSceneScriptProgramAt(String)
    case noSurface

    var errorDescription: String? {
        switch self {
        case .missingPackageCache:
            "Scene 资源缓存不可用。"
        case .conflictingBoundedSceneScriptTargets(let details):
            "Scene 有界脚本目标存在冲突，已停止启动。\(details)"
        case .invalidBoundedSceneScriptProgramAt(let phase):
            "Scene 有界脚本目标在 \(phase) 无法形成，已停止启动。"
        case .noSurface:
            "Scene 宿主未能创建可播放表面。"
        }
    }
}

extension SceneDesktopWallpaperHost {
    @discardableResult
    func launch(
        rootURL: URL,
        propertyOverrides: [String: SceneUserPropertyValue] = [:],
        userPropertyTextureURLs: [String: URL] = [:],
        logURL: URL? = nil,
        recordID: String? = nil
    ) throws -> SceneRuntimeModel {
        let model = try SceneRuntimeModelBuilder().build(
            rootURL: rootURL,
            propertyOverrides: propertyOverrides
        )
        guard let cacheDirectory = model.diagnostics.packageReport?.outputURL else {
            throw SceneDesktopWallpaperHostLaunchError.missingPackageCache
        }
        let runtimeInput = model.runtimeInput
        let timelineProgram = SceneTimelineTargetCompiler.compile(
            descriptor: runtimeInput.renderDescriptor
        )
        let launchOriginTransitionProgram =
            SceneLaunchOriginTransitionProgramCompiler.compile(
                descriptor: runtimeInput.renderDescriptor,
                scriptBindings: model.sceneDocument.scriptBindings,
                scriptSourceEvidence: model.sceneDocument.scriptSourceEvidence
            )
        let launchOriginTransitionTargets = Set(
            launchOriginTransitionProgram.definitions.map(\.target)
        )
        let hoverOriginTransitionProgram =
            SceneHoverOriginTransitionProgramCompiler.compile(
                descriptor: runtimeInput.renderDescriptor,
                scriptBindings: model.sceneDocument.scriptBindings,
                scriptSourceEvidence: model.sceneDocument.scriptSourceEvidence
            )
        let hoverOriginTransitionTargets = Set(
            hoverOriginTransitionProgram.definitions.map(\.target)
        )
        let audioScaledValueTargets = Set(
            model.audioScaledValueProgram.definitions.map(\.target)
        )
        let propertyVectorScriptTargets = Set(
            model.propertyVectorScriptProgram.definitions.map(\.target)
        )
        let propertyBindingTargets = Set(
            runtimeInput.propertyBindingProgram.definitions.map(\.target)
        )
        let userPropertyProducers = Set(
            runtimeInput.propertyBindingProgram.instructions.map {
                SceneDynamicUserPropertyProducer(
                    propertyKey: $0.propertyKey,
                    target: $0.target,
                    valueType: $0.valueType
                )
            }
        )
        let timelineTargets = Set(timelineProgram.bindings.map(\.target))
        typealias VisibilityOwner =
            SceneResolvedMaterialExecutionCapabilityAdmission
                .DynamicEffectVisibilityOwner
        // User-property visibility stays live for typed consumers; otherwise
        // live-state rejects atomically and the service relaunches the Scene.
        // Admission only blocks frame-driven topology changes here.
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
        let stageCompileEffectVisibilityOwners = Set(
            frameDrivenEffectVisibilityOwners.map {
                SceneEffectStageCompileInput.DynamicEffectVisibilityOwner(
                    layerID: $0.layerID,
                    effectIndex: $0.effectIndex
                )
            }
        )
        let dedicatedStageLeaves = runtimeInput.authoredEffectRenderPlans.flatMap {
            SceneEffectProgramCompiler.compileDedicatedLeaves(
                graph: $0,
                descriptor: runtimeInput.renderDescriptor,
                shaderContracts: runtimeInput.shaderContracts,
                userPropertyProducers: userPropertyProducers,
                frameDrivenEffectVisibilityOwners:
                    stageCompileEffectVisibilityOwners
            )
        }
        let dedicatedStageFamilies = Dictionary(
            uniqueKeysWithValues: dedicatedStageLeaves.map {
                ($0.effectKey, $0.executionPlan.backend.stableName)
            }
        )
        let dedicatedLeafKeys = Set(dedicatedStageLeaves.compactMap {
            $0.executionPlan.backend.supportsUnifiedPairLeaf ? $0.effectKey : nil
        })
        let dedicatedGraphStageKeys = Set(dedicatedStageLeaves.compactMap {
            $0.executionPlan.supportsUnifiedLogicalTargetStage
                ? $0.effectKey : nil
        })
        let timeOfDayEffectScriptCandidateProgram: SceneTimeOfDayEffectScriptProgram
        let timeOfDayEffectScriptAdmissionDiagnostic: String?
        switch SceneTimeOfDayEffectScriptProgramCompiler.compile(
            descriptor: runtimeInput.renderDescriptor
        ) {
        case let .success(program):
            timeOfDayEffectScriptCandidateProgram = program
            timeOfDayEffectScriptAdmissionDiagnostic = nil
        case let .failure(failure) where failure.isDescriptorIntegrityFailure:
            throw SceneDesktopWallpaperHostLaunchError
                .invalidBoundedSceneScriptProgramAt(
                    "time-of-day-candidates-\(failure.code.rawValue)"
                )
        case let .failure(failure):
            timeOfDayEffectScriptCandidateProgram = .empty
            timeOfDayEffectScriptAdmissionDiagnostic = failure.diagnostic
        }
        let timeOfDayEffectScriptCandidates =
            timeOfDayEffectScriptCandidateProgram.bindings
        let timeOfDayEffectScriptCandidateTargets = Set(
            timeOfDayEffectScriptCandidates.map(\.definition.target)
        )
        guard let mediaPlaybackPlaceholderFadeCandidates =
                SceneMediaPlaybackPlaceholderFadeProgramCompiler.compile(
                    descriptor: runtimeInput.renderDescriptor,
                    scriptBindings: model.sceneDocument.scriptBindings
                ) else {
            throw SceneDesktopWallpaperHostLaunchError
                .invalidBoundedSceneScriptProgramAt("media-placeholder-candidates")
        }
        let mediaPlaybackPlaceholderFadeCandidateTargets = Set(
            mediaPlaybackPlaceholderFadeCandidates.bindings.map(\.definition.target)
        )
        guard let mediaColorTransitionCandidates =
                SceneMediaColorTransitionProgramCompiler.compile(
                    descriptor: runtimeInput.renderDescriptor,
                    scriptBindings: model.sceneDocument.scriptBindings
                ) else {
            throw SceneDesktopWallpaperHostLaunchError
                .invalidBoundedSceneScriptProgramAt("media-color-candidates")
        }
        let mediaColorTransitionCandidateTargets = Set(
            mediaColorTransitionCandidates.bindings.map(\.definition.target)
        )
        let boundedProducerTargets: [(String, Set<SceneDynamicTarget>, Int)] = [
            ("launch-origin", launchOriginTransitionTargets,
             launchOriginTransitionProgram.definitions.count),
            ("hover-origin", hoverOriginTransitionTargets,
             hoverOriginTransitionProgram.definitions.count),
            ("audio-scaled", audioScaledValueTargets,
             model.audioScaledValueProgram.definitions.count),
            ("property-vector", propertyVectorScriptTargets,
             model.propertyVectorScriptProgram.definitions.count),
            ("media-placeholder", mediaPlaybackPlaceholderFadeCandidateTargets,
             mediaPlaybackPlaceholderFadeCandidates.bindings.count),
            ("media-color", mediaColorTransitionCandidateTargets,
             mediaColorTransitionCandidates.bindings.count),
        ]
        var boundedSceneScriptTargets: Set<SceneDynamicTarget> = []
        var boundedProducerConflicts: [String] = []
        for (name, targets, definitionCount) in boundedProducerTargets {
            if targets.count != definitionCount {
                boundedProducerConflicts.append("\(name)/duplicate")
            }
            if !targets.isDisjoint(with: propertyBindingTargets) {
                boundedProducerConflicts.append("\(name)/property")
            }
            if !targets.isDisjoint(with: timelineTargets) {
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
        nextSceneScriptGeneration &+= 1
        let sceneScriptScalarProgram = SceneScriptScalarProgram.compile(
            descriptor: runtimeInput.renderDescriptor,
            scriptBindings: model.sceneDocument.scriptBindings,
            excludedTargets: boundedSceneScriptTargets,
            generation: nextSceneScriptGeneration
        )
        let sceneScriptScalarTargets = Set(
            sceneScriptScalarProgram.definitions.map(\.target)
        )
        guard sceneScriptScalarTargets.count
                == sceneScriptScalarProgram.definitions.count,
              sceneScriptScalarTargets.isDisjoint(with: boundedSceneScriptTargets) else {
            throw SceneDesktopWallpaperHostLaunchError
                .invalidBoundedSceneScriptProgramAt("scalar-target-ownership")
        }
        let provenSceneScriptValueTargets = timeOfDayEffectScriptCandidateTargets
            .union(mediaPlaybackPlaceholderFadeCandidateTargets)
            .union(mediaColorTransitionCandidateTargets)
            .union(launchOriginTransitionProgram.scalarBindings.map {
                $0.definition.target
            })
            .union(sceneScriptScalarTargets)
        let resolvedMaterialAdmissionCandidates =
            SceneResolvedMaterialExecutionCapabilityAdmission.compile(
                descriptor: runtimeInput.renderDescriptor,
                authoredPlans: runtimeInput.authoredEffectRenderPlans,
                dedicatedStagePrograms: dedicatedStageLeaves,
                dynamicEffectVisibilityOwners:
                    frameDrivenEffectVisibilityOwners,
                conditionSchemaEvidence:
                    SceneGraphConditionSchemaEvidenceCompiler.compile(
                        descriptor: runtimeInput.renderDescriptor,
                        authoredPlans: runtimeInput.authoredEffectRenderPlans,
                        shaderContracts: runtimeInput.shaderContracts
                    )
            )
        let resolvedMaterialCatalog = SceneResolvedMaterialRuntimeCatalog(
            descriptor: runtimeInput.renderDescriptor,
            admissionCandidates: resolvedMaterialAdmissionCandidates,
            shaderContracts: runtimeInput.shaderContracts,
            provenSceneScriptValueTargets: provenSceneScriptValueTargets
        )
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw SceneDesktopWallpaperHostLaunchError.noSurface
        }
        let materialAssetCatalog = SceneMaterialAssetTextureCatalog(
            demands: resolvedMaterialCatalog.assetDemands,
            resourceView: model.diagnostics.resourceView,
            descriptor: runtimeInput.renderDescriptor,
            device: device
        )
        let resolvedMaterialExecutionCapabilities =
            SceneResolvedMaterialExecutionCapabilityCatalog(
                admissionCandidates: resolvedMaterialAdmissionCandidates,
                materialCatalog: resolvedMaterialCatalog,
                dynamicProducers: .init(
                    userProperties: userPropertyProducers,
                    authoredFallbackTargets: propertyBindingTargets,
                    timelineTargets: Set(timelineProgram.bindings.map(\.target)),
                    sceneScriptTargets: provenSceneScriptValueTargets
                ),
                assetFormatFacts: materialAssetCatalog.launchFormatFacts,
                assetStates: materialAssetCatalog.launchStates,
                dedicatedStageFamilies: dedicatedStageFamilies,
                dedicatedLeafKeys: dedicatedLeafKeys,
                dedicatedGraphStageKeys: dedicatedGraphStageKeys
            )
        let resolvedMaterialSubjects = resolvedMaterialExecutionCapabilities
            .runtimeDispositionOwnerships.flatMap(\.subjects)
        let verifiedXRayStockIdentityKeys =
            SceneAuthoredXRayPlanner.verifiedStockIdentityEffectKeys(
                descriptor: runtimeInput.renderDescriptor,
                shaderContracts: runtimeInput.shaderContracts
            )
        let effectAdmissionCatalog = SceneEffectAdmissionCatalog(
            descriptor: runtimeInput.renderDescriptor,
            authoredPlans: runtimeInput.authoredEffectRenderPlans,
            resolvedMaterialSubjects: resolvedMaterialSubjects,
            verifiedXRayStageKeys: verifiedXRayStockIdentityKeys
        )
        let sceneScriptConsumerTargets =
            resolvedMaterialExecutionCapabilities.sceneScriptConsumerTargets
        let timeOfDayEffectScriptConflictingTargets = propertyBindingTargets
            .union(timelineTargets)
            .union(boundedSceneScriptTargets)
            .union(sceneScriptScalarTargets)
        guard let timeOfDayEffectScriptProgram =
                SceneTimeOfDayEffectScriptProgram.validatedConsumers(
                    candidates: timeOfDayEffectScriptCandidates,
                    consumerTargets: sceneScriptConsumerTargets,
                    conflictingTargets: timeOfDayEffectScriptConflictingTargets
                ) else {
            throw SceneDesktopWallpaperHostLaunchError
                .conflictingBoundedSceneScriptTargets(
                    " phases=time-of-day/consumer-ownership"
                )
        }
        guard let mediaPlaybackPlaceholderFadeProgram =
                SceneMediaPlaybackPlaceholderFadeProgram.validated(
                    bindings: mediaPlaybackPlaceholderFadeCandidates.bindings.filter {
                        sceneScriptConsumerTargets.contains(
                            $0.definition.target
                        )
                    }
                ) else {
            throw SceneDesktopWallpaperHostLaunchError
                .invalidBoundedSceneScriptProgramAt("media-placeholder-consumers")
        }
        guard let mediaColorTransitionProgram =
                SceneMediaColorTransitionProgram.validated(
                    bindings: mediaColorTransitionCandidates.bindings.filter {
                        sceneScriptConsumerTargets.contains(
                            $0.definition.target
                        )
                    }
                ) else {
            throw SceneDesktopWallpaperHostLaunchError
                .invalidBoundedSceneScriptProgramAt("media-color-consumers")
        }
        let mediaThumbnailBindings = SceneMediaThumbnailBindingCompiler.compile(
            descriptor: runtimeInput.renderDescriptor,
            scriptBindings: model.sceneDocument.scriptBindings
        )
        try activate(SceneDesktopWallpaperLaunchContext(
            runtimeInput: runtimeInput,
            effectAdmissionCatalog: effectAdmissionCatalog,
            resolvedMaterialCatalog: resolvedMaterialCatalog,
            resolvedMaterialExecutionCapabilities:
                resolvedMaterialExecutionCapabilities,
            materialAssetCatalog: materialAssetCatalog,
            pipelineRepository: SceneImageEffectPipelineRepository(device: device),
            spriteTextureLoader: SceneMultiImageSpriteTextureLoader(),
            timelineProgram: timelineProgram,
            textScriptProgram: SceneTextScriptCompiler.compile(
                descriptor: runtimeInput.renderDescriptor
            ),
            timeOfDayEffectScriptProgram: timeOfDayEffectScriptProgram,
            timeOfDayEffectScriptAdmissionDiagnostic:
                timeOfDayEffectScriptAdmissionDiagnostic,
            mediaPlaybackPlaceholderFadeProgram:
                mediaPlaybackPlaceholderFadeProgram,
            mediaColorTransitionProgram: mediaColorTransitionProgram,
            sharedLayerAlphaProgram: model.sharedLayerAlphaProgram,
            launchOriginTransitionProgram: launchOriginTransitionProgram,
            hoverOriginTransitionProgram: hoverOriginTransitionProgram,
            audioScaledValueProgram: model.audioScaledValueProgram,
            propertyVectorScriptProgram: model.propertyVectorScriptProgram,
            sceneScriptScalarProgram: sceneScriptScalarProgram,
            mediaThumbnailBindings: mediaThumbnailBindings,
            liveState: ScenePropertyLiveUpdateState(
                program: runtimeInput.propertyBindingProgram,
                effectiveValues: runtimeInput.effectivePropertyValues,
                activeConsumerTargets: Self.activeLiveConsumerTargets(
                    in: runtimeInput.renderDescriptor,
                    resolvedMaterialExecutionCapabilities:
                        resolvedMaterialExecutionCapabilities
                )
            ),
            userPropertyTextureURLs: userPropertyTextureURLs,
            cacheDirectory: cacheDirectory,
            resourceView: model.diagnostics.resourceView,
            logURL: logURL,
            recordID: recordID
        ))
        return model
    }

}
