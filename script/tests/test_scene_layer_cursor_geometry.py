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
    SOURCE_ROOT / "SceneMatrix.swift",
    SOURCE_ROOT / "SceneLayerCursorGeometry.swift",
    SOURCE_ROOT / "SceneParticlePointerProjection.swift",
]

HARNESS_SOURCE = r'''
import Foundation
import simd

@main
enum Harness {
    static func pair(_ value: SIMD2<Float>?) -> [Float] {
        guard let value else { return [] }
        return [value.x, value.y]
    }

    static func triple(_ value: SIMD3<Double>?) -> [Double] {
        guard let value else { return [] }
        return [value.x, value.y, value.z]
    }

    static func main() throws {
        let local = SIMD4<Float>(0.1, -0.2, 0, 1)
        let transformedMVP = SceneMatrix.translation(SIMD3(0.2, -0.1, 0))
            * SceneMatrix.rotationZ(.pi / 3)
            * SceneMatrix.rotationX(.pi / 7)
            * SceneMatrix.scale(SIMD3(0.7, 1.3, 1))
        let projected = transformedMVP * local
        let normalized = SIMD2(projected.x, projected.y) / projected.w
        let singular = SceneMatrix.scale(SIMD3(0, 1, 1))
        let singularUnusedProjection = SceneLayerCursorGeometry
            .effectProjectionInverse(singular, required: false)
        let inverseRestoresKnownPoint: Bool = {
            guard let inverse = SceneLayerCursorGeometry.inverseModelViewProjection(
                transformedMVP
            ) else { return false }
            let restored = inverse * projected
            return abs(restored.x / restored.w - local.x) < 0.00001
                && abs(restored.y / restored.w - local.y) < 0.00001
        }()
        let result: [String: Any] = [
            "identityCenter": pair(SceneLayerCursorGeometry.layerUV(
                mouseNormalized: .zero,
                modelViewProjection: SceneMatrix.identity()
            )),
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
            "singularInverseRejected":
                SceneLayerCursorGeometry.inverseModelViewProjection(singular) == nil,
            "singularUnusedProjectionUsesIdentity":
                singularUnusedProjection == matrix_identity_float4x4,
            "singularRequiredProjectionRejected": SceneLayerCursorGeometry
                .effectProjectionInverse(singular, required: true) == nil,
            "invertibleRequiredProjectionMatchesStrictInverse":
                SceneLayerCursorGeometry.effectProjectionInverse(
                    transformedMVP,
                    required: true
                ) == SceneLayerCursorGeometry.inverseModelViewProjection(
                    transformedMVP
                ),
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
        cls.binary = root / "cursor-geometry"
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
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

    def test_identity_maps_surface_center_to_layer_center(self) -> None:
        self.assert_pair_almost_equal(self.result["identityCenter"], [0.5, 0.5])

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

    def test_finite_points_outside_layer_remain_available_for_halo_clipping(self) -> None:
        self.assert_pair_almost_equal(self.result["outsideFinite"], [2.0, 2.0])

    def test_singular_transform_is_rejected(self) -> None:
        self.assertTrue(self.result["singularRejected"])
        self.assertTrue(self.result["singularInverseRejected"])

    def test_public_inverse_matches_layer_local_projection(self) -> None:
        self.assertTrue(self.result["inverseRestoresKnownPoint"])

    def test_effect_projection_placeholder_requires_an_unobserved_matrix(self) -> None:
        self.assertTrue(self.result["singularUnusedProjectionUsesIdentity"])
        self.assertTrue(self.result["singularRequiredProjectionRejected"])
        self.assertTrue(
            self.result["invertibleRequiredProjectionMatchesStrictInverse"]
        )


if __name__ == "__main__":
    unittest.main()
