#!/usr/bin/env python3

"""GPU pixels for REFRACT normal storage and single-coverage compositing."""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneTexDataReader.swift",
    SCENE_ROOT / "Format/SceneTexContainer.swift",
    SCENE_ROOT / "Format/SceneBCTextureDecoder.swift",
    SCENE_ROOT / "Resources/SceneImageTextureUploader.swift",
    SCENE_ROOT / "Resources/SceneCompressedTextureUploader.swift",
    SCENE_ROOT / "Resources/SceneTextureMipUploader.swift",
    SCENE_ROOT / "Resources/SceneTextureLoader.swift",
    SCENE_ROOT / "Resources/SceneTextureSampling.swift",
    SCENE_ROOT / "Rendering/SceneMatrix.swift",
    SCENE_ROOT / "Rendering/SceneFramebufferSnapshot.swift",
    SCENE_ROOT / "Particles/SceneParticleDefinition.swift",
    SCENE_ROOT / "Particles/SceneParticleDefinitionParser.swift",
    SCENE_ROOT / "Particles/SceneParticleRenderSupport.swift",
    SCENE_ROOT / "Particles/SceneParticleSimulationSupport.swift",
    SCENE_ROOT / "Particles/SceneParticleStepSnapshotRecorder.swift",
    SCENE_ROOT / "Particles/SceneParticleRopeTrailPlan.swift",
    SCENE_ROOT / "Particles/SceneParticleMetalInstanceBuffer.swift",
    SCENE_ROOT / "Particles/SceneParticleRefractionBinding.swift",
    SCENE_ROOT / "Particles/SceneParticleRefractionTextureLoader.swift",
    SCENE_ROOT / "Particles/SceneParticleShaderSource.swift",
    SCENE_ROOT / "Particles/SceneParticleSamplerStateSet.swift",
    SCENE_ROOT / "Particles/SceneParticleMetalPipeline.swift",
    SCENE_ROOT / "Particles/SceneParticleTextureSource.swift",
]

