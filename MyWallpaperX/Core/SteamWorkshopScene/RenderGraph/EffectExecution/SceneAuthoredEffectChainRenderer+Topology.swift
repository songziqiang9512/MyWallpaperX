import Foundation
import Metal

extension SceneAuthoredEffectChainRenderer {
    enum StagePreparation {
        case ready(PreparedStage)
        case rejected(reason: String)
    }

    struct PreparedStage {
        let stage: SceneAuthoredEffectExecutionPlan
        let sourceTexture: MTLTexture
        let targets: SceneGraphRenderTargetTable
        let inputs: SceneResolvedMaterialRuntimeBridge.DedicatedFrameInputs
        let sourcePipeline: SceneImageLayerPipeline
        let time: Float
    }

    static func prepareStage(
        _ stage: SceneAuthoredEffectExecutionPlan,
        sourceTexture: MTLTexture,
        targets: SceneGraphRenderTargetTable,
        inputs: SceneResolvedMaterialRuntimeBridge.DedicatedFrameInputs,
        sourcePipeline: SceneImageLayerPipeline,
        time: Float
    ) -> StagePreparation {
        guard stage.backend.supportsUnifiedPairLeaf else {
            return .rejected(reason: "backend-unsupported")
        }
        guard stage.logicalRenderTargetCount == 0,
              stage.renderGraph.renderTargets.isEmpty,
              targets.plan.logicalTargets.isEmpty else {
            return .rejected(reason: "logical-target-unsupported")
        }
        guard targets.inputTexture === sourceTexture else {
            return .rejected(reason: "source-texture-mismatch")
        }
        guard targets.inputTexture !== targets.outputTexture else {
            return .rejected(reason: "pair-texture-aliased")
        }
        guard targets.plan.input == stage.renderGraph.effects.first?.input else {
            return .rejected(reason: "stage-input-mismatch")
        }
        guard targets.plan.output == stage.renderGraph.finalOutput else {
            return .rejected(reason: "stage-output-mismatch")
        }
        if let rejection = leafInputRejection(stage, inputs: inputs) {
            return .rejected(reason: rejection)
        }
        return .ready(.init(
            stage: stage,
            sourceTexture: sourceTexture,
            targets: targets,
            inputs: inputs,
            sourcePipeline: sourcePipeline,
            time: time
        ))
    }

    static func encodePreparedStage(
        _ prepared: PreparedStage,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        let inputs = prepared.inputs
        guard prepared.targets.encodeInitialTargetClear(commandBuffer: commandBuffer),
              let output = renderStage(
                  prepared.stage,
                  sourceTexture: prepared.sourceTexture,
                  masks: inputs.masks,
                  targets: prepared.targets,
                  dynamicValues: inputs.dynamicValues,
                  sourceUniforms: .neutral(),
                  pipeline: prepared.sourcePipeline,
                  pipelines: inputs.pipelines,
                  cursorUV: inputs.cursorUV,
                  previousCursorUV: inputs.previousCursorUV,
                  pointerIsInside: inputs.pointerIsInside,
                  previousPointerIsInside: inputs.previousPointerIsInside,
                  frameTime: inputs.frameTime,
                  time: prepared.time,
                  audioSpectrum: inputs.audioSpectrum,
                  dependencyEffect: inputs.dependencyEffect,
                  commandBuffer: commandBuffer
              ) else { return false }
        return output === prepared.targets.outputTexture
    }

