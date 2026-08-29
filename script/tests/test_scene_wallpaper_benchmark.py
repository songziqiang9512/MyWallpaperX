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
DEBUG_POINTER_DRAG_SOURCE = (
    SCRIPT_DIR.parent
    / "MyWallpaperX/App/DebugScenePlaybackRunner+PointerDrag.swift"
)

import scene_wallpaper_benchmark as benchmark
import scene_preview_visual_evidence as visual
import generate_scene_full_matrix as matrix_generator
from script.tests.scene_wallpaper_graph_output_test_support import (
    assert_named_graph_output_publication_has_one_terminal_owner,
    assert_named_provider_terminal,
    assert_visible_provider_requires_compositor_consumption,
    assert_visible_publication_execution_metrics,
)


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
    return "\n".join([
        "authoredEffectGraphStageCount: 1",
        "effectStageDescriptorCount: 2",
        "effectStageParsedCount: 2",
        "effectStageActivityCounts: author-disabled=0,property-inactive=0,layer-hidden=0,active=2",
        "effectStageAdmissionCounts: inactive=0,admitted-dedicated=1,admitted-fallback=0,admitted-generic=1,admitted-passthrough=0,not-admitted=0",
        "effectStageCoverageCounts: inactive=0,complete=2,rejected-missing-graph=0,rejected-ambiguous-graph=0,rejected-graph-mismatch=0,rejected-capability=0",
        "effectStageDescriptorIdentityConserved: true",
        "effectStageActivityConserved: true",
        "effectStageInactiveAdmissionConserved: true",
        "effectStageActiveAdmissionConserved: true",
        "effectStageExecutionIdentityConserved: true",
        "effectStageAdmission: layer=2 effect=0 descriptor=2%23effect%230 activity=active admission=admitted-dedicated coverage=complete backend=fixture-dedicated profile=- reason=- path=effects/fixture-dedicated/effect.json",
        "effectStageAdmission: layer=2 effect=1 descriptor=2%23effect%231 activity=active admission=admitted-generic coverage=complete backend=resolved-material profile=program reason=- path=effects/generic/effect.json",
        "effectStageRuntimeDispositionSchema: 1",
        "effectStageRuntimeRouteScope: unified-effect-graph",
        "effectStageRuntimeDispositionCount: 2",
        "effectStageRuntimeDispositionKindCounts: inactive=0,dedicated=1,fallback=0,passthrough=0,program=1,unsupported=0,unattributed=0",
        "effectStageRuntimeDispositionAttributionCounts: exact-key=2,none=0",
        "effectStageRuntimeDispositionRoleCounts: owner=2,member=0,none=0",
        "effectStaticRouteGroupCount: 1",
        "effectStaticRouteGroupKindCounts: inactive=0,direct=0,resolved=1",
        "effectStageRuntimeDescriptorIdentityConserved: true",
        "effectStageRuntimeGroupIdentityConserved: true",
        "effectStageRuntimeAdmissionIdentityConserved: true",
        "effectStageRuntimeResolvedMaterialOwnershipConserved: true",
        "effectStaticRouteGroup: layer=2 scope=unified-effect-graph kind=resolved effects=2 owners=2 reason=-",
        "effectStageRuntimeDisposition: layer=2 effect=0 descriptor=2%23effect%230 kind=dedicated attribution=exact-key family=fixture-dedicated group=2 role=owner reason=- path=effects/fixture-dedicated/effect.json",
        "effectStageRuntimeDisposition: layer=2 effect=1 descriptor=2%23effect%231 kind=program attribution=exact-key family=resolved-material group=2 role=owner reason=resolved-material-capability-owner path=effects/generic/effect.json",
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
    allocation_generation: int | None = None,
    mapping_generation: int | None = None,
    mapping_before_sha256: str = "a" * 64,
    mapping_after_sha256: str = "b" * 64,
    target_descriptors_sha256: str = "-",
    target_descriptor_counts: str = "-",
    input_width: int = 2_048,
    input_height: int = 1_152,
    history: str = "none",
    reset: str = "-",
    history_rehydrate_copy_count: int = 0,
    history_content_discarded: bool = False,
    runtime_instance_identity: str | None = None,
    effect: int | None = None,
    descriptor_id: str | None = None,
    program: str | None = None,
) -> str:
    final_output = f"output-{transaction}" if publish else "-"
    final_physical = f"physical-{transaction}" if publish else "-"
    final_publication = f"publication-{transaction}" if publish else "-"
    publication_generation = frame if publish else 0
    allocation_generation = (
        frame if allocation_generation is None else allocation_generation
    )
    mapping_generation = frame if mapping_generation is None else mapping_generation
    runtime_field = (
        f"runtime={runtime_instance_identity} "
        if runtime_instance_identity is not None else ""
    )
    effect_field = f"effect={effect} " if effect is not None else ""
    descriptor_field = (
        f"descriptor={descriptor_id} " if descriptor_id is not None else ""
    )
    program_field = f"program={program} " if program is not None else ""
    return (
        "MWX DEBUG SCENE: schema=1 axis=graph-execution "
        f"{runtime_field}frame={frame} layer={layer} "
        f"{effect_field}{descriptor_field}"
        f"trigger={trigger} transaction={transaction} "
        f"{program_field}"
        f"authoredNodes={authored} materialNodes={material} "
        f"copyNodes={copy} swapNodes={swap} composeNodes={compose} "
        f"rejectedNodes={rejected} "
        f"allocationGeneration={allocation_generation} "
        f"mappingGeneration={mapping_generation} "
        f"mappingBeforeSHA256={mapping_before_sha256} "
        f"mappingAfterSHA256={mapping_after_sha256} "
        f"targetDescriptorsSHA256={target_descriptors_sha256} "
        f"targetDescriptorCounts={target_descriptor_counts} "
        f"inputWidth={input_width} inputHeight={input_height} "
        f"historyRehydrateCopyCount={history_rehydrate_copy_count} "
        f"historyContentDiscarded={'true' if history_content_discarded else 'false'} "
        f"history={history} reset={reset} "
        f"finalOutput={final_output} "
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
            "kind": "program",
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


def resolved_graph_passthrough_evidence(
    layer_id: int,
    *,
    include_program: bool = False,
) -> tuple[dict[str, object], dict[str, object]]:
    descriptor_id = f"{layer_id}#effect#0"
    records = [{
        "layer_id": layer_id,
        "effect_index": 0,
        "descriptor_id": descriptor_id,
        "definition_path": f"effects/{layer_id}/inactive/effect.json",
        "family": "initially-inactive-passthrough",
        "kind": "passthrough",
        "role": "member",
        "reason": "initially-inactive-property-stage-passthrough",
    }]
    events = [effect_cpu_event(
        frame=90,
        origin="resolved-material-graph",
        subject="effect",
        layer=layer_id,
        effect=0,
        descriptor=f"{layer_id}%23effect%230",
        family="initially-inactive-passthrough",
        backend=benchmark.RESOLVED_MATERIAL_GRAPH_BACKEND,
    )]
    if include_program:
        records.append({
            "layer_id": layer_id,
            "effect_index": 1,
            "descriptor_id": f"{layer_id}#effect#1",
            "definition_path": f"effects/{layer_id}/program/effect.json",
            "family": "generic-fragment",
            "kind": "program",
            "role": "owner",
            "reason": "resolved-material-capability-owner",
        })
        events.append(effect_cpu_event(
            frame=90,
            origin="resolved-material-graph",
            subject="effect",
            layer=layer_id,
            effect=1,
            descriptor=f"{layer_id}%23effect%231",
            family="generic-fragment",
            backend=benchmark.RESOLVED_MATERIAL_GRAPH_BACKEND,
        ))
    disposition = static_effect_disposition(
        records=records,
        groups=[{"layer_id": layer_id, "kind": "resolved"}],
    )
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
            ])
        )
        self.assertEqual(metrics, {
            "current_binding_count": 3,
            "current_binding_layer_ids": [10, 20, 30],
        })

    def test_scene_script_scalar_metrics_keep_typed_targets_and_values(self) -> None:
        metrics = benchmark.scene_script_scalar_runtime_metrics(
            "scene script VM: schema=quickjs-ng-scalar-v1 bindings=2 targets=2 "
            "route=generic-only fallback=previous-current",
            "\n".join([
                "MWX SceneScript VM: target=effectConstant(layerID: 301, "
                'effectIndex: 1, passIndex: 0, name: "multiply") '
                "callback=completed input=1 output=0 mutations=0 "
                "mutationTargets= route=generic-only",
                "MWX SceneScript VM: target=effectConstant(layerID: 301, "
                'effectIndex: 0, passIndex: 0, name: "multiply") '
                "callback=completed input=1 output=0 mutations=0 "
                "mutationTargets= route=generic-only",
            ]),
        )
        self.assertEqual(metrics["binding_count"], 2)
        self.assertEqual(metrics["target_count"], 2)
        self.assertEqual(metrics["route"], "generic-only")
        self.assertEqual(metrics["fallback"], "previous-current")
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
        self.assertEqual(
            [completion["output"] for completion in metrics["completions"]],
            [0.0, 0.0],
        )

    def test_scene_script_typed_metrics_keep_vec3_layer_completions(self) -> None:
        metrics = benchmark.scene_script_scalar_runtime_metrics(
            "scene script VM: schema=quickjs-ng-typed-v2 bindings=0 "
            "vec3Bindings=3 targets=0 route=generic-only "
            "fallback=previous-current",
            "MWX SceneScript VM: target=layer(layerID: 235, field: "
            "MyWallpaperX.SceneDynamicLayerField.angles) callback=completed "
            "type=vector3 input=vector3(-81,41,0) output=vector3(-81,-43,0) "
            "audio=false audioGeneration=0 route=generic-only",
        )
        self.assertEqual(metrics["binding_count"], 0)
        self.assertEqual(metrics["vec3_binding_count"], 3)
        self.assertEqual(metrics["vec3_completions"], [{
            "layer_id": 235,
            "field": "angles",
            "input": "vector3(-81,41,0)",
            "output": "vector3(-81,-43,0)",
            "route": "generic-only",
        }])

    def test_scene_script_typed_metrics_capture_pass_vec2_and_audio_value(self) -> None:
        metrics = benchmark.scene_script_scalar_runtime_metrics(
            "scene script VM: schema=quickjs-ng-typed-v2 bindings=2 "
            "vectorBindings=25 stringBindings=0 targets=27 "
            "route=generic-only fallback=previous-current",
            "MWX SceneScript VM: target=effectConstant(layerID: 65, "
            "effectIndex: 2, passIndex: 0, name: \"scale\") "
            "callback=completed type=vector2 input=vector2(1.0, 1.0) "
            "output=vector2(1.0, 1.0) audio=true audioGeneration=0 "
            "route=generic-only\n"
            "MWX SceneScript VM: target=effectConstant(layerID: 65, "
            "effectIndex: 2, passIndex: 0, name: \"scale\") "
            "callback=audioValuePublished type=vector2 generation=2 "
            "input=vector2(1.0, 1.0) output=vector2(1.25, 1.25) "
            "route=generic-only",
        )
        self.assertEqual(metrics["binding_count"], 2)
        self.assertEqual(metrics["vector_binding_count"], 25)
        self.assertEqual(metrics["target_count"], 27)
        self.assertEqual(metrics["effect_vector_completions"][0]["output"],
                         "vector2(1.0, 1.0)")
        self.assertEqual(metrics["audio_vector_publications"][0]["generation"], 2)
        self.assertEqual(metrics["audio_vector_publications"][0]["output"],
                         "vector2(1.25, 1.25)")

    def test_scene_script_typed_metrics_capture_pass_scalar_audio_value(self) -> None:
        metrics = benchmark.scene_script_scalar_runtime_metrics(
            "scene script VM: schema=quickjs-ng-typed-v2 bindings=1 "
            "vectorBindings=0 stringBindings=0 targets=1 "
            "route=generic-only fallback=previous-current",
            "MWX SceneScript VM: target=effectConstant(layerID: 1509, "
            "effectIndex: 4, passIndex: 0, name: \"strength\") "
            "callback=audioValuePublished type=scalar generation=3 "
            "input=1 output=1.5 route=generic-only",
        )
        self.assertEqual(metrics["audio_scalar_publications"], [{
            "layer_id": 1509,
            "effect_index": 4,
            "pass_index": 0,
            "constant": "strength",
            "generation": 3,
            "input": 1.0,
            "output": 1.5,
            "route": "generic-only",
        }])

    def test_typed_user_property_scalar_uniform_publications_keep_exact_identity(self) -> None:
        publications = benchmark.typed_user_property_scalar_uniform_publications(
            "MWX typed input publication: channel=user-property "
            "consumer=material-uniform layer=530 effect=1 "
            "descriptor=530#effect#538 node=0 property=newproperty39 "
            "pass=0 constant=strength uniform=g_Strength stage=fragment "
            "type=float frame=4 generation=2 value=0.075000003\n"
            "MWX typed input publication: channel=user-property "
            "consumer=material-uniform layer=410 effect=0 "
            "descriptor=410#effect#1369 node=0 property=newproperty52 "
            "pass=0 constant=direction uniform=g_Direction stage=fragment "
            "type=float frame=3 generation=2 value=37"
        )
        self.assertEqual(publications, [
            {
                "layer_id": 410,
                "effect_index": 0,
                "descriptor_id": "410#effect#1369",
                "node_index": 0,
                "property_key": "newproperty52",
                "pass_index": 0,
                "constant": "direction",
                "uniform": "g_Direction",
                "stage": "fragment",
                "type": "float",
                "frame": 3,
                "generation": 2,
                "value": 37.0,
            },
            {
                "layer_id": 530,
                "effect_index": 1,
                "descriptor_id": "530#effect#538",
                "node_index": 0,
                "property_key": "newproperty39",
                "pass_index": 0,
                "constant": "strength",
                "uniform": "g_Strength",
                "stage": "fragment",
                "type": "float",
                "frame": 4,
                "generation": 2,
                "value": 0.075000003,
            },
        ])

    def test_typed_user_property_scalar_splat_publications_keep_projection(self) -> None:
        publications = (
            benchmark.typed_user_property_scalar_splat_uniform_publications(
                "MWX typed input publication: channel=user-property "
                "consumer=material-uniform layer=525 effect=0 "
                "descriptor=525#effect#528 node=0 property=blurbackground "
                "pass=0 constant=scale uniform=g_Scale stage=vertex "
                "type=float2-scalar-splat frame=0 generation=1 value=0,0"
            )
        )
        self.assertEqual(publications, [{
            "layer_id": 525,
            "effect_index": 0,
            "descriptor_id": "525#effect#528",
            "node_index": 0,
            "property_key": "blurbackground",
            "pass_index": 0,
            "constant": "scale",
            "uniform": "g_Scale",
            "stage": "vertex",
            "type": "float2",
            "source_type": "scalar",
            "projection": "isotropic-splat",
            "frame": 0,
            "generation": 1,
            "value": [0.0, 0.0],
        }])

    def test_typed_user_property_bool_activation_publications_keep_decision(self) -> None:
        publications = benchmark.typed_user_property_bool_activation_publications(
            "MWX typed input publication: channel=user-property "
            "consumer=effect-activation layer=530 effect=1 "
            "descriptor=530#effect#538 property=newproperty7 type=bool "
            "frame=0 generation=1 value=true decision=active"
        )
        self.assertEqual(publications, [{
            "layer_id": 530,
            "effect_index": 1,
            "descriptor_id": "530#effect#538",
            "property_key": "newproperty7",
            "type": "bool",
            "frame": 0,
            "generation": 1,
            "value": True,
            "decision": "active",
        }])

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

    def test_load_matrix_accepts_digest_pinned_suite(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-matrix-") as directory:
            root = Path(directory)
            base_path = root / "base.json"
            suite_path = root / "suite.json"
            base_path.write_text(
                json.dumps({
                    "schema_version": 1,
                    "name": "base",
                    "samples": [{"id": "1", "value": "base"}],
                }),
                encoding="utf-8",
            )
            suite_path.write_text(
                json.dumps({
                    "schema_version": 2,
                    "name": "suite",
                    "base_matrix": "base.json",
                    "base_matrix_sha256": hashlib.sha256(
                        base_path.read_bytes()
                    ).hexdigest(),
                    "sample_ids": ["1"],
                    "sample_overrides": {
                        "1": {"set": {"value": "suite"}}
                    },
                }),
                encoding="utf-8",
            )

            matrix = benchmark.load_matrix(suite_path)
            self.assertEqual(matrix["name"], "suite")
            self.assertEqual(matrix["samples"], [{"id": "1", "value": "suite"}])

    def test_load_matrix_rejects_unknown_schema(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-matrix-") as directory:
            path = Path(directory) / "matrix.json"
            path.write_text(
                json.dumps({"schema_version": 99, "samples": []}),
                encoding="utf-8",
            )
            with self.assertRaises(ValueError):
                benchmark.load_matrix(path)

    def test_load_matrix_requires_click_for_subframe_click(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-matrix-") as directory:
            path = Path(directory) / "matrix.json"
            path.write_text(
                json.dumps({
                    "schema_version": 1,
                    "name": "fixture",
                    "samples": [{
                        "id": "1",
                        "cursor_primary_click_subframe": True,
                    }],
                }),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(
                ValueError,
                "cursor_primary_click_subframe requires cursor_primary_click",
            ):
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

    def test_hover_pointer_stationary_entry_accepts_only_boolean(self) -> None:
        self.assertFalse(benchmark.hover_pointer_stationary_entry({}))
        self.assertTrue(benchmark.hover_pointer_stationary_entry({
            "hover_pointer_stationary_entry": True
        }))
        for value in (0, 1, "true", None):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    benchmark.hover_pointer_stationary_entry({
                        "hover_pointer_stationary_entry": value
                    })

    def test_cursor_primary_click_accepts_only_boolean(self) -> None:
        self.assertFalse(benchmark.cursor_primary_click({}))
        self.assertTrue(benchmark.cursor_primary_click({
            "cursor_primary_click": True
        }))
        for value in (0, 1, "true", None, []):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    benchmark.cursor_primary_click({
                        "cursor_primary_click": value
                    })

    def test_cursor_primary_click_subframe_accepts_only_boolean(self) -> None:
        self.assertFalse(benchmark.cursor_primary_click_subframe({}))
        self.assertTrue(benchmark.cursor_primary_click_subframe({
            "cursor_primary_click_subframe": True
        }))
        for value in (0, 1, "true", None, []):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    benchmark.cursor_primary_click_subframe({
                        "cursor_primary_click_subframe": value
                    })

    def test_cursor_drag_to_normalized_accepts_only_finite_pairs(self) -> None:
        self.assertEqual(
            benchmark.cursor_drag_to_normalized({
                "cursor_drag_to_normalized": [0.25, -0.5]
            }),
            (0.25, -0.5),
        )
        self.assertIsNone(benchmark.cursor_drag_to_normalized({}))
        for value in ([0], [0, 2], [float("nan"), 0], "0,0", [True, 0]):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    benchmark.cursor_drag_to_normalized({
                        "cursor_drag_to_normalized": value
                    })

    def test_cursor_drag_requires_hover_and_owns_primary_edges(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "matrix.json"
            path.write_text(json.dumps({
                "schema_version": 1,
                "name": "fixture",
                "samples": [{
                    "id": "1",
                    "cursor_drag_to_normalized": [0.1, 0.2],
                }],
            }), encoding="utf-8")
            with self.assertRaisesRegex(
                ValueError,
                "cursor_drag_to_normalized requires hover_pointer_normalized",
            ):
                benchmark.load_matrix(path)

    def test_cursor_drag_output_changes_then_preserves_settled_position(self) -> None:
        motion = {
            "before_to_hover": {"changed_ratio": 0.08},
            "hover_to_after": {"changed_ratio": 0.0},
        }
        sample = {
            "minimum_hover_changed_ratio": 0.05,
            "maximum_drag_settle_changed_ratio": 0.001,
        }
        self.assertEqual(
            benchmark.cursor_interaction_output_failures(
                sample, motion, (0.6, 0.4)
            ),
            [],
        )
        self.assertIn(
            "drag interaction output evidence below minimum",
            benchmark.cursor_interaction_output_failures(
                sample,
                {**motion, "before_to_hover": {"changed_ratio": 0.01}},
                (0.6, 0.4),
            ),
        )
        self.assertIn(
            "drag interaction output did not preserve settled position",
            benchmark.cursor_interaction_output_failures(
                sample,
                {**motion, "hover_to_after": {"changed_ratio": 0.01}},
                (0.6, 0.4),
            ),
        )

    def test_debug_runner_sequences_drag_between_press_and_release(self) -> None:
        source = DEBUG_POINTER_DRAG_SOURCE.read_text(encoding="utf-8")
        self.assertIn("--mwx-debug-scene-cursor-drag-to-json", source)
        press = source.index('state: "press"')
        drag = source.index('state: "drag"', press)
        release = source.index('state: "release"', drag)
        hover = source.index('reason: "hover"', release)
        outside = source.index("setPointerOutside()", hover)
        after = source.index('reason: "after"', outside)
        self.assertLess(press, drag)
        self.assertLess(drag, release)
        self.assertLess(release, hover)
        self.assertLess(hover, outside)
        self.assertLess(outside, after)

    def test_debug_runner_sequences_before_hover_and_after_frames(self) -> None:
        source = DEBUG_RUNNER_SOURCE.read_text(encoding="utf-8")
        self.assertIn("--mwx-debug-scene-hover-pointer-json", source)
        self.assertIn("--mwx-debug-scene-hover-pointer-stationary-entry", source)
        self.assertIn("--mwx-debug-scene-primary-click", source)
        self.assertIn("--mwx-debug-scene-primary-click-subframe", source)
        self.assertIn("--mwx-debug-scene-after-snapshot-delay", source)
        self.assertIn("--mwx-debug-scene-periodic-snapshot-interval", source)
        self.assertIn('String(format: "series-%04d", index)', source)
        self.assertIn("interval >= 0.08", source)
        self.assertIn(
            "schedulePeriodicSnapshots(outputDirectory: evidenceDirectory)",
            source,
        )
        prelaunch_outside = source.index(
            "SceneDesktopWallpaperHost.shared.setDebugPointerOverride(.init())"
        )
        launch = source.index(
            "let model = try SceneDesktopWallpaperHost.shared.launch("
        )
        self.assertLess(prelaunch_outside, launch)
        before = source.index('requestSnapshot(reason: "before"')
        move_state = source.index("movePointer(to: hoverPointer)", before)
        hold_state = source.index("holdPointer(at: hoverPointer)", move_state)
        hover = source.index('reason: "hover"', hold_state)
        outside = source.index("setPointerOutside()", hover)
        after = source.index('reason: "after"', outside)
        self.assertLess(before, move_state)
        self.assertLess(move_state, hold_state)
        self.assertLess(hold_state, hover)
        self.assertLess(hover, outside)
        self.assertLess(outside, after)
        self.assertIn("previous: previous", source)
        self.assertIn("state=move", source)
        self.assertIn('state: "hold"', source)
        press = source.index('state: "press"', hold_state)
        release = source.index('state: "release"', press)
        self.assertLess(press, release)
        self.assertLess(release, hover)
        subframe_branch = source.index("if requestedPrimaryClickSubframe", press)
        subframe_release = source.index(
            'primaryButtonIsDown: false, state: "release"',
            subframe_branch,
        )
        subframe_wait = source.index(
            "DispatchQueue.main.asyncAfter",
            subframe_release,
        )
        self.assertLess(subframe_release, subframe_wait)

    def test_cursor_ripple_persistence_accepts_expansion_and_decay_after_exit(
        self,
    ) -> None:
        def row(
            *, active: int, bounds: str, maximum: int, inside: bool,
            movement: float,
        ) -> str:
            return (
                "MWX DEBUG SCENE: phase=cursor-ripple-state layer=68 effect=0 "
                "descriptor=68%23effect%230 status=completed width=256 height=256 "
                f"output=ObjectIdentifier(0x1) activePixels={active} "
                f"bounds={bounds} max={maximum} sum={active * maximum} "
                "current=0.500000,0.500000 previous=0.400000,0.500000 "
                f"inside={'true' if inside else 'false'} previousInside=true "
                f"movement={movement:.6f} mask=false frameTime=0.016667"
            )

        log_text = "\n".join([
            row(active=600, bounds="90,120,125,136", maximum=190,
                inside=True, movement=0.04),
            row(active=900, bounds="86,116,129,140", maximum=184,
                inside=True, movement=0),
            row(active=1300, bounds="82,112,133,144", maximum=176,
                inside=False, movement=0),
            row(active=1900, bounds="76,106,139,150", maximum=160,
                inside=False, movement=0),
            row(active=2600, bounds="70,100,145,156", maximum=142,
                inside=False, movement=0),
        ])
        metrics = benchmark.cursor_ripple_persistence_metrics(log_text)
        self.assertTrue(metrics["accepted"])
        self.assertEqual(metrics["record_count"], 5)
        self.assertEqual(metrics["selected"]["post_exit_nonzero_frames"], 3)
        self.assertTrue(metrics["selected"]["expanded_width"])
        self.assertTrue(metrics["selected"]["expanded_height"])
        self.assertTrue(metrics["selected"]["peak_decayed"])
        self.assertEqual(
            benchmark.cursor_ripple_persistence_failures(metrics, True),
            [],
        )

    def test_cursor_ripple_persistence_rejects_missing_movement_injection(
        self,
    ) -> None:
        log_text = (
            "MWX DEBUG SCENE: phase=cursor-ripple-state layer=68 effect=0 "
            "descriptor=68%23effect%230 status=completed width=256 height=256 "
            "output=ObjectIdentifier(0x1) activePixels=12 bounds=1,1,3,4 "
            "max=20 sum=100 current=0.5,0.5 previous=0.5,0.5 "
            "inside=true previousInside=true movement=0.000000 mask=false"
        )
        metrics = benchmark.cursor_ripple_persistence_metrics(log_text)
        self.assertFalse(metrics["accepted"])
        self.assertEqual(
            benchmark.cursor_ripple_persistence_failures(metrics, True),
            ["cursor ripple movement injection evidence missing"],
        )

    def test_cursor_ripple_persistence_rejects_immediate_disappearance(self) -> None:
        injection = (
            "MWX DEBUG SCENE: phase=cursor-ripple-state layer=68 effect=0 "
            "descriptor=68%23effect%230 status=completed width=256 height=256 "
            "output=ObjectIdentifier(0x1) activePixels=600 bounds=90,120,125,136 "
            "max=190 sum=114000 current=0.5,0.5 previous=0.4,0.5 "
            "inside=true previousInside=true movement=0.040000 mask=false"
        )
        vanished = (
            "MWX DEBUG SCENE: phase=cursor-ripple-state layer=68 effect=0 "
            "descriptor=68%23effect%230 status=completed width=256 height=256 "
            "output=ObjectIdentifier(0x1) activePixels=0 bounds=256,256,-1,-1 "
            "max=0 sum=0 current=0.5,0.5 previous=0.5,0.5 "
            "inside=false previousInside=true movement=0.000000 mask=false"
        )
        metrics = benchmark.cursor_ripple_persistence_metrics(
            "\n".join([injection, vanished, vanished, vanished])
        )
        failures = benchmark.cursor_ripple_persistence_failures(metrics, True)
        self.assertIn(
            "cursor ripple disappeared before three post-exit GPU frames",
            failures,
        )
        self.assertIn(
            "cursor ripple extent did not expand after pointer exit",
            failures,
        )

    def test_cursor_ripple_visible_output_must_persist_expand_and_decay(self) -> None:
        def row(
            *, changed: int, bounds: str, maximum: int, inside: bool,
            movement: float,
        ) -> str:
            return (
                "MWX DEBUG SCENE: phase=cursor-ripple-visible layer=68 effect=0 "
                "descriptor=68%23effect%230 status=completed width=1168 height=1168 "
                f"changedPixels={changed} bounds={bounds} max={maximum} "
                f"sum={changed * maximum} current=0.500000,0.500000 "
                "previous=0.400000,0.500000 "
                f"inside={'true' if inside else 'false'} previousInside=true "
                f"movement={movement:.6f}"
            )

        log_text = "\n".join([
            row(changed=800, bounds="420,500,560,540", maximum=190,
                inside=True, movement=0.04),
            row(changed=1200, bounds="400,480,580,560", maximum=174,
                inside=False, movement=0),
            row(changed=1900, bounds="370,450,610,590", maximum=158,
                inside=False, movement=0),
            row(changed=2600, bounds="330,410,650,630", maximum=140,
                inside=False, movement=0),
            row(changed=1000, bounds="300,380,680,660", maximum=80,
                inside=False, movement=0),
        ])
        metrics = benchmark.cursor_ripple_visible_metrics(log_text)
        self.assertTrue(metrics["accepted"])
        self.assertEqual(metrics["selected"]["post_exit_nonzero_frames"], 4)
        self.assertTrue(metrics["selected"]["visible_sum_decayed"])
        self.assertEqual(benchmark.cursor_ripple_visible_failures(metrics, True), [])

        missing = benchmark.cursor_ripple_visible_metrics("")
        self.assertEqual(
            benchmark.cursor_ripple_visible_failures(missing, True),
            ["cursor ripple visible output evidence missing"],
        )

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

    def test_resize_sequence_argument_is_forwarded_atomically(self) -> None:
        command = ["MyWallpaperX"]
        benchmark.append_resize_sequence_argument(
            command,
            "1.5:0.6,3.5:1.0",
        )
        self.assertEqual(command, [
            "MyWallpaperX",
            "--mwx-debug-scene-resize-sequence",
            "1.5:0.6,3.5:1.0",
        ])

        unchanged = ["MyWallpaperX"]
        benchmark.append_resize_sequence_argument(unchanged, None)
        self.assertEqual(unchanged, ["MyWallpaperX"])

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

    def test_failed_and_passing_runtime_are_removed_without_keep_flag(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-retention-") as directory:
            runtime_root = Path(directory) / "runtime"
            app_root = runtime_root / "runtime-app-fixture"
            runtime_binary = (
                app_root / "MyWallpaperX.app/Contents/MacOS/MyWallpaperX"
            )
            runtime_binary.parent.mkdir(parents=True)
            runtime_binary.write_bytes(b"binary")
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
            app_identity = {
                "runtime_root_path": str(app_root),
                "runtime_bundle_path": str(app_root / "MyWallpaperX.app"),
                "runtime_executable_path": str(runtime_binary),
                "runtime_retained": True,
            }

            benchmark.apply_runtime_retention(
                runtime_root,
                app_identity,
                results,
                keep_runtime=False,
            )

            self.assertFalse((runtime_root / "runtime-samples/1").exists())
            self.assertFalse((runtime_root / "runtime-homes/1").exists())
            self.assertFalse((runtime_root / "runtime-samples/2").exists())
            self.assertFalse((runtime_root / "runtime-homes/2").exists())
            self.assertFalse(results[0]["runtime_retained"])
            self.assertFalse(results[1]["runtime_retained"])
            self.assertFalse(app_identity["runtime_retained"])
            self.assertFalse(runtime_root.exists())

    def test_keep_flag_retains_failed_and_passing_runtime(self) -> None:
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
                keep_runtime=True,
            )

            self.assertTrue((runtime_root / "runtime-samples/1").is_dir())
            self.assertTrue((runtime_root / "runtime-homes/1").is_dir())
            self.assertTrue((runtime_root / "runtime-samples/2").is_dir())
            self.assertTrue((runtime_root / "runtime-homes/2").is_dir())
            self.assertTrue(results[0]["runtime_retained"])
            self.assertTrue(results[1]["runtime_retained"])
            self.assertTrue(app_identity["runtime_retained"])

    def test_runtime_cleanup_retries_read_only_directories(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-retention-") as directory:
            runtime_root = Path(directory) / "runtime"
            runtime_sample = runtime_root / "runtime-samples/1"
            runtime_home = runtime_root / "runtime-homes/1"
            runtime_binary = (
                runtime_root
                / "runtime-app-fixture/MyWallpaperX.app/Contents/MacOS/MyWallpaperX"
            )
            read_only = runtime_sample / "shaders"
            read_only.mkdir(parents=True)
            (read_only / "author-source.frag").write_text("void main() {}")
            read_only.chmod(0o500)
            runtime_home.mkdir(parents=True)
            runtime_binary.parent.mkdir(parents=True)
            runtime_binary.write_bytes(b"binary")
            result = {
                "id": "1",
                "passed": False,
                "runtime_sample": str(runtime_sample),
                "runtime_home": str(runtime_home),
                "runtime_retained": True,
            }
            app_identity = {
                "runtime_root_path": str(runtime_root / "runtime-app-fixture"),
                "runtime_bundle_path": str(
                    runtime_root / "runtime-app-fixture/MyWallpaperX.app"
                ),
                "runtime_executable_path": str(runtime_binary),
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
        camera_shake = benchmark.CAMERA_SHAKE_RE.search(
            "camera shake: status=executable enabled=true amplitude=2.3e-1 "
            "roughness=1.0 speed=1.25"
        )
        invalid_camera_shake = benchmark.CAMERA_SHAKE_RE.search(
            "camera shake: status=invalid enabled=invalid amplitude=invalid "
            "roughness=invalid speed=invalid"
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
        self.assertEqual(camera_shake.group("status"), "executable")
        self.assertEqual(camera_shake.group("enabled"), "true")
        self.assertEqual(float(camera_shake.group("amplitude")), 0.23)
        self.assertEqual(float(camera_shake.group("roughness")), 1.0)
        self.assertEqual(float(camera_shake.group("speed")), 1.25)
        self.assertEqual(invalid_camera_shake.group("status"), "invalid")
        self.assertEqual(invalid_camera_shake.group("amplitude"), "invalid")

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

    def test_dynamic_values_fault_argument_is_explicit_and_frame_bounded(self) -> None:
        command = ["MyWallpaperX"]
        benchmark.append_dynamic_values_fault_argument(command, 42)
        self.assertEqual(command, [
            "MyWallpaperX",
            "--mwx-debug-scene-drop-dynamic-values-frame",
            "42",
        ])

        unchanged = ["MyWallpaperX"]
        benchmark.append_dynamic_values_fault_argument(unchanged, None)
        self.assertEqual(unchanged, ["MyWallpaperX"])

        self.assertEqual(benchmark.positive_uint64("1"), 1)
        self.assertEqual(benchmark.positive_uint64(str((1 << 64) - 1)), (1 << 64) - 1)
        for invalid in ("0", "-1", str(1 << 64), "1.5"):
            with self.assertRaises(benchmark.argparse.ArgumentTypeError):
                benchmark.positive_uint64(invalid)

    def test_media_properties_arguments_are_atomic_and_bounded(self) -> None:
        command = ["MyWallpaperX"]
        failures: list[str] = []
        benchmark.append_media_properties_arguments(
            command,
            "春日歌",
            "Fixture Artist 🎵",
            failures,
        )
        self.assertEqual(failures, [])
        self.assertEqual(command, [
            "MyWallpaperX",
            "--mwx-debug-scene-media-title",
            "春日歌",
            "--mwx-debug-scene-media-artist",
            "Fixture Artist 🎵",
        ])

        empty_command = ["MyWallpaperX"]
        empty_failures: list[str] = []
        benchmark.append_media_properties_arguments(
            empty_command,
            "",
            "",
            empty_failures,
        )
        self.assertEqual(empty_failures, [])
        self.assertEqual(empty_command[-4:], [
            "--mwx-debug-scene-media-title",
            "",
            "--mwx-debug-scene-media-artist",
            "",
        ])

        exact_limit_command = ["MyWallpaperX"]
        exact_limit_failures: list[str] = []
        benchmark.append_media_properties_arguments(
            exact_limit_command,
            "a" * (4 * 1_024),
            "artist",
            exact_limit_failures,
        )
        self.assertEqual(exact_limit_failures, [])
        self.assertEqual(len(exact_limit_command), 5)

        invalid_pairs = (
            ("title", None, "media properties require title and artist together"),
            (None, "artist", "media properties require title and artist together"),
            (7, "artist", "invalid media properties"),
            ("title\nline", "artist", "invalid media properties"),
            ("界" * 1_366, "artist", "invalid media properties"),
            ("\ud800", "artist", "invalid media properties"),
        )
        for title, artist, expected_failure in invalid_pairs:
            invalid_command = ["MyWallpaperX"]
            invalid_failures: list[str] = []
            benchmark.append_media_properties_arguments(
                invalid_command,
                title,
                artist,
                invalid_failures,
            )
            self.assertEqual(invalid_failures, [expected_failure])
            self.assertEqual(invalid_command, ["MyWallpaperX"])

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

    def test_media_thumbnail_store_metrics_preserve_pending_and_clear_state(self) -> None:
        log = """
MWX media thumbnail store: phase=ready generation=1 hasCurrent=true
MWX media thumbnail store: phase=pending-last-ready requestedGeneration=2 readyGeneration=1 hasCurrent=true
MWX media thumbnail store: phase=ready generation=2 hasCurrent=true
MWX DEBUG SCENE: phase=media-thumbnail-cleared
MWX media thumbnail store: phase=pending-last-ready requestedGeneration=3 readyGeneration=2 hasCurrent=true
MWX media thumbnail store: phase=ready generation=3 hasCurrent=false
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
                    },
                    {
                        "generation": 2,
                        "has_current": True,
                    },
                    {
                        "generation": 3,
                        "has_current": False,
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

    def test_audio_scaled_value_evidence_joins_typed_targets_and_live_batches(self) -> None:
        preview = (
            "scene audio scaled value: schema=bounded-audio-scaled-value-v1 "
            "bindings=3 rejectedParticleLayerIDs=[1991, 85705] "
            "rejectedScaleLayerIDs=[9002] resolution=16\n"
        )
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "scene-audio-scaled-value-evidence.json"
            path.write_text(json.dumps({
                "schemaVersion": 1,
                "frameIndex": 420,
                "audioGeneration": 7,
                "audioWasSilent": True,
                "bindings": [
                    {"layerID": 31057, "target": "particle.rate",
                     "effectiveValue": [1.6],
                     "liveParticleCount": 502},
                    {"layerID": 1314, "target": "layer.scale",
                     "effectiveValue": [0.8, 0.8, 0.8],
                     "liveParticleCount": None},
                    {"layerID": 5944, "target": "particle.rate",
                     "effectiveValue": [0.8],
                     "liveParticleCount": 239},
                ],
            }), encoding="utf-8")
            metrics = benchmark.audio_scaled_value_evidence_metrics(preview, path)
        self.assertTrue(metrics["has_evidence"])
        self.assertEqual(metrics["expected_binding_count"], 3)
        self.assertEqual(metrics["rejected_particle_layer_ids"], [1991, 85705])
        self.assertEqual(metrics["rejected_scale_layer_ids"], [9002])
        self.assertEqual(metrics["frame_index"], 420)
        self.assertTrue(metrics["audio_was_silent"])
        self.assertEqual(
            metrics["bindings"],
            [
                {"layer_id": 1314, "target": "layer.scale",
                 "effective_value": [0.8, 0.8, 0.8],
                 "live_particle_count": None},
                {"layer_id": 5944, "target": "particle.rate",
                 "effective_value": [0.8],
                 "live_particle_count": 239},
                {"layer_id": 31057, "target": "particle.rate",
                 "effective_value": [1.6],
                 "live_particle_count": 502},
            ],
        )
        self.assertEqual(metrics["failures"], [])

        missing = benchmark.audio_scaled_value_evidence_metrics(
            preview, Path("/definitely/missing/audio-scaled-value.json")
        )
        self.assertEqual(
            missing["failures"], ["audio scaled value evidence missing"]
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
    def test_authored_workshop_shadow_count_is_an_exact_gate(self) -> None:
        preview = "authoredEffectGraphWorkshopShadowCount: 1\n"
        count = benchmark.authored_effect_graph_workshop_shadow_count(preview)
        self.assertEqual(count, 1)
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_workshop_shadow_count": 1},
                workshop_shadow_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Workshop Shadow count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_workshop_shadow_count": 0},
                workshop_shadow_count=count,
            ),
        )

    def test_authored_procedural_noise_count_is_an_exact_gate(self) -> None:
        preview = "authoredEffectGraphProceduralNoiseCount: 3\n"
        count = benchmark.authored_effect_graph_procedural_noise_count(preview)
        self.assertEqual(count, 3)
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_procedural_noise_count": 3},
                procedural_noise_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Procedural Noise count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_procedural_noise_count": 0},
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
                film_grain_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Film Grain count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_film_grain_count": 0},
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
                light_shafts_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Light Shafts count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_light_shafts_count": 0},
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
                shake_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Shake count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_shake_count": 0},
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
                None,
                water_flow_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Water Flow count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_water_flow_count": 0},
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
                None,
                water_waves_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Water Waves count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_water_waves_count": 0},
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
                None,
                water_caustics_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Water Caustics count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_water_caustics_count": 0},
                None,
                water_caustics_count=count,
            ),
        )
        self.assertIsNone(benchmark.authored_effect_graph_water_caustics_count(""))

    def test_authored_cursor_ripple_count_is_an_exact_gate(self) -> None:
        preview = (
            "authoredEffectGraphCursorRippleCount: 3\n"
            "authoredEffectGraphCursorRippleIsolatedCount: 0\n"
            "authoredEffectGraphCursorRippleOmittedEffects: \n"
        )
        count = benchmark.authored_effect_graph_cursor_ripple_count(preview)
        self.assertEqual(count, 3)
        self.assertEqual(
            benchmark.authored_effect_graph_cursor_ripple_isolated_count(preview),
            0,
        )
        self.assertEqual(
            benchmark.authored_effect_graph_cursor_ripple_omitted_effects(preview),
            [],
        )
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {
                    "expected_authored_effect_graph_cursor_ripple_count": 3,
                    "expected_authored_effect_graph_cursor_ripple_isolated_count": 0,
                    "expected_authored_effect_graph_cursor_ripple_omitted_effects": [],
                },
                None,
                cursor_ripple_count=count,
                cursor_ripple_isolated_count=0,
                cursor_ripple_omitted_effects=[],
            ),
            [],
        )
        self.assertIn(
            "Cursor Ripple count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_cursor_ripple_count": 0},
                None,
                cursor_ripple_count=count,
            )[0],
        )
        self.assertIn(
            "isolated Cursor Ripple count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_cursor_ripple_isolated_count": 1},
                None,
                cursor_ripple_isolated_count=0,
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

    def test_interactive_effect_counts_are_exact_gates(self) -> None:
        preview = (
            "authoredEffectGraphFoliageSwayCount: 3\n"
            "authoredEffectGraphWaterRippleCount: 2\n"
            "authoredEffectGraphIrisInlineSuffixCount: 0\n"
        )
        self.assertEqual(
            benchmark.authored_effect_graph_foliage_sway_count(preview), 3
        )
        self.assertEqual(
            benchmark.authored_effect_graph_water_ripple_count(preview), 2
        )
        self.assertEqual(
            benchmark.authored_effect_graph_iris_inline_suffix_count(preview), 0
        )
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {
                    "expected_authored_effect_graph_foliage_sway_count": 3,
                    "expected_authored_effect_graph_water_ripple_count": 2,
                    "expected_authored_effect_graph_iris_inline_suffix_count": 0,
                },
                None,
                foliage_sway_count=3,
                water_ripple_count=2,
                iris_inline_suffix_count=0,
            ),
            [],
        )
        failures = benchmark.authored_effect_graph_failures(
            {
                "expected_authored_effect_graph_foliage_sway_count": 0,
                "expected_authored_effect_graph_water_ripple_count": 0,
                "expected_authored_effect_graph_iris_inline_suffix_count": 1,
            },
            None,
            foliage_sway_count=3,
            water_ripple_count=2,
            iris_inline_suffix_count=0,
        )
        self.assertIn("authored effect graph Foliage Sway count mismatch", failures)
        self.assertIn("authored effect graph Water Ripple count mismatch", failures)
        self.assertIn(
            "authored effect graph Iris inline suffix count mismatch", failures
        )
        self.assertIsNone(benchmark.authored_effect_graph_foliage_sway_count(""))
        self.assertIsNone(benchmark.authored_effect_graph_water_ripple_count(""))
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
                None,
                clipping_mask_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Clipping Mask count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_clipping_mask_count": 0},
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
                None,
                blend_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Blend count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_blend_count": 0},
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
                None,
                transform_count=count,
                transform_static_fallback_count=fallback_count,
                transform_static_fallback_diagnostics=parsed_diagnostics,
            ),
            [],
        )
        failures = benchmark.authored_effect_graph_failures(
            sample,
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
            "authored_effect_graph_iris_inline_suffix_count": 0,
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

    def test_tracked_full_matrix_retires_legacy_effect_counts_only_with_owner_transfer(self) -> None:
        matrix = json.loads(
            (SCRIPT_DIR / "scene_wallpaper_full_sample_matrix.json").read_text(
                encoding="utf-8"
            )
        )
        samples = matrix["samples"]
        self.assertEqual(len(samples), 45)
        owner_transfer_keys = {
            "expected_authored_effect_graph_opacity_count",
            "expected_authored_effect_graph_opacity_layer_ids",
            "expected_authored_effect_graph_color_key_count",
            "expected_authored_effect_graph_workshop_shadow_count",
            "expected_authored_effect_graph_procedural_noise_count",
            "expected_authored_effect_graph_film_grain_count",
            "expected_authored_effect_graph_transform_count",
            "expected_authored_effect_graph_transform_static_fallback_count",
            "expected_authored_effect_graph_transform_static_fallback_diagnostics",
            "expected_authored_effect_graph_light_shafts_count",
            "expected_authored_effect_graph_shake_count",
            "expected_authored_effect_graph_water_flow_count",
            "expected_authored_effect_graph_water_waves_count",
            "expected_authored_effect_graph_blend_count",
            "expected_authored_effect_graph_authored_shader_count",
            "expected_authored_effect_graph_foliage_sway_count",
            "expected_authored_effect_graph_water_ripple_count",
        }
        all_legacy_keys = {
            expectation.matrix_key
            for expectation in benchmark.AUTHORED_EFFECT_RUNTIME_EXPECTATIONS
        }
        for sample in samples:
            with self.subTest(sample_id=sample["id"]):
                present = owner_transfer_keys.intersection(sample)
                self.assertIn(len(present), (0, len(owner_transfer_keys)))
                if not present:
                    self.assertFalse(all_legacy_keys.intersection(sample))
                    replacement = sample.get(
                        "expected_resolved_material_graph_succeeded_layer_ids"
                    )
                    self.assertIsInstance(replacement, list)
                    self.assertTrue(replacement)

    def test_authored_shader_count_is_an_exact_gate(self) -> None:
        preview = "authoredEffectGraphAuthoredShaderCount: 1\n"
        count = benchmark.authored_effect_graph_authored_shader_count(preview)
        self.assertEqual(count, 1)
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_authored_shader_count": 1},
                None,
                authored_shader_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph authored shader count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_authored_shader_count": 0},
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
                None,
                scroll_count=count,
            ),
            [],
        )
        self.assertIn(
            "authored effect graph Scroll count mismatch",
            benchmark.authored_effect_graph_failures(
                {"expected_authored_effect_graph_scroll_count": 0},
                None,
                scroll_count=count,
            ),
        )
        self.assertIsNone(benchmark.authored_effect_graph_scroll_count(""))


    def test_effect_stage_admission_metrics_are_structured_and_conserved(self) -> None:
        coverage = (
            "inactive=1,complete=1,rejected-missing-graph=0,"
            "rejected-ambiguous-graph=0,rejected-graph-mismatch=0,"
            "rejected-capability=1"
        )
        preview = "\n".join([
            "authoredEffectGraphStageCount: 1",
            "effectStageDescriptorCount: 3",
            "effectStageParsedCount: 3",
            "effectStageActivityCounts: author-disabled=1,property-inactive=0,layer-hidden=0,active=2",
            "effectStageAdmissionCounts: inactive=1,admitted-dedicated=1,admitted-fallback=0,admitted-generic=0,admitted-passthrough=0,not-admitted=1",
            f"effectStageCoverageCounts: {coverage}",
            "effectStageDescriptorIdentityConserved: true",
            "effectStageActivityConserved: true",
            "effectStageInactiveAdmissionConserved: true",
            "effectStageActiveAdmissionConserved: true",
            "effectStageExecutionIdentityConserved: true",
            "effectStageAdmission: layer=1 effect=0 descriptor=1%23effect%230 activity=author-disabled admission=inactive coverage=inactive backend=- profile=- reason=- path=effects/disabled/effect.json",
            "effectStageAdmission: layer=1 effect=1 descriptor=1%23effect%231 activity=active admission=admitted-dedicated coverage=complete backend=fixture-dedicated profile=- reason=- path=effects/fixture-dedicated/effect.json",
            "effectStageAdmission: layer=1 effect=2 descriptor=1%23effect%232 activity=active admission=not-admitted coverage=rejected-capability backend=- profile=- reason=unified-capability-unavailable path=effects/unknown/effect.json",
        ])
        metrics = benchmark.effect_stage_admission_metrics(preview)
        self.assertTrue(metrics["has_evidence"])
        self.assertEqual(metrics["schema_version"], 1)
        self.assertEqual(metrics["descriptor_count"], 3)
        self.assertEqual(metrics["parsed_count"], 3)
        self.assertEqual(metrics["activity_counts"]["active"], 2)
        self.assertEqual(metrics["admission_counts"]["admitted-dedicated"], 1)
        self.assertEqual(metrics["records"][0]["descriptor_id"], "1#effect#0")
        self.assertEqual(metrics["validation_failures"], [])
        self.assertEqual(len(metrics["canonical_sha256"]), 64)
        self.assertEqual(
            benchmark.effect_stage_admission_failures(
                {},
                metrics,
            ),
            [],
        )

        duplicate = preview.replace(
            "effect=2 descriptor=1%23effect%232",
            "effect=1 descriptor=1%23effect%231",
        )
        duplicate_metrics = benchmark.effect_stage_admission_metrics(duplicate)
        self.assertIn(
            "effect stage admission identity duplicated",
            duplicate_metrics["validation_failures"],
        )

        invalid_combination = preview.replace(
            "admission=not-admitted coverage=rejected-capability backend=- profile=- reason=unified-capability-unavailable",
            "admission=not-admitted coverage=complete backend=fixture-dedicated profile=- reason=unified-capability-unavailable",
        )
        invalid_combination_metrics = (
            benchmark.effect_stage_admission_metrics(invalid_combination)
        )
        self.assertIn(
            "effect stage non-admitted state combination invalid",
            invalid_combination_metrics["validation_failures"],
        )

        generic_preview = preview.replace(
            "admitted-dedicated=1,admitted-fallback=0,admitted-generic=0,admitted-passthrough=0",
            "admitted-dedicated=1,admitted-fallback=0,admitted-generic=1,admitted-passthrough=0",
        ).replace(
            "not-admitted=1",
            "not-admitted=0",
        ).replace(
            "complete=1",
            "complete=2",
        ).replace(
            "rejected-capability=1",
            "rejected-capability=0",
        ).replace(
            "admission=not-admitted coverage=rejected-capability backend=- profile=- reason=unified-capability-unavailable",
            "admission=admitted-generic coverage=complete backend=resolved-material profile=program reason=-",
        )
        generic_metrics = benchmark.effect_stage_admission_metrics(
            generic_preview
        )
        self.assertEqual(generic_metrics["validation_failures"], [])

        unified_leaf_metrics = benchmark.effect_stage_admission_metrics(
            generic_preview.replace(
                "admitted-dedicated=1,admitted-fallback=0,admitted-generic=1,admitted-passthrough=0",
                "admitted-dedicated=2,admitted-fallback=0,admitted-generic=1,admitted-passthrough=0",
            ).replace(
                "effectStageDescriptorCount: 3",
                "effectStageDescriptorCount: 4",
            ).replace(
                "effectStageParsedCount: 3",
                "effectStageParsedCount: 4",
            ).replace(
                "author-disabled=1,property-inactive=0,layer-hidden=0,active=2",
                "author-disabled=1,property-inactive=0,layer-hidden=0,active=3",
            ).replace(
                "inactive=1,complete=2",
                "inactive=1,complete=3",
            ) + "\n"
            "effectStageAdmission: layer=2 effect=0 "
            "descriptor=2%23effect%230 activity=active "
            "admission=admitted-dedicated coverage=complete backend=shake "
            "profile=- reason=- path=effects/shake/effect.json"
        )
        self.assertEqual(unified_leaf_metrics["validation_failures"], [])

        property_inactive_metrics = benchmark.effect_stage_admission_metrics(
            generic_preview.replace(
                "property-inactive=0,layer-hidden=0,active=2",
                "property-inactive=1,layer-hidden=0,active=1",
            ).replace(
                "effect=2 descriptor=1%23effect%232 activity=active",
                "effect=2 descriptor=1%23effect%232 activity=property-inactive",
            )
        )
        self.assertEqual(property_inactive_metrics["validation_failures"], [])

        for invalid_owner in (
            "backend=authored-shader profile=program",
            "backend=resolved-material profile=generic-fragment",
        ):
            invalid_generic_metrics = benchmark.effect_stage_admission_metrics(
                generic_preview.replace(
                    "backend=resolved-material profile=program",
                    invalid_owner,
                )
            )
            self.assertIn(
                "effect stage generic owner invalid",
                invalid_generic_metrics["validation_failures"],
            )

        structural_rejection = preview.replace(
            "coverage=rejected-capability backend=- profile=- reason=unified-capability-unavailable",
            "coverage=rejected-graph-mismatch backend=- profile=- reason=stage-graph-mismatch",
        ).replace(
            "rejected-graph-mismatch=0,rejected-capability=1",
            "rejected-graph-mismatch=1,rejected-capability=0",
        )
        structural_metrics = benchmark.effect_stage_admission_metrics(
            structural_rejection
        )
        self.assertIn(
            "effect stage admission structural rejection: rejected-graph-mismatch",
            structural_metrics["validation_failures"],
        )

    def test_effect_local_fallback_admission_and_disposition_are_conserved(
        self,
    ) -> None:
        preview = effect_runtime_disposition_preview().replace(
            "effectStageDescriptorCount: 2",
            "effectStageDescriptorCount: 3",
        ).replace(
            "effectStageParsedCount: 2",
            "effectStageParsedCount: 3",
        ).replace(
            "author-disabled=0,property-inactive=0,layer-hidden=0,active=2",
            "author-disabled=0,property-inactive=0,layer-hidden=0,active=3",
        ).replace(
            "admitted-dedicated=1,admitted-fallback=0,admitted-generic=1,admitted-passthrough=0",
            "admitted-dedicated=1,admitted-fallback=1,admitted-generic=1,admitted-passthrough=0",
        ).replace(
            "inactive=0,complete=2",
            "inactive=0,complete=3",
        ).replace(
            "effectStageRuntimeDispositionCount: 2",
            "effectStageRuntimeDispositionCount: 3",
        ).replace(
            "inactive=0,dedicated=1,fallback=0,passthrough=0,program=1",
            "inactive=0,dedicated=1,fallback=1,passthrough=0,program=1",
        ).replace(
            "exact-key=2,none=0",
            "exact-key=3,none=0",
        ).replace(
            "owner=2,member=0,none=0",
            "owner=3,member=0,none=0",
        ).replace(
            "kind=resolved effects=2 owners=2",
            "kind=resolved effects=3 owners=3",
        ) + "\n" + "\n".join([
            "effectStageAdmission: layer=2 effect=2 "
            "descriptor=2%23effect%232 activity=active "
            "admission=admitted-fallback coverage=complete "
            "backend=visual-failure-passthrough "
            "profile=effect-local-passthrough reason=- "
            "path=effects/broken/effect.json",
            "effectStageRuntimeDisposition: layer=2 effect=2 "
            "descriptor=2%23effect%232 kind=fallback "
            "attribution=exact-key family=visual-failure-passthrough "
            "group=2 role=owner reason=effect-local-visual-failure "
            "path=effects/broken/effect.json",
        ])

        admission = benchmark.effect_stage_admission_metrics(preview)
        self.assertEqual(admission["validation_failures"], [])
        self.assertEqual(admission["admission_counts"]["admitted-fallback"], 1)
        disposition = benchmark.effect_runtime_disposition_metrics(
            preview,
            admission,
        )
        self.assertEqual(disposition["validation_failures"], [])
        self.assertEqual(disposition["kind_counts"]["fallback"], 1)
        failed_fallback = effect_cpu_event(
            frame=22,
            origin="resolved-material-graph",
            subject="effect",
            layer=2,
            effect=2,
            descriptor="2%23effect%232",
            family="visual-failure-passthrough",
            backend="resolved-material-graph",
            outcome="failed",
            reason=(
                "effect-local-passthrough-"
                "material-variant-envelope-frontend"
            ),
        )
        execution = benchmark.effect_execution_metrics(
            effect_execution_log(22, [failed_fallback], []),
            disposition,
        )
        self.assertEqual(execution["validation_failures"], [])
        self.assertIn(
            "effect execution CPU invocation failed",
            benchmark.effect_execution_failures(execution),
        )

        invalid_admission = benchmark.effect_stage_admission_metrics(
            preview.replace(
                "backend=visual-failure-passthrough "
                "profile=effect-local-passthrough",
                "backend=resolved-material profile=program",
                1,
            )
        )
        self.assertIn(
            "effect stage fallback owner invalid",
            invalid_admission["validation_failures"],
        )

    def test_startup_inactive_passthrough_has_no_exact_cpu_demand(self) -> None:
        preview = "\n".join([
            "authoredEffectGraphStageCount: 1",
            "effectStageDescriptorCount: 1",
            "effectStageParsedCount: 1",
            "effectStageActivityCounts: author-disabled=0,property-inactive=1,layer-hidden=0,active=0",
            "effectStageAdmissionCounts: inactive=0,admitted-dedicated=0,admitted-fallback=0,admitted-generic=0,admitted-passthrough=1,not-admitted=0",
            "effectStageCoverageCounts: inactive=0,complete=1,rejected-missing-graph=0,rejected-ambiguous-graph=0,rejected-graph-mismatch=0,rejected-capability=0",
            "effectStageDescriptorIdentityConserved: true",
            "effectStageActivityConserved: true",
            "effectStageInactiveAdmissionConserved: true",
            "effectStageActiveAdmissionConserved: true",
            "effectStageExecutionIdentityConserved: true",
            "effectStageAdmission: layer=2 effect=0 descriptor=2%23effect%230 activity=property-inactive admission=admitted-passthrough coverage=complete backend=initially-inactive-passthrough profile=inactive-passthrough reason=- path=effects/inactive/effect.json",
            "effectStageRuntimeDispositionSchema: 1",
            "effectStageRuntimeRouteScope: unified-effect-graph",
            "effectStageRuntimeDispositionCount: 1",
            "effectStageRuntimeDispositionKindCounts: inactive=0,dedicated=0,fallback=0,passthrough=1,program=0,unsupported=0,unattributed=0",
            "effectStageRuntimeDispositionAttributionCounts: exact-key=1,none=0",
            "effectStageRuntimeDispositionRoleCounts: owner=0,member=1,none=0",
            "effectStaticRouteGroupCount: 1",
            "effectStaticRouteGroupKindCounts: inactive=0,direct=0,resolved=1",
            "effectStageRuntimeDescriptorIdentityConserved: true",
            "effectStageRuntimeGroupIdentityConserved: true",
            "effectStageRuntimeAdmissionIdentityConserved: true",
            "effectStageRuntimeResolvedMaterialOwnershipConserved: true",
            "effectStaticRouteGroup: layer=2 scope=unified-effect-graph kind=resolved effects=1 owners=0 reason=-",
            "effectStageRuntimeDisposition: layer=2 effect=0 descriptor=2%23effect%230 kind=passthrough attribution=exact-key family=initially-inactive-passthrough group=2 role=member reason=initially-inactive-property-stage-passthrough path=effects/inactive/effect.json",
        ])

        admission = benchmark.effect_stage_admission_metrics(preview)
        self.assertEqual(admission["validation_failures"], [])
        self.assertEqual(
            admission["admission_counts"]["admitted-passthrough"],
            1,
        )
        self.assertEqual(admission["admission_counts"]["admitted-fallback"], 0)

        disposition = benchmark.effect_runtime_disposition_metrics(
            preview,
            admission,
        )
        self.assertEqual(disposition["validation_failures"], [])
        self.assertEqual(disposition["kind_counts"]["passthrough"], 1)
        self.assertEqual(disposition["kind_counts"]["fallback"], 0)
        demand = benchmark.effect_execution_static_demand(disposition)
        self.assertTrue(demand.static_is_valid)
        self.assertEqual(demand.eligible_exact_effect_count, 0)
        self.assertNotIn("passthrough", benchmark.EFFECT_EXECUTION_EXACT_KINDS)

        execution = benchmark.effect_execution_metrics("", disposition)
        self.assertFalse(execution["has_evidence"])
        self.assertEqual(
            benchmark.effect_execution_failures(
                execution,
                require_evidence=True,
                static_disposition=disposition,
            ),
            [],
        )

    def test_effect_stage_admission_evidence_is_optional_unless_requested(self) -> None:
        metrics = benchmark.effect_stage_admission_metrics("")
        self.assertFalse(metrics["has_evidence"])
        self.assertIsNone(metrics["schema_version"])
        self.assertEqual(
            benchmark.effect_stage_admission_failures({}, metrics),
            [],
        )
        self.assertEqual(
            benchmark.effect_stage_admission_failures(
                {"expected_effect_stage_descriptor_count": 1},
                metrics,
            ),
            [],
        )
        self.assertEqual(
            benchmark.effect_stage_admission_failures(
                {},
                metrics,
                require_evidence=True,
            ),
            ["effect stage admission evidence missing"],
        )

    def test_effect_stage_compile_metrics_are_bounded_conserved_and_hashed(self) -> None:
        empty_preview = "\n".join([
            "effectStageCompileFailureCount: 0",
            "effectStageCompileFailureCodes: ",
            "effectStageCompilerProbeOutcomeCounts: ",
            "effectStageCompilerFailureCodes: ",
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
            "effectStageCompileFailureCount: 2",
            "effectStageCompileFailureCodes: "
            "no-backend-accepted=1,stage-program-invariant=1",
            "effectStageCompilerProbeOutcomeCounts: "
            "not-applicable=33,rejected=2",
            "effectStageCompilerFailureCodes: "
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
            "effectStageCompileFailureCount: 1\n"
        )
        self.assertIn(
            "effect stage compile summary missing, duplicated, or malformed",
            partial["validation_failures"],
        )

        duplicate = "\n".join([
            "effectStageCompileFailureCount: 1",
            "effectStageCompileFailureCount: 1",
            "effectStageCompileFailureCodes: no-backend-accepted=1",
            "effectStageCompilerProbeOutcomeCounts: rejected=1",
            "effectStageCompilerFailureCodes: "
            "water-flow/compatibility/dedicated-profile-rejected=1",
        ])
        self.assertIn(
            "effect stage compile summary missing, duplicated, or malformed",
            benchmark.authored_effect_stage_compile_metrics(duplicate)[
                "validation_failures"
            ],
        )

        invalid = "\n".join([
            "effectStageCompileFailureCount: 1",
            "effectStageCompileFailureCodes: no-backend-accepted=2",
            "effectStageCompilerProbeOutcomeCounts: "
            "not-applicable=35,rejected=2",
            "effectStageCompilerFailureCodes: "
            "water-flow/compatibility/dedicated-profile-rejected=1",
        ])
        failures = benchmark.authored_effect_stage_compile_metrics(invalid)[
            "validation_failures"
        ]
        self.assertIn("effect stage compile failure count mismatch", failures)
        self.assertIn("effect stage compiler rejection count mismatch", failures)
        self.assertIn("effect stage compiler probe count exceeds bound", failures)

        malformed = "\n".join([
            "effectStageCompileFailureCount: 1",
            "effectStageCompileFailureCodes: unknown-code=1",
            "effectStageCompilerProbeOutcomeCounts: rejected=1",
            "effectStageCompilerFailureCodes: "
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
            family="fixture-dedicated",
            backend="fixture-dedicated",
        )
        failure = effect_cpu_event(
            frame=12,
            origin="strict-chain",
            subject="effect",
            layer=2,
            effect=0,
            descriptor="2%23effect%230",
            family="fixture-dedicated",
            backend="fixture-dedicated",
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
            family="fixture-dedicated",
            backend="fixture-dedicated",
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
        self.assertEqual(completed_only["validation_failures"], [])

    def test_effect_execution_deduplicates_events_before_frame_contract(self) -> None:
        disposition = benchmark.effect_runtime_disposition_metrics(
            effect_runtime_disposition_preview()
        )
        event = effect_cpu_event(
            frame=14,
            origin="resolved-material-graph",
            subject="effect",
            layer=2,
            effect=1,
            descriptor="2%23effect%231",
            family="resolved-material",
            backend="resolved-material-graph",
        )
        route = effect_route_event(
            frame=14,
            origin="resolved-material-graph",
            layer=2,
            operation="graph-stage",
        )
        repeated_event = effect_cpu_event(
            frame=15,
            origin="resolved-material-graph",
            subject="effect",
            layer=2,
            effect=1,
            descriptor="2%23effect%231",
            family="resolved-material",
            backend="resolved-material-graph",
        )
        repeated_route = effect_route_event(
            frame=15,
            origin="resolved-material-graph",
            layer=2,
            operation="graph-stage",
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
            family="fixture-dedicated",
            backend="fixture-dedicated",
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
            origin="graph-executor",
            layer=2,
            operation="typed-stage",
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

    def test_effect_execution_degraded_encoded_route_is_non_pass(self) -> None:
        ordinary_route = effect_route_event(
            frame=17,
            origin="graph-executor",
            layer=2,
            operation="typed-stage",
        )
        ordinary_metrics = benchmark.effect_execution_metrics(
            effect_execution_log(17, [], [ordinary_route])
        )
        self.assertEqual(len(ordinary_metrics["encoded_route_operations"]), 1)
        self.assertEqual(ordinary_metrics["degraded_route_operations"], [])
        self.assertEqual(ordinary_metrics["failed_route_operations"], [])
        self.assertEqual(
            benchmark.effect_execution_failures(ordinary_metrics),
            [],
        )

        degraded_route = effect_route_event(
            frame=18,
            origin="graph-executor",
            layer=2,
            operation="degraded-layer-source-passthrough",
        )
        degraded_metrics = benchmark.effect_execution_metrics(
            effect_execution_log(18, [], [degraded_route])
        )
        self.assertEqual(len(degraded_metrics["encoded_route_operations"]), 1)
        self.assertEqual(
            degraded_metrics["degraded_route_operations"],
            degraded_metrics["encoded_route_operations"],
        )
        self.assertEqual(degraded_metrics["failed_route_operations"], [])
        self.assertEqual(
            benchmark.effect_execution_failures(degraded_metrics),
            ["effect execution degraded layer source passthrough"],
        )

        malformed_metrics = benchmark.effect_execution_metrics(
            "schema=1 axis=effect-route-operation frame=19 "
            "origin=graph-executor layer=2 operation=typed-stage "
            "outcome=encoded"
        )
        self.assertIn(
            "effect execution route operation malformed",
            malformed_metrics["validation_failures"],
        )

    def test_effect_execution_expected_local_fallback_is_bounded(self) -> None:
        route = effect_route_event(
            frame=20,
            origin="image",
            layer=17,
            operation="unclaimed-effect-product-authority",
            outcome="failed",
            reason="unclaimed-visible-effects",
        )
        metrics = benchmark.effect_execution_metrics(
            effect_execution_log(20, [], [route])
        )
        expected = [{
            "origin": "image",
            "layer_id": 17,
            "operation": "unclaimed-effect-product-authority",
            "outcome": "failed",
            "reason": "unclaimed-visible-effects",
        }]
        self.assertEqual(
            benchmark.effect_execution_failures(
                metrics,
                sample={
                    "expected_effect_execution_local_fallbacks": expected,
                },
            ),
            [],
        )
        self.assertIn(
            "effect execution local fallback expectation mismatch",
            benchmark.effect_execution_failures(
                metrics,
                sample={
                    "expected_effect_execution_local_fallbacks": [],
                },
            ),
        )


    def test_resolved_material_graph_execution_gate_accepts_conserved_evidence(
        self,
    ) -> None:
        preview_text = (
            "resolved material execution capabilities: "
            "schema=layer-graph-capability-v1 candidates=2 accepted=1 "
            "rejected=1 variantLimit=8\n"
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=68 status=accepted "
            "dependency=none dependencyReferences=0\n"
            "resolved material scene background: "
            "schema=scene-background-provider-v1 layer=68 effect=0 "
            "node=0 slot=1 mode=same-frame-main-target\n"
        )
        log_text = "\n".join([
            "resolved material runtime audit: schema=scene-graph-executor-v1 "
            "claimed=1 encoded=0 failures=0 deferred=1 pending=1 "
            "gpuEncoded=0 localFallbacks=0",
            "resolved material runtime audit: schema=scene-graph-executor-v1 "
            "claimed=1 encoded=1 failures=0 deferred=0 pending=1 "
            "gpuEncoded=1 localFallbacks=0",
            graph_execution_observation(
                frame=10,
                transaction="tx-10",
                trigger="first-frame+first-success+gpu-completed",
                target_descriptors_sha256="a" * 64,
                target_descriptor_counts="1512x982/rgbaBackbuffer:2",
            ),
            graph_execution_observation(
                frame=11,
                transaction="tx-11",
                trigger="next-frame+compositor-consume+gpu-completed",
                consumed=True,
                target_descriptors_sha256="a" * 64,
                target_descriptor_counts="1512x982/rgbaBackbuffer:2",
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
            "schema_version": "layer-graph-capability-v1",
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
        self.assertEqual(metrics["scene_background"], {
            "has_evidence": True,
            "schema_version": "scene-background-provider-v1",
            "layer_ids": [68],
            "duplicate_layer_ids": [],
            "unaccepted_layer_ids": [],
            "malformed_observation_count": 0,
            "observations": [{
                "layer_id": 68,
                "effect_index": 0,
                "node_index": 0,
                "slot": 1,
            }],
        })
        self.assertEqual(metrics["executor"]["claimed_count"], 2)
        self.assertEqual(metrics["executor"]["encoded_count"], 1)
        self.assertEqual(metrics["executor"]["gpu_encoded_count"], 1)
        self.assertEqual(
            metrics["graph_observations"]["successful_transactions"],
            ["tx-10", "tx-11"],
        )
        self.assertEqual(
            metrics["graph_observations"]["target_descriptor_counts"],
            ["1512x982/rgbaBackbuffer:2"],
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
            "schema_version": "layer-graph-route-v1",
            "accepted_layer_ids": [68],
            "observed_layer_ids": [68],
            "compositor_consumed_layer_ids": [68],
            "named_published_layer_ids": [],
            "visible_graph_output_published_layer_ids": [],
            "named_graph_output_published_layer_ids": [],
            "named_compositor_overlap_layer_ids": [],
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
        })
        self.assertEqual(metrics["succeeded_layer_ids"], [68])
        self.assertEqual(
            benchmark.resolved_material_graph_execution_failures(
                metrics,
                require_evidence=True,
                sample={
                    "expected_resolved_material_graph_succeeded_layer_ids": [68],
                    "expected_resolved_material_graph_target_descriptor_counts": [
                        "1512x982/rgbaBackbuffer:2"
                    ],
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

    def test_resolved_material_graph_gate_accepts_named_provider_terminal(
        self,
    ) -> None:
        assert_named_provider_terminal(
            self,
            benchmark=benchmark,
            graph_execution_observation=graph_execution_observation,
            resolved_graph_exact_evidence=resolved_graph_exact_evidence,
        )

    def test_resolved_material_graph_gate_accepts_visible_graph_output_provider(
        self,
    ) -> None:
        assert_visible_provider_requires_compositor_consumption(
            self,
            benchmark=benchmark,
            graph_execution_observation=graph_execution_observation,
            resolved_graph_exact_evidence=resolved_graph_exact_evidence,
        )

    def test_resolved_material_graph_extent_lifecycle_accepts_aba_profiles(
        self,
    ) -> None:
        preview_text = (
            "resolved material execution capabilities: "
            "schema=layer-graph-capability-v1 candidates=1 accepted=1 "
            "rejected=0 variantLimit=8\n"
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=533 status=accepted "
            "dependency=none dependencyReferences=0\n"
        )
        audit = (
            "resolved material runtime audit: schema=scene-graph-executor-v1 "
            "claimed=1 encoded=1 failures=0 deferred=0 pending=1 "
            "gpuEncoded=1 localFallbacks=0"
        )
        disposition, exact_execution = resolved_graph_exact_evidence([533])
        cases = (
            {
                "name": "scaled-target-descriptors",
                "observations": [
                    graph_execution_observation(
                        frame=1,
                        layer=533,
                        transaction="scale-a-initial",
                        trigger="first-frame+compositor-consume+gpu-completed",
                        consumed=True,
                        target_descriptors_sha256="a" * 64,
                        target_descriptor_counts="1024x576/rgbaBackbuffer:2",
                        history="seeded",
                        reset="initial",
                    ),
                    graph_execution_observation(
                        frame=2,
                        layer=533,
                        transaction="scale-a-cow",
                        trigger="next-frame+compositor-consume+gpu-completed",
                        consumed=True,
                        target_descriptors_sha256="a" * 64,
                        target_descriptor_counts="1024x576/rgbaBackbuffer:2",
                        history="reused",
                        reset="history-copy-on-write",
                        history_rehydrate_copy_count=2,
                    ),
                    graph_execution_observation(
                        frame=3,
                        layer=533,
                        transaction="scale-b-reprepare",
                        trigger="next-frame+compositor-consume+gpu-completed",
                        consumed=True,
                        target_descriptors_sha256="b" * 64,
                        target_descriptor_counts="481x271/rgbaBackbuffer:2",
                        input_width=962,
                        input_height=542,
                        history="seeded",
                        reset="allocation-reprepare",
                        history_content_discarded=True,
                    ),
                    graph_execution_observation(
                        frame=4,
                        layer=533,
                        transaction="scale-b-cow",
                        trigger="next-frame+compositor-consume+gpu-completed",
                        consumed=True,
                        target_descriptors_sha256="b" * 64,
                        target_descriptor_counts="481x271/rgbaBackbuffer:2",
                        input_width=962,
                        input_height=542,
                        history="reused",
                        reset="history-copy-on-write",
                        history_rehydrate_copy_count=2,
                    ),
                    graph_execution_observation(
                        frame=5,
                        layer=533,
                        transaction="scale-a-restored",
                        trigger="next-frame+compositor-consume+gpu-completed",
                        consumed=True,
                        target_descriptors_sha256="a" * 64,
                        target_descriptor_counts="1024x576/rgbaBackbuffer:2",
                        history="seeded",
                        reset="allocation-reprepare",
                        history_content_discarded=True,
                    ),
                ],
                "anchors": [
                    {
                        "input_width": 2048,
                        "input_height": 1152,
                        "target_descriptor_counts":
                            "1024x576/rgbaBackbuffer:2",
                        "history": "seeded",
                        "reset": "initial",
                        "history_rehydrate_copy_count": 0,
                        "history_content_discarded": False,
                    },
                    {
                        "input_width": 962,
                        "input_height": 542,
                        "target_descriptor_counts":
                            "481x271/rgbaBackbuffer:2",
                        "history": "seeded",
                        "reset": "allocation-reprepare",
                        "history_rehydrate_copy_count": 0,
                        "history_content_discarded": True,
                    },
                    {
                        "input_width": 2048,
                        "input_height": 1152,
                        "target_descriptor_counts":
                            "1024x576/rgbaBackbuffer:2",
                        "history": "seeded",
                        "reset": "allocation-reprepare",
                        "history_rehydrate_copy_count": 0,
                        "history_content_discarded": True,
                    },
                ],
            },
            {
                "name": "absolute-target-descriptors",
                "observations": [
                    graph_execution_observation(
                        frame=1,
                        layer=533,
                        transaction="absolute-a-initial",
                        trigger="first-frame+compositor-consume+gpu-completed",
                        consumed=True,
                        target_descriptors_sha256="c" * 64,
                        target_descriptor_counts="640x360/rgbaBackbuffer:2",
                        history="seeded",
                        reset="initial",
                    ),
                    graph_execution_observation(
                        frame=2,
                        layer=533,
                        transaction="absolute-a-cow",
                        trigger="next-frame+compositor-consume+gpu-completed",
                        consumed=True,
                        target_descriptors_sha256="c" * 64,
                        target_descriptor_counts="640x360/rgbaBackbuffer:2",
                        history="reused",
                        reset="history-copy-on-write",
                        history_rehydrate_copy_count=2,
                    ),
                    graph_execution_observation(
                        frame=3,
                        layer=533,
                        transaction="absolute-b-reprepare",
                        trigger="next-frame+compositor-consume+gpu-completed",
                        consumed=True,
                        target_descriptors_sha256="c" * 64,
                        target_descriptor_counts="640x360/rgbaBackbuffer:2",
                        input_width=962,
                        input_height=542,
                        history="reused",
                        reset="allocation-reprepare",
                        history_rehydrate_copy_count=2,
                    ),
                    graph_execution_observation(
                        frame=4,
                        layer=533,
                        transaction="absolute-b-cow",
                        trigger="next-frame+compositor-consume+gpu-completed",
                        consumed=True,
                        target_descriptors_sha256="c" * 64,
                        target_descriptor_counts="640x360/rgbaBackbuffer:2",
                        input_width=962,
                        input_height=542,
                        history="reused",
                        reset="history-copy-on-write",
                        history_rehydrate_copy_count=2,
                    ),
                    graph_execution_observation(
                        frame=5,
                        layer=533,
                        transaction="absolute-a-restored",
                        trigger="next-frame+compositor-consume+gpu-completed",
                        consumed=True,
                        target_descriptors_sha256="c" * 64,
                        target_descriptor_counts="640x360/rgbaBackbuffer:2",
                        history="reused",
                        reset="allocation-reprepare",
                        history_rehydrate_copy_count=2,
                    ),
                ],
                "anchors": [
                    {
                        "input_width": 2048,
                        "input_height": 1152,
                        "target_descriptor_counts":
                            "640x360/rgbaBackbuffer:2",
                        "history": "seeded",
                        "reset": "initial",
                        "history_rehydrate_copy_count": 0,
                        "history_content_discarded": False,
                    },
                    {
                        "input_width": 962,
                        "input_height": 542,
                        "target_descriptor_counts":
                            "640x360/rgbaBackbuffer:2",
                        "history": "reused",
                        "reset": "allocation-reprepare",
                        "history_rehydrate_copy_count": 2,
                        "history_content_discarded": False,
                    },
                    {
                        "input_width": 2048,
                        "input_height": 1152,
                        "target_descriptor_counts":
                            "640x360/rgbaBackbuffer:2",
                        "history": "reused",
                        "reset": "allocation-reprepare",
                        "history_rehydrate_copy_count": 2,
                        "history_content_discarded": False,
                    },
                ],
            },
        )

        for case in cases:
            with self.subTest(profile=case["name"]):
                metrics = benchmark.resolved_material_graph_execution_metrics(
                    preview_text,
                    "\n".join([audit, *case["observations"]]),
                    effect_execution=exact_execution,
                    static_disposition=disposition,
                )
                sample = {
                    "expected_resolved_material_graph_succeeded_layer_ids": [
                        533
                    ],
                    "expected_resolved_material_graph_extent_lifecycle": {
                        "layer_id": 533,
                        "anchors": case["anchors"],
                        "require_history_copy_on_write": True,
                    },
                }

                self.assertEqual(
                    benchmark.resolved_material_graph_execution_failures(
                        metrics,
                        require_evidence=True,
                        sample=sample,
                    ),
                    [],
                )
                transitions = metrics["graph_observations"][
                    "lifecycle_transitions"
                ]
                self.assertEqual(
                    [entry["allocation_generation"] for entry in transitions],
                    [1, 3, 5],
                )
                self.assertEqual(
                    [entry["mapping_generation"] for entry in transitions],
                    [1, 3, 5],
                )
                self.assertEqual(
                    [entry["mapping_before_sha256"] for entry in transitions],
                    ["a" * 64] * 3,
                )
                self.assertEqual(
                    [entry["mapping_after_sha256"] for entry in transitions],
                    ["b" * 64] * 3,
                )
                self.assertEqual(
                    metrics["graph_observations"][
                        "history_copy_on_write_count"
                    ],
                    2,
                )

    def test_graph_lifecycle_is_scoped_to_runtime_instance(self) -> None:
        observations = []
        for runtime in ("runtime-a", "runtime-b"):
            observations.extend([
                graph_execution_observation(
                    frame=1,
                    layer=533,
                    transaction="r4:1:1:0",
                    trigger="first-frame+compositor-consume+gpu-completed",
                    consumed=True,
                    target_descriptors_sha256="a" * 64,
                    target_descriptor_counts="1024x576/rgbaBackbuffer:2",
                    history="seeded",
                    reset="initial",
                    runtime_instance_identity=runtime,
                ),
                graph_execution_observation(
                    frame=2,
                    layer=533,
                    transaction="r4:1:2:0",
                    trigger="next-frame+compositor-consume+gpu-completed",
                    consumed=True,
                    target_descriptors_sha256="a" * 64,
                    target_descriptor_counts="1024x576/rgbaBackbuffer:2",
                    history="reused",
                    reset="history-copy-on-write",
                    history_rehydrate_copy_count=2,
                    runtime_instance_identity=runtime,
                ),
            ])

        metrics = benchmark.resolved_material_graph_observation_metrics(
            "\n".join(observations)
        )

        self.assertEqual(metrics["validation_failures"], [])
        self.assertEqual(metrics["runtime_instance_identities"], [
            "runtime-a", "runtime-b",
        ])
        self.assertEqual(metrics["runtime_instance_identity_count"], 2)
        self.assertEqual(metrics["successful_transaction_count"], 4)
        self.assertEqual(metrics["history_copy_on_write_count"], 2)

    def test_graph_lifecycle_is_scoped_to_exact_effect_identity(self) -> None:
        observations = [
            graph_execution_observation(
                frame=1,
                layer=17,
                effect=0,
                descriptor_id="17%23effect%230",
                transaction="r4:1:1:0",
                trigger="first-frame+gpu-completed",
                allocation_generation=1,
                mapping_generation=1,
                runtime_instance_identity="runtime-a",
            ),
            graph_execution_observation(
                frame=1,
                layer=17,
                effect=1,
                descriptor_id="17%23effect%231",
                transaction="r4:1:1:1",
                trigger="first-frame+compositor-consume+gpu-completed",
                consumed=True,
                allocation_generation=1,
                mapping_generation=1,
                target_descriptors_sha256="a" * 64,
                target_descriptor_counts="512x288/rgba8888:2",
                history="seeded",
                reset="initial",
                runtime_instance_identity="runtime-a",
            ),
            graph_execution_observation(
                frame=2,
                layer=17,
                effect=0,
                descriptor_id="17%23effect%230",
                transaction="r4:1:2:0",
                trigger="next-frame+gpu-completed",
                allocation_generation=2,
                mapping_generation=1,
                reset="initial",
                runtime_instance_identity="runtime-a",
            ),
            graph_execution_observation(
                frame=2,
                layer=17,
                effect=1,
                descriptor_id="17%23effect%231",
                transaction="r4:1:2:1",
                trigger="next-frame+compositor-consume+gpu-completed",
                consumed=True,
                allocation_generation=2,
                mapping_generation=2,
                target_descriptors_sha256="a" * 64,
                target_descriptor_counts="512x288/rgba8888:2",
                history="reused",
                reset="history-copy-on-write",
                history_rehydrate_copy_count=1,
                runtime_instance_identity="runtime-a",
            ),
        ]

        metrics = benchmark.resolved_material_graph_observation_metrics(
            "\n".join(observations)
        )

        self.assertEqual(metrics["validation_failures"], [])
        self.assertEqual(metrics["history_copy_on_write_count"], 1)
        self.assertEqual(
            {
                (entry["effect_index"], entry["descriptor_id"])
                for entry in metrics["terminal_success_observations"]
            },
            {(0, "17#effect#0"), (1, "17#effect#1")},
        )

    def test_graph_lifecycle_remains_strict_within_runtime_instance(self) -> None:
        observations = [
            graph_execution_observation(
                frame=1,
                layer=533,
                transaction="initial",
                trigger="first-frame+compositor-consume+gpu-completed",
                consumed=True,
                allocation_generation=2,
                mapping_generation=2,
                target_descriptors_sha256="a" * 64,
                target_descriptor_counts="1024x576/rgbaBackbuffer:2",
                history="seeded",
                reset="initial",
                runtime_instance_identity="runtime-a",
            ),
            graph_execution_observation(
                frame=2,
                layer=533,
                transaction="regressed",
                trigger="next-frame+compositor-consume+gpu-completed",
                consumed=True,
                allocation_generation=1,
                mapping_generation=1,
                target_descriptors_sha256="a" * 64,
                target_descriptor_counts="1024x576/rgbaBackbuffer:2",
                history="reused",
                reset="history-copy-on-write",
                history_rehydrate_copy_count=2,
                runtime_instance_identity="runtime-a",
            ),
        ]

        metrics = benchmark.resolved_material_graph_observation_metrics(
            "\n".join(observations)
        )

        self.assertIn(
            "resolved material graph allocation identity transition invalid",
            metrics["validation_failures"],
        )

    def test_resolved_material_graph_lifecycle_rejects_mislabeled_transitions(
        self,
    ) -> None:
        initial = graph_execution_observation(
            frame=1,
            layer=533,
            transaction="initial",
            trigger="first-frame+compositor-consume+gpu-completed",
            consumed=True,
            target_descriptors_sha256="a" * 64,
            target_descriptor_counts="1024x576/rgbaBackbuffer:2",
            history="seeded",
            reset="initial",
        )
        cases = (
            (
                "unknown-reset",
                graph_execution_observation(
                    frame=2,
                    layer=533,
                    transaction="unknown-reset",
                    trigger="next-frame+compositor-consume+gpu-completed",
                    consumed=True,
                    target_descriptors_sha256="a" * 64,
                    target_descriptor_counts="1024x576/rgbaBackbuffer:2",
                    history="reused",
                    reset="unknown-lifecycle",
                    history_rehydrate_copy_count=2,
                ),
                "resolved material graph reset reason invalid",
            ),
            (
                "copy-on-write-changed-descriptor",
                graph_execution_observation(
                    frame=2,
                    layer=533,
                    transaction="mislabeled-cow",
                    trigger="next-frame+compositor-consume+gpu-completed",
                    consumed=True,
                    target_descriptors_sha256="b" * 64,
                    target_descriptor_counts="481x271/rgbaBackbuffer:2",
                    input_width=962,
                    input_height=542,
                    history="reused",
                    reset="history-copy-on-write",
                    history_rehydrate_copy_count=2,
                ),
                (
                    "resolved material graph history copy-on-write "
                    "transition invalid"
                ),
            ),
            (
                "reprepare-stable-descriptor",
                graph_execution_observation(
                    frame=2,
                    layer=533,
                    transaction="mislabeled-reprepare",
                    trigger="next-frame+compositor-consume+gpu-completed",
                    consumed=True,
                    target_descriptors_sha256="a" * 64,
                    target_descriptor_counts="1024x576/rgbaBackbuffer:2",
                    history="reused",
                    reset="allocation-reprepare",
                    history_rehydrate_copy_count=2,
                ),
                (
                    "resolved material graph allocation reprepare "
                    "transition invalid"
                ),
            ),
        )

        for name, observation, expected_failure in cases:
            with self.subTest(case=name):
                metrics = benchmark.resolved_material_graph_observation_metrics(
                    "\n".join([initial, observation])
                )
                self.assertIn(
                    expected_failure,
                    metrics["validation_failures"],
                )

    def test_resolved_material_graph_extent_lifecycle_expectation_is_exact(
        self,
    ) -> None:
        preview_text = (
            "resolved material execution capabilities: "
            "schema=layer-graph-capability-v1 candidates=1 accepted=1 "
            "rejected=0 variantLimit=8\n"
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=533 status=accepted\n"
        )
        log_text = "\n".join([
            "resolved material runtime audit: schema=scene-graph-executor-v1 "
            "claimed=1 encoded=1 failures=0 deferred=0 pending=1 "
            "gpuEncoded=1 localFallbacks=0",
            graph_execution_observation(
                frame=1,
                layer=533,
                transaction="a",
                trigger="first-frame+compositor-consume+gpu-completed",
                consumed=True,
                target_descriptors_sha256="a" * 64,
                target_descriptor_counts="1024x576/rgbaBackbuffer:2",
                history="seeded",
                reset="initial",
            ),
            graph_execution_observation(
                frame=2,
                layer=533,
                transaction="b",
                trigger="next-frame+compositor-consume+gpu-completed",
                consumed=True,
                target_descriptors_sha256="b" * 64,
                target_descriptor_counts="481x271/rgbaBackbuffer:2",
                input_width=962,
                input_height=542,
                history="seeded",
                reset="allocation-reprepare",
                history_content_discarded=True,
            ),
        ])
        disposition, exact_execution = resolved_graph_exact_evidence([533])
        metrics = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            log_text,
            effect_execution=exact_execution,
            static_disposition=disposition,
        )
        base_sample = {
            "expected_resolved_material_graph_succeeded_layer_ids": [533],
        }

        malformed = dict(base_sample)
        malformed["expected_resolved_material_graph_extent_lifecycle"] = {
            "layer_id": 533,
            "anchors": [],
            "require_history_copy_on_write": False,
        }
        self.assertIn(
            "resolved material graph extent lifecycle expectation invalid",
            benchmark.resolved_material_graph_execution_failures(
                metrics,
                require_evidence=True,
                sample=malformed,
            ),
        )

        wrong_anchor = dict(base_sample)
        wrong_anchor["expected_resolved_material_graph_extent_lifecycle"] = {
            "layer_id": 533,
            "anchors": [
                {
                    "input_width": 2048,
                    "input_height": 1152,
                    "target_descriptor_counts":
                        "1024x576/rgbaBackbuffer:2",
                    "history": "seeded",
                    "reset": "initial",
                    "history_rehydrate_copy_count": 0,
                    "history_content_discarded": False,
                },
                {
                    "input_width": 963,
                    "input_height": 542,
                    "target_descriptor_counts":
                        "481x271/rgbaBackbuffer:2",
                    "history": "seeded",
                    "reset": "allocation-reprepare",
                    "history_rehydrate_copy_count": 0,
                    "history_content_discarded": True,
                },
            ],
            "require_history_copy_on_write": False,
        }
        self.assertIn(
            "resolved material graph extent lifecycle evidence mismatch",
            benchmark.resolved_material_graph_execution_failures(
                metrics,
                require_evidence=True,
                sample=wrong_anchor,
            ),
        )

    def test_resolved_material_graph_typed_fallback_requires_recovery(
        self,
    ) -> None:
        preview_text = (
            "resolved material execution capabilities: "
            "schema=layer-graph-capability-v1 candidates=1 accepted=1 "
            "rejected=0 variantLimit=8\n"
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=533 status=accepted\n"
        )
        disposition = static_effect_disposition(
            records=[{
                "layer_id": 533,
                "effect_index": 0,
                "descriptor_id": "533#effect#0",
                "definition_path": "effects/533/effect.json",
                "family": "generic-fragment",
                "kind": "program",
            }],
            groups=[{"layer_id": 533, "kind": "authored"}],
        )
        cpu = effect_cpu_event(
            frame=2,
            origin="resolved-material-graph",
            subject="effect",
            layer=533,
            effect=0,
            descriptor="533%23effect%230",
            family="generic-fragment",
            backend=benchmark.RESOLVED_MATERIAL_GRAPH_BACKEND,
        )
        route = effect_route_event(
            frame=2,
            origin="solid",
            layer=533,
            operation="unclaimed-effect-product-authority",
            outcome="failed",
            reason="unclaimed-visible-effects",
        )
        effect_log = effect_execution_log(2, [cpu], [route])
        effect_execution = benchmark.effect_execution_metrics(
            effect_log,
            disposition,
        )
        graph_before = graph_execution_observation(
            frame=1,
            layer=533,
            transaction="before-fallback",
            trigger="next-frame+compositor-consume+gpu-completed",
            consumed=True,
            target_descriptors_sha256="a" * 64,
            target_descriptor_counts="1024x576/rgbaBackbuffer:2",
            history="seeded",
            reset="initial",
        )
        graph_after = graph_execution_observation(
            frame=3,
            layer=533,
            transaction="after-recovery",
            trigger="next-frame+compositor-consume+gpu-completed",
            consumed=True,
            allocation_generation=2,
            mapping_generation=2,
            target_descriptors_sha256="a" * 64,
            target_descriptor_counts="1024x576/rgbaBackbuffer:2",
            history="reused",
            reset="history-copy-on-write",
            history_rehydrate_copy_count=2,
        )
        common_log = [
            "resolved material runtime audit: schema=scene-graph-executor-v1 "
            "claimed=1 encoded=1 failures=0 deferred=0 pending=1 "
            "gpuEncoded=1 localFallbacks=1",
            "layer-local-fallback count=1 entries="
            "533:frame-target-plan-unsupported-target-descriptor",
            "schema=1 axis=graph-execution frame=2 "
            "diagnostic=frame-target-plan-unsupported-target-descriptor",
            graph_before,
        ]
        expected_graph_fallback = [{
            "layer_id": 533,
            "reason": "frame-target-plan-unsupported-target-descriptor",
        }]
        graph_sample = {
            "expected_resolved_material_graph_succeeded_layer_ids": [533],
            "expected_resolved_material_graph_local_fallbacks":
                expected_graph_fallback,
        }

        recovered = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            "\n".join([*common_log, graph_after]),
            effect_execution=effect_execution,
            static_disposition=disposition,
        )
        self.assertEqual(
            recovered["executor"][
                "transient_recovered_fallback_layer_ids"
            ],
            [533],
        )
        self.assertEqual(
            benchmark.resolved_material_graph_execution_failures(
                recovered,
                require_evidence=True,
                sample=graph_sample,
            ),
            [],
        )
        self.assertEqual(
            benchmark.effect_execution_failures(
                effect_execution,
                sample={
                    "expected_effect_execution_local_fallbacks": [{
                        "origin": "solid",
                        "layer_id": 533,
                        "operation":
                            "unclaimed-effect-product-authority",
                        "outcome": "failed",
                        "reason": "unclaimed-visible-effects",
                    }],
                },
            ),
            [],
        )

        not_recovered = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            "\n".join(common_log),
            effect_execution=effect_execution,
            static_disposition=disposition,
        )
        self.assertIn(
            "resolved material graph local fallback evidence mismatch",
            benchmark.resolved_material_graph_execution_failures(
                not_recovered,
                require_evidence=True,
                sample=graph_sample,
            ),
        )

    def test_resolved_material_graph_gate_accepts_typed_local_fallback(
        self,
    ) -> None:
        preview_text = (
            "resolved material execution capabilities: "
            "schema=layer-graph-capability-v1 candidates=1 accepted=1 "
            "rejected=0 variantLimit=8\n"
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=533 status=accepted "
            "dependency=none dependencyReferences=0\n"
        )
        log_text = "\n".join([
            "resolved material runtime audit: schema=scene-graph-executor-v1 "
            "claimed=0 encoded=0 failures=0 deferred=0 pending=0 "
            "gpuEncoded=0 localFallbacks=1",
            "layer-local-fallback count=1 entries="
            "533:frame-target-plan-unsupported-target-descriptor",
            "schema=1 axis=graph-execution frame=1 "
            "diagnostic=frame-target-plan-unsupported-target-descriptor",
        ])
        metrics = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            log_text,
        )
        expected_fallbacks = [{
            "layer_id": 533,
            "reason": "frame-target-plan-unsupported-target-descriptor",
        }]

        self.assertEqual(
            metrics["executor"]["local_fallbacks"],
            expected_fallbacks,
        )
        self.assertEqual(
            benchmark.resolved_material_graph_execution_failures(
                metrics,
                require_evidence=True,
                sample={
                    "expected_resolved_material_graph_succeeded_layer_ids": [],
                    "expected_resolved_material_graph_local_fallbacks":
                        expected_fallbacks,
                },
            ),
            [],
        )
        self.assertIn(
            "resolved material graph local fallback evidence mismatch",
            benchmark.resolved_material_graph_execution_failures(
                metrics,
                sample={
                    "expected_resolved_material_graph_succeeded_layer_ids": [],
                    "expected_resolved_material_graph_local_fallbacks": [{
                        "layer_id": 533,
                        "reason": "frame-target-plan-rejected",
                    }],
                },
            ),
        )

    def test_resolved_material_graph_execution_gate_accepts_dependency_routes(
        self,
    ) -> None:
        preview_text = "\n".join([
            "resolved material execution capabilities: "
            "schema=layer-graph-capability-v1 candidates=3 accepted=3 "
            "rejected=0 variantLimit=8",
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=68 status=accepted "
            "dependency=none dependencyReferences=0",
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=70 status=accepted "
            "dependency=graph-internal dependencyReferences=1",
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=72 status=accepted "
            "dependency=external-primary dependencyReferences=1",
        ])

        metrics = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            "",
        )

        self.assertEqual(
            metrics["capability"]["accepted_layer_ids"],
            [68, 70, 72],
        )
        self.assertEqual(
            metrics["capability"]["malformed_route_observation_count"],
            0,
        )
        self.assertNotIn(
            "resolved material graph accepted layer evidence malformed",
            metrics["validation_failures"],
        )

        malformed = benchmark.resolved_material_graph_execution_metrics(
            "\n".join([
                "resolved material execution capabilities: "
                "schema=layer-graph-capability-v1 candidates=1 accepted=1 "
                "rejected=0 variantLimit=8",
                "resolved material execution capability: "
                "schema=layer-graph-route-v1 layer=72 status=accepted "
                "dependency=external-primary dependencyReferences=0",
            ]),
            "",
        )
        self.assertEqual(
            malformed["capability"]["malformed_route_observation_count"],
            1,
        )
        self.assertIn(
            "resolved material graph accepted layer evidence malformed",
            malformed["validation_failures"],
        )

        malformed_background = benchmark.resolved_material_graph_execution_metrics(
            preview_text
            + "\nresolved material scene background: "
            + "schema=scene-background-provider-v1 layer=70 mode=unknown",
            "",
        )
        self.assertIn(
            "resolved material scene background evidence malformed",
            malformed_background["validation_failures"],
        )

        unaccepted_background = benchmark.resolved_material_graph_execution_metrics(
            preview_text
            + "\nresolved material scene background: "
            + "schema=scene-background-provider-v1 layer=99 effect=0 "
            + "node=0 slot=1 mode=same-frame-main-target",
            "",
        )
        self.assertIn(
            "resolved material scene background layer not accepted",
            unaccepted_background["validation_failures"],
        )

    def test_resolved_material_graph_execution_gate_rejects_false_success(
        self,
    ) -> None:
        no_admission = benchmark.resolved_material_graph_execution_metrics(
            "resolved material execution capabilities: "
            "schema=layer-graph-capability-v1 candidates=1 accepted=0 "
            "rejected=1 variantLimit=8\n",
            "resolved material runtime audit: schema=scene-graph-executor-v1 "
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
            "schema=layer-graph-capability-v1 candidates=1 accepted=1 "
            "rejected=0 variantLimit=8\n",
            "resolved material runtime audit: schema=scene-graph-executor-v1 "
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
                "schema=layer-graph-capability-v1 candidates=2 accepted=1 "
                "rejected=0 variantLimit=8\n",
                "resolved material runtime audit: "
                "schema=scene-graph-executor-v1 claimed=1 encoded=2 "
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
            "resolved material runtime audit: schema=scene-graph-executor-v1 "
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
            "schema=layer-graph-capability-v1 candidates=1 accepted=1 "
            "rejected=0 variantLimit=8\n"
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=68 status=accepted\n"
        )
        audit = (
            "resolved material runtime audit: schema=scene-graph-executor-v1 "
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

        activation_passthrough = (
            benchmark.resolved_material_graph_observation_metrics(
                graph_execution_observation(
                    frame=13,
                    transaction="tx-activation",
                    trigger="next-frame+compositor-consume+gpu-completed",
                    authored=1,
                    material=0,
                    copy=0,
                    swap=0,
                    compose=0,
                    rejected=1,
                    consumed=True,
                    program=(
                        "activation-passthrough:"
                        "effect-activation-visibility-disabled"
                    ),
                )
            )
        )
        self.assertEqual(activation_passthrough["validation_failures"], [])
        self.assertEqual(
            activation_passthrough["activation_passthrough_count"],
            1,
        )
        self.assertEqual(
            activation_passthrough["activation_passthrough_reason_codes"],
            ["effect-activation-visibility-disabled"],
        )
        self.assertEqual(
            activation_passthrough["program_terminal_success_count"],
            0,
        )
        self.assertTrue(
            activation_passthrough["terminal_success_observations"][0][
                "activation_passthrough"
            ]
        )

        disposition, exact_execution = resolved_graph_exact_evidence([68])
        activation_only = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            "\n".join([
                "resolved material runtime audit: "
                "schema=scene-graph-executor-v1 claimed=2 encoded=2 "
                "failures=0 deferred=0 pending=0 gpuEncoded=2",
                graph_execution_observation(
                    frame=13,
                    transaction="tx-activation-13",
                    trigger=(
                        "first-frame+compositor-consume+gpu-completed"
                    ),
                    authored=1,
                    material=0,
                    copy=0,
                    swap=0,
                    compose=0,
                    rejected=1,
                    consumed=True,
                    program=(
                        "activation-passthrough:"
                        "effect-activation-scalar-below-minimum"
                    ),
                ),
                graph_execution_observation(
                    frame=14,
                    transaction="tx-activation-14",
                    trigger="next-frame+compositor-consume+gpu-completed",
                    authored=1,
                    material=0,
                    copy=0,
                    swap=0,
                    compose=0,
                    rejected=1,
                    consumed=True,
                    program=(
                        "activation-passthrough:"
                        "effect-activation-scalar-below-minimum"
                    ),
                ),
            ]),
            effect_execution=exact_execution,
            static_disposition=disposition,
        )
        self.assertFalse(activation_only["execution_succeeded"])
        self.assertEqual(activation_only["succeeded_layer_ids"], [])
        self.assertIn(
            "resolved material graph Program transaction count below two",
            benchmark.resolved_material_graph_execution_failures(
                activation_only,
                require_evidence=True,
            ),
        )
        self.assertEqual(
            benchmark.resolved_material_graph_execution_failures(
                activation_only,
                sample={
                    "required_activation_passthrough_reason_codes": [
                        "effect-activation-scalar-below-minimum"
                    ],
                    "minimum_activation_passthrough_count": 2,
                },
            ),
            [],
        )

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

    def test_resolved_graph_startup_passthrough_joins_terminal_evidence(
        self,
    ) -> None:
        preview_text = "\n".join([
            "resolved material execution capabilities: "
            "schema=layer-graph-capability-v1 candidates=1 accepted=1 "
            "rejected=0 variantLimit=8",
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=68 status=accepted",
        ])
        disposition, effect_execution = resolved_graph_passthrough_evidence(68)
        self.assertEqual(effect_execution["validation_failures"], [])
        self.assertEqual(effect_execution["succeeded_exact_effects"], [])

        def passthrough_log(
            reason: str,
            *,
            compositor_consumed: bool,
        ) -> str:
            program = f"activation-passthrough:{reason}"
            return "\n".join([
                "resolved material runtime audit: "
                "schema=scene-graph-executor-v1 claimed=2 encoded=2 "
                "failures=0 deferred=0 pending=0 gpuEncoded=2",
                graph_execution_observation(
                    frame=10,
                    layer=68,
                    effect=0,
                    descriptor_id="68%23effect%230",
                    transaction="tx-passthrough-10",
                    trigger="first-frame+gpu-completed",
                    authored=1,
                    material=0,
                    copy=0,
                    swap=0,
                    compose=0,
                    rejected=1,
                    program=program,
                ),
                graph_execution_observation(
                    frame=11,
                    layer=68,
                    effect=0,
                    descriptor_id="68%23effect%230",
                    transaction="tx-passthrough-11",
                    trigger="next-frame+compositor-consume+gpu-completed",
                    authored=1,
                    material=0,
                    copy=0,
                    swap=0,
                    compose=0,
                    rejected=1,
                    consumed=compositor_consumed,
                    program=program,
                ),
            ])

        metrics = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            passthrough_log(
                "initially-inactive-property-stage-passthrough",
                compositor_consumed=True,
            ),
            effect_execution=effect_execution,
            static_disposition=disposition,
        )
        self.assertTrue(metrics["execution_succeeded"])
        self.assertEqual(metrics["succeeded_layer_ids"], [68])
        self.assertEqual(metrics["exact_backend"]["required_layer_ids"], [])
        self.assertEqual(metrics["exact_backend"]["no_demand_layer_ids"], [68])
        self.assertEqual(metrics["passthrough"]["complete_layer_ids"], [68])
        self.assertEqual(metrics["validation_failures"], [])
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

        mixed_disposition, mixed_execution = (
            resolved_graph_passthrough_evidence(68, include_program=True)
        )
        self.assertEqual(mixed_execution["validation_failures"], [])
        self.assertEqual(len(mixed_execution["succeeded_exact_effects"]), 1)
        mixed_log = passthrough_log(
            "initially-inactive-property-stage-passthrough",
            compositor_consumed=True,
        ).replace(
            "claimed=2 encoded=2 failures=0 deferred=0 pending=0 gpuEncoded=2",
            "claimed=4 encoded=4 failures=0 deferred=0 pending=0 gpuEncoded=4",
        ) + "\n" + "\n".join([
            graph_execution_observation(
                frame=10,
                layer=68,
                effect=1,
                descriptor_id="68%23effect%231",
                transaction="tx-program-10",
                trigger="first-frame+gpu-completed",
                program="program-identity",
            ),
            graph_execution_observation(
                frame=11,
                layer=68,
                effect=1,
                descriptor_id="68%23effect%231",
                transaction="tx-program-11",
                trigger="next-frame+gpu-completed",
                program="program-identity",
            ),
        ])
        mixed = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            mixed_log,
            effect_execution=mixed_execution,
            static_disposition=mixed_disposition,
        )
        self.assertTrue(mixed["execution_succeeded"])
        self.assertEqual(mixed["succeeded_layer_ids"], [68])
        self.assertEqual(mixed["exact_backend"]["required_layer_ids"], [68])
        self.assertEqual(mixed["passthrough"]["complete_layer_ids"], [68])
        self.assertEqual(mixed["validation_failures"], [])

        wrong_reason = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            passthrough_log(
                "effect-activation-visibility-disabled",
                compositor_consumed=True,
            ),
            effect_execution=effect_execution,
            static_disposition=disposition,
        )
        self.assertEqual(wrong_reason["succeeded_layer_ids"], [])
        self.assertIn(
            "resolved material graph passthrough activation evidence malformed",
            wrong_reason["validation_failures"],
        )

        missing_compositor = (
            benchmark.resolved_material_graph_execution_metrics(
                preview_text,
                passthrough_log(
                    "initially-inactive-property-stage-passthrough",
                    compositor_consumed=False,
                ),
                effect_execution=effect_execution,
                static_disposition=disposition,
            )
        )
        self.assertEqual(missing_compositor["succeeded_layer_ids"], [])
        self.assertIn(
            "resolved material graph passthrough compositor evidence missing",
            missing_compositor["validation_failures"],
        )

    def test_resolved_material_graph_execution_gate_conserves_layer_routes(
        self,
    ) -> None:
        preview_text = "\n".join([
            "resolved material execution capabilities: "
            "schema=layer-graph-capability-v1 candidates=3 accepted=2 "
            "rejected=1 variantLimit=8",
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=68 status=accepted",
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=76 status=accepted",
        ])
        log_text = "\n".join([
            "resolved material runtime audit: schema=scene-graph-executor-v1 "
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
    def test_resolved_material_graph_execution_gate_rejects_bad_layer_routes(
        self,
    ) -> None:
        metrics = benchmark.resolved_material_graph_execution_metrics(
            "\n".join([
                "resolved material execution capabilities: "
                "schema=layer-graph-capability-v1 candidates=2 accepted=2 "
                "rejected=0 variantLimit=8",
                "resolved material execution capability: "
                "schema=layer-graph-route-v1 layer=68 status=accepted",
                "resolved material execution capability: "
                "schema=layer-graph-route-v1 layer=68 status=accepted",
                "resolved material execution capability: "
                "schema=layer-graph-route-v1 layer=bad status=accepted",
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
            "schema=layer-graph-capability-v1 candidates=2 accepted=2 "
            "rejected=0 variantLimit=8",
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=68 status=accepted",
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=76 status=accepted",
        ])
        log_text = "\n".join([
            "resolved material runtime audit: schema=scene-graph-executor-v1 "
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
                "resolved material runtime audit: schema=scene-graph-executor-v1 "
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
            "schema=layer-graph-capability-v1 candidates=2 accepted=2 "
            "rejected=0 variantLimit=8",
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=68 status=accepted",
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=76 status=accepted",
        ])
        log_text = "\n".join([
            "resolved material runtime audit: schema=scene-graph-executor-v1 "
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
            "schema=layer-graph-capability-v1 candidates=1 accepted=0 "
            "rejected=1 variantLimit=8",
            "resolved material runtime audit: schema=scene-graph-executor-v1 "
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
            "schema=layer-graph-capability-v1 candidates=1 accepted=0 "
            "rejected=1 variantLimit=8",
            "\n".join([
                "resolved material runtime audit: schema=scene-graph-executor-v1 "
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
            "schema=layer-graph-capability-v1 candidates=1 accepted=1 "
            "rejected=0 variantLimit=8",
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=68 status=accepted",
        ])
        graph_log = "\n".join([
            "resolved material runtime audit: schema=scene-graph-executor-v1 "
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
                {68: "non-unified-backend"},
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

    def test_resolved_material_graph_execution_gate_rejects_unaccepted_layers(
        self,
    ) -> None:
        preview_text = "\n".join([
            "resolved material execution capabilities: "
            "schema=layer-graph-capability-v1 candidates=1 accepted=1 "
            "rejected=0 variantLimit=8",
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=68 status=accepted",
        ])
        log_text = "\n".join([
            "resolved material runtime audit: schema=scene-graph-executor-v1 "
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

    def test_cursor_ripple_persistence_can_be_required_from_cli(self) -> None:
        old_argv = sys.argv
        try:
            sys.argv = [
                "scene_wallpaper_benchmark.py",
                "--app", "/tmp/MyWallpaperX",
                "--sample-root", "/tmp/samples",
                "--output-dir", "/tmp/results",
                "--require-cursor-ripple-persistence",
            ]
            args = benchmark.parse_args()
        finally:
            sys.argv = old_argv
        self.assertTrue(args.require_cursor_ripple_persistence)


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

    def test_authored_tint_pulse_and_godrays_counts_are_exact_gates(self) -> None:
        preview = (
            "authoredEffectGraphTintCount: 24\n"
            "authoredEffectGraphPulseCount: 1\n"
            "authoredEffectGraphGodraysCount: 12\n"
        )
        tint_count = benchmark.authored_effect_graph_tint_count(preview)
        pulse_count = benchmark.authored_effect_graph_pulse_count(preview)
        godrays_count = benchmark.authored_effect_graph_godrays_count(preview)
        self.assertEqual(tint_count, 24)
        self.assertEqual(pulse_count, 1)
        self.assertEqual(godrays_count, 12)
        self.assertEqual(
            benchmark.authored_effect_graph_failures(
                {
                    "expected_authored_effect_graph_tint_count": 24,
                    "expected_authored_effect_graph_pulse_count": 1,
                    "expected_authored_effect_graph_godrays_count": 12,
                },
                None,
                tint_count=tint_count,
                pulse_count=pulse_count,
                godrays_count=godrays_count,
            ),
            [],
        )
        failures = benchmark.authored_effect_graph_failures(
            {
                "expected_authored_effect_graph_tint_count": 0,
                "expected_authored_effect_graph_pulse_count": 0,
                "expected_authored_effect_graph_godrays_count": 0,
            },
            None,
            tint_count=tint_count,
            pulse_count=pulse_count,
            godrays_count=godrays_count,
        )
        self.assertIn("authored effect graph Tint count mismatch", failures)
        self.assertIn("authored effect graph Pulse count mismatch", failures)
        self.assertIn("authored effect graph Godrays count mismatch", failures)
        self.assertIsNone(benchmark.authored_effect_graph_tint_count(""))
        self.assertIsNone(benchmark.authored_effect_graph_pulse_count(""))
        self.assertIsNone(benchmark.authored_effect_graph_godrays_count(""))

    def test_named_target_runtime_pins_completed_consumers(self) -> None:
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

    def test_visible_graph_output_publication_execution_is_typed(self) -> None:
        assert_visible_publication_execution_metrics(
            self,
            benchmark=benchmark,
        )

    def test_named_graph_output_publication_has_one_terminal_owner(self) -> None:
        assert_named_graph_output_publication_has_one_terminal_owner(
            self,
            benchmark=benchmark,
            graph_execution_observation=graph_execution_observation,
            resolved_graph_exact_evidence=resolved_graph_exact_evidence,
        )


if __name__ == "__main__":
    unittest.main()
