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
    SCENE_ROOT / "Resources/SceneTextureUVTransform.swift",
    SCENE_ROOT / "Resources/SceneTextureCandidate.swift",
    SCENE_ROOT / "Resources/SceneTextureLoader+Candidate.swift",
    SCENE_ROOT / "Rendering/SceneMatrix.swift",
    SCENE_ROOT / "Rendering/SceneFramebufferSnapshot.swift",
    SCENE_ROOT / "Particles/SceneParticleDefinition.swift",
    SCENE_ROOT / "Particles/SceneParticleInitializer.swift",
    SCENE_ROOT / "Particles/SceneParticleAudioResponsePlan.swift",
    SCENE_ROOT / "Particles/SceneParticleVortex.swift",
    SCENE_ROOT / "Particles/SceneParticleRemapValue.swift",
    SCENE_ROOT / "Particles/SceneParticleReduceMovement.swift",
    SCENE_ROOT / "Particles/SceneParticleCollisionPlane.swift",
    SCENE_ROOT / "Particles/SceneParticlePositionAroundControlPoint.swift",
    SCENE_ROOT / "Particles/SceneParticleDefinitionParser.swift",
    SCENE_ROOT / "Particles/SceneParticleDefinitionParser+Operator.swift",
    SCENE_ROOT / "Particles/SceneParticleRenderSupport.swift",
    SCENE_ROOT / "Particles/SceneParticleBoids.swift",
    SCENE_ROOT / "Particles/SceneParticleSimulationSupport.swift",
    SCENE_ROOT / "Particles/SceneParticleSimulationDiagnostic.swift",
    SCENE_ROOT / "Particles/SceneParticleCapVelocity.swift",
    SCENE_ROOT / "Particles/SceneParticleControlPointForce.swift",
    SCENE_ROOT / "Particles/SceneParticlePeriodicEmission.swift",
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
import CoreGraphics
import Foundation
import ImageIO
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
    init(container: SceneTexContainer, sourceURL: URL) {}
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
        let paddedURL = directory.appendingPathComponent("padded-normal.tex")
        try makePaddedRawNormalTex().write(to: paddedURL)
        let padded = try refraction(
            colorURL: opaqueURL,
            normalURL: paddedURL,
            amount: 0.25,
            loader: loader,
            device: device
        )
        let clampBorderURL = directory.appendingPathComponent(
            "clamp-border-normal.tex"
        )
        try makeRawTex(
            pixel: [255, 128, 0, 128],
            flags: 8
        ).write(to: clampBorderURL)
        let clampBorder = try refraction(
            colorURL: opaqueURL,
            normalURL: clampBorderURL,
            amount: 0.25,
            loader: loader,
            device: device
        )
        let sameFile = try refraction(
            colorURL: opaqueURL,
            normalURL: opaqueURL,
            amount: 0.25,
            loader: loader,
            device: device
        )
        let oversizedSameSourceURL = directory.appendingPathComponent(
            "oversized-same-source.tex"
        )
        try makeTex(
            format: 0,
            textureWidth: 4_097,
            textureHeight: 2,
            imageWidth: 4_097,
            imageHeight: 2,
            payload: try makeOpaquePNG(width: 4_097, height: 2)
        ).write(to: oversizedSameSourceURL)
        let oversizedSameSourceRejected = SceneParticleRefractionTextureLoader.load(
            colorSource: .file(oversizedSameSourceURL),
            declaration: SceneParticleRefractionDeclaration(
                normalTextureSource: .file(oversizedSameSourceURL),
                amount: 0.25,
                overbright: 1
            ),
            textureLoader: loader,
            device: device
        ) == nil
        let invalidMappedURL = directory.appendingPathComponent(
            "invalid-mapped-normal.tex"
        )
        try makeRawTex(
            pixel: [255, 128, 0, 128],
            textureWidth: 4,
            textureHeight: 4,
            imageWidth: 8,
            imageHeight: 4
        ).write(to: invalidMappedURL)
        let invalidMappedRejected = SceneParticleRefractionTextureLoader.load(
            colorSource: .file(opaqueURL),
            declaration: SceneParticleRefractionDeclaration(
                normalTextureSource: .file(invalidMappedURL),
                amount: 0.25,
                overbright: 1
            ),
            textureLoader: loader,
            device: device
        ) == nil
        let dxt5nNormal = try normalArguments(dxt5n.binding)
        let paddedNormal = try normalArguments(padded.binding)
        let sameFileNormal = try normalArguments(sameFile.binding)
        let clampBorderNormal = try normalArguments(clampBorder.binding)
        let wrongPurposeRejected = SceneParticleRefractionBinding(
            normalCandidate: candidate(
                texture: dxt5nNormal.texture,
                purpose: .flow
            ),
            amount: 0.25,
            overbright: 1,
            colorEncoding: .rgba
        ) == nil
        let clampBorderCandidateRejected = SceneParticleRefractionBinding(
            normalCandidate: candidate(
                texture: dxt5nNormal.texture,
                purpose: .normal,
                sampling: SceneTextureSampling(texFlags: 8)
            ),
            amount: 0.25,
            overbright: 1,
            colorEncoding: .rgba
        ) == nil
        let wrongUsageDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 4,
            height: 4,
            mipmapped: false
        )
        wrongUsageDescriptor.usage = .renderTarget
        let wrongTypeDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 4,
            height: 4,
            mipmapped: false
        )
        wrongTypeDescriptor.textureType = .type2DArray
        wrongTypeDescriptor.arrayLength = 2
        wrongTypeDescriptor.usage = .shaderRead
        guard let wrongUsageTexture = device.makeTexture(
                  descriptor: wrongUsageDescriptor
              ),
              let wrongTypeTexture = device.makeTexture(
                  descriptor: wrongTypeDescriptor
              ) else {
            throw HarnessError.texture
        }
        let wrongUsageRejected = SceneParticleRefractionBinding(
            normalCandidate: candidate(
                texture: wrongUsageTexture,
                purpose: .normal
            ),
            amount: 0.25,
            overbright: 1,
            colorEncoding: .rgba
        ) == nil
        let wrongTypeRejected = SceneParticleRefractionBinding(
            normalCandidate: candidate(
                texture: wrongTypeTexture,
                purpose: .normal
            ),
            amount: 0.25,
            overbright: 1,
            colorEncoding: .rgba
        ) == nil

        let result: [String: Any] = [
            "available": true,
            "decodedDXT5n": decoded.map(Int.init),
            "loadedDXT5nNormal": readPixel(
                dxt5nNormal.texture
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
                "padded": try draw(
                    device: device,
                    refraction: padded,
                    particleAlpha: 1,
                    blendMode: .translucent,
                    gradientBackground: true
                ),
            ],
            "normalRoutes": [
                "dxt5nStaticCandidate":
                    dxt5n.binding.usesStaticNormalCandidate,
                "rgbaStaticCandidate":
                    rgba.binding.usesStaticNormalCandidate,
                "paddedStaticCandidate":
                    padded.binding.usesStaticNormalCandidate,
                "paddedUVScale": [
                    paddedNormal.uvScale.x,
                    paddedNormal.uvScale.y,
                ],
                "multiImageLegacy":
                    !directDXT5n.binding.usesStaticNormalCandidate,
                "sameFileLegacy":
                    !sameFile.binding.usesStaticNormalCandidate,
                "sameFileSharesUpload":
                    sameFile.color === sameFileNormal.texture,
                "oversizedSameSourceRejected": oversizedSameSourceRejected,
                "clampBorderLegacy":
                    !clampBorder.binding.usesStaticNormalCandidate
                        && clampBorderNormal.sampling.usesClampBorderFallback,
                "invalidMappedRejected": invalidMappedRejected,
                "wrongPurposeRejected": wrongPurposeRejected,
                "clampBorderCandidateRejected":
                    clampBorderCandidateRejected,
                "wrongUsageRejected": wrongUsageRejected,
                "wrongTypeRejected": wrongTypeRejected,
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
            renderState: SceneParticlePipelineRenderState(
                blendMode: blendMode,
                cullMode: .none
            ),
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

    private static func makeRawTex(
        pixel: [UInt8],
        flags: UInt32 = 0,
        textureWidth: UInt32 = 4,
        textureHeight: UInt32 = 4,
        imageWidth: UInt32 = 4,
        imageHeight: UInt32 = 4
    ) -> Data {
        makeTex(
            format: 0,
            flags: flags,
            textureWidth: textureWidth,
            textureHeight: textureHeight,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            payload: Data(
                (0 ..< Int(textureWidth * textureHeight)).flatMap { _ in pixel }
            )
        )
    }

    private static func makePaddedRawNormalTex() -> Data {
        let mapped: [UInt8] = [255, 128, 0, 128]
        let padding: [UInt8] = [255, 255, 0, 0]
        let payload = Data((0 ..< 4).flatMap { _ in
            (0 ..< 4).flatMap { _ in mapped }
                + (0 ..< 4).flatMap { _ in padding }
        })
        return makeTex(
            format: 0,
            flags: 2,
            textureWidth: 8,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
            payload: payload
        )
    }

    private static func makeOpaquePNG(width: Int, height: Int) throws -> Data {
        let pixels = Data(repeating: 255, count: width * height * 4)
        guard let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(
                      rawValue: CGImageAlphaInfo.noneSkipLast.rawValue
                  ),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ),
              let data = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(
                  data,
                  "public.png" as CFString,
                  1,
                  nil
              ) else {
            throw HarnessError.texture
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw HarnessError.texture
        }
        return data as Data
    }

    private static func makeTex(
        format: UInt32,
        flags: UInt32 = 0,
        textureWidth: UInt32 = 4,
        textureHeight: UInt32 = 4,
        imageWidth: UInt32 = 4,
        imageHeight: UInt32 = 4,
        payload: Data
    ) -> Data {
        var data = Data("TEXV0005\0TEXI0001\0".utf8)
        func append(_ value: UInt32) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) {
                data.append(contentsOf: $0)
            }
        }
        append(format)
        append(flags)
        append(textureWidth)
        append(textureHeight)
        append(imageWidth)
        append(imageHeight)
        append(0)
        data.append(Data("TEXB0002\0".utf8))
        append(1)
        append(1)
        append(textureWidth)
        append(textureHeight)
        append(0)
        append(0)
        append(UInt32(payload.count))
        data.append(payload)
        return data
    }

    private static func candidate(
        texture: MTLTexture,
        purpose: SceneTextureLoadPurpose,
        sampling: SceneTextureSampling = .linearClamp
    ) -> SceneTextureCandidate {
        let size = CGSize(width: texture.width, height: texture.height)
        let content: SceneTextureContent
        switch purpose {
        case .premultipliedColor:
            content = .color(.resolved(.premultipliedAlpha))
        case .straightAlbedo:
            content = .color(.resolved(.straightAlpha))
        default:
            content = .data
        }
        return SceneTextureCandidate(
            texture: texture,
            identity: .builtIn(name: "refraction-test"),
            generation: .immutable(revision: 1),
            purpose: purpose,
            content: content,
            physicalSize: size,
            mappedSize: size,
            uvTransform: .identity,
            sampling: sampling
        )
    }

    private static func normalArguments(
        _ binding: SceneParticleRefractionBinding
    ) throws -> SceneParticleRefractionBinding.NormalArguments {
        guard let arguments = binding.resolvedNormalArguments() else {
            throw HarnessError.texture
        }
        return arguments
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
        self.assertLessEqual(
            max(abs(left - right) for left, right in zip(
                pixels["padded"], pixels["neutral"]
            )),
            2,
        )

    def test_static_normal_candidate_is_atomic_and_legacy_routes_stay_closed(
        self,
    ) -> None:
        self.require_metal()
        routes = self.result["normalRoutes"]
        self.assertTrue(routes["dxt5nStaticCandidate"], routes)
        self.assertTrue(routes["rgbaStaticCandidate"], routes)
        self.assertTrue(routes["paddedStaticCandidate"], routes)
        self.assertEqual(routes["paddedUVScale"], [0.5, 1])
        self.assertTrue(routes["multiImageLegacy"], routes)
        self.assertTrue(routes["sameFileLegacy"], routes)
        self.assertTrue(routes["sameFileSharesUpload"], routes)
        self.assertTrue(routes["oversizedSameSourceRejected"], routes)
        self.assertTrue(routes["clampBorderLegacy"], routes)
        self.assertTrue(routes["invalidMappedRejected"], routes)
        self.assertTrue(routes["wrongPurposeRejected"], routes)
        self.assertTrue(routes["clampBorderCandidateRejected"], routes)
        self.assertTrue(routes["wrongUsageRejected"], routes)
        self.assertTrue(routes["wrongTypeRejected"], routes)

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
