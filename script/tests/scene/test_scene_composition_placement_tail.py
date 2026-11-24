"""Authored local Compose FBOs and a placement-raster tail through Metal in the App."""

import json
import math
import re
import unittest
from unittest.mock import patch

from script.scene.scene_wallpaper_graph_output_metrics import (
    structured_runtime_observations, terminal_composition_snapshot,
)
from script.tests.scene import test_scene_composition_authored_order_integration as authored
from script.web.web_benchmark_capture import png_rgb_pixels


LOCAL_SIZE = (64, 32)
HALF_SIZE = (32, 16)
BACKGROUND_RGB = (16, 24, 32)
STRIPE_RGB = (42, 75, 134)
COMPOSITION_PREFIX = "MWX SCENE COMPOSITION OBSERVATION: "

VERTEX = b"""
uniform mat4 g_ModelViewProjectionMatrix;
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 v_CardUV;
void main() {
    gl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);
    v_CardUV = a_TexCoord;
}
"""
PIXEL_INPUT = """
uniform sampler2D g_Texture0;
varying vec2 v_CardUV;
"""
SEED = """
uniform vec3 u_Paint; // {"material":"ink","default":"0.2 0.4 0.8"}
varying vec2 v_CardUV;
void main() {
    vec3 paint = u_Paint;
    float coverage = 0.0;
    for (int tap = 0; tap < 2; tap++) {
        float candidate = (192.0 / 255.0) * step(v_CardUV.x, 0.5);
        coverage = max(coverage, candidate);
    }
    gl_FragColor = vec4(paint, coverage);
}
"""


def alpha_fragment(weight):
    return PIXEL_INPUT + f"""
void main() {{
    vec4 sampled = texSample2D(g_Texture0, v_CardUV);
    sampled.a *= {weight};
    gl_FragColor = sampled;
}}
"""


def fixture(*, tail_visible, renamed):
    project, entries = authored.fixture_entries(copy_background=False, childless=True,
                                                effect=False, renamed=renamed)
    scene = json.loads(entries["scene.json"])
    background, root = scene["objects"]
    background["color"] = " ".join(str(channel / 255.0) for channel in BACKGROUND_RGB)
    root.update(size="64 32", scale="2 3 1", config={"passthrough": True}, colorBlendMode=31)
    entries[root["image"]] = authored.encoded({"width": 64, "height": 32, "autosize": False})

    prefix = "rekeyed_raster" if renamed else "owned_raster"
    fbo = "_rt_RekeyedHalf" if renamed else "_rt_OwnedHalf"
    stripe = "step(0.5, fract(v_CardUV.y * 32.0 + 0.125))"
    if renamed:
        stripe = "step(0.5, fract(v_CardUV.y * (8.0 * 4.0) + 1.0 / 8.0))"
    fragments = {
        "seed": SEED,
        "downsample": PIXEL_INPUT + "void main() { gl_FragColor = texSample2D(g_Texture0, v_CardUV); }",
        "restore": alpha_fragment("2.0 / 3.0"),
        "stripe": alpha_fragment(stripe),
    }
    materials = {}
    for name, fragment in fragments.items():
        shader = f"{prefix}_{name}"
        material = f"materials/{shader}.json"
        materials[name] = material
        vertex = VERTEX
        if renamed:
            vertex = vertex.replace(b"v_CardUV", b"v_RetitledST")
            fragment = (fragment.replace("v_CardUV", "v_RetitledST")
                        .replace("sampled", "earlierPaint").replace("coverage", "opacity"))
        entries[material] = authored.encoded({"passes": [{"shader": shader,
            "textures": [] if name == "seed" else [None], "blending": "normal", "depthtest": "disabled",
            "depthwrite": "disabled", "cullmode": "nocull"}]})
        entries[f"shaders/{shader}.vert"] = vertex
        entries[f"shaders/{shader}.frag"] = fragment.encode()

    effects = (
        ("seed", {"passes": [{"material": materials["seed"]}]}),
        ("prefix", {"fbos": [{"name": fbo, "format": "rgba_backbuffer", "scale": 2}],
                    "passes": [{"material": materials["downsample"], "target": fbo,
                                "bind": [{"index": 0, "name": "previous"}]},
                               {"material": materials["restore"],
                                "bind": [{"index": 0, "name": fbo}]}]}),
        ("tail", {"passes": [{"material": materials["stripe"]}]}),
    )
    root["effects"] = []
    for index, (name, effect) in enumerate(effects):
        path = f"effects/{prefix}_{name}/effect.json"
        entries[path] = authored.encoded(effect)
        root["effects"].append({"id": root["id"] * 10 + index, "file": path,
                                "visible": name != "tail" or tail_visible})
    entries["scene.json"] = authored.encoded(scene)

    patches = {"transparentHalf": ((141, 111, 151, 121), BACKGROUND_RGB),
               "outOfBounds": ((201, 111, 211, 121), BACKGROUND_RGB)}
    if not tail_visible:
        patches["prefixWithoutTail"] = ((101, 111, 111, 121), STRIPE_RGB)
    protocol = {"canvas": authored.CANVAS, "layerIDs": {"composition": root["id"]},
                "localSourceExtent": LOCAL_SIZE, "prefixFramebufferExtent": HALF_SIZE,
                "terminalEnabled": tail_visible, "renamed": renamed,
                "scanCanvas": [108, 85, 171], "darkRGB": BACKGROUND_RGB,
                "litRGB": STRIPE_RGB, "channelTolerance": authored.CHANNEL_TOLERANCE,
                "oracle": {name: {"canvasRect": rect, "expectedRGB": color}
                           for name, (rect, color) in patches.items()}}
    return project, entries, protocol


