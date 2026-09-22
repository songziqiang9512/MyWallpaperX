#!/usr/bin/env python3

from __future__ import annotations

import json
import io
import struct
import sys
import tempfile
import unittest
from collections import Counter
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path


SCRIPT_ROOT = Path(__file__).resolve().parents[1]
if str(SCRIPT_ROOT) not in sys.path:
    sys.path.insert(0, str(SCRIPT_ROOT))

import scene_capability_census as census
from scene_capability_census_io import (
    PkgArchive,
    ResolvedResource,
    ensure_outputs_outside_roots,
)
from scene_capability_census_profiles import (
    family_key,
    scenescript_audio_registrations,
    script_profile,
)


def pkg(entries: list[tuple[str, bytes]], magic: str = "PKGV0024") -> bytes:
    table = bytearray()
    magic_bytes = magic.encode("utf-8")
    table += struct.pack("<I", len(magic_bytes)) + magic_bytes
    table += struct.pack("<I", len(entries))
    payload = bytearray()
    for path, value in entries:
        path_bytes = path.encode("utf-8")
        table += struct.pack("<I", len(path_bytes)) + path_bytes
        table += struct.pack("<II", len(payload), len(value))
        payload += value
    return bytes(table + payload)


def json_bytes(value: object) -> bytes:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


