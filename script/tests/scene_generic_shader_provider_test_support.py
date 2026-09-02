"""Provider-backed and typed-slot assertions for the generic shader harness."""

from __future__ import annotations

import json
from pathlib import Path
import tempfile
import textwrap
from typing import Any

from scene_shader_compiler_artifact import ArtifactFailure


def assert_transform_abi_request_and_cache_namespaces(
    test_case: Any,
    *,
    cache_source: Path,
    vertex: str,
    fragment: str,
) -> None:
    request_source = cache_source.with_name(
        "SceneResolvedMaterialGenericShaderRequest.swift"
    )
    request_text = request_source.read_text(encoding="utf-8")
    cache_text = cache_source.read_text(encoding="utf-8")
    test_case.assertIn('"mwx-generic-shader-request-v10"', request_text)
    test_case.assertIn('"SceneGenericShaderPrograms-v9"', cache_text)
    test_case.assertNotIn('"mwx-generic-shader-request-v5"', request_text)
    test_case.assertNotIn('"SceneGenericShaderPrograms-v5"', cache_text)

    with tempfile.TemporaryDirectory(
        prefix="mwx-generic-artifact-test-"
    ) as directory:
        root = Path(directory)
        observed, _, cache, _ = test_case.run_harness(
            root, route="observe-only"
        )
        current_key = test_case.request_key(
            "mwx-generic-shader-request-v10", vertex, fragment
        )
        legacy_key = test_case.request_key(
            "mwx-generic-shader-request-v5", vertex, fragment
        )
        test_case.assertEqual(observed["requestKey"], current_key)
        test_case.assertNotEqual(current_key, legacy_key)
        stale = test_case.artifact(legacy_key)
        (cache / f"{legacy_key}.json").write_text(
            json.dumps(stale), encoding="utf-8"
        )
        unavailable, _, _, log = test_case.run_harness(
            root, route="prefer-generic"
        )
        test_case.assertEqual(unavailable["requestKey"], current_key)
        test_case.assertEqual(
            unavailable["code"],
            "compiler-configuration-licensebundleunavailable",
        )
        test_case.assertNotIn("artifact-invalid-json", log)


def assert_python_worker_rejects_typed_input_without_compatible_transfer(
    test_case: Any,
) -> None:
    with test_case.assertRaisesRegex(
        ArtifactFailure,
        "premultiplied-color-input-transfer",
    ):
        test_case.python_artifact(
            "typed-input-color-worker-request",
            premultiplied_color_input_slots=(1,),
        )


def assert_independent_signal_request_contract(
    test_case: Any,
    *,
    vertex: str,
    fragment: str,
) -> None:
    with tempfile.TemporaryDirectory(
        prefix="mwx-generic-independent-request-"
    ) as directory:
        root = Path(directory)
        observed, requests, _, _ = test_case.run_harness(
            root,
            route="observe-only",
            fragment=fragment,
        )
        request_path = requests / f"{observed['requestKey']}.json"
        request = json.loads(request_path.read_text(encoding="utf-8"))
        expected = ("independent-alpha-signal-preserving", 1)
        test_case.assertEqual(request["schemaVersion"], 5)
        test_case.assertEqual(request["premultipliedColorInputSlots"], [])
        test_case.assertEqual(request["expectedColorTransfer"], {
            "kind": expected[0], "slot": expected[1],
        })
        keyed = test_case.request_key(
            "mwx-generic-shader-request-v10",
            textwrap.dedent(vertex),
            textwrap.dedent(fragment),
            expected,
        )
        unresolved = test_case.request_key(
            "mwx-generic-shader-request-v10",
            textwrap.dedent(vertex),
            textwrap.dedent(fragment),
        )
        test_case.assertEqual(observed["requestKey"], keyed)
        test_case.assertNotEqual(keyed, unresolved)


