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

    # A provider whose published graph output a downstream execution
    # consumed through a typed dependency input satisfies the consumption
    # contract through that dependency edge; the terminal compositor
    # consumption belongs to the downstream consumer.
    dependency_consumed = benchmark.resolved_material_graph_execution_metrics(
        preview_text,
        "\n".join([
            "resolved material runtime audit: "
            "schema=scene-graph-executor-v1 claimed=1 encoded=1 "
            "failures=0 deferred=0 pending=1 gpuEncoded=1 localFallbacks=0",
            "phase=visible-graph-output-publication layer=67 status=succeeded",
            graph_execution_observation(
                frame=10,
                layer=67,
                transaction="dependency-consumed-10",
                trigger="first-frame+first-success+gpu-completed",
            ),
            graph_execution_observation(
                frame=11,
                layer=67,
                transaction="dependency-consumer-11",
                trigger="next-frame+compositor-consume+gpu-completed",
                consumed=True,
                dependency_providers=[67],
            ),
        ]),
        effect_execution=exact_execution,
        static_disposition=disposition,
    )
    test_case.assertEqual(dependency_consumed["validation_failures"], [])


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


def assert_utility_capture_respects_dormant_graph_members(
    test_case: Any, *, benchmark: Any,
    graph_execution_observation: Callable[..., str],
) -> None:
    """A prepared route is idle only with complete, never-active evidence."""
    preview = "\n".join([
        "utilityLayerCount: 2", "utilityCapturePlannedCount: 2",
        "utilityDependencyEdgeCount: 0", "utilityNamedConsumerCount: 0",
        "utilityNamedTargetPlannedCount: 0", "utilityNamedBindingPlannedCount: 0",
        "utilityNamedTargetGapCount: 0",
        "utility layer 101: capture kind=fullscreen trigger=101",
        "utility layer 265: capture kind=fullscreen trigger=265",
        "resolved material execution capabilities: "
        "schema=layer-graph-capability-v1 candidates=2 accepted=2 rejected=0 variantLimit=8",
        "resolved material execution capability: schema=layer-graph-route-v1 layer=101 status=accepted",
        "resolved material execution capability: schema=layer-graph-route-v1 layer=265 status=accepted",
    ])
    def visibility(layer: int, effective: bool, frame: int = 0) -> str:
        value = str(effective).lower()
        return ("MWX dynamic layer visibility: schema=dynamic-layer-visibility-v1 "
                f"frame={frame} generation={frame + 1} layer={layer} "
                f"source=userProperty value={value} effective={value}")
    visible = visibility(101, True)
    hidden = visibility(265, False)
    success = "phase=utility-capture layer=101 status=succeeded"
    below = "utility capture execution below planned count"
    reported = "utility capture execution reported failures"
    # No GPU is needed: these inputs exercise the actual producer parsers and
    # the same utility consumer invoked by run_sample.
    cases = [
        ("never-active prepared capture", preview, [visible, hidden, success], {}, []),
        ("visible capture missing", preview, [visible, hidden], {}, [below]),
        ("unrelated success cannot replace required identity", preview,
         [visible, hidden, "phase=utility-capture layer=999 status=succeeded"], {}, [below]),
        ("visibility missing", preview, [success], {}, [below]),
        ("visibility malformed", preview,
         [visible, hidden.replace("source=userProperty", "source=unknown"), success], {}, [below]),
        ("visibility duplicate", preview, [visible, hidden, hidden, success], {}, [below]),
        ("visible then hidden still owes capture", preview,
         [visible, visibility(265, True), visibility(265, False, 1), success], {}, [below]),
        ("hidden then visible owes capture", preview,
         [visible, hidden, visibility(265, True, 1), success], {}, [below]),
        ("capture survives later hiding", preview,
         [visible, visibility(265, True), visibility(265, False, 1), success,
          "phase=utility-capture layer=265 status=succeeded"], {}, []),
        ("dormant capture failure never exempt", preview,
         [visible, hidden, success, "phase=utility-capture layer=265 status=failed"], {}, [reported]),
        ("success never erases earlier failure", preview,
         [visible, hidden, "phase=utility-capture layer=101 status=failed", success], {}, [reported]),
        ("explicit requirement stronger than dormant", preview, [visible, hidden, success],
         {"required_utility_capture_succeeded_layer_ids": [265]},
         ["utility layer 265 capture should succeed"]),
        ("hidden graph execution proves activation", preview,
         [visible, hidden, success, graph_execution_observation(
             frame=1, layer=265, transaction="hidden-active-1",
             trigger="first-frame+first-success+gpu-completed")], {}, [below]),
        ("hidden nonterminal execution proves activation", preview,
         [visible, hidden, success, graph_execution_observation(
             frame=1, layer=265, transaction="hidden-first-success-1",
             trigger="first-frame+first-success", gpu_completion="-")], {}, [below]),
        ("hidden failed execution proves activation", preview,
         [visible, hidden, success, graph_execution_observation(
             frame=1, layer=265, transaction="hidden-failed-1",
             trigger="first-frame+failure", outcome="failed", gpu_completion="-")], {}, [below]),
        ("hidden GPU failure proves activation", preview,
         [visible, hidden, success, graph_execution_observation(
             frame=1, layer=265, transaction="hidden-gpu-failed-1",
             trigger="gpu-failed", gpu_completion="failed")], {}, [below]),
        ("malformed graph identity remains strict", preview,
         [visible, hidden, success, graph_execution_observation(
             frame=1, layer=265, transaction="hidden-malformed-1",
             trigger="first-success", gpu_completion="-").replace("layer=265", "layer=unknown")],
         {}, [below]),
        ("hidden named provider still owes capture", preview.replace(
            "utility layer 265: capture kind=fullscreen trigger=265",
            "utility layer 265: capture kind=fullscreen trigger=265; named target planned"),
         [visible, hidden, success], {}, [below]),
        ("hidden unaccepted layer not dormant", preview.replace(
            "candidates=2 accepted=2", "candidates=1 accepted=1").replace(
            "resolved material execution capability: schema=layer-graph-route-v1 layer=265 status=accepted", ""),
         [visible, hidden, success], {}, [below]),
        ("capture membership incomplete remains strict", preview.replace(
            "utility layer 265: capture kind=fullscreen trigger=265", ""),
         [visible, hidden, success], {}, [below]),
    ]
    for name, prepared, lines, sample, expected in cases:
        with test_case.subTest(utility_capture_case=name):
            log = "\n".join(lines)
            graph = benchmark.resolved_material_graph_execution_metrics(prepared, log)
            utility = benchmark.utility_runtime_metrics(prepared)
            capture = benchmark.utility_capture_execution_metrics(log)
            test_case.assertEqual(benchmark.utility_runtime_failures(
                sample, utility, capture_execution=capture, graph_execution=graph), expected)
            if name in {
                "hidden nonterminal execution proves activation",
                "hidden failed execution proves activation",
                "hidden GPU failure proves activation",
            }:
                test_case.assertEqual(graph["graph_observations"]["execution_observed_layer_ids"], [265])
                test_case.assertEqual(graph["graph_observations"]["successful_gpu_completed_layer_ids"], [])
            if name == "visible then hidden still owes capture":
                # Latest records intentionally retain only the final snapshot.
                # The existing visibility owner must preserve the earlier true.
                test_case.assertEqual(graph["dynamic_visibility"]["execution_expected_layer_ids"], [101])
                test_case.assertEqual(graph["dynamic_visibility"]["ever_visible_layer_ids"], [101, 265])
            if name == "never-active prepared capture":
                observations = graph["graph_observations"]
                projected = observations.pop("execution_observed_layer_ids", None)
                test_case.assertEqual(benchmark.utility_runtime_failures(
                    sample, utility, capture_execution=capture, graph_execution=graph), [below])
                observations["execution_observed_layer_ids"] = projected
                graph["dynamic_visibility"].pop("ever_visible_layer_ids")
                test_case.assertEqual(benchmark.utility_runtime_failures(
                    sample, utility, capture_execution=capture, graph_execution=graph), [below])
