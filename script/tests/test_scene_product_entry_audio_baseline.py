#!/usr/bin/env python3

from __future__ import annotations

import base64
import contextlib
import io
import json
import stat
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

import scene_product_entry_audio_baseline as baseline
import scene_wallpaper_benchmark as benchmark


def particle_audio_event(
    *,
    path: str = "particles/audio.json",
    layer: int = 1,
    component: str = "emitter",
    index: int = 0,
    generation: int = 1,
    channel: int = 3,
    frequency_start: int = 0,
    frequency_end: int = 1,
    selected_nonzero: int = 1,
    route: str = "generic-only",
    trailing: str = "",
) -> str:
    encoded_path = base64.b64encode(path.encode("utf-8")).decode("ascii")
    return (
        "MWX particle audio: consumer=particle-component "
        f"layer={layer} pathBase64={encoded_path} component={component} "
        f"index={index} generation={generation} channel={channel} "
        f"frequencyStart={frequency_start} frequencyEnd={frequency_end} "
        f"selectedNonZero={selected_nonzero} route={route}{trailing}"
    )


def successful_payload(sample_id: str = "123") -> dict[str, object]:
    return {
        "sampleID": sample_id,
        "launchEntry": "steam-workshop-product",
        "launchPhase": "launched",
        "activeRecordID": "debug-scene-daemon-client",
        "stableDaemonClientRequested": True,
        "startupPropertyOverrides": {},
        "firstPresentCount": 1,
        "firstPresentRecordIDs": ["debug-scene-daemon-client"],
        "uniqueRequestCount": 1,
        "audioSpectrumDemanded": True,
        "audioSpectrumScopeEpoch": 1,
        "audioSpectrumPublicationCount": 2,
        "audioSpectrumPublicationPeaks": [0.25, 0.5],
        "latestStats": {"rendered": 12},
        "failures": [],
    }


