"""Observe and validate utility capture and named-target consumers."""

from __future__ import annotations

import re
from scene_wallpaper_effect_expectations import effect_local_passthrough_expectation
from typing import Any


UTILITY_LAYER_COUNT_RE = re.compile(r"^utilityLayerCount: (?P<count>\d+)$", re.MULTILINE)

UTILITY_CAPTURE_COUNT_RE = re.compile(
    r"^utilityCapturePlannedCount: (?P<count>\d+)$", re.MULTILINE
)

UTILITY_DEPENDENCY_COUNT_RE = re.compile(
    r"^utilityDependencyEdgeCount: (?P<count>\d+)$", re.MULTILINE
)

UTILITY_NAMED_TARGET_PLANNED_RE = re.compile(
    r"^utilityNamedTargetPlannedCount: (?P<count>\d+)$", re.MULTILINE
)

UTILITY_NAMED_CONSUMER_COUNT_RE = re.compile(
    r"^utilityNamedConsumerCount: (?P<count>\d+)$", re.MULTILINE
)

UTILITY_NAMED_BINDING_PLANNED_RE = re.compile(
    r"^utilityNamedBindingPlannedCount: (?P<count>\d+)$", re.MULTILINE
)

UTILITY_NAMED_BINDING_CONDITIONAL_RE = re.compile(
    r"^utilityNamedBindingConditionalCount: (?P<count>\d+)$", re.MULTILINE
)

UTILITY_NAMED_BINDING_CONDITIONAL_IDS_RE = re.compile(
    r"^utilityNamedBindingConditionalLayerIDs: (?P<ids>[0-9,]*)$", re.MULTILINE
)

UTILITY_NAMED_BINDING_CONSUMER_IDS_RE = re.compile(
    r"^utilityNamedBindingConsumerLayerIDs: (?P<ids>[0-9,]*)$", re.MULTILINE
)

UTILITY_NAMED_TARGET_GAP_RE = re.compile(
    r"^utilityNamedTargetGapCount: (?P<count>\d+)$", re.MULTILINE
)

UTILITY_LAYER_RE = re.compile(
    r"^utility layer (?P<id>\d+): (?P<disposition>\w+) kind=(?P<kind>\w+)"
    r"(?: trigger=\d+)?(?P<named_target>; named target planned)?",
    re.MULTILINE,
)

UTILITY_CAPTURE_EXECUTION_RE = re.compile(
    r"phase=utility-capture layer=(?P<id>\d+) status=(?P<status>succeeded|failed)"
)

NAMED_TARGET_CAPTURE_EXECUTION_RE = re.compile(
    r"phase=named-target-capture layer=(?P<id>\d+) status=(?P<status>succeeded|failed)"
)

NAMED_TARGET_BINDING_EXECUTION_RE = re.compile(
    r"phase=named-target-binding layer=(?P<id>\d+) status=(?P<status>succeeded|failed)"
)

