"""Owned composition: inactive dim effect -> live GPU pixels.

Reuse the frozen fullscreen runner's App identity, whole-key acknowledgements,
Metal captures and later green-peer oracle. Only the authored utility type is
changed; particle-member cases use a black card behind the white particle so
missing member rendering cannot pass the white/gray pixel oracle.
Requires MWX_SCENE_INTEGRATION_APP; the root agent runs these GPU cases serially.
"""
from pathlib import Path
from functools import partial
import hashlib
import json
import unittest
from unittest.mock import patch

from . import test_scene_fullscreen_visibility_integration as fullscreen
from .test_scene_composition_authored_order_integration import encoded


_BASE_ENTRIES = fullscreen.fixture_entries


def fixture_entries(*, particle_subtree=False, renamed=False, **parameters):
    project, entries = _BASE_ENTRIES(**parameters)
    scene = json.loads(entries["scene.json"])
    layer = next(item for item in scene["objects"] if item["id"] == 20)
    layer.update(name="Owned childless composition dim filter",
                 image="models/util/composelayer.json", copybackground=True,
                 passthrough=False)
    # This public utility discriminator carries our own model bytes. No stock
    # shader/model source is consumed.
    entries["models/util/composelayer.json"] = entries.pop("models/util/fullscreenlayer.json")
    children = []
    if particle_subtree:
        children = [614, 925] if renamed else [41, 42]
        scene["objects"].extend([
            {"id": children[0], "parent": 20, "image": "models/own_solid.json",
             "origin": "-64 0 0", "size": "48 48", "color": "0 0 0"},
            {"id": children[1], "parent": 20, "particle": "particles/owned_member.json",
             "origin": "-64 0 0", "scale": "1 1 1", "visible": True}])
        entries["particles/owned_member.json"] = encoded({
            "flags": 1, "material": "materials/owned_member.json", "maxcount": 1, "starttime": .5,
            "emitter": [{"name": "sphererandom", "rate": 0, "instantaneous": 1,
                         "distancemin": 0, "distancemax": 0}],
            "initializer": [{"name": "lifetimerandom", "min": 60, "max": 60},
                            {"name": "sizerandom", "min": 96, "max": 96},
                            {"name": "colorrandom", "min": "255 255 255", "max": "255 255 255"}],
            "renderer": [{"name": "sprite"}]})
        entries["materials/owned_member.json"] = encoded({"passes": [{
            "shader": "genericparticle", "textures": ["owned_member.png"], "blending": "translucent",
            "depthtest": "disabled", "depthwrite": "disabled", "cullmode": "nocull"}]})
        entries["materials/owned_member.png"] = fullscreen.white_png()
    entries["scene.json"] = encoded(scene)
    if renamed:
        entries = {name.replace("owned_member", "unseen_marker").replace("own_dim", "another_gain"):
                   data.replace(b"owned_member", b"unseen_marker").replace(b"own_dim", b"another_gain")
                   for name, data in entries.items()}
    entries["owned-composition-effect-oracle.json"] = encoded({
        "testSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "layerID": 20, "effectIndex": 0, "copybackground": True,
        "parent": None, "children": children, "dependencies": [],
        "effectSequence": [False, True, False],
        "boundary": "self-authored utility and optional particle members; no official parity"})
    return project, entries


class SceneCompositionEffectVisibilityIntegrationTests(unittest.TestCase):
    setUpClass = classmethod(fullscreen.SceneFullscreenVisibilityIntegrationTests.setUpClass.__func__)
    run_case = fullscreen.SceneFullscreenVisibilityIntegrationTests.run_case

    def test_startup_inactive_composition_effect_drives_white_gray_white_pixels(self):
        with patch.object(fullscreen, "fixture_entries", fixture_entries):
            self.run_case(inactive_effect=True, launch={"mode": "on", "fx": False},
                          sequence=[{"fx": True}, {"fx": False}], expected_dims=[True, False])

    def test_missing_composition_shader_rejects_enable_and_preserves_healthy_peer(self):
        with patch.object(fullscreen, "fixture_entries", fixture_entries):
            self.run_case(inactive_effect=True, missing_shader=True,
                          launch={"mode": "on", "fx": False},
                          sequence=[{"fx": True}, {"fx": False}], expected_dims=[False, False],
                          expected_accepted=[False, True])

    def test_particle_members_survive_inactive_active_inactive_parent_effect(self):
        with patch.object(fullscreen, "fixture_entries", partial(fixture_entries, particle_subtree=True)):
            self.run_case(inactive_effect=True, launch={"mode": "on", "fx": False},
                          sequence=[{"fx": True}, {"fx": False}], expected_dims=[True, False])

    def test_renamed_particle_members_use_the_same_parent_effect_toggle(self):
        with patch.object(fullscreen, "fixture_entries", partial(fixture_entries, particle_subtree=True,
                                                                  renamed=True)):
            self.run_case(inactive_effect=True, launch={"mode": "on", "fx": False},
                          sequence=[{"fx": True}, {"fx": False}], expected_dims=[True, False])

    def test_missing_parent_shader_preserves_particle_source_and_later_peer(self):
        with patch.object(fullscreen, "fixture_entries", partial(fixture_entries, particle_subtree=True)):
            self.run_case(inactive_effect=True, missing_shader=True, launch={"mode": "on", "fx": False},
                          # Rejected enable leaves fx=false. Repeating false
                          # is the existing no-op, without requiring a shader.
                          sequence=[{"fx": True}, {"fx": False}], expected_dims=[False, False],
                          expected_accepted=[False, True])


if __name__ == "__main__":
    unittest.main()
