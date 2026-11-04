"""Self-authored TEX -> image/effect -> named output App integration.

The oracle is fixed in canvas coordinates before launch. Source capture performs
host image mapping once; authored sampling of that capture keeps its own UV.
Companion cases explicitly map a separately bound authored atlas once.
"""
from pathlib import Path
import copy
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
import zlib

from script.web_benchmark_capture import png_rgb_pixels
from script.scene_wallpaper_graph_output_metrics import (
    structured_runtime_observations, terminal_composition_snapshot,
)
from .scene_pkg_fixture import make_package
from .fixtures.scene_timeline_combined_cases import linked_effect_constants

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


def texture(axis, colors=COLORS):
    """One uncompressed RGBA mip; one positive-axis TEXS frame or padding."""
    width, height = 64, 32
    ox, oy = (16, 8) if axis else (0, 0)
    payload = bytearray()
    for y in range(height):
        for x in range(width):
            color = SENTINEL
            if ox <= x < ox + 32 and oy <= y < oy + 16:
                color = colors[int(y >= oy + 8) * 2 + int(x >= ox + 16)]
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


SECOND_COLORS = ((0, 255, 255), (255, 0, 255), (255, 255, 0), (0, 0, 255))
ORIGINAL_ATLAS_PACKAGE_SHA256 = "3c2a32970436923433f6c7ad82735811b882067f6214df453c46cff8e92dc4f2"
ORIGINAL_PROJECT_SHA256 = "2a5e61fb3064dc35c646e3dce93f13967496219ea96ddad8a73545d1b6207f60"


def changing_atlas(permute=False):
    # Two disjoint, equal positive-axis frames; frame one lasts 2 seconds,
    # frame two lasts an hour. Ready is requested at 1 second, after at 3.
    # Expected colors are fixed by request class before either image is read.
    width, height = 128, 32
    payload = bytearray()
    for y in range(height):
        for x in range(width):
            color = SENTINEL
            for origin, palette in ((16, COLORS), (80, SECOND_COLORS)):
                if origin <= x < origin + 32 and 8 <= y < 24:
                    color = palette[int(y >= 16) * 2 + int(x >= origin + 16)]
                    if permute:
                        color = (color[1], color[2], color[0])
            payload.extend((*color, 255))
    result = (b"TEXV0005\0TEXI0001\0" + struct.pack("<7I", 0, 4, width, height, width, height, 0)
              + b"TEXB0002\0" + struct.pack("<2I", 1, 1)
              + struct.pack("<5I", width, height, 0, len(payload), len(payload)) + payload
              + b"TEXS0002\0" + struct.pack("<I", 2))
    for origin, duration in ((16, 2.0), (80, 3600.0)):
        result += struct.pack("<if6f", 0, duration, origin, 8, 32, 0, 0, 16)
    return bytes(result)


def solid_texture(rgb):
    pixels = bytes((*rgb, 255)) * 256
    return (b"TEXV0005\0TEXI0001\0" + struct.pack("<7I", 0, 0, 16, 16, 16, 16, 0)
            + b"TEXB0002\0" + struct.pack("<2I", 1, 1)
            + struct.pack("<5I", 16, 16, 0, len(pixels), len(pixels)) + pixels)


