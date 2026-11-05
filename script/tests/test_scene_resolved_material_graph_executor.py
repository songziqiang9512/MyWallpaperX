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
for relative in (
    "Compilation/Material/SceneEffectDefinition.swift",
    "Compilation/Graph/SceneAuthoredEffectRenderPlanner.swift",
    "Compilation/Graph/SceneAuthoredEffectRenderPlanner+Resolution.swift",
    "Compilation/Graph/SceneGraphConditionSchemaEvidenceCompiler.swift",
):
    source = CONTRACT_FIXTURE["SCENE_ROOT"] / relative
    if source not in CONTRACT_FIXTURE["SWIFT_SOURCES"]:
        CONTRACT_FIXTURE["SWIFT_SOURCES"].append(source)
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
    runtime_evidence: Path | None = None,
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
        if runtime_evidence is not None:
            (runtime_evidence / "runtime.stdout.log").write_bytes(completed.stdout.encode("utf-8"))
            (runtime_evidence / "runtime.stderr.log").write_bytes(completed.stderr.encode("utf-8"))
        return compilation, separate_graph_debug_output(completed)


FIXTURE_ROOT = Path(__file__).with_name("fixtures")
DEPENDENCY_ROOT = Path(__file__).resolve().parents[2] / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Dependencies"
DEPENDENCY_MODEL = (DEPENDENCY_ROOT / "SceneDependencyRenderPlan.swift").read_text()
DEPENDENCY_MODEL += (DEPENDENCY_ROOT / "SceneDependencyRenderPlan+StaticModel.swift").read_text().split(
    "extension SceneDependencyRenderPlan {", 1)[0]
