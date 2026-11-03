import Foundation
import Metal
import simd

@main
enum ParticleUploadOwnershipHarness {
    enum Failure: Error { case unavailable(String) }

    struct Context {
        let device: MTLDevice
        let queue: MTLCommandQueue
        let pipeline: SceneParticleMetalPipeline
        let white: MTLTexture

        init() throws {
            guard let device = MTLCreateSystemDefaultDevice(),
                  let queue = device.makeCommandQueue(),
                  let pipeline = SceneParticleMetalPipeline(device: device,
                    requiredVariants: [.init(blendMode: .translucent)]) else {
                throw Failure.unavailable("Metal particle pipeline")
            }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
            descriptor.storageMode = .shared
            descriptor.usage = .shaderRead
            guard let white = device.makeTexture(descriptor: descriptor) else {
                throw Failure.unavailable("white texture")
            }
            var pixel: [UInt8] = [255, 255, 255, 255]
            white.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                          withBytes: &pixel, bytesPerRow: 4)
            self.device = device
            self.queue = queue
            self.pipeline = pipeline
            self.white = white
        }
    }

    struct EncodedDraw {
        let command: MTLCommandBuffer
        let output: MTLTexture
    }

    static func main() throws {
        let context = try Context()
        let payload: [String: Any] = [
            "keys": try [keyIsolation(context, layer: 17, peer: 29, path: "particles/shared.json"),
                         keyIsolation(context, layer: 173, peer: 291, path: "particles/renamed/equivalent.json")],
            "pipelines": try pipelineIsolation(context),
            "reappearance": try reappearance(context),
            "inFlight": try inFlight(context),
            "cancellation": try cancellation(context),
            "finiteInstances": try finiteInstances(context),
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func instance(x: Float = 0, color: SIMD3<Float>, size: Float = 0.35) -> SceneParticleGPUInstance {
        SceneParticleGPUInstance(position: .init(x, 0, 0), size: size, rotation: .zero,
            color: color, alpha: 1, currentFrame: .identity, nextFrame: .identity, frameMix: 0)
    }

    static func batch(_ context: Context, layer: Int, child: Int? = nil,
                      path: String = "particles/shared.json",
                      instances: [SceneParticleGPUInstance]) -> SceneParticleDrawBatch {
        .init(layerID: layer, particlePath: path, texture: context.white,
              colorUVScale: .init(repeating: 1), colorSampling: .directImageFallback,
              refraction: nil, renderState: .init(blendMode: .translucent, cullMode: .none),
              childTemplateIndex: child, instances: instances,
              orientation: .screen, orientationAxis: nil, usesPerspective: false)
    }

    static func currentState(_ batch: SceneParticleMetalPipeline.PreparedBatch) throws -> (buffer: MTLBuffer, count: Int) {
        guard let state = batch.instanceBuffer.currentDrawState() else {
            throw Failure.unavailable("prepared batch has no uploaded records")
        }
        return state
    }

    static func first(_ pipeline: SceneParticleMetalPipeline,
                      _ draw: SceneParticleDrawBatch) throws -> SceneParticleMetalPipeline.PreparedBatch {
        guard let prepared = pipeline.prepare([draw]).first else {
            throw Failure.unavailable("valid draw was not prepared")
        }
        return prepared
    }

    static func encode(_ context: Context, pipeline: SceneParticleMetalPipeline,
                       batches: [SceneParticleMetalPipeline.PreparedBatch]) throws -> EncodedDraw {
        guard let command = context.queue.makeCommandBuffer() else {
            throw Failure.unavailable("command buffer")
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 64, height: 64, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .renderTarget
        guard let output = context.device.makeTexture(descriptor: descriptor) else {
            throw Failure.unavailable("readback target")
        }
        for batch in batches {
            guard batch.instanceBuffer.armSubmission(on: command) else {
                throw Failure.unavailable("arm before encode")
            }
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            throw Failure.unavailable("particle encoder")
        }
        let uniforms = SceneParticleLayerUniforms(
            viewProjection: SceneMatrix.identity(), layerModel: SceneMatrix.identity(),
            basis: .init(right: .init(1, 0, 0), up: .init(0, 1, 0)))
        for batch in batches {
            let draw = batch.draw
            guard pipeline.draw(texture: draw.texture, instances: batch.instanceBuffer,
                uniforms: uniforms, renderState: draw.renderState,
                colorUVScale: draw.colorUVScale, colorSampling: draw.colorSampling, encoder: encoder) else {
                encoder.endEncoding()
                throw Failure.unavailable("prepared particle did not encode")
            }
        }
        encoder.endEncoding()
        for batch in batches {
            guard batch.instanceBuffer.markSubmitted(on: command) else {
                throw Failure.unavailable("mark encoded instance slot")
            }
        }
        return .init(command: command, output: output)
    }

    static func finish(_ draw: EncodedDraw) throws {
        guard SceneParticleOffscreenReadbackHarness.commitAndWait(draw.command) else {
            throw Failure.unavailable("GPU completion")
        }
    }

    static func pixel(_ texture: MTLTexture, x: Int = 32) -> [Int] {
        var bytes = [UInt8](repeating: 0, count: 4)
        texture.getBytes(&bytes, bytesPerRow: 4, from: MTLRegionMake2D(x, 32, 1, 1), mipmapLevel: 0)
        return [Int(bytes[2]), Int(bytes[1]), Int(bytes[0]), Int(bytes[3])]
    }

    static func keyIsolation(_ context: Context, layer: Int, peer: Int, path: String) throws -> [String: Any] {
        let ids: [(Int, Int?)] = [(layer, nil), (layer, 0), (layer, 1), (peer, 0)]
        let colors: [SIMD3<Float>] = [.init(1, 0, 0), .init(0, 1, 0), .init(0, 0, 1), .init(1, 1, 0)]
        let draws = ids.enumerated().map { index, id in
            batch(context, layer: id.0, child: id.1, path: path,
                instances: [instance(x: Float(index) * 0.5 - 0.75, color: colors[index])])
        }
        let prepared = context.pipeline.prepare(draws)
        let native = try prepared.map { try currentState($0).buffer }
        let encoded = try encode(context, pipeline: context.pipeline, batches: prepared)
        try finish(encoded)
        return ["preparedCount": prepared.count,
            "bufferOwnerCount": Set(prepared.map { ObjectIdentifier($0.instanceBuffer) }).count,
            "nativeBufferCount": Set(native.map { ObjectIdentifier($0) }).count,
            "childTemplateIndices": prepared.map { $0.draw.childTemplateIndex ?? -1 },
            "pixelsRGBA": [8, 24, 40, 56].map { pixel(encoded.output, x: $0) }]
    }

    static func pipelineIsolation(_ context: Context) throws -> [String: Any] {
        guard let other = SceneParticleMetalPipeline(device: context.device,
            requiredVariants: [.init(blendMode: .translucent)]) else {
            throw Failure.unavailable("second pipeline")
        }
        let a = try first(context.pipeline, batch(context, layer: 301, child: 0,
            instances: [instance(color: .init(1, 0, 0))]))
        let b = try first(other, batch(context, layer: 301, child: 0,
            instances: [instance(color: .init(0, 1, 0))]))
        let aBuffer = try currentState(a).buffer
        let bBuffer = try currentState(b).buffer
        let firstDraw = try encode(context, pipeline: context.pipeline, batches: [a])
        let secondDraw = try encode(context, pipeline: other, batches: [b])
        try finish(firstDraw)
        try finish(secondDraw)
        return ["differentBufferOwners": a.instanceBuffer !== b.instanceBuffer,
            "differentNativeBuffers": aBuffer !== bBuffer,
            "firstPixelRGBA": pixel(firstDraw.output), "secondPixelRGBA": pixel(secondDraw.output)]
    }

    static func reappearance(_ context: Context) throws -> [String: Any] {
        let a = try first(context.pipeline, batch(context, layer: 401,
            instances: [instance(color: .init(1, 0, 0))]))
        let original = try currentState(a).buffer
        let firstDraw = try encode(context, pipeline: context.pipeline, batches: [a])
        try finish(firstDraw)
        let absent = context.pipeline.prepare([])
        let b = try first(context.pipeline, batch(context, layer: 401,
            instances: [instance(color: .init(0, 1, 0))]))
        let next = try currentState(b).buffer
        let secondDraw = try encode(context, pipeline: context.pipeline, batches: [b])
        try finish(secondDraw)
        return ["absentPreparedCount": absent.count,
            "sameBufferOwner": a.instanceBuffer === b.instanceBuffer, "sameNativeBuffer": original === next,
            "firstPixelRGBA": pixel(firstDraw.output), "nextPixelRGBA": pixel(secondDraw.output)]
    }

    static func inFlight(_ context: Context) throws -> [String: Any] {
        let a = try first(context.pipeline, batch(context, layer: 501,
            instances: [instance(color: .init(1, 0, 0))]))
        let firstState = try currentState(a)
        let firstDraw = try encode(context, pipeline: context.pipeline, batches: [a])
        // Enqueue without commit fixes the ownership boundary without timing
        // sleeps or assuming how quickly a real GPU finishes its work.
        firstDraw.command.enqueue()
        context.pipeline.cancel([a], on: firstDraw.command)
        let b = try first(context.pipeline, batch(context, layer: 501,
            instances: [instance(color: .init(0, 1, 0))]))
        let secondState = try currentState(b)
        let oldValue = firstState.buffer.contents().assumingMemoryBound(to: SceneParticleGPUInstance.self).pointee
        let secondDraw = try encode(context, pipeline: context.pipeline, batches: [b])
        try finish(firstDraw)
        let c = try first(context.pipeline, batch(context, layer: 501,
            instances: [instance(color: .init(0, 0, 1))]))
        let thirdState = try currentState(c)
        let thirdDraw = try encode(context, pipeline: context.pipeline, batches: [c])
        try finish(secondDraw)
        try finish(thirdDraw)
        return ["sameBufferOwner": a.instanceBuffer === b.instanceBuffer && b.instanceBuffer === c.instanceBuffer,
            "enqueuedCancelKeepsReservation": firstState.buffer !== secondState.buffer,
            "oldUploadedValuePreserved": oldValue.colorAndFrameMix == SIMD4<Float>(1, 0, 0, 0)
                && oldValue.rotationAndAlpha.w == 1,
            "firstSlotReusedAfterCompletion": thirdState.buffer === firstState.buffer,
            "firstPixelRGBA": pixel(firstDraw.output), "secondPixelRGBA": pixel(secondDraw.output),
            "thirdPixelRGBA": pixel(thirdDraw.output)]
    }

    static func cancellation(_ context: Context) throws -> [String: Any] {
        let a = try first(context.pipeline, batch(context, layer: 601,
            instances: [instance(color: .init(1, 0, 0))]))
        let original = try currentState(a).buffer
        guard let pending = context.queue.makeCommandBuffer() else {
            throw Failure.unavailable("pending command")
        }
        context.pipeline.cancel([a], on: pending)
        let pendingCleared = a.instanceBuffer.currentDrawState() == nil
        let b = try first(context.pipeline, batch(context, layer: 601,
            instances: [instance(color: .init(0, 0, 1))]))
        let pendingReused = try currentState(b).buffer === original
        let discarded = try encode(context, pipeline: context.pipeline, batches: [b])
        context.pipeline.cancel([b], on: discarded.command)
        context.pipeline.cancel([b], on: discarded.command)
        let reservedCleared = b.instanceBuffer.currentDrawState() == nil
        let c = try first(context.pipeline, batch(context, layer: 601,
            instances: [instance(color: .init(0, 1, 0))]))
        let reservedReused = try currentState(c).buffer === original
        let finalDraw = try encode(context, pipeline: context.pipeline, batches: [c])
        try finish(finalDraw)
        return ["pendingCleared": pendingCleared, "pendingSlotReused": pendingReused,
            "reservedCleared": reservedCleared, "reservedSlotReused": reservedReused,
            "cancelledCommandsRemainNotEnqueued": pending.status == .notEnqueued && discarded.command.status == .notEnqueued,
            "finalPixelRGBA": pixel(finalDraw.output)]
    }

    static func finiteInstances(_ context: Context) throws -> [String: Any] {
        var invalid = instance(color: .init(1, 1, 1))
        invalid.positionAndSize.x = .nan
        let draws = [
            batch(context, layer: 701, instances: [instance(x: -0.5, color: .init(1, 0, 0)), invalid,
                instance(x: 0.5, color: .init(0, 0, 1))]),
            batch(context, layer: 702, instances: [instance(color: .init(0, 1, 0))]),
            batch(context, layer: 703, instances: []), batch(context, layer: 704, instances: [invalid])]
        let prepared = context.pipeline.prepare(draws)
        let states = try prepared.map { try currentState($0) }
        let positions = states.first.map { state in
            let values = state.buffer.contents().assumingMemoryBound(to: SceneParticleGPUInstance.self)
            return (0..<state.count).map { values[$0].positionAndSize.x }
        } ?? []
        let draw = try encode(context, pipeline: context.pipeline, batches: prepared)
        try finish(draw)
        return ["preparedLayerIDs": prepared.map { $0.draw.layerID }, "uploadedCounts": states.map { $0.count },
            "uploadedPositions": positions, "sourceCountsUnchanged": draws.map { $0.instances.count },
            "pixelsRGBA": [16, 32, 48].map { pixel(draw.output, x: $0) }]
    }
}
