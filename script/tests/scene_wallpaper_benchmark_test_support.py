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
    full_frame_pair_storage: str = "owned",
    full_frame_pair_generation: int | None = None,
    final_physical_identity: str | None = None,
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
    dependency_providers: list[int] | None = None,
) -> str:
    final_output = f"output-{transaction}" if publish else "-"
    final_physical = (
        final_physical_identity or f"physical-{transaction}"
    ) if publish else "-"
    final_publication = f"publication-{transaction}" if publish else "-"
    publication_generation = frame if publish else 0
    allocation_generation = (
        frame if allocation_generation is None else allocation_generation
    )
    mapping_generation = frame if mapping_generation is None else mapping_generation
    full_frame_pair_generation = (
        allocation_generation
        if full_frame_pair_generation is None else full_frame_pair_generation
    )
    runtime_field = (
        f"runtime={runtime_instance_identity} "
        if runtime_instance_identity is not None else ""
    )
    effect_field = f"effect={effect} " if effect is not None else ""
    descriptor_field = (
        f"descriptor={descriptor_id} " if descriptor_id is not None else ""
    )
    program_field = f"program={program} " if program is not None else ""
    dependency_providers_field = (
        "dependencyProviders="
        + ",".join(str(provider) for provider in dependency_providers)
        + " "
        if dependency_providers is not None else ""
    )
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
        f"fullFramePairStorage={full_frame_pair_storage} "
        f"fullFramePairGeneration={full_frame_pair_generation} "
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
        + (f" {dependency_providers_field}".rstrip() if dependency_providers_field else "")
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


def resolved_graph_effect_local_failure_evidence(
    layer_id: int = 68,
    *,
    reason: str = "material-finalizer-system-provider-purpose-mismatch",
    event_descriptor_id: str | None = None,
    backend: str = benchmark.RESOLVED_MATERIAL_GRAPH_BACKEND,
    include_extra_failed_program: bool = False,
    include_successful_program: bool = False,
    fallback_effect_index: int = 0,
) -> tuple[dict[str, object], dict[str, object], dict[str, object]]:
    descriptor_id = f"{layer_id}#effect#{fallback_effect_index}"
    records = [{
        "layer_id": layer_id,
        "effect_index": fallback_effect_index,
        "descriptor_id": descriptor_id,
        "definition_path": f"effects/{layer_id}/fallback/effect.json",
        "family": "visual-failure-passthrough",
        "kind": "fallback",
    }]
    events = [effect_cpu_event(
        frame=90,
        origin="resolved-material-graph",
        subject="effect",
        layer=layer_id,
        effect=fallback_effect_index,
        descriptor=(
            event_descriptor_id or descriptor_id.replace("#", "%23")
        ),
        family="visual-failure-passthrough",
        backend=backend,
        outcome="failed",
        reason=f"effect-local-passthrough-{reason}",
    )]
    if include_extra_failed_program or include_successful_program:
        program_effect_index = 0 if fallback_effect_index == 1 else 1
        records.append({
            "layer_id": layer_id,
            "effect_index": program_effect_index,
            "descriptor_id": f"{layer_id}#effect#{program_effect_index}",
            "definition_path": f"effects/{layer_id}/program/effect.json",
            "family": "generic-fragment",
            "kind": "program",
        })
        events.append(effect_cpu_event(
            frame=90,
            origin="resolved-material-graph",
            subject="effect",
            layer=layer_id,
            effect=program_effect_index,
            descriptor=f"{layer_id}%23effect%23{program_effect_index}",
            family="generic-fragment",
            backend=benchmark.RESOLVED_MATERIAL_GRAPH_BACKEND,
            outcome=(
                "failed" if include_extra_failed_program
                else "encoded-output"
            ),
            reason=(
                "fixture-failure" if include_extra_failed_program else "-"
            ),
        ))
    disposition = static_effect_disposition(
        records=records,
        groups=[{"layer_id": layer_id, "kind": "resolved"}],
    )
    execution = benchmark.effect_execution_metrics(
        effect_execution_log(90, events, []),
        disposition,
    )
    expectation = {
        "layer_id": layer_id,
        "effect_index": fallback_effect_index,
        "descriptor_id": descriptor_id,
        "reason": reason,
    }
    return disposition, execution, expectation


