"""Owned KERNEL1 four-pass blur -> actual App pixels and effect visibility.

The three-point weights and offsets below are our test oracle, not official
Gaussian weights or an official pixel-parity claim. Every package asset is
authored here or by the existing owned fullscreen fixture. The existing App
runner supplies input/App identity, same-window, Metal capture and drain checks.
"""
from pathlib import Path
import hashlib
import json
import unittest
from unittest.mock import patch

from . import test_scene_fullscreen_visibility_integration as fullscreen
from .test_scene_composition_authored_order_integration import VERTEX, encoded


_BASE_ENTRIES = fullscreen.fixture_entries
GAUSSIAN_VERTEX = b'''
// [COMBO] {"combo":"KERNEL","default":0,"options":[0,1]}
// [COMBO] {"combo":"VERTICAL","default":0,"options":[0,1]}
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
uniform vec2 g_Scale; // {"material":"scale","default":"1 1"}
varying vec2 v_TexCoord;
varying vec2 v_Offset;
void main() {
    gl_Position = vec4(a_Position, 1.0);
    v_TexCoord = a_TexCoord;
#if VERTICAL == 1
    v_Offset = vec2(0.0, g_Scale.y * 0.125);
#else
    v_Offset = vec2(g_Scale.x * 0.125, 0.0);
#endif
}
'''
GAUSSIAN_FRAGMENT = b'''
uniform sampler2D g_Texture0;
varying vec2 v_TexCoord;
varying vec2 v_Offset;
void main() {
#if KERNEL == 1
    vec4 albedo = texSample2D(g_Texture0, v_TexCoord - v_Offset) * 0.25
                + texSample2D(g_Texture0, v_TexCoord) * 0.5
                + texSample2D(g_Texture0, v_TexCoord + v_Offset) * 0.25;
    gl_FragColor = albedo;
#else
    gl_FragColor = texSample2D(g_Texture0, v_TexCoord);
#endif
}
'''
COMPOSITE_FRAGMENT = b'''
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture2;
uniform vec3 g_CompositeColor; // {"material":"compositecolor","default":"1 1 1"}
varying vec2 v_TexCoord;
vec4 identityComposite(vec4 oldColor, vec4 effectColor) { return effectColor; }
vec4 compositeCarrier(vec4 oldColor, vec4 effectColor) {
    effectColor.rgb *= g_CompositeColor;
    return identityComposite(oldColor, effectColor);
}
void main() {
    vec4 blurred = texSample2D(g_Texture0, v_TexCoord);
    vec4 previous = texSample2D(g_Texture2, v_TexCoord);
    float mask = 1.0;
    float divisor = mix(blurred.a, 1, step(blurred.a, 0));
    blurred = compositeCarrier(previous, vec4(blurred.rgb / divisor, blurred.a));
    blurred = mix(previous, blurred, mask);
    gl_FragColor = blurred;
}
'''


def fixture_entries(**parameters):
    project, entries = _BASE_ENTRIES(**parameters)
    scene = json.loads(entries["scene.json"])
    scene["objects"][0]["color"] = "0 0 0"
    for index, x in enumerate((64, 128)):
        scene["objects"].insert(index + 1, {
            "id": index + 2, "name": "Owned full-height white stripe",
            "image": "models/own_solid.json", "origin": f"{x} 128 0",
            "size": "32 256", "color": "1 1 1"})
    layer = next(value for value in scene["objects"] if value["id"] == 20)
    layer["name"] = "Owned four-pass KERNEL1 blur"
    layer["effects"][0]["file"] = "effects/own/blur/effect.json"
    entries["scene.json"] = encoded(scene)
    for path in ("effects/own_dim/effect.json", "materials/own_dim.json",
                 "shaders/own_dim.vert", "shaders/own_dim.frag"):
        entries.pop(path)
    material_names = ("downsample", "horizontal", "vertical", "combine")
    targets = ("_rt_OwnQuarterA", "_rt_OwnQuarterB", "_rt_OwnQuarterA", None)
    sources = ("previous", "_rt_OwnQuarterA", "_rt_OwnQuarterB", "_rt_OwnQuarterA")
    passes = []
    for index, name in enumerate(material_names):
        effect_pass = {"material": f"materials/own_blur_{name}.json",
                       "bind": [{"name": sources[index], "index": 0}]}
        if targets[index]:
            effect_pass["target"] = targets[index]
        if index == 3:
            effect_pass["bind"].append({"name": "previous", "index": 2})
        passes.append(effect_pass)
        shader = "blur_gaussian" if index in (1, 2) else "blur_downsample4" if index == 0 else "blur_combine"
        material = {"shader": f"own/effects/{shader}", "textures": [],
                    "blending": "normal", "depthtest": "disabled",
                    "depthwrite": "disabled", "cullmode": "nocull"}
        if index in (1, 2):
            material.update(combos={"KERNEL": 1, "VERTICAL": index - 1},
                            constantshadervalues={"scale": "1 1"})
        entries[effect_pass["material"]] = encoded({"passes": [material]})
    entries["effects/own/blur/effect.json"] = encoded({"version": 1, "passes": passes,
        "fbos": [{"name": name, "scale": 4, "format": "rgba_backbuffer"}
                 for name in ("_rt_OwnQuarterA", "_rt_OwnQuarterB")]})
    for name, vertex, fragment in (
        ("blur_downsample4", VERTEX, b"uniform sampler2D g_Texture0;\nvarying vec2 v_TexCoord;\nvoid main(){gl_FragColor=texSample2D(g_Texture0,v_TexCoord);}\n"),
        ("blur_gaussian", GAUSSIAN_VERTEX, GAUSSIAN_FRAGMENT),
        ("blur_combine", VERTEX, COMPOSITE_FRAGMENT)):
        entries[f"shaders/own/effects/{name}.vert"] = vertex
        entries[f"shaders/own/effects/{name}.frag"] = fragment
    entries["owned-blur-oracle.json"] = encoded({"testSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "kernel": 1, "weights": [.25, .5, .25], "canvasOffset": 32,
        "sequence": [False, True, False], "expectedWhiteStripeRGB": [255, 128, 255],
        "evidenceBoundary": "self-authored filter, not official Gaussian weights or pixel parity"})
    return project, entries


class SceneStandardBlurVisibilityIntegrationTests(unittest.TestCase):
    setUpClass = classmethod(fullscreen.SceneFullscreenVisibilityIntegrationTests.setUpClass.__func__)
    run_case = fullscreen.SceneFullscreenVisibilityIntegrationTests.run_case

    def test_kernel_one_blur_visibility_changes_and_restores_pixels(self):
        identity = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
        with patch.object(fullscreen, "fixture_entries", fixture_entries):
            log, _ = self.run_case(inactive_effect=True, launch={"mode": "on", "fx": False},
                sequence=[{"fx": True}, {"fx": False}], expected_dims=[True, False])
        self.assertRegex(log, r"generic shader execution state=generic-only profile=source-proven-previous-blurred-composite layer=20 effect=0 [^\n]*node=3 ")
        self.assertNotIn("source-proven-previous-blurred-composite-unowned", log)
        self.assertEqual(hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), identity)
