#!/usr/bin/env python3

"""R4 production resolved-material graph executor Metal gate."""

from __future__ import annotations

import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import tempfile
import unittest

from script.tests.scene_dependency_binding_test_support import (
    SCENE_DEPENDENCY_BINDING_SUPPORT,
)
from script.tests.scene_framebuffer_source_test_support import (
    framebuffer_source_material_declarations,
)
from script.tests.scene_harness_io import separate_graph_debug_output


CONTRACT_GATE = Path(__file__).with_name(
    "test_scene_resolved_material_graph_visual_failure_contract.py"
)
CONTRACT_FIXTURE = runpy.run_path(str(CONTRACT_GATE))
EFFECT_INGRESS_SOURCE = Path(__file__).resolve().parents[2] / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialEffectIngress.swift"
if EFFECT_INGRESS_SOURCE not in CONTRACT_FIXTURE["SWIFT_SOURCES"]:
    CONTRACT_FIXTURE["SWIFT_SOURCES"].append(EFFECT_INGRESS_SOURCE)
LIT_PIPELINE_SOURCE = Path(__file__).resolve().parents[2] / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Metal/SceneLitImageLayerPipeline.swift"
if LIT_PIPELINE_SOURCE not in CONTRACT_FIXTURE["SWIFT_SOURCES"]:
    CONTRACT_FIXTURE["SWIFT_SOURCES"].append(LIT_PIPELINE_SOURCE)
SCENE_METAL_SOURCES = [
    Path(__file__).resolve().parents[2] / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneImageLayer.metal",
    Path(__file__).resolve().parents[2] / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneLitImageLayer.metal",
]
PUBLICATION_FIXTURE = CONTRACT_FIXTURE["PUBLICATION_FIXTURE"]
compile_harness = CONTRACT_FIXTURE["compile_harness"]


def compile_lit_harness(
    support_text: str, harness_text: str, *,
    extra_swift_flags: tuple[str, ...] = (),
    extra_swift_sources: tuple[Path, ...] = (),
):
    """compile_harness plus a default.metallib built from the real image and
    lit capture shaders, so the harness binary can resolve the default
    library the lit pipeline reads its functions from."""
    with tempfile.TemporaryDirectory(
        prefix="mwx-resolved-material-lit-"
    ) as directory:
        root = Path(directory)
        support = root / "Support.swift"
        harness = root / "Harness.swift"
        binary = root / "resolved-material-graph-executor-test"
        support.write_text(support_text, encoding="utf-8")
        harness.write_text(harness_text, encoding="utf-8")
        air_paths: list[Path] = []
        for index, metal_source in enumerate(SCENE_METAL_SOURCES):
            air = root / f"scene-lit-{index}.air"
            metallization = subprocess.run(
                [
                    "xcrun",
                    "--sdk",
                    "macosx",
                    "metal",
                    "-c",
                    str(metal_source),
                    "-o",
                    str(air),
                ],
                capture_output=True,
                text=True,
            )
            if metallization.returncode != 0:
                return metallization, None
            air_paths.append(air)
        metallib = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "metallib",
                *(str(path) for path in air_paths),
                "-o",
                str(root / "default.metallib"),
            ],
            capture_output=True,
            text=True,
        )
        if metallib.returncode != 0:
            return metallib, None
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
        scene_cache = root / "scene-cache"
        scene_cache.mkdir()
        environment["MWX_SCENE_GENERIC_SHADER_CACHE"] = str(scene_cache)
        environment["MWX_SCENE_PIPELINE_BINARY_ARCHIVE"] = str(scene_cache)
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                "-parse-as-library",
                *CONTRACT_FIXTURE["GRAPH_SWIFT_FLAGS"],
                *extra_swift_flags,
                str(support),
                *(str(path) for path in dict.fromkeys([
                    *CONTRACT_FIXTURE["SWIFT_SOURCES"], *extra_swift_sources,
                ])),
                str(harness),
                "-framework",
                "Metal",
                "-framework",
                "CoreGraphics",
                "-framework",
                "ImageIO",
                "-module-cache-path",
                str(root / "module-cache"),
                "-o",
                str(binary),
            ],
            cwd=CONTRACT_FIXTURE["REPOSITORY_ROOT"],
            env=environment,
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            return compilation, None
        completed = subprocess.run(
            [str(binary)],
            cwd=CONTRACT_FIXTURE["REPOSITORY_ROOT"],
            env=environment,
            capture_output=True,
            text=True,
        )
        return compilation, separate_graph_debug_output(completed)


