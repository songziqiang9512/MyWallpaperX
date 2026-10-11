#!/usr/bin/env python3
"""Preparation ownership tests; the controlled loader does not test decoding/draws."""

from __future__ import annotations

import json
import os
import platform
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
PREPARATION = SCENE / "Runtime/Session/ScenePreparedDeviceResources.swift"
RESOLVER = SCENE / "Resources/Textures/SceneTexturePathResolver.swift"
BUILTIN = SCENE / "Compilation/ShaderContract/SceneBuiltinShaderIdentity.swift"
RENDER_STATE = SCENE / "Compilation/Material/SceneMaterialRenderState.swift"
FIXTURE = Path(__file__).with_name("fixtures") / "ScenePreparedBaseImageResourcesHarness.swift"


@unittest.skipUnless(platform.system() == "Darwin", "requires native Metal textures")
class ScenePreparedBaseImageResourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.workspace = tempfile.TemporaryDirectory(prefix="mwx-prepared-base-images-")
        workspace = Path(cls.workspace.name)
        cls.addClassCleanup(cls.workspace.cleanup)
        binary = workspace / "checks"
        source = Path(os.environ.get("MWX_PREPARED_BASE_IMAGE_SOURCE", PREPARATION))
        compile_result = subprocess.run(
            ["xcrun", "swiftc", "-swift-version", "5", str(source), str(RESOLVER),
             str(BUILTIN), str(RENDER_STATE),
             str(FIXTURE), "-framework", "Metal", "-module-cache-path",
             str(workspace / "modules"), "-o", str(binary)],
            capture_output=True, text=True, timeout=120,
        )
        if compile_result.returncode:
            raise AssertionError(compile_result.stdout + compile_result.stderr)
        run = subprocess.run([str(binary), str(workspace / "assets")],
                             capture_output=True, text=True, timeout=30)
        if run.returncode:
            raise AssertionError(run.stdout + run.stderr)
        cls.facts = json.loads(run.stdout)
        if cls.facts.get("skip"):
            raise unittest.SkipTest(cls.facts["skip"])
        if output := os.environ.get("MWX_PREPARED_BASE_IMAGE_RESULT"):
            Path(output).write_text(json.dumps(cls.facts, indent=2, sort_keys=True) + "\n")

    def test_successful_entries_reuse_the_same_loaded_reference_without_loading(self) -> None:
        case = self.facts["shared"]
        self.assertEqual(case["loads"], 2)
        self.assertEqual(case["loadedCount"], 2)
        self.assertEqual(case["dynamicCount"], 1)
        self.assertTrue(case["sameTexture"])
        self.assertTrue(case["sameCandidate"])
        self.assertEqual(case["size"], [2, 1])

    def test_layer_override_cannot_publish_as_the_model_default(self) -> None:
        case = self.facts["overrideWithCanonicalPeer"]
        self.assertEqual(case["loads"], 2)
        self.assertEqual(case["dynamicCount"], 1)
        self.assertTrue(case["sameCanonicalTexture"])
        self.assertTrue(case["differentOverrideTexture"])
        for name in ("overrideOnly", "missingCanonical"):
            with self.subTest(name=name):
                self.assertEqual(self.facts[name]["loads"], 1)
                self.assertEqual(self.facts[name]["dynamicCount"], 0)

    def test_deferred_missing_and_special_providers_are_not_opened(self) -> None:
        for name in ("deferred", "missing", "puppet", "composition", "solid", "animated"):
            with self.subTest(name=name):
                self.assertEqual(self.facts[name]["loads"], 0)
                self.assertEqual(self.facts[name]["dynamicCount"], 0)
        self.assertTrue(self.facts["deferred"]["pending"])

    def test_failed_or_untyped_publication_cannot_escape_into_dynamic_resources(self) -> None:
        for name in ("decodeFailure", "uploadFailure", "noCandidate", "mismatchedCandidate", "loadedAnimation"):
            with self.subTest(name=name):
                self.assertEqual(self.facts[name]["loads"], 1)
                self.assertEqual(self.facts[name]["dynamicCount"], 0)
        case = self.facts["uploadFailure"]
        self.assertFalse(case["hasOutcome"])
        self.assertEqual(case["loadedCount"], 0)
        self.assertEqual(case["failedCount"], 1)
        self.assertEqual(case["evicted"], 1)

    def test_explicit_dynamic_preparation_retains_priority_and_existing_behavior(self) -> None:
        case = self.facts["explicitWithEntry"]
        self.assertEqual(case["loads"], 2)
        self.assertEqual(case["loadedCount"], 2)
        self.assertEqual(case["dynamicCount"], 1)
        self.assertEqual(case["dynamicLoadOrdinal"], 2)
        self.assertEqual(case["entryLoadOrdinal"], 1)
        self.assertEqual(self.facts["explicitOnly"]["loads"], 1)
        self.assertEqual(self.facts["explicitOnly"]["dynamicCount"], 1)

    def test_plain_texture_success_cannot_admit_unknown_material_semantics(self) -> None:
        for name in ("customShader", "multiplePasses", "duplicateModelLinks", "secondSlot",
                     "provider", "constant", "userShaderValue", "unknownCombo", "wrongVersion",
                     "additive", "depthEnabled", "alphaWriting"):
            with self.subTest(name=name):
                self.assertEqual(self.facts[name]["loads"], 1)
                self.assertTrue(self.facts[name]["hasOutcome"])
                self.assertEqual(self.facts[name]["dynamicCount"], 0)


if __name__ == "__main__":
    unittest.main()