HARNESS = r'''
import Foundation
import Metal
import simd

final class SceneVideoTextureSource {
    init?(
        layerID: Int,
        mp4PayloadData: Data,
        cacheDirectory: URL,
        device: MTLDevice
    ) { return nil }
}

nonisolated struct SceneParticleRefractionDeclaration {
    let normalTextureSource: SceneParticleTextureSource
    let amount: Float
    let overbright: Float
}

struct SceneSpriteAnimation {
    init(frames: [SceneTexContainer.SpriteFrame]) {}
}

@main
enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("{\"available\":false}")
            return
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-refraction-pixels-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let loader = SceneTextureLoader()
        let dxt5nURL = directory.appendingPathComponent("packed-normal.tex")
        try makeDXT5nTex().write(to: dxt5nURL)
        let directDXT5nURL = directory.appendingPathComponent(
            "packed-normal-multi-image.tex"
        )
        try makeDirectDXT5nTex().write(to: directDXT5nURL)
        let decodedTexture = try loaded(loader.load(
            from: dxt5nURL,
            purpose: .normal,
            device: device
        ))
        let decoded = readPixel(decodedTexture)

        let rgbaURL = directory.appendingPathComponent("rgba-normal.tex")
        try makeRawTex(pixel: decoded).write(to: rgbaURL)

        let swappedURL = directory.appendingPathComponent("swapped-normal.tex")
        try makeRawTex(
            pixel: [decoded[0], decoded[3], decoded[2], decoded[1]]
        ).write(to: swappedURL)

        let neutralURL = directory.appendingPathComponent("neutral-normal.tex")
        try makeRawTex(pixel: [255, 128, 0, 128]).write(to: neutralURL)

        let opaqueURL = directory.appendingPathComponent("opaque-albedo.tex")
        try makeRawTex(pixel: [255, 255, 255, 255]).write(to: opaqueURL)

        let fractionalURL = directory.appendingPathComponent("fractional-albedo.tex")
        try makeRawTex(pixel: [255, 255, 255, 128]).write(to: fractionalURL)
        let dxt5n = try refraction(
            colorURL: opaqueURL,
            normalURL: dxt5nURL,
            amount: 0.25,
            loader: loader,
            device: device
        )
        let rgba = try refraction(
            colorURL: opaqueURL,
            normalURL: rgbaURL,
            amount: 0.25,
            loader: loader,
            device: device
        )
        let directDXT5n = try refraction(
            colorURL: opaqueURL,
            normalURL: directDXT5nURL,
            amount: 0.25,
            loader: loader,
            device: device
        )
        let swapped = try refraction(
            colorURL: opaqueURL,
            normalURL: swappedURL,
            amount: 0.25,
            loader: loader,
            device: device
        )
        let neutral = try refraction(
            colorURL: opaqueURL,
            normalURL: neutralURL,
            amount: 0.25,
            loader: loader,
            device: device
        )
        let fractional = try refraction(
            colorURL: fractionalURL,
            normalURL: neutralURL,
            amount: 0,
            loader: loader,
            device: device
        )

        let result: [String: Any] = [
            "available": true,
            "decodedDXT5n": decoded.map(Int.init),
            "loadedDXT5nNormal": readPixel(
                dxt5n.binding.normalTexture
            ).map(Int.init),
            "normalPixels": [
                "dxt5n": try draw(
                    device: device,
                    refraction: dxt5n,
                    particleAlpha: 1,
                    blendMode: .translucent,
                    gradientBackground: true
                ),
                "rgba": try draw(
                    device: device,
                    refraction: rgba,
                    particleAlpha: 1,
                    blendMode: .translucent,
                    gradientBackground: true
                ),
                "dxt5nDirect": try draw(
                    device: device,
                    refraction: directDXT5n,
                    particleAlpha: 1,
                    blendMode: .translucent,
                    gradientBackground: true
                ),
                "swapped": try draw(
                    device: device,
                    refraction: swapped,
                    particleAlpha: 1,
                    blendMode: .translucent,
                    gradientBackground: true
                ),
                "neutral": try draw(
                    device: device,
                    refraction: neutral,
                    particleAlpha: 1,
                    blendMode: .translucent,
                    gradientBackground: true
                ),
            ],
            "coveragePixels": [
                "translucent": try draw(
                    device: device,
                    refraction: fractional,
                    particleAlpha: 0.5,
                    blendMode: .translucent,
                    gradientBackground: false
                ),
                "additive": try draw(
                    device: device,
                    refraction: fractional,
                    particleAlpha: 0.5,
                    blendMode: .additive,
                    gradientBackground: false
                ),
                "albedo": readPixel(fractional.color).map(Int.init),
            ],
        ]
        let output = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: output, as: UTF8.self))
    }

    private static func draw(
        device: MTLDevice,
        refraction: SceneParticleRefractionTextureLoader.Loaded,
        particleAlpha: Float,
        blendMode: SceneParticlePipelineBlendMode,
        gradientBackground: Bool
    ) throws -> [Int] {
        let size = 32
        guard let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue(),
              let command = queue.makeCommandBuffer() else {
            throw HarnessError.gpu
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: size,
            height: size,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead]
        guard let background = device.makeTexture(descriptor: descriptor),
              let target = device.makeTexture(descriptor: descriptor) else {
            throw HarnessError.gpu
        }
        var backgroundBytes = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0 ..< size {
            for x in 0 ..< size {
                let offset = (y * size + x) * 4
                if gradientBackground {
                    backgroundBytes[offset] = UInt8(20 + x * 5)
                    backgroundBytes[offset + 1] = UInt8(30 + y * 3)
                    backgroundBytes[offset + 2] = 40
                } else {
                    backgroundBytes[offset] = 200
                    backgroundBytes[offset + 1] = 100
                    backgroundBytes[offset + 2] = 50
                }
                backgroundBytes[offset + 3] = 255
            }
        }
        background.replace(
            region: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0,
            withBytes: &backgroundBytes,
            bytesPerRow: size * 4
        )
        guard let captured = pipeline.snapshot(
            target: background,
            commandBuffer: command
        ) else {
            throw HarnessError.gpu
        }
        let instances = SceneParticleMetalInstanceBuffer()
        guard instances.update(device: device, instances: [
            SceneParticleGPUInstance(
                position: .zero,
                size: 2,
                rotation: .zero,
                color: SIMD3(repeating: 1),
                alpha: particleAlpha
            ),
        ]) else {
            throw HarnessError.gpu
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(
            descriptor: pass
        ) else {
            throw HarnessError.gpu
        }
        pipeline.drawRefraction(
            texture: refraction.color,
            binding: refraction.binding,
            background: captured,
            instances: instances,
            uniforms: SceneParticleLayerUniforms(
                viewProjection: SceneMatrix.identity(),
                layerModel: SceneMatrix.identity(),
                basis: SceneParticleOrientation.screen.basis(
                    cameraRight: SIMD3(1, 0, 0),
                    cameraUp: SIMD3(0, 1, 0),
                    cameraForward: SIMD3(0, 0, -1)
                ),
                viewportSize: SIMD2(repeating: Float(size))
            ),
            blendMode: blendMode,
            colorUVScale: refraction.colorUVScale,
            colorSampling: refraction.colorSampling,
            encoder: encoder
        )
        encoder.endEncoding()
        guard instances.markSubmitted(on: command) else {
            throw HarnessError.gpu
        }
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else {
            throw HarnessError.gpu
        }
        var pixel = [UInt8](repeating: 0, count: 4)
        target.getBytes(
            &pixel,
            bytesPerRow: size * 4,
            from: MTLRegionMake2D(size / 2, size / 2, 1, 1),
            mipmapLevel: 0
        )
        return pixel.map(Int.init)
    }

    private static func refraction(
        colorURL: URL,
        normalURL: URL,
        amount: Float,
        loader: SceneTextureLoader,
        device: MTLDevice
    ) throws -> SceneParticleRefractionTextureLoader.Loaded {
        guard let loaded = SceneParticleRefractionTextureLoader.load(
            colorSource: .file(colorURL),
            declaration: SceneParticleRefractionDeclaration(
                normalTextureSource: .file(normalURL),
                amount: amount,
                overbright: 1
            ),
            textureLoader: loader,
            device: device
        ) else {
            throw HarnessError.texture
        }
        return loaded
    }

    private static func makeDXT5nTex() -> Data {
        makeTex(
            format: 4,
            payload: dxt5nBlock()
        )
    }

    private static func makeDirectDXT5nTex() -> Data {
        var data = Data("TEXV0005\0TEXI0001\0".utf8)
        func append(_ value: UInt32) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) {
                data.append(contentsOf: $0)
            }
        }
        append(4)
        append(0)
        append(4)
        append(4)
        append(4)
        append(4)
        append(0)
        data.append(Data("TEXB0002\0".utf8))
        append(2)
        for _ in 0 ..< 2 {
            let block = dxt5nBlock()
            append(1)
            append(4)
            append(4)
            append(0)
            append(0)
            append(UInt32(block.count))
            data.append(block)
        }
        return data
    }

    private static func dxt5nBlock() -> Data {
        Data([
            64, 64, 0, 0, 0, 0, 0, 0,
            0x00, 0xFC, 0x00, 0xFC, 0, 0, 0, 0,
        ])
    }

    private static func makeRawTex(pixel: [UInt8]) -> Data {
        makeTex(
            format: 0,
            payload: Data((0 ..< 16).flatMap { _ in pixel })
        )
    }

    private static func makeTex(format: UInt32, payload: Data) -> Data {
        var data = Data("TEXV0005\0TEXI0001\0".utf8)
        func append(_ value: UInt32) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) {
                data.append(contentsOf: $0)
            }
        }
        append(format)
        append(0)
        append(4)
        append(4)
        append(4)
        append(4)
        append(0)
        data.append(Data("TEXB0002\0".utf8))
        append(1)
        append(1)
        append(4)
        append(4)
        append(0)
        append(0)
        append(UInt32(payload.count))
        data.append(payload)
        return data
    }

    private static func loaded(
        _ outcome: SceneTextureLoadOutcome
    ) throws -> MTLTexture {
        guard case let .loaded(texture) = outcome else {
            throw HarnessError.texture
        }
        return texture
    }

    private static func readPixel(_ texture: MTLTexture) -> [UInt8] {
        var pixel = [UInt8](repeating: 0, count: 4)
        texture.getBytes(
            &pixel,
            bytesPerRow: texture.width * 4,
            from: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0
        )
        return pixel
    }

    private enum HarnessError: Error {
        case gpu
        case texture
    }
}
'''


class SceneParticleRefractionPixelTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls._temporary_directory = tempfile.TemporaryDirectory()
        temporary = Path(cls._temporary_directory.name)
        harness = temporary / "harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = temporary / "harness"
        compilation = subprocess.run(
            ["swiftc", *map(str, SWIFT_SOURCES), str(harness), "-o", str(binary)],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise AssertionError(
                f"harness compilation failed:\n{compilation.stderr}"
            )
        completed = subprocess.run(
            [str(binary)],
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            raise AssertionError(f"harness run failed:\n{completed.stderr}")
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls._temporary_directory.cleanup()

    def require_metal(self) -> None:
        if not self.result["available"]:
            self.skipTest("Metal is unavailable")

    def test_dxt5n_and_byte_equivalent_rgba_normal_displace_equally(self) -> None:
        self.require_metal()
        self.assertEqual(self.result["decodedDXT5n"], [255, 130, 0, 64])
        self.assertEqual(self.result["loadedDXT5nNormal"], [255, 130, 0, 64])
        pixels = self.result["normalPixels"]
        self.assertLessEqual(
            max(abs(left - right) for left, right in zip(
                pixels["dxt5n"], pixels["rgba"]
            )),
            2,
        )
        self.assertLessEqual(
            max(abs(left - right) for left, right in zip(
                pixels["dxt5nDirect"], pixels["rgba"]
            )),
            2,
        )
        self.assertGreater(
            max(abs(left - right) for left, right in zip(
                pixels["rgba"], pixels["swapped"]
            )),
            8,
        )
        self.assertGreater(
            max(abs(left - right) for left, right in zip(
                pixels["rgba"], pixels["neutral"]
            )),
            8,
        )

    def test_refraction_composite_coverage_is_applied_once(self) -> None:
        self.require_metal()
        self.assertEqual(
            self.result["coveragePixels"]["albedo"],
            [255, 255, 255, 128],
        )
        expected = [50, 25, 13, 64]
        double_applied = [13, 6, 3, 64]
        for mode in ("translucent", "additive"):
            pixel = self.result["coveragePixels"][mode]
            expected_error = sum(abs(left - right) for left, right in zip(
                pixel, expected
            ))
            double_error = sum(abs(left - right) for left, right in zip(
                pixel, double_applied
            ))
            self.assertLessEqual(max(abs(left - right) for left, right in zip(
                pixel, expected
            )), 2)
            self.assertLess(expected_error, double_error)


if __name__ == "__main__":
    unittest.main()
