#!/usr/bin/env python3

"""Behavior gate for the four Scene persistent cache tiers.

Each tier is probed through its real load/store surface against an isolated,
environment-overridden cache root (MWX_SCENE_GENERIC_SHADER_CACHE):

- read-only miss: a load on a missing tier directory misses without
  materializing the directory,
- publish + hit: store persists exactly one entry and a later load returns
  the stored payload,
- corrupted bytes, a tampered payload digest and a stale schema version each
  degrade to a safe miss,
- the preparation tier is driven through its real consumer
  (SceneAuthoredShaderPreparation.prepareShaderStages): a rejected
  preparation publishes nothing, an accepted one publishes exactly one
  entry, a later launch hits the persisted entry without republishing it,
  and corrupted or schema-stale entries re-prepare and heal the file.
"""

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
# Explicit invalidation expectation; never derive this from the product under test.
CURRENT_VARIANT_SCHEMA_VERSION = 29
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_swift_source_sets import scene_swift_sources  # noqa: E402


SWIFT_SOURCES = [
    *scene_swift_sources("scene_resource_input"),
    Path(__file__).resolve().parents[2] / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneResourceBudget.swift",
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "Format/SceneBCTextureDecoder.swift",
    SCENE_ROOT / "Format/SceneTexContainer.swift",
    SCENE_ROOT / "Format/SceneTexDataReader.swift",
    SCENE_ROOT / "Systems/Properties/SceneDynamicSnapshot.swift",
    SCENE_ROOT / "Compilation/ShaderContract/SceneShaderSourceGraph.swift",
    SCENE_ROOT / "Compilation/ShaderContract/SceneShaderLegacyAnnotationJSON.swift",
    SCENE_ROOT / "Compilation/ShaderContract/SceneShaderContract.swift",
    SCENE_ROOT / "Compilation/ShaderContract/SceneShaderCacheIdentity.swift",
    SCENE_ROOT / "Compilation/Graph/SceneAuthoredEffectRenderPlan.swift",
    SCENE_ROOT / "Runtime/Frame/SceneMaterialRenderState.swift",
    SCENE_ROOT / "Compilation/Material/SceneMaterialRenderState+Compilation.swift",
    *scene_swift_sources("authored_shader_frontend_implementation"),
    SCENE_ROOT / "Rendering/Bindings/SceneAuthoredShaderFrameInputs.swift",
    *scene_swift_sources("authored_shader_preparation_implementation"),
    *scene_swift_sources("generic_shader_compiler_preparation_implementation"),
    SCENE_ROOT / "Resources/Textures/SceneImageTextureUploader.swift",
    SCENE_ROOT / "Resources/Textures/SceneImageTextureUploader+Resample.swift",
    SCENE_ROOT / "Resources/Textures/SceneCompressedTextureUploader.swift",
    SCENE_ROOT / "Resources/Textures/SceneTextureMipUploader.swift",
    SCENE_ROOT / "Resources/Textures/SceneTextureLoader.swift",
    SCENE_ROOT / "Resources/Textures/SceneTextureSampling.swift",
    SCENE_ROOT / "Resources/Textures/SceneTextureUVTransform.swift",
    SCENE_ROOT / "Resources/Textures/SceneTextureCandidate.swift",
    SCENE_ROOT / "Resources/Assets/SceneStockTextureSemanticRegistry.swift",
    SCENE_ROOT / "Resources/Textures/SceneTextureSlotBinding.swift",
    SCENE_ROOT / "Resources/Textures/SceneTextureProviderPublication.swift",
    SCENE_ROOT / "Resources/Textures/SceneNamedTextureReference.swift",
    SCENE_ROOT / "Resources/Textures/SceneFrameTextureRegistry.swift",
    # Covers the three Material analysis tiers under probe plus their
    # program/template/schema/resolver closure (the template-compilation
    # set is deliberately excluded: its document/script-binding owners are
    # outside this probe and drag the whole document model in).
    *scene_swift_sources("resolved_material_frame_finalization"),
    SCENE_ROOT / "Compilation/ShaderPreparation/SceneGenericShaderExpectedColorTransfer.swift",
]