def measure_capture(path, protocol, base_measure):
    result = base_measure(path, protocol)
    width, height, rows = png_rgb_pixels(path)
    factor = max(width / 256, height / 256)
    x, y0, y1 = protocol["scanCanvas"]
    column = math.floor(width / 2 + (x - 128) * factor)
    top = math.ceil(height / 2 + (y0 - 128) * factor)
    bottom = math.floor(height / 2 + (y1 - 128) * factor)
    if not (0 <= column < width and 0 <= top < bottom <= height):
        raise AssertionError(f"Stripe control cropped at {width}×{height}")

    def matches(pixel, expected):
        return all(abs(value - wanted) <= authored.CHANNEL_TOLERANCE
                   for value, wanted in zip(pixel, expected, strict=True))

    pixels = [rows[y][column * 3:column * 3 + 3] for y in range(top, bottom)]
    labels = [1 if matches(pixel, STRIPE_RGB) else 0 if matches(pixel, BACKGROUND_RGB) else -1
              for pixel in pixels]
    accepted = [label for label in labels if label >= 0]
    result["stripes"] = {"samples": len(labels), "lit": labels.count(1), "dark": labels.count(0),
                         "transitions": sum(a != b for a, b in zip(accepted, accepted[1:]))}
    return result


class SceneCompositionPlacementTailTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        authored.SceneCompositionAuthoredOrderIntegrationTests.setUpClass.__func__(cls)

    def test_transparent_local_prefix_and_additive_placement_tail(self):
        self.run_fixture(tail_visible=True, renamed=False)

    def test_inactive_placement_tail_keeps_the_local_prefix(self):
        self.run_fixture(tail_visible=False, renamed=False)

    def test_rekeyed_placement_tail_uses_the_same_raster_and_color(self):
        self.run_fixture(tail_visible=True, renamed=True)

    def run_fixture(self, *, tail_visible, renamed):
        project, entries, protocol = fixture(tail_visible=tail_visible, renamed=renamed)
        base_measure = authored.measure_capture
        with patch.object(authored, "fixture_entries", return_value=(project, entries)), \
                patch.object(authored, "preregistration", return_value=protocol), \
                patch.object(authored, "measure_capture",
                             side_effect=lambda path, spec: measure_capture(path, spec, base_measure)):
            log, pixels = authored.SceneCompositionAuthoredOrderIntegrationTests.run_case(
                self, childless=True, copy_background=False)

        for capture, measurement in pixels.items():
            with self.subTest(capture=capture):
                stripes = measurement["stripes"]
                if tail_visible:
                    self.assertGreater(stripes["lit"], .30 * stripes["samples"], stripes)
                    self.assertGreater(stripes["dark"], .30 * stripes["samples"], stripes)
                    self.assertGreaterEqual(stripes["transitions"], 50, stripes)
                else:
                    self.assertEqual(stripes["lit"], stripes["samples"], stripes)
                    self.assertEqual(stripes["transitions"], 0, stripes)

        root = protocol["layerIDs"]["composition"]
        for name, event in self.capture_events(log):
            with self.subTest(capture=name, request=event["captureRequestID"]):
                self.assert_placement_rows(event["rows"], root, tail_visible)

    def capture_events(self, log):
        observations = structured_runtime_observations(log, COMPOSITION_PREFIX)
        self.assertEqual(observations["parse_errors"], 0)
        for reason in ("ready", "after"):
            requests = re.findall(rf"phase=snapshot reason={reason} request=(\d+) source=metal ", log)
            self.assertEqual(len(requests), 1, log[-3000:])
            request = int(requests[0])
            encoded = re.search(rf"phase=snapshot-encoded request={request} commandBufferToken=(\d+) "
                                r"textureToken=(\d+) width=(\d+) height=(\d+)", log)
            self.assertIsNotNone(encoded)
            command, texture, width, height = encoded.groups()
            receipt = terminal_composition_snapshot({"status": "captured", "request_id": request,
                "command_buffer_token": command, "texture_token": texture,
                "source_width": int(width), "source_height": int(height)}, observations)
            self.assertTrue(receipt["composition_receipt_matched"], receipt)
            event, = [e for e in observations["events"] if e.get("captureRequestID") == request
                      and e["commandBufferToken"] == command]
            self.assertEqual((event["gpuStatus"], event["truncatedRows"]), ("completed", 0))
            yield reason, event

    def assert_placement_rows(self, rows, root, tail_visible):
        cohort = [row for row in rows if row.get("layerID") == root]
        captures = [row for row in cohort if row["kind"] == "sourceCapture"
                    and row.get("outcome") == "encoded"]
        local = [row for row in cohort if row["kind"] == "material"
                 and row.get("outcome") == "draw-encoded"]
        replay = [row for row in cohort if row["kind"] == "terminal-material-replay"
                  and row.get("outcome") == "draw-encoded"]
        tail = [row for row in cohort if row["kind"] == "tail-consume"
                and row.get("outcome") == "terminal-consumed"]
        seal = [row for row in rows if row["kind"] == "frame-seal" and row.get("outcome") == "sealed"]
        self.assertEqual([len(captures), len(local), len(tail), len(seal)], [1, 3, 1, 1], cohort)
        first, downsample, restore = local
        self.assertEqual([r["effectIndex"] for r in local], [0, 1, 1], cohort)
        self.assertEqual([(r["target"]["width"], r["target"]["height"])
                          for r in [captures[0], *local]], [LOCAL_SIZE, LOCAL_SIZE, HALF_SIZE, LOCAL_SIZE])
        self.assertEqual(first["access"], "no-texture-input")
        self.assertEqual([r["source"]["textureToken"] for r in (downsample, restore)],
                         [r["target"]["textureToken"] for r in (first, downsample)])
        self.assertEqual(len(replay), int(tail_visible), cohort)
        if tail_visible:
            draw = replay[0]
            self.assertEqual((draw["effectIndex"], draw["slot"], draw["access"]), (2, 0, "texture-bind"))
            self.assertEqual(draw["source"]["textureToken"], restore["target"]["textureToken"])
            self.assertEqual((draw["source"]["width"], draw["source"]["height"]), LOCAL_SIZE)
            self.assertEqual(draw["target"]["textureToken"], seal[0]["target"]["textureToken"])
            self.assertEqual(tail[0]["access"], "terminal-material-replay")
            self.assertFalse([r for r in cohort if r["kind"] in ("background-copy", "color-blend-background")], cohort)
            order = [captures[0], *local, draw, tail[0], seal[0]]
        else:
            self.assertEqual(tail[0]["access"], "output-texture-composite")
            order = [captures[0], *local, tail[0], seal[0]]
        self.assertEqual([rows.index(row) for row in order], sorted(rows.index(row) for row in order))