def resolved_graph_effect_recovery_evidence(
    layer_id: int = 68,
    *,
    reason: str = "material-finalizer-system-provider-unavailable",
    failure_frame: int = 10,
    failure_frames: tuple[int, ...] | None = None,
    success_frame: int = 20,
    failure_backend: str = benchmark.RESOLVED_MATERIAL_GRAPH_BACKEND,
    failure_descriptor_id: str | None = None,
) -> tuple[dict[str, object], dict[str, object], dict[str, object]]:
    descriptor_id = f"{layer_id}#effect#0"
    disposition = static_effect_disposition(
        records=[{
            "layer_id": layer_id,
            "effect_index": 0,
            "descriptor_id": descriptor_id,
            "definition_path": f"effects/{layer_id}/fallback/effect.json",
            "family": "visual-failure-passthrough",
            "kind": "fallback",
        }],
        groups=[{"layer_id": layer_id, "kind": "resolved"}],
    )
    failure_frames = failure_frames or (failure_frame,)
    failed_events = [
        effect_cpu_event(
            frame=frame,
            origin="resolved-material-graph",
            subject="effect",
            layer=layer_id,
            effect=0,
            descriptor=(
                failure_descriptor_id or descriptor_id.replace("#", "%23")
            ),
            family="visual-failure-passthrough",
            backend=failure_backend,
            outcome="failed",
            reason=f"effect-local-passthrough-{reason}",
        )
        for frame in failure_frames
    ]
    succeeded = effect_cpu_event(
        frame=success_frame,
        origin="resolved-material-graph",
        subject="effect",
        layer=layer_id,
        effect=0,
        descriptor=descriptor_id.replace("#", "%23"),
        family="visual-failure-passthrough",
        backend=benchmark.RESOLVED_MATERIAL_GRAPH_BACKEND,
        outcome="encoded-output",
        reason="-",
    )
    execution = benchmark.effect_execution_metrics(
        "\n".join([
            *(
                effect_execution_log(frame, [failed], [])
                for frame, failed in zip(failure_frames, failed_events)
            ),
            effect_execution_log(success_frame, [succeeded], []),
        ]),
        disposition,
    )
    expectation = {
        "layer_id": layer_id,
        "effect_index": 0,
        "descriptor_id": descriptor_id,
        "reason": reason,
    }
    return disposition, execution, expectation


def resolved_graph_effect_recovery_log(
    layer_id: int = 68,
    *,
    reason: str = "material-finalizer-system-provider-unavailable",
    failure_frame: int = 10,
    success_frame: int = 20,
    fallback_consumed: bool = True,
    program_consumed: bool = True,
    next_program_consumed: bool = True,
    fallback_outcome: str = "succeeded",
    program_outcome: str = "succeeded",
    next_program_outcome: str = "succeeded",
    fallback_gpu_completion: str = "completed",
    program_gpu_completion: str = "completed",
    next_program_gpu_completion: str = "completed",
    program_identity: str = "a" * 64,
    next_program_identity: str | None = None,
    include_program_next_frame: bool = True,
) -> str:
    descriptor_id = f"{layer_id}%23effect%230"
    next_program_identity = next_program_identity or program_identity
    encoded_count = 2 + int(include_program_next_frame)
    lines = [
        "resolved material runtime audit: "
        f"schema=scene-graph-executor-v1 claimed={encoded_count} "
        f"encoded={encoded_count} failures=0 deferred=0 pending=0 "
        f"gpuEncoded={encoded_count} localFallbacks=0",
        graph_execution_observation(
            frame=failure_frame,
            layer=layer_id,
            effect=0,
            descriptor_id=descriptor_id,
            transaction=f"tx-recovery-failure-{failure_frame}",
            trigger="first-frame+gpu-completed",
            authored=1,
            material=0,
            copy=0,
            swap=0,
            compose=0,
            rejected=1,
            consumed=fallback_consumed,
            outcome=fallback_outcome,
            gpu_completion=fallback_gpu_completion,
            program=f"visual-failure-passthrough:{reason}",
        ),
        graph_execution_observation(
            frame=success_frame,
            layer=layer_id,
            effect=0,
            descriptor_id=descriptor_id,
            transaction=f"tx-recovery-program-{success_frame}",
            trigger="provider-ready+gpu-completed",
            authored=1,
            material=1,
            copy=0,
            swap=0,
            compose=0,
            consumed=program_consumed,
            outcome=program_outcome,
            gpu_completion=program_gpu_completion,
            program=program_identity,
        ),
    ]
    if include_program_next_frame:
        lines.append(graph_execution_observation(
            frame=success_frame + 1,
            layer=layer_id,
            effect=0,
            descriptor_id=descriptor_id,
            transaction=f"tx-recovery-program-{success_frame + 1}",
            trigger="next-frame+gpu-completed",
            authored=1,
            material=1,
            copy=0,
            swap=0,
            compose=0,
            consumed=next_program_consumed,
            outcome=next_program_outcome,
            gpu_completion=next_program_gpu_completion,
            program=next_program_identity,
        ))
    return "\n".join(lines)


