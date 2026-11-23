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
import re
import struct
import tempfile
import unittest
from unittest.mock import patch
import zlib

from script.tests.scene import test_scene_reflection_history_integration as app_runner
from script.tests.scene.test_scene_static_model_reader import build_model
from script.tests.scene.test_scene_static_model_parts import join_parts
from script.web.web_benchmark_capture import png_rgb_pixels
from script.scene.scene_wallpaper_graph_output_metrics import (
    structured_runtime_observations, terminal_composition_snapshot,
)


REPO = Path(__file__).resolve().parents[3]
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
PREFIX_TINT = (205, 45, 235)
TOLERANCE = 4
DEPTH_CARD_IDS = (20, 21, 22)
DEPTH_CARD_COLORS = ((40, 80, 225), (45, 190, 75), (70, 95, 210))
DEPTH_CARD_MATERIAL = "materials/depth_card_20.json"


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


def native_world_scene(objects):
    return {
        "version": 3,
        "camera": {"eye": "0 0 6", "center": "0 0 0", "up": "0 1 0"},
        "general": {"orthogonalprojection": None, "fov": 60, "nearz": .1,
                    "farz": 100, "zoom": 1, "clearcolor": "0 0 0",
                    "clearenabled": True, "hdr": False, "bloom": False,
                    "ambientcolor": "0 0 0", "skylightcolor": "0 0 0",
                    "cameraparallax": False, "camerashake": False},
        "objects": objects,
    }


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
    binding_case = _label
    _label = 2 if _label == 4 else 0 if _label in (3, 5) else _label
    renamed = _label == 2
    plane_model = "models/retitled/surface.json" if renamed else "models/local_plane.json"
    source_material = "materials/retitled/current_view.json" if renamed else "materials/receiver.json"
    source_shader = "retitled/current_view" if renamed else "owned_main_plane"
    effect_path = "effects/retitled/output/effect.json" if renamed else "effects/invert/effect.json"
    effect_material = "materials/retitled/output.json" if renamed else "materials/inverse.json"
    effect_shader = "retitled/output" if renamed else "owned_inverse"
    scene = native_world_scene([
            {"id": 1, "model": "models/main_prefix.mdl", "origin": "0 0 0",
             "perspective": True, "castshadow": False},
            {"id": 2, "model": "models/orange_writer.mdl", "origin": "0 0 0",
             "perspective": True, "castshadow": False},
            {"id": 10, "name": "ordinary authored transform parent",
             "origin": " ".join(map(str, PARENT_ORIGIN)),
             "scale": " ".join(map(str, PARENT_SCALE)),
             "angles": " ".join(map(str, PARENT_ANGLES))},
            {"id": TARGET_LAYER, "name": "owned framebuffer Program plane",
             "parent": 10, "image": plane_model,
             "size": "128 96", "origin": "0 0 0",
             "scale": f"{PLANE_SIZE[0] / 128} {PLANE_SIZE[1] / 96} 1",
             "perspective": True, "visible": True,
             "effects": [{"id": 200, "file": effect_path, "visible": True}]},
            # Behind the utility, before the background in depth, and authored
            # after it: green survives only if the utility did not write depth.
            {"id": 30, "model": "models/later_peer.mdl", "origin": "0 0 0",
             "perspective": True, "castshadow": False},
    ])
    if _label in (1, 2):
        scene["objects"][3]["dependencies"] = [1 if _label == 1 else 30]
    source = {"passes": [{
        "shader": source_shader, "textures": ["_rt_FullFrameBuffer"],
        "constantshadervalues": {"localsize": " ".join(map(str, LOCAL_SIZE))},
        "blending": "translucent", "depthtest": "enabled",
        "depthwrite": "disabled", "cullmode": "nocull"}]}
    effect = {"passes": [{"shader": effect_shader, "textures": [None],
                           "blending": "normal", "depthtest": "disabled",
                           "depthwrite": "disabled", "cullmode": "nocull"}]}
    entries = {
        "scene.json": encoded(scene),
        "models/main_prefix.mdl": mdl_quad(-9, 9, -6, 6, -2, "materials/grid.json"),
        "models/orange_writer.mdl": mdl_quad(-.65, .15, -1.2, 1.2, 1, "materials/orange.json"),
        "models/later_peer.mdl": mdl_quad(.67, .97, -.65, -.35, -1.2, "materials/green.json"),
        plane_model: encoded({"material": source_material, "passthrough": True}),
        source_material: encoded(source),
        "materials/grid.json": model_material("materials/grid.png"),
        "materials/orange.json": model_material("materials/orange.png"),
        "materials/green.json": model_material("materials/green.png"),
        "materials/grid.png": png(*GRID_SIZE, grid_color),
        "materials/orange.png": png(4, 4, lambda _x, _y: ORANGE),
        "materials/green.png": png(4, 4, lambda _x, _y: GREEN),
        f"shaders/{source_shader}.vert": SOURCE_VERTEX,
        f"shaders/{source_shader}.frag": SOURCE_FRAGMENT,
        effect_path: encoded({"passes": [{"material": effect_material}]}),
        effect_material: encoded(effect),
        f"shaders/{effect_shader}.vert": EFFECT_VERTEX,
        f"shaders/{effect_shader}.frag": EFFECT_FRAGMENT,
    }
    if binding_case in (3, 4):
        slot = 3 if binding_case == 3 else 5
        if binding_case == 4:
            for shader in (source_shader, effect_shader):
                for stage in ("vert", "frag"):
                    key = f"shaders/{shader}.{stage}"
                    entries[key] = entries[key].replace(b"v_MainPlane", b"v_ProjectedSample").replace(
                        b"v_TexCoord", b"v_OutputCoord").replace(b"mainUV", b"retitledUV").replace(
                        b"before", b"currentInput")
        for shader, coordinate, local in (
            (source_shader, "mainUV" if slot == 3 else "retitledUV", "unusedSource" if slot == 3 else "forgottenView"),
            (effect_shader, "v_TexCoord" if slot == 3 else "v_OutputCoord", "unusedEffect" if slot == 3 else "forgottenPaint"),
        ):
            key = f"shaders/{shader}.frag"
            body, end = entries[key].rsplit(b"}", 1)
            entries[key] = (f"uniform sampler2D g_Texture{slot};\n".encode() + body
                + f"vec4 {local}=texSample2D(g_Texture{slot},{coordinate});\n}}".encode() + end)
    elif binding_case == 5:
        for ordinal, name, fragment in (
            (1, "owned_live_missing", b'''uniform sampler2D g_Texture3; // {"material":"albedo"}
varying vec2 v_TexCoord;
void main(){gl_FragColor=texSample2D(g_Texture3,v_TexCoord);}
'''),
            (2, "owned_healthy_suffix", b'''uniform sampler2D g_Texture0;
varying vec2 v_TexCoord;
void main(){gl_FragColor=texSample2D(g_Texture0,v_TexCoord);}
'''),
        ):
            path = f"effects/{name}/effect.json"
            scene["objects"][3]["effects"].append({"id": 200 + ordinal, "file": path, "visible": True})
            entries[path] = encoded({"passes": [{"material": f"materials/{name}.json"}]})
            entries[f"materials/{name}.json"] = encoded({"passes": [{"shader": name, "textures": [None],
                "blending": "normal", "depthtest": "disabled", "depthwrite": "disabled", "cullmode": "nocull"}]})
            entries[f"shaders/{name}.vert"] = EFFECT_VERTEX
            entries[f"shaders/{name}.frag"] = fragment
        entries["scene.json"] = encoded(scene)
    return entries