def data_layout_fixture(case):
    renamed, broken = case == "data-layout-renamed", case == "data-layout-bad-mask"
    prefix, word, shift = ("unseen_density", "amount", 1000) if renamed else ("own_channel_data", "density", 0)
    palettes = {str(51 + shift): ((120, 90, 240),) * 4 if broken else
                ((0, 0, 0), (40, 30, 80), (80, 60, 160), (120, 90, 240)),
                str(52 + shift): ((0, 0, 0), (40, 30, 80), (80, 60, 160), (120, 90, 240)),
                str(53 + shift): ((0, 255, 0),) * 4}
    def mask_png(alpha):
        raw = bytearray()
        for y in range(16):
            raw.append(0)
            for x in range(16):
                q = int(y >= 8) * 2 + int(x >= 8)
                raw.append((0, 85, 170, 255)[q])
                if alpha:
                    raw.append((255, 0, 64, 255)[q])
        def chunk(kind, data):
            return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
        return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 16, 16, 8, 4 if alpha else 0, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
    entries, objects, panels = {}, [], []
    for index, (name, x, y) in enumerate((("gray", 64, 64), ("gray-alpha", 192, 64), ("peer", 128, 144))):
        layer, path = 51 + shift + index, f"{prefix}/{name}"
        model, material, source = f"models/{path}.json", f"materials/{path}.json", f"materials/{path}.tex"
        entries[model] = encoded({"material": material})
        entries[material] = encoded({"passes": [{"shader": "genericimage", "textures": [source]}]})
        entries[source] = solid_texture((0, 255, 0) if name == "peer" else (120, 180, 240))
        obj = {"id": layer, "name": path, "image": model, "origin": f"{x} {CANVAS[1] - y} 0",
               "size": "64 32", "visible": True}
        if name != "peer":
            mask = f"materials/{path}-values.png"
            entries[mask] = b"owned invalid PNG" if broken and index == 0 else mask_png(index == 1)
            effects = []
            for stage_index, stage in enumerate(("scalar", "suffix")):
                shader = f"{path}-{stage}"
                slots = [None, None, mask] if stage == "scalar" else [None]
                entries[f"effects/{shader}/effect.json"] = encoded({"passes": [{"material": f"materials/{shader}.json"}]})
                entries[f"materials/{shader}.json"] = encoded({"passes": [{"shader": shader, "textures": slots,
                    "blending": "normal", "depthtest": "disabled", "depthwrite": "disabled", "cullmode": "nocull"}]})
                entries[f"shaders/{shader}.vert"] = VERTEX
                body = (f"float {word}=texSample2D(g_Texture2,v_TexCoord).r;gl_FragColor=vec4(c.rgb,c.a*{word});"
                        if stage == "scalar" else "gl_FragColor=vec4(c.r,c.g*0.5,c.b,c.a);")
                declaration = 'uniform sampler2D g_Texture2; // {"mode":"opacitymask"}\n' if stage == "scalar" else ""
                entries[f"shaders/{shader}.frag"] = ("uniform sampler2D g_Texture0;\n" + declaration
                    + "varying vec2 v_TexCoord;\nvoid main(){vec4 c=texSample2D(g_Texture0,v_TexCoord);" + body + "}\n").encode()
                effects.append({"id": layer * 10 + stage_index, "file": f"effects/{shader}/effect.json", "visible": True})
            obj["effects"] = effects
        objects.append(obj)
        panels.append((layer, x, y, False))
    entries["scene.json"] = encoded({"version": 3, "general": {
        "orthogonalprojection": {"width": CANVAS[0], "height": CANVAS[1]}, "clearcolor": "0 0 0"}, "objects": objects})
    return {"type": "scene", "file": "scene.json"}, entries, panels, palettes


