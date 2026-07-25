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
REAL_SAMPLE_CACHE = (
    REPOSITORY_ROOT
    / ".codex/scene-particle-contract-20260722/runtime-homes/3742133044"
    / "Library/Caches/MyWallpaperX/SteamWorkshopScene/72cdb5be4865b335"
)
EVENTSPAWN_SAMPLE_CACHE = (
    REPOSITORY_ROOT
    / ".codex/scene-halo4-targeted-compact-20260724/runtime-homes/3768903841"
    / "Library/Caches/MyWallpaperX/SteamWorkshopScene/964b264a636e9e02"
)
EVENTDEATH_SAMPLE_CACHE = (
    REPOSITORY_ROOT
    / ".codex/scene-eventspawn-targeted-final-20260724/runtime-homes/2131872317"
    / "Library/Caches/MyWallpaperX/SteamWorkshopScene/8ccb6157084ce19f"
)
FLARE_PARTICLE_CACHE = (
    REPOSITORY_ROOT
    / ".codex/scene-turbulent-velocity-final-targeted-20260725/runtime-homes/2998757800"
    / "Library/Caches/MyWallpaperX/SteamWorkshopScene/302becd241426966"
    / "particles/workshop/2105295491"
)
STATIC_ORIGIN_SAMPLE_CACHE = (
    REPOSITORY_ROOT
    / ".codex/scene-snow-smoke-full45-20260725/runtime-homes/3088601835"
    / "Library/Caches/MyWallpaperX/SteamWorkshopScene/fdbdffd7b8183bd4"
)
SWIFT_SOURCES = [
    SOURCE_ROOT / "Resources/SceneResourceIndex.swift",
    SOURCE_ROOT / "Particles/SceneParticleDefinition.swift",
    SOURCE_ROOT / "Particles/SceneParticleDefinitionParser.swift",
    SOURCE_ROOT / "Particles/SceneParticleTextureSource.swift",
    SOURCE_ROOT / "Particles/SceneParticleBuiltInTextureRegistry.swift",
    SOURCE_ROOT / "Particles/SceneParticleAssetGraph.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulationSupport.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulator.swift",
    SOURCE_ROOT / "Particles/SceneParticleChildLifecycle.swift",
    SOURCE_ROOT / "Particles/SceneParticleChildTemplateSupport.swift",
    SOURCE_ROOT / "Particles/SceneParticleTrailRenderPlan.swift",
    SOURCE_ROOT / "Particles/SceneParticleRenderSupport.swift",
    SOURCE_ROOT / "Particles/SceneParticleMetalPipeline.swift",
    SOURCE_ROOT / "Format/SceneTexDataReader.swift",
    SOURCE_ROOT / "Format/SceneTexContainer.swift",
    SOURCE_ROOT / "Format/SceneBCTextureDecoder.swift",
    SOURCE_ROOT / "Resources/SceneCompressedTextureUploader.swift",
    SOURCE_ROOT / "Resources/SceneTextureLoader.swift",
    SOURCE_ROOT / "Rendering/SceneSpriteAnimation.swift",
    SOURCE_ROOT / "Rendering/SceneLayerVisibility.swift",
    SOURCE_ROOT / "Particles/SceneParticleChildRuntime.swift",
    SOURCE_ROOT / "Particles/SceneParticleRuntime.swift",
    SOURCE_ROOT / "Particles/SceneParticleRuntime+Support.swift",
    SOURCE_ROOT / "Particles/SceneParticlePlaybackState.swift",
]


