#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from collections import defaultdict
from pathlib import Path
from unittest import mock

SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))
DEBUG_RUNNER_SOURCE = (
    SCRIPT_DIR.parent / "MyWallpaperX/App/Debug/DebugScenePlaybackRunner.swift"
)
DEBUG_ARGUMENTS_RUNNER_SOURCE = (
    SCRIPT_DIR.parent
    / "MyWallpaperX/App/Debug/DebugScenePlaybackRunner+Arguments.swift"
)

import scene_wallpaper_benchmark as benchmark
import scene_preview_visual_evidence as visual
import generate_scene_full_matrix as matrix_generator
from script.tests.scene_wallpaper_graph_output_test_support import (
    assert_named_graph_output_publication_has_one_terminal_owner,
    assert_named_provider_terminal,
    assert_visible_provider_requires_compositor_consumption,
    assert_visible_publication_execution_metrics,
    assert_utility_capture_respects_dormant_graph_members,
)

from script.tests.scene_wallpaper_benchmark_test_support import (
    static_effect_disposition,
    shader_stage,
    runtime_evidence,
    effect_runtime_disposition_preview,
    effect_cpu_event,
    effect_route_event,
    effect_execution_log,
    graph_execution_observation,
    resolved_graph_exact_evidence,
    resolved_graph_passthrough_evidence,
    resolved_graph_effect_local_failure_evidence,
    resolved_graph_effect_recovery_evidence,
    resolved_graph_effect_recovery_log,
    resolved_graph_visual_failure_log,
)