def perspective_image_depth_entries(label):
    objects = [{"id": 2, "model": "models/orange_writer.mdl", "perspective": True, "castshadow": False}]
    entries = {
        "models/orange_writer.mdl": mdl_quad(-1.4, 1.4, -.06, .30, 1, "materials/orange.json"),
        "models/later_peer.mdl": mdl_quad(-1.4, 1.4, -.56, -.25, -1.2, "materials/green.json"),
        "materials/orange.json": model_material("materials/orange.png"),
        "materials/green.json": model_material("materials/green.png"),
        "materials/orange.png": png(4, 4, lambda _x, _y: ORANGE),
        "materials/green.png": png(4, 4, lambda _x, _y: GREEN),
    }
    vertex = EFFECT_VERTEX.replace(
        b"varying vec2 v_TexCoord;",
        b"uniform mat4 g_ModelViewProjectionMatrix;\nvarying vec2 v_TexCoord;",
    ).replace(b"gl_Position = vec4", b"gl_Position = g_ModelViewProjectionMatrix * vec4")
    for layer, x, z, depth_test, depth_write in (
        (22, 1.05, 0, "disabled", "disabled"),
        (20, -1.05, .2, "enabled", "disabled"),
        (21, 0, 0, "enabled", "enabled"),
    ):
        rgb = DEPTH_CARD_COLORS[DEPTH_CARD_IDS.index(layer)]
        model, base, texture = (f"{folder}/depth_card_{layer}.{suffix}" for folder, suffix in
                                (("models", "json"), ("materials", "json"), ("materials", "png")))
        shader = "retitled_depth_paint" if layer == 21 else "owned_depth_paint"
        effect = f"effects/{shader}/effect.json"
        material = f"materials/{shader}.json"
        objects.append({"id": layer, "image": model, "origin": f"{x} 0 {z}", "size": "128 96",
                        "scale": f"{.92 / 128} {1.4 / 96} 1", "perspective": True,
                        "effects": [{"id": 200 + layer, "file": effect, "visible": True}]})
        fragment = b"""uniform sampler2D g_Texture0;
varying vec2 v_TexCoord;
void main() {
    vec4 source = texSample2D(g_Texture0, v_TexCoord);
    gl_FragColor = vec4(source.bgr, source.a);
}
"""
        paint_vertex = vertex
        if layer == 21:
            paint_vertex = vertex.replace(b"v_TexCoord", b"v_PaintUV")
            fragment = fragment.replace(b"v_TexCoord", b"v_PaintUV").replace(
                b"    gl_FragColor = vec4(source.bgr, source.a);",
                b"    float coverage = step(0.20, abs(v_PaintUV.x - 0.5));\n"
                b"    gl_FragColor = vec4(source.b, source.g, source.r, source.a) * coverage;",
            ).replace(b"source", b"priorColor")
        entries.update({
            model: encoded({"material": base}),
            base: encoded({"passes": [{"shader": "genericimage4", "textures": [texture],
                "blending": " TrAnSlUcEnT \t" if layer == 21 else "translucent",
                "depthtest": " EnAbLeD \t" if layer == 21 else depth_test,
                "depthwrite": " ENABLED " if layer == 21 else depth_write,
                "cullmode": " NoCull " if layer == 21 else "nocull"}]}),
            texture: png(4, 4, lambda _x, _y: rgb),
            effect: encoded({"passes": [{"material": material}]}),
            material: encoded({"passes": [{"shader": shader, "textures": [None],
                "blending": "normal", "depthtest": "disabled", "depthwrite": "disabled",
                "cullmode": "nocull"}]}),
            f"shaders/{shader}.vert": paint_vertex,
            f"shaders/{shader}.frag": fragment,
        })
    objects.append({"id": 30, "model": "models/later_peer.mdl", "perspective": True, "castshadow": False})
    scene = native_world_scene(objects)
    scene["general"]["transparentsorting"] = label == 6
    entries["scene.json"] = encoded(scene)
    return entries


