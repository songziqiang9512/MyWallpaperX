#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

from scene_real_test_fixtures import sample_cache_root, sample_runtime_evidence_path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
REAL_SAMPLE_CACHE = sample_cache_root("3742133044")
REAL_SAMPLE_EVIDENCE = sample_runtime_evidence_path("3742133044")
EVENTSPAWN_SAMPLE_CACHE = sample_cache_root("3768903841")
EVENTSPAWN_SAMPLE_EVIDENCE = sample_runtime_evidence_path("3768903841")
EVENTDEATH_SAMPLE_CACHE = sample_cache_root("2131872317")
EVENTDEATH_SAMPLE_EVIDENCE = sample_runtime_evidence_path("2131872317")
FLARE_PARTICLE_CACHE = (
    sample_cache_root("2998757800") / "particles/workshop/2105295491"
)
STATIC_ORIGIN_SAMPLE_CACHE = sample_cache_root("3088601835")
STATIC_ORIGIN_SAMPLE_EVIDENCE = sample_runtime_evidence_path("3088601835")
REFRACTION_SAMPLE_CACHE = sample_cache_root("3768229922")
REFRACTION_SAMPLE_EVIDENCE = sample_runtime_evidence_path("3768229922")
WATER_IMPACT_SAMPLE_CACHE = sample_cache_root("3770444459")
WATER_IMPACT_SAMPLE_EVIDENCE = sample_runtime_evidence_path("3770444459")
NESTED_SAMPLE_CACHE = sample_cache_root("2974757317")
NESTED_SAMPLE_EVIDENCE = sample_runtime_evidence_path("2974757317")
NESTED_AUTHOR_OFF_SAMPLE_CACHE = sample_cache_root("2938612768")
NESTED_AUTHOR_OFF_SAMPLE_EVIDENCE = sample_runtime_evidence_path("2938612768")
SWIFT_SOURCES = [
    SOURCE_ROOT / "RenderGraph/SceneMaterialRenderState.swift",
    SOURCE_ROOT / "Resources/SceneTextureSampling.swift",
    SOURCE_ROOT / "Resources/SceneResourceIndex.swift",
    SOURCE_ROOT / "Resources/SceneResourceView.swift",
    SOURCE_ROOT / "Resources/SceneStockTextureResolver.swift",
    SOURCE_ROOT / "Particles/SceneParticleDefinition.swift",
    SOURCE_ROOT / "Particles/SceneParticleDefinitionParser.swift",
    SOURCE_ROOT / "Particles/SceneParticleWorldSpacePlan.swift",
    SOURCE_ROOT / "Particles/SceneParticleTextureSource.swift",
    SOURCE_ROOT / "Particles/SceneParticleRefractionPlan.swift",
    SOURCE_ROOT / "Particles/SceneParticleRefractionBinding.swift",
    SOURCE_ROOT / "Particles/SceneParticleRefractionTextureLoader.swift",
    SOURCE_ROOT / "Particles/SceneParticleBuiltInTextureRegistry.swift",
    SOURCE_ROOT / "Particles/SceneParticleAssetGraph.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulationSupport.swift",
    SOURCE_ROOT / "Particles/SceneParticleControlPointForce.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulator+ControlPointForce.swift",
    SOURCE_ROOT / "Particles/SceneParticlePeriodicEmission.swift",
    SOURCE_ROOT / "Particles/SceneParticleLayerImageEmissionMap.swift",
    SOURCE_ROOT / "Particles/SceneParticleOscillationCache.swift",
    SOURCE_ROOT / "Particles/SceneParticleStepSnapshotRecorder.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulator.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulator+Random.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulator+InstanceOverride.swift",
    SOURCE_ROOT / "Particles/SceneParticleChildLifecycle.swift",
    SOURCE_ROOT / "Particles/SceneParticleChildTemplateSupport.swift",
    SOURCE_ROOT / "Particles/SceneParticleTrailRenderPlan.swift",
    SOURCE_ROOT / "Particles/SceneParticleRopeTrailPlan.swift",
    SOURCE_ROOT / "Particles/SceneParticleRenderSupport.swift",
    SOURCE_ROOT / "Particles/SceneParticleMetalInstanceBuffer.swift",
    SOURCE_ROOT / "Particles/SceneParticleShaderSource.swift",
    SOURCE_ROOT / "Particles/SceneParticleSamplerStateSet.swift",
    SOURCE_ROOT / "Particles/SceneParticleMetalPipeline.swift",
    SOURCE_ROOT / "Rendering/SceneFramebufferSnapshot.swift",
    SOURCE_ROOT / "Format/SceneTexDataReader.swift",
    SOURCE_ROOT / "Format/SceneTexContainer.swift",
    SOURCE_ROOT / "Format/SceneBCTextureDecoder.swift",
    SOURCE_ROOT / "Resources/SceneImageTextureUploader.swift",
    SOURCE_ROOT / "Resources/SceneCompressedTextureUploader.swift",
    SOURCE_ROOT / "Resources/SceneTextureMipUploader.swift",
    SOURCE_ROOT / "Resources/SceneTextureLoader.swift",
    SOURCE_ROOT / "Resources/SceneTextureUVTransform.swift",
    SOURCE_ROOT / "Resources/SceneTextureCandidate.swift",
    SOURCE_ROOT / "Resources/SceneTextureLoader+Candidate.swift",
    SOURCE_ROOT / "Runtime/SceneTextureAnimationPlaybackPlan.swift",
    SOURCE_ROOT / "Resources/SceneTextureAnimationPlaybackClock.swift",
    SOURCE_ROOT / "Rendering/SceneSpriteAnimation.swift",
    SOURCE_ROOT / "Rendering/SceneLayerVisibility.swift",
    SOURCE_ROOT / "Particles/SceneParticleChildGraphExpansion.swift",
    SOURCE_ROOT / "Particles/SceneParticleChildRuntimeModels.swift",
    SOURCE_ROOT / "Particles/SceneParticleChildRuntime.swift",
    SOURCE_ROOT / "Particles/SceneParticleRuntimeModels.swift",
    SOURCE_ROOT / "Particles/SceneParticleRuntime.swift",
    SOURCE_ROOT / "Particles/SceneParticleRuntime+Support.swift",
    SOURCE_ROOT / "Particles/SceneParticlePlaybackState.swift",
    SOURCE_ROOT / "Properties/SceneDynamicSnapshot.swift",
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
        let passIndex: Int
        let shaderPath: String?
        let texturePaths: [String]
        let textureSlots: [String?]
        let constantShaderValues: [String: SceneDocument.ShaderValue]
        let userTextureInputs: [SceneUserTextureInput?]
        let userShaderValues: [String: String]
        let blending: String?
        let combos: [String: Int]
        let depthTest: String?
        let depthWrite: String?
        let cullMode: String?
        let alphaWriting: String?

        init(
            materialPath: String,
            passIndex: Int = 0,
            shaderPath: String?,
            texturePaths: [String],
            textureSlots: [String?]? = nil,
            constantShaderValues: [String: SceneDocument.ShaderValue] = [:],
            userTextureInputs: [SceneUserTextureInput?] = [],
            userShaderValues: [String: String] = [:],
            blending: String?,
            combos: [String: Int] = [:],
            depthTest: String? = "disabled",
            depthWrite: String? = "disabled",
            cullMode: String? = "nocull",
            alphaWriting: String? = nil
        ) {
            self.materialPath = materialPath
            self.passIndex = passIndex
            self.shaderPath = shaderPath
            self.texturePaths = texturePaths
            self.textureSlots = textureSlots ?? texturePaths.map(Optional.some)
            self.constantShaderValues = constantShaderValues
            self.userTextureInputs = userTextureInputs
            self.userShaderValues = userShaderValues
            self.blending = blending
            self.combos = combos
            self.depthTest = depthTest
            self.depthWrite = depthWrite
            self.cullMode = cullMode
            self.alphaWriting = alphaWriting
        }
    }

    let layers: [Layer]
    let renderOrderLayerIDs: [Int]
    let materialPasses: [MaterialPassDescriptor]

    var staticParticleWorldSpaceFrames: [Int: SceneParticleWorldSpaceFrame] {
        Dictionary(uniqueKeysWithValues: layers.map {
            ($0.id, SceneParticleWorldSpaceFrame(worldFrame: matrix_identity_float4x4)!)
        })
    }
}

