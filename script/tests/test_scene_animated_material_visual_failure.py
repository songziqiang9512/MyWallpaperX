#!/usr/bin/env python3

"""GPU proof for the typed animated-frame launch visual failure."""

from __future__ import annotations

import json
import unittest

from script.tests import test_scene_resolved_material_graph_executor as base


class SceneAnimatedMaterialVisualFailureTests(unittest.TestCase):
    def test_invalid_frame_metadata_preserves_previous_current(self) -> None:
        source = base.HARNESS
        ready = "assetStates: [colorBlendMaskIdentity: .ready(.data)],"
        unavailable = (
            "assetStates: [colorBlendMaskIdentity: "
            ".effectLocalUnavailable(.animatedFrameMetadataInvalid)],"
        )
        self.assertEqual(source.count(ready), 1)
        source = source.replace(ready, unavailable)

        sampler_call = """\
        let samplerSchemaFailure = executeVisualFailurePassthrough(
            claim: samplerSchemaPixelClaim,
            capability: samplerSchemaPixelCapability,
            capabilities: samplerSchemaPixelCapabilities,
            generation: 8,
            reason: "material-variant-envelope-sampler-schema"
        )
"""
        metadata_call = """\
        let samplerSchemaFailure = executeVisualFailurePassthrough(
            claim: colorBlendClaim,
            capability: colorBlendCapability,
            capabilities: colorBlendCapabilities,
            generation: 8,
            reason: "material-variant-envelope-animated-frame-metadata"
        )
"""
        self.assertEqual(source.count(sampler_call), 1)
        source = source.replace(sampler_call, metadata_call)

        compilation, completed = base.compile_harness(base.SUPPORT, source)
        self.assertEqual(compilation.returncode, 0, compilation.stderr)
        self.assertIsNotNone(completed)
        assert completed is not None
        self.assertEqual(completed.returncode, 0, completed.stderr)
        payload = json.loads(completed.stdout)
        if not payload["metalAvailable"]:
            self.skipTest("Metal is unavailable")
        expected = [
            "samplerSchemaFailurePassthroughPrepared",
            "samplerSchemaFailurePassthroughEncoded",
            "samplerSchemaFailurePassthroughGPUCompleted",
            "samplerSchemaFailurePreservesPreviousAndContinuesSuffix",
        ]
        self.assertEqual(
            [name for name in expected if not payload["results"][name]],
            [],
            payload,
        )


if __name__ == "__main__":
    unittest.main()
