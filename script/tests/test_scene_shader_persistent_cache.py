#!/usr/bin/env python3

from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX" / "Core" / "SteamWorkshopScene"
FRONTEND = (
    SCENE
    / "RenderGraph"
    / "ShaderFrontend"
    / "SceneAuthoredShaderFrontend.swift"
)
PREPARATION = (
    SCENE
    / "RenderGraph"
    / "ShaderPreparation"
    / "SceneAuthoredShaderPreparation.swift"
)
ARCHITECTURE = ROOT / "docs" / "scene" / "runtime-architecture.md"


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
            "frontendSchemaVersion",
            "vertexSourceSHA256",
            "fragmentSourceSHA256",
            "runtimeLoopBounds",
            "provenColorTransfer",
        ):
            self.assertIn(field, key)
        self.assertIn("SceneShaderStableDigest.hash(Data(vertexSource.utf8))", key)
        self.assertIn("SceneShaderStableDigest.hash(Data(fragmentSource.utf8))", key)

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

    def test_envelopes_bind_requested_key_and_payload_digest(self) -> None:
        frontend_cache = declaration_body(
            self.frontend, "private final class ProgramCache"
        )
        preparation_cache = declaration_body(
            self.preparation, "private final class PersistentPreparationCache"
        )
        for cache in (frontend_cache, preparation_cache):
            self.assertIn("let key:", cache)
            self.assertIn("envelope.key == key", cache)
            self.assertIn("SceneShaderStableDigest.hash(envelope.key)", cache)
            self.assertIn("programSHA256", cache)
            self.assertIn("SceneShaderStableDigest.hash(envelope.program)", cache)
            self.assertIn("options: .atomic", cache)

    def test_persistent_tier_only_stores_accepted_products(self) -> None:
        frontend_compile = declaration_body(self.frontend, "static func compile(")
        self.assertLess(
            frontend_compile.index("let program = SceneAuthoredShaderProgram("),
            frontend_compile.index("programCache.store(program, for: cacheKey)"),
        )
        preparation_entry = declaration_body(
            self.preparation, "nonisolated static func prepareShaderStages("
        )
        self.assertIn("if case let .accepted(program) = result", preparation_entry)
        accepted_block = preparation_entry[
            preparation_entry.index("if case let .accepted(program) = result") :
        ]
        self.assertIn("persistentPreparationCache.store(", accepted_block)
        before_accepted = preparation_entry[
            : preparation_entry.index("if case let .accepted(program) = result")
        ]
        self.assertNotIn("persistentPreparationCache.store(", before_accepted)

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
