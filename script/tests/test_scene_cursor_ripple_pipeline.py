#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
PIPELINE_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Effects/SceneCursorRipplePipeline.swift"
)
MATERIAL_RENDER_STATE_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneMaterialRenderState.swift"
)
CURSOR_RIPPLE_RENDER_STATES_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneCursorRippleRenderStates.swift"
)

HARNESS = r'''
import Foundation
import Metal
import simd

struct SceneCursorRippleExecutionPlan {
    struct RenderStates: Equatable {
        let applyForce: SceneMaterialRenderState
        let simulateForce: SceneMaterialRenderState
        let combine: SceneMaterialRenderState
    }

    let simulationResolution: Int
    let rippleScale: Float
    let decay: Float
    let speed: Float
    let strength: Float
    let maskTexturePath: String?
    let renderStates: RenderStates

    init(
        simulationResolution: Int,
        rippleScale: Float,
        decay: Float,
        speed: Float,
        strength: Float,
        maskTexturePath: String?,
        renderStates: RenderStates = .supported
    ) {
        self.simulationResolution = simulationResolution
        self.rippleScale = rippleScale
        self.decay = decay
        self.speed = speed
        self.strength = strength
        self.maskTexturePath = maskTexturePath
        self.renderStates = renderStates
    }
}

@main
enum Harness {
    static func texture(
        device: MTLDevice,
        format: MTLPixelFormat,
        width: Int,
        height: Int,
        usage: MTLTextureUsage,
        storageMode: MTLStorageMode = .shared
    ) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = storageMode
        descriptor.usage = usage
        return device.makeTexture(descriptor: descriptor)!
    }

    static func clear(_ texture: MTLTexture, byte: UInt8 = 0) {
        let channels = texture.pixelFormat == .r8Unorm ? 1 : 4
        let bytesPerRow = texture.width * channels
        let bytes = [UInt8](
            repeating: byte,
            count: bytesPerRow * texture.height
        )
        texture.replace(
            region: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: bytesPerRow
        )
    }

    static func fillRGBA(_ texture: MTLTexture, _ pixel: [UInt8]) {
        precondition(texture.pixelFormat == .rgba8Unorm)
        precondition(pixel.count == 4)
        let bytesPerRow = texture.width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * texture.height)
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            bytes.replaceSubrange(offset ..< offset + 4, with: pixel)
        }
        texture.replace(
            region: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: bytesPerRow
        )
    }

    static func fillVisiblePattern(_ texture: MTLTexture) {
        precondition(texture.pixelFormat == .bgra8Unorm)
        let bytesPerRow = texture.width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * texture.height)
        for y in 0 ..< texture.height {
            for x in 0 ..< texture.width {
                let offset = y * bytesPerRow + x * 4
                bytes[offset] = UInt8((x * 3 + y * 5) & 255)
                bytes[offset + 1] = UInt8((x / 6).isMultiple(of: 2) ? 36 : 220)
                bytes[offset + 2] = UInt8((y / 6).isMultiple(of: 2) ? 48 : 232)
                bytes[offset + 3] = 255
            }
        }
        texture.replace(
            region: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: bytesPerRow
        )
    }

    static func visibleDifference(
        source: MTLTexture,
        output: MTLTexture,
        threshold: Int = 2
    ) -> [Int] {
        precondition(source.pixelFormat == .bgra8Unorm)
        precondition(output.pixelFormat == .bgra8Unorm)
        precondition(source.width == output.width && source.height == output.height)
        let bytesPerRow = source.width * 4
        var sourceBytes = [UInt8](repeating: 0, count: bytesPerRow * source.height)
        var outputBytes = [UInt8](repeating: 0, count: bytesPerRow * output.height)
        let region = MTLRegionMake2D(0, 0, source.width, source.height)
        source.getBytes(
            &sourceBytes, bytesPerRow: bytesPerRow,
            from: region, mipmapLevel: 0
        )
        output.getBytes(
            &outputBytes, bytesPerRow: bytesPerRow,
            from: region, mipmapLevel: 0
        )
        var minimumX = source.width
        var minimumY = source.height
        var maximumX = -1
        var maximumY = -1
        var count = 0
        var sum = 0
        var maximum = 0
        for y in 0 ..< source.height {
            for x in 0 ..< source.width {
                let offset = y * bytesPerRow + x * 4
                var pixelMaximum = 0
                for channel in 0 ..< 3 {
                    pixelMaximum = max(
                        pixelMaximum,
                        abs(Int(sourceBytes[offset + channel]) - Int(outputBytes[offset + channel]))
                    )
                }
                guard pixelMaximum > threshold else { continue }
                minimumX = min(minimumX, x)
                minimumY = min(minimumY, y)
                maximumX = max(maximumX, x)
                maximumY = max(maximumY, y)
                count += 1
                sum += pixelMaximum
                maximum = max(maximum, pixelMaximum)
            }
        }
        return [minimumX, minimumY, maximumX, maximumY, count, sum, maximum]
    }

    static func byteSum(_ texture: MTLTexture) -> Int {
        let bytesPerRow = texture.width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * texture.height)
        texture.getBytes(
            &bytes,
            bytesPerRow: bytesPerRow,
            from: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0
        )
        return bytes.reduce(0) { $0 + Int($1) }
    }

    static func appendReadback(
        _ texture: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) -> (MTLBuffer, Int)? {
        let unalignedBytesPerRow = texture.width * 4
        let bytesPerRow = (unalignedBytesPerRow + 255) & ~255
        let byteCount = bytesPerRow * texture.height
        guard let buffer = texture.device.makeBuffer(
            length: byteCount,
            options: .storageModeShared
        ), let blit = commandBuffer.makeBlitCommandEncoder() else { return nil }
        blit.copy(
            from: texture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: .init(
                width: texture.width,
                height: texture.height,
                depth: 1
            ),
            to: buffer,
            destinationOffset: 0,
            destinationBytesPerRow: bytesPerRow,
            destinationBytesPerImage: byteCount
        )
        blit.endEncoding()
        return (buffer, bytesPerRow)
    }

    static func readbackSum(
        _ readback: (MTLBuffer, Int),
        width: Int,
        height: Int
    ) -> Int {
        let bytes = readback.0.contents().assumingMemoryBound(to: UInt8.self)
        var sum = 0
        for y in 0 ..< height {
            let row = bytes.advanced(by: y * readback.1)
            for offset in 0 ..< width * 4 { sum += Int(row[offset]) }
        }
        return sum
    }

    static func channelRanges(_ texture: MTLTexture) -> [Int] {
        precondition(texture.pixelFormat == .rgba8Unorm)
        let bytesPerRow = texture.width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * texture.height)
        texture.getBytes(
            &bytes,
            bytesPerRow: bytesPerRow,
            from: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0
        )
        var minimums = [Int](repeating: 255, count: 4)
        var maximums = [Int](repeating: 0, count: 4)
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            for channel in 0 ..< 4 {
                let value = Int(bytes[offset + channel])
                minimums[channel] = min(minimums[channel], value)
                maximums[channel] = max(maximums[channel], value)
            }
        }
        return zip(minimums, maximums).flatMap { [$0.0, $0.1] }
    }

    static func activeExtent(_ texture: MTLTexture) -> [Int] {
        precondition(texture.pixelFormat == .rgba8Unorm)
        let bytesPerRow = texture.width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * texture.height)
        texture.getBytes(
            &bytes,
            bytesPerRow: bytesPerRow,
            from: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0
        )
        var minimumX = texture.width
        var minimumY = texture.height
        var maximumX = -1
        var maximumY = -1
        var count = 0
        for y in 0 ..< texture.height {
            for x in 0 ..< texture.width {
                let offset = y * bytesPerRow + x * 4
                guard bytes[offset ..< offset + 4].contains(where: { $0 > 0 }) else {
                    continue
                }
                minimumX = min(minimumX, x)
                minimumY = min(minimumY, y)
                maximumX = max(maximumX, x)
                maximumY = max(maximumY, y)
                count += 1
            }
        }
        return [minimumX, minimumY, maximumX, maximumY, count]
    }

    static func encode(
        pipeline: SceneCursorRipplePipeline,
        queue: MTLCommandQueue,
        history: MTLTexture,
        intermediate: MTLTexture,
        source: MTLTexture,
        output: MTLTexture,
        mask: MTLTexture?,
        plan: SceneCursorRippleExecutionPlan,
        current: SIMD2<Float>,
        previous: SIMD2<Float>,
        pointerMovement: Float? = nil,
        pointerIsInside: Bool = true,
        previousPointerIsInside: Bool = true,
        frameTime: Float = 1 / 60
    ) -> Bool {
        guard let commandBuffer = queue.makeCommandBuffer() else { return false }
        let encoded = pipeline.encode(
            history: history,
            intermediate: intermediate,
            source: source,
            output: output,
            mask: mask,
            maskUVScale: SIMD2(repeating: 1),
            plan: plan,
            currentCursorUV: current,
            previousCursorUV: previous,
            pointerIsInside: pointerIsInside,
            previousPointerIsInside: previousPointerIsInside,
            pointerMovement: pointerMovement
                ?? simd_length(current - previous) * 0.5,
            primaryButtonIsDown: false,
            frameTime: frameTime,
            commandBuffer: commandBuffer
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return encoded && commandBuffer.status == .completed
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pipeline = SceneCursorRipplePipeline(device: device) else {
            print(#"{"available":false}"#)
            return
        }
        let history = texture(
            device: device, format: .rgba8Unorm, width: 256, height: 256,
            usage: [.shaderRead, .renderTarget]
        )
        let intermediate = texture(
            device: device, format: .rgba8Unorm, width: 256, height: 256,
            usage: [.shaderRead, .renderTarget]
        )
        let source = texture(
            device: device, format: .bgra8Unorm, width: 256, height: 256,
            usage: [.shaderRead, .renderTarget]
        )
        let output = texture(
            device: device, format: .bgra8Unorm, width: 256, height: 256,
            usage: [.shaderRead, .renderTarget]
        )
        let mask = texture(
            device: device, format: .r8Unorm, width: 256, height: 256,
            usage: [.shaderRead]
        )
        clear(history)
        clear(intermediate)
        clear(source, byte: 127)
        clear(output)
        clear(mask, byte: 255)

        let unmasked = SceneCursorRippleExecutionPlan(
            simulationResolution: 256,
            rippleScale: 1,
            decay: 1,
            speed: 1,
            strength: 1,
            maskTexturePath: nil
        )
        let unmaskedEncoded = encode(
            pipeline: pipeline, queue: queue,
            history: history, intermediate: intermediate,
            source: source, output: output, mask: nil, plan: unmasked,
            current: SIMD2(0.7, 0.5), previous: SIMD2(0.3, 0.5)
        )
        let unmaskedSum = byteSum(history)
        let unmaskedIntermediateSum = byteSum(intermediate)
        let unmaskedIntermediateChannels = channelRanges(intermediate)
        let motionExtent = activeExtent(history)
        let stationaryEncoded = encode(
            pipeline: pipeline, queue: queue,
            history: history, intermediate: intermediate,
            source: source, output: output, mask: nil, plan: unmasked,
            current: SIMD2(0.7, 0.5), previous: SIMD2(0.7, 0.5)
        )
        let stationarySum = byteSum(history)
        let firstStationaryExtent = activeExtent(history)
        for _ in 0 ..< 10 {
            _ = encode(
                pipeline: pipeline, queue: queue,
                history: history, intermediate: intermediate,
                source: source, output: output, mask: nil, plan: unmasked,
                current: SIMD2(0.7, 0.5), previous: SIMD2(0.7, 0.5)
            )
        }
        let settledExtent = activeExtent(history)
        let settledSum = byteSum(history)

        let realisticHistory = texture(
            device: device, format: .rgba8Unorm, width: 256, height: 256,
            usage: [.shaderRead, .renderTarget]
        )
        let realisticIntermediate = texture(
            device: device, format: .rgba8Unorm, width: 256, height: 256,
            usage: [.shaderRead, .renderTarget]
        )
        clear(realisticHistory)
        clear(realisticIntermediate)
        let realisticMotionEncoded = encode(
            pipeline: pipeline, queue: queue,
            history: realisticHistory, intermediate: realisticIntermediate,
            source: source, output: output, mask: nil, plan: unmasked,
            current: SIMD2(0.5, 0.6075), previous: SIMD2(0.357629, 0.6075),
            pointerMovement: 0.04
        )
        let realisticMotionSum = byteSum(realisticHistory)
        let realisticStationaryEncoded = encode(
            pipeline: pipeline, queue: queue,
            history: realisticHistory, intermediate: realisticIntermediate,
            source: source, output: output, mask: nil, plan: unmasked,
            current: SIMD2(0.5, 0.6075), previous: SIMD2(0.5, 0.6075),
            pointerMovement: 0
        )
        let realisticStationarySum = byteSum(realisticHistory)

        let visibleHistory = texture(
            device: device, format: .rgba8Unorm, width: 256, height: 256,
            usage: [.shaderRead, .renderTarget]
        )
        let visibleIntermediate = texture(
            device: device, format: .rgba8Unorm, width: 256, height: 256,
            usage: [.shaderRead, .renderTarget]
        )
        let visibleSource = texture(
            device: device, format: .bgra8Unorm, width: 256, height: 256,
            usage: [.shaderRead, .renderTarget]
        )
        let visibleOutput = texture(
            device: device, format: .bgra8Unorm, width: 256, height: 256,
            usage: [.shaderRead, .renderTarget]
        )
        clear(visibleHistory)
        clear(visibleIntermediate)
        fillVisiblePattern(visibleSource)
        clear(visibleOutput)
        let visibleMotionEncoded = encode(
            pipeline: pipeline, queue: queue,
            history: visibleHistory, intermediate: visibleIntermediate,
            source: visibleSource, output: visibleOutput, mask: nil, plan: unmasked,
            current: SIMD2(0.5, 0.6075), previous: SIMD2(0.357629, 0.6075),
            pointerMovement: 0.04
        )
        var visibleFrames: [[Int]] = [[0] + visibleDifference(
            source: visibleSource,
            output: visibleOutput
        )]
        let visibleCheckpoints = Set([1, 4, 12, 30, 60, 120, 180, 240])
        for frame in 1 ... 240 {
            _ = encode(
                pipeline: pipeline, queue: queue,
                history: visibleHistory, intermediate: visibleIntermediate,
                source: visibleSource, output: visibleOutput, mask: nil, plan: unmasked,
                current: SIMD2(0.5, 0.6075), previous: SIMD2(0.5, 0.6075),
                pointerMovement: 0,
                pointerIsInside: false,
                previousPointerIsInside: false
            )
            if visibleCheckpoints.contains(frame) {
                visibleFrames.append([frame] + visibleDifference(
                    source: visibleSource,
                    output: visibleOutput
                ))
            }
        }

        let privateHistoryA = texture(
            device: device, format: .rgba8Unorm, width: 256, height: 256,
            usage: [.shaderRead, .renderTarget], storageMode: .private
        )
        let privateHistoryB = texture(
            device: device, format: .rgba8Unorm, width: 256, height: 256,
            usage: [.shaderRead, .renderTarget], storageMode: .private
        )
        let privateIntermediate = texture(
            device: device, format: .rgba8Unorm, width: 256, height: 256,
            usage: [.shaderRead, .renderTarget], storageMode: .private
        )
        let privateMotionEncoded = encode(
            pipeline: pipeline, queue: queue,
            history: privateHistoryA, intermediate: privateIntermediate,
            source: source, output: output, mask: nil, plan: unmasked,
            current: SIMD2(0.7, 0.5), previous: SIMD2(0.3, 0.5)
        )
        guard let copiedFrame = queue.makeCommandBuffer(),
              let copyEncoder = copiedFrame.makeBlitCommandEncoder() else {
            fatalError("private history copy setup failed")
        }
        copyEncoder.copy(
            from: privateHistoryA,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: .init(width: 256, height: 256, depth: 1),
            to: privateHistoryB,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: .init(x: 0, y: 0, z: 0)
        )
        copyEncoder.endEncoding()
        let privateStationaryEncoded = pipeline.encode(
            history: privateHistoryB,
            intermediate: privateIntermediate,
            source: source,
            output: output,
            mask: nil,
            maskUVScale: SIMD2(repeating: 1),
            plan: unmasked,
            currentCursorUV: SIMD2(0.7, 0.5),
            previousCursorUV: SIMD2(0.7, 0.5),
            pointerIsInside: true,
            previousPointerIsInside: true,
            pointerMovement: 0,
            primaryButtonIsDown: false,
            frameTime: 1 / 60,
            commandBuffer: copiedFrame
        )
        guard let privateReadback = appendReadback(
            privateHistoryB,
            commandBuffer: copiedFrame
        ) else { fatalError("private history readback failed") }
        copiedFrame.commit()
        copiedFrame.waitUntilCompleted()
        let privateStationarySum = readbackSum(
            privateReadback,
            width: 256,
            height: 256
        )

        clear(intermediate)
        fillRGBA(history, [0, 0, 0, 255])
        let negativeState = SceneCursorRippleExecutionPlan(
            simulationResolution: 256,
            rippleScale: 0.4,
            decay: 1,
            speed: 0.2,
            strength: 0.25,
            maskTexturePath: nil
        )
        let negativeStateEncoded = encode(
            pipeline: pipeline, queue: queue,
            history: history, intermediate: intermediate,
            source: source, output: output, mask: nil, plan: negativeState,
            current: SIMD2(0.5, 0.5), previous: SIMD2(0.5, 0.5)
        )
        let negativeStateChannels = channelRanges(history)

        let cappedDeltaHistory = texture(
            device: device, format: .rgba8Unorm, width: 256, height: 256,
            usage: [.shaderRead, .renderTarget]
        )
        let cappedDeltaIntermediate = texture(
            device: device, format: .rgba8Unorm, width: 256, height: 256,
            usage: [.shaderRead, .renderTarget]
        )
        let actualDeltaHistory = texture(
            device: device, format: .rgba8Unorm, width: 256, height: 256,
            usage: [.shaderRead, .renderTarget]
        )
        let actualDeltaIntermediate = texture(
            device: device, format: .rgba8Unorm, width: 256, height: 256,
            usage: [.shaderRead, .renderTarget]
        )
        fillRGBA(cappedDeltaHistory, [255, 0, 0, 0])
        clear(cappedDeltaIntermediate)
        fillRGBA(actualDeltaHistory, [255, 0, 0, 0])
        clear(actualDeltaIntermediate)
        let cappedDeltaEncoded = encode(
            pipeline: pipeline, queue: queue,
            history: cappedDeltaHistory, intermediate: cappedDeltaIntermediate,
            source: source, output: output, mask: nil, plan: unmasked,
            current: SIMD2(0.5, 0.5), previous: SIMD2(0.5, 0.5),
            pointerMovement: 0,
            pointerIsInside: false,
            previousPointerIsInside: false,
            frameTime: 1 / 30
        )
        let actualDeltaEncoded = encode(
            pipeline: pipeline, queue: queue,
            history: actualDeltaHistory, intermediate: actualDeltaIntermediate,
            source: source, output: output, mask: nil, plan: unmasked,
            current: SIMD2(0.5, 0.5), previous: SIMD2(0.5, 0.5),
            pointerMovement: 0,
            pointerIsInside: false,
            previousPointerIsInside: false,
            frameTime: 0.05
        )

        let defaultAlphaState = SceneMaterialRenderState.compile(
            blending: "normal",
            depthTest: "disabled",
            depthWrite: "disabled",
            cullMode: "nocull",
            alphaWriting: "default"
        )!
        let invalidStates = SceneCursorRippleExecutionPlan.RenderStates(
            applyForce: defaultAlphaState,
            simulateForce: SceneCursorRippleExecutionPlan.RenderStates.supported.simulateForce,
            combine: SceneCursorRippleExecutionPlan.RenderStates.supported.combine
        )
        let invalidStatePlan = SceneCursorRippleExecutionPlan(
            simulationResolution: 256,
            rippleScale: 0.4,
            decay: 0.4,
            speed: 0.2,
            strength: 0.25,
            maskTexturePath: nil,
            renderStates: invalidStates
        )
        let invalidStateRejected = !encode(
            pipeline: pipeline, queue: queue,
            history: history, intermediate: intermediate,
            source: source, output: output, mask: nil, plan: invalidStatePlan,
            current: SIMD2(0.5, 0.5), previous: SIMD2(0.5, 0.5)
        )
        let unknownStateRejected = SceneMaterialRenderState.compile(
            blending: "normal",
            depthTest: "disabled",
            depthWrite: "disabled",
            cullMode: "nocull",
            alphaWriting: "unknown"
        ) == nil

        clear(history)
        clear(intermediate)
        let masked = SceneCursorRippleExecutionPlan(
            simulationResolution: 256,
            rippleScale: 0.4,
            decay: 0.4,
            speed: 0.2,
            strength: 0.25,
            maskTexturePath: "masks/collision"
        )
        let maskedEncoded = encode(
            pipeline: pipeline, queue: queue,
            history: history, intermediate: intermediate,
            source: source, output: output, mask: mask, plan: masked,
            current: SIMD2(0.7, 0.5), previous: SIMD2(0.3, 0.5)
        )
        let result: [String: Any] = [
            "available": true,
            "unmaskedEncoded": unmaskedEncoded,
            "unmaskedSum": unmaskedSum,
            "unmaskedIntermediateSum": unmaskedIntermediateSum,
            "unmaskedIntermediateChannels": unmaskedIntermediateChannels,
            "stationaryEncoded": stationaryEncoded,
            "stationarySum": stationarySum,
            "motionExtent": motionExtent,
            "firstStationaryExtent": firstStationaryExtent,
            "settledExtent": settledExtent,
            "settledSum": settledSum,
            "realisticMotionEncoded": realisticMotionEncoded,
            "realisticMotionSum": realisticMotionSum,
            "realisticStationaryEncoded": realisticStationaryEncoded,
            "realisticStationarySum": realisticStationarySum,
            "visibleMotionEncoded": visibleMotionEncoded,
            "visibleFrames": visibleFrames,
            "privateMotionEncoded": privateMotionEncoded,
            "privateStationaryEncoded": privateStationaryEncoded,
            "privateStationaryGPUCompleted": copiedFrame.status == .completed,
            "privateStationarySum": privateStationarySum,
            "negativeStateEncoded": negativeStateEncoded,
            "negativeStateChannels": negativeStateChannels,
            "cappedDeltaEncoded": cappedDeltaEncoded,
            "cappedDeltaSum": byteSum(cappedDeltaHistory),
            "actualDeltaEncoded": actualDeltaEncoded,
            "actualDeltaSum": byteSum(actualDeltaHistory),
            "invalidStateRejected": invalidStateRejected,
            "unknownStateRejected": unknownStateRejected,
            "maskedEncoded": maskedEncoded,
            "maskedSum": byteSum(history),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneCursorRipplePipelineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("xcrun") is None:
            raise unittest.SkipTest("xcrun is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-cursor-ripple-"
        )
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        cls.binary = root / "scene-cursor-ripple"
        harness.write_text(HARNESS)
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                str(MATERIAL_RENDER_STATE_SOURCE),
                str(CURSOR_RIPPLE_RENDER_STATES_SOURCE),
                str(PIPELINE_SOURCE),
                str(harness),
                "-o",
                str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(cls.binary)],
            check=True,
            capture_output=True,
            text=True,
        )
        cls.result = json.loads(completed.stdout)
        if not cls.result["available"]:
            raise unittest.SkipTest("Metal is unavailable")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_motion_seeds_history_and_stationary_frame_preserves_wave(self) -> None:
        self.assertTrue(self.result["unmaskedEncoded"])
        self.assertGreater(self.result["unmaskedSum"], 0)
        self.assertTrue(self.result["stationaryEncoded"])
        self.assertGreater(self.result["stationarySum"], 0)
        self.assertGreater(self.result["settledSum"], 0)
        motion = self.result["motionExtent"]
        settled = self.result["settledExtent"]
        self.assertLess(settled[1], motion[1])
        self.assertGreater(settled[3], motion[3])
        self.assertGreater(settled[4], motion[4])

    def test_white_collision_mask_blocks_wave_state(self) -> None:
        self.assertTrue(self.result["maskedEncoded"])
        self.assertEqual(self.result["maskedSum"], 0)

    def test_private_copy_on_write_history_is_visible_to_next_render_pass(self) -> None:
        self.assertTrue(self.result["privateMotionEncoded"])
        self.assertTrue(self.result["privateStationaryEncoded"])
        self.assertTrue(self.result["privateStationaryGPUCompleted"])
        self.assertGreater(self.result["privateStationarySum"], 0)

    def test_sample_strength_motion_survives_a_stationary_frame(self) -> None:
        self.assertTrue(self.result["realisticMotionEncoded"])
        self.assertGreater(self.result["realisticMotionSum"], 0)
        self.assertTrue(self.result["realisticStationaryEncoded"])
        self.assertGreater(self.result["realisticStationarySum"], 0)

    def test_visible_displacement_outlives_pointer_exit_and_expands(self) -> None:
        self.assertTrue(self.result["visibleMotionEncoded"])
        frames = {row[0]: row[1:] for row in self.result["visibleFrames"]}
        self.assertGreater(frames[1][4], 0)
        self.assertGreater(frames[12][4], 0)
        self.assertLess(frames[12][0], frames[1][0])
        self.assertGreater(frames[12][2], frames[1][2])
        self.assertGreater(frames[12][4], frames[1][4])
        self.assertEqual(frames[240][4], 0)

    def test_state_targets_preserve_directional_force_channels(self) -> None:
        self.assertTrue(self.result["negativeStateEncoded"])
        ranges = self.result["negativeStateChannels"]
        self.assertEqual(ranges[0:2], [0, 0])
        self.assertGreater(ranges[3], 220)
        self.assertEqual(ranges[4:6], [0, 0])
        self.assertGreater(ranges[7], 220)
        self.assertLessEqual(abs(ranges[3] - ranges[7]), 1)

    def test_default_and_unknown_alpha_states_are_not_mapped(self) -> None:
        self.assertTrue(self.result["invalidStateRejected"])
        self.assertTrue(self.result["unknownStateRejected"])

    def test_simulation_consumes_the_host_frame_delta_without_a_second_cap(self) -> None:
        self.assertTrue(self.result["cappedDeltaEncoded"])
        self.assertTrue(self.result["actualDeltaEncoded"])
        self.assertLess(
            self.result["actualDeltaSum"],
            self.result["cappedDeltaSum"],
        )


if __name__ == "__main__":
    unittest.main()
