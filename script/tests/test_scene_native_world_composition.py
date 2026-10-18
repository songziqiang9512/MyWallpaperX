#!/usr/bin/env python3
"""Native framebuffer source Program and terminal depth through a frozen App.

All media and shaders are authored here. The existing real-App/Metal runner
owns dispatch, immutable identities, snapshots and stop checks. This fixture
does not replace the source Program, compositor, model depth or camera owners.
"""
from __future__ import annotations

import hashlib
import json
import math
import os
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
import zlib

from script.tests import test_scene_reflection_history_integration as app_runner
from script.tests.test_scene_static_model_reader import build_model
from script.web_benchmark_capture import png_rgb_pixels


REPO = Path(__file__).resolve().parents[2]
TARGET_LAYER = 20
LOCAL_SIZE = (128, 96)
PARENT_ORIGIN = (.25, -.12, 0.)
PARENT_SCALE = (1.1, .9, 1.)
PARENT_ANGLES = (.10, .60, .08)
PLANE_SIZE = (2.4, 1.6)
BACKGROUND_BOUNDS = (-9., 9., -6., 6.)
BACKGROUND_Z = -2.
EYE_Z = 6.
FOV = math.radians(60)
GRID_SIZE = (256, 192)
ORANGE = (232, 95, 20)
GREEN = (20, 220, 60)
TOLERANCE = 4


def encoded(value) -> bytes:
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()


def grid_color(x: int, y: int) -> tuple[int, int, int]:
    """Nonperiodic cell colors plus an asymmetric L; no runtime-derived oracle."""
    if (9 <= x < 12 and 11 <= y < 39) or (9 <= x < 37 and 36 <= y < 39):
        return (245, 241, 231)
    if x % 8 == 0 or y % 8 == 0:
        return (12, 18, 28)
    column, row = x // 8, y // 8
    return (30 + (17 * column + 29 * row) % 190,
            30 + (43 * column + 11 * row) % 190,
            30 + (7 * column + 47 * row) % 190)


def png(width: int, height: int, color) -> bytes:
    def chunk(kind: bytes, data: bytes) -> bytes:
        return (struct.pack(">I", len(data)) + kind + data
                + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF))
    rows = b"".join(b"\0" + b"".join(bytes((*color(x, y), 255))
                                   for x in range(width)) for y in range(height))
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


def mdl_quad(x0, x1, y0, y1, z, material):
    # Explicit top-left texture UV in a native Y-up world. No renderer shim.
    vertices = [((x, y, z), (0., 0., 1.), (1., 0., 0., 1.), uv)
                for x, y, uv in [(x0, y0, (0., 1.)), (x1, y0, (1., 1.)),
                                 (x1, y1, (1., 0.)), (x0, y1, (0., 0.))]]
    return build_model(vertices=vertices, indices=(0, 1, 2, 0, 2, 3),
                       bounds=(x0, y0, z, x1, y1, z), material=material.encode())


def model_material(texture: str) -> bytes:
    return encoded({"passes": [{
        "shader": "generic4", "textures": [texture],
        "combos": {"LIGHTING": 0, "REFLECTION": 0, "NORMALMAP": 0},
        "constantshadervalues": {"alpha": 1, "brightness": 1, "color": [1, 1, 1]},
        "blending": "normal", "depthtest": "enabled", "depthwrite": "enabled",
        "cullmode": "nocull"}]})


SOURCE_VERTEX = b"""
attribute vec3 a_Position;
uniform mat4 g_ModelViewProjectionMatrix;
uniform vec2 g_LocalSize; // {"material":"localsize","default":"128 96"}
varying vec3 v_MainPlane;
void main() {
    vec4 worldClip = g_ModelViewProjectionMatrix * vec4(a_Position, 1.0);
    v_MainPlane = vec3(worldClip.x, worldClip.y, worldClip.w);
    gl_Position = vec4(a_Position.xy * (vec2(2.0) / g_LocalSize), 0.0, 1.0);
}
"""
SOURCE_FRAGMENT = b"""
uniform sampler2D g_Texture0;
varying vec3 v_MainPlane;
void main() {
    vec2 normalizedView = v_MainPlane.xy / v_MainPlane.z;
    vec2 mainUV = vec2(0.5 + 0.5 * normalizedView.x,
                       0.5 - 0.5 * normalizedView.y);
    gl_FragColor = texSample2D(g_Texture0, mainUV);
}
"""
EFFECT_VERTEX = b"""
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 v_TexCoord;
void main() { gl_Position = vec4(a_Position, 1.0); v_TexCoord = a_TexCoord; }
"""
EFFECT_FRAGMENT = b"""
uniform sampler2D g_Texture0;
varying vec2 v_TexCoord;
void main() {
    vec4 before = texSample2D(g_Texture0, v_TexCoord);
    gl_FragColor = vec4(vec3(1.0) - before.rgb, 1.0);
}
"""