def resolved_graph_visual_failure_log(
    layer_id: int = 68,
    *,
    reason: str = "material-finalizer-system-provider-purpose-mismatch",
    local_fallback_reason: str | None = None,
    fallback_effect_index: int = 0,
    include_program: bool = False,
    include_program_next_frame: bool = True,
    include_visual_next_frame: bool = True,
) -> str:
    program = f"visual-failure-passthrough:{reason}"
    local_fallback_count = 1 if local_fallback_reason is not None else 0
    encoded_count = (
        1
        + int(include_visual_next_frame)
        + int(include_program)
        + int(include_program and include_program_next_frame)
    )
    lines = [
        "resolved material runtime audit: "
        f"schema=scene-graph-executor-v1 claimed={encoded_count} "
        f"encoded={encoded_count} failures=0 deferred=0 pending=0 "
        f"gpuEncoded={encoded_count} "
        f"localFallbacks={local_fallback_count}",
    ]
    if local_fallback_reason is not None:
        lines.append(
            "layer-local-fallback count=1 entries="
            f"{layer_id}:{local_fallback_reason}"
        )
    program_effect_index = 0 if fallback_effect_index == 1 else 1
    if include_program:
        lines.append(graph_execution_observation(
            frame=10,
            layer=layer_id,
            effect=program_effect_index,
            descriptor_id=f"{layer_id}%23effect%23{program_effect_index}",
            transaction="tx-program-10",
            trigger="first-frame+gpu-completed",
            authored=1,
            material=1,
            copy=0,
            swap=0,
            compose=0,
            program="a" * 64,
        ))
        if include_program_next_frame:
            lines.append(graph_execution_observation(
                frame=11,
                layer=layer_id,
                effect=program_effect_index,
                descriptor_id=(
                    f"{layer_id}%23effect%23{program_effect_index}"
                ),
                transaction="tx-program-11",
                trigger="next-frame+gpu-completed",
                authored=1,
                material=1,
                copy=0,
                swap=0,
                compose=0,
                consumed=not include_visual_next_frame,
                program="a" * 64,
            ))
    lines.append(
        graph_execution_observation(
            frame=10,
            layer=layer_id,
            effect=fallback_effect_index,
            descriptor_id=f"{layer_id}%23effect%23{fallback_effect_index}",
            transaction="tx-visual-failure-10",
            trigger="first-frame+gpu-completed",
            authored=1,
            material=0,
            copy=0,
            swap=0,
            compose=0,
            rejected=1,
            program=program,
        )
    )
    if include_visual_next_frame:
        lines.append(graph_execution_observation(
            frame=11,
            layer=layer_id,
            effect=fallback_effect_index,
            descriptor_id=f"{layer_id}%23effect%23{fallback_effect_index}",
            transaction="tx-visual-failure-11",
            trigger="next-frame+compositor-consume+gpu-completed",
            authored=1,
            material=0,
            copy=0,
            swap=0,
            compose=0,
            rejected=1,
            consumed=True,
            program=program,
        ))
    return "\n".join(lines)
