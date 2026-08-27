"""Graph-output publication assertions shared by benchmark tests."""

from __future__ import annotations

from typing import Any, Callable


def assert_named_provider_terminal(
    test_case: Any,
    *,
    benchmark: Any,
    graph_execution_observation: Callable[..., str],
    resolved_graph_exact_evidence: Callable[..., tuple[Any, Any]],
) -> None:
    preview_text = (
        "resolved material execution capabilities: "
        "schema=layer-graph-capability-v1 candidates=2 accepted=2 "
        "rejected=0 variantLimit=8\n"
        "resolved material execution capability: "
        "schema=layer-graph-route-v1 layer=67 status=accepted "
        "dependency=none dependencyReferences=0\n"
        "resolved material execution capability: "
        "schema=layer-graph-route-v1 layer=68 status=accepted "
        "dependency=external-primary dependencyReferences=1\n"
    )
    log_text = "\n".join([
        "resolved material runtime audit: schema=scene-graph-executor-v1 "
        "claimed=2 encoded=2 failures=0 deferred=0 pending=2 "
        "gpuEncoded=2 localFallbacks=0",
        "phase=named-target-capture layer=67 status=succeeded",
        graph_execution_observation(
            frame=10,
            layer=67,
            transaction="provider-10",
            trigger="first-frame+first-success+gpu-completed",
        ),
        graph_execution_observation(
            frame=11,
            layer=67,
            transaction="provider-11",
            trigger="next-frame+gpu-completed",
        ),
        graph_execution_observation(
            frame=10,
            layer=68,
            transaction="consumer-10",
            trigger="first-frame+first-success+gpu-completed",
        ),
        graph_execution_observation(
            frame=11,
            layer=68,
            transaction="consumer-11",
            trigger="next-frame+compositor-consume+gpu-completed",
            consumed=True,
        ),
    ])
    disposition, exact_execution = resolved_graph_exact_evidence([67, 68])
    metrics = benchmark.resolved_material_graph_execution_metrics(
        preview_text,
        log_text,
        effect_execution=exact_execution,
        static_disposition=disposition,
    )

    test_case.assertTrue(metrics["execution_succeeded"])
    test_case.assertEqual(metrics["validation_failures"], [])
    test_case.assertEqual(metrics["succeeded_layer_ids"], [67, 68])
    test_case.assertEqual(
        metrics["layer_routes"]["named_published_layer_ids"],
        [67],
    )
    test_case.assertEqual(
        metrics["layer_routes"]["compositor_consumed_layer_ids"],
        [68],
    )
    test_case.assertEqual(
        metrics["layer_routes"]["next_frame_layer_ids"],
        [67, 68],
    )
    test_case.assertEqual(
        metrics["layer_routes"]["missing_compositor_consumed_layer_ids"],
        [],
    )


def assert_visible_provider_requires_compositor_consumption(
    test_case: Any,
    *,
    benchmark: Any,
    graph_execution_observation: Callable[..., str],
    resolved_graph_exact_evidence: Callable[..., tuple[Any, Any]],
) -> None:
    preview_text = (
        "resolved material execution capabilities: "
        "schema=layer-graph-capability-v1 candidates=1 accepted=1 "
        "rejected=0 variantLimit=8\n"
        "resolved material execution capability: "
        "schema=layer-graph-route-v1 layer=67 status=accepted "
        "dependency=none dependencyReferences=0\n"
    )
    log_text = "\n".join([
        "resolved material runtime audit: schema=scene-graph-executor-v1 "
        "claimed=1 encoded=1 failures=0 deferred=0 pending=1 "
        "gpuEncoded=1 localFallbacks=0",
        "phase=visible-graph-output-publication layer=67 status=succeeded",
        graph_execution_observation(
            frame=10,
            layer=67,
            transaction="visible-provider-10",
            trigger=(
                "first-frame+first-success+compositor-consume+gpu-completed"
            ),
            consumed=True,
        ),
        graph_execution_observation(
            frame=11,
            layer=67,
            transaction="visible-provider-11",
            trigger="next-frame+compositor-consume+gpu-completed",
            consumed=True,
        ),
    ])
    disposition, exact_execution = resolved_graph_exact_evidence([67])
    metrics = benchmark.resolved_material_graph_execution_metrics(
        preview_text,
        log_text,
        effect_execution=exact_execution,
        static_disposition=disposition,
    )

    test_case.assertTrue(metrics["execution_succeeded"])
    test_case.assertEqual(metrics["validation_failures"], [])
    test_case.assertEqual(
        metrics["layer_routes"]["visible_graph_output_published_layer_ids"],
        [67],
    )
    test_case.assertEqual(
        metrics["layer_routes"]["compositor_consumed_layer_ids"],
        [67],
    )
    test_case.assertEqual(
        metrics["layer_routes"]["named_compositor_overlap_layer_ids"],
        [],
    )

    publication_only = benchmark.resolved_material_graph_execution_metrics(
        preview_text,
        "\n".join([
            "resolved material runtime audit: "
            "schema=scene-graph-executor-v1 claimed=1 encoded=1 "
            "failures=0 deferred=0 pending=1 gpuEncoded=1 localFallbacks=0",
            "phase=visible-graph-output-publication layer=67 status=succeeded",
            graph_execution_observation(
                frame=10,
                layer=67,
                transaction="publication-only-10",
                trigger="first-frame+first-success+gpu-completed",
            ),
            graph_execution_observation(
                frame=11,
                layer=67,
                transaction="publication-only-11",
                trigger="next-frame+gpu-completed",
            ),
        ]),
        effect_execution=exact_execution,
        static_disposition=disposition,
    )
    test_case.assertIn(
        "resolved material graph accepted layer compositor consumption missing",
        publication_only["validation_failures"],
    )


