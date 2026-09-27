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
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/ScenePerformanceCounterHub.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/SceneGPUCensus.swift",
    SCENE_ROOT / "Format/SceneTexDataReader.swift",
    SCENE_ROOT / "Format/SceneTexContainer.swift",
    SCENE_ROOT / "Format/SceneBCTextureDecoder.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneImageTextureUploader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneCompressedTextureUploader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureMipUploader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureLoader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureSampling.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureUVTransform.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureCandidate.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureLoader+Candidate.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/SceneMatrix.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneFramebufferSnapshot.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleDefinition.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleInitializer.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleAudioResponsePlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleVortex.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRemapValue.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleReduceMovement.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleCollisionPlane.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticlePositionAroundControlPoint.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleDefinitionParser.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleDefinitionParser+Operator.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleRenderSupport.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleBoids.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulationSupport.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulationDiagnostic.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleCapVelocity.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleControlPointForce.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticlePeriodicEmission.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleStepSnapshotRecorder.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRopeTrailPlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleMetalInstanceBuffer.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRefractionBinding.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRefractionTextureLoader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleShaderSource.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleSamplerStateSet.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleMetalPipeline.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleDepthTargetPool.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleTextureSource.swift",
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
    let normalTextureSource: SceneParticleTextureSource?
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
        let flatDefault = try refraction(
            colorURL: opaqueURL,
            normalURL: nil,
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
        let normalCopyURL = directory.appendingPathComponent("normal-copy.tex")
        try Data(contentsOf: opaqueURL).write(to: normalCopyURL)
        let separateFile = try refraction(colorURL: opaqueURL, normalURL: normalCopyURL,
            amount: 0.25, loader: loader, device: device)
        let sameFilePixels = try draw(device: device, refraction: sameFile,
            particleAlpha: 1, blendMode: .translucent, gradientBackground: true)
        let separateFilePixels = try draw(device: device, refraction: separateFile,
            particleAlpha: 1, blendMode: .translucent, gradientBackground: true)
        let sixteenURL = directory.appendingPathComponent("sixteen.tex")
        try makeTex(format: 0, textureWidth: 2, textureHeight: 2, imageWidth: 2, imageHeight: 2,
            payload: try makeOpaquePNG(width: 2, height: 2, straight16: true)).write(to: sixteenURL)
        let sixteenColor = SceneParticleRefractionTextureLoader.load(
            colorSource: .file(sixteenURL),
            declaration: SceneParticleRefractionDeclaration(normalTextureSource: nil,
                amount: 0.25, overbright: 1), textureLoader: loader, device: device)
        let sixteenNormal = SceneParticleRefractionTextureLoader.load(
            colorSource: .file(sixteenURL),
            declaration: SceneParticleRefractionDeclaration(normalTextureSource: .file(sixteenURL),
                amount: 0.25, overbright: 1), textureLoader: loader, device: device)
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
        let clampBorderNormal = try normalArguments(clampBorder.binding)
        let flatDefaultNormal = try normalArguments(flatDefault.binding)
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

        let directNormal = try normalArguments(directDXT5n.binding)
        let unknownFormatRejected = SceneParticleRefractionBinding(
            normalCandidate: candidate(texture: dxt5nNormal.texture, purpose: .normal, authoredFormat: nil),
            amount: 1, overbright: 1, colorEncoding: .rgba) == nil
        let unsupportedFormatRejected = SceneParticleRefractionBinding(
            normalCandidate: candidate(texture: dxt5nNormal.texture, purpose: .normal, authoredFormat: .rg88),
            amount: 1, overbright: 1, colorEncoding: .rgba) == nil
        let mismatchedFormatRejected = SceneParticleRefractionBinding(
            normalCandidate: candidate(texture: directNormal.texture, purpose: .normal, authoredFormat: .rgba8888),
            amount: 1, overbright: 1, colorEncoding: .rgba) == nil
        let sameFileDXT5n = try refraction(colorURL: dxt5nURL, normalURL: dxt5nURL,
            amount: 0.75, loader: loader, device: device)
        var sourceFormatPixels: [String: [Int]] = [:]
        for (name, url) in [("rgba", rgbaURL), ("cpuBC3", dxt5nURL), ("nativeBC3", directDXT5nURL)] {
            let value = try refraction(colorURL: opaqueURL, normalURL: url, amount: 0.75,
                loader: loader, device: device)
            sourceFormatPixels[name] = try draw(device: device, refraction: value,
                particleAlpha: 1, blendMode: .translucent, gradientBackground: true)
        }
        let coloredURL = directory.appendingPathComponent("colored-albedo.tex")
        try makeRawTex(pixel: [64,192,128,128]).write(to: coloredURL)
        let rg88URL = directory.appendingPathComponent("rg88-albedo.tex")
        try makeTex(format: 8, payload: Data((0..<16).flatMap { _ in [UInt8(128),128] })).write(to: rg88URL)
        var absentPixels: [String: [[Int]]] = [:]
        for (name, url) in [("white",opaqueURL), ("colored",coloredURL), ("rg88",rg88URL)] {
            for (modeName, mode) in [("translucent",SceneParticlePipelineBlendMode.translucent),
                                     ("additive",SceneParticlePipelineBlendMode.additive)] {
                absentPixels[name + modeName] = try [Float(-1),0,1].map { amount in
                    let value = try refraction(colorURL: url, normalURL: nil, amount: amount,
                        loader: loader, device: device)
                    return try draw(device: device, refraction: value, particleAlpha: 0.5,
                        blendMode: mode, gradientBackground: true)
                }
            }
        }
        let explicitNeutral = try refraction(colorURL: opaqueURL, normalURL: neutralURL,
            amount: 1, loader: loader, device: device)
        let absentStrong = try refraction(colorURL: opaqueURL, normalURL: nil,
            amount: 1, loader: loader, device: device)
        let result: [String: Any] = [
            "available": true,
            "sourceFormatPixels": sourceFormatPixels,
            "absentPixels": absentPixels,
            "explicitNeutral": try draw(device: device, refraction: explicitNeutral,
                particleAlpha: 1, blendMode: .translucent, gradientBackground: true),
            "absentStrong": try draw(device: device, refraction: absentStrong,
                particleAlpha: 1, blendMode: .translucent, gradientBackground: true),

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
                "flatDefault": try draw(
                    device: device,
                    refraction: flatDefault,
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
                "sameFilePixels": sameFilePixels,
                "separateFilePixels": separateFilePixels,
                "sixteenColorAccepted": sixteenColor != nil,
                "sixteenNormalRejected": sixteenNormal == nil,
                "decodedBC3IsRGBA": dxt5nNormal.texture.pixelFormat == .rgba8Unorm,
                "directBC3IsNative": directNormal.texture.pixelFormat == .bc3_rgba,
                "decodedBC3Format": dxt5nNormal.authoredFormat?.rawValue ?? 999,
                "nativeBC3Format": directNormal.authoredFormat?.rawValue ?? 999,
                "sameFileBC3Format": try normalArguments(sameFileDXT5n.binding).authoredFormat?.rawValue ?? 999,
                "rgbaFormat": try normalArguments(rgba.binding).authoredFormat?.rawValue ?? 999,
                "absentFormat": flatDefaultNormal.authoredFormat == nil,
                "unknownFormatRejected": unknownFormatRejected,
                "unsupportedFormatRejected": unsupportedFormatRejected,
                "mismatchedFormatRejected": mismatchedFormatRejected,
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
        normalURL: URL?,
        amount: Float,
        loader: SceneTextureLoader,
        device: MTLDevice
    ) throws -> SceneParticleRefractionTextureLoader.Loaded {
        guard let loaded = SceneParticleRefractionTextureLoader.load(
            colorSource: .file(colorURL),
            declaration: SceneParticleRefractionDeclaration(
                normalTextureSource: normalURL.map(SceneParticleTextureSource.file),
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

    private static func makeOpaquePNG(width: Int, height: Int, straight16: Bool = false) throws -> Data {
        let pixels = straight16
            ? Data((0 ..< width * height).flatMap { _ in [UInt8](arrayLiteral: 255,255,18,52,171,205,128,1) })
            : Data(repeating: 255, count: width * height * 4)
        guard let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: straight16 ? 16 : 8,
                  bitsPerPixel: straight16 ? 64 : 32,
                  bytesPerRow: width * (straight16 ? 8 : 4),
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(
                      rawValue: straight16 ? CGImageAlphaInfo.last.rawValue | CGBitmapInfo.byteOrder16Big.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
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
        sampling: SceneTextureSampling = .linearClamp,
        authoredFormat: SceneShaderTextureFormat? = .rgba8888
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
            sampling: sampling,
            authoredFormat: authoredFormat
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

    def test_normal_storage_preserves_channels_and_source_format_decoding(self) -> None:
        self.require_metal()
        self.assertEqual(self.result["decodedDXT5n"], [255, 130, 0, 64])
        self.assertEqual(self.result["loadedDXT5nNormal"], [255, 130, 0, 64])
        pixels = self.result["normalPixels"]
        self.assertLessEqual(max(abs(a - b) for a, b in zip(
            pixels["dxt5n"], pixels["dxt5nDirect"])), 2)
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
        self.assertLessEqual(
            max(abs(left - right) for left, right in zip(
                pixels["flatDefault"], pixels["neutral"]
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
        self.assertEqual(routes["sameFilePixels"], routes["separateFilePixels"])
        self.assertTrue(any(routes["sameFilePixels"][:3]))
        self.assertTrue(routes["sixteenColorAccepted"], routes)
        self.assertTrue(routes["sixteenNormalRejected"], routes)
        self.assertTrue(routes["decodedBC3IsRGBA"], routes)
        self.assertTrue(routes["directBC3IsNative"], routes)
        self.assertEqual(routes["decodedBC3Format"], 4)
        self.assertEqual(routes["nativeBC3Format"], 4)
        self.assertEqual(routes["sameFileBC3Format"], 4)
        self.assertEqual(routes["rgbaFormat"], 0)
        self.assertTrue(routes["absentFormat"])
        self.assertTrue(routes["unknownFormatRejected"])
        self.assertTrue(routes["unsupportedFormatRejected"])
        self.assertTrue(routes["mismatchedFormatRejected"])
        self.assertTrue(routes["oversizedSameSourceRejected"], routes)
        self.assertTrue(routes["clampBorderLegacy"], routes)
        self.assertTrue(routes["invalidMappedRejected"], routes)
        self.assertTrue(routes["wrongPurposeRejected"], routes)
        self.assertTrue(routes["clampBorderCandidateRejected"], routes)
        self.assertTrue(routes["wrongUsageRejected"], routes)
        self.assertTrue(routes["wrongTypeRejected"], routes)

    def test_bc3_bias_uses_authored_format_after_cpu_or_native_upload(self) -> None:
        self.require_metal()
        values = self.result["sourceFormatPixels"]
        # With A=64/255, RGBA X=2*A-1 while BC3 X=2*A-.965.
        # The 32px background changes by 5 blue units/pixel, amount=.75.
        for key, bias in [("rgba", 1), ("cpuBC3", .965), ("nativeBC3", .965)]:
            expected_blue = 100 + (2 * 64 / 255 - bias) * .75 * 32 * 5
            self.assertAlmostEqual(values[key][0], expected_blue, delta=1)
        self.assertGreater(values["cpuBC3"][0], values["rgba"][0] + 2)
        self.assertAlmostEqual(values["cpuBC3"][1], values["rgba"][1], delta=1)

    def test_absent_normal_has_exact_zero_displacement_for_any_amount(self) -> None:
        self.require_metal()
        self.assertEqual(len(self.result["absentPixels"]), 6)
        for name, pixels in self.result["absentPixels"].items():
            with self.subTest(name=name):
                self.assertEqual(pixels[0], pixels[1])
                self.assertEqual(pixels[2], pixels[1])
                self.assertGreater(pixels[1][3], 0)
        self.assertEqual(self.result["absentStrong"], [100,78,40,255])
        self.assertNotEqual(self.result["explicitNeutral"], self.result["absentStrong"])

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


# The loader double changes source identity exactly between metadata and upload.
# Only I/O is doubled; the production refraction preparation and binding execute.
IDENTITY_HARNESS = r'''
import Foundation
import Metal
import simd

typealias SceneParticleTextureSampling = SceneTextureSampling
enum SceneTextureLoadPurpose { case normal, straightAlbedo }
enum SceneParticleTextureSource { case file(URL), builtIn(String) }
struct SceneParticleRefractionDeclaration {
    let normalTextureSource: SceneParticleTextureSource?
    let amount: Float = 1
    let overbright: Float = 1
}
struct SceneTexContainer {
    struct SpriteFrame {
        let imageIndex: Int; let duration: Float
        let origin: SIMD2<Float>; let xAxis: SIMD2<Float>; let yAxis: SIMD2<Float>
    }
    struct Mip { let width = 4; let height = 4 }
    let format: UInt32
    let flags: UInt32
    let imageCount = 1; let isAnimated = false
    let spriteFrames: [SpriteFrame] = []; let mips = [Mip()]
    let imageWidth = 4; let imageHeight = 4; let textureWidth = 4; let textureHeight = 4
}
struct SceneSpriteAnimation { init(container: SceneTexContainer, sourceURL: URL) {} }
struct SceneTextureCandidate {
    let texture: MTLTexture
    let authoredFormat: SceneShaderTextureFormat?
    let sampling = SceneTextureSampling.linearClamp
    var pixelFormat: MTLPixelFormat { texture.pixelFormat }
    func axisAlignedMappedUVScale(expectedPurpose: SceneTextureLoadPurpose) -> SIMD2<Float>? { SIMD2(1,1) }
}
final class SceneTextureLoader {
    struct SourceKey: Equatable { let revision: Int }
    enum Outcome { case loaded(MTLTexture) }
    enum CandidateOutcome { case loaded(SceneTextureCandidate) }
    let texture: MTLTexture
    let mode: String
    var revision: [String: Int] = [:]
    var changed = false
    init(device: MTLDevice, mode: String) {
        self.mode = mode
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
            width: 4, height: 4, mipmapped: false)
        d.usage = .shaderRead
        texture = device.makeTexture(descriptor: d)!
    }
    func sourceKey(for url: URL) -> SourceKey? { .init(revision: revision[url.path, default: 0]) }
    func texContainer(from url: URL) -> SceneTexContainer? {
        .init(format: revision[url.path, default: 0] == 0 ? 0 : 4,
              flags: mode == "normal-base" ? 8 : 0)
    }
    func changeIfNeeded(_ url: URL, candidate: Bool) {
        guard !changed else { return }
        let change = (mode == "color" || mode == "same-file") && url.lastPathComponent == "color.tex"
            || mode == "normal-base" && url.lastPathComponent == "normal.tex"
            || mode == "normal-candidate" && candidate
        if change { revision[url.path, default: 0] += 1; changed = true }
    }
    func load(from url: URL, purpose: SceneTextureLoadPurpose, device: MTLDevice) -> Outcome {
        changeIfNeeded(url, candidate: false); return .loaded(texture)
    }
    func loadCandidate(from url: URL, purpose: SceneTextureLoadPurpose, device: MTLDevice) -> CandidateOutcome {
        changeIfNeeded(url, candidate: true)
        return .loaded(.init(texture: texture,
            authoredFormat: revision[url.path, default: 0] == 0 ? .rgba8888 : .dxt5))
    }
}
@main enum Main {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { fatalError("Metal unavailable") }
        let color = URL(fileURLWithPath: "/fixture/color.tex")
        let normal = URL(fileURLWithPath: "/fixture/normal.tex")
        var result: [String: [Bool]] = [:]
        for mode in ["stable", "color", "same-file", "normal-base", "normal-candidate"] {
            let loader = SceneTextureLoader(device: device, mode: mode)
            let declaration = SceneParticleRefractionDeclaration(
                normalTextureSource: mode == "color" ? nil : .file(mode == "same-file" ? color : normal))
            func prepare() -> Bool {
                SceneParticleRefractionTextureLoader.load(colorSource: .file(color),
                    declaration: declaration, textureLoader: loader, device: device) != nil
            }
            result[mode] = [prepare(), prepare()]
        }
        let data = try JSONSerialization.data(withJSONObject: result, options: .sortedKeys)
        print(String(decoding: data, as: UTF8.self))
    }
}
'''

class SceneParticleRefractionIdentityTests(unittest.TestCase):
    def test_metadata_upload_identity_drift_is_rejected_and_retry_recovers(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-refraction-identity-") as directory:
            root = Path(directory)
            harness = root / "harness.swift"
            harness.write_text(IDENTITY_HARNESS)
            binary = root / "harness"
            sources = [
                SCENE_ROOT / "Resources/Textures/SceneTextureSampling.swift",
                SCENE_ROOT / "Systems/Particles/SceneParticleRefractionBinding.swift",
                SCENE_ROOT / "Systems/Particles/SceneParticleRefractionTextureLoader.swift",
            ]
            result = subprocess.run(["swiftc", *map(str, sources), str(harness), "-o", str(binary)],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            values = json.loads(result.stdout)
            self.assertEqual(values["stable"], [True, True])
            for key in ["color", "same-file", "normal-base", "normal-candidate"]:
                self.assertEqual(values[key], [False, True], key)


if __name__ == "__main__":
    unittest.main()
