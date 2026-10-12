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


class SceneWallpaperPublicationsTests(unittest.TestCase):
    def test_media_thumbnail_metrics_keep_current_and_previous_layer_identities(
        self,
    ) -> None:
        metrics = benchmark.media_thumbnail_runtime_metrics(
            "\n".join([
                "mediaThumbnailCurrentBindingCount: 3",
                "mediaThumbnailCurrentBindingLayerIDs: 10,20,30",
                "mediaThumbnailPreviousBindingCount: 1",
                "mediaThumbnailPreviousBindingLayerIDs: 702",
            ])
        )
        self.assertEqual(metrics, {
            "current_binding_count": 3,
            "current_binding_layer_ids": [10, 20, 30],
            "previous_binding_count": 1,
            "previous_binding_layer_ids": [702],
        })

    def test_scene_script_scalar_metrics_keep_typed_targets_and_values(self) -> None:
        metrics = benchmark.scene_script_scalar_runtime_metrics(
            "scene script VM: schema=quickjs-ng-scalar-v1 bindings=2 targets=2 "
            "route=generic-only fallback=previous-current",
            "\n".join([
                "MWX SceneScript VM: target=effectConstant(layerID: 301, "
                'effectIndex: 1, passIndex: 0, name: "multiply") '
                "callback=completed input=1 output=0 mutations=0 "
                "mutationTargets= route=generic-only",
                "MWX SceneScript VM: target=effectConstant(layerID: 301, "
                'effectIndex: 0, passIndex: 0, name: "multiply") '
                "callback=completed input=1 output=0 mutations=0 "
                "mutationTargets= route=generic-only",
            ]),
        )
        self.assertEqual(metrics["binding_count"], 2)
        self.assertEqual(metrics["target_count"], 2)
        self.assertEqual(metrics["route"], "generic-only")
        self.assertEqual(metrics["fallback"], "previous-current")
        self.assertEqual(metrics["bindings"], [
            {
                "layer_id": 301,
                "effect_index": 0,
                "pass_index": 0,
                "constant": "multiply",
            },
            {
                "layer_id": 301,
                "effect_index": 1,
                "pass_index": 0,
                "constant": "multiply",
            },
        ])
        self.assertEqual(
            [completion["output"] for completion in metrics["completions"]],
            [0.0, 0.0],
        )

    def test_scene_script_typed_metrics_keep_vec3_layer_completions(self) -> None:
        metrics = benchmark.scene_script_scalar_runtime_metrics(
            "scene script VM: schema=quickjs-ng-typed-v2 bindings=0 "
            "vec3Bindings=3 targets=0 route=generic-only "
            "fallback=previous-current",
            "MWX SceneScript VM: target=layer(layerID: 235, field: "
            "MyWallpaperX.SceneDynamicLayerField.angles) callback=completed "
            "type=vector3 input=vector3(-81,41,0) output=vector3(-81,-43,0) "
            "audio=false audioGeneration=0 route=generic-only",
        )
        self.assertEqual(metrics["binding_count"], 0)
        self.assertEqual(metrics["vec3_binding_count"], 3)
        self.assertEqual(metrics["vec3_completions"], [{
            "layer_id": 235,
            "target_kind": "layer",
            "field": "angles",
            "input": "vector3(-81,41,0)",
            "output": "vector3(-81,-43,0)",
            "route": "generic-only",
        }])

    def test_scene_script_typed_metrics_keep_text_color_completions(self) -> None:
        metrics = benchmark.scene_script_scalar_runtime_metrics(
            "scene script VM: schema=quickjs-ng-typed-v2 bindings=0 "
            "vec3Bindings=1 targets=0 route=generic-only "
            "fallback=previous-current",
            "MWX SceneScript VM: target=text(layerID: 501, field: "
            "MyWallpaperX.SceneDynamicTextField.color) callback=completed "
            "type=vector3 input=vector3(0,0,0) "
            "output=vector3(0.2,0.4,0.8) audio=false "
            "audioGeneration=0 route=generic-only",
        )
        self.assertEqual(metrics["vec3_completions"], [{
            "layer_id": 501,
            "target_kind": "text",
            "field": "color",
            "input": "vector3(0,0,0)",
            "output": "vector3(0.2,0.4,0.8)",
            "route": "generic-only",
        }])

    def test_scene_script_typed_metrics_keep_object_scalar_completions(self) -> None:
        metrics = benchmark.scene_script_scalar_runtime_metrics(
            "scene script VM: schema=quickjs-ng-typed-v2 bindings=1 "
            "vectorBindings=0 stringBindings=0 targets=1 "
            "route=generic-only fallback=current-frame-lower-priority",
            "MWX SceneScript VM: target=layer(layerID: 345, field: "
            "MyWallpaperX.SceneDynamicLayerField.alpha) callback=completed "
            "input=0.73 output=0.2 mutations=0 mutationTargets= "
            "route=generic-only",
        )
        self.assertEqual(metrics["object_scalar_completions"], [{
            "layer_id": 345,
            "target_kind": "layer",
            "field": "alpha",
            "input": 0.73,
            "output": 0.2,
            "mutation_count": 0,
            "route": "generic-only",
        }])

    def test_scene_script_typed_metrics_capture_pass_vec2_and_audio_value(self) -> None:
        metrics = benchmark.scene_script_scalar_runtime_metrics(
            "scene script VM: schema=quickjs-ng-typed-v2 bindings=2 "
            "vectorBindings=25 stringBindings=0 targets=27 "
            "route=generic-only fallback=previous-current",
            "MWX SceneScript VM: target=effectConstant(layerID: 65, "
            "effectIndex: 2, passIndex: 0, name: \"scale\") "
            "callback=completed type=vector2 input=vector2(1.0, 1.0) "
            "output=vector2(1.0, 1.0) audio=true audioGeneration=0 "
            "route=generic-only\n"
            "MWX SceneScript VM: target=effectConstant(layerID: 65, "
            "effectIndex: 2, passIndex: 0, name: \"scale\") "
            "callback=audioValuePublished type=vector2 generation=2 "
            "input=vector2(1.0, 1.0) output=vector2(1.25, 1.25) "
            "route=generic-only",
        )
        self.assertEqual(metrics["binding_count"], 2)
        self.assertEqual(metrics["vector_binding_count"], 25)
        self.assertEqual(metrics["target_count"], 27)
        self.assertEqual(metrics["effect_vector_completions"][0]["output"],
                         "vector2(1.0, 1.0)")
        self.assertEqual(metrics["audio_vector_publications"][0]["generation"], 2)
        self.assertEqual(metrics["audio_vector_publications"][0]["output"],
                         "vector2(1.25, 1.25)")

    def test_scene_script_typed_metrics_capture_pass_scalar_audio_value(self) -> None:
        metrics = benchmark.scene_script_scalar_runtime_metrics(
            "scene script VM: schema=quickjs-ng-typed-v2 bindings=1 "
            "vectorBindings=0 stringBindings=0 targets=1 "
            "route=generic-only fallback=previous-current",
            "MWX SceneScript VM: target=effectConstant(layerID: 1509, "
            "effectIndex: 4, passIndex: 0, name: \"strength\") "
            "callback=audioValuePublished type=scalar generation=3 "
            "input=1 output=1.5 route=generic-only",
        )
        self.assertEqual(metrics["audio_scalar_publications"], [{
            "layer_id": 1509,
            "effect_index": 4,
            "pass_index": 0,
            "constant": "strength",
            "generation": 3,
            "input": 1.0,
            "output": 1.5,
            "route": "generic-only",
        }])

    def test_typed_user_property_scalar_uniform_publications_keep_exact_identity(self) -> None:
        publications = benchmark.typed_user_property_scalar_uniform_publications(
            "MWX typed input publication: channel=user-property "
            "consumer=material-uniform layer=530 effect=1 "
            "descriptor=530#effect#538 node=0 property=newproperty39 "
            "pass=0 constant=strength uniform=g_Strength stage=fragment "
            "type=float frame=4 generation=2 value=0.075000003\n"
            "MWX typed input publication: channel=user-property "
            "consumer=material-uniform layer=410 effect=0 "
            "descriptor=410#effect#1369 node=0 property=newproperty52 "
            "pass=0 constant=direction uniform=g_Direction stage=fragment "
            "type=float frame=3 generation=2 value=37"
        )
        self.assertEqual(publications, [
            {
                "layer_id": 410,
                "effect_index": 0,
                "descriptor_id": "410#effect#1369",
                "node_index": 0,
                "property_key": "newproperty52",
                "pass_index": 0,
                "constant": "direction",
                "uniform": "g_Direction",
                "stage": "fragment",
                "type": "float",
                "frame": 3,
                "generation": 2,
                "value": 37.0,
            },
            {
                "layer_id": 530,
                "effect_index": 1,
                "descriptor_id": "530#effect#538",
                "node_index": 0,
                "property_key": "newproperty39",
                "pass_index": 0,
                "constant": "strength",
                "uniform": "g_Strength",
                "stage": "fragment",
                "type": "float",
                "frame": 4,
                "generation": 2,
                "value": 0.075000003,
            },
        ])

    def test_typed_user_property_scalar_splat_publications_keep_projection(self) -> None:
        publications = (
            benchmark.typed_user_property_scalar_splat_uniform_publications(
                "MWX typed input publication: channel=user-property "
                "consumer=material-uniform layer=525 effect=0 "
                "descriptor=525#effect#528 node=0 property=blurbackground "
                "pass=0 constant=scale uniform=g_Scale stage=vertex "
                "type=float2-scalar-splat frame=0 generation=1 value=0,0"
            )
        )
        self.assertEqual(publications, [{
            "layer_id": 525,
            "effect_index": 0,
            "descriptor_id": "525#effect#528",
            "node_index": 0,
            "property_key": "blurbackground",
            "pass_index": 0,
            "constant": "scale",
            "uniform": "g_Scale",
            "stage": "vertex",
            "type": "float2",
            "source_type": "scalar",
            "projection": "isotropic-splat",
            "frame": 0,
            "generation": 1,
            "value": [0.0, 0.0],
        }])

    def test_typed_user_property_bool_activation_publications_keep_decision(self) -> None:
        publications = benchmark.typed_user_property_bool_activation_publications(
            "MWX typed input publication: channel=user-property "
            "consumer=effect-activation layer=530 effect=1 "
            "descriptor=530#effect#538 property=newproperty7 type=bool "
            "frame=0 generation=1 value=true decision=active"
        )
        self.assertEqual(publications, [{
            "layer_id": 530,
            "effect_index": 1,
            "descriptor_id": "530#effect#538",
            "property_key": "newproperty7",
            "type": "bool",
            "frame": 0,
            "generation": 1,
            "value": True,
            "decision": "active",
        }])


if __name__ == "__main__":
    unittest.main()