def timeline_layout_fixture(case):
    renamed = case == "timeline-layout-renamed"
    prefix, keys, shift = ("unseen_clock", ("drive", "turn"), 1000) if renamed else (
        "own_linked", ("master", "follower"), 0)
    root, child = linked_effect_constants(root_key=keys[0], child_key=keys[1], fps=10,
        length=200, startpaused=False, root_lane=[{"frame": 0, "value": .2}, {"frame": 200, "value": .8}],
        child_lane=[{"frame": 0, "value": .9}, {"frame": 200, "value": .3}])
    entries, objects = {}, []
    for index, x in enumerate((64, 192)):
        layer, path = 61 + shift + index, f"{prefix}/card{index}"
        entries[f"models/{path}.json"] = encoded({"material": f"materials/{path}.json"})
        entries[f"materials/{path}.json"] = encoded({"passes": [{"shader": "genericimage",
            "textures": [f"materials/{path}.tex"]}]})
        entries[f"materials/{path}.tex"] = solid_texture((180, 180, 180) if index == 0 else (0, 255, 0))
        obj = {"id": layer, "image": f"models/{path}.json", "origin": f"{x} 96 0",
               "size": "64 32", "visible": True}
        if index == 0:
            definitions, overrides = [], []
            for ordinal in range(4):
                scalar_key = keys[ordinal % 2]
                shader = f"{prefix}/channel{ordinal}"
                uniform = "u_master" if ordinal % 2 == 0 else "u_follower"
                body = [f"vec4(c.r*{uniform},c.g,c.b,c.a)", f"vec4(c.r,c.g*{uniform},c.b,c.a)",
                        f"vec4(c.r,c.g,c.b*{uniform},c.a)", f"vec4(c.rgb,c.a*{uniform})"][ordinal]
                entries[f"materials/{shader}.json"] = encoded({"passes": [{"shader": shader,
                    "textures": [None], "blending": "normal", "depthtest": "disabled",
                    "depthwrite": "disabled", "cullmode": "nocull"}]})
                entries[f"shaders/{shader}.vert"] = VERTEX
                entries[f"shaders/{shader}.frag"] = ("uniform sampler2D g_Texture0;\n"
                    f'uniform float {uniform}; // {{"material":"{scalar_key}"}}\n'
                    "varying vec2 v_TexCoord;\nvoid main(){vec4 c=texSample2D(g_Texture0,v_TexCoord);"
                    f"gl_FragColor={body};}}\n").encode()
                definition = {"material": f"materials/{shader}.json",
                    "bind": [{"name": "previous" if ordinal == 0 else f"step{ordinal - 1}", "index": 0}]}
                if ordinal < 3:
                    definition["target"] = f"step{ordinal}"
                definitions.append(definition)
                value = copy.deepcopy(root if ordinal % 2 == 0 else child)
                if ordinal % 2 == 0:
                    value["animation"]["options"]["name"] = f"{prefix} clock {ordinal}"
                if case == "timeline-layout-bad-link" and ordinal == 3:
                    value["animation"]["options"]["parent"]["key"] = "unavailable_root"
                overrides.append({"constantshadervalues": {scalar_key: value}})
            entries[f"effects/{prefix}/linked/effect.json"] = encoded({"passes": definitions,
                "fbos": [{"name": f"step{i}", "scale": 1, "format": "rgba_backbuffer"} for i in range(3)]})
            suffix = f"{prefix}/suffix"
            entries[f"effects/{suffix}/effect.json"] = encoded({"passes": [{"material": f"materials/{suffix}.json"}]})
            entries[f"materials/{suffix}.json"] = encoded({"passes": [{"shader": suffix, "textures": [None],
                "blending": "normal", "depthtest": "disabled", "depthwrite": "disabled", "cullmode": "nocull"}]})
            entries[f"shaders/{suffix}.vert"] = VERTEX
            entries[f"shaders/{suffix}.frag"] = (b"uniform sampler2D g_Texture0;\nvarying vec2 v_TexCoord;\n"
                b"void main(){vec4 c=texSample2D(g_Texture0,v_TexCoord);gl_FragColor=vec4(c.r,c.g*0.5,c.b,c.a);}\n")
            obj["effects"] = [{"id": layer * 10, "file": f"effects/{prefix}/linked/effect.json", "passes": overrides},
                              {"id": layer * 10 + 1, "file": f"effects/{suffix}/effect.json"}]
        objects.append(obj)
    entries["scene.json"] = encoded({"version": 3, "general": {"orthogonalprojection": {
        "width": CANVAS[0], "height": CANVAS[1]}, "clearcolor": "0 0 0"}, "objects": objects})
    return {"type": "scene", "file": "scene.json"}, entries, [(61 + shift, 64, 96, False), (62 + shift, 192, 96, False)]


