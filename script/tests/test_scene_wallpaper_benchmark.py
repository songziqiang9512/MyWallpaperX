#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from collections import defaultdict
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))
DEBUG_RUNNER_SOURCE = (
    SCRIPT_DIR.parent / "MyWallpaperX/App/DebugScenePlaybackRunner.swift"
)

import scene_wallpaper_benchmark as benchmark
import scene_preview_visual_evidence as visual
import generate_scene_full_matrix as matrix_generator


def static_effect_disposition(
    *,
    records: list[dict[str, object]] | None = None,
    groups: list[dict[str, object]] | None = None,
    validation_failures: list[str] | None = None,
) -> dict[str, object]:
    return {
        "has_evidence": True,
        "schema_version": 1,
        "records": records or [],
        "groups": groups or [],
        "validation_failures": validation_failures or [],
    }


def shader_stage(identity: str, kind: str, source: str) -> dict[str, object]:
    suffix = "vert" if kind == "vertex" else "frag"
    return {
        "kind": kind,
        "relativePath": f"shaders/{identity}.{suffix}",
        "source": source,
        "rawSHA256": hashlib.sha256(source.encode("utf-8")).hexdigest(),
        "includes": [],
        "annotations": [],
        "declarations": [],
    }


def runtime_evidence(runtime_input: dict[str, object]) -> dict[str, object]:
    return {
        "schemaVersion": 1,
        "sourceEntryPath": "scene.json",
        "runtimeInput": runtime_input,
    }


def effect_runtime_disposition_preview() -> str:
    coverage = (
        "inactive=1,complete=2,terminal-inline-prefix=0,"
        "terminal-inline-suffix=1,isolated-accepted=0,isolated-omitted=0,"
        "prefix-accepted=0,prefix-omitted=0,rejected-missing-graph=0,"
        "rejected-ambiguous-graph=0,rejected-chain=8,"
        "rejected-graph-mismatch=0,rejected-invariant=0"
    )
    kind_counts = (
        "inactive=1,strict-dedicated=1,strict-generic=1,"
        "strict-inline-suffix=1,omitted-by-strict-chain=1,"
        "legacy-exact-inline=1,legacy-exact-offscreen=1,"
        "legacy-structural-member=0,"
        "legacy-coalesced-inline=1,legacy-coalesced-offscreen=0,"
        "legacy-shadowed=1,"
        "route-only-member=1,composite-refused=1,unsupported=1,"
        "unattributed=0"
    )
    return "\n".join([
        "authoredEffectGraphStageCount: 2",
        "authoredEffectStageDescriptorCount: 12",
        "authoredEffectStageParsedCount: 12",
        "authoredEffectStageActivityCounts: author-disabled=1,layer-hidden=0,active=11",
        "authoredEffectStageStrictAdmissionCounts: inactive=1,admitted-dedicated=1,admitted-generic=1,not-admitted=9",
        f"authoredEffectStageCoverageCounts: {coverage}",
        "authoredEffectStageDescriptorIdentityConserved: true",
        "authoredEffectStageActivityConserved: true",
        "authoredEffectStageInactiveAdmissionConserved: true",
        "authoredEffectStageActiveAdmissionConserved: true",
        "authoredEffectStageStrictIdentityConserved: true",
        "authoredEffectStageAdmission: layer=1 effect=0 descriptor=1%23effect%230 activity=author-disabled strict=inactive coverage=inactive backend=- profile=- reason=- path=effects/disabled/effect.json",
        "authoredEffectStageAdmission: layer=2 effect=0 descriptor=2%23effect%230 activity=active strict=admitted-dedicated coverage=complete backend=opacity profile=- reason=- path=effects/opacity/effect.json",
        "authoredEffectStageAdmission: layer=2 effect=1 descriptor=2%23effect%231 activity=active strict=admitted-generic coverage=complete backend=authored-shader profile=generic-fragment reason=- path=effects/generic/effect.json",
        "authoredEffectStageAdmission: layer=2 effect=2 descriptor=2%23effect%232 activity=active strict=not-admitted coverage=terminal-inline-suffix backend=- profile=- reason=terminal-inline-suffix path=effects/iris/effect.json",
        "authoredEffectStageAdmission: layer=2 effect=3 descriptor=2%23effect%233 activity=active strict=not-admitted coverage=rejected-chain backend=- profile=- reason=unsupported-stage path=effects/omitted/effect.json",
        "authoredEffectStageAdmission: layer=3 effect=0 descriptor=3%23effect%230 activity=active strict=not-admitted coverage=rejected-chain backend=- profile=- reason=unsupported-stage path=effects/chromatic/effect.json",
        "authoredEffectStageAdmission: layer=3 effect=1 descriptor=3%23effect%231 activity=active strict=not-admitted coverage=rejected-chain backend=- profile=- reason=unsupported-stage path=effects/chromatic/effect.json",
        "authoredEffectStageAdmission: layer=4 effect=0 descriptor=4%23effect%230 activity=active strict=not-admitted coverage=rejected-chain backend=- profile=- reason=unsupported-stage path=effects/capture/effect.json",
        "authoredEffectStageAdmission: layer=5 effect=0 descriptor=5%23effect%230 activity=active strict=not-admitted coverage=rejected-chain backend=- profile=- reason=unsupported-stage path=effects/bloom/effect.json",
        "authoredEffectStageAdmission: layer=5 effect=1 descriptor=5%23effect%231 activity=active strict=not-admitted coverage=rejected-chain backend=- profile=- reason=unsupported-stage path=effects/blur/effect.json",
        "authoredEffectStageAdmission: layer=6 effect=0 descriptor=6%23effect%230 activity=active strict=not-admitted coverage=rejected-chain backend=- profile=- reason=unsupported-stage path=effects/composite/effect.json",
        "authoredEffectStageAdmission: layer=7 effect=0 descriptor=7%23effect%230 activity=active strict=not-admitted coverage=rejected-chain backend=- profile=- reason=unsupported-stage path=effects/unknown/effect.json",
        "effectStageRuntimeDispositionSchema: 1",
        "effectStageRuntimeRouteScope: effect-induced-static",
        "effectStageRuntimeDispositionCount: 12",
        f"effectStageRuntimeDispositionKindCounts: {kind_counts}",
        "effectStageRuntimeDispositionAttributionCounts: exact-key=8,layer-aggregate=2,none=2",
        "effectStageRuntimeDispositionRoleCounts: owner=5,aggregate-contributor=1,member=5,none=1",
        "effectStaticRouteGroupCount: 7",
        "effectStaticRouteGroupKindCounts: inactive=1,direct=2,authored=1,legacy-offscreen=1,offscreen-passthrough=1,composite-refused=1",
        "effectStageRuntimeDescriptorIdentityConserved: true",
        "effectStageRuntimeGroupIdentityConserved: true",
        "effectStageRuntimeStrictIdentityConserved: true",
        "effectStaticRouteGroup: layer=1 scope=effect-induced-static kind=inactive effects=0 owners=0 aggregate=0 reason=no-active-effect",
        "effectStaticRouteGroup: layer=2 scope=effect-induced-static kind=authored effects=4 owners=3 aggregate=0 reason=-",
        "effectStaticRouteGroup: layer=3 scope=effect-induced-static kind=direct effects=2 owners=1 aggregate=1 reason=-",
        "effectStaticRouteGroup: layer=4 scope=effect-induced-static kind=offscreen-passthrough effects=1 owners=0 aggregate=0 reason=no-implemented-offscreen-stage",
        "effectStaticRouteGroup: layer=5 scope=effect-induced-static kind=legacy-offscreen effects=2 owners=1 aggregate=0 reason=-",
        "effectStaticRouteGroup: layer=6 scope=effect-induced-static kind=composite-refused effects=1 owners=0 aggregate=0 reason=legacy-composite-refused",
        "effectStaticRouteGroup: layer=7 scope=effect-induced-static kind=direct effects=1 owners=0 aggregate=0 reason=-",
        "effectStageRuntimeDisposition: layer=1 effect=0 descriptor=1%23effect%230 kind=inactive attribution=none family=- group=- role=none reason=author-disabled path=effects/disabled/effect.json",
        "effectStageRuntimeDisposition: layer=2 effect=0 descriptor=2%23effect%230 kind=strict-dedicated attribution=exact-key family=opacity group=2 role=owner reason=- path=effects/opacity/effect.json",
        "effectStageRuntimeDisposition: layer=2 effect=1 descriptor=2%23effect%231 kind=strict-generic attribution=exact-key family=generic-fragment group=2 role=owner reason=- path=effects/generic/effect.json",
        "effectStageRuntimeDisposition: layer=2 effect=2 descriptor=2%23effect%232 kind=strict-inline-suffix attribution=exact-key family=iris-inline group=2 role=owner reason=terminal-inline-suffix path=effects/iris/effect.json",
        "effectStageRuntimeDisposition: layer=2 effect=3 descriptor=2%23effect%233 kind=omitted-by-strict-chain attribution=exact-key family=- group=2 role=member reason=unsupported-stage path=effects/omitted/effect.json",
        "effectStageRuntimeDisposition: layer=3 effect=0 descriptor=3%23effect%230 kind=legacy-exact-inline attribution=exact-key family=chromatic-aberration group=3 role=owner reason=- path=effects/chromatic/effect.json",
        "effectStageRuntimeDisposition: layer=3 effect=1 descriptor=3%23effect%231 kind=legacy-coalesced-inline attribution=layer-aggregate family=chromatic-aberration group=3 role=aggregate-contributor reason=multiple-instances-coalesced-to-one-flag path=effects/chromatic/effect.json",
        "effectStageRuntimeDisposition: layer=4 effect=0 descriptor=4%23effect%230 kind=route-only-member attribution=exact-key family=declared-multipass group=4 role=member reason=capture-or-neutral-copy-only path=effects/capture/effect.json",
        "effectStageRuntimeDisposition: layer=5 effect=0 descriptor=5%23effect%230 kind=legacy-exact-offscreen attribution=exact-key family=bloom group=5 role=owner reason=- path=effects/bloom/effect.json",
        "effectStageRuntimeDisposition: layer=5 effect=1 descriptor=5%23effect%231 kind=legacy-shadowed attribution=exact-key family=blur group=5 role=member reason=shadowed-by-legacy-precedence path=effects/blur/effect.json",
        "effectStageRuntimeDisposition: layer=6 effect=0 descriptor=6%23effect%230 kind=composite-refused attribution=layer-aggregate family=unsupported-composite group=6 role=member reason=waterflow-waterripple-perspective-opacity path=effects/composite/effect.json",
        "effectStageRuntimeDisposition: layer=7 effect=0 descriptor=7%23effect%230 kind=unsupported attribution=none family=unknown group=7 role=member reason=no-legacy-visual-route path=effects/unknown/effect.json",
    ])


def effect_cpu_event(
    *,
    frame: int,
    origin: str,
    subject: str,
    layer: int,
    effect: int | None,
    descriptor: str | None,
    family: str,
    backend: str,
    outcome: str = "encoded-output",
    reason: str = "-",
) -> dict[str, object]:
    effect_token = "-" if effect is None else str(effect)
    descriptor_token = "-" if descriptor is None else descriptor
    return {
        "line": (
            f"schema=1 axis=effect-cpu-invocation frame={frame} origin={origin} "
            f"subject={subject} layer={layer} effect={effect_token} "
            f"descriptor={descriptor_token} family={family} backend={backend} "
            f"outcome={outcome} reason={reason}"
        ),
        "canonical": (
            f"effect|origin={origin}|subject={subject}|layer={layer}"
            f"|effect={effect_token}|descriptor={descriptor_token}"
            f"|family={family}|backend={backend}|outcome={outcome}"
            f"|reason={reason}"
        ),
        "subject": (
            origin,
            subject,
            layer,
            effect,
            descriptor_token,
            family,
            backend,
        ),
        "outcome": outcome,
    }


def effect_route_event(
    *,
    frame: int,
    origin: str,
    layer: int,
    operation: str,
    outcome: str = "encoded",
    reason: str = "-",
) -> dict[str, object]:
    return {
        "line": (
            f"schema=1 axis=effect-route-operation frame={frame} "
            f"origin={origin} layer={layer} operation={operation} "
            f"outcome={outcome} reason={reason}"
        ),
        "canonical": (
            f"route|origin={origin}|layer={layer}|operation={operation}"
            f"|outcome={outcome}|reason={reason}"
        ),
        "subject": (origin, layer, operation),
        "outcome": outcome,
    }


def effect_execution_log(
    frame: int,
    cpu_events: list[dict[str, object]],
    route_events: list[dict[str, object]],
    *,
    status: str = "completed",
    count_overrides: dict[str, int] | None = None,
    cohort_override: str | None = None,
) -> str:
    attempted = {event["subject"] for event in cpu_events}
    returned = {
        event["subject"] for event in cpu_events
        if event["outcome"] == "encoded-output"
    }
    failed = {
        event["subject"] for event in cpu_events
        if event["outcome"] == "failed"
    }
    routes = {event["subject"] for event in route_events}
    counts = {
        "attempted": len(attempted),
        "returned": len(returned),
        "failed": len(failed),
        "routes": len(routes),
    }
    counts.update(count_overrides or {})
    cohort = cohort_override or hashlib.sha256("\n".join(sorted({
        str(event["canonical"]) for event in cpu_events + route_events
    })).encode("utf-8")).hexdigest()
    frame_line = (
        f"schema=1 axis=scene-frame-command-buffer frame={frame} "
        f"attemptedEffects={counts['attempted']} "
        f"returnedOutputs={counts['returned']} "
        f"failedInvocations={counts['failed']} "
        f"routeOperations={counts['routes']} cohortSHA256={cohort} "
        f"status={status}"
    )
    return "\n".join([
        *(str(event["line"]) for event in cpu_events),
        *(str(event["line"]) for event in route_events),
        frame_line,
    ])


def graph_execution_observation(
    *,
    frame: int,
    layer: int = 68,
    transaction: str,
    trigger: str,
    authored: int = 2,
    material: int = 1,
    copy: int = 1,
    swap: int = 0,
    compose: int = 1,
    rejected: int = 0,
    consumed: bool = False,
    publish: bool = True,
    outcome: str = "succeeded",
    gpu_completion: str = "completed",
) -> str:
    final_output = f"output-{transaction}" if publish else "-"
    final_physical = f"physical-{transaction}" if publish else "-"
    final_publication = f"publication-{transaction}" if publish else "-"
    publication_generation = frame if publish else 0
    return (
        "MWX DEBUG SCENE: schema=1 axis=graph-execution "
        f"frame={frame} layer={layer} trigger={trigger} transaction={transaction} "
        f"authoredNodes={authored} materialNodes={material} "
        f"copyNodes={copy} swapNodes={swap} composeNodes={compose} "
        f"rejectedNodes={rejected} finalOutput={final_output} "
        f"physicalIdentity={final_physical} "
        f"publication={final_publication} "
        f"publicationGeneration={publication_generation} "
        f"compositorConsumed={'true' if consumed else 'false'} "
        f"outcome={outcome} gpuCompletion={gpu_completion}"
    )


def resolved_graph_exact_evidence(
    layer_ids: list[int],
    *,
    backends: dict[int, str] | None = None,
    outcomes: dict[int, str] | None = None,
    omitted_layer_ids: set[int] | None = None,
) -> tuple[dict[str, object], dict[str, object]]:
    backends = backends or {}
    outcomes = outcomes or {}
    omitted_layer_ids = omitted_layer_ids or set()
    records = []
    groups = []
    events = []
    for layer_id in layer_ids:
        descriptor_id = f"{layer_id}#effect#0"
        records.append({
            "layer_id": layer_id,
            "effect_index": 0,
            "descriptor_id": descriptor_id,
            "definition_path": f"effects/{layer_id}/effect.json",
            "family": "generic-fragment",
            "kind": "strict-generic",
        })
        groups.append({"layer_id": layer_id, "kind": "authored"})
        if layer_id not in omitted_layer_ids:
            events.append(effect_cpu_event(
                frame=90,
                origin="resolved-material-graph",
                subject="effect",
                layer=layer_id,
                effect=0,
                descriptor=f"{layer_id}%23effect%230",
                family="generic-fragment",
                backend=backends.get(
                    layer_id,
                    benchmark.RESOLVED_MATERIAL_GRAPH_BACKEND,
                ),
                outcome=outcomes.get(layer_id, "encoded-output"),
                reason=(
                    "-" if outcomes.get(layer_id, "encoded-output")
                    == "encoded-output" else "fixture-failure"
                ),
            ))
    disposition = static_effect_disposition(records=records, groups=groups)
    execution = benchmark.effect_execution_metrics(
        effect_execution_log(90, events, []),
        disposition,
    )
    return disposition, execution


