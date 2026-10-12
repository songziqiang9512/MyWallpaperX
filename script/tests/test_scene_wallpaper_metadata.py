#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from collections import defaultdict
from pathlib import Path
from unittest import mock

SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))
DEBUG_RUNNER_SOURCE = (
    SCRIPT_DIR.parent / "MyWallpaperX/App/Debug/DebugScenePlaybackRunner.swift"
)
DEBUG_ARGUMENTS_RUNNER_SOURCE = (
    SCRIPT_DIR.parent
    / "MyWallpaperX/App/Debug/DebugScenePlaybackRunner+Arguments.swift"
)

import scene_wallpaper_benchmark as benchmark
import scene_preview_visual_evidence as visual
import generate_scene_full_matrix as matrix_generator
from script.tests.scene_wallpaper_graph_output_test_support import (
    assert_named_graph_output_publication_has_one_terminal_owner,
    assert_named_provider_terminal,
    assert_visible_provider_requires_compositor_consumption,
    assert_visible_publication_execution_metrics,
    assert_utility_capture_respects_dormant_graph_members,
)

from script.tests.scene_wallpaper_benchmark_test_support import (
    static_effect_disposition,
    shader_stage,
    runtime_evidence,
    effect_runtime_disposition_preview,
    effect_cpu_event,
    effect_route_event,
    effect_execution_log,
    graph_execution_observation,
    resolved_graph_exact_evidence,
    resolved_graph_passthrough_evidence,
    resolved_graph_effect_local_failure_evidence,
    resolved_graph_effect_recovery_evidence,
    resolved_graph_effect_recovery_log,
    resolved_graph_visual_failure_log,
)


