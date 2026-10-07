#!/usr/bin/env python3

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
METAL_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneStaticModel.metal"
SHADOW_SOURCE = SCENE_ROOT / "Rendering/Metal/SceneStaticModelShadow.swift"
PIPELINE_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Metal/SceneStaticModelPipeline.swift"
DYNAMIC_SNAPSHOT_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneDynamicSnapshot.swift"
BINDINGS_SOURCE = SCENE_ROOT / "Runtime/Frame/SceneStaticModelMaterialBindings.swift"
DYNAMIC_LAYER_VALUES_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneDynamicLayerValues.swift"
MODEL_SOURCE = SCENE_ROOT / "Format/SceneMdlStaticModel.swift"
SAMPLING_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureSampling.swift"
UV_TRANSFORM_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureUVTransform.swift"
LIGHT_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Lighting/SceneLightSnapshot.swift"
VISIBILITY_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/SceneLayerVisibility.swift"
DIRECTIONAL_LIGHT_SOURCE = (
    SCENE_ROOT / "Format/SceneDirectionalLightDefinition.swift"
)
POINT_LIGHT_SOURCE = SCENE_ROOT / "Format/ScenePointLightDefinition.swift"
SPOT_LIGHT_SOURCE = SCENE_ROOT / "Format/SceneSpotLightDefinition.swift"
PERFORMANCE_COUNTER_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/ScenePerformanceCounterHub.swift"
)

LIGHTING_STUB = r'''
struct SceneLayerDisplayScriptOwnership {
    let visible: Bool
    let alpha: Bool
    var isEmpty: Bool { !visible && !alpha }
    var fields: [String] { [] }
}

struct SceneRenderDescriptor {
    struct LightingDescriptor {
        struct DistanceFog {
            let color: [Float]
            let start: Float
            let end: Float
            let startDensity: Float
            let endDensity: Float
        }
        struct LightClassesDescriptor {
            var directional: Bool = true
            var point: Bool = true
            var spot: Bool = true
        }
        let ambientColorRGB: [Float]?
        let skylightColorRGB: [Float]?
        var lightClasses: LightClassesDescriptor = .init()
        var distanceFog: DistanceFog? = nil
    }

    struct CameraDescriptor {
        let orthoHeight: Float?
    }

    struct Layer {
        let id: Int
        let visible: Bool?
        var anglesXYZ: [Float]? = nil
        var pointLight: ScenePointLightDefinition? = nil
        let spotLight: SceneSpotLightDefinition?
        let directionalLight: SceneDirectionalLightDefinition?
        var parentID: Int? = nil
        var displayScriptOwnership: SceneLayerDisplayScriptOwnership? = nil
    }

    let lighting: LightingDescriptor?
    let camera: CameraDescriptor
    let layers: [Layer]
    let renderOrderLayerIDs: [Int]

    init(
        lighting: LightingDescriptor?,
        layers: [Layer],
        renderOrderLayerIDs: [Int]? = nil
    ) {
        self.lighting = lighting
        self.camera = CameraDescriptor(orthoHeight: nil)
        self.layers = layers
        self.renderOrderLayerIDs = renderOrderLayerIDs ?? layers.map(\.id)
    }
}
'''