struct SceneDocument {
    struct ShaderValue: Codable {
        let rawValue: String
        let valueKind: String
        let components: [Double]?
        let userBinding: String?
        let timeline: SceneJSONPresence?
        let timelineDiagnostics: [String]
    }
}

struct SceneJSONPresence: Codable {
    init(from decoder: Decoder) throws {}
    func encode(to encoder: Encoder) throws {}
}

struct SceneUserTextureInput: Codable {
    init(from decoder: Decoder) throws {}
    func encode(to encoder: Encoder) throws {}
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

private struct RuntimeEvidence: Decodable {
    struct RuntimeInput: Decodable {
        let renderDescriptor: SceneRenderDescriptor
    }

    let runtimeInput: RuntimeInput
}

@main
enum Harness {
    static func main() throws {
        guard CommandLine.arguments.count >= 2 else { throw HarnessError.missingMode }
        switch CommandLine.arguments[1] {
        case "real":
            guard CommandLine.arguments.count == 4 else { throw HarnessError.missingPath }
            try printJSON(realSample(
                evidencePath: CommandLine.arguments[2],
                cachePath: CommandLine.arguments[3]
            ))
        case "eventspawn-real":
            guard CommandLine.arguments.count == 4 else { throw HarnessError.missingPath }
            try printJSON(realEventSpawnSample(
                evidencePath: CommandLine.arguments[2],
                cachePath: CommandLine.arguments[3]
            ))
        case "eventdeath-real":
            guard CommandLine.arguments.count == 4 else { throw HarnessError.missingPath }
            try printJSON(realEventDeathSample(
                evidencePath: CommandLine.arguments[2],
                cachePath: CommandLine.arguments[3]
            ))
        case "eventfollow-synthetic":
            try printJSON(syntheticEventFollow())
        case "nested-synthetic":
            try printJSON(syntheticNestedChildren())
        case "nested-real":
            guard CommandLine.arguments.count == 4 else { throw HarnessError.missingPath }
            try printJSON(realNestedMatrix(
                evidencePath: CommandLine.arguments[2],
                cachePath: CommandLine.arguments[3]
            ))
        case "continuous-profile-real":
            guard CommandLine.arguments.count == 3 else { throw HarnessError.missingPath }
            try printJSON(realContinuousProfiles(cachePath: CommandLine.arguments[2]))
        case "static-origin-real":
            guard CommandLine.arguments.count == 4 else { throw HarnessError.missingPath }
            try printJSON(realStaticOriginSample(
                evidencePath: CommandLine.arguments[2],
                cachePath: CommandLine.arguments[3]
            ))
        case "refraction-real":
            guard CommandLine.arguments.count == 4 else { throw HarnessError.missingPath }
            try printJSON(realRefractionSample(
                evidencePath: CommandLine.arguments[2],
                cachePath: CommandLine.arguments[3]
            ))
        case "refraction-child-real":
            guard CommandLine.arguments.count == 4 else { throw HarnessError.missingPath }
            try printJSON(realRefractionChildSample(
                evidencePath: CommandLine.arguments[2],
                cachePath: CommandLine.arguments[3]
            ))
        case "water-impact-real":
            guard CommandLine.arguments.count == 4 else { throw HarnessError.missingPath }
            try printJSON(realWaterImpactSample(
                evidencePath: CommandLine.arguments[2],
                cachePath: CommandLine.arguments[3]
            ))
        case "stock-synthetic":
            guard CommandLine.arguments.count == 3 else { throw HarnessError.missingPath }
            try printJSON(stockSynthetic(bundlePath: CommandLine.arguments[2]))
        case "rope-trail-synthetic":
            try printJSON(syntheticRopeTrail())
        case "dynamic-control-point-synthetic":
            try printJSON(syntheticDynamicControlPoint())
        case "synthetic":
            try printJSON(synthetic())
        default:
            throw HarnessError.missingMode
        }
    }

    private static func renderDescriptor(evidencePath: String) throws -> SceneRenderDescriptor {
        let evidenceURL = URL(fileURLWithPath: evidencePath)
        return try JSONDecoder().decode(
            RuntimeEvidence.self,
            from: Data(contentsOf: evidenceURL)
        ).runtimeInput.renderDescriptor
    }

    private static func realSample(
        evidencePath: String,
        cachePath: String
    ) throws -> [String: Any] {
        let cache = URL(fileURLWithPath: cachePath, isDirectory: true)
        let descriptor = try renderDescriptor(evidencePath: evidencePath)
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
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
        let override = descriptor.layers
            .first(where: { $0.id == 196 })?.particleInstanceOverride
        guard let playback = SceneParticlePlaybackState(
            descriptor: descriptor,
            cacheDirectory: cache,
            device: device
        ) else { throw HarnessError.noParticlePipeline }
        let playbackReport = playback.loadReportLines(descriptor: descriptor)

        return [
            "activeLayerIDs": runtime.activeLayerIDs,
            "batchLayerIDs": initial.map(\.layerID),
            "initialCount": initialInstances.count,
            "advancedCount": advancedInstances.count,
            "stateChanged": firstPositions != secondPositions,
            "bufferMatchesData": initialBufferMatchesData,
            "blend": initial.first?.renderState.blendMode.rawValue ?? "",
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

    private static func realRefractionSample(
        evidencePath: String,
        cachePath: String
    ) throws -> [String: Any] {
        let descriptor = try renderDescriptor(evidencePath: evidencePath)
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: URL(fileURLWithPath: cachePath, isDirectory: true),
            device: device,
            stockTextureBundleURL: URL(fileURLWithPath:
                "\(FileManager.default.currentDirectoryPath)/MyWallpaperX/Resources/SceneStockAssets.bundle",
                isDirectory: true
            )
        )
        let batches = runtime.advance(by: 0)
        return [
            "batchLayerIDs": batches.map(\.layerID),
            "refractionLayerIDs": batches.filter { $0.refraction != nil }.map(\.layerID),
            "sameTextureIdentity": batches.filter { $0.refraction != nil }.allSatisfy {
                $0.texture === $0.refraction?
                    .resolvedNormalArguments()?.texture
            },
            "staticCandidateLayerIDs": batches.filter {
                $0.refraction?.usesStaticNormalCandidate == true
            }.map(\.layerID),
            "amounts": batches.compactMap { $0.refraction?.amount },
            "diagnostics": runtime.diagnostics.map(\.kind.rawValue),
            "diagnosticDetails": runtime.diagnostics.map { $0.detail ?? "" },
        ]
    }

    private static func realRefractionChildSample(
        evidencePath: String,
        cachePath: String
    ) throws -> [String: Any] {
        let descriptor = try renderDescriptor(evidencePath: evidencePath)
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: URL(fileURLWithPath: cachePath, isDirectory: true),
            device: device,
            stockTextureBundleURL: URL(fileURLWithPath:
                "\(FileManager.default.currentDirectoryPath)/MyWallpaperX/Resources/SceneStockAssets.bundle",
                isDirectory: true
            )
        )
        var paths = Set<String>()
        var candidatePaths = Set<String>()
        var legacyPaths = Set<String>()
        var firstFrame = -1
        for frame in 0..<(7 * 60) {
            let refractive = runtime.advance(by: 1.0 / 60.0).filter {
                $0.refraction != nil && !$0.instances.isEmpty
            }
            if !refractive.isEmpty && firstFrame < 0 { firstFrame = frame }
            paths.formUnion(refractive.map(\.particlePath))
            candidatePaths.formUnion(refractive.filter {
                $0.refraction?.usesStaticNormalCandidate == true
            }.map(\.particlePath))
            legacyPaths.formUnion(refractive.filter {
                $0.refraction?.usesStaticNormalCandidate == false
            }.map(\.particlePath))
        }
        return [
            "firstFrame": firstFrame,
            "paths": paths.sorted(),
            "candidatePaths": candidatePaths.sorted(),
            "legacyPaths": legacyPaths.sorted(),
            "refractionUnsupported": runtime.diagnostics.filter {
                $0.kind == .refractionUnsupported
            }.map { $0.detail ?? "" },
        ]
    }

