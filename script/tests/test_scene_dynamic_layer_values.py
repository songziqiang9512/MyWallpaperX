#!/usr/bin/env python3

from __future__ import annotations

from script.tests.source_family import read_source_family
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
DYNAMIC_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneDynamicSnapshot.swift"
LAYER_VALUES_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneDynamicLayerValues.swift"
RENDERER_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer.swift"
EFFECT_EXECUTION_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+EffectExecution.swift"
)
UTILITY_FRAME_RENDERER_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneUtilityPlanFrameRenderer.swift"
)
COMPOSITOR_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneImageLayerCompositor.swift"
COMPOSITOR_UNIFORMS_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneImageLayerCompositor+Uniforms.swift"
)
UTILITY_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneUtilityLayerRenderer.swift"

HARNESS = r'''
import Foundation

@main
enum Harness {
    static func main() throws {
        let alpha = SceneDynamicTarget.layer(layerID: 7, field: .alpha)
        let otherAlpha = SceneDynamicTarget.layer(layerID: 8, field: .alpha)
        let color = SceneDynamicTarget.layer(layerID: 7, field: .color)
        let otherColor = SceneDynamicTarget.layer(layerID: 8, field: .color)
        let resolver = SceneDynamicSnapshotResolver()
        let dynamic = resolver.resolve(
            frameIndex: 1,
            generation: 1,
            definitions: [
                .init(target: alpha, valueType: .scalar, authoredValue: .scalar(0.6)),
                .init(target: otherAlpha, valueType: .scalar, authoredValue: .scalar(0.8)),
                .init(target: color, valueType: .vector3, authoredValue: .vector3(0.1, 0.2, 0.3)),
                .init(target: otherColor, valueType: .vector3, authoredValue: .vector3(0.2, 0.3, 0.4)),
            ],
            userValues: [
                alpha: .scalar(0.25),
                otherAlpha: .scalar(2),
                color: .vector3(-0.25, 0.5, 1.25),
                otherColor: .vector3(.infinity, 0.5, 0.5),
            ]
        ).snapshot
        let wrongType = resolver.resolve(
            frameIndex: 2,
            generation: 1,
            definitions: [
                .init(target: alpha, valueType: .string, authoredValue: .string("bad")),
                .init(target: color, valueType: .string, authoredValue: .string("bad")),
            ]
        ).snapshot
        let empty = SceneDynamicSnapshot.empty(frameIndex: 3)
        let payload: [String: Any] = [
            "dynamic": value(layerID: 7, authored: 0.6, snapshot: dynamic),
            "dynamicClamp": value(layerID: 8, authored: 0.6, snapshot: dynamic),
            "wrongLayer": value(layerID: 9, authored: 0.4, snapshot: dynamic),
            "wrongType": value(layerID: 7, authored: 0.3, snapshot: wrongType),
            "authored": value(layerID: 7, authored: 0.4, snapshot: empty),
            "authoredLow": value(layerID: 7, authored: -2, snapshot: empty),
            "authoredHigh": value(layerID: 7, authored: 3, snapshot: empty),
            "authoredNonFinite": value(layerID: 7, authored: .infinity, snapshot: empty),
            "default": value(layerID: 7, authored: nil, snapshot: empty),
            "colorDynamicClamp": components(colorValue(
                layerID: 7, authored: [0.6, 0.7, 0.8], snapshot: dynamic
            )),
            "colorNonFiniteFallback": components(colorValue(
                layerID: 8, authored: [0.6, 0.7, 0.8], snapshot: dynamic
            )),
            "colorWrongLayer": components(colorValue(
                layerID: 9, authored: [0.4, 0.5, 0.6], snapshot: dynamic
            )),
            "colorWrongType": components(colorValue(
                layerID: 7, authored: [0.3, 0.4, 0.5], snapshot: wrongType
            )),
            "colorAuthoredClamp": components(colorValue(
                layerID: 7, authored: [-0.2, 0.25, 1.2], snapshot: empty
            )),
            "colorAuthoredNonFinite": components(colorValue(
                layerID: 7, authored: [.nan, 0.5, 0.5], snapshot: empty
            )),
            "colorAuthoredPadded": components(colorValue(
                layerID: 7, authored: [0.2, 0.3], snapshot: empty
            )),
            "colorDefault": components(colorValue(
                layerID: 7, authored: nil, snapshot: empty
            )),
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func value(
        layerID: Int,
        authored: Double?,
        snapshot: SceneDynamicSnapshot
    ) -> Float {
        SceneDynamicLayerValues.alpha(
            layerID: layerID,
            authoredValue: authored,
            snapshot: snapshot
        )
    }

    static func colorValue(
        layerID: Int,
        authored: [Float]?,
        snapshot: SceneDynamicSnapshot
    ) -> SIMD3<Float> {
        SceneDynamicLayerValues.color(
            layerID: layerID,
            authoredValue: authored,
            snapshot: snapshot
        )
    }

    static func components(_ value: SIMD3<Float>) -> [Float] {
        [value.x, value.y, value.z]
    }
}
'''


