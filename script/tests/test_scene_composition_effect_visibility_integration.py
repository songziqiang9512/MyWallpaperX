"""Owned childless composition: inactive dim effect -> live GPU pixels.

Reuse the frozen fullscreen runner's App identity, whole-key acknowledgements,
Metal captures and later green-peer oracle. Only the authored utility type is
changed; no nested composition, dependency provider or official parity claim.
Requires MWX_SCENE_INTEGRATION_APP; the root agent runs these GPU cases serially.
"""
from pathlib import Path
import hashlib
import json
import unittest
from unittest.mock import patch

from . import test_scene_fullscreen_visibility_integration as fullscreen
from .test_scene_composition_authored_order_integration import encoded


_BASE_ENTRIES = fullscreen.fixture_entries


def fixture_entries(**parameters):
    project, entries = _BASE_ENTRIES(**parameters)
    scene = json.loads(entries["scene.json"])
    layer = next(item for item in scene["objects"] if item["id"] == 20)
    layer.update(name="Owned childless composition dim filter",
                 image="models/util/composelayer.json", copybackground=True,
                 passthrough=False)
    # This public utility discriminator carries our own model bytes. No stock
    # shader/model source is consumed, and no object has layer 20 as its parent.
    entries["models/util/composelayer.json"] = entries.pop("models/util/fullscreenlayer.json")
    entries["scene.json"] = encoded(scene)
    entries["owned-composition-effect-oracle.json"] = encoded({
        "testSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "layerID": 20, "effectIndex": 0, "copybackground": True,
        "parent": None, "children": [], "dependencies": [],
        "effectSequence": [False, True, False],
        "expectedBackgroundRGB": [255, 128, 255], "laterPeerRGB": [0, 255, 0],
        "missingShaderExpectedAccepted": [False, False],
        "missingShaderExpectedBackgroundRGB": [255, 255, 255],
        "boundary": "self-authored childless utility; no nested group or official parity"})
    return project, entries


class SceneCompositionEffectVisibilityIntegrationTests(unittest.TestCase):
    setUpClass = classmethod(fullscreen.SceneFullscreenVisibilityIntegrationTests.setUpClass.__func__)
    run_case = fullscreen.SceneFullscreenVisibilityIntegrationTests.run_case

    def test_startup_inactive_composition_effect_drives_white_gray_white_pixels(self):
        with patch.object(fullscreen, "fixture_entries", fixture_entries):
            self.run_case(inactive_effect=True, launch={"mode": "on", "fx": False},
                          sequence=[{"fx": True}, {"fx": False}], expected_dims=[True, False])

    def test_missing_composition_shader_rejects_updates_and_preserves_healthy_peer(self):
        with patch.object(fullscreen, "fixture_entries", fixture_entries):
            self.run_case(inactive_effect=True, missing_shader=True,
                          launch={"mode": "on", "fx": False},
                          sequence=[{"fx": True}, {"fx": False}], expected_dims=[False, False])


if __name__ == "__main__":
    unittest.main()
