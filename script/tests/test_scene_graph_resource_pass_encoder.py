#!/usr/bin/env python3

"""R4 graph-resource preflight and bounded Metal command encoding gate."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
ENCODER_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/EffectExecution"
    / "SceneGraphResourcePassEncoder.swift"
)


SUPPORT = r'''
import Foundation
import Metal
import simd

nonisolated struct SceneGraphRenderTargetPlan {
    struct ClearColor: Equatable {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
    }
}

struct SceneLayerFragmentUniforms {
    let color: SIMD4<Float>

    static func neutral() -> Self {
        .init(color: SIMD4<Float>(repeating: 1))
    }
}

struct SceneImageLayerPipeline {
    private struct Vertex {
        let position: SIMD2<Float>
        let texcoord: SIMD2<Float>
    }

    private static let vertices = [
        Vertex(position: .init(-0.5, -0.5), texcoord: .init(0, 1)),
        Vertex(position: .init( 0.5, -0.5), texcoord: .init(1, 1)),
        Vertex(position: .init(-0.5,  0.5), texcoord: .init(0, 0)),
        Vertex(position: .init( 0.5,  0.5), texcoord: .init(1, 0)),
    ]

    let state: MTLRenderPipelineState

    func bind(encoder: MTLRenderCommandEncoder) {
        encoder.setRenderPipelineState(state)
        var vertices = Self.vertices
        encoder.setVertexBytes(
            &vertices,
            length: vertices.count * MemoryLayout<Vertex>.stride,
            index: 0
        )
    }

    func drawLayer(
        texture: MTLTexture,
        dependencyTexture: MTLTexture? = nil,
        mvp: simd_float4x4,
        uniforms: SceneLayerFragmentUniforms,
        encoder: MTLRenderCommandEncoder
    ) {
        _ = dependencyTexture
        var mvp = mvp
        var uniforms = uniforms
        encoder.setVertexBytes(
            &mvp,
            length: MemoryLayout<simd_float4x4>.size,
            index: 1
        )
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<SceneLayerFragmentUniforms>.size,
            index: 0
        )
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(
            type: .triangleStrip,
            vertexStart: 0,
            vertexCount: 4
        )
    }
}
'''


HARNESS = r'''
import Foundation
import Metal

private typealias Encoder = SceneGraphResourcePassEncoder
private typealias Clear = SceneGraphRenderTargetPlan.ClearColor

private func texture(
    device: MTLDevice,
    format: MTLPixelFormat = .rgba8Unorm,
    width: Int = 2,
    height: Int = 2,
    mipmapped: Bool = false,
    usage: MTLTextureUsage,
    fill: [UInt8]? = nil
) -> MTLTexture? {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: format,
        width: width,
        height: height,
        mipmapped: mipmapped
    )
    descriptor.storageMode = .shared
    descriptor.usage = usage
    guard let result = device.makeTexture(descriptor: descriptor) else {
        return nil
    }
    if let fill {
        let bytesPerPixel = format == .r8Unorm ? 1 : 4
        result.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: fill,
            bytesPerRow: width * bytesPerPixel
        )
    }
    return result
}

private func target(
    device: MTLDevice,
    format: MTLPixelFormat = .rgba8Unorm,
    width: Int = 2,
    height: Int = 2,
    mipmapped: Bool = false,
    usage: MTLTextureUsage = [.renderTarget, .shaderRead],
    fill: [UInt8]? = nil
) -> MTLTexture {
    texture(
        device: device,
        format: format,
        width: width,
        height: height,
        mipmapped: mipmapped,
        usage: usage,
        fill: fill
    )!
}

private func pixels(_ texture: MTLTexture) -> [UInt8] {
    let bytesPerPixel = texture.pixelFormat == .r8Unorm ? 1 : 4
    var result = [UInt8](
        repeating: 0,
        count: texture.width * texture.height * bytesPerPixel
    )
    texture.getBytes(
        &result,
        bytesPerRow: texture.width * bytesPerPixel,
        from: MTLRegionMake2D(0, 0, texture.width, texture.height),
        mipmapLevel: 0
    )
    return result
}

private func capturePipeline(_ device: MTLDevice) -> SceneImageLayerPipeline {
    let source = """
    #include <metal_stdlib>
    using namespace metal;
    struct Vertex { float2 position; float2 texcoord; };
    struct Varying { float4 position [[position]]; float2 texcoord; };
    struct Uniforms { float4 color; };
    vertex Varying captureVertex(
        const device Vertex *vertices [[buffer(0)]],
        constant float4x4 &mvp [[buffer(1)]],
        uint id [[vertex_id]]
    ) {
        Varying out;
        out.position = mvp * float4(vertices[id].position, 0, 1);
        out.texcoord = vertices[id].texcoord;
        return out;
    }
    fragment float4 captureFragment(
        Varying in [[stage_in]],
        texture2d<float> source [[texture(0)]],
        constant Uniforms &uniforms [[buffer(0)]]
    ) {
        constexpr sampler s(coord::normalized, address::clamp_to_edge,
                            filter::nearest);
        return source.sample(s, in.texcoord).a * uniforms.color;
    }
    """
    let library = try! device.makeLibrary(source: source, options: nil)
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = library.makeFunction(name: "captureVertex")
    descriptor.fragmentFunction = library.makeFunction(name: "captureFragment")
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    return .init(state: try! device.makeRenderPipelineState(
        descriptor: descriptor
    ))
}

private func completed(
    _ command: MTLCommandBuffer,
    encoded: Bool
) -> Bool {
    command.commit()
    command.waitUntilCompleted()
    return encoded && command.status == .completed && command.error == nil
}

private func emptyCommandCompleted(_ command: MTLCommandBuffer) -> Bool {
    command.commit()
    command.waitUntilCompleted()
    return command.status == .completed && command.error == nil
}

private func multisampleTexture(device: MTLDevice) -> MTLTexture? {
    let descriptor = MTLTextureDescriptor()
    descriptor.textureType = .type2DMultisample
    descriptor.pixelFormat = .rgba8Unorm
    descriptor.width = 2
    descriptor.height = 2
    descriptor.depth = 1
    descriptor.mipmapLevelCount = 1
    descriptor.sampleCount = 4
    descriptor.arrayLength = 1
    descriptor.storageMode = .private
    descriptor.usage = [.renderTarget, .shaderRead]
    return device.makeTexture(descriptor: descriptor)
}

private func arrayTexture(
    device: MTLDevice,
    usage: MTLTextureUsage
) -> MTLTexture? {
    let descriptor = MTLTextureDescriptor()
    descriptor.textureType = .type2DArray
    descriptor.pixelFormat = .rgba8Unorm
    descriptor.width = 2
    descriptor.height = 2
    descriptor.depth = 1
    descriptor.mipmapLevelCount = 1
    descriptor.sampleCount = 1
    descriptor.arrayLength = 2
    descriptor.storageMode = .shared
    descriptor.usage = usage
    return device.makeTexture(descriptor: descriptor)
}

@main
private enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let otherQueue = device.makeCommandQueue() else {
            print("{\"metalAvailable\":false}")
            return
        }
        let encoder = Encoder(commandQueue: queue)
        let otherOwner = Encoder(commandQueue: queue)
        let clear = Clear(red: 1, green: 0, blue: 1, alpha: 1)
        let sentinel: [UInt8] = Array(repeating: [13, 27, 49, 71], count: 4)
            .flatMap { $0 }
        let sourceBytes: [UInt8] = [
            1, 2, 3, 4, 5, 6, 7, 8,
            9, 10, 11, 12, 13, 14, 15, 16,
        ]

        let captureSource = texture(
            device: device,
            format: .bgra8Unorm,
            width: 1,
            height: 1,
            usage: .shaderRead,
            fill: [0, 0, 255, 255]
        )!
        let captureTarget = target(
            device: device,
            format: .bgra8Unorm,
            fill: sentinel
        )
        let sourcePipeline = capturePipeline(device)
        let preparedCapture = encoder.prepareSourceCapture(
            source: captureSource,
            target: captureTarget,
            uniforms: .init(color: .init(0, 1, 0, 1)),
            pipeline: sourcePipeline
        )
        let capturePrepareHasNoSideEffect = pixels(captureTarget) == sentinel
        var captureCommandsAppended = false
        var captureGPUCompleted = false
        if let preparedCapture, let command = queue.makeCommandBuffer() {
            captureCommandsAppended = encoder.encode(
                preparedCapture,
                commandBuffer: command
            )
            captureGPUCompleted = completed(
                command,
                encoded: captureCommandsAppended
            )
        }
        let expectedCapture: [UInt8] = Array(
            repeating: [0, 255, 0, 255],
            count: 4
        ).flatMap { $0 }
        let captureFullTargetDrawMatches = pixels(captureTarget)
            == expectedCapture

        let captureUnreadableSourceRejected = encoder.prepareSourceCapture(
            source: target(
                device: device,
                format: .bgra8Unorm,
                width: 1,
                height: 1,
                usage: .renderTarget
            ),
            target: target(device: device, format: .bgra8Unorm),
            uniforms: .neutral(),
            pipeline: sourcePipeline
        ) == nil
        let captureTargetFormatRejected = encoder.prepareSourceCapture(
            source: captureSource,
            target: target(device: device, format: .rgba8Unorm),
            uniforms: .neutral(),
            pipeline: sourcePipeline
        ) == nil
        let captureTargetUsageRejected = encoder.prepareSourceCapture(
            source: captureSource,
            target: target(
                device: device,
                format: .bgra8Unorm,
                usage: .shaderRead
            ),
            uniforms: .neutral(),
            pipeline: sourcePipeline
        ) == nil
        let captureAlias = target(device: device, format: .bgra8Unorm)
        let captureAliasRejected = encoder.prepareSourceCapture(
            source: captureAlias,
            target: captureAlias,
            uniforms: .neutral(),
            pipeline: sourcePipeline
        ) == nil

        let clearTarget = target(device: device, fill: sentinel)
        let preparedClear = encoder.prepareInitialization(
            target: clearTarget,
            clear: clear
        )
        let clearPrepareHasNoSideEffect = pixels(clearTarget) == sentinel
        var clearCommandsAppended = false
        var clearGPUCompleted = false
        if let preparedClear, let command = queue.makeCommandBuffer() {
            clearCommandsAppended = encoder.encode(
                preparedClear,
                commandBuffer: command
            )
            clearGPUCompleted = completed(
                command,
                encoded: clearCommandsAppended
            )
        }
        let expectedClear: [UInt8] = Array(
            repeating: [255, 0, 255, 255],
            count: 4
        ).flatMap { $0 }
        let clearReadbackMatches = pixels(clearTarget) == expectedClear

        let copySource = texture(
            device: device,
            usage: .shaderRead,
            fill: sourceBytes
        )!
        let copyTarget = target(device: device, fill: sentinel)
        let preparedCopy = encoder.prepareCopy(
            source: copySource,
            target: copyTarget
        )
        let copyPrepareHasNoSideEffect = pixels(copyTarget) == sentinel
        var copyCommandsAppended = false
        var copyGPUCompleted = false
        if let preparedCopy, let command = queue.makeCommandBuffer() {
            copyCommandsAppended = encoder.encode(
                preparedCopy,
                commandBuffer: command
            )
            copyGPUCompleted = completed(
                command,
                encoded: copyCommandsAppended
            )
        }
        let copyReadbackMatches = pixels(copyTarget) == sourceBytes

        let r8Sentinel = [UInt8](repeating: 13, count: 4)
        let r8ClearTarget = target(
            device: device,
            format: .r8Unorm,
            fill: r8Sentinel
        )
        let preparedR8Clear = encoder.prepareInitialization(
            target: r8ClearTarget,
            clear: clear
        )
        var r8ClearEncoded = false
        var r8ClearGPUCompleted = false
        if let preparedR8Clear, let command = queue.makeCommandBuffer() {
            r8ClearEncoded = encoder.encode(preparedR8Clear, commandBuffer: command)
            r8ClearGPUCompleted = completed(command, encoded: r8ClearEncoded)
        }
        let r8ClearMatches = pixels(r8ClearTarget) == [255, 255, 255, 255]

        let r8SourceBytes: [UInt8] = [1, 63, 129, 255]
        let r8CopySource = texture(
            device: device,
            format: .r8Unorm,
            usage: .shaderRead,
            fill: r8SourceBytes
        )!
        let r8CopyTarget = target(
            device: device,
            format: .r8Unorm,
            fill: r8Sentinel
        )
        let preparedR8Copy = encoder.prepareCopy(
            source: r8CopySource,
            target: r8CopyTarget
        )
        var r8CopyEncoded = false
        var r8CopyGPUCompleted = false
        if let preparedR8Copy, let command = queue.makeCommandBuffer() {
            r8CopyEncoded = encoder.encode(preparedR8Copy, commandBuffer: command)
            r8CopyGPUCompleted = completed(command, encoded: r8CopyEncoded)
        }
        let r8CopyMatches = pixels(r8CopyTarget) == r8SourceBytes

        let wrongExtent = texture(
            device: device,
            width: 1,
            usage: .shaderRead
        )!
        let extentMismatchRejected = encoder.prepareCopy(
            source: wrongExtent,
            target: target(device: device)
        ) == nil
        let wrongFormat = texture(
            device: device,
            format: .bgra8Unorm,
            usage: .shaderRead
        )!
        let formatMismatchRejected = encoder.prepareCopy(
            source: wrongFormat,
            target: target(device: device)
        ) == nil
        let alias = target(device: device)
        let aliasRejected = encoder.prepareCopy(
            source: alias,
            target: alias
        ) == nil
        let unreadableSource = texture(
            device: device,
            usage: .renderTarget
        )!
        let sourceUsageRejected = encoder.prepareCopy(
            source: unreadableSource,
            target: target(device: device)
        ) == nil
        let noRenderTarget = target(device: device, usage: .shaderRead)
        let targetRenderUsageRejected = encoder.prepareCopy(
            source: copySource,
            target: noRenderTarget
        ) == nil
        let initializationRenderUsageRejected = encoder.prepareInitialization(
            target: noRenderTarget,
            clear: clear
        ) == nil
        let noShaderRead = target(device: device, usage: .renderTarget)
        let targetReadUsageRejected = encoder.prepareCopy(
            source: copySource,
            target: noShaderRead
        ) == nil
        let initializationReadUsageRejected = encoder.prepareInitialization(
            target: noShaderRead,
            clear: clear
        ) == nil
        let mipSource = texture(
            device: device,
            mipmapped: true,
            usage: .shaderRead
        )!
        let sourceMipRejected = encoder.prepareCopy(
            source: mipSource,
            target: target(device: device)
        ) == nil
        let mipTarget = target(device: device, mipmapped: true)
        let targetMipRejected = encoder.prepareCopy(
            source: copySource,
            target: mipTarget
        ) == nil
        let unsupportedTarget = target(device: device, format: .rg8Unorm)
        let unsupportedTargetFormatRejected = encoder.prepareInitialization(
            target: unsupportedTarget,
            clear: clear
        ) == nil
        let multisample = multisampleTexture(device: device)
        let sampleCountRejected = multisample.map {
            encoder.prepareCopy(
                source: $0,
                target: target(device: device)
            ) == nil
        } ?? true
        let arraySource = arrayTexture(device: device, usage: .shaderRead)
        let sourceTypeRejected = arraySource.map {
            encoder.prepareCopy(
                source: $0,
                target: target(device: device)
            ) == nil
        } ?? true
        let arrayTarget = arrayTexture(
            device: device,
            usage: [.renderTarget, .shaderRead]
        )
        let targetTypeRejected = arrayTarget.map {
            encoder.prepareInitialization(target: $0, clear: clear) == nil
        } ?? true
        let nonFiniteClearRejected = encoder.prepareInitialization(
            target: target(device: device),
            clear: .init(red: .nan, green: 0, blue: 0, alpha: 0)
        ) == nil

        let ownerTarget = target(device: device, fill: sentinel)
        let ownerPrepared = encoder.prepareCopy(
            source: copySource,
            target: ownerTarget
        )!
        var foreignOwnerRejected = false
        var foreignOwnerNoPartialWrite = false
        if let command = queue.makeCommandBuffer() {
            foreignOwnerRejected = !otherOwner.encode(
                ownerPrepared,
                commandBuffer: command
            )
            let emptyCompleted = emptyCommandCompleted(command)
            foreignOwnerNoPartialWrite = emptyCompleted
                && pixels(ownerTarget) == sentinel
        }

        let queueTarget = target(device: device, fill: sentinel)
        let queuePrepared = encoder.prepareCopy(
            source: copySource,
            target: queueTarget
        )!
        var wrongQueueRejected = false
        var wrongQueueNoPartialWrite = false
        if let command = otherQueue.makeCommandBuffer() {
            wrongQueueRejected = !encoder.encode(
                queuePrepared,
                commandBuffer: command
            )
            let emptyCompleted = emptyCommandCompleted(command)
            wrongQueueNoPartialWrite = emptyCompleted
                && pixels(queueTarget) == sentinel
        }

        let resetTarget = target(device: device, fill: sentinel)
        let resetPrepared = encoder.prepareInitialization(
            target: resetTarget,
            clear: clear
        )!
        encoder.reset()
        var resetRejected = false
        var resetNoPartialWrite = false
        if let command = queue.makeCommandBuffer() {
            resetRejected = !encoder.encode(
                resetPrepared,
                commandBuffer: command
            )
            let emptyCompleted = emptyCommandCompleted(command)
            resetNoPartialWrite = emptyCompleted
                && pixels(resetTarget) == sentinel
        }
        let prepareAfterReset = encoder.prepareInitialization(
            target: resetTarget,
            clear: clear
        ) != nil

        let committedTarget = target(device: device, fill: sentinel)
        let committedPrepared = encoder.prepareCopy(
            source: copySource,
            target: committedTarget
        )!
        var committedBufferRejected = false
        var committedBufferNoPartialWrite = false
        if let command = queue.makeCommandBuffer() {
            command.commit()
            command.waitUntilCompleted()
            committedBufferRejected = !encoder.encode(
                committedPrepared,
                commandBuffer: command
            )
            committedBufferNoPartialWrite = pixels(committedTarget) == sentinel
        }

        let failedPrepareTarget = target(device: device, fill: sentinel)
        let failedPrepare = encoder.prepareCopy(
            source: wrongExtent,
            target: failedPrepareTarget
        ) == nil
        let failedPrepareHasNoSideEffect = failedPrepare
            && pixels(failedPrepareTarget) == sentinel

        var crossDeviceRejected = true
        var crossDeviceExercised = false
        if let otherDevice = MTLCopyAllDevices().first(where: {
            $0.registryID != device.registryID
        }), let otherTarget = texture(
            device: otherDevice,
            usage: [.renderTarget, .shaderRead]
        ) {
            crossDeviceExercised = true
            crossDeviceRejected = encoder.prepareCopy(
                source: copySource,
                target: otherTarget
            ) == nil
        }

        let results: [String: Bool] = [
            "metalAvailable": true,
            "sourceCapturePrepared": preparedCapture?.kind == .sourceCapture,
            "sourceCapturePrepareHasNoSideEffect":
                capturePrepareHasNoSideEffect,
            "sourceCaptureCommandsAppended": captureCommandsAppended,
            "sourceCaptureGPUCompleted": captureGPUCompleted,
            "sourceCaptureUsesFullTargetRenderDraw":
                captureFullTargetDrawMatches,
            "sourceCaptureUnreadableSourceRejected":
                captureUnreadableSourceRejected,
            "sourceCaptureTargetFormatRejected": captureTargetFormatRejected,
            "sourceCaptureTargetUsageRejected": captureTargetUsageRejected,
            "sourceCaptureAliasRejected": captureAliasRejected,
            "clearPrepared": preparedClear?.kind == .initialization,
            "clearPrepareHasNoSideEffect": clearPrepareHasNoSideEffect,
            "clearCommandsAppended": clearCommandsAppended,
            "clearGPUCompleted": clearGPUCompleted,
            "clearReadbackMatches": clearReadbackMatches,
            "copyPrepared": preparedCopy?.kind == .copy,
            "copyPrepareHasNoSideEffect": copyPrepareHasNoSideEffect,
            "copyCommandsAppended": copyCommandsAppended,
            "copyGPUCompleted": copyGPUCompleted,
            "copyReadbackMatches": copyReadbackMatches,
            "r8ClearPrepared": preparedR8Clear?.kind == .initialization,
            "r8ClearEncoded": r8ClearEncoded,
            "r8ClearGPUCompleted": r8ClearGPUCompleted,
            "r8ClearStoresRedChannel": r8ClearMatches,
            "r8CopyPrepared": preparedR8Copy?.kind == .copy,
            "r8CopyEncoded": r8CopyEncoded,
            "r8CopyGPUCompleted": r8CopyGPUCompleted,
            "r8CopyReadbackMatches": r8CopyMatches,
            "extentMismatchRejected": extentMismatchRejected,
            "formatMismatchRejected": formatMismatchRejected,
            "aliasRejected": aliasRejected,
            "sourceUsageRejected": sourceUsageRejected,
            "targetRenderUsageRejected": targetRenderUsageRejected,
            "initializationRenderUsageRejected": initializationRenderUsageRejected,
            "targetReadUsageRejected": targetReadUsageRejected,
            "initializationReadUsageRejected": initializationReadUsageRejected,
            "sourceMipRejected": sourceMipRejected,
            "targetMipRejected": targetMipRejected,
            "unsupportedTargetFormatRejected": unsupportedTargetFormatRejected,
            "sampleCountRejectedWhenAvailable": sampleCountRejected,
            "sourceTypeRejectedWhenAvailable": sourceTypeRejected,
            "targetTypeRejectedWhenAvailable": targetTypeRejected,
            "nonFiniteClearRejected": nonFiniteClearRejected,
            "foreignOwnerRejected": foreignOwnerRejected,
            "foreignOwnerHasNoPartialWrite": foreignOwnerNoPartialWrite,
            "wrongQueueRejected": wrongQueueRejected,
            "wrongQueueHasNoPartialWrite": wrongQueueNoPartialWrite,
            "resetInvalidatesPrepared": resetRejected,
            "resetHasNoPartialWrite": resetNoPartialWrite,
            "prepareAfterReset": prepareAfterReset,
            "committedBufferRejected": committedBufferRejected,
            "committedBufferHasNoPartialWrite": committedBufferNoPartialWrite,
            "failedPrepareHasNoSideEffect": failedPrepareHasNoSideEffect,
            "crossDeviceRejectedWhenAvailable": crossDeviceRejected,
        ]
        let payload: [String: Any] = [
            "results": results,
            "crossDeviceExercised": crossDeviceExercised,
            "multisampleExercised": multisample != nil,
            "arrayTextureExercised": arraySource != nil && arrayTarget != nil,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        FileHandle.standardOutput.write(data)
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneGraphResourcePassEncoderTests(unittest.TestCase):
    def test_resource_commands_are_prepared_before_encoding(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-graph-resource-pass-"
        ) as directory:
            root = Path(directory)
            support = root / "Support.swift"
            harness = root / "Harness.swift"
            binary = root / "graph-resource-pass-test"
            support.write_text(SUPPORT, encoding="utf-8")
            harness.write_text(HARNESS, encoding="utf-8")
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
            environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
            compilation = subprocess.run(
                [
                    "xcrun",
                    "--sdk",
                    "macosx",
                    "swiftc",
                    "-parse-as-library",
                    str(support),
                    str(ENCODER_SOURCE),
                    str(harness),
                    "-framework",
                    "Metal",
                    "-module-cache-path",
                    str(root / "module-cache"),
                    "-o",
                    str(binary),
                ],
                cwd=REPOSITORY_ROOT,
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary)],
                cwd=REPOSITORY_ROOT,
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
        payload = json.loads(completed.stdout)
        results = payload["results"]
        if not results["metalAvailable"]:
            self.skipTest("Metal is unavailable")
        self.assertEqual(
            [name for name, passed in results.items() if not passed],
            [],
            payload,
        )


if __name__ == "__main__":
    unittest.main()
