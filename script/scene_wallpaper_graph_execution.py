"""Join layer routes and graph execution and lifecycle observations."""

from __future__ import annotations

import re
from scene_wallpaper_effect_execution import effect_execution_metrics
from scene_wallpaper_effect_expectations import authored_deactivated_activation_identities
from scene_wallpaper_graph_output_metrics import (
    resolved_material_graph_observation_metrics, resolved_material_graph_output_metrics,
)
from scene_wallpaper_graph_subjects import (
    resolved_material_graph_exact_backend_metrics, resolved_material_graph_passthrough_metrics,
)
from scene_wallpaper_utility_capture import named_target_capture_execution_metrics
from typing import Any


RESOLVED_MATERIAL_LAYER_CAPABILITY_RE = re.compile(
    r"resolved material execution capabilities: "
    r"schema=layer-graph-capability-v1 "
    r"candidates=(?P<candidates>\d+) accepted=(?P<accepted>\d+) "
    r"rejected=(?P<rejected>\d+) variantLimit=(?P<variant_limit>\d+)(?=\s|$)"
)

RESOLVED_MATERIAL_LAYER_ROUTE_V1_RE = re.compile(
    r"resolved material execution capability: "
    r"schema=layer-graph-route-v1 layer=(?P<id>\d+) status=accepted"
)

RESOLVED_MATERIAL_LAYER_ROUTE_V2_RE = re.compile(
    r"resolved material execution capability: "
    r"schema=layer-graph-route-v1 layer=(?P<id>\d+) status=accepted "
    r"dependency=(?P<dependency>none|graph-internal|external-primary|external-aggregate) "
    r"dependencyReferences=(?P<dependency_references>\d+)"
)

DYNAMIC_LAYER_VISIBILITY_RE = re.compile(
    r"MWX dynamic layer visibility: "
    r"schema=dynamic-layer-visibility-v1 "
    r"frame=(?P<frame>\d+) generation=(?P<generation>\d+) "
    r"layer=(?P<id>\d+) "
    r"source=(?P<source>authored|userProperty|timeline|sceneScript) "
    r"value=(?P<value>true|false) effective=(?P<effective>true|false)(?=\s|$)",
)

RESOLVED_MATERIAL_SCENE_BACKGROUND_RE = re.compile(
    r"resolved material scene background: "
    r"schema=scene-background-provider-v1 layer=(?P<id>\d+) "
    r"effect=(?P<effect>\d+) node=(?P<node>\d+) slot=(?P<slot>\d+) "
    r"(?:bindings=(?P<bindings>\d+) )?"
    r"mode=same-frame-main-target"
)

RESOLVED_MATERIAL_GRAPH_EXECUTOR_RE = re.compile(
    r"resolved material runtime audit: schema=scene-graph-executor-v1 "
    r"claimed=(?P<claimed>\d+) encoded=(?P<encoded>\d+) "
    r"failures=(?P<failures>\d+) deferred=(?P<deferred>\d+) "
    r"pending=(?P<pending>\d+) gpuEncoded=(?P<gpu_encoded>\d+)"
    r"(?: localFallbacks=(?P<local_fallbacks>\d+))?(?=\s|$)"
)

RESOLVED_MATERIAL_GRAPH_LOCAL_FALLBACK_RE = re.compile(
    r"layer-local-fallback count=(?P<count>\d+) "
    r"entries=(?P<entries>\d+:[A-Za-z0-9._-]+"
    r"(?:,\d+:[A-Za-z0-9._-]+)*)"
    r"(?: frame=(?P<frame>\d+))?(?=\s|$)"
)

