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
    SOURCE_ROOT / "Systems/Properties/SceneDynamicLayerValues.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/ScenePerformanceCounterHub.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/SceneGPUCensus.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Media/SceneAudioSpectrum.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneMaterialRenderState.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureSampling.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Assets/SceneResourceIndex.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Assets/SceneResourceView.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Assets/SceneStockTextureResolver.swift",
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
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleDefinitionParser+InstanceOverride.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleWorldSpacePlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleTextureSource.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRefractionPlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRefractionBinding.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRefractionTextureLoader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleBuiltInTextureRegistry.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleAssetGraph.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticlePipelineRenderStateCompiler.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleBoids.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulationSupport.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulationDiagnostic.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleControlPointForce.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulator+ControlPointForce.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulator+ReduceMovement.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulator+CollisionPlane.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulator+PositionAroundControlPoint.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulator+Boids.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulator+AudioResponse.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulator+Vortex.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleCapVelocity.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulator+CapVelocity.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleUnaryOperatorPlans.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticlePeriodicEmission.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleLayerImageEmissionMap.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleOscillationCache.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleStepSnapshotRecorder.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulator.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulator+Initializer.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulator+Random.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulator+InstanceOverride.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleInstanceOverride+Dynamic.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleChildLifecycle.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleChildTemplateSupport.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleTrailRenderPlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRopePlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRopeTrailPlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleRenderSupport.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleMetalInstanceBuffer.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleShaderSource.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleSamplerStateSet.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleMetalPipeline.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleDepthTargetPool.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneFramebufferSnapshot.swift",
    SOURCE_ROOT / "Format/SceneTexDataReader.swift",
    SOURCE_ROOT / "Format/SceneTexContainer.swift",
    SOURCE_ROOT / "Format/SceneBCTextureDecoder.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneImageTextureUploader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneCompressedTextureUploader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureMipUploader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureLoader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureUVTransform.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureCandidate.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureLoader+Candidate.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneSourceUpdateTransaction.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Animation/SceneSpriteAnimation.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/SceneLayerVisibility.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleChildGraphExpansion.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleChildRuntimeModels.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleChildInstanceBuilder.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleChildRuntime.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRuntimeModels.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleLayerRuntime.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRuntime.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRuntime+Support.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticlePlaybackState.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneDynamicSnapshot.swift",
]


