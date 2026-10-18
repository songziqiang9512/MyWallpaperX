"""Owned KERNEL1 four-pass blur -> actual App pixels and effect visibility.

The three-point weights and offsets below are our test oracle, not official
Gaussian weights or an official pixel-parity claim. Every package asset is
authored here or by the existing owned fullscreen fixture. The existing App
runner supplies input/App identity, same-window, Metal capture and drain checks.
"""
from pathlib import Path
import hashlib
import json
import re
import unittest
from unittest.mock import patch

from . import test_scene_fullscreen_visibility_integration as fullscreen
from .test_scene_composition_authored_order_integration import VERTEX, encoded


_BASE_ENTRIES = fullscreen.fixture_entries
_ENCODED = fullscreen.encoded
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


def fixture_entries(*, sampling_scale=(1, 1), square_pattern=False,
                    rename_resources=False, **parameters):
    project, entries = _BASE_ENTRIES(**parameters)
    scene = json.loads(entries["scene.json"])
    scene["objects"][0]["color"] = "0 0 0"
    for index, x in enumerate((64, 128)):
        scene["objects"].insert(index + 1, {
            "id": index + 2, "name": "Owned full-height white stripe",
            "image": "models/own_solid.json", "origin": f"{x} 128 0",
            "size": "32 32" if square_pattern else "32 256", "color": "1 1 1"})
    layer = next(value for value in scene["objects"] if value["id"] == 20)
    layer["name"] = "Owned four-pass KERNEL1 blur"
    effect_path = ("effects/independent/soften/effect.json" if rename_resources
                   else "effects/own/blur/effect.json")
    shader_prefix = "independent/stages" if rename_resources else "own/effects"
    material_prefix = "materials/independent/soft" if rename_resources else "materials/own_blur"
    layer["effects"][0]["file"] = effect_path
    entries["scene.json"] = encoded(scene)
    for path in ("effects/own_dim/effect.json", "materials/own_dim.json",
                 "shaders/own_dim.vert", "shaders/own_dim.frag"):
        entries.pop(path)
    material_names = ("downsample", "horizontal", "vertical", "combine")
    targets = ("_rt_OwnQuarterA", "_rt_OwnQuarterB", "_rt_OwnQuarterA", None)
    sources = ("previous", "_rt_OwnQuarterA", "_rt_OwnQuarterB", "_rt_OwnQuarterA")
    passes = []
    for index, name in enumerate(material_names):
        effect_pass = {"material": f"{material_prefix}_{name}.json",
                       "bind": [{"name": sources[index], "index": 0}]}
        if targets[index]:
            effect_pass["target"] = targets[index]
        if index == 3:
            effect_pass["bind"].append({"name": "previous", "index": 2})
        passes.append(effect_pass)
        shader = "blur_gaussian" if index in (1, 2) else "blur_downsample4" if index == 0 else "blur_combine"
        material = {"shader": f"{shader_prefix}/{shader}", "textures": [],
                    "blending": "normal", "depthtest": "disabled",
                    "depthwrite": "disabled", "cullmode": "nocull"}
        if index in (1, 2):
            material.update(combos={"KERNEL": 1, "VERTICAL": index - 1},
                            constantshadervalues={"scale": " ".join(map(str, sampling_scale))})
        entries[effect_pass["material"]] = encoded({"passes": [material]})
    entries[effect_path] = encoded({"version": 1, "passes": passes,
        "fbos": [{"name": name, "scale": 4, "format": "rgba_backbuffer"}
                 for name in ("_rt_OwnQuarterA", "_rt_OwnQuarterB")]})
    for name, vertex, fragment in (
        ("blur_downsample4", VERTEX, b"uniform sampler2D g_Texture0;\nvarying vec2 v_TexCoord;\nvoid main(){gl_FragColor=texSample2D(g_Texture0,v_TexCoord);}\n"),
        ("blur_gaussian", GAUSSIAN_VERTEX, GAUSSIAN_FRAGMENT),
        ("blur_combine", VERTEX, COMPOSITE_FRAGMENT)):
        if rename_resources and name == "blur_gaussian":
            vertex = vertex.replace(b"v_Offset", b"v_FilterDelta").replace(
                b"g_Scale.y * 0.125", b"g_Scale.y / 8.0").replace(
                b"g_Scale.x * 0.125", b"g_Scale.x / 8.0")
            fragment = fragment.replace(b"v_Offset", b"v_FilterDelta").replace(b"albedo", b"weightedColor")
        entries[f"shaders/{shader_prefix}/{name}.vert"] = vertex
        entries[f"shaders/{shader_prefix}/{name}.frag"] = fragment
    oracle = {"testSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "kernel": 1, "weights": [.25, .5, .25], "canvasOffset": 32,
        "sequence": [False, True, False], "expectedWhiteStripeRGB": [255, 128, 255],
        "evidenceBoundary": "self-authored filter, not official Gaussian weights or pixel parity"}
    if square_pattern:
        horizontal, vertical = (amount != 0 for amount in sampling_scale)
        active = (round(255 * (.5 if horizontal else 1) * (.5 if vertical else 1)),
                  round(255 * .5 * (.5 if vertical else 1)) if horizontal else 0,
                  round(255 * .25 * (.5 if horizontal else 1)) if vertical else 0)
        rectangles = {"center": (124, 124, 132, 132), "horizontalWing": (92, 124, 100, 132),
                      "verticalWing": (124, 92, 132, 100), "healthyLaterPeer": (184, 120, 200, 136)}
        def description(enabled):
            levels = active if enabled else (255, 0, 0)
            return {name: {"canvasRect": rect, "expectedRGB": (0, 255, 0)
                    if name == "healthyLaterPeer" else (levels[index],) * 3}
                    for index, (name, rect) in enumerate(rectangles.items())}
        oracle.pop("expectedWhiteStripeRGB")
        oracle.update(pattern="two32x32-squares", samplingScale=list(sampling_scale),
            qualifiedAxisAmounts=[0, .99], fboScale=4, sequence=[False, True, True, False],
            snapshotOracles={"scene-ready-window.png": description(False),
                "scene-series-0002-window.png": description(True),
                "scene-series-0004-window.png": description(True),
                "scene-after-window.png": description(False)},
            captureBoundary="two settled enabled captures; not adjacent-frame pixel samples",
            allZeroBoundary="downsample and upsample remain; not original-image identity")
    entries["owned-blur-oracle.json"] = encoded(oracle)
    if square_pattern:
        entries["owned-zero-axis-input.json"] = encoded({"scale": list(sampling_scale),
            "squareCenters": [[64, 128], [128, 128]], "squareSize": [32, 32],
            "fboScale": 4, "renamedResourcesAndEquivalentOffsets": rename_resources,
            "boundary": "zero sampling offsets retain downsample/upsample; not original-image identity"})
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

    def _run_zero_axis_case(self, scale, expected_active, *, rename_resources=False):
        identity = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
        regions = {"center": (124, 124, 132, 132), "horizontalWing": (92, 124, 100, 132),
                   "verticalWing": (124, 92, 132, 100), "healthyLaterPeer": (184, 120, 200, 136)}

        def inputs(**parameters):
            return fixture_entries(sampling_scale=scale, square_pattern=True,
                                   rename_resources=rename_resources, **parameters)

        def oracle(name):
            # Two settled captures while enabled, then the original producer
            # is restored. These are not adjacent GPU pixel captures.
            active = name.startswith("scene-series-")
            levels = expected_active if active else (255, 0, 0)
            return {name: {"canvasRect": rect,
                        "expectedRGB": (0, 255, 0) if name == "healthyLaterPeer"
                        else (levels[index],) * 3}
                        for index, (name, rect) in enumerate(regions.items())}

        def encode_protocol(value):
            # Fill the existing capture protocol before it is frozen/written
            # or the App starts; retain the one shared PNG measurement owner.
            if isinstance(value, dict) and "snapshotOracles" in value:
                value["snapshotOracles"] = {name: oracle(name) for name in value["snapshotOracles"]}
                value["gaussianZeroAxis"] = {"scale": list(scale), "fboScale": 4,
                    "renamedResourcesAndEquivalentOffsets": rename_resources,
                    "boundary": "two settled enabled captures plus consecutive GPU completions, not adjacent-frame pixel samples"}
            return _ENCODED(value)

        with patch.object(fullscreen, "fixture_entries", inputs), patch.object(fullscreen, "encoded", encode_protocol):
            log, pixels = self.run_case(inactive_effect=True, launch={"mode": "on", "fx": False},
                sequence=[{"fx": True}, {"fx": True}, {"fx": False}], expected_dims=[False, False, False])
        self.assertRegex(log, r"generic shader execution state=generic-only profile=source-proven-previous-blurred-composite layer=20 effect=0 [^\n]*node=3 ")
        self.assertNotIn("source-proven-previous-blurred-composite-unowned", log)
        completed = {int(frame) for frame in re.findall(
            r"state=completed frame=(\d+) surface=\d+ gpu=completed", log)}
        self.assertTrue(any(frame + 1 in completed for frame in completed), sorted(completed))
        self.assertIn("scene-series-0002-window.png", pixels)
        self.assertIn("scene-series-0004-window.png", pixels)
        self.assertEqual(hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), identity)

    def test_horizontal_sampling_with_zero_vertical_axis(self):
        self._run_zero_axis_case((.99, 0), (128, 128, 0), rename_resources=True)

    def test_vertical_sampling_with_zero_horizontal_axis(self):
        self._run_zero_axis_case((0, .99), (128, 0, 64))

    def test_all_zero_sampling_keeps_the_downsample_chain(self):
        self._run_zero_axis_case((0, 0), (255, 0, 0))

    def test_two_positive_axes_remain_a_separable_neighbor(self):
        self._run_zero_axis_case((.99, .99), (64, 64, 32))
