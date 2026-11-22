#!/usr/bin/env python3
"""Focused contract tests for the Scene sample debug archive."""

from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import script.scene_sample_debug_archive as archive_module
from script.scene_sample_debug_archive import _json, build_archive


class SceneSampleDebugArchiveTests(unittest.TestCase):
    def _write(self, path: Path, value: object) -> Path:
        path.write_text(json.dumps(value), encoding="utf-8")
        return path

    def test_unreported_samples_are_explicit_and_reported_chain_is_not_visual_pass(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            samples = root / "Scene"
            (samples / "10").mkdir(parents=True)
            (samples / "20").mkdir()
            snapshot = self._write(root / "snapshot.json", {
                "samples": [
                    {
                        "sample_id": "10", "title": "Ten",
                        "project_sha256": "p10", "package_sha256": "k10",
                        "tree_sha256": "t10",
                        "parse_state": "parsed", "object_count": 1,
                        "occurrence_count": 1, "visible_occurrence_count": 1,
                        "effect_instance_count": 0, "particle_layer_count": 0,
                        "dynamic_feature_counts": {},
                    },
                    {
                        "sample_id": "20", "title": "Twenty",
                        "project_sha256": "p20", "package_sha256": "k20",
                        "parse_state": "parsed", "object_count": 1,
                        "occurrence_count": 1, "visible_occurrence_count": 1,
                        "effect_instance_count": 0, "particle_layer_count": 0,
                        "dynamic_feature_counts": {},
                    },
                ]
            })
            report = self._write(root / "report.json", {
                "matrix": "identity.json", "matrix_sha256": "matrix",
                "app_identity": {"bundle_id": "test"},
                "samples": [{
                    "id": "10", "passed": True, "failures": [],
                    "exit_code": 0, "timed_out": False,
                    "hashes": {"project_sha256": "p10", "package_sha256": "k10", "tree_sha256": "t10"},
                    "evidence": {"ready_non_black": True, "after_non_black": True},
                    "runtime": {
                        "surfaces": 1,
                        "resolved_material_graph_execution": {
                            "has_evidence": True,
                            "executor": {"failure_count": 0},
                            "layer_routes": {
                                "accepted_layer_ids": [1],
                                "compositor_consumed_layer_ids": [1],
                                "next_frame_layer_ids": [1],
                            },
                            "graph_observations": {},
                        },
                    },
                }]
            })

            expected = {path: hashlib.sha256(path.read_bytes()).hexdigest() for path in (snapshot, report)}
            reads = {path: 0 for path in expected}
            original_open = Path.open

            def observed_open(path: Path, *args: object, **kwargs: object):
                if path in reads:
                    reads[path] += 1
                return original_open(path, *args, **kwargs)

            with patch.object(Path, "open", observed_open):
                archive = build_archive(samples, snapshot, [report])

            self.assertEqual(reads, {snapshot: 1, report: 1})
            self.assertEqual(archive["source"]["censusSnapshot"]["sha256"], expected[snapshot])
            self.assertEqual(archive["reports"][0]["sha256"], expected[report])
            self.assertEqual(archive["samples"][0]["evidence"]["report"]["sha256"], expected[report])

        self.assertEqual(archive["summary"]["sampleCount"], 2)
        self.assertEqual(archive["summary"]["reportedSampleCount"], 1)
        statuses = {item["id"]: item["runtime"]["status"] for item in archive["samples"]}
        self.assertEqual(statuses, {
            "10": "terminal-compositor-observed-visual-review",
            "20": "not-run",
        })
        self.assertEqual(
            archive["samples"][0]["nextAction"],
            "perform-authored-preview-and-next-frame-visual-review",
        )
        self.assertEqual(
            archive["claimBoundary"],
            "runtime-first-breakpoint-and-lifecycle-diagnostics-only-not-visual-correctness",
        )

    def test_attempts_keep_original_failure_and_select_last_explicit_report(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            samples = root / "Scene"
            (samples / "10").mkdir(parents=True)
            hashes = {"project_sha256": "project", "package_sha256": "package", "tree_sha256": "tree"}
            snapshot = self._write(root / "snapshot.json", {"samples": [{"sample_id": "10", "parse_state": "parsed", **hashes}]})
            raw = {"id": "10", "hashes": hashes, "evidence": {"visual_status": "not-requested"},
                   "runtime": {"surfaces": 1}, "exit_code": 0}
            first = self._write(root / "first.json", {"app_identity": {"executable_sha256": "first-app"},
                "samples": [{**raw, "timed_out": True, "passed": False}]})
            retry = self._write(root / "retry.json", {"app_identity": {"executable_sha256": "retry-app"},
                "samples": [{**raw, "passed": True}]})
            archive = build_archive(samples, snapshot, [first, retry, retry])
            row = archive["samples"][0]
            self.assertEqual(archive["summary"]["sampleCount"], 1)
            self.assertEqual(archive["summary"]["attemptCount"], 2)
            self.assertEqual(len(row["attempts"]), 2)
            self.assertEqual(row["attempts"][0]["runtime"]["firstBreakpoint"]["reasonCode"], "process-timeout")
            self.assertEqual(row["attempts"][0]["appIdentity"], {"executable_sha256": "first-app"})
            self.assertEqual(row["attempts"][1]["inputIdentity"]["status"], "matched")
            self.assertEqual(row["selectedAttempt"], row["attempts"][1]["id"])
            self.assertEqual(row["selectionBasis"], "last-explicit-report")
            reversed_row = build_archive(samples, snapshot, [retry, first])["samples"][0]
            self.assertEqual(reversed_row["runtime"]["status"], "blocked")
            self.assertEqual(reversed_row["runtime"]["firstBreakpoint"]["reasonCode"], "process-timeout")
            self.assertEqual(reversed_row["attempts"][0]["runtime"]["benchmarkResultIgnored"]["passed"], True)

    def test_identity_missing_drift_and_loose_package_are_never_qualified(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            samples = root / "Scene"
            (samples / "10").mkdir(parents=True)
            hashes = {"project_sha256": "project", "package_sha256": None, "tree_sha256": "tree"}
            census_row = {"sample_id": "10", "parse_state": "parsed", **hashes}
            snapshot = self._write(root / "snapshot.json", {"samples": [census_row]})
            report = root / "report.json"
            for actual, expected in [({}, "unknown"), ({**hashes, "tree_sha256": "different"}, "mismatch"),
                                     ({**hashes, "package_sha256": "invented"}, "mismatch"), (hashes, "matched")]:
                with self.subTest(actual=actual):
                    self._write(report, {"samples": [{"id": "10", "hashes": actual, "passed": True,
                        "runtime": {"surfaces": 1}, "evidence": {"visual_status": "not-requested"}}]})
                    row = build_archive(samples, snapshot, [report])["samples"][0]
                    self.assertEqual(row["attempts"][0]["inputIdentity"]["status"], expected)
                    if expected != "matched":
                        self.assertEqual(row["runtime"]["status"], "input-identity-" + expected)
            self._write(snapshot, {"samples": [{"sample_id": "10", "parse_state": "failed"}]})
            self._write(report, {"samples": [{"id": "10", "input_status": "source-invalid",
                "input_reason_code": "project-json-missing", "runtime": {}, "evidence": {"visual_status": "not-requested"}}]})
            row = build_archive(samples, snapshot, [report])["samples"][0]
            self.assertEqual(row["attempts"][0]["inputIdentity"]["status"], "source-invalid")
            self.assertEqual(row["runtime"]["firstBreakpoint"]["reasonCode"], "project-json-missing")

    def test_report_ids_must_be_in_census_and_unique_within_each_report(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            samples = root / "Scene"
            (samples / "10").mkdir(parents=True)
            snapshot = self._write(root / "snapshot.json", {"samples": [{"sample_id": "10"}]})
            for rows, error in [([{"id": "20"}], "outside"), ([{"id": "10"}, {"id": "10"}], "duplicate sample id within")]:
                report = self._write(root / "report.json", {"samples": rows})
                with self.subTest(rows=rows), self.assertRaisesRegex(ValueError, error):
                    build_archive(samples, snapshot, [report])

    def test_failed_app_verification_keeps_observations_but_cannot_qualify_matched_input(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            samples = root / "Scene"
            (samples / "10").mkdir(parents=True)
            hashes = {"project_sha256": "project", "package_sha256": "package", "tree_sha256": "tree"}
            occurrence = {"sample_id": "10", "occurrence_id": "component", "domain": "particle", "kind": "emitter",
                "location": {"layer_id": 1, "definition_path": "particles/root.json", "component_category": "emitter", "component_index": 0}}
            snapshot = self._write(root / "snapshot.json", {"samples": [{"sample_id": "10", "parse_state": "parsed", **hashes}],
                "validation": {"occurrence_index": {"items": [occurrence]}}})
            event = {"schemaVersion": 1, "layerID": 1, "particlePath": "particles/root.json", "category": "emitter",
                     "componentIndex": 0, "stage": "evaluated", "reason": "evaluation-completed"}
            raw = {"id": "10", "hashes": hashes, "runtime": {"surfaces": 1,
                "particle_component_observations": {"events": [event], "observed_count": 1, "parse_errors": 0},
                "resolved_material_graph_execution": {"graph_observations": {"successful_gpu_completed_layer_ids": [1]}}},
                "evidence": {"visual_status": "not-requested"}}
            for verified_after in (False, True, None):
                with self.subTest(verified_after=verified_after):
                    report = self._write(root / "report.json", {"app_identity": {"verified_after": verified_after}, "samples": [raw]})
                    row = build_archive(samples, snapshot, [report])["samples"][0]
                    self.assertEqual(row["attempts"][0]["inputIdentity"]["status"], "matched")
                    observations = row["runtime"]["occurrenceObservations"]
                    self.assertEqual(observations["sources"]["particleComponent"]["eventCount"], 1)
                    self.assertEqual(row["runtime"]["evidenceSummary"]["successfulGPUCompletedLayerIds"], [1])
                    component = observations["occurrences"][0]
                    if verified_after is False:
                        self.assertEqual(row["runtime"]["firstBreakpoint"]["reasonCode"], "measurement-app-identity-verification-failed")
                        self.assertEqual(row["nextAction"], "rerun-with-verified-app-identity")
                        self.assertEqual(component["observedStages"], ["declared"])
                        self.assertEqual(component["evidenceRefs"], [])
                    else:
                        self.assertIsNone(row["runtime"]["firstBreakpoint"])
                        self.assertEqual(component["observationState"], "executed")

    def test_inventory_parent_chain_is_not_a_runtime_denominator_and_scene_consumers_remain(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            samples = root / "Scene"
            (samples / "10").mkdir(parents=True)
            hashes = {"project_sha256": "project", "package_sha256": "package", "tree_sha256": "tree"}
            resource = {"relative_path": "materials/shared.tex", "sha256": "shared"}
            occurrences = [
                {"occurrence_id": "consumer-texture", "domain": "texture", "kind": "image-material-slot",
                    "location": {"owner_occurrence": "scene-material", "slot_index": 0}, "resource": resource},
                {"occurrence_id": "nested-default", "domain": "texture", "kind": "shader-default-slot",
                    "location": {"owner_occurrence": "shader-default", "slot_index": 0}, "resource": resource},
                {"occurrence_id": "shader-default", "domain": "texture", "kind": "shader-default-slot",
                    "location": {"owner_occurrence": "physical-shader", "slot_index": 0}, "resource": resource},
                {"occurrence_id": "scene-material", "domain": "material", "kind": "image-pass",
                    "location": {"owner_occurrence": "scene-layer", "material_pass_index": 0}},
                {"occurrence_id": "scene-layer", "domain": "layer", "kind": "image",
                    "location": {"owner_occurrence": "physical-shader", "layer_id": 11, "object_index": 0}},
                {"occurrence_id": "physical-shader", "domain": "shader", "kind": "frag", "location": {"package_entry_index": 4}},
                {"occurrence_id": "physical-texture", "domain": "texture", "kind": "package-resource",
                    "location": {"package_entry_index": 5}, "resource": resource},
            ]
            for item in occurrences:
                item["sample_id"] = "10"
            snapshot = self._write(root / "snapshot.json", {"samples": [{"sample_id": "10", "parse_state": "parsed",
                "occurrence_count": len(occurrences), **hashes}], "validation": {"occurrence_index": {"items": occurrences}}})
            raw = {"id": "10", "hashes": hashes, "runtime": {"surfaces": 1}, "evidence": {"visual_status": "not-requested"}}
            first = self._write(root / "first.json", {"samples": [raw]})
            event = {"schemaVersion": 1, "surfaceIdentity": "surface", "commandBufferToken": "submit", "gpuStatus": "completed",
                "rows": [{"kind": "material", "layerID": 11, "slot": 0, "access": "texture-bind", "outcome": "draw-encoded",
                    "source": {"logical": "asset:materials/shared.tex", "textureToken": "texture"}, "target": {"textureToken": "output"}}]}
            raw["runtime"]["composition_observations"] = {"events": [event]}
            retry = self._write(root / "retry.json", {"samples": [raw]})
            with patch.object(archive_module, "_occurrence_locations", wraps=archive_module._occurrence_locations) as indexed:
                archive = build_archive(samples, snapshot, [first, retry])
            indexed.assert_called_once()
            row = archive["samples"][0]
            observed = {item["occurrenceId"]: item for item in row["runtime"]["occurrenceObservations"]["occurrences"]}
            for identity in ("physical-shader", "physical-texture", "shader-default", "nested-default"):
                self.assertEqual(observed[identity]["consumptionScope"], "inventory-only")
                self.assertEqual(observed[identity]["observationState"], "inventory-only")
                self.assertEqual(observed[identity]["evidenceRefs"], [])
            for identity in ("scene-layer", "scene-material", "consumer-texture"):
                self.assertEqual(observed[identity]["consumptionScope"], "authored-occurrence")
            self.assertIn("bound", observed["consumer-texture"]["observedStages"])
            self.assertEqual(archive["summary"]["attemptCount"], 2)
            self.assertEqual(archive["summary"]["occurrenceScopes"], {
                "classifiedSampleCount": 1, "unclassifiedSampleCount": 0,
                "inventoryOnlyCount": 4, "runtimeCandidateCount": 3,
                "runtimeCandidateStateCounts": {"executed": 2, "unknown": 1},
            })
            self.assertEqual(row["attempts"][0]["runtime"]["occurrenceObservations"]["runtimeCandidateStateCounts"], {"unknown": 3})

    def test_occurrences_require_exact_consumer_and_component_identity_and_png_is_sample_only(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            samples = root / "Scene"
            (samples / "10").mkdir(parents=True)
            hashes = {"project_sha256": "project", "package_sha256": "package", "tree_sha256": "tree"}
            occurrences = [
                {"occurrence_id": "layer", "domain": "layer", "kind": "image", "location": {"layer_id": 1, "object_index": 0}},
                {"occurrence_id": "neighbor", "domain": "layer", "kind": "image", "location": {"layer_id": 2, "object_index": 1}},
                {"occurrence_id": "material", "domain": "material", "kind": "image-pass", "location": {"layer_id": 1, "object_index": 0, "material_pass_index": 0}},
                {"occurrence_id": "texture", "domain": "texture", "kind": "image-material-slot", "location": {"owner_occurrence": "material", "slot_index": 0}, "resource": {"relative_path": "materials/image.tex"}},
                {"occurrence_id": "root-component", "domain": "particle", "kind": "emitter", "location": {"layer_id": 1, "definition_path": "particles/root.json", "component_category": "emitter", "component_index": 0}},
                {"occurrence_id": "child-component", "domain": "particle", "kind": "emitter", "location": {"layer_id": 1, "definition_path": "particles/child.json", "component_category": "emitter", "component_index": 0}},
                {"occurrence_id": "root-renderer", "domain": "particle", "kind": "renderer", "location": {"layer_id": 1, "definition_path": "particles/root.json", "component_category": "renderer", "component_index": 2}},
                {"occurrence_id": "child-renderer", "domain": "particle", "kind": "renderer", "location": {"layer_id": 1, "definition_path": "particles/child.json", "component_category": "renderer", "component_index": 2}},
                {"occurrence_id": "inventory", "domain": "texture", "kind": "package-resource", "location": {"package_entry_index": 9}},
            ]
            for item in occurrences:
                item["sample_id"] = "10"
            snapshot = self._write(root / "snapshot.json", {"samples": [{"sample_id": "10", "parse_state": "parsed", **hashes}],
                "validation": {"occurrence_index": {"items": occurrences}}})
            bind = {"kind": "material", "layerID": 1, "slot": 0, "access": "texture-bind", "outcome": "draw-encoded",
                "source": {"logical": "asset:materials/image.tex", "textureToken": "input"}, "target": {"textureToken": "consumer-output"}}
            tail = {"kind": "tail-consume", "layerID": 1, "access": "output-texture-composite", "outcome": "terminal-consumed",
                "source": {"textureToken": "consumer-output"}, "target": {"textureToken": "terminal"}}
            event = {"schemaVersion": 1, "surfaceIdentity": "surface", "commandBufferToken": "submit", "gpuStatus": "completed", "rows": [bind, tail]}
            runtime = {"surfaces": 1, "composition_observations": {"events": [event], "parse_errors": 0},
                "particle_component_observations": {"events": [{"schemaVersion": 1, "layerID": 1, "particlePath": "particles/child.json",
                    "category": "emitter", "componentIndex": 0, "stage": "evaluated", "reason": "evaluation-completed"}]}}
            raw = {"id": "10", "hashes": hashes, "runtime": runtime,
                "evidence": {"visual_status": "not-requested", "snapshot_capture": {"status": "written", "path": "terminal.png"}}}
            report_path = root / "report.json"

            def observe():
                self._write(report_path, {"samples": [raw]})
                row = build_archive(samples, snapshot, [report_path])["samples"][0]
                return row, {item["occurrenceId"]: item for item in row["runtime"]["occurrenceObservations"]["occurrences"]}

            row, observed = observe()
            self.assertEqual(row["evidence"]["snapshotCapture"]["path"], "terminal.png")
            self.assertEqual(observed["texture"]["observationState"], "executed")
            self.assertIn("bound", observed["texture"]["observedStages"])
            self.assertIn("logical-tail-consumed", observed["texture"]["observedStages"])
            self.assertEqual(observed["texture"]["evidenceRefs"][0]["logicalTailRowIndex"], 1)
            self.assertTrue(all("terminal-consumed" not in item["observedStages"] for item in observed.values()))
            self.assertEqual(observed["child-component"]["observationState"], "executed")
            for identity in ("neighbor", "material", "root-component"):
                self.assertEqual(observed[identity]["observationState"], "unknown")
                self.assertEqual(observed[identity]["evidenceRefs"], [])
            self.assertEqual(observed["inventory"]["observationState"], "inventory-only")
            self.assertTrue(all(item["visibleContribution"] == "unknown" for item in observed.values()))

            value = json.loads(snapshot.read_text())
            texture = next(item for item in value["validation"]["occurrence_index"]["items"] if item["occurrence_id"] == "texture")
            texture["reference"] = "materials/image.tex"
            self._write(snapshot, value)
            _, observed = observe()
            self.assertIn("bound", observed["texture"]["observedStages"])
            texture["reference"] = "image"
            self._write(snapshot, value)
            bind["source"]["logical"] = "asset:image"
            bind["target"]["role"] = "group-intermediate"
            _, observed = observe()
            self.assertIn("bound", observed["texture"]["observedStages"])
            self.assertIn("logical-tail-consumed", observed["texture"]["observedStages"])
            self.assertEqual(observed["texture"]["visibleContribution"], "unknown")
            tail["access"] = "named-publication-only"
            _, observed = observe()
            self.assertNotIn("logical-tail-consumed", observed["texture"]["observedStages"])
            self.assertIn("named-publication-only", observed["layer"]["observedStages"])
            tail["access"] = "output-texture-composite"
            bind["source"]["logical"] = "asset:materials/image.tex"

            bind["outcome"] = "failed"
            _, observed = observe()
            self.assertEqual(observed["texture"]["observationState"], "failed")
            self.assertNotIn("bound", observed["texture"]["observedStages"])
            self.assertNotIn("gpu-completed", observed["texture"]["observedStages"])
            bind["access"] = "color-attachment-read"
            _, observed = observe()
            self.assertNotIn("attachment-read-encoded", observed["layer"]["observedStages"])
            bind.update(outcome="draw-encoded", access="texture-bind")

            particle = {"kind": "particle", "layerID": 1, "slot": 0, "access": "texture-bind", "outcome": "draw-encoded",
                "source": {"textureToken": "particle"}, "target": {"textureToken": "terminal"},
                "details": {"particlePath": "particles/child.json", "childTemplateIndex": "3", "rendererComponentIndex": "2"}}
            event["rows"].append(particle)
            _, observed = observe()
            self.assertIn("gpu-completed", observed["child-renderer"]["observedStages"])
            self.assertEqual(observed["root-renderer"]["observationState"], "unknown")
            self.assertNotIn("gpu-completed", observed["child-component"]["observedStages"])
            self.assertEqual(observed["child-renderer"]["instanceCoverage"], "unknown")
            event["rows"].pop()

            bind["details"] = {"selectionMetadataRole": "prepared-logical-origin", "physicalBinding": "replacement-copy"}
            _, observed = observe()
            self.assertEqual(observed["texture"]["observationState"], "unknown")
            self.assertIn("logical-origin-attributed", observed["texture"]["observedStages"])
            self.assertNotIn("bound", observed["texture"]["observedStages"])
            del bind["details"]
            bind["access"] = "color-attachment-read"
            _, observed = observe()
            self.assertEqual(observed["texture"]["evidenceRefs"], [])
            self.assertIn("attachment-read-encoded", observed["layer"]["observedStages"])
            bind["access"] = "texture-bind"

            runtime["composition_observations"]["events"] = [{**event, "rows": [bind, {**tail, "layerID": 2}]}]
            _, observed = observe()
            self.assertNotIn("logical-tail-consumed", observed["texture"]["observedStages"])
            runtime["composition_observations"]["events"] = [{**event, "gpuStatus": "cancelled-not-submitted"}]
            _, observed = observe()
            self.assertEqual(observed["texture"]["observationState"], "encoded")
            self.assertNotIn("gpu-completed", observed["texture"]["observedStages"])

            runtime["composition_observations"]["events"] = [{**event, "rows": [bind]}, {**event, "commandBufferToken": "different-submit", "rows": [tail]}]
            _, observed = observe()
            self.assertNotIn("logical-tail-consumed", observed["texture"]["observedStages"])
            runtime["composition_observations"]["events"] = [{**event, "surfaceIdentity": None}]
            _, observed = observe()
            self.assertEqual(observed["texture"]["observationState"], "unknown")
            self.assertIn("surface-or-submission-identity-unavailable", observed["texture"]["reasons"])

            runtime["composition_observations"]["events"] = [event]
            value = json.loads(snapshot.read_text())
            value["validation"]["occurrence_index"]["items"].extend([
                {"sample_id": "10", "occurrence_id": "second-material", "domain": "material", "kind": "image-pass",
                    "location": {"layer_id": 1, "object_index": 0, "material_pass_index": 1}},
                {"sample_id": "10", "occurrence_id": "second-texture", "domain": "texture", "kind": "image-material-slot",
                    "location": {"owner_occurrence": "second-material", "slot_index": 0}, "resource": {"relative_path": "materials/image.tex"}},
            ])
            self._write(snapshot, value)
            _, observed = observe()
            self.assertEqual(observed["texture"]["observationState"], "unknown")
            self.assertIn("authored-pass-identity-ambiguous", observed["texture"]["reasons"])

            raw["hashes"] = {**hashes, "tree_sha256": "different-content"}
            _, observed = observe()
            self.assertEqual(observed["texture"]["evidenceRefs"], [])
            self.assertEqual(observed["child-component"]["observationState"], "unknown")

    def test_effect_fallback_preserves_physical_copy_without_claiming_authored_execution(self) -> None:
        occurrences = [
            {"occurrence_id": identity, "domain": domain, "kind": "fixture",
             "location": {"layer_id": layer, "effect_index": effect, "object_index": layer}}
            for identity, domain, layer, effect in (
                ("layer", "layer", 11, None), ("bypassed", "effect", 11, 0),
                ("suffix", "effect", 11, 1), ("neighbor", "effect", 22, 0))
        ]
        copy = {"kind": "copy", "layerID": 11, "effectIndex": 0,
                "access": "copy-source", "outcome": "encoded"}
        runtime = {
            "effect_runtime_disposition": {"records": [
                {"layer_id": 11, "effect_index": 0, "descriptor_id": "opaque-author-id",
                 "kind": "fallback", "attribution": "exact-key", "reason": "effect-local-visual-failure"},
                {"layer_id": 22, "effect_index": 0, "kind": "fallback", "attribution": "none"}]},
            "resolved_material_graph_execution": {"graph_observations": {"visual_failure_passthroughs": [
                {"layer_id": 11, "effect_index": 0, "descriptor_id": "opaque-author-id",
                 "reason": "material-input-unavailable"}]}},
            "composition_observations": {"events": [{"schemaVersion": 1,
                "surfaceIdentity": "surface", "commandBufferToken": "submit", "gpuStatus": "completed",
                "rows": [copy, {**copy, "kind": "material", "effectIndex": 1, "outcome": "draw-encoded"},
                         {**copy, "layerID": 22}]}]},
        }
        locations = archive_module._occurrence_locations(occurrences)

        def observe(qualify=True):
            result = archive_module._occurrence_observations(occurrences, locations, runtime, qualify=qualify)
            return {item["occurrenceId"]: item for item in result["occurrences"]}

        observed = observe()
        fallback = observed["bypassed"]
        self.assertEqual(fallback["observationState"], "fallback")
        self.assertTrue({"fallback", "encoded", "gpu-completed"}.issubset(fallback["observedStages"]))
        self.assertEqual(set(fallback["reasons"]), {"effect-local-visual-failure", "material-input-unavailable"})
        self.assertTrue(any(ref.get("rowIndex") == 0 for ref in fallback["evidenceRefs"]))
        for identity in ("layer", "suffix", "neighbor"):
            self.assertEqual(observed[identity]["observationState"], "executed")
            self.assertNotIn("fallback", observed[identity]["observedStages"])
        self.assertEqual(fallback["visibleContribution"], "unknown")
        self.assertEqual(observe(False)["bypassed"]["observationState"], "unknown")
        runtime["composition_observations"]["events"] = []
        self.assertEqual(observe()["bypassed"]["observationState"], "fallback")
        self.assertEqual(observe()["suffix"]["observationState"], "unknown")

    def test_json_uses_same_utf8_bytes_for_value_and_digest_and_keeps_errors(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "input.json"
            raw = '{\r\n  "title": "壁纸", "value": 1\r\n}\n'.encode("utf-8")
            path.write_bytes(raw)
            self.assertEqual(_json(path), ({"title": "壁纸", "value": 1}, hashlib.sha256(raw).hexdigest()))
            for encoding in ("utf-16", "utf-32"):
                path.write_bytes('{"value": 1}'.encode(encoding))
                with self.subTest(encoding=encoding), self.assertRaises(UnicodeDecodeError):
                    _json(path)
            path.write_text("[1, 2]", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "JSON document is not an object"):
                _json(path)
            path.write_text("{", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "cannot load JSON") as raised:
                _json(path)
            self.assertIsInstance(raised.exception.__cause__, json.JSONDecodeError)
            path.unlink()
            with self.assertRaisesRegex(ValueError, "cannot load JSON") as raised:
                _json(path)
            self.assertIsInstance(raised.exception.__cause__, OSError)

    def test_append_normalizes_only_disjoint_subset_and_keeps_base_rows(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            samples = root / "Scene"
            (samples / "10").mkdir(parents=True)
            old_snapshot = self._write(root / "old-census.json", {"samples": [{
                "sample_id": "10", "parse_state": "parsed", "title": "Old",
            }]})
            old_report = self._write(root / "old-report.json", {
                "app_identity": {"executable_sha256": "old-app"},
                "samples": [{"id": "10", "passed": False, "runtime": {}}],
            })
            original = build_archive(samples, old_snapshot, [old_report])
            base = self._write(root / "base.json", original)
            base_bytes = base.read_bytes()
            old_snapshot.unlink()
            old_report.unlink()
            (samples / "20").mkdir()
            subset_value = {
                "snapshot": {"inputs": {"scope": "subset"}},
                "samples": [{"sample_id": "20", "parse_state": "parsed"}],
            }
            subset = self._write(root / "subset.json", subset_value)
            new_report_value = {
                "app_identity": {"executable_sha256": "new-app"},
                "samples": [{"id": "20", "passed": True, "runtime": {}}],
            }
            new_report = self._write(root / "new-report.json", new_report_value)
            real_open = Path.open

            def forbid_old_reads(path: Path, *args: object, **kwargs: object):
                if path in (old_snapshot, old_report):
                    raise AssertionError(f"old observation reopened: {path}")
                return real_open(path, *args, **kwargs)

            with patch.object(Path, "open", forbid_old_reads):
                merged = build_archive(samples, subset, [new_report], base_archive_path=base)

            self.assertEqual(base.read_bytes(), base_bytes)
            self.assertEqual(merged["samples"][0], original["samples"][0])
            self.assertEqual(merged["reports"][:1], original["reports"])
            self.assertEqual(merged["source"]["baseArchive"]["sha256"], hashlib.sha256(base_bytes).hexdigest())
            self.assertEqual(merged["source"]["censusSnapshot"]["sampleCount"], 1)
            self.assertEqual(merged["source"]["censusSnapshot"]["scope"], "subset")
            self.assertEqual(merged["summary"]["sampleCount"], 2)
            self.assertEqual(merged["summary"]["reportedSampleCount"], 2)
            self.assertEqual(sum(merged["summary"]["statusCounts"].values()), 2)
            self.assertEqual(merged["appIdentities"], [
                {"executable_sha256": "old-app"}, {"executable_sha256": "new-app"},
            ])

            for label, static_rows, report_rows, expected in (
                ("overlap", [{"sample_id": "10"}], [{"id": "10"}], "overlap"),
                ("gap", [], [], "mismatch"),
                ("duplicate", [{"sample_id": "20"}, {"sample_id": "20"}], [{"id": "20"}], "duplicate census"),
                ("outside-report", [{"sample_id": "20"}], [{"id": "10"}], "outside"),
            ):
                with self.subTest(label=label):
                    self._write(subset, {**subset_value, "samples": static_rows})
                    self._write(new_report, {**new_report_value, "samples": report_rows})
                    with self.assertRaisesRegex(ValueError, expected):
                        build_archive(samples, subset, [new_report], base_archive_path=base)


if __name__ == "__main__":
    unittest.main()
