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
    let privateMediaCacheDirectory: URL
    let resourceView: SceneResourceView
    let logURL: URL?
    let recordID: String?
    let capturesExecutionObservations: Bool
    var userShortcuts: ScenePlaybackShortcutConfiguration = .empty
    var userShortcutKeys: Set<String> = []

    func requiresSystemMedia(excludingLayerIDs: Set<Int>) -> Bool {
        !propertyVectorScriptProgram.mediaOwnerRegistrations.isEmpty
            || !sceneScriptScalarProgram.mediaOwnerRegistrations.isEmpty
            || !sceneScriptStringProgram.mediaOwnerRegistrations.isEmpty
            || baseMaterialProviderBindings.baseMaterialBindings.values.contains {
                !excludingLayerIDs.contains($0.layerID) && $0.provider.isSystemProvider
            }
            || resolvedMaterialExecutionCapabilities.systemProviderConsumerLayerIDs.contains { provider, layerIDs in
                (provider.name == SceneBaseMaterialProviderBindingProgram.currentIdentity
                    || provider.name == SceneBaseMaterialProviderBindingProgram.previousIdentity)
                    && !layerIDs.subtracting(excludingLayerIDs).isEmpty
            }
    }

    func makeSurfacePreparationInput(
        dynamicValues: SceneDynamicSnapshot,
        particlePlayback: [Int: SceneParticlePlaybackSnapshot],
        destroyedAuthoredLayerIDs: Set<Int>,
        audioInput: SceneParticleAudioInput
    ) -> SceneSurfacePreparationInput {
        SceneSurfacePreparationInput(
            descriptor: runtimeInput.renderDescriptor,
            particleAssets: preparedParticleAssets,
            baseImages: preparedDeviceResources.baseImages,
            device: preparedDeviceResources.device,
            visibilityLayerIDs: preparedParticleVisibilityLayerIDs,
            dynamicValues: dynamicValues, particlePlayback: particlePlayback,
            destroyedLayerIDs: destroyedAuthoredLayerIDs, audioInput: audioInput,
            materialCatalog: resolvedMaterialCatalog,
            materialCapabilities: resolvedMaterialExecutionCapabilities,
            materialAssets: materialAssetCatalog,
            firstMaterialRuntime: preparedFirstSurfaceRuntime.take(),
            capturesExecutionObservations: capturesExecutionObservations
        )
    }

}

struct SceneSurfacePreparationInput {
    let descriptor: SceneRenderDescriptor
    let particleAssets: SceneParticleAssetGraph
    let baseImages: ScenePreparedBaseImageResources
    let device: MTLDevice
    let visibilityLayerIDs: Set<Int>
    let dynamicValues: SceneDynamicSnapshot
    let particlePlayback: [Int: SceneParticlePlaybackSnapshot]
    let destroyedLayerIDs: Set<Int>
    let audioInput: SceneParticleAudioInput
    let materialCatalog: SceneResolvedMaterialRuntimeCatalog
    let materialCapabilities: SceneResolvedMaterialExecutionCapabilityCatalog
    let materialAssets: SceneMaterialAssetTextureCatalog
    let firstMaterialRuntime: SceneResolvedMaterialRuntimeBridge?
    let capturesExecutionObservations: Bool

    func prepare(displayIDs: [CGDirectDisplayID], cancellation: SceneWallpaperLaunchCancellation?)
        throws -> [SceneDesktopWallpaperSession.PreparedSurface] {
        try cancellation?.check()
        let layerImage = baseImages.particleLayerImageCompilation(
            descriptor: descriptor, destroyedIDs: destroyedLayerIDs)
        var prepared: [SceneDesktopWallpaperSession.PreparedSurface] = []
        do {
            for displayID in displayIDs {
                try cancellation?.check()
                let playback = SceneParticlePlaybackState(
                    descriptor: descriptor, preparedAssets: particleAssets,
                    device: device, textureLoader: baseImages.textureLoader,
                    layerImage: layerImage,
                    preparedParticleVisibilityLayerIDs: visibilityLayerIDs,
                    initialDynamicValues: dynamicValues, initialPlayback: particlePlayback,
                    initialAudioInput: audioInput,
                    destroyedAuthoredLayerIDs: destroyedLayerIDs,
                    shouldCancelPrewarm: { cancellation?.isCancelled == true })
                let material = prepared.isEmpty ? firstMaterialRuntime : nil
                prepared.append(.init(displayID: displayID, playback: playback,
                    materialRuntime: material ?? ScenePreparedDeviceResources.makeMaterialRuntime(
                        catalog: materialCatalog, capabilities: materialCapabilities,
                        assets: materialAssets, device: device,
                        capturesExecutionObservations: capturesExecutionObservations)))
                try cancellation?.check()
            }
            return prepared
        } catch {
            for surface in prepared { _ = surface.playback.teardown(reason: "preparationCancelled") }
            throw error
        }
    }
}

/// Prepares exactly one surface-scoped resolved-material runtime while the
/// launch worker continues compiling SceneScript Programs. The prepared
/// runtime is consumed by the first surface only; later displays still receive
/// independent graph/history/epoch owners.
final class ScenePreparedFirstSurfaceRuntime {
    private let lock = NSLock()
    private var runtime: SceneResolvedMaterialRuntimeBridge?

    init(_ runtime: SceneResolvedMaterialRuntimeBridge) {
        self.runtime = runtime
    }

    func take() -> SceneResolvedMaterialRuntimeBridge? {
        lock.lock()
        defer { lock.unlock() }
        let value = runtime
        runtime = nil
        return value
    }
}
