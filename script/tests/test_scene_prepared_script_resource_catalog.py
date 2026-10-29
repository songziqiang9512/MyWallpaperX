"""Actual launch resource join with controlled carriers, without Metal or VM startup."""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SCHEMA = SCENE / "Runtime/Session/SceneDesktopWallpaperLaunchFrameSchema.swift"
HOST = SCENE / "Runtime/Session/SceneDesktopWallpaperHost+Launch.swift"
RESOURCE = SCENE / "Runtime/Session/ScenePreparedDeviceResources.swift"
PROFILE = SCENE / "Compilation/Material/SceneBaseMaterialLightingProfile.swift"
TOPOLOGY = SCENE / "Systems/Script/SceneScriptLayerTopologyModels.swift"
IDENTITY = SCENE / "Resources/Assets/SceneModelResourceIdentity.swift"
FIXTURE = ROOT / "script/tests/fixtures/ScenePreparedScriptResourceCatalogHarness.swift"


def swift_declaration(source: str, signature: str) -> str:
    """Extract one whole production declaration, retaining its implementation."""
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 0
    for index in range(opening, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[start:index + 1]
    raise AssertionError(f"unterminated Swift declaration: {signature}")


class ScenePreparedScriptResourceCatalogTests(unittest.TestCase):
    def test_actual_launch_join_preserves_only_executable_resource_templates(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        # Compile the complete real join method and real value carriers. The
        # remainder of frame schema, resource preparation and profile compilation
        # have independent owners/gates; they are deliberately outside this cut.
        production = "import Foundation\n" + "\n".join([
            "enum SceneDesktopWallpaperLaunchFrameSchema {\n"
            + swift_declaration(SCHEMA.read_text(), "    static func preparedResourceCatalog(")
            + "\n}",
            swift_declaration(RESOURCE.read_text(), "struct ScenePreparedDynamicImageResource {"),
            swift_declaration(PROFILE.read_text(), "nonisolated struct SceneBaseMaterialLightingProfile:"),
            swift_declaration(TOPOLOGY.read_text(), "nonisolated struct SceneScriptPreparedResourceLayerTemplate:"),
        ])
        with tempfile.TemporaryDirectory(prefix="mwx-prepared-resource-join-") as directory:
            temporary = Path(directory)
            source = temporary / "ProductionJoin.swift"
            source.write_text(production, encoding="utf-8")
            binary = temporary / "join"
            compiled = subprocess.run([
                "swiftc", str(IDENTITY), str(source), str(FIXTURE),
                "-module-cache-path", str(temporary / "cache"), "-o", str(binary),
            ], cwd=ROOT, text=True, capture_output=True, timeout=60)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            completed = subprocess.run([str(binary)], cwd=ROOT, text=True,
                                       capture_output=True, timeout=15)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            result = json.loads(completed.stdout)

        templates = result["templates"]
        self.assertEqual(set(templates), {
            "models/plain.json", "models/lit.json", "models/full-source.json",
            "models/lowered.json", "models/autosize.json", "models/puppet.json",
            "models/composition.json", "models/video.json", "models/video-autosize.json",
            "models/video-source.json",
        })
        self.assertEqual(set(result["profiles"]), {
            "models/plain.json", "models/lit.json", "models/autosize.json", "models/puppet.json",
            "models/video.json", "MODELS\\VIDEO-AUTOSIZE.JSON",
        })
        for key in ("models/plain.json", "models/lit.json"):
            with self.subTest(builtin=key):
                self.assertEqual(templates[key]["modelPath"], key)
                self.assertIn(key, result["profiles"])
        self.assertEqual(templates["models/plain.json"]["renderSizeWH"], [96, 48])
        self.assertEqual(result["profiles"]["models/plain.json"], {"lighting": False, "scalar": []})
        self.assertEqual(result["profiles"]["models/lit.json"]["lighting"], True)
        self.assertEqual(len(result["profiles"]["models/lit.json"]["scalar"]), 2)
        for actual, wanted in zip(result["profiles"]["models/lit.json"]["scalar"], [.21, .79]):
            self.assertAlmostEqual(actual, wanted, places=6)
        for key in ("models/full-source.json", "models/lowered.json", "models/video-source.json"):
            with self.subTest(source_material=key):
                self.assertIn(key, templates)
                self.assertNotIn(key, result["profiles"])
        self.assertEqual(templates["models/full-source.json"]["modelPath"], "MODELS\\FULL-SOURCE.JSON")
        self.assertEqual(result["unprovedSourceTemplates"], [])
        for name, passed in result["rejected"].items():
            with self.subTest(rejected=name):
                self.assertTrue(passed)
        autosize = templates["models/autosize.json"]
        self.assertTrue(autosize["autosize"])
        self.assertEqual(autosize["renderSizeWH"], [800, 600])
        self.assertEqual(autosize["defaultRenderSizeWH"], [800, 600])
        video = templates["models/video.json"]
        self.assertEqual(video["kind"], "image")
        self.assertEqual(video["renderSizeWH"], [3750, 2250])
        self.assertEqual(video["defaultRenderSizeWH"], [1, 1])
        self.assertFalse(video["autosize"])
        self.assertIsNone(video["puppetMeshPath"])
        video_auto = templates["models/video-autosize.json"]
        self.assertEqual(video_auto["modelPath"], "MODELS\\VIDEO-AUTOSIZE.JSON")
        self.assertEqual(video_auto["kind"], "image")
        self.assertTrue(video_auto["autosize"])
        self.assertEqual(video_auto["renderSizeWH"], [3750, 2250])
        self.assertEqual(video_auto["defaultRenderSizeWH"], [3750, 2250])
        puppet = templates["models/puppet.json"]
        self.assertEqual(puppet["puppetMeshPath"], "models/unseen-puppet.mdl")
        self.assertEqual(puppet["renderSizeWH"], [512, 256])
        self.assertEqual(puppet["defaultRenderSizeWH"], [1, 1])
        self.assertFalse(puppet["autosize"])
        self.assertFalse(result["profiles"]["models/puppet.json"]["lighting"])
        composition = templates["models/composition.json"]
        self.assertEqual(composition["kind"], "composition")
        self.assertEqual(composition["renderSizeWH"], [1, 1])
        self.assertIsNone(composition["puppetMeshPath"])
        self.assertEqual(result["compositionOnlyProfiles"], [])
        self.assertTrue(result["compositionRequiresOrthographicHeight"])
        self.assertTrue(result["inputProfilesPreserved"])

    def test_host_supplies_successful_runtime_and_admitted_lowered_paths(self) -> None:
        # Interface wiring only. The compiled test above proves join behavior;
        # these source checks do not claim shader/VM/GPU preparation succeeded.
        host = re.sub(r"\s+", "", HOST.read_text())
        self.assertIn("letprovenMaterialBindings=model.propertyVectorProjection.materialBindings", host)
        self.assertIn("letloweredMaterialModelPaths=Set(provenMaterialBindings"
                      ".filter(\\.canLowerToCompositor).map(\\.modelPath))", host)
        self.assertIn("sourceMaterialModelPaths:Set(firstSurfaceRuntime.sourceMaterialPrototypeByModel.keys)"
                      ".union(loweredMaterialModelPaths)", host)
        self.assertIn("letpreparedResourceLayerTemplates=resourceCatalog.templates", host)
        self.assertIn(".preparingDynamicImageMaterials(resourceCatalog.lightingProfiles)", host)
        self.assertIn("configurePreparedResourceLayerCatalog(preparedResourceLayerTemplates)", host)
        self.assertIn("preparedResourceLayerTemplates:preparedResourceLayerTemplates", host)


if __name__ == "__main__":
    unittest.main()