def perspective_image_depth_regions(sorting):
    left, center, right = [rgb[::-1] for rgb in DEPTH_CARD_COLORS]
    return {label: {"world": [x, y, 0], "expectedRGB": color} for label, x, y, color in (
        ("read-only-overlap", -1.05, .16, ORANGE),
        ("read-only-exposed", -1.05, -.58, left),
        ("read-only-later-opaque", -1.05, -.35, left if sorting else GREEN),
        ("renamed-overlap", .30, .16, ORANGE),
        ("renamed-exposed", .30, -.58, center),
        ("renamed-over-later-opaque", .30, -.35, center if sorting else GREEN),
        ("renamed-transparent-hole", 0, -.35, GREEN),
        ("disabled-over-earlier-opaque", 1.05, .16, right),
        ("disabled-later-opaque", 1.05, -.35, GREEN),
    )}


MODEL_DEPTH_STATES = (
    ("tested-writer", "enabled", "enabled", (255, 0, 0)),
    ("untested-writer", "disabled", "enabled", (0, 255, 0)),
    ("untested-reader", "disabled", "disabled", (0, 0, 255)),
    ("tested-reader", "enabled", "disabled", (255, 0, 0)),
)
MODEL_DEPTH_ROIS = {name: (32 + 64 * index, 128)
                    for index, (name, _, _, _) in enumerate(MODEL_DEPTH_STATES)}


def model_depth_state_entries(renamed=False):
    folder = "retitled-surfaces" if renamed else "depth-state"
    ids = (1701, 1802, 1903) if renamed else (401, 402, 403)
    stems = ("foreground", "distant", "between") if renamed else ("near", "far", "middle")
    entries, objects = {}, []
    for layer, stem, z, rgb in zip(ids, stems, (10, -10, 0),
                                  ((255, 0, 0), (0, 0, 255), (0, 255, 0)), strict=True):
        texture = f"materials/{folder}/{stem}.png"
        entries[texture] = png(4, 4, lambda _x, _y, color=rgb: color)
        parts = []
        for index, (name, test, write, _) in enumerate(MODEL_DEPTH_STATES):
            material = f"materials/{folder}/{stem}-{name}.json"
            render_pass = json.loads(model_material(texture))["passes"][0]
            if z == -10:
                render_pass.update(depthtest=test, depthwrite=write)
            entries[material] = encoded({"passes": [render_pass]})
            x = 32 + 64 * index
            parts.append(mdl_quad(x - 22, x + 22, 106, 150, z, material))
        model = f"models/{folder}/{stem}.mdl"
        entries[model] = join_parts(parts)
        objects.append({"id": layer, "model": model, "origin": "0 256 0", "scale": "1 -1 1",
                        "perspective": False, "castshadow": False})
    entries["scene.json"] = encoded({"version": 3, "objects": objects, "general": {
        "orthogonalprojection": {"width": 256, "height": 256}, "nearz": .1, "farz": 100,
        "clearenabled": True, "clearcolor": "0 0 0", "hdr": False, "bloom": False,
        "ambientcolor": "0 0 0", "skylightcolor": "0 0 0", "cameraparallax": False,
        "camerashake": False, "transparentsorting": False}})
    return entries


def model_depth_sort_barrier_entries(tested):
    entries, objects = {}, []
    vertex = EFFECT_VERTEX.replace(b"varying vec2 v_TexCoord;",
        b"uniform mat4 g_ModelViewProjectionMatrix;\nvarying vec2 v_TexCoord;").replace(
        b"gl_Position = vec4", b"gl_Position = g_ModelViewProjectionMatrix * vec4")
    for layer, stem, z, color in ((511, "red", .2, (255, 0, 0)),
                                  (512, "blue", 0, (0, 0, 255)), (513, "green", .1, (0, 255, 0))):
        material = f"materials/order-barrier/{stem}.json"
        texture = f"materials/order-barrier/{stem}.png"
        entries[texture] = png(4, 4, lambda _x, _y, rgb=color: rgb)
        if stem == "blue":
            model = "models/order-barrier/occluder.mdl"
            entries[model] = mdl_quad(-1, 1, -.8, .8, 0, material)
            render_pass = json.loads(model_material(texture))["passes"][0]
            render_pass["depthtest"] = "enabled" if tested else "disabled"
            entries[material] = encoded({"passes": [render_pass]})
            objects.append({"id": layer, "model": model, "perspective": True, "castshadow": False})
        else:
            model = f"models/order-barrier/{stem}.json"
            effect = f"effects/order-barrier/{stem}/effect.json"
            effect_material = f"materials/order-barrier/{stem}-effect.json"
            entries[model] = encoded({"material": material})
            entries[material] = encoded({"passes": [{"shader": "genericimage4", "textures": [texture],
                "combos": {"LIGHTING": 0, "REFLECTION": 0, "NORMALMAP": 0}, "blending": "translucent",
                "depthtest": "enabled", "depthwrite": "enabled", "cullmode": "nocull"}]})
            entries[effect] = encoded({"passes": [{"material": effect_material}]})
            entries[effect_material] = encoded({"passes": [{"shader": "owned_barrier_copy", "textures": [None],
                "blending": "normal", "depthtest": "disabled", "depthwrite": "disabled", "cullmode": "nocull"}]})
            objects.append({"id": layer, "image": model, "origin": f"0 0 {z}", "size": "128 96",
                "scale": "0.015625 0.016666666666666666 1", "alpha": .5, "perspective": True,
                "effects": [{"id": layer + 1000, "file": effect, "visible": True}]})
    entries["shaders/owned_barrier_copy.vert"] = vertex
    entries["shaders/owned_barrier_copy.frag"] = b'''uniform sampler2D g_Texture0;
varying vec2 v_TexCoord;
void main() { gl_FragColor = texSample2D(g_Texture0, v_TexCoord); }
'''
    scene = native_world_scene(objects)
    scene["general"]["transparentsorting"] = True
    entries["scene.json"] = encoded(scene)
    return entries


