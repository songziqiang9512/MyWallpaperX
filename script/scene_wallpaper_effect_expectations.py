"""Validate typed effect fallback and recovery subject expectations."""

from __future__ import annotations

import re
from scene_matrix_contract import RESOLVED_MATERIAL_GRAPH_BACKEND
from typing import Any
from urllib.parse import unquote


# Activation-passthrough program identities the runtime may legally emit for
# a statically admitted-passthrough stage. Mirrors the product whitelist in
# prepareActivationPassthrough (ProgramFirstStages / VisualFailurePassthrough):
# D2b'' added the script-gated preproof downgrade reason for dependency
# consumers (2938612768 layers 239/657/1509).
ACTIVATION_PASSTHROUGH_PROGRAM_REASONS = frozenset({
    "effect-activation-visibility-disabled",
    "effect-activation-pointer-provider-unavailable",
    "effect-activation-scalar-below-minimum",
    "initially-inactive-property-stage-passthrough",
    "script-gated-dependency-preproof-mismatch",
})

ACTIVATION_PASSTHROUGH_PROGRAM_IDENTITIES = frozenset({
    "activation-passthrough:" + reason
    for reason in ACTIVATION_PASSTHROUGH_PROGRAM_REASONS
})

EFFECT_LOCAL_PASSTHROUGH_EXPECTATION_KEY = (
    "expected_resolved_material_graph_effect_local_passthroughs"
)

EFFECT_RECOVERY_EXPECTATION_KEY = "expected_effect_recoveries"

EFFECT_LOCAL_PASSTHROUGH_CPU_PREFIX = "effect-local-passthrough-"

TYPED_EFFECT_ACTIVATION_DECISION_RE = re.compile(
    r"channel=user-property consumer=effect-activation "
    r"layer=(?P<layer>\d+) effect=(?P<effect>\d+) "
    r"descriptor=(?P<descriptor>\S+) property=\S+ type=bool "
    r"frame=\d+ generation=\d+ value=\S+ "
    r"decision=(?P<decision>active|inactive)"
)

def authored_deactivated_activation_identities(
    log_text: str,
) -> set[tuple[int, int, str]]:
    """Effect subjects whose typed user-property activation stayed disabled.

    The product evaluates every authored effect activation per frame and
    publishes the decision with the full (layer, effect, descriptor)
    identity. A subject with at least one decision and no active decision
    is authored-deactivated for the whole run: its graph transaction is
    the activation passthrough by design, so it must not be demanded as a
    program execution subject.
    """
    decisions: dict[tuple[int, int, str], set[str]] = {}
    for match in TYPED_EFFECT_ACTIVATION_DECISION_RE.finditer(log_text):
        identity = (
            int(match.group("layer")),
            int(match.group("effect")),
            unquote(match.group("descriptor")),
        )
        decisions.setdefault(identity, set()).add(
            match.group("decision")
        )
    return {
        identity
        for identity, values in decisions.items()
        if values == {"inactive"}
    }

def effect_local_passthrough_expectation(
    sample: dict[str, Any],
) -> tuple[bool, bool, set[tuple[int, int, str, str]]]:
    if EFFECT_LOCAL_PASSTHROUGH_EXPECTATION_KEY not in sample:
        return False, True, set()
    raw = sample[EFFECT_LOCAL_PASSTHROUGH_EXPECTATION_KEY]
    if not isinstance(raw, list):
        return True, False, set()
    entries: list[tuple[int, int, str, str]] = []
    for value in raw:
        if not isinstance(value, dict) or set(value) != {
            "layer_id", "effect_index", "descriptor_id", "reason",
        }:
            return True, False, set()
        layer_id = value["layer_id"]
        effect_index = value["effect_index"]
        descriptor_id = value["descriptor_id"]
        reason = value["reason"]
        if (
            not isinstance(layer_id, int)
            or isinstance(layer_id, bool)
            or layer_id < 0
            or not isinstance(effect_index, int)
            or isinstance(effect_index, bool)
            or effect_index < 0
            or not isinstance(descriptor_id, str)
            or not descriptor_id
            or not isinstance(reason, str)
            or re.fullmatch(r"[A-Za-z0-9._-]+", reason) is None
        ):
            return True, False, set()
        entries.append((layer_id, effect_index, descriptor_id, reason))
    if entries != sorted(entries) or len(entries) != len(set(entries)):
        return True, False, set()
    return True, True, set(entries)

def effect_recovery_expectation(
    sample: dict[str, Any],
) -> tuple[bool, bool, set[tuple[int, int, str, str]]]:
    if EFFECT_RECOVERY_EXPECTATION_KEY not in sample:
        return False, True, set()
    raw = sample[EFFECT_RECOVERY_EXPECTATION_KEY]
    if not isinstance(raw, list) or not raw:
        return True, False, set()
    entries: list[tuple[int, int, str, str]] = []
    for value in raw:
        if not isinstance(value, dict) or set(value) != {
            "layer_id", "effect_index", "descriptor_id", "reason",
        }:
            return True, False, set()
        layer_id = value["layer_id"]
        effect_index = value["effect_index"]
        descriptor_id = value["descriptor_id"]
        reason = value["reason"]
        if (
            not isinstance(layer_id, int)
            or isinstance(layer_id, bool)
            or layer_id < 0
            or not isinstance(effect_index, int)
            or isinstance(effect_index, bool)
            or effect_index < 0
            or not isinstance(descriptor_id, str)
            or not descriptor_id
            or not isinstance(reason, str)
            or re.fullmatch(r"[A-Za-z0-9._-]+", reason) is None
        ):
            return True, False, set()
        entries.append((layer_id, effect_index, descriptor_id, reason))
    if entries != sorted(entries) or len(entries) != len(set(entries)):
        return True, False, set()
    return True, True, set(entries)