def resolved_material_graph_execution_metrics(
    preview_text: str,
    log_text: str,
    *,
    effect_execution: dict[str, Any] | None = None,
    static_disposition: dict[str, Any] | None = None,
    visible_graph_output_publication: dict[str, Any] | None = None,
    named_graph_output_publication: dict[str, Any] | None = None,
    execution_observations_enabled: bool = True,
) -> dict[str, Any]:
    graph_observations = resolved_material_graph_observation_metrics(log_text)
    capability_observations = [
        {
            "candidate_count": int(match.group("candidates")),
            "accepted_count": int(match.group("accepted")),
            "rejected_count": int(match.group("rejected")),
            "variant_limit": int(match.group("variant_limit")),
        }
        for match in RESOLVED_MATERIAL_LAYER_CAPABILITY_RE.finditer(preview_text)
    ]
    capability_failures: list[str] = []
    if (
        "schema=layer-graph-capability-v1" in preview_text
        and not capability_observations
    ):
        capability_failures.append(
            "resolved material graph capability evidence malformed"
        )
    capability_signatures = {
        tuple(observation.values()) for observation in capability_observations
    }
    if len(capability_signatures) > 1:
        capability_failures.append(
            "resolved material graph capability evidence conflicts"
        )
    for observation in capability_observations:
        if observation["candidate_count"] != (
            observation["accepted_count"] + observation["rejected_count"]
        ):
            capability_failures.append(
                "resolved material graph capability count conservation failed"
            )
        if observation["variant_limit"] <= 0:
            capability_failures.append(
                "resolved material graph capability variant limit invalid"
            )
    capability = capability_observations[-1] if capability_observations else None

    route_lines = [
        line.strip()
        for line in preview_text.splitlines()
        if "schema=layer-graph-route-v" in line
    ]
    accepted_layer_observations: list[int] = []
    route_schema_versions: list[str] = []
    malformed_route_count = 0
    for line in route_lines:
        current = RESOLVED_MATERIAL_LAYER_ROUTE_V2_RE.fullmatch(line)
        if current is not None:
            dependency = current.group("dependency")
            reference_count = int(current.group("dependency_references"))
            # Self dependencies remain graph-internal when their named reads
            # are shadowed by graph bindings; the producer then reports zero
            # effective references. Only external owners require a live slot.
            if (dependency == "none" and reference_count != 0) or (
                dependency in {"external-primary", "external-aggregate"}
                and reference_count == 0
            ):
                malformed_route_count += 1
                continue
            accepted_layer_observations.append(int(current.group("id")))
            route_schema_versions.append("layer-graph-route-v1")
            continue
        legacy = RESOLVED_MATERIAL_LAYER_ROUTE_V1_RE.fullmatch(line)
        if legacy is not None:
            accepted_layer_observations.append(int(legacy.group("id")))
            route_schema_versions.append("layer-graph-route-v1")
            continue
        malformed_route_count += 1
    accepted_layer_ids = sorted(set(accepted_layer_observations))
    accepted_layer_counts: dict[int, int] = {}
    for layer_id in accepted_layer_observations:
        accepted_layer_counts[layer_id] = accepted_layer_counts.get(layer_id, 0) + 1
    duplicate_accepted_layer_ids = sorted(
        layer_id
        for layer_id, count in accepted_layer_counts.items()
        if count > 1
    )
    if malformed_route_count:
        capability_failures.append(
            "resolved material graph accepted layer evidence malformed"
        )
    route_schema_version_set = set(route_schema_versions)
    if len(route_schema_version_set) > 1:
        capability_failures.append(
            "resolved material graph accepted layer evidence schema conflicts"
        )
    if duplicate_accepted_layer_ids:
        capability_failures.append(
            "resolved material graph accepted layer evidence duplicated"
        )
    if capability is None and accepted_layer_observations:
        capability_failures.append(
            "resolved material graph accepted layer evidence has no aggregate capability"
        )
    if capability is not None and (
        len(accepted_layer_observations) != capability["accepted_count"]
        or len(accepted_layer_ids) != capability["accepted_count"]
    ):
        capability_failures.append(
            "resolved material graph accepted layer count conservation failed"
        )

    visibility_lines = [
        line.strip()
        for line in log_text.splitlines()
        if "MWX dynamic layer visibility:" in line
    ]
    raw_visibility_records = [
        {
            "frame": int(match.group("frame")),
            "generation": int(match.group("generation")),
            "layer_id": int(match.group("id")),
            "source": match.group("source"),
            "value": match.group("value") == "true",
            "effective": match.group("effective") == "true",
        }
        for match in DYNAMIC_LAYER_VISIBILITY_RE.finditer(log_text)
    ]
    visibility_counts: dict[tuple[int, int, int], int] = {}
    latest_visibility_by_layer: dict[int, dict[str, Any]] = {}
    for record in raw_visibility_records:
        key = (record["frame"], record["generation"], record["layer_id"])
        visibility_counts[key] = visibility_counts.get(key, 0) + 1
        latest_visibility_by_layer[record["layer_id"]] = record
    duplicate_visibility_layer_ids = sorted(
        key[2] for key, count in visibility_counts.items()
        if count > 1
    )
    visibility_records = sorted(
        latest_visibility_by_layer.values(),
        key=lambda record: record["layer_id"],
    )
    malformed_visibility_count = (
        len(visibility_lines) - len(raw_visibility_records)
    )
    if malformed_visibility_count:
        capability_failures.append(
            "resolved material graph dynamic visibility evidence malformed"
        )
    if duplicate_visibility_layer_ids:
        capability_failures.append(
            "resolved material graph dynamic visibility evidence duplicated"
        )
    current_hidden_layer_ids = sorted({
        record["layer_id"] for record in visibility_records
        if record["effective"] is False
    })

    scene_background_lines = [
        line.strip()
        for line in preview_text.splitlines()
        if "schema=scene-background-provider-v1" in line
    ]
    scene_background_observations: list[dict[str, int]] = []
    malformed_scene_background_count = 0
    for line in scene_background_lines:
        current = RESOLVED_MATERIAL_SCENE_BACKGROUND_RE.fullmatch(line)
        if current is None:
            malformed_scene_background_count += 1
            continue
        scene_background_observations.append({
            "layer_id": int(current.group("id")),
            "effect_index": int(current.group("effect")),
            "node_index": int(current.group("node")),
            "slot": int(current.group("slot")),
            "binding_count": int(current.group("bindings") or "1"),
        })
    scene_background_layer_ids = sorted({
        value["layer_id"] for value in scene_background_observations
    })
    duplicate_scene_background_layer_ids = sorted(
        layer_id
        for layer_id in scene_background_layer_ids
        if sum(
            value["layer_id"] == layer_id
            for value in scene_background_observations
        ) > 1
    )
    unaccepted_scene_background_layer_ids = sorted(
        set(scene_background_layer_ids) - set(accepted_layer_ids)
    )
    if malformed_scene_background_count:
        capability_failures.append(
            "resolved material scene background evidence malformed"
        )
    if duplicate_scene_background_layer_ids:
        capability_failures.append(
            "resolved material scene background evidence duplicated"
        )
    if unaccepted_scene_background_layer_ids:
        capability_failures.append(
            "resolved material scene background layer not accepted"
        )

    executor_observations = [
        {
            "claimed": int(match.group("claimed")),
            "encoded": int(match.group("encoded")),
            "failures": int(match.group("failures")),
            "deferred": int(match.group("deferred")),
            "pending": int(match.group("pending")),
            "gpu_encoded": int(match.group("gpu_encoded")),
            "local_fallbacks": int(match.group("local_fallbacks") or 0),
        }
        for match in RESOLVED_MATERIAL_GRAPH_EXECUTOR_RE.finditer(log_text)
    ]
    executor_failures: list[str] = []
    local_fallback_observations: list[dict[str, Any]] = []
    local_fallback_lines = [
        line for line in log_text.splitlines()
        if "layer-local-fallback" in line
    ]
    for line in local_fallback_lines:
        match = RESOLVED_MATERIAL_GRAPH_LOCAL_FALLBACK_RE.search(line)
        if match is None:
            executor_failures.append(
                "resolved material graph local fallback evidence malformed"
            )
            continue
        entries: list[dict[str, Any]] = []
        for token in match.group("entries").split(","):
            layer, reason = token.split(":", 1)
            entries.append({
                "layer_id": int(layer),
                "reason": reason,
                "frame": (
                    int(match.group("frame"))
                    if match.group("frame") is not None else None
                ),
            })
        if (
            int(match.group("count")) != len(entries)
            or len({entry["layer_id"] for entry in entries}) != len(entries)
        ):
            executor_failures.append(
                "resolved material graph local fallback evidence malformed"
            )
            continue
        local_fallback_observations.extend(entries)
    local_fallbacks = sorted(
        {
            (entry["layer_id"], entry["reason"])
            for entry in local_fallback_observations
        }
    )
    if len({layer for layer, _ in local_fallbacks}) != len(local_fallbacks):
        executor_failures.append(
            "resolved material graph local fallback evidence conflicts"
        )
    if "schema=scene-graph-executor-v1" in log_text and not executor_observations:
        executor_failures.append(
            "resolved material graph executor evidence malformed"
        )
    for observation in executor_observations:
        if observation["encoded"] > observation["claimed"]:
            executor_failures.append(
                "resolved material graph executor claim conservation failed"
            )
        if observation["gpu_encoded"] != observation["encoded"]:
            executor_failures.append(
                "resolved material graph executor GPU encode conservation failed"
            )
        if (
            observation["failures"] == 0
            and observation["deferred"] == 0
            and observation["claimed"] != observation["encoded"]
        ):
            executor_failures.append(
                "resolved material graph executor successful claim conservation failed"
            )
        if observation["failures"] > 0:
            executor_failures.append(
                "resolved material graph executor reported failures"
            )

    claimed_count = sum(value["claimed"] for value in executor_observations)
    encoded_count = sum(value["encoded"] for value in executor_observations)
    failure_count = sum(value["failures"] for value in executor_observations)
    gpu_encoded_count = sum(
        value["gpu_encoded"] for value in executor_observations
    )
    local_fallback_count = sum(
        value["local_fallbacks"] for value in executor_observations
    )
    fallback_route_frames: dict[int, int] = {}
    for operation in (effect_execution or {}).get("route_operations", []):
        layer_id = operation.get("layer_id")
        frame_id = operation.get("frame_id")
        if (
            operation.get("operation") == "unclaimed-effect-product-authority"
            and operation.get("outcome") == "failed"
            and isinstance(layer_id, int)
            and isinstance(frame_id, int)
        ):
            fallback_route_frames[layer_id] = min(
                frame_id, fallback_route_frames.get(layer_id, frame_id)
            )
    for observation in local_fallback_observations:
        layer_id = observation["layer_id"]
        frame_id = observation["frame"]
        if frame_id is not None:
            fallback_route_frames[layer_id] = min(
                frame_id, fallback_route_frames.get(layer_id, frame_id)
            )
    transient_recovered_fallback_layer_ids = sorted(
        layer_id for layer_id, frame_id in fallback_route_frames.items()
        if (
            frame_id == 0 or any(
                value["layer_id"] == layer_id and value["frame"] < frame_id
                for value in graph_observations[
                    "terminal_success_observations"
                ]
            )
        ) and any(
            value["layer_id"] == layer_id and value["frame"] > frame_id
            for value in graph_observations["terminal_success_observations"]
        ) and any(
            value["layer_id"] == layer_id
            and value["frame"] > frame_id
            and "next-frame" in value["trigger"]
            for value in graph_observations["terminal_success_observations"]
        )
    )
    accepted_count = capability["accepted_count"] if capability else None
    observed_layer_ids = graph_observations[
        "successful_gpu_completed_layer_ids"
    ]
    program_observed_layer_ids = graph_observations[
        "program_successful_gpu_completed_layer_ids"
    ]
    compositor_consumed_layer_ids = graph_observations[
        "compositor_consumed_layer_ids"
    ]
    next_frame_layer_ids = graph_observations["next_frame_layer_ids"]
    program_next_frame_layer_ids = graph_observations[
        "program_next_frame_layer_ids"
    ]
    accepted_layer_set = set(accepted_layer_ids)
    dormant_layer_set = (
        accepted_layer_set.intersection(current_hidden_layer_ids)
    )
    execution_expected_layer_set = accepted_layer_set.difference(
        dormant_layer_set
    )
    execution_expected_layer_ids = sorted(execution_expected_layer_set)
    named_capture = named_target_capture_execution_metrics(log_text)
    graph_output = resolved_material_graph_output_metrics(
        accepted_layer_ids,
        graph_observations,
        named_capture,
        log_text,
        visible_graph_output_publication=(
            visible_graph_output_publication
        ),
        named_graph_output_publication=named_graph_output_publication,
    )
    named_published_layer_ids = graph_output[
        "named_published_layer_ids"
    ]
    visible_graph_output_published_layer_ids = graph_output[
        "visible_graph_output_published_layer_ids"
    ]
    named_graph_output_published_layer_ids = graph_output[
        "named_graph_output_published_layer_ids"
    ]
    output_consumed_layer_set = set(
        graph_output["output_consumed_layer_ids"]
    )
    program_output_consumed_layer_set = set(
        graph_output["program_output_consumed_layer_ids"]
    )
    named_compositor_overlap_layer_ids = graph_output[
        "named_compositor_overlap_layer_ids"
    ]
    if effect_execution is None:
        effect_execution = effect_execution_metrics(log_text, static_disposition)
    exact_backend = resolved_material_graph_exact_backend_metrics(
        execution_expected_layer_ids,
        effect_execution,
        static_disposition,
        graph_observations,
        dormant_layer_ids=set(dormant_layer_set),
        activation_dormant_identities=(
            authored_deactivated_activation_identities(log_text)
        ),
    )
    if execution_observations_enabled and (
        exact_backend["unjoined_cpu_effect_local_passthroughs"]
        or exact_backend["unjoined_graph_effect_local_passthroughs"]
        or exact_backend["missing_next_frame_effect_local_passthroughs"]
    ):
        capability_failures.append(
            "resolved material graph effect-local passthrough exact join failed"
        )
    if exact_backend["unproven_effect_local_passthroughs"]:
        capability_failures.append(
            "resolved material graph effect-local passthrough identity unproven"
        )
    if execution_observations_enabled and (
        exact_backend["mixed_program_missing_terminal_subjects"]
        or exact_backend["mixed_program_missing_next_frame_subjects"]
    ):
        capability_failures.append(
            "resolved material graph mixed Program exact subject join failed"
        )
    passthrough = resolved_material_graph_passthrough_metrics(
        execution_expected_layer_ids,
        graph_observations,
        static_disposition,
        execution_observations_enabled=execution_observations_enabled,
    )
    if capability is None and (
        executor_observations
        or graph_observations["observation_count"] > 0
        or exact_backend["resolved_backend_layer_ids"]
    ):
        capability_failures.append(
            "resolved material graph activity has no capability evidence"
        )
    missing_gpu_completed_layer_ids = sorted(
        execution_expected_layer_set.difference(observed_layer_ids)
    )
    dependency_consumed_provider_layer_ids = graph_observations[
        "dependency_consumed_provider_layer_ids"
    ]
    missing_compositor_consumed_layer_ids = sorted(
        execution_expected_layer_set
        .difference(named_published_layer_ids)
        # A layer whose typed dependency input a downstream execution
        # consumed is published through that dependency slot; its terminal
        # compositor consumption belongs to the consumer, not the provider.
        .difference(dependency_consumed_provider_layer_ids)
        .difference(compositor_consumed_layer_ids)
    )
    missing_next_frame_layer_ids = sorted(
        execution_expected_layer_set.difference(next_frame_layer_ids)
    )
    missing_exact_backend_layer_ids = exact_backend["missing_layer_ids"]
    missing_passthrough_layer_ids = sorted(
        execution_expected_layer_set.difference(
            passthrough["complete_layer_ids"]
        )
    )
    missing_layer_ids = sorted(
        set(missing_gpu_completed_layer_ids).union(
            missing_compositor_consumed_layer_ids,
            missing_next_frame_layer_ids,
            missing_exact_backend_layer_ids,
            missing_passthrough_layer_ids,
        )
    )
    unexpected_gpu_completed_layer_ids = sorted(
        set(observed_layer_ids).difference(accepted_layer_set)
    )
    unexpected_compositor_consumed_layer_ids = sorted(
        set(compositor_consumed_layer_ids).difference(accepted_layer_set)
    )
    unexpected_next_frame_layer_ids = sorted(
        set(next_frame_layer_ids).difference(accepted_layer_set)
    )
    unexpected_exact_backend_layer_ids = exact_backend["unexpected_layer_ids"]
    unexpected_layer_ids = sorted(
        set(unexpected_gpu_completed_layer_ids).union(
            unexpected_compositor_consumed_layer_ids,
            unexpected_next_frame_layer_ids,
            unexpected_exact_backend_layer_ids,
        )
    )
    if execution_observations_enabled and missing_gpu_completed_layer_ids:
        capability_failures.append(
            "resolved material graph accepted layer GPU completion missing"
        )
    if execution_observations_enabled and missing_compositor_consumed_layer_ids:
        capability_failures.append(
            "resolved material graph accepted layer compositor consumption missing"
        )
    if named_compositor_overlap_layer_ids:
        capability_failures.append(
            "resolved material graph named publication also consumed by compositor"
        )
    if execution_observations_enabled and missing_next_frame_layer_ids:
        capability_failures.append(
            "resolved material graph accepted layer next-frame evidence missing"
        )
    if execution_observations_enabled and missing_exact_backend_layer_ids:
        capability_failures.append(
            "resolved material graph accepted layer exact backend evidence missing"
        )
    if exact_backend["wrong_backend_layer_ids"]:
        capability_failures.append(
            "resolved material graph accepted layer exact backend mismatch"
        )
    if exact_backend["failed_layer_ids"]:
        capability_failures.append(
            "resolved material graph accepted layer exact execution failed"
        )
    if exact_backend["malformed_layer_ids"]:
        capability_failures.append(
            "resolved material graph accepted layer exact evidence malformed"
        )
    if unexpected_gpu_completed_layer_ids:
        capability_failures.append(
            "resolved material graph non-accepted layer GPU completion observed"
        )
    if unexpected_compositor_consumed_layer_ids:
        capability_failures.append(
            "resolved material graph non-accepted layer compositor consumption observed"
        )
    if unexpected_next_frame_layer_ids:
        capability_failures.append(
            "resolved material graph non-accepted layer next-frame observed"
        )
    if unexpected_exact_backend_layer_ids:
        capability_failures.append(
            "resolved material graph non-accepted layer exact backend observed"
        )
    if execution_observations_enabled and execution_expected_layer_ids:
        if not executor_observations:
            executor_failures.append(
                "resolved material graph executor evidence missing"
            )
        if claimed_count <= 0:
            executor_failures.append(
                "resolved material graph executor claimed count is zero"
            )
        if encoded_count <= 0:
            executor_failures.append(
                "resolved material graph executor encoded count is zero"
            )
        if gpu_encoded_count <= 0:
            executor_failures.append(
                "resolved material graph executor GPU encoded count is zero"
            )
        if not graph_observations["has_evidence"]:
            capability_failures.append(
                "resolved material graph terminal evidence missing"
            )
        elif graph_observations["successful_transaction_count"] < 2:
            capability_failures.append(
                "resolved material graph successful transaction count below two"
            )

    zero_executor_counters = bool(
        executor_observations
        and claimed_count == 0
        and encoded_count == 0
        and failure_count == 0
        and gpu_encoded_count == 0
        and all(
            observation["deferred"] == 0 and observation["pending"] == 0
            for observation in executor_observations
        )
    )
    validation_failures = (
        capability_failures
        + executor_failures
        + graph_observations["validation_failures"]
        + passthrough["validation_failures"]
    )
    if accepted_count == 0:
        if execution_observations_enabled and not executor_observations:
            validation_failures.append(
                "resolved material graph zero contract executor evidence missing"
            )
        elif executor_observations and not zero_executor_counters:
            validation_failures.append(
                "resolved material graph zero contract executor counters nonzero"
            )
        if graph_observations["observation_count"] > 0:
            validation_failures.append(
                "resolved material graph zero contract observed graph execution"
            )
    validation_failures = list(dict.fromkeys(validation_failures))
    exact_required_layer_ids = set(exact_backend["required_layer_ids"])
    passthrough_required_layer_ids = set(passthrough["required_layer_ids"])
    effect_local_passthrough_layer_ids = set(
        exact_backend["effect_local_passthrough_layer_ids"]
    )
    program_required_layer_ids = set(
        exact_backend["program_required_layer_ids"]
    )
    pure_program_layer_ids = program_required_layer_ids.difference(
        effect_local_passthrough_layer_ids,
        passthrough_required_layer_ids,
    )
    effect_local_only_layer_ids = effect_local_passthrough_layer_ids.difference(
        program_required_layer_ids
    )
    execution_observed_layer_ids = program_required_layer_ids.intersection(
        program_observed_layer_ids
    ).union(
        effect_local_only_layer_ids.intersection(observed_layer_ids),
        execution_expected_layer_set.difference(
            exact_required_layer_ids
        ).intersection(
            observed_layer_ids
        )
    )
    output_evidence_layer_ids = pure_program_layer_ids.intersection(
        program_output_consumed_layer_set
    ).union(
        execution_expected_layer_set.difference(
            pure_program_layer_ids
        ).intersection(
            output_consumed_layer_set
        ),
        # Same dependency-consumed exemption as the route-level missing
        # list: a provider whose typed dependency input a downstream
        # execution consumed publishes through that dependency slot, so
        # its output evidence is the downstream consumption.
        pure_program_layer_ids.intersection(
            dependency_consumed_provider_layer_ids
        )
    )
    next_frame_evidence_layer_ids = program_required_layer_ids.intersection(
        program_next_frame_layer_ids
    ).union(
        execution_expected_layer_set.difference(
            program_required_layer_ids
        ).intersection(
            next_frame_layer_ids
        )
    )
    succeeded_layer_ids = sorted(
        execution_expected_layer_set
        .intersection(execution_observed_layer_ids)
        .intersection(output_evidence_layer_ids)
        .intersection(next_frame_evidence_layer_ids)
        .intersection(exact_backend["complete_layer_ids"])
        .intersection(passthrough["complete_layer_ids"])
    )
    minimum_transactions_satisfied = (
        graph_observations["program_successful_transaction_count"] >= 2
        if program_required_layer_ids
        else graph_observations["successful_transaction_count"] >= 2
    )
    execution_succeeded = bool(
        execution_observations_enabled
        and capability is not None
        and execution_expected_layer_ids
        and executor_observations
        and claimed_count > 0
        and encoded_count > 0
        and gpu_encoded_count > 0
        and failure_count == 0
        and minimum_transactions_satisfied
        and succeeded_layer_ids == execution_expected_layer_ids
        and not missing_layer_ids
        and not unexpected_layer_ids
        and not validation_failures
    )
    route_evidence_complete = bool(
        capability is not None
        and len(accepted_layer_observations) == accepted_count
        and len(accepted_layer_ids) == accepted_count
        and not duplicate_accepted_layer_ids
        and malformed_route_count == 0
    )
    zero_contract_succeeded = bool(
        execution_observations_enabled
        and capability is not None
        and accepted_count == 0
        and route_evidence_complete
        and zero_executor_counters
        and graph_observations["observation_count"] == 0
        and not unexpected_layer_ids
        and not validation_failures
    )
    dormant_contract_succeeded = bool(
        execution_observations_enabled
        and capability is not None
        and accepted_count is not None
        and accepted_count > 0
        and not execution_expected_layer_ids
        and route_evidence_complete
        and zero_executor_counters
        and graph_observations["observation_count"] == 0
        and not unexpected_layer_ids
        and not validation_failures
    )
    has_evidence = bool(
        execution_observations_enabled
        and capability_observations
        and route_evidence_complete
        and executor_observations
        and (
            graph_observations["has_evidence"]
            and exact_backend["has_evidence"]
            and passthrough["has_evidence"]
            if execution_expected_layer_ids
            else graph_observations["observation_count"] == 0
        )
    )
    return {
        "execution_observations_enabled": execution_observations_enabled,
        "observation_status": "available" if has_evidence else "unavailable",
        "observation_unavailable_reason": (
            None if has_evidence else (
                "missing-or-incomplete" if execution_observations_enabled
                else "explicitly-disabled"
            )
        ),
        "has_evidence": has_evidence,
        "execution_succeeded": execution_succeeded,
        "zero_contract_succeeded": zero_contract_succeeded,
        "dormant_contract_succeeded": dormant_contract_succeeded,
        "contract_succeeded": (
            execution_succeeded
            or zero_contract_succeeded
            or dormant_contract_succeeded
        ),
        "succeeded_layer_ids": (
            succeeded_layer_ids if execution_observations_enabled else []
        ),
        "dynamic_visibility": {
            "has_evidence": bool(visibility_records),
            "schema_version": (
                "dynamic-layer-visibility-v1" if visibility_records else None
            ),
            "current_hidden_layer_ids": current_hidden_layer_ids,
            "ever_visible_layer_ids": sorted({
                record["layer_id"] for record in raw_visibility_records
                if record["effective"]
            }),
            "dormant_accepted_layer_ids": sorted(dormant_layer_set),
            "execution_expected_layer_ids": execution_expected_layer_ids,
            "duplicate_layer_ids": duplicate_visibility_layer_ids,
            "malformed_observation_count": malformed_visibility_count,
            "records": sorted(
                visibility_records, key=lambda record: record["layer_id"]
            ),
        },
        "capability": {
            "has_evidence": bool(capability_observations),
            "schema_version": (
                "layer-graph-capability-v1" if capability_observations else None
            ),
            "observation_count": len(capability_observations),
            "candidate_count": (
                capability["candidate_count"] if capability else None
            ),
            "accepted_count": accepted_count,
            "rejected_count": (
                capability["rejected_count"] if capability else None
            ),
            "variant_limit": capability["variant_limit"] if capability else None,
            "accepted_layer_ids": accepted_layer_ids,
            "accepted_layer_observation_count": len(accepted_layer_observations),
            "duplicate_accepted_layer_ids": duplicate_accepted_layer_ids,
            "malformed_route_observation_count": malformed_route_count,
        },
        "scene_background": {
            "has_evidence": bool(scene_background_observations),
            "schema_version": (
                "scene-background-provider-v1"
                if scene_background_observations else None
            ),
            "layer_ids": scene_background_layer_ids,
            "duplicate_layer_ids": duplicate_scene_background_layer_ids,
            "unaccepted_layer_ids": unaccepted_scene_background_layer_ids,
            "malformed_observation_count": malformed_scene_background_count,
            "observations": scene_background_observations,
        },
        "executor": {
            "has_evidence": bool(executor_observations),
            "schema_version": (
                "scene-graph-executor-v1" if executor_observations else None
            ),
            "observation_count": len(executor_observations),
            "claimed_count": claimed_count,
            "encoded_count": encoded_count,
            "failure_count": failure_count,
            "deferred_count": sum(
                value["deferred"] for value in executor_observations
            ),
            "pending_max": max(
                (value["pending"] for value in executor_observations),
                default=0,
            ),
            "gpu_encoded_count": gpu_encoded_count,
            "local_fallback_count": local_fallback_count,
            "local_fallbacks": [
                {"layer_id": layer, "reason": reason}
                for layer, reason in local_fallbacks
            ],
            "transient_recovered_fallback_layer_ids": (
                transient_recovered_fallback_layer_ids
            ),
            "observations": executor_observations,
        },
        "graph_observations": graph_observations,
        "exact_backend": exact_backend,
        "passthrough": passthrough,
        "layer_routes": {
            "has_evidence": route_evidence_complete,
            "schema_version": (
                next(iter(route_schema_version_set))
                if len(route_schema_version_set) == 1 else None
            ),
            "accepted_layer_ids": accepted_layer_ids,
            "observed_layer_ids": observed_layer_ids,
            "compositor_consumed_layer_ids": compositor_consumed_layer_ids,
            "named_published_layer_ids": named_published_layer_ids,
            "visible_graph_output_published_layer_ids": (
                visible_graph_output_published_layer_ids
            ),
            "named_graph_output_published_layer_ids": (
                named_graph_output_published_layer_ids
            ),
            "named_compositor_overlap_layer_ids": (
                named_compositor_overlap_layer_ids
            ),
            "next_frame_layer_ids": next_frame_layer_ids,
            "missing_layer_ids": missing_layer_ids,
            "missing_gpu_completed_layer_ids": missing_gpu_completed_layer_ids,
            "missing_compositor_consumed_layer_ids": (
                missing_compositor_consumed_layer_ids
            ),
            "missing_next_frame_layer_ids": missing_next_frame_layer_ids,
            "missing_exact_backend_layer_ids": missing_exact_backend_layer_ids,
            "unexpected_layer_ids": unexpected_layer_ids,
            "unexpected_gpu_completed_layer_ids": (
                unexpected_gpu_completed_layer_ids
            ),
            "unexpected_compositor_consumed_layer_ids": (
                unexpected_compositor_consumed_layer_ids
            ),
            "unexpected_next_frame_layer_ids": unexpected_next_frame_layer_ids,
            "unexpected_exact_backend_layer_ids": (
                unexpected_exact_backend_layer_ids
            ),
        },
        "validation_failures": validation_failures,
    }
