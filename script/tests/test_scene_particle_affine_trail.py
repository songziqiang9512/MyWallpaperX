#!/usr/bin/env python3
"""GPU coverage of self-authored SpriteTrail affine cards and nearby controls.

The positive local 2D trail geometry is bounded by the fixed official black-box
scale experiment of 2026-10-04: size 128 publishes width 64, fixed stretch 4
publishes length 256; scale (.5, .125) yields X length/width 128/8 and Y 32/32.
Negative/zero scales are project safety controls, not official parity claims.
Pixels are read from the production Metal pipeline using a self-authored white
texture; no private stock, shader, script, or corpus resource is read.
"""

from __future__ import annotations

import hashlib
import json
import math
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

if __package__:
    from .test_scene_particle_rendering import SWIFT_SOURCES
else:
    from test_scene_particle_rendering import SWIFT_SOURCES


FIXTURE = Path(__file__).with_name("fixtures") / "SceneParticleAffineTrailHarness.swift"


def case(name, scale=(1, 1, 1), velocity=(0.0001, 0, 0), angle=0, kind="trail", **options):
    return {
        "name": name, "kind": kind, "scale": list(scale),
        "velocity": list(velocity), "angle": angle, "size": 128, "stretch": 4,
        **options,
    }


NONUNIFORM = (.5, .125, .25)
DIAGONAL = (.0001, .0001, 0)
CASES = [
    case("unit-x"),
    case("unit-y", velocity=(0, .0001, 0)),
    case("nonuniform-x", NONUNIFORM),
    case("nonuniform-y", NONUNIFORM, velocity=(0, .0001, 0)),
    case("nonuniform-diagonal", NONUNIFORM, DIAGONAL),
    case("nonuniform-diagonal-rotated", NONUNIFORM, DIAGONAL, -.7),
    case("uniform-diagonal", (.5, .5, .5), DIAGONAL),
    case("nonuniform-x-rotated", NONUNIFORM, angle=-.7),
    case("project-mirror-x", (-.5, .125, .25), DIAGONAL),
    case("project-mirror-y-rotated", (.5, -.125, .25), DIAGONAL, -.7),
    case("project-zero-x", (0, .125, .25), DIAGONAL),
    case("project-zero-y", (.5, 0, .25)),
    case("project-zero-all", (0, 0, 0), DIAGONAL),
    case("sprite-nonuniform", NONUNIFORM, kind="sprite"),
    case("sprite-nonuniform-rotated", NONUNIFORM, angle=-.7, kind="sprite"),
    case("rope-nonuniform-x", NONUNIFORM, kind="rope"),
    case("rope-nonuniform-diagonal-rotated", NONUNIFORM, DIAGONAL, -.7, "rope"),
    case("project-zero-depth-tilt-x", (.5, .125, 0), angle=-.7, tiltX=.3),
    case("project-zero-depth-tilt-y", (.5, .125, 0), (0, .0001, 0), -.7, tiltX=.3),
    case("project-zero-depth-tilt-diagonal", (.5, .125, 0), DIAGONAL, -.7, tiltX=.3),
    case("project-tiny-uniform-x", (1e-12, 1e-12, 1e-12), angle=-.7,
         vertexOnly=True),
    case("project-tiny-uniform-diagonal", (1e-12, 1e-12, 1e-12), DIAGONAL, -.7,
         vertexOnly=True),
    case("trail-world-size-nonuniform-x", NONUNIFORM, angle=-.7, worldSize=True),
    case("trail-world-size-nonuniform-diagonal", NONUNIFORM, DIAGONAL, -.7, worldSize=True),
    case("project-fixed-xz-tilted", NONUNIFORM, angle=-.7, tiltX=.3,
         orientation="fixed", orientationAxis=[0, 1, 0]),
    case("project-fixed-xz-unused-y-zero", (.5, 0, .25), angle=-.7, tiltX=.3,
         orientation="fixed", orientationAxis=[0, 1, 0]),
]