def effect_recovery_cpu_evidence(
    effect_execution: dict[str, Any] | None,
) -> dict[str, Any]:
    invocations = (
        effect_execution.get("cpu_invocations", [])
        if isinstance(effect_execution, dict) else []
    )
    successful_frames: dict[tuple[int, int, str], list[int]] = {}
    failed_frames: dict[tuple[int, int, str, str], list[int]] = {}
    for invocation in invocations:
        if (
            not isinstance(invocation, dict)
            or invocation.get("subject") != "effect"
            or invocation.get("backend") != RESOLVED_MATERIAL_GRAPH_BACKEND
            or invocation.get("join_valid") is not True
            or not isinstance(invocation.get("frame_id"), int)
            or isinstance(invocation.get("frame_id"), bool)
            or not isinstance(invocation.get("layer_id"), int)
            or isinstance(invocation.get("layer_id"), bool)
            or not isinstance(invocation.get("effect_index"), int)
            or isinstance(invocation.get("effect_index"), bool)
            or not isinstance(invocation.get("descriptor_id"), str)
        ):
            continue
        identity = (
            invocation["layer_id"],
            invocation["effect_index"],
            invocation["descriptor_id"],
        )
        invocation_frames = invocation.get("frame_ids")
        if not (
            isinstance(invocation_frames, list)
            and invocation_frames
            and all(
                isinstance(frame, int) and not isinstance(frame, bool)
                for frame in invocation_frames
            )
        ):
            invocation_frames = [invocation["frame_id"]]
        if invocation.get("outcome") == "encoded-output":
            successful_frames.setdefault(identity, []).extend(invocation_frames)
            continue
        reason = invocation.get("reason")
        if (
            invocation.get("outcome") == "failed"
            and isinstance(reason, str)
            and reason.startswith(EFFECT_LOCAL_PASSTHROUGH_CPU_PREFIX)
        ):
            key = (
                *identity,
                reason.removeprefix(EFFECT_LOCAL_PASSTHROUGH_CPU_PREFIX),
            )
            failed_frames.setdefault(key, []).extend(invocation_frames)

    transition_keys = {
        key for key in failed_frames if key[:3] in successful_frames
    }
    ordered_frames: dict[tuple[int, int, str, str], tuple[int, int]] = {}
    for key in transition_keys:
        first_success_frame = min(successful_frames[key[:3]])
        if max(failed_frames[key]) < first_success_frame:
            ordered_frames[key] = (
                min(failed_frames[key]), first_success_frame
            )
    return {
        "transition_keys": transition_keys,
        "ordered_keys": set(ordered_frames),
        "ordered_frames": ordered_frames,
    }

def effect_local_passthrough_cpu_keys(
    effect_execution: dict[str, Any] | None,
) -> set[tuple[int, int, str, str]]:
    if not isinstance(effect_execution, dict):
        return set()
    result: set[tuple[int, int, str, str]] = set()
    for invocation in effect_execution.get("cpu_invocations", []):
        reason = invocation.get("reason")
        if (
            invocation.get("subject") != "effect"
            or invocation.get("outcome") != "failed"
            or invocation.get("backend") != RESOLVED_MATERIAL_GRAPH_BACKEND
            or invocation.get("join_valid") is not True
            or not isinstance(invocation.get("layer_id"), int)
            or isinstance(invocation.get("layer_id"), bool)
            or not isinstance(invocation.get("effect_index"), int)
            or isinstance(invocation.get("effect_index"), bool)
            or not isinstance(invocation.get("descriptor_id"), str)
            or not isinstance(reason, str)
            or not reason.startswith(EFFECT_LOCAL_PASSTHROUGH_CPU_PREFIX)
        ):
            continue
        result.add((
            invocation["layer_id"],
            invocation["effect_index"],
            invocation["descriptor_id"],
            reason.removeprefix(EFFECT_LOCAL_PASSTHROUGH_CPU_PREFIX),
        ))
    return result

def effect_local_passthrough_graph_keys(
    graph_observations: dict[str, Any],
    field: str = "visual_failure_passthroughs",
) -> set[tuple[int, int, str, str]]:
    result: set[tuple[int, int, str, str]] = set()
    for value in graph_observations.get(field, []):
        if (
            isinstance(value, dict)
            and isinstance(value.get("layer_id"), int)
            and not isinstance(value.get("layer_id"), bool)
            and isinstance(value.get("effect_index"), int)
            and not isinstance(value.get("effect_index"), bool)
            and isinstance(value.get("descriptor_id"), str)
            and isinstance(value.get("reason"), str)
        ):
            result.add((
                value["layer_id"], value["effect_index"],
                value["descriptor_id"], value["reason"],
            ))
    return result

def graph_effect_subject_keys(
    graph_observations: dict[str, Any],
    field: str,
) -> set[tuple[int, int, str]]:
    result: set[tuple[int, int, str]] = set()
    for value in graph_observations.get(field, []):
        if (
            isinstance(value, dict)
            and isinstance(value.get("layer_id"), int)
            and not isinstance(value.get("layer_id"), bool)
            and isinstance(value.get("effect_index"), int)
            and not isinstance(value.get("effect_index"), bool)
            and isinstance(value.get("descriptor_id"), str)
        ):
            result.add((
                value["layer_id"],
                value["effect_index"],
                value["descriptor_id"],
            ))
    return result