UTILITY_ALPHA_HARNESS = r'''
import Foundation
import simd

// GPU surfaces are observation doubles. The production utility draw function
// makes all route, source-uniform and compositor-request decisions.
struct MTLTexture { let identity: Int }
struct SceneRenderDescriptor { struct Layer {} }
struct SceneUtilityLayerRuntimePlan {
    enum Kind { case composition, project, fullscreen }
    let shouldCapture: Bool
    let kind: Kind
}
enum SceneEffectExecutionOrigin { case utilityComposition, utilityProject, utilityFullscreen }
struct SceneImageLayerMasks {}
struct SceneDynamicSnapshot {}
struct SceneAudioSpectrumSnapshot {}
struct SceneDependencyEffectInput {}
struct SceneImageLayerPipeline {}
struct SceneOffscreenTexturePool {}
struct SceneResolvedMaterialFrameTargetPlan {}
struct SceneEffectExecutionFrameTrace {}
struct SceneTextureUVTransform { static let identity = Self() }
struct SceneLayerEffectSourceExtent {
    init?(pixelSize: CGSize) { if pixelSize.width <= 0 || pixelSize.height <= 0 { return nil } }
}
enum SceneMatrix {
    static func scale(_ value: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(diagonal: SIMD4(value.x, value.y, value.z, 1))
    }
}
struct SceneImageLayerUniformValues {
    let time: Float
    let alpha: Float
    let cursorUV: SIMD2<Float>
    let cursorIsInside: Bool
}
struct SceneImageLayerDrawRequest {
    let layer: SceneRenderDescriptor.Layer
    let texture: MTLTexture
    let masks: SceneImageLayerMasks
    let textureFrame: SceneTextureUVTransform
    let mvp: simd_float4x4
    let uniforms: SceneImageLayerUniformValues
    let offscreenTexturePool: SceneOffscreenTexturePool
    let resolvedMaterialFrameTargetPlan: SceneResolvedMaterialFrameTargetPlan?
    let effectSourceExtent: SceneLayerEffectSourceExtent?
    let requiresSourceCopy: Bool
    let finalCompositeAlpha: Float
    let dependencyEffects: [SceneDependencyEffectInput]
    let requiresDependencyEffect: Bool
    let dynamicValues: SceneDynamicSnapshot
    let audioSpectrum: SceneAudioSpectrumSnapshot
}
struct SceneCaptureGeometryResolver {
    struct Geometry {
        let sourceUV = SceneTextureUVTransform.identity
        let outputMVP = matrix_identity_float4x4
        let pixelSize = CGSize(width: 2, height: 2)
    }
    static func resolve(kind: SceneUtilityLayerRuntimePlan.Kind,
                        layerMVP: simd_float4x4, viewportSize: CGSize) -> Geometry? { Geometry() }
}
final class SceneMainPassEncoder {
    var captures = 0
    func withReadableTarget<T>(_ body: (MTLTexture, Int) -> T) -> T? {
        captures += 1
        return body(MTLTexture(identity: 1), 0)
    }
}
final class SceneImageLayerCompositor {
    var requests: [SceneImageLayerDrawRequest] = []
    func draw(_ request: SceneImageLayerDrawRequest, pipeline: SceneImageLayerPipeline,
              mainPass: SceneMainPassEncoder, executionTrace: SceneEffectExecutionFrameTrace?,
              executionOrigin: SceneEffectExecutionOrigin) -> Bool {
        requests.append(request)
        return true
    }
}
@main enum Harness {
    static func main() throws {
        var results: [[String: Any]] = []
        for isolated in [false, true] {
            for alpha: Float in [0, 0.25, 0.5, 1] {
                let compositor = SceneImageLayerCompositor()
                let pass = SceneMainPassEncoder()
                let drawn = SceneUtilityLayerRenderer.draw(
                    layer: .init(), plan: .init(shouldCapture: true, kind: .composition),
                    layerMVP: matrix_identity_float4x4, viewportSize: CGSize(width: 2, height: 2),
                    time: 0, finalCompositeAlpha: alpha, masks: .init(), cursorUV: .zero,
                    pointerIsInside: false, dynamicValues: .init(), audioSpectrum: .init(),
                    pipeline: .init(), compositor: compositor, offscreenTexturePool: .init(),
                    mainPass: pass, isolatedGroupSource: isolated
                        ? (MTLTexture(identity: 2), CGSize(width: 2, height: 2)) : nil)
                results.append(["isolated": isolated, "alpha": alpha, "drawn": drawn,
                                "captures": pass.captures,
                                "requests": compositor.requests.map {
                                    ["sourceAlpha": $0.uniforms.alpha,
                                     "finalAlpha": $0.finalCompositeAlpha,
                                     "sourceCopy": $0.requiresSourceCopy,
                                     "texture": $0.texture.identity] as [String: Any]
                                }])
            }
        }
        print(String(data: try JSONSerialization.data(withJSONObject: results), encoding: .utf8)!)
    }
}
'''


class SceneDynamicLayerValuesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-dynamic-layer-values-"
        )
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = directory / "scene-dynamic-layer-values"
        compilation = subprocess.run(
            [
                "swiftc",
                str(DYNAMIC_SOURCE),
                str(LAYER_VALUES_SOURCE),
                str(harness),
                "-o",
                str(binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_dynamic_scalar_wins_and_is_clamped(self) -> None:
        self.assertEqual(self.result["dynamic"], 0.25)
        self.assertEqual(self.result["dynamicClamp"], 1)
        self.assertAlmostEqual(self.result["wrongLayer"], 0.4)

    def test_invalid_dynamic_value_falls_back_to_authored_alpha(self) -> None:
        self.assertAlmostEqual(self.result["wrongType"], 0.3)

    def test_authored_alpha_is_finite_clamped_and_defaults_to_one(self) -> None:
        self.assertAlmostEqual(self.result["authored"], 0.4)
        self.assertEqual(self.result["authoredLow"], 0)
        self.assertEqual(self.result["authoredHigh"], 1)
        self.assertEqual(self.result["authoredNonFinite"], 1)
        self.assertEqual(self.result["default"], 1)

    def test_dynamic_color_wins_clamps_and_rejects_non_finite_values(self) -> None:
        self.assert_color("colorDynamicClamp", [0, 0.5, 1])
        self.assert_color("colorNonFiniteFallback", [0.2, 0.3, 0.4])
        self.assert_color("colorWrongLayer", [0.4, 0.5, 0.6])

    def test_invalid_dynamic_color_falls_back_to_authored_color(self) -> None:
        self.assert_color("colorWrongType", [0.3, 0.4, 0.5])

    def test_authored_color_is_clamped_and_invalid_values_default_to_white(self) -> None:
        self.assert_color("colorAuthoredClamp", [0, 0.25, 1])
        self.assert_color("colorAuthoredNonFinite", [1, 1, 1])
        self.assert_color("colorAuthoredPadded", [0.2, 0.3, 1])
        self.assert_color("colorDefault", [1, 1, 1])

    def assert_color(self, key: str, expected: list[float]) -> None:
        self.assertEqual(len(self.result[key]), len(expected))
        for actual, wanted in zip(self.result[key], expected):
            self.assertAlmostEqual(actual, wanted, places=6)

    def test_renderer_consumes_snapshot_for_non_particle_layer_alpha(self) -> None:
        renderer = read_source_family(RENDERER_SOURCE)
        utility_frame_renderer = UTILITY_FRAME_RENDERER_SOURCE.read_text(
            encoding="utf-8"
        )
        effect_execution = EFFECT_EXECUTION_SOURCE.read_text(encoding="utf-8")
        image_case = renderer.split('case "image", "solid", "text":', 1)[1].split(
            'case "composition", "project", "fullscreen":', 1
        )[0]
        _, particle_tail = renderer.split('case "composition":', 1)[1].split(
            'case "particle":', 1
        )
        utility_dispatch = effect_execution.split("func renderUtilityPlans(", 1)[1]
        particle_case = particle_tail.split("default:", 1)[0]
        self.assertIn("SceneDynamicLayerValues.alpha(", image_case)
        self.assertIn("SceneDynamicLayerValues.color(", image_case)
        self.assertIn("snapshot: frameContext.dynamicValues", image_case)
        self.assertIn("alpha: layerAlpha", image_case)
        self.assertIn("renderUtilityPlans(", renderer)
        self.assertIn("SceneUtilityPlanFrameRenderer.render(", utility_dispatch)
        self.assertIn("SceneDynamicLayerValues.alpha(", utility_frame_renderer)
        self.assertIn(
            "finalCompositeAlpha: SceneDynamicLayerValues.alpha(",
            utility_frame_renderer,
        )
        self.assertIn(
            "snapshot: frameContext.dynamicValues",
            utility_frame_renderer,
        )
        self.assertNotIn("SceneDynamicLayerValues.alpha(", particle_case)
        self.assertNotIn("Float(layer.alpha ?? 1)", renderer)
        self.assertNotIn("Float(layer.alpha ?? 1)", utility_frame_renderer)

        compositor_uniforms = COMPOSITOR_UNIFORMS_SOURCE.read_text(encoding="utf-8")
        self.assertRegex(
            compositor_uniforms,
            r'usesAuthoredColor[\s\S]{0,80}layer\.contentKind == "image"'
            r'[\s\S]{0,100}layer\.contentKind == "solid"'
            r"[\s\S]{0,100}tint\s*=\s*usesAuthoredColor"
            r"\s*\?\s*values\.tint"
            r"\s*:\s*SIMD3<Float>\(repeating:\s*1\)",
        )

    def test_utility_capture_keeps_source_neutral_and_applies_alpha_once(self) -> None:
        # Execute the real utility owner through both exclusive routes. Doubles
        # observe its compositor handoff; this is not GPU pixel/blend evidence.
        original = UTILITY_SOURCE.read_text(encoding="utf-8")
        variants = {
            "production": original,
            "source-alpha-reapplied": original.replace("alpha: 1,", "alpha: finalCompositeAlpha,"),
            "terminal-alpha-squared": original.replace(
                "finalCompositeAlpha: finalCompositeAlpha,",
                "finalCompositeAlpha: finalCompositeAlpha * finalCompositeAlpha,"),
        }
        def assert_handoff(rows: list[dict]) -> None:
            self.assertEqual(len(rows), 8)
            for row in rows:
                self.assertTrue(row["drawn"])
                self.assertEqual(row["captures"], 0 if row["isolated"] else 1)
                self.assertEqual(len(row["requests"]), 1)
                request = row["requests"][0]
                self.assertEqual(request["sourceAlpha"], 1)
                self.assertEqual(request["finalAlpha"], row["alpha"])
                self.assertEqual(request["sourceCopy"], not row["isolated"])
                self.assertEqual(request["texture"], 2 if row["isolated"] else 1)

        with tempfile.TemporaryDirectory(prefix="mwx-utility-alpha-") as temporary:
            directory = Path(temporary)
            harness = directory / "Harness.swift"
            harness.write_text(UTILITY_ALPHA_HARNESS, encoding="utf-8")
            for name, source in variants.items():
                with self.subTest(owner=name):
                    owner = directory / "SceneUtilityLayerRenderer.swift"
                    owner.write_text(source, encoding="utf-8")
                    binary = directory / name
                    compiled = subprocess.run(
                        ["swiftc", str(owner), str(harness), "-o", str(binary)],
                        capture_output=True, text=True,
                    )
                    self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
                    result = subprocess.run([str(binary)], check=True, capture_output=True, text=True)
                    rows = json.loads(result.stdout)
                    if name == "production":
                        assert_handoff(rows)
                    else:
                        with self.assertRaises(AssertionError):
                            assert_handoff(rows)


if __name__ == "__main__":
    unittest.main()