def utility_runtime_metrics(preview_text: str) -> dict[str, Any]:
    count_match = UTILITY_LAYER_COUNT_RE.search(preview_text)
    capture_match = UTILITY_CAPTURE_COUNT_RE.search(preview_text)
    dependency_match = UTILITY_DEPENDENCY_COUNT_RE.search(preview_text)
    named_consumer_match = UTILITY_NAMED_CONSUMER_COUNT_RE.search(preview_text)
    named_target_match = UTILITY_NAMED_TARGET_PLANNED_RE.search(preview_text)
    named_binding_match = UTILITY_NAMED_BINDING_PLANNED_RE.search(preview_text)
    named_binding_conditional_match = UTILITY_NAMED_BINDING_CONDITIONAL_RE.search(
        preview_text
    )
    named_binding_conditional_ids_match = (
        UTILITY_NAMED_BINDING_CONDITIONAL_IDS_RE.search(preview_text)
    )
    named_binding_consumer_ids_match = (
        UTILITY_NAMED_BINDING_CONSUMER_IDS_RE.search(preview_text)
    )
    named_gap_match = UTILITY_NAMED_TARGET_GAP_RE.search(preview_text)
    layers = [
        {
            "id": int(match.group("id")),
            "disposition": match.group("disposition"),
            "kind": match.group("kind"),
            "named_target_planned": match.group("named_target") is not None,
        }
        for match in UTILITY_LAYER_RE.finditer(preview_text)
    ]
    return {
        "has_evidence": all(
            match is not None
            for match in (
                count_match,
                capture_match,
                dependency_match,
                named_consumer_match,
                named_target_match,
                named_binding_match,
                named_gap_match,
            )
        ),
        "candidates": int(count_match.group("count")) if count_match else 0,
        "capture_planned": int(capture_match.group("count")) if capture_match else 0,
        "dependency_edges": int(dependency_match.group("count")) if dependency_match else 0,
        "named_consumers": int(named_consumer_match.group("count")) if named_consumer_match else 0,
        "named_target_planned": int(named_target_match.group("count")) if named_target_match else 0,
        "named_binding_planned": int(named_binding_match.group("count")) if named_binding_match else 0,
        "named_binding_conditional": int(
            named_binding_conditional_match.group("count")
        ) if named_binding_conditional_match else 0,
        "named_binding_conditional_layer_ids": [
            int(layer_id)
            for layer_id in (
                named_binding_conditional_ids_match.group("ids").split(",")
                if named_binding_conditional_ids_match
                else []
            )
            if layer_id
        ],
        "named_binding_consumer_layer_ids": [
            int(layer_id)
            for layer_id in (
                named_binding_consumer_ids_match.group("ids").split(",")
                if named_binding_consumer_ids_match
                else []
            )
            if layer_id
        ],
        "named_target_planned_layer_ids": sorted(
            layer["id"] for layer in layers if layer["named_target_planned"]
        ),
        "named_target_gaps": int(named_gap_match.group("count")) if named_gap_match else 0,
        "layers": layers,
    }

def utility_runtime_failures(
    sample: dict[str, Any],
    metrics: dict[str, Any],
    *,
    capture_execution: dict[str, Any] | None = None,
    graph_execution: dict[str, Any] | None = None,
    execution_observations_enabled: bool = True,
) -> list[str]:
    expected_metrics = {
        "expected_utility_candidates": "candidates",
        "expected_utility_capture_planned": "capture_planned",
        "expected_utility_dependency_edges": "dependency_edges",
        "expected_utility_named_consumers": "named_consumers",
        "expected_utility_named_target_planned": "named_target_planned",
        "expected_utility_named_binding_planned": "named_binding_planned",
        "expected_utility_named_target_gaps": "named_target_gaps",
    }
    requires_evidence = any(key in sample for key in expected_metrics) or bool(
        sample.get("required_utility_dispositions")
    )
    if requires_evidence and not metrics["has_evidence"]:
        return ["utility layer runtime evidence missing"]

    failures: list[str] = []
    for expectation, metric in expected_metrics.items():
        if expectation in sample and metrics[metric] != int(sample[expectation]):
            failures.append(f"utility {metric} mismatch")
    actual_dispositions = {
        str(layer["id"]): layer["disposition"] for layer in metrics["layers"]
    }
    for layer_id, disposition in sample.get("required_utility_dispositions", {}).items():
        if actual_dispositions.get(str(layer_id)) != disposition:
            failures.append(
                f"utility layer {layer_id} disposition should be {disposition}"
            )
    if capture_execution is not None:
        succeeded = set(capture_execution["succeeded_layer_ids"])
        if capture_execution["failed_layer_ids"]:
            failures.append("utility capture execution reported failures")
        if not execution_observations_enabled:
            return failures
        planned = {
            layer["id"]: layer for layer in metrics["layers"]
            if layer["disposition"] == "capture"
        }
        visibility = (graph_execution or {}).get("dynamic_visibility", {})
        routes = (graph_execution or {}).get("layer_routes", {})
        observations = (graph_execution or {}).get("graph_observations", {})
        dormant: set[int] = set()
        if (routes.get("has_evidence") and visibility.get("has_evidence")
                and visibility.get("schema_version") == "dynamic-layer-visibility-v1"
                and "ever_visible_layer_ids" in visibility
                and "execution_observed_layer_ids" in observations
                and not observations.get("validation_failures")
                and not visibility.get("duplicate_layer_ids")
                and not visibility.get("malformed_observation_count")):
            # A latest-hidden layer may have needed capture earlier. Only a
            # proven dormant graph member that never became visible is idle;
            # hidden named providers still owe their consumer a publication.
            dormant = set(visibility["dormant_accepted_layer_ids"]).difference(
                visibility["ever_visible_layer_ids"],
                observations["execution_observed_layer_ids"])
            dormant.intersection_update(
                layer_id for layer_id, layer in planned.items()
                if not layer["named_target_planned"]
            )
        if len(planned) == metrics["capture_planned"]:
            missing_capture = bool(set(planned).difference(dormant, succeeded))
        else:
            # Older/incomplete membership cannot justify an identity exemption.
            missing_capture = len(succeeded) < metrics["capture_planned"]
        if missing_capture:
            failures.append("utility capture execution below planned count")
        for layer_id in sample.get("required_utility_capture_succeeded_layer_ids", []):
            if layer_id not in succeeded:
                failures.append(f"utility layer {layer_id} capture should succeed")
    return failures