    private static func realWaterImpactSample(
        evidencePath: String,
        cachePath: String
    ) throws -> [String: Any] {
        let descriptor = try renderDescriptor(evidencePath: evidencePath)
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: URL(fileURLWithPath: cachePath, isDirectory: true),
            device: device,
            stockTextureBundleURL: URL(fileURLWithPath:
                "\(FileManager.default.currentDirectoryPath)/MyWallpaperX/Resources/SceneStockAssets.bundle",
                isDirectory: true
            )
        )
        let targetLayers = Set([239, 245, 248])
        var activeFrames: [Int: Int] = [:]
        var maximumInstances: [Int: Int] = [:]
        var candidateLayers = Set<Int>()
        var legacyLayers = Set<Int>()
        for _ in 0..<(8 * 60) {
            for batch in runtime.advance(by: 1.0 / 60.0) {
                if batch.refraction?.usesStaticNormalCandidate == true {
                    candidateLayers.insert(batch.layerID)
                } else if batch.refraction != nil {
                    legacyLayers.insert(batch.layerID)
                }
                if targetLayers.contains(batch.layerID)
                    && batch.refraction != nil
                    && !batch.instances.isEmpty {
                    activeFrames[batch.layerID, default: 0] += 1
                    maximumInstances[batch.layerID] = max(
                        maximumInstances[batch.layerID, default: 0],
                        batch.instances.count
                    )
                }
            }
        }
        return [
            "activeFrames": Dictionary(uniqueKeysWithValues: targetLayers.sorted().map {
                (String($0), activeFrames[$0, default: 0])
            }),
            "maximumInstances": Dictionary(uniqueKeysWithValues: targetLayers.sorted().map {
                (String($0), maximumInstances[$0, default: 0])
            }),
            "candidateLayers": candidateLayers.sorted(),
            "legacyLayers": legacyLayers.sorted(),
            "refractionUnsupported": runtime.diagnostics.filter {
                $0.kind == .refractionUnsupported
            }.map { $0.detail ?? "" },
        ]
    }

