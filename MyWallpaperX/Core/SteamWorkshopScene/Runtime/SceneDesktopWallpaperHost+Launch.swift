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
    let mediaPlaybackPlaceholderFadeProgram:
        SceneMediaPlaybackPlaceholderFadeProgram
    let mediaColorTransitionProgram: SceneMediaColorTransitionProgram
    let launchOriginTransitionProgram: SceneLaunchOriginTransitionProgram
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
            "resolved material system providers: schema=r3-system-provider-v1"
                + " demands=\(resolvedMaterialCatalog.systemProviderDemands.count)"
                + " missingState=unavailable"
                + " reason=snapshot-lifecycle-unproven",
            "scene media placeholder fade: schema=bounded-playback-fade-v1"
                + " bindings=\(mediaPlaybackPlaceholderFadeProgram.bindings.count)"
                + " input=typed-inbox liveProvider=unavailable initialMode=stopped",
            "scene media color transition: schema=bounded-secondary-color-v1"
                + " bindings=\(mediaColorTransitionProgram.bindings.count)"
                + " input=typed-inbox liveProvider=unavailable",
            "scene launch origin transition: schema=bounded-shared-origin-v1"
                + " cohorts=\(launchOriginTransitionProgram.cohorts.count)"
                + " bindings=\(launchOriginTransitionProgram.bindings.count)"
                + " layerIDs=\(launchOriginTransitionProgram.layerIDs)"
                + " interaction=unavailable"
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
    case invalidBoundedSceneScriptProgram
    case noSurface

    var errorDescription: String? {
        switch self {
        case .missingPackageCache:
            "Scene 资源缓存不可用。"
        case .invalidBoundedSceneScriptProgram:
            "Scene 有界脚本目标存在冲突，已停止启动。"
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
        guard launchOriginTransitionTargets.count
                == launchOriginTransitionProgram.definitions.count,
              launchOriginTransitionTargets.isDisjoint(with: Set(
            runtimeInput.propertyBindingProgram.definitions.map(\.target)
        )), launchOriginTransitionTargets.isDisjoint(with: Set(
            timelineProgram.bindings.map(\.target)
        )) else {
            throw SceneDesktopWallpaperHostLaunchError.invalidBoundedSceneScriptProgram
        }
        typealias VisibilityOwner =
            SceneResolvedMaterialExecutionCapabilityAdmission
                .DynamicEffectVisibilityOwner
        // User-property visibility stays live for typed consumers; otherwise
        // live-state rejects atomically and the service relaunches the Scene.
        // Admission only blocks frame-driven topology changes here.
        var frameDrivenEffectVisibilityOwners = Set<VisibilityOwner>()
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
                  let effectIndex = binding.owner.effectIndex else { continue }
            frameDrivenEffectVisibilityOwners.insert(.init(
                layerID: layerID,
                effectIndex: effectIndex
            ))
        }
        let dedicatedStageLeaves = runtimeInput.authoredEffectRenderPlans.flatMap {
            SceneEffectProgramCompiler.compileDedicatedLeaves(
                graph: $0,
                descriptor: runtimeInput.renderDescriptor,
                shaderContracts: runtimeInput.shaderContracts
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
            $0.executionPlan.supportsUnifiedLogicalTargetStage ? $0.effectKey : nil
        })
        let dedicatedFullFrameComposeStageKeys = Set(
            dedicatedStageLeaves.compactMap {
                $0.executionPlan.supportsUnifiedFullFrameComposeStage
                    ? $0.effectKey : nil
            }
        )
        let timeOfDayEffectScriptCandidates = dedicatedStageLeaves.compactMap {
            $0.executionPlan.blend?.dynamicMultiplyBinding
        }
        let timeOfDayEffectScriptCandidateTargets = Set(
            timeOfDayEffectScriptCandidates.map(\.definition.target)
        )
        guard let mediaPlaybackPlaceholderFadeCandidates =
                SceneMediaPlaybackPlaceholderFadeProgramCompiler.compile(
                    descriptor: runtimeInput.renderDescriptor,
                    scriptBindings: model.sceneDocument.scriptBindings
                ) else {
            throw SceneDesktopWallpaperHostLaunchError.invalidBoundedSceneScriptProgram
        }
        let mediaPlaybackPlaceholderFadeCandidateTargets = Set(
            mediaPlaybackPlaceholderFadeCandidates.bindings.map(\.definition.target)
        )
        guard let mediaColorTransitionCandidates =
                SceneMediaColorTransitionProgramCompiler.compile(
                    descriptor: runtimeInput.renderDescriptor,
                    scriptBindings: model.sceneDocument.scriptBindings
                ) else {
            throw SceneDesktopWallpaperHostLaunchError.invalidBoundedSceneScriptProgram
        }
        let mediaColorTransitionCandidateTargets = Set(
            mediaColorTransitionCandidates.bindings.map(\.definition.target)
        )
        guard timeOfDayEffectScriptCandidateTargets.isDisjoint(
            with: mediaPlaybackPlaceholderFadeCandidateTargets
        ), timeOfDayEffectScriptCandidateTargets.isDisjoint(
            with: mediaColorTransitionCandidateTargets
        ), mediaPlaybackPlaceholderFadeCandidateTargets.isDisjoint(
            with: mediaColorTransitionCandidateTargets
        ) else {
            throw SceneDesktopWallpaperHostLaunchError.invalidBoundedSceneScriptProgram
        }
        let provenSceneScriptValueTargets = timeOfDayEffectScriptCandidateTargets
            .union(mediaPlaybackPlaceholderFadeCandidateTargets)
            .union(mediaColorTransitionCandidateTargets)
        let resolvedMaterialAdmissionCandidates =
            SceneResolvedMaterialExecutionCapabilityAdmission.compile(
                descriptor: runtimeInput.renderDescriptor,
                authoredPlans: runtimeInput.authoredEffectRenderPlans,
                dedicatedStagePrograms: dedicatedStageLeaves,
                dynamicEffectVisibilityOwners:
                    frameDrivenEffectVisibilityOwners
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
                    userProperties: Set(
                        runtimeInput.propertyBindingProgram.instructions.map {
                            .init(
                                propertyKey: $0.propertyKey,
                                target: $0.target
                            )
                        }
                    ),
                    timelineTargets: Set(timelineProgram.bindings.map(\.target)),
                    sceneScriptTargets: provenSceneScriptValueTargets
                ),
                assetFormatFacts: materialAssetCatalog.launchFormatFacts,
                assetStates: materialAssetCatalog.launchStates,
                dedicatedStageFamilies: dedicatedStageFamilies,
                dedicatedLeafKeys: dedicatedLeafKeys,
                dedicatedGraphStageKeys: dedicatedGraphStageKeys,
                dedicatedFullFrameComposeStageKeys:
                    dedicatedFullFrameComposeStageKeys
            )
        let resolvedMaterialSubjects = resolvedMaterialExecutionCapabilities
            .runtimeDispositionOwnerships.flatMap(\.subjects)
        let effectAdmissionCatalog = SceneEffectAdmissionCatalog(
            descriptor: runtimeInput.renderDescriptor,
            authoredPlans: runtimeInput.authoredEffectRenderPlans,
            resolvedMaterialSubjects: resolvedMaterialSubjects
        )
        let sceneScriptConsumerTargets =
            resolvedMaterialExecutionCapabilities.sceneScriptConsumerTargets
        let timeOfDayEffectScriptProgram = SceneTimeOfDayEffectScriptProgram(
            bindings: timeOfDayEffectScriptCandidates.filter {
                sceneScriptConsumerTargets.contains($0.definition.target)
            }.sorted { lhs, rhs in
                guard case let .effectConstant(
                    lhsLayer, lhsEffect, lhsPass, lhsName
                ) = lhs.definition.target,
                    case let .effectConstant(
                        rhsLayer, rhsEffect, rhsPass, rhsName
                    ) = rhs.definition.target else { return false }
                if lhsLayer != rhsLayer { return lhsLayer < rhsLayer }
                if lhsEffect != rhsEffect { return lhsEffect < rhsEffect }
                if lhsPass != rhsPass { return lhsPass < rhsPass }
                return lhsName < rhsName
            }
        )
        guard let mediaPlaybackPlaceholderFadeProgram =
                SceneMediaPlaybackPlaceholderFadeProgram.validated(
                    bindings: mediaPlaybackPlaceholderFadeCandidates.bindings.filter {
                        sceneScriptConsumerTargets.contains(
                            $0.definition.target
                        )
                    }
                ) else {
            throw SceneDesktopWallpaperHostLaunchError.invalidBoundedSceneScriptProgram
        }
        guard let mediaColorTransitionProgram =
                SceneMediaColorTransitionProgram.validated(
                    bindings: mediaColorTransitionCandidates.bindings.filter {
                        sceneScriptConsumerTargets.contains(
                            $0.definition.target
                        )
                    }
                ) else {
            throw SceneDesktopWallpaperHostLaunchError.invalidBoundedSceneScriptProgram
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
            mediaPlaybackPlaceholderFadeProgram:
                mediaPlaybackPlaceholderFadeProgram,
            mediaColorTransitionProgram: mediaColorTransitionProgram,
            launchOriginTransitionProgram: launchOriginTransitionProgram,
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
