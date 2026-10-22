#!/usr/bin/env python3
"""Authored observations and conservative declaration classification."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from collections import Counter
from pathlib import Path

SCRIPT_ROOT = Path(__file__).resolve().parents[1]
if str(SCRIPT_ROOT) not in sys.path:
    sys.path.insert(0, str(SCRIPT_ROOT))

import scene_capability_census as census
from scene_capability_census_io import ResolvedResource
from scene_capability_census_profiles import family_key, scenescript_audio_registrations, script_profile
from script.tests.scene_capability_census_test_support import json_bytes, make_fixture, pkg


class SceneCapabilityCensusObservationTests(unittest.TestCase):
    def test_scenescript_cursor_hook_profile_requires_proven_export(self) -> None:
        profile = script_profile(r'''
            // export function cursorClick() {}
            const ignored = "export function cursorEnter() {}";
            function clickHandler() {}
            export { clickHandler as cursorClick };
            export function cursorDown() {}
            export const cursorMove = event => event.worldPosition;
            export const cursorLeave = dynamicHandler;
        ''')
        self.assertEqual(
            profile["hooks"], ["cursorClick", "cursorDown", "cursorMove"]
        )
        self.assertEqual(profile["unresolved_cursor_hooks"], ["cursorLeave"])

    def test_family_key_ignores_concrete_revision_values(self) -> None:
        left = family_key("fixture", "binding", {
            "kind": "object",
            "numeric_min": 0,
            "numeric_max": 1,
            "script": {"sha256": "first", "hooks": ["update"]},
        })
        right = family_key("fixture", "binding", {
            "kind": "object",
            "numeric_min": -200,
            "numeric_max": 900,
            "script": {"sha256": "second", "hooks": ["update"]},
        })
        changed_semantics = family_key("fixture", "binding", {
            "kind": "object",
            "numeric_min": 0,
            "numeric_max": 1,
            "script": {"sha256": "first", "hooks": ["cursorDown"]},
        })
        self.assertEqual(left, right)
        self.assertNotEqual(left, changed_semantics)

    def test_census_is_deterministic_conserving_and_payload_free(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-census-") as directory:
            root = Path(directory)
            samples, stock, matrix, ledger = make_fixture(root)
            first = census.build_census(samples, stock, matrix, ledger)
            second = census.build_census(samples, stock, matrix, ledger)
            self.assertEqual(census.canonical_json_bytes(first), census.canonical_json_bytes(second))
            self.assertEqual(first["summary"]["discovered_sample_count"], 1)
            self.assertEqual(first["summary"]["parsed_sample_count"], 1)
            self.assertEqual(first["summary"]["added_since_matrix"], ["0000000001"])
            self.assertTrue(first["validation"]["conservation"]["occurrences_balanced"])
            self.assertTrue(first["validation"]["conservation"]["schema_fields"]["balanced"])
            self.assertTrue(first["validation"]["conservation"]["package_resources"]["balanced"])
            self.assertTrue(first["validation"]["conservation"]["parameter_occurrence_refs"]["balanced"])
            self.assertTrue(first["validation"]["conservation"]["revisions"]["balanced"])
            self.assertTrue(first["validation"]["conservation"]["texture_use_visibility"]["balanced"])
            self.assertEqual(first["summary"]["package_entry_count"], 13)
            self.assertEqual(first["summary"]["texture"]["physical_resource_count"], 3)
            self.assertFalse(first["validation"]["failures"])
            domains = first["summary"]["occurrences_by_domain"]
            for domain in (
                "resource", "shader", "layer", "effect", "material", "render-graph", "render-target",
                "texture", "particle", "audio-declaration", "dynamic-input", "project-property",
            ):
                self.assertGreater(domains.get(domain, 0), 0, domain)
            serialized = census.canonical_json_bytes(first)
            self.assertNotIn(b"export function update", serialized)
            self.assertNotIn(b"engine.frametime", serialized)
            script_fields = [field for field in first["schema_fields"] if field["field_name"] == "script"]
            self.assertTrue(script_fields)
            self.assertTrue(script_fields[0]["script_hashes"])
            graph_bindings = [
                item for item in first["occurrences"] if item["kind"] == "graph-binding"
            ]
            self.assertTrue(graph_bindings)
            self.assertEqual({item["slot_state"] for item in graph_bindings}, {"runtime-provided"})
            texture_uses = [
                item for item in first["occurrences"]
                if item["domain"] == "texture" and item["kind"] != "package-resource"
            ]
            self.assertTrue(all("effective_visibility" in item for item in texture_uses))
            image_slots = [item for item in texture_uses if item["kind"] == "image-material-slot"]
            self.assertEqual(
                {item["effective_visibility"] for item in image_slots},
                {"hidden", "visible"},
            )
            self.assertTrue(all(profile.get("occurrence_refs") for profile in first["parameter_profiles"]))
            audio = [
                item for item in first["occurrences"]
                if item["domain"] == "audio-declaration"
            ]
            self.assertEqual(
                Counter(item["kind"] for item in audio),
                {
                    "project-support-enabled": 1,
                    "material-host-spectrum": 1,
                    "material-audio-response": 1,
                    "particle-audio-response": 1,
                    "scenescript-registration": 1,
                },
            )
            script_audio = next(
                item for item in audio if item["kind"] == "scenescript-registration"
            )
            self.assertEqual(script_audio["resolution_states"], ["32"])
            self.assertEqual(script_audio["call_count"], 1)
            self.assertEqual(script_audio["scope_states"], ["proven-global"])
            self.assertEqual(script_audio["admission_states"], ["statically-admitted"])
            material_audio = next(
                item for item in audio if item["kind"] == "material-host-spectrum"
            )
            self.assertEqual(material_audio["resolutions"], [16, 32, 64])
            self.assertEqual(material_audio["channels"], ["left", "right"])
            self.assertEqual(material_audio["source_exact_resolutions"], [16])
            self.assertEqual(
                material_audio["source_abi_state_counts"],
                {
                    "preprocessor-conditioned": 1,
                    "source-shape-exact": 2,
                    "wrong-array-length": 1,
                    "wrong-type": 1,
                },
            )
            self.assertEqual(
                material_audio["runtime_admission_state"],
                "launch-envelope-unjoined",
            )
            self.assertEqual(material_audio["effective_visibility"], "hidden")
            audio_summary = first["summary"]["audio_declarations"]
            self.assertEqual(audio_summary["project_support_sample_count"], 1)
            self.assertEqual(audio_summary["relationship_sample_count"], 1)
            self.assertEqual(audio_summary["relationship_sample_ids"], ["0000000001"])
            self.assertEqual(audio_summary["static_consumer_intent_sample_count"], 1)
            self.assertEqual(
                audio_summary["static_consumer_intent_sample_ids"],
                ["0000000001"],
            )
            self.assertEqual(audio_summary["runtime_confirmed_sample_count"], 0)
            self.assertFalse(audio_summary["support_without_relationship"])
            self.assertFalse(audio_summary["relationship_without_support"])

    def test_scenescript_audio_registration_scope_is_conservative(self) -> None:
        profile = scenescript_audio_registrations("""
            // engine.registerAudioBuffers(16)
            const ignored = "engine.registerAudioBuffers(32)";
            const pattern = /engine.registerAudioBuffers\\(/;
            const direct = engine.registerAudioBuffers(engine.AUDIO_RESOLUTION_32);
            const computed = engine["registerAudioBuffers"](
                engine["AUDIO_RESOLUTION_64"]
            );
            const interpolated = `${engine.registerAudioBuffers(16)}`;
            function callback() { return engine.registerAudioBuffers(16); }
            const arrow = () => engine.registerAudioBuffers(16);
            const bare = engine.registerAudioBuffers(AUDIO_RESOLUTION_16);
        """)
        self.assertIsNotNone(profile)
        assert profile is not None
        self.assertEqual(profile["call_count"], 6)
        self.assertEqual(profile["statically_admitted_call_count"], 3)
        self.assertEqual(
            profile["resolution_state_counts"],
            {"16": 3, "32": 1, "64": 1, "dynamic-or-invalid": 1},
        )
        self.assertEqual(
            profile["scope_state_counts"],
            {"non-global-or-nested": 2, "proven-global": 4},
        )
        self.assertEqual(
            profile["admission_state_counts"],
            {
                "resolution-unresolved": 1,
                "scope-unproven": 2,
                "statically-admitted": 3,
            },
        )
        self.assertEqual(profile["cursor_event_exports"], [])
        self.assertEqual(profile["cursor_event_unresolved_exports"], [])
        self.assertEqual(
            profile["cursor_audio_consumer_state"], "no-cursor-event"
        )

    def test_scenescript_cursor_audio_relation_ignores_non_code_mentions(self) -> None:
        profile = scenescript_audio_registrations(r'''
            const audio = engine.registerAudioBuffers(16);
            // export function cursorMove() {}
            const ignored = "export function cursorClick() {}";
            const pattern = /export function cursorEnter\(/;
            export function cursorDown() { return audio.left[0]; }
            export async function cursorUp() { return audio.right[0]; }
            export async function* cursorEnter() { yield audio.average[0]; }
            export const cursorMove = () => audio.average[0];
            const localClick = async () => audio.average[1];
            export { localClick as cursorClick };
            function localLeave() { return audio.average[2]; }
            export { localLeave as cursorLeave };
        ''')
        self.assertIsNotNone(profile)
        assert profile is not None
        self.assertEqual(
            profile["cursor_event_exports"],
            [
                "cursorClick", "cursorDown", "cursorEnter", "cursorLeave",
                "cursorMove", "cursorUp",
            ],
        )
        self.assertEqual(profile["cursor_event_unresolved_exports"], [])
        self.assertEqual(
            profile["cursor_audio_consumer_state"], "statically-admitted"
        )

        non_module = scenescript_audio_registrations(r'''
            engine.registerAudioBuffers(16);
            if (true) { export function cursorMove() {} }
            const template = `${export function cursorClick() {}}`;
            const text = "export function cursorDown() {}";
        ''')
        self.assertIsNotNone(non_module)
        assert non_module is not None
        self.assertEqual(non_module["cursor_event_exports"], [])
        self.assertEqual(non_module["cursor_event_unresolved_exports"], [])
        self.assertEqual(
            non_module["cursor_audio_consumer_state"], "no-cursor-event"
        )

        unresolved = scenescript_audio_registrations('''
            const audio = engine.registerAudioBuffers(dynamicResolution);
            export function cursorMove() { return audio.average[0]; }
        ''')
        self.assertIsNotNone(unresolved)
        assert unresolved is not None
        self.assertEqual(
            unresolved["cursor_audio_consumer_state"],
            "audio-registration-unresolved",
        )

        unresolved_export = scenescript_audio_registrations('''
            const audio = engine.registerAudioBuffers(16);
            const localUp = resolveCursorHandler();
            export { localUp as cursorUp };
            export const cursorMove = resolveCursorHandler();
            export const cursorClick = function () {}();
            export const { cursorEnter } = dynamicHandlers;
            export let cursorLeave = () => audio.average[0];
            export function cursorDown() { return audio.left[0]; }
            cursorDown = resolveCursorHandler();
        ''')
        self.assertIsNotNone(unresolved_export)
        assert unresolved_export is not None
        self.assertEqual(unresolved_export["cursor_event_exports"], [])
        self.assertEqual(
            unresolved_export["cursor_event_unresolved_exports"],
            [
                "cursorClick", "cursorDown", "cursorEnter", "cursorLeave",
                "cursorMove", "cursorUp",
            ],
        )
        self.assertEqual(
            unresolved_export["cursor_audio_consumer_state"],
            "cursor-export-unresolved",
        )

        unresolved_reexport = scenescript_audio_registrations('''
            engine.registerAudioBuffers(16);
            export { remote as cursorMove } from "./callbacks.js";
            export * from "./more-callbacks.js";
        ''')
        self.assertIsNotNone(unresolved_reexport)
        assert unresolved_reexport is not None
        self.assertEqual(unresolved_reexport["cursor_event_exports"], [])
        self.assertEqual(
            unresolved_reexport["cursor_event_unresolved_exports"],
            ["<wildcard-reexport>", "cursorMove"],
        )
        self.assertEqual(
            unresolved_reexport["cursor_audio_consumer_state"],
            "cursor-export-unresolved",
        )

        for write in (
            "++cursorMove;",
            "({x: cursorMove} = {x: null});",
            "for (cursorMove of [null]) {}",
        ):
            with self.subTest(write=write):
                changed_binding = scenescript_audio_registrations(f'''
                    engine.registerAudioBuffers(16);
                    export function cursorMove() {{}}
                    {write}
                ''')
                self.assertIsNotNone(changed_binding)
                assert changed_binding is not None
                self.assertEqual(changed_binding["cursor_event_exports"], [])
                self.assertEqual(
                    changed_binding["cursor_event_unresolved_exports"],
                    ["cursorMove"],
                )

        exported_class = scenescript_audio_registrations('''
            engine.registerAudioBuffers(16);
            export class cursorMove {}
        ''')
        self.assertIsNotNone(exported_class)
        assert exported_class is not None
        self.assertEqual(exported_class["cursor_event_exports"], [])
        self.assertEqual(
            exported_class["cursor_event_unresolved_exports"],
            ["cursorMove"],
        )

        property_key_only = scenescript_audio_registrations('''
            engine.registerAudioBuffers(16);
            export const { cursorMove: handler } = dynamicHandlers;
        ''')
        self.assertIsNotNone(property_key_only)
        assert property_key_only is not None
        self.assertEqual(property_key_only["cursor_event_exports"], [])
        self.assertEqual(property_key_only["cursor_event_unresolved_exports"], [])
        self.assertEqual(
            property_key_only["cursor_audio_consumer_state"],
            "no-cursor-event",
        )

        destructured_cursor = scenescript_audio_registrations('''
            engine.registerAudioBuffers(16);
            export const { handler: cursorMove } = dynamicHandlers;
        ''')
        self.assertIsNotNone(destructured_cursor)
        assert destructured_cursor is not None
        self.assertEqual(destructured_cursor["cursor_event_exports"], [])
        self.assertEqual(
            destructured_cursor["cursor_event_unresolved_exports"],
            ["cursorMove"],
        )

        named_async_expression = scenescript_audio_registrations('''
            engine.registerAudioBuffers(16);
            export const cursorDown = async function cursorDown() {};
        ''')
        self.assertIsNotNone(named_async_expression)
        assert named_async_expression is not None
        self.assertEqual(
            named_async_expression["cursor_event_exports"], ["cursorDown"]
        )
        self.assertEqual(
            named_async_expression["cursor_event_unresolved_exports"], []
        )

    def test_cursor_audio_family_summary_explains_family_split(self) -> None:
        occurrence = {
            "occurrence_id": "audio/fixture",
            "family_key": "audio-declaration/scenescript-registration@fixture",
            "revision_key": "revision",
            "domain": "audio-declaration",
            "kind": "scenescript-registration",
            "location": {"sample_id": "0000000001"},
            "effective_visibility": "visible",
            "cursor_event_exports": ["cursorDown"],
            "cursor_event_unresolved_exports": ["cursorMove"],
            "cursor_audio_consumer_state": "cursor-export-unresolved",
        }
        row = census._family_rollup([occurrence], {"families": []})[0]
        self.assertEqual(
            row["feature_summary"]["cursor_event_exports"],
            [["cursorDown"]],
        )
        self.assertEqual(
            row["feature_summary"]["cursor_event_unresolved_exports"],
            [["cursorMove"]],
        )
        self.assertEqual(
            row["feature_summary"]["cursor_audio_consumer_state"],
            ["cursor-export-unresolved"],
        )

    def test_shader_combo_annotation_does_not_imply_material_activation(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-audio-shader-") as directory:
            shader = Path(directory) / "fixture.frag"
            shader.write_text(
                "uniform float g_AudioSpectrum16Left[16]; "
                "// {\"combo\":\"AUDIOPROCESSING\",\"default\":1}\n",
                encoding="utf-8",
            )

            class FixtureView:
                def resolve(self, path: str) -> ResolvedResource | None:
                    if path == "shaders/fixture.frag":
                        return ResolvedResource(
                            origin="fixture",
                            relative_path=path,
                            file_path=shader,
                        )
                    return None

            owner = {
                "occurrence_id": "material/fixture",
                "domain": "material",
                "shader_identity": "fixture",
                "audio_processing_state": "absent",
                "effective_visibility": "visible",
                "combo_keys": [],
                "instance_combo_keys": [],
                "constant_keys": [],
                "instance_constant_keys": [],
            }
            relationships = census._audio_owner_occurrences(
                sample_id="fixture",
                occurrences=[owner],
                view=FixtureView(),
            )
            host = next(
                item for item in relationships
                if item["kind"] == "material-host-spectrum"
            )
            self.assertTrue(host["source_declares_audio_processing_combo"])
            self.assertEqual(host["activation_state"], "not-authored")
            self.assertEqual(
                host["runtime_admission_state"], "launch-envelope-unjoined"
            )

    def test_system_usertextures_are_typed_by_scope_role_and_visibility(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-census-") as directory:
            samples, stock, matrix, ledger = make_fixture(Path(directory))
            result = census.build_census(samples, stock, matrix, ledger)
            system_textures = [
                item for item in result["occurrences"]
                if item.get("provider_kind") == "system"
            ]

            self.assertEqual(len(system_textures), 9)
            self.assertEqual(len({item["occurrence_id"] for item in system_textures}), 9)
            self.assertEqual(
                Counter(item["consumer_scope"] for item in system_textures),
                {"base-image": 7, "effect": 2},
            )
            self.assertEqual(
                Counter(item["system_role"] for item in system_textures),
                {"current": 4, "previous": 3, "named": 2},
            )
            self.assertEqual(
                Counter(item["system_name"] for item in system_textures),
                {
                    "$mediaThumbnail": 4,
                    "$mediaPreviousThumbnail": 3,
                    "$customProvider": 2,
                },
            )
            self.assertEqual(
                Counter(item["provenance"] for item in system_textures),
                {"material-user": 7, "instance-user": 2},
            )
            self.assertEqual(
                {item["kind"] for item in system_textures},
                {
                    "base-image-system-current",
                    "base-image-system-previous",
                    "base-image-system-named",
                    "effect-system-current",
                    "effect-system-previous",
                },
            )
            self.assertEqual(
                {item["effective_visibility"] for item in system_textures},
                {"hidden", "visible"},
            )
            self.assertEqual(
                Counter(item["effective_visibility"] for item in system_textures),
                {"hidden": 6, "visible": 3},
            )
            self.assertEqual(
                {item["slot_state"] for item in system_textures},
                {"runtime-provided"},
            )
            self.assertNotIn("not-system", {item["system_name"] for item in system_textures})
            self.assertTrue(result["validation"]["conservation"]["occurrences_balanced"])
            self.assertTrue(result["validation"]["conservation"]["texture_use_visibility"]["balanced"])
            self.assertFalse(result["validation"]["failures"])
            base_current = next(
                item for item in result["families"]
                if item["kind"] == "base-image-system-current"
            )
            self.assertEqual(base_current["occurrence_count"], 3)
            self.assertEqual(base_current["visible_occurrence_count"], 1)
            self.assertEqual(
                base_current["feature_summary"]["provenance"],
                ["instance-user", "material-user"],
            )

    def test_failed_directories_keep_diagnostics_and_actual_material_presence(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-census-failed-") as directory:
            samples, stock, matrix, ledger = make_fixture(Path(directory), include_failures=True)
            result = census.build_census(samples, stock, matrix, ledger)
            summary = result["summary"]
            self.assertEqual(summary["discovered_sample_count"], 3)
            self.assertEqual(summary["parsed_sample_count"], 1)
            self.assertEqual(summary["failed_sample_count"], 2)
            self.assertEqual(
                summary["discovered_sample_count"],
                summary["parsed_sample_count"] + summary["failed_sample_count"],
            )
            rows = {row["sample_id"]: row for row in result["samples"]}
            for sample_id, code, material_present in (
                ("0000000002", "project-json-missing", False),
                ("0000000003", "json-decode-failed", True),
            ):
                with self.subTest(sample_id=sample_id):
                    row = rows[sample_id]
                    self.assertEqual(row["parse_state"], "failed")
                    self.assertEqual(row["diagnostics"], [{"code": code}])
                    self.assertIs(row["has_manual_screenshot"], material_present)
                    self.assertIs(row["has_user_observation"], material_present)
                    self.assertGreater(row["file_count"], 0)
                    self.assertEqual(row["occurrence_refs"], [])
            self.assertEqual(result["validation"]["failures"], [])


if __name__ == "__main__":
    unittest.main()
