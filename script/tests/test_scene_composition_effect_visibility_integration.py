"""Owned composition/Project: inactive dim effect -> live GPU pixels.

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


def fixture_entries(*, particle_subtree=False, renamed=False, utility_kind="composition",
                    passthrough=False, active_at_launch=False, **parameters):
    project, entries = _BASE_ENTRIES(**parameters)
    scene = json.loads(entries["scene.json"])
    layer = next(item for item in scene["objects"] if item["id"] == 20)
    utility_path = ("models/util/projectlayer.json" if utility_kind == "project"
                    else "models/util/composelayer.json")
    layer.update(name="Owned childless composition dim filter",
                 image=utility_path, copybackground=True, passthrough=False)
    # This public utility discriminator carries our own model bytes. No stock
    # shader/model source is consumed.
    entries[utility_path] = entries.pop("models/util/fullscreenlayer.json")
    effects_only = utility_kind == "project" or passthrough
    if effects_only:
        layer.update(name="Owned always-visible utility capture", visible=True,
                     config={"passthrough": passthrough})
        layer.pop("passthrough")
        layer["effects"][0]["visible"] = {"user": "fx", "value": active_at_launch}
        project["general"]["properties"] = {"fx": {"type": "bool", "value": active_at_launch}}
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
    if renamed and effects_only:
        ids = {1: 97, 20: 731, 30: 846}
        names = {97: "Renamed neutral canvas", 731: "Renamed always-visible Project capture",
                 846: "Renamed healthy late peer"}
        for item in scene["objects"]:
            item["id"] = ids[item["id"]]
            item["name"] = names[item["id"]]
        layer["effects"][0].update(id=7310, visible={"user": "alternate_gain_enabled",
                                                   "value": active_at_launch})
        project["general"]["properties"] = {
            "alternate_gain_enabled": {"type": "bool", "value": active_at_launch}}
        replacements = {"models/own_solid.json": "models/moved_canvas_color.json",
                        "effects/own_dim/effect.json": "effects/alternate_half_gain/effect.json",
                        "materials/own_dim.json": "materials/alternate_half_gain.json",
                        "own_dim": "alternate_half_gain"}

        def rename_text(value):
            for old, new in replacements.items():
                value = value.replace(old, new)
            return value

        entries = {rename_text(name): rename_text(data.decode()).encode()
                   for name, data in entries.items() if name != "scene.json"}
        entries["shaders/alternate_half_gain.vert"] = fullscreen.VERTEX.replace(
            b"v_TexCoord", b"v_AlternateUV")
        fragment = "shaders/alternate_half_gain.frag"
        if fragment in entries:
            entries[fragment] = (
                b"uniform sampler2D g_Texture0;\nvarying vec2 v_AlternateUV;\n"
                b"void main(){vec4 sampledValue=texSample2D(g_Texture0,v_AlternateUV);"
                b"gl_FragColor=vec4(sampledValue.rgb/2.0,sampledValue.a);}\n")
        entries["scene.json"] = encoded(json.loads(rename_text(json.dumps(scene))))
    elif renamed:
        entries = {name.replace("owned_member", "unseen_marker").replace("own_dim", "another_gain"):
                   data.replace(b"owned_member", b"unseen_marker").replace(b"own_dim", b"another_gain")
                   for name, data in entries.items()}
    if not effects_only:
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

    def test_startup_inactive_project_effect_drives_white_gray_white_pixels(self):
        with patch.object(fullscreen, "fixture_entries", partial(fixture_entries, utility_kind="project")):
            self.run_case(inactive_effect=True, launch={"fx": False},
                          sequence=[{"fx": True}, {"fx": False}], expected_dims=[True, False])

    def test_renamed_project_effect_uses_the_same_capture_and_bool_toggle(self):
        with patch.object(fullscreen, "fixture_entries", partial(fixture_entries, utility_kind="project",
                                                                  renamed=True)):
            self.run_case(inactive_effect=True, launch={"alternate_gain_enabled": False},
                          sequence=[{"alternate_gain_enabled": True}, {"alternate_gain_enabled": False}],
                          expected_dims=[True, False], effect_layer_id=731)

    def test_missing_project_shader_rejects_enable_and_preserves_healthy_peer(self):
        with patch.object(fullscreen, "fixture_entries", partial(fixture_entries, utility_kind="project")):
            self.run_case(inactive_effect=True, missing_shader=True, launch={"fx": False},
                          sequence=[{"fx": True}, {"fx": False}], expected_dims=[False, False],
                          expected_accepted=[False, True])

    def test_active_project_effect_can_hide_without_changing_its_source(self):
        with patch.object(fullscreen, "fixture_entries", partial(fixture_entries, utility_kind="project",
                                                                  active_at_launch=True)):
            self.run_case(inactive_effect=True, launch={"fx": True}, sequence=[{"fx": False}],
                          expected_dims=[False], initially_dimmed=True)

    def test_active_childless_passthrough_effect_uses_its_authored_background(self):
        with patch.object(fullscreen, "fixture_entries", partial(fixture_entries, passthrough=True,
                                                                  active_at_launch=True)):
            self.run_case(inactive_effect=True, launch={"fx": True}, sequence=[{"fx": False}],
                          expected_dims=[False], initially_dimmed=True)


if __name__ == "__main__":
    unittest.main()