def case_fixture(case):
    if case.startswith("timeline-layout"):
        return timeline_layout_fixture(case)
    if case.startswith("data-layout"):
        return data_layout_fixture(case)[:3]
    project, entries = fixture_entries()
    panels = list(PANELS)
    if case == "padding":
        return project, entries, panels
    entries = {name: data.replace(b"_rt_imageLayerComposite_22_a", b"_rt_imageLayerComposite_12_a")
               if name.endswith(".json") else data for name, data in entries.items()}
    scene = json.loads(entries["scene.json"])
    scene["objects"][-1]["dependencies"] = [12]
    entries["scene.json"] = encoded(scene)
    # This exact old failing input is the atlas positive control, not a
    # regenerated lookalike or the later padding substitution.
    assert hashlib.sha256(make_package(list(entries.items()))).hexdigest() == ORIGINAL_ATLAS_PACKAGE_SHA256
    assert hashlib.sha256(encoded(project)).hexdigest() == ORIGINAL_PROJECT_SHA256
    if case == "raw-miss":
        del scene["objects"][1]["effects"]
        panels = [(layer, x, y, effect and layer not in (12, 31)) for layer, x, y, effect in panels]
    elif case == "two-consumers":
        scene["objects"][-1]["origin"] = "80 40 0"
        second = json.loads(json.dumps(scene["objects"][-1]))
        second.update(id=32, name="Second named output consumer", origin="176 40 0")
        second["effects"][0]["id"] = 320
        second["effects"][0]["passes"][0]["id"] = 321
        scene["objects"].append(second)
        panels[-1] = (31, 80, 152, True)
        panels.append((32, 176, 152, True))
    elif case in ("companion", "companion-vertex", "companion-frame") or case.startswith("invalid-companion-"):
        # The independent slot1 asset reaches the real asset publication owner;
        # slot0's already captured image must not supply these uniforms.
        entries["materials/companion.tex"] = texture(True, tuple((g, b, r) for r, g, b in COLORS))
        scene["objects"][1]["effects"][0]["file"] = "effects/own_companion/effect.json"
        scene["objects"][1]["effects"][0]["passes"][0]["textures"] = [None, "materials/companion.tex"]
        entries["effects/own_companion/effect.json"] = encoded({
            "passes": [{"material": "materials/own_companion.json"}]})
        entries["materials/own_companion.json"] = encoded({"passes": [{
            "shader": "own_companion", "textures": [None, "materials/companion.tex"],
            "blending": "normal", "depthtest": "disabled", "depthwrite": "disabled",
            "cullmode": "nocull"}]})
        declarations = (b"uniform vec4 g_Texture1Rotation;\n"
                        b"uniform vec2 g_Texture1Translation;\n")
        expression = (b"g_Texture1Translation + g_Texture1Rotation.xy * v_TexCoord.x"
                      b" + g_Texture1Rotation.zw * v_TexCoord.y")
        entries["shaders/own_companion.vert"] = VERTEX
        fragment = (b'uniform sampler2D g_Texture1; // {"material":"albedo"}\n'
                    b"varying vec2 v_TexCoord;\n"
                    + declarations + b"void main(){vec4 c=texSample2D(g_Texture1,"
                    + expression + b");gl_FragColor=vec4(c.rgb*c.a,c.a);}\n")
        if case == "companion-vertex":
            entries["shaders/own_companion.vert"] = declarations + VERTEX.replace(
                b"v_TexCoord=a_TexCoord;", b"v_TexCoord="
                + expression.replace(b"v_TexCoord", b"a_TexCoord") + b";")
            fragment = fragment.replace(declarations, b"").replace(expression, b"v_TexCoord")
        if case.startswith("invalid-companion-"):
            kind = case.removeprefix("invalid-companion-")
            declarations = {
                "type": b'uniform vec3 g_Texture1Rotation; // {"default":"0 0 0"}\n',
                "array": b'uniform vec4 g_Texture1Rotation[1]; // {"default":"0 0 0 0"}\n',
                "inactive": b'uniform vec4 g_Texture1Rotation; // {"default":"0 0 0 0"}\n',
            }
            slot = 0 if kind == "inactive" else 1
            name = b"g_Texture1Rotation[0]" if kind == "array" else b"g_Texture1Rotation"
            fragment = (f'uniform sampler2D g_Texture{slot}; // {{"material":"albedo"}}\n'.encode()
                        + b"varying vec2 v_TexCoord;\n" + declarations[kind]
                        + f"void main(){{vec4 c=texSample2D(g_Texture{slot},v_TexCoord+".encode()
                        + name + b".xy);gl_FragColor=vec4(c.rgb*c.a,c.a);}\n")
            panels = [(layer, x, y, effect and layer not in (12, 31))
                      for layer, x, y, effect in panels]
        entries["shaders/own_companion.frag"] = fragment
        if case == "companion-frame":
            entries["materials/axis.tex"] = changing_atlas()
            entries["materials/companion.tex"] = changing_atlas(permute=True)
    elif case == "new-frame":
        entries["materials/axis.tex"] = changing_atlas()
    elif case not in ("atlas", "resize"):
        raise ValueError(case)
    entries["scene.json"] = encoded(scene)
    return project, entries, panels


