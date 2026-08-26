#!/usr/bin/env python3
"""Owner gate for same-slot whole-color graph-input replacement."""

from __future__ import annotations

import json
from pathlib import Path
import tempfile
import unittest

from script.tests import test_scene_generic_shader_program_artifact as shared


PROFILE = "source-proven-graph-input-same-slot-color-replacement"
FRAGMENT = """
uniform sampler2D g_Texture0;
varying vec4 v_TexCoord;
varying vec2 v_Displacement;
void main() {
    vec4 original = texSample2D(g_Texture0, v_TexCoord.xy);
    float neutralMask = 1.0;
    vec4 shifted = texSample2D(
        g_Texture0, v_TexCoord.xy + v_Displacement * neutralMask
    );
    original = shifted;
    gl_FragColor = original;
}
"""
UNSEEN_FRAGMENT = """
uniform sampler2D g_Texture3;
varying vec2 coordinate;
varying vec2 delta;
void main() {
    float4 retained = texture2D(g_Texture3, coordinate);
    float4 replacement = texture2D(g_Texture3, coordinate - delta);
    retained = replacement;
    gl_FragColor = retained;
}
"""


class SceneSameSlotColorReplacementOwnerTests(unittest.TestCase):
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

    def artifact(self, key: str, slot: int = 0) -> dict:
        artifact = shared.SceneGenericShaderProgramArtifactTests.artifact(
            self, key, color_transfer="passthrough"
        )
        if slot != 0:
            artifact["program"]["textureBindings"][0]["name"] = (
                f"g_Texture{slot}"
            )
            artifact["program"]["textureBindings"][0]["slot"] = slot
            artifact["program"]["colorTransfer"]["slot"] = slot
        return artifact

    @staticmethod
    def facts(slot: int = 0) -> dict:
        return {
            "graph_input_slots": (slot,),
            "active_slots": (slot,),
            "has_only_graph_input_sampler": True,
        }

    def publish_artifact(
        self,
        root: Path,
        fragment: str = FRAGMENT,
        slot: int = 0,
    ) -> str:
        observed, _, cache, _ = self.run_harness(
            root,
            route="observe-only",
            fragment=fragment,
            **self.facts(slot),
        )
        artifact = self.artifact(observed["requestKey"], slot)
        (cache / f"{observed['requestKey']}.json").write_text(
            json.dumps(artifact), encoding="utf-8"
        )
        return observed["requestKey"]

    def test_default_failure_rollback_recovery_and_legacy_route(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-same-slot-replacement-owner-"
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

    def test_unseen_names_and_slot_are_admitted(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-same-slot-replacement-unseen-"
        ) as directory:
            observed, _, _, _ = self.run_harness(
                Path(directory),
                route="observe-only",
                fragment=UNSEEN_FRAGMENT,
                **self.facts(3),
            )
            self.assertEqual(observed["routeProfile"], PROFILE)
            self.assertEqual(observed["routeState"], "generic-only")

    def test_source_drift_keeps_the_broad_incumbent(self) -> None:
        cases = [
            FRAGMENT.replace("g_Texture0, v_TexCoord.xy +", "g_Texture1, v_TexCoord.xy +")
                .replace(
                    "uniform sampler2D g_Texture0;",
                    "uniform sampler2D g_Texture0;\nuniform sampler2D g_Texture1;",
                ),
            FRAGMENT.replace(
                "    original = shifted;",
                "    if (neutralMask > 0.5) { original = shifted; }",
            ),
            FRAGMENT.replace(
                "    original = shifted;",
                "    shifted.a = 1.0;\n    original = shifted;",
            ),
            FRAGMENT.replace(
                "    gl_FragColor = original;",
                "    gl_FragColor = shifted;",
            ),
        ]
        for fragment in cases:
            with self.subTest(fragment=fragment[-180:]), tempfile.TemporaryDirectory(
                prefix="mwx-same-slot-replacement-source-reject-"
            ) as directory:
                observed, _, _, log = self.run_harness(
                    Path(directory),
                    route="observe-only",
                    fragment=fragment,
                    **self.facts(),
                )
                self.assertNotEqual(observed["routeProfile"], PROFILE)
                self.assertNotIn(f"profile={PROFILE}", log)

    def test_resource_and_output_drift_keep_the_broad_incumbent(self) -> None:
        cases = [
            {},
            {"graph_input_slots": (0,), "active_slots": (0,)},
            {
                "graph_input_slots": (0,),
                "active_slots": (0, 1),
                "has_only_graph_input_sampler": True,
            },
            {**self.facts(), "graph_slots": (0,)},
            {**self.facts(), "graph_input_slots": (1,)},
            {**self.facts(), "has_external_provider": True},
            {**self.facts(), "has_only_graph_input_sampler": False},
            {**self.facts(), "produces_scalar_output": True},
            {**self.facts(), "produces_red_green_unorm_output": True},
            {**self.facts(), "preserved_rgba_output": True},
        ]
        for facts in cases:
            with self.subTest(facts=facts), tempfile.TemporaryDirectory(
                prefix="mwx-same-slot-replacement-contract-reject-"
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
