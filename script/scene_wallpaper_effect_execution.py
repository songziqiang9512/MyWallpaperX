"""Parse CPU effect execution, routes and frame completion evidence."""

from __future__ import annotations

import hashlib
import json
import re
from scene_matrix_contract import (
    EFFECT_EXECUTION_EXACT_KINDS, EFFECT_EXECUTION_EXPECTATIONS,
    RESOLVED_MATERIAL_GRAPH_BACKEND, effect_execution_static_demand,
)
from scene_wallpaper_effect_expectations import (
    EFFECT_LOCAL_PASSTHROUGH_CPU_PREFIX, effect_local_passthrough_cpu_keys,
    effect_local_passthrough_expectation, effect_recovery_cpu_evidence,
    effect_recovery_expectation,
)
from typing import Any
from urllib.parse import unquote


EFFECT_CPU_INVOCATION_RE = re.compile(
    r"schema=(?P<schema>\d+) axis=effect-cpu-invocation "
    r"frame=(?P<frame>\d+) origin=(?P<origin>\S+) "
    r"subject=(?P<subject>effect) layer=(?P<layer>\d+) "
    r"effect=(?P<effect>-|\d+) descriptor=(?P<descriptor>\S+) "
    r"family=(?P<family>\S+) backend=(?P<backend>\S+) "
    r"outcome=(?P<outcome>encoded-output|failed) "
    r"reason=(?P<reason>\S+)"
)

EFFECT_ROUTE_OPERATION_RE = re.compile(
    r"schema=(?P<schema>\d+) axis=effect-route-operation "
    r"frame=(?P<frame>\d+) origin=(?P<origin>\S+) "
    r"layer=(?P<layer>\d+) operation=(?P<operation>\S+) "
    r"outcome=(?P<outcome>encoded|failed) reason=(?P<reason>\S+)"
)

SCENE_FRAME_COMMAND_BUFFER_RE = re.compile(
    r"schema=(?P<schema>\d+) axis=scene-frame-command-buffer "
    r"frame=(?P<frame>\d+) attemptedEffects=(?P<attempted>\d+) "
    r"returnedOutputs=(?P<returned>\d+) "
    r"failedInvocations=(?P<failed>\d+) "
    r"routeOperations=(?P<routes>\d+) "
    r"cohortSHA256=(?P<cohort>[0-9a-fA-F]{64}) "
    r"status=(?P<status>completed|failed)"
)

def _effect_execution_static_catalog(
    disposition: dict[str, Any] | None,
) -> tuple[bool, list[dict[str, Any]], list[dict[str, Any]]]:
    is_valid = effect_execution_static_demand(disposition).static_is_valid
    records = list(disposition.get("records", [])) if is_valid else []
    eligible_exact = [
        {
            "layer_id": record["layer_id"],
            "effect_index": record["effect_index"],
            "descriptor_id": record["descriptor_id"],
            "definition_path": record["definition_path"],
            "family": record["family"],
            "disposition_kind": record["kind"],
        }
        for record in records
        if record.get("kind") in EFFECT_EXECUTION_EXACT_KINDS
    ]
    eligible_exact.sort(key=lambda item: (
        item["layer_id"], item["effect_index"], item["descriptor_id"]
    ))
    return is_valid, records, eligible_exact

def _empty_effect_execution_metrics() -> dict[str, Any]:
    return {
        "has_evidence": False,
        "schema_version": None,
        "axis_evidence": {
            "cpu_invocation": False,
            "route_operation": False,
            "frame_command_buffer": False,
        },
        "cpu_invocation_count": 0,
        "route_operation_count": 0,
        "frame_observation_count": 0,
        "cpu_invocations": [],
        "succeeded_exact_effects": [],
        "failed_exact_effects": [],
        "route_operations": [],
        "encoded_route_operations": [],
        "degraded_route_operations": [],
        "failed_route_operations": [],
        "frames": [],
        "completed_frame_ids": [],
        "failed_frame_ids": [],
        "canonical_sha256": None,
        "validation_failures": [],
    }

def _effect_execution_payload(line: str) -> str | None:
    start = line.find("schema=")
    return line[start:].strip() if start >= 0 else None