def fixture_entries(_label: int = 0) -> dict[str, bytes]:
    """One complete authored scene; the label is the existing runner's case ID."""
    scene = {
        "version": 3,
        "camera": {"eye": "0 0 6", "center": "0 0 0", "up": "0 1 0"},
        "general": {"orthogonalprojection": None, "fov": 60, "nearz": .1,
                    "farz": 100, "zoom": 1, "clearcolor": "0 0 0",
                    "clearenabled": True, "hdr": False, "bloom": False,
                    "ambientcolor": "0 0 0", "skylightcolor": "0 0 0",
                    "cameraparallax": False, "camerashake": False},
        "objects": [
            {"id": 1, "model": "models/main_prefix.mdl", "origin": "0 0 0",
             "perspective": True, "castshadow": False},
            {"id": 2, "model": "models/orange_writer.mdl", "origin": "0 0 0",
             "perspective": True, "castshadow": False},
            {"id": 10, "name": "ordinary authored transform parent",
             "origin": " ".join(map(str, PARENT_ORIGIN)),
             "scale": " ".join(map(str, PARENT_SCALE)),
             "angles": " ".join(map(str, PARENT_ANGLES))},
            {"id": TARGET_LAYER, "name": "owned framebuffer Program plane",
             "parent": 10, "image": "models/local_plane.json",
             "size": "128 96", "origin": "0 0 0",
             "scale": f"{PLANE_SIZE[0] / 128} {PLANE_SIZE[1] / 96} 1",
             "perspective": True, "visible": True,
             "effects": [{"id": 200, "file": "effects/invert/effect.json", "visible": True}]},
            # Behind the utility, before the background in depth, and authored
            # after it: green survives only if the utility did not write depth.
            {"id": 30, "model": "models/later_peer.mdl", "origin": "0 0 0",
             "perspective": True, "castshadow": False},
        ],
    }
    source = {"passes": [{
        "shader": "owned_main_plane", "textures": ["_rt_FullFrameBuffer"],
        "constantshadervalues": {"localsize": " ".join(map(str, LOCAL_SIZE))},
        "blending": "translucent", "depthtest": "enabled",
        "depthwrite": "disabled", "cullmode": "nocull"}]}
    effect = {"passes": [{"shader": "owned_inverse", "textures": [None],
                           "blending": "normal", "depthtest": "disabled",
                           "depthwrite": "disabled", "cullmode": "nocull"}]}
    return {
        "scene.json": encoded(scene),
        "models/main_prefix.mdl": mdl_quad(-9, 9, -6, 6, -2, "materials/grid.json"),
        "models/orange_writer.mdl": mdl_quad(-.65, .15, -1.2, 1.2, 1, "materials/orange.json"),
        "models/later_peer.mdl": mdl_quad(.67, .97, -.65, -.35, -1.2, "materials/green.json"),
        "models/local_plane.json": encoded({"material": "materials/receiver.json", "passthrough": True}),
        "materials/receiver.json": encoded(source),
        "materials/grid.json": model_material("materials/grid.png"),
        "materials/orange.json": model_material("materials/orange.png"),
        "materials/green.json": model_material("materials/green.png"),
        "materials/grid.png": png(*GRID_SIZE, grid_color),
        "materials/orange.png": png(4, 4, lambda _x, _y: ORANGE),
        "materials/green.png": png(4, 4, lambda _x, _y: GREEN),
        "shaders/owned_main_plane.vert": SOURCE_VERTEX,
        "shaders/owned_main_plane.frag": SOURCE_FRAGMENT,
        "effects/invert/effect.json": encoded({"passes": [{"material": "materials/inverse.json"}]}),
        "materials/inverse.json": encoded(effect),
        "shaders/owned_inverse.vert": EFFECT_VERTEX,
        "shaders/owned_inverse.frag": EFFECT_FRAGMENT,
    }