TEXT_DEPTH_CASES = (
    (71, "direct-far", -1.8, -.8, "enabled", None),
    (72, "effect-far", -.6, -.8, "enabled", "owned_ink"),
    (73, "renamed-effect-far", .6, -.8, "enabled", "retitled_coverage"),
    (74, "disabled-far", 1.8, -.8, "disabled", None),
    (81, "direct-near", -1.8, .8, "enabled", None),
    (82, "effect-near", -.6, .8, "enabled", "owned_ink"),
)


def perspective_text_depth_entries(*, named_first=False, renamed=False, sorting=True, prefix=False):
    objects = [{"id": 2, "model": "models/near.mdl", "castshadow": False}]
    entries = {
        "models/near.mdl": mdl_quad(-5, 5, .38, 1.18, 1, "materials/orange.json"),
        "models/far.mdl": mdl_quad(-6, 6, -3, 3, -1.2, "materials/green.json"),
        "materials/orange.json": model_material("materials/orange.png"),
        "materials/green.json": model_material("materials/green.png"),
        "materials/orange.png": png(4, 4, lambda _x, _y: ORANGE),
        "materials/green.png": png(4, 4, lambda _x, _y: GREEN),
    }
    vertex = EFFECT_VERTEX.replace(
        b"varying vec2 v_TexCoord;",
        b"uniform mat4 g_ModelViewProjectionMatrix;\nvarying vec2 v_TexCoord;",
    ).replace(b"gl_Position = vec4", b"gl_Position = g_ModelViewProjectionMatrix * vec4")
    for name, varying, output in (
        ("owned_ink", "v_TexCoord", "vec4(ink.rgb, ink.a * g_GlyphOpacity)"),
        ("retitled_coverage", "v_InkUV", "vec4(ink.r, ink.g, ink.b, g_GlyphOpacity * ink.a)"),
    ):
        material = f"materials/{name}.json"
        entries[f"effects/{name}/effect.json"] = encoded({"passes": [{"material": material}]})
        entries[material] = encoded({"passes": [{"shader": name, "textures": [None],
            "blending": "normal", "depthtest": "disabled", "depthwrite": "disabled",
            "cullmode": "nocull"}]})
        entries[f"shaders/{name}.vert"] = vertex.replace(b"v_TexCoord", varying.encode())
        entries[f"shaders/{name}.frag"] = f'''uniform sampler2D g_Texture0;
uniform float g_GlyphOpacity; // {{"material":"alpha","default":1.0}}
varying vec2 {varying};
void main() {{
    vec4 ink = texSample2D(g_Texture0, {varying});
    gl_FragColor = {output};
}}
'''.encode()
    cases = TEXT_DEPTH_CASES if named_first else (TEXT_DEPTH_CASES[3], *TEXT_DEPTH_CASES[:3], *TEXT_DEPTH_CASES[4:])
    for layer, name, x, y, depth_test, effect in cases:
        obj = {"id": layer, "name": name, "text": "HH", "font": "systemfont_arial",
               "pointsize": 24, "padding": 40, "color": "1 1 1", "origin": f"{x} {y} 0",
               "scale": "0.0055 0.0055 1", "horizontalalign": "center",
               "verticalalign": "center", "depthtest": depth_test, "perspective": True}
        if effect:
            obj["effects"] = [{"id": layer + 200, "file": f"effects/{effect}/effect.json", "visible": True,
                               "passes": [{"id": 0, "constantshadervalues": {"alpha": .5}}]}]
        objects.append(obj)
    objects.append({"id": 30, "model": "models/far.mdl", "castshadow": False})
    scene = native_world_scene(objects)
    scene["general"]["transparentsorting"] = sorting
    if named_first:
        provider = 901 if renamed else 11
        stem = "retitled_depth_feed" if renamed else "depth_feed"
        model, material, texture = (f"{folder}/{stem}.{suffix}" for folder, suffix in
                                    (("models", "json"), ("materials", "json"), ("materials", "png")))
        scene["objects"][0]["dependencies"] = [provider]
        named = json.loads(entries["materials/orange.json"])
        named["passes"][0]["textures"] = [f"_rt_imageLayerComposite_{provider}_a"]
        entries["materials/orange.json"] = encoded(named)
        entries[model] = encoded({"material": material})
        entries[material] = encoded({"passes": [{"shader": "genericimage", "textures": [texture]}]})
        entries[texture] = entries["materials/orange.png"]
        # The first model cannot resolve this hidden source in depth preflight.
        # The real provider schedule must publish it before the model encodes.
        scene["objects"].append({"id": provider, "image": model, "origin": "0 0 0",
                                 "size": "4 4", "visible": False})
    if prefix:
        scene["objects"].insert(3, {"id": TARGET_LAYER, "image": "models/prefix_tint.json",
            "origin": "-1.8 -0.8 0", "size": "128 96", "scale": f"{1 / 128} {.56 / 96} 1",
            "perspective": True, "colorBlendMode": 2})
        entries["models/prefix_tint.json"] = encoded({"material": "materials/prefix_tint.json"})
        entries["materials/prefix_tint.json"] = encoded({"passes": [{"shader": "genericimage",
            "textures": ["materials/prefix_tint.png"]}]})
        entries["materials/prefix_tint.png"] = png(4, 4, lambda _x, _y: PREFIX_TINT)
    entries["scene.json"] = encoded(scene)
    return entries