    private static func leafInputRejection(
        _ stage: SceneAuthoredEffectExecutionPlan,
        inputs: SceneResolvedMaterialRuntimeBridge.DedicatedFrameInputs
    ) -> String? {
        let pipelines = inputs.pipelines
        switch stage.backend {
        case .workshopShiftHue:
            return pipelines.shiftHue == nil ? "shift-hue-pipeline-missing" : nil
        case .workshopAudioBars(let plan):
            if case .enhancedSegmented = plan.profile {
                return pipelines.audioBars == nil ? "audio-bars-pipeline-missing" : nil
            }
            return "audio-bars-profile-unsupported"
        case .workshopGradient:
            return pipelines.workshopGradient == nil
                ? "gradient-pipeline-missing" : nil
        case .workshopShadow:
            return pipelines.workshopShadow == nil ? "shadow-pipeline-missing" : nil
        case .spin:
            return pipelines.spin == nil ? "spin-pipeline-missing" : nil
        case .proceduralNoise(let plan):
            let dependencyReady = plan.dependencySlotIndex.map {
                $0 == 3 && inputs.dependencyEffect?.slotIndex == $0
                    && inputs.dependencyEffect?.blendMode == 0
            } ?? (inputs.dependencyEffect == nil)
            guard dependencyReady else { return "procedural-noise-dependency-missing" }
            return pipelines.proceduralNoise == nil
                ? "procedural-noise-pipeline-missing" : nil
        case .filmGrain(let plan):
            guard let resources = inputs.masks.filmGrainEffects[
                plan.effectKey.descriptorID
            ] else { return "film-grain-resource-missing" }
            guard resources.matches(plan), resources.noise != nil else {
                return "film-grain-resource-mismatch"
            }
            return pipelines.filmGrain == nil ? "film-grain-pipeline-missing" : nil
        case .waterFlow(let plan):
            guard let resources = inputs.masks.waterFlowEffects[
                plan.effectKey.descriptorID
            ], resources.matches(plan) else {
                return "water-flow-resource-missing"
            }
            return pipelines.waterFlow == nil ? "water-flow-pipeline-missing" : nil
        case .foliageSway(let plan):
            guard let resources = inputs.masks.foliageSwayEffects[
                plan.effectKey.descriptorID
            ], resources.resolvedArguments(for: plan) != nil else {
                return "foliage-sway-resource-missing"
            }
            return pipelines.foliageSway == nil
                ? "foliage-sway-pipeline-missing" : nil
        case .depthParallax(let plan):
            guard let resources = inputs.masks.depthParallaxEffects[
                plan.effectKey.descriptorID
            ], resources.resolvedArguments(for: plan) != nil else {
                return "depth-parallax-resource-missing"
            }
            return pipelines.depthParallax == nil
                ? "depth-parallax-pipeline-missing" : nil
        case .shake(let plan):
            guard inputs.masks.shakeEffects[plan.effectKey.descriptorID] != nil else {
                return "shake-resource-missing"
            }
            return pipelines.shake == nil ? "shake-pipeline-missing" : nil
        case .fisheyeZeroDistortion:
            return pipelines.fisheyeZeroDistortion == nil
                ? "fisheye-pipeline-missing" : nil
        default:
            return "backend-unhandled"
        }
    }

    static func validTopology(
        chain: SceneAuthoredEffectExecutionChain,
        targets: [SceneGraphRenderTargetTable]
    ) -> Bool {
        let executionStages = chain.executionStages
        var previousOutput: SceneAuthoredEffectRenderPlan.TextureIdentity?
        for index in executionStages.indices {
            let stage = executionStages[index]
            let table = targets[index]
            guard stage.layerID == chain.layerID,
                  table.plan.layerID == chain.layerID,
                  table.plan.inputRole == stage.inputRole,
                  table.plan.input == stage.renderGraph.effects.first?.input,
                  table.plan.output == stage.renderGraph.finalOutput else {
                return false
            }
            if index == executionStages.startIndex {
                guard stage.inputRole == .layerSource else { return false }
            } else {
                guard stage.inputRole == .priorEffectOutput,
                      stage.renderGraph.effects.first?.input == previousOutput else {
                    return false
                }
            }
            previousOutput = stage.renderGraph.finalOutput
        }
        return previousOutput == chain.renderGraph.finalOutput
    }
}
