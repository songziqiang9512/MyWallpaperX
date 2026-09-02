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
METAL_SOURCE = SCENE_ROOT / "Rendering/SceneStaticModel.metal"
PIPELINE_SOURCE = SCENE_ROOT / "Rendering/SceneStaticModelPipeline.swift"
MODEL_SOURCE = SCENE_ROOT / "Format/SceneMdlStaticModel.swift"
SAMPLING_SOURCE = SCENE_ROOT / "Resources/SceneTextureSampling.swift"
UV_TRANSFORM_SOURCE = SCENE_ROOT / "Resources/SceneTextureUVTransform.swift"
LIGHT_SOURCE = SCENE_ROOT / "Rendering/SceneLightSnapshot.swift"
DIRECTIONAL_LIGHT_SOURCE = (
    SCENE_ROOT / "Format/SceneDirectionalLightDefinition.swift"
)

LIGHTING_STUB = r'''
struct SceneRenderDescriptor {
    struct LightingDescriptor {
        let ambientColorRGB: [Float]?
        let skylightColorRGB: [Float]?
    }

    struct Layer {
        let id: Int
        let visible: Bool?
        let directionalLight: SceneDirectionalLightDefinition?
    }

    let lighting: LightingDescriptor?
    let layers: [Layer]
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
        self.assertIn("sampler colorSampler [[sampler(0)]]", source)
        self.assertNotIn("constexpr sampler", source)
        self.assertIn("modelVertex.uv.x * uniforms.textureFrame0.zw", source)
        self.assertIn("modelVertex.uv.y * uniforms.textureFrame1.xy", source)
        self.assertIn("uniforms.materialFlags.x != 0", source)
        self.assertIn("uniforms.lightDirectionIntensity[lightIndex]", source)
        self.assertIn("max(dot(normal, light.xyz), 0.0)", source)
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
                    str(lighting_stub),
                    str(LIGHT_SOURCE),
                    str(PIPELINE_SOURCE),
                ],
                capture_output=True,
                text=True,
                env=environment,
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
                    str(lighting_stub),
                    str(LIGHT_SOURCE),
                    str(PIPELINE_SOURCE),
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

    def test_pipeline_uses_fixed_depth_cull_blend_and_slots(self) -> None:
        source = PIPELINE_SOURCE.read_text(encoding="utf-8")
        for contract in (
            "device.makeDefaultLibrary()",
            "writingDepthDescriptor.depthCompareFunction = .greaterEqual",
            "writingDepthDescriptor.isDepthWriteEnabled = true",
            "nonwritingDepthDescriptor.depthCompareFunction = .greaterEqual",
            "nonwritingDepthDescriptor.isDepthWriteEnabled = false",
            "attachment.sourceRGBBlendFactor = .one",
            "attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha",
            "encoder.setCullMode(.back)",
            "encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)",
            "encoder.setFragmentTexture(texture, index: 0)",
            "samplerStates.state(for: sampling)",
            "material: SceneStaticModelMaterial",
            "lighting: SceneLightSnapshot",
            "struct SceneStaticModelDepthPlan",
            "case isolated",
            "lhs.geometryIdentity == rhs.geometryIdentity",
            "encoder.setFragmentBytes(",
            "sampling.isResolvedForMaterialProgram",
            "!sampling.usesClampBorderFallback",
            "writesDepth ? writingDepthState : nonwritingDepthState",
            "indexType: .uint16",
        ):
            self.assertIn(contract, source)
        self.assertNotIn("makeLibrary(source:", source)
        self.assertNotIn("generic4", source.lower())
        self.assertNotIn("chroma4", source.lower())
        self.assertNotIn("parity", source.lower())

if __name__ == "__main__":
    unittest.main()