HARNESS_SOURCE = r'''
import CoreGraphics
import Foundation
import ImageIO
import Metal
import simd

struct SceneRenderDescriptor: Codable {
    struct Layer: Codable {
        let id: Int
        let name: String?
        let contentKind: String
        let particlePath: String?
        let particleInstanceOverride: SceneParticleInstanceOverride?
        let parentID: Int?
        let visible: Bool?
        let alpha: Double?
    }

    struct MaterialPassDescriptor: Codable {
        let materialPath: String
        let shaderPath: String?
        let texturePaths: [String]
        let blending: String?
        var combos: [String: Int] = [:]
    }

    let layers: [Layer]
    let renderOrderLayerIDs: [Int]
    let materialPasses: [MaterialPassDescriptor]
}

struct SceneLayerFragmentUniforms {
    var time: Float
    var alpha: Float
    var effectFlags: UInt32
    var dependencyBlendMode: UInt32
    var cursorUV: SIMD2<Float>
    var _pad1: SIMD2<Float>
    var tint: SIMD4<Float>
    var effectParams0: SIMD4<Float>
    var effectParams1: SIMD4<Float>
    var effectParams2: SIMD4<Float>
    var effectParams3: SIMD4<Float>
    var effectParams4: SIMD4<Float>
    var effectParams5: SIMD4<Float>
    var textureFrame0: SIMD4<Float>
    var textureFrame1: SIMD4<Float>
}

struct SceneEffectFlags: OptionSet {
    let rawValue: UInt32

    static let dependencyBlend = SceneEffectFlags(rawValue: 1 << 10)
}

final class SceneVideoTextureSource {
    init?(
        layerID: Int,
        mp4PayloadData: Data,
        cacheDirectory: URL,
        device: MTLDevice
    ) { return nil }
}

private struct Interpretation: Decodable {
    let renderDescriptor: SceneRenderDescriptor
}

@main
enum Harness {
    static func main() throws {
        guard CommandLine.arguments.count >= 2 else { throw HarnessError.missingMode }
        switch CommandLine.arguments[1] {
        case "real":
            guard CommandLine.arguments.count == 3 else { throw HarnessError.missingPath }
            try printJSON(realSample(cachePath: CommandLine.arguments[2]))
        case "eventspawn-real":
            guard CommandLine.arguments.count == 3 else { throw HarnessError.missingPath }
            try printJSON(realEventSpawnSample(cachePath: CommandLine.arguments[2]))
        case "eventdeath-real":
            guard CommandLine.arguments.count == 3 else { throw HarnessError.missingPath }
            try printJSON(realEventDeathSample(cachePath: CommandLine.arguments[2]))
        case "eventfollow-synthetic":
            try printJSON(syntheticEventFollow())
        case "continuous-profile-real":
            guard CommandLine.arguments.count == 3 else { throw HarnessError.missingPath }
            try printJSON(realContinuousProfiles(cachePath: CommandLine.arguments[2]))
        case "static-origin-real":
            guard CommandLine.arguments.count == 3 else { throw HarnessError.missingPath }
            try printJSON(realStaticOriginSample(cachePath: CommandLine.arguments[2]))
        case "synthetic":
            try printJSON(synthetic())
        default:
            throw HarnessError.missingMode
        }
    }

    private static func realSample(cachePath: String) throws -> [String: Any] {
        let cache = URL(fileURLWithPath: cachePath, isDirectory: true)
        let interpretation = try JSONDecoder().decode(
            Interpretation.self,
            from: Data(contentsOf: cache.appendingPathComponent(".mywallpaperx-scene-interpretation.json"))
        )
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let runtime = SceneParticleRuntime(
            descriptor: interpretation.renderDescriptor,
            cacheDirectory: cache,
            device: device
        )
        let initial = runtime.advance(by: 0)
        let initialInstances = initial.first?.instances ?? []
        let firstPositions = initialInstances.map(\.positionAndSize)
        let initialBufferMatchesData = initial.first?.instanceBuffer.count == initialInstances.count
        let advanced = runtime.advance(by: 1)
        let advancedInstances = advanced.first?.instances ?? []
        let secondPositions = advancedInstances.map(\.positionAndSize)
        let override = interpretation.renderDescriptor.layers
            .first(where: { $0.id == 196 })?.particleInstanceOverride
        guard let playback = SceneParticlePlaybackState(
            descriptor: interpretation.renderDescriptor,
            cacheDirectory: cache,
            device: device
        ) else { throw HarnessError.noParticlePipeline }
        let playbackReport = playback.loadReportLines(descriptor: interpretation.renderDescriptor)

        return [
            "activeLayerIDs": runtime.activeLayerIDs,
            "batchLayerIDs": initial.map(\.layerID),
            "initialCount": initialInstances.count,
            "advancedCount": advancedInstances.count,
            "stateChanged": firstPositions != secondPositions,
            "bufferMatchesData": initialBufferMatchesData,
            "blend": initial.first?.blendMode == .additive ? "additive" : "translucent",
            "usesPerspective": initial.first?.usesPerspective ?? false,
            "orientationScreen": initial.first?.orientation == .screen,
            "maximumLocalSize": initialInstances.map { $0.positionAndSize.w }.max() ?? 0,
            "meanLocalY": initialInstances.isEmpty ? 0 : initialInstances.reduce(0) {
                $0 + $1.positionAndSize.y
            } / Float(initialInstances.count),
            "overrideCount": scalar(override?.count),
            "overrideLifetime": scalar(override?.lifetime),
            "overrideSize": scalar(override?.size),
            "diagnosticKinds": runtime.diagnostics.map { $0.kind.rawValue },
            "playbackLoadedLine": playbackReport.first { $0.hasPrefix("particle loaded:") } ?? "",
            "missingBatchLoadedLine": SceneParticlePlaybackState.loadedSummaryLine(
                batchLayerIDs: [], visibleLayerCount: 1
            ),
        ]
    }

    private static func realEventSpawnSample(cachePath: String) throws -> [String: Any] {
        let cache = URL(fileURLWithPath: cachePath, isDirectory: true)
        let interpretation = try JSONDecoder().decode(
            Interpretation.self,
            from: Data(contentsOf: cache.appendingPathComponent(".mywallpaperx-scene-interpretation.json"))
        )
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let runtime = SceneParticleRuntime(
            descriptor: interpretation.renderDescriptor,
            cacheDirectory: cache,
            device: device
        )
        _ = runtime.advance(by: 0.5)
        let batches = runtime.advance(by: 1.0 / 60.0)
        let childPath = "particles/workshop/2562725207/presets/shootingstarglow.json"
        return [
            "activeLayerIDs": runtime.activeLayerIDs,
            "childInstanceCount": batches.first { $0.particlePath == childPath }?.instances.count ?? 0,
            "childTextureWidth": batches.first { $0.particlePath == childPath }?.texture.width ?? 0,
            "layer264ChildUnsupported": runtime.diagnostics.contains {
                $0.layerID == 264 && $0.kind == .childSystemsUnsupported
            },
        ]
    }

    private static func realEventDeathSample(cachePath: String) throws -> [String: Any] {
        let cache = URL(fileURLWithPath: cachePath, isDirectory: true)
        let interpretation = try JSONDecoder().decode(
            Interpretation.self,
            from: Data(contentsOf: cache.appendingPathComponent(".mywallpaperx-scene-interpretation.json"))
        )
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let runtime = SceneParticleRuntime(
            descriptor: interpretation.renderDescriptor,
            cacheDirectory: cache,
            device: device
        )
        let hitPath = "particles/workshop/2110548715/presets/fireworks1hit.json"
        var firstHitBatches: [SceneParticleDrawBatch] = []
        var firstRootInstances: [SceneParticleGPUInstance] = []
        var firstHitFrame = -1
        for frame in 0..<(8 * 60) {
            let batches = runtime.advance(by: 1.0 / 60.0)
            let hitBatches = batches.filter { $0.particlePath == hitPath }
            if !hitBatches.isEmpty {
                firstHitFrame = frame
                firstHitBatches = hitBatches
                firstRootInstances = batches.filter {
                    $0.layerID == 529 && $0.particlePath != hitPath
                }.flatMap(\.instances)
                break
            }
        }
        let hitBatches = firstHitBatches
        let hitInstances = hitBatches.flatMap(\.instances)
        let pixels = renderEventDeathBatches(hitBatches, device: device)
        return [
            "firstHitFrame": firstHitFrame,
            "hitInstanceCount": hitInstances.count,
            "hitMaximumAlpha": hitInstances.map(\.rotationAndAlpha.w).max() ?? -1,
            "hitMaximumSize": hitInstances.map(\.positionAndSize.w).max() ?? -1,
            "hitMaximumTrailStretch": hitInstances.map(\.velocityAndTrail.w).max() ?? -1,
            "hitMinimumPosition": vector(hitInstances.map(\.positionAndSize).min {
                $0.y < $1.y
            } ?? .zero),
            "hitMaximumPosition": vector(hitInstances.map(\.positionAndSize).max {
                $0.y < $1.y
            } ?? .zero),
            "rootPositions": firstRootInstances.map { vector($0.positionAndSize) },
            "renderedPixelCount": pixels["count"] ?? 0,
            "renderedPixelWidth": pixels["width"] ?? 0,
            "renderedPixelHeight": pixels["height"] ?? 0,
            "hitUsesTrail": hitBatches.contains {
                ($0.instances.first?.velocityAndTrail.w ?? -1) >= 0
            },
            "layer529ChildUnsupported": runtime.diagnostics.contains {
                $0.layerID == 529 && $0.kind == .childSystemsUnsupported
            },
            "layer529SimulationDetails": runtime.diagnostics.compactMap {
                $0.layerID == 529 && $0.kind == .simulationLimitation ? $0.detail : nil
            },
        ]
    }

    private static func renderEventDeathBatches(
        _ batches: [SceneParticleDrawBatch],
        device: MTLDevice
    ) -> [String: Int] {
        let width = 1280
        let height = 831
        guard !batches.isEmpty,
              let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue(),
              let command = queue.makeCommandBuffer() else { return [:] }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = .renderTarget
        descriptor.storageMode = .shared
        guard let output = device.makeTexture(descriptor: descriptor) else { return [:] }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return [:] }

        let origin = SIMD2<Float>(1783.794, 2160 - 589.649)
        let halfExtents = SIMD2<Float>(Float(width) / Float(height) * 1080, 1080)
        let model = simd_float4x4(columns: (
            SIMD4(1 / halfExtents.x, 0, 0, 0),
            SIMD4(0, 1 / halfExtents.y, 0, 0),
            SIMD4(0, 0, 1, 0),
            SIMD4(
                (origin.x - 1920) / halfExtents.x,
                1 - origin.y / halfExtents.y,
                0,
                1
            )
        ))
        let basis = SceneParticleOrientation.screen.basis(
            cameraRight: SIMD3(1, 0, 0),
            cameraUp: SIMD3(0, -1, 0),
            cameraForward: SIMD3(0, 0, -1)
        )
        for batch in batches {
            pipeline.draw(
                texture: batch.texture,
                instances: batch.instanceBuffer,
                uniforms: SceneParticleLayerUniforms(
                    viewProjection: matrix_identity_float4x4,
                    layerModel: model,
                    basis: basis
                ),
                blendMode: batch.blendMode,
                encoder: encoder
            )
        }
        encoder.endEncoding()
        for batch in batches { batch.instanceBuffer.markSubmitted(on: command) }
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else { return [:] }

        var values = [UInt8](repeating: 0, count: width * height * 4)
        output.getBytes(
            &values,
            bytesPerRow: width * 4,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )
        var count = 0
        var minimumX = width
        var minimumY = height
        var maximumX = -1
        var maximumY = -1
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                guard values[offset] > 3 || values[offset + 1] > 3 || values[offset + 2] > 3 else {
                    continue
                }
                count += 1
                minimumX = min(minimumX, x)
                minimumY = min(minimumY, y)
                maximumX = max(maximumX, x)
                maximumY = max(maximumY, y)
            }
        }
        return [
            "count": count,
            "width": maximumX >= minimumX ? maximumX - minimumX + 1 : 0,
            "height": maximumY >= minimumY ? maximumY - minimumY + 1 : 0,
        ]
    }

    private static func syntheticEventFollow() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-particle-follow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writeParticle(
            "particles/follow-root.json", material: "materials/shared.json",
            velocityX: 60, lifetime: 4.0 / 60.0, moves: true, rate: 0, instantaneous: 1,
            children: [[
                "name": "particles/follow-child.json", "type": "eventfollow", "maxcount": 1,
            ]], under: directory
        )
        try writeParticle(
            "particles/follow-child.json", material: "materials/shared.json",
            rate: 60, under: directory
        )
        try writeParticle(
            "particles/bounded-root.json", material: "materials/shared.json",
            lifetime: 1.0 / 60.0, rate: 0, instantaneous: 1,
            children: [[
                "name": "particles/bounded-child.json", "type": "eventspawn",
            ]], under: directory
        )
        try writeParticle(
            "particles/bounded-child.json", material: "materials/shared.json",
            lifetime: 2.0 / 60.0, rate: 60, emitterDuration: 3.0 / 60.0, under: directory
        )
        try writeParticle(
            "particles/budget-root.json", material: "materials/shared.json",
            rate: 0, instantaneous: 100,
            children: [[
                "name": "particles/budget-child.json", "type": "eventspawn",
            ]], under: directory
        )
        try writeParticle(
            "particles/budget-child.json", material: "materials/shared.json",
            rate: 60, instantaneous: 1, under: directory
        )
        try writeParticle(
            "particles/audio-root.json", material: "materials/shared.json",
            rate: 0, instantaneous: 1,
            children: [[
                "name": "particles/audio-child.json", "type": "eventspawn",
            ]], under: directory
        )
        try writeParticle(
            "particles/audio-child.json", material: "materials/shared.json",
            rate: 60, audioProcessingMode: 1, under: directory
        )

        let descriptor = SceneRenderDescriptor(
            layers: [
                layer(10, "particles/follow-root.json"),
                layer(11, "particles/bounded-root.json"),
                layer(12, "particles/budget-root.json"),
                layer(13, "particles/audio-root.json"),
            ],
            renderOrderLayerIDs: [10, 11, 12, 13],
            materialPasses: [
                .init(
                    materialPath: "materials/shared.json",
                    shaderPath: "genericparticle", texturePaths: ["shared.png"], blending: "additive"
                ),
            ]
        )
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: directory,
            device: device
        )
        var childCounts: [Int] = []
        var childPositions: [Float] = []
        var boundedCounts: [Int] = []
        var budgetCounts: [Int] = []
        for _ in 0..<6 {
            let batches = runtime.advance(by: 1.0 / 60.0)
            let instances = batches.first {
                $0.particlePath == "particles/follow-child.json"
            }?.instances ?? []
            childCounts.append(instances.count)
            if let position = instances.first?.positionAndSize.x {
                childPositions.append(position)
            }
            boundedCounts.append(batches.first {
                $0.particlePath == "particles/bounded-child.json"
            }?.instances.count ?? 0)
            budgetCounts.append(batches.first {
                $0.particlePath == "particles/budget-child.json"
            }?.instances.count ?? 0)
        }
        return [
            "childCounts": childCounts,
            "childPositions": childPositions,
            "boundedCounts": boundedCounts,
            "budgetCounts": budgetCounts,
            "childUnsupportedLayers": runtime.diagnostics.compactMap {
                $0.kind == .childSystemsUnsupported && $0.layerID != 13 ? $0.layerID : nil
            },
            "budgetDetails": runtime.diagnostics.compactMap {
                $0.layerID == 12 && $0.kind == .simulationLimitation ? $0.detail : nil
            },
            "audioChildDetails": runtime.diagnostics.compactMap {
                $0.layerID == 13 && $0.kind == .childSystemsUnsupported ? $0.detail : nil
            },
        ]
    }

    private static func realContinuousProfiles(cachePath: String) throws -> [String: Any] {
        let root = URL(fileURLWithPath: cachePath, isDirectory: true)
        let parser = SceneParticleDefinitionParser()
        var supported: [String: Bool] = [:]
        var completion: [String: String] = [:]
        var rates: [String: Double] = [:]
        var instantaneous: [String: Int] = [:]
        for name in ["Flare_Flame", "Flare_Smoke", "Flare_Sparks"] {
            let definition = try parser.parse(
                data: Data(contentsOf: root.appendingPathComponent("\(name).json"))
            )
            supported[name] = SceneParticleChildLifecycle.supportsEmitterProfile(definition)
            completion[name] = SceneParticleChildLifecycle.emissionCompletionTime(definition)
                .map { String($0) } ?? "infinite"
            rates[name] = definition.emitters.first?.rate ?? -1
            instantaneous[name] = definition.emitters.first?.instantaneousCount ?? 0
        }
        return [
            "supported": supported,
            "completion": completion,
            "rates": rates,
            "instantaneous": instantaneous,
        ]
    }

    private static func realStaticOriginSample(cachePath: String) throws -> [String: Any] {
        let cache = URL(fileURLWithPath: cachePath, isDirectory: true)
        let interpretation = try JSONDecoder().decode(
            Interpretation.self,
            from: Data(contentsOf: cache.appendingPathComponent(".mywallpaperx-scene-interpretation.json"))
        )
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let runtime = SceneParticleRuntime(
            descriptor: interpretation.renderDescriptor,
            cacheDirectory: cache,
            device: device
        )
        let childPath = "particles/presets/snowstormfog.json"
        let childBatches = runtime.advance(by: 0.5).filter {
            [513, 534].contains($0.layerID) && $0.particlePath == childPath
        }
        return [
            "childLayerIDs": childBatches.map(\.layerID).sorted(),
            "childInstanceCounts": childBatches.map(\.instances.count).sorted(),
            "childTextureWidths": childBatches.map(\.texture.width).sorted(),
            "unsupportedLayerIDs": runtime.diagnostics.compactMap {
                [513, 534].contains($0.layerID) && $0.kind == .childSystemsUnsupported
                    ? $0.layerID : nil
            }.sorted(),
        ]
    }

    private static func synthetic() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-particle-runtime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))

        try writeParticle("particles/no-texture.json", material: "materials/no-texture.json", under: directory)
        try writeParticle("particles/world.json", material: "materials/shared.json", flags: 1, under: directory)
        try writeParticle(
            "particles/trail.json", material: "materials/shared.json",
            renderer: "spritetrail", rendererLength: 0.05,
            rendererMinimumLength: 1, rendererMaximumLength: 10,
            velocityX: 100, under: directory
        )
        try writeParticle(
            "particles/child-root.json", material: "materials/shared.json",
            children: [[
                "name": "particles/child.json", "type": "eventspawn", "maxcount": 500,
            ]], under: directory
        )
        try writeParticle(
            "particles/child.json", material: "materials/shared.json",
            rate: 0, instantaneous: 1, under: directory
        )
        try writeParticle(
            "particles/unsupported-child-root.json", material: "materials/shared.json",
            children: [
                ["name": "particles/child.json", "type": "static"],
                ["name": "particles/child.json"],
                ["name": "particles/origin-child.json", "type": "static", "origin": "1 2 3"],
                ["name": "particles/angles-child.json", "type": "static", "angles": "1 0 0"],
                ["name": "particles/scale-child.json", "type": "static", "scale": "2 2 2"],
                ["name": "particles/event-origin-child.json", "type": "eventspawn", "origin": "1 2 3"],
                ["name": "particles/nan-origin-child.json", "type": "static", "origin": "nan 0 0"],
                ["name": "particles/probability-child.json", "type": "static", "probability": 0.5],
            ], under: directory
        )
        for path in [
            "particles/origin-child.json", "particles/angles-child.json",
            "particles/scale-child.json", "particles/event-origin-child.json",
            "particles/nan-origin-child.json", "particles/probability-child.json",
        ] {
            try writeParticle(
                path, material: "materials/shared.json", rate: 0, instantaneous: 1,
                under: directory
            )
        }
        try writeParticle("particles/drop.json", material: "materials/drop.json", under: directory)
        try writeParticle("particles/halo.json", material: "materials/halo.json", under: directory)
        try writeParticle("particles/unknown.json", material: "materials/unknown.json", under: directory)

        let descriptor = SceneRenderDescriptor(
            layers: [
                layer(1, "particles/no-texture.json"),
                layer(2, "particles/world.json"),
                layer(3, "particles/trail.json"),
                layer(4, "particles/child-root.json"),
                layer(5, "particles/hidden-never-loaded.json", visible: false),
                layer(6, "particles/drop.json"),
                layer(7, "particles/halo.json"),
                layer(8, "particles/unknown.json"),
                layer(9, "particles/unsupported-child-root.json"),
            ],
            renderOrderLayerIDs: [1, 2, 3, 4, 5, 6, 7, 8, 9],
            materialPasses: [
                .init(
                    materialPath: "materials/no-texture.json",
                    shaderPath: "genericparticle", texturePaths: [], blending: "translucent"
                ),
                .init(
                    materialPath: "materials/shared.json",
                    shaderPath: "genericparticle", texturePaths: ["shared.png"], blending: "additive"
                ),
                .init(
                    materialPath: "materials/drop.json",
                    shaderPath: "genericparticle", texturePaths: ["particle/drop"], blending: "additive"
                ),
                .init(
                    materialPath: "materials/halo.json",
                    shaderPath: "genericparticle", texturePaths: ["particle/halo"], blending: "additive"
                ),
                .init(
                    materialPath: "materials/unknown.json",
                    shaderPath: "genericparticle", texturePaths: ["particle/not-supported"], blending: "additive"
                ),
            ]
        )
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: directory,
            device: device
        )
        _ = runtime.advance(by: 0.25)
        let batches = runtime.advance(by: 0.25)
        return [
            "activeLayerIDs": runtime.activeLayerIDs,
            "batchLayerIDs": batches.map(\.layerID),
            "activeParticleCount": batches.first?.instances.count ?? 0,
            "childInstanceCount": batches.first {
                $0.particlePath == "particles/child.json"
            }?.instances.count ?? 0,
            "staticChildInstanceCount": batches.filter {
                $0.layerID == 9 && $0.particlePath != "particles/unsupported-child-root.json"
            }.reduce(0) { $0 + $1.instances.count },
            "staticChildOrigins": batches.filter {
                $0.layerID == 9 && $0.particlePath != "particles/unsupported-child-root.json"
            }.compactMap { batch in
                batch.instances.first.map {
                    [$0.positionAndSize.x, $0.positionAndSize.y, $0.positionAndSize.z]
                }
            },
            "staticChildUnsupportedDetails": runtime.diagnostics.compactMap {
                $0.layerID == 9 && $0.kind == .childSystemsUnsupported ? $0.detail : nil
            },
            "batchTextureSizes": batches.reduce(into: [String: [Int]]()) {
                $0[String($1.layerID)] = [$1.texture.width, $1.texture.height]
            },
            "trailStretch": batches.first(where: { $0.layerID == 3 })?
                .instances.first?.velocityAndTrail.w ?? -1,
            "trailVelocity": batches.first(where: { $0.layerID == 3 })?
                .instances.first.map {
                    [$0.velocityAndTrail.x, $0.velocityAndTrail.y, $0.velocityAndTrail.z]
                } ?? [],
            "diagnostics": runtime.diagnostics.map {
                [
                    "kind": $0.kind.rawValue,
                    "layer": $0.layerID as Any,
                    "path": $0.particlePath,
                    "detail": $0.detail as Any,
                ]
            },
            "hiddenMentioned": runtime.diagnostics.contains {
                $0.layerID == 5 || $0.particlePath.contains("hidden-never-loaded")
            },
        ]
    }

    private static func layer(
        _ id: Int,
        _ path: String,
        visible: Bool = true
    ) -> SceneRenderDescriptor.Layer {
        .init(
            id: id, name: nil, contentKind: "particle", particlePath: path,
            particleInstanceOverride: nil, parentID: nil, visible: visible, alpha: 1
        )
    }

    private static func writeParticle(
        _ path: String,
        material: String,
        flags: Int = 0,
        renderer: String = "sprite",
        rendererLength: Double? = nil,
        rendererMinimumLength: Double? = nil,
        rendererMaximumLength: Double? = nil,
        velocityX: Double? = nil,
        lifetime: Double = 10,
        moves: Bool = false,
        rate: Double = 60,
        emitterDuration: Double? = nil,
        audioProcessingMode: Int? = nil,
        instantaneous: Int? = nil,
        children: [[String: Any]] = [],
        under root: URL
    ) throws {
        var initializers: [[String: Any]] = [
            ["name": "lifetimerandom", "min": lifetime, "max": lifetime],
            ["name": "sizerandom", "min": 8, "max": 8],
        ]
        if let velocityX {
            initializers.append([
                "name": "velocityrandom",
                "min": [velocityX, 0, 0],
                "max": [velocityX, 0, 0],
            ])
        }
        var rendererDefinition: [String: Any] = ["name": renderer]
        if let rendererLength { rendererDefinition["length"] = rendererLength }
        if let rendererMinimumLength { rendererDefinition["minlength"] = rendererMinimumLength }
        if let rendererMaximumLength { rendererDefinition["maxlength"] = rendererMaximumLength }
        var emitter: [String: Any] = [
            "name": "sphererandom", "rate": rate, "distancemin": 0, "distancemax": 0,
        ]
        if let emitterDuration { emitter["duration"] = emitterDuration }
        if let audioProcessingMode { emitter["audioprocessingmode"] = audioProcessingMode }
        if let instantaneous { emitter["instantaneous"] = instantaneous }
        var definition: [String: Any] = [
            "material": material,
            "maxcount": 100,
            "flags": flags,
            "emitter": [emitter],
            "initializer": initializers,
            "renderer": [rendererDefinition],
            "children": children,
        ]
        if moves { definition["operator"] = [["name": "movement"]] }
        try writeJSON(definition, to: root.appendingPathComponent(path))
    }

    private static func writeJSON(_ value: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]).write(to: url)
    }

    private static func writePNG(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage(),
           let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        else { throw HarnessError.imageWrite }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw HarnessError.imageWrite }
    }

    private static func scalar(_ value: SceneParticleBoundValue?) -> Double {
        value?.value?.scalarValue ?? -1
    }

    private static func vector(_ value: SIMD4<Float>) -> [Float] {
        [value.x, value.y, value.z, value.w]
    }

    private static func printJSON(_ value: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    private enum HarnessError: Error {
        case missingMode
        case missingPath
        case noMetal
        case noParticlePipeline
        case imageWrite
    }
}
'''


class SceneParticleRuntimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-particle-runtime-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "scene-particle-runtime"
        compilation = subprocess.run(
            [
                swiftc,
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-framework", "Metal",
                "-framework", "CoreGraphics",
                "-framework", "ImageIO",
                "-o", str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def run_harness(self, *arguments: str) -> dict[str, object]:
        completed = subprocess.run(
            [str(self.binary), *arguments],
            check=True,
            capture_output=True,
            text=True,
        )
        return json.loads(completed.stdout)

    def test_real_3742133044_only_assembles_visible_snow_layer(self) -> None:
        if not (REAL_SAMPLE_CACHE / ".mywallpaperx-scene-interpretation.json").is_file():
            self.skipTest("isolated 3742133044 cache is unavailable")
        result = self.run_harness("real", str(REAL_SAMPLE_CACHE))
        self.assertEqual(result["activeLayerIDs"], [196])
        self.assertEqual(result["batchLayerIDs"], [196])
        self.assertGreater(result["initialCount"], 0)
        self.assertTrue(result["stateChanged"])
        self.assertTrue(result["bufferMatchesData"])
        self.assertEqual(result["blend"], "additive")
        self.assertTrue(result["usesPerspective"])
        self.assertTrue(result["orientationScreen"])
        self.assertAlmostEqual(result["overrideCount"], 0.60000002, places=6)
        self.assertAlmostEqual(result["overrideLifetime"], 1.4, places=6)
        self.assertAlmostEqual(result["overrideSize"], 1.8, places=6)
        self.assertLessEqual(result["maximumLocalSize"], 72.001)
        self.assertGreater(result["maximumLocalSize"], 9)
        self.assertLess(result["meanLocalY"], 700)
        self.assertEqual(result["playbackLoadedLine"], "particle loaded: 1 / 1")
        self.assertEqual(result["missingBatchLoadedLine"], "particle loaded: 0 / 1")

    def test_synthetic_rejects_unsupported_roots_and_keeps_diagnostics(self) -> None:
        result = self.run_harness("synthetic")
        self.assertEqual(result["activeLayerIDs"], [3, 4, 6, 7, 9])
        self.assertEqual(result["batchLayerIDs"], [3, 4, 4, 6, 7, 9, 9, 9, 9])
        self.assertGreater(result["activeParticleCount"], 0)
        self.assertGreater(result["childInstanceCount"], 0)
        self.assertEqual(result["staticChildInstanceCount"], 3)
        self.assertEqual(result["staticChildOrigins"], [[0, 0, 0], [0, 0, 0], [1, 2, 3]])
        # 内置纹理尺寸已对齐官方 .tex 的 imageWidth/imageHeight，非方形纹理不再按方形近似。
        self.assertEqual(result["batchTextureSizes"]["6"], [32, 128])
        self.assertEqual(result["batchTextureSizes"]["7"], [64, 64])
        self.assertAlmostEqual(result["trailStretch"], 5)
        self.assertEqual(result["trailVelocity"], [100, 0, 0])
        self.assertFalse(result["hiddenMentioned"])
        diagnostics = result["diagnostics"]
        kinds = {value["kind"] for value in diagnostics}
        self.assertIn("missingTextureReference", kinds)
        self.assertIn("worldSpaceUnsupported", kinds)
        self.assertNotIn("trailRendererUnsupported", kinds)
        self.assertNotIn("missingSpriteRenderer", kinds)
        self.assertIn("childSystemsUnsupported", kinds)
        for path in [
            "particles/angles-child.json",
            "particles/scale-child.json",
            "particles/event-origin-child.json",
            "particles/nan-origin-child.json",
        ]:
            self.assertIn(
                f"{path}:unsupportedTransformOrControlPoint",
                result["staticChildUnsupportedDetails"],
            )
        self.assertIn(
            "particles/probability-child.json:unsupportedStaticProbability",
            result["staticChildUnsupportedDetails"],
        )
        self.assertIn("builtInTextureUnavailable", kinds)

    def test_continuous_children_follow_finish_and_obey_aggregate_budget(self) -> None:
        result = self.run_harness("eventfollow-synthetic")
        self.assertEqual(result["childCounts"], [0, 1, 2, 0, 0, 0])
        self.assertEqual(result["childPositions"], [2, 3])
        self.assertEqual(result["boundedCounts"], [0, 1, 1, 1, 0, 0])
        self.assertEqual(result["budgetCounts"], [0, 64, 128, 192, 256, 320])
        self.assertEqual(result["childUnsupportedLayers"], [])
        self.assertIn(
            "aggregateSystemBudget:systems=64:particleCapacity=65536",
            result["budgetDetails"],
        )
        self.assertIn(
            "particles/audio-child.json:outsideStrictEventProfile",
            result["audioChildDetails"],
        )

    def test_real_flare_children_enter_continuous_emitter_profile(self) -> None:
        if not FLARE_PARTICLE_CACHE.is_dir():
            self.skipTest("isolated 2998757800 particle cache is unavailable")
        result = self.run_harness("continuous-profile-real", str(FLARE_PARTICLE_CACHE))
        self.assertEqual(result["supported"], {
            "Flare_Flame": True,
            "Flare_Smoke": True,
            "Flare_Sparks": True,
        })
        self.assertEqual(set(result["completion"].values()), {"infinite"})
        self.assertEqual(result["rates"]["Flare_Sparks"], 10)
        self.assertEqual(result["instantaneous"]["Flare_Sparks"], 1)

    def test_real_3088601835_applies_static_snowstorm_fog_origin(self) -> None:
        if not (STATIC_ORIGIN_SAMPLE_CACHE / ".mywallpaperx-scene-interpretation.json").is_file():
            self.skipTest("isolated 3088601835 cache is unavailable")
        result = self.run_harness("static-origin-real", str(STATIC_ORIGIN_SAMPLE_CACHE))
        self.assertEqual(result["childLayerIDs"], [513, 534])
        self.assertEqual(result["childInstanceCounts"], [1, 1])
        self.assertEqual(result["childTextureWidths"], [128, 128])
        self.assertEqual(result["unsupportedLayerIDs"], [])

    def test_real_3768903841_executes_strict_eventspawn_child(self) -> None:
        if not (EVENTSPAWN_SAMPLE_CACHE / ".mywallpaperx-scene-interpretation.json").is_file():
            self.skipTest("isolated 3768903841 cache is unavailable")
        result = self.run_harness("eventspawn-real", str(EVENTSPAWN_SAMPLE_CACHE))
        self.assertIn(264, result["activeLayerIDs"])
        self.assertGreater(result["childInstanceCount"], 0)
        self.assertEqual(result["childTextureWidth"], 128)
        self.assertFalse(result["layer264ChildUnsupported"])

    def test_real_2131872317_executes_eventdeath_firework_burst(self) -> None:
        if not (EVENTDEATH_SAMPLE_CACHE / ".mywallpaperx-scene-interpretation.json").is_file():
            self.skipTest("isolated 2131872317 cache is unavailable")
        result = self.run_harness("eventdeath-real", str(EVENTDEATH_SAMPLE_CACHE))
        self.assertGreater(result["firstHitFrame"], 0)
        self.assertEqual(result["hitInstanceCount"], 1_024)
        self.assertGreater(result["hitMaximumAlpha"], 0)
        self.assertGreater(result["hitMaximumSize"], 0)
        self.assertGreater(result["hitMaximumTrailStretch"], 1)
        self.assertGreater(result["renderedPixelCount"], 1_000)
        self.assertGreater(result["renderedPixelWidth"], 100)
        self.assertGreater(result["renderedPixelHeight"], 100)
        self.assertTrue(result["hitUsesTrail"])
        self.assertFalse(result["layer529ChildUnsupported"])
        self.assertIn(
            "particles/workshop/2110548715/presets/fireworks1hit.json:particleBudget:"
            "max=20000:instantaneous=8500:effective=1024",
            result["layer529SimulationDetails"],
        )


if __name__ == "__main__":
    unittest.main()