def measure_perspective_text_depth(path):
    width, height, rows = png_rgb_pixels(path)
    result = {}
    for _, name, x, y, _, _ in TEXT_DEPTH_CASES:
        x0, y0 = screen((x - .49, y + .27, 0), width, height)
        x1, y1 = screen((x + .49, y - .27, 0), width, height)
        pixels = [tuple(rows[row][column * 3:column * 3 + 3])
                  for row in range(math.ceil(y0), math.floor(y1))
                  for column in range(math.ceil(x0), math.floor(x1))]
        result[name] = {"count": len(pixels), "green": pixels.count(GREEN), "orange": pixels.count(ORANGE),
                        "tinted": sum(all(abs(actual - expected) <= TOLERANCE
                                          for actual, expected in zip(pixel, PREFIX_TINT, strict=True)) for pixel in pixels),
                        "white": sum(min(pixel) >= 230 for pixel in pixels),
                        "halfGreen": sum(all(abs(actual - (255 + base) / 2) <= TOLERANCE
                                             for actual, base in zip(pixel, GREEN, strict=True)) for pixel in pixels),
                        "halfGray": sum(104 <= min(pixel) <= max(pixel) <= 152
                                        and max(pixel) - min(pixel) <= 3 for pixel in pixels)}
    return result


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