class SceneWallpaperMetadataTests(unittest.TestCase):
    def test_runtime_evidence_metrics_preserve_slots_and_combos(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-runtime-evidence-") as directory:
            path = Path(directory) / "scene-runtime-evidence.json"
            shader_contracts = [{
                "identity": "effects/zeta",
                "sourceKind": "authoredSource",
                "stages": [
                    shader_stage("effects/zeta", "vertex", "zeta vertex"),
                    shader_stage("effects/zeta", "fragment", "zeta fragment"),
                ],
                "diagnostics": [],
                "canonicalSHA256": "b" * 64,
            }, {
                "identity": "genericimage4",
                "sourceKind": "hostBuiltin",
                "stages": [],
                "diagnostics": [],
                "canonicalSHA256": "c" * 64,
            }, {
                "identity": "effects/alpha",
                "sourceKind": "authoredSource",
                "stages": [
                    shader_stage("effects/alpha", "vertex", "alpha vertex"),
                    shader_stage("effects/alpha", "fragment", "alpha fragment"),
                ],
                "diagnostics": [{
                    "code": "malformedAnnotation",
                    "message": "bad annotation",
                    "relativePath": "shaders/effects/alpha.frag",
                    "line": 2,
                }],
                "canonicalSHA256": "a" * 64,
            }]
            effect_graphs = [{
                "effects": [{"key": "one"}, {"key": "two"}],
                "renderTargets": [{"name": "one"}, {"name": "two"}],
                "nodes": [
                    {"kind": "material"},
                    {"kind": "copy"},
                    {"kind": "swap"},
                ],
                "blockers": [{"reason": "unsupportedCondition"}],
            }, {
                "layerID": 9,
                "effects": [{
                    "key": "three",
                    "definitionPath": "Effects\\Opacity\\Effect.json",
                }],
                "renderTargets": [],
                "nodes": [{"kind": "material"}],
                "blockers": [],
            }]
            path.write_text(
                json.dumps(runtime_evidence({
                    "shaderContracts": shader_contracts,
                    "authoredEffectRenderPlans": effect_graphs,
                    "renderDescriptor": {
                        "materialPasses": [{
                            "textureSlots": [None, None, "phase.tex"],
                            "combos": {"VERSION": 2, "MODE": 0},
                        }],
                        "effectDefinitions": [{
                            "passes": [
                                {"materialPath": "materials/effects/test.json"},
                                {"command": "copy"},
                                {"command": "swap"},
                            ],
                            "framebuffers": [{"name": "one"}, {"name": "two"}],
                        }],
                        "effectDefinitionDiagnostics": [{"code": "unknownFields"}],
                        "builtInReferenceCount": 4,
                        "missingResources": ["one", "two"],
                        "layers": [{
                            "id": 1,
                            "visible": False,
                            "parentID": None,
                            "effects": [],
                        }, {
                            "effects": [{"file": "effects/test.json", "passes": [{
                                "textureSlots": [None, "normal.tex"],
                                "combos": {"REPEAT": 1},
                            }]}],
                            "id": 7,
                            "visible": True,
                            "parentID": 1,
                            "text": "property gate",
                            "contentKind": "solid",
                            "parallaxDepthXY": [2, 0],
                            "disablesParallaxPropagation": True,
                        }, {
                            "id": 8,
                            "visible": True,
                            "parentID": None,
                            "contentKind": "solid",
                            "colorRGB": [0.2, 0.4, 0.6],
                            "effects": [],
                        }, {
                            "id": 9,
                            "visible": True,
                            "parentID": 8,
                            "contentKind": "solid",
                            "effects": [],
                        }],
                    },
                })),
                encoding="utf-8",
            )
            metrics = benchmark.runtime_evidence_metrics(path)
            self.assertEqual(metrics["schema_version"], 1)
            self.assertEqual(metrics["shader_contract_count"], 3)
            self.assertEqual(metrics["shader_contract_authored_count"], 2)
            self.assertEqual(metrics["shader_contract_builtin_count"], 1)
            self.assertEqual(metrics["shader_contract_stage_count"], 4)
            self.assertEqual(metrics["shader_contract_diagnostic_count"], 1)
            self.assertEqual(
                metrics["shader_contract_aggregate_sha256"],
                "33c1609a3d79a75fef6e568b233d01a0b94ab6233d6137cc828418dfa74a9f4c",
            )
            self.assertEqual(metrics["effect_texture_slot_count"], 2)
            self.assertEqual(metrics["effect_texture_slot_hole_count"], 1)
            self.assertEqual(metrics["effect_combo_entry_count"], 1)
            self.assertEqual(metrics["material_texture_slot_count"], 3)
            self.assertEqual(metrics["material_texture_slot_hole_count"], 2)
            self.assertEqual(metrics["material_combo_entry_count"], 2)
            self.assertEqual(metrics["effect_definition_count"], 1)
            self.assertEqual(metrics["effect_definition_pass_count"], 3)
            self.assertEqual(metrics["effect_definition_material_pass_count"], 1)
            self.assertEqual(metrics["effect_definition_fbo_count"], 2)
            self.assertEqual(metrics["effect_definition_copy_command_count"], 1)
            self.assertEqual(metrics["effect_definition_swap_command_count"], 1)
            self.assertEqual(metrics["effect_definition_diagnostic_count"], 1)
            self.assertEqual(metrics["effect_graph_layer_count"], 2)
            self.assertEqual(metrics["effect_graph_effect_count"], 3)
            self.assertEqual(metrics["effect_graph_node_count"], 4)
            self.assertEqual(metrics["effect_graph_material_node_count"], 2)
            self.assertEqual(metrics["effect_graph_copy_node_count"], 1)
            self.assertEqual(metrics["effect_graph_swap_node_count"], 1)
            self.assertEqual(metrics["effect_graph_render_target_count"], 2)
            self.assertEqual(metrics["effect_graph_blocker_count"], 1)
            self.assertEqual(
                metrics["effect_graph_blocker_reasons"],
                {"unsupportedCondition": 1},
            )
            self.assertEqual(metrics["effect_graph_unblocked_layer_count"], 1)
            self.assertEqual(
                metrics["effect_graph_sha256"],
                hashlib.sha256(json.dumps(
                    effect_graphs,
                    ensure_ascii=True,
                    sort_keys=True,
                    separators=(",", ":"),
                ).encode("utf-8")).hexdigest(),
            )
            self.assertEqual(metrics["visible_layer_count"], 3)
            self.assertEqual(metrics["visible_layer_ids"], [7, 8, 9])
            self.assertEqual(metrics["root_layer_count"], 2)
            self.assertEqual(metrics["child_edge_count"], 2)
            self.assertEqual(metrics["parent_layer_count"], 2)
            self.assertEqual(metrics["max_hierarchy_depth"], 1)
            self.assertEqual(metrics["effective_visible_layer_count"], 2)
            self.assertEqual(metrics["effective_visible_layer_ids"], [8, 9])
            self.assertEqual(
                metrics["stock_opacity_single_effect_candidate_layer_ids"],
                [9],
            )
            self.assertEqual(metrics["solid_layer_count"], 3)
            self.assertEqual(metrics["solid_layer_ids"], [7, 8, 9])
            self.assertEqual(metrics["authored_solid_color_layer_count"], 1)
            self.assertEqual(metrics["authored_solid_color_layer_ids"], [8])
            self.assertEqual(metrics["effective_visible_solid_layer_count"], 2)
            self.assertEqual(metrics["effective_visible_solid_layer_ids"], [8, 9])
            self.assertEqual(metrics["authored_parallax_layer_count"], 1)
            self.assertEqual(metrics["authored_parallax_layer_ids"], [7])
            self.assertEqual(metrics["parallax_propagation_block_count"], 1)
            self.assertEqual(metrics["text_values"], ["property gate"])
            self.assertEqual(metrics["effect_files"], ["effects/test.json"])
            self.assertEqual(metrics["built_in_reference_count"], 4)
            self.assertEqual(metrics["missing_resource_count"], 2)
            self.assertIsNone(metrics["error"])

    def test_runtime_evidence_metrics_reject_invalid_slot_shape(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-runtime-evidence-") as directory:
            path = Path(directory) / "scene-runtime-evidence.json"
            path.write_text(json.dumps(runtime_evidence({
                "shaderContracts": [],
                "renderDescriptor": {
                    "layers": [{"effects": [{"passes": [{"textureSlots": "bad", "combos": {}}]}]}],
                    "materialPasses": [],
                },
            })), encoding="utf-8")
            metrics = benchmark.runtime_evidence_metrics(path)
            self.assertIsNone(metrics["schema_version"])
            self.assertIn("invalid shape", metrics["error"])

    def test_shader_contract_aggregate_is_independent_of_contract_order(self) -> None:
        contracts = [{
            "identity": "effects/zeta",
            "sourceKind": "authoredSource",
            "stages": [
                shader_stage("effects/zeta", "vertex", "zeta vertex"),
                shader_stage("effects/zeta", "fragment", "zeta fragment"),
            ],
            "diagnostics": [],
            "canonicalSHA256": "b" * 64,
        }, {
            "identity": "genericimage4",
            "sourceKind": "hostBuiltin",
            "stages": [],
            "diagnostics": [],
            "canonicalSHA256": "c" * 64,
        }]
        forward = benchmark.shader_contract_metrics(contracts)
        reverse = benchmark.shader_contract_metrics(list(reversed(contracts)))
        self.assertEqual(
            forward["shader_contract_aggregate_sha256"],
            reverse["shader_contract_aggregate_sha256"],
        )

    def test_runtime_evidence_metrics_reject_missing_or_malformed_shader_contracts(self) -> None:
        valid_contract = {
            "identity": "effects/example",
            "sourceKind": "authoredSource",
            "stages": [
                shader_stage("effects/example", "vertex", "example vertex"),
                shader_stage("effects/example", "fragment", "example fragment"),
            ],
            "diagnostics": [],
            "canonicalSHA256": "a" * 64,
        }
        malformed_contract_sets = {
            "missing": None,
            "not-an-array": {},
            "non-object-contract": ["bad"],
            "missing-identity": [{
                key: value for key, value in valid_contract.items() if key != "identity"
            }],
            "unknown-source-kind": [{**valid_contract, "sourceKind": "generated"}],
            "stages-not-an-array": [{**valid_contract, "stages": {}}],
            "stage-not-an-object": [{**valid_contract, "stages": ["bad"]}],
            "stage-missing-fields": [{**valid_contract, "stages": [{}]}],
            "stage-hash-mismatch": [{
                **valid_contract,
                "stages": [{**valid_contract["stages"][0], "source": "changed"}],
            }],
            "diagnostics-not-an-array": [{**valid_contract, "diagnostics": {}}],
            "diagnostic-not-an-object": [{**valid_contract, "diagnostics": ["bad"]}],
            "diagnostic-missing-fields": [{**valid_contract, "diagnostics": [{}]}],
            "empty-canonical-sha": [{**valid_contract, "canonicalSHA256": ""}],
            "malformed-canonical-sha": [{**valid_contract, "canonicalSHA256": "A" * 64}],
            "duplicate-identity": [valid_contract, valid_contract],
            "builtin-with-stage": [{
                **valid_contract,
                "identity": "genericimage2",
                "sourceKind": "hostBuiltin",
                "stages": [shader_stage("genericimage2", "vertex", "bad")],
            }],
        }
        with tempfile.TemporaryDirectory(prefix="mwx-scene-runtime-evidence-") as directory:
            path = Path(directory) / "scene-runtime-evidence.json"
            for case, contracts in malformed_contract_sets.items():
                with self.subTest(case=case):
                    payload = {
                        "renderDescriptor": {"layers": [], "materialPasses": []},
                    }
                    if case != "missing":
                        payload["shaderContracts"] = contracts
                    path.write_text(
                        json.dumps(runtime_evidence(payload)), encoding="utf-8"
                    )
                    metrics = benchmark.runtime_evidence_metrics(path)
                    self.assertIsNone(metrics["schema_version"])
                    self.assertIsNone(metrics["shader_contract_aggregate_sha256"])
                    self.assertTrue(metrics["error"])

    def test_runtime_log_patterns_capture_ready_and_release(self) -> None:
        ready = benchmark.READY_RE.search(
            "MWX DEBUG SCENE: phase=ready root=/tmp/sample layers=35 "
            "imageLayers=24 effects=29 surfaces=1 startupElapsedMS=1825.250 "
            "windows=42 previewLog=/tmp/log "
            "runtimeEvidence=/tmp/evidence/scene-runtime-evidence.json"
        )
        evidence = benchmark.RUNTIME_EVIDENCE_RE.search(
            "MWX DEBUG SCENE: phase=ready root=/tmp/sample layers=35 "
            "imageLayers=24 effects=29 surfaces=1 startupElapsedMS=1825.250 "
            "windows=42 previewLog=/tmp/log "
            "runtimeEvidence=/tmp/evidence/scene-runtime-evidence.json"
        )
        stopped = benchmark.STOPPED_RE.search(
            "MWX DEBUG SCENE: phase=stopped surfacesBefore=1 surfacesAfter=0"
        )
        live = benchmark.live_property_update_metrics(
            "MWX DEBUG SCENE: phase=live-property-update accepted=true "
            "surfacesBefore=1 surfacesAfter=1 windowsBefore=42 windowsAfter=42 "
            "keys=newproperty11"
        )
        loaded = benchmark.LOADED_RE.search("loaded: 20 / 24")
        text_loaded = benchmark.TEXT_LOADED_RE.search("text loaded: 10 / 10")
        particle_loaded = benchmark.PARTICLE_LOADED_RE.search("particle loaded: 3 / 4")
        particle_refract = benchmark.PARTICLE_REFRACT_LOADED_RE.search(
            "particle refract loaded: 2"
        )
        particle_live = benchmark.PARTICLE_INITIAL_LIVE_RE.search("particle initial live: 96")
        camera = benchmark.CAMERA_RE.search(
            "camera: projection=cover parallax=false amount=8e-2 delay=0.25 mouseInfluence=-1.0"
        )
        camera_shake = benchmark.CAMERA_SHAKE_RE.search(
            "camera shake: status=executable enabled=true amplitude=2.3e-1 "
            "roughness=1.0 speed=1.25"
        )
        invalid_camera_shake = benchmark.CAMERA_SHAKE_RE.search(
            "camera shake: status=invalid enabled=invalid amplitude=invalid "
            "roughness=invalid speed=invalid"
        )
        self.assertEqual(ready.group("images"), "24")
        self.assertEqual(float(ready.group("startup_elapsed_ms")), 1825.25)
        self.assertEqual(
            evidence.group("path"),
            "/tmp/evidence/scene-runtime-evidence.json",
        )
        self.assertEqual(stopped.group("after"), "0")
        self.assertEqual(live, {
            "accepted": True,
            "surfaces_before": 1,
            "surfaces_after": 1,
            "windows_before": [42],
            "windows_after": [42],
            "keys": ["newproperty11"],
        })
        self.assertEqual(loaded.group("loaded"), "20")
        self.assertEqual(text_loaded.group("loaded"), "10")
        self.assertEqual(particle_loaded.group("loaded"), "3")
        self.assertEqual(particle_loaded.group("total"), "4")
        self.assertEqual(particle_refract.group("count"), "2")
        self.assertEqual(particle_live.group("live"), "96")
        self.assertEqual(camera.group("projection"), "cover")
        self.assertEqual(camera.group("parallax"), "false")
        self.assertEqual(float(camera.group("amount")), 0.08)
        self.assertEqual(float(camera.group("delay")), 0.25)
        self.assertEqual(float(camera.group("influence")), -1.0)
        self.assertEqual(camera_shake.group("status"), "executable")
        self.assertEqual(camera_shake.group("enabled"), "true")
        self.assertEqual(float(camera_shake.group("amplitude")), 0.23)
        self.assertEqual(float(camera_shake.group("roughness")), 1.0)
        self.assertEqual(float(camera_shake.group("speed")), 1.25)
        self.assertEqual(invalid_camera_shake.group("status"), "invalid")
        self.assertEqual(invalid_camera_shake.group("amplitude"), "invalid")


if __name__ == "__main__":
    unittest.main()
