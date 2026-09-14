import Foundation
import Metal
import QuartzCore
import simd

extension SceneMetalRenderer {
    init?(
        renderDescriptor: SceneRenderDescriptor,
        effectAdmissionCatalog: SceneEffectAdmissionCatalog,
        baseMaterialProviderBindings: SceneBaseMaterialProviderBindingProgram = .empty,
        staticModelResources: ScenePreparedStaticModelResources = .empty,
        pipelineRepository: SceneImageEffectPipelineRepository,
        resolvedMaterialRuntime: SceneResolvedMaterialRuntimeBridge? = nil
    ) {
        let device = pipelineRepository.device
        guard let commandQueue = device.makeCommandQueue() else {
            return nil
        }
        self.device = device
        self.commandQueue = commandQueue
        self.renderDescriptor = renderDescriptor
        self.baseMaterialProviderBindings = baseMaterialProviderBindings
        self.staticModelResources = staticModelResources
        self.pipelineRepository = pipelineRepository
        self.imageCompositor = SceneImageLayerCompositor(
            pipelineRepository: pipelineRepository,
            resolvedMaterialRuntime: resolvedMaterialRuntime
        )
        let visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(in: renderDescriptor)
        self.visibleLayerIDs = visibleLayerIDs
        self.effectAdmissionCatalog = effectAdmissionCatalog
        self.spotLightRuntime = SceneSpotLightRuntime(
            descriptor: renderDescriptor,
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
        let preparationLayerIDs = dependencyRuntime
            .resolvedMaterialPreparationOrder(
                authoredLayerIDs: renderDescriptor.renderOrderLayerIDs
            )
        let byID = Dictionary(
            uniqueKeysWithValues: renderDescriptor.layers.map { ($0.id, $0) }
        )
        self.authoredLayers = renderDescriptor.renderOrderLayerIDs.compactMap {
            byID[$0]
        }
        self.resolvedMaterialPreparationLayerIDs = preparationLayerIDs
        self.resolvedMaterialPreparationLayers = preparationLayerIDs.flatMap { ids in
            let layers = ids.compactMap { byID[$0] }
            return layers.count == ids.count ? layers : nil
        }
        self.layersByID = byID
        self.lightLayerIDs = renderDescriptor.layers.compactMap { layer in
            layer.spotLight != nil || layer.directionalLight != nil
                ? layer.id : nil
        }
        let utilityPlans = SceneUtilityLayerRuntimePlanner.plans(
            in: renderDescriptor,
            executableUtilityConsumerLayerIDs: executableUtilityConsumerLayerIDs,
            resolvedMaterialLayerIDs: resolvedMaterialLayerIDs,
            admittedResolvedMaterialReferences: resolvedMaterialRuntime?
                .admittedResolvedMaterialReferences ?? []
        )
        self.utilityPlansByTriggerLayerID = Dictionary(
            grouping: utilityPlans.values.filter(\.shouldCapture),
            by: \.triggerLayerID
        )
        self.utilityCaptureLayerIDs = Set(
            utilityPlans.values.filter(\.shouldCapture).map(\.layerID)
        )
        let worldFramesByLayerID = SceneLayerWorldFrameResolver.compute(
            descriptor: renderDescriptor,
            byID: byID
        )
        self.worldFramesByLayerID = worldFramesByLayerID
        self.parallaxByLayerID = SceneLayerParallax.resolveAll(layersByID: byID)
    }
}
