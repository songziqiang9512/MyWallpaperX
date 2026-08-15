#!/usr/bin/env python3

from __future__ import annotations

import json
import io
import struct
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path


SCRIPT_ROOT = Path(__file__).resolve().parents[1]
if str(SCRIPT_ROOT) not in sys.path:
    sys.path.insert(0, str(SCRIPT_ROOT))

import scene_capability_census as census
from scene_capability_census_io import PkgArchive, ensure_outputs_outside_roots
from scene_capability_census_profiles import family_key


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
                "effects": [{
                    "id": 9,
                    "file": "effects/fixture/effect.json",
                    "visible": True,
                    "passes": [{
                        "id": 0,
                        "combos": {"MASK": 0},
                        "constantshadervalues": {
                            "alpha": {
                                "script": "export function update() { return engine.frametime; }",
                                "value": 1,
                            }
                        },
                        "textures": [None, "mask"],
                    }],
                }],
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
            }]})),
            ("particles/root.json", json_bytes({
                "maxcount": 10, "starttime": 0,
                "material": "materials/particle.json",
                "emitter": [{"id": 1, "name": "sphererandom", "rate": 2}],
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
            ("shaders/fixture.vert", b"uniform mat4 g_ModelViewProjectionMatrix;\nvoid main() {}\n"),
            ("shaders/fixture.frag", (
                b'uniform sampler2D g_Texture0; // {"mode":"rgbmask","combo":"MASK"}\n'
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
                "texture", "particle", "dynamic-input", "project-property",
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
            self.assertEqual({item["effective_visibility"] for item in image_slots}, {"hidden"})
            self.assertTrue(all(profile.get("occurrence_refs") for profile in first["parameter_profiles"]))

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
            self.assertEqual(stored["validation"]["occurrence_index"]["count"], 43)
            self.assertEqual(len(stored["validation"]["occurrence_index"]["items"]), 43)
            self.assertEqual(stored["samples"][0]["occurrence_count"], 43)
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


if __name__ == "__main__":
    unittest.main()
