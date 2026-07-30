#!/usr/bin/env python3
"""GPU pixel and fail-closed gates for project-owned Depth Parallax."""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SOURCE_ROOT / "Resources/SceneTextureSampling.swift",
    SOURCE_ROOT / "Resources/SceneTextureUVTransform.swift",
    SOURCE_ROOT / "Resources/SceneTextureCandidate.swift",
    SOURCE_ROOT / "Resources/SceneTextureSlotBinding.swift",
    SOURCE_ROOT / "Resources/SceneDepthParallaxEffectTextureLoader.swift",
    SOURCE_ROOT / "Effects/SceneDepthParallaxPipeline.swift",
    SOURCE_ROOT / "Effects/SceneDepthParallaxRenderer.swift",
]


HARNESS = r'''
import CoreGraphics
import Foundation
import Metal
import simd

enum SceneTextureLoadPurpose: Hashable {
    case premultipliedColor
    case straightAlbedo
    case preservedChannels
    case mask
    case noise
    case flow
    case phase
    case normal
    case depth
}

enum SceneDepthParallaxQuality: Int {
    case basic = 0
    case occlusionPerformance = 1
    case occlusionQuality = 2

    var sampleCount: Int {
        switch self {
        case .basic: 1
        case .occlusionPerformance: 24
        case .occlusionQuality: 64
        }
    }
}

struct SceneDepthParallaxExecutionPlan {
    let depthTexturePath: String
    let scale: SIMD2<Float>
    let sensitivity: Float
    let center: Float
    let quality: SceneDepthParallaxQuality
}

struct SceneRenderDescriptor {
    struct EffectDescriptor {
        struct PassDescriptor {
            let textureSlots: [String?]
        }
        let id: String
        let file: String
        let passes: [PassDescriptor]
    }
    struct Layer {
        let effects: [EffectDescriptor]
    }
}

struct SceneTexturePathResolver {
    func resolveTextureFile(named path: String) -> URL? { nil }
}

final class SceneTextureLoader {}

struct SceneEffectTextureLoadResult {
    let candidate: SceneTextureCandidate?
    let message: String
}

enum SceneLayerEffectTextureLoader {
    static func loadTextureCandidate(
        url: URL?,
        label: String,
        purpose: SceneTextureLoadPurpose,
        loader: SceneTextureLoader,
        device: MTLDevice
    ) -> SceneEffectTextureLoadResult {
        .init(candidate: nil, message: "")
    }
}

@main
enum Harness {
    struct RenderResult {
        let encoded: Bool
        let bytes: [UInt8]
    }

    struct Difference {
        let sum: Int
        let changedBytes: Int
    }

    static let width = 128
    static let height = 96
    static let depthPath = "materials/depth_map"

    static func texture(
        device: MTLDevice,
        format: MTLPixelFormat,
        width: Int = width,
        height: Int = height,
        usage: MTLTextureUsage
    ) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = usage
        return device.makeTexture(descriptor: descriptor)!
    }

    static func sourceTexture(device: MTLDevice) -> MTLTexture {
        let result = texture(
            device: device,
            format: .bgra8Unorm,
            usage: [.shaderRead]
        )
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let offset = y * bytesPerRow + x * 4
                bytes[offset] = ((x / 2 + y / 3) & 1) == 0 ? 0 : 255
                bytes[offset + 1] = UInt8(y * 255 / (height - 1))
                bytes[offset + 2] = UInt8(x * 255 / (width - 1))
                bytes[offset + 3] = 255
            }
        }
        result.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: bytesPerRow
        )
        return result
    }

    static func depthTexture(
        device: MTLDevice,
        value: UInt8,
        format: MTLPixelFormat = .r8Unorm
    ) -> MTLTexture {
        let result = texture(
            device: device,
            format: format,
            usage: [.shaderRead]
        )
        if format == .r8Unorm {
            let bytes = [UInt8](repeating: value, count: width * height)
            result.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: bytes,
                bytesPerRow: width
            )
        } else {
            let bytes = [UInt8](repeating: value, count: width * height * 4)
            result.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: bytes,
                bytesPerRow: width * 4
            )
        }
        return result
    }

    static func targetTexture(device: MTLDevice) -> MTLTexture {
        texture(
            device: device,
            format: .bgra8Unorm,
            usage: [.shaderRead, .renderTarget]
        )
    }

    static func binding(
        depth: MTLTexture,
        purpose: SceneTextureLoadPurpose = .depth,
        transform: SceneTextureUVTransform = .identity,
        sampling: SceneTextureSampling = .linearClamp
    ) -> SceneTextureSlotBinding? {
        let size = CGSize(width: depth.width, height: depth.height)
        let candidate = SceneTextureCandidate(
            texture: depth,
            identity: .builtIn(name: "depth-fixture"),
            generation: .immutable(revision: 1),
            purpose: purpose,
            physicalSize: size,
            mappedSize: size,
            uvTransform: transform,
            sampling: sampling
        )
        return SceneTextureSlotBinding(slotIndex: 1, candidate: candidate)
    }

    static func resources(
        depth: MTLTexture,
        purpose: SceneTextureLoadPurpose = .depth,
        path: String = depthPath,
        transform: SceneTextureUVTransform = .identity,
        sampling: SceneTextureSampling = .linearClamp
    ) -> SceneDepthParallaxEffectTextures {
        .init(
            depthBinding: binding(
                depth: depth,
                purpose: purpose,
                transform: transform,
                sampling: sampling
            ),
            depthPath: path
        )
    }

    static func plan(
        quality: SceneDepthParallaxQuality
    ) -> SceneDepthParallaxExecutionPlan {
        .init(
            depthTexturePath: depthPath,
            scale: SIMD2(repeating: 2),
            sensitivity: 5,
            center: 0.5,
            quality: quality
        )
    }

    static func bytes(_ texture: MTLTexture) -> [UInt8] {
        let bytesPerRow = texture.width * 4
        var result = [UInt8](
            repeating: 0,
            count: bytesPerRow * texture.height
        )
        texture.getBytes(
            &result,
            bytesPerRow: bytesPerRow,
            from: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0
        )
        return result
    }

    static func render(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneDepthParallaxPipeline,
        source: MTLTexture,
        depth: MTLTexture,
        pointer: SIMD2<Float>,
        inside: Bool = true,
        quality: SceneDepthParallaxQuality = .basic,
        purpose: SceneTextureLoadPurpose = .depth,
        path: String = depthPath,
        transform: SceneTextureUVTransform = .identity,
        sampling: SceneTextureSampling = .linearClamp
    ) -> RenderResult {
        let target = targetTexture(device: device)
        guard let commandBuffer = queue.makeCommandBuffer() else {
            return .init(encoded: false, bytes: [])
        }
        let rendered = SceneDepthParallaxRenderer.render(
            plan: plan(quality: quality),
            resources: resources(
                depth: depth,
                purpose: purpose,
                path: path,
                transform: transform,
                sampling: sampling
            ),
            sourceTexture: source,
            target: target,
            cursorUV: pointer,
            pointerIsInside: inside,
            pipeline: pipeline,
            commandBuffer: commandBuffer
        )
        guard rendered != nil else {
            return .init(encoded: false, bytes: [])
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return .init(
            encoded: commandBuffer.status == .completed,
            bytes: bytes(target)
        )
    }

    static func difference(_ lhs: [UInt8], _ rhs: [UInt8]) -> Difference {
        guard lhs.count == rhs.count else {
            return .init(sum: Int.max, changedBytes: Int.max)
        }
        var sum = 0
        var changed = 0
        for (left, right) in zip(lhs, rhs) {
            let delta = abs(Int(left) - Int(right))
            sum += delta
            if delta != 0 { changed += 1 }
        }
        return .init(sum: sum, changedBytes: changed)
    }

    static func centerBGRA(_ bytes: [UInt8]) -> SIMD4<Int> {
        let offset = ((height / 2) * width + width / 2) * 4
        return SIMD4(
            Int(bytes[offset]),
            Int(bytes[offset + 1]),
            Int(bytes[offset + 2]),
            Int(bytes[offset + 3])
        )
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pipeline = SceneDepthParallaxPipeline(device: device) else {
            print(#"{"available":false}"#)
            return
        }

        let source = sourceTexture(device: device)
        let lowDepth = depthTexture(device: device, value: 0)
        let midDepth = depthTexture(device: device, value: 94)
        let highDepth = depthTexture(device: device, value: 255)
        let wrongFormatDepth = depthTexture(
            device: device,
            value: 255,
            format: .bgra8Unorm
        )

        let neutral = render(
            device: device, queue: queue, pipeline: pipeline,
            source: source, depth: highDepth,
            pointer: SIMD2(repeating: 0.5)
        )
        let outside = render(
            device: device, queue: queue, pipeline: pipeline,
            source: source, depth: highDepth,
            pointer: .zero, inside: false
        )
        let left = render(
            device: device, queue: queue, pipeline: pipeline,
            source: source, depth: highDepth,
            pointer: SIMD2(0, 0.5)
        )
        let right = render(
            device: device, queue: queue, pipeline: pipeline,
            source: source, depth: highDepth,
            pointer: SIMD2(1, 0.5)
        )
        let yNegative = render(
            device: device, queue: queue, pipeline: pipeline,
            source: source, depth: highDepth,
            pointer: SIMD2(0.5, 0)
        )
        let yPositive = render(
            device: device, queue: queue, pipeline: pipeline,
            source: source, depth: highDepth,
            pointer: SIMD2(0.5, 1)
        )
        let low = render(
            device: device, queue: queue, pipeline: pipeline,
            source: source, depth: lowDepth,
            pointer: SIMD2(1, 0.5)
        )
        let high = render(
            device: device, queue: queue, pipeline: pipeline,
            source: source, depth: highDepth,
            pointer: SIMD2(1, 0.5)
        )
        let basic = render(
            device: device, queue: queue, pipeline: pipeline,
            source: source, depth: midDepth,
            pointer: SIMD2(1, 0.5), quality: .basic
        )
        let performance = render(
            device: device, queue: queue, pipeline: pipeline,
            source: source, depth: midDepth,
            pointer: SIMD2(1, 0.5), quality: .occlusionPerformance
        )
        let quality = render(
            device: device, queue: queue, pipeline: pipeline,
            source: source, depth: midDepth,
            pointer: SIMD2(1, 0.5), quality: .occlusionQuality
        )

        let wrongPurpose = render(
            device: device, queue: queue, pipeline: pipeline,
            source: source, depth: highDepth,
            pointer: SIMD2(1, 0.5), purpose: .mask
        )
        let wrongFormat = render(
            device: device, queue: queue, pipeline: pipeline,
            source: source, depth: wrongFormatDepth,
            pointer: SIMD2(1, 0.5)
        )
        let wrongPath = render(
            device: device, queue: queue, pipeline: pipeline,
            source: source, depth: highDepth,
            pointer: SIMD2(1, 0.5), path: "materials/other"
        )
        let rotatedUV = render(
            device: device, queue: queue, pipeline: pipeline,
            source: source, depth: highDepth,
            pointer: SIMD2(1, 0.5),
            transform: .init(
                origin: .zero,
                xAxis: SIMD2(0, 1),
                yAxis: SIMD2(-1, 0)
            )
        )
        let clampBorder = render(
            device: device, queue: queue, pipeline: pipeline,
            source: source, depth: highDepth,
            pointer: SIMD2(1, 0.5),
            sampling: SceneTextureSampling(texFlags: 8)
        )

        let leftCenter = centerBGRA(left.bytes)
        let rightCenter = centerBGRA(right.bytes)
        let negativeCenter = centerBGRA(yNegative.bytes)
        let positiveCenter = centerBGRA(yPositive.bytes)
        let lowCenter = centerBGRA(low.bytes)
        let highCenter = centerBGRA(high.bytes)
        let basicPerformance = difference(basic.bytes, performance.bytes)
        let performanceQuality = difference(performance.bytes, quality.bytes)
        let basicQuality = difference(basic.bytes, quality.bytes)

        let result: [String: Any] = [
            "available": true,
            "validRendersEncoded": [
                neutral, outside, left, right, yNegative, yPositive,
                low, high, basic, performance, quality,
            ].allSatisfy { $0.encoded },
            "outsidePointerIsNeutral": outside.bytes == neutral.bytes,
            "horizontalDirection": rightCenter.z > leftCenter.z,
            "verticalDirection": positiveCenter.y > negativeCenter.y,
            "depthChangesDirection": highCenter.z > lowCenter.z,
            "qualityBranchesDiffer": [
                basicPerformance.changedBytes,
                performanceQuality.changedBytes,
                basicQuality.changedBytes,
            ].allSatisfy { $0 > 100 },
            "qualityBranchesCarryPixels": [
                basicPerformance.sum,
                performanceQuality.sum,
                basicQuality.sum,
            ].allSatisfy { $0 > 100 },
            "invalidBindingsRejected": [
                wrongPurpose, wrongFormat, wrongPath, rotatedUV, clampBorder,
            ].allSatisfy { !$0.encoded },
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneDepthParallaxPipelineTests(unittest.TestCase):
    def test_neutral_direction_depth_quality_and_atomic_rejections(self) -> None:
        if shutil.which("xcrun") is None:
            self.skipTest("xcrun is unavailable")
        with tempfile.TemporaryDirectory(
            prefix="mwx-depth-parallax-pipeline-",
            dir="/private/tmp",
        ) as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            binary = root / "depth-parallax-pipeline"
            harness.write_text(HARNESS, encoding="utf-8")
            compilation = subprocess.run(
                [
                    "xcrun",
                    "--sdk",
                    "macosx",
                    "swiftc",
                    *(str(path) for path in SWIFT_SOURCES),
                    str(harness),
                    "-framework",
                    "Metal",
                    "-module-cache-path",
                    str(root / "module-cache"),
                    "-o",
                    str(binary),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary)],
                check=True,
                capture_output=True,
                text=True,
            )
        result = json.loads(completed.stdout)
        if not result.get("available", False):
            self.skipTest("Metal device is unavailable")
        self.assertTrue(all(result.values()), result)


if __name__ == "__main__":
    unittest.main()
