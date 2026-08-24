import Foundation
import Metal

extension SceneEffectStageRenderer {
    enum StagePreparation {
        case ready(PreparedStage)
        case rejected(reason: String)
    }

    struct PreparedStage {
        let stage: SceneEffectStageExecutionPlan
        let sourceTexture: MTLTexture
        let targets: SceneGraphRenderTargetTable
        let inputs: SceneResolvedMaterialRuntimeBridge.DedicatedFrameInputs
        let sourcePipeline: SceneImageLayerPipeline
        let time: Float
    }

    static func prepareStage(
        _ stage: SceneEffectStageExecutionPlan,
        sourceTexture: MTLTexture,
        targets: SceneGraphRenderTargetTable,
        inputs: SceneResolvedMaterialRuntimeBridge.DedicatedFrameInputs,
        sourcePipeline: SceneImageLayerPipeline,
        time: Float
    ) -> StagePreparation {
        let pairLeaf = stage.backend.supportsUnifiedPairLeaf
            && stage.logicalRenderTargetCount == 0
            && stage.renderGraph.renderTargets.isEmpty
            && targets.plan.logicalTargets.isEmpty
        let logicalTargetStage = stage.supportsUnifiedLogicalTargetStage
            && stage.logicalRenderTargetCount > 0
            && stage.renderGraph.renderTargets.count == stage.logicalRenderTargetCount
            && targets.plan.logicalTargets.count == stage.logicalRenderTargetCount
            && stage.renderGraph.renderTargets.allSatisfy { !$0.declaredUnique }
        guard pairLeaf || logicalTargetStage else {
            return .rejected(reason: "backend-unsupported")
        }
        guard targets.inputTexture === sourceTexture else {
            return .rejected(reason: "source-texture-mismatch")
        }
        guard !targets.inputOutputAliased,
              targets.inputTexture !== targets.outputTexture else {
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
        // GraphExecutionState initialization intents are the sole owner of
        // authored clears and transparent history seeds. Clearing here would
        // run once per copy-on-write target table, after history rehydration,
        // and erase the committed state before a dedicated pass can read it.
        guard let output = renderStage(
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
            pointerMovement: inputs.pointerMovement,
            primaryButtonIsDown: inputs.primaryButtonIsDown,
            frameTime: inputs.frameTime,
            time: prepared.time,
            audioSpectrum: inputs.audioSpectrum,
            dependencyEffect: inputs.dependencyEffect,
            commandBuffer: commandBuffer
        ) else {
            logEncodeFailure(prepared.stage, phase: "render")
            return false
        }
        guard output === prepared.targets.outputTexture else {
            logEncodeFailure(prepared.stage, phase: "output-identity")
            return false
        }
        return true
    }

    private static func logEncodeFailure(
        _ stage: SceneEffectStageExecutionPlan,
        phase: String
    ) {
        guard let effect = stage.renderGraph.effects.first?.key else { return }
        NSLog(
            "MWX DEBUG SCENE: phase=dedicated-stage-encode layer=%d effect=%d"
                + " backend=%@ failure=%@",
            effect.layerID,
            effect.effectIndex,
            stage.backend.stableName,
            phase
        )
    }

    private static func leafInputRejection(
        _ stage: SceneEffectStageExecutionPlan,
        inputs: SceneResolvedMaterialRuntimeBridge.DedicatedFrameInputs
    ) -> String? {
        let pipelines = inputs.pipelines
        switch stage.backend {
        case .preciseGaussian:
            return pipelines.gaussianBlur == nil
                ? "precise-gaussian-pipeline-missing" : nil
        case .standardBlur(let plan):
            guard pipelines.standardBlur != nil else {
                return "standard-blur-pipeline-missing"
            }
            guard plan.maskTexturePath != nil else { return nil }
            guard let resources = inputs.masks.standardBlurEffects[
                plan.effectDescriptorID
            ], resources.matches(plan), resources.maskCandidate != nil else {
                return "standard-blur-resource-missing"
            }
            return nil
        case .localContrast:
            guard pipelines.localContrast != nil else {
                return "local-contrast-pipeline-missing"
            }
            guard let strength = stage.localContrastStrength(
                in: inputs.dynamicValues
            ), strength.isFinite, (0...5).contains(strength) else {
                return "local-contrast-strength-invalid"
            }
            return nil
        case .godrays(let plan):
            guard pipelines.godrays != nil else {
                return "godrays-pipeline-missing"
            }
            guard let resources = inputs.masks.godraysEffects[
                plan.effectKey.descriptorID
            ], resources.matches(plan) else {
                return "godrays-resource-missing"
            }
            return nil
        case .proceduralNoise(let plan):
            guard proceduralNoiseDependencyMatches(
                inputs.dependencyEffect,
                plan: plan
            ) else { return "procedural-noise-dependency-missing" }
            return pipelines.proceduralNoise == nil
                ? "procedural-noise-pipeline-missing" : nil
        case .waterWaves(let plan):
            guard let resources = inputs.masks.waterWavesEffects[
                plan.effectKey.descriptorID
            ], resources.matches(plan) else {
                return "water-waves-resource-missing"
            }
            return pipelines.waterWaves == nil ? "water-waves-pipeline-missing" : nil
        case .waterCaustics(let plan):
            guard let resources = inputs.masks.waterCausticsEffects[
                plan.effectKey.descriptorID
            ], resources.matches(plan) else {
                return "water-caustics-resource-missing"
            }
            return pipelines.waterCaustics == nil
                ? "water-caustics-pipeline-missing" : nil
        case .xRay(let plan):
            switch SceneXRayRuntimePlanner.resolve(
                declaration: plan.declaration,
                resources: inputs.masks.xRay,
                snapshot: inputs.dynamicValues,
                pointerIsInside: inputs.pointerIsInside
            ) {
            case .identity:
                return nil
            case .render:
                return pipelines.xRay == nil ? "x-ray-pipeline-missing" : nil
            case .unsupported:
                return "x-ray-runtime-unsupported"
            }
        case .blend(let plan):
            if let providerLayerID = plan.dependencyProviderLayerID {
                guard let dependency = inputs.dependencyEffect,
                      dependency.consumerLayerID == plan.layerID,
                      dependency.providerLayerID == providerLayerID,
                      dependency.variant == .primary,
                      dependency.slot.effectID == plan.effectKey.descriptorID,
                      dependency.slot.passIndex == 0,
                      dependency.slot.slotIndex == 1,
                      dependency.blendMode == plan.blendMode else {
                    return "blend-dependency-mismatch"
                }
                return pipelines.blend == nil ? "blend-pipeline-missing" : nil
            }
            guard let resources = inputs.masks.blendEffects[
                plan.effectKey.descriptorID
            ], resources.resolvedArguments(for: plan) != nil else {
                return "blend-resource-missing"
            }
            return pipelines.blend == nil ? "blend-pipeline-missing" : nil
        case .transform:
            return nil
        case .pulse(let plan):
            guard let resources = inputs.masks.pulseEffects[
                plan.effectKey.descriptorID
            ], resources.matches(plan) else {
                return "pulse-resource-missing"
            }
            let bounds = plan.resolvedComponents(.bounds, in: inputs.dynamicValues)
            guard bounds.x < bounds.y else { return "pulse-bounds-invalid" }
            return pipelines.pulse == nil ? "pulse-pipeline-missing" : nil
        }
    }

}
