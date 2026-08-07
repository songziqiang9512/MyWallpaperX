import Foundation
import Metal

struct SceneDesktopWallpaperLaunchContext {
    let runtimeInput: SceneRuntimeInput
    let authoredEffectCatalog: SceneAuthoredEffectExecutionCatalog
    let resolvedMaterialCatalog: SceneResolvedMaterialRuntimeCatalog
    let resolvedMaterialExecutionCapabilities:
        SceneResolvedMaterialExecutionCapabilityCatalog
    let materialAssetCatalog: SceneMaterialAssetTextureCatalog
    let pipelineRepository: SceneImageEffectPipelineRepository
    let spriteTextureLoader: SceneMultiImageSpriteTextureLoader
    let timelineProgram: SceneTimelineProgram
    let textScriptProgram: SceneTextScriptProgram
    let timeOfDayEffectScriptProgram: SceneTimeOfDayEffectScriptProgram
    let sceneScriptAudioBarsProgram: SceneScriptAudioBarsProgram
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
                + " reason=snapshot-lifecycle-unproven"
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
    case noSurface

    var errorDescription: String? {
        switch self {
        case .missingPackageCache:
            "Scene 资源缓存不可用。"
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
        let sceneScriptAudioBarsProgram = SceneScriptAudioBarsCompiler.compile(
            descriptor: runtimeInput.renderDescriptor,
            shaderContracts: runtimeInput.shaderContracts
        )
        typealias VisibilityOwner =
            SceneResolvedMaterialExecutionCapabilityAdmission
                .DynamicEffectVisibilityOwner
        var dynamicEffectVisibilityOwners = Set<VisibilityOwner>()
        for definition in runtimeInput.propertyBindingProgram.definitions {
            guard case let .effectVisibility(layerID, effectIndex) =
                    definition.target else { continue }
            dynamicEffectVisibilityOwners.insert(.init(
                layerID: layerID,
                effectIndex: effectIndex
            ))
        }
        for binding in timelineProgram.bindings {
            guard case let .effectVisibility(layerID, effectIndex) =
                    binding.definition.target else { continue }
            dynamicEffectVisibilityOwners.insert(.init(
                layerID: layerID,
                effectIndex: effectIndex
            ))
        }
        for binding in model.sceneDocument.scriptBindings {
            guard binding.owner.kind == .effect,
                  binding.targetKey == "visible",
                  let layerID = binding.owner.objectID,
                  let effectIndex = binding.owner.effectIndex else { continue }
            dynamicEffectVisibilityOwners.insert(.init(
                layerID: layerID,
                effectIndex: effectIndex
            ))
        }
        let dedicatedStageLeaves = runtimeInput.authoredEffectRenderPlans.flatMap {
            SceneAuthoredEffectChainPlanner.compileDedicatedLeaves(
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
        let resolvedMaterialAdmissionCandidates =
            SceneResolvedMaterialExecutionCapabilityAdmission.compile(
                descriptor: runtimeInput.renderDescriptor,
                authoredPlans: runtimeInput.authoredEffectRenderPlans,
                dedicatedStagePrograms: dedicatedStageLeaves,
                dynamicEffectVisibilityOwners: dynamicEffectVisibilityOwners,
                specializedLayerIDs: Set(
                    sceneScriptAudioBarsProgram.plans.map(\.layerID)
                )
            )
        let resolvedMaterialCatalog = SceneResolvedMaterialRuntimeCatalog(
            descriptor: runtimeInput.renderDescriptor,
            admissionCandidates: resolvedMaterialAdmissionCandidates,
            shaderContracts: runtimeInput.shaderContracts
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
                    sceneScriptTargets: []
                ),
                dedicatedStageFamilies: dedicatedStageFamilies,
                dedicatedLeafKeys: dedicatedLeafKeys
            )
        let resolvedMaterialSubjects = resolvedMaterialExecutionCapabilities
            .runtimeDispositionOwnerships.flatMap(\.subjects)
        let authoredEffectCatalog = SceneAuthoredEffectExecutionCatalog(
            descriptor: runtimeInput.renderDescriptor,
            authoredPlans: runtimeInput.authoredEffectRenderPlans,
            shaderContracts: runtimeInput.shaderContracts,
            resolvedMaterialSubjects: resolvedMaterialSubjects
        )
        let timeOfDayEffectScriptProgram = SceneTimeOfDayEffectScriptProgram(
            bindings: authoredEffectCatalog.chainsByLayerID.keys.sorted().flatMap { layerID in
                authoredEffectCatalog.chainsByLayerID[layerID]?
                    .executionStages.compactMap {
                        $0.blend?.dynamicMultiplyBinding
                    } ?? []
            }
        )
        let currentMediaThumbnailBindings = SceneMediaThumbnailBindingCompiler.compile(
            descriptor: runtimeInput.renderDescriptor,
            scriptBindings: model.sceneDocument.scriptBindings
        )
        let mediaThumbnailBindings = SceneMediaThumbnailTransitionCompiler.compile(
            descriptor: runtimeInput.renderDescriptor,
            shaderContracts: runtimeInput.shaderContracts,
            currentProgram: currentMediaThumbnailBindings
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
        try activate(SceneDesktopWallpaperLaunchContext(
            runtimeInput: runtimeInput,
            authoredEffectCatalog: authoredEffectCatalog,
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
            sceneScriptAudioBarsProgram: sceneScriptAudioBarsProgram,
            mediaThumbnailBindings: mediaThumbnailBindings,
            liveState: ScenePropertyLiveUpdateState(
                program: runtimeInput.propertyBindingProgram,
                effectiveValues: runtimeInput.effectivePropertyValues,
                activeConsumerTargets: Self.activeLiveConsumerTargets(
                    in: runtimeInput.renderDescriptor,
                    authoredEffectCatalog: authoredEffectCatalog
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
