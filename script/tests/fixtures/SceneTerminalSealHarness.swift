import Foundation
import Metal

// Uses the existing persistent-color carrier and compiles the complete product
// terminal helper, coordinator and PreparedFrame implementation. Presentation
// and the full renderer entrypoint are outside this boundary.
@main enum SceneTerminalSealHarness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue()
        else { fatalError("terminal seal behavior requires Metal") }
        let owner = SceneResolvedMaterialSubmissionCoordinator(device: device,
            capabilities: .init(admissionCandidates: [],
                materialCatalog: .init(entries: [:], resourceDemandIssues: [])),
            capturesExecutionObservations: false, logSink: { _ in })
        let renderer = SceneMetalRenderer(renderDescriptor: .init(hdrEnabled: false,
            camera: .init(clearColor: [0, 0, 0], bloom: .disabled)),
            imageCompositor: .init(resolvedMaterialRuntime: owner),
            bloomPostProcess: nil, displayMappingPostProcess: nil)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: 4, height: 4, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        let target = device.makeTexture(descriptor: descriptor)!
        var accepted: [Bool] = [], beforeSubmit: [Bool] = [], completed: [Bool] = []
        var markerValues: [Int] = [], rejection = ""
        for index: UInt64 in 1...3 {
            let snapshot = SceneDynamicSnapshotResolver().resolve(frameIndex: index,
                generation: index, definitions: []).snapshot
            owner.beginFrame(textureSnapshot: .init(frameEpoch: index, frameIndex: index, entries: [:]),
                dynamicSnapshot: snapshot, frameInputs: .init(frameIndex: index,
                    screenSize: CGSize(width: 4, height: 4), sceneTime: Float(index),
                    dayTime: 0, frameTime: 1 / 60, pointerCurrentNDC: .zero, pointerPreviousNDC: .zero))
            let buffer = queue.makeCommandBuffer()!
            let marker = device.makeBuffer(length: 4, options: .storageModeShared)!
            memset(marker.contents(), 0, 4)
            let encoder = buffer.makeBlitCommandEncoder()!
            encoder.fill(buffer: marker, range: 0..<4, value: UInt8(index * 11))
            encoder.endEncoding()
            // Exercise a real product invalidation between begin and seal.
            // The next iteration begins a fresh frame on the same owner.
            if index == 2 { owner.invalidate(reason: .executorInvalidation) }
            let failure = renderer.encodeTerminalColor(sceneColor: nil, target: target,
                offscreenTexturePool: nil, dynamicValues: snapshot, commandBuffer: buffer)
            accepted.append(failure == nil)
            beforeSubmit.append(buffer.status == .notEnqueued && marker.contents().load(as: UInt8.self) == 0)
            if let failure {
                rejection = failure.reasonCode ?? "missing reason"
                precondition(SceneMetalRenderer.submitPreparedFrame(failure) == failure)
                owner.cancelUnsubmittedFrame(on: buffer)
            } else {
                let candidate = SceneMetalRenderer.PreparedFrame(commandBuffer: buffer,
                    submit: { buffer.commit() }, cancel: { owner.cancelUnsubmittedFrame(on: buffer) })
                precondition(SceneMetalRenderer.submitPreparedFrame(.prepared(candidate)).isSubmitted)
                buffer.waitUntilCompleted()
                precondition(buffer.error == nil)
            }
            completed.append(buffer.status == .completed)
            markerValues.append(Int(marker.contents().load(as: UInt8.self)))
        }
        let output: [String: Any] = ["accepted": accepted, "beforeSubmit": beforeSubmit,
            "completed": completed, "marker": markerValues, "rejection": rejection]
        print(String(decoding: try JSONSerialization.data(withJSONObject: output), as: UTF8.self))
    }
}