FIXTURE_ROOT = Path(__file__).with_name("fixtures")
SUPPORT = (
    PUBLICATION_FIXTURE["SUPPORT"]
    + (FIXTURE_ROOT / "SceneGraphExecutorRuntimeSupport.swift").read_text(encoding="utf-8").replace(
        "/* SOURCE_MATERIAL_DECLARATIONS */", framebuffer_source_material_declarations()
    )
    + SCENE_DEPENDENCY_BINDING_SUPPORT
)
HARNESS_SUPPORT_SOURCE = "".join(
    (FIXTURE_ROOT / name).read_text(encoding="utf-8")
    for name in (
        "SceneGraphExecutorGraphInputs.swift",
        "SceneGraphExecutorShaderInputs.swift",
        "SceneGraphExecutorResourceSupport.swift",
        "SceneGraphExecutorLitCaptureScenarios.swift",
        "SceneGraphExecutorReadbackSupport.swift",
        "SceneGraphExecutorHistoryFunctionScenarios.swift",
        "SceneGraphExecutorCapabilitySupport.swift",
        "SceneGraphExecutorContinuityScenarios.swift",
    )
)
EXECUTOR_SCENARIOS_SOURCE = "".join(
    (FIXTURE_ROOT / name).read_text(encoding="utf-8")
    for name in (
        "SceneGraphExecutorActivationCases.swift",
        "SceneGraphExecutorCopyHistoryCases.swift",
        "SceneGraphExecutorNamedDependencyCases.swift",
        "SceneGraphExecutorStageChainCases.swift",
        "SceneGraphExecutorVisualFailureCases.swift",
        "SceneGraphExecutorOptionalProviderCases.swift",
        "SceneGraphExecutorMultiNodeCases.swift",
        "SceneGraphExecutorFeedbackCases.swift",
        "SceneGraphExecutorTypedDataCases.swift",
        "SceneGraphExecutorSamplerFramebufferCases.swift",
        "SceneGraphExecutorCompositionCases.swift",
        "SceneGraphExecutorOrdinaryFrameCacheCases.swift",
        "SceneGraphExecutorFinalAdmissionCases.swift",
        "SceneGraphExecutorMainHarness.swift",
    )
)
HARNESS = HARNESS_SUPPORT_SOURCE + EXECUTOR_SCENARIOS_SOURCE + (
    FIXTURE_ROOT / "SceneGraphExecutorDefaultHarness.swift"
).read_text(encoding="utf-8")


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneResolvedMaterialGraphExecutorTests(unittest.TestCase):
    def test_signal_raw_passthrough_crosses_effects_and_keeps_actual_fallback(self) -> None:
        harness = HARNESS_SUPPORT_SOURCE + (FIXTURE_ROOT / "SceneGraphExecutorRawSignalHarness.swift").read_text(encoding="utf-8")
        compilation, completed = compile_lit_harness(SUPPORT, harness)
        self.assertEqual(compilation.returncode, 0, compilation.stderr)
        self.assertIsNotNone(completed)
        assert completed is not None
        self.assertEqual(completed.returncode, 0, completed.stderr)
        payload = json.loads(completed.stdout)
        if not payload["metalAvailable"]:
            self.skipTest("Metal is unavailable")
        report = payload["rawSignal"]
        self.assertNotIn("failure", report, report)
        self.assertEqual(len(report["frames"]), 2, report)
        for row in report["frames"]:
            for assertion, passed in row.items():
                if isinstance(passed, bool) and assertion != "fallback":
                    self.assertTrue(passed, (assertion, row))

    def test_typed_scalar_and_pair_producers_feed_color_consumers_without_association(self) -> None:
        harness = HARNESS_SUPPORT_SOURCE + (FIXTURE_ROOT / "SceneGraphExecutorTypedDataHarness.swift").read_text(encoding="utf-8")
        compilation, completed = compile_lit_harness(SUPPORT, harness)
        self.assertEqual(compilation.returncode, 0, compilation.stderr)
        self.assertIsNotNone(completed)
        assert completed is not None
        self.assertEqual(completed.returncode, 0, completed.stderr)
        payload = json.loads(completed.stdout)
        if not payload["metalAvailable"]:
            self.skipTest("Metal is unavailable")
        self.assertEqual(set(payload["reports"]), {"r8", "rg88", "r16f", "rg1616f"})
        for format_name, report in payload["reports"].items():
            self.assertNotIn("failure", report, (format_name, report))
            for assertion, passed in report.items():
                if isinstance(passed, bool):
                    self.assertTrue(passed, (format_name, assertion, report))

    def test_regular_color_channel_reads_use_actual_straight_or_pma_input(self) -> None:
        harness = HARNESS_SUPPORT_SOURCE + (FIXTURE_ROOT / "SceneGraphExecutorColorChannelHarness.swift").read_text(encoding="utf-8")
        compilation, completed = compile_lit_harness(SUPPORT, harness)
        self.assertEqual(compilation.returncode, 0, compilation.stderr)
        self.assertIsNotNone(completed)
        assert completed is not None
        self.assertEqual(completed.returncode, 0, completed.stderr)
        payload = json.loads(completed.stdout)
        if not payload["metalAvailable"]:
            self.skipTest("Metal is unavailable")
        self.assertEqual(set(payload["channels"]), {"r", "g", "rg"})
        for probe, report in payload["channels"].items():
            self.assertNotIn("failure", report, (probe, report))
            self.assertTrue(report["oneWorkingPair"], report)
            self.assertEqual(len(report["frames"]), 4, report)
            for row in report["frames"]:
                for name, passed in row.items():
                    if isinstance(passed, bool) and name != "fallback":
                        self.assertTrue(passed, (probe, name, row))

    def test_generated_straight_color_survives_previous_effect_and_pma_fallback(self) -> None:
        harness = HARNESS_SUPPORT_SOURCE + (FIXTURE_ROOT / "SceneGraphExecutorStraightContinuityHarness.swift").read_text(encoding="utf-8")
        compilation, completed = compile_lit_harness(SUPPORT, harness)
        self.assertEqual(compilation.returncode, 0, compilation.stderr)
        self.assertIsNotNone(completed)
        assert completed is not None
        self.assertEqual(completed.returncode, 0, completed.stderr)
        payload = json.loads(completed.stdout)
        if not payload["metalAvailable"]:
            self.skipTest("Metal is unavailable")
        report = payload["continuity"]
        self.assertNotIn("failure", report, report)
        self.assertTrue(report["oneWorkingPair"], report)
        self.assertEqual(len(report["frames"]), 4, report)
        self.assertEqual([row["alpha"] for row in report["frames"]], [0, 0.5, 1, 0.5])
        for row in report["frames"]:
            for name, passed in row.items():
                if isinstance(passed, bool) and name != "fallback":
                    self.assertTrue(passed, (name, row))

    def test_same_layer_names_consume_latest_effect_output_without_snapshot(self) -> None:
        harness = HARNESS_SUPPORT_SOURCE + (FIXTURE_ROOT / "SceneGraphExecutorSelfCompositeHarness.swift").read_text(encoding="utf-8")
        compilation, completed = compile_lit_harness(SUPPORT, harness)
        self.assertEqual(compilation.returncode, 0, compilation.stderr)
        self.assertIsNotNone(completed)
        assert completed is not None
        self.assertEqual(completed.returncode, 0, completed.stderr)
        payload = json.loads(completed.stdout)
        if not payload["metalAvailable"]:
            self.skipTest("Metal is unavailable")
        self.assertEqual([key for key, passed in payload["results"].items() if not passed], [], payload)

    def test_production_executor_preflights_and_executes_atomic_graph(self) -> None:
        compilation, completed = compile_lit_harness(SUPPORT, HARNESS)
        self.assertEqual(compilation.returncode, 0, compilation.stderr)
        self.assertIsNotNone(completed)
        assert completed is not None
        self.assertEqual(completed.returncode, 0, completed.stderr)

        payload = json.loads(completed.stdout)
        if not payload["metalAvailable"]:
            self.skipTest("Metal is unavailable")
        self.assertEqual(
            [
                name
                for name, passed in payload["results"].items()
                if not passed
            ],
            [],
            payload,
        )


if __name__ == "__main__":
    unittest.main()
