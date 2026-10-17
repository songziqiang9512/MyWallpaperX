#!/usr/bin/env python3
"""Prepared scene defaults and current world control points through real Swift owners."""
from __future__ import annotations
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from script.tests.test_scene_particle_simulator import SWIFT_SOURCES as SIMULATOR_SOURCES
from script.tests.test_scene_solid_layers import SWIFT_SOURCES as DOCUMENT_SOURCES, HARNESS_SOURCE as DOCUMENT_CARRIER

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
FIXTURE = Path(__file__).parent / "fixtures/SceneParticleControlPointForceHarness.swift"
SWIFT_SOURCES = list(dict.fromkeys([
    *SIMULATOR_SOURCES, *DOCUMENT_SOURCES,
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/SceneLayerDynamicWorldFrameResolver.swift",
]))


def document_carrier() -> str:
    """Reuse existing non-particle link DTOs; production particle types own this gate."""
    prefix = DOCUMENT_CARRIER.split("@main\n", 1)[0]
    start = prefix.index("struct SceneParticleInstanceOverride: Codable {}")
    end = prefix.index("struct SceneTextDescriptor:", start)
    return prefix[:start] + prefix[end:]


class SceneParticleControlPointForceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-cp-force-")
        cls.addClassCleanup(cls.temporary.cleanup)
        directory = Path(cls.temporary.name)
        carrier = directory / "DocumentLinkDTOs.swift"
        carrier.write_text(document_carrier(), encoding="utf-8")
        cls.binary = directory / "force-checks"
        cls.compile_argv = [swiftc, "-module-cache-path", str(directory / "module-cache"),
                            *map(str, SWIFT_SOURCES), str(carrier), str(FIXTURE),
                            "-framework", "Metal", "-o", str(cls.binary)]
        compiled = subprocess.run(cls.compile_argv, capture_output=True, text=True, timeout=150)
        cls.compile_stdout, cls.compile_stderr = compiled.stdout, compiled.stderr
        if compiled.returncode:
            raise RuntimeError(compiled.stderr)
        actual = subprocess.run([str(cls.binary)], capture_output=True, text=True, timeout=20)
        cls.actual_stdout, cls.actual_stderr = actual.stdout, actual.stderr
        if actual.returncode:
            raise RuntimeError(actual.stderr)
        cls.results = json.loads(actual.stdout)

    def assertVector(self, actual: list[float], expected: list[float], tolerance: float = 1e-5) -> None:
        self.assertEqual(len(actual), len(expected))
        for a, e in zip(actual, expected):
            self.assertAlmostEqual(a, e, delta=tolerance)

    def test_authored_projection_selects_force_default_and_preserves_explicit_values(self) -> None:
        for row in self.results["projection"]:
            with self.subTest(name=row["name"]):
                active = row["name"] in {"fixed", "auto", "auto-with-zero-size"}
                self.assertTrue(row["activeKnown"])
                self.assertEqual(row["active"], active)
                self.assertEqual(row["default"], 512 if active else 5)
                self.assertEqual(row["maximum"], 512 if active else 5)
                self.assertVector(row["velocity"], [2, 0, 0] if active else [0, 0, 0])
                self.assertVector(row["nearVelocity"], [2, 0, 0])
                self.assertEqual(row["explicitZeroMaximum"], 0)
                self.assertVector(row["explicitZeroVelocity"], [0, 0, 0])
                self.assertVector(row["explicit20Velocity"], [2, 0, 0])
        self.assertTrue(self.results["legacyUnknownDefault"])
        for row in self.results["malformedThreshold"]:
            self.assertFalse(row["plan"], row)
            self.assertVector(row["velocity"], [0, 0, 0])

    def test_world_target_uses_canonical_transform_and_current_frame(self) -> None:
        for row in self.results["world"]:
            with self.subTest(name=row["name"]):
                self.assertTrue(row["allowed"])
                self.assertEqual(row["space"], "world")
                self.assertVector(row["localPoint"], [10, 20, 0], 2e-4)
                self.assertVector(row["velocity"], [2 / (5 ** .5), 4 / (5 ** .5), 0], 2e-4)
                self.assertVector(row["localVelocity"], [2, 0, 0])
                self.assertTrue(row["changedFrameTurnsForce"])
        self.assertVector(self.results["fixedWorldAfterTranslation"], [-30, -40, 0])
        self.assertTrue(self.results["rollbackRestoresForceFrame"])
        self.assertTrue(self.results["prewarmUsesInitialFrame"])

    def test_world_admission_and_invalid_frame_failure_are_local(self) -> None:
        for row in self.results["admission"]:
            with self.subTest(name=row["name"]):
                self.assertFalse(row["allowed"])
                self.assertFalse(row["worldPlan"])
                self.assertEqual(row["default"], 512)
                self.assertTrue(row["localPlan"])
        for row in self.results["invalidFrames"]:
            with self.subTest(name=row["name"]):
                self.assertTrue(row["rejected"])
                self.assertEqual(row["particleCount"], 1)
                self.assertVector(row["velocity"], [0, 1, 0])
                self.assertTrue(row["worldRecovers"])
        self.assertTrue(self.results["unpreparedChildKeepsExplicitLocalOnly"])
        self.assertTrue(self.results["worldZeroIsRejectedLocalZeroPreserved"])
        self.assertTrue(self.results["worldOffsetRejectedLocalOriginPreserved"])


if __name__ == "__main__":
    unittest.main()
