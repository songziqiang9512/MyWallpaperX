"""Self-authored TEX -> image/effect -> named output App integration.

The oracle is fixed in canvas coordinates before launch. Source capture performs
host image mapping once; authored sampling of that capture keeps its own UV.
This does not test the separately blocked texture-companion value contract.
"""
from pathlib import Path
import hashlib
import json
import math
import os
import re
import shutil
import struct
import subprocess
import tempfile
import unittest

from script.web_benchmark_capture import png_rgb_pixels
from .test_scene_pkg_cache_extractor import make_package

CANVAS = (256, 192)
COLORS = ((255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 0))
SENTINEL = (32, 96, 160)
PANELS = ((11, 64, 48, False), (12, 192, 48, True),
          (21, 64, 100, False), (22, 192, 100, True),
          (31, 128, 152, True))
VERTEX = (b"attribute vec3 a_Position;\nattribute vec2 a_TexCoord;\n"
          b"varying vec2 v_TexCoord;\n"
          b"void main(){gl_Position=vec4(a_Position,1.0);v_TexCoord=a_TexCoord;}\n")


def encoded(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def texture(axis):
    """One uncompressed RGBA mip; one positive-axis TEXS frame or padding."""
    width, height = 64, 32
    ox, oy = (16, 8) if axis else (0, 0)
    payload = bytearray()
    for y in range(height):
        for x in range(width):
            color = SENTINEL
            if ox <= x < ox + 32 and oy <= y < oy + 16:
                color = COLORS[int(y >= oy + 8) * 2 + int(x >= ox + 16)]
            payload.extend((*color, 255))
    mapped = (width, height) if axis else (32, 16)
    result = (b"TEXV0005\0TEXI0001\0"
              + struct.pack("<7I", 0, 4 if axis else 0, width, height, *mapped, 0)
              + b"TEXB0002\0" + struct.pack("<2I", 1, 1)
              + struct.pack("<5I", width, height, 0, len(payload), len(payload)) + payload)
    if axis:
        result += b"TEXS0002\0" + struct.pack("<Iif6f", 1, 0, 1.0, 16, 8, 32, 0, 0, 16)
    return bytes(result)


def fixture_entries():
    objects = []
    for layer, x, y, effect in PANELS:
        kind = "axis" if layer in (11, 12, 31) else "padding"
        obj = {"id": layer, "name": f"Owned sampling panel {layer}",
               "image": f"models/{kind}.json", "origin": f"{x} {CANVAS[1] - y} 0",
               "size": "64 32", "visible": True, "clampuvs": True, "nointerpolation": True}
        if effect:
            name = "named" if layer == 31 else "permute"
            textures = [None, "_rt_imageLayerComposite_22_a"] if layer == 31 else [None]
            obj["effects"] = [{"id": layer * 10, "file": f"effects/own_{name}/effect.json",
                               "visible": True, "passes": [{"id": layer * 10 + 1, "textures": textures}]}]
        if layer == 31:
            obj["dependencies"] = [22]
        objects.append(obj)
    scene = {"version": 3, "general": {"orthogonalprojection": {"width": CANVAS[0], "height": CANVAS[1]},
                                      "clearcolor": "0 0 0"}, "objects": objects}
    entries = {"scene.json": encoded(scene)}
    for kind in ("axis", "padding"):
        entries[f"models/{kind}.json"] = encoded({"material": f"materials/{kind}.json"})
        entries[f"materials/{kind}.json"] = encoded({"passes": [{"shader": "genericimage", "textures": [f"materials/{kind}.tex"]}]})
        entries[f"materials/{kind}.tex"] = texture(kind == "axis")
    for name in ("permute", "named"):
        entries[f"effects/own_{name}/effect.json"] = encoded({"passes": [{"material": f"materials/own_{name}.json"}]})
        textures = [None, "_rt_imageLayerComposite_22_a"] if name == "named" else [None]
        entries[f"materials/own_{name}.json"] = encoded({"passes": [{"shader": f"own_{name}", "textures": textures,
            "blending": "normal", "depthtest": "disabled", "depthwrite": "disabled", "cullmode": "nocull"}]})
        entries[f"shaders/own_{name}.vert"] = VERTEX
    entries["shaders/own_permute.frag"] = (b"uniform sampler2D g_Texture0;\nvarying vec2 v_TexCoord;\n"
        b"void main(){vec4 c=texSample2D(g_Texture0,v_TexCoord);gl_FragColor=vec4(c.gbr,c.a);}\n")
    entries["shaders/own_named.frag"] = (b"uniform sampler2D g_Texture1;\nvarying vec2 v_TexCoord;\n"
        b"void main(){gl_FragColor=texSample2D(g_Texture1,v_TexCoord);}\n")
    return {"type": "scene", "file": "scene.json"}, entries


def preregistration():
    project, entries = fixture_entries()
    hashes = {name: hashlib.sha256(data).hexdigest() for name, data in entries.items()}
    hashes["project.json"] = hashlib.sha256(encoded(project)).hexdigest()
    hashes["scene.pkg"] = hashlib.sha256(make_package(list(entries.items()))).hexdigest()
    return {"inputSHA256": hashes, "canvas": CANVAS, "panelSize": [64, 32],
            "panels": [{"id": layer, "center": [x, y],
                        "quadrantRGB": [list((c[1], c[2], c[0]) if effect else c) for c in COLORS]}
                       for layer, x, y, effect in PANELS],
            "oracle": {"interiorInsetCanvas": 3, "minimumCorrectAreaFraction": .99,
                       "channelTolerance": 3, "outsideBoundaryOffsetCanvas": 2,
                       "outsideRGB": [0, 0, 0], "sentinelRGB": SENTINEL},
            "timingLimit": "ready/after PNG plus completed later frames; no strict adjacent-frame pixel binding"}


def measure_capture(path):
    width, height, rows = png_rgb_pixels(path)
    scale = max(width / CANVAS[0], height / CANVAS[1])
    def point(x, y):
        return ((x - CANVAS[0] / 2) * scale + width / 2,
                (y - CANVAS[1] / 2) * scale + height / 2)
    def pixel(x, y):
        px, py = point(x, y)
        ix, iy = math.floor(px), math.floor(py)
        if not (0 <= ix < width and 0 <= iy < height):
            raise AssertionError(f"preregistered ROI outside capture: {(x, y, width, height)}")
        return list(rows[iy][ix * 3:ix * 3 + 3])
    panels = []
    for layer, cx, cy, effect in PANELS:
        quadrants = []
        for q, color in enumerate(COLORS):
            expected = (color[1], color[2], color[0]) if effect else color
            left, top = cx - 32 + (q % 2) * 32, cy - 16 + (q // 2) * 16
            x0, y0 = point(left + 3, top + 3)
            x1, y1 = point(left + 29, top + 13)
            if not (0 <= x0 < x1 < width and 0 <= y0 < y1 < height):
                raise AssertionError("preregistered quadrant cropped")
            correct = total = 0
            for y in range(math.ceil(y0), math.floor(y1)):
                for x in range(math.ceil(x0), math.floor(x1)):
                    rgb = rows[y][x * 3:x * 3 + 3]
                    correct += all(abs(a - b) <= 3 for a, b in zip(rgb, expected))
                    total += 1
            quadrants.append({"expected": expected, "center": pixel(left + 16, top + 8),
                              "correct": correct, "total": total})
        outside = [pixel(cx + dx, cy + dy) for dx, dy in ((-34, 0), (34, 0), (0, -18), (0, 18))]
        panels.append({"id": layer, "quadrants": quadrants, "outside": outside})
    return {"size": [width, height], "panels": panels}


class SceneAuthoredSamplingIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        executable = os.environ.get("MWX_SCENE_INTEGRATION_APP")
        if not executable:
            raise unittest.SkipTest("requires explicitly frozen Debug App executable")
        cls.app = Path(executable).resolve(strict=True)

    def test_axis_padding_effect_and_named_consumer(self):
        protocol = preregistration()
        with tempfile.TemporaryDirectory(prefix="mwx-authored-sampling-") as temporary:
            root = Path(temporary)
            content, home, evidence = root / "content", root / "home", root / "evidence"
            content.mkdir()
            home.mkdir()
            project, entries = fixture_entries()
            (content / "project.json").write_bytes(encoded(project))
            (content / "scene.pkg").write_bytes(make_package(list(entries.items())))
            (root / "preregistration.json").write_bytes(encoded(protocol))
            env = os.environ.copy()
            env.update(HOME=str(home), CFFIXED_USER_HOME=str(home), MWX_SCENE_DEBUG_SURFACE_COUNT="1")
            command = [str(self.app), "--mwx-debug-scene-root", str(content),
                       "--mwx-debug-scene-duration", "6", "--mwx-debug-scene-evidence-dir", str(evidence)]
            result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=60)
            log = result.stdout + result.stderr
            (root / "app.log").write_text(log)
            (root / "run.json").write_bytes(encoded({"command": command, "returncode": result.returncode,
                "executableSHA256": hashlib.sha256(self.app.read_bytes()).hexdigest()}))
            try:
                preview = "\n".join(p.read_text() for p in evidence.glob("*preview*.log"))
                captures = sorted(evidence.glob("*-window.png"))
                measurements = {p.name: measure_capture(p) for p in captures}
                (root / "measurements.json").write_bytes(encoded(measurements))
                self.assertEqual(result.returncode, 0, log[-6000:])
                self.assertIn("gpuDrained=true", log)
                self.assertRegex(log, r"state=completed frame=[1-9]\d* surface=\d+ gpu=completed")
                self.assertGreaterEqual(len(captures), 2)
                self.assertTrue(any("ready" in p.name for p in captures))
                self.assertTrue(any("after" in p.name for p in captures))
                for layer in (12, 22, 31):
                    self.assertRegex(log + preview, rf"generic shader execution [^\n]*layer={layer} effect=0 ")
                self.assertRegex(log, r"phase=(?:visible|named)-graph-output-publication layer=22 status=succeeded")
                self.assertIn("phase=named-target-binding layer=31 status=succeeded", log)
                for name, measurement in measurements.items():
                    for panel in measurement["panels"]:
                        for quadrant in panel["quadrants"]:
                            self.assertGreater(quadrant["total"], 0)
                            self.assertGreaterEqual(quadrant["correct"] / quadrant["total"], .99,
                                                    (name, panel["id"], quadrant))
                        for outside in panel["outside"]:
                            self.assertTrue(all(channel <= 3 for channel in outside), (name, panel["id"], outside))
            finally:
                if destination := os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE"):
                    saved = Path(destination) / self._testMethodName
                    saved.mkdir(parents=True, exist_ok=True)
                    for name in ("content", "evidence"):
                        if (root / name).exists():
                            shutil.copytree(root / name, saved / name, dirs_exist_ok=True)
                    for path in root.glob("*.json"):
                        shutil.copy2(path, saved / path.name)
                    shutil.copy2(root / "app.log", saved / "app.log")
