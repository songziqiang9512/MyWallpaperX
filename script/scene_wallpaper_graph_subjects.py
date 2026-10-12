"""Join graph terminal subjects with exact CPU backend ownership."""

from __future__ import annotations


from scene_matrix_contract import RESOLVED_MATERIAL_GRAPH_BACKEND
from scene_wallpaper_effect_execution import _effect_execution_static_catalog
from scene_wallpaper_effect_expectations import (
    ACTIVATION_PASSTHROUGH_PROGRAM_IDENTITIES, EFFECT_LOCAL_PASSTHROUGH_CPU_PREFIX,
    effect_local_passthrough_cpu_keys, effect_local_passthrough_graph_keys,
    effect_recovery_cpu_evidence, graph_effect_subject_keys,
)
from typing import Any


def resolved_material_graph_exact_backend_metrics(
    accepted_layer_ids: list[int],
    effect_execution: dict[str, Any],
    static_disposition: dict[str, Any] | None,
    graph_observations: dict[str, Any],
    dormant_layer_ids: set[int] | None = None,
    activation_dormant_identities: set[tuple[int, int, str]] | None = None,
) -> dict[str, Any]:
    accepted_layers = set(accepted_layer_ids)
    disposition_is_valid, _, eligible_exact = (
        _effect_execution_static_catalog(static_disposition)
    )
    eligible_exact_identities = {
        (
            subject.get("layer_id"),
            subject.get("effect_index"),
            subject.get("descriptor_id"),
        )
        for subject in eligible_exact
    }
    # Authored-deactivated activations never execute their program subject;
    # their passthrough encode is not a program success either.
    activation_dormant = (
        activation_dormant_identities or set()
    ).intersection(eligible_exact_identities)
    required_by_layer: dict[int, set[tuple[int, str]]] = {
        layer_id: set() for layer_id in accepted_layers
    }
    if disposition_is_valid:
        for subject in eligible_exact:
            layer_id = subject.get("layer_id")
            effect_index = subject.get("effect_index")
            descriptor_id = subject.get("descriptor_id")
            if (
                layer_id in accepted_layers
                and isinstance(effect_index, int)
                and not isinstance(effect_index, bool)
                and isinstance(descriptor_id, str)
                and (layer_id, effect_index, descriptor_id)
                    not in activation_dormant
            ):
                required_by_layer[layer_id].add((effect_index, descriptor_id))

    invocations = (
        effect_execution.get("cpu_invocations", [])
        if isinstance(effect_execution, dict)
        else []
    )
    execution_is_well_formed = bool(
        isinstance(effect_execution, dict)
        and effect_execution.get("has_evidence") is True
        and effect_execution.get("validation_failures") == []
        and isinstance(invocations, list)
        and all(isinstance(invocation, dict) for invocation in invocations)
    )
    successful_by_layer: dict[int, set[tuple[int, str]]] = {
        layer_id: set() for layer_id in accepted_layers
    }
    cpu_effect_local_passthroughs = effect_local_passthrough_cpu_keys(
        effect_execution
    )
    recovery_cpu_evidence = effect_recovery_cpu_evidence(effect_execution)
    recovery_cpu_keys = recovery_cpu_evidence["transition_keys"]
    recovery_cpu_identities = {value[:3] for value in recovery_cpu_keys}
    graph_effect_local_passthroughs = effect_local_passthrough_graph_keys(
        graph_observations
    )
    next_frame_effect_local_passthroughs = effect_local_passthrough_graph_keys(
        graph_observations,
        field="visual_failure_passthrough_next_frame_subjects",
    )
    persistent_effect_local_passthroughs = (
        cpu_effect_local_passthroughs.difference(recovery_cpu_keys)
    )
    effect_local_passthroughs = (
        persistent_effect_local_passthroughs.intersection(
            graph_effect_local_passthroughs,
            next_frame_effect_local_passthroughs,
        ).union(
            recovery_cpu_keys.intersection(graph_effect_local_passthroughs)
        )
    )
    unjoined_cpu_effect_local_passthroughs = (
        cpu_effect_local_passthroughs.difference(
            graph_effect_local_passthroughs
        )
    )
    unjoined_graph_effect_local_passthroughs = (
        graph_effect_local_passthroughs.difference(
            cpu_effect_local_passthroughs
        )
    )
    missing_next_frame_effect_local_passthroughs = (
        graph_effect_local_passthroughs.difference(recovery_cpu_keys).difference(
            next_frame_effect_local_passthroughs
        )
    )
    effect_local_passthrough_identities = {
        value[:3] for value in effect_local_passthroughs
    }
    effect_local_passthrough_layer_ids = {
        value[0] for value in effect_local_passthroughs
    }
    persistent_effect_local_passthrough_identities = (
        effect_local_passthrough_identities.difference(recovery_cpu_identities)
    )
    unproven_effect_local_passthroughs = {
        value for value in effect_local_passthroughs
        if value[:3] not in eligible_exact_identities
        or value[0] not in accepted_layers
    }
    program_required_layer_ids = sorted(
        layer_id for layer_id, subjects in required_by_layer.items()
        if any(
            (layer_id, effect_index, descriptor_id)
                not in persistent_effect_local_passthrough_identities
            for effect_index, descriptor_id in subjects
        )
    )
    program_required_subjects = {
        (layer_id, effect_index, descriptor_id)
        for layer_id, subjects in required_by_layer.items()
        for effect_index, descriptor_id in subjects
        if (layer_id, effect_index, descriptor_id)
            not in persistent_effect_local_passthrough_identities
    }
    mixed_program_required_subjects = {
        value for value in program_required_subjects
        if value[0] in effect_local_passthrough_layer_ids
    }
    graph_program_effect_subjects = graph_effect_subject_keys(
        graph_observations,
        "program_effect_subjects",
    )
    graph_program_next_frame_effect_subjects = graph_effect_subject_keys(
        graph_observations,
        "program_next_frame_effect_subjects",
    )
    mixed_program_missing_terminal_subjects = (
        mixed_program_required_subjects.difference(
            graph_program_effect_subjects
        )
    )
    mixed_program_missing_next_frame_subjects = (
        mixed_program_required_subjects.difference(
            graph_program_next_frame_effect_subjects
        )
    )
    wrong_backend_layer_ids: set[int] = set()
    failed_layer_ids: set[int] = set()
    malformed_layer_ids: set[int] = set()
    resolved_backend_layer_ids: set[int] = set()
    if isinstance(invocations, list):
        for invocation in invocations:
            if not isinstance(invocation, dict) or invocation.get("subject") != "effect":
                continue
            layer_id = invocation.get("layer_id")
            if not isinstance(layer_id, int) or isinstance(layer_id, bool):
                continue
            effect_index = invocation.get("effect_index")
            descriptor_id = invocation.get("descriptor_id")
            exact_identity = (layer_id, effect_index, descriptor_id)
            if exact_identity not in eligible_exact_identities:
                continue
            if invocation.get("backend") == RESOLVED_MATERIAL_GRAPH_BACKEND:
                resolved_backend_layer_ids.add(layer_id)
            if exact_identity in activation_dormant:
                continue
            if layer_id not in accepted_layers:
                continue
            if invocation.get("backend") != RESOLVED_MATERIAL_GRAPH_BACKEND:
                wrong_backend_layer_ids.add(layer_id)
            if (
                invocation.get("join_valid") is not True
                or not isinstance(effect_index, int)
                or isinstance(effect_index, bool)
                or not isinstance(descriptor_id, str)
            ):
                malformed_layer_ids.add(layer_id)
                continue
            if (
                invocation.get("backend") == RESOLVED_MATERIAL_GRAPH_BACKEND
                and invocation.get("outcome") == "encoded-output"
            ):
                successful_by_layer[layer_id].add((effect_index, descriptor_id))
            elif (
                invocation.get("backend") == RESOLVED_MATERIAL_GRAPH_BACKEND
                and invocation.get("outcome") == "failed"
                and isinstance(invocation.get("reason"), str)
                and (
                    layer_id,
                    effect_index,
                    descriptor_id,
                    invocation["reason"].removeprefix(
                        EFFECT_LOCAL_PASSTHROUGH_CPU_PREFIX
                    ),
                ) in effect_local_passthroughs
                and invocation["reason"].startswith(
                    EFFECT_LOCAL_PASSTHROUGH_CPU_PREFIX
                )
            ):
                successful_by_layer[layer_id].add((effect_index, descriptor_id))
            elif invocation.get("outcome") != "encoded-output":
                failed_layer_ids.add(layer_id)

    complete_layer_ids = sorted(
        layer_id for layer_id in accepted_layers
        if disposition_is_valid
        and (
            not required_by_layer[layer_id]
            or (
                execution_is_well_formed
                and required_by_layer[layer_id] == successful_by_layer[layer_id]
                and layer_id not in wrong_backend_layer_ids
                and layer_id not in failed_layer_ids
                and layer_id not in malformed_layer_ids
            )
        )
    )
    missing_layer_ids = sorted(accepted_layers.difference(complete_layer_ids))
    unexpected_layer_ids = sorted(
        resolved_backend_layer_ids.difference(accepted_layers)
        .difference(dormant_layer_ids or set())
    )
    return {
        "has_evidence": disposition_is_valid and (
            not any(required_by_layer.values()) or execution_is_well_formed
        ),
        "backend": RESOLVED_MATERIAL_GRAPH_BACKEND,
        "required_layer_ids": sorted(
            layer_id for layer_id, subjects in required_by_layer.items()
            if subjects
        ),
        "program_required_layer_ids": program_required_layer_ids,
        "mixed_program_required_subjects": sorted(
            mixed_program_required_subjects
        ),
        "mixed_program_missing_terminal_subjects": sorted(
            mixed_program_missing_terminal_subjects
        ),
        "mixed_program_missing_next_frame_subjects": sorted(
            mixed_program_missing_next_frame_subjects
        ),
        "no_demand_layer_ids": sorted(
            layer_id for layer_id, subjects in required_by_layer.items()
            if not subjects
        ),
        "complete_layer_ids": complete_layer_ids,
        "missing_layer_ids": missing_layer_ids,
        "wrong_backend_layer_ids": sorted(wrong_backend_layer_ids),
        "failed_layer_ids": sorted(failed_layer_ids),
        "malformed_layer_ids": sorted(malformed_layer_ids),
        "unexpected_layer_ids": unexpected_layer_ids,
        "resolved_backend_layer_ids": sorted(resolved_backend_layer_ids),
        "effect_local_passthroughs": [
            {
                "layer_id": layer_id,
                "effect_index": effect_index,
                "descriptor_id": descriptor_id,
                "reason": reason,
            }
            for layer_id, effect_index, descriptor_id, reason in sorted(
                effect_local_passthroughs
            )
        ],
        "effect_local_passthrough_layer_ids": sorted({
            value[0] for value in effect_local_passthroughs
        }),
        "recovery_cpu_keys": sorted(recovery_cpu_keys),
        "recovery_cpu_frames": [
            {
                "layer_id": layer_id,
                "effect_index": effect_index,
                "descriptor_id": descriptor_id,
                "reason": reason,
                "failure_frame": frames[0],
                "success_frame": frames[1],
            }
            for (
                layer_id, effect_index, descriptor_id, reason
            ), frames in sorted(
                recovery_cpu_evidence["ordered_frames"].items()
            )
        ],
        "unjoined_cpu_effect_local_passthroughs": sorted(
            unjoined_cpu_effect_local_passthroughs
        ),
        "unjoined_graph_effect_local_passthroughs": sorted(
            unjoined_graph_effect_local_passthroughs
        ),
        "missing_next_frame_effect_local_passthroughs": sorted(
            missing_next_frame_effect_local_passthroughs
        ),
        "unproven_effect_local_passthroughs": sorted(
            unproven_effect_local_passthroughs
        ),
    }

