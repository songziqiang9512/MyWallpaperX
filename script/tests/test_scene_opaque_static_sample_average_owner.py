#!/usr/bin/env python3
"""Owner gate for opaque graph-target static sample averages."""

from __future__ import annotations

import json
from pathlib import Path
import tempfile
import unittest

from script.tests import test_scene_generic_shader_program_artifact as shared


PROFILE = "source-proven-graph-target-opaque-static-sample-average"
FRAGMENT = """
varying vec2 v_TexCoord;
varying vec4 v_StepSize;
uniform sampler2D g_Texture0;
void main() {
    vec3 albedo = texSample2D(g_Texture0, v_TexCoord).rgb;
    albedo += texSample2D(g_Texture0, v_TexCoord + v_StepSize.xy).rgb;
    albedo += texSample2D(g_Texture0, v_TexCoord + v_StepSize.zy).rgb;
    albedo += texSample2D(g_Texture0, v_TexCoord + v_StepSize.xw).rgb;
    albedo += texSample2D(g_Texture0, v_TexCoord + v_StepSize.zw).rgb;
    gl_FragColor = vec4(albedo * 0.2, 1.0);
}
"""
UNSEEN_FRAGMENT = """
uniform sampler2D g_Texture3;
varying float2 coordinate;
varying float2 stride;
void main() {
    float3 gathered = texture2D(g_Texture3, coordinate - stride).xyz;
    gathered += texture2D(g_Texture3, coordinate).xyz;
    gathered += texture2D(g_Texture3, coordinate + stride).xyz;
    gl_FragColor = float4(0.3333333333333333 * gathered, 1.0);
}
"""


