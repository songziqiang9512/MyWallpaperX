#!/usr/bin/env python3

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
    SOURCE_ROOT / "Effects/SceneBlendModeShaderSource.swift",
    SOURCE_ROOT / "Effects/SceneWaterFlowPipeline.swift",
    SOURCE_ROOT / "Effects/SceneGodraysPipeline.swift",
    SOURCE_ROOT / "Effects/SceneGodraysPipeline+Encoding.swift",
    SOURCE_ROOT / "Effects/SceneTintPipeline.swift",
]

HARNESS = r'''
import Foundation
import Metal
import simd

struct SceneWaterFlowExecutionPlan {
    let speed: Float
    let strength: Float
    let phaseScale: Float
    let phaseFeather: Float?
}

struct SceneGodraysPlan {
    let threshold: Float
    let noiseAmount: Float
    let noiseScale: Float
    let noiseSpeed: Float
    let noiseSmoothness: Float
    let center: SIMD2<Float>
    let colorRays: SIMD3<Float>
    let rayLength: Float
    let rayIntensity: Float
    let samples50: Bool
    let kernel13: Bool
    let direction: Float?
    let usesDirectionalGaussianKernel: Bool
    let blurScaleX: SIMD2<Float>
    let blurScaleY: SIMD2<Float>
    let blendMode: Int
}

@main
enum Harness {
    static func texture(
        device: MTLDevice,
        format: MTLPixelFormat,
        mipmapped: Bool,
        usage: MTLTextureUsage
    ) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format,
            width: 8,
            height: 8,
            mipmapped: mipmapped
        )
        descriptor.storageMode = .shared
        descriptor.usage = usage
        return device.makeTexture(descriptor: descriptor)!
    }

    static func waterFlowAcceptsAuxiliaryMips(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneWaterFlowPipeline
    ) -> Bool {
        let source = texture(
            device: device, format: .bgra8Unorm,
            mipmapped: false, usage: .shaderRead
        )
        let target = texture(
            device: device, format: .bgra8Unorm,
            mipmapped: false, usage: .renderTarget
        )
        let flow = texture(
            device: device, format: .rg8Unorm,
            mipmapped: true, usage: .shaderRead
        )
        let phase = texture(
            device: device, format: .r8Unorm,
            mipmapped: true, usage: .shaderRead
        )
        let command = queue.makeCommandBuffer()!
        let accepted = pipeline.encode(
            source: source,
            flowTexture: flow,
            phaseTexture: phase,
            target: target,
            plan: .init(speed: 0.2, strength: 1, phaseScale: 2, phaseFeather: nil),
            time: 1,
            maskUVScale: SIMD2(repeating: 1),
            commandBuffer: command
        )
        command.commit()
        command.waitUntilCompleted()
        return accepted && command.status == .completed
    }

    static func waterFlowRejectsMipmappedTarget(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneWaterFlowPipeline
    ) -> Bool {
        let source = texture(
            device: device, format: .bgra8Unorm,
            mipmapped: false, usage: .shaderRead
        )
        let target = texture(
            device: device, format: .bgra8Unorm,
            mipmapped: true, usage: .renderTarget
        )
        let flow = texture(
            device: device, format: .rg8Unorm,
            mipmapped: false, usage: .shaderRead
        )
        let phase = texture(
            device: device, format: .r8Unorm,
            mipmapped: false, usage: .shaderRead
        )
        let command = queue.makeCommandBuffer()!
        return !pipeline.encode(
            source: source,
            flowTexture: flow,
            phaseTexture: phase,
            target: target,
            plan: .init(speed: 0.2, strength: 1, phaseScale: 2, phaseFeather: nil),
            time: 1,
            maskUVScale: SIMD2(repeating: 1),
            commandBuffer: command
        )
    }

    static func godraysAcceptsAuxiliaryMips(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneGodraysPipeline
    ) -> Bool {
        let source = texture(
            device: device, format: .bgra8Unorm,
            mipmapped: false, usage: .shaderRead
        )
        let target = texture(
            device: device, format: .bgra8Unorm,
            mipmapped: false, usage: .renderTarget
        )
        let mask = texture(
            device: device, format: .r8Unorm,
            mipmapped: true, usage: .shaderRead
        )
        let noise = texture(
            device: device, format: .rgba8Unorm,
            mipmapped: true, usage: .shaderRead
        )
        let command = queue.makeCommandBuffer()!
        let accepted = pipeline.encodeDownsample(
            source: source,
            mask: mask,
            maskUVScale: SIMD2(repeating: 1),
            noise: noise,
            target: target,
            plan: godraysPlan(),
            time: 1,
            commandBuffer: command
        )
        command.commit()
        command.waitUntilCompleted()
        return accepted && command.status == .completed
    }

    static func godraysRejectsMipmappedTarget(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneGodraysPipeline
    ) -> Bool {
        let source = texture(
            device: device, format: .bgra8Unorm,
            mipmapped: false, usage: .shaderRead
        )
        let target = texture(
            device: device, format: .bgra8Unorm,
            mipmapped: true, usage: .renderTarget
        )
        let command = queue.makeCommandBuffer()!
        return !pipeline.encodeDownsample(
            source: source,
            mask: nil,
            maskUVScale: SIMD2(repeating: 1),
            noise: nil,
            target: target,
            plan: godraysPlan(),
            time: 1,
            commandBuffer: command
        )
    }

    static func tintAcceptsAuxiliaryMips(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneTintPipeline
    ) -> Bool {
        let source = texture(
            device: device, format: .bgra8Unorm,
            mipmapped: false, usage: .shaderRead
        )
        let target = texture(
            device: device, format: .bgra8Unorm,
            mipmapped: false, usage: .renderTarget
        )
        let mask = texture(
            device: device, format: .r8Unorm,
            mipmapped: true, usage: .shaderRead
        )
        let command = queue.makeCommandBuffer()!
        let accepted = pipeline.encode(
            source: source,
            mask: mask,
            target: target,
            color: SIMD3(repeating: 1),
            alpha: 1,
            blendMode: 9,
            commandBuffer: command
        )
        command.commit()
        command.waitUntilCompleted()
        return accepted && command.status == .completed
    }

    static func godraysPlan() -> SceneGodraysPlan {
        .init(
            threshold: 0.5,
            noiseAmount: 0.4,
            noiseScale: 3,
            noiseSpeed: 0.15,
            noiseSmoothness: 0.2,
            center: SIMD2(repeating: 0.5),
            colorRays: SIMD3(repeating: 1),
            rayLength: 0.5,
            rayIntensity: 1,
            samples50: false,
            kernel13: false,
            direction: nil,
            usesDirectionalGaussianKernel: false,
            blurScaleX: SIMD2(repeating: 1),
            blurScaleY: SIMD2(repeating: 1),
            blendMode: 9
        )
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let waterFlow = SceneWaterFlowPipeline(device: device),
              let godrays = SceneGodraysPipeline(device: device),
              let tint = SceneTintPipeline(device: device) else {
            print("SKIP")
            return
        }
        let result = [
            "waterFlowAuxiliaryMips": waterFlowAcceptsAuxiliaryMips(
                device: device, queue: queue, pipeline: waterFlow
            ),
            "waterFlowMipmappedTargetRejected": waterFlowRejectsMipmappedTarget(
                device: device, queue: queue, pipeline: waterFlow
            ),
            "godraysAuxiliaryMips": godraysAcceptsAuxiliaryMips(
                device: device, queue: queue, pipeline: godrays
            ),
            "godraysMipmappedTargetRejected": godraysRejectsMipmappedTarget(
                device: device, queue: queue, pipeline: godrays
            ),
            "tintAuxiliaryMips": tintAcceptsAuxiliaryMips(
                device: device, queue: queue, pipeline: tint
            ),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(data: data, encoding: .utf8)!)
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneEffectAuxiliaryMipTests(unittest.TestCase):
    def test_mipmapped_auxiliary_textures_are_sampleable(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-effect-mips-") as directory:
            root = Path(directory)
            harness = root / "main.swift"
            executable = root / "effect-mips-test"
            module_cache = root / "module-cache"
            harness.write_text(HARNESS, encoding="utf-8")
            subprocess.run(
                [
                    "swiftc",
                    "-parse-as-library",
                    *map(str, SWIFT_SOURCES),
                    str(harness),
                    "-module-cache-path",
                    str(module_cache),
                    "-o",
                    str(executable),
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            completed = subprocess.run(
                [str(executable)],
                check=True,
                capture_output=True,
                text=True,
            )
            if completed.stdout.strip() == "SKIP":
                self.skipTest("Metal is unavailable")
            self.assertEqual(
                json.loads(completed.stdout),
                {
                    "godraysAuxiliaryMips": True,
                    "godraysMipmappedTargetRejected": True,
                    "tintAuxiliaryMips": True,
                    "waterFlowAuxiliaryMips": True,
                    "waterFlowMipmappedTargetRejected": True,
                },
            )


if __name__ == "__main__":
    unittest.main()
