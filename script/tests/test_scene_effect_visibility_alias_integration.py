"""Same-effect handles activate an owned fullscreen filter through the real VM.

The existing runner executes the App, shader, compositor and Metal readbacks.
Only its input factory is replaced. Legal same-value mode requests keep the
layer visible while the script's scene clock alone controls the dim effect.
"""
from pathlib import Path
import hashlib
import json
import os
import unittest
from unittest.mock import patch

from . import test_scene_fullscreen_visibility_integration as fullscreen
from .test_scene_composition_authored_order_integration import encoded


_BASE_ENTRIES = fullscreen.fixture_entries
SCRIPT = """export function update(value) {
    const desired=engine.runtime>=3 && engine.runtime<6;
    thisLayer.getEffect(0).visible=desired;
    if(thisLayer.getEffect('Owned dim effect').visible!==desired ||
       thisScene.getLayer('Owned fullscreen dim filter').getEffect(0).visible!==desired ||
       thisObject.visible!==desired) throw Error('effect-alias-read-your-writes');
    return desired;
}
"""


def fixture_entries(**parameters):
    project, entries = _BASE_ENTRIES(**parameters)
    scene = json.loads(entries["scene.json"])
    layer = next(layer for layer in scene["objects"] if layer["id"] == 20)
    layer["effects"][0].update(name="Owned dim effect", visible={"value": False, "script": SCRIPT})
    entries["scene.json"] = encoded(scene)
    entries["owned-effect-alias-oracle.json"] = encoded({
        "testSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "scriptSHA256": hashlib.sha256(SCRIPT.encode()).hexdigest(),
        "layerID": 20, "effectIndex": 0, "activeSceneTime": [3, 6],
        "snapshotTimesSeconds": [1, 3.5, 7], "expectedBackgroundRGB": [255, 128, 255],
        "layerMode": "on for the entire run", "laterPeerRGB": [0, 255, 0],
        "boundary": "self-authored dim filter; no official pixel parity"})
    return project, entries


class SceneEffectVisibilityAliasIntegrationTests(unittest.TestCase):
    setUpClass = classmethod(fullscreen.SceneFullscreenVisibilityIntegrationTests.setUpClass.__func__)
    run_case = fullscreen.SceneFullscreenVisibilityIntegrationTests.run_case

    def test_same_effect_handles_drive_white_gray_white_pixels(self):
        identity = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
        environment = {key: value for key, value in os.environ.items() if not key.startswith("MWX_SCENE_DEBUG_")}
        with patch.dict(os.environ, environment, clear=True), patch.object(fullscreen, "fixture_entries", fixture_entries):
            log, _ = self.run_case(launch={"mode": "on"},
                sequence=[{"mode": "on"}, {"mode": "on"}], expected_dims=[True, False])
        self.assertRegex(log, r"target=effectVisibility\(layerID: 20, effectIndex: 0\) callback=completed type=bool ")
        self.assertNotRegex(log, r"Effect visibility owner produced out-of-cohort|effect-alias-read-your-writes|failure=(?:invalid-argument|exception|bad-return)")
        self.assertEqual(hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), identity)