HARNESS_SOURCE = r'''
import CoreGraphics
import Foundation
import ImageIO
import Metal
import simd

struct SceneLayerDisplayScriptOwnership: Codable {
    let visible: Bool
    let alpha: Bool
    var fields: [String] {
        (visible ? ["visible"] : []) + (alpha ? ["alpha"] : [])
    }
    var isEmpty: Bool { !visible && !alpha }
}

struct SceneRenderDescriptor: Codable {
    struct ColorTargetFormat {
        let metalPixelFormat: MTLPixelFormat = .bgra8Unorm
    }
    var colorTargetFormat: ColorTargetFormat { .init() }

    struct Layer: Codable {
        let id: Int
        let name: String?
        let contentKind: String
        let particlePath: String?
        let particleInstanceOverride: SceneParticleInstanceOverride?
        let parentID: Int?
        let visible: Bool?
        var displayScriptOwnership: SceneLayerDisplayScriptOwnership? = nil
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

    var staticParticleWorldSpaceChains: [Int: Set<Int>] {
        Dictionary(uniqueKeysWithValues: layers.map { ($0.id, [$0.id]) })
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
    var dependencyBlendMode: UInt32
    var usesDependencyBlend: UInt32
    var cursorUV: SIMD2<Float>
    var sourceSampling: SIMD2<Float>
    var tint: SIMD4<Float>
    var textureFrame0: SIMD4<Float>
    var textureFrame1: SIMD4<Float>
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
        case "delayed-children":
            try printJSON(delayedChildren())
        case "delayed-child-edges":
            try printJSON(delayedChildren(edges: true))
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
        case "worldspace-freeze":
            try printJSON(syntheticWorldSpaceFreeze())
        case "worldspace-gravity-frame":
            try printJSON(syntheticWorldSpaceGravityFrame())
        case "worldspace-pointer-emitter":
            try printJSON(syntheticWorldSpacePointerEmitter())
        case "audio-bounds-gate":
            try printJSON(syntheticAudioBoundsGate())
        case "worldspace-rope-trail":
            try printJSON(syntheticWorldSpaceRopeTrail())
        case "worldspace-pointer-force":
            try printJSON(syntheticWorldSpacePointerForce())
        case "worldspace-pointer-positionaround":
            try printJSON(syntheticWorldSpacePointerPositionAround())
        case "pointer-demand-real":
            guard CommandLine.arguments.count == 7 else {
                throw HarnessError.missingMode
            }
            try printJSON(realPointerDemand(
                evidencePath: CommandLine.arguments[2],
                cachePath: CommandLine.arguments[3],
                layerID: Int(CommandLine.arguments[4]) ?? 0,
                pointer: SIMD3(
                    Double(CommandLine.arguments[5]) ?? 0,
                    Double(CommandLine.arguments[6]) ?? 0,
                    0
                )
            ))
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
        case "rope-synthetic":
            try printJSON(syntheticRope())
        case "dynamic-control-point-synthetic":
            try printJSON(syntheticDynamicControlPoint())
        case "child-float-safety":
            try printJSON(syntheticChildFloatSafety())
        case "child-instance-override-synthetic":
            try printJSON(syntheticChildInstanceOverride())
        case "layer-alpha-synthetic":
            try printJSON(syntheticLayerAlpha())
        case "dynamic-instance-override-synthetic":
            try printJSON(syntheticDynamicInstanceOverride())
        case "velocity-defaults-synthetic":
            try printJSON(syntheticVelocityDefaults())
        case "child-pointer-control-point-synthetic":
            try printJSON(syntheticChildPointerControlPoint())
        case "dynamic-control-point-angle-synthetic":
            try printJSON(syntheticDynamicControlPointAngle())
        case "batch-evidence-synthetic":
            try printJSON(syntheticBatchEvidence())
        case "lifecycle-synthetic":
            try printJSON(syntheticLifecycle())
        case "playback-delta-synthetic":
            try printJSON(playbackDeltaBounds())
        case "frame-transaction-synthetic":
            try printJSON(frameTransactionBounds())
        case "subframe-lifetime-synthetic":
            try printJSON(syntheticSubframeLifetime())
        case "subframe-child-lifecycle-synthetic":
            try printJSON(syntheticSubframeChildLifecycle())
        case "sprite-geometry-synthetic":
            try printJSON(syntheticSpriteGeometry())
        case "child-capacity-synthetic":
            try printJSON(syntheticChildCapacity())
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

    private static func syntheticVelocityDefaults() throws -> [String: Any] {
        func velocity(minimum: Any?, maximum: Any?) -> [Double] {
            var velocity: [String: Any] = ["name": "velocityrandom"]
            if let minimum { velocity["min"] = minimum }
            if let maximum { velocity["max"] = maximum }
            let definition = SceneParticleDefinitionParser().parse(root: [
                "material": "materials/unused.json",
                "maxcount": 1,
                "emitter": [[
                    "name": "sphererandom", "rate": 0, "instantaneous": 1,
                    "distancemin": 0, "distancemax": 0,
                ]],
                "initializer": [
                    ["name": "lifetimerandom", "min": 10, "max": 10],
                    velocity,
                ],
                "renderer": [["name": "sprite"]],
            ])
            var simulator = SceneParticleSimulator(definition: definition, seed: 7)
            simulator.advance(by: 1.0 / 60.0)
            guard let value = simulator.particles.first?.velocity else { return [] }
            return [value.x, value.y, value.z]
        }
        return [
            "maximumOnly": velocity(minimum: nil, maximum: [0, 100, 0]),
            "minimumOnly": velocity(minimum: [0, -100, 0], maximum: nil),
            "omitted": velocity(minimum: nil, maximum: nil),
        ]
    }


    private static func syntheticChildCapacity() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-child-capacity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        func particle(_ name: String, maximum: Int, burst: Int, lifetime: Double = 10,
                      rate: Double = 0, startTime: Double = 0, children: [[String: Any]] = []) throws {
            try writeJSON([
                "material": "materials/shared.json", "maxcount": maximum, "starttime": startTime,
                "emitter": [["name": "sphererandom", "rate": rate,
                    "instantaneous": burst, "distancemin": 0, "distancemax": 0]],
                "initializer": [["name": "lifetimerandom", "min": lifetime, "max": lifetime],
                    ["name": "sizerandom", "min": 4, "max": 4]],
                "renderer": [["name": "sprite"]], "children": children,
            ], to: directory.appendingPathComponent("particles/\(name).json"))
        }
        func child(_ name: String, _ trigger: String = "static") -> [String: Any] {
            ["name": "particles/\(name).json", "type": trigger]
        }
        try particle("dense", maximum: 20000, burst: 8500)
        try particle("warm", maximum: 20000, burst: 8500, startTime: 0.1)
        try particle("prewarm", maximum: 1, burst: 0, children: [child("warm")])
        try particle("large", maximum: 20000, burst: 20000)
        try particle("small", maximum: 5536, burst: 5536)
        try particle("short", maximum: 20000, burst: 8500, lifetime: 1.0 / 60.0)
        try particle("single", maximum: 1, burst: 0, children: [child("dense")])
        try particle("static", maximum: 1, burst: 0,
                     children: Array(repeating: child("large"), count: 65) + [child("small")])
        for trigger in ["eventspawn", "eventdeath", "eventfollow"] {
            try particle(trigger, maximum: 4, burst: 4,
                         lifetime: trigger == "eventdeath" ? 1.0 / 60.0 : 10,
                         children: [child("large", trigger)])
        }
        try particle("head", maximum: 4, burst: 4, children: [child("large", "eventspawn")])
        try particle("nested", maximum: 1, burst: 0,
                     children: [child("head"), child("large"), child("large"), child("large")])
        try particle("recycle", maximum: 16, burst: 4, rate: 60,
                     children: [child("short", "eventspawn")])
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let pass = SceneRenderDescriptor.MaterialPassDescriptor(
            materialPath: "materials/shared.json", shaderPath: "genericparticle",
            texturePaths: ["shared.png"], blending: "additive")
        func runtime(_ name: String) -> SceneParticleRuntime {
            SceneParticleRuntime(descriptor: SceneRenderDescriptor(
                layers: [layer(970, "particles/\(name).json")], renderOrderLayerIDs: [970],
                materialPasses: [pass]), cacheDirectory: directory, device: device)
        }
        func count(_ batches: [SceneParticleDrawBatch], path: String) -> Int {
            batches.filter { $0.particlePath == "particles/\(path).json" }
                .reduce(0) { $0 + $1.instances.count }
        }
        var output: [String: Any] = [:]
        for name in ["single", "prewarm", "static", "eventspawn", "eventdeath", "eventfollow", "nested"] {
            let value = runtime(name)
            var peak = 0
            for _ in 0..<4 {
                let batches = value.advance(by: 1.0 / 60.0)
                if name == "static" { output["smallPeer"] = count(batches, path: "small") }
                peak = max(peak, count(batches, path: name == "single" ? "dense" : (name == "prewarm" ? "warm" : "large"))
                    + (name == "static" ? count(batches, path: "small") : 0))
            }
            output[name] = peak
            output[name + "Diagnostics"] = value.diagnostics.compactMap {
                $0.kind == .simulationLimitation ? $0.detail : nil
            }
            let systems = value.frameSnapshot().layers.first?.child?.systems ?? []
            output[name + "Capacity"] = [1, 2].map { depth in
                systems.filter { $0.depth == depth }.reduce(0) { $0 + $1.simulator.maximumParticleCount }
            }
        }
        let retry = runtime("recycle")
        _ = retry.advance(by: 1.0 / 60.0)
        let before = retry.frameSnapshot()
        var firstCounts: [Int] = []
        var allocations: [[Int]] = []
        for _ in 0..<5 {
            firstCounts.append(count(retry.advance(by: 1.0 / 60.0), path: "short"))
            let systems = retry.frameSnapshot().layers.first!.child!.systems
            allocations.append([systems.count, systems.reduce(0) { $0 + $1.simulator.maximumParticleCount }])
        }
        output["recycleAllocations"] = allocations
        let firstState = retry.frameSnapshot().layers.first!.child!
        let firstIDs = firstState.systems.map(\.id)
        retry.restoreFrame(before)
        var replayCounts: [Int] = []
        for _ in 0..<5 { replayCounts.append(count(retry.advance(by: 1.0 / 60.0), path: "short")) }
        let replayState = retry.frameSnapshot().layers.first!.child!
        output["identityReplay"] = firstIDs == replayState.systems.map(\.id)
            && firstState.nextSeed == replayState.nextSeed
            && firstState.nextSystemID == replayState.nextSystemID
        output["recycle"] = firstCounts
        output["replay"] = replayCounts
        return output
    }

    private static func playbackDeltaBounds() -> [String: Double] {
        [
            "sixtyFPS": SceneParticlePlaybackState.boundedRealtimeSimulationDelta(1.0 / 60.0),
            "thirtyFPS": SceneParticlePlaybackState.boundedRealtimeSimulationDelta(1.0 / 30.0),
            "slowFrame": SceneParticlePlaybackState.boundedRealtimeSimulationDelta(0.25),
            "negative": SceneParticlePlaybackState.boundedRealtimeSimulationDelta(-1),
            "nonFinite": SceneParticlePlaybackState.boundedRealtimeSimulationDelta(.infinity),
        ]
    }

    private static func frameTransactionBounds() -> [String: Any] {
        let definition = SceneParticleDefinitionParser().parse(root: [
            "material": "materials/unused.json",
            "maxcount": 8,
            "emitter": [[
                "name": "sphererandom", "rate": 30,
                "distancemin": 0, "distancemax": 0,
            ]],
            "initializer": [
                ["name": "lifetimerandom", "min": 2, "max": 2],
                ["name": "velocityrandom", "min": "-1 2 0", "max": "1 3 0"],
            ],
            "renderer": [["name": "sprite"]],
        ])
        var retry = SceneParticleSimulator(definition: definition, seed: 17)
        retry.advance(by: 1.0 / 60.0)
        let snapshot = retry.frameSnapshot()
        retry.advance(by: 1.0 / 60.0)
        retry.restoreFrame(snapshot)
        retry.advance(by: 1.0 / 60.0)
        var expected = SceneParticleSimulator(definition: definition, seed: 17)
        expected.advance(by: 1.0 / 60.0)
        expected.advance(by: 1.0 / 60.0)
        let subframeDefinition = SceneParticleDefinitionParser().parse(root: [
            "material": "materials/unused.json",
            "maxcount": 8,
            "emitter": [[
                "name": "sphererandom", "rate": 120,
                "distancemin": 0, "distancemax": 0,
            ]],
            "initializer": [[
                "name": "lifetimerandom", "min": 0.0004, "max": 0.0004,
            ]],
            "renderer": [["name": "sprite"]],
        ])
        let subframe = SceneParticleSimulator(definition: subframeDefinition, seed: 19)
        subframe.advance(by: 1.0 / 60.0)
        let subframeSnapshot = subframe.frameSnapshot()
        let transientBeforeConsume = subframe.renderParticlesForCurrentAdvance().count
        _ = subframe.consumeBirthEvents()
        _ = subframe.consumeDeathEvents()
        let transientAfterConsume = subframe.renderParticlesForCurrentAdvance().count
        subframe.advance(by: 0)
        let transientAfterNextAdvance = subframe.renderParticlesForCurrentAdvance().count
        subframe.restoreFrame(subframeSnapshot)
        let steadyDefinition = SceneParticleDefinitionParser().parse(root: [
            "material": "materials/unused.json",
            "maxcount": 8,
            "emitter": [[
                "name": "sphererandom", "rate": 60,
                "distancemin": 0, "distancemax": 0,
            ]],
            "initializer": [[
                "name": "lifetimerandom", "min": 0.025, "max": 0.025,
            ]],
            "renderer": [["name": "sprite"]],
        ])
        let steady = SceneParticleSimulator(definition: steadyDefinition, seed: 23)
        steady.advance(by: 1.0 / 60.0)
        _ = steady.consumeBirthEvents()
        _ = steady.consumeDeathEvents()
        steady.advance(by: 1.0 / 60.0)
        return [
            "sameParticles": retry.particles == expected.particles,
            "sameTime": retry.simulationTime == expected.simulationTime,
            "sameRandom": retry.random.state == expected.random.state,
            "transientPersistentCount": subframe.particles.count,
            "transientBeforeConsume": transientBeforeConsume,
            "transientAfterConsume": transientAfterConsume,
            "transientAfterNextAdvance": transientAfterNextAdvance,
            "transientRestored": subframe.renderParticlesForCurrentAdvance().count,
            "steadyPersistentCount": steady.particles.count,
            "steadyTransientCount": steady.transientRenderSampleCount,
        ]
    }

    private static func syntheticSubframeLifetime() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-particle-subframe-lifetime-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 100,
            "controlpoint": [["id": 1, "flags": 1, "offset": "0 0 0"]],
            "emitter": [[
                "name": "sphererandom", "rate": 50, "controlpoint": 1,
                "distancemin": 0, "distancemax": 0,
            ]],
            "initializer": [
                ["name": "lifetimerandom", "min": 0.02, "max": 0.02],
                ["name": "sizerandom", "min": 8, "max": 8],
            ],
            "renderer": [["name": "sprite"]],
            "children": [["name": "particles/child.json", "type": "static"]],
        ], to: directory.appendingPathComponent("particles/root.json"))
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 100,
            "emitter": [[
                "name": "sphererandom", "rate": 120,
                "distancemin": 0, "distancemax": 0,
            ]],
            "initializer": [
                ["name": "lifetimerandom", "min": 0.0004, "max": 0.0004],
                ["name": "sizerandom", "min": 4, "max": 4],
            ],
            "renderer": [["name": "sprite"]],
        ], to: directory.appendingPathComponent("particles/child.json"))
        let descriptor = SceneRenderDescriptor(
            layers: [layer(
                984, "particles/root.json",
                particleLifetime: 0.02, particleRate: 3.95
            )],
            renderOrderLayerIDs: [984],
            materialPasses: [
                .init(
                    materialPath: "materials/shared.json",
                    shaderPath: "genericparticle",
                    texturePaths: ["shared.png"],
                    blending: "additive"
                )
            ]
        )
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw HarnessError.noMetal
        }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: directory,
            device: device
        )
        let pointer = SIMD3<Double>(32, 48, 0)
        let first = runtime.advance(
            by: 1.0 / 20.0,
            pointerLocalPositions: [984: pointer]
        )
        let lifecycle = runtime.lifecycleSnapshot
        let rootBatch = first.first { $0.particlePath == "particles/root.json" }
        let childBatch = first.first { $0.particlePath == "particles/child.json" }
        let second = runtime.advance(by: 1.0 / 120.0)
        return [
            "rootInstanceCount": rootBatch?.instances.count ?? 0,
            "childInstanceCount": childBatch?.instances.count ?? 0,
            "rootPositions": rootBatch?.instances.map {
                [$0.positionAndSize.x, $0.positionAndSize.y, $0.positionAndSize.z]
            } ?? [],
            "rootPersistentCount": lifecycle.rootParticleCount,
            "childPersistentCount": lifecycle.childParticleCount,
            "secondAdvanceInstanceCount": second.reduce(0) { $0 + $1.instances.count },
        ]
    }

    private static func syntheticSubframeChildLifecycle() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-particle-subframe-child-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))

        func writeShortParticle(
            _ path: String,
            flags: Int = 0,
            children: [[String: Any]] = []
        ) throws {
            var root: [String: Any] = [
                "material": "materials/shared.json", "maxcount": 8,
                "flags": flags,
                "emitter": [[
                    "name": "sphererandom", "rate": 0, "instantaneous": 1,
                    "distancemin": 0, "distancemax": 0,
                ]],
                "initializer": [
                    ["name": "lifetimerandom", "min": 0.0004, "max": 0.0004],
                    ["name": "sizerandom", "min": 4, "max": 4],
                ],
                "renderer": [["name": "sprite"]],
            ]
            if !children.isEmpty { root["children"] = children }
            try writeJSON(root, to: directory.appendingPathComponent(path))
        }

        try writeShortParticle("particles/static-world.json", flags: 1)
        try writeShortParticle("particles/spawn-leaf.json")
        try writeShortParticle("particles/death-leaf.json")
        try writeShortParticle("particles/nested-leaf.json")
        try writeShortParticle(
            "particles/spawn-parent.json",
            children: [[
                "name": "particles/nested-leaf.json", "type": "eventspawn",
                "maxcount": 1,
            ]]
        )

        func writeRoot(_ path: String, child: [String: Any]) throws {
            try writeJSON([
                "material": "materials/shared.json", "maxcount": 8,
                "emitter": [[
                    "name": "sphererandom", "rate": 0, "instantaneous": 1,
                    "distancemin": 0, "distancemax": 0,
                ]],
                "initializer": [[
                    "name": "lifetimerandom", "min": 0.0004, "max": 0.0004,
                ]],
                "renderer": [["name": "sprite"]],
                "children": [child],
            ], to: directory.appendingPathComponent(path))
        }
        try writeRoot("particles/root-static.json", child: [
            "name": "particles/static-world.json", "type": "static",
            "origin": "7 9 0", "maxcount": 1,
        ])
        try writeRoot("particles/root-spawn.json", child: [
            "name": "particles/spawn-leaf.json", "type": "eventspawn", "maxcount": 1,
        ])
        try writeRoot("particles/root-death.json", child: [
            "name": "particles/death-leaf.json", "type": "eventdeath", "maxcount": 1,
        ])
        try writeRoot("particles/root-depth-two.json", child: [
            "name": "particles/spawn-parent.json", "type": "eventspawn", "maxcount": 1,
        ])
        func writeRepeatingRoot(_ path: String, child: [String: Any]) throws {
            try writeJSON([
                "material": "materials/shared.json", "maxcount": 16,
                "emitter": [[
                    "name": "sphererandom", "rate": 60,
                    "distancemin": 0, "distancemax": 0,
                ]],
                "initializer": [[
                    "name": "lifetimerandom", "min": 10, "max": 10,
                ]],
                "renderer": [["name": "sprite"]],
                "children": [child],
            ], to: directory.appendingPathComponent(path))
        }
        try writeRepeatingRoot("particles/root-replace-depth-one.json", child: [
            "name": "particles/spawn-leaf.json", "type": "eventspawn", "maxcount": 1,
        ])
        try writeRepeatingRoot("particles/root-replace-depth-two.json", child: [
            "name": "particles/spawn-parent.json", "type": "eventspawn", "maxcount": 1,
        ])

        guard let device = MTLCreateSystemDefaultDevice() else {
            throw HarnessError.noMetal
        }
        let pass = SceneRenderDescriptor.MaterialPassDescriptor(
            materialPath: "materials/shared.json",
            shaderPath: "genericparticle",
            texturePaths: ["shared.png"],
            blending: "additive"
        )
        func runtime(_ id: Int, _ path: String) -> SceneParticleRuntime {
            SceneParticleRuntime(
                descriptor: SceneRenderDescriptor(
                    layers: [layer(id, path)],
                    renderOrderLayerIDs: [id],
                    materialPasses: [pass]
                ),
                cacheDirectory: directory,
                device: device
            )
        }
        func instances(
            _ batches: [SceneParticleDrawBatch], path: String
        ) -> [SceneParticleGPUInstance] {
            batches.first { $0.particlePath == path }?.instances ?? []
        }
        func childInstanceTotal(_ batches: [SceneParticleDrawBatch]) -> Int {
            batches.filter { $0.particlePath != "particles/root-static.json"
                && $0.particlePath != "particles/root-spawn.json"
                && $0.particlePath != "particles/root-death.json"
                && $0.particlePath != "particles/root-depth-two.json"
            }.reduce(0) { $0 + $1.instances.count }
        }

        let staticRuntime = runtime(991, "particles/root-static.json")
        let staticFirst = staticRuntime.advance(by: 1.0 / 60.0)
        let staticFirstLifecycle = staticRuntime.lifecycleSnapshot
        let staticSecond = staticRuntime.advance(by: 1.0 / 60.0)
        let staticInstances = instances(staticFirst, path: "particles/static-world.json")

        let spawnRuntime = runtime(992, "particles/root-spawn.json")
        _ = spawnRuntime.advance(by: 1.0 / 60.0)
        let spawnSecond = spawnRuntime.advance(by: 1.0 / 60.0)
        let spawnSecondLifecycle = spawnRuntime.lifecycleSnapshot
        let spawnThird = spawnRuntime.advance(by: 1.0 / 60.0)

        let deathRuntime = runtime(993, "particles/root-death.json")
        _ = deathRuntime.advance(by: 1.0 / 60.0)
        let deathSecond = deathRuntime.advance(by: 1.0 / 60.0)
        let deathSecondLifecycle = deathRuntime.lifecycleSnapshot
        let deathThird = deathRuntime.advance(by: 1.0 / 60.0)

        let depthRuntime = runtime(994, "particles/root-depth-two.json")
        _ = depthRuntime.advance(by: 1.0 / 60.0)
        let depthSecond = depthRuntime.advance(by: 1.0 / 60.0)
        let depthSecondLifecycle = depthRuntime.lifecycleSnapshot
        let depthThird = depthRuntime.advance(by: 1.0 / 60.0)
        let depthThirdLifecycle = depthRuntime.lifecycleSnapshot
        let depthFourth = depthRuntime.advance(by: 1.0 / 60.0)

        let replacementRuntime = runtime(995, "particles/root-replace-depth-one.json")
        _ = replacementRuntime.advance(by: 1.0 / 60.0)
        let replacementSecond = replacementRuntime.advance(by: 1.0 / 60.0)
        let replacementSecondLifecycle = replacementRuntime.lifecycleSnapshot
        let replacementThird = replacementRuntime.advance(by: 1.0 / 60.0)
        let replacementThirdLifecycle = replacementRuntime.lifecycleSnapshot

        let nestedReplacementRuntime = runtime(996, "particles/root-replace-depth-two.json")
        _ = nestedReplacementRuntime.advance(by: 1.0 / 60.0)
        _ = nestedReplacementRuntime.advance(by: 1.0 / 60.0)
        let nestedReplacementThird = nestedReplacementRuntime.advance(by: 1.0 / 60.0)
        let nestedReplacementThirdLifecycle = nestedReplacementRuntime.lifecycleSnapshot
        let nestedReplacementFourth = nestedReplacementRuntime.advance(by: 1.0 / 60.0)
        let nestedReplacementFourthLifecycle = nestedReplacementRuntime.lifecycleSnapshot

        return [
            "staticCount": staticInstances.count,
            "staticPosition": staticInstances.first.map {
                [$0.positionAndSize.x, $0.positionAndSize.y, $0.positionAndSize.z]
            } ?? [],
            "staticLifecycleSystems": staticFirstLifecycle.childSystemCount,
            "staticLifecycleParticles": staticFirstLifecycle.childParticleCount,
            "staticNextCount": childInstanceTotal(staticSecond),
            "spawnCount": instances(spawnSecond, path: "particles/spawn-leaf.json").count,
            "spawnLifecycleSystems": spawnSecondLifecycle.childSystemCount,
            "spawnLifecycleParticles": spawnSecondLifecycle.childParticleCount,
            "spawnNextCount": childInstanceTotal(spawnThird),
            "deathCount": instances(deathSecond, path: "particles/death-leaf.json").count,
            "deathLifecycleSystems": deathSecondLifecycle.childSystemCount,
            "deathLifecycleParticles": deathSecondLifecycle.childParticleCount,
            "deathNextCount": childInstanceTotal(deathThird),
            "depthOneCount": instances(
                depthSecond, path: "particles/spawn-parent.json"
            ).count,
            "depthOneRemainingSystems": depthSecondLifecycle.childSystemCount,
            "depthTwoCount": instances(
                depthThird, path: "particles/nested-leaf.json"
            ).count,
            "depthTwoLifecycleSystems": depthThirdLifecycle.childSystemCount,
            "depthTwoLifecycleParticles": depthThirdLifecycle.childParticleCount,
            "depthTwoNextCount": childInstanceTotal(depthFourth),
            "replacementSecondCount": instances(
                replacementSecond, path: "particles/spawn-leaf.json"
            ).count,
            "replacementSecondSystems": replacementSecondLifecycle.childSystemCount,
            "replacementThirdCount": instances(
                replacementThird, path: "particles/spawn-leaf.json"
            ).count,
            "replacementThirdSystems": replacementThirdLifecycle.childSystemCount,
            "nestedReplacementThirdCount": instances(
                nestedReplacementThird, path: "particles/nested-leaf.json"
            ).count,
            "nestedReplacementThirdSystems": nestedReplacementThirdLifecycle.childSystemCount,
            "nestedReplacementFourthCount": instances(
                nestedReplacementFourth, path: "particles/nested-leaf.json"
            ).count,
            "nestedReplacementFourthSystems": nestedReplacementFourthLifecycle.childSystemCount,
        ]
    }

    private static func syntheticChildPointerControlPoint() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-particle-child-pointer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writeParticle(
            "particles/root.json", material: "materials/shared.json",
            lifetime: 1, rate: 0, instantaneous: 1,
            children: [[
                "name": "particles/child-force.json", "type": "eventfollow",
                "maxcount": 1, "scale": "2.5 2.5 1",
            ], [
                "name": "particles/child-emitter.json", "type": "eventfollow",
                "maxcount": 1, "scale": "2.5 2.5 1",
            ]], under: directory
        )
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 1,
            "controlpoint": [["id": 1, "flags": 1, "offset": "0 0 0"]],
            "emitter": [[
                "name": "sphererandom", "rate": 0, "instantaneous": 1,
                "distancemin": 0, "distancemax": 0,
            ]],
            "initializer": [["name": "lifetimerandom", "min": 1, "max": 1]],
            "operator": [
                [
                    "name": "controlpointattract", "controlpoint": 1,
                    "origin": "0 0 0", "scale": 60, "threshold": 5,
                ],
                ["name": "movement"],
            ],
            "renderer": [["name": "sprite"]],
        ], to: directory.appendingPathComponent("particles/child-force.json"))
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 1,
            "controlpoint": [["id": 1, "flags": 1, "offset": "0 0 0"]],
            "emitter": [[
                "name": "sphererandom", "rate": 0, "instantaneous": 1,
                "distancemin": 0, "distancemax": 0, "controlpoint": 1,
            ]],
            "initializer": [["name": "lifetimerandom", "min": 1, "max": 1]],
            "renderer": [["name": "sprite"]],
        ], to: directory.appendingPathComponent("particles/child-emitter.json"))
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 1,
            "controlpoint": [["id": 1, "flags": 1, "offset": "0 0 0"]],
            "emitter": [[
                "name": "sphererandom", "rate": 0, "instantaneous": 1,
                "origin": "5 0 0", "distancemin": 0, "distancemax": 0,
                "controlpoint": 1,
            ]],
            "initializer": [["name": "lifetimerandom", "min": 1, "max": 1]],
            "renderer": [["name": "sprite"]],
            "children": [[
                "name": "particles/child-static-emitter.json", "type": "eventfollow",
                "maxcount": 1, "scale": "2.5 2.5 1",
            ]],
        ], to: directory.appendingPathComponent("particles/root-pointer.json"))
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 1,
            "controlpoint": [["id": 1, "flags": 0, "offset": "4 0 0"]],
            "emitter": [[
                "name": "sphererandom", "rate": 0, "instantaneous": 1,
                "distancemin": 0, "distancemax": 0, "controlpoint": 1,
            ]],
            "initializer": [["name": "lifetimerandom", "min": 1, "max": 1]],
            "renderer": [["name": "sprite"]],
        ], to: directory.appendingPathComponent("particles/child-static-emitter.json"))
        let descriptor = SceneRenderDescriptor(
            layers: [layer(18, "particles/root.json")],
            renderOrderLayerIDs: [18],
            materialPasses: [.init(
                materialPath: "materials/shared.json", shaderPath: "genericparticle",
                texturePaths: ["shared.png"], blending: "additive"
            )]
        )
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let demandRuntime = SceneParticleRuntime(
            descriptor: descriptor, cacheDirectory: directory, device: device
        )
        let dynamicTarget = SceneDynamicTarget.particle(
            layerID: 18, field: .controlPoint(1)
        )
        let dynamicDefinition = SceneDynamicTargetDefinition(
            target: dynamicTarget,
            valueType: .vector3,
            authoredValue: .vector3(0, 0, 0)
        )
        let dynamicResolver = SceneDynamicSnapshotResolver()
        func dynamicSnapshot(_ value: SIMD3<Double>) -> SceneDynamicSnapshot {
            dynamicResolver.resolve(
                frameIndex: 1,
                generation: 1,
                definitions: [dynamicDefinition],
                timelineValues: [dynamicTarget: .vector3(value.x, value.y, value.z)]
            ).snapshot
        }
        func velocity(
            pointer: SIMD3<Double>?, dynamic: SIMD3<Double>? = nil
        ) -> [Float] {
            let runtime = SceneParticleRuntime(
                descriptor: descriptor, cacheDirectory: directory, device: device
            )
            var batches: [SceneParticleDrawBatch] = []
            for _ in 0..<2 {
                batches = runtime.advance(
                    by: 1.0 / 60.0,
                    dynamicValues: dynamic.map(dynamicSnapshot) ?? .empty(frameIndex: 0),
                    pointerLocalPositions: pointer.map { [18: $0] } ?? [:]
                )
            }
            guard let value = batches.first(where: {
                $0.particlePath == "particles/child-force.json"
            })?.instances.first?.velocityAndTrail else { return [] }
            return [value.x, value.y, value.z]
        }
        func emitterPositions(
            initialPointer: SIMD3<Double>?,
            recoveredPointer: SIMD3<Double>? = nil,
            dynamic: SIMD3<Double>? = nil
        ) -> [[Float]] {
            let runtime = SceneParticleRuntime(
                descriptor: descriptor, cacheDirectory: directory, device: device
            )
            var batches: [SceneParticleDrawBatch] = []
            for _ in 0..<2 {
                batches = runtime.advance(
                    by: 1.0 / 60.0,
                    dynamicValues: dynamic.map(dynamicSnapshot) ?? .empty(frameIndex: 0),
                    pointerLocalPositions: initialPointer.map { [18: $0] } ?? [:]
                )
            }
            if let recoveredPointer {
                batches = runtime.advance(
                    by: 1.0 / 60.0,
                    pointerLocalPositions: [18: recoveredPointer]
                )
            }
            return batches.first(where: {
                $0.particlePath == "particles/child-emitter.json"
            })?.instances.map {
                [$0.positionAndSize.x, $0.positionAndSize.y, $0.positionAndSize.z]
            } ?? []
        }
        func rootPointerChildStaticPosition() -> [Float] {
            let pointerDescriptor = SceneRenderDescriptor(
                layers: [layer(19, "particles/root-pointer.json")],
                renderOrderLayerIDs: [19],
                materialPasses: descriptor.materialPasses
            )
            let runtime = SceneParticleRuntime(
                descriptor: pointerDescriptor, cacheDirectory: directory, device: device
            )
            var batches: [SceneParticleDrawBatch] = []
            for _ in 0..<2 {
                batches = runtime.advance(
                    by: 1.0 / 60.0,
                    pointerLocalPositions: [19: SIMD3(10, 0, 0)]
                )
            }
            guard let position = batches.first(where: {
                $0.particlePath == "particles/child-static-emitter.json"
            })?.instances.first?.positionAndSize else { return [] }
            return [position.x, position.y, position.z]
        }
        return [
            "outside": velocity(pointer: nil),
            // Root-local x=10 becomes child-local x=4 through authored scale 2.5,
            // which is inside threshold 5. Without that frame conversion it is outside.
            "insideScaled": velocity(pointer: SIMD3(10, 0, 0)),
            "dynamicInsideScaled": velocity(
                pointer: nil, dynamic: SIMD3(10, 0, 0)
            ),
            "emitterMissing": emitterPositions(initialPointer: nil),
            "emitterDynamicOnly": emitterPositions(
                initialPointer: nil, dynamic: SIMD3(10, 0, 0)
            ),
            "emitterRecovered": emitterPositions(
                initialPointer: nil, recoveredPointer: SIMD3(10, 0, 0)
            ),
            // Root pointer overlays are root-only. The root emitter's +5 origin
            // makes the event-follow child origin differ from pointer x=10:
            // authored child CP1 yields 15 + 4*2.5 = 25, while the old leak
            // would add child-local (10-15)/2.5 to CP1 and yield x=20.
            "rootPointerChildStaticPosition": rootPointerChildStaticPosition(),
            "pointerDemandLayerIDs": demandRuntime.pointerControlPointLayerIDs.sorted(),
        ]
    }

    private static func syntheticDynamicControlPointAngle() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-particle-dynamic-cp-angle-\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 1,
            "controlpoint": [["id": 1, "flags": 0, "offset": "0 0 0"]],
            "emitter": [[
                "name": "sphererandom", "rate": 0, "instantaneous": 1,
                "distancemin": 0, "distancemax": 0, "controlpoint": 1,
            ]],
            "initializer": [
                ["name": "lifetimerandom", "min": 10, "max": 10],
                ["name": "velocityrandom", "min": [1, 0, 0], "max": [1, 0, 0]],
            ],
            "renderer": [["name": "sprite"]],
            "children": [[
                "name": "particles/angle-child.json", "type": "eventfollow", "maxcount": 1,
            ]],
        ], to: directory.appendingPathComponent("particles/root.json"))
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 1,
            "controlpoint": [["id": 1, "flags": 0, "offset": "0 0 0"]],
            "emitter": [[
                "name": "sphererandom", "rate": 0, "instantaneous": 1,
                "distancemin": 0, "distancemax": 0, "controlpoint": 1,
            ]],
            "initializer": [
                ["name": "lifetimerandom", "min": 10, "max": 10],
                ["name": "velocityrandom", "min": [1, 0, 0], "max": [1, 0, 0]],
            ],
            "renderer": [["name": "sprite"]],
        ], to: directory.appendingPathComponent("particles/angle-child.json"))
        let descriptor = SceneRenderDescriptor(
            layers: [layer(180, "particles/root.json")],
            renderOrderLayerIDs: [180],
            materialPasses: [.init(
                materialPath: "materials/shared.json", shaderPath: "genericparticle",
                texturePaths: ["shared.png"], blending: "additive"
            )]
        )
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let target = SceneDynamicTarget.particle(
            layerID: 180, field: .controlPointAngles(1)
        )
        let definition = SceneDynamicTargetDefinition(
            target: target, valueType: .vector3, authoredValue: .vector3(0, 0, 0)
        )
        let resolver = SceneDynamicSnapshotResolver()
        func snapshot(_ value: SceneDynamicValue) -> SceneDynamicSnapshot {
            resolver.resolve(
                frameIndex: 1, generation: 1, definitions: [definition],
                timelineValues: [target: value]
            ).snapshot
        }
        func velocities(_ values: SceneDynamicSnapshot) -> [[Float]] {
            let runtime = SceneParticleRuntime(
                descriptor: descriptor, cacheDirectory: directory, device: device
            )
            var batches: [SceneParticleDrawBatch] = []
            for _ in 0..<2 {
                batches = runtime.advance(by: 1.0 / 60.0, dynamicValues: values)
            }
            return [
                batches.first { $0.particlePath == "particles/root.json" }?.instances.first
                    .map { [$0.velocityAndTrail.x, $0.velocityAndTrail.y] } ?? [],
                batches.first { $0.particlePath == "particles/angle-child.json" }?.instances.first
                    .map { [$0.velocityAndTrail.x, $0.velocityAndTrail.y] } ?? [],
            ]
        }
        return [
            "dynamic": velocities(snapshot(.vector3(0, 0, Double.pi / 2))),
            "fallback": velocities(.empty(frameIndex: 0)),
            "malformed": velocities(snapshot(.vector2(0, 1))),
        ]
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
        let ropePaths = Set([
            "particles/presets/dripping_water_refract.json",
            "particles/presets/dripping_water_splash.json",
        ])
        let trailChildPath = "particles/presets/water_impact_droplets.json"
        var activeFrames: [Int: Int] = [:]
        var maximumInstances: [Int: Int] = [:]
        var candidateLayers = Set<Int>()
        var legacyLayers = Set<Int>()
        var activeRopePaths = Set<String>()
        var maximumRopeInstances: [String: Int] = [:]
        var refractiveRopePaths = Set<String>()
        var activeTrailChildLayers = Set<Int>()
        var maximumTrailChildInstances: [Int: Int] = [:]
        var minimumTrailStretch = Float.greatestFiniteMagnitude
        var maximumTrailStretch: Float = 0
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
                if ropePaths.contains(batch.particlePath), !batch.instances.isEmpty {
                    activeRopePaths.insert(batch.particlePath)
                    maximumRopeInstances[batch.particlePath] = max(
                        maximumRopeInstances[batch.particlePath, default: 0],
                        batch.instances.count
                    )
                    if batch.refraction != nil { refractiveRopePaths.insert(batch.particlePath) }
                }
                if batch.particlePath == trailChildPath, !batch.instances.isEmpty {
                    activeTrailChildLayers.insert(batch.layerID)
                    maximumTrailChildInstances[batch.layerID] = max(
                        maximumTrailChildInstances[batch.layerID, default: 0],
                        batch.instances.count
                    )
                    for instance in batch.instances {
                        minimumTrailStretch = min(minimumTrailStretch, instance.velocityAndTrail.w)
                        maximumTrailStretch = max(maximumTrailStretch, instance.velocityAndTrail.w)
                    }
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
            "activeRopePaths": activeRopePaths.sorted(),
            "maximumRopeInstances": maximumRopeInstances,
            "refractiveRopePaths": refractiveRopePaths.sorted(),
            "activeTrailChildLayers": activeTrailChildLayers.sorted(),
            "maximumTrailChildInstances": Dictionary(uniqueKeysWithValues:
                targetLayers.sorted().map {
                    (String($0), maximumTrailChildInstances[$0, default: 0])
                }
            ),
            "minimumTrailStretch": minimumTrailStretch.isFinite ? minimumTrailStretch : -1,
            "maximumTrailStretch": maximumTrailStretch,
            "trailChildUnsupported": runtime.diagnostics.compactMap { diagnostic in
                diagnostic.kind == .childSystemsUnsupported
                    && (diagnostic.detail ?? "").contains(trailChildPath)
                    ? (diagnostic.detail ?? "") : nil
            },
            "ropeUnsupported": runtime.diagnostics.compactMap { diagnostic in
                diagnostic.kind == .childSystemsUnsupported
                    && ropePaths.contains(where: {
                        (diagnostic.detail ?? "").contains($0)
                    })
                    ? (diagnostic.detail ?? "") : nil
            },
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
                "scale": "2.5 2.5 1",
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
                "scale": "0.2 0.2 0.2",
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
            ], [
                "name": "particles/audio-operator-child.json", "type": "static",
            ]], under: directory
        )
        try writeParticle(
            "particles/audio-child.json", material: "materials/shared.json",
            rate: 60, audioProcessingMode: 1, under: directory
        )
        try writeParticle(
            "particles/audio-operator-child.json", material: "materials/shared.json",
            rate: 0, operatorAudioProcessingMode: 1, instantaneous: 1, under: directory
        )
        try writeParticle(
            "particles/audio-churn-root.json", material: "materials/shared.json",
            lifetime: 1.0 / 60.0, rate: 60,
            children: [[
                "name": "particles/audio-churn-child.json", "type": "eventspawn",
            ]], under: directory
        )
        try writeParticle(
            "particles/audio-churn-child.json", material: "materials/shared.json",
            rate: 0, operatorAudioProcessingMode: 1, instantaneous: 1, under: directory
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
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 1,
            "emitter": [["name": "sphererandom", "rate": 0, "instantaneous": 1]],
            "initializer": [
                ["name": "lifetimerandom", "min": 1, "max": 1],
                ["name": "colorrandom", "min": "255 255 255", "max": "255 255 255"],
            ],
            "operator": [[
                "name": "colorchange", "starttime": 0, "endtime": 1,
                "startvalue": "1 1 1", "endvalue": "0 0 1",
            ]],
            "renderer": [["name": "sprite"]],
            "children": [[
                "name": "particles/inherit-follow-child.json", "type": "eventfollow",
            ]],
        ], to: directory.appendingPathComponent("particles/inherit-follow-root.json"))
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 1,
            "emitter": [["name": "sphererandom", "rate": 0, "instantaneous": 1]],
            "initializer": [["name": "lifetimerandom", "min": 1, "max": 1]],
            "operator": [["name": "inheritvaluefromevent"]],
            "renderer": [["name": "sprite"]],
        ], to: directory.appendingPathComponent("particles/inherit-follow-child.json"))
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 1,
            "emitter": [["name": "sphererandom", "rate": 0, "instantaneous": 1]],
            "initializer": [
                ["name": "lifetimerandom", "min": 1.0 / 60.0, "max": 1.0 / 60.0],
                ["name": "colorrandom", "min": "51 102 153", "max": "51 102 153"],
            ],
            "renderer": [["name": "sprite"]],
            "children": [[
                "name": "particles/inherit-death-child.json", "type": "eventdeath",
            ]],
        ], to: directory.appendingPathComponent("particles/inherit-death-root.json"))
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 1,
            "emitter": [["name": "sphererandom", "rate": 0, "instantaneous": 1]],
            "initializer": [
                ["name": "lifetimerandom", "min": 1, "max": 1],
                ["name": "inheritinitialvaluefromevent"],
            ],
            "renderer": [["name": "sprite"]],
        ], to: directory.appendingPathComponent("particles/inherit-death-child.json"))
        for (path, component): (String, [String: Any]) in [
            ("particles/invalid-inherit-static.json", ["name": "inheritinitialvaluefromevent"]),
            ("particles/invalid-inherit-death.json", ["name": "inheritvaluefromevent"]),
            ("particles/invalid-inherit-follow.json", [
                "name": "inheritvaluefromevent", "input": "setsize",
            ]),
        ] {
            var initializers: [[String: Any]] = [
                ["name": "lifetimerandom", "min": 1, "max": 1],
            ]
            var operators: [[String: Any]] = []
            if component["name"] as? String == "inheritinitialvaluefromevent" {
                initializers.append(component)
            } else {
                operators.append(component)
            }
            try writeJSON([
                "material": "materials/shared.json", "maxcount": 1,
                "emitter": [["name": "sphererandom", "rate": 0, "instantaneous": 1]],
                "initializer": initializers,
                "operator": operators,
                "renderer": [["name": "sprite"]],
            ], to: directory.appendingPathComponent(path))
        }
        try writeParticle(
            "particles/invalid-inherit-root.json", material: "materials/shared.json",
            rate: 0, instantaneous: 1,
            children: [
                ["name": "particles/invalid-inherit-static.json", "type": "static"],
                ["name": "particles/invalid-inherit-death.json", "type": "eventdeath"],
                ["name": "particles/invalid-inherit-follow.json", "type": "eventfollow"],
            ], under: directory
        )

        let descriptor = SceneRenderDescriptor(
            layers: [
                layer(10, "particles/follow-root.json"),
                layer(11, "particles/bounded-root.json"),
                layer(12, "particles/budget-root.json"),
                layer(13, "particles/audio-root.json"),
                layer(14, "particles/window-root.json"),
                layer(15, "particles/inherit-follow-root.json"),
                layer(16, "particles/inherit-death-root.json"),
                layer(17, "particles/invalid-inherit-root.json"),
            ],
            renderOrderLayerIDs: [10, 11, 12, 13, 14, 15, 16, 17],
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
        let activeAudioRuntime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: directory,
            device: device
        )
        let activeAudioInput = SceneParticleAudioInput(
            left: Array(repeating: 1, count: SceneParticleAudioInput.bandCount),
            right: Array(repeating: 1, count: SceneParticleAudioInput.bandCount),
            generation: 7
        )
        for _ in 0..<2 {
            _ = activeAudioRuntime.advance(by: 1.0 / 60.0, audioInput: activeAudioInput)
        }
        let activeChildAudioInput = activeAudioRuntime.frameSnapshot().layers
            .compactMap { $0.child?.systems.first?.simulatorFrame.audioInput.left.first }
            .first ?? 0
        let churnDescriptor = SceneRenderDescriptor(
            layers: [layer(18, "particles/audio-churn-root.json")],
            renderOrderLayerIDs: [18],
            materialPasses: descriptor.materialPasses
        )
        let churnRuntime = SceneParticleRuntime(
            descriptor: churnDescriptor,
            cacheDirectory: directory,
            device: device
        )
        _ = churnRuntime.advance(by: 1.0 / 60.0, audioInput: activeAudioInput)
        let churnRollbackSnapshot = churnRuntime.frameSnapshot()
        _ = churnRuntime.advance(by: 1.0 / 60.0, audioInput: activeAudioInput)
        let rejectedChurnObservations = churnRuntime.consumeAudioEvaluationObservations()
        churnRuntime.restoreFrame(churnRollbackSnapshot)
        let churnObservationsAfterRestore = churnRuntime
            .consumeAudioEvaluationObservations()
        _ = churnRuntime.advance(by: 1.0 / 60.0, audioInput: activeAudioInput)
        let retryChurnObservations = churnRuntime.consumeAudioEvaluationObservations()
        var laterChurnObservationCount = 0
        for _ in 0..<6 {
            _ = churnRuntime.advance(by: 1.0 / 60.0, audioInput: activeAudioInput)
            laterChurnObservationCount += churnRuntime
                .consumeAudioEvaluationObservations().count
        }
        var childCounts: [Int] = []
        var childPositions: [Float] = []
        var childSizes: [Float] = []
        var boundedCounts: [Int] = []
        var boundedSizes: [Float] = []
        var budgetCounts: [Int] = []
        var windowCounts: [Int] = []
        var inheritedFollowMatches: [Bool] = []
        var inheritedDeathColors: [[Float]] = []
        for _ in 0..<6 {
            let batches = runtime.advance(by: 1.0 / 60.0)
            let instances = batches.first {
                $0.particlePath == "particles/follow-child.json"
            }?.instances ?? []
            childCounts.append(instances.count)
            if let position = instances.first?.positionAndSize.x {
                childPositions.append(position)
            }
            if let size = instances.first?.positionAndSize.w {
                childSizes.append(size)
            }
            let boundedInstances = batches.first {
                $0.particlePath == "particles/bounded-child.json"
            }?.instances ?? []
            boundedCounts.append(boundedInstances.count)
            if let size = boundedInstances.first?.positionAndSize.w {
                boundedSizes.append(size)
            }
            budgetCounts.append(batches.first {
                $0.particlePath == "particles/budget-child.json"
            }?.instances.count ?? 0)
            windowCounts.append(batches.first {
                $0.particlePath == "particles/window-child.json"
            }?.instances.count ?? 0)
            let followRootColor = batches.first {
                $0.particlePath == "particles/inherit-follow-root.json"
            }?.instances.first?.colorAndFrameMix
            let followChildColor = batches.first {
                $0.particlePath == "particles/inherit-follow-child.json"
            }?.instances.first?.colorAndFrameMix
            if let root = followRootColor, let child = followChildColor {
                inheritedFollowMatches.append(
                    abs(root.x - child.x) < 1e-6 && abs(root.y - child.y) < 1e-6
                        && abs(root.z - child.z) < 1e-6
                )
            }
            if let color = batches.first(where: {
                $0.particlePath == "particles/inherit-death-child.json"
            })?.instances.first?.colorAndFrameMix {
                inheritedDeathColors.append([color.x, color.y, color.z])
            }
        }
        return [
            "windowCounts": windowCounts,
            "childCounts": childCounts,
            "childPositions": childPositions,
            "childSizes": childSizes,
            "boundedCounts": boundedCounts,
            "boundedSizes": boundedSizes,
            "budgetCounts": budgetCounts,
            "inheritedFollowMatches": inheritedFollowMatches,
            "inheritedDeathColors": inheritedDeathColors,
            "eventColorMarkers": runtime.diagnostics.compactMap {
                $0.kind == .simulationLimitation && $0.detail?.contains("eventColor") == true
                    ? $0.detail : nil
            },
            "invalidEventColorDetails": runtime.diagnostics.compactMap {
                $0.layerID == 17 && $0.kind == .childSystemsUnsupported
                    && $0.detail?.contains("eventColor") == true ? $0.detail : nil
            },
            "childUnsupportedLayers": runtime.diagnostics.compactMap {
                $0.kind == .childSystemsUnsupported && ![13, 17].contains($0.layerID)
                    ? $0.layerID : nil
            },
            "budgetDetails": runtime.diagnostics.compactMap {
                $0.layerID == 12 && $0.kind == .simulationLimitation ? $0.detail : nil
            },
            "audioChildDetails": runtime.diagnostics.compactMap {
                $0.layerID == 13 && $0.kind == .childSystemsUnsupported ? $0.detail : nil
            },
            "hasAudioConsumer": runtime.hasAudioConsumer,
            "activeChildAudioInput": activeChildAudioInput,
            "rejectedChurnObservationCount": rejectedChurnObservations.count,
            "churnObservationsAfterRestore": churnObservationsAfterRestore.count,
            "retryChurnObservationCount": retryChurnObservations.count,
            "retryChurnObservationPaths": retryChurnObservations.map(\.particlePath),
            "laterChurnObservationCount": laterChurnObservationCount,
            "childScaleDetails": runtime.diagnostics.compactMap {
                $0.kind == .simulationLimitation && $0.detail?.contains("childScaleBounded") == true
                    ? $0.detail : nil
            },
        ]
    }

    private static func syntheticWorldSpaceGravityFrame() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-particle-worldspace-gravity-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        func writeGravityParticle(_ path: String, startTime: Double) throws {
            try writeJSON([
                "material": "materials/shared.json", "maxcount": 100, "flags": 1,
                "starttime": startTime,
                "emitter": [[
                    "name": "sphererandom", "rate": 120,
                    "distancemin": 0, "distancemax": 0,
                ]],
                "initializer": [
                    ["name": "lifetimerandom", "min": 10, "max": 10],
                    ["name": "sizerandom", "min": 8, "max": 8],
                ],
                "operator": [[
                    "name": "movement", "flags": 1, "gravity": "60 0 0",
                ]],
                "renderer": [["name": "sprite"]],
            ], to: directory.appendingPathComponent(path))
        }
        try writeGravityParticle("particles/world-gravity-prewarm.json", startTime: 0.1)
        try writeGravityParticle("particles/world-gravity-live.json", startTime: 0)
        let materialPasses: [SceneRenderDescriptor.MaterialPassDescriptor] = [
            .init(
                materialPath: "materials/shared.json",
                shaderPath: "genericparticle",
                texturePaths: ["shared.png"],
                blending: "additive"
            )
        ]
        func descriptor(_ path: String) -> SceneRenderDescriptor {
            SceneRenderDescriptor(
                layers: [layer(81, path)],
                renderOrderLayerIDs: [81],
                materialPasses: materialPasses
            )
        }
        func positions(_ batches: [SceneParticleDrawBatch]) -> [[Float]] {
            (batches.first { $0.layerID == 81 })?.instances.map {
                [$0.positionAndSize.x, $0.positionAndSize.y, $0.positionAndSize.z]
            } ?? []
        }
        func axisSums(_ values: [[Float]]) -> (x: Double, y: Double) {
            (
                values.reduce(0) { $0 + abs(Double($1[0])) },
                values.reduce(0) { $0 + abs(Double($1[1])) }
            )
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw HarnessError.noMetal
        }
        // Prewarm: the init-time warm-up must convert world gravity through
        // the injected launch frame (a +90 degree Z rotation sends world +X
        // gravity into the local Y axis).
        let plusZ = simd_float4x4(columns: (
            SIMD4(0, 1, 0, 0), SIMD4(-1, 0, 0, 0),
            SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)
        ))
        let prewarm = SceneParticleRuntime(
            descriptor: descriptor("particles/world-gravity-prewarm.json"),
            cacheDirectory: directory,
            device: device,
            staticWorldSpaceFrames: [
                81: SceneParticleWorldSpaceFrame(worldFrame: plusZ)!,
            ]
        )
        let prewarmPositions = positions(
            prewarm.advance(by: 1.0 / 60.0, dynamicValues: .empty(frameIndex: 0))
        )
        // Live gravity: with a transform lane and a -90 degree Z current
        // frame, world +X gravity runs into local +Y during the advance.
        let minusZ = simd_float4x4(columns: (
            SIMD4(0, -1, 0, 0), SIMD4(1, 0, 0, 0),
            SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)
        ))
        let live = SceneParticleRuntime(
            descriptor: descriptor("particles/world-gravity-live.json"),
            cacheDirectory: directory,
            device: device
        )
        _ = live.advance(by: 1.0 / 60.0, dynamicValues: .empty(frameIndex: 0))
        var livePositions: [[Float]] = []
        for _ in 0..<6 {
            livePositions = positions(
                live.advance(
                    by: 1.0 / 60.0,
                    dynamicValues: snapshotWithTransformLane(layerID: 81),
                    layerWorldFrames: [81: minusZ]
                )
            )
        }
        let prewarmSums = axisSums(prewarmPositions)
        let liveSums = axisSums(livePositions)
        return [
            "prewarmPositions": prewarmPositions,
            "prewarmX": prewarmSums.x,
            "prewarmY": prewarmSums.y,
            "livePositions": livePositions,
            "liveX": liveSums.x,
            "liveY": liveSums.y,
        ]
    }

    /// Offline replay of a real captured render descriptor: advances the
    /// particle runtime with an injected pointer position and reports the
    /// layer's demand registration and birth positions.
    private static func realPointerDemand(
        evidencePath: String,
        cachePath: String,
        layerID: Int,
        pointer: SIMD3<Double>
    ) throws -> [String: Any] {
        let cache = URL(fileURLWithPath: cachePath, isDirectory: true)
        let descriptor = try renderDescriptor(evidencePath: evidencePath)
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw HarnessError.noMetal
        }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: cache,
            device: device
        )
        var batches: [SceneParticleDrawBatch] = []
        for _ in 0..<4 {
            batches = runtime.advance(
                by: 1.0 / 60.0,
                pointerLocalPositions: [layerID: pointer]
            )
        }
        let layerBatches = batches.filter { $0.layerID == layerID }
        let positions = layerBatches.flatMap { $0.instances.map {
            [$0.positionAndSize.x, $0.positionAndSize.y, $0.positionAndSize.z]
        } }
        return [
            "demandedLayerIDs": Array(runtime.pointerControlPointLayerIDs),
            "activeLayerIDs": runtime.activeLayerIDs,
            "positionCount": positions.count,
            "positions": positions,
            "diagnosticKinds": runtime.diagnostics.map(\.kind.rawValue),
        ]
    }

    /// Audio response gates emission through authored bounds alone: the
    /// editor writes `audioprocessingbounds` for an audio-gated emitter and
    /// `audioprocessingmode` only selects the channel. A bounds-only emitter
    /// (corpus: 8 emitters / 8 samples, e.g. 3665307769 red_fire) must stay
    /// silent without audio and emit with it.
    /// The pointer-trail rope family (2986218263 and five more samples):
    /// world system, pointer-locked CP0 with an implicit emitter source, and
    /// a rope renderer with flags=1 / subdivision=100 / maxcount=256.
    /// The mouse-repel family (1994794519 / 3078285611 / 3396722575): a
    /// world/perspective system whose pointer CP1 drives a negative-scale
    /// controlpointattract. The pointer value is the layer-local
    /// unprojection and the force composes positions entirely in local
    /// space, so the demand shares the emitter path's space pairing.
    /// positionaroundcontrolpoint (authored as mapsequencearoundcontrolpoint)
    /// on a pointer CP in a world system: births distribute around the
    /// pointer's layer-local position. Same-family release as the force path
    /// (no newly affected corpus consumer in the current shape).
    private static func syntheticWorldSpacePointerPositionAround() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-particle-worldspace-posaround-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 100, "flags": 1,
            "controlpoint": [
                ["id": 0, "flags": 0, "offset": "0 0 0"],
                ["id": 1, "flags": 1, "offset": "0 0 0"],
            ],
            "emitter": [[
                "name": "sphererandom", "rate": 120,
                "distancemin": 20, "distancemax": 50, "controlpoint": 1,
            ]],
            "initializer": [
                ["name": "lifetimerandom", "min": 10, "max": 10],
                ["name": "sizerandom", "min": 8, "max": 8],
                [
                    "name": "mapsequencearoundcontrolpoint", "controlpoint": 1,
                    "bounds": "0 1", "count": 4,
                    "speedmin": "10 10 0", "speedmax": "10 10 0",
                    "limitbehavior": "repeat",
                ],
            ],
            "renderer": [["name": "sprite"]],
        ], to: directory.appendingPathComponent("particles/world-posaround.json"))
        let descriptor = SceneRenderDescriptor(
            layers: [layer(131, "particles/world-posaround.json")],
            renderOrderLayerIDs: [131],
            materialPasses: [
                .init(
                    materialPath: "materials/shared.json",
                    shaderPath: "genericparticle",
                    texturePaths: ["shared.png"],
                    blending: "additive"
                )
            ]
        )
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw HarnessError.noMetal
        }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: directory,
            device: device
        )
        let pointer = SIMD3<Double>(60, 40, 0)
        var batches: [SceneParticleDrawBatch] = []
        for _ in 0..<4 {
            batches = runtime.advance(
                by: 1.0 / 60.0,
                pointerLocalPositions: [131: pointer]
            )
        }
        let positions = (batches.first { $0.layerID == 131 })?.instances.map {
            [$0.positionAndSize.x, $0.positionAndSize.y, $0.positionAndSize.z]
        } ?? []
        return [
            "demandedLayerIDs": Array(runtime.pointerControlPointLayerIDs),
            "positions": positions,
            "diagnosticKinds": runtime.diagnostics.map(\.kind.rawValue),
        ]
    }

    private static func syntheticWorldSpacePointerForce() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-particle-worldspace-force-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 100, "flags": 1,
            "controlpoint": [
                ["id": 0, "flags": 0, "offset": "0 0 0"],
                ["id": 1, "flags": 1, "offset": "0 0 0"],
            ],
            "emitter": [[
                "name": "sphererandom", "rate": 120,
                "distancemin": 0, "distancemax": 0,
            ]],
            "initializer": [
                ["name": "lifetimerandom", "min": 10, "max": 10],
                ["name": "sizerandom", "min": 8, "max": 8],
            ],
            "operator": [
                ["name": "movement"],
                [
                    "name": "controlpointattract", "controlpoint": 1,
                    "scale": -10000, "threshold": 128,
                ],
            ],
            "renderer": [["name": "sprite"]],
        ], to: directory.appendingPathComponent("particles/world-force.json"))
        let descriptor = SceneRenderDescriptor(
            layers: [layer(121, "particles/world-force.json")],
            renderOrderLayerIDs: [121],
            materialPasses: [
                .init(
                    materialPath: "materials/shared.json",
                    shaderPath: "genericparticle",
                    texturePaths: ["shared.png"],
                    blending: "additive"
                )
            ]
        )
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw HarnessError.noMetal
        }
        func positionsAfterAdvances(pointer: SIMD3<Double>?) -> [[Float]] {
            let runtime = SceneParticleRuntime(
                descriptor: descriptor,
                cacheDirectory: directory,
                device: device
            )
            var batches: [SceneParticleDrawBatch] = []
            for _ in 0..<4 {
                batches = runtime.advance(
                    by: 1.0 / 60.0,
                    pointerLocalPositions: pointer.map { [121: $0] } ?? [:]
                )
            }
            return (batches.first { $0.layerID == 121 })?.instances.map {
                [$0.positionAndSize.x, $0.positionAndSize.y, $0.positionAndSize.z]
            } ?? []
        }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: directory,
            device: device
        )
        _ = runtime.advance(by: 1.0 / 60.0)
        let demand = Array(runtime.pointerControlPointLayerIDs)
        // Pointer at +X with a negative-scale attract: particles near the
        // origin accelerate away from the pointer (negative X).
        let withPointer = positionsAfterAdvances(pointer: SIMD3(60, 0, 0))
        let withoutPointer = positionsAfterAdvances(pointer: nil)
        return [
            "demandedLayerIDs": demand,
            "withPointerPositions": withPointer,
            "withoutPointerPositions": withoutPointer,
            "diagnosticKinds": runtime.diagnostics.map(\.kind.rawValue),
        ]
    }

    private static func syntheticWorldSpaceRopeTrail() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-particle-worldspace-rope-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 256, "flags": 1,
            "controlpoint": [["id": 0, "flags": 1, "offset": "0 0 0"]],
            "emitter": [[
                "name": "sphererandom", "rate": 120, "flags": 2,
                "distancemin": 0, "distancemax": 0,
            ]],
            "initializer": [
                ["name": "lifetimerandom", "min": 0.5, "max": 0.5],
                ["name": "sizerandom", "min": 8, "max": 8],
            ],
            "renderer": [["name": "rope", "flags": 1, "subdivision": 100]],
        ], to: directory.appendingPathComponent("particles/world-rope.json"))
        let descriptor = SceneRenderDescriptor(
            layers: [layer(111, "particles/world-rope.json")],
            renderOrderLayerIDs: [111],
            materialPasses: [
                .init(
                    materialPath: "materials/shared.json",
                    shaderPath: "genericparticle",
                    texturePaths: ["shared.png"],
                    blending: "additive"
                )
            ]
        )
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw HarnessError.noMetal
        }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: directory,
            device: device
        )
        // The trail is the birth history: hold the pointer at two positions
        // so particles cluster around both and the connecting rope has real
        // extent.
        var batches: [SceneParticleDrawBatch] = []
        for pointer in [SIMD3<Double>(40, 60, 0), SIMD3<Double>(240, 180, 0)] {
            for _ in 0..<6 {
                batches = runtime.advance(
                    by: 1.0 / 60.0,
                    pointerLocalPositions: [111: pointer]
                )
            }
        }
        let ropeInstances = (batches.first { $0.layerID == 111 })?.instances ?? []
        let positions = ropeInstances.prefix(4).map {
            [$0.positionAndSize.x, $0.positionAndSize.y, $0.positionAndSize.z]
        }
        return [
            "activeLayerIDs": runtime.activeLayerIDs,
            "instanceCount": ropeInstances.count,
            "firstPositions": positions,
            "demandedLayerIDs": Array(runtime.pointerControlPointLayerIDs),
            "diagnosticKinds": runtime.diagnostics.map(\.kind.rawValue),
            "ropeDiagnostic": runtime.diagnostics.contains {
                $0.kind == .ropeRendererUnsupported && $0.layerID == 111
            },
        ]
    }

    private static func syntheticAudioBoundsGate() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-particle-audio-bounds-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        func writeGatedParticle(_ path: String, mode: Int?) throws {
            var emitter: [String: Any] = [
                "name": "sphererandom", "rate": 120,
                "distancemin": 0, "distancemax": 0,
                "audioprocessingbounds": "0.8 1",
            ]
            if let mode { emitter["audioprocessingmode"] = mode }
            try writeJSON([
                "material": "materials/shared.json", "maxcount": 100,
                "emitter": [emitter],
                "initializer": [
                    ["name": "lifetimerandom", "min": 10, "max": 10],
                    ["name": "sizerandom", "min": 8, "max": 8],
                ],
                "renderer": [["name": "sprite"]],
            ], to: directory.appendingPathComponent(path))
        }
        try writeGatedParticle("particles/bounds-only.json", mode: nil)
        try writeGatedParticle("particles/mode-center.json", mode: 3)
        let descriptor = SceneRenderDescriptor(
            layers: [
                layer(101, "particles/bounds-only.json"),
                layer(102, "particles/mode-center.json"),
            ],
            renderOrderLayerIDs: [101, 102],
            materialPasses: [
                .init(
                    materialPath: "materials/shared.json",
                    shaderPath: "genericparticle",
                    texturePaths: ["shared.png"],
                    blending: "additive"
                )
            ]
        )
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw HarnessError.noMetal
        }
        func runtimeFor(_ path: String) -> SceneParticleRuntime {
            SceneParticleRuntime(
                descriptor: SceneRenderDescriptor(
                    layers: [layer(path == "particles/bounds-only.json" ? 101 : 102, path)],
                    renderOrderLayerIDs: [path == "particles/bounds-only.json" ? 101 : 102],
                    materialPasses: descriptor.materialPasses
                ),
                cacheDirectory: directory,
                device: device
            )
        }
        let loud = SceneParticleAudioInput(
            left: Array(repeating: 1, count: SceneParticleAudioInput.bandCount),
            right: Array(repeating: 1, count: SceneParticleAudioInput.bandCount),
            generation: 1
        )
        func counts(_ runtime: SceneParticleRuntime, audio: SceneParticleAudioInput) -> Int {
            var batches: [SceneParticleDrawBatch] = []
            for _ in 0..<4 {
                batches = runtime.advance(by: 1.0 / 60.0, audioInput: audio)
            }
            return batches.reduce(0) { $0 + $1.instances.count }
        }
        let boundsOnly = runtimeFor("particles/bounds-only.json")
        let silentCount = counts(boundsOnly, audio: .silent)
        let loudCount = counts(
            runtimeFor("particles/bounds-only.json"), audio: loud
        )
        let modeCenter = runtimeFor("particles/mode-center.json")
        let modeSilentCount = counts(modeCenter, audio: .silent)
        return [
            "boundsOnlySilentCount": silentCount,
            "boundsOnlyLoudCount": loudCount,
            "modeCenterSilentCount": modeSilentCount,
        ]
    }

    private static func syntheticWorldSpacePointerEmitter() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-particle-worldspace-pointer-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 100, "flags": 1,
            "controlpoint": [["id": 1, "flags": 1, "offset": "0 0 0"]],
            "emitter": [[
                "name": "sphererandom", "rate": 120, "controlpoint": 1,
                "distancemin": 0, "distancemax": 0,
            ]],
            "initializer": [
                ["name": "lifetimerandom", "min": 0.5, "max": 0.5],
                ["name": "sizerandom", "min": 8, "max": 8],
            ],
            "renderer": [["name": "sprite"]],
        ], to: directory.appendingPathComponent("particles/world-pointer.json"))
        let descriptor = SceneRenderDescriptor(
            layers: [layer(91, "particles/world-pointer.json")],
            renderOrderLayerIDs: [91],
            materialPasses: [
                .init(
                    materialPath: "materials/shared.json",
                    shaderPath: "genericparticle",
                    texturePaths: ["shared.png"],
                    blending: "additive"
                )
            ]
        )
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw HarnessError.noMetal
        }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: directory,
            device: device
        )
        let pointer = SIMD3<Double>(40, 60, 0)
        var batches: [SceneParticleDrawBatch] = []
        for _ in 0..<3 {
            batches = runtime.advance(
                by: 1.0 / 60.0,
                pointerLocalPositions: [91: pointer]
            )
        }
        let positions = (batches.first { $0.layerID == 91 })?.instances.map {
            [$0.positionAndSize.x, $0.positionAndSize.y, $0.positionAndSize.z]
        } ?? []
        return [
            "pointerDemandLayerIDs": Array(runtime.pointerControlPointLayerIDs),
            "positions": positions,
            "diagnosticKinds": runtime.diagnostics.map(\.kind.rawValue),
        ]
    }

    private static func snapshotWithTransformLane(layerID: Int) -> SceneDynamicSnapshot {
        let lane = SceneDynamicTarget.layer(layerID: layerID, field: .origin)
        return SceneDynamicSnapshotResolver().resolve(
            frameIndex: 1,
            generation: 1,
            definitions: [
                SceneDynamicTargetDefinition(
                    target: lane,
                    valueType: .vector3,
                    authoredValue: .vector3(0, 0, 0)
                ),
            ],
            timelineValues: [lane: .vector3(10, 0, 0)]
        ).snapshot
    }

    private static func syntheticWorldSpaceFreeze() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-particle-worldspace-freeze-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writeParticle(
            "particles/world-freeze.json",
            material: "materials/shared.json",
            flags: 1,
            velocityX: 120,
            lifetime: 2.0 / 60.0,
            moves: true,
            movementFlags: 1,
            rate: 120,
            under: directory
        )
        let descriptor = SceneRenderDescriptor(
            layers: [layer(71, "particles/world-freeze.json")],
            renderOrderLayerIDs: [71],
            materialPasses: [
                .init(
                    materialPath: "materials/shared.json",
                    shaderPath: "genericparticle",
                    texturePaths: ["shared.png"],
                    blending: "additive"
                )
            ]
        )
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw HarnessError.noMetal
        }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: directory,
            device: device
        )
        _ = runtime.advance(by: 1.0 / 60.0, dynamicValues: .empty(frameIndex: 0))
        let moving = runtime.advance(by: 1.0 / 60.0, dynamicValues: .empty(frameIndex: 1))
        let frozen = runtime.advance(by: 1.0 / 60.0, dynamicValues: snapshotWithTransformLane(layerID: 71))
        let frozenAgain = runtime.advance(by: 1.0 / 60.0, dynamicValues: snapshotWithTransformLane(layerID: 71))
        func positions(_ batches: [SceneParticleDrawBatch]) -> [[Float]] {
            (batches.first { $0.layerID == 71 })?.instances.map {
                [$0.positionAndSize.x, $0.positionAndSize.y, $0.positionAndSize.z]
            } ?? []
        }
        // Live-frame adoption: the same transform lane with the renderer's
        // current world frame keeps the system simulating through that frame.
        func liveRuntime(
            worldFrame: simd_float4x4
        ) -> (positions: [[Float]], followsCurrent: Bool, frozen: Bool) {
            let live = SceneParticleRuntime(
                descriptor: descriptor,
                cacheDirectory: directory,
                device: device
            )
            _ = live.advance(by: 1.0 / 60.0, dynamicValues: .empty(frameIndex: 0))
            var livePositions: [[Float]] = []
            for _ in 0..<3 {
                livePositions = positions(
                    live.advance(
                        by: 1.0 / 60.0,
                        dynamicValues: snapshotWithTransformLane(layerID: 71),
                        layerWorldFrames: [71: worldFrame]
                    )
                )
            }
            return (
                livePositions,
                live.diagnostics.contains {
                    $0.kind == .simulationLimitation
                        && $0.layerID == 71
                        && $0.detail == "world-space frame follows current transform"
                },
                live.diagnostics.contains {
                    $0.kind == .simulationLimitation
                        && $0.layerID == 71
                        && $0.detail == "world-space frame frozen after runtime transform write"
                }
            )
        }
        let liveIdentity = liveRuntime(
            worldFrame: matrix_identity_float4x4
        )
        let liveRotated = liveRuntime(
            worldFrame: simd_float4x4(columns: (
                SIMD4(0, 1, 0, 0), SIMD4(-1, 0, 0, 0),
                SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)
            ))
        )
        return [
            "movingLayerActive": moving.contains { $0.layerID == 71 },
            "movingPositions": positions(moving),
            "frozenPositions": positions(frozen),
            "frozenAgainPositions": positions(frozenAgain),
            "freezeDiagnostic": runtime.diagnostics.contains {
                $0.kind == .simulationLimitation
                    && $0.layerID == 71
                    && $0.detail == "world-space frame frozen after runtime transform write"
            },
            "diagnosticKinds": runtime.diagnostics.map(\.kind.rawValue),
            "liveIdentityPositions": liveIdentity.positions,
            "liveIdentityFollowsCurrent": liveIdentity.followsCurrent,
            "liveIdentityFrozen": liveIdentity.frozen,
            "liveRotatedPositions": liveRotated.positions,
            "liveRotatedFollowsCurrent": liveRotated.followsCurrent,
            "liveRotatedFrozen": liveRotated.frozen,
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
        var headY: [Float] = []
        var headSize: [Float] = []
        var trailY: [Float] = []
        var trailSize: [Float] = []
        var trailVelocityY: [Float] = []
        for batch in batches {
            if batch.particlePath.hasSuffix("matrix_code_copy1.json") {
                headCount += batch.instances.count
                headY.append(contentsOf: batch.instances.map(\.positionAndSize.y))
                headSize.append(contentsOf: batch.instances.map(\.positionAndSize.w))
            }
            if batch.particlePath.hasSuffix("matrix_trail_copy1.json") {
                trailCount += batch.instances.count
                trailBatchCount += 1
                trailY.append(contentsOf: batch.instances.map(\.positionAndSize.y))
                trailSize.append(contentsOf: batch.instances.map(\.positionAndSize.w))
                trailVelocityY.append(contentsOf: batch.instances.map(\.velocityAndTrail.y))
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
            "headYRange": [headY.min() ?? 0, headY.max() ?? 0],
            "headSizeRange": [headSize.min() ?? 0, headSize.max() ?? 0],
            "trailYRange": [trailY.min() ?? 0, trailY.max() ?? 0],
            "trailSizeRange": [trailSize.min() ?? 0, trailSize.max() ?? 0],
            "trailVelocityYRange": [trailVelocityY.min() ?? 0, trailVelocityY.max() ?? 0],
            "staticRejections": staticRejections.count,
            "activeLayerIDs": runtime.activeLayerIDs,
            "nestedBudgetDetails": runtime.diagnostics.compactMap { value in
                (value.detail ?? "").contains("nestedAggregateSystemBudget")
                    ? (value.detail ?? "") : nil
            },
        ]
    }

    private static func delayedChildren(edges: Bool = false) throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mwx-child-delay-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        let device = MTLCreateSystemDefaultDevice()!
        func make(_ trigger: String, continuous: Bool = false, duration: Double? = nil,
                  nested: Bool = false, warm: Double = 0, multiple: Bool = false,
                  delay: Any = 0.2, rate: Double = 60) throws -> SceneParticleRuntime {
            try writeParticle("particles/child.json", material: "materials/shared.json",
                lifetime: 0.1, startTime: warm, rate: continuous ? rate : 0,
                emitterDuration: duration, instantaneous: continuous ? nil : 1, under: directory)
            let url = directory.appendingPathComponent("particles/child.json")
            var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
            var emitters = json["emitter"] as! [[String: Any]]
            emitters[0]["delay"] = delay
            emitters[0]["origin"] = "30 0 0"
            if multiple { var early = emitters[0]; early["delay"] = 0; early["origin"] = "-30 0 0"; emitters.insert(early, at: 0) }
            json["emitter"] = emitters
            try writeJSON(json, to: url)
            let child: [String: Any] = ["name":"particles/child.json", "type":trigger]
            if nested {
                try writeParticle("particles/middle.json", material: "materials/shared.json",
                    lifetime: 0.05, rate: 0, instantaneous: 1, children: [child], under: directory)
            }
            try writeParticle("particles/root.json", material: "materials/shared.json",
                lifetime: trigger == "eventdeath" ? 0.05 : 1, rate: 0, instantaneous: 1,
                children: nested ? [["name":"particles/middle.json","type":"static"]] : [child], under: directory)
            return SceneParticleRuntime(descriptor: .init(layers: [layer(91,"particles/root.json",particleRate:1)],
                renderOrderLayerIDs:[91],materialPasses:[.init(materialPath:"materials/shared.json",
                    shaderPath:"genericparticle",texturePaths:["shared.png"],blending:"additive")]),
                cacheDirectory: directory,device:device)
        }
        func run(_ runtime: SceneParticleRuntime, pause: Bool = false) -> [String: Any] {
            let target=SceneDynamicTarget.particle(layerID:91,field:.rate)
            let zero=SceneDynamicSnapshotResolver().resolve(frameIndex:1,generation:1,
                definitions:[.init(target:target,valueType:.scalar,authoredValue:.scalar(1))],
                userValues:[target:.scalar(0)]).snapshot
            if pause { for _ in 0..<60 { _=runtime.advance(by:1.0/60,dynamicValues:zero) } }
            var nonempty:[Int]=[];var counts:[Int]=[];var states:[Int]=[];var retryEqual=true
            for step in 1...180 {
                let before=runtime.frameSnapshot()
                let batches=runtime.advance(by:1.0/60)
                let count=batches.filter{$0.particlePath=="particles/child.json"}.reduce(0){$0+$1.instances.count}
                do {
                    let expected=batches.filter{$0.particlePath=="particles/child.json"}.flatMap(\.instances).map{vector($0.positionAndSize)+vector($0.rotationAndAlpha)}
                    let expectedState=runtime.frameSnapshot().layers.first?.child
                    runtime.restoreFrame(before)
                    let replay=runtime.advance(by:1.0/60).filter{$0.particlePath=="particles/child.json"}.flatMap(\.instances).map{vector($0.positionAndSize)+vector($0.rotationAndAlpha)}
                    let replayState=runtime.frameSnapshot().layers.first?.child
                    retryEqual = retryEqual && expected == replay
                        && expectedState?.systems.map(\.id) == replayState?.systems.map(\.id)
                        && expectedState?.nextSystemID == replayState?.nextSystemID
                        && expectedState?.nextSeed == replayState?.nextSeed
                }
                if count>0 { nonempty.append(step) };counts.append(count)
                states.append(runtime.frameSnapshot().layers.first?.child?.systems.count ?? 0)
            }
            return ["nonemptyFrames":nonempty,"counts":counts,"systems":states,"retryEqual":retryEqual]
        }
        if edges {
            return ["negativeDelay":run(try make("static",delay: -1)),
                    "excessiveDelay":run(try make("eventspawn",delay: 3601)),
                    "malformedDelay":run(try make("static",delay: "invalid")),
                    "invalidFinite":run(try make("static",continuous:true,duration:0.1,delay: -1)),
                    "safePeer":run(try make("static",multiple:true,delay: -1)),
                    "tinyBurst":run(try make("static",duration:1e-13,delay:0)),
                    "tinyDelayedBurst":run(try make("static",duration:1e-13)),
                    "tinyDelayedRate":run(try make("static",continuous:true,duration:1e-13,rate:1e14))]
        }
        return ["staticBurst":run(try make("static")),
                "staticFinite":run(try make("static",continuous:true,duration:0.1)),
                "spawnBurst":run(try make("eventspawn")),
                "deathBurst":run(try make("eventdeath")),
                "followBurst":run(try make("eventfollow")),
                "spawnFinite":run(try make("eventspawn",continuous:true,duration:0.1)),
                "spawnLongFinite":run(try make("eventspawn",continuous:true,duration:0.4)),
                "spawnFallback":run(try make("eventspawn",continuous:true)),
                "nestedBurst":run(try make("eventspawn",nested:true)),
                "multipleBurst":run(try make("static",multiple:true)),
                "prewarmBurst":run(try make("static",warm:0.25)),
                "pausedBurst":run(try make("static"),pause:true)]
    }

    private static func realContinuousProfiles(cachePath: String) throws -> [String: Any] {
        let root = URL(fileURLWithPath: cachePath, isDirectory: true)
        let parser = SceneParticleDefinitionParser()
        var supported: [String: Bool] = [:]
        var completed: [String: Bool] = [:]
        var rates: [String: Double] = [:]
        var instantaneous: [String: Int] = [:]
        for name in ["Flare_Flame", "Flare_Smoke", "Flare_Sparks"] {
            let definition = try parser.parse(
                data: Data(contentsOf: root.appendingPathComponent("\(name).json"))
            )
            supported[name] = SceneParticleChildLifecycle.supportsEmitterProfile(definition)
            let simulator = SceneParticleSimulator(definition: definition, seed: 17)
            simulator.advance(by: 3)
            completed[name] = simulator.hasFinishedEmission
            rates[name] = definition.emitters.first?.rate ?? -1
            instantaneous[name] = definition.emitters.first?.instantaneousCount ?? 0
        }
        return [
            "supported": supported,
            "completed": completed,
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
            "sizeIsWorldSpace": coarseBatch?.sizeIsWorldSpace ?? false,
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

    private static func syntheticRope() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-rope-runtime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writeAnimatedTEX(directory.appendingPathComponent("materials/animated.tex"))
        try writeParticle(
            "particles/rope.json",
            material: "materials/shared.json",
            renderer: "rope",
            velocityX: 100,
            moves: true,
            rate: 5,
            under: directory
        )
        try writeParticle(
            "particles/rope-animated.json",
            material: "materials/animated.json",
            renderer: "rope",
            velocityX: 100,
            moves: true,
            rate: 5,
            under: directory
        )
        try writeParticle(
            "particles/rope-mixed.json",
            material: "materials/shared.json",
            renderer: "rope",
            additionalRenderers: [["name": "sprite"]],
            velocityX: 100,
            moves: true,
            rate: 5,
            under: directory
        )
        try writeParticle(
            "particles/rope-world.json",
            material: "materials/shared.json",
            renderer: "rope",
            rendererFlags: 1,
            velocityX: 100,
            moves: true,
            rate: 5,
            under: directory
        )
        try writeJSON([
            "material": "materials/shared.json",
            "maxcount": 100,
            "emitter": [[
                "name": "sphererandom", "rate": 5,
                "distancemin": 0, "distancemax": 0,
                "flags": 2,
            ]],
            "initializer": [
                ["name": "lifetimerandom", "min": 10, "max": 10],
                ["name": "sizerandom", "min": 8, "max": 8],
                ["name": "velocityrandom", "min": [100, 0, 0], "max": [100, 0, 0]],
            ],
            "operator": [["name": "movement"]],
            "renderer": [["name": "rope", "subdivision": 1]],
        ], to: directory.appendingPathComponent("particles/rope-subdivision.json"))
        try writeJSON([
            "material": "materials/shared.json",
            "maxcount": 100,
            "emitter": [["name": "sphererandom", "rate": 5]],
            "initializer": [
                ["name": "lifetimerandom", "min": 10, "max": 10],
                ["name": "sizerandom", "min": 8, "max": 8],
                ["name": "velocityrandom", "min": [100, 0, 0], "max": [100, 0, 0]],
            ],
            "operator": [["name": "movement"]],
            "renderer": [["name": "rope", "uvscale": 2, "uvscrolling": true]],
        ], to: directory.appendingPathComponent("particles/rope-scroll.json"))
        try writeJSON([
            "material": "materials/shared.json",
            "maxcount": 100,
            "emitter": [["name": "sphererandom", "rate": 5]],
            "initializer": [
                ["name": "lifetimerandom", "min": 10, "max": 10],
                ["name": "sizerandom", "min": 8, "max": 8],
            ],
            "renderer": [["name": "rope", "uvscale": -1]],
        ], to: directory.appendingPathComponent("particles/rope-invalid.json"))
        try writeJSON([
            "material": "materials/shared.json",
            "maxcount": 20,
            "controlpoint": [
                ["id": 0, "parentcontrolpoint": 1],
                ["id": 1, "parentcontrolpoint": 2],
            ],
            "emitter": [[
                "name": "sphererandom", "rate": 5,
                "distancemin": 0, "distancemax": 0,
                "flags": 2,
            ]],
            "initializer": [
                ["name": "lifetimerandom", "min": 10, "max": 10],
                ["name": "sizerandom", "min": 8, "max": 8],
                ["name": "velocityrandom", "min": [50, 20, 0], "max": [50, 20, 0]],
            ],
            "operator": [["name": "movement"]],
            "renderer": [[
                "name": "rope", "subdivision": 1, "uvscale": 2,
                "uvscrolling": true, "uvsmoothing": false,
            ]],
        ], to: directory.appendingPathComponent("particles/rope-child.json"))
        try writeParticle(
            "particles/rope-parent.json",
            material: "materials/shared.json",
            children: [["name": "particles/rope-child.json", "origin": [40, 20, 0]]],
            under: directory
        )
        let descriptor = SceneRenderDescriptor(
            layers: [
                layer(41, "particles/rope.json"),
                layer(42, "particles/rope-animated.json"),
                layer(43, "particles/rope-mixed.json"),
                layer(44, "particles/rope-world.json"),
                layer(45, "particles/rope-subdivision.json"),
                layer(46, "particles/rope-scroll.json"),
                layer(47, "particles/rope-invalid.json"),
                layer(48, "particles/rope-parent.json"),
            ],
            renderOrderLayerIDs: [41, 42, 43, 44, 45, 46, 47, 48],
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
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: directory,
            device: device
        )
        var batches: [SceneParticleDrawBatch] = []
        for _ in 0..<90 {
            batches = runtime.advance(by: 1.0 / 60.0)
        }
        let batch = batches.first { $0.layerID == 41 }
        let subdivisionBatch = batches.first { $0.layerID == 45 }
        let scrollingBatch = batches.first { $0.layerID == 46 }
        let childBatch = batches.first { $0.particlePath == "particles/rope-child.json" }
        let instances = batch?.instances ?? []
        let diagnosticDetails = runtime.diagnostics.map {
            "\($0.kind.rawValue):\($0.layerID ?? -1):\($0.detail ?? "")"
        }
        return [
            "activeLayerIDs": runtime.activeLayerIDs,
            "instanceCount": instances.count,
            "bufferMatches": batch?.instanceBuffer.count == instances.count,
            "orientationScreen": batch?.orientation == .screen,
            "usesPerspective": batch?.usesPerspective ?? true,
            "allSegmentsNonzero": instances.allSatisfy {
                simd_length(SIMD3(
                    $0.velocityAndTrail.x,
                    $0.velocityAndTrail.y,
                    $0.velocityAndTrail.z
                )) > 0.0001
                    && $0.velocityAndTrail.w > 0
            },
            "uvStartsAtZero": instances.first?.frame0B.z == 0,
            "uvEndsAtOne": instances.last?.frame0B.w == 1,
            "uvContinuous": zip(instances, instances.dropFirst()).allSatisfy {
                abs($0.0.frame0B.w - $0.1.frame0B.z) < 0.0001
            },
            "usesDisplacement": instances.allSatisfy { $0.frame1B.z == 1 },
            // WE rope default subdivision is 3 (4 sub-segments per node
            // pair); the authored subdivision-1 fixture halves that density.
            "subdivisionHalvesDefaultDensity": subdivisionBatch?.instances.count
                == instances.count / 2,
            "scrollUVStart": scrollingBatch?.instances.first?.frame0B.z ?? -1,
            "scrollUVEnd": scrollingBatch?.instances.last?.frame0B.w ?? -1,
            "childRopeCount": childBatch?.instances.count ?? 0,
            "childRopeUsesSubdivision": (childBatch?.instances.count ?? 0) % 2 == 0,
            "childRopeTranslated": childBatch?.instances.allSatisfy {
                $0.positionAndSize.x >= 40 && $0.positionAndSize.y >= 20
            } ?? false,
            "childRopeUVStartsWithPhase": (childBatch?.instances.first?.frame0B.z ?? 0) > 0,
            "diagnosticDetails": diagnosticDetails,
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



    private static func syntheticChildFloatSafety() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-child-float-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        try writeParticle("particles/child.json", material: "materials/shared.json",
            rate: 60, under: directory)
        try writeParticle("particles/root.json", material: "materials/shared.json",
            flags: 248, rate: 60, children: [["name": "particles/child.json",
                "type": "static", "scale": "1024 1024 1"]], under: directory)
        let runtime = SceneParticleRuntime(descriptor: .init(
            layers: [layer(91, "particles/root.json", particleSize: 1)],
            renderOrderLayerIDs: [91], materialPasses: [.init(
                materialPath: "materials/shared.json", shaderPath: "genericparticle",
                texturePaths: ["shared.png"], blending: "additive")]),
            cacheDirectory: directory, device: device)
        let target = SceneDynamicTarget.particle(layerID: 91, field: .size)
        let dynamic = SceneDynamicSnapshotResolver().resolve(frameIndex: 1, generation: 1,
            definitions: [.init(target: target, valueType: .scalar, authoredValue: .scalar(1))],
            userValues: [target: .scalar(1e35)]).snapshot
        _ = runtime.advance(by: 1.0 / 60)
        let batches = runtime.advance(by: 1.0 / 60, dynamicValues: dynamic)
        let child = batches.first { $0.particlePath == "particles/child.json" }!
        let unsafeCount = child.instances.filter { !$0.positionAndSize.w.isFinite }.count
        let rootCount = batches.first { $0.particlePath == "particles/root.json" }!.instanceBuffer.count
        let safeCount = child.instanceBuffer.count
        let uploaded = child.instanceBuffer.buffer!.contents()
            .bindMemory(to: SceneParticleGPUInstance.self, capacity: safeCount)
        let finite = (0..<safeCount).allSatisfy { uploaded[$0].positionAndSize.w.isFinite }
        let next = runtime.advance(by: 1.0 / 60)
        let recovered = next.first { $0.particlePath == "particles/child.json" }!.instanceBuffer.count
        // Exercise every final ABI lane, with valid peers on either side.
        let peer = SceneParticleGPUInstance(position: .zero, size: 8, rotation: .zero,
            color: SIMD3(repeating: 1), alpha: 1)
        let buffer = SceneParticleMetalInstanceBuffer()
        var following = peer; following.positionAndSize.x = 7
        var rejected = 0
        for lane in 0..<40 {
            var invalid = peer
            withUnsafeMutableBytes(of: &invalid) { bytes in
                bytes.bindMemory(to: Float.self)[lane] = lane % 2 == 0 ? .infinity : .nan
            }
            _ = buffer.update(device: device, instances: [peer, invalid, following])
            let records = buffer.buffer!.contents()
                .bindMemory(to: SceneParticleGPUInstance.self, capacity: 3)
            if buffer.count == 2 && records[0].positionAndSize.x == 0
                && records[1].positionAndSize.x == 7 { rejected += 1 }
        }
        var invalid = peer; invalid.positionAndSize.x = .infinity
        _ = buffer.update(device: device, instances: [invalid])
        let emptyDraw = buffer.currentDrawState() == nil
        _ = buffer.update(device: device, instances: [peer])
        return ["unsafeAssembled": unsafeCount, "uploadedCount": safeCount,
            "uploadedFinite": finite, "rootCount": rootCount, "recoveredCount": recovered,
            "rejectedLanes": rejected, "emptyDraw": emptyDraw, "recoveredBuffer": buffer.count]
    }

    private static func syntheticChildInstanceOverride() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-child-modifiers-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let alpha = SceneDynamicTarget.particle(layerID: 91, field: .alpha)
        let size = SceneDynamicTarget.particle(layerID: 91, field: .size)
        let count = SceneDynamicTarget.particle(layerID: 91, field: .count)
        let rate = SceneDynamicTarget.particle(layerID: 91, field: .rate)
        let lifetime = SceneDynamicTarget.particle(layerID: 91, field: .lifetime)
        let speed = SceneDynamicTarget.particle(layerID: 91, field: .speed)
        let brightness = SceneDynamicTarget.particle(layerID: 91, field: .brightness)
        let color = SceneDynamicTarget.particle(layerID: 91, field: .normalizedColor)
        let values: [SceneDynamicTarget: SceneDynamicValue] = [alpha: .scalar(0.25),
            size: .scalar(3), count: .scalar(2), rate: .scalar(0.5), lifetime: .scalar(2),
            speed: .scalar(3), brightness: .scalar(0.5), color: .vector3(0.5, 1, 0.25)]
        let definitions = values.keys.map { target in
            SceneDynamicTargetDefinition(target: target,
                valueType: target == color ? .vector3 : .scalar,
                authoredValue: target == color ? .vector3(1, 1, 1) : .scalar(1))
        }
        let dynamic = SceneDynamicSnapshotResolver().resolve(frameIndex: 1, generation: 1,
            definitions: definitions, userValues: values).snapshot
        func child(_ path: String, _ trigger: String = "static") -> [String: Any] {
            ["name": "particles/\(path).json", "type": trigger]
        }
        func make(_ trigger: String = "static", flags: Int = 0, warm: Bool = false,
                  nested: Bool = false, container: Bool = false, continuous: Bool = false,
                  initial: SceneDynamicSnapshot = .empty(frameIndex: 0)) throws -> SceneParticleRuntime {
            try writeParticle("particles/child.json", material: "materials/shared.json",
                flags: flags, velocityX: 2, lifetime: 10, startTime: warm ? 0.1 : 0,
                rate: continuous ? 60 : 0, instantaneous: continuous ? 0 : 2, under: directory)
            if nested {
                try writeParticle("particles/middle.json", material: "materials/shared.json",
                    lifetime: trigger == "eventdeath" ? 1.0 / 60 : 10,
                    rate: 0, instantaneous: 1, children: [child("child", trigger)], under: directory)
            }
            try writeParticle("particles/root.json", material: "materials/shared.json",
                flags: 248, lifetime: trigger == "eventdeath" ? 1.0 / 60 : 10,
                rate: 0, instantaneous: 1,
                children: [child(nested ? "middle" : "child", nested ? "static" : trigger)], under: directory)
            if container {
                let url = directory.appendingPathComponent("particles/root.json")
                var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
                json["renderer"] = []; json["emitter"] = []; json["initializer"] = []
                try writeJSON(json, to: url)
            }
            return SceneParticleRuntime(descriptor: .init(layers: [layer(91, "particles/root.json",
                particleAlpha: 0.4, particleSize: 2, particleLifetime: 1.5, particleRate: 1,
                particleCount: 1, particleNormalizedColor: SIMD3(1, 0.5, 1))],
                renderOrderLayerIDs: [91], materialPasses: [.init(
                    materialPath: "materials/shared.json", shaderPath: "genericparticle",
                    texturePaths: ["shared.png"], blending: "additive")]),
                cacheDirectory: directory, device: device, initialDynamicValues: initial)
        }
        func observe(_ runtime: SceneParticleRuntime, _ batches: [SceneParticleDrawBatch]) -> [String: Any] {
            let instances = batches.filter { $0.particlePath == "particles/child.json" }.flatMap(\.instances)
            let systems = runtime.frameSnapshot().layers.first?.child?.systems ?? []
            let system = systems.last
            let particle = system?.simulator.particles.first
            let item = instances.first
            return ["count": instances.count, "alpha": item?.rotationAndAlpha.w ?? -1,
                "size": item?.positionAndSize.w ?? -1,
                "color": item.map { [$0.colorAndFrameMix.x, $0.colorAndFrameMix.y, $0.colorAndFrameMix.z] } ?? [],
                "lifetime": particle?.lifetime ?? -1, "velocity": particle?.velocity.x ?? -1,
                "simulationTime": system?.simulator.simulationTime ?? -1]
        }
        var result: [String: Any] = [:]
        for (name, flags) in [("static", 0), ("disabled", 248)] {
            let runtime = try make(flags: flags)
            result[name] = observe(runtime, runtime.advance(by: 0.1))
            let replay = try make(flags: flags)
            let saved = replay.frameSnapshot()
            let batches = replay.advance(by: 0.1, dynamicValues: dynamic)
            let output = observe(replay, batches)
            result[name + "Dynamic"] = output
            replay.restoreFrame(saved)
            let retry = observe(replay, replay.advance(by: 0.1, dynamicValues: dynamic))
            result[name + "RetryEqual"] = NSDictionary(dictionary: output).isEqual(to: retry)
            replay.restoreFrame(saved)
            result[name + "Fallback"] = observe(replay, replay.advance(by: 0.1))
        }
        for flags in [0, 248] {
            let continuous = try make(flags: flags, continuous: true)
            result["continuous" + String(flags)] = observe(continuous,
                continuous.advance(by: 0.1, dynamicValues: dynamic))
        }
        let warm = try make(warm: true, initial: dynamic)
        result["prewarm"] = observe(warm, warm.advance(by: 0, dynamicValues: dynamic))
        let container = try make(container: true)
        result["container"] = observe(container, container.advance(by: 0.1, dynamicValues: dynamic))
        for trigger in ["eventspawn", "eventdeath", "eventfollow"] {
            for nested in [false, true] {
                let runtime = try make(trigger, warm: true, nested: nested)
                var batches: [SceneParticleDrawBatch] = []
                for _ in 0..<6 { batches = runtime.advance(by: 1.0 / 60, dynamicValues: dynamic) }
                result[trigger + (nested ? "Nested" : "")] = observe(runtime, batches)
            }
        }
        return result
    }

    private static func syntheticLayerAlpha() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mwx-layer-alpha-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writeParticle("particles/child.json", material: "materials/shared.json",
            startTime: 0.1, rate: 0, instantaneous: 1, under: directory)
        try writeParticle("particles/root.json", material: "materials/shared.json",
            startTime: 0.1, rate: 0, instantaneous: 1,
            children: [["name": "particles/child.json", "type": "static"]], under: directory)
        let descriptor = SceneRenderDescriptor(
            layers: [layer(91, "particles/root.json", particleAlpha: 0.5, layerAlpha: 0.4)],
            renderOrderLayerIDs: [91], materialPasses: [.init(
                materialPath: "materials/shared.json", shaderPath: "genericparticle",
                texturePaths: ["shared.png"], blending: "additive")])
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let runtime = SceneParticleRuntime(descriptor: descriptor, cacheDirectory: directory, device: device)
        let target = SceneDynamicTarget.layer(layerID: 91, field: .alpha)
        let resolver = SceneDynamicSnapshotResolver()
        func snapshot(_ alpha: Double) -> SceneDynamicSnapshot {
            resolver.resolve(frameIndex: 1, generation: 1,
                definitions: [.init(target: target, valueType: .scalar, authoredValue: .scalar(0.4))],
                userValues: [target: .scalar(alpha)]).snapshot
        }
        func values(_ batches: [SceneParticleDrawBatch]) -> [Float] {
            batches.flatMap { $0.instances.map { $0.rotationAndAlpha.w } }
        }
        let initial = runtime.advance(by: 0.1)
        let changed = runtime.advance(by: 0, dynamicValues: snapshot(0.8))
        let hidden = runtime.advance(by: 0, dynamicValues: snapshot(0))
        let recovered = runtime.advance(by: 0, dynamicValues: snapshot(1))
        let fallback = runtime.advance(by: 0)
        guard let playback = SceneParticlePlaybackState(
            descriptor: descriptor, cacheDirectory: directory, device: device,
            initialDynamicValues: snapshot(0.8)) else { throw HarnessError.noParticlePipeline }
        let startup = values(playback.batches)
        playback.prepareFrame()
        let rejected = values(playback.advance(by: 0, dynamicValues: snapshot(0)))
        playback.discardPreparedFrame()
        let restored = values(playback.batches)
        playback.prepareFrame()
        let retry = values(playback.advance(by: 0, dynamicValues: snapshot(0.5)))
        playback.commitPreparedFrame()
        return ["startup": startup, "rejected": rejected, "restored": restored, "retry": retry,
            "initial": values(initial), "changed": values(changed),
            "hidden": values(hidden), "recovered": values(recovered), "fallback": values(fallback),
            "positionsUnchanged": initial.flatMap(\.instances).map(\.positionAndSize)
                == recovered.flatMap(\.instances).map(\.positionAndSize),
            "rootParticles": runtime.lifecycleSnapshot.rootParticleCount,
            "childParticles": runtime.lifecycleSnapshot.childParticleCount]
    }

    private static func syntheticDynamicInstanceOverride() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-particle-dynamic-override-\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writeParticle(
            "particles/live-override.json", material: "materials/shared.json",
            lifetime: 10, rate: 4, under: directory
        )
        let descriptor = SceneRenderDescriptor(
            layers: [layer(
                91, "particles/live-override.json", particleAlpha: 0,
                particleSize: 1, particleCount: 1,
                particleNormalizedColor: SIMD3(1, 1, 1), alphaHasUser: true
            )],
            renderOrderLayerIDs: [91],
            materialPasses: [.init(
                materialPath: "materials/shared.json", shaderPath: "genericparticle",
                texturePaths: ["shared.png"], blending: "additive"
            )]
        )
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor, cacheDirectory: directory, device: device
        )
        let alpha = SceneDynamicTarget.particle(layerID: 91, field: .alpha)
        let size = SceneDynamicTarget.particle(layerID: 91, field: .size)
        let count = SceneDynamicTarget.particle(layerID: 91, field: .count)
        let color = SceneDynamicTarget.particle(layerID: 91, field: .normalizedColor)
        let definitions = [
            SceneDynamicTargetDefinition(target: alpha, valueType: .scalar, authoredValue: .scalar(0)),
            .init(target: size, valueType: .scalar, authoredValue: .scalar(1)),
            .init(target: count, valueType: .scalar, authoredValue: .scalar(1)),
            .init(target: color, valueType: .vector3, authoredValue: .vector3(1, 1, 1)),
        ]
        let resolver = SceneDynamicSnapshotResolver()
        func snapshot(_ values: [SceneDynamicTarget: SceneDynamicValue]) -> SceneDynamicSnapshot {
            resolver.resolve(
                frameIndex: 1, generation: 1, definitions: definitions, userValues: values
            ).snapshot
        }
        let zero = runtime.advance(by: 0.25, dynamicValues: snapshot([count: .scalar(0)]))
        let dynamic = runtime.advance(by: 0.25, dynamicValues: snapshot([
            alpha: .scalar(0.25), size: .scalar(3), count: .scalar(2),
            color: .vector3(0.5, 1, 0.25),
        ]))
        let fallback = runtime.advance(by: 0.25)
        let dynamicParticle = dynamic.first?.instances.first
        let fallbackParticle = fallback.first?.instances.last
        return [
            "zeroCount": zero.first?.instances.count ?? 0,
            "dynamicCount": dynamic.first?.instances.count ?? 0,
            "dynamicAlpha": dynamicParticle?.rotationAndAlpha.w ?? -1,
            "dynamicSize": dynamicParticle?.positionAndSize.w ?? -1,
            "dynamicColor": dynamicParticle.map {
                [$0.colorAndFrameMix.x, $0.colorAndFrameMix.y, $0.colorAndFrameMix.z]
            } ?? [],
            "fallbackCount": fallback.first?.instances.count ?? 0,
            "fallbackAlpha": fallbackParticle?.rotationAndAlpha.w ?? -1,
            "fallbackSize": fallbackParticle?.positionAndSize.w ?? -1,
            "fallbackColor": fallbackParticle.map {
                [$0.colorAndFrameMix.x, $0.colorAndFrameMix.y, $0.colorAndFrameMix.z]
            } ?? [],
        ]
    }

    private static func syntheticSpriteGeometry() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-sprite-geometry-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func texture(_ name: String, embedded: Bool, atlas: Bool = false) throws {
            var rgba = [UInt8](repeating: 0, count: 8 * 8 * 4)
            for y in 0..<8 { for x in 0..<2 { for c in 0..<4 { rgba[(y * 8 + x) * 4 + c] = 255 } } }
            var payload = Data(rgba)
            if embedded {
                let encoded = NSMutableData()
                guard let provider = CGDataProvider(data: payload as CFData),
                      let image = CGImage(width: 8, height: 8, bitsPerComponent: 8, bitsPerPixel: 32,
                          bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                          provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
                      let destination = CGImageDestinationCreateWithData(encoded, "public.png" as CFString, 1, nil)
                else { throw HarnessError.imageWrite }
                CGImageDestinationAddImage(destination, image, nil)
                guard CGImageDestinationFinalize(destination) else { throw HarnessError.imageWrite }
                payload = encoded as Data
            }
            var data = Data("TEXV0005\0TEXI0001\0".utf8)
            for value: UInt32 in [0, atlas ? 7 : 3, 8, 8, 2, 8, 0] { appendUInt32(value, to: &data) }
            data.append(Data((embedded ? "TEXB0003\0" : "TEXB0002\0").utf8))
            appendUInt32(1, to: &data)
            if embedded { appendUInt32(13, to: &data) }
            for value: UInt32 in [1, 8, 8, 0, 0, UInt32(payload.count)] { appendUInt32(value, to: &data) }
            data.append(payload)
            if atlas {
                data.append(Data("TEXS0002\0".utf8)); appendUInt32(1, to: &data)
                appendUInt32(0, to: &data); appendFloat32(1, to: &data)
                for value: Float in [0, 0, 2, 0, 0, 8] { appendFloat32(value, to: &data) }
            }
            let url = directory.appendingPathComponent("materials/\(name).tex")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        try texture("raw", embedded: false)
        try texture("embedded", embedded: true)
        try texture("atlas", embedded: false, atlas: true)
        let names = ["raw", "embedded", "atlas", "refract"]
        var layers: [SceneRenderDescriptor.Layer] = []
        var materials: [SceneRenderDescriptor.MaterialPassDescriptor] = []
        for (index, name) in names.enumerated() {
            let material = "materials/\(name).json"
            try writeParticle("particles/\(name).json", material: material,
                instantaneous: 1, children: name == "raw" ? [[
                    "name": "particles/child.json", "type": "static"
                ], ["name": "particles/child-refract.json", "type": "static"]] : [], under: directory)
            layers.append(layer(index + 1, "particles/\(name).json"))
            materials.append(.init(materialPath: material, shaderPath: "genericparticle",
                texturePaths: ["materials/\(name == "refract" ? "raw" : name).tex"],
                blending: "translucent", combos: name == "refract" ? ["REFRACT": 1] : [:]))
        }
        try writeParticle("particles/child.json", material: "materials/embedded.json",
            instantaneous: 1, under: directory)
        try writeParticle("particles/child-refract.json", material: "materials/refract.json",
            instantaneous: 1, under: directory)
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let runtime = SceneParticleRuntime(descriptor: .init(layers: layers,
            renderOrderLayerIDs: [1, 2, 3, 4], materialPasses: materials),
            cacheDirectory: directory, device: device)
        let batches = runtime.advance(by: 1.0 / 60.0)
        var result: [String: Any] = [:]
        for batch in batches {
            guard let instance = batch.instances.first else { continue }
            let name = URL(fileURLWithPath: batch.particlePath).deletingPathExtension().lastPathComponent
            result[name] = [
                "aspect": [instance.frame0B.z, instance.frame0B.w],
                "uvScale": [batch.colorUVScale.x, batch.colorUVScale.y],
                "textureSize": [batch.texture.width, batch.texture.height],
                "pixels": spriteBatchBounds(batch, device: device)
            ]
        }
        result["active"] = runtime.activeLayerIDs
        return result
    }

    private static func spriteBatchBounds(_ batch: SceneParticleDrawBatch, device: MTLDevice) -> [Int] {
        let size = 64
        guard let pipeline = SceneParticleMetalPipeline(device: device),
              let command = device.makeCommandQueue()?.makeCommandBuffer() else { return [] }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: size, height: size, mipmapped: false)
        descriptor.usage = .renderTarget; descriptor.storageMode = .shared
        guard let output = device.makeTexture(descriptor: descriptor) else { return [] }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return [] }
        pipeline.draw(texture: batch.texture, instances: batch.instanceBuffer,
            uniforms: SceneParticleLayerUniforms(viewProjection: simd_float4x4(diagonal: SIMD4(1.0 / 32, 1.0 / 32, 1, 1)),
                layerModel: matrix_identity_float4x4, basis: .init(right: SIMD3(1, 0, 0), up: SIMD3(0, 1, 0))),
            renderState: batch.renderState, colorUVScale: batch.colorUVScale,
            colorSampling: batch.colorSampling, encoder: encoder)
        encoder.endEncoding()
        guard batch.instanceBuffer.markSubmitted(on: command) else { return [] }
        command.commit(); command.waitUntilCompleted()
        guard command.status == .completed else { return [] }
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        output.getBytes(&bytes, bytesPerRow: size * 4, from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
        let lit = (0..<(size * size)).filter { bytes[$0 * 4 + 3] > 127 }
        let xs = lit.map { $0 % size }, ys = lit.map { $0 / size }
        return [(xs.max() ?? -1) - (xs.min() ?? 0) + 1,
                (ys.max() ?? -1) - (ys.min() ?? 0) + 1,
                (xs.max() ?? -1) + (xs.min() ?? 0), (ys.max() ?? -1) + (ys.min() ?? 0)]
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
            "particles/default-trail.json", material: "materials/shared.json",
            renderer: "spritetrail", rendererMaximumLength: 2,
            velocityX: 100, under: directory
        )
        try writeParticle(
            "particles/malformed-trail.json", material: "materials/shared.json",
            renderer: "spritetrail", rendererLength: "invalid",
            velocityX: 100, under: directory
        )
        try writeParticle(
            "particles/child-root.json", material: "materials/shared.json",
            children: [
                ["name": "particles/child.json", "type": "eventspawn", "maxcount": 500],
                ["name": "particles/trail-child.json", "type": "eventspawn", "maxcount": 500],
            ], under: directory
        )
        try writeParticle(
            "particles/child.json", material: "materials/normal-cull.json",
            rate: 0, instantaneous: 1, under: directory
        )
        try writeParticle(
            "particles/trail-child.json", material: "materials/shared.json",
            renderer: "spritetrail", rendererMaximumLength: 2,
            velocityX: 100, rate: 0, instantaneous: 1, under: directory
        )
        try writeParticle(
            "particles/unsupported-child-root.json", material: "materials/shared.json",
            children: [
                ["name": "particles/child.json", "type": "static"],
                ["name": "particles/child.json"],
                ["name": "particles/origin-child.json", "type": "static", "origin": "1 2 3"],
                ["name": "particles/angles-child.json", "type": "static", "angles": "1 0 0"],
                ["name": "particles/scale-child.json", "type": "static", "scale": "2 2 2"],
                ["name": "particles/zero-scale-child.json", "type": "static", "scale": "0 0 1"],
                ["name": "particles/negative-scale-child.json", "type": "static", "scale": "-1 -1 1"],
                ["name": "particles/nonuniform-scale-child.json", "type": "static", "scale": "2 3 1"],
                ["name": "particles/huge-scale-child.json", "type": "static", "scale": "2048 2048 1"],
                ["name": "particles/malformed-scale-child.json", "type": "static", "scale": "invalid"],
                ["name": "particles/event-origin-child.json", "type": "eventspawn", "origin": "1 2 3"],
                ["name": "particles/nan-origin-child.json", "type": "static", "origin": "nan 0 0"],
                ["name": "particles/probability-child.json", "type": "static", "probability": 0.5],
                ["name": "particles/custom-shader.json", "type": "static"],
            ], under: directory
        )
        for path in [
            "particles/origin-child.json", "particles/angles-child.json",
            "particles/event-origin-child.json",
            "particles/nan-origin-child.json", "particles/probability-child.json",
        ] {
            try writeParticle(
                path, material: "materials/shared.json", rate: 0, instantaneous: 1,
                under: directory
            )
        try writeParticle(
            "particles/scale-child.json", material: "materials/shared.json",
            velocityX: 4, moves: true, rate: 0, instantaneous: 1, under: directory
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
                layer(19, "particles/default-trail.json"),
                layer(20, "particles/malformed-trail.json"),
            ],
            renderOrderLayerIDs: Array(1 ... 20),
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
            "scaledStaticInstance": batches.first {
                $0.layerID == 9 && $0.particlePath == "particles/scale-child.json"
            }?.instances.first.map {
                [
                    "position": [$0.positionAndSize.x, $0.positionAndSize.y, $0.positionAndSize.z],
                    "size": [$0.positionAndSize.w],
                    "velocity": [$0.velocityAndTrail.x, $0.velocityAndTrail.y, $0.velocityAndTrail.z],
                ]
            } ?? [:],
            "staticChildScaleBounded": runtime.diagnostics.contains {
                $0.layerID == 9
                    && $0.detail == "particles/scale-child.json:childScaleBounded:scale=2.0,2.0,2.0"
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
            "defaultTrailStretch": batches.first(where: { $0.layerID == 19 })?
                .instances.first?.velocityAndTrail.w ?? -1,
            "childTrailStretch": batches.first {
                $0.particlePath == "particles/trail-child.json"
            }?.instances.first?.velocityAndTrail.w ?? -1,
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

    private static func syntheticBatchEvidence() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-particle-evidence-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writeParticle("particles/burst.json", material: "materials/shared.json",
                          lifetime: 0.05, rate: 60, emitterDuration: 0.034, under: directory)
        try writeParticle("particles/dormant.json", material: "materials/shared.json",
                          rate: 0, under: directory)
        let descriptor = SceneRenderDescriptor(
            layers: [layer(200, "particles/burst.json"), layer(201, "particles/dormant.json")],
            renderOrderLayerIDs: [200, 201],
            materialPasses: [.init(materialPath: "materials/shared.json",
                shaderPath: "genericparticle", texturePaths: ["shared.png"], blending: "additive")]
        )
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        guard let playback = SceneParticlePlaybackState(
            descriptor: descriptor, cacheDirectory: directory, device: device
        ) else { throw HarnessError.noParticlePipeline }
        let initial = playback.loadReportLines(descriptor: descriptor)
        playback.prepareFrame()
        let rejected = playback.advance(by: 1.0 / 30.0)
        let beforeCommit = playback.committedNonemptyBatchLayerIDs.sorted()
        playback.discardPreparedFrame()
        let discarded = playback.loadReportLines(descriptor: descriptor)
        // A spurious commit cannot publish the rejected frame.
        playback.commitPreparedFrame()
        let afterDiscard = playback.committedNonemptyBatchLayerIDs.sorted()
        playback.prepareFrame()
        let retried = playback.advance(by: 1.0 / 30.0)
        playback.commitPreparedFrame()
        let committed = playback.committedNonemptyBatchLayerIDs.sorted()
        for _ in 0..<20 {
            playback.prepareFrame()
            _ = playback.advance(by: 1.0 / 30.0)
            playback.commitPreparedFrame()
        }
        return [
            "initial": initial,
            "rejectedCount": rejected.reduce(0) { $0 + $1.instances.count },
            "retriedCount": retried.reduce(0) { $0 + $1.instances.count },
            "beforeCommit": beforeCommit,
            "afterDiscard": afterDiscard,
            "discarded": discarded,
            "committed": committed,
            "dormant": playback.loadReportLines(descriptor: descriptor),
        ]
    }

    private static func syntheticLifecycle() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "mwx-particle-lifecycle-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writeParticle(
            "particles/root.json",
            material: "materials/shared.json",
            rate: 60,
            children: [[
                "name": "particles/child.json",
                "type": "eventspawn",
                "maxcount": 4,
            ]],
            under: directory
        )
        try writeParticle(
            "particles/child.json",
            material: "materials/shared.json",
            rate: 30,
            emitterDuration: 0.5,
            under: directory
        )
        let descriptor = SceneRenderDescriptor(
            layers: [layer(200, "particles/root.json")],
            renderOrderLayerIDs: [200],
            materialPasses: [
                .init(
                    materialPath: "materials/shared.json",
                    shaderPath: "genericparticle",
                    texturePaths: ["shared.png"],
                    blending: "additive"
                )
            ]
        )
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw HarnessError.noMetal
        }
        guard let playback = SceneParticlePlaybackState(
            descriptor: descriptor,
            cacheDirectory: directory,
            device: device
        ) else {
            throw HarnessError.noParticlePipeline
        }
        _ = playback.advance(by: 0.25)
        _ = playback.advance(by: 0.25)
        let identity = playback.lifecycleIdentity
        let active = playback.lifecycleSnapshot
        let observation = playback.teardown(reason: "scene-switch")
        let terminated = playback.lifecycleSnapshot
        let postTeardownBatches = playback.advance(by: 1)
        let repeatedObservation = playback.teardown(reason: "surface-stop")
        return [
            "identity": identity.uuidString,
            "observationIdentity": observation?.lifecycleIdentity.uuidString ?? "",
            "reason": observation?.reason ?? "",
            "active": lifecycleJSON(active),
            "observed": lifecycleJSON(
                observation?.snapshotBeforeTeardown ?? .empty
            ),
            "batchCountBeforeTeardown": observation?.batchCountBeforeTeardown ?? -1,
            "terminated": lifecycleJSON(terminated),
            "postTeardownBatchCount": postTeardownBatches.count,
            "repeatedObservation": repeatedObservation != nil,
        ]
    }

    private static func lifecycleJSON(
        _ value: SceneParticleRuntimeLifecycleSnapshot
    ) -> [String: Int] {
        [
            "layers": value.activeLayerCount,
            "rootSystems": value.rootSystemCount,
            "childSystems": value.childSystemCount,
            "rootParticles": value.rootParticleCount,
            "childParticles": value.childParticleCount,
        ]
    }

    private static func layer(
        _ id: Int,
        _ path: String,
        visible: Bool = true,
        particleAlpha: Double? = nil,
        layerAlpha: Double = 1,
        particleSize: Double? = nil,
        particleLifetime: Double? = nil,
        particleRate: Double? = nil,
        particleCount: Double? = nil,
        particleNormalizedColor: SIMD3<Double>? = nil,
        alphaHasUser: Bool = false,
        alphaHasScript: Bool = false,
        controlPoint: SIMD3<Double>? = nil,
        controlPointHasAnimation: Bool = false
    ) -> SceneRenderDescriptor.Layer {
        .init(
            id: id, name: nil, contentKind: "particle", particlePath: path,
            particleInstanceOverride: (particleAlpha != nil || particleSize != nil
                || particleLifetime != nil || particleRate != nil
                || particleCount != nil || particleNormalizedColor != nil
                || controlPoint != nil) ?
                SceneParticleInstanceOverride(
                    id: nil,
                    alpha: particleAlpha.map { value in SceneParticleBoundValue(
                        value: .scalar(value),
                        userPropertyKey: alphaHasUser ? "foreground" : nil,
                        hasScript: alphaHasScript,
                        hasAnimation: false
                    ) },
                    size: particleSize.map { SceneParticleBoundValue(
                        value: .scalar($0), userPropertyKey: "size",
                        hasScript: false, hasAnimation: false
                    ) },
                    lifetime: particleLifetime.map { SceneParticleBoundValue(
                        value: .scalar($0), userPropertyKey: nil,
                        hasScript: false, hasAnimation: false
                    ) },
                    rate: particleRate.map { SceneParticleBoundValue(
                        value: .scalar($0), userPropertyKey: nil,
                        hasScript: false, hasAnimation: false
                    ) },
                    speed: nil,
                    count: particleCount.map { SceneParticleBoundValue(
                        value: .scalar($0), userPropertyKey: "count",
                        hasScript: false, hasAnimation: false
                    ) },
                    brightness: nil,
                    color: nil,
                    normalizedColor: particleNormalizedColor.map { SceneParticleBoundValue(
                        value: .vector([$0.x, $0.y, $0.z]), userPropertyKey: "color",
                        hasScript: false, hasAnimation: false
                    ) },
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
            parentID: nil, visible: visible, alpha: layerAlpha
        )
    }

    private static func writeParticle(
        _ path: String,
        material: String,
        flags: Int = 0,
        renderer: String = "sprite",
        rendererFlags: Int = 0,
        rendererLength: Any? = nil,
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
        operatorAudioProcessingMode: Int? = nil,
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
        var operators: [[String: Any]] = []
        if moves {
            operators.append([
                "name": "movement",
                "flags": movementFlags,
            ])
        }
        if let operatorAudioProcessingMode {
            operators.append([
                "name": "turbulence",
                "audioprocessingmode": operatorAudioProcessingMode,
            ])
        }
        var definition: [String: Any] = [
            "material": material,
            "maxcount": 100,
            "flags": flags,
            "emitter": [emitter],
            "initializer": initializers,
            "operator": operators,
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

    def test_layer_alpha_updates_existing_root_and_child_particles(self) -> None:
        result = self.run_harness("layer-alpha-synthetic")
        for field, expected in [("initial", 0.2), ("changed", 0.4), ("hidden", 0),
                                ("recovered", 0.5), ("fallback", 0.2),
                                ("startup", 0.4), ("rejected", 0), ("restored", 0.4), ("retry", 0.25)]:
            self.assertEqual(len(result[field]), 2)
            for value in result[field]:
                self.assertAlmostEqual(value, expected, places=6)
        self.assertTrue(result["positionsUnchanged"])
        self.assertEqual(result["rootParticles"], 1)
        self.assertEqual(result["childParticles"], 1)

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

    def test_static_sprite_geometry_uses_mapped_color_extent_in_root_and_child(self) -> None:
        result = self.run_harness("sprite-geometry-synthetic")
        self.assertEqual(result["active"], [1, 2, 3, 4])
        for name in ["raw", "embedded", "atlas", "refract", "child", "child-refract"]:
            with self.subTest(name=name):
                self.assertEqual(result[name]["aspect"], [0.25, 0.25])
                self.assertEqual(result[name]["pixels"], [4, 16, 63, 63])
        self.assertEqual(result["raw"]["textureSize"], [8, 8])
        self.assertEqual(result["raw"]["uvScale"], [0.25, 1])
        self.assertEqual(result["atlas"]["textureSize"], [8, 8])
        self.assertEqual(result["atlas"]["uvScale"], [1, 1])
        for name in ["embedded", "refract", "child", "child-refract"]:
            self.assertEqual(result[name]["textureSize"], [8, 8])
            self.assertEqual(result[name]["uvScale"], [0.25, 1])

    def test_synthetic_rejects_unsupported_roots_and_keeps_diagnostics(self) -> None:
        result = self.run_harness("synthetic")
        self.assertEqual(
            result["activeLayerIDs"], [2, 3, 4, 6, 7, 9, 11, 13, 14, 16, 17, 18, 19]
        )
        self.assertEqual(
            result["batchLayerIDs"],
            [2, 3, 4, 4, 4, 6, 7, 9, 9, 9, 9, 9, 11, 13, 14, 16, 17, 17, 18, 19],
        )
        self.assertGreater(result["activeParticleCount"], 0)
        self.assertGreater(result["childInstanceCount"], 0)
        self.assertTrue(result["childCullStates"])
        self.assertEqual(set(result["childCullStates"]), {"back"})
        self.assertEqual(result["staticChildInstanceCount"], 4)
        self.assertEqual(result["staticChildOrigins"][:3], [[0, 0, 0], [0, 0, 0], [1, 2, 3]])
        self.assertEqual(result["scaledStaticInstance"]["size"], [8])
        self.assertEqual(result["scaledStaticInstance"]["velocity"], [8, 0, 0])
        self.assertTrue(result["staticChildScaleBounded"])
        # 内置纹理尺寸已对齐官方 .tex 的 imageWidth/imageHeight，非方形纹理不再按方形近似。
        self.assertEqual(result["batchTextureSizes"]["6"], [32, 128])
        self.assertEqual(result["batchTextureSizes"]["7"], [64, 64])
        self.assertAlmostEqual(result["trailStretch"], 5)
        self.assertEqual(result["trailVelocity"], [100, 0, 0])
        self.assertEqual(result["defaultTrailStretch"], 2)
        self.assertEqual(result["childTrailStretch"], 2)
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
        self.assertFalse(any(
            value["kind"] == "trailRendererUnsupported" and value["layer"] in (3, 4, 19)
            for value in diagnostics
        ))
        self.assertNotIn("missingSpriteRenderer", kinds)
        self.assertIn("childSystemsUnsupported", kinds)
        self.assertIn("unsupportedShader", kinds)
        self.assertNotIn(15, result["activeLayerIDs"])
        self.assertNotIn(15, result["batchLayerIDs"])
        self.assertNotIn(20, result["activeLayerIDs"])
        self.assertIn(
            "spritetrail:invalidLength",
            [value["detail"] for value in diagnostics if value["layer"] == 20],
        )
        for path in [
            "particles/angles-child.json",
            "particles/zero-scale-child.json",
            "particles/negative-scale-child.json",
            "particles/nonuniform-scale-child.json",
            "particles/huge-scale-child.json",
            "particles/malformed-scale-child.json",
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

    def test_playback_teardown_terminates_the_same_root_and_child_instance_once(self) -> None:
        result = self.run_harness("lifecycle-synthetic")
        self.assertEqual(result["identity"], result["observationIdentity"])
        self.assertEqual(result["reason"], "scene-switch")
        self.assertEqual(result["active"], result["observed"])
        self.assertEqual(result["active"]["layers"], 1)
        self.assertEqual(result["active"]["rootSystems"], 1)
        self.assertGreater(result["active"]["childSystems"], 0)
        self.assertGreater(result["active"]["rootParticles"], 0)
        self.assertGreater(result["active"]["childParticles"], 0)
        self.assertGreater(result["batchCountBeforeTeardown"], 0)
        self.assertEqual(result["terminated"], {
            "layers": 0,
            "rootSystems": 0,
            "childSystems": 0,
            "rootParticles": 0,
            "childParticles": 0,
        })
        self.assertEqual(result["postTeardownBatchCount"], 0)
        self.assertFalse(result["repeatedObservation"])

    def test_product_playback_discards_unbounded_fixed_step_debt(self) -> None:
        result = self.run_harness("playback-delta-synthetic")
        self.assertAlmostEqual(result["sixtyFPS"], 1 / 60)
        self.assertAlmostEqual(result["thirtyFPS"], 1 / 30)
        self.assertAlmostEqual(result["slowFrame"], 1 / 30)
        self.assertEqual(result["negative"], 0)
        self.assertEqual(result["nonFinite"], 0)

    def test_particle_frame_transaction_restores_simulation_and_random_state(self) -> None:
        result = self.run_harness("frame-transaction-synthetic")
        self.assertTrue(result["sameParticles"])
        self.assertTrue(result["sameTime"])
        self.assertTrue(result["sameRandom"])
        self.assertEqual(result["transientPersistentCount"], 0)
        self.assertGreater(result["transientBeforeConsume"], 0)
        self.assertEqual(
            result["transientAfterConsume"], result["transientBeforeConsume"]
        )
        self.assertEqual(result["transientAfterNextAdvance"], 0)
        self.assertEqual(
            result["transientRestored"], result["transientBeforeConsume"]
        )
        self.assertEqual(result["steadyPersistentCount"], 1)
        self.assertEqual(result["steadyTransientCount"], 0)

    def test_subframe_lifetime_renders_root_and_child_sprite_once_without_resurrection(self) -> None:
        result = self.run_harness("subframe-lifetime-synthetic")
        self.assertGreater(result["rootInstanceCount"], 0)
        self.assertGreater(result["childInstanceCount"], 0)
        self.assertEqual(result["rootPersistentCount"], 0)
        self.assertEqual(result["childPersistentCount"], 0)
        self.assertEqual(result["secondAdvanceInstanceCount"], 0)
        for position in result["rootPositions"]:
            self.assertAlmostEqual(position[0], 32, places=5)
            self.assertAlmostEqual(position[1], 48, places=5)
            self.assertAlmostEqual(position[2], 0, places=5)

    def test_subframe_child_final_sample_survives_retirement_then_never_repeats(self) -> None:
        result = self.run_harness("subframe-child-lifecycle-synthetic")
        self.assertEqual(result["staticCount"], 1)
        self.assertEqual(result["staticPosition"], [7, 9, 0])
        self.assertEqual(result["staticLifecycleSystems"], 0)
        self.assertEqual(result["staticLifecycleParticles"], 0)
        self.assertEqual(result["staticNextCount"], 0)

        self.assertEqual(result["spawnCount"], 1)
        self.assertEqual(result["spawnLifecycleSystems"], 0)
        self.assertEqual(result["spawnLifecycleParticles"], 0)
        self.assertEqual(result["spawnNextCount"], 0)

        self.assertEqual(result["deathCount"], 1)
        self.assertEqual(result["deathLifecycleSystems"], 0)
        self.assertEqual(result["deathLifecycleParticles"], 0)
        self.assertEqual(result["deathNextCount"], 0)

        self.assertEqual(result["depthOneCount"], 1)
        # The depth-one system retired; only the newly queued depth-two owner remains.
        self.assertEqual(result["depthOneRemainingSystems"], 1)
        self.assertEqual(result["depthTwoCount"], 1)
        self.assertEqual(result["depthTwoLifecycleSystems"], 0)
        self.assertEqual(result["depthTwoLifecycleParticles"], 0)
        self.assertEqual(result["depthTwoNextCount"], 0)

        # A retiring maxcount=1 owner must leave admission before the same
        # callback's next event is reconciled. The retired sample still draws
        # once, while lifecycle contains only the newly queued replacement.
        self.assertEqual(result["replacementSecondCount"], 1)
        self.assertEqual(result["replacementSecondSystems"], 1)
        self.assertEqual(result["replacementThirdCount"], 1)
        self.assertEqual(result["replacementThirdSystems"], 1)

        # The same contract applies to nested event children. One live depth-one
        # replacement plus one live depth-two replacement remain after each frame.
        self.assertEqual(result["nestedReplacementThirdCount"], 1)
        self.assertEqual(result["nestedReplacementThirdSystems"], 2)
        self.assertEqual(result["nestedReplacementFourthCount"], 1)
        self.assertEqual(result["nestedReplacementFourthSystems"], 2)

    def test_velocity_random_uses_official_zero_for_each_omitted_endpoint(self) -> None:
        result = self.run_harness("velocity-defaults-synthetic")
        maximum_only = result["maximumOnly"]
        minimum_only = result["minimumOnly"]
        self.assertEqual([maximum_only[0], maximum_only[2]], [0, 0])
        self.assertGreaterEqual(maximum_only[1], 0)
        self.assertLessEqual(maximum_only[1], 100)
        self.assertEqual([minimum_only[0], minimum_only[2]], [0, 0])
        self.assertGreaterEqual(minimum_only[1], -100)
        self.assertLessEqual(minimum_only[1], 0)
        self.assertEqual(result["omitted"], [0, 0, 0])

    def test_child_pointer_control_point_uses_child_local_scale_and_fails_closed_outside(self) -> None:
        result = self.run_harness("child-pointer-control-point-synthetic")
        self.assertEqual(result["outside"], [0, 0, 0])
        self.assertAlmostEqual(result["insideScaled"][0], 2.5, places=5)
        self.assertEqual(result["insideScaled"][1:], [0, 0])
        self.assertEqual(result["dynamicInsideScaled"], [0, 0, 0])
        self.assertEqual(result["emitterMissing"], [])
        self.assertEqual(result["emitterDynamicOnly"], [])
        self.assertEqual(len(result["emitterRecovered"]), 1)
        self.assertAlmostEqual(result["emitterRecovered"][0][0], 10, places=5)
        self.assertAlmostEqual(result["emitterRecovered"][0][1], 0, places=5)
        self.assertAlmostEqual(result["emitterRecovered"][0][2], 0, places=5)
        self.assertEqual(result["rootPointerChildStaticPosition"], [25, 0, 0])
        self.assertEqual(result["pointerDemandLayerIDs"], [18])

    def test_dynamic_control_point_angles_reach_root_and_child_emitters(self) -> None:
        result = self.run_harness("dynamic-control-point-angle-synthetic")
        for velocity in result["dynamic"]:
            self.assertAlmostEqual(velocity[0], 0, places=5)
            self.assertAlmostEqual(velocity[1], 1, places=5)
        for velocity in result["fallback"]:
            self.assertAlmostEqual(velocity[0], 1, places=5)
            self.assertAlmostEqual(velocity[1], 0, places=5)
        self.assertEqual(result["malformed"], result["fallback"])

    def test_runtime_consumes_each_surface_snapshot_then_restores_authored_fallback(self) -> None:
        result = self.run_harness("dynamic-control-point-synthetic")
        self.assertEqual(result["activeLayerIDs"], [90])
        self.assertEqual(
            result["positions"],
            [[11, 21, 31], [-4, 7, 8], [3, 4, 5]],
        )

    def test_child_scaled_float_overflow_keeps_safe_peer_and_recovers(self) -> None:
        result = self.run_harness("child-float-safety")
        self.assertGreater(result["unsafeAssembled"], 0)
        self.assertEqual(result["uploadedCount"], 1)
        self.assertTrue(result["uploadedFinite"])
        self.assertEqual(result["rootCount"], 2)
        self.assertEqual(result["recoveredCount"], 2)
        self.assertEqual(result["rejectedLanes"], 40)
        self.assertTrue(result["emptyDraw"])
        self.assertEqual(result["recoveredBuffer"], 1)

    def test_child_tree_inherits_layer_modifiers_with_flags_prewarm_and_rollback(self) -> None:
        result = self.run_harness("child-instance-override-synthetic")
        for name in ("static", "staticFallback"):
            self.assertEqual(result[name]["count"], 2)
            self.assertAlmostEqual(result[name]["alpha"], 0.4)
            self.assertAlmostEqual(result[name]["size"], 8)
            self.assertEqual(result[name]["color"], [1, 0.25, 1])
            self.assertAlmostEqual(result[name]["lifetime"], 15)
        for name in ("disabled", "disabledFallback"):
            self.assertAlmostEqual(result[name]["size"], 4)
            self.assertEqual(result[name]["color"], [1, 1, 1])
            self.assertAlmostEqual(result[name]["lifetime"], 10)
        for name in ("staticDynamic", "prewarm", "container", "eventspawn", "eventfollow",
                     "eventdeath", "eventspawnNested", "eventfollowNested", "eventdeathNested"):
            with self.subTest(name=name):
                self.assertGreater(result[name]["count"], 0)
                self.assertAlmostEqual(result[name]["alpha"], 0.25)
                self.assertAlmostEqual(result[name]["size"], 12)
                self.assertEqual(result[name]["color"], [0.125, 0.5, 0.03125])
                self.assertAlmostEqual(result[name]["lifetime"], 20)
                self.assertAlmostEqual(result[name]["velocity"], 6)
        self.assertEqual(result["staticDynamic"]["count"], 2)
        self.assertEqual(result["continuous0"]["count"], 6)
        self.assertEqual(result["continuous248"]["count"], 3)
        self.assertAlmostEqual(result["staticDynamic"]["simulationTime"], 0.05)
        self.assertAlmostEqual(result["prewarm"]["simulationTime"], 0.05)
        for name in ("eventspawn", "eventfollow", "eventspawnNested", "eventfollowNested"):
            self.assertAlmostEqual(result[name]["simulationTime"], 0.05 + 5 / 120)
        self.assertAlmostEqual(result["eventdeath"]["simulationTime"], 0.05 + 4 / 120)
        self.assertAlmostEqual(result["eventdeathNested"]["simulationTime"], 0.05 + 2 / 120)
        self.assertEqual(result["disabledDynamic"]["count"], 2)
        self.assertAlmostEqual(result["disabledDynamic"]["alpha"], 0.25)
        self.assertAlmostEqual(result["disabledDynamic"]["size"], 4)
        self.assertAlmostEqual(result["disabledDynamic"]["velocity"], 2)
        self.assertEqual(result["disabledDynamic"]["color"], [0.5, 0.5, 0.5])
        self.assertTrue(result["staticRetryEqual"])
        self.assertTrue(result["disabledRetryEqual"])

    def test_runtime_consumes_dynamic_instance_override_then_restores_authored_values(self) -> None:
        result = self.run_harness("dynamic-instance-override-synthetic")
        self.assertEqual(result["zeroCount"], 0)
        self.assertEqual(result["dynamicCount"], 2)
        self.assertAlmostEqual(result["dynamicAlpha"], 0.25)
        self.assertAlmostEqual(result["dynamicSize"], 12)
        self.assertEqual(result["dynamicColor"], [0.25, 1, 0.0625])
        self.assertEqual(result["fallbackCount"], 3)
        self.assertAlmostEqual(result["fallbackAlpha"], 0)
        self.assertAlmostEqual(result["fallbackSize"], 4)
        self.assertEqual(result["fallbackColor"], [1, 1, 1])

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
        self.assertTrue(result["sizeIsWorldSpace"])
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

    def test_rope_runtime_connects_live_particles_and_fails_closed(self) -> None:
        result = self.run_harness("rope-synthetic")
        # Layer 44 carries the renderer world flag (bit0): admitted since the
        # pointer-trail family batch — the spline is affine-invariant, so the
        # local construction renders identically through the layer matrix.
        self.assertEqual(result["activeLayerIDs"], [41, 44, 45, 46, 48])
        self.assertGreaterEqual(result["instanceCount"], 2)
        self.assertTrue(result["bufferMatches"])
        self.assertTrue(result["orientationScreen"])
        self.assertFalse(result["usesPerspective"])
        self.assertTrue(result["allSegmentsNonzero"])
        self.assertTrue(result["uvStartsAtZero"])
        self.assertTrue(result["uvEndsAtOne"])
        self.assertTrue(result["uvContinuous"])
        self.assertTrue(result["usesDisplacement"])
        self.assertTrue(result["subdivisionHalvesDefaultDensity"])
        self.assertAlmostEqual(result["scrollUVStart"], 0.5, places=5)
        self.assertAlmostEqual(result["scrollUVEnd"], 2.5, places=5)
        self.assertGreater(result["childRopeCount"], 0)
        self.assertTrue(result["childRopeUsesSubdivision"])
        self.assertTrue(result["childRopeTranslated"])
        self.assertTrue(result["childRopeUVStartsWithPhase"])
        self.assertIn(
            "ropeRendererUnsupported:42:rope:animatedTexture",
            result["diagnosticDetails"],
        )
        self.assertIn(
            "ropeRendererUnsupported:43:rope:unsupportedProfile",
            result["diagnosticDetails"],
        )
        # Layer 44 (renderer world flag) no longer reports unsupported; its
        # admission is covered by the activeLayerIDs assertion above.
        self.assertIn(
            "ropeRendererUnsupported:47:rope:unsupportedProfile",
            result["diagnosticDetails"],
        )
        self.assertFalse(any(
            "rope-child.json:outsideStrictStaticProfile" in detail
            for detail in result["diagnosticDetails"]
        ))
        self.assertIn(
            "simulationLimitation:48:particles/rope-child.json:"
            "unusedParentControlPointMappings:mappings=2",
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

    def test_child_bursts_preserve_authored_density_with_bounded_depth_capacity(self) -> None:
        result = self.run_harness("child-capacity-synthetic")
        self.assertEqual(result["single"], 8500)
        self.assertEqual(result["prewarm"], 8500)
        self.assertEqual(result["smallPeer"], 5536)
        self.assertTrue(result["identityReplay"])
        self.assertEqual(result["static"], 65536)
        self.assertEqual(result["staticCapacity"], [65536, 0])
        for trigger in ["eventspawn", "eventdeath", "eventfollow"]:
            self.assertEqual(result[trigger], 60000, trigger)
            self.assertEqual(result[trigger + "Capacity"], [60000, 0], trigger)
        self.assertEqual(result["nested"], 120000)
        self.assertEqual(result["nestedCapacity"], [60004, 60000])
        for name in ["static", "eventspawn", "eventdeath", "eventfollow"]:
            self.assertIn("aggregateSystemBudget:systems=64:particleCapacity=65536",
                          result[name + "Diagnostics"], name)
        self.assertIn("nestedAggregateSystemBudget:depth=2:systems=64:particleCapacity=65536",
                      result["nestedDiagnostics"])
        for systems, capacity in result["recycleAllocations"]:
            self.assertLessEqual(systems, 64)
            self.assertLessEqual(capacity, 65536)
        self.assertEqual(result["recycle"], result["replay"])
        self.assertGreater(max(result["recycle"]), 8500)
        self.assertGreater(result["recycle"][-1], 0)

    def test_continuous_children_follow_finish_and_obey_aggregate_budget(self) -> None:
        result = self.run_harness("eventfollow-synthetic")
        self.assertEqual(result["childCounts"], [0, 1, 2, 0, 0, 0])
        self.assertEqual(result["childPositions"], [2, 2])
        self.assertEqual(result["childSizes"], [10, 10])
        self.assertEqual(result["boundedCounts"], [0, 1, 1, 1, 0, 0])
        self.assertEqual(len(result["boundedSizes"]), 3)
        for size in result["boundedSizes"]:
            self.assertAlmostEqual(size, 0.8, places=5)
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
        self.assertEqual(set(result["childScaleDetails"]), {
            "particles/follow-child.json:childScaleBounded:scale=2.5,2.5,1.0",
            "particles/bounded-child.json:childScaleBounded:scale=0.2,0.2,0.2",
        })
        self.assertTrue(result["inheritedFollowMatches"])
        self.assertTrue(all(result["inheritedFollowMatches"]))
        self.assertTrue(result["inheritedDeathColors"])
        for color in result["inheritedDeathColors"]:
            for actual, expected in zip(color, [0.2, 0.4, 0.6]):
                self.assertAlmostEqual(actual, expected, places=6)
        self.assertEqual(set(result["eventColorMarkers"]), {
            "particles/inherit-follow-child.json:eventColorOperatorBounded:setcolor",
            "particles/inherit-death-child.json:eventColorInitializerBounded:setcolor",
        })
        self.assertEqual(set(result["invalidEventColorDetails"]), {
            "particles/invalid-inherit-static.json:eventColorInitializerOutsideEventChild",
            "particles/invalid-inherit-death.json:eventColorOperatorOutsideFollowChild",
            "particles/invalid-inherit-follow.json:eventColorOperatorUnsupported",
        })

    def test_nonempty_batch_evidence_requires_commit_and_survives_dormancy(self) -> None:
        result = self.run_harness("batch-evidence-synthetic")
        self.assertIn("particle loaded: 2 / 2", result["initial"])
        self.assertIn("particle current nonempty: layers=[]", result["initial"])
        self.assertIn("particle committed nonempty: layers=[]", result["initial"])
        self.assertGreater(result["rejectedCount"], 0)
        self.assertEqual(result["rejectedCount"], result["retriedCount"])
        self.assertEqual(result["beforeCommit"], [])
        self.assertEqual(result["afterDiscard"], [])
        self.assertIn("particle current nonempty: layers=[]", result["discarded"])
        self.assertEqual(result["committed"], [200])
        self.assertIn("particle loaded: 2 / 2", result["dormant"])
        self.assertIn("particle current nonempty: layers=[]", result["dormant"])
        self.assertIn("particle committed nonempty: layers=[200]", result["dormant"])

    def test_child_audio_consumer_receives_the_shared_typed_input(self) -> None:
        result = self.run_harness("eventfollow-synthetic")
        self.assertTrue(result["hasAudioConsumer"])
        self.assertEqual(result["activeChildAudioInput"], 1)

    def test_child_audio_observation_is_transactional_and_template_sticky(self) -> None:
        result = self.run_harness("eventfollow-synthetic")
        self.assertEqual(result["rejectedChurnObservationCount"], 1)
        self.assertEqual(result["churnObservationsAfterRestore"], 0)
        self.assertEqual(result["retryChurnObservationCount"], 1)
        self.assertEqual(result["retryChurnObservationPaths"], [
            "particles/audio-churn-child.json",
        ])
        self.assertEqual(result["laterChurnObservationCount"], 0)

    def test_rate_only_event_children_stop_after_bounded_window(self) -> None:
        result = self.run_harness("eventfollow-synthetic")
        counts = result["windowCounts"]
        # rate-only eventspawn child(无 duration)只允许一个有界 burst:
        # 发射窗口 = 自身粒子最大寿命,粒子清空后系统回收,计数必须归零并保持。
        self.assertGreaterEqual(max(counts), 1)
        self.assertEqual(counts[-2:], [0, 0])
        self.assertLess(counts.index(max(counts)), len(counts) - 2)

    def test_world_space_system_freezes_on_runtime_transform_write(self) -> None:
        result = self.run_harness("worldspace-freeze")
        self.assertTrue(result["movingLayerActive"])
        # The system simulates normally while no chain transform lane exists.
        self.assertTrue(result["movingPositions"])
        self.assertTrue(any(abs(x) > 0.01 for x, _, _ in result["movingPositions"]))
        # Without a current world frame the runtime transform write freezes
        # the system at its last committed state (previous-current) instead of
        # silently misconverting world forces through the stale launch frame.
        self.assertEqual(result["frozenPositions"], result["movingPositions"])
        self.assertEqual(result["frozenAgainPositions"], result["movingPositions"])
        self.assertTrue(result["freezeDiagnostic"])

    def test_world_space_system_follows_current_world_frame_over_transform_lane(self) -> None:
        result = self.run_harness("worldspace-freeze")
        # With the renderer's current world frame supplied, the same transform
        # lane no longer freezes the system: birth velocities and gravity run
        # through the live frame each advance.
        identity = result["liveIdentityPositions"]
        rotated = result["liveRotatedPositions"]
        self.assertTrue(identity)
        self.assertTrue(any(abs(x) > 0.01 for x, _, _ in identity))
        self.assertTrue(result["liveIdentityFollowsCurrent"])
        self.assertFalse(result["liveIdentityFrozen"])
        self.assertTrue(result["liveRotatedFollowsCurrent"])
        self.assertFalse(result["liveRotatedFrozen"])
        # A +90 degree Z world frame redirects the world +X birth velocity
        # into the local Y axis, so the rotated run moves on Y while the
        # identity run keeps moving on X.
        identityX = sum(abs(p[0]) for p in identity)
        identityY = sum(abs(p[1]) for p in identity)
        rotatedX = sum(abs(p[0]) for p in rotated)
        rotatedY = sum(abs(p[1]) for p in rotated)
        self.assertGreater(identityX, identityY * 4)
        self.assertGreater(rotatedY, rotatedX * 4)
        self.assertTrue(any(abs(y) > 0.01 for _, y, _ in rotated))

    def test_world_space_pointer_positionaround_births_around_pointer(self) -> None:
        result = self.run_harness("worldspace-pointer-positionaround")
        # The positionAround initializer's pointer demand is registered for
        # the world system and births distribute around the pointer position.
        self.assertIn(131, result["demandedLayerIDs"])
        self.assertTrue(result["positions"])
        for x, y, _ in result["positions"]:
            self.assertLess(abs(x - 60), 60)
            self.assertLess(abs(y - 40), 60)
        # Not all at the exact pointer point: the distance spread is real.
        distinct = len({(round(x), round(y)) for x, y, _ in result["positions"]})
        self.assertGreater(distinct, 1)

    def test_world_space_pointer_force_repels_from_pointer(self) -> None:
        result = self.run_harness("worldspace-pointer-force")
        # The pointer control point's demand is registered for the world
        # system, and the negative-scale attract accelerates particles away
        # from the pointer instead of staying inert at the origin.
        self.assertIn(121, result["demandedLayerIDs"])
        without = result["withoutPointerPositions"]
        with_pointer = result["withPointerPositions"]
        self.assertTrue(without)
        self.assertTrue(with_pointer)
        # Without the pointer the force is fail-closed: no acceleration.
        for x, _, _ in without:
            self.assertLess(abs(x), 0.5)
        # With the pointer at +X the repulsion drives particles to -X.
        moved = [x for x, _, _ in with_pointer if x < -0.5]
        self.assertGreater(len(moved), len(with_pointer) // 2)

    def test_world_space_rope_pointer_trail_renders(self) -> None:
        result = self.run_harness("worldspace-rope-trail")
        # The pointer-trail rope family profile (world system + pointer CP0 +
        # rope renderer flags=1/subdivision=100/maxcount=256) is admitted and
        # produces rope geometry following the pointer birth history.
        self.assertIn(111, result["activeLayerIDs"])
        self.assertIn(111, result["demandedLayerIDs"])
        self.assertFalse(result["ropeDiagnostic"])
        self.assertGreater(result["instanceCount"], 0)
        self.assertTrue(result["firstPositions"])

    def test_audio_bounds_without_mode_gates_emission(self) -> None:
        result = self.run_harness("audio-bounds-gate")
        # Authored bounds without a channel mode still gate the emitter: the
        # mode only selects left/right/center (bounds-only corpus shape comes
        # from the same editor flow as the mode-bearing copies).
        self.assertEqual(result["boundsOnlySilentCount"], 0)
        self.assertGreater(result["boundsOnlyLoudCount"], 0)
        # The explicit-mode shape keeps its existing gate.
        self.assertEqual(result["modeCenterSilentCount"], 0)

    def test_world_space_pointer_emitter_follows_pointer(self) -> None:
        result = self.run_harness("worldspace-pointer-emitter")
        # The emitter's pointer control-point demand must not be excluded for
        # world-space systems: the supplied pointer value is the layer-local
        # unprojection through the layer's current model matrix, the same
        # space every control-point consumer composes in.
        self.assertIn(91, result["pointerDemandLayerIDs"])
        self.assertTrue(result["positions"])
        # Births cluster at the pointer position, not at the static offset.
        for x, y, _ in result["positions"]:
            self.assertLess(abs(x - 40), 2.0)
            self.assertLess(abs(y - 60), 2.0)
        self.assertNotIn("pointerControlPointUnsupported", result["diagnosticKinds"])

    def test_world_space_prewarm_converts_gravity_through_launch_frame(self) -> None:
        result = self.run_harness("worldspace-gravity-frame")
        # The init-time warm-up must convert world gravity through the
        # injected +90 degree Z launch frame: world +X gravity moves the
        # prewarmed particles along the local Y axis, not raw +X.
        self.assertTrue(result["prewarmPositions"])
        self.assertGreater(result["prewarmY"], result["prewarmX"] * 4)

    def test_world_space_live_gravity_follows_current_frame(self) -> None:
        result = self.run_harness("worldspace-gravity-frame")
        # With a transform lane and a -90 degree Z current frame, world +X
        # gravity integrates into local +Y during live advances.
        self.assertTrue(result["livePositions"])
        self.assertGreater(result["liveY"], result["liveX"] * 4)

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
        self.assertEqual(result["headSizeRange"], [50, 50])
        self.assertEqual(result["trailSizeRange"], [50, 50])
        self.assertLess(result["headYRange"][1], -250)
        self.assertGreater(result["trailYRange"][0], result["headYRange"][1])
        self.assertGreaterEqual(
            result["trailYRange"][1] - result["trailYRange"][0], 240
        )
        self.assertEqual(result["trailVelocityYRange"], [100, 100])
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

    def test_delayed_child_emitters_survive_until_their_actual_emission_finishes(self) -> None:
        results = self.run_harness("delayed-children")
        for name, value in results.items():
            with self.subTest(profile=name):
                self.assertTrue(value["nonemptyFrames"], "delayed child never reached a draw batch")
                self.assertTrue(value["retryEqual"])
                self.assertEqual(value["systems"][-1], 0)
                if name not in ("multipleBurst", "prewarmBurst"):
                    self.assertGreaterEqual(value["nonemptyFrames"][0], 13)
                    self.assertLessEqual(value["nonemptyFrames"][0], 18)
                if name.startswith("static") or name == "pausedBurst":
                    self.assertEqual(value["systems"][5], 1)
        self.assertGreaterEqual(results["spawnLongFinite"]["nonemptyFrames"][-1], 40)
        self.assertEqual(results["staticBurst"]["nonemptyFrames"][0], 13)
        self.assertEqual(results["multipleBurst"]["nonemptyFrames"][0], 1)
        self.assertIn(13, results["multipleBurst"]["nonemptyFrames"])
        self.assertEqual(results["prewarmBurst"]["nonemptyFrames"][0], 1)
        self.assertEqual(results["pausedBurst"]["nonemptyFrames"], results["staticBurst"]["nonemptyFrames"])

    def test_child_emission_invalid_delay_and_tiny_duration_retire_safely(self) -> None:
        results = self.run_harness("delayed-child-edges")
        for name, value in results.items():
            with self.subTest(profile=name):
                self.assertTrue(value["retryEqual"], "replaying retirement must restore systems and allocator identity")
                self.assertEqual(value["systems"][-1], 0)
                if name in ("negativeDelay", "excessiveDelay", "malformedDelay", "invalidFinite"):
                    self.assertFalse(value["nonemptyFrames"])
                else:
                    self.assertTrue(value["nonemptyFrames"])
        self.assertEqual(results["safePeer"]["nonemptyFrames"][0], 1)
        self.assertEqual(results["tinyBurst"]["nonemptyFrames"][0], 1)
        self.assertEqual(results["tinyDelayedBurst"]["nonemptyFrames"][0], 13)
        self.assertEqual(results["tinyDelayedRate"]["nonemptyFrames"][0], 13)
        self.assertEqual(max(results["tinyDelayedRate"]["counts"]), 10)

    def test_real_flare_children_enter_continuous_emitter_profile(self) -> None:
        if not FLARE_PARTICLE_CACHE.is_dir():
            self.skipTest("isolated 2998757800 particle cache is unavailable")
        result = self.run_harness("continuous-profile-real", str(FLARE_PARTICLE_CACHE))
        self.assertEqual(result["supported"], {
            "Flare_Flame": True,
            "Flare_Smoke": True,
            "Flare_Sparks": True,
        })
        self.assertEqual(set(result["completed"].values()), {False})
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
        self.assertEqual(result["hitInstanceCount"], 8_500)
        self.assertGreater(result["hitMaximumAlpha"], 0)
        self.assertGreater(result["hitMaximumSize"], 0)
        self.assertGreater(result["hitMaximumTrailStretch"], 1)
        self.assertGreater(result["renderedPixelCount"], 1_000)
        self.assertGreater(result["renderedPixelWidth"], 100)
        self.assertGreater(result["renderedPixelHeight"], 100)
        self.assertTrue(result["hitUsesTrail"])
        self.assertFalse(result["layer529ChildUnsupported"])

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
        self.assertEqual(result["activeRopePaths"], [
            "particles/presets/dripping_water_refract.json",
            "particles/presets/dripping_water_splash.json",
        ], result)
        self.assertGreater(
            result["maximumRopeInstances"]["particles/presets/dripping_water_refract.json"],
            0,
        )
        self.assertGreater(
            result["maximumRopeInstances"]["particles/presets/dripping_water_splash.json"],
            0,
        )
        self.assertEqual(result["refractiveRopePaths"], [
            "particles/presets/dripping_water_refract.json",
        ])
        self.assertEqual(result["ropeUnsupported"], [])
        self.assertEqual(result["activeTrailChildLayers"], [239, 245, 248], result)
        for layer_id in ("239", "245", "248"):
            self.assertGreater(result["maximumTrailChildInstances"][layer_id], 0, result)
        self.assertGreaterEqual(result["minimumTrailStretch"], 1)
        self.assertLessEqual(result["maximumTrailStretch"], 2)
        self.assertEqual(result["trailChildUnsupported"], [])
        for layer_id in (239, 245, 248):
            self.assertIn(layer_id, result["legacyLayers"], result)


if __name__ == "__main__":
    unittest.main()