def resolved_material_graph_passthrough_metrics(
    accepted_layer_ids: list[int],
    graph_observations: dict[str, Any],
    static_disposition: dict[str, Any] | None,
    *,
    execution_observations_enabled: bool = True,
) -> dict[str, Any]:
    accepted_layers = set(accepted_layer_ids)
    disposition_is_valid, disposition_records, _ = (
        _effect_execution_static_catalog(static_disposition)
    )
    required_subjects = {
        (
            record.get("layer_id"),
            record.get("effect_index"),
            record.get("descriptor_id"),
        )
        for record in disposition_records
        if record.get("kind") == "passthrough"
        and record.get("layer_id") in accepted_layers
    }
    required_by_layer = {
        layer_id: {
            subject for subject in required_subjects
            if subject[0] == layer_id
        }
        for layer_id in accepted_layers
    }
    observed_subjects: set[tuple[int, int, str]] = set()
    next_frame_subjects: set[tuple[int, int, str]] = set()
    malformed_subjects: set[tuple[int, int, str]] = set()
    for observation in graph_observations.get(
        "terminal_success_observations", []
    ):
        subject = (
            observation.get("layer_id"),
            observation.get("effect_index"),
            observation.get("descriptor_id"),
        )
        if subject not in required_subjects:
            continue
        if (
            observation.get("activation_passthrough") is not True
            or observation.get("program_identity")
            not in ACTIVATION_PASSTHROUGH_PROGRAM_IDENTITIES
        ):
            malformed_subjects.add(subject)
            continue
        observed_subjects.add(subject)
        if "next-frame" in observation.get("trigger", []):
            next_frame_subjects.add(subject)

    missing_subjects = required_subjects.difference(observed_subjects)
    missing_next_frame_subjects = required_subjects.difference(
        next_frame_subjects
    )
    required_layer_ids = {
        layer_id for layer_id, required in required_by_layer.items()
        if required
    }
    missing_compositor_layer_ids = required_layer_ids.difference(
        graph_observations.get("compositor_consumed_layer_ids", [])
    )
    complete_layer_ids = sorted(
        layer_id for layer_id, required in required_by_layer.items()
        if required.issubset(observed_subjects)
        and required.issubset(next_frame_subjects)
        and required.isdisjoint(malformed_subjects)
        and layer_id not in missing_compositor_layer_ids
    )
    failures: list[str] = []
    if (
        execution_observations_enabled
        and required_subjects
        and not graph_observations.get("has_evidence")
    ):
        failures.append(
            "resolved material graph passthrough terminal evidence missing"
        )
    if execution_observations_enabled and missing_subjects:
        failures.append(
            "resolved material graph passthrough activation evidence missing"
        )
    if execution_observations_enabled and missing_next_frame_subjects:
        failures.append(
            "resolved material graph passthrough next-frame evidence missing"
        )
    if execution_observations_enabled and missing_compositor_layer_ids:
        failures.append(
            "resolved material graph passthrough compositor evidence missing"
        )
    if malformed_subjects:
        failures.append(
            "resolved material graph passthrough activation evidence malformed"
        )

    def public_subjects(
        subjects: set[tuple[int, int, str]],
    ) -> list[dict[str, Any]]:
        return [
            {
                "layer_id": layer_id,
                "effect_index": effect_index,
                "descriptor_id": descriptor_id,
            }
            for layer_id, effect_index, descriptor_id in sorted(subjects)
        ]

    return {
        "has_evidence": disposition_is_valid and (
            not required_subjects or graph_observations.get("has_evidence") is True
        ),
        "required_layer_ids": sorted(required_layer_ids),
        "complete_layer_ids": complete_layer_ids,
        "missing_compositor_layer_ids": sorted(
            missing_compositor_layer_ids
        ),
        "required_subjects": public_subjects(required_subjects),
        "observed_subjects": public_subjects(observed_subjects),
        "next_frame_subjects": public_subjects(next_frame_subjects),
        "missing_subjects": public_subjects(missing_subjects),
        "missing_next_frame_subjects": public_subjects(
            missing_next_frame_subjects
        ),
        "malformed_subjects": public_subjects(malformed_subjects),
        "validation_failures": failures,
    }