HARNESS_SOURCE = r'''
import Foundation
import Metal
import simd

enum SceneTextureLoadPurpose: Hashable {
    case premultipliedColor, straightAlbedo, preservedChannels, mask, noise
    case flow, phase, normal, depth, lookupTable
    var requiresVolumeTexture: Bool { self == .lookupTable }
}

struct SceneRenderDescriptor {
    struct Layer {
        let utilityLayer: Bool?
        let usesPerspective: Bool?
    }
    struct CameraDescriptor {
        let eye: [Float]
        let center: [Float]
        let up: [Float]
        let orthoWidth: Float?
        let orthoHeight: Float?
        let fovDegrees: Float?
        let perspectiveOverrideFOVDegrees: Float?
        let nearZ: Float
        let farZ: Float
    }
}

@main enum Harness {
    static func main() throws {
        let result = try SceneParticleAffineTrailHarness.run(
            casesURL: URL(fileURLWithPath: CommandLine.arguments[1])
        )
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


def expected_vertices(value, extent=512):
    """Independent public quad geometry, never product shader calculations."""
    sx, sy, sz = value["scale"]
    angle = -value["angle"]
    cosine, sine = math.cos(angle), math.sin(angle)
    tilt = value.get("tiltX", 0)

    def transform(point):
        x, y = point[0] * sx, -point[1] * sy
        z = point[2] * sz if len(point) > 2 else 0
        x, y = cosine * x - sine * y, sine * x + cosine * y
        return (x, math.cos(tilt) * y - math.sin(tilt) * z,
                math.sin(tilt) * y + math.cos(tilt) * z)

    length = math.hypot(*value["velocity"][:2])
    dx, dy = (component / length for component in value["velocity"][:2])
    published_width = 64  # Fixed black-box size128 -> full-width64 observation.
    published_length = 256  # Fixed stretch4 -> full-length256 observation.
    if value["kind"] == "sprite":
        # Existing local screen sprites preserve their complete layer frame.
        # The trail-only repair must leave this neighboring affine card intact.
        along = transform((published_width / 2, 0))
        across = transform((0, published_width / 2))
    else:
        along = transform((dx * published_length / 2, dy * published_length / 2))
        if value["kind"] == "rope" or value.get("worldSize"):
            # Existing Rope contract uses an actual displacement chord and a
            # screen-perpendicular cross section. Ordinary-trail repair must
            # preserve this neighboring branch.
            chord_length = math.hypot(*along[:2])
            width = published_width * (1 if value.get("worldSize") else abs(sx))
            across = (
                -along[1] / chord_length * width / 2,
                along[0] / chord_length * width / 2,
                0,
            )
        elif value.get("orientation") == "fixed":
            # Explicit local normal Y and X motion yield a local Z width axis.
            # This prevents a blanket local-Z normal from silently changing
            # the independently authored Fixed-XZ renderer plane.
            across = transform((0, 0, -published_width / 2))
        else:
            across = transform((-dy * published_width / 2, dx * published_width / 2))
    center = 0 if value.get("vertexOnly") else extent / 2
    return [
        (center + a * along[0] + b * across[0],
         center + a * along[1] + b * across[1],
         a * along[2] + b * across[2])
        for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1))
    ]


def expected_polygon(value, extent=512):
    return [vertex[:2] for vertex in expected_vertices(value, extent)]


def polygon_area(vertices):
    return abs(sum(
        first[0] * second[1] - first[1] * second[0]
        for first, second in zip(vertices, vertices[1:] + vertices[:1])
    )) / 2


def interior_distance(point, vertices):
    """Minimum signed distance to a convex polygon's supporting lines."""
    orientation = sum(
        first[0] * second[1] - first[1] * second[0]
        for first, second in zip(vertices, vertices[1:] + vertices[:1])
    )
    sign = 1 if orientation >= 0 else -1
    distances = []
    for first, second in zip(vertices, vertices[1:] + vertices[:1]):
        ex, ey = second[0] - first[0], second[1] - first[1]
        distance = math.hypot(ex, ey)
        if distance:
            distances.append(sign * (ex * (point[1] - first[1])
                                      - ey * (point[0] - first[0])) / distance)
    return min(distances, default=-math.inf)


def swift_sources():
    """Allow frozen shader/support/camera sources without editing the tree."""
    overrides = json.loads(os.environ.get("MWX_PARTICLE_AFFINE_SOURCE_OVERRIDES", "{}"))
    allowed = {"SceneParticleShaderSource.swift", "SceneParticleRenderSupport.swift",
               "SceneParticleCameraFrame.swift"}
    if not isinstance(overrides, dict) or set(overrides) - allowed:
        raise ValueError("Source overrides must name only particle shader/support/camera basenames")
    return [Path(overrides.get(path.name, path)) for path in SWIFT_SOURCES]


def run_checked(arguments, phase):
    completed = subprocess.run(arguments, capture_output=True, text=True)
    if completed.returncode:
        raise AssertionError(
            f"{phase} failed with exit {completed.returncode}:\n"
            f"{completed.stderr}\n{completed.stdout}"
        )
    return completed


class SceneParticleAffineTrailTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-particle-affine-")
        cls.addClassCleanup(cls.temporary_directory.cleanup)
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cases_path = directory / "cases.json"
        cases_path.write_text(json.dumps(CASES), encoding="utf-8")
        binary = directory / "scene-particle-affine"
        sources = swift_sources()
        run_checked(
            ["xcrun", "--sdk", "macosx", "swiftc",
             *(str(path) for path in sources), str(FIXTURE), str(harness),
             "-framework", "Metal", "-o", str(binary)],
            "Swift fixture compilation",
        )
        completed = run_checked(
            [str(binary), str(cases_path)],
            "Metal fixture execution",
        )
        cls.result = json.loads(completed.stdout)
        cls.rows = {row["name"]: row for row in cls.result["cases"]}
        report_path = os.environ.get("MWX_PARTICLE_AFFINE_REPORT")
        if report_path:
            Path(report_path).write_text(
                json.dumps({
                    "inputs": CASES, "gpu": cls.result,
                    "swiftSources": [{"path": str(path),
                                      "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
                                     for path in sources + [FIXTURE, harness]],
                }, indent=2) + "\n",
                encoding="utf-8",
            )

    def assert_card_coverage(self, value):
        row = self.rows[value["name"]]
        self.assertTrue(row["encoded"], row)
        self.assertTrue(row["gpuCompleted"], row)
        self.assertTrue(row["instancesFinite"], row)
        self.assertGreater(row["instanceCount"], 0)
        polygon = expected_polygon(value, self.result["extent"])
        covered = {(x, y) for y, start, end in row["coveredRuns"]
                   for x in range(start, end + 1)}
        self.assertEqual(len(covered), row["visiblePixels"])
        if polygon_area(polygon) < 1e-6:
            self.assertEqual(row["visiblePixels"], 0, row)
            self.assertEqual(row["bounds"], [], row)
            return
        self.assertTrue(covered, row)
        self.assertEqual(row["coveredMinimumBGRA"], [255] * 4, row)
        self.assertEqual(row["coveredMaximumBGRA"], [255] * 4, row)
        expected_bounds = [min(p[0] for p in polygon), min(p[1] for p in polygon),
                           max(p[0] for p in polygon), max(p[1] for p in polygon)]
        # Protocol tolerance: <=2 scene units for axis dimensions. Every
        # interior/exterior pixel outside a 1.25px raster-edge band is exact.
        for actual, wanted in zip(row["bounds"], expected_bounds):
            self.assertAlmostEqual(actual + .5, wanted, delta=1.5,
                                   msg=f"{value['name']}: {row['bounds']} vs {expected_bounds}")
        wrong_outside = [p for p in covered
                         if interior_distance((p[0] + .5, p[1] + .5), polygon) < -1.25]
        self.assertEqual(wrong_outside[:8], [],
                         f"{value['name']}: unexpected GPU coverage {wrong_outside[:8]}")
        missing = []
        for y in range(max(0, math.floor(expected_bounds[1])),
                       min(self.result["extent"], math.ceil(expected_bounds[3]))):
            for x in range(max(0, math.floor(expected_bounds[0])),
                           min(self.result["extent"], math.ceil(expected_bounds[2]))):
                if (x, y) not in covered and interior_distance((x + .5, y + .5), polygon) > 1.25:
                    missing.append((x, y))
        self.assertEqual(missing[:8], [],
                         f"{value['name']}: missing GPU coverage {missing[:8]}")

    def test_axis_trails_apply_length_and_width_scale_independently(self):
        for value in CASES[:4]:
            with self.subTest(case=value["name"]):
                self.assert_card_coverage(value)
        for name, dimensions in (("unit-x", (256, 64)), ("unit-y", (64, 256)),
                                 ("nonuniform-x", (128, 8)), ("nonuniform-y", (32, 32))):
            bounds = self.rows[name]["bounds"]
            self.assertEqual((bounds[2] - bounds[0] + 1, bounds[3] - bounds[1] + 1),
                             dimensions, name)

    def test_diagonal_and_rotated_trails_preserve_affine_card(self):
        for value in CASES[4:8]:
            with self.subTest(case=value["name"]):
                self.assert_card_coverage(value)

    def test_negative_and_zero_scales_are_finite_project_safety_controls(self):
        # These cases preserve signed affine inputs and degenerate safely.
        # Official mirror/zero behavior has not been measured.
        for value in CASES[8:13]:
            with self.subTest(case=value["name"]):
                self.assert_card_coverage(value)

    def test_screen_sprite_billboard_control_remains_unchanged(self):
        for value in CASES[13:15]:
            with self.subTest(case=value["name"]):
                self.assert_card_coverage(value)
        self.assertNotEqual(self.rows["sprite-nonuniform"]["coveredRuns"],
                            self.rows["sprite-nonuniform-rotated"]["coveredRuns"])

    def test_rope_displacement_keeps_screen_perpendicular_cross_section(self):
        for value in CASES[15:17]:
            with self.subTest(case=value["name"]):
                self.assert_card_coverage(value)

    def assert_vertex_geometry(self, value):
        row = self.rows[value["name"]]
        self.assertTrue(row["encoded"], row)
        self.assertTrue(row["gpuCompleted"], row)
        self.assertTrue(row["instancesFinite"], row)
        positions = row["probePositions"]
        self.assertEqual(len(positions), 4, row)
        self.assertTrue(all(len(p) == 4 and all(math.isfinite(c) for c in p)
                            for p in positions), row)
        if value.get("vertexOnly"):
            actual = [p[:3] for p in positions]
            tolerance = 1e-14  # Below 0.01% of the tiny card's shorter edge.
        else:
            extent = self.result["extent"]
            actual = [((p[0] + 1) * extent / 2, (1 - p[1]) * extent / 2,
                       (.5 - p[2]) * self.result["clipDepthSpan"]) for p in positions]
            tolerance = .002
        expected = expected_vertices(value, self.result["extent"])
        for wanted in expected:
            error = min(max(abs(a - b) for a, b in zip(observed, wanted))
                        for observed in actual)
            self.assertLessEqual(error, tolerance,
                                 f"{value['name']}: vertices {actual} vs {expected}")

    def test_zero_depth_with_x_and_z_rotation_keeps_affine_xy_card(self):
        # Project numerical counterexample: A=Rx(.3)*Rz(.7)*diag(.5,-.125,0).
        # Its valid XY plane must survive residual A^T normal components.
        for value in CASES[17:20]:
            with self.subTest(case=value["name"]):
                self.assert_vertex_geometry(value)
                self.assert_card_coverage(value)

    def test_tiny_uniform_scale_retains_nonzero_vertex_geometry(self):
        # Rasterization naturally has no coverage at this scale. Vertex output
        # distinguishes that from an erroneous collapsed affine width.
        for value in CASES[20:22]:
            with self.subTest(case=value["name"]):
                self.assert_vertex_geometry(value)

    def test_world_size_ordinary_trail_preserves_existing_width(self):
        for value in CASES[22:24]:
            with self.subTest(case=value["name"]):
                self.assert_vertex_geometry(value)
                self.assert_card_coverage(value)

    def test_fixed_xz_renderer_preserves_authored_local_plane(self):
        for value in CASES[24:]:
            with self.subTest(case=value["name"]):
                self.assert_vertex_geometry(value)
                self.assert_card_coverage(value)
        # Y is unused by this explicitly authored XZ plane. Zero Y scale must
        # not make a residual-normal fallback silently substitute an XY card.
        self.assertEqual(self.rows["project-fixed-xz-tilted"]["coveredRuns"],
                         self.rows["project-fixed-xz-unused-y-zero"]["coveredRuns"])


if __name__ == "__main__":
    unittest.main()