def measure_capture(path: Path, regions=None) -> dict:
    decoded = png_rgb_pixels(path)
    if decoded is None:
        raise AssertionError(f"undecodable capture: {path}")
    width, height, rows = decoded
    measurements = {"size": [width, height]}
    for label, region in (regions or roi_protocol()["regions"]).items():
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
                   REPO / "script/tests/scene/test_scene_static_model_reader.py",
                   REPO / "script/tests/scene/test_scene_static_model_parts.py",
                   REPO / "script/tests/support/scene_pkg_fixture.py",
                   REPO / "script/web/web_benchmark_capture.py"]
        cls.source_identity = {str(p): app_runner.sha256(p) for p in sources}
        entries = fixture_entries()
        protocol = {"app": cls.app_identity, "sources": cls.source_identity,
                    "entries": {k: hashlib.sha256(v).hexdigest() for k, v in entries.items()},
                    "declaredDependencyControls": {str(label): {
                        "dependencies": [] if label == 0 else [1 if label == 1 else 30],
                        "renamedResources": label == 2,
                        "entries": {k: hashlib.sha256(v).hexdigest()
                                    for k, v in fixture_entries(label).items()}}
                        for label in (0, 1, 2)},
                    "oracle": roi_protocol(), "realProductChain": "parser→typed role/source Program→ordered graph base/effect→same-frame depth→unique compositor",
                    "reusedCounterexamples": "Existing affine/source-color, read-only no-writer and cancel/resize/pending owners remain separate nearest gates."}
        protocol["materialTextureBindingControls"] = {str(label): {
            "deadSlot": 3 if label == 3 else 5 if label == 4 else None,
            "activeMissingSlot": 3 if label == 5 else None,
            "renamedResourcesAndVariables": label == 4,
            "sourceAndEffectDeadSample": label != 5,
            "extraSamplerHasDefaultOrResource": False,
            "healthySuffixEffect": 2 if label == 5 else None,
            "entries": {k: hashlib.sha256(v).hexdigest() for k, v in fixture_entries(label).items()}}
            for label in (3, 4, 5)}
        (cls.evidence_root / "protocol.json").write_bytes(encoded(protocol))
        print(f"N03 native-world source App evidence: {cls.evidence_root}", flush=True)

    def test_authored_source_program_effect_and_terminal_readonly_depth(self):
        self.run_source_case(0)

    def test_unused_earlier_and_later_declared_dependencies_preserve_current_main_source(self):
        for label in (1, 2):
            with self.subTest(dependency=1 if label == 1 else 30, renamed=label == 2):
                self.run_source_case(label)

    def test_dead_unbound_source_and_effect_samplers_preserve_native_world_pixels(self):
        for label in (3, 4):
            with self.subTest(slot=3 if label == 3 else 5, renamed=label == 4):
                self.run_source_case(label)

    def test_live_unbound_sampler_falls_back_locally_before_healthy_suffix(self):
        self.run_source_case(5)

    def test_perspective_image_effect_uses_authored_terminal_depth(self):
        self.run_perspective_image_depth_case(sorting=True)

    def test_perspective_image_effect_keeps_authored_order_without_sorting(self):
        self.run_perspective_image_depth_case(sorting=False)

    def test_model_depth_test_write_combinations_and_complete_resource_rename(self):
        expected = {name: rgb for name, _, _, rgb in MODEL_DEPTH_STATES}
        for renamed in (False, True):
            name = "model-depth-state-renamed" if renamed else "model-depth-state"
            entries = model_depth_state_entries(renamed)
            folder, stem = ("retitled-surfaces", "distant") if renamed else ("depth-state", "far")
            ids = (1701, 1802, 1903) if renamed else (401, 402, 403)
            (self.evidence_root / (name + "-protocol.json")).write_bytes(encoded({
                "states": MODEL_DEPTH_STATES, "ROIs": MODEL_DEPTH_ROIS, "canvas": [256, 256],
                "expectedRGB": expected, "tolerance": TOLERANCE, "renamed": renamed,
                "drawOrder": [[layer, 4] for layer in ids],
                "ROITransform": "viewportCenter+(world-128)*max(W/256,H/256); center horizontal row",
                "entries": {path: hashlib.sha256(data).hexdigest() for path, data in entries.items()}}))
            with patch.object(app_runner, "CANVAS", (256, 256)):
                result = app_runner.SceneReflectionHistoryIntegrationTests.run_case(self, 0, capture=True,
                    name=name, entries=entries, rois=MODEL_DEPTH_ROIS,
                    material_input_path=f"materials/{folder}/{stem}-tested-writer.json")
            work = self.evidence_root / name
            for path, event in self.composition_captures(work, (work / "app.log").read_text()):
                models = [r for r in event["rows"] if r["kind"] == "model" and r.get("outcome") == "draw-encoded"]
                self.assertEqual([r["layerID"] for r in models], [layer for layer in ids for _ in range(4)])
                self.assertEqual(len({r["target"]["textureToken"] for r in models}), 1)
                for region, rgb in expected.items():
                    measurement = result["pixels"][path.name][region]
                    self.assertGreater(measurement["count"], 0)
                    for statistic in ("minimum", "maximum"):
                        for actual, reference in zip(measurement[statistic], rgb, strict=True):
                            self.assertAlmostEqual(actual, reference, delta=TOLERANCE,
                                msg=str((name, path.name, region, measurement)))

    def test_untested_opaque_model_is_a_transparent_sorting_barrier(self):
        for tested in (False, True):
            name = "model-depth-sorting-tested" if tested else "model-depth-sorting-untested"
            entries = model_depth_sort_barrier_entries(tested)
            regions = {"overlap": {"world": [0, 0, 0],
                "expectedRGB": (128, 64, 64) if tested else (0, 128, 128)},
                "outside": {"world": [2, 1.5, 0], "expectedRGB": (0, 0, 0)}}
            order = (512, 513, 511) if tested else (511, 512, 513)
            (self.evidence_root / (name + "-protocol.json")).write_bytes(encoded({
                "test": tested, "write": True, "sorting": True, "terminalOrder": order,
                "regions": regions, "tolerance": TOLERANCE,
                "entries": {path: hashlib.sha256(data).hexdigest() for path, data in entries.items()}}))
            with patch.object(app_runner, "measure_capture", measure_capture):
                result = app_runner.SceneReflectionHistoryIntegrationTests.run_case(self, 0, capture=True,
                    name=name, entries=entries, rois=regions, material_input_path="materials/order-barrier/blue.json")
            work = self.evidence_root / name
            for path, event in self.composition_captures(work, (work / "app.log").read_text()):
                terminals = [r for r in event["rows"] if r.get("outcome") == "draw-encoded"
                    and r["kind"] in ("ordinary", "model") and r.get("layerID") in (511, 512, 513)]
                self.assertEqual([r["layerID"] for r in terminals], list(order))
                self.assertEqual(len({r["target"]["textureToken"] for r in terminals}), 1)
                for region, details in regions.items():
                    measurement = result["pixels"][path.name][region]
                    for actual, expected in zip(measurement["mean"], details["expectedRGB"], strict=True):
                        self.assertAlmostEqual(actual, expected, delta=TOLERANCE,
                            msg=str((name, path.name, region, measurement)))

    def test_independent_perspective_text_blends_over_world_only_with_sorting(self):
        for sorting in (False, True):
            with self.subTest(sorting=sorting):
                self.run_perspective_text_depth_case(sorting=sorting)

    def test_world_text_order_preserves_actual_main_prefix_reader(self):
        self.run_perspective_text_depth_case(prefix=True)

    def test_late_named_first_model_preserves_direct_and_effect_text_depth(self):
        for renamed in (False, True):
            with self.subTest(renamed=renamed):
                self.run_perspective_text_depth_case(named_first=True, renamed=renamed)

    def run_perspective_text_depth_case(self, *, named_first=False, renamed=False, sorting=True, prefix=False):
        entries = perspective_text_depth_entries(named_first=named_first, renamed=renamed, sorting=sorting, prefix=prefix)
        name = (("late-named-text-renamed" if renamed else "late-named-text") if named_first
                else "text-prefix" if prefix else f"text-sort-{sorting}")
        provider = (901 if renamed else 11) if named_first else None
        (self.evidence_root / (name + "-protocol.json")).write_bytes(encoded({
            "entries": {k: hashlib.sha256(v).hexdigest() for k, v in entries.items()},
            "firstModel": 2, "lateHiddenProvider": provider, "sorting": sorting,
            "prefixReader": TARGET_LAYER if prefix else None, "prefixTint": PREFIX_TINT if prefix else None,
            "textCases": TEXT_DEPTH_CASES, "renamedProviderResources": renamed}))
        with patch.object(app_runner, "measure_capture", measure_perspective_text_depth):
            result = app_runner.SceneReflectionHistoryIntegrationTests.run_case(
                self, 8, capture=True, entries=entries, name=name, material_input_path="materials/owned_ink.json")
        work = self.evidence_root / name
        log = (work / "app.log").read_text()
        if named_first:
            self.assertIn(f"phase=named-target-capture layer={provider} status=succeeded", log)
            self.assertIn("phase=named-target-binding layer=2 status=succeeded", log)
        identity = json.loads((work / "identity.json").read_text())
        self.assertEqual(app_runner.sha256(work / "content/scene.pkg"), identity["package"])
        self.assertEqual(app_runner.sha256(work / "content/project.json"), identity["project"])
        for path, event in self.composition_captures(work, log):
            with self.subTest(capture=path.name):
                rows = event["rows"]
                terminals = [row for row in rows if row["kind"] in ("ordinary", "model")
                             and row.get("outcome") == "draw-encoded"]
                if named_first:
                    order = [2, *(case[0] for case in TEXT_DEPTH_CASES), 30]
                elif prefix:
                    order = [2, 74, 71, TARGET_LAYER, 30, 72, 73, 81, 82]
                else:
                    order = [2, 74, 30, 71, 72, 73, 81, 82] if sorting else [2, 74, 71, 72, 73, 81, 82, 30]
                self.assertEqual([row["layerID"] for row in terminals], order)
                self.assertEqual(len({row["target"]["textureToken"] for row in terminals}), 1)
                for layer, _, _, _, _, effect in TEXT_DEPTH_CASES:
                    terminal, = (row for row in terminals if row["layerID"] == layer)
                    self.assertEqual(terminal["kind"], "ordinary")
                    self.assertEqual(terminal["details"]["contentKind"], "text")
                    layer_rows = [row for row in rows if row.get("layerID") == layer]
                    source, = (row for row in layer_rows if row["kind"] == "source-selection")
                    self.assertIn(f"dynamicText(layerID: {layer})", source["source"]["candidateIdentity"])
                    source_token = source["source"]["textureToken"]
                    if effect:
                        capture, = (row for row in layer_rows if row["kind"] == "sourceCapture")
                        material, = (row for row in layer_rows if row["kind"] == "material")
                        self.assertEqual(capture["source"]["textureToken"], source_token)
                        self.assertEqual(capture["target"]["textureToken"], material["source"]["textureToken"])
                        source_token = material["target"]["textureToken"]
                        self.assertLess(layer_rows.index(capture), layer_rows.index(material))
                        self.assertLess(layer_rows.index(material), layer_rows.index(terminal))
                    self.assertEqual(terminal["source"]["textureToken"], source_token)
                pixels = result["pixels"][path.name]
                for case, color in (("direct-far", "tinted" if prefix else "white"),
                                    ("effect-far", "halfGray" if named_first else "halfGreen"),
                                    ("renamed-effect-far", "halfGray" if named_first else "halfGreen")):
                    pixel = pixels[case]
                    if sorting:
                        self.assertGreater(pixel[color], 30, (case, pixels))
                        self.assertGreater(pixel["green"], pixel["count"] / 2, (case, pixels))
                    else:
                        self.assertEqual(pixel["green"], pixel["count"], (case, pixels))
                for case, color in (("disabled-far", "green"), ("direct-near", "orange"), ("effect-near", "orange")):
                    self.assertGreater(pixels[case]["count"], 100, (case, pixels))
                    self.assertEqual(pixels[case][color], pixels[case]["count"], (case, pixels))
                if prefix:
                    read, = (r for r in rows if r["kind"] == "background-copy"
                             and r.get("layerID") == TARGET_LAYER and r.get("outcome") == "encoded")
                    blend, = (r for r in rows if r["kind"] == "color-blend-background"
                              and r.get("layerID") == TARGET_LAYER and r.get("outcome") == "draw-encoded")
                    self.assertEqual(read["source"]["textureToken"], blend["target"]["textureToken"])
                    self.assertEqual(read["target"]["textureToken"], blend["source"]["textureToken"])
                    self.assertLess(rows.index(terminals[2]), rows.index(read))
                    self.assertLess(rows.index(blend), rows.index(terminals[4]))

    def run_perspective_image_depth_case(self, *, sorting):
        label = 6 if sorting else 7
        regions = perspective_image_depth_regions(sorting)
        entries = perspective_image_depth_entries(label)
        order = (2, 22, 30, 21, 20) if sorting else (2, 22, 20, 21, 30)
        (self.evidence_root / f"perspective-image-depth-{label}-protocol.json").write_bytes(encoded({
            "sorting": sorting, "terminalOrder": order, "regions": regions, "tolerance": TOLERANCE,
            "entries": {path: hashlib.sha256(data).hexdigest() for path, data in entries.items()},
        }))
        with patch.object(app_runner, "fixture_entries", perspective_image_depth_entries), patch.object(
                app_runner, "measure_capture", lambda path: measure_capture(path, regions)):
            result = app_runner.SceneReflectionHistoryIntegrationTests.run_case(self, label, capture=True,
                material_input_path=DEPTH_CARD_MATERIAL)
        work = self.evidence_root / f"Ref{label}-capture-on"
        identity = json.loads((work / "identity.json").read_text())
        self.assertEqual(app_runner.sha256(work / "content/scene.pkg"), identity["package"])
        self.assertEqual(app_runner.sha256(work / "content/project.json"), identity["project"])
        log = (work / "app.log").read_text()
        for path, event in self.composition_captures(work, log):
            draws = [row for row in event["rows"] if row.get("outcome") == "draw-encoded"]
            terminals = [row for row in draws if row["kind"] in ("ordinary", "model", "terminal-material-replay")
                         and row.get("layerID") in (2, *DEPTH_CARD_IDS, 30)]
            self.assertEqual([(row["kind"], row["layerID"]) for row in terminals],
                [("ordinary" if layer in DEPTH_CARD_IDS else "model", layer) for layer in order])
            self.assertEqual(len({row["target"]["textureToken"] for row in terminals}), 1)
            for terminal in (row for row in terminals if row["kind"] == "ordinary"):
                material = [row for row in draws if row["kind"] == "material"
                            and row.get("layerID") == terminal["layerID"] and row.get("effectIndex") == 0]
                self.assertEqual(len(material), 1, material)
                self.assertEqual(material[0]["target"]["textureToken"], terminal["source"]["textureToken"])
                self.assertLess(draws.index(material[0]), draws.index(terminal))
            for name, region in regions.items():
                measured = result["pixels"][path.name][name]
                self.assertGreater(measured["count"], 0)
                for actual, expected in zip(measured["mean"], region["expectedRGB"], strict=True):
                    self.assertAlmostEqual(actual, expected, delta=TOLERANCE,
                        msg=str((path.name, name, measured, region)))

    def run_source_case(self, label):
        # The existing runner dispatches one real App and asserts immutable
        # inputs, actual Metal completion, no GPU error, normal stop and drain.
        with patch.object(app_runner, "fixture_entries", fixture_entries), patch.object(
                app_runner, "measure_capture", measure_capture):
            result = app_runner.SceneReflectionHistoryIntegrationTests.run_case(self, label, capture=True,
                material_input_path="materials/retitled/current_view.json" if label in (2, 4) else "materials/receiver.json")
        work = self.evidence_root / f"Ref{label}-capture-on"
        identity = json.loads((work / "identity.json").read_text())
        inputs_after = {"package": app_runner.sha256(work / "content/scene.pkg"),
                        "project": app_runner.sha256(work / "content/project.json")}
        self.assertEqual(inputs_after["package"], identity["package"], inputs_after)
        self.assertEqual(inputs_after["project"], identity["project"], inputs_after)
        regions = roi_protocol()["regions"]
        for phase in ["scene-ready-window.png", "scene-after-window.png"]:
            for region_name, region in regions.items():
                measurement = result["pixels"][phase][region_name]
                self.assertGreater(measurement["count"], 0, (phase, region_name))
                for actual, expected in zip(measurement["mean"], region["expectedRGB"], strict=True):
                    self.assertAlmostEqual(actual, expected, delta=TOLERANCE,
                                           msg=str((phase, region_name, measurement, region)))
        log = (work / "app.log").read_text()
        completed = re_graph_frames(log)
        self.assertGreaterEqual(len(completed), 2, completed)
        self.assertNotRegex(log, r"entries=[^\n]*20:layer-source-not-ready")
        if label in (3, 4, 5):
            self.check_material_binding_captures(work, log, label)
        (work / "native-world-checks.json").write_bytes(encoded({
            "inputAfter": inputs_after, "inputImmutable": True,
            "completedTargetGraphFrames": sorted(completed),
            "targetGraphSourceExtent": list(LOCAL_SIZE),
            "oracle": roi_protocol(), "pixels": result["pixels"],
            "scope": "One full product-chain scene; two settled captures and completed graph frames, not adjacent-frame pixel pairing or official parity."}))

    def composition_captures(self, work, log):
        observations = structured_runtime_observations(log, "MWX SCENE COMPOSITION OBSERVATION: ")
        self.assertEqual(observations["parse_errors"], 0)
        for path in sorted((work / "evidence").glob("*-window.png")):
            reason = "ready" if "ready" in path.name else "after"
            request = re.search(rf"phase=snapshot reason={reason} request=(\d+) source=metal path={re.escape(str(path))}", log)
            self.assertIsNotNone(request)
            encoding = re.search(rf"phase=snapshot-encoded request={request[1]} commandBufferToken=(\d+) "
                r"textureToken=(\d+) width=(\d+) height=(\d+)", log)
            self.assertIsNotNone(encoding)
            receipt = terminal_composition_snapshot({"status": "captured", "request_id": int(request[1]),
                "command_buffer_token": encoding[1], "texture_token": encoding[2],
                "source_width": int(encoding[3]), "source_height": int(encoding[4])}, observations)
            self.assertTrue(receipt["composition_receipt_matched"], receipt)
            event = next(e for e in observations["events"] if e.get("captureRequestID") == int(request[1])
                and e.get("commandBufferToken") == encoding[1])
            self.assertEqual(event["truncatedRows"], 0)
            self.assertEqual(event["gpuStatus"], "completed")
            yield path, event

    def check_material_binding_captures(self, work, log, label):
        if label == 5:
            self.assertRegex(log, r"MWX resolved material envelope rejection: [^\n]* node=1 "
                r"kind=texture-binding reason=texture/textureBindingInvalid slot=3(?: |$)")
            self.assertRegex(log, r"axis=effect-cpu-invocation [^\n]*layer=20 effect=1 "
                r"[^\n]*backend=resolved-material-graph outcome=failed ")
        receipts = []
        for path, event in self.composition_captures(work, log):
            rows = event["rows"]
            material = [r for r in rows if r["kind"] == "material" and r.get("layerID") == TARGET_LAYER
                        and r.get("outcome") == "draw-encoded"]
            source = [r for r in material if "effectIndex" not in r]
            self.assertEqual(len(source), 1, source)
            self.assertEqual(source[0]["slot"], 0)
            self.assertEqual([(r["effectIndex"], r["slot"]) for r in material if "effectIndex" in r],
                             [(0, 0), (2, 0)] if label == 5 else [(0, 0)])
            self.assertEqual(source[0]["target"]["textureToken"], material[1]["source"]["textureToken"])
            copies = [r for r in rows if r["kind"] == "copy" and r.get("layerID") == TARGET_LAYER
                      and r.get("effectIndex") == 1 and r.get("outcome") == "encoded"]
            self.assertEqual(len(copies), int(label == 5), copies)
            if label == 5:
                self.assertEqual(material[1]["target"]["textureToken"], copies[0]["source"]["textureToken"])
                self.assertEqual(copies[0]["target"]["textureToken"], material[2]["source"]["textureToken"])
                self.assertLess(rows.index(material[1]), rows.index(copies[0]))
                self.assertLess(rows.index(copies[0]), rows.index(material[2]))
            self.assertEqual(sum(r["kind"] == "graph-transaction" and r.get("layerID") == TARGET_LAYER for r in rows), 1)
            group = [r for r in rows if r["kind"] == "group" and r.get("layerID") == TARGET_LAYER
                     and r.get("outcome") == "draw-encoded"]
            self.assertEqual(len(group), 1, group)
            self.assertEqual(material[-1]["target"]["textureToken"], group[0]["source"]["textureToken"])
            self.assertEqual(source[0]["source"]["textureToken"], group[0]["target"]["textureToken"])
            receipts.append({"capture": path.name, "frame": event["frameIndex"], "request": event["captureRequestID"],
                "commandBuffer": event["commandBufferToken"], "Surface": event["surfaceIdentity"],
                "sourceAndEffectSlots": [[r.get("effectIndex"), r["slot"]] for r in material],
                "missingEffectCopies": copies,
                "scope": "actual binding/encode and pixels; emitted-MSL/schema retirement is separately tested by the compiler gate"})
        (work / "material-binding-checks.json").write_bytes(encoded(receipts))


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