class SceneWallpaperGraphRecoveryTests(unittest.TestCase):
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

    def test_resolved_material_graph_typed_startup_fallback_requires_next_frame_recovery(
        self,
    ) -> None:
        preview_text = (
            "resolved material execution capabilities: "
            "schema=layer-graph-capability-v1 candidates=1 accepted=1 "
            "rejected=0 variantLimit=8\n"
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=22 status=accepted\n"
        )
        disposition = static_effect_disposition(
            records=[{
                "layer_id": 22,
                "effect_index": 0,
                "descriptor_id": "22#effect#23",
                "definition_path": "effects/xray/effect.json",
                "family": "resolved-material",
                "kind": "program",
            }],
            groups=[{"layer_id": 22, "kind": "authored"}],
        )
        cpu = effect_cpu_event(
            frame=8,
            origin="image",
            subject="effect",
            layer=22,
            effect=0,
            descriptor="22%23effect%2323",
            family="resolved-material",
            backend=benchmark.RESOLVED_MATERIAL_GRAPH_BACKEND,
        )
        effect_execution = benchmark.effect_execution_metrics(
            effect_execution_log(8, [cpu], []),
            disposition,
        )
        first = graph_execution_observation(
            frame=8,
            layer=22,
            transaction="first-provider-frame",
            trigger="first-frame+reset+first-success+compositor-consume+gpu-completed",
            consumed=True,
        )
        next_frame = graph_execution_observation(
            frame=9,
            layer=22,
            transaction="next-provider-frame",
            trigger="next-frame+compositor-consume+gpu-completed",
            consumed=True,
        )
        later_without_next_frame = graph_execution_observation(
            frame=9,
            layer=22,
            transaction="later-provider-frame",
            trigger="compositor-consume+gpu-completed",
            consumed=True,
        )
        expected_fallbacks = [{
            "layer_id": 22,
            "reason": "layer-source-not-ready",
        }]
        sample = {
            "expected_resolved_material_graph_succeeded_layer_ids": [22],
            "expected_resolved_material_graph_local_fallbacks":
                expected_fallbacks,
        }
        common_log = [
            "resolved material runtime audit: schema=scene-graph-executor-v1 "
            "claimed=0 encoded=0 failures=0 deferred=0 pending=0 "
            "gpuEncoded=0 localFallbacks=1",
            "schema=1 axis=graph-execution diagnostic="
            "layer-local-fallback count=1 entries="
            "22:layer-source-not-ready frame=0",
            "resolved material runtime audit: schema=scene-graph-executor-v1 "
            "claimed=1 encoded=1 failures=0 deferred=0 pending=1 "
            "gpuEncoded=1 localFallbacks=0",
            first,
        ]
        recovered = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            "\n".join([*common_log, next_frame]),
            effect_execution=effect_execution,
            static_disposition=disposition,
        )
        self.assertEqual(
            recovered["executor"][
                "transient_recovered_fallback_layer_ids"
            ],
            [22],
        )
        self.assertEqual(
            benchmark.resolved_material_graph_execution_failures(
                recovered,
                require_evidence=True,
                sample=sample,
            ),
            [],
        )

        missing_next_frame = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            "\n".join([*common_log, later_without_next_frame]),
            effect_execution=effect_execution,
            static_disposition=disposition,
        )
        self.assertEqual(
            missing_next_frame["executor"][
                "transient_recovered_fallback_layer_ids"
            ],
            [],
        )
        self.assertNotEqual(
            benchmark.resolved_material_graph_execution_failures(
                missing_next_frame,
                require_evidence=True,
                sample=sample,
            ),
            [],
        )

    def test_resolved_graph_effect_recovery_joins_typed_cpu_and_program_frames(
        self,
    ) -> None:
        preview_text = "\n".join([
            "resolved material execution capabilities: "
            "schema=layer-graph-capability-v1 candidates=1 accepted=1 "
            "rejected=0 variantLimit=8",
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=68 status=accepted "
            "dependency=none dependencyReferences=0",
        ])
        disposition, effect_execution, expectation = (
            resolved_graph_effect_recovery_evidence()
        )
        sample = {
            "expected_resolved_material_graph_succeeded_layer_ids": [68],
            benchmark.EFFECT_RECOVERY_EXPECTATION_KEY: [expectation],
        }
        metrics = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            resolved_graph_effect_recovery_log(),
            effect_execution=effect_execution,
            static_disposition=disposition,
        )

        self.assertTrue(metrics["execution_succeeded"])
        self.assertEqual(metrics["succeeded_layer_ids"], [68])
        self.assertEqual(
            metrics["exact_backend"]["program_required_layer_ids"],
            [68],
        )
        self.assertEqual(
            metrics["exact_backend"]["mixed_program_required_subjects"],
            [(68, 0, "68#effect#0")],
        )
        self.assertEqual(
            benchmark.resolved_material_graph_execution_failures(
                metrics,
                require_evidence=True,
                sample=sample,
            ),
            [],
        )
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

        wrong_static_contract = {
            "expected_resolved_material_graph_succeeded_layer_ids": [68],
            benchmark.EFFECT_LOCAL_PASSTHROUGH_EXPECTATION_KEY: [expectation],
        }
        self.assertIn(
            "resolved material graph recovery expectation scope conflicts",
            benchmark.resolved_material_graph_execution_failures(
                metrics,
                require_evidence=True,
                sample=wrong_static_contract,
            ),
        )

        for kwargs, expected_failure in (
            (
                {"fallback_outcome": "failed"},
                "resolved material graph recovery passthrough terminal missing",
            ),
            (
                {"fallback_gpu_completion": "-"},
                "resolved material graph recovery passthrough terminal missing",
            ),
            (
                {"program_outcome": "failed"},
                "resolved material graph recovery Program terminal missing",
            ),
            (
                {"program_gpu_completion": "-"},
                "resolved material graph recovery Program terminal missing",
            ),
            (
                {"next_program_outcome": "failed"},
                "resolved material graph recovery next-frame Program missing",
            ),
            (
                {"next_program_gpu_completion": "-"},
                "resolved material graph recovery next-frame Program missing",
            ),
        ):
            incomplete_terminal = (
                benchmark.resolved_material_graph_execution_metrics(
                    preview_text,
                    resolved_graph_effect_recovery_log(**kwargs),
                    effect_execution=effect_execution,
                    static_disposition=disposition,
                )
            )
            for recovery_sample in ({}, sample):
                self.assertIn(
                    expected_failure,
                    benchmark.resolved_material_graph_execution_failures(
                        incomplete_terminal,
                        require_evidence=True,
                        sample=recovery_sample,
                    ),
                )

        missing_next_frame = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            resolved_graph_effect_recovery_log(
                include_program_next_frame=False
            ),
            effect_execution=effect_execution,
            static_disposition=disposition,
        )
        missing_next_failures = (
            benchmark.resolved_material_graph_execution_failures(
                missing_next_frame,
                require_evidence=True,
                sample=sample,
            )
        )
        self.assertIn(
            "resolved material graph recovery next-frame Program missing",
            missing_next_failures,
        )
        self.assertIn(
            "resolved material graph mixed Program exact subject join failed",
            missing_next_frame["validation_failures"],
        )

        switched_program = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            resolved_graph_effect_recovery_log(
                next_program_identity="b" * 64
            ),
            effect_execution=effect_execution,
            static_disposition=disposition,
        )
        self.assertIn(
            "resolved material graph recovery next-frame Program missing",
            benchmark.resolved_material_graph_execution_failures(
                switched_program,
                require_evidence=True,
                sample=sample,
            ),
        )

        wrong_reason = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            resolved_graph_effect_recovery_log(
                reason="material-finalizer-system-provider-purpose-mismatch"
            ),
            effect_execution=effect_execution,
            static_disposition=disposition,
        )
        self.assertIn(
            "resolved material graph recovery evidence mismatch",
            benchmark.resolved_material_graph_execution_failures(
                wrong_reason,
                require_evidence=True,
                sample=sample,
            ),
        )

        source_lines = resolved_graph_effect_recovery_log().splitlines()
        for runtimes, expected_failure in (
            (("a", "a", "a"), None),
            (("a", "b", "b"), "resolved material graph recovery Program terminal missing"),
            (("a", "a", "b"), "resolved material graph recovery next-frame Program missing"),
        ):
            with self.subTest(runtimes=runtimes):
                lines = [source_lines[0], *(
                    line.replace("axis=graph-execution ",
                                 f"axis=graph-execution runtime={runtime} ")
                    for line, runtime in zip(source_lines[1:], runtimes)
                )]
                runtime_metrics = benchmark.resolved_material_graph_execution_metrics(
                    preview_text, "\n".join(lines),
                    effect_execution=effect_execution, static_disposition=disposition,
                )
                failures = benchmark.resolved_material_graph_execution_failures(
                    runtime_metrics, require_evidence=True,
                )
                if expected_failure:
                    self.assertIn(expected_failure, failures)
                else:
                    self.assertEqual(failures, [])
                    second_runtime = [
                        line.replace("runtime=a ", "runtime=b ")
                            .replace("transaction=", "transaction=second-")
                        for line in lines[1:]
                    ]
                    second_runtime[0] = second_runtime[0].replace("frame=10 ", "frame=11 ")
                    for extra, incomplete in (
                        (second_runtime[:1], True), (second_runtime, False),
                    ):
                        combined = benchmark.resolved_material_graph_execution_metrics(
                            preview_text, "\n".join([
                                lines[0].replace("claimed=3 encoded=3", f"claimed={3 + len(extra)} encoded={3 + len(extra)}")
                                    .replace("gpuEncoded=3", f"gpuEncoded={3 + len(extra)}"),
                                *lines[1:], *extra,
                            ]),
                            effect_execution=effect_execution, static_disposition=disposition,
                        )
                        combined_failures = benchmark.resolved_material_graph_execution_failures(
                            combined, require_evidence=True,
                        )
                        if incomplete:
                            self.assertIn("resolved material graph recovery Program terminal missing", combined_failures)
                        else:
                            self.assertEqual(combined_failures, [])

        later_fallback = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            "\n".join([*source_lines, source_lines[1].replace("frame=10 ", "frame=22 ")
                       .replace("transaction=", "transaction=late-")]),
            effect_execution=effect_execution, static_disposition=disposition,
        )
        self.assertIn(
            "resolved material graph recovery passthrough terminal missing",
            benchmark.resolved_material_graph_execution_failures(later_fallback, require_evidence=True),
        )

    def test_pending_fallback_needs_its_own_completed_transaction(self) -> None:
        preview = (
            "resolved material execution capabilities: schema=layer-graph-capability-v1 candidates=1 accepted=1 rejected=0 variantLimit=8\n"
            "resolved material execution capability: schema=layer-graph-route-v1 layer=68 status=accepted"
        )
        disposition, execution, _ = resolved_graph_effect_recovery_evidence(failure_frames=(10, 11))
        primary = [line.replace("axis=graph-execution ", "axis=graph-execution runtime=a ")
                   for line in resolved_graph_effect_recovery_log().splitlines()[1:]]
        secondary = [line.replace("runtime=a ", "runtime=b ")
                     .replace("transaction=", "transaction=second-") for line in primary]
        secondary[0] = secondary[0].replace("frame=10 ", "frame=11 ")
        pending = secondary[0].replace("gpuCompletion=completed", "gpuCompletion=-") \
            .replace("first-frame+gpu-completed", "first-frame")
        unrelated = primary[1].replace("gpuCompletion=completed", "gpuCompletion=-") \
            .replace("runtime=a ", "runtime=unrelated ")
        for name, extra, encoded, pending_count in (
            ("pending-only", [pending], 4, 1),
            ("pending-with-program", [pending, *secondary[1:]], 6, 1),
            ("wrong-transaction", [pending, secondary[0].replace("transaction=", "transaction=other-"), *secondary[1:]], 7, 1),
            ("completed", [pending, *secondary], 6, 0),
            ("completion-before-pending", [*secondary, pending], 6, 0),
            ("ordinary-program-pending", [unrelated], 4, 0),
        ):
            with self.subTest(name=name):
                audit = ("resolved material runtime audit: schema=scene-graph-executor-v1 "
                         f"claimed={encoded} encoded={encoded} failures=0 deferred=0 pending=0 "
                         f"gpuEncoded={encoded} localFallbacks=0")
                metrics = benchmark.resolved_material_graph_execution_metrics(
                    preview, "\n".join([audit, *primary, *extra]),
                    effect_execution=execution, static_disposition=disposition,
                )
                observations = metrics["graph_observations"]
                self.assertEqual(len(observations["pending_visual_failure_passthroughs"]), pending_count)
                self.assertTrue(all(value["gpu_completion"] == "completed"
                                    for value in observations["terminal_success_observations"]))
                failures = benchmark.resolved_material_graph_execution_failures(metrics, require_evidence=True)
                if pending_count:
                    self.assertIn("resolved material graph recovery passthrough terminal missing", failures)
                    if name == "pending-only":
                        self.assertIn("resolved material graph recovery Program terminal missing", failures)
                else:
                    self.assertEqual(failures, [])

        for name, invalid in (
            ("suffix", secondary[0].replace("visual-failure-passthrough:material-finalizer-system-provider-unavailable",
                                            "visual-failure-passthrough:bad:reason")),
            ("shape", secondary[0].replace("materialNodes=0", "materialNodes=1")
                .replace("rejectedNodes=1", "rejectedNodes=0")),
        ):
            for gpu in ("-", "completed"):
                with self.subTest(case=name, gpu=gpu):
                    audit = ("resolved material runtime audit: schema=scene-graph-executor-v1 "
                             "claimed=4 encoded=4 failures=0 deferred=0 pending=0 gpuEncoded=4 localFallbacks=0")
                    wire = invalid.replace("gpuCompletion=completed", f"gpuCompletion={gpu}")
                    if gpu == "-":
                        wire = wire.replace("+gpu-completed", "")
                    metrics = benchmark.resolved_material_graph_execution_metrics(
                        preview, "\n".join([audit, *primary, wire]),
                        effect_execution=execution, static_disposition=disposition,
                    )
                    observations = metrics["graph_observations"]
                    self.assertEqual(observations["terminal_success_count"], 3)
                    self.assertEqual(observations["program_terminal_success_count"], 2)
                    self.assertEqual(observations["pending_visual_failure_passthroughs"], [])
                    self.assertIn(
                        "resolved material graph visual failure passthrough identity or shape invalid",
                        benchmark.resolved_material_graph_execution_failures(metrics, require_evidence=True),
                    )

    def test_recovered_intermediate_effect_keeps_the_layer_terminal_gate(self) -> None:
        preview = (
            "resolved material execution capabilities: schema=layer-graph-capability-v1 candidates=1 accepted=1 rejected=0 variantLimit=8\n"
            "resolved material execution capability: schema=layer-graph-route-v1 layer=68 status=accepted"
        )
        disposition, _, expectation = resolved_graph_effect_recovery_evidence()
        disposition["records"].append({
            "layer_id": 68, "effect_index": 1, "descriptor_id": "68#effect#1",
            "definition_path": "effects/final/effect.json", "family": "generic-fragment",
            "kind": "program",
        })
        cpu_frames = defaultdict(list)
        for frame, index, outcome in ((10, 0, "failed"), (20, 0, "encoded-output"), (20, 1, "encoded-output")):
            cpu_frames[frame].append(effect_cpu_event(
                frame=frame, origin="resolved-material-graph", subject="effect", layer=68,
                effect=index, descriptor=f"68%23effect%23{index}",
                family="visual-failure-passthrough" if index == 0 else "generic-fragment",
                backend=benchmark.RESOLVED_MATERIAL_GRAPH_BACKEND, outcome=outcome,
                reason="effect-local-passthrough-" + expectation["reason"] if outcome == "failed" else "-",
            ))
        execution = benchmark.effect_execution_metrics(
            "\n".join(effect_execution_log(frame, events, []) for frame, events in cpu_frames.items()),
            disposition,
        )
        stages = resolved_graph_effect_recovery_log(
            fallback_consumed=False, program_consumed=False, next_program_consumed=False,
        ).splitlines()
        stages[0] = stages[0].replace("claimed=3 encoded=3", "claimed=5 encoded=5").replace("gpuEncoded=3", "gpuEncoded=5")
        for consumed in (True, False):
            with self.subTest(final_consumed=consumed):
                terminals = [graph_execution_observation(
                    frame=frame, layer=68, effect=1, descriptor_id="68%23effect%231",
                    transaction=f"final-{frame}", trigger="next-frame+gpu-completed",
                    consumed=consumed, program="b" * 64,
                ) for frame in (20, 21)]
                metrics = benchmark.resolved_material_graph_execution_metrics(
                    preview, "\n".join([*stages, *terminals]),
                    effect_execution=execution, static_disposition=disposition,
                )
                failures = benchmark.resolved_material_graph_execution_failures(metrics, require_evidence=True)
                if consumed:
                    self.assertEqual(failures, [])
                else:
                    self.assertIn("resolved material graph accepted layer compositor consumption missing", failures)
                    self.assertFalse(any("recovery" in failure for failure in failures))

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

        for reason in ("inactive-dependency-preproof-mismatch", "future-policy.v2_other"):
            with self.subTest(reason=reason):
                diagnosed = benchmark.resolved_material_graph_execution_metrics(
                    preview_text,
                    passthrough_log(reason, compositor_consumed=True),
                    effect_execution=effect_execution,
                    static_disposition=disposition,
                )
                self.assertEqual(diagnosed["succeeded_layer_ids"], [68])
                self.assertEqual(diagnosed["validation_failures"], [])
                self.assertEqual(diagnosed["graph_observations"]["activation_passthrough_reason_codes"], [reason])
                self.assertEqual(diagnosed["graph_observations"]["program_terminal_success_count"], 0)
                self.assertEqual(diagnosed["graph_observations"]["program_effect_subjects"], [])

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


if __name__ == "__main__":
    unittest.main()