class SceneWallpaperBenchmarkTests(unittest.TestCase):
    def test_media_thumbnail_metrics_keep_current_layer_identities(self) -> None:
        metrics = benchmark.media_thumbnail_runtime_metrics(
            "\n".join([
                "mediaThumbnailCurrentBindingCount: 3",
                "mediaThumbnailCurrentBindingLayerIDs: 10,20,30",
                "mediaThumbnailPreviousTransitionCount: 2",
                "mediaThumbnailPreviousTransitionLayerIDs: 10,30",
            ])
        )
        self.assertEqual(metrics["current_binding_count"], 3)
        self.assertEqual(metrics["current_binding_layer_ids"], [10, 20, 30])
        self.assertEqual(metrics["previous_transition_count"], 2)
        self.assertEqual(metrics["previous_transition_layer_ids"], [10, 30])

    def test_time_of_day_effect_script_metrics_keep_typed_targets(self) -> None:
        metrics = benchmark.time_of_day_effect_script_runtime_metrics(
            "\n".join([
                "timeOfDayEffectScriptBindingCount: 2",
                "timeOfDayEffectScriptDebugWallDate: 2026-07-31T22:00:00Z",
                "time-of-day effect script: layer=301 effect=0 pass=0 constant=multiply",
                "time-of-day effect script: layer=301 effect=1 pass=0 constant=multiply",
            ])
        )
        self.assertEqual(metrics["binding_count"], 2)
        self.assertEqual(metrics["debug_wall_date"], "2026-07-31T22:00:00Z")
        self.assertEqual(metrics["bindings"], [
            {
                "layer_id": 301,
                "effect_index": 0,
                "pass_index": 0,
                "constant": "multiply",
            },
            {
                "layer_id": 301,
                "effect_index": 1,
                "pass_index": 0,
                "constant": "multiply",
            },
        ])

    def test_project_preview_path_stays_inside_isolated_sample(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-preview-path-") as directory:
            root = Path(directory)
            preview = root / "preview.png"
            visual._write_rgb_png(preview, 1, 1, [bytes((8, 16, 32))])
            (root / "project.json").write_text(
                json.dumps({"preview": "preview.png"}),
                encoding="utf-8",
            )
            self.assertEqual(visual.project_preview_path(root), (preview.resolve(), None))

            (root / "project.json").write_text(
                json.dumps({"preview": "../outside.png"}),
                encoding="utf-8",
            )
            resolved, error = visual.project_preview_path(root)
            self.assertIsNone(resolved)
            self.assertIn("escapes", error)

    def test_directional_visual_metrics_center_crop_capture(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-preview-metrics-") as directory:
            root = Path(directory)
            preview = root / "preview.png"
            capture = root / "capture.png"
            blue = bytes((24, 72, 180))
            red = bytes((220, 24, 24))
            visual._write_rgb_png(preview, 2, 2, [blue * 2, blue * 2])
            visual._write_rgb_png(
                capture,
                4,
                2,
                [red + blue * 2 + red, red + blue * 2 + red],
            )

            metrics = visual.directional_visual_metrics(preview, capture)

            self.assertEqual(
                metrics["capture_center_crop"],
                {"x": 1, "y": 0, "width": 2, "height": 2},
            )
            self.assertEqual(metrics["spatial_color_similarity"], 1.0)
            self.assertEqual(metrics["spatial_luminance_similarity"], 1.0)
            self.assertEqual(metrics["preview_mean_rgb"], metrics["capture_mean_rgb"])

    def test_preview_visual_evidence_is_advisory_and_writes_montage(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-preview-evidence-") as directory:
            root = Path(directory)
            sample = root / "sample"
            result = root / "result"
            sample.mkdir()
            result.mkdir()
            preview = sample / "preview.png"
            capture = result / "scene-after-window.png"
            pixels = [bytes((32, 64, 96)) * 2, bytes((96, 64, 32)) * 2]
            visual._write_rgb_png(preview, 2, 2, pixels)
            visual._write_rgb_png(capture, 2, 2, pixels)
            (sample / "project.json").write_text(
                json.dumps({"preview": "preview.png"}),
                encoding="utf-8",
            )

            evidence = visual.collect_preview_visual_evidence(sample, capture, result)

            self.assertEqual(evidence["status"], "available")
            self.assertTrue(evidence["advisory"])
            self.assertFalse(evidence["gating"])
            self.assertFalse(evidence["cross_sample_ranking"])
            self.assertIsNone(evidence["absolute_threshold"])
            self.assertEqual(evidence["metrics"]["spatial_color_similarity"], 1.0)
            self.assertTrue(Path(evidence["reference_png"]).is_file())
            self.assertTrue(Path(evidence["comparison_montage"]).is_file())
            self.assertTrue(
                benchmark.png_has_non_black_pixel(Path(evidence["comparison_montage"]))
            )

    def test_missing_preview_visual_evidence_never_becomes_a_gate(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-preview-missing-") as directory:
            root = Path(directory)
            sample = root / "sample"
            result = root / "result"
            sample.mkdir()
            result.mkdir()
            capture = result / "scene-after-window.png"
            visual._write_rgb_png(capture, 1, 1, [bytes((12, 34, 56))])
            (sample / "project.json").write_text("{}", encoding="utf-8")

            evidence = visual.collect_preview_visual_evidence(sample, capture, result)

            self.assertEqual(evidence["status"], "unavailable")
            self.assertTrue(evidence["advisory"])
            self.assertFalse(evidence["gating"])
            self.assertIn("not declared", evidence["reason"])

    def test_preview_visual_summary_reports_coverage_without_threshold(self) -> None:
        results = [
            {
                "evidence": {
                    "preview_visual": {
                        "status": "available",
                        "metrics": {"spatial_color_similarity": 0.8},
                    }
                }
            },
            {"evidence": {"preview_visual": {"status": "unavailable"}}},
        ]

        self.assertEqual(
            visual.summarize_preview_visual_evidence(results),
            {
                "advisory": True,
                "gating": False,
                "comparison_scope": "same-sample-change-only",
                "cross_sample_ranking": False,
                "absolute_threshold": None,
                "available_count": 1,
                "unavailable_count": 1,
            },
        )

    def test_load_matrix_accepts_version_one_samples(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-matrix-") as directory:
            path = Path(directory) / "matrix.json"
            path.write_text(
                json.dumps({"schema_version": 1, "name": "fixture", "samples": [{"id": "1"}]}),
                encoding="utf-8",
            )
            self.assertEqual(benchmark.load_matrix(path)["samples"][0]["id"], "1")

    def test_load_matrix_rejects_unknown_schema(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-matrix-") as directory:
            path = Path(directory) / "matrix.json"
            path.write_text(
                json.dumps({"schema_version": 2, "samples": []}),
                encoding="utf-8",
            )
            with self.assertRaises(ValueError):
                benchmark.load_matrix(path)

    def test_select_matrix_samples_reuses_tracked_matrix_for_targeted_runs(self) -> None:
        matrix = {
            "schema_version": 1,
            "name": "fixture",
            "samples": [{"id": "1"}, {"id": "2"}, {"id": "3"}],
        }
        selected = benchmark.select_matrix_samples(matrix, ["3", "1"])
        self.assertEqual([sample["id"] for sample in selected["samples"]], ["1", "3"])
        self.assertEqual(len(matrix["samples"]), 3)
        with self.assertRaisesRegex(ValueError, "9"):
            benchmark.select_matrix_samples(matrix, ["9"])

    def test_hover_pointer_contract_accepts_only_finite_normalized_pairs(self) -> None:
        self.assertEqual(
            benchmark.hover_pointer_normalized(
                {"hover_pointer_normalized": [0.1, -0.25]}
            ),
            (0.1, -0.25),
        )
        self.assertIsNone(benchmark.hover_pointer_normalized({}))
        for value in ([0], [0, 0, 0], [2, 0], [0, float("nan")], ["0", 0]):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    benchmark.hover_pointer_normalized(
                        {"hover_pointer_normalized": value}
                    )

    def test_debug_runner_sequences_before_hover_and_after_frames(self) -> None:
        source = DEBUG_RUNNER_SOURCE.read_text(encoding="utf-8")
        self.assertIn("--mwx-debug-scene-hover-pointer-json", source)
        self.assertIn("--mwx-debug-scene-after-snapshot-delay", source)
        before = source.index('requestSnapshot(reason: "before"')
        hover_state = source.index("setPointer(hoverPointer)", before)
        hover = source.index('requestSnapshot(reason: "hover"', hover_state)
        outside = source.index("setPointerOutside()", hover)
        after = source.index('requestSnapshot(reason: "after"', outside)
        self.assertLess(before, hover_state)
        self.assertLess(hover_state, hover)
        self.assertLess(hover, outside)
        self.assertLess(outside, after)

    def test_copy_sample_requires_project_and_package(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-copy-") as directory:
            root = Path(directory)
            source = root / "source"
            source.mkdir()
            (source / "project.json").write_text("{}", encoding="utf-8")
            with self.assertRaises(FileNotFoundError):
                benchmark.copy_sample(source, root / "missing")

            (source / "scene.pkg").write_bytes(b"PKGV")
            destination = root / "copied"
            benchmark.copy_sample(source, destination)
            self.assertEqual((destination / "scene.pkg").read_bytes(), b"PKGV")

    def test_passing_runtime_is_removed_without_keep_flag(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-retention-") as directory:
            root = Path(directory)
            runtime_root = root / "runtime"
            runtime_sample = runtime_root / "runtime-samples/1"
            runtime_home = runtime_root / "runtime-homes/1"
            runtime_binary = (
                runtime_root
                / "runtime-app-fixture/MyWallpaperX.app/Contents/MacOS/MyWallpaperX"
            )
            for path in (runtime_sample, runtime_home, runtime_binary.parent):
                path.mkdir(parents=True, exist_ok=True)
            runtime_binary.write_bytes(b"binary")
            app_identity = {
                "runtime_root_path": str(runtime_root / "runtime-app-fixture"),
                "runtime_bundle_path": str(
                    runtime_root / "runtime-app-fixture/MyWallpaperX.app"
                ),
                "runtime_executable_path": str(runtime_binary),
                "runtime_retained": True,
            }
            result = {
                "id": "1",
                "passed": True,
                "runtime_sample": str(runtime_sample),
                "runtime_home": str(runtime_home),
                "runtime_retained": True,
            }

            benchmark.apply_runtime_retention(
                runtime_root,
                app_identity,
                [result],
                keep_runtime=False,
            )

            self.assertFalse(runtime_root.exists())
            self.assertFalse(result["runtime_retained"])
            self.assertIsNone(result["runtime_sample"])
            self.assertIsNone(result["runtime_home"])
            self.assertFalse(app_identity["runtime_retained"])

    def test_failed_runtime_is_retained_while_passing_sample_is_removed(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-retention-") as directory:
            runtime_root = Path(directory) / "runtime"
            app_root = runtime_root / "runtime-app-fixture"
            app_root.mkdir(parents=True)
            results = []
            for sample_id, passed in (("1", True), ("2", False)):
                runtime_sample = runtime_root / "runtime-samples" / sample_id
                runtime_home = runtime_root / "runtime-homes" / sample_id
                runtime_sample.mkdir(parents=True)
                runtime_home.mkdir(parents=True)
                results.append({
                    "id": sample_id,
                    "passed": passed,
                    "runtime_sample": str(runtime_sample),
                    "runtime_home": str(runtime_home),
                    "runtime_retained": True,
                })
            app_identity = {"runtime_retained": True}

            benchmark.apply_runtime_retention(
                runtime_root,
                app_identity,
                results,
                keep_runtime=False,
            )

            self.assertFalse((runtime_root / "runtime-samples/1").exists())
            self.assertFalse((runtime_root / "runtime-homes/1").exists())
            self.assertTrue((runtime_root / "runtime-samples/2").is_dir())
            self.assertTrue((runtime_root / "runtime-homes/2").is_dir())
            self.assertFalse(results[0]["runtime_retained"])
            self.assertTrue(results[1]["runtime_retained"])
            self.assertTrue(app_identity["runtime_retained"])

    def test_entry_basename_package_is_preferred_and_copied(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-copy-variant-") as directory:
            root = Path(directory)
            source = root / "source"
            source.mkdir()
            (source / "project.json").write_text(
                json.dumps({"type": "scene", "file": "nested\\gifscene.json"}),
                encoding="utf-8",
            )
            (source / "gifscene.pkg").write_bytes(b"NAMED")
            (source / "scene.pkg").write_bytes(b"FALLBACK")

            self.assertEqual(benchmark.scene_package_path(source), source / "gifscene.pkg")
            destination = root / "copied"
            benchmark.copy_sample(source, destination)
            self.assertEqual((destination / "gifscene.pkg").read_bytes(), b"NAMED")

    def test_custom_entry_falls_back_to_scene_package(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-copy-fallback-") as directory:
            source = Path(directory)
            (source / "project.json").write_text(
                json.dumps({"type": "scene", "file": "gifscene.json"}),
                encoding="utf-8",
            )
            (source / "scene.pkg").write_bytes(b"FALLBACK")
            self.assertEqual(benchmark.scene_package_path(source), source / "scene.pkg")

    def test_swift_project_loader_resolves_entry_package_and_fallback(self) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-scene-project-loader-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            binary = root / "scene-project-loader"
            harness.write_text(
                """
                import Foundation

                @main
                enum Harness {
                    static func main() throws {
                        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
                        let project = try SceneProjectLoader().load(from: root)
                        print(project.packageURL?.lastPathComponent ?? "nil")
                    }
                }
                """,
                encoding="utf-8",
            )
            subprocess.run(
                [
                    swiftc,
                    str(SCRIPT_DIR.parent / "MyWallpaperX/Core/SteamWorkshopScene/Properties/SceneUserProperty.swift"),
                    str(SCRIPT_DIR.parent / "MyWallpaperX/Core/SteamWorkshopScene/Properties/SceneUserPropertyDefinitionParser.swift"),
                    str(SCRIPT_DIR.parent / "MyWallpaperX/Core/SteamWorkshopScene/Format/SceneCompatibilityContext.swift"),
                    str(SCRIPT_DIR.parent / "MyWallpaperX/Core/SteamWorkshopScene/Format/SceneProject.swift"),
                    str(harness),
                    "-o",
                    str(binary),
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            sample = root / "sample"
            sample.mkdir()
            (sample / "project.json").write_text(
                json.dumps({"type": "scene", "file": "gifscene.json"}),
                encoding="utf-8",
            )
            (sample / "gifscene.pkg").write_bytes(b"NAMED")
            (sample / "scene.pkg").write_bytes(b"FALLBACK")
            named = subprocess.run(
                [str(binary), str(sample)],
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertEqual(named.stdout.strip(), "gifscene.pkg")

            (sample / "gifscene.pkg").unlink()
            fallback = subprocess.run(
                [str(binary), str(sample)],
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertEqual(fallback.stdout.strip(), "scene.pkg")

    def test_runtime_evidence_metrics_preserve_slots_and_combos(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-runtime-evidence-") as directory:
            path = Path(directory) / "scene-runtime-evidence.json"
            shader_contracts = [{
                "identity": "effects/zeta",
                "sourceKind": "authoredSource",
                "stages": [
                    shader_stage("effects/zeta", "vertex", "zeta vertex"),
                    shader_stage("effects/zeta", "fragment", "zeta fragment"),
                ],
                "diagnostics": [],
                "canonicalSHA256": "b" * 64,
            }, {
                "identity": "genericimage4",
                "sourceKind": "hostBuiltin",
                "stages": [],
                "diagnostics": [],
                "canonicalSHA256": "c" * 64,
            }, {
                "identity": "effects/alpha",
                "sourceKind": "authoredSource",
                "stages": [
                    shader_stage("effects/alpha", "vertex", "alpha vertex"),
                    shader_stage("effects/alpha", "fragment", "alpha fragment"),
                ],
                "diagnostics": [{
                    "code": "malformedAnnotation",
                    "message": "bad annotation",
                    "relativePath": "shaders/effects/alpha.frag",
                    "line": 2,
                }],
                "canonicalSHA256": "a" * 64,
            }]
            effect_graphs = [{
                "effects": [{"key": "one"}, {"key": "two"}],
                "renderTargets": [{"name": "one"}, {"name": "two"}],
                "nodes": [
                    {"kind": "material"},
                    {"kind": "copy"},
                    {"kind": "swap"},
                ],
                "blockers": [{"reason": "unsupportedCondition"}],
            }, {
                "layerID": 9,
                "effects": [{
                    "key": "three",
                    "definitionPath": "Effects\\Opacity\\Effect.json",
                }],
                "renderTargets": [],
                "nodes": [{"kind": "material"}],
                "blockers": [],
            }]
            path.write_text(
                json.dumps(runtime_evidence({
                    "shaderContracts": shader_contracts,
                    "authoredEffectRenderPlans": effect_graphs,
                    "renderDescriptor": {
                        "materialPasses": [{
                            "textureSlots": [None, None, "phase.tex"],
                            "combos": {"VERSION": 2, "MODE": 0},
                        }],
                        "effectDefinitions": [{
                            "passes": [
                                {"materialPath": "materials/effects/test.json"},
                                {"command": "copy"},
                                {"command": "swap"},
                            ],
                            "framebuffers": [{"name": "one"}, {"name": "two"}],
                        }],
                        "effectDefinitionDiagnostics": [{"code": "unknownFields"}],
                        "builtInReferenceCount": 4,
                        "missingResources": ["one", "two"],
                        "layers": [{
                            "id": 1,
                            "visible": False,
                            "parentID": None,
                            "effects": [],
                        }, {
                            "effects": [{"file": "effects/test.json", "passes": [{
                                "textureSlots": [None, "normal.tex"],
                                "combos": {"REPEAT": 1},
                            }]}],
                            "id": 7,
                            "visible": True,
                            "parentID": 1,
                            "text": "property gate",
                            "contentKind": "solid",
                            "parallaxDepthXY": [2, 0],
                            "disablesParallaxPropagation": True,
                        }, {
                            "id": 8,
                            "visible": True,
                            "parentID": None,
                            "contentKind": "solid",
                            "colorRGB": [0.2, 0.4, 0.6],
                            "effects": [],
                        }, {
                            "id": 9,
                            "visible": True,
                            "parentID": 8,
                            "contentKind": "solid",
                            "effects": [],
                        }],
                    },
                })),
                encoding="utf-8",
            )
            metrics = benchmark.runtime_evidence_metrics(path)
            self.assertEqual(metrics["schema_version"], 1)
            self.assertEqual(metrics["shader_contract_count"], 3)
            self.assertEqual(metrics["shader_contract_authored_count"], 2)
            self.assertEqual(metrics["shader_contract_builtin_count"], 1)
            self.assertEqual(metrics["shader_contract_stage_count"], 4)
            self.assertEqual(metrics["shader_contract_diagnostic_count"], 1)
            self.assertEqual(
                metrics["shader_contract_aggregate_sha256"],
                "33c1609a3d79a75fef6e568b233d01a0b94ab6233d6137cc828418dfa74a9f4c",
            )
            self.assertEqual(metrics["effect_texture_slot_count"], 2)
            self.assertEqual(metrics["effect_texture_slot_hole_count"], 1)
            self.assertEqual(metrics["effect_combo_entry_count"], 1)
            self.assertEqual(metrics["material_texture_slot_count"], 3)
            self.assertEqual(metrics["material_texture_slot_hole_count"], 2)
            self.assertEqual(metrics["material_combo_entry_count"], 2)
            self.assertEqual(metrics["effect_definition_count"], 1)
            self.assertEqual(metrics["effect_definition_pass_count"], 3)
            self.assertEqual(metrics["effect_definition_material_pass_count"], 1)
            self.assertEqual(metrics["effect_definition_fbo_count"], 2)
            self.assertEqual(metrics["effect_definition_copy_command_count"], 1)
            self.assertEqual(metrics["effect_definition_swap_command_count"], 1)
            self.assertEqual(metrics["effect_definition_diagnostic_count"], 1)
            self.assertEqual(metrics["effect_graph_layer_count"], 2)
            self.assertEqual(metrics["effect_graph_effect_count"], 3)
            self.assertEqual(metrics["effect_graph_node_count"], 4)
            self.assertEqual(metrics["effect_graph_material_node_count"], 2)
            self.assertEqual(metrics["effect_graph_copy_node_count"], 1)
            self.assertEqual(metrics["effect_graph_swap_node_count"], 1)
            self.assertEqual(metrics["effect_graph_render_target_count"], 2)
            self.assertEqual(metrics["effect_graph_blocker_count"], 1)
            self.assertEqual(
                metrics["effect_graph_blocker_reasons"],
                {"unsupportedCondition": 1},
            )
            self.assertEqual(metrics["effect_graph_unblocked_layer_count"], 1)
            self.assertEqual(
                metrics["effect_graph_sha256"],
                hashlib.sha256(json.dumps(
                    effect_graphs,
                    ensure_ascii=True,
                    sort_keys=True,
                    separators=(",", ":"),
                ).encode("utf-8")).hexdigest(),
            )
            self.assertEqual(metrics["visible_layer_count"], 3)
            self.assertEqual(metrics["visible_layer_ids"], [7, 8, 9])
            self.assertEqual(metrics["root_layer_count"], 2)
            self.assertEqual(metrics["child_edge_count"], 2)
            self.assertEqual(metrics["parent_layer_count"], 2)
            self.assertEqual(metrics["max_hierarchy_depth"], 1)
            self.assertEqual(metrics["effective_visible_layer_count"], 2)
            self.assertEqual(metrics["effective_visible_layer_ids"], [8, 9])
            self.assertEqual(
                metrics["stock_opacity_single_effect_candidate_layer_ids"],
                [9],
            )
            self.assertEqual(metrics["solid_layer_count"], 3)
            self.assertEqual(metrics["solid_layer_ids"], [7, 8, 9])
            self.assertEqual(metrics["authored_solid_color_layer_count"], 1)
            self.assertEqual(metrics["authored_solid_color_layer_ids"], [8])
            self.assertEqual(metrics["effective_visible_solid_layer_count"], 2)
            self.assertEqual(metrics["effective_visible_solid_layer_ids"], [8, 9])
            self.assertEqual(metrics["authored_parallax_layer_count"], 1)
            self.assertEqual(metrics["authored_parallax_layer_ids"], [7])
            self.assertEqual(metrics["parallax_propagation_block_count"], 1)
            self.assertEqual(metrics["text_values"], ["property gate"])
            self.assertEqual(metrics["effect_files"], ["effects/test.json"])
            self.assertEqual(metrics["built_in_reference_count"], 4)
            self.assertEqual(metrics["missing_resource_count"], 2)
            self.assertIsNone(metrics["error"])

    def test_runtime_evidence_metrics_reject_invalid_slot_shape(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-runtime-evidence-") as directory:
            path = Path(directory) / "scene-runtime-evidence.json"
            path.write_text(json.dumps(runtime_evidence({
                "shaderContracts": [],
                "renderDescriptor": {
                    "layers": [{"effects": [{"passes": [{"textureSlots": "bad", "combos": {}}]}]}],
                    "materialPasses": [],
                },
            })), encoding="utf-8")
            metrics = benchmark.runtime_evidence_metrics(path)
            self.assertIsNone(metrics["schema_version"])
            self.assertIn("invalid shape", metrics["error"])

    def test_shader_contract_aggregate_is_independent_of_contract_order(self) -> None:
        contracts = [{
            "identity": "effects/zeta",
            "sourceKind": "authoredSource",
            "stages": [
                shader_stage("effects/zeta", "vertex", "zeta vertex"),
                shader_stage("effects/zeta", "fragment", "zeta fragment"),
            ],
            "diagnostics": [],
            "canonicalSHA256": "b" * 64,
        }, {
            "identity": "genericimage4",
            "sourceKind": "hostBuiltin",
            "stages": [],
            "diagnostics": [],
            "canonicalSHA256": "c" * 64,
        }]
        forward = benchmark.shader_contract_metrics(contracts)
        reverse = benchmark.shader_contract_metrics(list(reversed(contracts)))
        self.assertEqual(
            forward["shader_contract_aggregate_sha256"],
            reverse["shader_contract_aggregate_sha256"],
        )

    def test_runtime_evidence_metrics_reject_missing_or_malformed_shader_contracts(self) -> None:
        valid_contract = {
            "identity": "effects/example",
            "sourceKind": "authoredSource",
            "stages": [
                shader_stage("effects/example", "vertex", "example vertex"),
                shader_stage("effects/example", "fragment", "example fragment"),
            ],
            "diagnostics": [],
            "canonicalSHA256": "a" * 64,
        }
        malformed_contract_sets = {
            "missing": None,
            "not-an-array": {},
            "non-object-contract": ["bad"],
            "missing-identity": [{
                key: value for key, value in valid_contract.items() if key != "identity"
            }],
            "unknown-source-kind": [{**valid_contract, "sourceKind": "generated"}],
            "stages-not-an-array": [{**valid_contract, "stages": {}}],
            "stage-not-an-object": [{**valid_contract, "stages": ["bad"]}],
            "stage-missing-fields": [{**valid_contract, "stages": [{}]}],
            "stage-hash-mismatch": [{
                **valid_contract,
                "stages": [{**valid_contract["stages"][0], "source": "changed"}],
            }],
            "diagnostics-not-an-array": [{**valid_contract, "diagnostics": {}}],
            "diagnostic-not-an-object": [{**valid_contract, "diagnostics": ["bad"]}],
            "diagnostic-missing-fields": [{**valid_contract, "diagnostics": [{}]}],
            "empty-canonical-sha": [{**valid_contract, "canonicalSHA256": ""}],
            "malformed-canonical-sha": [{**valid_contract, "canonicalSHA256": "A" * 64}],
            "duplicate-identity": [valid_contract, valid_contract],
            "builtin-with-stage": [{
                **valid_contract,
                "identity": "genericimage2",
                "sourceKind": "hostBuiltin",
                "stages": [shader_stage("genericimage2", "vertex", "bad")],
            }],
        }
        with tempfile.TemporaryDirectory(prefix="mwx-scene-runtime-evidence-") as directory:
            path = Path(directory) / "scene-runtime-evidence.json"
            for case, contracts in malformed_contract_sets.items():
                with self.subTest(case=case):
                    payload = {
                        "renderDescriptor": {"layers": [], "materialPasses": []},
                    }
                    if case != "missing":
                        payload["shaderContracts"] = contracts
                    path.write_text(
                        json.dumps(runtime_evidence(payload)), encoding="utf-8"
                    )
                    metrics = benchmark.runtime_evidence_metrics(path)
                    self.assertIsNone(metrics["schema_version"])
                    self.assertIsNone(metrics["shader_contract_aggregate_sha256"])
                    self.assertTrue(metrics["error"])

    def test_runtime_log_patterns_capture_ready_and_release(self) -> None:
        ready = benchmark.READY_RE.search(
            "MWX DEBUG SCENE: phase=ready root=/tmp/sample layers=35 "
            "imageLayers=24 effects=29 surfaces=1 startupElapsedMS=1825.250 "
            "windows=42 previewLog=/tmp/log "
            "runtimeEvidence=/tmp/evidence/scene-runtime-evidence.json"
        )
        evidence = benchmark.RUNTIME_EVIDENCE_RE.search(
            "MWX DEBUG SCENE: phase=ready root=/tmp/sample layers=35 "
            "imageLayers=24 effects=29 surfaces=1 startupElapsedMS=1825.250 "
            "windows=42 previewLog=/tmp/log "
            "runtimeEvidence=/tmp/evidence/scene-runtime-evidence.json"
        )
        stopped = benchmark.STOPPED_RE.search(
            "MWX DEBUG SCENE: phase=stopped surfacesBefore=1 surfacesAfter=0"
        )
        live = benchmark.live_property_update_metrics(
            "MWX DEBUG SCENE: phase=live-property-update accepted=true "
            "surfacesBefore=1 surfacesAfter=1 windowsBefore=42 windowsAfter=42 "
            "keys=newproperty11"
        )
        loaded = benchmark.LOADED_RE.search("loaded: 20 / 24")
        text_loaded = benchmark.TEXT_LOADED_RE.search("text loaded: 10 / 10")
        particle_loaded = benchmark.PARTICLE_LOADED_RE.search("particle loaded: 3 / 4")
        particle_refract = benchmark.PARTICLE_REFRACT_LOADED_RE.search(
            "particle refract loaded: 2"
        )
        particle_live = benchmark.PARTICLE_INITIAL_LIVE_RE.search("particle initial live: 96")
        camera = benchmark.CAMERA_RE.search(
            "camera: projection=cover parallax=false amount=8e-2 delay=0.25 mouseInfluence=-1.0"
        )
        self.assertEqual(ready.group("images"), "24")
        self.assertEqual(float(ready.group("startup_elapsed_ms")), 1825.25)
        self.assertEqual(
            evidence.group("path"),
            "/tmp/evidence/scene-runtime-evidence.json",
        )
        self.assertEqual(stopped.group("after"), "0")
        self.assertEqual(live, {
            "accepted": True,
            "surfaces_before": 1,
            "surfaces_after": 1,
            "windows_before": [42],
            "windows_after": [42],
            "keys": ["newproperty11"],
        })
        self.assertEqual(loaded.group("loaded"), "20")
        self.assertEqual(text_loaded.group("loaded"), "10")
        self.assertEqual(particle_loaded.group("loaded"), "3")
        self.assertEqual(particle_loaded.group("total"), "4")
        self.assertEqual(particle_refract.group("count"), "2")
        self.assertEqual(particle_live.group("live"), "96")
        self.assertEqual(camera.group("projection"), "cover")
        self.assertEqual(camera.group("parallax"), "false")
        self.assertEqual(float(camera.group("amount")), 0.08)
        self.assertEqual(float(camera.group("delay")), 0.25)
        self.assertEqual(float(camera.group("influence")), -1.0)

    def test_performance_metrics_parse_v7_evidence_and_normalize_surfaces(self) -> None:
        log = (
            "MWX DEBUG SCENE: phase=performance elapsed=6.833 callbacks=410 "
            "submitted=410 completed=409 failed=0 submittedFPS=60.004 "
            "completedFPS=59.857 callbackP50MS=16.666 callbackP95MS=16.698 "
            "callbackMaxMS=17.171 callbackOver16=199 callbackOver33=0 "
            "discontinuities=1 droppedMS=750.000 maxRawFrameMS=1000.000 "
            "drawableMissed=0 drawableWaitP95MS=0.013 drawableWaitMaxMS=0.034 "
            "preEncodeP95MS=7.671 preEncodeMaxMS=7.868 mainFrameP95MS=8.097 "
            "mainFrameMaxMS=8.311 cpuP50MS=0.348 cpuP95MS=0.380 "
            "cpuMaxMS=0.578 cpuOver16=0 cpuOver33=0 gpuSamples=409 "
            "gpuP50MS=2.279 gpuP95MS=3.886 gpuMaxMS=4.752 "
            "gpuOver16=0 gpuOver33=0"
        )
        metrics = benchmark.performance_metrics(log, surface_count=1)
        self.assertTrue(metrics["available"])
        self.assertEqual(metrics["driver_callbacks"], 410)
        self.assertAlmostEqual(metrics["driver_fps"], 410 / 6.833)
        self.assertEqual(metrics["completed_frames"], 409)
        self.assertEqual(metrics["callback_over_16_67_ms"], 199)
        self.assertEqual(metrics["discontinuity_count"], 1)
        self.assertEqual(metrics["dropped_frame_time_ms"], 750)
        self.assertEqual(metrics["maximum_raw_frame_time_ms"], 1000)
        self.assertAlmostEqual(metrics["completed_fps_per_surface"], 59.857)
        self.assertAlmostEqual(metrics["pre_encode_p95_ms"], 7.671)
        self.assertAlmostEqual(metrics["gpu_frame_p95_ms"], 3.886)
        two_surface = benchmark.performance_metrics(log, surface_count=2)
        self.assertAlmostEqual(two_surface["completed_fps_per_surface"], 29.9285)
        self.assertEqual(benchmark.performance_failures(metrics), [])

    def test_performance_metrics_fail_closed_on_missing_or_malformed_evidence(self) -> None:
        self.assertIn(
            "expected one performance event",
            benchmark.performance_metrics("", 1)["error"],
        )
        duplicate = (
            "phase=performance elapsed=1 elapsed=2\n"
        )
        self.assertIn("duplicate performance field", benchmark.performance_metrics(duplicate, 1)["error"])
        missing = "phase=performance elapsed=1 callbacks=60"
        self.assertIn("missing performance fields", benchmark.performance_metrics(missing, 1)["error"])

    def test_performance_summary_preserves_worst_sample_identity(self) -> None:
        results = [
            {
                "id": "fast",
                "runtime": {
                    "startup_ready_ms": 800.0,
                    "performance": {"available": True, "driver_fps": 60.0},
                },
            },
            {
                "id": "slow",
                "runtime": {
                    "startup_ready_ms": 1800.0,
                    "performance": {"available": True, "driver_fps": 48.0},
                },
            },
            {"id": "missing", "runtime": {"performance": {"available": False}}},
        ]
        summary = benchmark.summarize_performance(results)
        self.assertEqual(summary["available_count"], 2)
        self.assertEqual(summary["unavailable_count"], 1)
        self.assertEqual(summary["lowest_driver_fps"], {"id": "slow", "fps": 48.0})
        self.assertEqual(
            summary["slowest_startup_ready_ms"],
            {"id": "slow", "milliseconds": 1800.0},
        )

    def test_live_property_arguments_and_strict_identity_gate(self) -> None:
        command = ["MyWallpaperX"]
        benchmark.append_property_arguments(
            command,
            {"initial": 0.7},
            {"newproperty11": 0},
        )
        self.assertEqual(command, [
            "MyWallpaperX",
            "--mwx-debug-scene-properties-json",
            '{"initial":0.7}',
            "--mwx-debug-scene-live-properties-json",
            '{"newproperty11":0}',
        ])
        accepted = benchmark.live_property_update_metrics(
            "phase=live-property-update accepted=true surfacesBefore=1 surfacesAfter=1 "
            "windowsBefore=42 windowsAfter=42 keys=newproperty11"
        )
        replaced = benchmark.live_property_update_metrics(
            "phase=live-property-update accepted=true surfacesBefore=1 surfacesAfter=1 "
            "windowsBefore=42 windowsAfter=43 keys=newproperty11"
        )
        rejected = benchmark.live_property_update_metrics(
            "phase=live-property-update accepted=false surfacesBefore=1 surfacesAfter=1 "
            "windowsBefore=42 windowsAfter=42 keys=newproperty11"
        )
        requested = {"newproperty11": 0}
        self.assertEqual(benchmark.live_property_update_failures(requested, accepted), [])
        self.assertIn(
            "live property update replaced Scene windows",
            benchmark.live_property_update_failures(requested, replaced),
        )
        self.assertIn(
            "live property update rejected",
            benchmark.live_property_update_failures(requested, rejected),
        )
        self.assertIn(
            "live property update evidence missing",
            benchmark.live_property_update_failures(requested, None),
        )

    def test_media_thumbnail_argument_stays_inside_isolated_sample(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-media-thumbnail-argument-") as directory:
            runtime_sample = Path(directory)
            (runtime_sample / "cover.png").write_bytes(b"fixture")
            command = ["MyWallpaperX"]
            failures: list[str] = []

            benchmark.append_media_thumbnail_argument(
                command,
                "cover.png",
                runtime_sample,
                failures,
            )

            self.assertEqual(failures, [])
            self.assertEqual(command, [
                "MyWallpaperX",
                "--mwx-debug-scene-media-thumbnail",
                "cover.png",
            ])

            for invalid in ("../cover.png", "/tmp/cover.png", "cover.webp", "missing.png"):
                invalid_failures: list[str] = []
                benchmark.append_media_thumbnail_argument(
                    [],
                    invalid,
                    runtime_sample,
                    invalid_failures,
                )
                self.assertEqual(
                    invalid_failures,
                    ["invalid isolated media thumbnail path"],
                )

    def test_media_thumbnail_sequence_stays_inside_isolated_sample(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-media-thumbnail-sequence-") as directory:
            runtime_sample = Path(directory)
            (runtime_sample / "next.png").write_bytes(b"fixture")
            command = ["MyWallpaperX"]
            failures: list[str] = []
            benchmark.append_media_thumbnail_sequence_argument(
                command,
                [
                    {"path": "next.png", "delay": 1.5},
                    {"clear": True, "delay": 3.0},
                ],
                runtime_sample,
                failures,
            )
            self.assertEqual(failures, [])
            self.assertEqual(command[:2], [
                "MyWallpaperX",
                "--mwx-debug-scene-media-thumbnail-sequence-json",
            ])
            self.assertEqual(
                json.loads(command[2]),
                [
                    {"path": "next.png", "delay": 1.5},
                    {"clear": True, "delay": 3.0},
                ],
            )
            for invalid in (
                [{"path": "../next.png", "delay": 1.5}],
                [{"path": "next.png", "delay": 0}],
                [{"path": "next.png", "delay": True}],
                [{"path": "missing.png", "delay": 1.5}],
                [{"clear": False, "delay": 1.5}],
                [{"clear": True, "path": "next.png", "delay": 1.5}],
            ):
                invalid_failures: list[str] = []
                benchmark.append_media_thumbnail_sequence_argument(
                    [], invalid, runtime_sample, invalid_failures
                )
                self.assertEqual(
                    invalid_failures,
                    ["invalid isolated media thumbnail sequence"],
                )

    def test_media_thumbnail_transition_execution_metrics_collect_exact_phases(self) -> None:
        log = """
MWX media thumbnail transition: layer=526 generation=2 phase=started duration=1.0
MWX media thumbnail transition: layer=642 generation=2 phase=started duration=1.0
MWX media thumbnail transition: layer=526 generation=2 phase=midpoint
MWX media thumbnail transition: layer=642 generation=2 phase=midpoint
X media thumbnail transition: layer=526 generation=2 phase=completed
MWX media thumbnail transition: layer=642 generation=2 phase=completed
"""
        self.assertEqual(
            benchmark.media_thumbnail_transition_execution_metrics(log),
            {
                "generation_ids": [2],
                "started_layer_ids": [526, 642],
                "midpoint_layer_ids": [526, 642],
                "completed_layer_ids": [526, 642],
            },
        )

    def test_media_thumbnail_store_metrics_preserve_pending_and_clear_state(self) -> None:
        log = """
MWX media thumbnail store: phase=ready generation=1 hasCurrent=true hasPrevious=false
MWX media thumbnail store: phase=pending-last-ready requestedGeneration=2 readyGeneration=1 hasCurrent=true
MWX media thumbnail store: phase=ready generation=2 hasCurrent=true hasPrevious=true
MWX DEBUG SCENE: phase=media-thumbnail-cleared
MWX media thumbnail store: phase=pending-last-ready requestedGeneration=3 readyGeneration=2 hasCurrent=true
MWX media thumbnail store: phase=ready generation=3 hasCurrent=false hasPrevious=false
"""
        self.assertEqual(
            benchmark.media_thumbnail_store_metrics(log),
            {
                "pending_last_ready": [
                    {
                        "requested_generation": 2,
                        "ready_generation": 1,
                        "has_current": True,
                    },
                    {
                        "requested_generation": 3,
                        "ready_generation": 2,
                        "has_current": True,
                    },
                ],
                "ready_states": [
                    {
                        "generation": 1,
                        "has_current": True,
                        "has_previous": False,
                    },
                    {
                        "generation": 2,
                        "has_current": True,
                        "has_previous": True,
                    },
                    {
                        "generation": 3,
                        "has_current": False,
                        "has_previous": False,
                    },
                ],
                "clear_count": 1,
            },
        )

    def test_live_property_output_requires_a_visible_post_update_change(self) -> None:
        sample = {"minimum_live_changed_ratio": 0.01}
        self.assertEqual(
            benchmark.live_property_output_failures(sample, {"changed_ratio": 0.02}),
            [],
        )
        self.assertEqual(
            benchmark.live_property_output_failures(sample, {"changed_ratio": 0.001}),
            ["live property output evidence below minimum"],
        )
        self.assertEqual(
            benchmark.live_property_output_failures(sample, None),
            ["live property output evidence below minimum"],
        )

    def test_debug_runner_updates_the_existing_host_record(self) -> None:
        source = DEBUG_RUNNER_SOURCE.read_text(encoding="utf-8")
        self.assertIn('private static let debugRecordID = "debug-scene-playback"', source)
        self.assertIn("--mwx-debug-scene-live-properties-json", source)
        self.assertIn("recordID: debugRecordID", source)
        self.assertIn("phase=live-property-update", source)

    def test_scene_script_audio_bars_runtime_metrics_and_exact_gates(self) -> None:
        preview_log = """Scene preview texture load report
sceneScriptAudioBarsPlanCount: 1
sceneScriptAudioBarsDiagnosticCount: 0
sceneScriptAudioBarsHasAudioConsumer: true
sceneScript audio bars: layer=282 host=visible sourceSHA256=2d874f553bef33dfd4650b1d38630148ccf52940bb6b542f46860411aa5d9379 count=64 resolution=64 channel=average model=models/workshop/2079954552/bar.json material=materials/workshop/2079954552/bar.json texture=workshop/2079954552/bar width=1.00000 height=50.00000 depth=1.00000 xStep=5.60000 yStep=11.30000 angle=60.00000 alignment=centre firstStep=advanceBeforeFirstBar
"""
        metrics = benchmark.scene_script_audio_bars_runtime_metrics(preview_log)
        execution = benchmark.scene_script_audio_bars_execution_metrics(
            "MWX DEBUG SCENE: phase=scene-script-audio-bars "
            "layer=282 status=succeeded\n"
        )
        self.assertEqual(metrics["plan_count"], 1)
        self.assertEqual(metrics["diagnostic_count"], 0)
        self.assertTrue(metrics["has_audio_consumer"])
        self.assertEqual(metrics["plan_layer_ids"], [282])
        self.assertEqual(metrics["total_bar_count"], 64)
        self.assertEqual(
            metrics["plans"][0],
            {
                "layer_id": 282,
                "host": "visible",
                "source_sha256":
                    "2d874f553bef33dfd4650b1d38630148ccf52940bb6b542f46860411aa5d9379",
                "bar_count": 64,
                "audio_resolution": 64,
                "channel": "average",
                "model_path": "models/workshop/2079954552/bar.json",
                "material_path": "materials/workshop/2079954552/bar.json",
                "texture_path": "workshop/2079954552/bar",
                "width_multiplier": 1.0,
                "height_multiplier": 50.0,
                "depth_multiplier": 1.0,
                "x_step": 5.6,
                "y_step": 11.3,
                "angle_degrees": 60.0,
                "alignment": "centre",
                "first_step": "advanceBeforeFirstBar",
            },
        )
        self.assertTrue(execution["has_evidence"])
        self.assertEqual(execution["succeeded_layer_ids"], [282])
        self.assertEqual(execution["failed_layer_ids"], [])
        self.assertEqual(
            benchmark.scene_script_audio_bars_runtime_metrics(
                preview_log.replace("count=64", "instances=64")
            )["total_bar_count"],
            64,
        )
        sample = {
            "expected_scene_script_audio_bars_plan_count": 1,
            "expected_scene_script_audio_bars_diagnostic_count": 0,
            "expected_scene_script_audio_bars_has_audio_consumer": True,
            "expected_scene_script_audio_bars_total_bar_count": 64,
            "expected_scene_script_audio_bars_plan_layer_ids": [282],
            "expected_scene_script_audio_bars_plans": [dict(metrics["plans"][0])],
            "expected_scene_script_audio_bars_succeeded_layer_ids": [282],
            "required_scene_script_audio_bars_succeeded_layer_ids": [282],
        }
        self.assertEqual(
            benchmark.scene_script_audio_bars_runtime_failures(
                sample,
                metrics,
                execution,
            ),
            [],
        )

        tolerant = dict(sample)
        tolerant_plan = dict(metrics["plans"][0])
        tolerant_plan["x_step"] = 5.60005
        tolerant["expected_scene_script_audio_bars_plans"] = [tolerant_plan]
        self.assertNotIn(
            "SceneScript audio bars plan tuple mismatch",
            benchmark.scene_script_audio_bars_runtime_failures(
                tolerant,
                metrics,
                execution,
            ),
        )

        swapped = dict(sample)
        swapped_plan = dict(metrics["plans"][0])
        swapped_plan.update({
            "width_multiplier": 2.5,
            "depth_multiplier": 0.0,
            "x_step": 20.0,
            "y_step": 0.0,
            "angle_degrees": 0.0,
            "first_step": "ownerAtBaseOrigin",
        })
        swapped["expected_scene_script_audio_bars_plans"] = [swapped_plan]
        self.assertIn(
            "SceneScript audio bars plan tuple mismatch",
            benchmark.scene_script_audio_bars_runtime_failures(
                swapped,
                metrics,
                execution,
            ),
        )

        single_field = dict(sample)
        single_field_plan = dict(metrics["plans"][0])
        single_field_plan["material_path"] = "materials/wrong/bar.json"
        single_field["expected_scene_script_audio_bars_plans"] = [
            single_field_plan
        ]
        self.assertIn(
            "SceneScript audio bars plan tuple mismatch",
            benchmark.scene_script_audio_bars_runtime_failures(
                single_field,
                metrics,
                execution,
            ),
        )

        missing_telemetry = benchmark.scene_script_audio_bars_runtime_failures(
            sample,
            metrics,
            benchmark.scene_script_audio_bars_execution_metrics(""),
        )
        self.assertIn(
            "SceneScript audio bars execution evidence missing",
            missing_telemetry,
        )
        self.assertIn(
            "SceneScript audio bars planned layer 282 should succeed",
            missing_telemetry,
        )
        failed_telemetry = benchmark.scene_script_audio_bars_runtime_failures(
            sample,
            metrics,
            benchmark.scene_script_audio_bars_execution_metrics(
                "phase=scene-script-audio-bars layer=282 status=failed\n"
            ),
        )
        self.assertIn(
            "SceneScript audio bars layer 282 failed",
            failed_telemetry,
        )
        self.assertIn(
            "SceneScript audio bars planned layer 282 should succeed",
            failed_telemetry,
        )
        failed_then_succeeded = (
            benchmark.scene_script_audio_bars_execution_metrics(
                "phase=scene-script-audio-bars layer=282 status=failed\n"
                "phase=scene-script-audio-bars layer=282 status=succeeded\n"
            )
        )
        self.assertEqual(failed_then_succeeded["succeeded_layer_ids"], [282])
        self.assertEqual(failed_then_succeeded["failed_layer_ids"], [282])
        self.assertIn(
            "SceneScript audio bars layer 282 failed",
            benchmark.scene_script_audio_bars_runtime_failures(
                sample,
                metrics,
                failed_then_succeeded,
            ),
        )

        self.assertIn(
            "SceneScript audio bars runtime evidence missing",
            benchmark.scene_script_audio_bars_runtime_failures(
                sample,
                benchmark.scene_script_audio_bars_runtime_metrics(""),
                execution,
            ),
        )

    def test_solid_runtime_fixture_metrics_and_optional_gates(self) -> None:
        preview_log = """Scene preview texture load report
solidLayerCount: 3
layer 13 "Backdrop": OK procedural solid tint=(1.00000, 1.00000, 1.00000)
layer 311 "Accent": OK procedural solid tint=(0.20000, 0.40000, 0.60000)
"""
        metrics = benchmark.solid_runtime_metrics(preview_log)
        self.assertTrue(metrics["has_count_evidence"])
        self.assertEqual(metrics["loaded"], 2)
        self.assertEqual(metrics["candidates"], 3)
        self.assertEqual(metrics["loaded_ratio"], 2 / 3)
        self.assertEqual(metrics["loaded_layer_ids"], [13, 311])
        self.assertEqual(
            benchmark.solid_runtime_failures({
                "expected_solid_candidates": 3,
                "required_solid_loaded_layer_ids": [13, 311],
            }, metrics),
            [],
        )
        self.assertEqual(
            benchmark.solid_runtime_failures({
                "expected_solid_candidates": 4,
                "required_solid_loaded_layer_ids": [551],
            }, metrics),
            [
                "solid layer candidate count mismatch",
                "solid layer 551 should be loaded",
            ],
        )
        self.assertEqual(
            benchmark.solid_runtime_failures(
                {"expected_solid_candidates": 0},
                benchmark.solid_runtime_metrics("loaded: 2 / 2\n"),
            ),
            ["solid layer count evidence missing"],
        )

    def test_puppet_animation_runtime_metrics_and_exact_gates(self) -> None:
        preview_log = """Scene preview texture load report
layer 21 "Body": OK 1920x1080 puppet animation OK MDLV0023 mode=disjoint-additive ids=275,280,282 clips=3 rate=1.000
layer 44 "Arm": OK 512x512 puppet animation OK MDLV0023 mode=disjoint-additive ids=271,356 clips=2 rate=1.000
layer 157 "Tail": OK 1024x1024 puppet animation OK MDLV0023 mode=single-absolute ids=174 clips=1 rate=1.000
"""
        metrics = benchmark.puppet_animation_runtime_metrics(preview_log)
        self.assertEqual(metrics["layer_ids"], [21, 44, 157])
        self.assertEqual(metrics["disjoint_additive_layer_ids"], [21, 44])
        self.assertEqual(metrics["clip_count"], 6)
        self.assertEqual(metrics["entries"][0], {
            "layer_id": 21,
            "mode": "disjoint-additive",
            "animation_ids": [275, 280, 282],
            "clip_count": 3,
        })
        sample = {
            "expected_puppet_animation_layer_ids": [157, 44, 21],
            "expected_puppet_disjoint_additive_layer_ids": [44, 21],
            "expected_puppet_animation_clip_count": 6,
        }
        self.assertEqual(
            benchmark.puppet_animation_runtime_failures(sample, metrics),
            [],
        )
        self.assertEqual(
            benchmark.puppet_animation_runtime_failures(
                {
                    "expected_puppet_animation_layer_ids": [21, 157],
                    "expected_puppet_disjoint_additive_layer_ids": [21],
                    "expected_puppet_animation_clip_count": 5,
                },
                metrics,
            ),
            [
                "puppet animation layer IDs mismatch",
                "puppet disjoint-additive layer IDs mismatch",
                "puppet animation clip count mismatch",
            ],
        )

    def test_particle_runtime_fixture_metrics_and_optional_gates(self) -> None:
        preview_log = """Scene preview texture load report
loaded: 20 / 24
text loaded: 10 / 10
particle loaded: 3 / 4
particle refract loaded: 2
particle initial live: 96
particle authored: 5
particle visible: 3
particle layer 200 "Snow": OK 64x64 blend=additive initial=32 perspective=false
particle layer 201 "Bird": OK 64x64 blend=translucent initial=64 perspective=true
particle skipped hidden: 2
particle skipped transparent: 1
"""
        metrics = benchmark.particle_runtime_metrics(preview_log)
        self.assertTrue(metrics["has_load_evidence"])
        self.assertTrue(metrics["has_initial_live_evidence"])
        self.assertEqual(metrics["loaded"], 3)
        self.assertEqual(metrics["candidates"], 4)
        self.assertEqual(metrics["loaded_ratio"], 0.75)
        self.assertTrue(metrics["has_refract_evidence"])
        self.assertEqual(metrics["refract_loaded"], 2)
        self.assertEqual(metrics["initial_live"], 96)
        self.assertEqual(metrics["authored"], 5)
        self.assertEqual(metrics["visible"], 3)
        self.assertEqual(metrics["skipped_hidden"], 2)
        self.assertEqual(metrics["skipped_transparent"], 1)
        self.assertTrue(metrics["has_transparent_evidence"])
        self.assertEqual(metrics["loaded_layer_ids"], [200, 201])
        self.assertEqual(
            benchmark.particle_runtime_failures({
                "minimum_particle_loaded": 3,
                "expected_particle_candidates": 4,
                "minimum_particle_initial_live": 96,
                "expected_particle_authored": 5,
                "expected_particle_visible": 3,
                "expected_particle_skipped_hidden": 2,
                "expected_particle_skipped_transparent": 1,
                "expected_particle_refract_loaded": 2,
                "required_particle_loaded_layer_ids": [200, 201],
            }, metrics),
            [],
        )
        self.assertEqual(
            benchmark.particle_runtime_failures({
                "minimum_particle_loaded": 4,
                "expected_particle_candidates": 5,
                "minimum_particle_initial_live": 97,
                "expected_particle_authored": 4,
                "expected_particle_visible": 4,
                "expected_particle_skipped_hidden": 1,
                "expected_particle_refract_loaded": 3,
                "required_particle_loaded_layer_ids": [202],
            }, metrics),
            [
                "particle loaded count below minimum",
                "particle candidate count mismatch",
                "particle initial live count below minimum",
                "particle authored count mismatch",
                "particle visible count mismatch",
                "particle skipped_hidden count mismatch",
                "particle layer 202 should be loaded",
                "particle refract loaded count mismatch",
            ],
        )

    def test_utility_runtime_fixture_preserves_distinct_dispositions(self) -> None:
        preview_log = """Scene preview texture load report
utilityLayerCount: 3
utilityCapturePlannedCount: 1
utilityDependencyEdgeCount: 0
utilityNamedConsumerCount: 0
utilityNamedTargetPlannedCount: 0
utilityNamedBindingPlannedCount: 0
utilityNamedTargetGapCount: 0
utility layer 187: capture kind=project
utility layer 96: unsupportedEffects kind=composition
utility layer 763: skippedHidden kind=composition
"""
        metrics = benchmark.utility_runtime_metrics(preview_log)
        self.assertTrue(metrics["has_evidence"])
        self.assertEqual(metrics["candidates"], 3)
        self.assertEqual(metrics["capture_planned"], 1)
        self.assertEqual(metrics["named_consumers"], 0)
        self.assertEqual(metrics["named_target_planned"], 0)
        self.assertEqual(metrics["named_binding_planned"], 0)
        self.assertEqual(
            benchmark.utility_runtime_failures({
                "expected_utility_candidates": 3,
                "expected_utility_capture_planned": 1,
                "expected_utility_dependency_edges": 0,
                "expected_utility_named_consumers": 0,
                "expected_utility_named_target_planned": 0,
                "expected_utility_named_binding_planned": 0,
                "expected_utility_named_target_gaps": 0,
                "required_utility_dispositions": {
                    "187": "capture",
                    "96": "unsupportedEffects",
                    "763": "skippedHidden",
                },
            }, metrics),
            [],
        )
        self.assertEqual(
            benchmark.utility_runtime_failures({
                "expected_utility_capture_planned": 2,
                "required_utility_dispositions": {"96": "capture"},
            }, metrics),
            [
                "utility capture_planned mismatch",
                "utility layer 96 disposition should be capture",
            ],
        )

    def test_utility_capture_execution_preserves_failure_after_success(self) -> None:
        metrics = benchmark.utility_capture_execution_metrics(
            "phase=utility-capture layer=530 status=failed\n"
            "phase=utility-capture layer=530 status=succeeded\n"
            "phase=utility-capture layer=410 status=failed\n"
        )
        self.assertEqual(metrics["succeeded_layer_ids"], [530])
        self.assertEqual(metrics["failed_layer_ids"], [410, 530])

    def test_authored_effect_graph_execution_is_a_strict_layer_gate(self) -> None:
        metrics = benchmark.authored_effect_graph_execution_metrics(
            "phase=authored-effect-graph layer=68 status=failed\n"
            "phase=authored-effect-graph layer=68 status=succeeded\n"
            "phase=authored-effect-graph layer=76 status=succeeded\n"
        )
        self.assertEqual(metrics["succeeded_layer_ids"], [68, 76])
        self.assertEqual(metrics["failed_layer_ids"], [68])
        self.assertIn(
            "authored effect graph layer 68 failed",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_succeeded_layer_ids": [68, 76]},
                metrics,
                [],
                None,
            ),
        )
        self.assertIn(
            "authored effect graph succeeded layer IDs mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_succeeded_layer_ids": [68]},
                metrics,
                [],
                None,
            ),
        )

    def test_authored_effect_graph_legacy_blur_block_is_an_exact_gate(self) -> None:
        preview = "authoredEffectGraphLegacyBlurBlockedLayerIDs: 20,36\n"
        blocked = benchmark.authored_effect_graph_legacy_blur_blocked_layer_ids(preview)
        self.assertEqual(blocked, [20, 36])
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_legacy_blur_blocked_layer_ids": [20, 36]},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                blocked,
                None,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph legacy blur blocked layer IDs mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_legacy_blur_blocked_layer_ids": [20]},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                blocked,
                None,
            ),
        )

    def test_authored_local_contrast_count_is_an_exact_gate(self) -> None:
        preview = "authoredEffectGraphLocalContrastCount: 2\n"
        count = benchmark.authored_effect_graph_local_contrast_count(preview)
        self.assertEqual(count, 2)
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_local_contrast_count": 2},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Local Contrast count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_local_contrast_count": 0},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                count,
            ),
        )

    def test_authored_workshop_shadow_count_is_an_exact_gate(self) -> None:
        preview = "authoredEffectGraphWorkshopShadowCount: 1\n"
        count = benchmark.authored_effect_graph_workshop_shadow_count(preview)
        self.assertEqual(count, 1)
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_workshop_shadow_count": 1},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                workshop_shadow_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Workshop Shadow count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_workshop_shadow_count": 0},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                workshop_shadow_count=count,
            ),
        )

    def test_authored_spin_count_is_an_exact_gate(self) -> None:
        preview = "authoredEffectGraphSpinCount: 1\n"
        count = benchmark.authored_effect_graph_spin_count(preview)
        self.assertEqual(count, 1)
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_spin_count": 1},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                spin_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Spin count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_spin_count": 0},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                spin_count=count,
            ),
        )

    def test_authored_procedural_noise_count_is_an_exact_gate(self) -> None:
        preview = "authoredEffectGraphProceduralNoiseCount: 3\n"
        count = benchmark.authored_effect_graph_procedural_noise_count(preview)
        self.assertEqual(count, 3)
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_procedural_noise_count": 3},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                procedural_noise_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Procedural Noise count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_procedural_noise_count": 0},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                procedural_noise_count=count,
            ),
        )

    def test_authored_film_grain_count_is_an_exact_gate(self) -> None:
        preview = "authoredEffectGraphFilmGrainCount: 1\n"
        count = benchmark.authored_effect_graph_film_grain_count(preview)
        self.assertEqual(count, 1)
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_film_grain_count": 1},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                film_grain_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Film Grain count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_film_grain_count": 0},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                film_grain_count=count,
            ),
        )

    def test_authored_light_shafts_count_is_an_exact_gate(self) -> None:
        preview = "authoredEffectGraphLightShaftsCount: 2\n"
        count = benchmark.authored_effect_graph_light_shafts_count(preview)
        self.assertEqual(count, 2)
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_light_shafts_count": 2},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                light_shafts_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Light Shafts count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_light_shafts_count": 0},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                light_shafts_count=count,
            ),
        )
        self.assertIsNone(benchmark.authored_effect_graph_light_shafts_count(""))

    def test_authored_shake_count_is_an_exact_gate(self) -> None:
        preview = "authoredEffectGraphShakeCount: 3\n"
        count = benchmark.authored_effect_graph_shake_count(preview)
        self.assertEqual(count, 3)
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_shake_count": 3},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                shake_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Shake count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_shake_count": 0},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                shake_count=count,
            ),
        )
        self.assertIsNone(benchmark.authored_effect_graph_shake_count(""))

    def test_authored_water_flow_count_is_an_exact_gate(self) -> None:
        preview = "authoredEffectGraphWaterFlowCount: 2\n"
        count = benchmark.authored_effect_graph_water_flow_count(preview)
        self.assertEqual(count, 2)
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_water_flow_count": 2},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                water_flow_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Water Flow count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_water_flow_count": 0},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                water_flow_count=count,
            ),
        )
        self.assertIsNone(benchmark.authored_effect_graph_water_flow_count(""))

    def test_authored_water_waves_count_is_an_exact_gate(self) -> None:
        preview = "authoredEffectGraphWaterWavesCount: 4\n"
        count = benchmark.authored_effect_graph_water_waves_count(preview)
        self.assertEqual(count, 4)
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_water_waves_count": 4},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                water_waves_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Water Waves count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_water_waves_count": 0},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                water_waves_count=count,
            ),
        )
        self.assertIsNone(benchmark.authored_effect_graph_water_waves_count(""))

    def test_authored_water_caustics_count_is_an_exact_gate(self) -> None:
        preview = "authoredEffectGraphWaterCausticsCount: 4\n"
        count = benchmark.authored_effect_graph_water_caustics_count(preview)
        self.assertEqual(count, 4)
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_water_caustics_count": 4},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                water_caustics_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Water Caustics count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_water_caustics_count": 0},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                water_caustics_count=count,
            ),
        )
        self.assertIsNone(benchmark.authored_effect_graph_water_caustics_count(""))

    def test_authored_cursor_ripple_count_is_an_exact_gate(self) -> None:
        preview = (
            "authoredEffectGraphCursorRippleCount: 3\n"
            "authoredEffectGraphCursorRippleIsolatedCount: 2\n"
            "authoredEffectGraphCursorRippleOmittedEffects: "
            "layer=1,omitted=effects/blend/effect.json;"
            "layer=2,omitted=effects/reflection/effect.json\n"
        )
        count = benchmark.authored_effect_graph_cursor_ripple_count(preview)
        self.assertEqual(count, 3)
        self.assertEqual(
            benchmark.authored_effect_graph_cursor_ripple_isolated_count(preview),
            2,
        )
        self.assertEqual(
            benchmark.authored_effect_graph_cursor_ripple_omitted_effects(preview),
            [
                "layer=1,omitted=effects/blend/effect.json",
                "layer=2,omitted=effects/reflection/effect.json",
            ],
        )
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_cursor_ripple_count": 3},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                cursor_ripple_count=count,
                cursor_ripple_isolated_count=2,
                cursor_ripple_omitted_effects=[
                    "layer=1,omitted=effects/blend/effect.json",
                    "layer=2,omitted=effects/reflection/effect.json",
                ],
            ),
            [],
        )
        self.assertIn(
            "Cursor Ripple count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_cursor_ripple_count": 0},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                cursor_ripple_count=count,
            )[0],
        )
        self.assertIn(
            "isolated Cursor Ripple count mismatch",
            benchmark.authored_effect_graph_failures(
                {
                    "expected_authored_effect_graph_cursor_ripple_isolated_count": 1
                },
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                cursor_ripple_isolated_count=2,
            )[0],
        )
        self.assertIn(
            "Cursor Ripple omissions mismatch",
            benchmark.authored_effect_graph_failures(
                {
                    "expected_authored_effect_graph_cursor_ripple_omitted_effects": [
                        "layer=1,omitted=effects/blend/effect.json"
                    ]
                },
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                cursor_ripple_omitted_effects=[],
            )[0],
        )
        self.assertIsNone(benchmark.authored_effect_graph_cursor_ripple_count(""))
        self.assertIsNone(
            benchmark.authored_effect_graph_cursor_ripple_isolated_count("")
        )
        self.assertIsNone(
            benchmark.authored_effect_graph_cursor_ripple_omitted_effects("")
        )

    def test_authored_shine_count_is_an_exact_gate(self) -> None:
        preview = (
            "authoredEffectGraphShineCount: 4\n"
            "authoredEffectGraphShineIsolatedCount: 1\n"
            "authoredEffectGraphShineOmittedEffects: "
            "layer=59,omitted=effects/shake/effect.json;"
            "layer=59,omitted=effects/shine/effect.json\n"
        )
        omissions = [
            "layer=59,omitted=effects/shake/effect.json",
            "layer=59,omitted=effects/shine/effect.json",
        ]
        self.assertEqual(benchmark.authored_effect_graph_shine_count(preview), 4)
        self.assertEqual(
            benchmark.authored_effect_graph_shine_isolated_count(preview), 1
        )
        self.assertEqual(
            benchmark.authored_effect_graph_shine_omitted_effects(preview),
            omissions,
        )
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {
                    "expected_authored_effect_graph_shine_count": 4,
                    "expected_authored_effect_graph_shine_isolated_count": 1,
                    "expected_authored_effect_graph_shine_omitted_effects": omissions,
                },
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                shine_count=4,
                shine_isolated_count=1,
                shine_omitted_effects=omissions,
            ),
            [],
        )
        for sample, arguments, message in (
            (
                {"expected_authored_effect_graph_shine_count": 0},
                {"shine_count": 4},
                "Shine count mismatch",
            ),
            (
                {"expected_authored_effect_graph_shine_isolated_count": 0},
                {"shine_isolated_count": 1},
                "isolated Shine count mismatch",
            ),
            (
                {"expected_authored_effect_graph_shine_omitted_effects": []},
                {"shine_omitted_effects": omissions},
                "Shine omissions mismatch",
            ),
        ):
            self.assertIn(
                message,
                benchmark.authored_effect_graph_failures(
                    sample,
                    {"succeeded_layer_ids": [], "failed_layer_ids": []},
                    [],
                    None,
                    **arguments,
                )[0],
            )
        self.assertIsNone(benchmark.authored_effect_graph_shine_count(""))
        self.assertIsNone(
            benchmark.authored_effect_graph_shine_isolated_count("")
        )
        self.assertIsNone(
            benchmark.authored_effect_graph_shine_omitted_effects("")
        )

    def test_interactive_effect_counts_are_exact_gates(self) -> None:
        preview = (
            "authoredEffectGraphFoliageSwayCount: 3\n"
            "authoredEffectGraphWaterRippleCount: 2\n"
            "authoredEffectGraphDepthParallaxCount: 4\n"
            "authoredEffectGraphIrisInlineSuffixCount: 1\n"
        )
        self.assertEqual(
            benchmark.authored_effect_graph_foliage_sway_count(preview), 3
        )
        self.assertEqual(
            benchmark.authored_effect_graph_water_ripple_count(preview), 2
        )
        self.assertEqual(
            benchmark.authored_effect_graph_depth_parallax_count(preview), 4
        )
        self.assertEqual(
            benchmark.authored_effect_graph_iris_inline_suffix_count(preview), 1
        )
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {
                    "expected_authored_effect_graph_foliage_sway_count": 3,
                    "expected_authored_effect_graph_water_ripple_count": 2,
                    "expected_authored_effect_graph_depth_parallax_count": 4,
                    "expected_authored_effect_graph_iris_inline_suffix_count": 1,
                },
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                foliage_sway_count=3,
                water_ripple_count=2,
                depth_parallax_count=4,
                iris_inline_suffix_count=1,
            ),
            [],
        )
        failures = benchmark.authored_effect_graph_failures(
            {
                "expected_authored_effect_graph_foliage_sway_count": 0,
                "expected_authored_effect_graph_water_ripple_count": 0,
                "expected_authored_effect_graph_depth_parallax_count": 0,
                "expected_authored_effect_graph_iris_inline_suffix_count": 0,
            },
            {"succeeded_layer_ids": [], "failed_layer_ids": []},
            [],
            None,
            foliage_sway_count=3,
            water_ripple_count=2,
            depth_parallax_count=4,
            iris_inline_suffix_count=1,
        )
        self.assertIn("authored effect graph Foliage Sway count mismatch", failures)
        self.assertIn("authored effect graph Water Ripple count mismatch", failures)
        self.assertIn(
            "authored effect graph Depth Parallax count mismatch",
            failures,
        )
        self.assertIn(
            "authored effect graph Iris inline suffix count mismatch", failures
        )
        self.assertIsNone(benchmark.authored_effect_graph_foliage_sway_count(""))
        self.assertIsNone(benchmark.authored_effect_graph_water_ripple_count(""))
        self.assertIsNone(
            benchmark.authored_effect_graph_depth_parallax_count("")
        )
        self.assertIsNone(
            benchmark.authored_effect_graph_iris_inline_suffix_count("")
        )

    def test_authored_clipping_mask_count_is_an_exact_gate(self) -> None:
        preview = "authoredEffectGraphClippingMaskCount: 7\n"
        count = benchmark.authored_effect_graph_clipping_mask_count(preview)
        self.assertEqual(count, 7)
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_clipping_mask_count": 7},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                clipping_mask_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Clipping Mask count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_clipping_mask_count": 0},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                clipping_mask_count=count,
            ),
        )
        self.assertIsNone(benchmark.authored_effect_graph_clipping_mask_count(""))

    def test_authored_blend_count_is_an_exact_gate(self) -> None:
        preview = "authoredEffectGraphBlendCount: 1\n"
        count = benchmark.authored_effect_graph_blend_count(preview)
        self.assertEqual(count, 1)
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_blend_count": 1},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                blend_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Blend count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_blend_count": 0},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                blend_count=count,
            ),
        )
        self.assertIsNone(benchmark.authored_effect_graph_blend_count(""))

    def test_authored_transform_contract_is_an_exact_gate(self) -> None:
        diagnostics = [
            "layer=65,effect=2,pass=0,constant=scale,"
            "reason=unsupported-dynamic-binding-static-fallback",
            "layer=161,effect=2,pass=0,constant=scale,"
            "reason=unsupported-dynamic-binding-static-fallback",
        ]
        preview = (
            "authoredEffectGraphTransformCount: 2\n"
            "authoredEffectGraphTransformStaticFallbackCount: 2\n"
            "authoredEffectGraphTransformStaticFallbackDiagnostics: "
            + ";".join(diagnostics)
            + "\n"
        )
        count = benchmark.authored_effect_graph_transform_count(preview)
        fallback_count = (
            benchmark.authored_effect_graph_transform_static_fallback_count(preview)
        )
        parsed_diagnostics = (
            benchmark.authored_effect_graph_transform_static_fallback_diagnostics(
                preview
            )
        )
        self.assertEqual(count, 2)
        self.assertEqual(fallback_count, 2)
        self.assertEqual(parsed_diagnostics, diagnostics)
        sample = {
            "expected_authored_effect_graph_transform_count": 2,
            "expected_authored_effect_graph_transform_static_fallback_count": 2,
            "expected_authored_effect_graph_transform_static_fallback_diagnostics": (
                diagnostics
            ),
        }
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                sample,
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                transform_count=count,
                transform_static_fallback_count=fallback_count,
                transform_static_fallback_diagnostics=parsed_diagnostics,
            ),
            [],
        )
        failures = benchmark.authored_effect_graph_failures(
            sample,
            {"succeeded_layer_ids": [], "failed_layer_ids": []},
            [],
            None,
            transform_count=1,
            transform_static_fallback_count=1,
            transform_static_fallback_diagnostics=None,
        )
        self.assertIn(
            "authored effect graph Transform count mismatch",
            failures,
        )
        self.assertIn(
            "authored effect graph Transform static fallback count mismatch",
            failures,
        )
        self.assertIn(
            "authored effect graph Transform static fallback diagnostics mismatch",
            failures,
        )
        self.assertIsNone(benchmark.authored_effect_graph_transform_count(""))
        self.assertIsNone(
            benchmark.authored_effect_graph_transform_static_fallback_count("")
        )
        self.assertIsNone(
            benchmark.authored_effect_graph_transform_static_fallback_diagnostics("")
        )
        self.assertEqual(
            benchmark.authored_effect_graph_transform_static_fallback_diagnostics(
                "authoredEffectGraphTransformStaticFallbackDiagnostics: \n"
            ),
            [],
        )

    def test_full_matrix_generator_preserves_exact_authored_backend_counts(self) -> None:
        evidence = {
            metric: 0 for metric in matrix_generator.RUNTIME_EVIDENCE_METRICS
        }
        evidence.update({
            "shader_contract_aggregate_sha256": "a" * 64,
            "effect_graph_sha256": "b" * 64,
            "stock_opacity_single_effect_candidate_layer_ids": [],
        })
        runtime: defaultdict[str, object] = defaultdict(int)
        runtime["runtime_evidence"] = evidence
        expected_counts = {
            "authored_effect_graph_color_key_count": 1,
            "authored_effect_graph_spin_count": 2,
            "authored_effect_graph_procedural_noise_count": 3,
            "authored_effect_graph_film_grain_count": 4,
            "authored_effect_graph_light_shafts_count": 5,
            "authored_effect_graph_blend_count": 6,
            "authored_effect_graph_tint_count": 7,
            "authored_effect_graph_pulse_count": 8,
            "authored_effect_graph_godrays_count": 9,
            "authored_effect_graph_transform_count": 10,
            "authored_effect_graph_transform_static_fallback_count": 2,
            "authored_effect_graph_transform_static_fallback_diagnostics": [
                "fixture"
            ],
            "authored_effect_graph_authored_shader_count": 11,
            "authored_effect_graph_scroll_count": 12,
            "authored_effect_graph_iris_inline_suffix_count": 1,
        }
        runtime.update(expected_counts)
        sample = matrix_generator.matrix_sample(
            {
                "id": "fixture",
                "title": "Fixture",
                "package_file": "scene.pkg",
                "hashes": {"project_sha256": "c" * 64, "package_sha256": "d" * 64},
                "runtime": runtime,
            },
            {"capabilities": ["fixture"]},
        )
        for metric, expected in expected_counts.items():
            self.assertEqual(sample[f"expected_{metric}"], expected)

    def test_full_matrix_generator_tracks_scene_script_audio_bars_contract(self) -> None:
        evidence = {
            metric: 0 for metric in matrix_generator.RUNTIME_EVIDENCE_METRICS
        }
        evidence.update({
            "shader_contract_aggregate_sha256": "a" * 64,
            "effect_graph_sha256": "b" * 64,
            "stock_opacity_single_effect_candidate_layer_ids": [],
        })
        runtime: defaultdict[str, object] = defaultdict(int)
        plan = {
            "layer_id": 112,
            "host": "visible",
            "source_sha256":
                "e6ff1bbde3ab348731a5ba35f757f8f0fc97fd70a117dd7e74eaffe98026b149",
            "bar_count": 64,
            "audio_resolution": 64,
            "channel": "average",
            "model_path": "models/workshop/2727665642/bar.json",
            "material_path": "materials/workshop/2727665642/bar.json",
            "texture_path": "workshop/2727665642/bar",
            "width_multiplier": 2.5,
            "height_multiplier": 50.0,
            "depth_multiplier": 0.0,
            "x_step": 20.0,
            "y_step": 0.0,
            "angle_degrees": 0.0,
            "alignment": "centre",
            "first_step": "ownerAtBaseOrigin",
        }
        runtime.update({
            "runtime_evidence": evidence,
            "scene_script_audio_bars_plan_count": 1,
            "scene_script_audio_bars_diagnostic_count": 0,
            "scene_script_audio_bars_has_audio_consumer": True,
            "scene_script_audio_bars_total_bar_count": 64,
            "scene_script_audio_bars_plan_layer_ids": [112],
            "scene_script_audio_bars_plans": [plan],
            "scene_script_audio_bars_succeeded_layer_ids": [112],
        })
        sample = matrix_generator.matrix_sample(
            {
                "id": "fixture",
                "title": "Fixture",
                "package_file": "scene.pkg",
                "hashes": {
                    "project_sha256": "c" * 64,
                    "package_sha256": "d" * 64,
                },
                "runtime": runtime,
            },
            {"capabilities": ["fixture"]},
        )
        self.assertEqual(
            {
                key: sample[key]
                for key in matrix_generator.SCENE_SCRIPT_AUDIO_BARS_EXPECTATIONS
            },
            {
                "expected_scene_script_audio_bars_plan_count": 1,
                "expected_scene_script_audio_bars_diagnostic_count": 0,
                "expected_scene_script_audio_bars_has_audio_consumer": True,
                "expected_scene_script_audio_bars_total_bar_count": 64,
                "expected_scene_script_audio_bars_plan_layer_ids": [112],
                "expected_scene_script_audio_bars_plans": [plan],
                "expected_scene_script_audio_bars_succeeded_layer_ids": [112],
                "required_scene_script_audio_bars_succeeded_layer_ids": [112],
            },
        )
        self.assertEqual(
            sample["capabilities"],
            ["fixture", "scene_script_audio_bars"],
        )
        self.assertIn("scene_script_audio_bars", matrix_generator.capabilities(runtime))

    def test_tracked_full_matrix_closes_transform_and_light_shafts_contracts(self) -> None:
        matrix = json.loads(
            (SCRIPT_DIR / "scene_wallpaper_full_sample_matrix.json").read_text(
                encoding="utf-8"
            )
        )
        samples = matrix["samples"]
        self.assertEqual(len(samples), 45)
        for sample in samples:
            with self.subTest(sample_id=sample["id"]):
                self.assertIn(
                    "expected_authored_effect_graph_transform_count",
                    sample,
                )
                self.assertIn(
                    "expected_authored_effect_graph_transform_static_fallback_count",
                    sample,
                )
                self.assertIn(
                    "expected_authored_effect_graph_transform_static_fallback_diagnostics",
                    sample,
                )
                self.assertIn(
                    "expected_authored_effect_graph_light_shafts_count",
                    sample,
                )

    def test_tracked_full_matrix_gates_scene_script_audio_bars_profiles(self) -> None:
        matrix = json.loads(
            (SCRIPT_DIR / "scene_wallpaper_full_sample_matrix.json").read_text(
                encoding="utf-8"
            )
        )
        samples = {sample["id"]: sample for sample in matrix["samples"]}
        expected_plans = {
            "2241938645": {
                "layer_id": 282,
                "host": "visible",
                "source_sha256":
                    "2d874f553bef33dfd4650b1d38630148ccf52940bb6b542f46860411aa5d9379",
                "bar_count": 64,
                "audio_resolution": 64,
                "channel": "average",
                "model_path": "models/workshop/2079954552/bar.json",
                "material_path": "materials/workshop/2079954552/bar.json",
                "texture_path": "workshop/2079954552/bar",
                "width_multiplier": 1.0,
                "height_multiplier": 50.0,
                "depth_multiplier": 1.0,
                "x_step": 5.6,
                "y_step": 11.3,
                "angle_degrees": 60.0,
                "alignment": "centre",
                "first_step": "advanceBeforeFirstBar",
            },
            "3743305891": {
                "layer_id": 112,
                "host": "visible",
                "source_sha256":
                    "e6ff1bbde3ab348731a5ba35f757f8f0fc97fd70a117dd7e74eaffe98026b149",
                "bar_count": 64,
                "audio_resolution": 64,
                "channel": "average",
                "model_path": "models/workshop/2727665642/bar.json",
                "material_path": "materials/workshop/2727665642/bar.json",
                "texture_path": "workshop/2727665642/bar",
                "width_multiplier": 2.5,
                "height_multiplier": 50.0,
                "depth_multiplier": 0.0,
                "x_step": 20.0,
                "y_step": 0.0,
                "angle_degrees": 0.0,
                "alignment": "centre",
                "first_step": "ownerAtBaseOrigin",
            },
        }
        for sample_id, expected_plan in expected_plans.items():
            with self.subTest(sample_id=sample_id):
                sample = samples[sample_id]
                layer_id = expected_plan["layer_id"]
                self.assertEqual(
                    sample["expected_scene_script_audio_bars_plan_count"],
                    1,
                )
                self.assertEqual(
                    sample["expected_scene_script_audio_bars_diagnostic_count"],
                    0,
                )
                self.assertTrue(
                    sample["expected_scene_script_audio_bars_has_audio_consumer"]
                )
                self.assertEqual(
                    sample["expected_scene_script_audio_bars_total_bar_count"],
                    64,
                )
                self.assertEqual(
                    sample["expected_scene_script_audio_bars_plan_layer_ids"],
                    [layer_id],
                )
                self.assertEqual(
                    sample["expected_scene_script_audio_bars_plans"],
                    [expected_plan],
                )
                self.assertEqual(
                    sample[
                        "expected_scene_script_audio_bars_succeeded_layer_ids"
                    ],
                    [layer_id],
                )
                self.assertEqual(
                    sample[
                        "required_scene_script_audio_bars_succeeded_layer_ids"
                    ],
                    [layer_id],
                )
                self.assertIn("scene_script_audio_bars", sample["capabilities"])

    def test_authored_shader_count_is_an_exact_gate(self) -> None:
        preview = "authoredEffectGraphAuthoredShaderCount: 1\n"
        count = benchmark.authored_effect_graph_authored_shader_count(preview)
        self.assertEqual(count, 1)
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_authored_shader_count": 1},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                authored_shader_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph authored shader count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_authored_shader_count": 0},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                authored_shader_count=count,
            ),
        )
        self.assertIsNone(benchmark.authored_effect_graph_authored_shader_count(""))

    def test_scroll_count_is_an_exact_gate(self) -> None:
        preview = "authoredEffectGraphScrollCount: 30\n"
        count = benchmark.authored_effect_graph_scroll_count(preview)
        self.assertEqual(count, 30)
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_scroll_count": 30},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                scroll_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Scroll count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_scroll_count": 0},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                scroll_count=count,
            ),
        )
        self.assertIsNone(benchmark.authored_effect_graph_scroll_count(""))

    def test_authored_opacity_and_route_only_counts_are_exact_gates(self) -> None:
        preview = (
            "authoredEffectGraphOpacityCount: 4\n"
            "authoredEffectGraphColorKeyCount: 2\n"
            "authoredEffectGraphWorkshopShiftHueCount: 3\n"
            "authoredEffectGraphWorkshopAudioBarsCount: 2\n"
            "authoredEffectGraphFisheyeZeroDistortionCount: 1\n"
            "authoredEffectGraphWorkshopGradientCount: 2\n"
            "authoredEffectGraphWorkshopAudioHueShiftCount: 4\n"
            "layer 365: effect runtime opacity-authored; 1 declared pass(es)\n"
            "layer 372: effect runtime opacity-authored; 1 declared pass(es)\n"
            "layer 647: effect runtime opacity-authored; 1 declared pass(es)\n"
            "layer 664: effect runtime opacity-authored; 1 declared pass(es)\n"
            "layer 702: offscreen route-only\n"
            "layer 159: offscreen route-only\n"
            "layer 462: offscreen route-only\n"
        )
        opacity_count = benchmark.authored_effect_graph_opacity_count(preview)
        color_key_count = benchmark.authored_effect_graph_color_key_count(preview)
        shift_hue_count = benchmark.authored_effect_graph_workshop_shift_hue_count(preview)
        audio_bars_count = benchmark.authored_effect_graph_workshop_audio_bars_count(preview)
        fisheye_count = (
            benchmark.authored_effect_graph_fisheye_zero_distortion_count(preview)
        )
        gradient_count = benchmark.authored_effect_graph_workshop_gradient_count(preview)
        audio_hue_count = benchmark.authored_effect_graph_workshop_audio_hue_shift_count(preview)
        opacity_layers = benchmark.authored_effect_graph_opacity_layer_ids(preview)
        route_only_count = preview.count("offscreen route-only")
        self.assertEqual(opacity_count, 4)
        self.assertEqual(color_key_count, 2)
        self.assertEqual(shift_hue_count, 3)
        self.assertEqual(audio_bars_count, 2)
        self.assertEqual(fisheye_count, 1)
        self.assertEqual(gradient_count, 2)
        self.assertEqual(audio_hue_count, 4)
        self.assertEqual(opacity_layers, [365, 372, 647, 664])
        self.assertEqual(route_only_count, 3)
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {
                    "expected_authored_effect_graph_opacity_count": 4,
                    "expected_authored_effect_graph_color_key_count": 2,
                    "expected_authored_effect_graph_workshop_audio_bars_count": 2,
                    "expected_authored_effect_graph_fisheye_zero_distortion_count": 1,
                    "expected_authored_effect_graph_opacity_layer_ids":
                        [365, 372, 647, 664],
                    "expected_route_only_effect_count": 3,
                },
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                opacity_count=opacity_count,
                color_key_count=color_key_count,
                workshop_audio_bars_count=audio_bars_count,
                fisheye_zero_distortion_count=fisheye_count,
                route_only_effect_count=route_only_count,
                opacity_layer_ids=opacity_layers,
            ),
            [],
        )
        failures = benchmark.authored_effect_graph_failures(
            {
                "expected_authored_effect_graph_opacity_count": 0,
                "expected_authored_effect_graph_color_key_count": 0,
                "expected_authored_effect_graph_workshop_audio_bars_count": 0,
                "expected_authored_effect_graph_fisheye_zero_distortion_count": 0,
                "expected_authored_effect_graph_opacity_layer_ids": [],
                "expected_route_only_effect_count": 18,
            },
            {"succeeded_layer_ids": [], "failed_layer_ids": []},
            [],
            None,
            opacity_count=opacity_count,
            color_key_count=color_key_count,
            workshop_audio_bars_count=audio_bars_count,
            fisheye_zero_distortion_count=fisheye_count,
            route_only_effect_count=route_only_count,
            opacity_layer_ids=opacity_layers,
        )
        self.assertIn("authored effect graph Opacity count mismatch", failures)
        self.assertIn("authored effect graph Color Key count mismatch", failures)
        self.assertIn(
            "authored effect graph Workshop Audio Bars count mismatch",
            failures,
        )
        self.assertIn(
            "authored effect graph Fisheye Zero Distortion count mismatch",
            failures,
        )
        self.assertIn("authored effect graph Opacity layer IDs mismatch", failures)
        self.assertIn("offscreen route-only effect count mismatch", failures)
        self.assertIsNone(benchmark.authored_effect_graph_opacity_count(""))
        self.assertIsNone(benchmark.authored_effect_graph_color_key_count(""))
        self.assertIsNone(benchmark.authored_effect_graph_workshop_shift_hue_count(""))
        self.assertIsNone(benchmark.authored_effect_graph_workshop_audio_bars_count(""))
        self.assertIsNone(
            benchmark.authored_effect_graph_fisheye_zero_distortion_count("")
        )
        self.assertIsNone(benchmark.authored_effect_graph_workshop_gradient_count(""))
        self.assertIsNone(benchmark.authored_effect_graph_workshop_audio_hue_shift_count(""))
        self.assertEqual(benchmark.authored_effect_graph_opacity_layer_ids(""), [])

    def test_authored_effect_chain_counts_are_exact_gates(self) -> None:
        preview = (
            "authoredEffectGraphChainCount: 1\n"
            "authoredEffectGraphStageCount: 4\n"
        )
        metrics = benchmark.authored_effect_graph_chain_metrics(preview)
        self.assertEqual(metrics, {"chain_count": 1, "stage_count": 4})
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {
                    "expected_authored_effect_graph_chain_count": 1,
                    "expected_authored_effect_graph_stage_count": 4,
                },
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                metrics,
            ),
            [],
        )
        self.assertEqual(
            benchmark.authored_effect_graph_chain_metrics(""),
            {"chain_count": None, "stage_count": None},
        )
        self.assertIn(
            "authored effect graph chain count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_chain_count": 0},
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                metrics,
            ),
        )

    def test_effect_stage_admission_metrics_are_structured_and_conserved(self) -> None:
        coverage = (
            "inactive=1,complete=1,terminal-inline-prefix=0,"
            "terminal-inline-suffix=0,isolated-accepted=0,isolated-omitted=0,"
            "prefix-accepted=0,prefix-omitted=0,rejected-missing-graph=0,"
            "rejected-ambiguous-graph=0,rejected-chain=1,"
            "rejected-graph-mismatch=0,rejected-invariant=0"
        )
        preview = "\n".join([
            "authoredEffectGraphStageCount: 1",
            "authoredEffectStageDescriptorCount: 3",
            "authoredEffectStageParsedCount: 3",
            "authoredEffectStageActivityCounts: author-disabled=1,layer-hidden=0,active=2",
            "authoredEffectStageStrictAdmissionCounts: inactive=1,admitted-dedicated=1,admitted-generic=0,not-admitted=1",
            f"authoredEffectStageCoverageCounts: {coverage}",
            "authoredEffectStageDescriptorIdentityConserved: true",
            "authoredEffectStageActivityConserved: true",
            "authoredEffectStageInactiveAdmissionConserved: true",
            "authoredEffectStageActiveAdmissionConserved: true",
            "authoredEffectStageStrictIdentityConserved: true",
            "authoredEffectStageAdmission: layer=1 effect=0 descriptor=1%23effect%230 activity=author-disabled strict=inactive coverage=inactive backend=- profile=- reason=- path=effects/disabled/effect.json",
            "authoredEffectStageAdmission: layer=1 effect=1 descriptor=1%23effect%231 activity=active strict=admitted-dedicated coverage=complete backend=opacity profile=- reason=- path=effects/opacity/effect.json",
            "authoredEffectStageAdmission: layer=1 effect=2 descriptor=1%23effect%232 activity=active strict=not-admitted coverage=rejected-chain backend=- profile=- reason=unsupported-stage path=effects/unknown/effect.json",
        ])
        metrics = benchmark.authored_effect_stage_admission_metrics(preview)
        self.assertTrue(metrics["has_evidence"])
        self.assertEqual(metrics["schema_version"], 1)
        self.assertEqual(metrics["descriptor_count"], 3)
        self.assertEqual(metrics["parsed_count"], 3)
        self.assertEqual(metrics["activity_counts"]["active"], 2)
        self.assertEqual(metrics["strict_admission_counts"]["admitted-dedicated"], 1)
        self.assertEqual(metrics["records"][0]["descriptor_id"], "1#effect#0")
        self.assertEqual(metrics["validation_failures"], [])
        self.assertEqual(len(metrics["canonical_sha256"]), 64)
        self.assertEqual(
            benchmark.authored_effect_stage_admission_failures(
                {
                    "expected_effect_stage_admission_schema": 1,
                    "expected_effect_stage_descriptor_count": 3,
                    "expected_effect_stage_parsed_count": 3,
                    "expected_effect_stage_activity_counts": metrics[
                        "activity_counts"
                    ],
                    "expected_effect_stage_strict_admission_counts": metrics[
                        "strict_admission_counts"
                    ],
                    "expected_effect_stage_coverage_counts": metrics[
                        "coverage_counts"
                    ],
                    "expected_effect_stage_admission_sha256": metrics["canonical_sha256"],
                },
                metrics,
            ),
            [],
        )

        duplicate = preview.replace(
            "effect=2 descriptor=1%23effect%232",
            "effect=1 descriptor=1%23effect%231",
        )
        duplicate_metrics = benchmark.authored_effect_stage_admission_metrics(duplicate)
        self.assertIn(
            "effect stage admission identity duplicated",
            duplicate_metrics["validation_failures"],
        )

        invalid_combination = preview.replace(
            "strict=not-admitted coverage=rejected-chain backend=- profile=- reason=unsupported-stage",
            "strict=not-admitted coverage=complete backend=opacity profile=- reason=unsupported-stage",
        )
        invalid_combination_metrics = (
            benchmark.authored_effect_stage_admission_metrics(invalid_combination)
        )
        self.assertIn(
            "effect stage non-admitted state combination invalid",
            invalid_combination_metrics["validation_failures"],
        )

        missing_stage_count_metrics = benchmark.authored_effect_stage_admission_metrics(
            preview.replace("authoredEffectGraphStageCount: 1\n", "")
        )
        self.assertIn(
            "effect stage chain stage count missing",
            missing_stage_count_metrics["validation_failures"],
        )

        structural_rejection = preview.replace(
            "coverage=rejected-chain backend=- profile=- reason=unsupported-stage",
            "coverage=rejected-invariant backend=- profile=- reason=invalid-stage-identity",
        ).replace(
            "rejected-chain=1,rejected-graph-mismatch=0,rejected-invariant=0",
            "rejected-chain=0,rejected-graph-mismatch=0,rejected-invariant=1",
        )
        structural_metrics = benchmark.authored_effect_stage_admission_metrics(
            structural_rejection
        )
        self.assertIn(
            "effect stage admission structural rejection: rejected-invariant",
            structural_metrics["validation_failures"],
        )

    def test_effect_stage_admission_evidence_is_backward_compatible_until_expected(self) -> None:
        metrics = benchmark.authored_effect_stage_admission_metrics("")
        self.assertFalse(metrics["has_evidence"])
        self.assertIsNone(metrics["schema_version"])
        self.assertEqual(
            benchmark.authored_effect_stage_admission_failures({}, metrics),
            [],
        )
        self.assertEqual(
            benchmark.authored_effect_stage_admission_failures(
                {"expected_effect_stage_descriptor_count": 1},
                metrics,
            ),
            ["effect stage admission evidence missing"],
        )
        self.assertEqual(
            benchmark.authored_effect_stage_admission_failures(
                {},
                metrics,
                require_evidence=True,
            ),
            ["effect stage admission evidence missing"],
        )

    def test_effect_stage_compile_metrics_are_bounded_conserved_and_hashed(self) -> None:
        empty_preview = "\n".join([
            "authoredEffectStageCompileFailureCount: 0",
            "authoredEffectStageCompileFailureCodes: ",
            "authoredEffectStageCompilerProbeOutcomeCounts: ",
            "authoredEffectStageCompilerFailureCodes: ",
        ])
        empty = benchmark.authored_effect_stage_compile_metrics(empty_preview)
        self.assertTrue(empty["has_evidence"])
        self.assertEqual(empty["schema_version"], 1)
        self.assertEqual(empty["stage_failure_count"], 0)
        self.assertEqual(empty["stage_failure_code_counts"], {})
        self.assertEqual(
            empty["compiler_probe_outcome_counts"],
            {"not-applicable": 0, "rejected": 0},
        )
        self.assertEqual(empty["compiler_failure_code_counts"], {})
        self.assertEqual(empty["validation_failures"], [])
        self.assertEqual(len(empty["canonical_sha256"]), 64)

        preview = "\n".join([
            "authoredEffectStageCompileFailureCount: 2",
            "authoredEffectStageCompileFailureCodes: "
            "no-backend-accepted=1,stage-program-invariant=1",
            "authoredEffectStageCompilerProbeOutcomeCounts: "
            "not-applicable=33,rejected=2",
            "authoredEffectStageCompilerFailureCodes: "
            "authored-shader/material/material-texture-slot-unsupported=1,"
            "water-flow/compatibility/dedicated-profile-rejected=1",
        ])
        metrics = benchmark.authored_effect_stage_compile_metrics(preview)
        self.assertEqual(metrics["validation_failures"], [])
        self.assertEqual(metrics["stage_failure_count"], 2)
        self.assertEqual(
            metrics["compiler_probe_outcome_counts"],
            {"not-applicable": 33, "rejected": 2},
        )
        self.assertEqual(
            metrics["compiler_failure_code_counts"][
                "water-flow/compatibility/dedicated-profile-rejected"
            ],
            1,
        )
        reordered = preview.replace(
            "no-backend-accepted=1,stage-program-invariant=1",
            "stage-program-invariant=1,no-backend-accepted=1",
        ).replace(
            "not-applicable=33,rejected=2",
            "rejected=2,not-applicable=33",
        )
        self.assertEqual(
            benchmark.authored_effect_stage_compile_metrics(reordered)[
                "canonical_sha256"
            ],
            metrics["canonical_sha256"],
        )

    def test_effect_stage_compile_metrics_reject_partial_or_invalid_summaries(self) -> None:
        self.assertFalse(
            benchmark.authored_effect_stage_compile_metrics("")["has_evidence"]
        )
        partial = benchmark.authored_effect_stage_compile_metrics(
            "authoredEffectStageCompileFailureCount: 1\n"
        )
        self.assertIn(
            "effect stage compile summary missing, duplicated, or malformed",
            partial["validation_failures"],
        )

        duplicate = "\n".join([
            "authoredEffectStageCompileFailureCount: 1",
            "authoredEffectStageCompileFailureCount: 1",
            "authoredEffectStageCompileFailureCodes: no-backend-accepted=1",
            "authoredEffectStageCompilerProbeOutcomeCounts: rejected=1",
            "authoredEffectStageCompilerFailureCodes: "
            "water-flow/compatibility/dedicated-profile-rejected=1",
        ])
        self.assertIn(
            "effect stage compile summary missing, duplicated, or malformed",
            benchmark.authored_effect_stage_compile_metrics(duplicate)[
                "validation_failures"
            ],
        )

        invalid = "\n".join([
            "authoredEffectStageCompileFailureCount: 1",
            "authoredEffectStageCompileFailureCodes: no-backend-accepted=2",
            "authoredEffectStageCompilerProbeOutcomeCounts: "
            "not-applicable=35,rejected=2",
            "authoredEffectStageCompilerFailureCodes: "
            "water-flow/compatibility/dedicated-profile-rejected=1",
        ])
        failures = benchmark.authored_effect_stage_compile_metrics(invalid)[
            "validation_failures"
        ]
        self.assertIn("effect stage compile failure count mismatch", failures)
        self.assertIn("effect stage compiler rejection count mismatch", failures)
        self.assertIn("effect stage compiler probe count exceeds bound", failures)

        malformed = "\n".join([
            "authoredEffectStageCompileFailureCount: 1",
            "authoredEffectStageCompileFailureCodes: unknown-code=1",
            "authoredEffectStageCompilerProbeOutcomeCounts: rejected=1",
            "authoredEffectStageCompilerFailureCodes: "
            "water-flow/compatibility=1",
        ])
        malformed_failures = benchmark.authored_effect_stage_compile_metrics(
            malformed
        )["validation_failures"]
        self.assertIn(
            "effect stage compile failure code counts malformed",
            malformed_failures,
        )
        self.assertIn(
            "effect stage compile compiler failure code counts malformed",
            malformed_failures,
        )

    def test_effect_stage_admission_matrix_family_must_be_complete(self) -> None:
        coverage = (
            "inactive=0,complete=1,terminal-inline-prefix=0,"
            "terminal-inline-suffix=0,isolated-accepted=0,isolated-omitted=0,"
            "prefix-accepted=0,prefix-omitted=0,rejected-missing-graph=0,"
            "rejected-ambiguous-graph=0,rejected-chain=0,"
            "rejected-graph-mismatch=0,rejected-invariant=0"
        )
        preview = "\n".join([
            "authoredEffectGraphStageCount: 1",
            "authoredEffectStageDescriptorCount: 1",
            "authoredEffectStageParsedCount: 1",
            "authoredEffectStageActivityCounts: author-disabled=0,layer-hidden=0,active=1",
            "authoredEffectStageStrictAdmissionCounts: inactive=0,admitted-dedicated=1,admitted-generic=0,not-admitted=0",
            f"authoredEffectStageCoverageCounts: {coverage}",
            "authoredEffectStageDescriptorIdentityConserved: true",
            "authoredEffectStageActivityConserved: true",
            "authoredEffectStageInactiveAdmissionConserved: true",
            "authoredEffectStageActiveAdmissionConserved: true",
            "authoredEffectStageStrictIdentityConserved: true",
            "authoredEffectStageAdmission: layer=1 effect=0 descriptor=1%23effect%230 activity=active strict=admitted-dedicated coverage=complete backend=opacity profile=- reason=- path=effects/opacity/effect.json",
        ])
        metrics = benchmark.authored_effect_stage_admission_metrics(preview)
        self.assertEqual(metrics["validation_failures"], [])
        self.assertEqual(
            benchmark.authored_effect_stage_admission_failures(
                {"expected_effect_stage_admission_schema": 1},
                metrics,
            ),
            ["effect stage admission matrix contract incomplete"],
        )

    def test_effect_runtime_disposition_is_structured_joined_and_hashed(self) -> None:
        preview = effect_runtime_disposition_preview()
        admission = benchmark.authored_effect_stage_admission_metrics(preview)
        metrics = benchmark.effect_runtime_disposition_metrics(preview, admission)

        self.assertTrue(metrics["has_evidence"])
        self.assertEqual(metrics["schema_version"], 1)
        self.assertEqual(metrics["route_scope"], "effect-induced-static")
        self.assertEqual(metrics["record_count"], 12)
        self.assertEqual(metrics["group_count"], 7)
        self.assertTrue(all(
            group["scope"] == "effect-induced-static"
            for group in metrics["groups"]
        ))
        self.assertEqual(metrics["validation_failures"], [])
        self.assertEqual(len(metrics["canonical_sha256"]), 64)
        self.assertEqual(
            metrics["canonical_sha256"],
            hashlib.sha256(json.dumps(
                {
                    "groups": metrics["groups"],
                    "records": metrics["records"],
                },
                ensure_ascii=True,
                sort_keys=True,
                separators=(",", ":"),
            ).encode("utf-8")).hexdigest(),
        )
        records_by_kind = {
            record["kind"]: record for record in metrics["records"]
        }
        self.assertEqual(records_by_kind["inactive"]["group_id"], None)
        self.assertEqual(records_by_kind["strict-dedicated"]["role"], "owner")
        self.assertEqual(records_by_kind["strict-generic"]["role"], "owner")
        self.assertEqual(records_by_kind["strict-inline-suffix"]["role"], "owner")
        self.assertEqual(
            records_by_kind["omitted-by-strict-chain"]["role"],
            "member",
        )
        self.assertEqual(
            records_by_kind["legacy-coalesced-inline"]["attribution"],
            "layer-aggregate",
        )
        self.assertEqual(records_by_kind["route-only-member"]["role"], "member")
        self.assertEqual(records_by_kind["legacy-shadowed"]["role"], "member")
        self.assertEqual(records_by_kind["composite-refused"]["role"], "member")
        self.assertIn("unsupported", records_by_kind)

        migrated_preview = preview.replace(
            "strict-dedicated=1,strict-generic=1",
            "strict-dedicated=1,strict-generic=2",
        ).replace(
            "composite-refused=1,unsupported=1",
            "composite-refused=1,unsupported=0",
        ).replace(
            "exact-key=8,layer-aggregate=2,none=2",
            "exact-key=9,layer-aggregate=2,none=1",
        ).replace(
            "owner=5,aggregate-contributor=1,member=5,none=1",
            "owner=6,aggregate-contributor=1,member=4,none=1",
        ).replace(
            "inactive=1,direct=2,authored=1",
            "inactive=1,direct=1,authored=2",
        ).replace(
            "layer=7 scope=effect-induced-static kind=direct effects=1 owners=0",
            "layer=7 scope=effect-induced-static kind=authored effects=1 owners=1",
        ).replace(
            "kind=unsupported attribution=none family=unknown group=7 role=member reason=no-legacy-visual-route",
            "kind=strict-generic attribution=exact-key family=resolved-material group=7 role=owner reason=resolved-material-capability-owner",
        )
        migrated_metrics = benchmark.effect_runtime_disposition_metrics(
            migrated_preview
        )
        self.assertEqual(migrated_metrics["validation_failures"], [])
        migrated_record = next(
            record for record in migrated_metrics["records"]
            if record["layer_id"] == 7
        )
        self.assertEqual(migrated_record["kind"], "strict-generic")
        self.assertEqual(migrated_record["family"], "resolved-material")

        structural_preview = preview.replace(
            "legacy-structural-member=0,legacy-coalesced-inline=1,legacy-coalesced-offscreen=0,legacy-shadowed=1",
            "legacy-structural-member=1,legacy-coalesced-inline=1,legacy-coalesced-offscreen=0,legacy-shadowed=0",
        ).replace(
            "kind=legacy-shadowed attribution=exact-key family=blur group=5 role=member reason=shadowed-by-legacy-precedence",
            "kind=legacy-structural-member attribution=exact-key family=gradient-color group=5 role=member reason=shape-only-legacy-member",
        )
        structural_metrics = benchmark.effect_runtime_disposition_metrics(
            structural_preview
        )
        self.assertEqual(structural_metrics["validation_failures"], [])
        self.assertEqual(
            next(
                record for record in structural_metrics["records"]
                if record["kind"] == "legacy-structural-member"
            )["role"],
            "member",
        )

        coalesced_offscreen_preview = preview.replace(
            "legacy-exact-offscreen=1,legacy-structural-member=0,legacy-coalesced-inline=1,legacy-coalesced-offscreen=0",
            "legacy-exact-offscreen=0,legacy-structural-member=0,legacy-coalesced-inline=1,legacy-coalesced-offscreen=1",
        ).replace(
            "exact-key=8,layer-aggregate=2,none=2",
            "exact-key=7,layer-aggregate=3,none=2",
        ).replace(
            "owner=5,aggregate-contributor=1,member=5,none=1",
            "owner=4,aggregate-contributor=2,member=5,none=1",
        ).replace(
            "layer=5 scope=effect-induced-static kind=legacy-offscreen effects=2 owners=1 aggregate=0",
            "layer=5 scope=effect-induced-static kind=legacy-offscreen effects=2 owners=0 aggregate=1",
        ).replace(
            "kind=legacy-exact-offscreen attribution=exact-key family=bloom group=5 role=owner reason=-",
            "kind=legacy-coalesced-offscreen attribution=layer-aggregate family=water-ripple-normal group=5 role=aggregate-contributor reason=first-parameters-first-resolvable-normal",
        )
        coalesced_offscreen_metrics = (
            benchmark.effect_runtime_disposition_metrics(
                coalesced_offscreen_preview
            )
        )
        self.assertEqual(
            coalesced_offscreen_metrics["validation_failures"],
            [],
        )
        self.assertEqual(
            next(
                record for record in coalesced_offscreen_metrics["records"]
                if record["kind"] == "legacy-coalesced-offscreen"
            )["role"],
            "aggregate-contributor",
        )

        inline_passthrough_preview = preview.replace(
            "legacy-exact-inline=1,legacy-exact-offscreen=1",
            "legacy-exact-inline=2,legacy-exact-offscreen=1",
        ).replace(
            "route-only-member=1,composite-refused=1",
            "route-only-member=0,composite-refused=1",
        ).replace(
            "owner=5,aggregate-contributor=1,member=5,none=1",
            "owner=6,aggregate-contributor=1,member=4,none=1",
        ).replace(
            "layer=4 scope=effect-induced-static kind=offscreen-passthrough effects=1 owners=0 aggregate=0",
            "layer=4 scope=effect-induced-static kind=offscreen-passthrough effects=1 owners=1 aggregate=0",
        ).replace(
            "kind=route-only-member attribution=exact-key family=declared-multipass group=4 role=member reason=capture-or-neutral-copy-only",
            "kind=legacy-exact-inline attribution=exact-key family=opacity group=4 role=owner reason=-",
        )
        inline_passthrough_metrics = (
            benchmark.effect_runtime_disposition_metrics(
                inline_passthrough_preview
            )
        )
        self.assertEqual(
            inline_passthrough_metrics["validation_failures"],
            [],
        )

        unsupported_only_passthrough_preview = preview.replace(
            "route-only-member=1,composite-refused=1,unsupported=1",
            "route-only-member=0,composite-refused=1,unsupported=2",
        ).replace(
            "exact-key=8,layer-aggregate=2,none=2",
            "exact-key=7,layer-aggregate=2,none=3",
        ).replace(
            "kind=route-only-member attribution=exact-key family=declared-multipass group=4 role=member reason=capture-or-neutral-copy-only",
            "kind=unsupported attribution=none family=declared-multipass group=4 role=member reason=no-legacy-visual-route",
        )
        unsupported_only_passthrough_metrics = (
            benchmark.effect_runtime_disposition_metrics(
                unsupported_only_passthrough_preview
            )
        )
        self.assertIn(
            "effect runtime disposition passthrough group invalid",
            unsupported_only_passthrough_metrics["validation_failures"],
        )

        invalid_coalesced_offscreen = (
            benchmark.effect_runtime_disposition_metrics(
                coalesced_offscreen_preview.replace(
                    "reason=first-parameters-first-resolvable-normal",
                    "reason=claimed-exact-stage-execution",
                )
            )
        )
        self.assertIn(
            "effect runtime disposition coalesced offscreen reason mismatch",
            invalid_coalesced_offscreen["validation_failures"],
        )

        sample = {
            expectation.matrix_key: metrics[expectation.metric_key]
            for expectation in benchmark.EFFECT_RUNTIME_DISPOSITION_EXPECTATIONS
        }
        self.assertEqual(
            benchmark.effect_runtime_disposition_failures(sample, metrics),
            [],
        )

    def test_effect_runtime_disposition_rejects_semantic_and_join_drift(self) -> None:
        preview = effect_runtime_disposition_preview()
        mutations = {
            "duplicate-key": (
                preview.replace(
                    "effectStageRuntimeDisposition: layer=7 effect=0 descriptor=7%23effect%230",
                    "effectStageRuntimeDisposition: layer=6 effect=0 descriptor=6%23effect%230",
                ),
                "effect runtime disposition identity duplicated",
            ),
            "path-join": (
                preview.replace(
                    "reason=no-legacy-visual-route path=effects/unknown/effect.json",
                    "reason=no-legacy-visual-route path=effects/other/effect.json",
                ),
                "effect runtime disposition definition path mismatch",
            ),
            "inactive-group": (
                preview.replace(
                    "kind=inactive attribution=none family=- group=- role=none",
                    "kind=inactive attribution=none family=- group=1 role=none",
                ),
                "effect runtime disposition state group invalid",
            ),
            "strict-omission-became-legacy": (
                preview.replace(
                    "kind=omitted-by-strict-chain attribution=exact-key family=- group=2 role=member",
                    "kind=legacy-exact-inline attribution=exact-key family=omitted group=2 role=owner",
                ),
                "effect runtime disposition conflicts with admission",
            ),
            "coalesced-claims-exact": (
                preview.replace(
                    "kind=legacy-coalesced-inline attribution=layer-aggregate",
                    "kind=legacy-coalesced-inline attribution=exact-key",
                ),
                "effect runtime disposition state combination invalid",
            ),
            "route-only-claims-owner": (
                preview.replace(
                    "kind=route-only-member attribution=exact-key family=declared-multipass group=4 role=member",
                    "kind=route-only-member attribution=exact-key family=declared-multipass group=4 role=owner",
                ),
                "effect runtime disposition state combination invalid",
            ),
            "composite-claims-exact": (
                preview.replace(
                    "kind=composite-refused attribution=layer-aggregate",
                    "kind=composite-refused attribution=exact-key",
                ),
                "effect runtime disposition state combination invalid",
            ),
            "group-owner-count": (
                preview.replace(
                    "layer=5 scope=effect-induced-static kind=legacy-offscreen effects=2 owners=1 aggregate=0",
                    "layer=5 scope=effect-induced-static kind=legacy-offscreen effects=2 owners=2 aggregate=0",
                ),
                "effect runtime disposition group owner count mismatch",
            ),
            "duplicate-group-layer": (
                preview.replace(
                    "effectStaticRouteGroup: layer=7 scope=effect-induced-static kind=direct",
                    "effectStaticRouteGroup: layer=6 scope=effect-induced-static kind=direct",
                ),
                "effect runtime disposition route group layer duplicated",
            ),
            "group-scope": (
                preview.replace(
                    "effectStaticRouteGroup: layer=7 scope=effect-induced-static",
                    "effectStaticRouteGroup: layer=7 scope=full-compositor",
                ),
                "effect runtime disposition group scope invalid",
            ),
            "failed-conservation": (
                preview.replace(
                    "effectStageRuntimeGroupIdentityConserved: true",
                    "effectStageRuntimeGroupIdentityConserved: false",
                ),
                "effect runtime disposition Swift conservation failed",
            ),
            "unattributed": (
                preview.replace(
                    "kind=unsupported attribution=none family=unknown",
                    "kind=unattributed attribution=none family=-",
                ),
                "effect runtime disposition contains unattributed stage",
            ),
        }
        for name, (mutated, expected_failure) in mutations.items():
            with self.subTest(name=name):
                metrics = benchmark.effect_runtime_disposition_metrics(mutated)
                self.assertIn(expected_failure, metrics["validation_failures"])

    def test_effect_runtime_disposition_rejects_summary_and_matrix_drift(self) -> None:
        preview = effect_runtime_disposition_preview()
        malformed = benchmark.effect_runtime_disposition_metrics(
            preview.replace("effectStageRuntimeDispositionSchema: 1\n", "")
        )
        self.assertIn(
            "effect runtime disposition summary missing or malformed",
            malformed["validation_failures"],
        )
        self.assertIn(
            "effect runtime disposition schema unsupported",
            malformed["validation_failures"],
        )

        metrics = benchmark.effect_runtime_disposition_metrics(preview)
        self.assertEqual(metrics["validation_failures"], [])
        self.assertEqual(
            benchmark.effect_runtime_disposition_failures(
                {"expected_effect_runtime_disposition_schema": 1},
                metrics,
            ),
            ["effect runtime disposition matrix contract incomplete"],
        )
        sample = {
            expectation.matrix_key: metrics[expectation.metric_key]
            for expectation in benchmark.EFFECT_RUNTIME_DISPOSITION_EXPECTATIONS
        }
        sample["expected_effect_runtime_disposition_sha256"] = "0" * 64
        self.assertIn(
            "effect runtime disposition sha256 mismatch",
            benchmark.effect_runtime_disposition_failures(sample, metrics),
        )

    def test_effect_runtime_disposition_evidence_is_backward_compatible(self) -> None:
        metrics = benchmark.effect_runtime_disposition_metrics("")
        self.assertFalse(metrics["has_evidence"])
        self.assertIsNone(metrics["schema_version"])
        self.assertEqual(
            benchmark.effect_runtime_disposition_failures({}, metrics),
            [],
        )
        self.assertEqual(
            benchmark.effect_runtime_disposition_failures(
                {}, metrics, require_evidence=True
            ),
            ["effect runtime disposition evidence missing"],
        )
        self.assertEqual(
            benchmark.effect_runtime_disposition_failures(
                {"expected_effect_runtime_disposition_record_count": 1},
                metrics,
            ),
            ["effect runtime disposition evidence missing"],
        )

    def test_effect_runtime_disposition_can_be_required_from_cli(self) -> None:
        old_argv = sys.argv
        try:
            sys.argv = [
                "scene_wallpaper_benchmark.py",
                "--app", "/tmp/MyWallpaperX",
                "--sample-root", "/tmp/samples",
                "--output-dir", "/tmp/results",
                "--require-effect-runtime-disposition",
            ]
            args = benchmark.parse_args()
        finally:
            sys.argv = old_argv
        self.assertTrue(args.require_effect_runtime_disposition)

    def test_effect_execution_preserves_three_axes_and_static_identity(self) -> None:
        disposition = benchmark.effect_runtime_disposition_metrics(
            effect_runtime_disposition_preview()
        )
        exact = effect_cpu_event(
            frame=7,
            origin="strict-chain",
            subject="effect",
            layer=2,
            effect=0,
            descriptor="2%23effect%230",
            family="opacity",
            backend="opacity",
        )
        aggregate = effect_cpu_event(
            frame=7,
            origin="legacy-inline",
            subject="aggregate",
            layer=3,
            effect=None,
            descriptor=None,
            family="chromatic-aberration",
            backend="legacy-inline",
        )
        route = effect_route_event(
            frame=7,
            origin="offscreen-route",
            layer=4,
            operation="source-capture",
        )
        metrics = benchmark.effect_execution_metrics(
            effect_execution_log(7, [exact, aggregate], [route]),
            disposition,
        )

        self.assertTrue(metrics["has_evidence"])
        self.assertEqual(metrics["schema_version"], 1)
        self.assertEqual(metrics["axis_evidence"], {
            "cpu_invocation": True,
            "route_operation": True,
            "frame_command_buffer": True,
        })
        self.assertEqual(metrics["cpu_invocation_count"], 2)
        self.assertEqual(metrics["route_operation_count"], 1)
        self.assertEqual(metrics["frame_observation_count"], 1)
        self.assertEqual(metrics["validation_failures"], [])
        self.assertEqual(
            metrics["succeeded_exact_effects"][0]["definition_path"],
            "effects/opacity/effect.json",
        )
        self.assertEqual(len(metrics["succeeded_exact_effects"]), 1)
        self.assertEqual(len(metrics["succeeded_aggregates"]), 1)
        self.assertEqual(
            metrics["succeeded_aggregates"][0]["contributors"][0][
                "effect_index"
            ],
            1,
        )
        self.assertEqual(metrics["eligible_exact_effect_count"], 5)
        self.assertEqual(metrics["observed_eligible_exact_effect_count"], 1)
        self.assertEqual(metrics["eligible_exact_gap_count"], 4)
        self.assertEqual(len(metrics["unobserved_eligible_exact_effects"]), 4)
        self.assertEqual(metrics["eligible_aggregate_subject_count"], 1)
        self.assertEqual(
            metrics["observed_eligible_aggregate_subject_count"], 1
        )
        self.assertEqual(metrics["eligible_aggregate_gap_count"], 0)
        self.assertEqual(metrics["unobserved_eligible_aggregates"], [])
        self.assertEqual(metrics["completed_frame_ids"], [7])
        self.assertEqual(metrics["failed_frame_ids"], [])
        self.assertEqual(
            metrics["frames"][0]["cohort_sha256"],
            str(effect_execution_log(7, [exact, aggregate], [route])).split(
                "cohortSHA256=", 1
            )[1].split()[0],
        )
        self.assertEqual(
            metrics["canonical_sha256"],
            hashlib.sha256(json.dumps(
                {
                    "cpu_invocation_transitions": [
                        {"frame_id": 7, "event": event}
                        for event in sorted([
                            str(exact["canonical"]),
                            str(aggregate["canonical"]),
                        ])
                    ],
                    "route_operation_transitions": [{
                        "frame_id": 7,
                        "event": str(route["canonical"]),
                    }],
                    "frames": metrics["frames"],
                },
                ensure_ascii=True,
                sort_keys=True,
                separators=(",", ":"),
            ).encode("utf-8")).hexdigest(),
        )
        self.assertEqual(benchmark.effect_execution_failures(metrics), [])

    def test_effect_execution_rejects_illegal_disposition_joins(self) -> None:
        preview = effect_runtime_disposition_preview()
        disposition = benchmark.effect_runtime_disposition_metrics(preview)
        invalid_exact_cases = [
            ("inactive", 1, 0, "1%23effect%230", "disabled"),
            ("omitted", 2, 3, "2%23effect%233", "omitted"),
            ("coalesced-as-exact", 3, 1, "3%23effect%231", "chromatic-aberration"),
            ("route-only", 4, 0, "4%23effect%230", "declared-multipass"),
            ("shadowed", 5, 1, "5%23effect%231", "blur"),
            ("unsupported", 7, 0, "7%23effect%230", "unknown"),
        ]
        for name, layer, effect, descriptor, family in invalid_exact_cases:
            with self.subTest(name=name):
                event = effect_cpu_event(
                    frame=1,
                    origin="invalid-probe",
                    subject="effect",
                    layer=layer,
                    effect=effect,
                    descriptor=descriptor,
                    family=family,
                    backend="probe",
                )
                metrics = benchmark.effect_execution_metrics(
                    effect_execution_log(1, [event], []),
                    disposition,
                )
                self.assertIn(
                    "effect execution exact disposition cannot invoke",
                    metrics["validation_failures"],
                )

        composite = effect_cpu_event(
            frame=2,
            origin="invalid-probe",
            subject="aggregate",
            layer=6,
            effect=None,
            descriptor=None,
            family="unsupported-composite",
            backend="probe",
        )
        composite_metrics = benchmark.effect_execution_metrics(
            effect_execution_log(2, [composite], []),
            disposition,
        )
        self.assertIn(
            "effect execution aggregate disposition cannot invoke",
            composite_metrics["validation_failures"],
        )

        wrong_family = effect_cpu_event(
            frame=3,
            origin="strict-chain",
            subject="effect",
            layer=2,
            effect=0,
            descriptor="2%23effect%230",
            family="not-opacity",
            backend="opacity",
        )
        wrong_family_metrics = benchmark.effect_execution_metrics(
            effect_execution_log(3, [wrong_family], []),
            disposition,
        )
        self.assertIn(
            "effect execution exact family mismatch",
            wrong_family_metrics["validation_failures"],
        )

        wrong_aggregate_family = effect_cpu_event(
            frame=3,
            origin="legacy-inline",
            subject="aggregate",
            layer=3,
            effect=None,
            descriptor=None,
            family="not-chromatic-aberration",
            backend="legacy-inline",
        )
        wrong_aggregate_metrics = benchmark.effect_execution_metrics(
            effect_execution_log(3, [wrong_aggregate_family], []),
            disposition,
        )
        self.assertIn(
            "effect execution aggregate family mismatch",
            wrong_aggregate_metrics["validation_failures"],
        )

        structural_preview = preview.replace(
            "legacy-structural-member=0,legacy-coalesced-inline=1,legacy-coalesced-offscreen=0,legacy-shadowed=1",
            "legacy-structural-member=1,legacy-coalesced-inline=1,legacy-coalesced-offscreen=0,legacy-shadowed=0",
        ).replace(
            "kind=legacy-shadowed attribution=exact-key family=blur group=5 role=member reason=shadowed-by-legacy-precedence",
            "kind=legacy-structural-member attribution=exact-key family=gradient-color group=5 role=member reason=shape-only-legacy-member",
        )
        structural_disposition = benchmark.effect_runtime_disposition_metrics(
            structural_preview
        )
        structural = effect_cpu_event(
            frame=4,
            origin="invalid-probe",
            subject="effect",
            layer=5,
            effect=1,
            descriptor="5%23effect%231",
            family="gradient-color",
            backend="probe",
        )
        structural_metrics = benchmark.effect_execution_metrics(
            effect_execution_log(4, [structural], []),
            structural_disposition,
        )
        self.assertIn(
            "effect execution exact disposition cannot invoke",
            structural_metrics["validation_failures"],
        )

        unattributed_preview = preview.replace(
            "composite-refused=1,unsupported=1,unattributed=0",
            "composite-refused=1,unsupported=0,unattributed=1",
        ).replace(
            "kind=unsupported attribution=none family=unknown group=7 role=member reason=no-legacy-visual-route",
            "kind=unattributed attribution=none family=- group=7 role=member reason=unattributed-runtime-stage",
        )
        unattributed_disposition = benchmark.effect_runtime_disposition_metrics(
            unattributed_preview
        )
        unattributed = effect_cpu_event(
            frame=5,
            origin="invalid-probe",
            subject="effect",
            layer=7,
            effect=0,
            descriptor="7%23effect%230",
            family="unknown",
            backend="probe",
        )
        unattributed_metrics = benchmark.effect_execution_metrics(
            effect_execution_log(5, [unattributed], []),
            unattributed_disposition,
        )
        self.assertIn(
            "effect execution static disposition unavailable or invalid",
            unattributed_metrics["validation_failures"],
        )

    def test_effect_execution_aggregate_is_not_expanded_into_exact_successes(self) -> None:
        disposition = benchmark.effect_runtime_disposition_metrics(
            effect_runtime_disposition_preview()
        )
        aggregate = effect_cpu_event(
            frame=11,
            origin="legacy-inline",
            subject="aggregate",
            layer=3,
            effect=None,
            descriptor=None,
            family="chromatic-aberration",
            backend="legacy-inline",
        )
        metrics = benchmark.effect_execution_metrics(
            effect_execution_log(11, [aggregate], []),
            disposition,
        )
        self.assertEqual(metrics["succeeded_exact_effects"], [])
        self.assertEqual(len(metrics["succeeded_aggregates"]), 1)
        self.assertEqual(
            metrics["succeeded_aggregates"][0]["contributors"][0][
                "descriptor_id"
            ],
            "3#effect#1",
        )

    def test_effect_execution_decodes_tokens_before_static_family_join(self) -> None:
        disposition = json.loads(json.dumps(
            benchmark.effect_runtime_disposition_metrics(
                effect_runtime_disposition_preview()
            )
        ))
        record = next(
            item for item in disposition["records"]
            if item["layer_id"] == 2 and item["effect_index"] == 0
        )
        record["descriptor_id"] = "same descriptor"
        record["family"] = "Tint Space"
        event = effect_cpu_event(
            frame=20,
            origin="image",
            subject="effect",
            layer=2,
            effect=0,
            descriptor="same%20descriptor",
            family="Tint%20Space",
            backend="strict%20generic",
        )
        metrics = benchmark.effect_execution_metrics(
            effect_execution_log(20, [event], []),
            disposition,
        )
        self.assertEqual(metrics["validation_failures"], [])
        self.assertEqual(metrics["cpu_invocations"][0]["family"], "Tint Space")
        self.assertEqual(
            metrics["cpu_invocations"][0]["backend"], "strict generic"
        )
        self.assertEqual(
            metrics["succeeded_exact_effects"][0]["descriptor_id"],
            "same descriptor",
        )

    def test_effect_execution_failure_is_sticky_across_completed_frame(self) -> None:
        disposition = benchmark.effect_runtime_disposition_metrics(
            effect_runtime_disposition_preview()
        )
        success = effect_cpu_event(
            frame=12,
            origin="strict-chain",
            subject="effect",
            layer=2,
            effect=0,
            descriptor="2%23effect%230",
            family="opacity",
            backend="opacity",
        )
        failure = effect_cpu_event(
            frame=12,
            origin="strict-chain",
            subject="effect",
            layer=2,
            effect=0,
            descriptor="2%23effect%230",
            family="opacity",
            backend="opacity",
            outcome="failed",
            reason="encoder-refused",
        )
        later_success = effect_cpu_event(
            frame=13,
            origin="strict-chain",
            subject="effect",
            layer=2,
            effect=0,
            descriptor="2%23effect%230",
            family="opacity",
            backend="opacity",
        )
        metrics = benchmark.effect_execution_metrics(
            "\n".join([
                effect_execution_log(12, [failure], [], status="completed"),
                effect_execution_log(
                    13, [later_success], [], status="completed"
                ),
            ]),
            disposition,
        )
        self.assertEqual(metrics["completed_frame_ids"], [12, 13])
        self.assertEqual(len(metrics["succeeded_exact_effects"]), 1)
        self.assertEqual(len(metrics["failed_exact_effects"]), 1)
        self.assertIn(
            "effect execution exact identity both succeeded and failed",
            metrics["validation_failures"],
        )
        failures = benchmark.effect_execution_failures(metrics)
        self.assertIn("effect execution CPU invocation failed", failures)
        self.assertNotIn(
            "effect execution frame command buffer failed",
            failures,
        )

        completed_only = benchmark.effect_execution_metrics(
            effect_execution_log(
                14,
                [],
                [],
                count_overrides={"attempted": 1, "returned": 1},
                cohort_override=hashlib.sha256(
                    str(success["canonical"]).encode("utf-8")
                ).hexdigest(),
            ),
            disposition,
        )
        self.assertEqual(completed_only["succeeded_exact_effects"], [])
        self.assertEqual(completed_only["succeeded_aggregates"], [])
        self.assertEqual(completed_only["validation_failures"], [])

    def test_effect_execution_deduplicates_events_before_frame_contract(self) -> None:
        disposition = benchmark.effect_runtime_disposition_metrics(
            effect_runtime_disposition_preview()
        )
        event = effect_cpu_event(
            frame=14,
            origin="strict-chain",
            subject="effect",
            layer=2,
            effect=1,
            descriptor="2%23effect%231",
            family="generic-fragment",
            backend="authored-shader",
        )
        route = effect_route_event(
            frame=14,
            origin="strict-chain",
            layer=2,
            operation="authored-chain",
        )
        repeated_event = effect_cpu_event(
            frame=15,
            origin="strict-chain",
            subject="effect",
            layer=2,
            effect=1,
            descriptor="2%23effect%231",
            family="generic-fragment",
            backend="authored-shader",
        )
        repeated_route = effect_route_event(
            frame=15,
            origin="strict-chain",
            layer=2,
            operation="authored-chain",
        )
        metrics = benchmark.effect_execution_metrics(
            "\n".join([
                effect_execution_log(14, [event, event], [route, route]),
                effect_execution_log(15, [repeated_event], [repeated_route]),
            ]),
            disposition,
        )
        self.assertEqual(metrics["cpu_invocation_count"], 1)
        self.assertEqual(metrics["route_operation_count"], 1)
        self.assertEqual(metrics["frame_observation_count"], 2)
        self.assertEqual(metrics["frames"][0]["attempted_effects"], 1)
        self.assertEqual(metrics["frames"][0]["route_operations"], 1)
        self.assertEqual(metrics["validation_failures"], [])

    def test_effect_execution_validates_frame_summary_relations_and_format(self) -> None:
        disposition = benchmark.effect_runtime_disposition_metrics(
            effect_runtime_disposition_preview()
        )
        event = effect_cpu_event(
            frame=15,
            origin="strict-chain",
            subject="effect",
            layer=2,
            effect=0,
            descriptor="2%23effect%230",
            family="opacity",
            backend="opacity",
        )
        bad_returned = benchmark.effect_execution_metrics(
            effect_execution_log(
                15,
                [event],
                [],
                count_overrides={"attempted": 0},
            ),
            disposition,
        )
        self.assertIn(
            "effect execution frame returned outputs exceed attempted effects",
            bad_returned["validation_failures"],
        )
        bad_failed = benchmark.effect_execution_metrics(
            effect_execution_log(
                15,
                [event],
                [],
                count_overrides={"attempted": 0, "returned": 0, "failed": 1},
            ),
            disposition,
        )
        self.assertIn(
            "effect execution frame failed invocations exceed attempted effects",
            bad_failed["validation_failures"],
        )
        opaque_valid_hash = benchmark.effect_execution_metrics(
            effect_execution_log(15, [event], [], cohort_override="0" * 64),
            disposition,
        )
        self.assertNotIn(
            "effect execution frame summary malformed",
            opaque_valid_hash["validation_failures"],
        )
        malformed_hash_log = effect_execution_log(15, [event], []).replace(
            "cohortSHA256=", "cohortSHA256=x"
        )
        malformed_hash = benchmark.effect_execution_metrics(
            malformed_hash_log,
            disposition,
        )
        self.assertIn(
            "effect execution frame summary malformed",
            malformed_hash["validation_failures"],
        )

        first_summary = effect_execution_log(15, [event], [])
        conflicting_summary = effect_execution_log(
            15,
            [],
            [],
            cohort_override="1" * 64,
        ).splitlines()[-1]
        duplicate_status = benchmark.effect_execution_metrics(
            f"{first_summary}\n{conflicting_summary}",
            disposition,
        )
        self.assertIn(
            "effect execution frame status identity duplicated",
            duplicate_status["validation_failures"],
        )

    def test_effect_execution_route_and_shared_buffer_failures_gate(self) -> None:
        disposition = benchmark.effect_runtime_disposition_metrics(
            effect_runtime_disposition_preview()
        )
        route = effect_route_event(
            frame=16,
            origin="offscreen-route",
            layer=5,
            operation="legacy-offscreen",
            outcome="failed",
            reason="encoder-refused",
        )
        metrics = benchmark.effect_execution_metrics(
            "\n".join([
                effect_execution_log(16, [], [route], status="failed"),
                effect_execution_log(16, [], [route], status="completed"),
            ]),
            disposition,
        )
        self.assertEqual(metrics["completed_frame_ids"], [16])
        self.assertEqual(metrics["failed_frame_ids"], [16])
        self.assertNotIn(
            "effect execution frame status identity duplicated",
            metrics["validation_failures"],
        )
        failures = benchmark.effect_execution_failures(metrics)
        self.assertIn("effect execution route operation failed", failures)
        self.assertIn(
            "effect execution frame command buffer failed",
            failures,
        )

    def test_effect_execution_is_backward_compatible_and_cli_optional(self) -> None:
        metrics = benchmark.effect_execution_metrics("")
        self.assertFalse(metrics["has_evidence"])
        self.assertEqual(benchmark.effect_execution_failures(metrics), [])
        self.assertEqual(
            benchmark.effect_execution_failures(metrics, require_evidence=True),
            ["effect execution evidence missing"],
        )
        static_only = benchmark.effect_execution_metrics(
            "",
            benchmark.effect_runtime_disposition_metrics(
                effect_runtime_disposition_preview()
            ),
        )
        self.assertFalse(static_only["has_evidence"])
        self.assertEqual(static_only["eligible_exact_effect_count"], 5)
        self.assertEqual(static_only["eligible_exact_gap_count"], 5)
        self.assertEqual(static_only["eligible_aggregate_subject_count"], 1)
        self.assertEqual(static_only["eligible_aggregate_gap_count"], 1)
        old_argv = sys.argv
        try:
            sys.argv = [
                "scene_wallpaper_benchmark.py",
                "--app", "/tmp/MyWallpaperX",
                "--sample-root", "/tmp/samples",
                "--output-dir", "/tmp/results",
                "--require-effect-execution",
            ]
            args = benchmark.parse_args()
        finally:
            sys.argv = old_argv
        self.assertTrue(args.require_effect_execution)

    def test_resolved_material_graph_execution_gate_accepts_conserved_evidence(
        self,
    ) -> None:
        preview_text = (
            "resolved material execution capabilities: "
            "schema=r4-layer-capability-v2 candidates=2 accepted=1 "
            "rejected=1 variantLimit=8\n"
            "resolved material execution capability: "
            "schema=r4-layer-route-v1 layer=68 status=accepted\n"
        )
        log_text = "\n".join([
            "resolved material runtime audit: schema=r4-graph-executor-v1 "
            "claimed=1 encoded=0 failures=0 deferred=1 pending=1 "
            "gpuEncoded=0",
            "resolved material runtime audit: schema=r4-graph-executor-v1 "
            "claimed=1 encoded=1 failures=0 deferred=0 pending=1 "
            "gpuEncoded=1",
            graph_execution_observation(
                frame=10,
                transaction="tx-10",
                trigger="first-frame+first-success+gpu-completed",
            ),
            graph_execution_observation(
                frame=11,
                transaction="tx-11",
                trigger="next-frame+compositor-consume+gpu-completed",
                consumed=True,
            ),
        ])

        disposition, exact_execution = resolved_graph_exact_evidence([68])
        metrics = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            log_text,
            effect_execution=exact_execution,
            static_disposition=disposition,
        )

        self.assertTrue(metrics["has_evidence"])
        self.assertTrue(metrics["execution_succeeded"])
        self.assertEqual(metrics["validation_failures"], [])
        self.assertEqual(metrics["capability"], {
            "has_evidence": True,
            "schema_version": "r4-layer-capability-v2",
            "observation_count": 1,
            "candidate_count": 2,
            "accepted_count": 1,
            "rejected_count": 1,
            "variant_limit": 8,
            "accepted_layer_ids": [68],
            "accepted_layer_observation_count": 1,
            "duplicate_accepted_layer_ids": [],
            "malformed_route_observation_count": 0,
        })
        self.assertEqual(metrics["executor"]["claimed_count"], 2)
        self.assertEqual(metrics["executor"]["encoded_count"], 1)
        self.assertEqual(metrics["executor"]["gpu_encoded_count"], 1)
        self.assertEqual(
            metrics["graph_observations"]["successful_transactions"],
            ["tx-10", "tx-11"],
        )
        first_terminal = metrics["graph_observations"][
            "terminal_success_observations"
        ][0]
        self.assertEqual(first_terminal["layer_id"], 68)
        self.assertEqual(first_terminal["final_output"], "output-tx-10")
        self.assertEqual(first_terminal["final_physical"], "physical-tx-10")
        self.assertEqual(
            first_terminal["final_publication"],
            "publication-tx-10",
        )
        self.assertEqual(first_terminal["publication_generation"], 10)
        self.assertTrue(
            metrics["graph_observations"]["next_frame_observed"]
        )
        self.assertEqual(
            metrics["graph_observations"]["next_frame_layer_ids"],
            [68],
        )
        self.assertTrue(
            metrics["graph_observations"][
                "terminal_compositor_consume_observed"
            ]
        )
        self.assertEqual(metrics["layer_routes"], {
            "has_evidence": True,
            "schema_version": "r4-layer-route-v1",
            "accepted_layer_ids": [68],
            "observed_layer_ids": [68],
            "compositor_consumed_layer_ids": [68],
            "next_frame_layer_ids": [68],
            "missing_layer_ids": [],
            "missing_gpu_completed_layer_ids": [],
            "missing_compositor_consumed_layer_ids": [],
            "missing_next_frame_layer_ids": [],
            "missing_exact_backend_layer_ids": [],
            "unexpected_layer_ids": [],
            "unexpected_gpu_completed_layer_ids": [],
            "unexpected_compositor_consumed_layer_ids": [],
            "unexpected_next_frame_layer_ids": [],
            "unexpected_exact_backend_layer_ids": [],
            "legacy_conflict_layer_ids": [],
        })
        self.assertEqual(metrics["succeeded_layer_ids"], [68])
        self.assertEqual(
            benchmark.resolved_material_graph_execution_failures(
                metrics,
                require_evidence=True,
                sample={
                    "expected_resolved_material_graph_succeeded_layer_ids": [68]
                },
            ),
            [],
        )
        self.assertIn(
            "resolved material graph succeeded layer IDs mismatch",
            benchmark.resolved_material_graph_execution_failures(
                metrics,
                sample={
                    "expected_resolved_material_graph_succeeded_layer_ids": []
                },
            ),
        )

    def test_resolved_material_graph_execution_gate_rejects_false_success(
        self,
    ) -> None:
        no_admission = benchmark.resolved_material_graph_execution_metrics(
            "resolved material execution capabilities: "
            "schema=r4-layer-capability-v2 candidates=1 accepted=0 "
            "rejected=1 variantLimit=8\n",
            "resolved material runtime audit: schema=r4-graph-executor-v1 "
            "claimed=1 encoded=1 failures=0 deferred=0 pending=0 "
            "gpuEncoded=1\n",
        )
        self.assertFalse(no_admission["execution_succeeded"])
        no_admission_failures = (
            benchmark.resolved_material_graph_execution_failures(
                no_admission,
                require_evidence=True,
            )
        )
        self.assertIn(
            "resolved material graph zero contract executor counters nonzero",
            no_admission_failures,
        )
        self.assertIn(
            "resolved material graph zero contract executor counters nonzero",
            benchmark.resolved_material_graph_execution_failures(no_admission),
        )
        self.assertIn(
            "resolved material graph execution has no admitted capability",
            no_admission_failures,
        )

        executor_failure = benchmark.resolved_material_graph_execution_metrics(
            "resolved material execution capabilities: "
            "schema=r4-layer-capability-v2 candidates=1 accepted=1 "
            "rejected=0 variantLimit=8\n",
            "resolved material runtime audit: schema=r4-graph-executor-v1 "
            "claimed=1 encoded=1 failures=1 deferred=0 pending=0 "
            "gpuEncoded=1\n",
        )
        self.assertFalse(executor_failure["execution_succeeded"])
        self.assertIn(
            "resolved material graph executor reported failures",
            benchmark.resolved_material_graph_execution_failures(
                executor_failure,
                require_evidence=True,
            ),
        )

        broken_conservation = (
            benchmark.resolved_material_graph_execution_metrics(
                "resolved material execution capabilities: "
                "schema=r4-layer-capability-v2 candidates=2 accepted=1 "
                "rejected=0 variantLimit=8\n",
                "resolved material runtime audit: "
                "schema=r4-graph-executor-v1 claimed=1 encoded=2 "
                "failures=0 deferred=0 pending=0 gpuEncoded=1\n",
            )
        )
        self.assertIn(
            "resolved material graph capability count conservation failed",
            broken_conservation["validation_failures"],
        )
        self.assertIn(
            "resolved material graph executor claim conservation failed",
            broken_conservation["validation_failures"],
        )
        self.assertIn(
            "resolved material graph executor GPU encode conservation failed",
            broken_conservation["validation_failures"],
        )

        missing = benchmark.resolved_material_graph_execution_metrics("", "")
        self.assertEqual(
            benchmark.resolved_material_graph_execution_failures(
                missing,
                require_evidence=True,
            ),
            ["resolved material graph capability evidence missing"],
        )
        self.assertEqual(
            benchmark.resolved_material_graph_execution_failures(missing),
            [],
        )

        orphan_executor = benchmark.resolved_material_graph_execution_metrics(
            "",
            "resolved material runtime audit: schema=r4-graph-executor-v1 "
            "claimed=0 encoded=0 failures=0 deferred=0 pending=0 "
            "gpuEncoded=0",
        )
        self.assertIn(
            "resolved material graph activity has no capability evidence",
            benchmark.resolved_material_graph_execution_failures(orphan_executor),
        )

    def test_resolved_material_graph_execution_gate_requires_terminal_evidence(
        self,
    ) -> None:
        preview_text = (
            "resolved material execution capabilities: "
            "schema=r4-layer-capability-v2 candidates=1 accepted=1 "
            "rejected=0 variantLimit=8\n"
            "resolved material execution capability: "
            "schema=r4-layer-route-v1 layer=68 status=accepted\n"
        )
        audit = (
            "resolved material runtime audit: schema=r4-graph-executor-v1 "
            "claimed=1 encoded=1 failures=0 deferred=0 pending=1 "
            "gpuEncoded=1"
        )
        incomplete = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            "\n".join([
                audit,
                graph_execution_observation(
                    frame=10,
                    transaction="tx-10",
                    trigger="first-frame+gpu-completed",
                ),
                graph_execution_observation(
                    frame=10,
                    transaction="tx-10",
                    trigger="gpu-completed",
                ),
            ]),
        )
        incomplete_failures = (
            benchmark.resolved_material_graph_execution_failures(
                incomplete,
                require_evidence=True,
            )
        )
        self.assertIn(
            "resolved material graph successful transaction count below two",
            incomplete_failures,
        )
        self.assertIn(
            "resolved material graph accepted layer next-frame evidence missing",
            incomplete_failures,
        )
        self.assertIn(
            "resolved material graph accepted layer compositor consumption missing",
            incomplete_failures,
        )

        invalid_terminal = benchmark.resolved_material_graph_observation_metrics(
            graph_execution_observation(
                frame=12,
                transaction="tx-invalid",
                trigger="next-frame+gpu-completed",
                authored=3,
                material=1,
                copy=1,
                compose=2,
                rejected=1,
                consumed=True,
                publish=False,
            )
        )
        for failure in (
            "resolved material graph observation rejected nodes are nonzero",
            "resolved material graph observation node conservation failed",
            "resolved material graph observation compose count invalid",
            "resolved material graph observation final publication missing",
            "resolved material graph observation publication generation invalid",
        ):
            self.assertIn(failure, invalid_terminal["validation_failures"])
        self.assertEqual(invalid_terminal["successful_transaction_count"], 0)

        malformed_layer = benchmark.resolved_material_graph_observation_metrics(
            graph_execution_observation(
                frame=12,
                transaction="tx-bad-layer",
                trigger="next-frame+gpu-completed",
                consumed=True,
            ).replace("layer=68", "layer=bad")
        )
        self.assertEqual(malformed_layer["terminal_success_count"], 0)
        self.assertIn(
            "resolved material graph observation evidence malformed",
            malformed_layer["validation_failures"],
        )

        bad_axis = benchmark.resolved_material_graph_observation_metrics(
            "\n".join([
                graph_execution_observation(
                    frame=10,
                    transaction="tx-10",
                    trigger="first-frame+gpu-completed",
                ),
                graph_execution_observation(
                    frame=11,
                    transaction="tx-11",
                    trigger="next-frame+gpu-completed",
                    consumed=True,
                ),
                "MWX DEBUG SCENE: schema=1 axis=graph-execution "
                "diagnostic=transaction-signature-conflict",
                graph_execution_observation(
                    frame=12,
                    transaction="tx-failed",
                    trigger="first-failure",
                    outcome="failed",
                    gpu_completion="-",
                ),
                graph_execution_observation(
                    frame=13,
                    transaction="tx-gpu-failed",
                    trigger="gpu-failed",
                    outcome="failed",
                    gpu_completion="failed",
                ),
            ])
        )
        self.assertEqual(bad_axis["diagnostic_count"], 1)
        self.assertEqual(bad_axis["failed_outcome_count"], 2)
        self.assertEqual(bad_axis["gpu_failed_count"], 1)
        for failure in (
            "resolved material graph observation diagnostic reported",
            "resolved material graph observation failed outcome reported",
            "resolved material graph observation GPU failure reported",
        ):
            self.assertIn(failure, bad_axis["validation_failures"])

    def test_resolved_material_graph_execution_gate_conserves_layer_routes(
        self,
    ) -> None:
        preview_text = "\n".join([
            "resolved material execution capabilities: "
            "schema=r4-layer-capability-v2 candidates=3 accepted=2 "
            "rejected=1 variantLimit=8",
            "resolved material execution capability: "
            "schema=r4-layer-route-v1 layer=68 status=accepted",
            "resolved material execution capability: "
            "schema=r4-layer-route-v1 layer=76 status=accepted",
        ])
        log_text = "\n".join([
            "resolved material runtime audit: schema=r4-graph-executor-v1 "
            "claimed=2 encoded=2 failures=0 deferred=0 pending=2 "
            "gpuEncoded=2",
            graph_execution_observation(
                frame=10,
                layer=68,
                transaction="tx-68",
                trigger="next-frame+first-success+compositor-consume+gpu-completed",
                consumed=True,
            ),
            graph_execution_observation(
                frame=11,
                layer=76,
                transaction="tx-76",
                trigger="next-frame+first-success+compositor-consume+gpu-completed",
                consumed=True,
            ),
        ])

        disposition, exact_execution = resolved_graph_exact_evidence([68, 76])
        metrics = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            log_text,
            effect_execution=exact_execution,
            static_disposition=disposition,
        )

        self.assertTrue(metrics["execution_succeeded"])
        self.assertEqual(metrics["validation_failures"], [])
        self.assertEqual(
            metrics["graph_observations"][
                "successful_gpu_completed_layer_ids"
            ],
            [68, 76],
        )
        self.assertEqual(metrics["layer_routes"]["accepted_layer_ids"], [68, 76])
        self.assertEqual(metrics["layer_routes"]["observed_layer_ids"], [68, 76])
        self.assertEqual(
            metrics["layer_routes"]["next_frame_layer_ids"],
            [68, 76],
        )
        self.assertEqual(metrics["layer_routes"]["missing_layer_ids"], [])
        self.assertEqual(metrics["layer_routes"]["legacy_conflict_layer_ids"], [])

    def test_resolved_material_graph_execution_gate_rejects_bad_layer_routes(
        self,
    ) -> None:
        metrics = benchmark.resolved_material_graph_execution_metrics(
            "\n".join([
                "resolved material execution capabilities: "
                "schema=r4-layer-capability-v2 candidates=2 accepted=2 "
                "rejected=0 variantLimit=8",
                "resolved material execution capability: "
                "schema=r4-layer-route-v1 layer=68 status=accepted",
                "resolved material execution capability: "
                "schema=r4-layer-route-v1 layer=68 status=accepted",
                "resolved material execution capability: "
                "schema=r4-layer-route-v1 layer=bad status=accepted",
            ]),
            "",
        )

        self.assertFalse(metrics["layer_routes"]["has_evidence"])
        self.assertEqual(metrics["capability"]["accepted_layer_ids"], [68])
        self.assertEqual(
            metrics["capability"]["duplicate_accepted_layer_ids"],
            [68],
        )
        self.assertEqual(
            metrics["capability"]["malformed_route_observation_count"],
            1,
        )
        for failure in (
            "resolved material graph accepted layer evidence malformed",
            "resolved material graph accepted layer evidence duplicated",
            "resolved material graph accepted layer count conservation failed",
        ):
            self.assertIn(failure, metrics["validation_failures"])
            self.assertIn(
                failure,
                benchmark.resolved_material_graph_execution_failures(metrics),
            )

    def test_resolved_material_graph_execution_gate_rejects_per_layer_gaps(
        self,
    ) -> None:
        preview_text = "\n".join([
            "resolved material execution capabilities: "
            "schema=r4-layer-capability-v2 candidates=2 accepted=2 "
            "rejected=0 variantLimit=8",
            "resolved material execution capability: "
            "schema=r4-layer-route-v1 layer=68 status=accepted",
            "resolved material execution capability: "
            "schema=r4-layer-route-v1 layer=76 status=accepted",
        ])
        log_text = "\n".join([
            "resolved material runtime audit: schema=r4-graph-executor-v1 "
            "claimed=2 encoded=2 failures=0 deferred=0 pending=2 "
            "gpuEncoded=2",
            graph_execution_observation(
                frame=10,
                layer=68,
                transaction="tx-68",
                trigger="next-frame+first-success+compositor-consume+gpu-completed",
                consumed=True,
            ),
            graph_execution_observation(
                frame=11,
                layer=76,
                transaction="tx-76",
                trigger="next-frame+first-success+gpu-completed",
            ),
        ])

        disposition, exact_execution = resolved_graph_exact_evidence([68, 76])
        metrics = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            log_text,
            effect_execution=exact_execution,
            static_disposition=disposition,
        )

        self.assertFalse(metrics["execution_succeeded"])
        self.assertEqual(metrics["layer_routes"]["observed_layer_ids"], [68, 76])
        self.assertEqual(metrics["layer_routes"]["missing_layer_ids"], [76])
        self.assertEqual(
            metrics["layer_routes"][
                "missing_compositor_consumed_layer_ids"
            ],
            [76],
        )
        self.assertIn(
            "resolved material graph accepted layer compositor consumption missing",
            benchmark.resolved_material_graph_execution_failures(
                metrics,
                require_evidence=True,
            ),
        )

        missing_gpu_metrics = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            "\n".join([
                "resolved material runtime audit: schema=r4-graph-executor-v1 "
                "claimed=2 encoded=2 failures=0 deferred=0 pending=2 "
                "gpuEncoded=2",
                graph_execution_observation(
                    frame=10,
                    layer=68,
                    transaction="tx-68-a",
                    trigger="first-frame+first-success+compositor-consume+gpu-completed",
                    consumed=True,
                ),
                graph_execution_observation(
                    frame=11,
                    layer=68,
                    transaction="tx-68-b",
                    trigger="next-frame+compositor-consume+gpu-completed",
                    consumed=True,
                ),
            ]),
            effect_execution=exact_execution,
            static_disposition=disposition,
        )
        self.assertEqual(
            missing_gpu_metrics["layer_routes"][
                "missing_gpu_completed_layer_ids"
            ],
            [76],
        )
        self.assertEqual(
            missing_gpu_metrics["layer_routes"]["missing_layer_ids"],
            [76],
        )
        self.assertIn(
            "resolved material graph accepted layer GPU completion missing",
            missing_gpu_metrics["validation_failures"],
        )

    def test_resolved_material_graph_next_frame_is_conserved_per_layer(
        self,
    ) -> None:
        preview_text = "\n".join([
            "resolved material execution capabilities: "
            "schema=r4-layer-capability-v2 candidates=2 accepted=2 "
            "rejected=0 variantLimit=8",
            "resolved material execution capability: "
            "schema=r4-layer-route-v1 layer=68 status=accepted",
            "resolved material execution capability: "
            "schema=r4-layer-route-v1 layer=76 status=accepted",
        ])
        log_text = "\n".join([
            "resolved material runtime audit: schema=r4-graph-executor-v1 "
            "claimed=2 encoded=2 failures=0 deferred=0 pending=2 "
            "gpuEncoded=2",
            graph_execution_observation(
                frame=10,
                layer=68,
                transaction="tx-68",
                trigger="first-frame+compositor-consume+gpu-completed",
                consumed=True,
            ),
            graph_execution_observation(
                frame=11,
                layer=76,
                transaction="tx-76",
                trigger="next-frame+compositor-consume+gpu-completed",
                consumed=True,
            ),
        ])
        disposition, exact_execution = resolved_graph_exact_evidence([68, 76])

        metrics = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            log_text,
            effect_execution=exact_execution,
            static_disposition=disposition,
        )

        self.assertTrue(metrics["graph_observations"]["next_frame_observed"])
        self.assertEqual(
            metrics["graph_observations"]["next_frame_layer_ids"],
            [76],
        )
        self.assertEqual(
            metrics["layer_routes"]["missing_next_frame_layer_ids"],
            [68],
        )
        self.assertEqual(metrics["succeeded_layer_ids"], [76])
        self.assertFalse(metrics["execution_succeeded"])

    def test_resolved_material_graph_zero_contract_is_explicit(self) -> None:
        metrics = benchmark.resolved_material_graph_execution_metrics(
            "resolved material execution capabilities: "
            "schema=r4-layer-capability-v2 candidates=1 accepted=0 "
            "rejected=1 variantLimit=8",
            "resolved material runtime audit: schema=r4-graph-executor-v1 "
            "claimed=0 encoded=0 failures=0 deferred=0 pending=0 "
            "gpuEncoded=0",
        )

        self.assertTrue(metrics["has_evidence"])
        self.assertTrue(metrics["zero_contract_succeeded"])
        self.assertTrue(metrics["contract_succeeded"])
        self.assertFalse(metrics["execution_succeeded"])
        self.assertEqual(metrics["succeeded_layer_ids"], [])
        self.assertEqual(metrics["validation_failures"], [])
        self.assertEqual(
            benchmark.resolved_material_graph_execution_failures(
                metrics,
                sample={
                    "expected_resolved_material_graph_succeeded_layer_ids": []
                },
            ),
            [],
        )
        self.assertEqual(
            benchmark.resolved_material_graph_execution_failures(
                metrics,
                require_evidence=True,
                sample={
                    "expected_resolved_material_graph_succeeded_layer_ids": []
                },
            ),
            [],
        )

    def test_resolved_material_graph_zero_contract_rejects_unauthorized_activity(
        self,
    ) -> None:
        disposition, exact_execution = resolved_graph_exact_evidence([68])
        metrics = benchmark.resolved_material_graph_execution_metrics(
            "resolved material execution capabilities: "
            "schema=r4-layer-capability-v2 candidates=1 accepted=0 "
            "rejected=1 variantLimit=8",
            "\n".join([
                "resolved material runtime audit: schema=r4-graph-executor-v1 "
                "claimed=0 encoded=0 failures=0 deferred=0 pending=0 "
                "gpuEncoded=0",
                graph_execution_observation(
                    frame=10,
                    layer=68,
                    transaction="tx-unauthorized",
                    trigger="next-frame+compositor-consume+gpu-completed",
                    consumed=True,
                ),
            ]),
            effect_execution=exact_execution,
            static_disposition=disposition,
        )

        self.assertFalse(metrics["zero_contract_succeeded"])
        self.assertEqual(
            metrics["exact_backend"]["unexpected_layer_ids"],
            [68],
        )
        failures = benchmark.resolved_material_graph_execution_failures(metrics)
        self.assertIn(
            "resolved material graph zero contract observed graph execution",
            failures,
        )
        self.assertIn(
            "resolved material graph non-accepted layer exact backend observed",
            failures,
        )

    def test_resolved_material_graph_exact_backend_must_own_every_subject(
        self,
    ) -> None:
        preview_text = "\n".join([
            "resolved material execution capabilities: "
            "schema=r4-layer-capability-v2 candidates=1 accepted=1 "
            "rejected=0 variantLimit=8",
            "resolved material execution capability: "
            "schema=r4-layer-route-v1 layer=68 status=accepted",
        ])
        graph_log = "\n".join([
            "resolved material runtime audit: schema=r4-graph-executor-v1 "
            "claimed=1 encoded=1 failures=0 deferred=0 pending=1 "
            "gpuEncoded=1",
            graph_execution_observation(
                frame=10,
                transaction="tx-10",
                trigger="next-frame+compositor-consume+gpu-completed",
                consumed=True,
            ),
            graph_execution_observation(
                frame=11,
                transaction="tx-11",
                trigger="next-frame+compositor-consume+gpu-completed",
                consumed=True,
            ),
        ])
        cases = (
            (
                {68: "authored-effect-chain"},
                {},
                set(),
                "resolved material graph accepted layer exact backend mismatch",
            ),
            (
                {},
                {68: "failed"},
                set(),
                "resolved material graph accepted layer exact execution failed",
            ),
            (
                {},
                {},
                {68},
                "resolved material graph accepted layer exact backend evidence missing",
            ),
        )
        for backends, outcomes, omitted, expected_failure in cases:
            with self.subTest(expected_failure=expected_failure):
                disposition, exact_execution = resolved_graph_exact_evidence(
                    [68],
                    backends=backends,
                    outcomes=outcomes,
                    omitted_layer_ids=omitted,
                )
                metrics = benchmark.resolved_material_graph_execution_metrics(
                    preview_text,
                    graph_log,
                    effect_execution=exact_execution,
                    static_disposition=disposition,
                )
                self.assertEqual(metrics["succeeded_layer_ids"], [])
                self.assertIn(expected_failure, metrics["validation_failures"])
                self.assertIn(
                    "resolved material graph succeeded layer IDs mismatch",
                    benchmark.resolved_material_graph_execution_failures(
                        metrics,
                        sample={
                            "expected_resolved_material_graph_succeeded_layer_ids": [68]
                        },
                    ),
                )

    def test_resolved_material_graph_execution_gate_rejects_legacy_route_conflicts(
        self,
    ) -> None:
        preview_text = "\n".join([
            "resolved material execution capabilities: "
            "schema=r4-layer-capability-v2 candidates=2 accepted=2 "
            "rejected=0 variantLimit=8",
            "resolved material execution capability: "
            "schema=r4-layer-route-v1 layer=68 status=accepted",
            "resolved material execution capability: "
            "schema=r4-layer-route-v1 layer=76 status=accepted",
        ])
        log_text = "\n".join([
            "resolved material runtime audit: schema=r4-graph-executor-v1 "
            "claimed=2 encoded=2 failures=0 deferred=0 pending=2 "
            "gpuEncoded=2",
            graph_execution_observation(
                frame=10,
                layer=68,
                transaction="tx-68",
                trigger="next-frame+first-success+compositor-consume+gpu-completed",
                consumed=True,
            ),
            graph_execution_observation(
                frame=11,
                layer=76,
                transaction="tx-76",
                trigger="next-frame+first-success+compositor-consume+gpu-completed",
                consumed=True,
            ),
            "phase=authored-effect-graph layer=68 status=succeeded",
            "phase=authored-effect-graph layer=76 status=failed",
        ])

        disposition, exact_execution = resolved_graph_exact_evidence([68, 76])
        metrics = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            log_text,
            effect_execution=exact_execution,
            static_disposition=disposition,
        )

        self.assertFalse(metrics["execution_succeeded"])
        self.assertEqual(
            metrics["layer_routes"]["legacy_conflict_layer_ids"],
            [68, 76],
        )
        self.assertIn(
            "resolved material graph accepted layer selected legacy authored route",
            benchmark.resolved_material_graph_execution_failures(
                metrics,
                require_evidence=True,
            ),
        )

    def test_resolved_material_graph_execution_gate_rejects_unaccepted_layers(
        self,
    ) -> None:
        preview_text = "\n".join([
            "resolved material execution capabilities: "
            "schema=r4-layer-capability-v2 candidates=1 accepted=1 "
            "rejected=0 variantLimit=8",
            "resolved material execution capability: "
            "schema=r4-layer-route-v1 layer=68 status=accepted",
        ])
        log_text = "\n".join([
            "resolved material runtime audit: schema=r4-graph-executor-v1 "
            "claimed=2 encoded=2 failures=0 deferred=0 pending=2 "
            "gpuEncoded=2",
            graph_execution_observation(
                frame=10,
                layer=68,
                transaction="tx-68",
                trigger="next-frame+first-success+compositor-consume+gpu-completed",
                consumed=True,
            ),
            graph_execution_observation(
                frame=11,
                layer=76,
                transaction="tx-76",
                trigger="next-frame+first-success+compositor-consume+gpu-completed",
                consumed=True,
            ),
        ])

        disposition, exact_execution = resolved_graph_exact_evidence([68])
        metrics = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            log_text,
            effect_execution=exact_execution,
            static_disposition=disposition,
        )

        self.assertFalse(metrics["execution_succeeded"])
        self.assertEqual(metrics["layer_routes"]["missing_layer_ids"], [])
        self.assertEqual(
            metrics["layer_routes"]["unexpected_layer_ids"],
            [76],
        )
        self.assertEqual(
            metrics["layer_routes"]["unexpected_gpu_completed_layer_ids"],
            [76],
        )
        self.assertEqual(
            metrics["layer_routes"][
                "unexpected_compositor_consumed_layer_ids"
            ],
            [76],
        )
        failures = benchmark.resolved_material_graph_execution_failures(
            metrics,
            require_evidence=True,
        )
        self.assertIn(
            "resolved material graph non-accepted layer GPU completion observed",
            failures,
        )
        self.assertIn(
            "resolved material graph non-accepted layer compositor consumption observed",
            failures,
        )

    def test_resolved_material_graph_execution_can_be_required_from_cli(
        self,
    ) -> None:
        old_argv = sys.argv
        try:
            sys.argv = [
                "scene_wallpaper_benchmark.py",
                "--app", "/tmp/MyWallpaperX",
                "--sample-root", "/tmp/samples",
                "--output-dir", "/tmp/results",
                "--require-graph-execution",
            ]
            args = benchmark.parse_args()
        finally:
            sys.argv = old_argv
        self.assertTrue(args.require_graph_execution)

    def test_effect_execution_matrix_contract_is_exact_and_complete(self) -> None:
        disposition = benchmark.effect_runtime_disposition_metrics(
            effect_runtime_disposition_preview()
        )
        metrics = benchmark.effect_execution_metrics(
            effect_execution_log(21, [], []),
            disposition,
        )
        sample = {
            expectation.matrix_key: metrics[expectation.metric_key]
            for expectation in benchmark.EFFECT_EXECUTION_EXPECTATIONS
        }
        self.assertEqual(
            benchmark.effect_execution_failures(metrics, sample=sample),
            [],
        )

        for expectation in benchmark.EFFECT_EXECUTION_EXPECTATIONS:
            with self.subTest(matrix_key=expectation.matrix_key):
                mismatched = dict(sample)
                mismatched[expectation.matrix_key] = (
                    int(mismatched[expectation.matrix_key]) + 1
                )
                self.assertIn(
                    expectation.failure_message,
                    benchmark.effect_execution_failures(
                        metrics,
                        sample=mismatched,
                    ),
                )

        self.assertIn(
            "effect execution matrix contract incomplete",
            benchmark.effect_execution_failures(
                metrics,
                sample={"expected_effect_execution_schema": 1},
            ),
        )

    def test_effect_execution_matrix_contract_is_optional_and_stable_only(self) -> None:
        missing_metrics = benchmark.effect_execution_metrics("")
        self.assertEqual(
            benchmark.effect_execution_failures(
                missing_metrics,
                sample={"expected_effect_execution_schema": 1},
            ),
            ["effect execution evidence missing"],
        )
        self.assertEqual(
            benchmark.effect_execution_failures(
                missing_metrics,
                sample={
                    "expected_effect_execution_canonical_sha256": "0" * 64,
                    "expected_effect_execution_completed_frame_ids": [1],
                    "expected_effect_execution_cpu_invocation_count": 3,
                },
            ),
            [],
        )

    def test_effect_execution_require_is_conditioned_on_static_demand(self) -> None:
        empty_disposition = static_effect_disposition()
        empty_metrics = benchmark.effect_execution_metrics(
            "",
            empty_disposition,
        )
        self.assertEqual(
            benchmark.effect_execution_failures(
                empty_metrics,
                require_evidence=True,
                static_disposition=empty_disposition,
            ),
            [],
        )
        stale_zero_sample = {
            expectation.matrix_key: (
                1 if expectation.metric_key == "schema_version" else 0
            )
            for expectation in benchmark.EFFECT_EXECUTION_EXPECTATIONS
        }
        self.assertEqual(
            benchmark.effect_execution_failures(
                empty_metrics,
                require_evidence=True,
                sample=stale_zero_sample,
                static_disposition=empty_disposition,
            ),
            ["effect execution evidence missing"],
        )

        inactive_disposition = static_effect_disposition(groups=[{
            "layer_id": 1,
            "kind": "inactive",
        }])
        self.assertEqual(
            benchmark.effect_execution_failures(
                benchmark.effect_execution_metrics("", inactive_disposition),
                require_evidence=True,
                static_disposition=inactive_disposition,
            ),
            [],
        )

        invalid_disposition = static_effect_disposition(
            validation_failures=["invalid static disposition"]
        )
        self.assertEqual(
            benchmark.effect_execution_failures(
                benchmark.effect_execution_metrics("", None),
                require_evidence=True,
                static_disposition=None,
            ),
            ["effect execution evidence missing"],
        )
        self.assertEqual(
            benchmark.effect_execution_failures(
                benchmark.effect_execution_metrics("", invalid_disposition),
                require_evidence=True,
                static_disposition=invalid_disposition,
            ),
            ["effect execution static disposition unavailable or invalid"],
        )
        invalid_route = effect_route_event(
            frame=30,
            origin="image",
            layer=1,
            operation="legacy-direct-layer",
        )
        self.assertIn(
            "effect execution static disposition unavailable or invalid",
            benchmark.effect_execution_failures(
                benchmark.effect_execution_metrics(
                    effect_execution_log(30, [], [invalid_route]),
                    invalid_disposition,
                ),
                require_evidence=True,
                static_disposition=invalid_disposition,
            ),
        )

        exact_disposition = static_effect_disposition(
            records=[{
                "layer_id": 1,
                "effect_index": 0,
                "descriptor_id": "1#effect#0",
                "definition_path": "effects/opacity/effect.json",
                "family": "opacity",
                "kind": "strict-dedicated",
            }],
            groups=[{"layer_id": 1, "kind": "authored"}],
        )
        self.assertEqual(
            benchmark.effect_execution_failures(
                benchmark.effect_execution_metrics("", exact_disposition),
                require_evidence=True,
                static_disposition=exact_disposition,
            ),
            ["effect execution evidence missing"],
        )

        for route_kind in (
            "direct",
            "authored",
            "legacy-offscreen",
            "offscreen-passthrough",
            "composite-refused",
        ):
            disposition = static_effect_disposition(groups=[{
                "layer_id": 1,
                "kind": route_kind,
            }])
            with self.subTest(route_kind=route_kind):
                self.assertEqual(
                    benchmark.effect_execution_failures(
                        benchmark.effect_execution_metrics("", disposition),
                        require_evidence=True,
                        static_disposition=disposition,
                    ),
                    ["effect execution evidence missing"],
                )

    def test_route_only_execution_registers_zero_counts_but_requires_evidence(
        self,
    ) -> None:
        disposition = static_effect_disposition(groups=[{
            "layer_id": 1,
            "kind": "offscreen-passthrough",
        }])
        route = effect_route_event(
            frame=31,
            origin="image",
            layer=1,
            operation="legacy-neutral-copy",
        )
        metrics = benchmark.effect_execution_metrics(
            effect_execution_log(31, [], [route]),
            disposition,
        )
        sample = {
            expectation.matrix_key: metrics[expectation.metric_key]
            for expectation in benchmark.EFFECT_EXECUTION_EXPECTATIONS
        }
        self.assertEqual(sample["expected_effect_execution_schema"], 1)
        self.assertTrue(all(
            value == 0
            for key, value in sample.items()
            if key != "expected_effect_execution_schema"
        ))
        self.assertEqual(
            benchmark.effect_execution_failures(
                metrics,
                require_evidence=True,
                sample=sample,
                static_disposition=disposition,
            ),
            [],
        )

        missing = benchmark.effect_execution_metrics("", disposition)
        self.assertEqual(
            benchmark.effect_execution_failures(
                missing,
                sample=sample,
                static_disposition=disposition,
            ),
            ["effect execution evidence missing"],
        )

    def test_authored_color_and_godrays_counts_are_exact_gates(self) -> None:
        preview = (
            "authoredEffectGraphTintCount: 24\n"
            "authoredEffectGraphColorGradingCount: 1\n"
            "authoredEffectGraphPulseCount: 1\n"
            "authoredEffectGraphGodraysCount: 12\n"
        )
        tint_count = benchmark.authored_effect_graph_tint_count(preview)
        color_grading_count = (
            benchmark.authored_effect_graph_color_grading_count(preview)
        )
        pulse_count = benchmark.authored_effect_graph_pulse_count(preview)
        godrays_count = benchmark.authored_effect_graph_godrays_count(preview)
        self.assertEqual(tint_count, 24)
        self.assertEqual(color_grading_count, 1)
        self.assertEqual(pulse_count, 1)
        self.assertEqual(godrays_count, 12)
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {
                    "expected_authored_effect_graph_tint_count": 24,
                    "expected_authored_effect_graph_color_grading_count": 1,
                    "expected_authored_effect_graph_pulse_count": 1,
                    "expected_authored_effect_graph_godrays_count": 12,
                },
                {"succeeded_layer_ids": [], "failed_layer_ids": []},
                [],
                None,
                tint_count=tint_count,
                color_grading_count=color_grading_count,
                pulse_count=pulse_count,
                godrays_count=godrays_count,
            ),
            [],
        )
        failures = benchmark.authored_effect_graph_failures(
            {
                "expected_authored_effect_graph_tint_count": 0,
                "expected_authored_effect_graph_color_grading_count": 0,
                "expected_authored_effect_graph_pulse_count": 0,
                "expected_authored_effect_graph_godrays_count": 0,
            },
            {"succeeded_layer_ids": [], "failed_layer_ids": []},
            [],
            None,
            tint_count=tint_count,
            color_grading_count=color_grading_count,
            pulse_count=pulse_count,
            godrays_count=godrays_count,
        )
        self.assertIn("authored effect graph Tint count mismatch", failures)
        self.assertIn("authored effect graph Color Grading count mismatch", failures)
        self.assertIn("authored effect graph Pulse count mismatch", failures)
        self.assertIn("authored effect graph Godrays count mismatch", failures)
        self.assertIsNone(benchmark.authored_effect_graph_tint_count(""))
        self.assertIsNone(benchmark.authored_effect_graph_color_grading_count(""))
        self.assertIsNone(benchmark.authored_effect_graph_pulse_count(""))
        self.assertIsNone(benchmark.authored_effect_graph_godrays_count(""))

    def test_image_blend_runtime_pins_planned_and_completed_consumers(self) -> None:
        metrics = benchmark.image_blend_runtime_metrics(
            "imageBlendPlannedCount: 1\n",
            "phase=image-blend layer=1509 status=succeeded\n",
        )
        self.assertEqual(metrics["planned"], 1)
        self.assertEqual(metrics["succeeded_layer_ids"], [1509])
        self.assertEqual(
            benchmark.image_blend_runtime_failures(
                {
                    "expected_image_blend_planned": 1,
                    "required_image_blend_succeeded_layer_ids": [1509],
                },
                metrics,
            ),
            [],
        )

        named_metrics = benchmark.named_target_capture_execution_metrics(
            "phase=named-target-capture layer=125 status=failed\n"
            "phase=named-target-capture layer=125 status=succeeded\n"
            "phase=named-target-capture layer=84 status=failed\n"
        )
        self.assertEqual(named_metrics["succeeded_layer_ids"], [125])
        self.assertEqual(named_metrics["failed_layer_ids"], [84, 125])

        binding_metrics = benchmark.named_target_binding_execution_metrics(
            "phase=named-target-binding layer=70 status=failed\n"
            "phase=named-target-binding layer=70 status=succeeded\n"
            "phase=named-target-binding layer=182 status=failed\n"
        )
        self.assertEqual(binding_metrics["succeeded_layer_ids"], [70])
        self.assertEqual(binding_metrics["failed_layer_ids"], [70, 182])
        self.assertEqual(
            benchmark.named_target_binding_failures(
                {"required_named_target_binding_succeeded_layer_ids": [70, 182]},
                2,
                binding_metrics,
            ),
            [
                "named target binding execution below planned count",
                "named target consumer 182 binding should succeed",
            ],
        )

        missing = benchmark.particle_runtime_metrics("loaded: 20 / 24\n")
        self.assertEqual(
            benchmark.particle_runtime_failures({
                "expected_particle_candidates": 0,
                "minimum_particle_initial_live": 0,
                "expected_particle_refract_loaded": 0,
            }, missing),
            [
                "particle load evidence missing",
                "particle initial live evidence missing",
                "particle refract evidence missing",
            ],
        )


if __name__ == "__main__":
    unittest.main()