class SceneCapabilityCensusTests(unittest.TestCase):
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

    def make_fixture(self, root: Path) -> tuple[Path, Path, Path, Path]:
        samples = root / "samples"
        stock = root / "stock"
        sample = samples / "0000000001"
        sample.mkdir(parents=True)
        stock.mkdir(parents=True)
        (sample / "project.json").write_text(
            json.dumps({
                "type": "Scene",
                "file": "scene.json",
                "title": "Fixture",
                "general": {
                    "supportsaudioprocessing": True,
                    "properties": {
                        "toggle": {"type": "bool", "value": True, "order": 0, "text": "Toggle"}
                    }
                },
            }),
            encoding="utf-8",
        )
        scene = {
            "version": 1,
            "objects": [{
                "id": 6,
                "name": "Hidden Parent",
                "visible": False,
            }, {
                "id": 7,
                "name": "Layer",
                "image": "models/layer.json",
                "visible": True,
                "parent": 6,
                "origin": "10 20 0",
                "instance": {
                    "usertextures": [
                        {"type": "system", "name": "$mediaThumbnail"},
                        {"type": "property", "name": "not-system"},
                        {"type": "system", "name": ""},
                        42,
                    ],
                },
                "effects": [{
                    "id": 9,
                    "file": "effects/fixture/effect.json",
                    "visible": True,
                    "passes": [{
                        "id": 0,
                        "combos": {"MASK": 0},
                        "constantshadervalues": {
                            "alpha": {
                                "script": (
                                    "// engine.registerAudioBuffers(64);\n"
                                    "const ignored = 'engine.registerAudioBuffers(16)';\n"
                                    "const audio = engine.registerAudioBuffers("
                                    "engine.AUDIO_RESOLUTION_32);\n"
                                    "export function update() { return engine.frametime; }"
                                ),
                                "value": 1,
                            }
                        },
                        "textures": [None, "mask"],
                        "usertextures": [
                            None,
                            {"type": "system", "name": "$mediaPreviousThumbnail"},
                            {"type": "system"},
                        ],
                    }],
                }],
            }, {
                "id": 10,
                "name": "Visible Material Reuse",
                "image": "models/layer.json",
                "visible": True,
            }, {
                "id": 8,
                "particle": "particles/root.json",
                "visible": True,
                "instanceoverride": {"id": 8, "rate": {"user": "toggle", "value": 2}},
            }],
        }
        entries = [
            ("scene.json", json_bytes(scene)),
            ("models/layer.json", json_bytes({"autosize": True, "material": "materials/layer.json"})),
            ("materials/layer.json", json_bytes({"passes": [{
                "shader": "genericimage2", "blending": "translucent",
                "depthtest": "disabled", "depthwrite": "disabled",
                "cullmode": "nocull", "textures": ["image"],
                "usertextures": [
                    {"type": "system", "name": "$mediaThumbnail"},
                    {"type": "system", "name": "$mediaPreviousThumbnail"},
                    {"type": "system", "name": "$customProvider"},
                    {"type": "property", "name": "not-system"},
                    {"type": "system", "name": ""},
                    "plain-string",
                ],
            }]})),
            ("materials/image.tex", b"not-a-real-tex"),
            ("materials/mask.tex", b"not-a-real-tex"),
            ("effects/fixture/effect.json", json_bytes({
                "name": "Fixture", "group": "Test", "dependencies": [],
                "passes": [{
                    "material": "materials/effects/fixture.json",
                    "target": "_rt_fixture",
                    "bind": [{"name": "previous", "index": 0}],
                }],
                "fbos": [{"name": "_rt_fixture", "format": "rgba8888", "scale": 2}],
            })),
            ("effects/fixture/materials/effects/fixture.json", json_bytes({"passes": [{
                "shader": "effects/fixture", "blending": "translucent",
                "depthtest": "disabled", "depthwrite": "disabled",
                "cullmode": "nocull", "textures": [None, "mask"],
                "combos": {"AUDIOPROCESSING": 0},
                "constantshadervalues": {"audioamount": 1},
                "usertextures": [
                    {"type": "SYSTEM", "name": "  $mediaThumbnail  "},
                    {"type": "property", "name": "not-system"},
                    {"type": "system", "name": ""},
                ],
            }]})),
            ("particles/root.json", json_bytes({
                "maxcount": 10, "starttime": 0,
                "material": "materials/particle.json",
                "emitter": [{
                    "id": 1, "name": "sphererandom", "rate": 2,
                    "audioprocessingmode": 3,
                }],
                "initializer": [{"id": 2, "name": "lifetimerandom", "min": 1, "max": 2}],
                "operator": [{"id": 3, "name": "movement", "gravity": "0 1 0"}],
                "renderer": [{"id": 4, "name": "sprite"}],
                "children": [{"id": 5, "name": "particles/child.json", "type": "static"}],
            })),
            ("particles/child.json", json_bytes({
                "maxcount": 1, "starttime": 0,
                "material": "materials/particle.json",
                "emitter": [{"id": 1, "name": "boxrandom", "rate": 1}],
                "initializer": [], "operator": [],
                "renderer": [{"id": 2, "name": "sprite"}],
            })),
            ("materials/particle.json", json_bytes({"passes": [{
                "shader": "particle", "textures": ["particle"],
                "blending": "additive", "depthtest": "disabled",
                "depthwrite": "disabled", "cullmode": "nocull",
            }]})),
            ("materials/particle.tex", b"not-a-real-tex"),
            ("shaders/effects/fixture.vert", b"uniform mat4 g_ModelViewProjectionMatrix;\nvoid main() {}\n"),
            ("shaders/effects/fixture.frag", (
                b'uniform sampler2D g_Texture0; // {"mode":"rgbmask","combo":"MASK"}\n'
                b"// uniform float g_AudioSpectrum64Right[64];\n"
                b"uniform float g_AudioSpectrum16Left[16];\n"
                b"uniform float g_AudioSpectrum16Right[16];\n"
                b"uniform vec2 g_AudioSpectrum32Left[32];\n"
                b"uniform float g_AudioSpectrum32Right[16];\n"
                b"#if 0\n"
                b"uniform float g_AudioSpectrum64Left[64];\n"
                b"#endif\n"
                b"uniform float g_Alpha;\nvoid main() {}\n"
            )),
        ]
        (sample / "scene.pkg").write_bytes(pkg(entries))
        matrix = root / "matrix.json"
        matrix.write_text(json.dumps({"schema_version": 1, "samples": []}), encoding="utf-8")
        ledger = root / "ledger.json"
        ledger.write_text(json.dumps({"schema_version": 1, "families": []}), encoding="utf-8")
        return samples, stock, matrix, ledger

    def test_census_is_deterministic_conserving_and_payload_free(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-census-") as directory:
            root = Path(directory)
            samples, stock, matrix, ledger = self.make_fixture(root)
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
            samples, stock, matrix, ledger = self.make_fixture(Path(directory))
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

    def test_generate_verify_and_input_root_write_rejection(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-census-") as directory:
            root = Path(directory)
            samples, stock, matrix, ledger = self.make_fixture(root)
            snapshot = root / "out/census.json"
            markdown = root / "out/census.md"
            args = type("Args", (), {
                "samples_root": samples, "stock_root": stock,
                "matrix": matrix, "ledger": ledger,
                "snapshot": snapshot, "markdown": markdown,
            })()
            self.assertEqual(census.generate(args), 0)
            stored = json.loads(snapshot.read_text(encoding="utf-8"))
            self.assertNotIn("occurrences", stored)
            self.assertEqual(stored["validation"]["occurrence_index"]["count"], 61)
            self.assertEqual(len(stored["validation"]["occurrence_index"]["items"]), 61)
            self.assertEqual(stored["samples"][0]["occurrence_count"], 61)
            system_index = [
                item for item in stored["validation"]["occurrence_index"]["items"]
                if "-system-" in item["kind"]
            ]
            self.assertEqual(len(system_index), 9)
            self.assertEqual(
                {item["effective_visibility"] for item in system_index},
                {"hidden", "visible"},
            )
            manifest = stored["snapshot"]["generator"]["source_manifest"]
            self.assertEqual(set(manifest["files"]), set(census.GENERATOR_PATHS))
            self.assertEqual(manifest["sha256"], census.canonical_sha256(manifest["files"]))
            generated_markdown = markdown.read_text(encoding="utf-8")
            self.assertIn(
                "| family | 修复事件 / 事件运行证据 / 事件回归保护（非能力状态） |",
                generated_markdown,
            )
            self.assertIn("_尚无已登记修复_", generated_markdown)
            self.assertEqual(census.verify(args), 0)
            snapshot_query = type("Args", (), {
                "samples_root": samples, "stock_root": stock,
                "matrix": matrix, "ledger": ledger,
                "family": None, "sample": "0000000001", "domain": "texture",
                "live": False, "snapshot": snapshot,
            })()
            query_output = io.StringIO()
            with redirect_stdout(query_output):
                self.assertEqual(census.query(snapshot_query), 0)
            self.assertEqual(json.loads(query_output.getvalue())["source"], "committed-snapshot")
            snapshot.write_text("{}", encoding="utf-8")
            self.assertEqual(census.verify(args), 1)
            with self.assertRaises(ValueError):
                ensure_outputs_outside_roots([samples / "bad.json"], [samples, stock])

    def test_query_requires_a_filter_and_reconstructs_occurrences(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-census-") as directory:
            samples, stock, matrix, ledger = self.make_fixture(Path(directory))
            filtered = type("Args", (), {
                "samples_root": samples,
                "stock_root": stock,
                "matrix": matrix,
                "ledger": ledger,
                "family": None,
                "sample": "0000000001",
                "domain": "texture",
                "live": True,
                "snapshot": Path(directory) / "missing.json",
            })()
            output = io.StringIO()
            with redirect_stdout(output):
                self.assertEqual(census.query(filtered), 0)
            payload = json.loads(output.getvalue())
            self.assertEqual(payload["filters"]["sample"], "0000000001")
            self.assertGreater(payload["count"], 0)
            self.assertEqual(
                {value["domain"] for value in payload["occurrences"]},
                {"texture"},
            )

            unfiltered = type("Args", (), {
                "samples_root": samples,
                "stock_root": stock,
                "matrix": matrix,
                "ledger": ledger,
                "family": None,
                "sample": None,
                "domain": None,
                "live": True,
                "snapshot": Path(directory) / "missing.json",
            })()
            with redirect_stderr(io.StringIO()), redirect_stdout(io.StringIO()):
                self.assertEqual(census.query(unfiltered), 2)

    def test_pkg_reader_reports_duplicate_path_without_hiding_it(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-census-") as directory:
            package = Path(directory) / "fixture.pkg"
            package.write_bytes(pkg([
                ("scene.json", b"{}"),
                ("fonts/font.otf", b"same"),
                ("fonts/font.otf", b"same"),
            ]))
            with PkgArchive(package) as archive:
                self.assertEqual(len(archive.entries), 3)
                self.assertEqual(len(archive.matches("fonts/font.otf")), 2)
                duplicate = next(
                    item for item in archive.diagnostics
                    if item["code"] == "duplicate-package-path"
                )
                self.assertTrue(duplicate["content_equal"])

    def test_unsafe_package_paths_and_output_symlinks_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-census-") as directory:
            root = Path(directory)
            package = root / "fixture.pkg"
            package.write_bytes(pkg([
                ("scene.json", b"{}"),
                ("../scene.json", b"unsafe"),
                ("/scene.json", b"absolute"),
            ]))
            with PkgArchive(package) as archive:
                self.assertEqual(len(archive.matches("scene.json")), 1)
                self.assertEqual(
                    sum(item["code"] == "unsafe-package-path" for item in archive.diagnostics),
                    2,
                )

            samples = root / "samples"
            outside = root / "outside"
            samples.mkdir()
            outside.mkdir()
            linked = samples / "linked"
            linked.symlink_to(outside, target_is_directory=True)
            with self.assertRaises(ValueError):
                ensure_outputs_outside_roots([linked / "census.json"], [samples])

    def test_verified_ledger_requires_visible_proof_gates_and_event(self) -> None:
        ledger = {
            "schema_version": 1,
            "status_contract": census.REPAIR_STATUS_CONTRACT,
            "families": [{
                "family_key": "effect/fixture@1",
                "repair_state": "bounded-verified",
                "runtime_proof_state": "partial-chain",
                "regression_protection_state": "synthetic",
                "regression_gates": [{"kind": "synthetic-positive", "reference": "fixture"}],
                "events": [],
            }],
        }
        failures = census.validate_repair_ledger(ledger, {"effect/fixture@1"})
        self.assertEqual(
            {failure["code"] for failure in failures},
            {
                "verified-repair-lacks-visible-proof",
                "verified-repair-lacks-targeted-regression-protection",
                "verified-repair-lacks-regression-gates",
                "verified-repair-lacks-event",
                "verified-repair-missing-fields",
                "verified-repair-field-invalid",
            },
        )

    def test_valid_verified_ledger_and_invalid_enums(self) -> None:
        valid = {
            "schema_version": 1,
            "status_contract": census.REPAIR_STATUS_CONTRACT,
            "families": [{
                "family_key": "effect/fixture@1",
                "repair_state": "bounded-verified",
                "runtime_proof_state": "visible-chain-closed",
                "regression_protection_state": "targeted-runtime",
                "root_cause": "typed public cause",
                "public_fix": "public fix",
                "commit": "abcdef0",
                "targeted_samples": ["fixture"],
                "roi_evidence": ["report#roi"],
                "remaining_boundaries": ["official parity unproven"],
                "regression_gates": [
                    {"kind": "synthetic-positive", "reference": "test#positive"},
                    {"kind": "synthetic-negative", "reference": "test#negative"},
                    {"kind": "targeted-runtime", "reference": "report#runtime"},
                ],
                "events": [{
                    "date": "2026-08-13",
                    "state": "bounded-verified",
                    "commit": "abcdef0",
                    "evidence_refs": ["report#runtime"],
                    "notes": "bounded fixture",
                }],
            }],
        }
        self.assertFalse(census.validate_repair_ledger(valid, {"effect/fixture@1"}))
        rendered = census.render_markdown({
            "summary": {
                "discovered_sample_count": 0, "parsed_sample_count": 0,
                "matrix_sample_count": 0, "matrix_coverage_state": "current-complete",
                "added_since_matrix": [], "occurrence_count": 0, "family_count": 0,
                "parameter_profile_count": 0, "schema_field_profile_count": 0,
                "package_entry_count": 0, "package_unique_path_count": 0,
                "package_byte_count": 0, "unclassified_count": 0,
                "generic_or_unknown_family_count": 0,
                "texture": {
                    "physical_resource_count": 0, "physical_format_counts": {},
                    "physical_feature_counts": {}, "use_occurrence_count": 0,
                    "use_state_counts": {},
                },
                "object_kind_counts": {}, "visible_object_kind_counts": {},
                "effect_instance_count": 0, "particle_layer_count": 0,
                "dynamic_feature_counts": {},
            },
            "samples": [], "families": [], "occurrences": [],
            "repair_ledger": valid,
        })
        self.assertIn("`effect/fixture@1`", rendered)
        self.assertIn("`bounded-verified / visible-chain-closed / targeted-runtime`", rendered)
        self.assertIn("修复事件（非能力状态）", rendered)
        self.assertIn("不是该 family 的能力实现、current、support 或待办状态", rendered)
        self.assertIn("`untriaged` 不表示缺失", rendered)
        self.assertIn("public fix", rendered)
        self.assertIn("official parity unproven", rendered)
        valid["families"][0]["repair_state"] = "complete"
        self.assertIn(
            "repair-state-invalid",
            {failure["code"] for failure in census.validate_repair_ledger(
                valid, {"effect/fixture@1"}
            )},
        )

    def test_repair_references_gate_accepts_resolved_and_transient_targets(self) -> None:
        # A kind outside the built-in defaults proves the gate reads the ledger's
        # own contract instead of silently falling back to the defaults.
        ledger = {
            "entry_contract": {
                "regression_gate_kinds": [
                    *census.DEFAULT_REGRESSION_GATE_KINDS, "fixture-only-kind",
                ],
            },
            "families": [{
                "family_key": "effect/fixture@1",
                "commit": "uncommitted-working-tree",
                "targeted_samples": ["3747492842"],
                "roi_evidence": [
                    "script/scene_capability_census.py#anchor",
                    "/private/tmp/mwx-some-run/report.json sha256=deadbeef",
                ],
                "regression_gates": [
                    {
                        "kind": "synthetic-positive",
                        "reference": "script/tests/test_scene_capability_census.py"
                                     "#test_family_key_ignores_concrete_revision_values",
                    },
                    {
                        "kind": "fixture-only-kind",
                        "reference": "script/scene_capability_census.py"
                                     "#validate_repair_references",
                    },
                    {
                        "kind": "targeted-runtime",
                        "reference": "/private/tmp/mwx-some-run/report.json#3747492842",
                    },
                ],
                "events": [{
                    "date": "2026-09-17",
                    "state": "implemented",
                    "commit": "abcdef0",
                    "evidence_refs": ["script/scene_capability_census.py#anchor"],
                    "notes": "fixture",
                }],
            }],
        }
        failures = census.validate_repair_references(
            ledger, {"3747492842"}, census.REPOSITORY_ROOT
        )
        self.assertEqual(failures, [])

    def test_repair_references_gate_rejects_dangling_and_unknown_targets(self) -> None:
        ledger = {
            "entry_contract": {"regression_gate_kinds": list(census.DEFAULT_REGRESSION_GATE_KINDS)},
            "families": [{
                "family_key": "effect/fixture@1",
                "commit": "not-a-commit",
                "targeted_samples": ["0000000000"],
                "roi_evidence": ["docs/scene/semantics/does-not-exist.md"],
                "regression_gates": [
                    {
                        "kind": "synthetic-positive",
                        "reference": "script/tests/test_scene_dynamic_snapshot.py"
                                     "#test_symbol_absent_from_every_file_zz",
                    },
                    {
                        "kind": "synthetic-negative",
                        "reference": "script/tests/test_missing_fixture_file.py#test_nothing",
                    },
                    {
                        "kind": "synthetic-negative",
                        "reference": "../outside-the-repository.py#test_nothing",
                    },
                    {"kind": "made-up-kind", "reference": "script/tests/whatever.py#test_x"},
                ],
                "events": [{
                    "date": "2026-09-17",
                    "state": "implemented",
                    "commit": "abcdef0",
                    "evidence_refs": ["docs/scene/semantics/does-not-exist.md"],
                    "notes": "fixture",
                }],
            }],
        }
        codes = {failure["code"] for failure in census.validate_repair_references(
            ledger, {"3747492842"}, census.REPOSITORY_ROOT
        )}
        self.assertEqual(codes, {
            "repair-sample-reference-unknown",
            "repair-gate-symbol-missing",
            "repair-gate-file-missing",
            "repair-gate-reference-outside-repository",
            "repair-gate-kind-unknown",
            "repair-evidence-file-missing",
            "repair-commit-shape-invalid",
        })

    def test_default_repair_ledger_has_no_dangling_references(self) -> None:
        ledger = census.load_repair_ledger(census.DEFAULT_LEDGER)
        snapshot = json.loads(
            (census.REPOSITORY_ROOT / "script/scene_capability_census_snapshot.json")
            .read_text(encoding="utf-8")
        )
        sample_ids: set[str] = set()

        def collect(node: object) -> None:
            if isinstance(node, dict):
                values = node.get("sample_ids")
                if isinstance(values, list):
                    sample_ids.update(v for v in values if isinstance(v, str))
                for value in node.values():
                    collect(value)
            elif isinstance(node, list):
                for value in node:
                    collect(value)

        collect(snapshot)
        self.assertTrue(sample_ids)
        failures = census.validate_repair_references(
            ledger, sample_ids, census.REPOSITORY_ROOT
        )
        self.assertEqual(failures, [])

    def test_repair_references_gate_never_raises_on_malformed_input(self) -> None:
        malformed = [
            None,
            [],
            "not a ledger",
            {"families": 5},
            {"families": [{"family_key": "a", "regression_gates": 5}]},
            {"families": [{"family_key": "a", "regression_gates": True}]},
            {"families": [{"family_key": "a", "regression_gates": [
                {"kind": [], "reference": "script/tests/test_scene_capability_census.py#x"},
            ]}]},
            {"families": [{"family_key": "a", "targeted_samples": 7, "roi_evidence": 7}]},
            {"families": [{"family_key": "a", "events": 7}]},
            {"families": [{"family_key": "a", "events": [{"evidence_refs": 7}]}]},
            {"families": [{"family_key": "a", "regression_gates": [
                {"kind": "synthetic-positive", "reference": "a\u0000b.py#x"},
            ]}]},
            {"families": 5, "entry_contract": 7},
        ]
        for index, ledger in enumerate(malformed):
            with self.subTest(index=index):
                failures = census.validate_repair_references(
                    ledger, {"3747492842"}, census.REPOSITORY_ROOT
                )
                self.assertIsInstance(failures, list)
        self.assertEqual(
            {"repair-ledger-not-object"},
            {failure["code"] for failure in census.validate_repair_references(
                None, set(), census.REPOSITORY_ROOT
            )},
        )

    def test_repair_references_gate_rejects_references_that_escape(self) -> None:
        ledger = {
            "families": [{
                "commit": "abcdef0",
                "roi_evidence": [
                    "../../../../etc/hosts",
                    "#anchor only",
                ],
                "regression_gates": [
                    {
                        "kind": "synthetic-positive",
                        "reference": "../sibling-with-same-prefix/file.py#test_x",
                    },
                ],
            }],
        }
        codes = {failure["code"] for failure in census.validate_repair_references(
            ledger, set(), census.REPOSITORY_ROOT
        )}
        self.assertEqual(codes, {
            "repair-gate-reference-outside-repository",
            "repair-evidence-reference-outside-repository",
        })

    def test_repair_gate_symbol_must_be_a_whole_identifier(self) -> None:
        ledger = {
            "families": [{
                "commit": "abcdef0",
                "regression_gates": [
                    {
                        "kind": "synthetic-positive",
                        "reference": "script/scene_capability_census.py"
                                     "#validate_repair_references",
                    },
                    {
                        "kind": "synthetic-negative",
                        "reference": "script/scene_capability_census.py"
                                     "#validate_repair",
                    },
                ],
            }],
        }
        failures = census.validate_repair_references(
            ledger, set(), census.REPOSITORY_ROOT
        )
        self.assertEqual(
            [failure["code"] for failure in failures],
            ["repair-gate-symbol-missing"],
        )


class SceneCapabilityFamilyMapTests(unittest.TestCase):
    def test_default_family_map_loads_without_structural_failures(self) -> None:
        family_map, failures = census.load_family_map(census.DEFAULT_FAMILY_MAP)
        self.assertEqual(failures, [])
        self.assertTrue(family_map["vocabulary"])
        self.assertTrue(family_map["rules"])

    def test_default_family_map_anchors_resolve_in_authority_docs(self) -> None:
        family_map, failures = census.load_family_map(census.DEFAULT_FAMILY_MAP)
        self.assertEqual(failures, [])
        self.assertEqual(
            census.family_map_anchor_failures(family_map, census.REPOSITORY_ROOT),
            [],
        )

    def test_apply_family_map_matches_rules_and_records_unknown(self) -> None:
        family_map = {
            "schema_version": 1,
            "vocabulary": {
                "cap.a.one": {"authority": {"doc": "d.md", "row": "r"}, "scope": "s"},
            },
            "rules": [
                {
                    "rule_id": "rule.a.k1",
                    "match": {"domain": "a", "kind": "k1"},
                    "capabilities": [{"capability": "cap.a.one", "profile": "p-coarse"}],
                },
                {
                    "rule_id": "rule.a.fallback",
                    "match": {"domain": "a"},
                    "unknown_reason": "fallback-unknown",
                },
            ],
            "family_overrides": {"a/k2@x": {"unknown_reason": "manual-unknown"}},
        }
        self.assertEqual(census._family_map_structural_failures(family_map), [])
        families = [
            {"family_key": "a/k1@x", "domain": "a", "kind": "k1", "occurrence_count": 2, "sample_count": 2, "sample_ids": ["s1", "s2"]},
            {"family_key": "a/k9@y", "domain": "a", "kind": "k9", "occurrence_count": 3, "sample_count": 2, "sample_ids": ["s2", "s3"]},
            {"family_key": "a/k2@x", "domain": "a", "kind": "k2", "occurrence_count": 1, "sample_count": 1, "sample_ids": ["s1"]},
        ]
        apply_failures: list[dict] = []
        stats = census._apply_family_map(families, family_map, apply_failures)
        self.assertEqual(apply_failures, [])
        self.assertEqual(families[0]["capability_state"], "mapped")
        self.assertEqual(families[0]["capability_refs"][0]["capability"], "cap.a.one")
        self.assertEqual(families[0]["capability_refs"][0]["rule_id"], "rule.a.k1")
        self.assertEqual(families[1]["capability_state"], "unknown")
        self.assertEqual(families[1]["capability_unknown_reason"], "fallback-unknown")
        self.assertEqual(families[2]["capability_unknown_reason"], "manual-unknown")
        self.assertEqual(stats["mapped_family_count"], 1)
        self.assertEqual(stats["unknown_family_count"], 2)
        self.assertEqual(stats["per_capability"]["cap.a.one"]["occurrence_count"], 2)
        self.assertEqual(stats["per_capability"]["cap.a.one"]["sample_count"], 2)

    def test_structural_failures_capture_undefined_capability_and_rule_order(self) -> None:
        bad = {
            "schema_version": 1,
            "vocabulary": {
                "cap.a.one": {"authority": {"doc": "d.md", "row": "r"}, "scope": "s"},
            },
            "rules": [
                {
                    "rule_id": "rule.bad.ref",
                    "match": {"domain": "a", "kind": "k"},
                    "capabilities": [{"capability": "cap.missing.x", "profile": "p"}],
                },
                {"rule_id": "rule.bad.none", "match": {"domain": "a"}},
                {"rule_id": "rule.fallback", "match": {"domain": "a"}, "unknown_reason": "fb"},
                {"rule_id": "rule.bad.order", "match": {"domain": "b"}, "unknown_reason": "fb"},
                {
                    "rule_id": "rule.bad.late-specific",
                    "match": {"domain": "b", "kind": "k"},
                    "capabilities": [{"capability": "cap.a.one", "profile": "p"}],
                },
                {"rule_id": "rule.bad.dup", "match": {"domain": "a"}, "unknown_reason": "fb"},
                {"rule_id": "rule.fallback", "match": {"domain": "c"}, "unknown_reason": "fb"},
            ],
            "family_overrides": {
                "a/bad@type": "bogus",
                "a/bad@outcome": {"profile": "p"},
                "a/bad@ref": {"capabilities": [{"capability": "cap.missing.x", "profile": "p"}]},
                "a/bad@empty-reason": {"unknown_reason": ""},
                "a/bad@capabilities-type": {"capabilities": "bogus"},
                "a/good@override": {"unknown_reason": "manual-unknown"},
            },
        }
        codes = {
            item["code"] for item in census._family_map_structural_failures(bad)
        }
        self.assertIn("family-map-undefined-capability", codes)
        self.assertIn("family-map-rule-outcome-required", codes)
        self.assertIn("family-map-fallback-before-specific", codes)
        self.assertIn("family-map-invalid-rule-id", codes)
        self.assertIn("family-map-invalid-override", codes)
        self.assertIn("family-map-override-outcome-required", codes)
        self.assertIn("family-map-invalid-capabilities-type", codes)

    def test_structural_failures_attribute_override_refs_with_clean_rules(self) -> None:
        clean_rules_map = {
            "schema_version": 1,
            "vocabulary": {
                "cap.a.one": {"authority": {"doc": "d.md", "row": "r"}, "scope": "s"},
            },
            "rules": [
                {
                    "rule_id": "rule.a.fallback",
                    "match": {"domain": "a"},
                    "unknown_reason": "fallback-unknown",
                },
            ],
            "family_overrides": {
                "a/good@x": {"capabilities": [{"capability": "cap.missing.x", "profile": "p"}]},
            },
        }
        failures = census._family_map_structural_failures(clean_rules_map)
        self.assertEqual(
            [failure["code"] for failure in failures],
            ["family-map-undefined-capability"],
        )
        self.assertEqual(failures[0].get("family_key"), "a/good@x")

    def test_apply_family_map_defends_against_malformed_override(self) -> None:
        family_map = {
            "schema_version": 1,
            "vocabulary": {},
            "rules": [],
            "family_overrides": {"a/k1@x": "bogus"},
        }
        families = [
            {"family_key": "a/k1@x", "domain": "a", "kind": "k1", "occurrence_count": 1, "sample_count": 1, "sample_ids": ["s1"]},
        ]
        apply_failures: list[dict] = []
        stats = census._apply_family_map(families, family_map, apply_failures)
        self.assertEqual(families[0]["capability_state"], "unknown")
        self.assertEqual(families[0]["capability_unknown_reason"], "family-map-invalid-override")
        self.assertIn(
            "family-map-invalid-override",
            {failure["code"] for failure in apply_failures},
        )
        self.assertEqual(stats["unknown_family_count"], 1)

    def test_anchor_failures_report_missing_row(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            doc = root / "ledger.md"
            doc.write_text("# row exists here\n", encoding="utf-8")
            family_map = {
                "vocabulary": {
                    "cap.ok.one": {
                        "authority": {"doc": "ledger.md", "row": "row exists"},
                        "scope": "s",
                    },
                    "cap.bad.one": {
                        "authority": {"doc": "ledger.md", "row": "not present"},
                        "scope": "s",
                    },
                },
            }
            failures = census.family_map_anchor_failures(family_map, root)
            self.assertEqual(len(failures), 1)
            self.assertEqual(failures[0]["capability"], "cap.bad.one")
            self.assertEqual(failures[0]["code"], "family-map-anchor-missing")


if __name__ == "__main__":
    unittest.main()