class SceneStaticModelPipelineTests(unittest.TestCase):
    def test_fixed_metal_shader_compiles_and_matches_vertex_abi(self) -> None:
        metal = subprocess.run(
            ["xcrun", "--sdk", "macosx", "--find", "metal"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
        with tempfile.TemporaryDirectory(prefix="mwx-static-model-metal-") as tmp:
            output = Path(tmp) / "SceneStaticModel.air"
            completed = subprocess.run(
                [
                    metal,
                    "-x", "metal",
                    "-std=macos-metal2.4",
                    "-c", str(METAL_SOURCE),
                    "-o", str(output),
                ],
                capture_output=True,
                text=True,
            )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        source = METAL_SOURCE.read_text(encoding="utf-8")
        ordered_fields = (
            "float3 position;",
            "float3 normal;",
            "float4 tangent;",
            "float2 uv;",
        )
        offsets = [source.index(field) for field in ordered_fields]
        self.assertEqual(offsets, sorted(offsets))
        self.assertIn("texture2d<half> colorTexture [[texture(0)]]", source)
        self.assertIn("texture2d<half> componentTexture [[texture(1)]]", source)
        self.assertIn("sampler colorSampler [[sampler(0)]]", source)
        self.assertIn("modelVertex.uv.x * uniforms.textureFrame0.zw", source)
        self.assertIn("modelVertex.uv.y * uniforms.textureFrame1.xy", source)
        self.assertIn("(uniforms.materialFlags.x & 1u) != 0u", source)
        self.assertIn("(uniforms.materialFlags.x & 2u) != 0u", source)
        self.assertIn("(uniforms.materialFlags.y & 1u) != 0u", source)
        self.assertIn("(uniforms.materialFlags.y & 2u) == 0u", source)
        self.assertIn("sampler componentSampler [[sampler(1)]]", source)
        self.assertIn("out.componentUV = uniforms.componentTextureFrame0.xy", source)
        self.assertIn("componentTexture.sample(componentSampler, in.componentUV).a", source)
        self.assertIn("uniforms.componentTextureFrame0.xy", source)
        self.assertIn("uniforms.emissiveColorAndBrightness.w", source)
        self.assertIn("uniforms.lightDirectionIntensity[lightIndex]", source)
        self.assertIn("max(dot(normal, light.xyz), 0.0)", source)
        self.assertNotIn("lighting / (float3(1.0) + lighting)", source)
        self.assertIn("uniforms.materialFlags.w != 0", source)
        self.assertIn("surfaceColor = mix(albedo.rgb, tinted, albedo.a)", source)
        self.assertIn("uniforms.viewTintBackAndEnabled.w > 0.5", source)
        self.assertIn("uniforms.cameraPosition.xyz - in.worldPosition", source)
        self.assertIn("litColor * outputAlpha", source)

    def test_pipeline_typechecks_against_decoded_vertex_contract(self) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-static-model-swift-") as tmp:
            root = Path(tmp)
            lighting_stub = root / "LightingStub.swift"
            lighting_stub.write_text(LIGHTING_STUB, encoding="utf-8")
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-modules")
            environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-modules")
            completed = subprocess.run(
                [
                    swiftc,
                    "-typecheck",
                    str(MODEL_SOURCE),
                    str(SAMPLING_SOURCE),
                    str(UV_TRANSFORM_SOURCE),
                    str(DIRECTIONAL_LIGHT_SOURCE),
                    str(POINT_LIGHT_SOURCE),
                    str(SPOT_LIGHT_SOURCE),
                    str(lighting_stub),
                    str(LIGHT_SOURCE),
                    str(DYNAMIC_SNAPSHOT_SOURCE),
                    str(DYNAMIC_LAYER_VALUES_SOURCE),
                    str(PERFORMANCE_COUNTER_SOURCE),
                    str(SCENE_ROOT / "Resources/Textures/SceneResourceBudget.swift"),
                    str(BINDINGS_SOURCE),
                    str(PIPELINE_SOURCE),
                    str(SHADOW_SOURCE),
                ],
                capture_output=True,
                text=True,
                env=environment,
            )
        self.assertEqual(completed.returncode, 0, completed.stderr)

    def test_material_consumes_dynamic_values_and_preserves_cull_mode(self) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            self.skipTest("swiftc is unavailable")
        harness_source = r'''
import Metal
import simd

@main
enum MaterialHarness {
    static func main() {
        precondition(SceneStaticModelPipeline.hasExpectedUniformABI)
        let definitions: [SceneDynamicTargetDefinition] = [
            .init(
                target: .materialConstant(
                    layerID: 7, passIndex: 0, name: "color"
                ),
                valueType: .vector3,
                authoredValue: .vector3(1, 1, 1)
            ),
            .init(
                target: .materialConstant(
                    layerID: 7, passIndex: 0, name: "emissivecolor"
                ),
                valueType: .vector3,
                authoredValue: .vector3(1, 1, 1)
            ),
            .init(
                target: .materialConstant(
                    layerID: 7, passIndex: 0, name: "alpha"
                ),
                valueType: .scalar,
                authoredValue: .scalar(1)
            ),
            .init(
                target: .materialConstant(
                    layerID: 7, passIndex: 0, name: "brightness"
                ),
                valueType: .scalar,
                authoredValue: .scalar(1)
            ),
            .init(
                target: .materialConstant(
                    layerID: 7, passIndex: 0,
                    name: "emissivebrightness"
                ),
                valueType: .scalar,
                authoredValue: .scalar(1)
            ),
        ]
        let snapshot = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 1,
            generation: 2,
            definitions: definitions,
            userValues: [
                .materialConstant(
                    layerID: 7, passIndex: 0, name: "color"
                ): .vector3(0.2, 0.4, 0.6),
                .materialConstant(
                    layerID: 7, passIndex: 0, name: "emissivecolor"
                ): .vector3(0.9, 0.3, 0.1),
                .materialConstant(
                    layerID: 7, passIndex: 0, name: "alpha"
                ): .scalar(0.4),
                .materialConstant(
                    layerID: 7, passIndex: 0, name: "brightness"
                ): .scalar(1.75),
                .materialConstant(
                    layerID: 7, passIndex: 0,
                    name: "emissivebrightness"
                ): .scalar(3),
            ]
        ).snapshot
        let base = SceneStaticModelMaterial(
            color: SIMD3(1, 1, 1), opacity: 1,
            receivesLighting: true, textureAlphaIsOpacity: true,
            textureAlphaIsTintMask: false,
            emissiveColor: SIMD3(1, 1, 1), emissiveBrightness: 1,
            brightness: 1, usesHDRBrightness: true,
            viewTint: .init(front: SIMD3(1, 0, 0), back: SIMD3(0, 0, 1),
                exponent: 2, usesDynamicBackColor: true)
        )
        precondition(base.cullMode == .back)
        for mode: MTLCullMode in [.none, .back, .front] {
            var authoredCull = base
            authoredCull.cullMode = mode
            let dynamic = authoredCull.resolvingDynamicValues(
                layerID: 7, snapshot: snapshot
            )
            precondition(dynamic.opacity == 0.4 && dynamic.color != base.color)
            precondition(dynamic.cullMode == mode)
            let tint = dynamic.resolvingDynamicViewTintBack(SIMD3(0.8, 0.7, 0.6))
            precondition(tint.viewTint?.back == SIMD3<Float>(0.8, 0.7, 0.6))
            precondition(tint.cullMode == mode)
            precondition(authoredCull.resolvingDynamicValues(
                layerID: 8, snapshot: snapshot
            ).cullMode == mode)
        }
        let resolved = base.resolvingDynamicValues(
            layerID: 7, snapshot: snapshot
        )
        precondition(resolved.color == SIMD3<Float>(0.2, 0.4, 0.6))
        precondition(resolved.emissiveColor == SIMD3<Float>(0.9, 0.3, 0.1))
        precondition(resolved.opacity == 0.4)
        precondition(resolved.brightness == 1.75)
        precondition(resolved.emissiveBrightness == 3)
        precondition(base.resolvingDynamicValues(
            layerID: 8, snapshot: snapshot
        ).color == base.color)
        var unproven = base
        unproven.channelBindings = .init(state: .unavailable, bindings: [], rejectionReason: "interface-unproven")
        let legacy = unproven.resolvingDynamicValues(layerID: 7, snapshot: snapshot)
        precondition(legacy.color == resolved.color && legacy.opacity == resolved.opacity)
        precondition(legacy.brightness == resolved.brightness && legacy.emissiveBrightness == resolved.emissiveBrightness)
        precondition(legacy.emissiveColor == resolved.emissiveColor)
        let authoredBindings = SceneStaticModelMaterialBindings(
            state: .authored,
            bindings: [
                .init(channel: .alpha, uniformName: "g_TintAlpha", materialKey: "Alpha", components: [0.02]),
                .init(channel: .color, uniformName: "g_TintColor", materialKey: "Color", components: [0.2, 0.4, 0.6]),
                .init(channel: .brightness, uniformName: "g_Brightness", materialKey: "Brigtness", components: [1.25]),
            ],
            rejectionReason: nil
        )
        var authored = base
        authored.channelBindings = authoredBindings
        let exactPath = "materials/authored.json"
        let unrelatedPath = "materials/peer.json"
        func target(_ name: String, layerID: Int = 7, path: String = "materials/authored.json") -> SceneDynamicTarget {
            .materialConstant(layerID: layerID, passIndex: 0, name: name, materialPath: path)
        }
        let exactDefinitions: [SceneDynamicTargetDefinition] = [
            .init(target: target("Alpha"), valueType: .scalar, authoredValue: .scalar(0.02)),
            .init(target: target("Color"), valueType: .vector3, authoredValue: .vector3(0.2, 0.4, 0.6)),
            .init(target: target("Brigtness"), valueType: .scalar, authoredValue: .scalar(1.25)),
            .init(target: target("alpha"), valueType: .scalar, authoredValue: .scalar(1)),
            .init(target: target("color"), valueType: .vector3, authoredValue: .vector3(1, 0, 0)),
            .init(target: target("brightness"), valueType: .scalar, authoredValue: .scalar(8)),
            .init(target: target("Alpha", layerID: 8), valueType: .scalar, authoredValue: .scalar(0.9)),
            .init(target: target("Alpha", path: unrelatedPath), valueType: .scalar, authoredValue: .scalar(0.6)),
        ]
        let exactSnapshot = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 2, generation: 2, definitions: exactDefinitions,
            userValues: [
                target("Alpha"): .scalar(0.3), target("Color"): .vector3(0.1, 0.5, 0.9),
                target("Brigtness"): .scalar(2), target("alpha"): .scalar(1),
                target("color"): .vector3(1, 0, 0), target("brightness"): .scalar(8),
                target("Alpha", layerID: 8): .scalar(0.9),
                target("Alpha", path: unrelatedPath): .scalar(0.6),
            ]
        ).snapshot
        let exact = authored.resolvingDynamicValues(layerID: 7, materialPath: exactPath, snapshot: exactSnapshot)
        precondition(exact.opacity == 0.3)
        precondition(exact.color == SIMD3<Float>(0.1, 0.5, 0.9))
        precondition(exact.brightness == 2)
        precondition(exact.channelBindings == authoredBindings)
        precondition(authored.resolvingDynamicValues(layerID: 8, materialPath: exactPath, snapshot: exactSnapshot).opacity == 0.9)
        precondition(authored.resolvingDynamicValues(layerID: 7, materialPath: unrelatedPath, snapshot: exactSnapshot).opacity == 0.6)
        precondition(authored.resolvingDynamicValues(layerID: 9, materialPath: exactPath, snapshot: exactSnapshot).opacity == base.opacity)

        var defaultsOnly = authored
        defaultsOnly.channelBindings = SceneStaticModelMaterialBindings(
            state: .authored,
            bindings: [
                .init(channel: .alpha, uniformName: "g_TintAlpha", materialKey: nil, components: [0.02]),
                .init(channel: .color, uniformName: "g_TintColor", materialKey: nil, components: [0.2, 0.4, 0.6]),
                .init(channel: .brightness, uniformName: "g_Brightness", materialKey: nil, components: [1.25]),
            ], rejectionReason: nil
        )
        let unchanged = defaultsOnly.resolvingDynamicValues(layerID: 7, materialPath: exactPath, snapshot: exactSnapshot)
        precondition(unchanged.opacity == defaultsOnly.opacity && unchanged.color == defaultsOnly.color)
        precondition(unchanged.brightness == defaultsOnly.brightness)
        precondition(exact.resolvingDynamicViewTintBack(SIMD3(0.8, 0.7, 0.6)).channelBindings == authoredBindings)
        let overflowSnapshot = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 3, generation: 2, definitions: [
                .init(target: target("Brigtness"), valueType: .scalar, authoredValue: .scalar(1.25)),
            ], userValues: [target("Brigtness"): .scalar(1e100)]
        ).snapshot
        precondition(authored.resolvingDynamicValues(
            layerID: 7, materialPath: exactPath, snapshot: overflowSnapshot
        ).brightness == authored.brightness)
        func transform(_ scale: SIMD3<Float>) -> simd_float4x4 {
            var matrix = matrix_identity_float4x4
            matrix.columns.0.x = scale.x
            matrix.columns.1.y = scale.y
            matrix.columns.2.z = scale.z
            return matrix
        }
        for scale: Float in [1, 0.001, 0.000001, 1e-30, 1e30] {
            let normal = SceneStaticModelPipeline.normalMatrix(
                for: transform(SIMD3(repeating: scale))
            )
            precondition(normal != nil)
            precondition(simd_length(normal!.columns.0 - SIMD3(1, 0, 0)) < 1e-5)
            precondition(simd_length(normal!.columns.1 - SIMD3(0, 1, 0)) < 1e-5)
            precondition(simd_length(normal!.columns.2 - SIMD3(0, 0, 1)) < 1e-5)
        }
        let anisotropic = SceneStaticModelPipeline.normalMatrix(
            for: transform(SIMD3(-0.001, 0.002, 0.004))
        )!
        precondition(abs(anisotropic.columns.0.x + 1) < 1e-5)
        precondition(abs(anisotropic.columns.1.y - 0.5) < 1e-5)
        precondition(abs(anisotropic.columns.2.z - 0.25) < 1e-5)
        precondition(SceneStaticModelPipeline.normalMatrix(
            for: transform(SIMD3(1, 0, 1))
        ) == nil)
        precondition(SceneStaticModelPipeline.normalMatrix(
            for: transform(SIMD3(Float.nan, 1, 1))
        ) == nil)
        var singular = matrix_identity_float4x4
        singular.columns.1 = singular.columns.0
        precondition(SceneStaticModelPipeline.normalMatrix(for: singular) == nil)
    }
}
'''
        with tempfile.TemporaryDirectory(prefix="mwx-model-material-consumer-") as tmp:
            root = Path(tmp)
            lighting_stub = root / "LightingStub.swift"
            harness = root / "MaterialHarness.swift"
            executable = root / "MaterialHarness"
            lighting_stub.write_text(LIGHTING_STUB, encoding="utf-8")
            harness.write_text(harness_source, encoding="utf-8")
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-modules")
            environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-modules")
            compiled = subprocess.run(
                [
                    swiftc,
                    str(MODEL_SOURCE),
                    str(SAMPLING_SOURCE),
                    str(UV_TRANSFORM_SOURCE),
                    str(DIRECTIONAL_LIGHT_SOURCE),
                    str(POINT_LIGHT_SOURCE),
                    str(SPOT_LIGHT_SOURCE),
                    str(lighting_stub),
                    str(LIGHT_SOURCE),
                    str(DYNAMIC_SNAPSHOT_SOURCE),
                    str(DYNAMIC_LAYER_VALUES_SOURCE),
                    str(PERFORMANCE_COUNTER_SOURCE),
                    str(SCENE_ROOT / "Resources/Textures/SceneResourceBudget.swift"),
                    str(BINDINGS_SOURCE),
                    str(PIPELINE_SOURCE),
                    str(SHADOW_SOURCE),
                    str(harness),
                    "-framework", "Metal",
                    "-o", str(executable),
                ],
                capture_output=True,
                text=True,
                env=environment,
            )
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            completed = subprocess.run(
                [str(executable)], capture_output=True, text=True, env=environment
            ) if compiled.returncode == 0 else compiled
        self.assertEqual(completed.returncode, 0, completed.stderr)

    def test_light_snapshot_publishes_bounded_spot_geometry_and_dynamic_color(self) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            self.skipTest("swiftc is unavailable")
        harness_source = r'''
import simd

@main
enum LightSnapshotHarness {
    static func main() {
        let spot = SceneSpotLightDefinition(
            kind: "lspot", colorRGB: [1, 1, 1], intensity: 3,
            radius: 6000, innerConeDegrees: 60, outerConeDegrees: 90,
            density: nil, exponent: nil, volumetricsExponent: nil,
            castsVolumetrics: nil, castsShadow: true, isSolid: true
        )
        let point = ScenePointLightDefinition(
            kind: "lpoint", colorRGB: [0.8, 0.6, 0.4], intensity: 2,
            radius: 40, castsVolumetrics: false, castsShadow: false,
            isSolid: true
        )
        let descriptor = SceneRenderDescriptor(
            lighting: .init(
                ambientColorRGB: [0.1, 0.2, 0.3],
                skylightColorRGB: [0.2, 0.1, 0],
                lightClasses: .init(directional: false, point: true, spot: true),
                distanceFog: .init(color: [0.1, 0.2, 0.3], start: 10, end: 100,
                                   startDensity: 0.2, endDensity: 0.8)
            ),
            layers: [
                .init(
                    id: 6, visible: true, pointLight: point,
                    spotLight: nil, directionalLight: nil
                ),
                .init(
                    id: 7, visible: true, pointLight: nil,
                    spotLight: spot, directionalLight: nil
                ),
            ]
        )
        let frame = simd_float4x4(columns: (
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(10, 20, 30, 1)
        ))
        let dynamicSnapshot = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 1,
            generation: 1,
            definitions: [
                .init(
                    target: .layer(layerID: 6, field: .intensity),
                    valueType: .scalar,
                    authoredValue: .scalar(2)
                ),
                .init(
                    target: .layer(layerID: 7, field: .intensity),
                    valueType: .scalar,
                    authoredValue: .scalar(3)
                ),
            ],
            userValues: [.layer(layerID: 6, field: .intensity): .scalar(4)],
            sceneScriptValues: [
                .layer(layerID: 7, field: .intensity): .scalar(5),
            ]
        ).snapshot
        let snapshot = SceneLightSnapshot.make(
            descriptor: descriptor,
            worldFramesByLayerID: [6: frame, 7: frame],
            dynamicLayerColors: [
                6: SIMD3(1, 0.5, 0.25),
                7: SIMD3(0.25, 0.5, 1),
            ],
            dynamicSnapshot: dynamicSnapshot
        )
        let explicitBlack = SceneRenderDescriptor(
            lighting: .init(ambientColorRGB: [0, 0, 0], skylightColorRGB: [0, 0, 0]),
            layers: []
        )
        precondition(SceneLightSnapshot.make(
            descriptor: explicitBlack, worldFramesByLayerID: [:]
        ).ambient == .zero)
        let omittedAmbient = SceneRenderDescriptor(lighting: nil, layers: [])
        precondition(SceneLightSnapshot.make(
            descriptor: omittedAmbient, worldFramesByLayerID: [:]
        ).ambient == .zero)
        // An unadmitted spot class (lightconfig.spot absent) must stay inert.
        let ungatedSpotDescriptor = SceneRenderDescriptor(
            lighting: .init(
                ambientColorRGB: [0, 0, 0], skylightColorRGB: [0, 0, 0],
                lightClasses: .init(directional: false, point: false, spot: false)
            ),
            layers: [
                .init(
                    id: 12, visible: true, pointLight: nil,
                    spotLight: spot, directionalLight: nil
                ),
            ]
        )
        precondition(SceneLightSnapshot.make(
            descriptor: ungatedSpotDescriptor,
            worldFramesByLayerID: [12: frame]
        ).spot.isEmpty)
        // Official directional semantics (own-fixture black-box, 2026-10-06):
        // angle values are radians; an exactly identity rotation keeps the
        // official default aim (0, 0, -1) and yaw sweeps XZ toward +Z.
        let directionalFrame = simd_float4x4(columns: (
            SIMD4<Float>(0.5403023, 0, -0.84147096, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0.84147096, 0, 0.5403023, 0),
            SIMD4<Float>(10, 20, 30, 1)
        ))
        let directionalDescriptor = SceneRenderDescriptor(
            lighting: .init(
                ambientColorRGB: [0, 0, 0], skylightColorRGB: [0, 0, 0],
                lightClasses: .init(directional: true, point: false, spot: false)
            ),
            layers: [
                .init(
                    id: 13, visible: true, pointLight: nil, spotLight: nil,
                    directionalLight: .init(colorRGB: [1, 1, 1], intensity: 4)
                ),
                .init(
                    id: 14, visible: true, anglesXYZ: [0, 1, 0],
                    pointLight: nil, spotLight: nil,
                    directionalLight: .init(colorRGB: [1, 1, 1], intensity: 4)
                ),
            ]
        )
        let directionalSnapshot = SceneLightSnapshot.make(
            descriptor: directionalDescriptor,
            worldFramesByLayerID: [13: frame, 14: directionalFrame]
        )
        precondition(directionalSnapshot.directional.count == 2)
        precondition(directionalSnapshot.directional[0].directionTowardLight
            == SIMD3(0, 0, -1))
        let yawed = directionalSnapshot.directional[1].directionTowardLight
        precondition(abs(yawed.x - 0.5403023) < 1e-4
            && abs(yawed.y) < 1e-4
            && abs(yawed.z - 0.84147096) < 1e-4)
        precondition(snapshot.ambient == SIMD3(0.3, 0.3, 0.3))
        precondition(snapshot.distanceFogColor == SIMD4(0.1, 0.2, 0.3, 1))
        precondition(snapshot.distanceFogRange == SIMD4(10, 100, 0.2, 0.8))
        precondition(snapshot.directional.isEmpty)
        precondition(snapshot.point.count == 1)
        precondition(snapshot.point[0].position == SIMD3(10, 20, 30))
        precondition(snapshot.point[0].color == SIMD3(1, 0.5, 0.25))
        precondition(snapshot.point[0].intensity == 4)
        precondition(snapshot.point[0].radius == 40)
        precondition(snapshot.spot.count == 1)
        precondition(snapshot.overflowCount == 0)
        let light = snapshot.spot[0]
        precondition(light.position == SIMD3(10, 20, 30))
        precondition(light.directionFromLight == SIMD3(0, 0, -1))
        precondition(light.color == SIMD3(0.25, 0.5, 1))
        precondition(light.intensity == 5 && light.radius == 6000)
        precondition(abs(light.innerConeCosine - cos(Float.pi / 6)) < 1e-6)
        precondition(abs(light.outerConeCosine - cos(Float.pi / 4)) < 1e-6)
        let liveTargets = SceneLightSnapshot.liveConsumerTargets(
            descriptor: descriptor
        )
        precondition(liveTargets == [
            .layer(layerID: 6, field: .color),
            .layer(layerID: 6, field: .intensity),
            .layer(layerID: 7, field: .color),
            .layer(layerID: 7, field: .intensity),
        ])
        let hiddenParentDescriptor = SceneRenderDescriptor(
            lighting: .init(
                ambientColorRGB: [0, 0, 0], skylightColorRGB: [0, 0, 0],
                lightClasses: .init(directional: true, point: true, spot: true)
            ),
            layers: [
                .init(
                    id: 8, visible: false, pointLight: nil,
                    spotLight: nil, directionalLight: nil
                ),
                .init(
                    id: 9, visible: false, pointLight: nil,
                    spotLight: nil,
                    directionalLight: .init(
                        colorRGB: [1, 1, 1], intensity: 11
                    ),
                    parentID: 8
                ),
            ]
        )
        precondition(SceneLightSnapshot.liveConsumerTargets(
            descriptor: hiddenParentDescriptor
        ) == [
            .layer(layerID: 9, field: .color),
            .layer(layerID: 9, field: .intensity),
        ])
        let activatedSnapshot = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 2,
            generation: 2,
            definitions: [
                .init(
                    target: .layer(layerID: 8, field: .visibility),
                    valueType: .bool, authoredValue: .bool(false)
                ),
                .init(
                    target: .layer(layerID: 9, field: .visibility),
                    valueType: .bool, authoredValue: .bool(false)
                ),
                .init(
                    target: .layer(layerID: 9, field: .intensity),
                    valueType: .scalar, authoredValue: .scalar(11)
                ),
            ],
            userValues: [
                .layer(layerID: 8, field: .visibility): .bool(true),
                .layer(layerID: 9, field: .visibility): .bool(true),
                .layer(layerID: 9, field: .intensity): .scalar(19),
            ]
        ).snapshot
        let hiddenLayersByID = Dictionary(uniqueKeysWithValues:
            hiddenParentDescriptor.layers.map { ($0.id, $0) }
        )
        // Lights are admitted regardless of the layer visibility flag
        // (3589454154 authors `lpoint` with `visible:false` and the official
        // client still lights the scene from it); the dynamic intensity
        // snapshot remains the activation channel.
        let activated = SceneLightSnapshot.make(
            descriptor: hiddenParentDescriptor,
            worldFramesByLayerID: [9: frame],
            dynamicSnapshot: activatedSnapshot
        )
        precondition(activated.directional.map(\.intensity) == [19])

        func makePoint(_ intensity: Float, radius: Float = 40)
            -> ScenePointLightDefinition {
            .init(
                kind: "lpoint", colorRGB: [1, 1, 1], intensity: intensity,
                radius: radius, castsVolumetrics: nil, castsShadow: nil,
                isSolid: nil
            )
        }
        func direction(_ intensity: Float)
            -> SceneDirectionalLightDefinition {
            .init(colorRGB: [1, 1, 1], intensity: intensity)
        }
        func cone(_ intensity: Float) -> SceneSpotLightDefinition {
            .init(
                kind: "lspot", colorRGB: [1, 1, 1], intensity: intensity,
                radius: 40, innerConeDegrees: 60, outerConeDegrees: 90,
                density: nil, exponent: nil, volumetricsExponent: nil,
                castsVolumetrics: nil, castsShadow: nil, isSolid: nil
            )
        }
        let orderedDescriptor = SceneRenderDescriptor(
            lighting: .init(
                ambientColorRGB: [0, 0, 0], skylightColorRGB: [0, 0, 0],
                lightClasses: .init(directional: true, point: true, spot: true)
            ),
            layers: [
                .init(id: 1, visible: true, pointLight: nil,
                      spotLight: nil, directionalLight: direction(11)),
                .init(id: 2, visible: true, pointLight: makePoint(12),
                      spotLight: nil, directionalLight: nil),
                .init(id: 3, visible: true, pointLight: nil,
                      spotLight: cone(13), directionalLight: nil,
                      parentID: 30),
                .init(id: 4, visible: true, pointLight: nil,
                      spotLight: nil, directionalLight: direction(14)),
                .init(id: 5, visible: true, pointLight: makePoint(15),
                      spotLight: nil, directionalLight: nil),
                .init(id: 6, visible: true, pointLight: nil,
                      spotLight: cone(16), directionalLight: nil,
                      displayScriptOwnership: .init(
                          visible: true, alpha: false
                      )),
                .init(id: 7, visible: true, pointLight: makePoint(17),
                      spotLight: nil, directionalLight: nil),
                .init(id: 30, visible: false, pointLight: nil,
                      spotLight: nil, directionalLight: nil),
            ],
            renderOrderLayerIDs: [7, 6, 5, 4, 30, 3, 2, 1]
        )
        let orderedByID = Dictionary(
            uniqueKeysWithValues: orderedDescriptor.layers.map { ($0.id, $0) }
        )
        let orderedIDs = SceneLightSnapshot.orderedLightLayerIDs(
            descriptor: orderedDescriptor, layersByID: orderedByID
        )
        precondition(orderedIDs == [7, 6, 5, 4, 3, 2, 1])
        // Script-hidden lights stay admitted: illumination is independent of
        // the visibility flag (3589454154 `lpoint` visible:false still lights
        // the scene officially), so the four-slot budget spans all seven
        // ordered lights and three overflow.
        let bounded = SceneLightSnapshot.make(
            descriptor: orderedDescriptor,
            worldFramesByLayerID: Dictionary(
                uniqueKeysWithValues: (1...7).map { ($0, frame) }
            ),
            candidateLayerIDs: orderedIDs,
            layersByID: orderedByID
        )
        precondition(bounded.directional.map(\.intensity) == [14])
        precondition(bounded.point.map(\.intensity) == [17, 15])
        precondition(bounded.spot.map(\.intensity) == [16])
        precondition(bounded.overflowCount == 3)

        let invalidRadiusDescriptor = SceneRenderDescriptor(
            lighting: nil,
            layers: [
                .init(id: 8, visible: true, pointLight: makePoint(1, radius: 0),
                      spotLight: nil, directionalLight: nil),
                .init(id: 9, visible: true, pointLight: makePoint(1, radius: -1),
                      spotLight: nil, directionalLight: nil),
            ]
        )
        let invalidRadius = SceneLightSnapshot.make(
            descriptor: invalidRadiusDescriptor,
            worldFramesByLayerID: [8: frame, 9: frame]
        )
        precondition(invalidRadius.point.isEmpty)
        precondition(invalidRadius.ambient == .zero)
    }
}
'''
        with tempfile.TemporaryDirectory(prefix="mwx-light-snapshot-") as tmp:
            root = Path(tmp)
            lighting_stub = root / "LightingStub.swift"
            harness = root / "LightSnapshotHarness.swift"
            executable = root / "LightSnapshotHarness"
            lighting_stub.write_text(LIGHTING_STUB, encoding="utf-8")
            harness.write_text(harness_source, encoding="utf-8")
            completed = subprocess.run(
                [
                    swiftc,
                    "-parse-as-library",
                    str(DIRECTIONAL_LIGHT_SOURCE),
                    str(POINT_LIGHT_SOURCE),
                    str(SPOT_LIGHT_SOURCE),
                    str(lighting_stub),
                    str(DYNAMIC_SNAPSHOT_SOURCE),
                    str(DYNAMIC_LAYER_VALUES_SOURCE),
                    str(VISIBILITY_SOURCE),
                    str(LIGHT_SOURCE),
                    str(harness),
                    "-o", str(executable),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            completed = subprocess.run(
                [str(executable)], capture_output=True, text=True
            )
        self.assertEqual(completed.returncode, 0, completed.stderr)

    def test_depth_plan_isolates_only_near_coincident_same_geometry(self) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            self.skipTest("swiftc is unavailable")
        harness_source = r'''
import simd

@main
enum DepthPlanHarness {
    static func matrix(
        scale: Float,
        translation: SIMD3<Float> = .zero
    ) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4(scale, 0, 0, 0),
            SIMD4(0, scale, 0, 0),
            SIMD4(0, 0, scale, 0),
            SIMD4(translation.x, translation.y, translation.z, 1)
        ))
    }

    static func main() {
        var shellPlan = SceneStaticModelDepthPlan()
        precondition(shellPlan.target(
            geometryIdentity: "sphere",
            modelMatrix: matrix(scale: 65)
        ) == .shared)
        precondition(shellPlan.target(
            geometryIdentity: "sphere",
            modelMatrix: matrix(scale: 65.1)
        ) == .isolated)

        var identityPlan = SceneStaticModelDepthPlan()
        _ = identityPlan.target(
            geometryIdentity: "sphere",
            modelMatrix: matrix(scale: 65)
        )
        precondition(identityPlan.target(
            geometryIdentity: "cube",
            modelMatrix: matrix(scale: 65.1)
        ) == .shared)

        var distancePlan = SceneStaticModelDepthPlan()
        _ = distancePlan.target(
            geometryIdentity: "sphere",
            modelMatrix: matrix(scale: 65)
        )
        precondition(distancePlan.target(
            geometryIdentity: "sphere",
            modelMatrix: matrix(
                scale: 65.1,
                translation: SIMD3(20, 0, 0)
            )
        ) == .shared)

        var scalePlan = SceneStaticModelDepthPlan()
        _ = scalePlan.target(
            geometryIdentity: "sphere",
            modelMatrix: matrix(scale: 65)
        )
        precondition(scalePlan.target(
            geometryIdentity: "sphere",
            modelMatrix: matrix(scale: 70)
        ) == .shared)
    }
}
'''
        with tempfile.TemporaryDirectory(prefix="mwx-model-depth-plan-") as tmp:
            root = Path(tmp)
            lighting_stub = root / "LightingStub.swift"
            harness = root / "DepthPlanHarness.swift"
            executable = root / "DepthPlanHarness"
            lighting_stub.write_text(LIGHTING_STUB, encoding="utf-8")
            harness.write_text(harness_source, encoding="utf-8")
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-modules")
            environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-modules")
            compiled = subprocess.run(
                [
                    swiftc,
                    str(MODEL_SOURCE),
                    str(SAMPLING_SOURCE),
                    str(UV_TRANSFORM_SOURCE),
                    str(DIRECTIONAL_LIGHT_SOURCE),
                    str(POINT_LIGHT_SOURCE),
                    str(SPOT_LIGHT_SOURCE),
                    str(lighting_stub),
                    str(LIGHT_SOURCE),
                    str(DYNAMIC_SNAPSHOT_SOURCE),
                    str(DYNAMIC_LAYER_VALUES_SOURCE),
                    str(PERFORMANCE_COUNTER_SOURCE),
                    str(SCENE_ROOT / "Resources/Textures/SceneResourceBudget.swift"),
                    str(BINDINGS_SOURCE),
                    str(PIPELINE_SOURCE),
                    str(SHADOW_SOURCE),
                    str(harness),
                    "-framework", "Metal",
                    "-o", str(executable),
                ],
                capture_output=True,
                text=True,
                env=environment,
            )
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            completed = subprocess.run(
                [str(executable)],
                capture_output=True,
                text=True,
                env=environment,
            ) if compiled.returncode == 0 else compiled
        self.assertEqual(completed.returncode, 0, completed.stderr)

    def test_pipeline_uses_fixed_depth_blend_and_slots(self) -> None:
        source = PIPELINE_SOURCE.read_text(encoding="utf-8")
        self.assertIn("material.usesHDRBrightness", source)
        self.assertIn("material.color.x * brightness", source)
        for contract in (
            "device.makeDefaultLibrary()",
            "writingDepthDescriptor.depthCompareFunction = .greaterEqual",
            "writingDepthDescriptor.isDepthWriteEnabled = true",
            "nonwritingDepthDescriptor.depthCompareFunction = .greaterEqual",
            "nonwritingDepthDescriptor.isDepthWriteEnabled = false",
            "attachment.sourceRGBBlendFactor = .one",
            "attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha",
            "encoder.setFrontFacing(.counterClockwise)",
            "encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)",
            "encoder.setFragmentTexture(texture, index: 0)",
            "encoder.setFragmentTexture(emissiveMask ?? texture, index: 1)",
            "samplerStates.state(for: sampling)",
            "material: SceneStaticModelMaterial",
            "emissiveMask: MTLTexture?",
            "emissiveMaskTextureFrame: SceneTextureUVTransform?",
            "emissiveMaskSampling: SceneTextureSampling?",
            "lighting: SceneLightSnapshot",
            "struct SceneStaticModelDepthPlan",
            "case isolated",
            "lhs.geometryIdentity == rhs.geometryIdentity",
            "encoder.setFragmentBytes(",
            "sampling.isResolvedForMaterialProgram",
            "!sampling.usesClampBorderFallback",
            "writesDepth ? writingDepthState : nonwritingDepthState",
            "indexType: mesh.indexType",
            "indexType: usesWideIndices ? .uint32 : .uint16",
            "indices.contains { $0 > UInt16.max }",
        ):
            self.assertIn(contract, source)
        self.assertNotIn("makeLibrary(source:", source)
        self.assertNotIn("generic4", source.lower())
        self.assertNotIn("chroma4", source.lower())
        self.assertNotIn("parity", source.lower())

if __name__ == "__main__":
    unittest.main()
