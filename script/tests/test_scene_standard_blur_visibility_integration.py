"""Owned two/four/five-pass filters -> actual App pixels and effect visibility.

The three-point weights and offsets below are our test oracle, not official
Gaussian weights or an official pixel-parity claim. Every package asset is
authored here or by the existing owned fullscreen fixture. The existing App
runner supplies input/App identity, same-window, Metal capture and drain checks.
These topologies qualify generic execution of these authored graphs, not all
effect combinations or the ordinary color ABI for arbitrary alpha/HDR inputs.
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
SQUARE_REGIONS = {"center": (124, 124, 132, 132), "horizontalWing": (92, 124, 100, 132),
                  "verticalWing": (124, 92, 132, 100), "healthyLaterPeer": (184, 120, 200, 136)}
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
DYNAMIC_COMPOSITE_FRAGMENT = b'''
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture2;
uniform float g_DistinctMixAmount; // {"material":"mixamount","default":0.5}
varying vec2 v_TexCoord;
vec4 fetchOriginal(vec2 point) { return texSample2D(g_Texture2, point); }
vec4 combineCoverage(vec4 filtered, vec4 original, float amount) {
    float coverage = mix(filtered.a, 1, step(filtered.a, 0));
    vec4 straightColor = vec4(filtered.rgb / coverage, filtered.a);
    return mix(original, straightColor, amount);
}
void main() {
    vec4 filtered = texSample2D(g_Texture0, v_TexCoord);
    vec4 original = fetchOriginal(v_TexCoord);
    if (g_DistinctMixAmount < 0.75) {
        vec4 repeated = texSample2D(g_Texture2, v_TexCoord);
        gl_FragColor = combineCoverage(filtered, (original + repeated) * 0.5, g_DistinctMixAmount);
    } else {
        gl_FragColor = combineCoverage(filtered, original, g_DistinctMixAmount);
    }
}
'''


def square_oracle(levels, regions, enabled):
    levels = levels if enabled else (255, 0, 0)
    return {name: {"canvasRect": rect, "expectedRGB": (0, 255, 0)
            if name == "healthyLaterPeer" else (levels[index],) * 3}
            for index, (name, rect) in enumerate(regions.items())}


def fixture_entries(*, sampling_scale=(1, 1), square_pattern=False,
                    rename_resources=False, processing_stages=None, target_names=None,
                    fbo_scale=4, active_square_rgb=None, regions=SQUARE_REGIONS,
                    dynamic_mix=False, dynamic_tint=False, capture_levels=None, **parameters):
    project, entries = _BASE_ENTRIES(**parameters)
    scene = json.loads(entries["scene.json"])
    scene["objects"][0]["color"] = "0 0 0"
    for index, x in enumerate((64, 128)):
        scene["objects"].insert(index + 1, {
            "id": index + 2, "name": "Owned full-height white stripe",
            "image": "models/own_solid.json", "origin": f"{x} 128 0",
            "size": "32 32" if square_pattern else "32 256", "color": "1 1 1"})
    layer = next(value for value in scene["objects"] if value["id"] == 20)
    stages = processing_stages or (("blur_downsample4", None, 0),
        ("blur_gaussian", sampling_scale, 0), ("blur_gaussian", sampling_scale, 1))
    target_names = target_names or ("_rt_OwnQuarterA", "_rt_OwnQuarterB")
    targets = [target_names[index % len(target_names)] for index in range(len(stages))]
    layer["name"] = f"Owned {len(stages) + 1}-pass filter graph"
    effect_path = ("effects/independent/soften/effect.json" if rename_resources
                   else "effects/own/blur/effect.json")
    shader_prefix = "independent/stages" if rename_resources else "own/effects"
    material_prefix = "materials/independent/soft" if rename_resources else "materials/own_blur"
    layer["effects"][0]["file"] = effect_path
    if dynamic_mix:
        project["general"]["properties"]["ownedBlend"] = {
            "type": "slider", "value": .5, "min": 0, "max": 1, "step": .5, "fraction": True}
        layer["effects"][0]["passes"] = [{} for _ in stages] + [{"constantshadervalues": {
            "mixamount": {"user": "ownedBlend", "value": .5}}}]
    if dynamic_tint:
        project["general"]["properties"]["ownedTint"] = {"type": "color", "value": "0.5 0.5 0.5"}
        layer["effects"][0]["passes"] = [{} for _ in stages] + [{"constantshadervalues": {
            "compositecolor": {"user": "ownedTint", "value": "0.5 0.5 0.5"}}}]
    entries["scene.json"] = encoded(scene)
    for path in ("effects/own_dim/effect.json", "materials/own_dim.json",
                 "shaders/own_dim.vert", "shaders/own_dim.frag"):
        entries.pop(path)
    shader_names = ({"blur_downsample4": "extract", "blur_gaussian": "weighted_filter",
                     "half_gain": "attenuate", "blur_combine": "output_mix"}
                    if rename_resources else {})
    passes = []
    for index, (shader, scale, direction) in enumerate((*stages, ("blur_combine", None, 0))):
        terminal = index == len(stages)
        effect_pass = {"material": f"{material_prefix}_{index}.json",
                       "bind": [{"name": targets[index - 1] if index else "previous", "index": 0}]}
        if not terminal:
            effect_pass["target"] = targets[index]
        if terminal:
            effect_pass["bind"].append({"name": "previous", "index": 2})
        passes.append(effect_pass)
        material = {"shader": f"{shader_prefix}/{shader_names.get(shader, shader)}", "textures": [],
                    "blending": "normal", "depthtest": "disabled",
                    "depthwrite": "disabled", "cullmode": "nocull"}
        if scale is not None:
            material.update(combos={"KERNEL": 1, "VERTICAL": direction},
                            constantshadervalues={"scale": " ".join(map(str, scale))})
        entries[effect_pass["material"]] = encoded({"passes": [material]})
    entries[effect_path] = encoded({"version": 1, "passes": passes,
        "fbos": [{"name": name, "scale": fbo_scale, "format": "rgba_backbuffer"}
                 for name in dict.fromkeys(targets)]})
    used_shaders = {stage[0] for stage in stages} | {"blur_combine"}
    for name, vertex, fragment in (
        ("blur_downsample4", VERTEX, b"uniform sampler2D g_Texture0;\nvarying vec2 v_TexCoord;\nvoid main(){gl_FragColor=texSample2D(g_Texture0,v_TexCoord);}\n"),
        ("blur_gaussian", GAUSSIAN_VERTEX, GAUSSIAN_FRAGMENT),
        ("half_gain", VERTEX, b"uniform sampler2D g_Texture0;\nvarying vec2 v_TexCoord;\nvoid main(){vec4 c=texSample2D(g_Texture0,v_TexCoord);gl_FragColor=vec4(c.rgb*0.5,c.a);}\n"),
        ("blur_combine", VERTEX, DYNAMIC_COMPOSITE_FRAGMENT if dynamic_mix else COMPOSITE_FRAGMENT)):
        if name not in used_shaders:
            continue
        if rename_resources and name == "blur_gaussian":
            vertex = vertex.replace(b"v_Offset", b"v_FilterDelta").replace(
                b"g_Scale.y * 0.125", b"g_Scale.y / 8.0").replace(
                b"g_Scale.x * 0.125", b"g_Scale.x / 8.0")
            fragment = fragment.replace(b"v_Offset", b"v_FilterDelta").replace(b"albedo", b"weightedColor")
        entries[f"shaders/{shader_prefix}/{shader_names.get(name, name)}.vert"] = vertex
        entries[f"shaders/{shader_prefix}/{shader_names.get(name, name)}.frag"] = fragment
    oracle = {"testSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "kernel": 1, "weights": [.25, .5, .25], "canvasOffset": 32,
        "processingStages": stages, "targetNames": list(dict.fromkeys(targets)), "fboScale": fbo_scale,
        "sequence": [False, True, False], "expectedWhiteStripeRGB": [255, 128, 255],
        "evidenceBoundary": "self-authored filter, not official Gaussian weights or pixel parity"}
    if square_pattern:
        horizontal, vertical = (amount != 0 for amount in sampling_scale)
        active = active_square_rgb or (round(255 * (.5 if horizontal else 1) * (.5 if vertical else 1)),
                  round(255 * .5 * (.5 if vertical else 1)) if horizontal else 0,
                  round(255 * .25 * (.5 if horizontal else 1)) if vertical else 0)
        oracle.pop("expectedWhiteStripeRGB")
        oracle.update(pattern="two32x32-squares", samplingScale=list(sampling_scale),
            sequence=[False, True, True, False],
            snapshotOracles={"scene-ready-window.png": square_oracle(active, regions, False),
                "scene-series-0002-window.png": square_oracle(active, regions, True),
                "scene-series-0004-window.png": square_oracle(active, regions, True),
                "scene-after-window.png": square_oracle(active, regions, False)},
            captureBoundary="two settled enabled captures; not adjacent-frame pixel samples")
        if processing_stages is None:
            oracle["allZeroBoundary"] = "downsample and upsample remain; not original-image identity"
        for name, levels in (capture_levels or {}).items():
            oracle["snapshotOracles"][name] = square_oracle(levels, regions, True)
    entries["owned-blur-oracle.json"] = encoded(oracle)
    if square_pattern and processing_stages is None:
        entries["owned-zero-axis-input.json"] = encoded({"scale": list(sampling_scale),
            "squareCenters": [[64, 128], [128, 128]], "squareSize": [32, 32],
            "fboScale": fbo_scale, "renamedResourcesAndEquivalentOffsets": rename_resources,
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
        self.assertRegex(log, r"generic shader execution state=generic-only profile=\S+ layer=20 effect=0 [^\n]*node=3 ")
        self.assertEqual(hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), identity)

    def _run_square_case(self, scale, expected_active, *, rename_resources=False,
                         processing_stages=None, target_names=None, fbo_scale=4,
                         regions=SQUARE_REGIONS, sampling_domain=None,
                         dynamic_mix=False, dynamic_tint=False, capture_levels=None):
        identity = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()

        def inputs(**parameters):
            return fixture_entries(sampling_scale=scale, square_pattern=True,
                rename_resources=rename_resources, processing_stages=processing_stages,
                target_names=target_names, fbo_scale=fbo_scale, active_square_rgb=expected_active,
                regions=regions, dynamic_mix=dynamic_mix, dynamic_tint=dynamic_tint,
                capture_levels=capture_levels, **parameters)

        def encode_protocol(value):
            # Fill the existing capture protocol before it is frozen/written
            # or the App starts; retain the one shared PNG measurement owner.
            if isinstance(value, dict) and "snapshotOracles" in value:
                value["snapshotOracles"] = {name: square_oracle((capture_levels or {}).get(name, expected_active), regions,
                    name.startswith("scene-series-")) for name in value["snapshotOracles"]}
                value["ownedFilterGraph"] = {"scale": list(scale), "fboScale": fbo_scale,
                    "processingStages": processing_stages, "targetNames": target_names,
                    "samplingDomain": sampling_domain,
                    "dynamicMix": dynamic_mix,
                    "dynamicTint": dynamic_tint,
                    "renamedResourcesAndEquivalentOffsets": rename_resources,
                    "boundary": "two settled enabled captures plus consecutive GPU completions, not adjacent-frame pixel samples"}
            return _ENCODED(value)

        with patch.object(fullscreen, "fixture_entries", inputs), patch.object(fullscreen, "encoded", encode_protocol):
            log, pixels = self.run_case(inactive_effect=True,
                launch={"mode": "on", "fx": False, **({"ownedBlend": .5} if dynamic_mix else {}),
                    **({"ownedTint": "0.5 0.5 0.5"} if dynamic_tint else {})},
                sequence=[{"fx": True, **({"ownedBlend": .5} if dynamic_mix else {}),
                    **({"ownedTint": "0.5 0.5 0.5"} if dynamic_tint else {})},
                    {"fx": True, **({"ownedBlend": 1} if dynamic_mix else {}),
                    **({"ownedTint": "1 1 1"} if dynamic_tint else {})}, {"fx": False}],
                expected_dims=[False, False, False])
        terminal = len(processing_stages) if processing_stages is not None else 3
        self.assertRegex(log, rf"generic shader execution state=generic-only profile=\S+ layer=20 effect=0 [^\n]*node={terminal} ")
        self.assertRegex(log, rf"axis=graph-execution [^\n]*layer=20 effect=0 [^\n]*"
            rf"materialNodes={terminal + 1} copyNodes=0 [^\n]*rejectedNodes=0 [^\n]*"
            r"compositorConsumed=true outcome=succeeded failure=- gpuCompletion=completed")
        completed = {int(frame) for frame in re.findall(
            r"state=completed frame=(\d+) surface=\d+ gpu=completed", log)}
        self.assertTrue(any(frame + 1 in completed for frame in completed), sorted(completed))
        self.assertIn("scene-series-0002-window.png", pixels)
        self.assertIn("scene-series-0004-window.png", pixels)
        self.assertEqual(hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), identity)

    def test_horizontal_sampling_with_zero_vertical_axis(self):
        self._run_square_case((.99, 0), (128, 128, 0), rename_resources=True)

    def test_vertical_sampling_with_zero_horizontal_axis(self):
        self._run_square_case((0, .99), (128, 0, 64))

    def test_all_zero_sampling_keeps_the_downsample_chain(self):
        self._run_square_case((0, 0), (255, 0, 0))

    def test_two_positive_axes_remain_a_separable_neighbor(self):
        self._run_square_case((.99, .99), (64, 64, 32))

    def test_two_pass_renamed_graph_samples_before_composite(self):
        self._run_square_case((.99, 0), (128, 128, 0), rename_resources=True,
            processing_stages=(("blur_gaussian", (.99, 0), 0),),
            target_names=("_rt_IndependentIntermediate",), fbo_scale=1)

    def test_typed_color_compiles_helper_conditional_samples_and_dynamic_uniform(self):
        self._run_square_case((.99, 0), (128, 128, 0), rename_resources=True, dynamic_mix=True,
            processing_stages=(("blur_gaussian", (.99, 0), 0),),
            target_names=("_rt_AuthoredWeightedInput",), fbo_scale=1,
            capture_levels={"scene-series-0002-window.png": (192, 64, 0),
                            "scene-series-0004-window.png": (128, 128, 0)})

    def test_typed_color_accepts_dynamic_composite_tint_without_static_permission(self):
        # Keep the original source-proven shader bytes; only the tint producer changes.
        self._run_square_case((.99, 0), (128, 128, 0), rename_resources=True, dynamic_tint=True,
            processing_stages=(("blur_gaussian", (.99, 0), 0),),
            target_names=("_rt_DynamicTintInput",), fbo_scale=1,
            capture_levels={"scene-series-0002-window.png": (64, 64, 0),
                            "scene-series-0004-window.png": (128, 128, 0)})

    def test_five_pass_renamed_graph_keeps_independent_sampling_and_gain(self):
        # UV offsets span the captured viewport, including its cover crop.
        # Half gain makes skipping the fourth producer visible in every lit ROI.
        self._run_square_case((.99, 1.99), (32, 32, 16), rename_resources=True,
            processing_stages=(("blur_downsample4", None, 0),
                ("blur_gaussian", (.99, .17), 0), ("blur_gaussian", (.37, 1.99), 1),
                ("half_gain", None, 0)),
            target_names=("_rt_IndependentSeed", "_rt_IndependentAcross",
                          "_rt_IndependentAlong", "_rt_IndependentAttenuated"),
            fbo_scale=2, regions={**SQUARE_REGIONS, "verticalWing": (124, 83, 132, 91)},
            sampling_domain={"sourceExtent": [3024, 1964], "uvDomain": "full captured viewport",
                "coverScale": "max(sourceWidth / 256, sourceHeight / 256)",
                "visibleCanvasHeight": "sourceHeight / coverScale",
                "verticalCanvasOffset": "(1.99 / 8) * visibleCanvasHeight = 41.3583068783",
                "verticalWingCenterY": "128 - verticalCanvasOffset = 86.6416931217",
                "verticalWingROI": "round(verticalWingCenterY) +/- 4 = [83, 91]"})
