import Foundation
import Metal

private func pixels(_ texture: MTLTexture) -> [UInt8] {
    var result = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
    texture.getBytes(
        &result,
        bytesPerRow: texture.width * 4,
        from: MTLRegionMake2D(0, 0, texture.width, texture.height),
        mipmapLevel: 0
    )
    return result
}

private func sourceCaptureIsExact(
    source: MTLTexture,
    pipeline: SceneImageLayerPipeline,
    queue: MTLCommandQueue
) -> Bool {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: source.pixelFormat,
        width: source.width,
        height: source.height,
        mipmapped: false
    )
    descriptor.storageMode = .shared
    descriptor.usage = [.renderTarget, .shaderRead]
    guard let target = source.device.makeTexture(descriptor: descriptor),
          let commandBuffer = queue.makeCommandBuffer() else { return false }
    let encoder = SceneGraphResourcePassEncoder(commandQueue: queue)
    guard let command = encoder.prepareSourceCapture(
        source: source,
        target: target,
        uniforms: .neutral(),
        pipeline: pipeline
    ), encoder.encode(command, commandBuffer: commandBuffer) else { return false }
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    return commandBuffer.status == .completed
        && commandBuffer.error == nil
        && pixels(source) == pixels(target)
}

@main
private enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            print("{\"metalAvailable\":false}")
            return
        }
        let source = sourceTexture(device)
        let pipeline = sourcePipeline(device)
        let exactSourceCapture = sourceCaptureIsExact(
            source: source, pipeline: pipeline, queue: queue
        )
        let serialQuarter = runCoordinatorSequence(
            mixWeight: 0.25,
            exercisesInFlightBoundary: false,
            device: device,
            queue: queue,
            source: source,
            pipeline: pipeline
        )
        let inFlightQuarter = runCoordinatorSequence(
            mixWeight: 0.25,
            exercisesInFlightBoundary: true,
            device: device,
            queue: queue,
            source: source,
            pipeline: pipeline
        )
        let serialThreeQuarters = runCoordinatorSequence(
            mixWeight: 0.75,
            exercisesInFlightBoundary: false,
            device: device,
            queue: queue,
            source: source,
            pipeline: pipeline
        )
        let inFlightThreeQuarters = runCoordinatorSequence(
            mixWeight: 0.75,
            exercisesInFlightBoundary: true,
            device: device,
            queue: queue,
            source: source,
            pipeline: pipeline
        )
        let quarterScales: [Float] = [0.25, 0.4375, 0.578125]
        let threeQuarterScales: [Float] = [0.75, 0.9375, 0.984375]
        let payload: [String: Any] = [
            "metalAvailable": true,
            "sourceCaptureIsExact": exactSourceCapture,
            "quarterFailure": "success",
            "threeQuarterFailure": "success",
            "serialQuarterConverges": sequenceMatches(
                serialQuarter, scales: quarterScales
            ),
            "inFlightQuarterConverges": sequenceMatches(
                inFlightQuarter, scales: quarterScales
            ),
            "serialThreeQuarterConverges": sequenceMatches(
                serialThreeQuarters, scales: threeQuarterScales
            ),
            "inFlightThreeQuarterConverges": sequenceMatches(
                inFlightThreeQuarters, scales: threeQuarterScales
            ),
            "pendingHistoryDefersNextFrame": inFlightQuarter
                .deferredWhileHistoryPending
                && inFlightThreeQuarters.deferredWhileHistoryPending,
            "authoredWeightsProduceDistinctPixels": inFlightQuarter.frames[0]
                .outputPixels != inFlightThreeQuarters.frames[0].outputPixels,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        FileHandle.standardOutput.write(data)
    }
}
