#!/usr/bin/env python3
"""Owner gate for opaque graph-target loop sample averages."""

from __future__ import annotations

import json
from pathlib import Path
import tempfile
import unittest

from script.tests import test_scene_generic_shader_program_artifact as shared


PROFILE = "source-proven-graph-target-opaque-loop-sample-average"
FRAGMENT = """
uniform sampler2D g_Texture0;
uniform float u_strength;
uniform float u_alpha;
varying vec2 v_TexCoord;
varying vec2 v_SizeMultiplier;
void main() {
    vec3 albedo = CAST3(0.0);
    if (u_strength > 0.001 && u_alpha > 0.001) {
        vec2 offset = CAST2(0.0);
        for (int i = -2; i <= 2; i++) {
            offset.x = float(i) * v_SizeMultiplier.x;
            albedo += texSample2D(g_Texture0, v_TexCoord + offset).rgb;
        }
        albedo /= float(2 + 2) + 1.0;
    }
    gl_FragColor = vec4(albedo, 1.0);
}
"""
UNSEEN_FRAGMENT = """
uniform sampler2D g_Texture3;
uniform float gateOne;
uniform float gateTwo;
varying vec2 coordinate;
varying vec2 stride;
void main() {
    float3 result = float3(0.0);
    if (gateOne > 0.25 && gateTwo > 0.5) {
        float2 delta = float2(0.0);
        for (int probe = -3; probe <= 3; ++probe) {
            delta.y = float(probe) * stride.y;
            result += texture2D(g_Texture3, coordinate + delta).xyz;
        }
        result /= float(3 + 3) + 1.0;
    }
    gl_FragColor = float4(result, 1.0);
}
"""


class SceneOpaqueLoopSampleAverageOwnerTests(unittest.TestCase):
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
            prefix="mwx-opaque-loop-average-owner-"
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

    def test_unseen_names_slot_radius_and_vertical_axis_are_admitted(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-opaque-loop-average-unseen-"
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
            FRAGMENT.replace("float(2 + 2) + 1.0", "float(2 + 2)"),
            FRAGMENT.replace("i <= 2", "i <= 17").replace("i = -2", "i = -17"),
            FRAGMENT.replace("i <= 2", "i <= dynamicBound").replace(
                "uniform float u_alpha;",
                "uniform float u_alpha;\nuniform int dynamicBound;",
            ),
            FRAGMENT.replace(".rgb;", ".rgba;"),
            FRAGMENT.replace("vec4(albedo, 1.0)", "vec4(albedo, 0.5)"),
            FRAGMENT.replace(
                "        albedo /=",
                "        albedo += texSample2D(g_Texture0, v_TexCoord).rgb;\n"
                "        albedo /=",
            ),
            FRAGMENT.replace(
                "    gl_FragColor =",
                "    gl_FragColor = vec4(0.0);\n    gl_FragColor =",
            ),
        ]
        for fragment in cases:
            with self.subTest(fragment=fragment[-180:]), tempfile.TemporaryDirectory(
                prefix="mwx-opaque-loop-average-source-reject-"
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
                prefix="mwx-opaque-loop-average-contract-reject-"
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