def plane_world(local):
    """Independent double Rz*Ry*Rx, scale then translation, before any App run."""
    x = local[0] * PLANE_SIZE[0] * PARENT_SCALE[0]
    y = local[1] * PLANE_SIZE[1] * PARENT_SCALE[1]
    z = 0.
    ax, ay, az = PARENT_ANGLES
    y, z = math.cos(ax) * y - math.sin(ax) * z, math.sin(ax) * y + math.cos(ax) * z
    x, z = math.cos(ay) * x + math.sin(ay) * z, -math.sin(ay) * x + math.cos(ay) * z
    x, y = math.cos(az) * x - math.sin(az) * y, math.sin(az) * x + math.cos(az) * y
    return tuple(v + t for v, t in zip((x, y, z), PARENT_ORIGIN, strict=True))


def screen(point, width, height):
    focal = height / (2 * math.tan(FOV / 2))
    return (width / 2 + focal * point[0] / (EYE_Z - point[2]),
            height / 2 - focal * point[1] / (EYE_Z - point[2]))


def background_at_plane(point):
    ratio = (EYE_Z - BACKGROUND_Z) / (EYE_Z - point[2])
    x, y = point[0] * ratio, point[1] * ratio
    tx = (x - BACKGROUND_BOUNDS[0]) / 18 * GRID_SIZE[0]
    ty = (BACKGROUND_BOUNDS[3] - y) / 12 * GRID_SIZE[1]
    return {"world": [x, y, BACKGROUND_Z], "texel": [tx, ty],
            "RGB": grid_color(int(tx), int(ty))}


def affine_countermodel(local):
    corners = [plane_world(p) for p in [(-.5, .5), (.5, .5), (-.5, -.5)]]
    ratios = [(p[0] / (EYE_Z - p[2]), p[1] / (EYE_Z - p[2])) for p in corners]
    affine = [ratios[0][i] + (local[0] + .5) * (ratios[1][i] - ratios[0][i])
              + (.5 - local[1]) * (ratios[2][i] - ratios[0][i]) for i in range(2)]
    x, y = affine[0] * 8, affine[1] * 8
    tx, ty = (x + 9) / 18 * GRID_SIZE[0], (6 - y) / 12 * GRID_SIZE[1]
    return {"texel": [tx, ty], "RGB": grid_color(int(tx), int(ty))}


def roi_protocol():
    regions = {}
    # Chosen from independent geometry before any GPU capture: exact samples
    # lie inside constant-color cells; a three-corner affine pullback hits a
    # grid line instead. No oracle value is fitted to an observed App output.
    for label, local in {"uncoveredA": (.22, -.11), "uncoveredB": (.40, -.11),
                         "occluded": (-.32, .15)}.items():
        world = plane_world(local)
        background = background_at_plane(world)
        expected = ORANGE if label == "occluded" else tuple(255 - c for c in background["RGB"])
        regions[label] = {"local": local, "world": world, "background": background,
                          "affineCountermodel": affine_countermodel(local), "expectedRGB": expected}
    regions["laterFarPeer"] = {"world": [.82, -.5, -1.2], "expectedRGB": GREEN}
    regions["prefixOutsidePlane"] = {"world": [-2., 1.4, -2.],
                                     "expectedRGB": background_at_plane((-1.5, 1.05, 0.))["RGB"]}
    return {"regions": regions, "radiusPixels": 2, "tolerance": TOLERANCE,
            "screenMapping": "center+(x,-y)*H/(2*tan30)/(6-z); native viewport, no cover or image-fit",
            "boundary": "Own geometry and piecewise grid values; no corpus/official screen ROI inferred."}


def measure_capture(path: Path) -> dict:
    decoded = png_rgb_pixels(path)
    if decoded is None:
        raise AssertionError(f"undecodable capture: {path}")
    width, height, rows = decoded
    measurements = {"size": [width, height]}
    for label, region in roi_protocol()["regions"].items():
        px, py = screen(region["world"], width, height)
        x0, y0, x1, y1 = math.ceil(px - 2), math.ceil(py - 2), math.floor(px + 2), math.floor(py + 2)
        if not (0 <= x0 < x1 <= width and 0 <= y0 < y1 <= height):
            raise AssertionError(f"preregistered {label} ROI cropped: {(x0,y0,x1,y1)}")
        values = [rows[y][x * 3:x * 3 + 3] for y in range(y0, y1) for x in range(x0, x1)]
        measurements[label] = {"bounds": [x0, y0, x1, y1], "count": len(values),
            "mean": [sum(v[c] for v in values) / len(values) for c in range(3)],
            "minimum": [min(v[c] for v in values) for c in range(3)],
            "maximum": [max(v[c] for v in values) for c in range(3)]}
    return measurements


class SceneNativeWorldCompositionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        configured = os.environ.get("MWX_SCENE_INTEGRATION_APP")
        if not configured:
            raise unittest.SkipTest("requires an explicitly frozen Debug App executable")
        cls.app = Path(configured).resolve(strict=True)
        binaries = [cls.app, cls.app.with_name("MyWallpaperX.debug.dylib"),
                    cls.app.parent.parent / "Resources/default.metallib"]
        cls.app_identity = {str(p): app_runner.sha256(p) for p in binaries if p.is_file()}
        parent = os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE")
        if parent:
            Path(parent).mkdir(parents=True, exist_ok=True)
        cls.evidence_root = Path(tempfile.mkdtemp(prefix="native-world-source-", dir=parent))
        sources = [Path(__file__), Path(app_runner.__file__),
                   REPO / "script/tests/test_scene_static_model_reader.py",
                   REPO / "script/tests/test_scene_pkg_cache_extractor.py",
                   REPO / "script/web_benchmark_capture.py"]
        cls.source_identity = {str(p): app_runner.sha256(p) for p in sources}
        entries = fixture_entries()
        protocol = {"app": cls.app_identity, "sources": cls.source_identity,
                    "entries": {k: hashlib.sha256(v).hexdigest() for k, v in entries.items()},
                    "oracle": roi_protocol(), "realProductChain": "parser→typed role/source Program→ordered graph base/effect→same-frame depth→unique compositor",
                    "reusedCounterexamples": "Existing affine/source-color, read-only no-writer and cancel/resize/pending owners remain separate nearest gates."}
        (cls.evidence_root / "protocol.json").write_bytes(encoded(protocol))
        print(f"N03 native-world source App evidence: {cls.evidence_root}", flush=True)

    def test_authored_source_program_effect_and_terminal_readonly_depth(self):
        # The existing runner dispatches one real App and asserts immutable
        # inputs, actual Metal completion, no GPU error, normal stop and drain.
        with patch.object(app_runner, "fixture_entries", fixture_entries), patch.object(
                app_runner, "measure_capture", measure_capture):
            result = app_runner.SceneReflectionHistoryIntegrationTests.run_case(self, 0, capture=True)
        work = self.evidence_root / "Ref0-capture-on"
        identity = json.loads((work / "identity.json").read_text())
        inputs_after = {"package": app_runner.sha256(work / "content/scene.pkg"),
                        "project": app_runner.sha256(work / "content/project.json")}
        self.assertEqual(inputs_after["package"], identity["package"], inputs_after)
        self.assertEqual(inputs_after["project"], identity["project"], inputs_after)
        regions = roi_protocol()["regions"]
        for phase in ["scene-ready-window.png", "scene-after-window.png"]:
            for label, region in regions.items():
                measurement = result["pixels"][phase][label]
                self.assertGreater(measurement["count"], 0, (phase, label))
                for actual, expected in zip(measurement["mean"], region["expectedRGB"], strict=True):
                    self.assertAlmostEqual(actual, expected, delta=TOLERANCE,
                                           msg=str((phase, label, measurement, region)))
        log = (work / "app.log").read_text()
        completed = re_graph_frames(log)
        self.assertGreaterEqual(len(completed), 2, completed)
        self.assertNotRegex(log, r"entries=[^\n]*20:layer-source-not-ready")
        (work / "native-world-checks.json").write_bytes(encoded({
            "inputAfter": inputs_after, "inputImmutable": True,
            "completedTargetGraphFrames": sorted(completed),
            "targetGraphSourceExtent": list(LOCAL_SIZE),
            "oracle": roi_protocol(), "pixels": result["pixels"],
            "scope": "One full product-chain scene; two settled captures and completed graph frames, not adjacent-frame pixel pairing or official parity."}))


def re_graph_frames(log: str) -> set[int]:
    import re
    frames = set()
    for line in log.splitlines():
        if "axis=graph-execution runtime=" not in line:
            continue
        fields = dict(re.findall(r"(\w+)=([^ ]+)", line))
        if (fields.get("layer") == str(TARGET_LAYER)
                and int(fields.get("materialNodes", "0")) > 0
                and fields.get("rejectedNodes") == "0"
                and fields.get("inputWidth") == str(LOCAL_SIZE[0])
                and fields.get("inputHeight") == str(LOCAL_SIZE[1])
                and fields.get("compositorConsumed") == "true"
                and fields.get("outcome") == "succeeded"
                and fields.get("gpuCompletion") == "completed"):
            frames.add(int(fields["frame"]))
    return frames


if __name__ == "__main__":
    unittest.main()
