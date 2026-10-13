#!/usr/bin/env python3

"""Atomic R3 Program derivation and cache-identity boundaries."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_swift_source_sets import scene_swift_sources  # noqa: E402


SWIFT_SOURCES = [
    *scene_swift_sources("authored_shader_frontend_core"),
    *scene_swift_sources("shader_variant_environment"),
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Graph/SceneAuthoredEffectRenderPlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneMaterialRenderState.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureSampling.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureUVTransform.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureCandidate.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureSlotBinding.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneNamedTextureReference.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureProviderPublication.swift",
    *scene_swift_sources("resolved_material_program_model"),
]


FIXTURE_ROOT = REPOSITORY_ROOT / "script/tests/fixtures"
SUPPORT_SOURCE = FIXTURE_ROOT / "SceneResolvedMaterialDerivationSupport.swift"
FIXTURE_SOURCES = [
    SUPPORT_SOURCE,
    FIXTURE_ROOT / "SceneResolvedMaterialDerivationFixtures.swift",
    FIXTURE_ROOT / "SceneResolvedMaterialPreparedAssemblyCases.swift",
    FIXTURE_ROOT / "SceneResolvedMaterialDerivationCases.swift",
]


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneResolvedMaterialProgramDerivationTests(unittest.TestCase):
    def test_program_is_derived_atomically_and_identities_are_bounded(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-resolved-material-program-"
        ) as directory:
            root = Path(directory)
            binary = root / "resolved-material-program-test"
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
            environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
            compilation = subprocess.run(
                [
                    "xcrun",
                    "--sdk",
                    "macosx",
                    "swiftc",
                    "-parse-as-library",
                    *(str(path) for path in SWIFT_SOURCES),
                    *(str(path) for path in FIXTURE_SOURCES),
                    "-framework",
                    "Metal",
                    "-framework",
                    "CoreGraphics",
                    "-module-cache-path",
                    str(root / "module-cache"),
                    "-o",
                    str(binary),
                ],
                cwd=REPOSITORY_ROOT,
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary)],
                cwd=REPOSITORY_ROOT,
                env=environment,
                check=True,
                capture_output=True,
                text=True,
            )
        result = json.loads(completed.stdout)
        if not result["metalAvailable"]:
            self.skipTest("Metal is unavailable")
        self.assertEqual(
            [name for name, passed in result.items() if not passed],
            [],
            result,
        )


if __name__ == "__main__":
    unittest.main()