def preregistration(case="padding"):
    project, entries, panels = case_fixture(case)
    hashes = {name: hashlib.sha256(data).hexdigest() for name, data in entries.items()}
    hashes["project.json"] = hashlib.sha256(encoded(project)).hexdigest()
    hashes["scene.pkg"] = hashlib.sha256(make_package(list(entries.items()))).hexdigest()
    protocol = {"case": case, "inputSHA256": hashes, "canvas": CANVAS, "panelSize": [64, 32],
            "panels": [{"id": layer, "center": [x, y],
                        "quadrantRGB": [list((c[1], c[2], c[0]) if effect else c) for c in COLORS]}
                       for layer, x, y, effect in panels],
            "newFramePalette": SECOND_COLORS if case in ("new-frame", "companion-frame") else None,
            "oracle": {"interiorInsetCanvas": 3, "minimumCorrectAreaFraction": .99,
                       "channelTolerance": 3, "outsideBoundaryOffsetCanvas": 2,
                       "outsideRGB": [0, 0, 0], "sentinelRGB": SENTINEL},
            "timingLimit": "ready/after PNG plus completed later frames; no strict adjacent-frame pixel binding"}
    if case.startswith("data-layout"):
        protocol["paletteByLayer"] = data_layout_fixture(case)[3]
        protocol["maskSource"] = {"PNGColorTypes": [0, 4], "gray": [0, 85, 170, 255],
                                  "GAAlpha": [255, 0, 64, 255], "purpose": "mask", "read": "r only"}
        for panel in protocol["panels"]:
            panel["quadrantRGB"] = protocol["paletteByLayer"][str(panel["id"])]
    if case.startswith("timeline-layout"):
        protocol["timeline"] = {"root": ".2+.03*sceneTime", "child": ".9-.03*sceneTime",
            "pixelRGB": "[180*root*child,90*child*child,180*root*child]",
            "sceneTimeWindow": [0, 6], "maximumClockBracketSeconds": .4,
            "passNodeIndices": [0, 1, 2, 3],
            "identity": "same stream/frame/generation; four full pass targets; no image-derived fitting",
            "badLinkRGB": [180, 90, 180], "peerRGB": [0, 255, 0]}
    return protocol