SUPPORT = (
    PUBLICATION_FIXTURE["SUPPORT"]
    + (FIXTURE_ROOT / "SceneGraphExecutorRuntimeSupport.swift").read_text(encoding="utf-8").replace(
        "/* SOURCE_MATERIAL_DECLARATIONS */", framebuffer_source_material_declarations()
    ).replace("/* DEPENDENCY_PLAN_MODEL */", DEPENDENCY_MODEL)
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
    def test_property_fallback_is_target_local_through_capability_uniforms_and_metal(self) -> None:
        from . import test_scene_property_binding_program as property_inputs

        harness = HARNESS_SUPPORT_SOURCE + (
            FIXTURE_ROOT / "SceneGraphExecutorPropertyFallbackHarness.swift"
        ).read_text(encoding="utf-8")
        evidence = None
        if parent := os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE"):
            Path(parent).mkdir(parents=True, exist_ok=True)
            evidence = Path(tempfile.mkdtemp(prefix="property-target-fallback-", dir=parent))
            print(f"property target fallback evidence: {evidence}", flush=True)
        compilation, completed = compile_lit_harness(
            SUPPORT, harness, extra_swift_sources=tuple(property_inputs.SWIFT_SOURCES), runtime_evidence=evidence)
        self.assertEqual(compilation.returncode, 0, compilation.stderr)
        self.assertIsNotNone(completed)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        result = json.loads(completed.stdout)
        if not result["metalAvailable"]:
            self.skipTest("Metal is unavailable")
        rows = {row["case"]: row for row in result["rows"]}
        self.assertEqual(len(rows), 19)
        positive = {"fallback": ([51, 102, 153, 255], [.2, .4, .6, 0]),
                    "renamed": ([51, 102, 153, 255], [.2, .4, .6, 0]),
                    "inactive": ([24, 40, 56, 255], [.2, .4, .6, 0]),
                    "liveColor": ([204, 51, 102, 255], [.8, .2, .4, 0]),
                    "liveColorChanged": ([102, 153, 204, 255], [.4, .6, .8, 0])}
        cold_reasons = {name: "material-dynamic-uniform-producer-unavailable" for name in (
            "writerKey", "writerType", "writerMultiple", "noFallbackDefinition", "wrapper", "timelineMissing")}
        cold_reasons.update(multiContributor="material-generic-owner-revoked",
                            script="material-generic-owner-revoked")
        direct_uniform_reasons = {"multiContributor": "material-dynamic-uniform-contributor-policy",
                                  "script": "material-dynamic-uniform-script-attachment-unproven"}
        frame_failures = {"snapshotMissing", "source", "abi", "bits", "snapshotType"}
        self.assertEqual(set(rows), set(positive) | set(cold_reasons) | frame_failures | {"declarationTarget"})
        for name, row in rows.items():
            with self.subTest(case=name):
                self.assertEqual(row["sameKeyOtherProducers"], 2, row)
                self.assertEqual(row["rebuildKeys"], [], row)
                if name == "fallback":
                    self.assertEqual(row["comboRebuildKeys"], ["shared-toggle"], row)
                    self.assertEqual(row["comboBoolProducerCount"], 2, row)
                    self.assertEqual(row["comboColorInstructions"], 0, row)
                    self.assertTrue(row["comboHasAuthoredDefinition"], row)
                if name in direct_uniform_reasons:
                    self.assertEqual(row["directUniformReason"], direct_uniform_reasons[name], row)
                if name == "declarationTarget":
                    self.assertEqual(row["capability"], "rejected", row)
                    self.assertTrue(any("dynamic-uniform-unavailable" in line for line in row["catalogReports"]), row)
                    continue
                self.assertNotIn("executionFailure", row)
                self.assertTrue(row["completed"], row)
                self.assertTrue(row["peerHasBoolPolicy"], row)
                self.assertTrue(row["allPixelsUniform"], row)
                self.assertEqual(len(row["pixelsRGBA"]), 2, row)
                expected_first = positive[name][0] if name in positive else [24, 40, 56, 255]
                for actual, expected in zip(row["pixelsRGBA"][0], expected_first, strict=True):
                    self.assertAlmostEqual(actual, expected, delta=1, msg=str(row))
                self.assertEqual(row["pixelsRGBA"][1], [24, 40, 56, 255] if name == "inactive" else [0, 255, 0, 255], row)
                if name in cold_reasons:
                    self.assertEqual(row["capability"], "visual-failure", row)
                    self.assertEqual(row["coldReason"], cold_reasons[name], row)
                    self.assertEqual(row["frameBinding"], "not-entered", row)
                    self.assertEqual(row["stageFailures"], [cold_reasons[name], ""], row)
                elif name in frame_failures:
                    self.assertEqual(row["capability"], "resolved", row)
                    self.assertEqual(row["frameBinding"], "uniform/dynamicUniformBindingInvalid", row)
                    self.assertEqual(row["stageFailures"], ["material-finalizer-dynamic-uniform-binding", ""], row)
                else:
                    self.assertEqual(row["capability"], "resolved", row)
                    self.assertTrue(row["firstHasBoolPolicy"], row)
                    self.assertEqual(row["frameBinding"], "success", row)
                    source = "userProperty" if name.startswith("liveColor") else "authored"
                    self.assertEqual(row["snapshotSource"], source, row)
                    self.assertEqual(row["uniformSource"], source, row)
                    self.assertEqual(row["colorInstructions"], int(name.startswith("liveColor")), row)
                    self.assertEqual(len(row["uniformValues"]), 4, row)
                    for actual, expected in zip(row["uniformValues"], positive[name][1], strict=True):
                        self.assertAlmostEqual(actual, expected, places=6, msg=str(row))
                    self.assertEqual(row["stageFailures"], ["", ""], row)
                    reason = "effect-activation-visibility-disabled" if name == "inactive" else ""
                    self.assertEqual(row["activationBypasses"], [reason, reason], row)

    def test_named_inputs_each_contribute_through_prepared_slot_vectors(self) -> None:
        harness = HARNESS_SUPPORT_SOURCE + (FIXTURE_ROOT / "SceneGraphExecutorNamedDependencyCases.swift").read_text() + r'''
@main private enum NamedVectorHarness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            print("{\"metalAvailable\":false}"); return
        }
        let result: [String: Any] = ["metalAvailable": true,
            "rows": runNamedInputVectorCases(device: device, queue: queue,
                sourcePipeline: makeSourcePipeline(device))]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result,
            options: [.sortedKeys]), as: UTF8.self))
    }
}
'''
        compilation, completed = compile_lit_harness(SUPPORT, harness)
        self.assertEqual(compilation.returncode, 0, compilation.stderr)
        self.assertIsNotNone(completed)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        result = json.loads(completed.stdout)
        if not result["metalAvailable"]:
            self.skipTest("Metal is unavailable")
        self.assertEqual(len(result["rows"]), 23)
        expected = {"both": [148, 64, 28, 255], "A0": [4, 40, 16, 255],
                    "B0": [144, 24, 12, 255], "swap": [60, 128, 52, 255]}
        for row in result["rows"]:
            topology = row["topology"]
            with self.subTest(topology=topology, control=row["control"]):
                self.assertTrue(row["prepared"], row)
                self.assertTrue(row["completed"], row)
                self.assertEqual(row["peer"], [0, 255, 0, 255])
                pixel = expected[row["control"]]
                if topology in ("unused", "missingSuffix"):
                    pixel = [192, 32, 16, 255]
                elif topology in ("missing", "metadataMissing"):
                    pixel = [24, 40, 56, 255]
                elif topology == "metadata":
                    # Physical/mapped extent4x2; rotation/translation are zero.
                    pixel = [128, 64, 64, 255]
                elif topology == "background":
                    pixel = [108, 68, 72, 255]  # .5A + .25B + .25(32,48,192).
                for actual, value in zip(row["pixel"], pixel, strict=True):
                    self.assertAlmostEqual(actual, value, delta=1, msg=str(row))
                providers = [901, 902]
                if topology == "sameProvider" or topology == "unused":
                    providers = [901]
                elif topology in ("metadata", "metadataMissing"):
                    providers = [902]
                elif topology == "renamed":
                    providers = [1901, 1902]
                self.assertEqual(row["providers"], providers)
                self.assertEqual(row["backgroundRequired"], topology == "background")
                if topology not in ("missing", "missingSuffix", "metadataMissing"):
                    self.assertFalse(any(row["failures"]), row)
                if topology == "sameProvider":
                    self.assertEqual(row["bindings"], ["z-first:0:2=901", "z-first:0:5=901"])
                elif topology == "passes":
                    self.assertEqual(row["bindings"], ["z-first:0:2=901", "z-first:1:5=902"])
                elif topology == "cross":
                    self.assertEqual(row["bindings"], ["z-first:0:2=901", "a-second:0:5=902"])
                elif topology == "unused":
                    self.assertEqual(row["bindings"], ["z-first:0:2=901"])
                elif topology in ("metadata", "metadataMissing"):
                    self.assertEqual(row["bindings"], ["z-first:0:5=902"])

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
