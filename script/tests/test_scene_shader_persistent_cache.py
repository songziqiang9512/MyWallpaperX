#!/usr/bin/env python3

from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX" / "Core" / "SteamWorkshopScene"
FRONTEND = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderFrontend/SceneAuthoredShaderFrontend.swift"
)
PREPARATION = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneAuthoredShaderPreparation.swift"
)
ARCHITECTURE = ROOT / "docs/scene/architecture/runtime-architecture.md"


def declaration_body(source: str, signature: str) -> str:
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 0
    for index in range(opening, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[opening : index + 1]
    raise AssertionError(f"unterminated declaration: {signature}")


class SceneShaderPersistentCacheTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.frontend = FRONTEND.read_text(encoding="utf-8")
        cls.preparation = PREPARATION.read_text(encoding="utf-8")
        cls.architecture = ARCHITECTURE.read_text(encoding="utf-8")

    def test_frontend_key_covers_full_compile_inputs_and_schema(self) -> None:
        key = declaration_body(self.frontend, "private struct ProgramCacheKey")
        for field in (
            "cacheSchemaVersion",
            "vertexSourceSHA256",
            "fragmentSourceSHA256",
            "runtimeLoopBounds",
            "provenColorTransfer",
        ):
            self.assertIn(field, key)
        self.assertIn("ProgramCacheDigest.hash(Data(vertexSource.utf8))", key)
        self.assertIn("ProgramCacheDigest.hash(Data(fragmentSource.utf8))", key)
        self.assertNotIn("SceneShaderVariantEnvironment", key)

    def test_preparation_key_covers_graph_variant_and_resource_facts(self) -> None:
        key = declaration_body(self.preparation, "private struct PreparationCacheKey")
        for field in (
            "frontendSchemaVersion",
            "contractCanonicalSHA256",
            "sourceGraphSHA256",
            "combos",
            "inactiveComboProviders",
            "textureReadiness",
            "textureFormats",
        ):
            self.assertIn(field, key)
        self.assertIn("SceneShaderStableDigest.hash(graph)", key)
        self.assertIn(".sorted", key)



    def test_disk_failure_is_optional_and_capacity_is_bounded(self) -> None:
        self.assertIn("private let retainedEntryLimit = 1_024", self.frontend)
        self.assertIn("private let retainedEntryLimit = 2_048", self.preparation)
        self.assertIn("guard let data = try? Data(contentsOf: url)", self.frontend)
        self.assertIn("guard let data = try? Data(contentsOf: url)", self.preparation)
        self.assertIn("options: [.skipsHiddenFiles]", self.frontend)
        self.assertIn("options: [.skipsHiddenFiles]", self.preparation)
        store = declaration_body(
            self.frontend,
            "func store(_ program: SceneAuthoredShaderProgram",
        )
        self.assertLess(
            store.index("memory[key] = program"),
            store.index("guard let directory = directoryURL()"),
        )

    def test_architecture_does_not_confuse_cpu_cache_with_device_ready(self) -> None:
        self.assertIn(
            "PreparedContent -> PreparedLaunchPlan -> PreparedDeviceResources",
            self.architecture,
        )
        self.assertIn("只代表 CPU Program/preparation 可复用", self.architecture)
        self.assertIn("不得声明 device 资源或首帧已经 ready", self.architecture)


if __name__ == "__main__":
    unittest.main()