class SceneOpaqueStaticSampleAverageOwnerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        shared.SceneGenericShaderProgramArtifactTests.setUpClass()
        cls.binary = shared.SceneGenericShaderProgramArtifactTests.binary

    @classmethod
    def tearDownClass(cls) -> None:
        shared.SceneGenericShaderProgramArtifactTests.tearDownClass()

    def run_harness(self, root: Path, **kwargs):
        return shared.SceneGenericShaderProgramArtifactTests.run_harness(
            self, root, **kwargs
        )

    def artifact(self, key: str) -> dict:
        return shared.SceneGenericShaderProgramArtifactTests.artifact(
            self, key, color_transfer="opaque"
        )

    @staticmethod
    def facts(slot: int = 0) -> dict:
        return {
            "graph_slots": (slot,),
            "graph_input_slots": (slot,),
            "active_slots": (slot,),
            "has_only_graph_input_sampler": True,
        }

    def publish_artifact(self, root: Path, fragment: str = FRAGMENT) -> str:
        observed, _, cache, _ = self.run_harness(
            root,
            route="observe-only",
            fragment=fragment,
            **self.facts(),
        )
        artifact = self.artifact(observed["requestKey"])
        (cache / f"{observed['requestKey']}.json").write_text(
            json.dumps(artifact), encoding="utf-8"
        )
        return observed["requestKey"]

    def test_default_failure_rollback_recovery_and_legacy_route(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-opaque-static-average-owner-"
        ) as directory:
            root = Path(directory)
            request_key = self.publish_artifact(root)

            accepted, _, cache, log = self.run_harness(
                root, route=None, fragment=FRAGMENT, **self.facts()
            )
            self.assertEqual(accepted["status"], "accepted")
            self.assertEqual(accepted["backend"], "genericCompilerArtifact")
            self.assertEqual(accepted["routeState"], "generic-only")
            self.assertEqual(accepted["routeProfile"], PROFILE)
            self.assertIn(
                f"state=generic-only profile={PROFILE} outcome=accepted", log
            )

            legacy, _, _, _ = self.run_harness(
                root,
                route="disable-generic",
                fragment=FRAGMENT,
                **self.facts(),
            )
            self.assertEqual(legacy["status"], "accepted")
            self.assertEqual(legacy["routeState"], "generic-only")

            artifact_path = cache / f"{request_key}.json"
            artifact = json.loads(artifact_path.read_text(encoding="utf-8"))
            artifact["program"]["metalSourceSHA256"] = "0" * 64
            artifact_path.write_text(json.dumps(artifact), encoding="utf-8")
            rejected, _, _, rejected_log = self.run_harness(
                root, route=None, fragment=FRAGMENT, **self.facts()
            )
            self.assertEqual(rejected["code"], "artifact-contract-rejected")
            self.assertFalse(rejected["permitsBoundedFrontend"])
            self.assertIn(
                f"state=generic-only profile={PROFILE} outcome=rejected",
                rejected_log,
            )

            rolled_back, _, _, rollback_log = self.run_harness(
                root,
                route=None,
                profile_routes=f"{PROFILE}=disable-generic",
                fragment=FRAGMENT,
                **self.facts(),
            )
            self.assertEqual(rolled_back["code"], "route-disabled")
            self.assertTrue(rolled_back["permitsBoundedFrontend"])
            self.assertIn(
                f"state=disable-generic profile={PROFILE} outcome=fallback",
                rollback_log,
            )

            artifact_path.write_text(
                json.dumps(self.artifact(request_key)), encoding="utf-8"
            )
            recovered, _, _, _ = self.run_harness(
                root, route=None, fragment=FRAGMENT, **self.facts()
            )
            self.assertEqual(recovered["status"], "accepted")
            self.assertEqual(recovered["routeProfile"], PROFILE)

    def test_unseen_names_slot_coordinates_and_count_are_admitted(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-opaque-static-average-unseen-"
        ) as directory:
            observed, _, _, _ = self.run_harness(
                Path(directory),
                route="observe-only",
                fragment=UNSEEN_FRAGMENT,
                **self.facts(3),
            )
            self.assertEqual(observed["routeProfile"], PROFILE)
            self.assertEqual(observed["routeState"], "generic-only")

    def test_source_drift_keeps_the_incumbent(self) -> None:
        cases = [
            FRAGMENT.replace("albedo * 0.2", "albedo * 0.25"),
            FRAGMENT.replace("albedo * 0.2", "albedo / 5.0"),
            FRAGMENT.replace("texSample2D", "texture"),
            FRAGMENT.replace(
                "g_Texture0, v_TexCoord).rgb",
                "g_Texture0, v_TexCoord + "
                "texture2DLod(g_Texture0, v_TexCoord, 0.0).xy).rgb",
                1,
            ),
            UNSEEN_FRAGMENT.replace("g_Texture3", "g_Texture0").replace(
                "0.3333333333333333", "0.3"
            ),
            FRAGMENT.replace("g_Texture0, v_TexCoord + v_StepSize.zy", "g_Texture1, v_TexCoord + v_StepSize.zy"),
            FRAGMENT.replace(".rgb;\n    albedo +=", ".rgba;\n    albedo +=", 1),
            FRAGMENT.replace("vec4(albedo * 0.2, 1.0)", "vec4(albedo * 0.2, 0.5)"),
            FRAGMENT.replace(
                "    gl_FragColor =",
                "    albedo *= 0.5;\n    gl_FragColor =",
            ),
            FRAGMENT.replace(
                "    vec3 albedo =",
                "    if (v_TexCoord.x > 0.0) { return; }\n    vec3 albedo =",
            ),
            FRAGMENT.replace(
                "    gl_FragColor =",
                "    gl_FragColor = vec4(0.0);\n    gl_FragColor =",
            ),
        ]
        for fragment in cases:
            with self.subTest(fragment=fragment[-180:]), tempfile.TemporaryDirectory(
                prefix="mwx-opaque-static-average-source-reject-"
            ) as directory:
                observed, _, _, log = self.run_harness(
                    Path(directory),
                    route="observe-only",
                    fragment=fragment,
                    **self.facts(),
                )
                self.assertNotEqual(observed["routeProfile"], PROFILE)
                self.assertNotIn(f"profile={PROFILE}", log)

    def test_resource_and_target_drift_keep_the_incumbent(self) -> None:
        cases = [
            {},
            {"graph_slots": (0,), "active_slots": (0,)},
            {
                "graph_slots": (0,),
                "graph_input_slots": (0,),
                "active_slots": (0, 1),
                "has_only_graph_input_sampler": True,
            },
            {**self.facts(), "has_external_provider": True},
            {**self.facts(), "has_only_graph_input_sampler": False},
            {**self.facts(), "produces_scalar_output": True},
            {**self.facts(), "produces_red_green_unorm_output": True},
            {**self.facts(), "preserved_rgba_output": True},
        ]
        for facts in cases:
            with self.subTest(facts=facts), tempfile.TemporaryDirectory(
                prefix="mwx-opaque-static-average-contract-reject-"
            ) as directory:
                observed, _, _, _ = self.run_harness(
                    Path(directory),
                    route="observe-only",
                    fragment=FRAGMENT,
                    **facts,
                )
                self.assertNotEqual(observed["routeProfile"], PROFILE)


if __name__ == "__main__":
    unittest.main()
