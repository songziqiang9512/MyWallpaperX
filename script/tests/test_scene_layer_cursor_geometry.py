#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering"
SWIFT_SOURCES = [
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+ParticlePointer.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/SceneMatrix.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/SceneLayerCursorGeometry.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticlePointerProjection.swift",
]

def instrument_inverse_count(source: str) -> str:
    """Count the real inverse leaf in a temporary test copy, never product code."""
    start = source.index("static func preciseInverseModelViewProjection(")
    body = source.index("{", start) + 1
    return (
        "nonisolated enum SceneCursorInverseProbe { "
        "nonisolated(unsafe) static var count = 0 }\n"
        + source[:body]
        + "\n        SceneCursorInverseProbe.count += 1"
        + source[body:]
    )


HARNESS_SOURCE = r'''
import Foundation
import simd


// Minimal host shell; pointer selection and inverse projection are product code.
struct SceneFrameContext {
    struct Pointer { let current: SIMD2<Float>; let isInside: Bool }
    let pointer: Pointer
    let screenSize = SIMD2<Float>(1280, 720)
    let cameraParallaxPosition = SIMD2<Float>.zero
    let dynamicValues = 0
}
struct SceneParticleCameraFrame { let orthographicViewProjection: simd_float4x4 }
struct SceneMetalRendererFrameWorldProjection {
    struct Layer { let id: Int; let contentKind: String }
    let layersByID: [Int: Layer]
    let worldFrames: [Int: simd_float4x4]
}
struct SceneMetalRenderer {
    func parallaxConfiguration(cameraFrame: SceneParticleCameraFrame,
        viewportSize: SIMD2<Float>, dynamicValues: Int) -> Int { 0 }
    func particleModelMatrix(for layer: SceneMetalRendererFrameWorldProjection.Layer,
        worldFramesByLayerID: [Int: simd_float4x4],
        parallaxMouseNormalized: SIMD2<Float>, configuration: Int) -> simd_float4x4 {
        worldFramesByLayerID[layer.id] ?? matrix_identity_float4x4
    }
}

@main
enum Harness {
    // Test-only reference sequence: an independent inverse for each former
    // effect request. No obsolete matrix-taking effect API remains in product.
    static func independentEffectProjection(
        _ matrix: simd_float4x4, required: Bool
    ) -> simd_float4x4? {
        guard required else { return matrix_identity_float4x4 }
        return SceneLayerCursorGeometry.effectTextureProjectionInverse(
            inverseModelViewProjection: SceneLayerCursorGeometry.preciseInverseModelViewProjection(matrix),
            required: true
        )
    }

    static func pair(_ value: SIMD2<Float>?) -> [Float] {
        guard let value else { return [] }
        return [value.x, value.y]
    }

    static func triple(_ value: SIMD3<Double>?) -> [Double] {
        guard let value else { return [] }
        return [value.x, value.y, value.z]
    }

    static func floatTriple(_ value: SIMD3<Float>) -> [Float] {
        [value.x, value.y, value.z]
    }

    static func main() throws {
        let local = SIMD4<Float>(0.1, -0.2, 0, 1)
        let transformedMVP = SceneMatrix.translation(SIMD3(0.2, -0.1, 0))
            * SceneMatrix.rotationZ(.pi / 3)
            * SceneMatrix.rotationX(.pi / 7)
            * SceneMatrix.scale(SIMD3(0.7, 1.3, 1))
        let projected = transformedMVP * local
        let normalized = SIMD2(projected.x, projected.y) / projected.w
        let effectCardMVP = SceneMatrix.translation(SIMD3(0.2, -0.1, 0))
            * SceneMatrix.rotationZ(.pi / 3)
            * SceneMatrix.scale(SIMD3(0.7, 1.3, 1))
        let effectCardProjected = effectCardMVP * local
        let effectCardNormalized = SIMD2(
            effectCardProjected.x,
            effectCardProjected.y
        ) / effectCardProjected.w
        let singular = SceneMatrix.scale(SIMD3(0, 1, 1))
        var nonfinite = matrix_identity_float4x4
        nonfinite.columns.3.x = .infinity
        let inverseOverflow = SceneMatrix.scale(SIMD3<Float>(1e-39, 1, 1))
        let effectOverflow = SceneMatrix.scale(SIMD3<Float>(5e-39, 1, 1))
        let largeDepthProjection = SceneMatrix.ortho(
            left: -128, right: 128,
            bottom: 128, top: -128,
            near: 0.1, far: 10_000
        ) * SceneMatrix.lookAt(
            eye: SIMD3(0, 0, 1),
            center: .zero,
            up: SIMD3(0, 1, 0)
        )
        let singularUnusedProjection = independentEffectProjection(singular, required: false)
        let inverseRestoresKnownPoint: Bool = {
            guard let inverse = SceneLayerCursorGeometry.inverseModelViewProjection(
                transformedMVP
            ) else { return false }
            let restored = inverse * projected
            return abs(restored.x / restored.w - local.x) < 0.00001
                && abs(restored.y / restored.w - local.y) < 0.00001
        }()
        let effectTextureProjection: [Float] = {
            guard let inverse = independentEffectProjection(
                    effectCardMVP,
                    required: true
                ) else { return [] }
            let shaderClip = SIMD4<Float>(
                effectCardNormalized.x,
                effectCardNormalized.y,
                0,
                1
            )
            let projectedTexture = inverse * shaderClip
            guard projectedTexture.w.isFinite,
                  abs(projectedTexture.w) > 0.00000001 else { return [] }
            return [
                projectedTexture.x / projectedTexture.w * 0.5,
                projectedTexture.y / projectedTexture.w * 0.5,
            ]
        }()
        let rippleTextureUV: [Float] = {
            guard effectTextureProjection.count == 2 else { return [] }
            return [
                effectTextureProjection[0] + 0.5,
                1 - (effectTextureProjection[1] + 0.5),
            ]
        }()
        let objectSize = SIMD2<Float>(320, 180)
        let transformedPixelPoints: [[Double]] = [
            transformedMVP,
            SceneMatrix.translation(SIMD3(0.3, 0.1, 0))
                * SceneMatrix.rotationZ(-0.4)
                * SceneMatrix.scale(SIMD3(-0.6, 1.2, 1))
                * transformedMVP
                * SceneMatrix.translation(SIMD3(0.5, -0.5, 0)),
        ].map { mvp in
            let clip = mvp * local
            guard let point = SceneLayerCursorGeometry.layerPoint(
                mouseNormalized: SIMD2(clip.x, clip.y) / clip.w,
                modelViewProjection: mvp
            ) else { return [] }
            return triple(SceneLayerCursorGeometry.authoredLocalPosition(point, size: objectSize))
        }
        let boneModel = SceneMatrix.translation(SIMD3(130, 200, 7))
            * SceneMatrix.rotationZ(0.4) * SceneMatrix.scale(SIMD3(2, -3, 1))
        let bonePoint = SIMD4<Float>(12, 15, 2, 1)
        let internalPoint = boneModel * bonePoint
        let authorModel = SceneLayerCursorGeometry.authoredWorldTransform(
            boneModel, sceneOrthoHeight: 1080)
        let authorPoint = authorModel * bonePoint
        let cursorPoint = SceneLayerCursorGeometry.authoredWorldPosition(
            SIMD3(internalPoint.x, internalPoint.y, internalPoint.z), sceneOrthoHeight: 1080)
        let restoredBone = simd_inverse(authorModel) * authorPoint
        let upInAuthor = simd_inverse(authorModel) * (authorPoint + SIMD4(0, 20, 0, 0))
        let movedInternal = boneModel * upInAuthor
        let boneCoordinateErrors = [
            simd_length(SIMD3(authorPoint.x, authorPoint.y, authorPoint.z) - cursorPoint),
            simd_length(restoredBone - bonePoint),
            abs(movedInternal.y - internalPoint.y + 20),
        ]
        let perspectiveBoneUnchanged = SceneLayerCursorGeometry.authoredWorldTransform(
            boneModel, sceneOrthoHeight: nil) == boneModel

        let host = SceneMetalRenderer()
        let camera = SceneParticleCameraFrame(orthographicViewProjection: matrix_identity_float4x4)
        let pointerLayer = SceneMetalRendererFrameWorldProjection.Layer(id: 7, contentKind: "particle")
        func hostPositions(_ model: simd_float4x4, demand: Set<Int> = [7],
                           inside: Bool = true) -> [Int: SIMD3<Double>] {
            host.particlePointerLocalPositions(
                frameContext: .init(pointer: .init(current: normalized, isInside: inside)),
                cameraFrame: camera,
                frameProjection: .init(layersByID: [7: pointerLayer,
                    8: .init(id: 8, contentKind: "image")], worldFrames: [7: model]),
                demandedLayerIDs: demand)
        }
        let hostFirst = hostPositions(transformedMVP)
        let movedFrame = SceneMatrix.translation(SIMD3(0.15, -0.12, 0)) * transformedMVP
        let hostNext = hostPositions(movedFrame)
        func screenError(_ position: SIMD3<Double>?, model: simd_float4x4) -> Float {
            guard let p = position else { return 1000 }
            let clip = model * SIMD4<Float>(Float(p.x), Float(p.y), Float(p.z), 1)
            return simd_length(SIMD2(clip.x, clip.y) / clip.w - normalized)
        }

        var nearWZero = matrix_identity_float4x4
        nearWZero.columns.2 = SIMD4(0, 0, 0, 1)
        nearWZero.columns.3 = SIMD4(0, 0, 1, 0)
        var farWZero = matrix_identity_float4x4
        farWZero.columns.2.w = 1
        var parallelRay = matrix_identity_float4x4
        parallelRay.columns.0 = SIMD4(0, 0, 1, 0)
        parallelRay.columns.2 = SIMD4(1, 0, 0, 0)
        var pointDependentW = matrix_identity_float4x4
        pointDependentW.columns.0.w = -1
        let queryCases: [(String, simd_float4x4, SIMD2<Float>, SIMD2<Float>)] = [
            ("identity-outside", matrix_identity_float4x4, .zero, SIMD2(1.5, -1.5)),
            ("rotated-scaled", transformedMVP, normalized, .zero),
            ("new-frame", movedFrame, normalized, .zero),
            ("large-depth", largeDepthProjection, .zero, SIMD2(0.1, -0.2)),
            ("current-nan", transformedMVP, SIMD2(.nan, 0), normalized),
            ("previous-infinity", transformedMVP, normalized, SIMD2(.infinity, 0)),
            ("current-invalid-w", pointDependentW, SIMD2(-1, 0), .zero),
            ("previous-invalid-w", pointDependentW, .zero, SIMD2(-1, 0)),
            ("near-zero-w", nearWZero, .zero, SIMD2(0.1, -0.2)),
            ("far-zero-w", farWZero, .zero, SIMD2(0.1, -0.2)),
            ("parallel-ray", parallelRay, .zero, SIMD2(0.1, -0.2)),
            ("singular", singular, .zero, .zero),
            ("nonfinite-matrix", nonfinite, .zero, .zero),
            ("inverse-float-overflow", inverseOverflow, .zero, .zero),
            ("effect-float-overflow", effectOverflow, .zero, .zero),
        ]
        typealias Projection = (
            effect: simd_float4x4?, current: SIMD2<Float>?, previous: SIMD2<Float>?
        )
        func projection(_ matrix: simd_float4x4, current: SIMD2<Float>,
                        previous: SIMD2<Float>, required: Bool, shared: Bool) -> Projection {
            if shared {
                let inverse = SceneLayerCursorGeometry.preciseInverseModelViewProjection(matrix)
                guard let effect = SceneLayerCursorGeometry.effectTextureProjectionInverse(
                    inverseModelViewProjection: inverse, required: required
                ) else { return (nil, nil, nil) }
                return (effect, SceneLayerCursorGeometry.layerUV(
                    mouseNormalized: current, inverseModelViewProjection: inverse),
                    SceneLayerCursorGeometry.layerUV(
                        mouseNormalized: previous, inverseModelViewProjection: inverse))
            }
            guard let effect = independentEffectProjection(
                matrix, required: required
            ) else { return (nil, nil, nil) }
            return (effect, SceneLayerCursorGeometry.layerUV(
                mouseNormalized: current, modelViewProjection: matrix),
                SceneLayerCursorGeometry.layerUV(
                    mouseNormalized: previous, modelViewProjection: matrix))
        }
        func same(_ lhs: Projection, _ rhs: Projection) -> Bool {
            lhs.effect == rhs.effect && lhs.current == rhs.current && lhs.previous == rhs.previous
        }
        let sharedInverseQueries: [[String: Any]] = queryCases.map { name, matrix, current, previous in
            SceneCursorInverseProbe.count = 0
            let inverse = SceneLayerCursorGeometry.preciseInverseModelViewProjection(matrix)
            let currentUV = SceneLayerCursorGeometry.layerUV(
                mouseNormalized: current, inverseModelViewProjection: inverse)
            let previousUV = SceneLayerCursorGeometry.layerUV(
                mouseNormalized: previous, inverseModelViewProjection: inverse)
            let pairCount = SceneCursorInverseProbe.count
            SceneCursorInverseProbe.count = 0
            let originalCurrent = SceneLayerCursorGeometry.layerUV(
                mouseNormalized: current, modelViewProjection: matrix)
            let originalPrevious = SceneLayerCursorGeometry.layerUV(
                mouseNormalized: previous, modelViewProjection: matrix)
            let singleCount = SceneCursorInverseProbe.count
            SceneCursorInverseProbe.count = 0
            let required = projection(matrix, current: current, previous: previous,
                required: true, shared: true)
            let requiredCount = SceneCursorInverseProbe.count
            SceneCursorInverseProbe.count = 0
            let originalRequired = projection(matrix, current: current, previous: previous,
                required: true, shared: false)
            let originalRequiredCount = SceneCursorInverseProbe.count
            SceneCursorInverseProbe.count = 0
            let unused = projection(matrix, current: current, previous: previous,
                required: false, shared: true)
            let unusedCount = SceneCursorInverseProbe.count
            SceneCursorInverseProbe.count = 0
            let originalUnused = projection(matrix, current: current, previous: previous,
                required: false, shared: false)
            let originalUnusedCount = SceneCursorInverseProbe.count
            return [
                "name": name,
                "pairMatchesSingles": currentUV == originalCurrent && previousUV == originalPrevious,
                "currentAvailable": currentUV != nil, "previousAvailable": previousUV != nil,
                "pairInverseCount": pairCount, "singleInverseCount": singleCount,
                "requiredMatchesOriginal": same(required, originalRequired),
                "requiredAvailable": required.effect != nil,
                "requiredInverseCount": requiredCount, "originalRequiredInverseCount": originalRequiredCount,
                "unusedMatchesOriginal": same(unused, originalUnused),
                "unusedUsesIdentity": unused.effect == matrix_identity_float4x4,
                "unusedInverseCount": unusedCount, "originalUnusedInverseCount": originalUnusedCount,
            ]
        }

        let result: [String: Any] = [
            "sharedInverseQueries": sharedInverseQueries,
            "hostFirst": triple(hostFirst[7]),
            "hostNextError": screenError(hostNext[7], model: movedFrame),
            "staleFrameError": screenError(hostFirst[7], model: movedFrame),
            "hostRecovery": hostPositions(transformedMVP) == hostFirst,
            "hostOutside": hostPositions(transformedMVP, inside: false).isEmpty,
            "hostNoDemand": hostPositions(transformedMVP, demand: []).isEmpty,
            "hostInvalidDemand": hostPositions(transformedMVP, demand: [8, 99]).isEmpty,
            "hostSingular": hostPositions(singular).isEmpty,
            "boneCoordinateErrors": boneCoordinateErrors,
            "perspectiveBoneUnchanged": perspectiveBoneUnchanged,
            "localPixelCenter": triple(SceneLayerCursorGeometry.authoredLocalPosition(
                .zero, size: objectSize
            )),
            "localPixelCorners": [SIMD3<Float>(-0.5,-0.5,0), SIMD3<Float>(0.5,0.5,0)].map {
                triple(SceneLayerCursorGeometry.authoredLocalPosition($0, size: objectSize))
            },
            "localPixelOutside": triple(SceneLayerCursorGeometry.authoredLocalPosition(
                SIMD3(1.5,-1.5,0), size: objectSize
            )),
            "transformedPixelPoints": transformedPixelPoints,
            "invalidLocalPixelInputs": [
                SceneLayerCursorGeometry.authoredLocalPosition(.zero, size: .zero),
                SceneLayerCursorGeometry.authoredLocalPosition(.zero, size: SIMD2(-1,20)),
                SceneLayerCursorGeometry.authoredLocalPosition(.zero, size: SIMD2(.infinity,20)),
                SceneLayerCursorGeometry.authoredLocalPosition(SIMD3(.nan,0,0), size: objectSize),
            ].allSatisfy { $0 == nil },
            "identityCenter": pair(SceneLayerCursorGeometry.layerUV(
                mouseNormalized: .zero,
                modelViewProjection: SceneMatrix.identity()
            )),
            "authoredOrthographicWorld": floatTriple(
                SceneLayerCursorGeometry.authoredWorldPosition(
                    SIMD3(4, 200, 7), sceneOrthoHeight: 1080
                )
            ),
            "authoredPerspectiveWorld": floatTriple(
                SceneLayerCursorGeometry.authoredWorldPosition(
                    SIMD3(4, 200, 7), sceneOrthoHeight: nil
                )
            ),
            "transformedKnownPoint": pair(SceneLayerCursorGeometry.layerUV(
                mouseNormalized: normalized,
                modelViewProjection: transformedMVP
            )),
            "outsideFinite": pair(SceneLayerCursorGeometry.layerUV(
                mouseNormalized: SIMD2(1.5, -1.5),
                modelViewProjection: SceneMatrix.identity()
            )),
            "singularRejected": SceneLayerCursorGeometry.layerUV(
                mouseNormalized: .zero,
                modelViewProjection: singular
            ) == nil,
            "inverseRestoresKnownPoint": inverseRestoresKnownPoint,
            "effectTextureProjection": effectTextureProjection,
            "rippleTextureUV": rippleTextureUV,
            "singularInverseRejected":
                SceneLayerCursorGeometry.inverseModelViewProjection(singular) == nil,
            "nonfiniteInverseRejected": SceneLayerCursorGeometry.inverseModelViewProjection(nonfinite) == nil,
            "nonfiniteHitRejected": SceneLayerCursorGeometry.layerPoint(
                mouseNormalized: .zero, modelViewProjection: nonfinite) == nil,
            "inverseFloatOverflowRejected": SceneLayerCursorGeometry.inverseModelViewProjection(inverseOverflow) == nil,
            "effectFloatOverflowRejected": SceneLayerCursorGeometry.inverseModelViewProjection(effectOverflow) != nil
                && independentEffectProjection(effectOverflow, required: true) == nil,
            "singularUnusedProjectionUsesIdentity":
                singularUnusedProjection == matrix_identity_float4x4,
            "singularRequiredProjectionRejected": independentEffectProjection(
                    singular,
                    required: true
                ) == nil,
            "largeDepthOrthographicProjectionAccepted":
                SceneLayerCursorGeometry.layerPoint(
                    mouseNormalized: .zero,
                    modelViewProjection: largeDepthProjection
                ) != nil,
            "invertibleRequiredProjectionIsAvailable":
                independentEffectProjection(
                    transformedMVP,
                    required: true
                ) != nil,
            "particleLocalPosition": triple(SceneParticlePointerProjection.localPosition(
                mouseNormalized: normalized,
                isInside: true,
                modelViewProjection: transformedMVP
            )),
            "particleOutsideRejected": SceneParticlePointerProjection.localPosition(
                mouseNormalized: normalized,
                isInside: false,
                modelViewProjection: transformedMVP
            ) == nil,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneLayerCursorGeometryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-cursor-geometry-")
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        geometry = next(path for path in SWIFT_SOURCES if path.name == "SceneLayerCursorGeometry.swift")
        instrumented = root / geometry.name
        instrumented.write_text(instrument_inverse_count(geometry.read_text()), encoding="utf-8")
        cls.binary = root / "cursor-geometry"
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                *(str(instrumented if path == geometry else path) for path in SWIFT_SOURCES),
                str(harness),
                "-o",
                str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(cls.binary)],
            check=True,
            capture_output=True,
            text=True,
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def assert_pair_almost_equal(
        self,
        actual: list[float],
        expected: list[float],
    ) -> None:
        self.assertEqual(len(actual), len(expected))
        for actual_component, expected_component in zip(actual, expected):
            self.assertAlmostEqual(actual_component, expected_component, places=5)

    def test_particle_host_uses_current_draw_frame_and_recovers_after_change(self) -> None:
        self.assert_pair_almost_equal(self.result["hostFirst"], [0.1, -0.2, 0])
        self.assertLess(self.result["hostNextError"], 0.00001)
        self.assertGreater(self.result["staleFrameError"], 0.1)
        self.assertTrue(self.result["hostRecovery"])

    def test_particle_host_rejects_outside_missing_demand_and_singular_frames(self) -> None:
        for key in ["hostOutside", "hostNoDemand", "hostInvalidDemand", "hostSingular"]:
            self.assertTrue(self.result[key], key)

    def test_cursor_local_pixels_use_unscaled_object_size(self) -> None:
        self.assertEqual(self.result["localPixelCenter"], [160, 90, 0])
        self.assertEqual(self.result["localPixelCorners"], [[0, 0, 0], [320, 180, 0]])
        for point in self.result["transformedPixelPoints"]:
            self.assertEqual(len(point), 3)
            for actual, expected in zip(point, [192, 54, 0]):
                self.assertAlmostEqual(actual, expected, places=3)

    def test_cursor_local_pixels_keep_outside_drag_and_reject_invalid_size(self) -> None:
        self.assertEqual(self.result["localPixelOutside"], [640, -180, 0])
        self.assertTrue(self.result["invalidLocalPixelInputs"])

    def test_bone_world_and_cursor_world_agree_and_inverse_writes_keep_direction(self) -> None:
        for error in self.result["boneCoordinateErrors"]:
            self.assertLess(error, 0.0001)
        self.assertTrue(self.result["perspectiveBoneUnchanged"])

    def test_identity_maps_surface_center_to_layer_center(self) -> None:
        self.assert_pair_almost_equal(self.result["identityCenter"], [0.5, 0.5])

    def test_orthographic_cursor_world_is_converted_to_author_space(self) -> None:
        self.assertEqual(
            self.result["authoredOrthographicWorld"], [4.0, 880.0, 7.0]
        )

    def test_native_perspective_cursor_world_keeps_its_author_space(self) -> None:
        self.assertEqual(
            self.result["authoredPerspectiveWorld"], [4.0, 200.0, 7.0]
        )

    def test_particle_pointer_uses_layer_local_plane_and_rejects_outside(self) -> None:
        self.assertEqual(len(self.result["particleLocalPosition"]), 3)
        for actual, expected in zip(
            self.result["particleLocalPosition"], [0.1, -0.2, 0]
        ):
            self.assertAlmostEqual(actual, expected, places=5)
        self.assertTrue(self.result["particleOutsideRejected"])

    def test_rotated_scaled_layer_uses_inverse_projected_hit(self) -> None:
        self.assert_pair_almost_equal(
            self.result["transformedKnownPoint"],
            [0.6, 0.7],
        )

    def test_effect_texture_projection_maps_clip_to_centered_local(self) -> None:
        self.assert_pair_almost_equal(
            self.result["effectTextureProjection"], [0.1, -0.2]
        )
        self.assert_pair_almost_equal(
            self.result["rippleTextureUV"], [0.6, 0.7]
        )

    def test_finite_points_outside_layer_remain_available_for_halo_clipping(self) -> None:
        self.assert_pair_almost_equal(self.result["outsideFinite"], [2.0, 2.0])

    def test_singular_transform_is_rejected(self) -> None:
        self.assertTrue(self.result["singularRejected"])
        self.assertTrue(self.result["singularInverseRejected"])

    def test_nonfinite_and_float_abi_overflow_are_rejected(self) -> None:
        for key in ("nonfiniteInverseRejected", "nonfiniteHitRejected",
                    "inverseFloatOverflowRejected", "effectFloatOverflowRejected"):
            self.assertTrue(self.result[key], key)

    def test_public_inverse_matches_layer_local_projection(self) -> None:
        self.assertTrue(self.result["inverseRestoresKnownPoint"])

    def test_large_depth_orthographic_projection_is_not_rejected_by_scale(self) -> None:
        self.assertTrue(self.result["largeDepthOrthographicProjectionAccepted"])

    def test_effect_projection_placeholder_requires_an_unobserved_matrix(self) -> None:
        self.assertTrue(self.result["singularUnusedProjectionUsesIdentity"])
        self.assertTrue(self.result["singularRequiredProjectionRejected"])
        self.assertTrue(
            self.result["invertibleRequiredProjectionIsAvailable"]
        )


    def test_current_and_previous_queries_share_one_inverse_and_match_single_point_results(self) -> None:
        for case in self.result["sharedInverseQueries"]:
            with self.subTest(case=case["name"]):
                self.assertTrue(case["pairMatchesSingles"], case)
                self.assertEqual(case["pairInverseCount"], 1, case)
                self.assertEqual(case["singleInverseCount"], 2, case)

    def test_shared_projection_keeps_independent_point_failures_and_numeric_boundaries(self) -> None:
        cases = {case["name"]: case for case in self.result["sharedInverseQueries"]}
        for name in ("current-nan", "current-invalid-w"):
            self.assertFalse(cases[name]["currentAvailable"], cases[name])
            self.assertTrue(cases[name]["previousAvailable"], cases[name])
        for name in ("previous-infinity", "previous-invalid-w"):
            self.assertTrue(cases[name]["currentAvailable"], cases[name])
            self.assertFalse(cases[name]["previousAvailable"], cases[name])
        for name in ("near-zero-w", "far-zero-w", "parallel-ray", "singular", "nonfinite-matrix"):
            self.assertFalse(cases[name]["currentAvailable"], cases[name])
            self.assertFalse(cases[name]["previousAvailable"], cases[name])
        for name in ("inverse-float-overflow", "effect-float-overflow"):
            self.assertTrue(cases[name]["currentAvailable"], cases[name])
            self.assertTrue(cases[name]["previousAvailable"], cases[name])
            self.assertFalse(cases[name]["requiredAvailable"], cases[name])

    def test_preflight_effect_projection_and_both_points_share_one_inverse(self) -> None:
        for case in self.result["sharedInverseQueries"]:
            with self.subTest(case=case["name"]):
                self.assertTrue(case["requiredMatchesOriginal"], case)
                self.assertTrue(case["unusedMatchesOriginal"], case)
                self.assertTrue(case["unusedUsesIdentity"], case)
                self.assertEqual(case["requiredInverseCount"], 1, case)
                self.assertEqual(case["unusedInverseCount"], 1, case)
                self.assertEqual(case["originalRequiredInverseCount"], 3 if case["requiredAvailable"] else 1, case)
                self.assertEqual(case["originalUnusedInverseCount"], 2, case)


if __name__ == "__main__":
    unittest.main()