def assert_visible_publication_execution_metrics(
    test_case: Any,
    *,
    benchmark: Any,
) -> None:
    metrics = benchmark.visible_graph_output_publication_execution_metrics(
        "phase=visible-graph-output-publication layer=23 status=succeeded\n"
        "phase=visible-graph-output-publication layer=46 status=failed\n"
    )
    test_case.assertEqual(metrics["succeeded_layer_ids"], [23])
    test_case.assertEqual(metrics["failed_layer_ids"], [46])


def assert_named_graph_output_publication_has_one_terminal_owner(
    test_case: Any,
    *,
    benchmark: Any,
    graph_execution_observation: Callable[..., str],
    resolved_graph_exact_evidence: Callable[..., tuple[Any, Any]],
) -> None:
    preview_text = (
        "resolved material execution capabilities: "
        "schema=layer-graph-capability-v1 candidates=1 accepted=1 "
        "rejected=0 variantLimit=8\n"
        "resolved material execution capability: "
        "schema=layer-graph-route-v1 layer=67 status=accepted "
        "dependency=none dependencyReferences=0\n"
    )
    audit = (
        "resolved material runtime audit: schema=scene-graph-executor-v1 "
        "claimed=1 encoded=1 failures=0 deferred=0 pending=1 "
        "gpuEncoded=1 localFallbacks=0"
    )
    disposition, exact_execution = resolved_graph_exact_evidence([67])

    named_only_log = "\n".join([
        audit,
        "phase=named-graph-output-publication layer=67 status=succeeded",
        graph_execution_observation(
            frame=10,
            layer=67,
            transaction="named-output-10",
            trigger="first-frame+first-success+gpu-completed",
        ),
        graph_execution_observation(
            frame=11,
            layer=67,
            transaction="named-output-11",
            trigger="next-frame+gpu-completed",
        ),
    ])
    named_only = benchmark.resolved_material_graph_execution_metrics(
        preview_text,
        named_only_log,
        effect_execution=exact_execution,
        static_disposition=disposition,
    )
    test_case.assertTrue(named_only["execution_succeeded"])
    test_case.assertEqual(named_only["validation_failures"], [])
    test_case.assertEqual(
        named_only["layer_routes"]["named_published_layer_ids"], [67]
    )
    test_case.assertEqual(
        named_only["layer_routes"]["named_graph_output_published_layer_ids"],
        [67],
    )
    test_case.assertEqual(
        named_only["layer_routes"]["compositor_consumed_layer_ids"], []
    )

    overlapping_log = "\n".join([
        audit,
        "phase=named-graph-output-publication layer=67 status=succeeded",
        graph_execution_observation(
            frame=10,
            layer=67,
            transaction="named-overlap-10",
            trigger=(
                "first-frame+first-success+compositor-consume+gpu-completed"
            ),
            consumed=True,
        ),
        graph_execution_observation(
            frame=11,
            layer=67,
            transaction="named-overlap-11",
            trigger="next-frame+compositor-consume+gpu-completed",
            consumed=True,
        ),
    ])
    overlapping = benchmark.resolved_material_graph_execution_metrics(
        preview_text,
        overlapping_log,
        effect_execution=exact_execution,
        static_disposition=disposition,
    )
    test_case.assertFalse(overlapping["execution_succeeded"])
    test_case.assertEqual(
        overlapping["layer_routes"]["named_compositor_overlap_layer_ids"],
        [67],
    )
    test_case.assertIn(
        "resolved material graph named publication also consumed by compositor",
        overlapping["validation_failures"],
    )
