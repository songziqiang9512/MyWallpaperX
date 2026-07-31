import Metal
import simd

final class SceneSpotLightRuntime {
    struct Frame {
        let sceneTime: Double
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
            viewProjection = cameraFrame.orthographicViewProjection
            self.mainPass = mainPass
            self.commandBuffer = commandBuffer
        }
    }

    let plansByLayerID: [Int: SceneSpotLightPlan]
    private let pipeline: SceneSpotLightPipeline?
    private let telemetry = SceneGPUCompletionTelemetry(phase: "spot-light")

    init(
        descriptor: SceneRenderDescriptor,
        pipeline: SceneSpotLightPipeline?
    ) {
        plansByLayerID = Dictionary(
            uniqueKeysWithValues: descriptor.layers.compactMap { layer in
                SceneSpotLightPlan(layer: layer).map { (layer.id, $0) }
            }
        )
        self.pipeline = pipeline
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
        let encoded = pipeline.draw(
            plan: plan,
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