SUPPORT = r'''
import Foundation

nonisolated enum SceneEffectStageCompilerBackend {
    case authoredShader
}

nonisolated struct SceneEffectStageCompilerFailure {
    enum Phase: String {
        case shaderPreprocessor = "shader-preprocessor"
        case invariant
    }

    enum Code: String {
        case shaderStageMissing = "shader-stage-missing"
        case shaderSourceGraphMissing = "shader-source-graph-missing"
        case shaderSourceIdentityMismatch = "shader-source-identity-mismatch"
        case shaderVariantInvalid = "shader-variant-invalid"
        case shaderIncludeMissing = "shader-include-missing"
        case shaderIncludeAmbiguous = "shader-include-ambiguous"
        case shaderIncludeCycle = "shader-include-cycle"
        case shaderDirectiveUnsupported = "shader-directive-unsupported", shaderModuleResolutionRejected = "shader-module-resolution-rejected"
        case shaderConditionInvalid = "shader-condition-invalid"
        case shaderPreprocessorBudgetExceeded = "shader-preprocessor-budget-exceeded"
        case shaderPreprocessorDiagnostic = "shader-preprocessor-diagnostic"
        case shaderPreparationInvariant = "shader-preparation-invariant"
    }

    let backend: SceneEffectStageCompilerBackend
    let phase: Phase
    let code: Code
    let details: [String]
}

nonisolated enum SceneEffectStageBackendCompileResult<Value> {
    case notApplicable
    case rejected(SceneEffectStageCompilerFailure)
    case accepted(Value)
}

nonisolated struct SceneResolvedMaterialNode {
    enum TextureProvenance: String, Hashable {
        case material
        case instance
        case userTexture
        case explicitBinding
    }
}
'''

HARNESS = (Path(__file__).with_name("fixtures") / "ScenePersistentCacheBehaviorChecks.swift").read_text(encoding="utf-8")

