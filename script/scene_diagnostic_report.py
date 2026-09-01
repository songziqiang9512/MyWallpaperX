#!/usr/bin/env python3
"""Normalize benchmark runtime evidence into stable first-breakpoint clusters.

This tool intentionally does not interpret benchmark matrix expectations and it
does not make a visual-correctness claim.  It only classifies evidence already
present in one or more ``scene_wallpaper_benchmark`` report.json files.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import defaultdict
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 1
CLAIM_BOUNDARY = "runtime-and-output-diagnostics-only-not-visual-correctness"

STAGE_ORDER = {
    "process": 0,
    "launch": 10,
    "resource-load": 15,
    "effect-admission": 20,
    "script-execution": 25,
    "effect-execution": 30,
    "graph-execution": 40,
    "gpu-completion": 50,
    "named-target-capture": 60,
    "named-target-binding": 61,
    "publication": 70,
    "terminal-compositor": 80,
    "next-frame": 90,
}
SEVERITY_ORDER = {"warning": 0, "degraded": 1, "blocking": 2}

SCENE_SCRIPT_TARGET_FAILURE_RE = re.compile(
    r"MWX SceneScript VM: target=(?P<kind>layer|text|particle)"
    r"\(layerID: (?P<layer>\d+), field: [^)]*\."
    r"(?P<field>[A-Za-z][A-Za-z0-9]*)\) failure=(?P<failure>.*?) "
    r"code=(?P<code>\S+) fallback=(?P<fallback>\S+)"
)
SCENE_SCRIPT_EFFECT_FAILURE_RE = re.compile(
    r"MWX SceneScript VM: target=effectConstant"
    r"\(layerID: (?P<layer>\d+), effectIndex: (?P<effect>\d+), "
    r"passIndex: \d+, name: \"[^\"]+\"\) failure=(?P<failure>.*?) "
    r"code=(?P<code>\S+) fallback=(?P<fallback>\S+)"
)


class DiagnosticReportError(ValueError):
    """Raised when an input is not a benchmark report shape."""


def _mapping(value: object) -> Mapping[str, Any]:
    return value if isinstance(value, Mapping) else {}


def _records(value: object) -> list[Mapping[str, Any]]:
    if not isinstance(value, list):
        return []
    return [item for item in value if isinstance(item, Mapping)]


def _integer(value: object) -> int | None:
    if isinstance(value, bool):
        return None
    return value if isinstance(value, int) else None


def _integer_set(value: object) -> set[int]:
    if not isinstance(value, list):
        return set()
    return {
        item for item in value
        if isinstance(item, int) and not isinstance(item, bool)
    }


def _token(value: object, fallback: str) -> str:
    if not isinstance(value, str):
        return fallback
    stripped = value.strip()
    return stripped if stripped and stripped != "-" else fallback


def _definition_family(value: object) -> str:
    """Return a semantic effect family without retaining authored path identity."""
    if not isinstance(value, str):
        return "authored-effect"
    components = [
        component.lower()
        for component in value.replace("\\", "/").split("/")
        if component and component not in {".", ".."}
    ]
    if len(components) < 2:
        return "authored-effect"
    family = components[-2]
    if not all(character.isalnum() or character in {"-", "_"}
               for character in family):
        return "authored-effect"
    return "effect-family:" + family


def _unit(
    radius: str,
    *,
    layer_id: int | None = None,
    effect_index: int | None = None,
    descriptor_id: str | None = None,
) -> tuple[dict[str, Any], str]:
    public: dict[str, Any] = {"kind": radius}
    key_parts = [radius]
    if layer_id is not None:
        public["layerId"] = layer_id
        key_parts.append(f"layer={layer_id}")
    if effect_index is not None:
        public["effectIndex"] = effect_index
        key_parts.append(f"effect={effect_index}")
    if descriptor_id:
        public["descriptorId"] = descriptor_id
        key_parts.append(f"descriptor={descriptor_id}")
    return public, ":".join(key_parts)


def _event(
    *,
    stage: str,
    owner: str,
    reason_code: str,
    profile_or_shape: str,
    failure_radius: str,
    severity: str,
    layer_id: int | None = None,
    effect_index: int | None = None,
    descriptor_id: str | None = None,
    fallback_preserved: bool | None = None,
    evidence_basis: str,
) -> dict[str, Any]:
    unit, unit_key = _unit(
        failure_radius,
        layer_id=layer_id,
        effect_index=effect_index,
        descriptor_id=descriptor_id,
    )
    return {
        "stage": stage,
        "owner": owner,
        "reasonCode": reason_code,
        "capabilityProfileOrAuthoredShape": profile_or_shape,
        "failureRadius": failure_radius,
        "severity": severity,
        "unit": unit,
        "fallbackPreservedTerminalCompositor": fallback_preserved,
        "evidenceBasis": evidence_basis,
        "_unitKey": unit_key,
    }


def _event_sort_key(event: Mapping[str, Any]) -> tuple[object, ...]:
    return (
        STAGE_ORDER.get(str(event.get("stage")), 999),
        -SEVERITY_ORDER.get(str(event.get("severity")), -1),
        str(event.get("owner", "")),
        str(event.get("reasonCode", "")),
        str(event.get("capabilityProfileOrAuthoredShape", "")),
        str(event.get("failureRadius", "")),
        str(event.get("_unitKey", "")),
    )


def _deduplicate(events: list[dict[str, Any]]) -> list[dict[str, Any]]:
    by_key: dict[tuple[object, ...], dict[str, Any]] = {}
    for event in events:
        key = (
            event["stage"],
            event["owner"],
            event["reasonCode"],
            event["capabilityProfileOrAuthoredShape"],
            event["failureRadius"],
            event["_unitKey"],
        )
        existing = by_key.get(key)
        if existing is None or SEVERITY_ORDER[event["severity"]] > (
            SEVERITY_ORDER[existing["severity"]]
        ):
            by_key[key] = event
    return sorted(by_key.values(), key=_event_sort_key)


def _terminal_sets(runtime: Mapping[str, Any]) -> tuple[set[int], set[int]]:
    resolved = _mapping(runtime.get("resolved_material_graph_execution"))
    routes = _mapping(resolved.get("layer_routes"))
    graph = _mapping(resolved.get("graph_observations"))
    compositor = _integer_set(routes.get("compositor_consumed_layer_ids"))
    if not compositor:
        compositor = _integer_set(graph.get("compositor_consumed_layer_ids"))
    next_frame = _integer_set(routes.get("next_frame_layer_ids"))
    if not next_frame:
        next_frame = _integer_set(graph.get("next_frame_layer_ids"))
    return compositor, next_frame


def _preserved(
    layer_id: int | None,
    compositor_ids: set[int],
    next_frame_ids: set[int],
) -> bool | None:
    if layer_id is None:
        return None
    return layer_id in compositor_ids and layer_id in next_frame_ids


def _process_events(sample: Mapping[str, Any]) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    if sample.get("timed_out") is True:
        events.append(_event(
            stage="process",
            owner="DebugScenePlaybackRunner",
            reason_code="process-timeout",
            profile_or_shape="scene-process",
            failure_radius="scene",
            severity="blocking",
            evidence_basis="sample.timed_out",
        ))
    else:
        exit_code = _integer(sample.get("exit_code"))
        if exit_code is not None and exit_code != 0:
            events.append(_event(
                stage="process",
                owner="DebugScenePlaybackRunner",
                reason_code="process-exit-nonzero",
                profile_or_shape="scene-process",
                failure_radius="scene",
                severity="blocking",
                evidence_basis="sample.exit_code",
            ))
    runtime = _mapping(sample.get("runtime"))
    surfaces = _integer(runtime.get("surfaces"))
    if surfaces is None:
        events.append(_event(
            stage="launch",
            owner="SceneDesktopWallpaperHost",
            reason_code="ready-event-missing",
            profile_or_shape="scene-surface",
            failure_radius="scene",
            severity="blocking",
            evidence_basis="runtime.surfaces",
        ))
    elif surfaces < 1:
        events.append(_event(
            stage="launch",
            owner="SceneDesktopWallpaperHost",
            reason_code="surface-unavailable",
            profile_or_shape="scene-surface",
            failure_radius="scene",
            severity="blocking",
            evidence_basis="runtime.surfaces",
        ))
    return events


def _resource_events(runtime: Mapping[str, Any]) -> list[dict[str, Any]]:
    """Report authored drawable inputs that never reached a runtime owner.

    Benchmark matrices historically made these ratios optional expectations.
    Basic-display triage still needs these ratios as cohort leads, but the
    aggregate may include dormant/on-demand candidates. Downstream route and
    output evidence must prove that a currently visible drawable was lost.
    """
    specifications = (
        ("texture_candidates", "loaded_textures", "BaseImageTextureStore",
         "base-image-texture-load-incomplete", "image-layer"),
        ("text_candidates", "loaded_textures_text", "SceneTextTextureLoader",
         "text-texture-load-incomplete", "text-layer"),
        ("solid_candidates", "loaded_solid_layers", "SceneSolidTextureLoader",
         "solid-texture-load-incomplete", "solid-layer"),
        ("particle_candidates", "loaded_particle_layers", "ParticleRuntime",
         "particle-layer-load-incomplete", "particle-layer"),
    )
    events: list[dict[str, Any]] = []
    for candidate_field, loaded_field, owner, reason, shape in specifications:
        candidates = _integer(runtime.get(candidate_field))
        loaded = _integer(runtime.get(loaded_field))
        if candidates is None or candidates <= 0 or loaded is None:
            continue
        if loaded >= candidates:
            continue
        events.append(_event(
            stage="resource-load",
            owner=owner,
            reason_code=reason,
            profile_or_shape=shape,
            failure_radius="scene",
            # The aggregate loader ratio includes intentionally dormant and
            # on-demand candidates. It is a cohort lead, not proof that the
            # currently visible frame lost this drawable family.
            severity="degraded",
            evidence_basis=f"runtime.{loaded_field}/{candidate_field}",
        ))

    skipped_composites = _integer(
        runtime.get("skipped_unsupported_composite_count")
    )
    if skipped_composites is not None and skipped_composites > 0:
        events.append(_event(
            stage="resource-load",
            owner="SceneCompositor",
            reason_code="authored-composite-skipped-unsupported",
            profile_or_shape="layer-composite",
            failure_radius="scene",
            severity="blocking",
            evidence_basis="runtime.skipped_unsupported_composite_count",
        ))
    return events


def _output_events(sample: Mapping[str, Any]) -> list[dict[str, Any]]:
    evidence = _mapping(sample.get("evidence"))
    events: list[dict[str, Any]] = []
    if evidence.get("ready_non_black") is not True or (
        evidence.get("after_non_black") is not True
    ):
        events.append(_event(
            stage="terminal-compositor",
            owner="SceneCompositor",
            reason_code="terminal-output-non-black-missing",
            profile_or_shape="captured-scene-output",
            failure_radius="scene",
            severity="blocking",
            evidence_basis="evidence.ready_non_black/after_non_black",
        ))

    borders = _mapping(evidence.get("flat_border_ratio"))
    ready_border = borders.get("ready")
    after_border = borders.get("after")
    preview = _mapping(evidence.get("preview_visual"))
    metrics = _mapping(preview.get("metrics"))
    spatial_similarity = metrics.get("spatial_color_similarity")
    if (
        isinstance(ready_border, (int, float))
        and not isinstance(ready_border, bool)
        and isinstance(after_border, (int, float))
        and not isinstance(after_border, bool)
        and ready_border >= 0.999
        and after_border >= 0.999
        and preview.get("status") == "available"
        and isinstance(spatial_similarity, (int, float))
        and not isinstance(spatial_similarity, bool)
        and spatial_similarity < 0.9
    ):
        events.append(_event(
            stage="terminal-compositor",
            owner="SceneCompositor",
            reason_code="terminal-output-flat-preview-divergence",
            profile_or_shape="captured-scene-output",
            failure_radius="scene",
            severity="blocking",
            evidence_basis=(
                "evidence.flat_border_ratio/preview_visual.metrics."
                "spatial_color_similarity"
            ),
        ))
    return events


def _scene_script_events(sample: Mapping[str, Any]) -> list[dict[str, Any]]:
    """Read typed VM failures from the app log referenced by the report.

    The benchmark currently embeds successful typed publications but retains
    failed callback records in its bounded app log.  Keep authored identity out
    of the cluster key: target kind/field and typed failure code are the shared
    runtime contract that can benefit multiple samples.
    """
    evidence = _mapping(sample.get("evidence"))
    raw_path = evidence.get("app_log")
    if not isinstance(raw_path, str) or not raw_path:
        return []
    try:
        log_text = Path(raw_path).read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []

    events: list[dict[str, Any]] = []
    for match in SCENE_SCRIPT_TARGET_FAILURE_RE.finditer(log_text):
        events.append(_event(
            stage="script-execution",
            owner="SceneScriptVM",
            reason_code=_scene_script_reason_code(match),
            profile_or_shape=(
                "target:" + match.group("kind") + ":" + match.group("field")
            ),
            failure_radius="script",
            severity="degraded",
            layer_id=int(match.group("layer")),
            fallback_preserved=None,
            evidence_basis="evidence.app_log typed SceneScript failure",
        ))
    for match in SCENE_SCRIPT_EFFECT_FAILURE_RE.finditer(log_text):
        events.append(_event(
            stage="script-execution",
            owner="SceneScriptVM",
            reason_code=_scene_script_reason_code(match),
            profile_or_shape="target:effectConstant",
            failure_radius="script",
            severity="degraded",
            layer_id=int(match.group("layer")),
            effect_index=int(match.group("effect")),
            fallback_preserved=None,
            evidence_basis="evidence.app_log typed SceneScript failure",
        ))
    return events


def _scene_script_reason_code(match: re.Match[str]) -> str:
    code = match.group("code")
    failure = match.group("failure")
    if code == "exception":
        exception_match = re.match(
            r'exception\("(?P<class>[A-Za-z][A-Za-z0-9]*):', failure
        )
        if exception_match is not None:
            exception_class = re.sub(
                r"(?<!^)(?=[A-Z])", "-", exception_match.group("class")
            ).lower()
            return "scene-script-exception-" + exception_class
    return "scene-script-" + code


def _admission_events(
    runtime: Mapping[str, Any],
    compositor_ids: set[int],
    next_frame_ids: set[int],
) -> list[dict[str, Any]]:
    admission = _mapping(runtime.get("effect_stage_admission"))
    events: list[dict[str, Any]] = []
    for record in _records(admission.get("records")):
        if record.get("activity") != "active":
            continue
        route = _token(record.get("admission"), "not-admitted")
        coverage = _token(record.get("coverage"), "unknown-coverage")
        if route not in {
            "not-admitted", "admitted-fallback", "admitted-passthrough"
        } and not coverage.startswith("rejected-"):
            continue
        layer_id = _integer(record.get("layer_id"))
        effect_index = _integer(record.get("effect_index"))
        descriptor_id = record.get("descriptor_id")
        if not isinstance(descriptor_id, str):
            descriptor_id = None
        terminal_preserved = _preserved(
            layer_id, compositor_ids, next_frame_ids
        )
        reason_fallback = coverage if coverage.startswith("rejected-") else route
        reason = _token(record.get("reason"), reason_fallback)
        profile = _token(
            record.get("profile"),
            "backend:" + _token(
                record.get("backend"),
                _definition_family(record.get("definition_path")),
            ),
        )
        events.append(_event(
            stage="effect-admission",
            owner="EffectStageAdmission",
            reason_code=reason,
            profile_or_shape=profile,
            failure_radius="effect",
            # Admission proves a capability gap, never the downstream visual
            # failure radius.  Route operations, graph observations and output
            # evidence below decide whether the layer or scene was lost.
            severity="degraded",
            layer_id=layer_id,
            effect_index=effect_index,
            descriptor_id=descriptor_id,
            fallback_preserved=True if terminal_preserved else None,
            evidence_basis="runtime.effect_stage_admission.records",
        ))
    return events


def _execution_events(
    runtime: Mapping[str, Any],
    compositor_ids: set[int],
    next_frame_ids: set[int],
) -> list[dict[str, Any]]:
    execution = _mapping(runtime.get("effect_execution"))
    events: list[dict[str, Any]] = []
    for invocation in _records(execution.get("cpu_invocations")):
        if invocation.get("outcome") != "failed":
            continue
        layer_id = _integer(invocation.get("layer_id"))
        effect_index = _integer(invocation.get("effect_index"))
        descriptor_id = invocation.get("descriptor_id")
        if not isinstance(descriptor_id, str):
            descriptor_id = None
        terminal_preserved = _preserved(
            layer_id, compositor_ids, next_frame_ids
        )
        events.append(_event(
            stage="effect-execution",
            owner="ResolvedMaterialExecution",
            reason_code=_token(invocation.get("reason"), "effect-execution-failed"),
            profile_or_shape=_token(
                invocation.get("backend"),
                "family:" + _token(invocation.get("family"), "unknown"),
            ),
            failure_radius="effect",
            severity="degraded" if terminal_preserved else "blocking",
            layer_id=layer_id,
            effect_index=effect_index,
            descriptor_id=descriptor_id,
            fallback_preserved=terminal_preserved,
            evidence_basis="runtime.effect_execution.cpu_invocations",
        ))
    for operation in _records(execution.get("route_operations")):
        outcome = _token(operation.get("outcome"), "unknown")
        operation_name = _token(
            operation.get("operation"),
            _token(operation.get("operation_token"), "unknown"),
        )
        is_degraded_passthrough = (
            outcome == "encoded"
            and operation_name == "degraded-layer-source-passthrough"
        )
        if outcome != "failed" and not is_degraded_passthrough:
            continue
        layer_id = _integer(operation.get("layer_id"))
        terminal_preserved = _preserved(
            layer_id, compositor_ids, next_frame_ids
        )
        if is_degraded_passthrough:
            # This operation is emitted only after the shared main-pass
            # compositor accepted and encoded the validated base source.
            terminal_preserved = True
        events.append(_event(
            stage="effect-execution",
            owner="ResolvedMaterialExecution",
            reason_code=(
                "degraded-layer-source-passthrough"
                if is_degraded_passthrough else _token(
                    operation.get("reason"),
                    _token(
                        operation.get("reason_token"),
                        "route-operation-failed",
                    ),
                )
            ),
            profile_or_shape="operation:" + operation_name,
            failure_radius="layer",
            severity=(
                "degraded" if terminal_preserved else "blocking"
            ),
            layer_id=layer_id,
            fallback_preserved=terminal_preserved,
            evidence_basis="runtime.effect_execution.route_operations",
        ))
    for frame in _records(execution.get("frames")):
        if frame.get("status") != "failed":
            continue
        events.append(_event(
            stage="gpu-completion",
            owner="SceneFrameCommandBuffer",
            reason_code="command-buffer-failed",
            profile_or_shape="scene-frame",
            failure_radius="scene",
            severity="blocking",
            evidence_basis="runtime.effect_execution.frames",
        ))
    return events


def _resolved_graph_events(
    runtime: Mapping[str, Any],
    compositor_ids: set[int],
    next_frame_ids: set[int],
) -> list[dict[str, Any]]:
    resolved = _mapping(runtime.get("resolved_material_graph_execution"))
    executor = _mapping(resolved.get("executor"))
    routes = _mapping(resolved.get("layer_routes"))
    graph = _mapping(resolved.get("graph_observations"))
    events: list[dict[str, Any]] = []

    failure_count = _integer(executor.get("failure_count"))
    if failure_count is not None and failure_count > 0:
        events.append(_event(
            stage="graph-execution",
            owner="GraphExecutor",
            reason_code="graph-executor-reported-failure",
            profile_or_shape="resolved-material-graph",
            failure_radius="scene",
            severity="blocking",
            evidence_basis=(
                "runtime.resolved_material_graph_execution.executor.failure_count"
            ),
        ))

    for fallback in _records(executor.get("local_fallbacks")):
        layer_id = _integer(fallback.get("layer_id"))
        terminal_preserved = _preserved(
            layer_id, compositor_ids, next_frame_ids
        )
        events.append(_event(
            stage="graph-execution",
            owner="GraphExecutor",
            reason_code=_token(fallback.get("reason"), "layer-local-fallback"),
            profile_or_shape="resolved-material-graph",
            failure_radius="layer",
            severity="degraded" if terminal_preserved else "blocking",
            layer_id=layer_id,
            fallback_preserved=terminal_preserved,
            evidence_basis=(
                "runtime.resolved_material_graph_execution.executor.local_fallbacks"
            ),
        ))

    for fallback in _records(graph.get("visual_failure_passthroughs")):
        layer_id = _integer(fallback.get("layer_id"))
        effect_index = _integer(fallback.get("effect_index"))
        descriptor_id = fallback.get("descriptor_id")
        if not isinstance(descriptor_id, str):
            descriptor_id = None
        terminal_preserved = _preserved(
            layer_id, compositor_ids, next_frame_ids
        )
        events.append(_event(
            stage="graph-execution",
            owner="GraphExecutor",
            reason_code=_token(
                fallback.get("reason"), "visual-failure-passthrough"
            ),
            profile_or_shape="visual-failure-passthrough",
            failure_radius="effect",
            severity="degraded" if terminal_preserved else "blocking",
            layer_id=layer_id,
            effect_index=effect_index,
            descriptor_id=descriptor_id,
            fallback_preserved=terminal_preserved,
            evidence_basis=(
                "runtime.resolved_material_graph_execution.graph_observations"
                ".visual_failure_passthroughs"
            ),
        ))

    route_failures = (
        ("missing_layer_ids", "graph-execution", "GraphExecutor",
         "graph-execution-missing", "resolved-material-graph"),
        ("missing_gpu_completed_layer_ids", "gpu-completion", "GraphExecutor",
         "gpu-completion-missing", "resolved-material-graph"),
        ("missing_compositor_consumed_layer_ids", "terminal-compositor",
         "SceneCompositor", "terminal-compositor-missing", "graph-output"),
        ("missing_next_frame_layer_ids", "next-frame", "SceneCompositor",
         "next-frame-missing", "graph-output"),
    )
    for field, stage, owner, reason, shape in route_failures:
        for layer_id in sorted(_integer_set(routes.get(field))):
            events.append(_event(
                stage=stage,
                owner=owner,
                reason_code=reason,
                profile_or_shape=shape,
                failure_radius="layer",
                severity="blocking",
                layer_id=layer_id,
                evidence_basis=(
                    "runtime.resolved_material_graph_execution.layer_routes."
                    + field
                ),
            ))
    return events


def _named_target_events(runtime: Mapping[str, Any]) -> list[dict[str, Any]]:
    specs = (
        ("named_target_capture_failed_layer_ids", "named-target-capture",
         "GraphTargets", "named-target-capture-failed", "named-target"),
        ("named_target_binding_failed_layer_ids", "named-target-binding",
         "LayerDependencies", "named-target-binding-failed", "named-binding"),
        ("visible_graph_output_publication_failed_layer_ids", "publication",
         "GraphTargets", "visible-graph-output-publication-failed",
         "visible-graph-output"),
        ("named_graph_output_publication_failed_layer_ids", "publication",
         "GraphTargets", "named-graph-output-publication-failed",
         "named-graph-output"),
    )
    events: list[dict[str, Any]] = []
    for field, stage, owner, reason, shape in specs:
        for layer_id in sorted(_integer_set(runtime.get(field))):
            events.append(_event(
                stage=stage,
                owner=owner,
                reason_code=reason,
                profile_or_shape=shape,
                failure_radius="layer",
                severity="degraded",
                layer_id=layer_id,
                evidence_basis="runtime." + field,
            ))
    return events


def _public_event(event: Mapping[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in event.items() if not key.startswith("_")}


def _evidence_summary(sample: Mapping[str, Any]) -> dict[str, Any]:
    runtime = _mapping(sample.get("runtime"))
    resolved = _mapping(runtime.get("resolved_material_graph_execution"))
    routes = _mapping(resolved.get("layer_routes"))
    graph = _mapping(resolved.get("graph_observations"))
    accepted = _integer_set(routes.get("accepted_layer_ids"))
    if not accepted:
        capability = _mapping(resolved.get("capability"))
        accepted = _integer_set(capability.get("accepted_layer_ids"))
    compositor, next_frame = _terminal_sets(runtime)
    evidence = _mapping(sample.get("evidence"))
    borders = _mapping(evidence.get("flat_border_ratio"))
    preview = _mapping(evidence.get("preview_visual"))
    preview_metrics = _mapping(preview.get("metrics"))
    return {
        "surfaceCount": _integer(runtime.get("surfaces")),
        "readyNonBlackObserved": evidence.get("ready_non_black") is True,
        "afterNonBlackObserved": evidence.get("after_non_black") is True,
        "readyFlatBorderRatio": borders.get("ready"),
        "afterFlatBorderRatio": borders.get("after"),
        "previewSpatialColorSimilarityAdvisory": preview_metrics.get(
            "spatial_color_similarity"
        ),
        "graphEvidenceObserved": (
            resolved.get("has_evidence") is True
            or graph.get("has_evidence") is True
        ),
        "acceptedGraphLayerCount": len(accepted),
        "terminalCompositorLayerCount": len(compositor),
        "nextFrameLayerCount": len(next_frame),
    }


def _sample_observation(
    sample: Mapping[str, Any], report_index: int
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    sample_id = sample.get("id")
    if not isinstance(sample_id, str) or not sample_id:
        raise DiagnosticReportError(
            f"report {report_index} contains a sample without a string id"
        )
    runtime = _mapping(sample.get("runtime"))
    compositor_ids, next_frame_ids = _terminal_sets(runtime)
    events = _process_events(sample)
    events.extend(_resource_events(runtime))
    events.extend(_admission_events(runtime, compositor_ids, next_frame_ids))
    events.extend(_scene_script_events(sample))
    events.extend(_execution_events(
        runtime, compositor_ids, next_frame_ids
    ))
    events.extend(_resolved_graph_events(
        runtime, compositor_ids, next_frame_ids
    ))
    events.extend(_named_target_events(runtime))
    events.extend(_output_events(sample))
    events = _deduplicate(events)

    if any(event["severity"] == "blocking" for event in events):
        status = "blocked"
    elif events:
        status = "degraded"
    else:
        summary = _evidence_summary(sample)
        if summary["graphEvidenceObserved"]:
            status = "terminal-chain-complete"
        else:
            status = "runtime-evidence-incomplete"

    failures = sample.get("failures")
    failure_count = len(failures) if isinstance(failures, list) else 0
    first = _public_event(events[0]) if events else None
    secondary = [_public_event(event) for event in events[1:]]
    observation = {
        "reportIndex": report_index,
        "sampleId": sample_id,
        "basicDisplayStatus": status,
        "firstBreakpoint": first,
        "secondaryEvents": secondary,
        "benchmarkResultIgnored": {
            "passed": sample.get("passed") if isinstance(
                sample.get("passed"), bool
            ) else None,
            "failureCount": failure_count,
            "reason": "matrix-and-benchmark-expectations-are-not-runtime-breakpoints",
        },
        "evidenceSummary": _evidence_summary(sample),
    }
    return observation, events


def _clusters(
    observations: list[tuple[int, str, list[dict[str, Any]]]],
) -> list[dict[str, Any]]:
    grouped: dict[
        tuple[str, str, str, str, str],
        list[tuple[int, str, dict[str, Any]]],
    ] = defaultdict(list)
    for report_index, sample_id, events in observations:
        for event in events:
            key = (
                event["stage"], event["owner"], event["reasonCode"],
                event["capabilityProfileOrAuthoredShape"],
                event["failureRadius"],
            )
            grouped[key].append((report_index, sample_id, event))

    output: list[dict[str, Any]] = []
    for key, members in grouped.items():
        stage, owner, reason, profile, radius = key
        severities = [member[2]["severity"] for member in members]
        severity = max(severities, key=SEVERITY_ORDER.__getitem__)
        sample_ids = sorted({member[1] for member in members})
        observations_set = {(member[0], member[1]) for member in members}
        units = {
            (member[0], member[1], member[2]["_unitKey"])
            for member in members
        }
        fallback_values = [
            member[2]["fallbackPreservedTerminalCompositor"]
            for member in members
            if member[2]["fallbackPreservedTerminalCompositor"] is not None
        ]
        preserved_count = sum(value is True for value in fallback_values)
        unpreserved_count = sum(value is False for value in fallback_values)
        output.append({
            "key": {
                "stage": stage,
                "owner": owner,
                "reasonCode": reason,
                "capabilityProfileOrAuthoredShape": profile,
                "failureRadius": radius,
            },
            "affectedSampleCount": len(sample_ids),
            "affectedObservationCount": len(observations_set),
            "affectedUnitCount": len(units),
            "severity": severity,
            "representativeSampleIds": sample_ids[:3],
            "fallbackTerminalCompositor": {
                "applicableCount": len(fallback_values),
                "preservedCount": preserved_count,
                "unpreservedCount": unpreserved_count,
                "allPreserved": (
                    preserved_count == len(fallback_values)
                    if fallback_values else None
                ),
            },
        })
    return sorted(output, key=lambda cluster: (
        STAGE_ORDER.get(cluster["key"]["stage"], 999),
        -SEVERITY_ORDER[cluster["severity"]],
        -cluster["affectedSampleCount"],
        -cluster["affectedUnitCount"],
        cluster["key"]["owner"],
        cluster["key"]["reasonCode"],
        cluster["key"]["capabilityProfileOrAuthoredShape"],
        cluster["key"]["failureRadius"],
    ))


def normalize_reports(
    reports: Sequence[Mapping[str, Any]],
) -> dict[str, Any]:
    """Return deterministic diagnostics for already-loaded benchmark reports."""
    samples: list[dict[str, Any]] = []
    cluster_inputs: list[tuple[int, str, list[dict[str, Any]]]] = []
    report_summaries: list[dict[str, Any]] = []
    for report_index, report in enumerate(reports):
        if not isinstance(report, Mapping):
            raise DiagnosticReportError(f"input {report_index} is not a JSON object")
        raw_samples = report.get("samples")
        if not isinstance(raw_samples, list):
            raise DiagnosticReportError(
                f"input {report_index} has no benchmark samples array"
            )
        matrix = report.get("matrix")
        report_summaries.append({
            "reportIndex": report_index,
            "matrixName": (
                Path(matrix).name if isinstance(matrix, str) else None
            ),
            "sampleCount": len(raw_samples),
        })
        for raw_sample in raw_samples:
            if not isinstance(raw_sample, Mapping):
                raise DiagnosticReportError(
                    f"report {report_index} contains a non-object sample"
                )
            observation, events = _sample_observation(raw_sample, report_index)
            samples.append(observation)
            cluster_inputs.append((
                report_index, observation["sampleId"], events
            ))

    samples.sort(key=lambda item: (item["sampleId"], item["reportIndex"]))
    return {
        "schemaVersion": SCHEMA_VERSION,
        "claimBoundary": CLAIM_BOUNDARY,
        "reportCount": len(reports),
        "sampleCount": len(samples),
        "uniqueSampleCount": len({item["sampleId"] for item in samples}),
        "reports": report_summaries,
        "samples": samples,
        "clusters": _clusters(cluster_inputs),
    }


def _load_report(path: Path) -> Mapping[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except OSError as error:
        raise DiagnosticReportError(f"cannot read {path}: {error}") from error
    except json.JSONDecodeError as error:
        raise DiagnosticReportError(f"invalid JSON in {path}: {error}") from error
    if not isinstance(payload, Mapping):
        raise DiagnosticReportError(f"{path} does not contain a JSON object")
    return payload


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Normalize existing Scene benchmark runtime evidence into stable "
            "first-breakpoint clusters. This does not verify visual correctness."
        )
    )
    parser.add_argument(
        "reports", type=Path, nargs="+", help="benchmark report.json files"
    )
    parser.add_argument(
        "-o", "--output", type=Path,
        help="write JSON here instead of stdout",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    arguments = _parser().parse_args(argv)
    try:
        normalized = normalize_reports([
            _load_report(path) for path in arguments.reports
        ])
    except DiagnosticReportError as error:
        print(f"scene_diagnostic_report: {error}", file=sys.stderr)
        return 2
    text = json.dumps(
        normalized, ensure_ascii=False, indent=2, sort_keys=True
    ) + "\n"
    if arguments.output is None:
        sys.stdout.write(text)
        return 0
    try:
        arguments.output.write_text(text, encoding="utf-8")
    except OSError as error:
        print(
            f"scene_diagnostic_report: cannot write {arguments.output}: {error}",
            file=sys.stderr,
        )
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
