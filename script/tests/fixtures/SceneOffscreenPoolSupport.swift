
import Foundation
import Metal

struct SceneEffectStageExecutionPlan {
    let layerID: Int
    let renderGraph: SceneAuthoredEffectRenderPlan
    let materialNodeCount: Int
    let logicalRenderTargetCount: Int
    let requiresExactInputExtent: Bool
    let inputRole: SceneAuthoredEffectInputRole

    var authoredShader: Int? {
        renderGraph.effects.first?.definitionPath.contains("/direct/") == true ? 1 : nil
    }
    var supportsUnifiedFullFrameComposeStage: Bool { false }
}

nonisolated enum SceneTextureLoadPurpose: Hashable, Sendable {
    case premultipliedColor
    case straightAlbedo
    case preservedChannels
    case mask
    case noise
    case flow
    case phase
    case normal
    case depth
    case lookupTable
}

nonisolated enum SceneFrameTextureIdentity: Hashable {
    case graph(SceneAuthoredEffectRenderPlan.TextureIdentity)
}

struct SceneTextureProviderPublication {
    let requestIdentity: SceneFrameTextureIdentity
    let candidate: SceneTextureCandidate
    let contentGeneration: UInt64
}

struct SceneFrameTextureResource {
    let publication: SceneTextureProviderPublication
    let resourceGeneration: UInt64

    var isCompleteGraphResource: Bool {
        resourceGeneration > 0
            && resourceGeneration == publication.contentGeneration
    }
}

nonisolated enum SceneResolvedMaterialExecutionCapabilityCatalog {
    struct Token: Hashable {}
}

extension SceneLayerGraphTargetPlan {
    static func make(
        plans: [SceneGraphRenderTargetPlan],
        pairPlan: SceneLayerFullFramePairPlan,
        byteBudget: Int,
        pairStorage: FullFramePairStorage = .owned
    ) -> Result<Self, Failure> {
        make(
            plans: plans,
            pairPlan: pairPlan,
            byteBudget: byteBudget,
            pairStorage: pairStorage,
            makeInputsDigests: Array(repeating: 0, count: plans.count)
        )
    }
}

extension SceneOffscreenTexturePool {
    func preparePersistentGraphTargets(
        admittedGraphs: [SceneAuthoredEffectRenderPlan],
        materialFunctionTargetsByEffect: [
            SceneAuthoredEffectRenderPlan.EffectKey:
                Set<SceneAuthoredEffectRenderPlan.TextureIdentity>
        ] = [:],
        pairPlan: SceneLayerFullFramePairPlan,
        extentPolicy: SceneFullFrameExtentPolicy = .standard,
        requestedWidth: Int,
        requestedHeight: Int,
        usesSharedFullFrameWorkingPair: Bool = false,
        orderingContext: SceneGraphCommandQueueOrderingContext? = nil
    ) -> ScenePreparedPersistentGraphTargets? {
        guard let plan = framePlanForPersistentGraphTargets(
            admittedGraphs: admittedGraphs,
            materialFunctionTargetsByEffect: materialFunctionTargetsByEffect,
            pairPlan: pairPlan,
            extentPolicy: extentPolicy,
            requestedWidth: requestedWidth,
            requestedHeight: requestedHeight,
            usesSharedFullFrameWorkingPair: usesSharedFullFrameWorkingPair,
            orderingContext: orderingContext
        ) else { return nil }
        return preparePersistentGraphTargets(framePlan: plan)
    }
}

