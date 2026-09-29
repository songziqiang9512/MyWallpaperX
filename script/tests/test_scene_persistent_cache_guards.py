#!/usr/bin/env python3

"""Source-shape regression gate for the four Scene persistent cache tiers.

SceneGenericShaderAnalysisCache, SceneMaterialDemandAnalysisPersistentCache,
SceneResolvedMaterialVariantAnalysisCache and
SceneAuthoredShaderPreparation.PersistentPreparationCache share one guard
contract. This gate locks it per tier:

- the load path never creates the cache directory (read-only miss),
- the envelope chain validates schemaVersion plus recomputed key and
  payload digests, so corrupted or stale entries degrade to a safe miss,
- store is reachable only from success/accepted paths.
"""

from __future__ import annotations

import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
MATERIAL = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material"
)
PREPARATION = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation"
)

GENERIC_COORDINATION = (
    MATERIAL / "SceneResolvedMaterialGenericShaderPreparationCoordination.swift"
)
MATERIAL_DEMAND = MATERIAL / "SceneMaterialDemandAnalysisPersistentCache.swift"
VARIANT_ANALYSIS = MATERIAL / "SceneResolvedMaterialVariantAnalysisCache.swift"
SHADER_PREPARATION = PREPARATION / "SceneAuthoredShaderPreparation.swift"
GENERIC_ARTIFACT_CACHE = (
    MATERIAL / "SceneResolvedMaterialGenericShaderArtifactCache.swift"
)
RUNTIME_CATALOG = MATERIAL / "SceneResolvedMaterialRuntimeCatalog.swift"
VARIANT_COMPILATION = (
    MATERIAL
    / "SceneResolvedMaterialExecutionCapabilityVariant+Compilation.swift"
)


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


class ScenePersistentCacheGuardTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.generic = GENERIC_COORDINATION.read_text(encoding="utf-8")
        cls.demand = MATERIAL_DEMAND.read_text(encoding="utf-8")
        cls.variant = VARIANT_ANALYSIS.read_text(encoding="utf-8")
        cls.preparation = SHADER_PREPARATION.read_text(encoding="utf-8")
        cls.artifact_cache = GENERIC_ARTIFACT_CACHE.read_text(encoding="utf-8")
        cls.catalog = RUNTIME_CATALOG.read_text(encoding="utf-8")
        cls.compilation = VARIANT_COMPILATION.read_text(encoding="utf-8")

    # MARK: - Gate 1: the load path never creates the cache directory.

    def test_enum_cache_load_paths_only_read_the_cache_directory(self) -> None:
        cases = {
            "generic_analysis": self.generic,
            "material_demand": self.demand,
            "variant_analysis": self.variant,
        }
        for name, source in cases.items():
            with self.subTest(cache=name):
                load = declaration_body(source, "static func load(")
                store = declaration_body(source, "static func store(")
                helper = declaration_body(
                    source, "private static func cacheDirectory("
                )
                self.assertIn("cacheDirectory(createIfNeeded: false)", load)
                self.assertNotIn("createIfNeeded: true", load)
                self.assertIn("cacheDirectory(createIfNeeded: true)", store)
                self.assertNotIn("createIfNeeded: false", store)
                # The flag must reach the support layer, so a load miss
                # really cannot materialize the directory.
                self.assertIn(
                    "ScenePersistentCacheSupport.versionedCacheDirectory(",
                    helper,
                )
                self.assertIn("createIfNeeded: createIfNeeded", helper)

    def test_preparation_cache_load_path_is_read_only(self) -> None:
        cache = declaration_body(
            self.preparation,
            "private final class PersistentPreparationCache",
        )
        load = declaration_body(cache, "func load(")
        store = declaration_body(cache, "func store(")
        directory = declaration_body(cache, "private func directoryURL()")
        # The preparation tier guards the same contract structurally: the
        # load path only reads an existing file and a missing directory or
        # entry degrades to a safe miss.
        self.assertNotIn("createDirectory", load)
        self.assertNotIn("createDirectory", directory)
        self.assertIn("try? Data(contentsOf: url)", load)
        # The only directory creation in the tier lives inside store.
        self.assertEqual(cache.count("createDirectory"), 1)
        self.assertIn("withIntermediateDirectories: true", store)

    # MARK: - Gate 2: envelope chain = schemaVersion + digests.

    def test_enum_cache_envelopes_validate_schema_and_recomputed_digests(
        self,
    ) -> None:
        cases = {
            "generic_analysis": (
                self.generic,
                "let inputSHA256: String",
                "let analysisSHA256: String",
                "envelope.inputSHA256 == digest",
                "recomputed == envelope.analysisSHA256",
            ),
            "material_demand": (
                self.demand,
                "let keySHA256: String",
                "let analysisSHA256: String",
                "envelope.keySHA256 == digest",
                "recomputed == envelope.analysisSHA256",
            ),
            "variant_analysis": (
                self.variant,
                "let keySHA256: String",
                "let recordSHA256: String",
                "envelope.keySHA256 == keySHA256",
                "recomputed == envelope.recordSHA256",
            ),
        }
        for name, (
            source,
            key_field,
            payload_field,
            key_binding,
            payload_binding,
        ) in cases.items():
            with self.subTest(cache=name):
                envelope = declaration_body(source, "struct Envelope: Codable {")
                self.assertIn("let schemaVersion: Int", envelope)
                self.assertIn(key_field, envelope)
                self.assertIn(payload_field, envelope)
                load = declaration_body(source, "static func load(")
                self.assertIn("envelope.schemaVersion == schemaVersion", load)
                self.assertIn(key_binding, load)
                self.assertIn("let recomputed", load)
                self.assertIn(payload_binding, load)

    def test_preparation_envelope_validates_schema_and_recomputed_digests(
        self,
    ) -> None:
        cache = declaration_body(
            self.preparation,
            "private final class PersistentPreparationCache",
        )
        envelope = declaration_body(cache, "struct Envelope: Codable {")
        self.assertIn("let schemaVersion: Int", envelope)
        self.assertIn("let key: PreparationCacheKey", envelope)
        self.assertIn("let keySHA256: String", envelope)
        self.assertIn("let programSHA256: String", envelope)
        load = declaration_body(cache, "func load(")
        self.assertIn("envelope.schemaVersion == schemaVersion", load)
        self.assertIn("envelope.key == key", load)
        self.assertIn("envelope.keySHA256 == keySHA256", load)
        self.assertIn(
            "envelope.keySHA256 == SceneShaderStableDigest.hash(envelope.key)",
            load,
        )
        self.assertIn(
            "envelope.programSHA256"
            " == SceneShaderStableDigest.hash(envelope.program)",
            load,
        )

    # MARK: - Gate 3: store is reachable only from success paths.

    def test_generic_analysis_store_only_publishes_the_accepted_route(
        self,
    ) -> None:
        consumer = self.artifact_cache
        self.assertEqual(
            consumer.count("SceneGenericShaderAnalysisCache.store("), 1
        )
        store = consumer.index("SceneGenericShaderAnalysisCache.store(")
        telemetry = consumer.rindex('outcome: "accepted"', 0, store)
        guard = consumer.rindex("if !analysisFromCache {", 0, store)
        accepted_return = consumer.index("return .accepted(", store)
        # The publication sits on the accepted route: accepted telemetry,
        # fresh-analysis guard, then the accepted resolution return.
        self.assertLess(telemetry, guard)
        self.assertLess(guard, store)
        self.assertLess(store - guard, 200)
        self.assertLess(store, accepted_return)
        self.assertLess(accepted_return - store, 400)
        # A cached-analysis hit never republishes the entry.
        self.assertEqual(consumer.count("if !analysisFromCache {"), 1)

    def test_material_demand_store_only_publishes_ready_analysis(self) -> None:
        consumer = self.catalog
        self.assertEqual(
            consumer.count("SceneMaterialDemandAnalysisPersistentCache.store("),
            1,
        )
        closure = declaration_body(
            consumer, "analyses.result(for: analysisKey)"
        )
        load = closure.index(".load(key: analysisKey)")
        formats = closure.index("launchTextureFormatSlots(")
        samplers = closure.index("reachableSamplers(")
        store = closure.index("SceneMaterialDemandAnalysisPersistentCache.store(")
        ready = closure.index("return .ready(", store)
        catch = closure.index("} catch {", store)
        failed = closure.index("return .failed(", catch)
        # The store sits after the load miss and after both `try` analyses
        # succeeded, before the ready return; the catch path publishes
        # nothing and returns .failed instead.
        self.assertLess(load, store)
        self.assertLess(formats, store)
        self.assertLess(samplers, store)
        self.assertLess(store, ready)
        self.assertLess(store, catch)
        self.assertLess(catch, failed)
        self.assertNotIn(
            "SceneMaterialDemandAnalysisPersistentCache.store(",
            closure[catch:],
        )

    def test_variant_analysis_store_only_publishes_computed_compilations(
        self,
    ) -> None:
        consumer = self.compilation
        self.assertEqual(
            consumer.count("SceneResolvedMaterialVariantAnalysisCache.store("), 1
        )
        body = declaration_body(consumer, "static func compile(")
        guard = "if cachedAnalysis == nil, let variantAnalysisKey {"
        self.assertEqual(body.count(guard), 1)
        guard_index = body.index(guard)
        store = body.index("SceneResolvedMaterialVariantAnalysisCache.store(")
        end_variant = body.index(
            "SceneResolvedMaterialVariantCompileProfile.endVariant()"
        )
        success_return = body.index("return .init(", end_variant)
        # The store fires exactly once per fresh compilation, on the
        # straight-line path that ends in the compiled variant.
        self.assertLess(guard_index, store)
        self.assertLess(store, end_variant)
        self.assertLess(end_variant, success_return)
        self.assertIn(
            "readinessMask:", body[success_return : success_return + 200]
        )
        # No failure hop between the guard and the publication.
        guarded_window = body[guard_index:store]
        self.assertNotIn("catch", guarded_window)
        self.assertNotIn("throw ", guarded_window)

    def test_preparation_store_is_only_called_on_accepted_results(self) -> None:
        consumer = self.preparation
        self.assertEqual(
            consumer.count("persistentPreparationCache.store("), 1
        )
        entry = declaration_body(
            consumer, "nonisolated static func prepareShaderStages("
        )
        accepted = entry.index("if case let .accepted(program) = result")
        store = entry.index("persistentPreparationCache.store(")
        self.assertLess(accepted, store)
        self.assertNotIn(
            "persistentPreparationCache.store(", entry[:accepted]
        )


if __name__ == "__main__":
    unittest.main()
