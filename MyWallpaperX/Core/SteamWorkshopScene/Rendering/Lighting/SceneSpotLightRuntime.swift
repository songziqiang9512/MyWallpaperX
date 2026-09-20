import Metal
import simd

final class SceneSpotLightRuntime {
    struct Frame {
        let sceneTime: Double
        let dynamicValues: SceneDynamicSnapshot
        let viewProjection: simd_float4x4
        let mainPass: SceneMainPassEncoder
        let commandBuffer: MTLCommandBuffer

        init(
            frameContext: SceneFrameContext,
            cameraFrame: SceneParticleCameraFrame,
            mainPass: SceneMainPassEncoder,
            commandBuffer: MTLCommandBuffer
        ) {
            sceneTime = frameContext.sceneTime
            dynamicValues = frameContext.dynamicValues
            viewProjection = cameraFrame.viewProjection(
                usesPerspective: cameraFrame.defaultsToPerspective
            )
            self.mainPass = mainPass
            self.commandBuffer = commandBuffer
        }
    }

    let plansByLayerID: [Int: SceneSpotLightPlan]
    private let pipeline: SceneSpotLightPipeline?
    private let telemetry = SceneGPUCompletionTelemetry(phase: "spot-light")

    init(
        descriptor: SceneRenderDescriptor,
        instantiatedSceneScriptTargets: Set<SceneDynamicTarget> = [],
        scriptSourceEvidence: [SceneScriptSourceEvidenceIR] = [],
        pipeline: @autoclosure () -> SceneSpotLightPipeline?
    ) {
        plansByLayerID = Dictionary(
            uniqueKeysWithValues: descriptor.layers.compactMap { layer in
                SceneSpotLightPlan(
                    layer: layer,
                    instantiatedSceneScriptTargets:
                        instantiatedSceneScriptTargets,
                    scriptSourceEvidence: scriptSourceEvidence
                ).map { (layer.id, $0) }
            }
        )
        self.pipeline = plansByLayerID.isEmpty ? nil : pipeline()
    }

    func render(
        layerID: Int,
        worldFrame: simd_float4x4?,
        frame: Frame
    ) {
        guard let plan = plansByLayerID[layerID],
              let pipeline,
              let worldFrame,
              let encoder = frame.mainPass.encoder() else {
            telemetry.recordFailure(layerID: layerID)
            return
        }
        let color = SceneDynamicLayerValues.color(
            layerID: layerID,
            authoredValue: [plan.color.x, plan.color.y, plan.color.z],
            snapshot: frame.dynamicValues
        )
        guard let intensity = SceneDynamicLayerValues.lightIntensity(
            layerID: layerID,
            authoredValue: plan.intensity,
            snapshot: frame.dynamicValues
        ) else {
            telemetry.recordFailure(layerID: layerID)
            return
        }
        let encoded = pipeline.draw(
            plan: plan,
            color: color,
            intensity: intensity,
            worldOrigin: SIMD2(worldFrame.columns.3.x, worldFrame.columns.3.y),
            viewProjection: frame.viewProjection,
            sceneTime: frame.sceneTime,
            encoder: encoder
        )
        telemetry.record(layerID: layerID, encoded: encoded, on: frame.commandBuffer)
    }

    func reportLines(candidateCount: Int) -> [String] {
        [
            "spotLightCandidateCount: \(candidateCount)",
            "spotLightPlanCount: \(plansByLayerID.count)",
            "spotLightPlanLayerIDs: \(plansByLayerID.keys.sorted())",
        ]
    }
}