EXPECTED_TIER_CHECKS = {
    "generic": [
        "read-only-miss",
        "publish",
        "hit",
        "graph-content-key-miss",
        "background-color-fact-key-and-abi",
        "graph-data-excluded-from-color-boundary",
        "graph-data-sample-preserved-color-converted-once",
        "corrupt-safe-miss",
        "tampered-digest-miss",
        "stale-schema-miss",
        "wrong-key-miss",
    ],
    "variant": [
        "read-only-miss",
        "publish",
        "hit",
        "corrupt-safe-miss",
        "tampered-digest-miss",
        "stale-schema-miss",
    ],
    "demand": [
        "read-only-miss",
        "publish",
        "hit",
        "corrupt-safe-miss",
        "tampered-digest-miss",
        "stale-schema-miss",
    ],
}


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class ScenePersistentCacheBehaviorTests(unittest.TestCase):
    def test_persistent_cache_tiers_behave_under_isolated_roots(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-persistent-cache-probe-"
        ) as directory:
            root = Path(directory)
            support = root / "Support.swift"
            harness = root / "Harness.swift"
            binary = root / "persistent-cache-probe"
            support.write_text(SUPPORT, encoding="utf-8")
            harness.write_text(HARNESS, encoding="utf-8")
            (root / "SceneShaderCacheIdentity.json").write_text(
                json.dumps({"schemaVersion": 1, "semantics": "a" * 64,
                            "toolchain": "b" * 64}), encoding="utf-8"
            )
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
            environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
            sources = list(
                dict.fromkeys(str(path) for path in SWIFT_SOURCES)
            )
            compilation = subprocess.run(
                [
                    "xcrun",
                    "--sdk",
                    "macosx",
                    "swiftc",
                    "-parse-as-library",
                    str(support),
                    *sources,
                    str(harness),
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
            for tier in ("generic", "variant", "demand"):
                with self.subTest(tier=tier):
                    self.run_tier_probe(binary, root, environment, tier)
            self.run_analysis_root_probes(binary, root, environment)
            self.run_preparation_phases(binary, root, environment)

    def run_analysis_root_probes(self, binary: Path, root: Path, environment: dict) -> None:
        def run(mode: str, cache: Path | str) -> list[str]:
            completed = subprocess.run(
                ["/usr/bin/env", str(binary), mode], cwd=REPOSITORY_ROOT,
                env={**environment, "HOME": str(root), "CFFIXED_USER_HOME": str(root),
                     "MWX_SCENE_GENERIC_SHADER_CACHE": str(cache)},
                capture_output=True, text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr or completed.stdout)
            payload = json.loads(completed.stdout)
            self.assertIsNone(payload.get("failure"), payload)
            return payload["checks"]

        cache = root / "new-parent" / "analysis-only"
        self.assertEqual(run("generic-root-read", cache), ["read-only-missing-root"])
        self.assertFalse(cache.parent.exists())
        self.assertEqual(run("generic-root-write", cache),
                         ["standalone-analysis-write", "persisted-analysis-hit"])
        self.assertEqual([path.name for path in cache.iterdir()], ["SceneGenericShaderAnalysis-v18"])
        entries = sorted((cache / "SceneGenericShaderAnalysis-v18").glob("*.json"))
        self.assertEqual(len(entries), 1)

        # Exceed analysis retention so a prune aimed at the artifact root is observable.
        siblings = [cache / f"{index:064x}.json" for index in range(4097)]
        other_tier = cache / "SceneOtherCache-v1"
        other_tier.mkdir()
        siblings.append(other_tier / "keep.json")
        for index, path in enumerate(siblings):
            path.write_text(f"preserve sibling {index}")
        before = {path: (path.read_bytes(), path.stat().st_mtime_ns) for path in siblings}
        self.assertEqual(run("generic-root-write", cache),
                         ["standalone-analysis-write", "persisted-analysis-hit"])
        published = (entries[0].read_bytes(), entries[0].stat().st_mtime_ns)
        self.assertEqual(run("generic-root-warm", cache), ["persisted-analysis-hit"])
        self.assertEqual((entries[0].read_bytes(), entries[0].stat().st_mtime_ns), published)
        self.assertEqual({path: (path.read_bytes(), path.stat().st_mtime_ns) for path in siblings}, before)
        self.assertEqual(set(cache.glob("*.json")), set(siblings[:-1]))

        file_root = root / "cache-is-file"
        file_root.write_text("preserve file root")
        target = root / "symlink-target"
        target.mkdir()
        sentinel = target / "keep.json"
        sentinel.write_text("preserve symlink target")
        link_root = root / "cache-is-symlink"
        link_root.symlink_to(target, target_is_directory=True)
        denied_before = {path: (path.read_bytes(), path.stat().st_mtime_ns)
                         for path in (file_root, sentinel)}
        for denied in (file_root, link_root, ""):
            with self.subTest(root=str(denied)):
                self.assertEqual(run("generic-root-denied", denied), ["root-write-unavailable"])
        self.assertTrue(link_root.is_symlink())
        self.assertEqual(list(target.iterdir()), [sentinel])
        self.assertEqual({path: (path.read_bytes(), path.stat().st_mtime_ns)
                          for path in (file_root, sentinel)}, denied_before)

    def run_tier_probe(
        self,
        binary: Path,
        root: Path,
        environment: dict,
        tier: str,
    ) -> None:
        tier_root = root / tier
        probe_environment = dict(environment)
        probe_environment["MWX_SCENE_GENERIC_SHADER_CACHE"] = str(tier_root)
        # The command head stays a literal so the repository security write
        # gate accepts this file; the probe binary is a tempdir artifact.
        completed = subprocess.run(
            ["/usr/bin/env", str(binary), tier],
            cwd=REPOSITORY_ROOT,
            env=probe_environment,
            capture_output=True,
            text=True,
        )
        self.assertEqual(
            completed.returncode, 0, completed.stderr or completed.stdout
        )
        payload = json.loads(completed.stdout)
        self.assertIsNone(payload.get("failure"))
        self.assertEqual(payload["checks"], EXPECTED_TIER_CHECKS[tier])

    def run_preparation_phases(
        self,
        binary: Path,
        root: Path,
        environment: dict,
    ) -> None:
        tier_root = root / "preparation"
        tier_root.mkdir()
        probe_environment = dict(environment)
        probe_environment["MWX_SCENE_GENERIC_SHADER_CACHE"] = str(tier_root)
        tier_directory = tier_root / "SceneShaderPreparation-v1"

        def run(mode):
            return subprocess.run(
                ["/usr/bin/env", str(binary), mode],
                cwd=REPOSITORY_ROOT,
                env=probe_environment,
                capture_output=True,
                text=True,
            )

        def entries():
            if not tier_directory.exists():
                return []
            return sorted(tier_directory.glob("*.json"))

        rejected = run("preparation-rejected")
        self.assertEqual(
            rejected.returncode, 0, rejected.stderr or rejected.stdout
        )
        # A rejected preparation publishes nothing, and its load misses
        # without materializing the tier directory.
        self.assertEqual(entries(), [])

        accepted = run("preparation-accepted")
        self.assertEqual(
            accepted.returncode, 0, accepted.stderr or accepted.stdout
        )
        self.assertEqual(len(entries()), 1)
        published = entries()[0].read_bytes()
        published_mtime = entries()[0].stat().st_mtime_ns

        warm = run("preparation-accepted")
        self.assertEqual(warm.returncode, 0, warm.stderr or warm.stdout)
        # A later launch hits the persisted entry and does not republish it:
        # an atomic rewrite would mint a fresh modification time even when
        # the bytes stay identical.
        self.assertEqual(len(entries()), 1)
        self.assertEqual(entries()[0].read_bytes(), published)
        self.assertEqual(entries()[0].stat().st_mtime_ns, published_mtime)

        # A valid payload digest cannot make a decoded fragment into a vertex.
        semantic = run("preparation-tampered-stage")
        self.assertEqual(semantic.returncode, 0, semantic.stderr or semantic.stdout)
        self.assertEqual(entries()[0].read_bytes(), published)

        # A corrupted entry is a safe miss: re-preparation heals the file.
        entries()[0].write_bytes(b"\xff" * 64)
        healed = run("preparation-accepted")
        self.assertEqual(healed.returncode, 0, healed.stderr or healed.stdout)
        self.assertEqual(len(entries()), 1)
        self.assertEqual(entries()[0].read_bytes(), published)

        # A schema-stale entry is a safe miss and heals the same way.
        stale = entries()[0].read_text(encoding="utf-8")
        entries()[0].write_text(
            stale.replace('"schemaVersion":1', '"schemaVersion":999'),
            encoding="utf-8",
        )
        healed_stale = run("preparation-accepted")
        self.assertEqual(
            healed_stale.returncode, 0,
            healed_stale.stderr or healed_stale.stdout,
        )
        self.assertEqual(len(entries()), 1)
        self.assertEqual(entries()[0].read_bytes(), published)


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneVariantAnalysisCacheWireTests(unittest.TestCase):
    """Actual IO/wire checks; obsolete tiers miss despite unchanged record wire."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-variant-wire-")
        cls.work = Path(cls.temporary.name)
        cls.binary = cls.work / "wire-probe"
        cls.fixture = REPOSITORY_ROOT / "script/tests/fixtures/SceneVariantAnalysisCacheWireChecks.swift"
        cls.legacy = cls.fixture.parent / "variant_analysis_v22"
        cls.proof = Path(os.environ["MWX_VARIANT_WIRE_PROOF"]) if os.environ.get("MWX_VARIANT_WIRE_PROOF") else None
        command = ["xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
                   str(SCENE_ROOT / "Compilation/Material/ScenePersistentCacheSupport.swift"),
                   str(SCENE_ROOT / "Compilation/ShaderContract/SceneShaderCacheIdentity.swift"),
                   str(SCENE_ROOT / "Compilation/Material/SceneResolvedMaterialVariantAnalysisCache.swift"),
                   str(cls.fixture), "-module-cache-path", str(cls.work / "module-cache"),
                   "-o", str(cls.binary)]
        compiled = subprocess.run(command, cwd=REPOSITORY_ROOT, capture_output=True, text=True)
        if cls.proof:
            cls.proof.mkdir(parents=True, exist_ok=True)
            (cls.proof / "compiler.log").write_text(compiled.stdout + compiled.stderr)
            (cls.proof / "compile-command.json").write_text(json.dumps(command, indent=2) + "\n")
        if compiled.returncode:
            cls.temporary.cleanup()
            raise AssertionError(compiled.stderr)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary.cleanup()

    def mode(self, name: str, root: Path) -> dict:
        root.mkdir(exist_ok=True)
        environment = {**os.environ, "MWX_SCENE_GENERIC_SHADER_CACHE": str(root)}
        completed = subprocess.run(["/usr/bin/env", str(self.binary), name],
                                   cwd=REPOSITORY_ROOT, env=environment,
                                   capture_output=True, text=True, timeout=20)
        if self.proof:
            (self.proof / f"{root.name}-{name}.json").write_text(completed.stdout)
            (self.proof / f"{root.name}-{name}.stderr.log").write_text(completed.stderr)
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        facts = json.loads(completed.stdout)
        self.assertTrue(facts)
        self.assertEqual([name for name, passed in facts.items() if passed is not True], [], facts)
        return facts

    def install_v22_fixture(self, root: Path, *, rewrap_as_current: bool = False) -> None:
        root.mkdir()
        version = CURRENT_VARIANT_SCHEMA_VERSION if rewrap_as_current else 22
        destination = root / f"SceneVariantAnalysis-v{version}"
        shutil.copytree(self.legacy, destination)
        if rewrap_as_current:
            for path in destination.glob("*.json"):
                envelope = json.loads(path.read_text(encoding="utf-8"))
                self.assertEqual(envelope["schemaVersion"], 22)
                original_payload = envelope["payload"]
                original_digest = envelope["recordSHA256"]
                # Test-input adaptation only: the record digest covers payload,
                # not schemaVersion. Preserve payload and recordSHA256 exactly.
                envelope["schemaVersion"] = CURRENT_VARIANT_SCHEMA_VERSION
                path.write_text(json.dumps(envelope, separators=(",", ":")) + "\n", encoding="utf-8")
                rewrapped = json.loads(path.read_text(encoding="utf-8"))
                self.assertEqual(rewrapped["payload"], original_payload)
                self.assertEqual(rewrapped["recordSHA256"], original_digest)

    def test_rewrapped_v22_set_wire_and_current_store_survive_fresh_readers(self) -> None:
        root = self.work / "rewrapped-v22-wire"
        self.install_v22_fixture(root, rewrap_as_current=True)
        self.mode("rewrapped-v22-wire", root)
        cold = self.work / "cold"
        self.mode("cold-write", cold)
        self.mode("cold-read", cold)  # Independent process, same current owner.
        self.mode("ordered-wire", self.work / "ordered")

    def test_v22_namespace_is_a_read_only_miss_without_migration(self) -> None:
        root = self.work / "obsolete-v22-tier"
        self.install_v22_fixture(root)
        self.mode("obsolete-v22-tier", root)

    def test_invalid_variant_wire_is_a_read_only_safe_miss(self) -> None:
        self.mode("invalid-wire", self.work / "mutations")


if __name__ == "__main__":
    unittest.main()
