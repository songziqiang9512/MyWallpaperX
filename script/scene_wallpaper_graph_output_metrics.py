"""Parse resolved-material graph and graph-output publication evidence."""

from __future__ import annotations

import re
from typing import Any
from urllib.parse import unquote


RESOLVED_MATERIAL_GRAPH_OBSERVATION_RE = re.compile(
    r"schema=1 axis=graph-execution (?P<fields>[^\r\n]+)"
)
VISIBLE_GRAPH_OUTPUT_PUBLICATION_EXECUTION_RE = re.compile(
    r"phase=visible-graph-output-publication layer=(?P<id>\d+) "
    r"status=(?P<status>succeeded|failed)"
)
NAMED_GRAPH_OUTPUT_PUBLICATION_EXECUTION_RE = re.compile(
    r"phase=named-graph-output-publication layer=(?P<id>\d+) "
    r"status=(?P<status>succeeded|failed)"
)


def _publication_execution_metrics(
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


def visible_graph_output_publication_execution_metrics(
    log_text: str,
) -> dict[str, Any]:
    return _publication_execution_metrics(
        log_text,
        VISIBLE_GRAPH_OUTPUT_PUBLICATION_EXECUTION_RE,
    )


def named_graph_output_publication_execution_metrics(
    log_text: str,
) -> dict[str, Any]:
    return _publication_execution_metrics(
        log_text,
        NAMED_GRAPH_OUTPUT_PUBLICATION_EXECUTION_RE,
    )


def resolved_material_graph_output_metrics(
    accepted_layer_ids: list[int],
    graph_observations: dict[str, Any],
    named_target_capture: dict[str, Any],
    log_text: str,
    *,
    visible_graph_output_publication: dict[str, Any] | None = None,
    named_graph_output_publication: dict[str, Any] | None = None,
) -> dict[str, list[int]]:
    """Classify terminal output without granting visible publication ownership."""
    accepted_layer_set = set(accepted_layer_ids)
    compositor_consumed_layer_ids = graph_observations[
        "compositor_consumed_layer_ids"
    ]
    program_compositor_consumed_layer_ids = graph_observations[
        "program_compositor_consumed_layer_ids"
    ]
    visible_graph_output_publication = (
        visible_graph_output_publication
        or visible_graph_output_publication_execution_metrics(log_text)
    )
    named_graph_output_publication = (
        named_graph_output_publication
        or named_graph_output_publication_execution_metrics(log_text)
    )
    clean_named_capture_layer_ids = set(
        named_target_capture["succeeded_layer_ids"]
    ).difference(named_target_capture["failed_layer_ids"])
    clean_visible_graph_output_layer_ids = set(
        visible_graph_output_publication["succeeded_layer_ids"]
    ).difference(visible_graph_output_publication["failed_layer_ids"])
    clean_named_graph_output_layer_ids = set(
        named_graph_output_publication["succeeded_layer_ids"]
    ).difference(named_graph_output_publication["failed_layer_ids"])

    named_output_layer_ids = clean_named_capture_layer_ids.union(
        clean_named_graph_output_layer_ids
    )
    named_published_layer_ids = sorted(
        accepted_layer_set
        .intersection(named_output_layer_ids)
        .difference(compositor_consumed_layer_ids)
    )
    return {
        "named_published_layer_ids": named_published_layer_ids,
        "visible_graph_output_published_layer_ids": sorted(
            accepted_layer_set.intersection(
                clean_visible_graph_output_layer_ids
            )
        ),
        "named_graph_output_published_layer_ids": sorted(
            accepted_layer_set.intersection(
                clean_named_graph_output_layer_ids
            )
        ),
        "output_consumed_layer_ids": sorted(
            set(compositor_consumed_layer_ids).union(
                named_published_layer_ids
            )
        ),
        "program_output_consumed_layer_ids": sorted(
            set(program_compositor_consumed_layer_ids).union(
                named_published_layer_ids
            )
        ),
        "named_compositor_overlap_layer_ids": sorted(
            accepted_layer_set
            .intersection(named_output_layer_ids)
            .intersection(compositor_consumed_layer_ids)
        ),
    }


def resolved_material_graph_observation_metrics(
    log_text: str,
) -> dict[str, Any]:
    payloads = [
        match.group("fields").strip()
        for match in RESOLVED_MATERIAL_GRAPH_OBSERVATION_RE.finditer(log_text)
    ]
    validation_failures: list[str] = []
    terminal_successes: list[dict[str, Any]] = []
    diagnostic_count = 0
    failed_outcome_count = 0
    gpu_failed_count = 0
    if "schema=1 axis=graph-execution" in log_text and not payloads:
        validation_failures.append(
            "resolved material graph observation evidence malformed"
        )

    count_fields = {
        "authored_nodes": "authoredNodes",
        "material_nodes": "materialNodes",
        "copy_nodes": "copyNodes",
        "swap_nodes": "swapNodes",
        "compose_nodes": "composeNodes",
        "rejected_nodes": "rejectedNodes",
    }
    required_fields = {
        "frame", "layer", "trigger", "transaction", *count_fields.values(),
        "allocationGeneration", "mappingGeneration",
        "mappingBeforeSHA256", "mappingAfterSHA256",
        "targetDescriptorsSHA256", "targetDescriptorCounts",
        "inputWidth", "inputHeight", "historyRehydrateCopyCount",
        "historyContentDiscarded", "history", "reset",
        "finalOutput", "physicalIdentity", "publication",
        "publicationGeneration", "compositorConsumed", "outcome",
        "gpuCompletion",
    }
    for payload in payloads:
        tokens = [token.split("=", 1) for token in payload.split() if "=" in token]
        fields = {key: value for key, value in tokens if key and value}
        malformed = len(tokens) != len(payload.split()) or len(fields) != len(tokens)
        trigger = fields.get("trigger", "")
        if "diagnostic" in fields:
            diagnostic_count += 1
            continue
        if malformed or not required_fields.issubset(fields):
            validation_failures.append(
                "resolved material graph observation evidence malformed"
            )
            continue
        outcome = fields["outcome"]
        gpu_completion = fields["gpuCompletion"]
        if outcome == "failed":
            failed_outcome_count += 1
        elif outcome != "succeeded":
            validation_failures.append(
                "resolved material graph observation outcome invalid"
            )
        if gpu_completion == "failed":
            gpu_failed_count += 1
        elif gpu_completion not in {"completed", "-"}:
            validation_failures.append(
                "resolved material graph observation GPU completion invalid"
            )
        if outcome != "succeeded" or gpu_completion != "completed":
            continue

        try:
            counts = {
                key: int(fields[field]) for key, field in count_fields.items()
            }
            frame = int(fields["frame"])
            layer_id = int(fields["layer"])
            effect_index = (
                int(fields["effect"]) if "effect" in fields else None
            )
            allocation_generation = int(fields["allocationGeneration"])
            mapping_generation = int(fields["mappingGeneration"])
            publication_generation = int(fields["publicationGeneration"])
            input_width = int(fields["inputWidth"])
            input_height = int(fields["inputHeight"])
            history_rehydrate_copy_count = int(
                fields["historyRehydrateCopyCount"]
            )
        except ValueError:
            validation_failures.append(
                "resolved material graph observation evidence malformed"
            )
            continue
        outputs = (
            fields["finalOutput"], fields["physicalIdentity"], fields["publication"]
        )
        target_descriptors_sha256 = fields["targetDescriptorsSHA256"]
        target_descriptor_counts = unquote(fields["targetDescriptorCounts"])
        descriptor_id = (
            unquote(fields["descriptor"])
            if "descriptor" in fields else None
        )
        exact_effect_identity_complete = (
            (effect_index is None) == (descriptor_id is None)
        )
        history = fields["history"]
        reset = fields["reset"]
        runtime_instance_identity = fields.get("runtime", "legacy")
        history_content_discarded = fields["historyContentDiscarded"] == "true"
        descriptor_counts_valid = target_descriptor_counts == "-" or bool(
            re.fullmatch(
                r"\d+x\d+/[A-Za-z0-9_-]+:\d+"
                r"(?:,\d+x\d+/[A-Za-z0-9_-]+:\d+)*",
                target_descriptor_counts,
            )
        )
        descriptor_hash_valid = (
            target_descriptors_sha256 == "-"
            if target_descriptor_counts == "-"
            else bool(re.fullmatch(r"[0-9a-f]{64}", target_descriptors_sha256))
        )
        program_identity = unquote(fields.get("program", ""))
        rejected_passthrough_shape = (
            counts["rejected_nodes"] == counts["authored_nodes"]
            and counts["authored_nodes"] > 0
            and counts["material_nodes"] == 0
            and counts["copy_nodes"] == 0
            and counts["swap_nodes"] == 0
            and counts["compose_nodes"] == 0
        )
        activation_passthrough = rejected_passthrough_shape and (
            program_identity.startswith("activation-passthrough:")
        )
        visual_failure_reason = program_identity.removeprefix(
            "visual-failure-passthrough:"
        )
        visual_failure_passthrough = (
            rejected_passthrough_shape
            and program_identity.startswith("visual-failure-passthrough:")
            and effect_index is not None
            and descriptor_id is not None
            and re.fullmatch(r"[A-Za-z0-9._-]+", visual_failure_reason)
                is not None
        )
        successful_rejected_passthrough = (
            activation_passthrough or visual_failure_passthrough
        )
        terminal_failures = [
            message for valid, message in (
                (
                    runtime_instance_identity == "legacy" or bool(re.fullmatch(
                        r"[A-Za-z0-9._:-]+", runtime_instance_identity
                    )),
                    "resolved material graph runtime identity invalid",
                ),
                (
                    layer_id >= 0 and all(value >= 0 for value in counts.values()),
                    "resolved material graph observation node count invalid",
                ),
                (
                    exact_effect_identity_complete
                    and (effect_index is None or effect_index >= 0)
                    and (descriptor_id is None or bool(descriptor_id)),
                    "resolved material graph effect identity invalid",
                ),
                (
                    counts["rejected_nodes"] == 0
                    or successful_rejected_passthrough,
                    "resolved material graph observation rejected nodes are nonzero",
                ),
                (
                    counts["authored_nodes"] == counts["material_nodes"]
                    + counts["copy_nodes"] + counts["swap_nodes"]
                    or successful_rejected_passthrough,
                    "resolved material graph observation node conservation failed",
                ),
                (
                    counts["compose_nodes"] <= counts["material_nodes"],
                    "resolved material graph observation compose count invalid",
                ),
                (
                    fields["transaction"] != "-" and "-" not in outputs,
                    "resolved material graph observation final publication missing",
                ),
                (
                    publication_generation > 0,
                    "resolved material graph observation publication generation invalid",
                ),
                (
                    allocation_generation > 0 and mapping_generation > 0,
                    "resolved material graph lifecycle generation invalid",
                ),
                (
                    input_width > 0 and input_height > 0,
                    "resolved material graph input extent invalid",
                ),
                (
                    history_rehydrate_copy_count >= 0
                    and fields["historyContentDiscarded"] in {"true", "false"}
                    and not (
                        history_rehydrate_copy_count > 0
                        and history_content_discarded
                    ),
                    "resolved material graph history lifecycle invalid",
                ),
                (
                    history in {"none", "seeded", "reused"},
                    "resolved material graph history state invalid",
                ),
                (
                    reset in {
                        "-", "initial", "scene-switch", "surface-stop",
                        "allocation-reprepare", "allocation-rebind",
                        "history-copy-on-write", "effect-reparse",
                        "device-loss", "executor-invalidation",
                    },
                    "resolved material graph reset reason invalid",
                ),
                (
                    all(
                        re.fullmatch(r"[0-9a-f]{64}", fields[name])
                        for name in ("mappingBeforeSHA256", "mappingAfterSHA256")
                    ),
                    "resolved material graph mapping evidence invalid",
                ),
                (
                    fields["compositorConsumed"] in {"true", "false"},
                    "resolved material graph observation compositor state invalid",
                ),
                (
                    descriptor_counts_valid and descriptor_hash_valid,
                    "resolved material graph target descriptor evidence invalid",
                ),
            ) if not valid
        ]
        validation_failures.extend(terminal_failures)
        if terminal_failures:
            continue
        terminal_successes.append({
            "runtime_instance_identity": runtime_instance_identity,
            "frame": frame,
            "layer_id": layer_id,
            "effect_index": effect_index,
            "descriptor_id": descriptor_id,
            "trigger": trigger.split("+"),
            "transaction": fields["transaction"],
            "program_identity": program_identity,
            "activation_passthrough": activation_passthrough,
            "visual_failure_passthrough": visual_failure_passthrough,
            **counts,
            "final_output": outputs[0],
            "final_physical": outputs[1],
            "final_publication": outputs[2],
            "publication_generation": publication_generation,
            "allocation_generation": allocation_generation,
            "mapping_generation": mapping_generation,
            "mapping_before_sha256": fields["mappingBeforeSHA256"],
            "mapping_after_sha256": fields["mappingAfterSHA256"],
            "compositor_consumed": fields["compositorConsumed"] == "true",
            "outcome": outcome,
            "gpu_completion": gpu_completion,
            "target_descriptors_sha256": target_descriptors_sha256,
            "target_descriptor_counts": target_descriptor_counts,
            "input_width": input_width,
            "input_height": input_height,
            "history": history,
            "reset": reset,
            "history_rehydrate_copy_count": history_rehydrate_copy_count,
            "history_content_discarded": history_content_discarded,
        })

    if diagnostic_count:
        validation_failures.append(
            "resolved material graph observation diagnostic reported"
        )
    if failed_outcome_count:
        validation_failures.append(
            "resolved material graph observation failed outcome reported"
        )
    if gpu_failed_count:
        validation_failures.append(
            "resolved material graph observation GPU failure reported"
        )
    program_terminal_successes = [
        observation for observation in terminal_successes
        if not observation["activation_passthrough"]
        and not observation["visual_failure_passthrough"]
    ]
    activation_terminal_successes = [
        observation for observation in terminal_successes
        if observation["activation_passthrough"]
    ]
    visual_failure_terminal_successes = [
        observation for observation in terminal_successes
        if observation["visual_failure_passthrough"]
    ]
    visual_failure_passthroughs = [
        {
            "layer_id": layer_id,
            "effect_index": effect_index,
            "descriptor_id": descriptor_id,
            "reason": reason,
        }
        for layer_id, effect_index, descriptor_id, reason in sorted({
            (
                observation["layer_id"],
                observation["effect_index"],
                observation["descriptor_id"],
                observation["program_identity"].removeprefix(
                    "visual-failure-passthrough:"
                ),
            )
            for observation in visual_failure_terminal_successes
        }, key=lambda value: (
            value[0],
            -1 if value[1] is None else value[1],
            "" if value[2] is None else value[2],
            value[3],
        ))
    ]
    visual_failure_passthrough_next_frame_subjects = [
        {
            "layer_id": layer_id,
            "effect_index": effect_index,
            "descriptor_id": descriptor_id,
            "reason": reason,
        }
        for layer_id, effect_index, descriptor_id, reason in sorted({
            (
                observation["layer_id"],
                observation["effect_index"],
                observation["descriptor_id"],
                observation["program_identity"].removeprefix(
                    "visual-failure-passthrough:"
                ),
            )
            for observation in visual_failure_terminal_successes
            if "next-frame" in observation["trigger"]
        })
    ]
    program_effect_subjects = [
        {
            "layer_id": layer_id,
            "effect_index": effect_index,
            "descriptor_id": descriptor_id,
        }
        for layer_id, effect_index, descriptor_id in sorted({
            (
                observation["layer_id"],
                observation["effect_index"],
                observation["descriptor_id"],
            )
            for observation in program_terminal_successes
            if observation["effect_index"] is not None
            and observation["descriptor_id"] is not None
        })
    ]
    program_next_frame_effect_subjects = [
        {
            "layer_id": layer_id,
            "effect_index": effect_index,
            "descriptor_id": descriptor_id,
        }
        for layer_id, effect_index, descriptor_id in sorted({
            (
                observation["layer_id"],
                observation["effect_index"],
                observation["descriptor_id"],
            )
            for observation in program_terminal_successes
            if observation["effect_index"] is not None
            and observation["descriptor_id"] is not None
            and "next-frame" in observation["trigger"]
        })
    ]
    successful_transactions = sorted({
        observation["transaction"]
            if observation["runtime_instance_identity"] == "legacy"
            else (
                observation["runtime_instance_identity"]
                + ":" + observation["transaction"]
            )
        for observation in terminal_successes
    })
    program_successful_transactions = sorted({
        observation["transaction"]
            if observation["runtime_instance_identity"] == "legacy"
            else (
                observation["runtime_instance_identity"]
                + ":" + observation["transaction"]
            )
        for observation in program_terminal_successes
    })
    runtime_instance_identities = sorted({
        observation["runtime_instance_identity"]
        for observation in terminal_successes
    })
    successful_layer_ids = sorted({
        observation["layer_id"] for observation in terminal_successes
    })
    program_successful_layer_ids = sorted({
        observation["layer_id"] for observation in program_terminal_successes
    })
    compositor_consumed_layer_ids = sorted({
        observation["layer_id"]
        for observation in terminal_successes
        if observation["compositor_consumed"]
    })
    next_frame_layer_ids = sorted({
        observation["layer_id"]
        for observation in terminal_successes
        if "next-frame" in observation["trigger"]
    })
    program_compositor_consumed_layer_ids = sorted({
        observation["layer_id"]
        for observation in program_terminal_successes
        if observation["compositor_consumed"]
    })
    program_next_frame_layer_ids = sorted({
        observation["layer_id"]
        for observation in program_terminal_successes
        if "next-frame" in observation["trigger"]
    })
    target_descriptor_counts = sorted({
        observation["target_descriptor_counts"]
        for observation in terminal_successes
        if observation["target_descriptor_counts"] != "-"
    })
    lifecycle_transitions: list[dict[str, Any]] = []
    history_copy_on_write_count = 0
    lifecycle_subjects = sorted({
        (
            observation["runtime_instance_identity"],
            observation["layer_id"],
            observation["effect_index"],
            observation["descriptor_id"],
        )
        for observation in terminal_successes
    }, key=lambda value: (
        value[0], value[1],
        -1 if value[2] is None else value[2],
        "" if value[3] is None else value[3],
    ))
    for (
        runtime_instance_identity, layer_id, effect_index, descriptor_id
    ) in lifecycle_subjects:
        previous: dict[str, Any] | None = None
        for observation in sorted(
            (
                value for value in terminal_successes
                if value["runtime_instance_identity"] == runtime_instance_identity
                and value["layer_id"] == layer_id
                and value["effect_index"] == effect_index
                and value["descriptor_id"] == descriptor_id
            ),
            key=lambda value: (value["frame"], value["transaction"]),
        ):
            reset = observation["reset"]
            signature = (
                observation["input_width"], observation["input_height"],
                observation["target_descriptors_sha256"],
                observation["target_descriptor_counts"],
            )
            if previous is None or signature != (
                previous["input_width"], previous["input_height"],
                previous["target_descriptors_sha256"],
                previous["target_descriptor_counts"],
            ):
                lifecycle_transitions.append(observation)
            if reset == "history-copy-on-write":
                history_copy_on_write_count += 1
                valid = (
                    previous is not None
                    and signature == (
                        previous["input_width"], previous["input_height"],
                        previous["target_descriptors_sha256"],
                        previous["target_descriptor_counts"],
                    )
                    and observation["history"] == "reused"
                    and observation["history_rehydrate_copy_count"] > 0
                    and not observation["history_content_discarded"]
                )
                if not valid:
                    validation_failures.append(
                        "resolved material graph history copy-on-write transition invalid"
                    )
            elif reset == "allocation-reprepare":
                valid = previous is not None and signature != (
                    previous["input_width"], previous["input_height"],
                    previous["target_descriptors_sha256"],
                    previous["target_descriptor_counts"],
                )
                if not valid:
                    validation_failures.append(
                        "resolved material graph allocation reprepare transition invalid"
                    )
            elif reset == "allocation-rebind":
                valid = (
                    previous is not None
                    and signature == (
                        previous["input_width"], previous["input_height"],
                        previous["target_descriptors_sha256"],
                        previous["target_descriptor_counts"],
                    )
                    and observation["history_rehydrate_copy_count"] == 0
                    and not observation["history_content_discarded"]
                )
                if not valid:
                    validation_failures.append(
                        "resolved material graph allocation rebind transition invalid"
                    )
            if reset in {
                "history-copy-on-write", "allocation-reprepare", "allocation-rebind"
            } and previous is not None:
                if not (
                    observation["allocation_generation"]
                        > previous["allocation_generation"]
                    and observation["mapping_generation"]
                        > previous["mapping_generation"]
                    and observation["final_physical"] != previous["final_physical"]
                    and observation["final_publication"]
                        != previous["final_publication"]
                ):
                    validation_failures.append(
                        "resolved material graph allocation identity transition invalid"
                    )
            previous = observation
    return {
        "has_evidence": bool(payloads),
        "schema_version": 1 if payloads else None,
        "observation_count": len(payloads),
        "terminal_success_count": len(terminal_successes),
        "successful_transaction_count": len(successful_transactions),
        "successful_transactions": successful_transactions,
        "program_terminal_success_count": len(program_terminal_successes),
        "program_successful_transaction_count": len(
            program_successful_transactions
        ),
        "program_successful_transactions": program_successful_transactions,
        "runtime_instance_identities": runtime_instance_identities,
        "runtime_instance_identity_count": len(runtime_instance_identities),
        "successful_gpu_completed_layer_ids": successful_layer_ids,
        "program_successful_gpu_completed_layer_ids": (
            program_successful_layer_ids
        ),
        "compositor_consumed_layer_ids": compositor_consumed_layer_ids,
        "program_compositor_consumed_layer_ids": (
            program_compositor_consumed_layer_ids
        ),
        "next_frame_layer_ids": next_frame_layer_ids,
        "program_next_frame_layer_ids": program_next_frame_layer_ids,
        "next_frame_observed": bool(next_frame_layer_ids),
        "target_descriptor_counts": target_descriptor_counts,
        "lifecycle_transitions": lifecycle_transitions,
        "history_copy_on_write_count": history_copy_on_write_count,
        "activation_passthrough_count": sum(
            observation["activation_passthrough"]
            for observation in terminal_successes
        ),
        "activation_passthrough_reason_codes": sorted({
            observation["program_identity"].removeprefix(
                "activation-passthrough:"
            )
            for observation in activation_terminal_successes
        }),
        "visual_failure_passthrough_count": len(
            visual_failure_terminal_successes
        ),
        "visual_failure_passthroughs": visual_failure_passthroughs,
        "visual_failure_passthrough_next_frame_subjects": (
            visual_failure_passthrough_next_frame_subjects
        ),
        "program_effect_subjects": program_effect_subjects,
        "program_next_frame_effect_subjects": (
            program_next_frame_effect_subjects
        ),
        "terminal_compositor_consume_observed": any(
            observation["compositor_consumed"] for observation in terminal_successes
        ),
        "diagnostic_count": diagnostic_count,
        "failed_outcome_count": failed_outcome_count,
        "gpu_failed_count": gpu_failed_count,
        "terminal_success_observations": terminal_successes,
        "validation_failures": list(dict.fromkeys(validation_failures)),
    }
