import Foundation
import Metal

struct SceneDesktopWallpaperLaunchContext {
    let runtimeInput: SceneRuntimeInput
    let preparedParticleAssets: SceneParticleAssetGraph
    let particleLayerIDs: Set<Int>
    let particleVisibilityRequirements: [Int: Set<Int>]
    var preparedParticleVisibilityLayerIDs: Set<Int> {
        Set(particleVisibilityRequirements.values.joined())
    }
    let effectAdmissionCatalog: SceneEffectAdmissionCatalog
    let resolvedMaterialCatalog: SceneResolvedMaterialRuntimeCatalog
    let resolvedMaterialExecutionCapabilities:
        SceneResolvedMaterialExecutionCapabilityCatalog
    let materialAssetCatalog: SceneMaterialAssetTextureCatalog
    let stockNoiseTextures: SceneStockNoiseTextureStore
    let preparedDeviceResources: ScenePreparedDeviceResources
    let preparedFirstSurfaceRuntime: ScenePreparedFirstSurfaceRuntime
    let timelineProgram: SceneTimelineProgram
    let timelinePlaybackRuntime: SceneTimelinePlaybackRuntime
    let textureAnimationPlaybackRuntime: SceneTextureAnimationPlaybackRuntime
    let puppetAnimationPlaybackRuntime: ScenePuppetAnimationPlaybackRuntime
    let textScriptProgram: SceneTextScriptProgram
    let sharedLayerAlphaProgram: SceneSharedLayerAlphaProgram
    let sceneScriptCursorProgram: SceneScriptCursorProgram
    let propertyVectorScriptProgram: SceneScriptVectorProgram
    let propertyVectorPassCandidateTargets: Set<SceneDynamicTarget>
    let propertyVectorPassConsumerTargets: Set<SceneDynamicTarget>
    let propertyVectorPassFailedTargets: Set<SceneDynamicTarget>
    let propertyVectorMediaTargets: Set<SceneDynamicTarget>
    let sceneScriptFallbackDefinitions: [SceneDynamicTargetDefinition]
    let sceneScriptVectorMediaRoute: SceneScriptVectorMediaRouteState
    let sceneScriptScalarProgram: SceneScriptScalarProgram
    let sceneScriptSourceEvidence: [SceneScriptSourceEvidenceIR]
    let sceneScriptStringProgram: SceneScriptStringProgram
    let sceneScriptDynamicLayerRuntime: SceneScriptDynamicLayerRuntime
    let sceneScriptStorageSession: SceneScriptLocalStorageSession?
    let frameSchema: SceneDesktopWallpaperLaunchFrameSchema
    var sceneScriptStatefulTargets: Set<SceneDynamicTarget> {
        frameSchema.sceneScriptStatefulTargets
    }
    var dynamicDefinitions: [SceneDynamicTargetDefinition] {
        frameSchema.dynamicDefinitions
    }
    var dynamicDefinitionIndex: SceneDynamicSnapshotDefinitionIndex {
        frameSchema.dynamicDefinitionIndex
    }
    let baseMaterialProviderBindings: SceneBaseMaterialProviderBindingProgram
    let soundPlaybackProgram: SceneSoundPlaybackProgram
    var liveState: ScenePropertyLiveUpdateState
    var userPropertyTextureLoad: SceneUserPropertyTextureLoadResult
    let privateMediaCacheDirectory: URL
    let resourceView: SceneResourceView
    let logURL: URL?
    let recordID: String?
    let capturesExecutionObservations: Bool
    var userShortcuts: ScenePlaybackShortcutConfiguration = .empty
    var userShortcutKeys: Set<String> = []

    var requiresSystemMedia: Bool {
        !propertyVectorScriptProgram.mediaOwnerRegistrations.isEmpty
            || !sceneScriptScalarProgram.mediaOwnerRegistrations.isEmpty
            || !sceneScriptStringProgram.mediaOwnerRegistrations.isEmpty
            || textScriptProgram.bindings.contains { $0.profile == .ecmaMediaPropertiesChangedSubset }
            || !baseMaterialProviderBindings.systemProviderDemands.isEmpty
            || resolvedMaterialCatalog.systemProviderDemands.contains {
                $0.name == SceneBaseMaterialProviderBindingProgram.currentIdentity
                    || $0.name == SceneBaseMaterialProviderBindingProgram.previousIdentity
            }
    }

    func makeResolvedMaterialRuntime() -> SceneResolvedMaterialRuntimeBridge {
        preparedFirstSurfaceRuntime.take() ?? ScenePreparedDeviceResources.makeMaterialRuntime(
            catalog: resolvedMaterialCatalog,
            capabilities: resolvedMaterialExecutionCapabilities,
            assets: materialAssetCatalog,
            device: preparedDeviceResources.device,
            capturesExecutionObservations: capturesExecutionObservations
        )
    }
}