def _effect_execution_identity_list(
    invocations: list[dict[str, Any]],
    outcome: str,
) -> list[dict[str, Any]]:
    grouped: dict[tuple[Any, ...], dict[str, Any]] = {}
    for invocation in invocations:
        if (
            invocation["outcome"] != outcome
            or invocation.get("join_valid") is not True
        ):
            continue
        key = (
            invocation["layer_id"],
            invocation["effect_index"],
            invocation["descriptor_id"],
            invocation["definition_path"],
            invocation["family"],
        )
        identity = {
            "layer_id": invocation["layer_id"],
            "effect_index": invocation["effect_index"],
            "descriptor_id": invocation["descriptor_id"],
            "definition_path": invocation["definition_path"],
            "family": invocation["family"],
            "origins": set(),
            "backends": set(),
        }
        entry = grouped.setdefault(key, identity)
        entry["origins"].add(invocation["origin"])
        entry["backends"].add(invocation["backend"])
    result = []
    for key in sorted(grouped, key=lambda value: tuple(
        "" if item is None else str(item) for item in value
    )):
        entry = grouped[key]
        entry["origins"] = sorted(entry["origins"])
        entry["backends"] = sorted(entry["backends"])
        result.append(entry)
    return result

def effect_execution_metrics(
    log_text: str,
    disposition: dict[str, Any] | None = None,
) -> dict[str, Any]:
    axis_markers = {
        "cpu_invocation": "axis=effect-cpu-invocation",
        "route_operation": "axis=effect-route-operation",
        "frame_command_buffer": "axis=scene-frame-command-buffer",
    }
    axis_lines = {
        key: [line for line in log_text.splitlines() if marker in line]
        for key, marker in axis_markers.items()
    }
    if not any(axis_lines.values()):
        return _empty_effect_execution_metrics()

    failures: list[str] = []
    raw_invocations: dict[str, dict[str, Any]] = {}
    raw_routes: dict[str, dict[str, Any]] = {}
    raw_frames: dict[tuple[Any, ...], dict[str, Any]] = {}
    invocation_transitions: dict[tuple[Any, ...], str] = {}
    route_transitions: dict[tuple[Any, ...], str] = {}

    for line in axis_lines["cpu_invocation"]:
        payload = _effect_execution_payload(line)
        match = EFFECT_CPU_INVOCATION_RE.fullmatch(payload or "")
        if match is None:
            failures.append("effect execution CPU invocation malformed")
            continue
        if int(match.group("schema")) != 1:
            failures.append("effect execution source schema unsupported")
        effect_token = match.group("effect")
        descriptor_token = match.group("descriptor")
        family_token = match.group("family")
        backend_token = match.group("backend")
        subject = match.group("subject")
        reason_token = match.group("reason")
        if effect_token == "-" or descriptor_token == "-":
            failures.append("effect execution CPU subject identity malformed")
        outcome = match.group("outcome")
        canonical_line = (
            f"effect|origin={match.group('origin')}|subject={subject}"
            f"|layer={match.group('layer')}|effect={effect_token}"
            f"|descriptor={descriptor_token}|family={family_token}"
            f"|backend={backend_token}|outcome={outcome}"
            f"|reason={reason_token}"
        )
        frame_id = int(match.group("frame"))
        transition_key = (
            match.group("origin"),
            subject,
            int(match.group("layer")),
            effect_token,
            descriptor_token,
            family_token,
            backend_token,
            outcome,
        )
        prior_line = invocation_transitions.setdefault(
            transition_key, canonical_line
        )
        if prior_line != canonical_line:
            failures.append("effect execution CPU transition identity duplicated")
        invocation = raw_invocations.setdefault(canonical_line, {
            "frame_id": frame_id,
            "frame_ids": set(),
            "origin": match.group("origin"),
            "subject": subject,
            "layer_id": int(match.group("layer")),
            "effect_index": None if effect_token == "-" else int(effect_token),
            "descriptor_token": descriptor_token,
            "descriptor_id": (
                None if descriptor_token == "-" else unquote(descriptor_token)
            ),
            "definition_path": None,
            "family_token": family_token,
            "family": unquote(family_token),
            "backend_token": backend_token,
            "backend": unquote(backend_token),
            "outcome": outcome,
            "reason_token": reason_token,
            "reason": None if reason_token == "-" else unquote(reason_token),
            "disposition_kind": None,
            "join_valid": False,
            "canonical_line": canonical_line,
        })
        invocation["frame_ids"].add(frame_id)

    for line in axis_lines["route_operation"]:
        payload = _effect_execution_payload(line)
        match = EFFECT_ROUTE_OPERATION_RE.fullmatch(payload or "")
        if match is None:
            failures.append("effect execution route operation malformed")
            continue
        if int(match.group("schema")) != 1:
            failures.append("effect execution source schema unsupported")
        outcome = match.group("outcome")
        operation_token = match.group("operation")
        reason_token = match.group("reason")
        canonical_line = (
            f"route|origin={match.group('origin')}|layer={match.group('layer')}"
            f"|operation={operation_token}|outcome={outcome}"
            f"|reason={reason_token}"
        )
        frame_id = int(match.group("frame"))
        transition_key = (
            match.group("origin"),
            int(match.group("layer")),
            operation_token,
            outcome,
        )
        prior_line = route_transitions.setdefault(transition_key, canonical_line)
        if prior_line != canonical_line:
            failures.append("effect execution route transition identity duplicated")
        raw_routes.setdefault(canonical_line, {
            "frame_id": frame_id,
            "origin": match.group("origin"),
            "layer_id": int(match.group("layer")),
            "operation_token": operation_token,
            "operation": unquote(operation_token),
            "outcome": outcome,
            "reason_token": reason_token,
            "reason": None if reason_token == "-" else unquote(reason_token),
            "canonical_line": canonical_line,
        })

    for line in axis_lines["frame_command_buffer"]:
        payload = _effect_execution_payload(line)
        match = SCENE_FRAME_COMMAND_BUFFER_RE.fullmatch(payload or "")
        if match is None:
            failures.append("effect execution frame summary malformed")
            continue
        if int(match.group("schema")) != 1:
            failures.append("effect execution source schema unsupported")
        frame = {
            "frame_id": int(match.group("frame")),
            "attempted_effects": int(match.group("attempted")),
            "returned_outputs": int(match.group("returned")),
            "failed_invocations": int(match.group("failed")),
            "route_operations": int(match.group("routes")),
            "cohort_sha256": match.group("cohort").lower(),
            "status": match.group("status"),
        }
        key = tuple(frame[field] for field in (
            "frame_id",
            "attempted_effects",
            "returned_outputs",
            "failed_invocations",
            "route_operations",
            "cohort_sha256",
            "status",
        ))
        raw_frames[key] = frame

    invocations = list(raw_invocations.values())
    routes = list(raw_routes.values())
    frames = list(raw_frames.values())
    for invocation in invocations:
        invocation["frame_ids"] = sorted(invocation["frame_ids"])
        invocation["frame_id"] = invocation["frame_ids"][0]
    invocations.sort(key=lambda item: (
        item["frame_id"],
        item["canonical_line"],
    ))
    routes.sort(key=lambda item: (item["frame_id"], item["canonical_line"]))
    frames.sort(key=lambda item: (
        item["frame_id"],
        item["status"],
        item["cohort_sha256"],
    ))

    (
        disposition_is_valid,
        disposition_records,
        eligible_exact,
    ) = _effect_execution_static_catalog(disposition)
    exact_records = {
        (
            record["layer_id"],
            record["effect_index"],
            record["descriptor_id"],
        ): record
        for record in disposition_records
    }
    if invocations and not disposition_is_valid:
        failures.append("effect execution static disposition unavailable or invalid")

    for invocation in invocations:
        if (
            invocation["effect_index"] is None
            or invocation["descriptor_id"] is None
        ):
            continue
        record = exact_records.get((
            invocation["layer_id"],
            invocation["effect_index"],
            invocation["descriptor_id"],
        ))
        if record is None:
            if disposition_is_valid:
                failures.append("effect execution exact identity missing from disposition")
            continue
        invocation["definition_path"] = record["definition_path"]
        invocation["disposition_kind"] = record["kind"]
        if record["kind"] == "passthrough":
            if invocation["family"] != record["family"]:
                failures.append("effect execution passthrough family mismatch")
            continue
        if record["kind"] not in EFFECT_EXECUTION_EXACT_KINDS:
            failures.append("effect execution exact disposition cannot invoke")
            continue
        if invocation["family"] != record["family"]:
            failures.append("effect execution exact family mismatch")
            continue
        invocation["join_valid"] = True

    frame_statuses: dict[tuple[int, str], int] = {}
    for frame in frames:
        frame_status = (frame["frame_id"], frame["status"])
        frame_statuses[frame_status] = frame_statuses.get(frame_status, 0) + 1
        if frame["returned_outputs"] > frame["attempted_effects"]:
            failures.append(
                "effect execution frame returned outputs exceed attempted effects"
            )
        if frame["failed_invocations"] > frame["attempted_effects"]:
            failures.append(
                "effect execution frame failed invocations exceed attempted effects"
            )
    if any(count != 1 for count in frame_statuses.values()):
        failures.append("effect execution frame status identity duplicated")

    succeeded_exact = _effect_execution_identity_list(invocations, "encoded-output")
    failed_exact = _effect_execution_identity_list(invocations, "failed")
    exact_key = lambda item: (
        item["layer_id"],
        item["effect_index"],
        item["descriptor_id"],
        item["definition_path"],
    )
    exact_outcome_transition_identities = sorted(
        {exact_key(item) for item in succeeded_exact}.intersection(
            exact_key(item) for item in failed_exact
        ),
        key=lambda value: tuple(str(item) for item in value),
    )

    route_identity = lambda item: {
        "origin": item["origin"],
        "layer_id": item["layer_id"],
        "operation": item["operation"],
    }
    encoded_routes = {
        json.dumps(route_identity(item), sort_keys=True): route_identity(item)
        for item in routes if item["outcome"] == "encoded"
    }
    degraded_routes = {
        key: route
        for key, route in encoded_routes.items()
        if route["operation"] == "degraded-layer-source-passthrough"
    }
    failed_routes = {
        json.dumps(route_identity(item), sort_keys=True): route_identity(item)
        for item in routes if item["outcome"] == "failed"
    }
    if set(encoded_routes).intersection(failed_routes):
        failures.append("effect execution route both encoded and failed")

    public_invocations = []
    for invocation in invocations:
        public_invocations.append({
            key: value for key, value in invocation.items()
            if key != "canonical_line"
        })
    public_routes = [
        {key: value for key, value in route.items() if key != "canonical_line"}
        for route in routes
    ]
    canonical_payload = {
        "cpu_invocation_transitions": [
            {
                "frame_ids": invocation["frame_ids"],
                "event": invocation["canonical_line"],
            }
            for invocation in invocations
        ],
        "route_operation_transitions": [
            {
                "frame_id": route["frame_id"],
                "event": route["canonical_line"],
            }
            for route in routes
        ],
        "frames": frames,
    }
    canonical_sha256 = hashlib.sha256(json.dumps(
        canonical_payload,
        ensure_ascii=True,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")).hexdigest()
    failures = list(dict.fromkeys(failures))
    return {
        "has_evidence": True,
        "schema_version": 1,
        "axis_evidence": {
            key: bool(lines) for key, lines in axis_lines.items()
        },
        "cpu_invocation_count": len(public_invocations),
        "route_operation_count": len(public_routes),
        "frame_observation_count": len(frames),
        "cpu_invocations": public_invocations,
        "succeeded_exact_effects": succeeded_exact,
        "failed_exact_effects": failed_exact,
        "exact_outcome_transition_effects": [
            {
                "layer_id": layer_id,
                "effect_index": effect_index,
                "descriptor_id": descriptor_id,
                "definition_path": definition_path,
            }
            for (
                layer_id, effect_index, descriptor_id, definition_path
            ) in exact_outcome_transition_identities
        ],
        "route_operations": public_routes,
        "encoded_route_operations": [
            encoded_routes[key] for key in sorted(encoded_routes)
        ],
        "degraded_route_operations": [
            degraded_routes[key] for key in sorted(degraded_routes)
        ],
        "failed_route_operations": [
            failed_routes[key] for key in sorted(failed_routes)
        ],
        "frames": frames,
        "completed_frame_ids": sorted({
            frame["frame_id"] for frame in frames
            if frame["status"] == "completed"
        }),
        "failed_frame_ids": sorted({
            frame["frame_id"] for frame in frames
            if frame["status"] == "failed"
        }),
        "canonical_sha256": canonical_sha256,
        "validation_failures": failures,
    }

def effect_execution_failures(
    metrics: dict[str, Any],
    require_evidence: bool = False,
    *,
    sample: dict[str, Any] | None = None,
    static_disposition: dict[str, Any] | None = None,
) -> list[str]:
    sample = sample or {}
    static_demand = effect_execution_static_demand(static_disposition)
    static_disposition_failure = bool(
        require_evidence
        and static_disposition is not None
        and not static_demand.static_is_valid
    )
    require_evidence = bool(
        require_evidence
        and (
            static_disposition is None
            or static_demand.has_demand
        )
    )
    expectation_keys = {
        expectation.matrix_key
        for expectation in EFFECT_EXECUTION_EXPECTATIONS
    }
    present_expectations = expectation_keys.intersection(sample)
    (
        expects_effect_local_passthrough,
        effect_local_passthrough_expectation_valid,
        expected_effect_local_passthroughs,
    ) = effect_local_passthrough_expectation(sample)
    (
        expects_effect_recovery,
        effect_recovery_expectation_valid,
        expected_effect_recoveries,
    ) = effect_recovery_expectation(sample)
    expects_evidence = bool(present_expectations) \
        or expects_effect_local_passthrough \
        or expects_effect_recovery
    if not metrics["has_evidence"]:
        failures = []
        if static_disposition_failure:
            failures.append(
                "effect execution static disposition unavailable or invalid"
            )
        if expects_evidence or require_evidence:
            failures.append("effect execution evidence missing")
        return failures
    failures = list(metrics["validation_failures"])
    actual_effect_local_passthroughs = effect_local_passthrough_cpu_keys(metrics)
    recovery_evidence = effect_recovery_cpu_evidence(metrics)
    actual_effect_recoveries = recovery_evidence["transition_keys"]
    ordered_effect_recoveries = recovery_evidence["ordered_keys"]
    actual_persistent_effect_local_passthroughs = (
        actual_effect_local_passthroughs.difference(actual_effect_recoveries)
    )
    if (
        expects_effect_local_passthrough
        and not effect_local_passthrough_expectation_valid
    ):
        failures.append(
            "effect execution effect-local passthrough expectation invalid"
        )
    elif (
        expects_effect_local_passthrough
        and actual_persistent_effect_local_passthroughs
            != expected_effect_local_passthroughs
    ):
        failures.append(
            "effect execution effect-local passthrough expectation mismatch"
        )
    if expects_effect_recovery and not effect_recovery_expectation_valid:
        failures.append("effect execution recovery expectation invalid")
    elif expects_effect_recovery and (
        actual_effect_recoveries != expected_effect_recoveries
        or ordered_effect_recoveries != expected_effect_recoveries
    ):
        failures.append("effect execution recovery evidence mismatch")
    expectation_scopes_conflict = bool(
        {value[:3] for value in expected_effect_local_passthroughs}.intersection(
            value[:3] for value in expected_effect_recoveries
        )
    )
    if expectation_scopes_conflict:
        failures.append("effect execution recovery expectation scope conflicts")
    transition_identities = {
        (
            value.get("layer_id"),
            value.get("effect_index"),
            value.get("descriptor_id"),
        )
        for value in metrics.get("exact_outcome_transition_effects", [])
        if isinstance(value, dict)
    }
    recovery_contract_satisfied = bool(
        expects_effect_recovery
        and effect_recovery_expectation_valid
        and not expectation_scopes_conflict
        and actual_effect_recoveries == expected_effect_recoveries
        and ordered_effect_recoveries == expected_effect_recoveries
        and transition_identities
            == {value[:3] for value in expected_effect_recoveries}
    )
    if transition_identities and not recovery_contract_satisfied:
        failures.append("effect execution exact identity both succeeded and failed")
    expected_local_fallbacks = sample.get(
        "expected_effect_execution_local_fallbacks"
    )
    expected_local_fallback_keys: set[tuple[Any, ...]] = set()
    local_fallback_contract_valid = expected_local_fallbacks is None
    if expected_local_fallbacks is not None:
        local_fallback_contract_valid = True
        if not isinstance(expected_local_fallbacks, list):
            failures.append("effect execution local fallback expectation invalid")
            local_fallback_contract_valid = False
        else:
            for expected in expected_local_fallbacks:
                if not isinstance(expected, dict) or set(expected) != {
                    "origin", "layer_id", "operation", "outcome", "reason",
                }:
                    failures.append(
                        "effect execution local fallback expectation invalid"
                    )
                    local_fallback_contract_valid = False
                    continue
                if (
                    not isinstance(expected["origin"], str)
                    or not isinstance(expected["layer_id"], int)
                    or isinstance(expected["layer_id"], bool)
                    or not isinstance(expected["operation"], str)
                    or not isinstance(expected["outcome"], str)
                    or (
                        expected["reason"] is not None
                        and not isinstance(expected["reason"], str)
                    )
                ):
                    failures.append(
                        "effect execution local fallback expectation invalid"
                    )
                    local_fallback_contract_valid = False
                    continue
                expected_local_fallback_keys.add((
                    expected["origin"],
                    expected["layer_id"],
                    expected["operation"],
                    expected["outcome"],
                    expected["reason"],
                ))
    actual_local_fallback_keys = {
        (
            route["origin"],
            route["layer_id"],
            route["operation"],
            route["outcome"],
            route["reason"],
        )
        for route in metrics["route_operations"]
        if route["outcome"] == "failed"
        or (
            route["outcome"] == "encoded"
            and route["operation"] == "degraded-layer-source-passthrough"
        )
    }
    if expected_local_fallbacks is not None and local_fallback_contract_valid:
        if actual_local_fallback_keys != expected_local_fallback_keys:
            failures.append("effect execution local fallback expectation mismatch")
    if static_disposition_failure:
        failures.append(
            "effect execution static disposition unavailable or invalid"
        )
    if present_expectations and present_expectations != expectation_keys:
        failures.append("effect execution matrix contract incomplete")
    for expectation in EFFECT_EXECUTION_EXPECTATIONS:
        if expectation.matrix_key not in sample:
            continue
        expected = sample[expectation.matrix_key]
        if expectation.comparison == "integer":
            try:
                expected = int(expected)
            except (TypeError, ValueError):
                failures.append(expectation.failure_message)
                continue
        if metrics[expectation.metric_key] != expected:
            failures.append(expectation.failure_message)
    failed_exact_invocations = [
        invocation for invocation in metrics["cpu_invocations"]
        if invocation.get("subject") == "effect"
        and invocation.get("outcome") == "failed"
    ]
    persistent_contract_satisfied = bool(
        expects_effect_local_passthrough
        and effect_local_passthrough_expectation_valid
        and not expectation_scopes_conflict
        and actual_persistent_effect_local_passthroughs
            == expected_effect_local_passthroughs
    )
    expected_failed_invocation_keys: set[tuple[int, int, str, str]] = set()
    if persistent_contract_satisfied:
        expected_failed_invocation_keys.update(expected_effect_local_passthroughs)
    if recovery_contract_satisfied:
        expected_failed_invocation_keys.update(expected_effect_recoveries)
    actual_failed_invocation_keys: set[tuple[int, int, str, str]] = set()
    failed_invocations_are_typed_exact_backend = True
    for invocation in failed_exact_invocations:
        reason = invocation.get("reason")
        if (
            invocation.get("backend") != RESOLVED_MATERIAL_GRAPH_BACKEND
            or invocation.get("join_valid") is not True
            or not isinstance(invocation.get("layer_id"), int)
            or isinstance(invocation.get("layer_id"), bool)
            or not isinstance(invocation.get("effect_index"), int)
            or isinstance(invocation.get("effect_index"), bool)
            or not isinstance(invocation.get("descriptor_id"), str)
            or not isinstance(reason, str)
            or not reason.startswith(EFFECT_LOCAL_PASSTHROUGH_CPU_PREFIX)
        ):
            failed_invocations_are_typed_exact_backend = False
            continue
        actual_failed_invocation_keys.add((
            invocation["layer_id"],
            invocation["effect_index"],
            invocation["descriptor_id"],
            reason.removeprefix(EFFECT_LOCAL_PASSTHROUGH_CPU_PREFIX),
        ))
    expected_failures_are_exact_passthroughs = bool(
        expected_failed_invocation_keys
        and failed_invocations_are_typed_exact_backend
        and actual_failed_invocation_keys == expected_failed_invocation_keys
    )
    if metrics["failed_exact_effects"] \
            and not expected_failures_are_exact_passthroughs:
        failures.append("effect execution CPU invocation failed")
    if metrics.get("degraded_route_operations", []) and expected_local_fallbacks is None:
        failures.append("effect execution degraded layer source passthrough")
    if metrics["failed_route_operations"] and expected_local_fallbacks is None:
        failures.append("effect execution route operation failed")
    if metrics["failed_frame_ids"]:
        failures.append("effect execution frame command buffer failed")
    return list(dict.fromkeys(failures))