def measure_capture(path, panel_specs=PANELS, second_frame=False, palettes=None):
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
    for layer, cx, cy, effect in panel_specs:
        quadrants = []
        palette = palettes[str(layer)] if palettes is not None else (
            SECOND_COLORS if second_frame and layer in (11, 12, 31) else COLORS)
        for q, color in enumerate(palette):
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

    def capture_event(self, capture, log, observations):
        reason = "ready" if "ready" in capture.name else "after"
        request = re.search(rf"phase=snapshot reason={reason} request=(\d+) source=metal path={re.escape(str(capture))}", log)
        self.assertIsNotNone(request)
        receipt = re.search(rf"phase=snapshot-encoded request={request[1]} commandBufferToken=(\d+) textureToken=(\d+) width=(\d+) height=(\d+)", log)
        self.assertIsNotNone(receipt)
        matched = terminal_composition_snapshot({"status": "captured", "request_id": int(request[1]),
            "command_buffer_token": receipt[1], "texture_token": receipt[2],
            "source_width": int(receipt[3]), "source_height": int(receipt[4])}, observations)
        self.assertTrue(matched["composition_receipt_matched"], matched)
        event = next(e for e in observations["events"] if e["captureRequestID"] == int(request[1])
                     and e["commandBufferToken"] == receipt[1])
        self.assertEqual(event["truncatedRows"], 0)
        return event

    def timeline_palette(self, case, log, event):
        layer = 1061 if case == "timeline-layout-renamed" else 61
        prefix = "MWX DEBUG SCENE: phase=timeline-frame-input json="
        records = [json.loads(line.split(prefix, 1)[1]) for line in log.splitlines() if prefix in line]
        frames = [r for r in records if r["kind"] == "frame" and r["stream"] == event["displayID"]]
        self.assertTrue(frames, "requested clock observations must reach the App")
        self.assertTrue(all(r["observationComplete"] and r["frame"] == r["snapshotFrame"] for r in frames))
        frame = event["frameIndex"]
        lower = max((r for r in frames if r["frame"] <= frame), key=lambda r: r["frame"])
        upper = min((r for r in frames if r["frame"] >= frame), key=lambda r: r["frame"])
        self.assertLessEqual(upper["sceneTime"] - lower["sceneTime"], .4)
        values, generations = {}, set()
        for line in log.splitlines():
            if "MWX typed input consumption: channel=timeline consumer=material-uniform " not in line:
                continue
            fields = dict(re.findall(r"(\w+)=([^\s]+)", line))
            if (fields.get("layer"), fields.get("effect"), fields.get("frame"), fields.get("stage")) != (
                    str(layer), "0", str(frame), "fragment"):
                continue
            index = int(fields["pass"])
            expected = (("drive", "turn") if case == "timeline-layout-renamed" else ("master", "follower"))[index % 2]
            self.assertEqual(fields["constant"], expected)
            self.assertEqual(fields["uniform"], "u_master" if index % 2 == 0 else "u_follower")
            scalar = re.fullmatch(r"scalar\(([^)]+)\)", fields["value"])
            self.assertIsNotNone(scalar)
            value = float(scalar[1])
            if index in values:
                self.assertEqual(values[index], value)
            values[index] = value
            generations.add(int(fields["generation"]))
        broken = case == "timeline-layout-bad-link"
        if broken:
            self.assertEqual(values, {})
            color = (180, 90, 180)
        else:
            self.assertEqual(set(values), {0, 1, 2, 3})
            self.assertEqual(len(generations), 1)
            generation = next(iter(generations))
            self.assertLessEqual(lower["generation"], generation)
            self.assertLessEqual(generation, upper["generation"])
            self.assertEqual(values[0], values[2])
            self.assertEqual(values[1], values[3])
            self.assertAlmostEqual(values[0] + values[1], 1.1, delta=1e-6)
            for index, value in values.items():
                endpoints = [(.2 + .03 * r["sceneTime"] if index % 2 == 0 else .9 - .03 * r["sceneTime"])
                             for r in (lower, upper)]
                self.assertGreaterEqual(value, min(endpoints) - 1e-6)
                self.assertLessEqual(value, max(endpoints) + 1e-6)
            root, child = values[0], values[1]
            color = tuple(round(v) for v in (180 * root * child, 90 * child * child, 180 * root * child))
        rows = [r for r in event["rows"] if r.get("layerID") == layer]
        self.assertTrue(any(r["kind"] == "sourceCapture" and r["outcome"] == "encoded" for r in rows))
        self.assertTrue(any(r["kind"] == "tail-consume" and r["outcome"] == "terminal-consumed" for r in rows))
        material = [r for r in rows if r["kind"] == "material" and r["outcome"] == "draw-encoded"]
        self.assertEqual({r["effectIndex"] for r in material}, {1} if broken else {0, 1})
        if not broken:
            self.assertEqual({r["nodeIndex"] for r in material if r["effectIndex"] == 0}, {0, 1, 2, 3})
        source = next(r for r in rows if r["kind"] == "sourceCapture" and r["outcome"] == "encoded")
        suffix = next(r for r in material if r["effectIndex"] == 1)
        if broken:
            stages = [next(r for r in rows if r["kind"] == "copy" and r["effectIndex"] == 0
                           and r["outcome"] == "encoded")]
        else:
            stages = sorted((r for r in material if r["effectIndex"] == 0), key=lambda r: r["nodeIndex"])
        chain = [source, *stages, suffix]
        for producer, consumer in zip(chain, chain[1:]):
            self.assertEqual(producer["target"]["textureToken"], consumer["source"]["textureToken"])
        tail = next(r for r in rows if r["kind"] == "tail-consume" and r["outcome"] == "terminal-consumed")
        ordinary = next(r for r in rows if r["kind"] == "ordinary" and r["outcome"] == "draw-encoded")
        seal = next(r for r in event["rows"] if r["kind"] == "frame-seal" and r["outcome"] == "sealed")
        self.assertEqual(suffix["target"]["textureToken"], tail["source"]["textureToken"])
        self.assertEqual(tail["source"]["textureToken"], ordinary["source"]["textureToken"])
        self.assertEqual(ordinary["target"]["textureToken"], seal["target"]["textureToken"])
        return {str(layer): (color,) * 4, str(layer + 1): ((0, 255, 0),) * 4}, {
            "frame": frame, "clockBracket": [lower["sceneTime"], upper["sceneTime"]],
            "uniformValues": values, "generations": sorted(generations), "expectedRGB": color}

    def run_case(self, case):
        protocol = preregistration(case)
        with tempfile.TemporaryDirectory(prefix="mwx-authored-sampling-") as temporary:
            root = Path(temporary)
            content, home, evidence = root / "content", root / "home", root / "evidence"
            content.mkdir()
            home.mkdir()
            project, entries, panel_specs = case_fixture(case)
            (content / "project.json").write_bytes(encoded(project))
            (content / "scene.pkg").write_bytes(make_package(list(entries.items())))
            (root / "preregistration.json").write_bytes(encoded(protocol))
            env = os.environ.copy()
            if case.startswith("timeline-layout"):
                for key in tuple(env):
                    if key.startswith(("MWX_SCENE_", "MYWALLPAPERX_SCENE_DEBUG_")):
                        del env[key]
            env.update(HOME=str(home), CFFIXED_USER_HOME=str(home), MWX_SCENE_DEBUG_SURFACE_COUNT="1")
            if case.startswith("timeline-layout"):
                env["MYWALLPAPERX_SCENE_DEBUG_TIMELINE_EVIDENCE"] = json.dumps({
                    "layerIDs": [panel_specs[0][0]], "sceneTimeWindow": [0, 6], "interval": .2, "maxSamples": 32})
            command = [str(self.app), "--mwx-debug-scene-root", str(content),
                       "--mwx-debug-scene-duration", "8" if case == "resize" else "6",
                       "--mwx-debug-scene-evidence-dir", str(evidence)]
            if case == "resize":
                command += ["--mwx-debug-scene-resize-sequence", "2:0.5,3:1"]
            result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=60)
            log = result.stdout + result.stderr
            (root / "app.log").write_text(log)
            (root / "run.json").write_bytes(encoded({"command": command, "returncode": result.returncode,
                "executableSHA256": hashlib.sha256(self.app.read_bytes()).hexdigest()}))
            try:
                preview = "\n".join(p.read_text() for p in evidence.glob("*preview*.log"))
                captures = sorted(evidence.glob("*-window.png"))
                observations = structured_runtime_observations(log, "MWX SCENE COMPOSITION OBSERVATION: ")
                measurements = {}
                for capture in captures:
                    palette = protocol.get("paletteByLayer")
                    if case.startswith("timeline-layout"):
                        palette, timeline = self.timeline_palette(case, log, self.capture_event(capture, log, observations))
                    measurement = measure_capture(capture, panel_specs,
                        second_frame=case in ("new-frame", "companion-frame") and "after" in capture.name,
                        palettes=palette)
                    if case.startswith("timeline-layout"):
                        measurement["timeline"] = timeline
                    measurements[capture.name] = measurement
                (root / "measurements.json").write_bytes(encoded(measurements))
                self.assertEqual(result.returncode, 0, log[-6000:])
                self.assertIn("gpuDrained=true", log)
                self.assertRegex(log, r"state=completed frame=[1-9]\d* surface=\d+ gpu=completed")
                self.assertGreaterEqual(len(captures), 2)
                self.assertTrue(any("ready" in p.name for p in captures))
                self.assertTrue(any("after" in p.name for p in captures))
                effect_layers = (22,) if case == "raw-miss" else (12, 22, 31)
                if case.startswith(("data-layout", "timeline-layout")):
                    effect_layers = ()
                if case.startswith("invalid-companion-"):
                    effect_layers = (22, 31)
                    if case == "invalid-companion-array":
                        self.assertIn("reason=frontend/shaderFrontendFailed", log)
                        self.assertIn("g_Texture1Rotation' has an unsupported array shape", log)
                    else:
                        self.assertIn("reason=uniform/staticUniformBindingInvalid", log)
                        self.assertIn("details=g_Texture1Rotation", log)
                    self.assertNotRegex(log + preview, r"generic shader execution [^\n]*layer=12 effect=0 ")
                if case == "two-consumers":
                    effect_layers += (32,)
                for layer in effect_layers:
                    self.assertRegex(log + preview, rf"generic shader execution [^\n]*layer={layer} effect=0 ")
                provider = 22 if case == "padding" else 12
                if case.startswith("data-layout"):
                    shift = 1000 if case == "data-layout-renamed" else 0
                    self.assertEqual(observations["parse_errors"], 0)
                    self.assertEqual(set(measurements), {"scene-ready-window.png", "scene-after-window.png"})
                    for layer in (51 + shift, 52 + shift):
                        bad = case == "data-layout-bad-mask" and layer == 51
                        for effect in (0, 1):
                            outcome = "failed" if bad and effect == 0 else "encoded-output"
                            self.assertRegex(log, rf"axis=effect-cpu-invocation [^\n]*layer={layer} effect={effect} "
                                rf"[^\n]*backend=resolved-material-graph outcome={outcome} ")
                            if outcome == "encoded-output":
                                self.assertRegex(log + preview, rf"generic shader execution [^\n]*layer={layer} effect={effect} ")
                    for capture in captures:
                        event = self.capture_event(capture, log, observations)
                        for layer in (51 + shift, 52 + shift):
                            rows = [r for r in event["rows"] if r.get("layerID") == layer]
                            self.assertTrue(any(r["kind"] == "sourceCapture" and r["outcome"] == "encoded" for r in rows))
                            self.assertTrue(any(r["kind"] == "tail-consume" and r["outcome"] == "terminal-consumed" for r in rows))
                            masks = [r for r in rows if r["kind"] == "material" and r.get("effectIndex") == 0
                                     and r.get("slot") == 2 and r["outcome"] == "draw-encoded"
                                     and r["access"] == "texture-bind"]
                            self.assertEqual(bool(masks), not (case == "data-layout-bad-mask" and layer == 51))
                            for mask in masks:
                                self.assertEqual((mask["source"]["purpose"], mask["source"]["content"]), ("mask", "data"))
                elif case.startswith("timeline-layout"):
                    self.assertEqual(observations["parse_errors"], 0)
                    self.assertEqual(len(measurements), 2)
                    layer = panel_specs[0][0]
                    for effect in (0, 1):
                        outcome = "failed" if effect == 0 and case == "timeline-layout-bad-link" else "encoded-output"
                        self.assertRegex(log, rf"axis=effect-cpu-invocation [^\n]*layer={layer} effect={effect} "
                                             rf"[^\n]*backend=resolved-material-graph outcome={outcome} ")
                elif case == "raw-miss":
                    self.assertNotIn("phase=named-target-capture layer=12 status=succeeded", log)
                    self.assertNotIn("phase=named-target-binding layer=31 status=succeeded", log)
                    self.assertNotRegex(log, r"phase=(?:visible|named)-graph-output-publication layer=12 status=succeeded")
                else:
                    self.assertRegex(log, rf"phase=(?:visible|named)-graph-output-publication layer={provider} status=succeeded")
                    self.assertIn("phase=named-target-binding layer=31 status=succeeded", log)
                if case == "two-consumers":
                    self.assertIn("phase=named-target-binding layer=32 status=succeeded", log)
                if case == "resize":
                    self.assertIn("phase=surface-resize index=0 scale=0.5000 accepted=true", log)
                    self.assertIn("phase=surface-resize index=1 scale=1.0000 accepted=true", log)
                    ready = measurements["scene-ready-window.png"]["size"]
                    self.assertEqual(measurements["scene-resize-00-window.png"]["size"], [n // 2 for n in ready])
                    self.assertEqual(measurements["scene-resize-01-window.png"]["size"], ready)
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
                    if case.startswith(("data-layout", "timeline-layout")):
                        saved /= case
                    saved.mkdir(parents=True, exist_ok=True)
                    for name in ("content", "evidence"):
                        if (root / name).exists():
                            shutil.copytree(root / name, saved / name, dirs_exist_ok=True)
                    for path in root.glob("*.json"):
                        shutil.copy2(path, saved / path.name)
                    shutil.copy2(root / "app.log", saved / "app.log")

    def test_axis_padding_effect_and_named_consumer(self):
        self.run_case("padding")

    def test_original_atlas_named_package(self):
        self.run_case("atlas")

    def test_raw_atlas_miss_preserves_entry_and_healthy_peers(self):
        self.run_case("raw-miss")

    def test_two_consumers_share_atlas_graph_output(self):
        self.run_case("two-consumers")

    def test_new_atlas_frame_reaches_named_output(self):
        self.run_case("new-frame")

    def test_resize_preserves_atlas_named_output(self):
        self.run_case("resize")

    def test_fragment_companion_maps_bound_asset_once(self):
        self.run_case("companion")

    def test_vertex_companion_maps_bound_asset_once(self):
        self.run_case("companion-vertex")

    def test_companion_tracks_actual_asset_frame_and_named_output(self):
        self.run_case("companion-frame")

    def test_companion_wrong_type_default_cannot_bypass_host_abi(self):
        self.run_case("invalid-companion-type")

    def test_companion_array_default_cannot_bypass_host_abi(self):
        self.run_case("invalid-companion-array")

    def test_companion_without_active_sampler_cannot_use_default(self):
        self.run_case("invalid-companion-inactive")

    def test_gray_and_gray_alpha_data_drive_pixels_and_fail_locally(self):
        for case in ("data-layout", "data-layout-renamed", "data-layout-bad-mask"):
            with self.subTest(case=case):
                self.run_case(case)

    def test_linked_numeric_uniforms_share_clock_and_preserve_local_failure(self):
        for case in ("timeline-layout", "timeline-layout-renamed", "timeline-layout-bad-link"):
            with self.subTest(case=case):
                self.run_case(case)
