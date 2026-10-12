"""Validate graph execution, terminal, recovery and lifecycle contracts."""

from __future__ import annotations

import re
from scene_matrix_contract import RESOLVED_MATERIAL_GRAPH_EXPECTATIONS
from scene_wallpaper_effect_expectations import (
    effect_local_passthrough_expectation, effect_local_passthrough_graph_keys,
    effect_recovery_expectation,
)
from typing import Any


def resolved_material_graph_execution_failures(
    metrics: dict[str, Any],
    require_evidence: bool = False,
    *,
    sample: dict[str, Any] | None = None,
) -> list[str]:
    sample = sample or {}
    expected_fallback_layers = sample.get(
        "expected_resolved_material_graph_local_fallback_layer_ids"
    )
    expected_fallbacks = sample.get(
        "expected_resolved_material_graph_local_fallbacks"
    )
    fallback_layers: set[int] = set()
    expected_fallback_keys: set[tuple[int, str]] | None = None
    fallback_contract_valid = not (
        expected_fallback_layers is not None and expected_fallbacks is not None
    )
    if expected_fallbacks is not None and fallback_contract_valid:
        expected_fallback_keys = set()
        if not isinstance(expected_fallbacks, list) or not expected_fallbacks:
            fallback_contract_valid = False
        else:
            for expected in expected_fallbacks:
                if (
                    not isinstance(expected, dict)
                    or set(expected) != {"layer_id", "reason"}
                    or not isinstance(expected["layer_id"], int)
                    or isinstance(expected["layer_id"], bool)
                    or expected["layer_id"] < 0
                    or not isinstance(expected["reason"], str)
                    or re.fullmatch(r"[A-Za-z0-9._-]+", expected["reason"])
                        is None
                ):
                    fallback_contract_valid = False
                    continue
                expected_fallback_keys.add((
                    expected["layer_id"], expected["reason"]
                ))
            if len(expected_fallback_keys) != len(expected_fallbacks):
                fallback_contract_valid = False
            fallback_layers = {layer for layer, _ in expected_fallback_keys}
    elif expected_fallback_layers is not None and fallback_contract_valid:
        fallback_contract_valid = True
        valid_layer_ids = (
            isinstance(expected_fallback_layers, list)
            and all(
                isinstance(layer_id, int)
                and not isinstance(layer_id, bool)
                and layer_id >= 0
                for layer_id in expected_fallback_layers
            )
        )
        if not valid_layer_ids or len(set(expected_fallback_layers)) != len(
            expected_fallback_layers
        ):
            fallback_contract_valid = False
        else:
            fallback_layers = set(expected_fallback_layers)

    allowlisted_local_failures = {
        "resolved material graph accepted layer GPU completion missing",
        "resolved material graph accepted layer compositor consumption missing",
        "resolved material graph accepted layer next-frame evidence missing",
        "resolved material graph accepted layer exact backend evidence missing",
        "resolved material graph observation diagnostic reported",
        "resolved material graph executor claimed count is zero",
        "resolved material graph executor encoded count is zero",
        "resolved material graph executor GPU encoded count is zero",
        "resolved material graph successful transaction count below two",
        "resolved material graph Program transaction count below two",
    }
    failures = list(metrics["validation_failures"])
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
    actual_effect_local_passthroughs = effect_local_passthrough_graph_keys(
        metrics["graph_observations"]
    )
    joined_effect_local_passthroughs = {
        (
            value["layer_id"], value["effect_index"],
            value["descriptor_id"], value["reason"],
        )
        for value in metrics["exact_backend"].get(
            "effect_local_passthroughs", []
        )
    }
    if actual_effect_local_passthroughs \
            != joined_effect_local_passthroughs:
        failures.append(
            "resolved material graph effect-local passthrough exact join failed"
        )
    recovery_cpu_keys = {
        tuple(value)
        for value in metrics["exact_backend"].get("recovery_cpu_keys", [])
        if isinstance(value, (list, tuple)) and len(value) == 4
    }
    actual_recovery_passthroughs = (
        actual_effect_local_passthroughs.intersection(recovery_cpu_keys)
    )
    actual_persistent_effect_local_passthroughs = (
        actual_effect_local_passthroughs.difference(recovery_cpu_keys)
    )
    if (
        expects_effect_local_passthrough
        and not effect_local_passthrough_expectation_valid
    ):
        failures.append(
            "resolved material graph effect-local passthrough expectation invalid"
        )
    elif expects_effect_local_passthrough:
        if actual_persistent_effect_local_passthroughs \
                != expected_effect_local_passthroughs:
            failures.append(
                "resolved material graph effect-local passthrough evidence mismatch"
            )
    elif actual_persistent_effect_local_passthroughs:
        failures.append(
            "resolved material graph unexpected effect-local passthrough"
        )
    expectation_scopes_conflict = bool(
        {value[:3] for value in expected_effect_local_passthroughs}.intersection(
            value[:3] for value in expected_effect_recoveries
        )
    )
    if expects_effect_recovery and not effect_recovery_expectation_valid:
        failures.append(
            "resolved material graph recovery expectation invalid"
        )
    elif expectation_scopes_conflict:
        failures.append(
            "resolved material graph recovery expectation scope conflicts"
        )
    elif expects_effect_recovery:
        recovery_cpu_frames = {
            (
                value.get("layer_id"),
                value.get("effect_index"),
                value.get("descriptor_id"),
                value.get("reason"),
            ): (value.get("failure_frame"), value.get("success_frame"))
            for value in metrics["exact_backend"].get(
                "recovery_cpu_frames", []
            )
            if isinstance(value, dict)
        }
        if (
            recovery_cpu_keys != expected_effect_recoveries
            or set(recovery_cpu_frames) != expected_effect_recoveries
            or actual_recovery_passthroughs != expected_effect_recoveries
        ):
            failures.append(
                "resolved material graph recovery evidence mismatch"
            )
        terminal_observations = metrics["graph_observations"].get(
            "terminal_success_observations", []
        )
        for recovery in sorted(expected_effect_recoveries):
            frames = recovery_cpu_frames.get(recovery)
            if frames is None:
                continue
            failure_frame, success_frame = frames
            identity = recovery[:3]
            visual_terminals = [
                observation
                for observation in terminal_observations
                if isinstance(observation, dict)
                and observation.get("visual_failure_passthrough") is True
                and (
                    observation.get("layer_id"),
                    observation.get("effect_index"),
                    observation.get("descriptor_id"),
                ) == identity
                and observation.get("program_identity")
                    == f"visual-failure-passthrough:{recovery[3]}"
                and observation.get("frame") == failure_frame
            ]
            visual_terminal_observed = bool(visual_terminals) and all(
                observation.get("outcome") == "succeeded"
                and observation.get("gpu_completion") == "completed"
                and observation.get("compositor_consumed") is True
                for observation in visual_terminals
            )
            program_terminals = [
                observation
                for observation in terminal_observations
                if isinstance(observation, dict)
                and observation.get("activation_passthrough") is False
                and observation.get("visual_failure_passthrough") is False
                and (
                    observation.get("layer_id"),
                    observation.get("effect_index"),
                    observation.get("descriptor_id"),
                ) == identity
                and observation.get("frame") == success_frame
            ]
            program_identities = {
                observation.get("program_identity")
                for observation in program_terminals
                if isinstance(observation.get("program_identity"), str)
                and observation.get("program_identity")
            }
            program_terminal_observed = bool(program_terminals) and all(
                observation.get("outcome") == "succeeded"
                and observation.get("gpu_completion") == "completed"
                and observation.get("compositor_consumed") is True
                for observation in program_terminals
            ) and len(program_identities) == 1
            recovered_program_identity = (
                next(iter(program_identities))
                if program_terminal_observed else None
            )
            program_next_frames = [
                observation
                for observation in terminal_observations
                if isinstance(observation, dict)
                and observation.get("activation_passthrough") is False
                and observation.get("visual_failure_passthrough") is False
                and (
                    observation.get("layer_id"),
                    observation.get("effect_index"),
                    observation.get("descriptor_id"),
                ) == identity
                and isinstance(observation.get("frame"), int)
                and observation["frame"] > success_frame
                and "next-frame" in observation.get("trigger", [])
            ]
            program_next_frame_observed = bool(program_next_frames) and all(
                observation.get("outcome") == "succeeded"
                and observation.get("gpu_completion") == "completed"
                and observation.get("compositor_consumed") is True
                and observation.get("program_identity")
                    == recovered_program_identity
                for observation in program_next_frames
            )
            if not visual_terminal_observed:
                failures.append(
                    "resolved material graph recovery passthrough terminal missing"
                )
            if not program_terminal_observed:
                failures.append(
                    "resolved material graph recovery Program terminal missing"
                )
            if not program_next_frame_observed:
                failures.append(
                    "resolved material graph recovery next-frame Program missing"
                )
    elif actual_recovery_passthroughs:
        failures.append(
            "resolved material graph unexpected effect recovery"
        )
    if {
        value[0] for value in actual_effect_local_passthroughs
    }.intersection(
        value["layer_id"] for value in metrics["executor"]["local_fallbacks"]
    ):
        failures.append(
            "resolved material graph fallback scopes conflict"
        )
    expected_activation_reason_codes = sample.get(
        "required_activation_passthrough_reason_codes"
    )
    minimum_activation_passthrough_count = sample.get(
        "minimum_activation_passthrough_count"
    )
    expects_activation_evidence = (
        expected_activation_reason_codes is not None
        or minimum_activation_passthrough_count is not None
    )
    activation_expectation_valid = True
    if expected_activation_reason_codes is not None:
        activation_expectation_valid = (
            isinstance(expected_activation_reason_codes, list)
            and bool(expected_activation_reason_codes)
            and all(
                isinstance(reason, str)
                and re.fullmatch(r"[A-Za-z0-9._-]+", reason) is not None
                for reason in expected_activation_reason_codes
            )
            and expected_activation_reason_codes
                == sorted(set(expected_activation_reason_codes))
        )
    if minimum_activation_passthrough_count is not None:
        activation_expectation_valid = activation_expectation_valid and (
            isinstance(minimum_activation_passthrough_count, int)
            and not isinstance(minimum_activation_passthrough_count, bool)
            and minimum_activation_passthrough_count > 0
        )
    if expects_activation_evidence and not activation_expectation_valid:
        failures.append(
            "resolved material graph activation passthrough expectation invalid"
        )
    elif expects_activation_evidence:
        actual_reason_codes = set(
            metrics["graph_observations"][
                "activation_passthrough_reason_codes"
            ]
        )
        if (
            expected_activation_reason_codes is not None
            and not set(expected_activation_reason_codes).issubset(
                actual_reason_codes
            )
        ) or (
            minimum_activation_passthrough_count is not None
            and metrics["graph_observations"]["activation_passthrough_count"]
                < minimum_activation_passthrough_count
        ):
            failures.append(
                "resolved material graph activation passthrough evidence mismatch"
            )
    fallback_evidence_satisfied = False
    if fallback_contract_valid and fallback_layers:
        missing_layers = set(metrics["layer_routes"]["missing_layer_ids"])
        accepted_layers = set(metrics["capability"]["accepted_layer_ids"])
        expected_success_layers = set(
            sample.get("expected_resolved_material_graph_succeeded_layer_ids", [])
        )
        actual_fallback_keys = {
            (entry["layer_id"], entry["reason"])
            for entry in metrics["executor"]["local_fallbacks"]
        }
        typed_fallback_mismatch = (
            expected_fallback_keys is not None
            and actual_fallback_keys != expected_fallback_keys
        )
        recovered_layers = set(
            metrics["executor"]["transient_recovered_fallback_layer_ids"]
        )
        fallback_shape_matches = missing_layers == fallback_layers
        transient_shape_matches = (
            not missing_layers
            and recovered_layers == fallback_layers
            and fallback_layers.issubset(expected_success_layers)
        )
        if (fallback_shape_matches or transient_shape_matches) and (
            accepted_layers != expected_success_layers.union(fallback_layers)
            or set(metrics["layer_routes"]["unexpected_layer_ids"])
            or set(metrics["graph_observations"]["successful_gpu_completed_layer_ids"])
            != expected_success_layers
            or metrics["graph_observations"]["diagnostic_count"] <= 0
            or metrics["executor"]["local_fallback_count"]
                < len(fallback_layers)
            or typed_fallback_mismatch
        ):
            failures.append(
                "resolved material graph local fallback evidence mismatch"
            )
        elif fallback_shape_matches or transient_shape_matches:
            fallback_evidence_satisfied = True
        else:
            failures.append(
                "resolved material graph local fallback evidence mismatch"
            )
    elif (
        expected_fallback_layers is not None or expected_fallbacks is not None
    ) and not fallback_contract_valid:
        failures.append(
            "resolved material graph local fallback expectation invalid"
        )
    expectation = RESOLVED_MATERIAL_GRAPH_EXPECTATIONS[0]
    expects_evidence = expectation.matrix_key in sample
    if (
        not require_evidence
        and not expects_evidence
        and not expects_activation_evidence
        and not expects_effect_local_passthrough
        and not expects_effect_recovery
    ):
        return list(dict.fromkeys(failures))

    capability = metrics["capability"]
    executor = metrics["executor"]
    graph_observations = metrics["graph_observations"]
    if not capability["has_evidence"]:
        failures.append("resolved material graph capability evidence missing")
        return list(dict.fromkeys(failures))

    if expects_evidence:
        expected_layer_ids = sample[expectation.matrix_key]
        if not (
            isinstance(expected_layer_ids, list)
            and all(
                isinstance(layer_id, int) and not isinstance(layer_id, bool)
                and layer_id >= 0
                for layer_id in expected_layer_ids
            )
            and expected_layer_ids == sorted(set(expected_layer_ids))
        ):
            failures.append(
                "resolved material graph succeeded layer IDs expectation invalid"
            )
        elif metrics["succeeded_layer_ids"] != expected_layer_ids:
            failures.append(expectation.failure_message)

    expected_target_descriptor_counts = sample.get(
        "expected_resolved_material_graph_target_descriptor_counts"
    )
    if expected_target_descriptor_counts is not None:
        valid_target_descriptor_counts = (
            isinstance(expected_target_descriptor_counts, list)
            and all(
                isinstance(value, str)
                and re.fullmatch(
                    r"\d+x\d+/[A-Za-z0-9_-]+:\d+"
                    r"(?:,\d+x\d+/[A-Za-z0-9_-]+:\d+)*",
                    value,
                )
                for value in expected_target_descriptor_counts
            )
            and expected_target_descriptor_counts
                == sorted(set(expected_target_descriptor_counts))
        )
        if not valid_target_descriptor_counts:
            failures.append(
                "resolved material graph target descriptor expectation invalid"
            )
        elif graph_observations["target_descriptor_counts"] \
                != expected_target_descriptor_counts:
            failures.append(
                "resolved material graph target descriptor evidence mismatch"
            )

    expected_lifecycle = sample.get(
        "expected_resolved_material_graph_extent_lifecycle"
    )
    if expected_lifecycle is not None:
        lifecycle_keys = {
            "input_width", "input_height", "target_descriptor_counts",
            "history", "reset", "history_rehydrate_copy_count",
            "history_content_discarded",
        }
        valid_lifecycle = (
            isinstance(expected_lifecycle, dict)
            and set(expected_lifecycle) == {
                "layer_id", "anchors", "require_history_copy_on_write",
            }
            and isinstance(expected_lifecycle.get("layer_id"), int)
            and not isinstance(expected_lifecycle.get("layer_id"), bool)
            and expected_lifecycle.get("layer_id", -1) >= 0
            and isinstance(expected_lifecycle.get("anchors"), list)
            and len(expected_lifecycle.get("anchors", [])) >= 2
            and isinstance(
                expected_lifecycle.get("require_history_copy_on_write"), bool
            )
        )
        if valid_lifecycle:
            for anchor in expected_lifecycle["anchors"]:
                if (
                    not isinstance(anchor, dict)
                    or set(anchor) != lifecycle_keys
                    or not all(
                        isinstance(anchor[key], int)
                        and not isinstance(anchor[key], bool)
                        and anchor[key] >= (1 if key in {
                            "input_width", "input_height"
                        } else 0)
                        for key in (
                            "input_width", "input_height",
                            "history_rehydrate_copy_count",
                        )
                    )
                    or not isinstance(anchor["target_descriptor_counts"], str)
                    or re.fullmatch(
                        r"\d+x\d+/[A-Za-z0-9_-]+:\d+"
                        r"(?:,\d+x\d+/[A-Za-z0-9_-]+:\d+)*",
                        anchor["target_descriptor_counts"],
                    ) is None
                    or anchor["history"] not in {"none", "seeded", "reused"}
                    or anchor["reset"] not in {
                        "initial", "allocation-reprepare",
                        "allocation-rebind", "history-copy-on-write",
                    }
                    or not isinstance(anchor["history_content_discarded"], bool)
                ):
                    valid_lifecycle = False
                    break
        if not valid_lifecycle:
            failures.append(
                "resolved material graph extent lifecycle expectation invalid"
            )
        else:
            layer_id = expected_lifecycle["layer_id"]
            actual_anchors = [
                {key: observation[key] for key in lifecycle_keys}
                for observation in graph_observations["lifecycle_transitions"]
                if observation["layer_id"] == layer_id
            ]
            if actual_anchors != expected_lifecycle["anchors"]:
                failures.append(
                    "resolved material graph extent lifecycle evidence mismatch"
                )
            if (
                expected_lifecycle["require_history_copy_on_write"]
                and graph_observations["history_copy_on_write_count"] <= 0
            ):
                failures.append(
                    "resolved material graph history copy-on-write evidence missing"
                )

    if capability["accepted_count"] <= 0:
        if require_evidence and not (
            expects_evidence and metrics["zero_contract_succeeded"]
        ):
            failures.append(
                "resolved material graph execution has no admitted capability"
            )
        if expects_evidence and not metrics["zero_contract_succeeded"]:
            failures.append(
                "resolved material graph zero contract not satisfied"
            )
        return list(dict.fromkeys(failures))
    if not executor["has_evidence"]:
        failures.append("resolved material graph executor evidence missing")
        return list(dict.fromkeys(failures))
    if executor["claimed_count"] <= 0:
        failures.append("resolved material graph executor claimed count is zero")
    if executor["encoded_count"] <= 0:
        failures.append("resolved material graph executor encoded count is zero")
    if executor["gpu_encoded_count"] <= 0:
        failures.append("resolved material graph executor GPU encoded count is zero")
    if executor["failure_count"] != 0:
        failures.append("resolved material graph executor reported failures")
    if not graph_observations["has_evidence"]:
        failures.append("resolved material graph terminal evidence missing")
    program_required_layer_ids = set(
        metrics["exact_backend"].get("program_required_layer_ids", [])
    )
    if (
        (
            require_evidence
            or expects_evidence
            or expects_effect_local_passthrough
            or expects_effect_recovery
        )
        and program_required_layer_ids
        and graph_observations["program_successful_transaction_count"] < 2
    ):
        failures.append(
            "resolved material graph Program transaction count below two"
        )
    elif (
        (
            expects_activation_evidence
            or expects_effect_local_passthrough
            or expects_effect_recovery
            or (
                (require_evidence or expects_evidence)
                and not metrics["exact_backend"].get("required_layer_ids")
            )
        )
        and graph_observations["successful_transaction_count"] < 2
    ):
        failures.append(
            "resolved material graph successful transaction count below two"
        )
    if fallback_evidence_satisfied:
        failures = [
            failure for failure in failures
            if failure not in allowlisted_local_failures
        ]
    elif (require_evidence or expects_evidence) and not metrics[
        "execution_succeeded"
    ]:
        failures.append(
            "resolved material graph execution contract not satisfied"
        )
    return list(dict.fromkeys(failures))