class SceneProductEntryAudioBaselineTests(unittest.TestCase):
    def test_existing_benchmark_exposes_product_entry_audio_mode(self) -> None:
        previous = sys.argv
        try:
            sys.argv = [
                "scene_wallpaper_benchmark.py",
                "--app", "/tmp/MyWallpaperX",
                "--sample-root", "/tmp/samples",
                "--output-dir", "/tmp/results",
                "--product-entry-audio-baseline",
            ]
            arguments = benchmark.parse_args()
        finally:
            sys.argv = previous
        self.assertTrue(arguments.product_entry_audio_baseline)
        self.assertEqual(
            arguments.audio_declaration_snapshot.name,
            "scene_capability_census_snapshot.json",
        )

    def test_snapshot_relationship_ids_are_the_only_matrix_owner(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-audio-snapshot-") as directory:
            path = Path(directory) / "snapshot.json"
            path.write_text(
                json.dumps({
                    "summary": {
                        "audio_declarations": {
                            "relationship_sample_count": 2,
                            "relationship_sample_ids": ["123", "456"],
                            "declaration_occurrence_count": 7,
                        }
                    }
                }),
                encoding="utf-8",
            )
            matrix = baseline.load_audio_declaration_matrix(path)

        self.assertEqual(
            matrix["name"],
            "scene-audio-declaration-product-entry-baseline",
        )
        self.assertEqual(matrix["samples"], [{"id": "123"}, {"id": "456"}])
        self.assertEqual(matrix["source"]["relationship_sample_count"], 2)
        self.assertEqual(matrix["source"]["declaration_occurrence_count"], 7)

    def test_snapshot_rejects_identity_or_count_drift(self) -> None:
        payloads = [
            {},
            {"summary": {"audio_declarations": {}}},
            {
                "summary": {"audio_declarations": {
                    "relationship_sample_count": 2,
                    "relationship_sample_ids": ["123"],
                }}
            },
            {
                "summary": {"audio_declarations": {
                    "relationship_sample_count": 2,
                    "relationship_sample_ids": ["123", "123"],
                }}
            },
            {
                "summary": {"audio_declarations": {
                    "relationship_sample_count": 2,
                    "relationship_sample_ids": ["456", "123"],
                }}
            },
            {
                "summary": {"audio_declarations": {
                    "relationship_sample_count": 1,
                    "relationship_sample_ids": ["sample-123"],
                }}
            },
        ]
        for index, payload in enumerate(payloads):
            with self.subTest(index=index), tempfile.TemporaryDirectory(
                prefix="mwx-audio-snapshot-invalid-"
            ) as directory:
                path = Path(directory) / "snapshot.json"
                path.write_text(json.dumps(payload), encoding="utf-8")
                with self.assertRaises(ValueError):
                    baseline.load_audio_declaration_matrix(path)

    def test_no_demand_reconciliation_keeps_dormant_schema_distinct(self) -> None:
        occurrences = [
            {
                "occurrence_id": "project-123",
                "domain": "audio-declaration",
                "kind": "project-support-enabled",
                "location": {"sample_id": "123"},
            },
            {
                "occurrence_id": "material-123-a",
                "domain": "audio-declaration",
                "kind": "material-host-spectrum",
                "location": {"sample_id": "123"},
                "activation_state": "not-authored",
                "source_declares_audio_processing_combo": True,
                "source_abi_state_counts": {"preprocessor-conditioned": 2},
                "source_exact_resolutions": [],
            },
            {
                "occurrence_id": "material-123-b",
                "domain": "audio-declaration",
                "kind": "material-host-spectrum",
                "location": {"sample_id": "123"},
                "activation_state": "not-authored",
                "source_declares_audio_processing_combo": True,
                "source_abi_state_counts": {"preprocessor-conditioned": 2},
                "source_exact_resolutions": [],
            },
            {
                "occurrence_id": "particle-456",
                "domain": "audio-declaration",
                "kind": "particle-audio-response",
                "location": {"sample_id": "456"},
                "activation_state": "missing-mode",
                "audio_parameter_keys": ["audioprocessingbounds"],
            },
            {
                "occurrence_id": "material-789",
                "domain": "audio-declaration",
                "kind": "material-host-spectrum",
                "location": {"sample_id": "789"},
                "activation_state": "not-authored",
                "source_declares_audio_processing_combo": True,
                "source_abi_state_counts": {"preprocessor-conditioned": 2},
                "source_exact_resolutions": [16],
            },
            {
                "occurrence_id": "particle-999",
                "domain": "audio-declaration",
                "kind": "particle-audio-response",
                "location": {"sample_id": "999"},
                "activation_state": "missing-mode",
                "audio_parameter_keys": "audioprocessingbounds",
            },
        ]
        result = baseline.reconcile_no_demand_declarations(
            ["123", "456", "789", "999"], occurrences
        )

        self.assertEqual(result["sample_count"], 4)
        self.assertEqual(
            result["categories"]["material-host-spectrum-not-authored"],
            {
                "sample_count": 1,
                "sample_ids": ["123"],
                "declaration_occurrence_count": 2,
            },
        )
        self.assertEqual(
            result["categories"]["particle-audio-mode-missing"]["sample_ids"],
            ["456"],
        )
        self.assertEqual(result["unresolved_sample_ids"], ["789", "999"])
        self.assertEqual(
            result["evidence_ceiling"], "declaration-reconciliation-only"
        )
        self.assertFalse(result["runtime_validated"])
        self.assertFalse(result["visual_validated"])

    def test_no_demand_reconciliation_fails_closed_on_identity_drift(self) -> None:
        valid = [{
            "occurrence_id": "material-123",
            "domain": "audio-declaration",
            "kind": "material-host-spectrum",
            "location": {"sample_id": "123"},
            "activation_state": "not-authored",
            "source_declares_audio_processing_combo": True,
            "source_abi_state_counts": {"preprocessor-conditioned": 2},
            "source_exact_resolutions": [],
        }]
        invalid_cases = (
            (["456", "123"], valid),
            (["123", "123"], valid),
            (["sample-123"], valid),
            (["456"], valid),
            (["123"], valid + [dict(valid[0])]),
            (["123"], [{**valid[0], "domain": "material"}]),
        )
        for sample_ids, occurrences in invalid_cases:
            with self.subTest(sample_ids=sample_ids, occurrences=occurrences):
                with self.assertRaises(ValueError):
                    baseline.reconcile_no_demand_declarations(
                        sample_ids, occurrences
                    )

    def test_no_demand_reconciliation_keeps_schema_drift_unresolved(self) -> None:
        material = {
            "occurrence_id": "material-123",
            "domain": "audio-declaration",
            "kind": "material-host-spectrum",
            "location": {"sample_id": "123"},
            "activation_state": "not-authored",
            "source_declares_audio_processing_combo": True,
            "source_abi_state_counts": {"preprocessor-conditioned": 2},
            "source_exact_resolutions": [],
        }
        particle = {
            "occurrence_id": "particle-123",
            "domain": "audio-declaration",
            "kind": "particle-audio-response",
            "location": {"sample_id": "123"},
            "activation_state": "missing-mode",
            "audio_parameter_keys": ["audioprocessingbounds"],
        }
        variants = (
            {key: value for key, value in material.items()
             if key != "source_declares_audio_processing_combo"},
            {**material, "source_declares_audio_processing_combo": False},
            {key: value for key, value in material.items()
             if key != "source_abi_state_counts"},
            {**material, "source_abi_state_counts": {"dynamic-array": 2}},
            {**material, "source_abi_state_counts": {
                "preprocessor-conditioned": True,
            }},
            {**particle, "audio_parameter_keys": []},
            {**particle, "audio_parameter_keys": ["unrelated"]},
            {**particle, "audio_parameter_keys": ["audioprocessingmode"]},
        )
        for index, occurrence in enumerate(variants):
            occurrence = {**occurrence, "occurrence_id": f"drift-{index}"}
            with self.subTest(index=index):
                result = baseline.reconcile_no_demand_declarations(
                    ["123"], [occurrence]
                )
                self.assertEqual(result["unresolved_sample_ids"], ["123"])

    def test_saved_consumer_inventory_preserves_owner_shape_and_evidence_ceiling(
        self,
    ) -> None:
        material_left = (
            "MWX typed input consumption: channel=audio-spectrum "
            "consumer=material-uniform layer=12 effect=3 "
            "descriptor=12#effect#90 node=4 "
            "uniform=g_AudioSpectrum32Left side=left count=32 "
            "frame=8 generation=5 state=nonzero nonZero=3 "
            "first=0 peak=0.75"
        )
        material_right = material_left.replace(
            "Spectrum32Left side=left", "Spectrum32Right side=right"
        ).replace("nonZero=3", "nonZero=2").replace("peak=0.75", "peak=0.5")
        script_particle = (
            "MWX SceneScript VM: target=particle(layerID: 44, "
            "field: MyWallpaperX.SceneDynamicParticleField.rate) "
            "callback=audioValuePublished type=scalar generation=6 "
            "input=0.25 output=0.5 route=generic-only"
        )
        script_layer = (
            "MWX SceneScript VM: target=layer(layerID: 55, "
            "field: MyWallpaperX.SceneDynamicLayerField.scale) "
            "callback=audioValuePublished type=vector3 generation=7 "
            "input=vector3(1, 1, 1) output=vector3(2, 2, 2) "
            "route=generic-only"
        )
        result = baseline.inventory_saved_audio_consumer_events(
            ["123", "456", "789", "999"],
            {
                "123": "\n".join((material_left, material_right)),
                "456": script_particle,
                "789": "\n".join((material_left, material_right, script_layer)),
                "999": "unrelated runtime log",
            },
        )

        self.assertEqual(result["sample_count"], 4)
        self.assertEqual(result["consumer_event_sample_count"], 3)
        self.assertEqual(result["no_consumer_event_sample_ids"], ["999"])
        self.assertEqual(result["event_class_counts"], {
            "material-and-scenescript-consumer-events": 1,
            "material-consumer-events": 1,
            "no-consumer-event-in-saved-log": 1,
            "scenescript-consumer-events": 1,
        })
        self.assertEqual(result["material_uniform_sample_count"], 2)
        self.assertEqual(result["material_uniform_consumer_count"], 2)
        self.assertEqual(result["material_resolution_consumer_counts"], {
            "16": 0,
            "32": 2,
            "64": 0,
        })
        self.assertEqual(result["material_resolution_sample_ids"]["32"], [
            "123", "789",
        ])
        self.assertEqual(result["material_side_profile_counts"], {
            "left+right": 2,
        })
        self.assertEqual(result["scenescript_sample_count"], 2)
        self.assertEqual(result["scenescript_target_count"], 2)
        self.assertEqual(result["scenescript_target_kind_counts"], {
            "layer": 1,
            "particle": 1,
        })
        self.assertEqual(result["scenescript_target_type_counts"], {
            "scalar": 1,
            "vector3": 1,
        })
        self.assertFalse(result["particle_component_execution_validated"])
        self.assertFalse(result["visual_validated"])
        rows = {value["sample_id"]: value for value in result["samples"]}
        self.assertEqual(
            rows["123"]["material_uniform_consumers"][0]["nonzero_sides"],
            ["left", "right"],
        )
        self.assertEqual(
            rows["456"]["evidence_ceiling"],
            "S3-saved-log-consumer-event",
        )
        self.assertEqual(
            rows["999"]["evidence_ceiling"],
            "S3-capture-publication-only",
        )

    def test_saved_consumer_inventory_preserves_authored_left_only_uniforms(
        self,
    ) -> None:
        log = (
            "MWX typed input consumption: channel=audio-spectrum "
            "consumer=material-uniform layer=380 effect=0 "
            "descriptor=380#effect#381 node=0 "
            "uniform=g_AudioSpectrum64Left side=left count=64 "
            "frame=26 generation=7 state=nonzero nonZero=1 "
            "first=0 peak=0.125"
        )
        result = baseline.inventory_saved_audio_consumer_events(
            ["3780391264"], {"3780391264": log}
        )

        self.assertEqual(result["material_side_profile_counts"], {"left": 1})
        self.assertEqual(
            result["samples"][0]["material_uniform_consumers"][0][
                "nonzero_sides"
            ],
            ["left"],
        )

    def test_saved_consumer_inventory_accepts_committed_particle_component_events(
        self,
    ) -> None:
        authored_path = (
            "particles/audio component=emitter index=9 generation=1 "
            "channel=1 frequencyStart=0 frequencyEnd=0 "
            "selectedNonZero=1 route=generic-only sphere.json"
        )
        emitter = particle_audio_event(
            path=authored_path, layer=832, index=0, generation=17,
            frequency_end=1, selected_nonzero=4,
        )
        second_emitter = particle_audio_event(
            path=authored_path, layer=832, index=1, generation=19,
            frequency_end=1, selected_nonzero=4,
        )
        result = baseline.inventory_saved_audio_consumer_events(
            ["2131872317"],
            {"2131872317": "\n".join((emitter, second_emitter))},
        )

        self.assertEqual(result["schema_version"], 2)
        self.assertEqual(result["consumer_event_sample_ids"], ["2131872317"])
        self.assertEqual(result["event_class_counts"], {
            "particle-consumer-events": 1,
        })
        self.assertEqual(result["particle_component_sample_count"], 1)
        self.assertEqual(result["particle_component_consumer_count"], 2)
        self.assertEqual(result["particle_component_kind_counts"], {
            "emitter": 2,
        })
        self.assertTrue(result["particle_component_execution_validated"])
        consumers = result["samples"][0]["particle_component_consumers"]
        self.assertEqual([value["component_index"] for value in consumers], [0, 1])
        self.assertTrue(all(
            value["particle_path"] == authored_path
            for value in consumers
        ))
        self.assertFalse(result["visual_validated"])

    def test_saved_consumer_inventory_fails_closed_on_identity_or_telemetry_drift(
        self,
    ) -> None:
        valid_material = (
            "MWX typed input consumption: channel=audio-spectrum "
            "consumer=material-uniform layer=12 effect=3 "
            "descriptor=12#effect#90 node=4 "
            "uniform=g_AudioSpectrum16Left side=left count=16 "
            "frame=8 generation=5 state=nonzero nonZero=3 "
            "first=0 peak=0.75"
        )
        invalid_cases = (
            (["456", "123"], {"123": "", "456": ""}),
            (["123", "123"], {"123": ""}),
            (["sample-123"], {"sample-123": ""}),
            (["123"], {}),
            (["123"], {"123": 1}),
            (["123"], {"123": valid_material.replace(
                "Spectrum16Left side=left", "Spectrum16Left side=right"
            )}),
            (["123"], {"123": valid_material.replace(
                "state=nonzero nonZero=3", "state=nonzero nonZero=0"
            )}),
            (["123"], {"123": valid_material.replace("peak=0.75", "peak=nan")}),
            (["123"], {"123": (
                "MWX SceneScript VM: target=layer(layerID: 1, field: scale) "
                "callback=audioValuePublished type=scalar generation=0 "
                "input=0 output=0 route=generic-only"
            )}),
            (["123"], {"123": (
                "MWX SceneScript VM: target=cursor(layerID: 1, field: scale) "
                "callback=audioValuePublished type=scalar generation=1 "
                "input=0 output=0 route=generic-only"
            )}),
            (["123"], {"123": (
                "MWX SceneScript VM: target=layer(layerID: 1, "
                "field: MyWallpaperX.SceneDynamicParticleField.rate) "
                "callback=audioValuePublished type=scalar generation=1 "
                "input=0 output=0 route=generic-only"
            )}),
            (["123"], {"123": particle_audio_event(generation=0)}),
            (["123"], {"123": particle_audio_event(
                channel=1, frequency_start=4, frequency_end=3
            )}),
            (["123"], {"123": particle_audio_event(
                channel=1, frequency_start=0, frequency_end=0,
                selected_nonzero=2,
            )}),
            (["123"], {"123": particle_audio_event(trailing=" trailing-garbage")}),
            (["123"], {"123": (
                "MWX particle audio: consumer=particle-component layer=1 "
                "pathBase64=%%% component=emitter index=0 generation=1 "
                "channel=3 frequencyStart=0 frequencyEnd=1 "
                "selectedNonZero=1 route=generic-only"
            )}),
        )
        for sample_ids, logs in invalid_cases:
            with self.subTest(sample_ids=sample_ids, logs=logs):
                with self.assertRaises(ValueError):
                    baseline.inventory_saved_audio_consumer_events(sample_ids, logs)

    def test_saved_consumer_inventory_rejects_value_type_drift_for_one_target(
        self,
    ) -> None:
        target = (
            "layer(layerID: 55, "
            "field: MyWallpaperX.SceneDynamicLayerField.scale)"
        )
        scalar = (
            f"MWX SceneScript VM: target={target} "
            "callback=audioValuePublished type=scalar generation=6 "
            "input=0.25 output=0.5 route=generic-only"
        )
        vector = (
            f"MWX SceneScript VM: target={target} "
            "callback=audioValuePublished type=vector3 generation=7 "
            "input=vector3(1, 1, 1) output=vector3(2, 2, 2) "
            "route=generic-only"
        )

        with self.assertRaisesRegex(ValueError, "value type changed"):
            baseline.inventory_saved_audio_consumer_events(
                ["123"], {"123": "\n".join((scalar, vector))}
            )

    def test_saved_consumer_inventory_does_not_promote_silent_uniforms(self) -> None:
        silent = (
            "MWX typed input consumption: channel=audio-spectrum "
            "consumer=material-uniform layer=12 effect=3 "
            "descriptor=12#effect#90 node=4 "
            "uniform=g_AudioSpectrum16Left side=left count=16 "
            "frame=0 generation=0 state=silent nonZero=0 first=0 peak=0"
        )
        result = baseline.inventory_saved_audio_consumer_events(
            ["123"], {"123": silent}
        )

        self.assertEqual(result["consumer_event_sample_count"], 0)
        self.assertEqual(result["no_consumer_event_sample_ids"], ["123"])
        self.assertEqual(result["material_uniform_consumer_count"], 0)

    def test_product_command_uses_only_existing_product_entry(self) -> None:
        command = baseline.product_entry_command(
            runtime_binary=Path("/tmp/MyWallpaperX"),
            runtime_sample=Path("/tmp/sample/123"),
            result_dir=Path("/tmp/result/123"),
            runtime_workshop=Path("/tmp/workshop/123"),
            sample_id="123",
            duration=9,
        )
        self.assertEqual(command[0], "/tmp/MyWallpaperX")
        for flag in (
            "--mwx-debug-scene-daemon-client",
            "--mwx-debug-scene-product-entry",
            "--mwx-debug-scene-daemon-stable",
            "--mwx-debug-scene-root",
            "--mwx-debug-workshop-root",
            "--mwx-debug-user-defaults-suite",
        ):
            self.assertIn(flag, command)
        suite_index = command.index("--mwx-debug-user-defaults-suite") + 1
        self.assertEqual(
            command[suite_index],
            "com.songziqiang.MyWallpaperX.Debug.AudioCorpus.123",
        )
        self.assertNotIn("--mwx-debug-scene-audio-spectrum-fixture", command)
        for invalid in ("", "../123", "１２３", "abc"):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                baseline.private_defaults_suite(invalid)

    def test_typed_startup_overrides_are_bounded_and_preserved(self) -> None:
        overrides = baseline.parse_product_entry_property_overrides(
            '{"enabled":true,"mode":"0","rate":1.5}'
        )
        self.assertEqual(overrides, {
            "enabled": True,
            "mode": "0",
            "rate": 1.5,
        })
        command = baseline.product_entry_command(
            runtime_binary=Path("/tmp/MyWallpaperX"),
            runtime_sample=Path("/tmp/sample/123"),
            result_dir=Path("/tmp/result/123"),
            runtime_workshop=Path("/tmp/workshop/123"),
            sample_id="123",
            duration=9,
            property_overrides=overrides,
        )
        payload_index = command.index("--mwx-debug-scene-properties-json") + 1
        self.assertEqual(
            json.loads(command[payload_index]),
            overrides,
        )

        invalid_payloads = (
            "{}",
            "[]",
            '{"duplicate":true,"duplicate":false}',
            '{"nested":{"value":1}}',
            '{"nan":NaN}',
            '{"bad\\u0000key":true}',
            r'{"\ud800":true}',
            r'{"bad":"\ud800"}',
            '{"huge":' + ("9" * 10_000) + "}",
        )
        for payload in invalid_payloads:
            with self.subTest(payload=payload), self.assertRaises(ValueError):
                baseline.parse_product_entry_property_overrides(payload)

    def test_unbounded_startup_overrides_fail_as_preconditions(self) -> None:
        for payload in (
            r'{"bad":"\ud800"}',
            '{"huge":' + ("9" * 10_000) + "}",
        ):
            previous = sys.argv
            errors = io.StringIO()
            try:
                sys.argv = [
                    "scene_wallpaper_benchmark.py",
                    "--app", "/tmp/MyWallpaperX",
                    "--sample-root", "/tmp/samples",
                    "--output-dir", "/tmp/results",
                    "--product-entry-properties-json",
                    payload,
                ]
                with contextlib.redirect_stderr(errors):
                    exit_code = benchmark.main()
            finally:
                sys.argv = previous
            self.assertEqual(exit_code, 2)
            self.assertIn("precondition failed", errors.getvalue())
            self.assertNotIn("Traceback", errors.getvalue())

    def test_result_classifier_stops_at_capture_publication(self) -> None:
        result = baseline.classify_product_entry_result(
            "123",
            successful_payload(),
            exit_code=0,
            timed_out=False,
        )
        self.assertTrue(result["passed"])
        self.assertEqual(result["status"], "capture-publication-observed")
        self.assertEqual(result["evidence_ceiling"], "S3-capture-publication")
        self.assertFalse(result["visual_validated"])
        self.assertFalse(result["consumer_execution_validated"])
        self.assertEqual(result["nonzero_publication_count"], 2)
        self.assertEqual(result["maximum_publication_peak"], 0.5)

        overridden = successful_payload()
        overridden["startupPropertyOverrides"] = {"mode": "0"}
        matched = baseline.classify_product_entry_result(
            "123",
            overridden,
            exit_code=0,
            timed_out=False,
            expected_property_overrides={"mode": "0"},
        )
        self.assertTrue(matched["passed"])
        mismatch = baseline.classify_product_entry_result(
            "123",
            overridden,
            exit_code=0,
            timed_out=False,
            expected_property_overrides={"mode": "1"},
        )
        self.assertFalse(mismatch["passed"])
        self.assertEqual(mismatch["status"], "result-identity-invalid")

        for actual, expected in ((True, 1.0), (1, True), (False, 0.0), (0, False)):
            typed_mismatch = successful_payload()
            typed_mismatch["startupPropertyOverrides"] = {"value": actual}
            result = baseline.classify_product_entry_result(
                "123",
                typed_mismatch,
                exit_code=0,
                timed_out=False,
                expected_property_overrides={"value": expected},
            )
            with self.subTest(actual=actual, expected=expected):
                self.assertFalse(result["passed"])
                self.assertEqual(result["status"], "result-identity-invalid")

        overflowed = successful_payload()
        overflowed["startupPropertyOverrides"] = {"value": 10**400}
        overflow_result = baseline.classify_product_entry_result(
            "123",
            overflowed,
            exit_code=0,
            timed_out=False,
            expected_property_overrides={"value": 1.0},
        )
        self.assertFalse(overflow_result["passed"])
        self.assertEqual(overflow_result["status"], "result-identity-invalid")

    def test_result_classifier_preserves_first_breakpoint_buckets(self) -> None:
        cases: list[tuple[str, object]] = []
        launch = successful_payload()
        launch["launchPhase"] = "preparing"
        cases.append(("launch-not-complete", launch))
        first_present = successful_payload()
        first_present["firstPresentCount"] = 0
        cases.append(("first-present-missing", first_present))
        demand = successful_payload()
        demand["audioSpectrumDemanded"] = False
        cases.append(("audio-demand-missing", demand))
        publication = successful_payload()
        publication["audioSpectrumPublicationCount"] = 0
        publication["audioSpectrumPublicationPeaks"] = []
        cases.append(("nonzero-publication-missing", publication))
        rendered = successful_payload()
        rendered["latestStats"] = {"rendered": 0}
        cases.append(("rendered-frame-missing", rendered))
        malformed_publication = successful_payload()
        malformed_publication["audioSpectrumPublicationPeaks"] = [0.25, 0]
        cases.append(("publication-evidence-malformed", malformed_publication))
        duplicate_present = successful_payload()
        duplicate_present["firstPresentCount"] = 2
        duplicate_present["firstPresentRecordIDs"] = [
            "debug-scene-daemon-client",
            "debug-scene-daemon-client",
        ]
        cases.append(("first-present-identity-invalid", duplicate_present))
        wrong_present_record = successful_payload()
        wrong_present_record["firstPresentRecordIDs"] = ["wrong-record"]
        cases.append(("first-present-identity-invalid", wrong_present_record))
        cases.append(("result-missing", None))

        for expected, payload in cases:
            with self.subTest(expected=expected):
                result = baseline.classify_product_entry_result(
                    "123", payload, exit_code=0, timed_out=False
                )
                self.assertFalse(result["passed"])
                self.assertEqual(result["status"], expected)

    def test_execution_or_identity_failure_precedes_product_breakpoint(self) -> None:
        cases: list[tuple[str, dict[str, object], int, bool]] = []
        timed_out = successful_payload()
        timed_out["audioSpectrumDemanded"] = False
        cases.append(("process-execution-failure", timed_out, -15, True))
        nonzero_exit = successful_payload()
        nonzero_exit["launchPhase"] = "preparing"
        cases.append(("process-execution-failure", nonzero_exit, 7, False))
        runner_failure = successful_payload()
        runner_failure["failures"] = ["transport-closed"]
        runner_failure["audioSpectrumDemanded"] = False
        cases.append(("daemon-client-failure", runner_failure, 0, False))
        malformed_failures = successful_payload()
        malformed_failures["failures"] = "not-a-list"
        malformed_failures["audioSpectrumPublicationCount"] = 0
        malformed_failures["audioSpectrumPublicationPeaks"] = []
        cases.append(("daemon-client-failure", malformed_failures, 0, False))
        identity_failure = successful_payload("wrong")
        identity_failure["firstPresentCount"] = 0
        cases.append(("result-identity-invalid", identity_failure, 0, False))

        for expected, payload, exit_code, timed_out_value in cases:
            with self.subTest(expected=expected):
                result = baseline.classify_product_entry_result(
                    "123",
                    payload,
                    exit_code=exit_code,
                    timed_out=timed_out_value,
                )
                self.assertFalse(result["passed"])
                self.assertEqual(result["status"], expected)

        missing_after_timeout = baseline.classify_product_entry_result(
            "123",
            None,
            exit_code=-15,
            timed_out=True,
        )
        self.assertEqual(
            missing_after_timeout["status"],
            "process-execution-failure",
        )

    def test_summary_keeps_every_failed_sample_in_the_denominator(self) -> None:
        results = [
            {
                "id": "123",
                "baseline": {"status": "capture-publication-observed"},
            },
            {"id": "456", "baseline": {"status": "audio-demand-missing"}},
            {"id": "789", "baseline": {"status": "audio-demand-missing"}},
        ]
        summary = baseline.summarize_product_entry_results(results)
        self.assertFalse(summary["passed"])
        self.assertEqual(summary["sample_count"], 3)
        self.assertEqual(summary["passed_count"], 1)
        self.assertEqual(summary["status_counts"], {
            "audio-demand-missing": 2,
            "capture-publication-observed": 1,
        })
        self.assertEqual(
            summary["sample_ids_by_status"]["audio-demand-missing"],
            ["456", "789"],
        )
        self.assertEqual(summary["visual_validated_count"], 0)

    def test_benchmark_executes_fake_product_entry_in_isolated_roots(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-audio-product-entry-") as directory:
            root = Path(directory)
            sample = root / "samples/Scene/123"
            sample.mkdir(parents=True)
            (sample / "project.json").write_text(
                json.dumps({"type": "scene", "file": "scene.json"}),
                encoding="utf-8",
            )
            (sample / "scene.pkg").write_bytes(b"PKG")
            executable = root / "fake-product-entry"
            executable.write_text(
                """#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path

arguments = sys.argv[1:]
def value(flag):
    return arguments[arguments.index(flag) + 1]

sample_root = Path(value("--mwx-debug-scene-root"))
evidence = Path(value("--mwx-debug-scene-evidence-dir"))
workshop = Path(value("--mwx-debug-workshop-root"))
failures = []
if os.environ.get("HOME") != os.environ.get("CFFIXED_USER_HOME"):
    failures.append("fixed-home-mismatch")
if not workshop.is_dir() or not sample_root.is_dir():
    failures.append("isolated-root-missing")
payload = {
    "sampleID": sample_root.name,
    "launchEntry": "steam-workshop-product",
    "launchPhase": "launched",
    "activeRecordID": "debug-scene-daemon-client",
    "stableDaemonClientRequested": True,
    "startupPropertyOverrides": json.loads(
        value("--mwx-debug-scene-properties-json")
    ) if "--mwx-debug-scene-properties-json" in arguments else {},
    "firstPresentCount": 1,
    "firstPresentRecordIDs": ["debug-scene-daemon-client"],
    "uniqueRequestCount": 1,
    "audioSpectrumDemanded": True,
    "audioSpectrumScopeEpoch": 2,
    "audioSpectrumPublicationCount": 1,
    "audioSpectrumPublicationPeaks": [0.4],
    "latestStats": {"rendered": 3},
    "failures": failures,
}
evidence.mkdir(parents=True, exist_ok=True)
(evidence / "scene-daemon-client-result.json").write_text(
    json.dumps(payload), encoding="utf-8"
)
(evidence / "generated.fragment.metal").write_text("rebuildable", encoding="utf-8")
(evidence / "generated-cache").mkdir()
(evidence / "generated-cache/data.bin").write_bytes(b"nested")
(evidence / "generated-link").symlink_to(sample_root / "project.json")
""",
                encoding="utf-8",
            )
            executable.chmod(executable.stat().st_mode | stat.S_IXUSR)
            output = root / "output"
            runtime = output / "runtime"
            output.mkdir()
            runtime.mkdir()

            result = benchmark.run_product_entry_audio_sample(
                runtime_binary=executable,
                sample_root=root / "samples",
                sample={"id": "123"},
                output_dir=output,
                runtime_root=runtime,
                duration=7,
                property_overrides={"mode": "0"},
            )

            self.assertTrue(result["passed"])
            self.assertEqual(
                result["baseline"]["status"],
                "capture-publication-observed",
            )
            self.assertEqual(result["daemon_client_result"]["failures"], [])
            self.assertEqual(result["property_overrides"], {"mode": "0"})
            self.assertTrue(Path(result["runtime_home"]).is_dir())
            self.assertTrue(Path(result["runtime_workshop"]).is_dir())
            self.assertTrue(result["evidence"]["app_log_sha256"])
            self.assertTrue(
                result["evidence"]["daemon_client_result_sha256"]
            )
            self.assertEqual(
                result["evidence"]["removed_rebuildable_artifact_count"],
                3,
            )
            self.assertFalse(
                (output / "results/123/generated.fragment.metal").exists()
            )
            self.assertFalse((output / "results/123/generated-cache").exists())
            self.assertFalse((output / "results/123/generated-link").exists())
            self.assertTrue(
                (Path(result["runtime_sample"]) / "project.json").is_file()
            )
            self.assertTrue((sample / "project.json").is_file())


if __name__ == "__main__":
    unittest.main()