    private static func realEventSpawnSample(
        evidencePath: String,
        cachePath: String
    ) throws -> [String: Any] {
        let cache = URL(fileURLWithPath: cachePath, isDirectory: true)
        let descriptor = try renderDescriptor(evidencePath: evidencePath)
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
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

    private static func realEventDeathSample(
        evidencePath: String,
        cachePath: String
    ) throws -> [String: Any] {
        let cache = URL(fileURLWithPath: cachePath, isDirectory: true)
        let descriptor = try renderDescriptor(evidencePath: evidencePath)
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
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
                renderState: batch.renderState,
                colorSampling: batch.colorSampling,
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
            flags: 1, rate: 60, under: directory
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
        try writeParticle(
            "particles/window-root.json", material: "materials/shared.json",
            rate: 0, instantaneous: 1,
            children: [[
                "name": "particles/window-child.json", "type": "eventspawn",
            ]], under: directory
        )
        try writeParticle(
            "particles/window-child.json", material: "materials/shared.json",
            lifetime: 2.0 / 60.0, rate: 60, under: directory
        )

        let descriptor = SceneRenderDescriptor(
            layers: [
                layer(10, "particles/follow-root.json"),
                layer(11, "particles/bounded-root.json"),
                layer(12, "particles/budget-root.json"),
                layer(13, "particles/audio-root.json"),
                layer(14, "particles/window-root.json"),
            ],
            renderOrderLayerIDs: [10, 11, 12, 13, 14],
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
        var windowCounts: [Int] = []
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
            windowCounts.append(batches.first {
                $0.particlePath == "particles/window-child.json"
            }?.instances.count ?? 0)
        }
        return [
            "windowCounts": windowCounts,
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

    private static func syntheticNestedChildren() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-particle-nested-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writeParticle(
            "particles/nested-root.json", material: "materials/shared.json",
            rate: 0, instantaneous: 1,
            children: [["name": "particles/nested-head.json", "origin": "40 0 0"]],
            under: directory
        )
        try writeParticle(
            "particles/nested-head.json", material: "materials/shared.json",
            velocityX: 60, lifetime: 5.0 / 60.0, moves: true, rate: 0, instantaneous: 1,
            children: [[
                "name": "particles/nested-trail.json", "type": "eventfollow", "maxcount": 1,
            ]], under: directory
        )
        try writeParticle(
            "particles/nested-trail.json", material: "materials/shared.json",
            rate: 60, under: directory
        )
        try writeParticle(
            "particles/depth-root.json", material: "materials/shared.json",
            rate: 0, instantaneous: 1,
            children: [["name": "particles/depth-two.json", "type": "eventfollow"]],
            under: directory
        )
        try writeParticle(
            "particles/depth-two.json", material: "materials/shared.json",
            rate: 60,
            children: [["name": "particles/depth-three.json", "type": "eventfollow"]],
            under: directory
        )
        try writeParticle(
            "particles/depth-three.json", material: "materials/shared.json",
            rate: 60,
            children: [["name": "particles/depth-four.json", "type": "eventfollow"]],
            under: directory
        )
        try writeParticle(
            "particles/depth-four.json", material: "materials/shared.json",
            rate: 60, under: directory
        )
        try writeParticle(
            "particles/static-root.json", material: "materials/shared.json",
            rate: 0, instantaneous: 1,
            children: [["name": "particles/static-mid.json"]], under: directory
        )
        try writeParticle(
            "particles/static-mid.json", material: "materials/shared.json",
            rate: 60,
            children: [["name": "particles/static-leaf.json", "type": "static"]],
            under: directory
        )
        try writeParticle(
            "particles/static-leaf.json", material: "materials/shared.json",
            rate: 60, under: directory
        )
        try writeParticle(
            "particles/budget-nested-root.json", material: "materials/shared.json",
            rate: 0, instantaneous: 1,
            children: [["name": "particles/budget-nested-head.json"]], under: directory
        )
        try writeParticle(
            "particles/budget-nested-head.json", material: "materials/shared.json",
            rate: 0, instantaneous: 80,
            children: [[
                "name": "particles/budget-nested-trail.json", "type": "eventfollow",
                "maxcount": 512,
            ]], under: directory
        )
        try writeParticle(
            "particles/budget-nested-trail.json", material: "materials/shared.json",
            rate: 60, under: directory
        )

        let descriptor = SceneRenderDescriptor(
            layers: [
                layer(20, "particles/nested-root.json"),
                layer(21, "particles/depth-root.json"),
                layer(22, "particles/static-root.json"),
                layer(23, "particles/budget-nested-root.json"),
            ],
            renderOrderLayerIDs: [20, 21, 22, 23],
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
        var trailCounts: [Int] = []
        var trailOrigins: [Float] = []
        var headPositions: [Float] = []
        var budgetTrailCounts: [Int] = []
        for _ in 0..<6 {
            let batches = runtime.advance(by: 1.0 / 60.0)
            let trail = batches.first {
                $0.particlePath == "particles/nested-trail.json"
            }?.instances ?? []
            trailCounts.append(trail.count)
            if let first = trail.first { trailOrigins.append(first.positionAndSize.x) }
            let head = batches.first {
                $0.particlePath == "particles/nested-head.json"
            }?.instances ?? []
            if let first = head.first { headPositions.append(first.positionAndSize.x) }
            budgetTrailCounts.append(batches.first {
                $0.particlePath == "particles/budget-nested-trail.json"
            }?.instances.count ?? 0)
        }
        return [
            "trailCounts": trailCounts,
            "trailOrigins": trailOrigins,
            "headPositions": headPositions,
            "budgetTrailCounts": budgetTrailCounts,
            "depthDetails": runtime.diagnostics.compactMap {
                $0.layerID == 21 && $0.kind == .childSystemsUnsupported ? $0.detail : nil
            },
            "staticDetails": runtime.diagnostics.compactMap {
                $0.layerID == 22 && $0.kind == .childSystemsUnsupported ? $0.detail : nil
            },
            "budgetDetails": runtime.diagnostics.compactMap {
                $0.layerID == 23 && $0.kind == .simulationLimitation ? $0.detail : nil
            },
            "nestedUnsupportedLayers": runtime.diagnostics.compactMap {
                $0.kind == .childSystemsUnsupported && $0.layerID != 21 && $0.layerID != 22
                    ? $0.layerID : nil
            },
        ]
    }

    private static func realNestedMatrix(
        evidencePath: String,
        cachePath: String
    ) throws -> [String: Any] {
        let cache = URL(fileURLWithPath: cachePath, isDirectory: true)
        let descriptor = try renderDescriptor(evidencePath: evidencePath)
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: cache,
            device: device
        )
        for _ in 0..<4 { _ = runtime.advance(by: 1) }
        let batches = runtime.advance(by: 1.0 / 60.0)
        var headCount = 0
        var trailCount = 0
        var trailBatchCount = 0
        for batch in batches {
            if batch.particlePath.hasSuffix("matrix_code_copy1.json") {
                headCount += batch.instances.count
            }
            if batch.particlePath.hasSuffix("matrix_trail_copy1.json") {
                trailCount += batch.instances.count
                trailBatchCount += 1
            }
        }
        let staticRejections = runtime.diagnostics.filter {
            $0.kind == .childSystemsUnsupported
                && ($0.detail ?? "").contains("matrix_code_copy1.json")
        }
        return [
            "headCount": headCount,
            "trailCount": trailCount,
            "trailBatchCount": trailBatchCount,
            "staticRejections": staticRejections.count,
            "activeLayerIDs": runtime.activeLayerIDs,
            "nestedBudgetDetails": runtime.diagnostics.compactMap { value in
                (value.detail ?? "").contains("nestedAggregateSystemBudget")
                    ? (value.detail ?? "") : nil
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

    private static func realStaticOriginSample(
        evidencePath: String,
        cachePath: String
    ) throws -> [String: Any] {
        let cache = URL(fileURLWithPath: cachePath, isDirectory: true)
        let descriptor = try renderDescriptor(evidencePath: evidencePath)
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
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

    private static func stockSynthetic(bundlePath: String) throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-particle-stock-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeParticle(
            "particles/stock.json",
            material: "materials/stock.json",
            children: [[
                "name": "particles/repeat-child.json",
                "type": "static",
            ]],
            under: directory
        )
        try writeParticle(
            "particles/repeat-child.json",
            material: "materials/repeat.json",
            under: directory
        )
        try writeParticle(
            "particles/wide.json",
            material: "materials/wide.json",
            under: directory
        )

        let descriptor = SceneRenderDescriptor(
            layers: [
                layer(21, "particles/stock.json"),
                layer(22, "particles/wide.json"),
            ],
            renderOrderLayerIDs: [21, 22],
            materialPasses: [
                .init(
                    materialPath: "materials/stock.json",
                    shaderPath: "genericparticle",
                    texturePaths: ["particle/debris/debris1.tex"],
                    blending: "translucent"
                ),
                .init(
                    materialPath: "materials/repeat.json",
                    shaderPath: "genericparticle",
                    texturePaths: ["particle/nature/leaves7"],
                    blending: "translucent"
                ),
                .init(
                    materialPath: "materials/wide.json",
                    shaderPath: "genericparticle",
                    texturePaths: ["particle/lightning/lightning3"],
                    blending: "translucent"
                ),
            ]
        )
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let bundleURL = URL(fileURLWithPath: bundlePath, isDirectory: true)
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: directory,
            device: device,
            stockTextureBundleURL: bundleURL
        )
        let batches = runtime.advance(by: 1.0 / 60.0)
        let root = batches.first { $0.particlePath == "particles/stock.json" }
        let child = batches.first {
            $0.particlePath == "particles/repeat-child.json"
        }
        let wide = batches.first { $0.particlePath == "particles/wide.json" }
        let refractionSampling: [String: Any]
        if let resolver = SceneStockTextureResolver(bundleRoot: bundleURL),
           let colorURL = resolver.textureURL(for: "particle/misc/wave"),
           let normalURL = resolver.textureURL(for: "particle/normal_splash"),
           let loaded = SceneParticleRefractionTextureLoader.load(
               colorSource: .file(colorURL),
               declaration: SceneParticleRefractionDeclaration(
                   normalTextureSource: .file(normalURL),
                   amount: 1,
                   overbright: 1
               ),
               textureLoader: SceneTextureLoader(),
               device: device
           ) {
            refractionSampling = [
                "color": sampling(loaded.colorSampling),
                "normal": loaded.binding.resolvedNormalArguments().map {
                    sampling($0.sampling)
                } ?? [:],
            ]
        } else {
            refractionSampling = [:]
        }
        return [
            "activeLayerIDs": runtime.activeLayerIDs,
            "textureWidth": root?.texture.width ?? 0,
            "textureHeight": root?.texture.height ?? 0,
            "rootSampling": root.map { sampling($0.colorSampling) } ?? [:],
            "childTextureWidth": child?.texture.width ?? 0,
            "childFrameAspects": child?.instances.first.map {
                [$0.frame0B.z, $0.frame0B.w]
            } ?? [],
            "childSampling": child.map { sampling($0.colorSampling) } ?? [:],
            "wideFrameAspects": wide?.instances.first.map {
                [$0.frame0B.z, $0.frame0B.w]
            } ?? [],
            "refractionSampling": refractionSampling,
            "diagnosticKinds": runtime.diagnostics.map(\.kind.rawValue),
        ]
    }

    private static func syntheticRopeTrail() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-rope-trail-runtime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func writeMalformedRendererParticle(_ path: String, renderer: Any) throws {
            try writeJSON([
                "material": "materials/shared.json",
                "maxcount": 100,
                "emitter": [["name": "sphererandom", "rate": 1]],
                "initializer": [
                    ["name": "lifetimerandom", "min": 1, "max": 1],
                    ["name": "sizerandom", "min": 8, "max": 8],
                ],
                "renderer": renderer,
            ], to: directory.appendingPathComponent(path))
        }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writeAnimatedTEX(directory.appendingPathComponent("materials/animated.tex"))
        try writeParticle(
            "particles/rope-trail.json",
            material: "materials/shared.json",
            flags: 5,
            renderer: "ropetrail",
            rendererLength: 0.5,
            velocityX: 100,
            startTime: 1,
            moves: true,
            rate: 0,
            instantaneous: 1,
            under: directory
        )
        try writeParticle(
            "particles/rope-trail-missing-length.json",
            material: "materials/shared.json",
            renderer: "ropetrail",
            velocityX: 100,
            moves: true,
            under: directory
        )
        try writeParticle(
            "particles/rope-trail-animated.json",
            material: "materials/animated.json",
            renderer: "ropetrail",
            rendererLength: 0.5,
            velocityX: 100,
            moves: true,
            under: directory
        )
        try writeParticle(
            "particles/rope-trail-mixed-renderers.json",
            material: "materials/shared.json",
            renderer: "ropetrail",
            rendererLength: 0.5,
            additionalRenderers: [["name": "sprite", "flags": 0]],
            velocityX: 100,
            moves: true,
            under: directory
        )
        try writeParticle(
            "particles/rope-trail-malformed-renderers.json",
            material: "materials/shared.json",
            renderer: "ropetrail",
            rendererLength: 0.5,
            additionalRenderers: [NSNull()],
            velocityX: 100,
            moves: true,
            under: directory
        )
        try writeMalformedRendererParticle(
            "particles/rope-trail-object-renderer.json",
            renderer: ["name": "ropetrail", "length": 0.5]
        )
        try writeMalformedRendererParticle(
            "particles/rope-trail-only-malformed-renderer.json",
            renderer: [NSNull()]
        )
        try writeMalformedRendererParticle(
            "particles/rope-trail-empty-renderer.json",
            renderer: []
        )
        let descriptor = SceneRenderDescriptor(
            layers: [
                layer(31, "particles/rope-trail.json"),
                layer(32, "particles/rope-trail-missing-length.json"),
                layer(33, "particles/rope-trail-animated.json"),
                layer(34, "particles/rope-trail-mixed-renderers.json"),
                layer(35, "particles/rope-trail-malformed-renderers.json"),
                layer(36, "particles/rope-trail-object-renderer.json"),
                layer(37, "particles/rope-trail-only-malformed-renderer.json"),
                layer(38, "particles/rope-trail-empty-renderer.json"),
            ],
            renderOrderLayerIDs: [31, 32, 33, 34, 35, 36, 37, 38],
            materialPasses: [
                .init(
                    materialPath: "materials/shared.json",
                    shaderPath: "genericparticle",
                    texturePaths: ["shared.png"],
                    blending: "additive"
                ),
                .init(
                    materialPath: "materials/animated.json",
                    shaderPath: "genericparticle",
                    texturePaths: ["animated.tex"],
                    blending: "additive"
                ),
            ]
        )
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        func makeRuntime() -> SceneParticleRuntime {
            SceneParticleRuntime(
                descriptor: descriptor,
                cacheDirectory: directory,
                device: device,
                staticWorldSpaceFrames: [
                    31: SceneParticleWorldSpaceFrame(
                        worldFrame: matrix_identity_float4x4
                    )!,
                ]
            )
        }
        let coarseRuntime = makeRuntime()
        let fineRuntime = makeRuntime()
        let prewarmedBatch = coarseRuntime.advance(by: 0).first {
            $0.layerID == 31
        }
        _ = fineRuntime.advance(by: 0)
        let coarseBatch = coarseRuntime.advance(by: 0.5).first {
            $0.layerID == 31
        }
        var fineBatch: SceneParticleDrawBatch?
        for _ in 0..<30 {
            fineBatch = fineRuntime.advance(by: 1.0 / 60.0).first {
                $0.layerID == 31
            }
        }
        let diagnosticDetails = coarseRuntime.diagnostics.map {
            "\($0.kind.rawValue):\($0.layerID ?? -1):\($0.detail ?? "")"
        }
        return [
            "activeLayerIDs": coarseRuntime.activeLayerIDs,
            "prewarmedInstanceCount": prewarmedBatch?.instances.count ?? -1,
            "prewarmedAllSegmentsMoveForward": prewarmedBatch?.instances.allSatisfy {
                $0.velocityAndTrail.x > 0
                    && abs($0.velocityAndTrail.y) < 0.0001
                    && $0.velocityAndTrail.w > 0
            } ?? false,
            "coarseSignature": ropeTrailSignature(coarseBatch),
            "fineSignature": ropeTrailSignature(fineBatch),
            "bufferMatches": coarseBatch?.instanceBuffer.count
                == coarseBatch?.instances.count,
            "usesPerspective": coarseBatch?.usesPerspective ?? false,
            "orientationScreen": coarseBatch?.orientation == .screen,
            "mixedRendererLoaded": coarseRuntime.activeLayerIDs.contains(34),
            "malformedRendererLoaded": coarseRuntime.activeLayerIDs.contains(35),
            "objectRendererLoaded": coarseRuntime.activeLayerIDs.contains(36),
            "onlyMalformedRendererLoaded": coarseRuntime.activeLayerIDs.contains(37),
            "emptyRendererLoaded": coarseRuntime.activeLayerIDs.contains(38),
            "diagnosticDetails": diagnosticDetails,
            "missingSpriteRenderer": coarseRuntime.diagnostics.contains {
                $0.kind == .missingSpriteRenderer
            },
        ]
    }

    private static func ropeTrailSignature(
        _ batch: SceneParticleDrawBatch?
    ) -> [Float] {
        batch?.instances.flatMap {
            [
                $0.positionAndSize.x,
                $0.positionAndSize.y,
                $0.velocityAndTrail.x,
                $0.velocityAndTrail.y,
                $0.velocityAndTrail.w,
                $0.frame0B.z,
                $0.frame0B.w,
                $0.rotationAndAlpha.w,
            ]
        } ?? []
    }

    private static func syntheticDynamicControlPoint() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-particle-dynamic-cp-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writeParticle(
            "particles/control-point.json",
            material: "materials/shared.json",
            lifetime: 10,
            rate: 1,
            emitterControlPoint: 1,
            controlPointOffset: [1, 1, 1],
            under: directory
        )
        let descriptor = SceneRenderDescriptor(
            layers: [layer(
                90,
                "particles/control-point.json",
                controlPoint: SIMD3(2, 3, 4)
            )],
            renderOrderLayerIDs: [90],
            materialPasses: [.init(
                materialPath: "materials/shared.json",
                shaderPath: "genericparticle",
                texturePaths: ["shared.png"],
                blending: "additive"
            )]
        )
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: directory,
            device: device
        )
        let target = SceneDynamicTarget.particle(layerID: 90, field: .controlPoint(1))
        let definition = SceneDynamicTargetDefinition(
            target: target,
            valueType: .vector3,
            authoredValue: .vector3(2, 3, 4)
        )
        let resolver = SceneDynamicSnapshotResolver()
        func snapshot(_ value: SceneDynamicValue, frame: UInt64) -> SceneDynamicSnapshot {
            resolver.resolve(
                frameIndex: frame,
                generation: frame,
                definitions: [definition],
                timelineValues: [target: value]
            ).snapshot
        }
        _ = runtime.advance(
            by: 1,
            dynamicValues: snapshot(.vector3(10, 20, 30), frame: 1)
        )
        _ = runtime.advance(
            by: 1,
            dynamicValues: snapshot(.vector3(-5, 6, 7), frame: 2)
        )
        let fallback = runtime.advance(by: 1)
        return [
            "positions": fallback.first?.instances.map {
                [$0.positionAndSize.x, $0.positionAndSize.y, $0.positionAndSize.z]
            } ?? [],
            "activeLayerIDs": runtime.activeLayerIDs,
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
            "particles/world-dynamic.json", material: "materials/shared.json",
            flags: 1, under: directory
        )
        try writeParticle(
            "particles/renderer-world.json", material: "materials/shared.json",
            rendererFlags: 1, under: directory
        )
        try writeParticle(
            "particles/movement-world.json", material: "materials/shared.json",
            moves: true, movementFlags: 1, under: directory
        )
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
            "particles/child.json", material: "materials/normal-cull.json",
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
                ["name": "particles/custom-shader.json", "type": "static"],
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
        try writeParticle(
            "particles/control-point-copy-root.json", material: "materials/shared.json",
            emitterControlPoint: 1, controlPointOffset: [0, 0, 0],
            children: [
                ["name": "particles/raw-copy-child.json", "type": "static"],
                ["name": "particles/adjusted-copy-child.json", "type": "static"],
                ["name": "particles/malformed-copy-child.json", "type": "static"],
                ["name": "particles/raw-copy-child.json", "type": "eventspawn"],
            ], under: directory
        )
        for (path, flags) in [
            ("particles/raw-copy-child.json", 4),
            ("particles/adjusted-copy-child.json", 0),
        ] {
            try writeJSON([
                "material": "materials/shared.json", "maxcount": 10,
                "emitter": [[
                    "name": "sphererandom", "rate": 0, "instantaneous": 1,
                    "controlpoint": 1, "distancemin": 0, "distancemax": 0,
                ]],
                "initializer": [["name": "lifetimerandom", "min": 10, "max": 10]],
                "renderer": [["name": "sprite"]],
                "controlpoint": [[
                    "id": 1, "flags": flags, "offset": [0, 0, 0],
                    "parentcontrolpoint": 1,
                ]],
            ], to: directory.appendingPathComponent(path))
        }
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 10,
            "emitter": [["name": "sphererandom", "rate": 0, "instantaneous": 1]],
            "initializer": [["name": "lifetimerandom", "min": 10, "max": 10]],
            "renderer": [["name": "sprite"]],
            "controlpoint": [["id": 1, "flags": 4, "offset": [0, 0, 0]]],
        ], to: directory.appendingPathComponent("particles/malformed-copy-child.json"))
        }
        try writeParticle("particles/drop.json", material: "materials/drop.json", under: directory)
        try writeParticle("particles/halo.json", material: "materials/halo.json", under: directory)
        try writeParticle("particles/unknown.json", material: "materials/unknown.json", under: directory)
        try writeParticle(
            "particles/custom-shader.json", material: "materials/custom-shader.json",
            under: directory
        )
        try writeParticle(
            "particles/normal-cull.json", material: "materials/normal-cull.json",
            under: directory
        )

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
                layer(10, "particles/trail.json", particleAlpha: 0),
                layer(11, "particles/trail.json", particleAlpha: 0, alphaHasScript: true),
                layer(12, "particles/world-dynamic.json"),
                layer(13, "particles/renderer-world.json"),
                layer(14, "particles/movement-world.json"),
                layer(15, "particles/custom-shader.json"),
                layer(16, "particles/normal-cull.json"),
                layer(
                    17, "particles/control-point-copy-root.json",
                    controlPoint: SIMD3(22, 0, 0)
                ),
                layer(
                    18, "particles/control-point-copy-root.json",
                    controlPoint: SIMD3(22, 0, 0), controlPointHasAnimation: true
                ),
            ],
            renderOrderLayerIDs: Array(1 ... 18),
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
                .init(
                    materialPath: "materials/custom-shader.json",
                    shaderPath: "customparticle", texturePaths: ["shared.png"], blending: "additive"
                ),
                .init(
                    materialPath: "materials/normal-cull.json",
                    shaderPath: "genericparticle", texturePaths: ["shared.png"],
                    blending: "translucent", combos: ["REFRACT": 0], cullMode: "normal"
                ),
            ]
        )
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: directory,
            device: device,
            staticWorldSpaceFrames: [
                2: SceneParticleWorldSpaceFrame(worldFrame: matrix_identity_float4x4)!,
                14: SceneParticleWorldSpaceFrame(worldFrame: matrix_identity_float4x4)!,
            ]
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
            "childCullStates": batches.filter {
                $0.particlePath == "particles/child.json"
            }.map { $0.renderState.cullMode.rawValue },
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
            "rendererWorldOrientation": batches.first(where: { $0.layerID == 13 })?
                .orientation == .worldScreen,
            "movementWorldLayerLoaded": batches.contains { $0.layerID == 14 },
            "normalCullState": batches.first(where: { $0.layerID == 16 })?
                .renderState.cullMode.rawValue ?? "",
            "rawControlPointCopyPositions": batches.first {
                $0.particlePath == "particles/raw-copy-child.json"
            }?.instances.map {
                [$0.positionAndSize.x, $0.positionAndSize.y, $0.positionAndSize.z]
            } ?? [],
            "adjustedControlPointCopyLoaded": batches.contains {
                $0.particlePath == "particles/adjusted-copy-child.json"
            },
            "rawControlPointCopyBounded": runtime.diagnostics.contains {
                $0.detail == "particles/raw-copy-child.json:rawParentControlPointCopyBounded:mappings=1"
            },
            "rawControlPointCopyLayerIDs": batches.filter {
                $0.particlePath == "particles/raw-copy-child.json"
            }.map(\.layerID),
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
        visible: Bool = true,
        particleAlpha: Double? = nil,
        alphaHasScript: Bool = false,
        controlPoint: SIMD3<Double>? = nil,
        controlPointHasAnimation: Bool = false
    ) -> SceneRenderDescriptor.Layer {
        .init(
            id: id, name: nil, contentKind: "particle", particlePath: path,
            particleInstanceOverride: (particleAlpha != nil || controlPoint != nil) ?
                SceneParticleInstanceOverride(
                    id: nil,
                    alpha: particleAlpha.map { value in SceneParticleBoundValue(
                        value: .scalar(value),
                        userPropertyKey: "foreground",
                        hasScript: alphaHasScript,
                        hasAnimation: false
                    ) },
                    size: nil,
                    lifetime: nil,
                    rate: nil,
                    speed: nil,
                    count: nil,
                    brightness: nil,
                    color: nil,
                    normalizedColor: nil,
                    controlPoints: controlPoint.map { value in [
                        1: SceneParticleBoundValue(
                            value: .vector([value.x, value.y, value.z]),
                            userPropertyKey: nil,
                            hasScript: false,
                            hasAnimation: controlPointHasAnimation
                        )
                    ] } ?? [:],
                    controlPointAngles: [:]
                )
                : nil,
            parentID: nil, visible: visible, alpha: 1
        )
    }

    private static func writeParticle(
        _ path: String,
        material: String,
        flags: Int = 0,
        renderer: String = "sprite",
        rendererFlags: Int = 0,
        rendererLength: Double? = nil,
        rendererMinimumLength: Double? = nil,
        rendererMaximumLength: Double? = nil,
        additionalRenderers: [Any] = [],
        velocityX: Double? = nil,
        lifetime: Double = 10,
        startTime: Double? = nil,
        moves: Bool = false,
        movementFlags: Int = 0,
        rate: Double = 60,
        emitterDuration: Double? = nil,
        audioProcessingMode: Int? = nil,
        instantaneous: Int? = nil,
        emitterControlPoint: Int? = nil,
        controlPointOffset: [Double]? = nil,
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
        var rendererDefinition: [String: Any] = [
            "name": renderer,
            "flags": rendererFlags,
        ]
        if let rendererLength { rendererDefinition["length"] = rendererLength }
        if let rendererMinimumLength { rendererDefinition["minlength"] = rendererMinimumLength }
        if let rendererMaximumLength { rendererDefinition["maxlength"] = rendererMaximumLength }
        var emitter: [String: Any] = [
            "name": "sphererandom", "rate": rate, "distancemin": 0, "distancemax": 0,
        ]
        if let emitterDuration { emitter["duration"] = emitterDuration }
        if let audioProcessingMode { emitter["audioprocessingmode"] = audioProcessingMode }
        if let instantaneous { emitter["instantaneous"] = instantaneous }
        if let emitterControlPoint { emitter["controlpoint"] = emitterControlPoint }
        var definition: [String: Any] = [
            "material": material,
            "maxcount": 100,
            "flags": flags,
            "emitter": [emitter],
            "initializer": initializers,
            "renderer": ([rendererDefinition] as [Any]) + additionalRenderers,
            "children": children,
        ]
        if let startTime { definition["starttime"] = startTime }
        if let emitterControlPoint, let controlPointOffset {
            definition["controlpoint"] = [[
                "id": emitterControlPoint,
                "offset": controlPointOffset,
            ]]
        }
        if moves {
            definition["operator"] = [[
                "name": "movement",
                "flags": movementFlags,
            ]]
        }
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

    private static func writeAnimatedTEX(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        var data = Data("TEXV0005\0TEXI0001\0".utf8)
        appendUInt32(0, to: &data)
        appendUInt32(4, to: &data)
        appendUInt32(2, to: &data)
        appendUInt32(2, to: &data)
        appendUInt32(2, to: &data)
        appendUInt32(2, to: &data)
        appendUInt32(0, to: &data)
        data.append(Data("TEXB0002\0".utf8))
        appendUInt32(1, to: &data)
        appendUInt32(1, to: &data)
        appendUInt32(2, to: &data)
        appendUInt32(2, to: &data)
        appendUInt32(0, to: &data)
        appendUInt32(0, to: &data)
        appendUInt32(16, to: &data)
        data.append(Data(repeating: 255, count: 16))
        data.append(Data("TEXS0002\0".utf8))
        appendUInt32(2, to: &data)
        for _ in 0..<2 {
            appendUInt32(0, to: &data)
            appendFloat32(0.1, to: &data)
            for value: Float in [0, 0, 2, 0, 0, 2] {
                appendFloat32(value, to: &data)
            }
        }
        try data.write(to: url)
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private static func appendFloat32(_ value: Float, to data: inout Data) {
        var bits = value.bitPattern.littleEndian
        withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
    }

    private static func scalar(_ value: SceneParticleBoundValue?) -> Double {
        value?.value?.scalarValue ?? -1
    }

    private static func sampling(
        _ value: SceneParticleTextureSampling
    ) -> [String: Any] {
        [
            "filter": value.filter.rawValue,
            "address": value.addressMode.rawValue,
            "clampBorderFallback": value.usesClampBorderFallback,
        ]
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
        if not REAL_SAMPLE_EVIDENCE.is_file() or not REAL_SAMPLE_CACHE.is_dir():
            self.skipTest("isolated 3742133044 runtime evidence is unavailable")
        result = self.run_harness(
            "real", str(REAL_SAMPLE_EVIDENCE), str(REAL_SAMPLE_CACHE)
        )
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
        self.assertEqual(
            result["activeLayerIDs"], [2, 3, 4, 6, 7, 9, 11, 13, 14, 16, 17, 18]
        )
        self.assertEqual(
            result["batchLayerIDs"],
            [2, 3, 4, 4, 6, 7, 9, 9, 9, 9, 11, 13, 14, 16, 17, 17, 18],
        )
        self.assertGreater(result["activeParticleCount"], 0)
        self.assertGreater(result["childInstanceCount"], 0)
        self.assertTrue(result["childCullStates"])
        self.assertEqual(set(result["childCullStates"]), {"back"})
        self.assertEqual(result["staticChildInstanceCount"], 3)
        self.assertEqual(result["staticChildOrigins"], [[0, 0, 0], [0, 0, 0], [1, 2, 3]])
        # 内置纹理尺寸已对齐官方 .tex 的 imageWidth/imageHeight，非方形纹理不再按方形近似。
        self.assertEqual(result["batchTextureSizes"]["6"], [32, 128])
        self.assertEqual(result["batchTextureSizes"]["7"], [64, 64])
        self.assertAlmostEqual(result["trailStretch"], 5)
        self.assertEqual(result["trailVelocity"], [100, 0, 0])
        self.assertTrue(result["rendererWorldOrientation"])
        self.assertTrue(result["movementWorldLayerLoaded"])
        self.assertEqual(result["normalCullState"], "back")
        self.assertEqual(result["rawControlPointCopyPositions"], [[22, 0, 0]])
        self.assertFalse(result["adjustedControlPointCopyLoaded"])
        self.assertTrue(result["rawControlPointCopyBounded"])
        self.assertEqual(result["rawControlPointCopyLayerIDs"], [17])
        self.assertFalse(result["hiddenMentioned"])
        self.assertNotIn(10, result["activeLayerIDs"])
        self.assertIn(11, result["activeLayerIDs"])
        diagnostics = result["diagnostics"]
        kinds = {value["kind"] for value in diagnostics}
        self.assertIn("missingTextureReference", kinds)
        self.assertIn("worldSpaceUnsupported", kinds)
        self.assertNotIn("trailRendererUnsupported", kinds)
        self.assertNotIn("missingSpriteRenderer", kinds)
        self.assertIn("childSystemsUnsupported", kinds)
        self.assertIn("unsupportedShader", kinds)
        self.assertNotIn(15, result["activeLayerIDs"])
        self.assertNotIn(15, result["batchLayerIDs"])
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
        self.assertIn(
            "particles/custom-shader.json:unsupportedShader",
            result["staticChildUnsupportedDetails"],
        )
        self.assertIn(
            "particles/adjusted-copy-child.json:rawParentControlPointCopyMalformed",
            [value["detail"] for value in diagnostics if value["detail"] is not None],
        )
        details = [value["detail"] for value in diagnostics if value["detail"] is not None]
        self.assertIn(
            "particles/malformed-copy-child.json:rawParentControlPointCopyMalformed",
            details,
        )
        self.assertIn(
            "particles/raw-copy-child.json:rawParentControlPointCopyOutsideStaticDepthOne",
            details,
        )
        self.assertIn(
            "particles/raw-copy-child.json:rawParentControlPointSourceDynamic",
            details,
        )
        self.assertIn("builtInTextureUnavailable", kinds)

    def test_runtime_consumes_each_surface_snapshot_then_restores_authored_fallback(self) -> None:
        result = self.run_harness("dynamic-control-point-synthetic")
        self.assertEqual(result["activeLayerIDs"], [90])
        self.assertEqual(
            result["positions"],
            [[11, 21, 31], [-4, 7, 8], [3, 4, 5]],
        )

    def test_rope_trail_runtime_builds_multisegment_batches_and_fails_closed(self) -> None:
        result = self.run_harness("rope-trail-synthetic")
        self.assertEqual(result["activeLayerIDs"], [31])
        self.assertGreaterEqual(result["prewarmedInstanceCount"], 4)
        self.assertTrue(result["prewarmedAllSegmentsMoveForward"])
        coarse = result["coarseSignature"]
        fine = result["fineSignature"]
        self.assertEqual(len(coarse), len(fine))
        self.assertGreaterEqual(len(coarse), 4 * 8)
        for coarse_value, fine_value in zip(coarse, fine):
            self.assertAlmostEqual(coarse_value, fine_value, places=5)
        self.assertTrue(result["bufferMatches"])
        self.assertTrue(result["usesPerspective"])
        self.assertTrue(result["orientationScreen"])
        self.assertFalse(result["mixedRendererLoaded"])
        self.assertFalse(result["malformedRendererLoaded"])
        self.assertFalse(result["objectRendererLoaded"])
        self.assertFalse(result["onlyMalformedRendererLoaded"])
        self.assertTrue(result["missingSpriteRenderer"])
        self.assertIn(
            "trailRendererUnsupported:32:ropetrail:unsupportedProfile",
            result["diagnosticDetails"],
        )
        self.assertIn(
            "trailRendererUnsupported:33:ropetrail:animatedTexture",
            result["diagnosticDetails"],
        )
        self.assertIn(
            "trailRendererUnsupported:34:ropetrail:unsupportedProfile",
            result["diagnosticDetails"],
        )
        self.assertIn(
            "trailRendererUnsupported:35:ropetrail:unsupportedProfile",
            result["diagnosticDetails"],
        )
        self.assertIn(
            "missingSpriteRenderer:36:",
            result["diagnosticDetails"],
        )
        self.assertIn(
            "missingSpriteRenderer:37:",
            result["diagnosticDetails"],
        )
        self.assertFalse(result["emptyRendererLoaded"])
        self.assertIn(
            "missingSpriteRenderer:38:",
            result["diagnosticDetails"],
        )

    def test_stock_tex_reference_loads_through_particle_runtime(self) -> None:
        bundle = REPOSITORY_ROOT / "MyWallpaperX/Resources/SceneStockAssets.bundle"
        result = self.run_harness("stock-synthetic", str(bundle))
        self.assertEqual(result["activeLayerIDs"], [21, 22])
        # debris1.tex 是官方 8 帧 128×128 spritesheet，整张上传为 1024×128 纹理。
        self.assertEqual(result["textureWidth"], 1024)
        self.assertEqual(result["textureHeight"], 128)
        self.assertEqual(result["rootSampling"], {
            "filter": "linear",
            "address": "clampToEdge",
            "clampBorderFallback": False,
        })
        self.assertEqual(result["childTextureWidth"], 512)
        for aspect in result["childFrameAspects"]:
            self.assertAlmostEqual(aspect, 85.334 / 102.4, places=5)
        self.assertEqual(result["wideFrameAspects"], [2, 2])
        self.assertEqual(result["childSampling"], {
            "filter": "linear",
            "address": "repeatWrap",
            "clampBorderFallback": False,
        })
        self.assertEqual(result["refractionSampling"], {
            "color": {
                "filter": "linear",
                "address": "repeatWrap",
                "clampBorderFallback": False,
            },
            "normal": {
                "filter": "linear",
                "address": "clampToEdge",
                "clampBorderFallback": False,
            },
        })
        self.assertEqual(result["diagnosticKinds"], [])

    def test_continuous_children_follow_finish_and_obey_aggregate_budget(self) -> None:
        result = self.run_harness("eventfollow-synthetic")
        self.assertEqual(result["childCounts"], [0, 1, 2, 0, 0, 0])
        self.assertEqual(result["childPositions"], [2, 2])
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

    def test_rate_only_event_children_stop_after_bounded_window(self) -> None:
        result = self.run_harness("eventfollow-synthetic")
        counts = result["windowCounts"]
        # rate-only eventspawn child(无 duration)只允许一个有界 burst:
        # 发射窗口 = 自身粒子最大寿命,粒子清空后系统回收,计数必须归零并保持。
        self.assertGreaterEqual(max(counts), 1)
        self.assertEqual(counts[-2:], [0, 0])
        self.assertLess(counts.index(max(counts)), len(counts) - 2)

    def test_synthetic_nested_children_follow_depth_limit_and_budget(self) -> None:
        result = self.run_harness("nested-synthetic")
        self.assertEqual(result["trailCounts"], [0, 1, 2, 3, 0, 0])
        heads = result["headPositions"]
        origins = result["trailOrigins"]
        self.assertEqual(len(heads), 4)
        self.assertEqual(len(origins), 3)
        for index, origin in enumerate(origins):
            self.assertAlmostEqual(origin, heads[index + 1], delta=0.01)
        for index in range(1, len(heads)):
            self.assertAlmostEqual(heads[index] - heads[index - 1], 1.0, delta=0.01)
        self.assertGreater(heads[0], 40)
        self.assertIn(
            "particles/depth-three.json:nestedDepthUnsupported", result["depthDetails"]
        )
        self.assertIn(
            "particles/static-leaf.json:nestedStaticChildUnsupported",
            result["staticDetails"],
        )
        self.assertIn(
            "nestedAggregateSystemBudget:depth=2:systems=64:particleCapacity=65536",
            result["budgetDetails"],
        )
        self.assertEqual(result["budgetTrailCounts"][0], 0)
        self.assertEqual(result["budgetTrailCounts"][1], 64)
        self.assertEqual(result["nestedUnsupportedLayers"], [])

    def test_real_2974757317_executes_nested_matrix_rain(self) -> None:
        if not NESTED_SAMPLE_EVIDENCE.is_file() or not NESTED_SAMPLE_CACHE.is_dir():
            self.skipTest("isolated 2974757317 runtime evidence is unavailable")
        result = self.run_harness(
            "nested-real", str(NESTED_SAMPLE_EVIDENCE), str(NESTED_SAMPLE_CACHE)
        )
        self.assertEqual(result["headCount"], 43)
        self.assertGreaterEqual(result["trailCount"], 43)
        self.assertEqual(result["trailBatchCount"], 1)
        self.assertEqual(result["staticRejections"], 0)
        self.assertEqual(result["nestedBudgetDetails"], [])

    def test_real_2938612768_keeps_author_disabled_matrix_off(self) -> None:
        cache = NESTED_AUTHOR_OFF_SAMPLE_CACHE
        if not NESTED_AUTHOR_OFF_SAMPLE_EVIDENCE.is_file() or not cache.is_dir():
            self.skipTest("isolated 2938612768 runtime evidence is unavailable")
        result = self.run_harness(
            "nested-real", str(NESTED_AUTHOR_OFF_SAMPLE_EVIDENCE), str(cache)
        )
        self.assertEqual(result["headCount"], 0)
        self.assertEqual(result["trailCount"], 0)
        self.assertNotIn(85705, result["activeLayerIDs"])
        self.assertEqual(result["staticRejections"], 0)

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
        if not STATIC_ORIGIN_SAMPLE_EVIDENCE.is_file() or not STATIC_ORIGIN_SAMPLE_CACHE.is_dir():
            self.skipTest("isolated 3088601835 runtime evidence is unavailable")
        result = self.run_harness(
            "static-origin-real",
            str(STATIC_ORIGIN_SAMPLE_EVIDENCE),
            str(STATIC_ORIGIN_SAMPLE_CACHE),
        )
        self.assertEqual(result["childLayerIDs"], [513, 534])
        self.assertEqual(result["childInstanceCounts"], [1, 1])
        self.assertEqual(result["childTextureWidths"], [128, 128])
        self.assertEqual(result["unsupportedLayerIDs"], [])

    def test_real_3768903841_executes_strict_eventspawn_child(self) -> None:
        if not EVENTSPAWN_SAMPLE_EVIDENCE.is_file() or not EVENTSPAWN_SAMPLE_CACHE.is_dir():
            self.skipTest("isolated 3768903841 runtime evidence is unavailable")
        result = self.run_harness(
            "eventspawn-real",
            str(EVENTSPAWN_SAMPLE_EVIDENCE),
            str(EVENTSPAWN_SAMPLE_CACHE),
        )
        self.assertIn(264, result["activeLayerIDs"])
        self.assertGreater(result["childInstanceCount"], 0)
        self.assertEqual(result["childTextureWidth"], 128)
        self.assertFalse(result["layer264ChildUnsupported"])

    def test_real_2131872317_executes_eventdeath_firework_burst(self) -> None:
        if not EVENTDEATH_SAMPLE_EVIDENCE.is_file() or not EVENTDEATH_SAMPLE_CACHE.is_dir():
            self.skipTest("isolated 2131872317 runtime evidence is unavailable")
        result = self.run_harness(
            "eventdeath-real",
            str(EVENTDEATH_SAMPLE_EVIDENCE),
            str(EVENTDEATH_SAMPLE_CACHE),
        )
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

    def test_real_3768229922_loads_strict_refraction_without_duplicate_upload(self) -> None:
        if not REFRACTION_SAMPLE_EVIDENCE.is_file() or not REFRACTION_SAMPLE_CACHE.is_dir():
            self.skipTest("isolated 3768229922 runtime evidence is unavailable")
        result = self.run_harness(
            "refraction-real",
            str(REFRACTION_SAMPLE_EVIDENCE),
            str(REFRACTION_SAMPLE_CACHE),
        )
        self.assertEqual(
            sorted(result["refractionLayerIDs"]), [1103, 1144], result
        )
        self.assertTrue(result["sameTextureIdentity"])
        self.assertEqual(result["staticCandidateLayerIDs"], [])
        self.assertEqual(result["amounts"], [0.5, 0.5])
        self.assertNotIn("refractionUnsupported", result["diagnostics"])

    def test_real_2131872317_executes_refractive_eventdeath_child(self) -> None:
        if not EVENTDEATH_SAMPLE_EVIDENCE.is_file() or not EVENTDEATH_SAMPLE_CACHE.is_dir():
            self.skipTest("isolated 2131872317 runtime evidence is unavailable")
        result = self.run_harness(
            "refraction-child-real",
            str(EVENTDEATH_SAMPLE_EVIDENCE),
            str(EVENTDEATH_SAMPLE_CACHE),
        )
        self.assertGreater(result["firstFrame"], 0)
        self.assertIn(
            "particles/presets/fireworkshitdistort.json",
            result["paths"],
        )
        self.assertIn(
            "particles/presets/fireworkshitdistort.json",
            result["candidatePaths"],
        )
        self.assertEqual(result["refractionUnsupported"], [])

    def test_real_3770444459_sustains_refractive_water_impacts(self) -> None:
        if (
            not WATER_IMPACT_SAMPLE_EVIDENCE.is_file()
            or not WATER_IMPACT_SAMPLE_CACHE.is_dir()
        ):
            self.skipTest("isolated 3770444459 runtime evidence is unavailable")
        result = self.run_harness(
            "water-impact-real",
            str(WATER_IMPACT_SAMPLE_EVIDENCE),
            str(WATER_IMPACT_SAMPLE_CACHE),
        )
        for layer_id in ("239", "245", "248"):
            self.assertGreater(result["activeFrames"][layer_id], 0, result)
            self.assertGreater(result["maximumInstances"][layer_id], 0, result)
        self.assertEqual(result["refractionUnsupported"], [])
        self.assertIn(48, result["candidateLayers"], result)
        for layer_id in (239, 245, 248):
            self.assertIn(layer_id, result["legacyLayers"], result)


if __name__ == "__main__":
    unittest.main()