def utility_capture_execution_metrics(log_text: str) -> dict[str, Any]:
    return capture_execution_metrics(log_text, UTILITY_CAPTURE_EXECUTION_RE)

def named_target_capture_execution_metrics(log_text: str) -> dict[str, Any]:
    return capture_execution_metrics(log_text, NAMED_TARGET_CAPTURE_EXECUTION_RE)

def named_target_binding_execution_metrics(log_text: str) -> dict[str, Any]:
    return capture_execution_metrics(log_text, NAMED_TARGET_BINDING_EXECUTION_RE)

def capture_execution_metrics(
    log_text: str,
    pattern: re.Pattern[str],
) -> dict[str, Any]:
    succeeded: set[int] = set()
    failed: set[int] = set()
    for match in pattern.finditer(log_text):
        layer_id = int(match.group("id"))
        if match.group("status") == "succeeded":
            succeeded.add(layer_id)
        else:
            failed.add(layer_id)
    return {
        "succeeded_layer_ids": sorted(succeeded),
        "failed_layer_ids": sorted(failed),
    }

def named_target_binding_failures(
    sample: dict[str, Any],
    planned_count: int,
    metrics: dict[str, Any],
    conditional_count: int = 0,
    utility_metrics: dict[str, Any] | None = None,
    *,
    execution_observations_enabled: bool = True,
) -> list[str]:
    succeeded = set(metrics["succeeded_layer_ids"])
    failed_only = set(metrics["failed_layer_ids"]).difference(succeeded)
    failures: list[str] = []
    if not execution_observations_enabled:
        if failed_only:
            failures.append("named target binding execution reported failures")
        return failures
    expects_passthrough, passthrough_valid, expected_passthroughs = (
        effect_local_passthrough_expectation(sample)
    )
    expected_provider_unavailable = {
        layer_id
        for layer_id, _, _, reason in expected_passthroughs
        if reason == "external-primary-provider-source-unavailable"
    } if expects_passthrough and passthrough_valid else set()
    if expected_provider_unavailable and (
        failed_only != expected_provider_unavailable
        or len(expected_provider_unavailable) > planned_count
    ):
        failures.append("named target binding unavailable set mismatch")
    # Bindings planned through optimistic launch visibility (either endpoint's
    # visibility is owned by a script, so the authored value is only a seed)
    # may legitimately stay idle until the owning script shows the layer. When
    # the planned consumer membership is known, excuse exactly those members
    # and require every remaining planned consumer to have succeeded. Without
    # membership (older logs) fall back to the aggregate count bound with the
    # conditional count excused.
    conditional_layer_ids = set(
        (utility_metrics or {}).get("named_binding_conditional_layer_ids", [])
    )
    planned_consumers = set(
        (utility_metrics or {}).get("named_binding_consumer_layer_ids", [])
    )
    if planned_consumers:
        required_members = (
            planned_consumers
            - conditional_layer_ids
            - expected_provider_unavailable
        )
        missing_members = required_members.difference(succeeded)
        if missing_members:
            failures.append(
                "named target binding execution below planned count"
            )
            for layer_id in sorted(missing_members):
                failures.append(
                    f"named target consumer {layer_id} binding should succeed"
                )
    else:
        required_success_count = max(
            0,
            planned_count - len(expected_provider_unavailable) - conditional_count,
        )
        if len(succeeded) < required_success_count:
            failures.append("named target binding execution below planned count")
    for layer_id in sample.get("required_named_target_binding_succeeded_layer_ids", []):
        if layer_id not in succeeded:
            failures.append(f"named target consumer {layer_id} binding should succeed")
    return failures