def assert_provider_backed_spatial_weighted_profile(
    test_case: Any,
    *,
    vertex: str,
    fragment: str,
) -> None:
    profile = "provider-backed-graph-input-spatial-weighted-color-blend"
    facts = {
        "has_external_provider": True,
        "graph_input_slots": (0,),
        "spatial_weighted_source_slot": 0,
        "spatial_weighted_active_slots": (0, 1, 2),
        "spatial_weighted_typed_auxiliary_slots": (1, 2),
        "spatial_weighted_external_color_slot": 1,
    }
    with tempfile.TemporaryDirectory(
        prefix="mwx-provider-spatial-weighted-owner-route-test-"
    ) as directory:
        root = Path(directory)
        legacy_observed, requests, cache, observed_log = test_case.run_harness(
            root,
            route="observe-only",
            fragment=fragment,
            **facts,
        )
        test_case.assertEqual(legacy_observed["routeProfile"], profile)
        test_case.assertEqual(legacy_observed["routeState"], "generic-only")
        test_case.assertFalse(legacy_observed["permitsBoundedFrontend"])
        test_case.assertIn(
            f"state=generic-only profile={profile} outcome=rejected",
            observed_log,
        )

        request = json.loads(
            (requests / f"{legacy_observed['requestKey']}.json").read_text(
                encoding="utf-8"
            )
        )
        test_case.assertEqual(request["schemaVersion"], 5)
        test_case.assertEqual(request["premultipliedColorInputSlots"], [1])
        expected_key = test_case.request_key(
            "mwx-generic-shader-request-v10",
            textwrap.dedent(vertex),
            textwrap.dedent(fragment),
            premultiplied_color_input_slots=(1,),
        )
        empty_contract_key = test_case.request_key(
            "mwx-generic-shader-request-v10",
            textwrap.dedent(vertex),
            textwrap.dedent(fragment),
        )
        test_case.assertEqual(legacy_observed["requestKey"], expected_key)
        test_case.assertNotEqual(expected_key, empty_contract_key)

        artifact = test_case.artifact(
            legacy_observed["requestKey"],
            color_transfer="straight-alpha-preserving",
            auxiliary_channel_uses={1: "wholeVector", 2: "wholeVector"},
            premultiplied_color_input_slots=(1,),
        )
        artifact_path = cache / f"{legacy_observed['requestKey']}.json"
        artifact_path.write_text(json.dumps(artifact), encoding="utf-8")
        accepted, _, _, accepted_log = test_case.run_harness(
            root,
            route=None,
            fragment=fragment,
            **facts,
        )
        test_case.assertEqual(accepted["status"], "accepted")
        test_case.assertEqual(accepted["routeState"], "generic-only")
        test_case.assertEqual(accepted["backend"], "genericCompilerArtifact")
        test_case.assertIn(
            f"state=generic-only profile={profile} outcome=accepted",
            accepted_log,
        )

        legacy_disabled, _, _, legacy_disabled_log = test_case.run_harness(
            root,
            route="disable-generic",
            fragment=fragment,
            **facts,
        )
        test_case.assertEqual(legacy_disabled["status"], "accepted")
        test_case.assertEqual(legacy_disabled["routeState"], "generic-only")
        test_case.assertIn(
            f"state=generic-only profile={profile} outcome=accepted",
            legacy_disabled_log,
        )

        artifact["program"]["premultipliedColorInputSlots"] = []
        artifact_path.write_text(json.dumps(artifact), encoding="utf-8")
        mismatched, _, _, mismatch_log = test_case.run_harness(
            root,
            route=None,
            fragment=fragment,
            **facts,
        )
        test_case.assertEqual(mismatched["code"], "artifact-contract-rejected")
        test_case.assertFalse(mismatched["permitsBoundedFrontend"])
        test_case.assertEqual(mismatched["fallbackOwner"], "bounded-frontend")
        test_case.assertIn(
            f"state=generic-only profile={profile} outcome=rejected "
            "reason=artifact-contract-rejected",
            mismatch_log,
        )

        artifact["program"]["premultipliedColorInputSlots"] = [1]
        artifact["program"]["metalSourceSHA256"] = "0" * 64
        artifact_path.write_text(json.dumps(artifact), encoding="utf-8")
        rejected, _, _, rejected_log = test_case.run_harness(
            root,
            route=None,
            fragment=fragment,
            **facts,
        )
        test_case.assertEqual(rejected["code"], "artifact-contract-rejected")
        test_case.assertFalse(rejected["permitsBoundedFrontend"])
        test_case.assertIn(
            f"state=generic-only profile={profile} outcome=rejected "
            "reason=artifact-contract-rejected",
            rejected_log,
        )

        exact_rollback, _, _, rollback_log = test_case.run_harness(
            root,
            route=None,
            profile_routes=f"{profile}=disable-generic",
            fragment=fragment,
            **facts,
        )
        test_case.assertEqual(exact_rollback["code"], "route-disabled")
        test_case.assertTrue(exact_rollback["permitsBoundedFrontend"])
        test_case.assertEqual(
            exact_rollback["fallbackOwner"], "bounded-frontend"
        )
        test_case.assertIn(
            f"state=disable-generic profile={profile} outcome=fallback",
            rollback_log,
        )
