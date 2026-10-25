import CoreGraphics
import Foundation
import Metal
import simd

// The existing terminal probe stays in this short entry unit, as before.
// TERMINAL_REPLAY_PROBE

@main
private enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let encoder = SceneResolvedMaterialPassEncoder(device: device) else {
            print("{\"metalAvailable\":false}")
            return
        }
        let color = runSceneResolvedMaterialPassColorCases(
            device: device, queue: queue, encoder: encoder)
        let displacement = runSceneResolvedMaterialPassDisplacementCases(
            device: device, queue: queue, encoder: encoder)
        let scalar = runSceneResolvedMaterialPassScalarCases(
            device: device, queue: queue, encoder: encoder,
            authoredTexture: color.authoredTexture, baseline: color.baseline,
            rgbaTarget: color.rgbaTarget)
        let pipeline = runSceneResolvedMaterialPassPipelineCases(
            device: device, queue: queue, encoder: encoder,
            baseline: color.baseline, rgbaTarget: color.rgbaTarget,
            second: color.second)
        var results = color.facts
        results.merge(displacement.facts) { _, new in new }
        results.merge(scalar) { _, new in new }
        results.merge(pipeline.facts) { _, new in new }
        results.merge(terminalReplayProbe(device: device, queue: queue)) { _, new in new }
        let payload: [String: Any] = [
            "results": results,
            "crossDeviceExercised": pipeline.crossDeviceExercised,
            "flow2DVector": [displacement.flow2DVector.x, displacement.flow2DVector.y],
            "flow2DSampleOffset": [displacement.flow2DSampleOffset.x, displacement.flow2DSampleOffset.y],
            "flow2DVisibleShift": [displacement.flow2DVisibleShift.x, displacement.flow2DVisibleShift.y],
            "shimmer2DCentroidShift": [
                displacement.shimmer2DCentroidShift.x,
                displacement.shimmer2DCentroidShift.y,
            ],
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        FileHandle.standardOutput.write(data)
    }
}
