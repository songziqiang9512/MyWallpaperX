#!/usr/bin/env python3

"""GPU proof for typed visibility activation on an admitted FBO graph."""

from __future__ import annotations

import json
import shutil
import unittest

from script.tests import test_scene_resolved_material_graph_executor as base


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneResolvedMaterialFBOStageActivationTests(unittest.TestCase):
    def test_visibility_activation_preserves_current_across_fbo_graph(self) -> None:
        pair_leaf = """\
        let activationGraph = graph(
            targets: [],
            nodes: [material(0, ordinal: 0, target: output, read: input)]
        )
"""
        framebuffer = """\
        let activationGraph = graph(
            targets: [rawTarget(first)],
            nodes: [
                material(0, ordinal: 0, target: first, read: input),
                material(1, ordinal: 1, target: output, read: first),
            ]
        )
"""
        self.assertEqual(base.HARNESS.count(pair_leaf), 1)
        harness = base.HARNESS.replace(pair_leaf, framebuffer)
        chained_lease = """\
            guard let claim = activationClaim,
                  let capability = activationCapability,
                  let leases = makeChainedLeases(
                      capability,
                      device: device,
                      generation: generation
                  ), let executor = Executor(
"""
        framebuffer_lease = """\
            let leases = [makeLease(
                requirePlan(activationGraph),
                device: device,
                generation: generation
            )]
            guard let claim = activationClaim,
                  let capability = activationCapability,
                  let executor = Executor(
"""
        self.assertEqual(harness.count(chained_lease), 1)
        harness = harness.replace(chained_lease, framebuffer_lease)

        compilation, completed = base.compile_harness(base.SUPPORT, harness)
        self.assertEqual(compilation.returncode, 0, compilation.stderr)
        self.assertIsNotNone(completed)
        assert completed is not None
        self.assertEqual(completed.returncode, 0, completed.stderr)
        payload = json.loads(completed.stdout)
        if not payload["metalAvailable"]:
            self.skipTest("Metal is unavailable")
        expected = [
            "activationPolicyAttachedToResolvedStage",
            "inactiveActivationPublishesPreviousCurrent",
            "inactiveActivationIsNotVisualFallback",
            "activeActivationContinuesThroughProgram",
        ]
        self.assertEqual(
            [name for name in expected if not payload["results"][name]],
            [],
            payload,
        )


if __name__ == "__main__":
    unittest.main()
