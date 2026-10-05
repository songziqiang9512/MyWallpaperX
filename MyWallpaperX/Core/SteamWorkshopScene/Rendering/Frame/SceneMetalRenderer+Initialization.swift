import Foundation
import Metal
import QuartzCore
import simd

extension SceneMetalRenderer {
    var hasPreparedReflectionConsumers: Bool {
        if baseMaterialProviderBindings.lightingProfileByLayerID.values.contains(where: {
            $0.reflection != nil
        }) {
            return true
        }
        guard let runtime = imageCompositor.resolvedMaterialRuntime else { return false }
        return runtime.executionLayerIDs.contains {
            runtime.requiresSceneEnvironment(layerID: $0)
        }
    }

    init?(
        renderDescriptor: SceneRenderDescriptor,
        effectAdmissionCatalog: SceneEffectAdmissionCatalog,
        baseMaterialProviderBindings: SceneBaseMaterialProviderBindingProgram = .empty,
        stockNoiseTextures: SceneStockNoiseTextureStore = .empty,
        staticModelResources: ScenePreparedStaticModelResources = .empty,
        hasDynamicBloom: Bool = false,
        instantiatedSceneScriptTargets: Set<SceneDynamicTarget> = [],
        scriptSourceEvidence: [SceneScriptSourceEvidenceIR] = [],
        pipelineRepository: SceneImageEffectPipelineRepository,
        resolvedMaterialRuntime: SceneResolvedMaterialRuntimeBridge? = nil
    ) {
        let device = pipelineRepository.device
        guard stockNoiseTextures.deviceRegistryID == nil
            || stockNoiseTextures.deviceRegistryID == device.registryID else { return nil }
        guard let commandQueue = device.makeCommandQueue() else {
            return nil
        }
        self.device = device
        self.commandQueue = commandQueue
        self.renderDescriptor = renderDescriptor
        self.bloomPostProcess = (renderDescriptor.camera.bloom.enabled || hasDynamicBloom)
            ? SceneBloomPostProcess(
                device: device,
                pixelFormat: renderDescriptor.colorTargetFormat.metalPixelFormat,
                hdrEnabled: renderDescriptor.camera.bloom.hdr != nil
            ) : nil
        // Both HDR routes map a distinct opaque source; accumulating scenes
        // retain raw scene color through the existing submission coordinator.
        self.displayMappingPostProcess = SceneDisplayMappingPostProcess(
            device: device,
            pixelFormat: renderDescriptor.colorTargetFormat.metalPixelFormat,
            hdrEnabled: renderDescriptor.hdrEnabled
        )
        self.baseMaterialProviderBindings = baseMaterialProviderBindings
        self.stockNoiseTextures = stockNoiseTextures
        self.staticModelResources = staticModelResources
        self.pipelineRepository = pipelineRepository
        if baseMaterialProviderBindings.lightingProfileByLayerID.values
            .contains(where: \.surfaceEnabled) {
            _ = pipelineRepository.prepareLitImageLayer()
        }
        self.imageCompositor = SceneImageLayerCompositor(
            pipelineRepository: pipelineRepository,
            resolvedMaterialRuntime: resolvedMaterialRuntime
        )
        let visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(in: renderDescriptor)
        self.visibleLayerIDs = visibleLayerIDs
        self.effectAdmissionCatalog = effectAdmissionCatalog
        self.spotLightRuntime = SceneSpotLightRuntime(
            descriptor: renderDescriptor,
            instantiatedSceneScriptTargets: instantiatedSceneScriptTargets,
            scriptSourceEvidence: scriptSourceEvidence,
            pipeline: pipelineRepository.spotLight()
        )
        let resolvedMaterialLayerIDs = resolvedMaterialRuntime?.executionLayerIDs ?? []
        let resolvedMaterialVisibleRootLayerIDs =
            resolvedMaterialRuntime?.visibleExecutionRootLayerIDs ?? []
        let executableUtilityConsumerLayerIDs = SceneUtilityLayerRuntimePlanner
            .executableUtilityConsumerLayerIDs(
                in: renderDescriptor,
                resolvedMaterialLayerIDs: resolvedMaterialLayerIDs
            )
        let dependencyRuntime = SceneDependencyFrameRuntime(
            descriptor: renderDescriptor,
            visibleLayerIDs:
                visibleLayerIDs.union(resolvedMaterialVisibleRootLayerIDs),
            executableUtilityConsumerLayerIDs: executableUtilityConsumerLayerIDs,
            verifiedXRayStageKeys: effectAdmissionCatalog.verifiedXRayStageKeys,
            admittedResolvedMaterialReferences: resolvedMaterialRuntime?
                .admittedResolvedMaterialReferences ?? [],
            device: device
        )
        self.dependencyRuntime = dependencyRuntime
        let utilityPlans = SceneUtilityLayerRuntimePlanner.plans(
            in: renderDescriptor,
            dependencyPlan: dependencyRuntime.plan,
            resolvedMaterialLayerIDs: resolvedMaterialLayerIDs
        )
        let utilityExecution = SceneUtilityLayerRuntimePlanner.execution(
            in: renderDescriptor, plans: utilityPlans
        )
        self.utilityExecution = utilityExecution
        let preparationLayerIDs = dependencyRuntime
            .resolvedMaterialPreparationOrder(
                authoredLayerIDs: utilityExecution.orderedLayerIDs
            )
        let byID = Dictionary(
            uniqueKeysWithValues: renderDescriptor.layers.map { ($0.id, $0) }
        )
        self.authoredLayers = utilityExecution.orderedLayerIDs.compactMap {
            byID[$0]
        }
        self.resolvedMaterialPreparationLayerIDs = preparationLayerIDs
        self.resolvedMaterialPreparationLayers = preparationLayerIDs.flatMap { ids in
            let layers = ids.compactMap { byID[$0] }
            return layers.count == ids.count ? layers : nil
        }
        self.layersByID = byID
        self.lightLayerIDs = SceneLightSnapshot.orderedLightLayerIDs(
            descriptor: renderDescriptor,
            layersByID: byID
        )
        let worldFramesByLayerID = SceneLayerWorldFrameResolver.compute(
            descriptor: renderDescriptor,
            byID: byID
        )
        self.worldFramesByLayerID = worldFramesByLayerID
        self.parallaxByLayerID = SceneLayerParallax.resolveAll(layersByID: byID)
    }
}
