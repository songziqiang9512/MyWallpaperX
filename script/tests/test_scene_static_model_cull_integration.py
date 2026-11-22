"""Owned opposite-winding MDL parts exercise authored cull in the real App.

Set MWX_SCENE_INTEGRATION_APP to an immutable Debug App. The App test uses
real reader/material preparation, color and shadow encoders, and compositor.
No corpus assets or official-client payloads are used; this is a bounded cull
regression, not model parity. CPU fixture validation runs without an App/GPU.
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

from script.tests import test_scene_static_model_reader as reader
from script.tests.test_scene_directional_shadow_integration import png, quad
from script.tests.test_scene_native_world_composition import png as grid_png
from script.tests.test_scene_static_model_parts import join_parts
from script.tests.support.scene_pkg_fixture import make_package
from script.tests.test_scene_fullscreen_visibility_integration import app_hashes, file_hashes
from script.web_benchmark_capture import png_rgb_pixels


REPO = Path(__file__).resolve().parents[2]
CANVAS = (160, 96)
TOLERANCE = 4
STATES = (("nocull", "  NoCull \n"), ("normal", "normal"),
          ("missing", None), ("unknown", "owned-unknown-cull"))
SOURCES = tuple(REPO / "script/tests" / name for name in (
    "test_scene_static_model_cull_integration.py", "test_scene_static_model_reader.py",
    "test_scene_static_model_parts.py", "test_scene_directional_shadow_integration.py",
    "scene_pkg_fixture.py", "test_scene_fullscreen_visibility_integration.py",
    "test_scene_named_model_shadow.py", "scene_color_blend_capture_test_support.py",
    "test_scene_native_world_composition.py"
)) + (REPO / "script/web_benchmark_capture.py",)


def encoded(value):
    return json.dumps(value, sort_keys=True).encode()


def fixture_entries(*, cast=True, all_nocull=False, texture_case=None, frame_phase=None, noise_case=None,
                    affine_case=None, normal_case=None, opacity_case=None, hdr_case=None, brightness_case=None,
                    effect_role_case=None, image_model_case=None, named_extent_case=None):
    if named_extent_case is not None:
        return named_extent_entries(named_extent_case)
    if image_model_case is not None:
        return image_model_entries(image_model_case)
    if effect_role_case is not None:
        return effect_role_entries(effect_role_case)
    if any(value is not None for value in (noise_case, normal_case, opacity_case, hdr_case, brightness_case)):
        texture_case = "crop"
    if affine_case is not None:
        texture_case = "crop" if affine_case.endswith("-crop") else "frame"
    entries, parts, cases = {}, [], []
    states = STATES if texture_case is None else (("texture", "nocull"),)
    for column, (state, raw) in enumerate(states):
        x = 30 + column * 35 if texture_case is None else 80
        for reverse in ((False, True) if texture_case is None else (False,)):
            y = (32 if not reverse else 64) if texture_case is None else 48
            name = f"{state}-{'reverse' if reverse else 'front'}"
            material = ("materials/independent-side.json" if normal_case and normal_case.startswith("yz")
                        else f"materials/{name}.json")
            if normal_case and normal_case.startswith("yz"):
                vertices = [((0., py, 160 - px), (-1., 0., 0.), (0., 0., -1., 1.), uv)
                            for px, py, uv in ((x - 3, y - 4, (0., 0.)), (x + 3, y - 4, (1., 0.)),
                                (x + 3, y + 4, (1., 1.)), (x - 3, y + 4, (0., 1.)))]
                model = reader.build_model(vertices=vertices, indices=(0, 2, 1, 0, 3, 2),
                    bounds=(0, y - 4, 160 - x - 3, 0, y + 4, 160 - x + 3), material=material.encode())
            else:
                model = quad(x - 3, x + 3, y - 4, y + 4, 0 if normal_case else 20, material)
            if reverse:
                vertices = [((px, py, 20.), (0., 0., 1.), (1., 0., 0., 1.), uv)
                            for px, py, uv in ((x - 3, y - 4, (0., 0.)),
                                (x + 3, y - 4, (1., 0.)), (x + 3, y + 4, (1., 1.)),
                                (x - 3, y + 4, (0., 1.)))]
                model = reader.build_model(vertices=vertices, indices=(0, 1, 2, 0, 2, 3),
                    bounds=(x - 3, y - 4, 20, x + 3, y + 4, 20), material=material.encode())
            parts.append(model)
            render_pass = {"shader": "genericimage", "textures": ["materials/green.png"],
                "combos": {"LIGHTING": 0}, "blending": "normal",
                "depthtest": "enabled", "depthwrite": "enabled"}
            if texture_case is not None:
                render_pass.update(textures=["materials/model-surface.tex"], blending="translucent")
            if opacity_case is not None:
                render_pass.update(shader="genericimage2",
                    constantshadervalues={"alpha": 1 if opacity_case == "opacity-control" else 1e300})
            if hdr_case is not None:
                render_pass.update(shader="genericimage2", constantshadervalues={
                    "color": [514 if hdr_case == "hdr-control" else 131072]*3, "alpha": 1/1024})
            if brightness_case is not None:
                render_pass.update(shader="genericimage2", constantshadervalues={"color": [1, 1, 1],
                    "alpha": 1, "brightness": (1 if brightness_case == "brightness-one" else
                        "1e300" if brightness_case == "brightness-renamed" else 1e300)})
            if noise_case is not None:
                render_pass.update(shader="chroma4", textures=["materials/model-surface.tex"] + [None] * 7
                    + ["materials/pigment-grain.tex"], combos={"LIGHTING": 1, "NORMALMAP": 0,
                        "REFLECTION": 0, "PBRMASKS": 0}, constantshadervalues={"metallic": 0,
                        "roughness": 0, "reflectivity": 0, "emissivebrightness": 0, "tintpigmentation": .2})
            if all_nocull or raw is not None:
                render_pass["cullmode"] = "nocull" if all_nocull else raw
            entries[material] = encoded({"passes": [render_pass]})
            if texture_case is None:
                cases.append({"name": name, "state": state, "reverse": reverse,
                    "material": material, "colorPoint": [x, y], "shadowPoint": [x - 12, y],
                    "visible": all_nocull or not reverse or state == "nocull",
                    "shadowed": cast and (all_nocull or not reverse or state == "nocull")})
            else:
                palettes = (([200, 0, 0, 255], [0, 200, 0, 0],
                             [0, 200, 0, 255], [0, 0, 200, 255]),
                            ([0, 0, 200, 255], [200, 0, 0, 255],
                             [200, 200, 0, 0], [0, 200, 0, 255]))
                palette = palettes[frame_phase or 0]
                if affine_case is not None:
                    order = (1, 3, 0, 2) if affine_case.startswith("rot90") else (2, 3, 0, 1)
                    palette = tuple(palettes[0][i] for i in order)
                    if affine_case == "skew":
                        palette = ([60, 70, 76, 255], [100, 70, 80, 0],
                                   [80, 110, 110, 255], [120, 110, 114, 255])
                if noise_case is not None:
                    palette = ([128, 128, 128, 255],) * 4
                if hdr_case is not None:
                    palette = ([255 if hdr_case == "hdr-control" else 1]*3 + [255],) * 4
                for i, rgba in enumerate(palette):
                    px, py = x + (-1.5 if i % 2 == 0 else 1.5), y + (-2 if i < 2 else 2)
                    cases.append({"name": f"texel-{i}", "state": state, "reverse": False,
                        "material": material, "colorPoint": [px, py], "shadowPoint": [px - 12, py],
                        "rgba": rgba, "visible": rgba[3] != 0, "shadowed": cast and rgba[3] != 0})
                source_palette = palettes[0] if affine_case and texture_case != "crop" else palette
                crop = b"".join(bytes(source_palette[(row // 2) * 2 + col // 2])
                                 for row in range(4) for col in range(4))
                width = 4 if texture_case == "crop" else 8
                pixels = bytearray(crop if texture_case == "crop" else bytes([255, 0, 255, 255]) * 64)
                if width == 8:
                    for row in range(4):
                        offset = ((row + 2) * 8 + 2) * 4
                        pixels[offset:offset + 16] = crop[row * 16:(row + 1) * 16]
                frames = [] if texture_case == "crop" else [(2, 2, 0 if texture_case == "zero" else 4, 0, 0, 4)]
                if texture_case == "multi": frames *= 2
                if affine_case and texture_case != "crop":
                    frames = [(6, 2, 0, 4, -4, 0) if affine_case.startswith("rot90") else (2, 6, 4, 0, 0, -4)]
                    if affine_case == "skew":
                        frames = [(1, 1.5, 4, 0, 2, 4)]
                        pixels = bytearray(c for py in range(8) for px in range(8)
                            for c in (20 + px * 20, 30 + py * 20, 40 + (px + 8 * py) * 2,
                                      0 if (px, py) == (4, 2) else 255))
                if texture_case == "animated":
                    pixels = bytearray(bytes([255, 0, 255, 255]) * 64)
                    frames = [(0, 0, 4, 0, 0, 4), (4, 4, 4, 0, 0, 4)]
                    for index, (ox, oy, *_) in enumerate(frames):
                        for row in range(4):
                            for col in range(4):
                                offset = ((row + oy) * 8 + ox + col) * 4
                                pixels[offset:offset + 4] = bytes(palettes[index][(row // 2) * 2 + col // 2])
                data = (b"TEXV0005\0TEXI0001\0" + struct.pack("<7I", 0, 3 | (4 if frames else 0),
                    width, width, width, width, 0) + b"TEXB0002\0"
                    + struct.pack("<7I", 1, 1, width, width, 0, 0, len(pixels)) + pixels)
                if frames:
                    data += b"TEXS0002\0" + struct.pack("<I", len(frames))
                    for index, frame in enumerate(frames):
                        duration = (2.0 if index == 0 else 3600.0) if texture_case == "animated" else 2.5
                        data += struct.pack("<If6f", 0, duration, *frame)
                entries["materials/model-surface.tex"] = data
    if noise_case is not None:
        width = 8 if noise_case == "atlas" else 2
        pixels = bytearray(bytes([255, 0, 255, 255]) * (width * width))
        origin = 2 if noise_case == "atlas" else 0
        for y in range(2):
            for x in range(2):
                offset = ((y + origin) * width + x + origin) * 4
                pixels[offset:offset + 4] = bytes([255 if (x + y) % 2 else 0] * 3 + [255])
        data = (b"TEXV0005\0TEXI0001\0" + struct.pack("<7I", 0, 5 if noise_case == "atlas" else 1,
            width, width, width, width, 0) + b"TEXB0002\0"
            + struct.pack("<7I", 1, 1, width, width, 0, 0, len(pixels)) + pixels)
        if noise_case == "atlas":
            data += b"TEXS0002\0" + struct.pack("<IIf6f", 1, 0, 2.5, 2, 2, 2, 0, 0, 2)
        entries["materials/pigment-grain.tex"] = data
    # Adjacent parts alternate authored states within one model; an independent
    # front-facing default material is drawn later in the same main encoder.
    # Legacy directional energy is 0.30 * intensity. Intensity 2 gives the +Z
    # receiver 180 * (0.025 + 0.60 / sqrt(1 + 0.6**2)) ~= 97, below saturation;
    # shadowed ambient remains ~= 5. Geometry and the pixel gates stay fixed.
    scene = {"version": 3, "general": {
        "orthogonalprojection": {"width": CANVAS[0], "height": CANVAS[1]},
        "clearcolor": "0 0 0", "ambientcolor": "0.05 0.05 0.05", "skylightcolor": "0 0 0",
        "lightconfig": {"directional": 1}},
        "objects": [
            {"id": 1, "model": "models/receiver.mdl", "origin": "0 96 0",
             "perspective": False, "castshadow": False},
            {"id": 2, "model": "models/cases.mdl", "origin": "0 96 0",
             "perspective": False, "castshadow": cast},
            {"id": 3, "light": "ldirectional", "angles": f"0 {math.pi / 2 + math.atan(.6)} 0",
             "color": "1 1 1", "intensity": 2, "castshadow": True},
            {"id": 4, "model": "models/healthy.mdl", "origin": "0 96 0",
             "perspective": False, "castshadow": False}]}
    if noise_case is not None:
        scene["general"]["ambientcolor"] = "0 0 0"
    # This older ROI carrier writes canonical-down vertices. Make that author
    # reflection explicit; the positive-Y-up basis gate uses separate geometry.
    for obj in scene["objects"]:
        if "model" in obj:
            obj["scale"] = "1 -1 1"
    entries.update({"scene.json": encoded(scene), "models/cases.mdl": join_parts(parts),
        "models/receiver.mdl": quad(10, 150, 10, 86, 0, "materials/receiver.json"),
        "models/healthy.mdl": quad(141, 149, 76, 84, 25, "materials/healthy.json"),
        "materials/green.png": png([0, 200, 0, 255]),
        "materials/white.png": png([180, 180, 180, 255]),
        "materials/blue.png": png([0, 0, 255, 255]),
        "materials/receiver.json": encoded({"passes": [{"shader": "genericimage",
            "textures": ["materials/white.png"], "combos": {"LIGHTING": 1},
            "cullmode": "nocull", "blending": "normal", "depthwrite": "enabled"}]}),
        "materials/healthy.json": encoded({"passes": [{"shader": "genericimage",
            "textures": ["materials/blue.png"], "combos": {"LIGHTING": 0},
            "blending": "normal", "depthwrite": "enabled"}]})})
    if normal_case is not None:
        subject = next(obj for obj in scene["objects"] if obj["id"] == 2)
        singular = normal_case.endswith("singular")
        subject.update(origin="0 96 20", scale="1 -1 0" if singular else "1 -1 1")
        if normal_case.startswith("yz"):
            subject.update(origin="0 96 0", parent=6, scale="0 -1 1" if singular else "1 -1 1",
                model="models/independent-side-plane.mdl")
            scene["objects"].insert(0, {"id": 6, "name": "Owned rotated mirrored parent",
                "origin": "160 0 20", "angles": f"0 {math.pi / 2} 0", "scale": "1 1 -1"})
            entries[subject["model"]] = entries.pop("models/cases.mdl")
            entries["materials/independent-surface.tex"] = entries.pop("materials/model-surface.tex")
            value = json.loads(entries["materials/independent-side.json"])
            value["passes"][0]["textures"] = ["materials/independent-surface.tex"]
            entries["materials/independent-side.json"] = encoded(value)
        scene["objects"].append({"id": 5, "model": "models/behind.mdl", "origin": "0 96 0",
            "scale": "1 -1 1", "perspective": False, "castshadow": False})
        entries.update({"models/behind.mdl": quad(77, 83, 44, 52, 10, "materials/behind.json"),
            "materials/behind.png": png([0, 0, 200, 255]),
            "materials/behind.json": encoded({"passes": [{"shader": "genericimage",
                "textures": ["materials/behind.png"], "combos": {"LIGHTING": 0}, "cullmode": "nocull",
                "blending": "normal", "depthtest": "enabled", "depthwrite": "enabled"}]}),
            "scene.json": encoded(scene)})
    if opacity_case is not None:
        subject = next(obj for obj in scene["objects"] if obj["id"] == 2)
        subject["castshadow"] = opacity_case != "opacity-huge-no-cast"
        for case in cases:
            case.update(layerID=2, shadowed=subject["castshadow"] and case["visible"])
        if opacity_case == "opacity-huge-renamed":
            material, texture = "materials/Relocated coat.json", "materials/Relocated color.tex"
            value = json.loads(entries.pop("materials/texture-front.json"))
            value["passes"][0]["textures"] = [texture]
            entries[material] = encoded(value)
            entries[texture] = entries.pop("materials/model-surface.tex")
            del entries["models/cases.mdl"]
            subject["model"] = "models/Relocated plane.mdl"
            entries[subject["model"]] = quad(77, 83, 44, 52, 20, material)
            for case in cases:
                case["material"] = material
        scene["objects"].append({"id": 5, "model": "models/caster-peer.mdl", "origin": "0 96 0",
            "scale": "1 -1 1", "perspective": False, "castshadow": True})
        entries.update({"models/caster-peer.mdl": quad(107, 113, 44, 52, 20, "materials/caster-peer.json"),
            "materials/caster-peer.json": encoded({"passes": [{"shader": "genericimage2",
                "textures": ["materials/green.png"], "combos": {"LIGHTING": 0},
                "constantshadervalues": {"alpha": 1}, "cullmode": "nocull", "blending": "normal",
                "depthtest": "enabled", "depthwrite": "enabled"}]}), "scene.json": encoded(scene)})
        cases.append({"name": "independent-caster", "state": "nocull", "reverse": False,
            "material": "materials/caster-peer.json", "layerID": 5, "colorPoint": [110, 48],
            "shadowPoint": [98, 48], "rgba": [0, 200, 0, 255], "visible": True, "shadowed": True})
    if hdr_case is not None:
        scene["general"]["hdr"] = True
        subject = next(obj for obj in scene["objects"] if obj["id"] == 2)
        subject["castshadow"] = False
        for case in cases: case["shadowed"] = False
        if hdr_case == "hdr-renamed":
            material, texture = "materials/HDR alternate coat.json", "materials/HDR alternate texel.tex"
            value = json.loads(entries.pop("materials/texture-front.json"))
            value["passes"][0]["textures"] = [texture]
            entries[material] = encoded(value)
            entries[texture] = entries.pop("materials/model-surface.tex")
            del entries["models/cases.mdl"]
            subject["model"] = "models/HDR alternate plane.mdl"
            entries[subject["model"]] = quad(77, 83, 44, 52, 20, material)
            for case in cases: case["material"] = material
        entries["scene.json"] = encoded(scene)
    if brightness_case is not None:
        scene["general"]["hdr"] = False
        if brightness_case == "brightness-renamed":
            material, texture = "materials/Unused gain coat.json", "materials/Unused gain color.tex"
            value = json.loads(entries.pop("materials/texture-front.json"))
            value["passes"][0]["textures"] = [texture]
            entries[material] = encoded(value)
            entries[texture] = entries.pop("materials/model-surface.tex")
            subject = next(obj for obj in scene["objects"] if obj["id"] == 2)
            del entries["models/cases.mdl"]
            subject["model"] = "models/Unused gain plane.mdl"
            entries[subject["model"]] = quad(77, 83, 44, 52, 20, material)
            for case in cases: case["material"] = material
        entries["scene.json"] = encoded(scene)
    # This geometric oracle is fixed before GPU execution. A ray from each
    # shadow ROI toward +X,+Z travels 20 in Z and 12 in X, hitting only its part.
    for case in cases:
        hit = [case["shadowPoint"][0] + 12, case["shadowPoint"][1]]
        case["rayHitParts"] = ([0] if texture_case is not None else [i for i, other in enumerate(cases)
            if abs(hit[0] - other["colorPoint"][0]) <= 3
            and abs(hit[1] - other["colorPoint"][1]) <= 4])
    return scene, entries, cases


def effect_role_entries(case):
    from script.tests import test_scene_named_model_shadow as named
    scene, entries = named.named_fixture("named-late")
    _, donor = named.named_fixture("forward-graph-neighbor")
    standard, explicit = "effects/own_dim/effect.json", "effects/selected-model-dim.json"
    for key in (standard, "materials/own_dim.json", "shaders/own_dim.vert", "shaders/own_dim.frag"):
        entries[key] = donor[key]
    entries[explicit] = entries[standard]
    selected = standard if case == "role-standard" else explicit
    if case == "role-material-directory":
        selected = "materials/selected-effect.json"
        entries[selected] = entries[standard]
    provider = next(obj for obj in scene["objects"] if obj["id"] == 11)
    provider["effects"] = [{"id": 110, "file": selected, "visible": True}]
    if case == "role-renamed":
        selected, effect_material = "definitions/Relocated dim.fx", "materials/Relocated dim.json"
        shader = "relocated_dim"
        entries[selected] = json.dumps({"passes": [{"material": effect_material}]}).encode()
        material = json.loads(entries.pop("materials/own_dim.json"))
        material["passes"][0]["shader"] = shader
        entries[effect_material] = json.dumps(material).encode()
        for stage in ("vert", "frag"):
            source = entries.pop(f"shaders/own_dim.{stage}").replace(b"v_TexCoord", b"lookupCoord")
            if stage == "frag":
                source = source.replace(b"vec4 c=", b"vec4 texelValue=").replace(
                    b"c.rgb*=0.5", b"texelValue.rgb=(texelValue.rgb+texelValue.rgb)*0.25").replace(
                    b"gl_FragColor=c;", b"gl_FragColor=texelValue;")
            entries[f"shaders/{shader}.{stage}"] = source
        del entries[standard], entries[explicit], entries["models/caster.mdl"]
        caster = next(obj for obj in scene["objects"] if obj["id"] == 2)
        caster["model"] = "models/Relocated caster.mdl"
        entries["materials/Relocated caster.json"] = entries.pop("materials/caster.json")
        entries[caster["model"]] = quad(70, 90, 38, 58, 20, "materials/Relocated caster.json")
        provider["image"] = "models/Relocated provider.json"
        del entries["models/provider.json"]
        entries[provider["image"]] = json.dumps({"material": "materials/Relocated provider.json"}).encode()
        material = json.loads(entries.pop("materials/provider.json"))
        material["passes"][0]["textures"] = ["materials/Relocated green.png"]
        entries["materials/Relocated provider.json"] = json.dumps(material).encode()
        entries["materials/Relocated green.png"] = entries.pop("materials/green.png")
        provider["effects"][0]["file"] = selected
    entries["scene.json"] = json.dumps(scene).encode()
    cases = [{"name": "caster", "colorPoint": [80, 48], "shadowPoint": [60, 48],
        "expectedRGB": [0, named.EXPECTED["caster"][1] * .5, 0],
        "expectedShadowRGB": named.EXPECTED["shadow"], "receiverRGB": named.EXPECTED["control"],
        "effectPath": selected, "tolerance": named.TOLERANCE}]
    return scene, entries, cases


def named_extent_entries(case):
    renamed = case == "extent-parent-renamed"
    scene, entries, cases = effect_role_entries("role-renamed" if renamed else "role-standard")
    provider = next(obj for obj in scene["objects"] if obj["id"] == 11)
    provider["size"] = "384 192"
    model = json.loads(entries[provider["image"]])
    material_path = model["material"]
    material = json.loads(entries[material_path])
    texture = material["passes"][0]["textures"][0]
    entries[texture] = grid_png(384, 192,
        lambda x, y: (200, 0, 0) if (y // 12) % 2 == 0 else (0, 200, 0))
    caster = next(obj for obj in scene["objects"] if obj["id"] == 2)
    caster_path = "materials/Relocated caster.json" if renamed else "materials/caster.json"
    caster_material = json.loads(entries[caster_path])
    caster_material["passes"][0]["combos"]["LIGHTING"] = 0
    if case == "extent-scaled":
        provider["scale"] = "100 0.007 0.01"
    if renamed:
        scene["objects"].insert(0, {"id": 601, "name": "Equivalent parent scale",
            "origin": "80 48 0", "scale": "100 0.007 0.01"})
        provider.update(id=411, name="Relocated stripe source", parent=601, origin="0 0 0")
        provider["effects"][0]["id"] = 4110
        caster["dependencies"] = [411]
        caster_material["passes"][0]["textures"] = ["_rt_imageLayerComposite_411_a"]
    entries[caster_path] = json.dumps(caster_material).encode()
    entries["scene.json"] = json.dumps(scene).encode()
    cases[0].update(expectedRGB=None, providerID=provider["id"],
        sourceExtent=[384, 192], namedExtentCase=case,
        bandPoints=[[80, 38 + (i + .5) * 20 / 16] for i in range(16)],
        bandRGB=[[100, 0, 0] if i % 2 == 0 else [0, 100, 0] for i in range(16)])
    return scene, entries, cases


def image_model_entries(case):
    renamed = case == "image-model-renamed"
    scene, entries, cases = effect_role_entries("role-renamed" if renamed else "role-standard")
    provider = next(obj for obj in scene["objects"] if obj["id"] == 11)
    if renamed:
        entries["effects/own_dim/effect.json"] = entries.pop(provider["effects"][0]["file"])
        provider["effects"][0]["file"] = "effects/own_dim/effect.json"
        path = "providers/Relocated provider.json"
        entries[path] = entries.pop(provider["image"])
        provider["image"] = path
    else:
        entries["providers/provider.json"] = entries["models/provider.json"]
        provider["image"] = "models/provider.json" if case == "image-model-standard" else "providers/provider.json"
    entries["scene.json"] = json.dumps(scene).encode()
    cases[0].update(effectPath="effects/own_dim/effect.json", imageModelPath=provider["image"])
    return scene, entries, cases


def measure(path, cases, probe_points=None):
    decoded = png_rgb_pixels(path)
    if decoded is None:
        raise AssertionError(f"invalid PNG: {path}")
    width, height, rows = decoded
    scale = max(width / CANVAS[0], height / CANVAS[1])
    points = {f"{case['name']}-{kind}": case[f"{kind}Point"]
              for case in cases for kind in ("color", "shadow")}
    points.update(probe_points if probe_points is not None else {"healthy": [145, 80], "clear": [80, 16]})
    result = {"dimensions": [width, height], "pixels": {}}
    for name, (x, y) in points.items():
        cx, cy = width / 2 + (x - 80) * scale, height / 2 + (y - 48) * scale
        if not (3 <= cx < width - 3 and 3 <= cy < height - 3):
            raise AssertionError(f"preregistered ROI cropped: {name}, {(width, height)}")
        colors = [rows[py][px * 3:px * 3 + 3] for py in range(round(cy) - 2, round(cy) + 2)
                  for px in range(round(cx) - 2, round(cx) + 2)]
        result["pixels"][name] = [sum(rgb[c] for rgb in colors) / len(colors) for c in range(3)]
    return result


class SceneStaticModelCullFixtureTests(unittest.TestCase):
    def test_actual_reader_preserves_eight_parts_with_opposite_winding(self):
        swiftc = shutil.which("swiftc")
        if not swiftc:
            self.skipTest("swiftc is unavailable")
        _, entries, cases = fixture_entries()
        with tempfile.TemporaryDirectory(prefix="mwx-model-cull-reader-") as temporary:
            root = Path(temporary)
            source, binary, model = root / "Harness.swift", root / "reader", root / "cases.mdl"
            source.write_text(reader.HARNESS)
            model.write_bytes(entries["models/cases.mdl"])
            built = subprocess.run([swiftc, *map(str, reader.SWIFT_SOURCES), str(source),
                "-module-cache-path", str(root / "cache"), "-o", str(binary)],
                capture_output=True, text=True, timeout=90)
            self.assertEqual(built.returncode, 0, built.stderr)
            result = subprocess.run([str(binary), str(model)], capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            row = json.loads(result.stdout)[0]
        self.assertTrue(row["ok"], row)
        self.assertEqual(len(row["parts"]), 8)
        for index, (part, case) in enumerate(zip(row["parts"], cases)):
            self.assertEqual(part["material"], case["material"])
            a, b, c = [part["positions"][i] for i in part["indices"][:3]]
            area = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
            self.assertGreater(area if case["reverse"] else -area, 0)
            self.assertEqual(case["rayHitParts"], [index])


class SceneStaticModelCullAppTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        configured = os.environ.get("MWX_SCENE_INTEGRATION_APP")
        if not configured:
            raise unittest.SkipTest("requires immutable MWX_SCENE_INTEGRATION_APP")
        app = Path(configured).resolve(strict=True)
        cls.exe = app / "Contents/MacOS/MyWallpaperX" if app.suffix == ".app" else app
        cls.app_identity, cls.source_identity = app_hashes(cls.exe), file_hashes(SOURCES)
        parent = os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE")
        if parent:
            Path(parent).mkdir(parents=True, exist_ok=True)
        cls.root = Path(tempfile.mkdtemp(prefix="model-cull-app-", dir=parent))
        cls.runs = {}
        print(f"static model cull evidence: {cls.root}", flush=True)

    def run_case(self, name, *, fixed_scene_time=None, **options):
        if name in self.runs:
            return self.runs[name]
        work = self.root / name
        (work / "content").mkdir(parents=True)
        (work / "home").mkdir()
        scene, entries, cases = fixture_entries(**options)
        named_model_case = (options.get("effect_role_case") or options.get("image_model_case")
                            or options.get("named_extent_case"))
        project = {"type": "scene", "file": "scene.json"}
        (work / "content/project.json").write_bytes(
            json.dumps(project).encode() if named_model_case else encoded(project))
        (work / "content/scene.pkg").write_bytes(make_package(list(entries.items())))
        inputs = tuple((work / "content").iterdir())
        identity = {"app": self.app_identity, "sources": self.source_identity,
            "inputs": file_hashes(inputs), "entries": {
                key: hashlib.sha256(data).hexdigest() for key, data in entries.items()}}
        (work / "scene-input.json").write_bytes(encoded(scene))
        (work / "preregistration.json").write_bytes(encoded({"canvas": CANVAS, "cases": cases,
            "tolerance": TOLERANCE,
            "colorVisibleRGB": ({case["name"]: case["rgba"] for case in cases}
                if any(options.get(key) for key in ("texture_case", "affine_case", "normal_case", "opacity_case", "hdr_case", "brightness_case")) else [0, 200, 0]), "healthyRGB": [0, 0, 255],
            "shadowDarkeningMinimum": 20, "unoccludedReceiverMinimum": 50,
            "oracle": "each z20 quad shadows only its x-12 receiver point; cull closes both color and shadow",
            "evidenceBoundary": "owned static MDL cull cases, no official pixel parity",
            **({"fixedSceneTime": fixed_scene_time, "selectedFrame": options["frame_phase"]}
               if fixed_scene_time is not None else {}),
            **({"colorVisibleRGB": None, "noise": {"case": options["noise_case"],
                "sampling": "nearest-repeat", "physicalProbeRule": "PNG/main center + X0..3 and Y1..3; dark iff (x+y) even",
                "expectedMinimumDarkBrightChannelGap": 4,
                "fullImageOracle": "atlas equals independent crop, no snapshot scaling"}}
               if options.get("noise_case") else {}),
            **({"affine": {"case": options["affine_case"], "filter": "nearest-clamp",
                "skewProbeSourceTexels": ([[2, 2], [4, 2], [3, 4], [5, 4]]
                    if options["affine_case"] == "skew" else None),
                "scope": "skew literal color/hole/shadow probes only; rot90/mirror compare independent crops"}}
               if options.get("affine_case") else {}),
            **({"normalConsumer": {"case": options["normal_case"], "receivesLighting": False,
                "viewTint": None, "reflectivity": 0, "holeRGB": [0, 0, 200],
                "depthOracle": "later far z10 blue remains behind opaque z20 subject and appears through its hole",
                "shadowOracle": "opaque source darkens x-12 receiver; alpha hole preserves lit receiver",
                "wholeImageOracle": "singular plane equals nonsingular control within the same axis/parent pair"}}
               if options.get("normal_case") else {}),
            **({"opacity": {"case": options["opacity_case"], "shader": "genericimage2",
                "alpha": 1 if options["opacity_case"] == "opacity-control" else 1e300,
                "independentCaster": {"layer": 5, "color": [110, 48], "receiver": [98, 48]},
                "noCastScope": "only independent caster color/shadow and blue peer; no subject restoration claim",
                "wholeImageOracle": "huge and renamed huge equal alpha1 control after projection"}}
               if options.get("opacity_case") else {}),
            **({"colorVisibleRGB": None, "hdr": {"case": options["hdr_case"], "opacity": 1/1024,
                "sourceByte": 255 if options["hdr_case"] == "hdr-control" else 1,
                "materialColor": 514 if options["hdr_case"] == "hdr-control" else 131072,
                "fragmentPMA": [257/512]*3, "storedAlpha": 1/1024,
                "wholeImageOracle": "high color/low texel and actual renamed variant equal safe color/white texel",
                "compositeBoundary": "same opacity/background; no PMA versus different-alpha comparison"}}
               if options.get("hdr_case") else {}),
            **({"brightness": {"case": options["brightness_case"], "hdr": False,
                "value": (1 if options["brightness_case"] == "brightness-one" else
                    "1e300" if options["brightness_case"] == "brightness-renamed" else 1e300),
                "wholeImageOracle": "unused brightness preserves colour, alpha holes, shadow and peer",
                "numericProducerVariant": "renamed resources use an authored numeric string"}}
               if options.get("brightness_case") else {}),
            **({"colorVisibleRGB": cases[0]["expectedRGB"], "healthyRGB": None,
                "tolerance": cases[0]["tolerance"], "receiverProbe": [140, 48],
                "receiverRGB": cases[0]["receiverRGB"],
                "oracle": "model at80,48 consumes dim provider; its shadow is60,48; independent receiver is140,48",
                "evidenceBoundary": "owned effectful named provider and MDL colour/shadow; no official parity",
                ("namedExtent" if options.get("named_extent_case") else
                    "effectRole" if options.get("effect_role_case") else "imageModel"): {
                    "case": named_model_case, "effectPath": cases[0]["effectPath"],
                    "provider": cases[0].get("providerID", 11), "model": 2,
                    "slot0": f"_rt_imageLayerComposite_{cases[0].get('providerID', 11)}_a",
                    "providerImagePath": cases[0].get("imageModelPath"),
                    "oracle": "same effect result reaches model colour; receiver/shadow unchanged",
                    "publication": "actual Program material -> named-publication-only -> model binding; no raw-capture log requirement",
                    "identityLimit": "model source token may differ after named publication; no unobserved copy or uniform readback claim"}}
               if named_model_case else {})}))
        command = [str(self.exe), "--mwx-debug-scene-root", str(work / "content"),
            "--mwx-debug-scene-duration", "6", "--mwx-debug-scene-evidence-dir", str(work / "evidence")]
        (work / "prerun.json").write_bytes(encoded({**identity, "command": command}))
        self.assertEqual(app_hashes(self.exe), self.app_identity)
        self.assertEqual(file_hashes(SOURCES), self.source_identity)
        env = {key: value for key, value in os.environ.items()
               if not key.startswith(("MWX_SCENE_DEBUG_", "MYWALLPAPERX_SCENE_DEBUG_"))}
        env.update(HOME=str(work / "home"), CFFIXED_USER_HOME=str(work / "home"),
            MWX_SCENE_DEBUG_SURFACE_COUNT="1", MWX_SCENE_GENERIC_SHADER_CACHE=str(work / "cache"))
        if fixed_scene_time is not None:
            env["MYWALLPAPERX_SCENE_DEBUG_SCENE_TIME"] = str(fixed_scene_time)
        with (work / "app.log").open("w") as output:
            result = subprocess.run(command, cwd=REPO, env=env, stdout=output,
                stderr=subprocess.STDOUT, timeout=90)
        log = (work / "app.log").read_text()
        probes = {"receiver": [140, 48]} if named_model_case else None
        pixels = {phase: measure(work / f"evidence/scene-{phase}-window.png", cases, probes)
                  for phase in ("ready", "after")}
        report = {"exit": result.returncode, "pixels": pixels, "cases": cases,
            "shadowEvents": [line for line in log.splitlines() if "shadow phase=" in line],
            "appAfter": app_hashes(self.exe), "sourcesAfter": file_hashes(SOURCES),
            "inputsAfter": file_hashes(inputs)}
        if named_model_case:
            report["effectRoleCaptures"] = [json.loads(line.split("MWX SCENE COMPOSITION OBSERVATION: ", 1)[1])
                for line in log.splitlines() if "MWX SCENE COMPOSITION OBSERVATION: " in line]
        if options.get("named_extent_case"):
            report["bandProbes"] = {}
            for phase in ("ready", "after"):
                width, height, rows = png_rgb_pixels(work / f"evidence/scene-{phase}-window.png")
                scale = max(width / CANVAS[0], height / CANVAS[1])
                points = [(round(width / 2 + (x - 80) * scale),
                           round(height / 2 + (y - 48) * scale)) for x, y in cases[0]["bandPoints"]]
                report["bandProbes"][phase] = [list(rows[y][x * 3:x * 3 + 3]) for x, y in points]
        if options.get("noise_case"):
            report["noiseProbes"] = {}
            for phase in ("ready", "after"):
                width, height, rows = png_rgb_pixels(work / f"evidence/scene-{phase}-window.png")
                request = re.search(rf"phase=snapshot reason={phase} request=(\d+) source=metal ", log)
                extent = re.search(rf"phase=snapshot-encoded request={request[1]} [^\n]* width=(\d+) height=(\d+)", log)
                self.assertEqual((width, height), tuple(map(int, extent.groups())))
                # Averaging the ordinary ROI would hide the two-pixel noise period.
                x, y = width // 2, height // 2
                points = [(x + i, y) for i in range(4)] + [(x, y + i) for i in range(1, 4)]
                report["noiseProbes"][phase] = [{"pixel": [px, py], "dark": (px + py) % 2 == 0,
                    "rgb": list(rows[py][px * 3:px * 3 + 3])} for px, py in points]
        (work / "result.json").write_bytes(encoded(report))
        self.assertEqual(result.returncode, 0, log[-6000:])
        for key, expected in (("appAfter", self.app_identity), ("sourcesAfter", self.source_identity),
                              ("inputsAfter", identity["inputs"])):
            self.assertEqual(report[key], expected)
        self.assertRegex(log, r"state=completed frame=1 surface=\d+ gpu=completed")
        self.assertRegex(log, r"state=completed frame=2 surface=\d+ gpu=completed")
        self.assertIn("gpuDrained=true", log)
        self.assertNotRegex(log, r"phase=launch-failed|phase=snapshot-(?:failed|rejected)|failure=exception")
        preview = (work / "evidence/scene-preview.log").read_text()
        if options.get("texture_case") != "animated" and not any(
                options.get(key) for key in ("affine_case", "normal_case", "opacity_case", "hdr_case")):
            expected_prepared = ("[1, 2]" if named_model_case else
                "[1, 4]" if options.get("texture_case") == "zero" else "[1, 2, 4]")
            self.assertIn("prepared static model layers: " + expected_prepared, preview)
        self.assertEqual(pixels["ready"], pixels["after"])
        for phase in ("ready", "after"):
            if named_model_case:
                self.assert_rgb(pixels[phase]["pixels"]["receiver"], cases[0]["receiverRGB"],
                    delta=cases[0]["tolerance"])
            else:
                self.assert_rgb(pixels[phase]["pixels"]["healthy"], [0, 0, 255])
                self.assertGreater(min(pixels[phase]["pixels"]["clear"]), 50)
            self.assertRegex(log, rf"phase=snapshot reason={phase} request=\d+ source=metal ")
        if named_model_case:
            self.assertIn("phase=named-target-binding layer=2 status=succeeded", log)
        self.runs[name] = report
        return report

    def assert_rgb(self, actual, expected, *, delta=TOLERANCE):
        for value, wanted in zip(actual, expected):
            self.assertAlmostEqual(value, wanted, delta=delta)

    def assert_texture_coverage(self, result, *, hole_rgb=None):
        for phase in ("ready", "after"):
            reference = result["pixels"][phase]["pixels"]
            for case in result["cases"]:
                color, shadow = f"{case['name']}-color", f"{case['name']}-shadow"
                if case["visible"]:
                    self.assert_rgb(reference[color], case["rgba"][:3])
                    self.assertLess(max(reference[shadow]), 15)
                else:
                    self.assert_rgb(reference[color], hole_rgb if hole_rgb is not None else reference["clear"])
                    self.assert_rgb(reference[shadow], reference["clear"])

    def test_authored_cull_controls_color_and_shadow_per_material(self):
        on = self.run_case("authored-on")
        off = self.run_case("authored-off", cast=False)
        two_sided = self.run_case("two-sided-control", all_nocull=True)
        for phase in ("depth-written", "receiver", "completed"):
            self.assertTrue(any(f"phase={phase} " in line for line in on["shadowEvents"]), phase)
        for phase in ("ready", "after"):
            active, disabled, control = [row["pixels"][phase]["pixels"] for row in (on, off, two_sided)]
            self.assertEqual(active["healthy"], disabled["healthy"])
            self.assertEqual(active["healthy"], control["healthy"])
            for case in on["cases"]:
                color, shadow = f"{case['name']}-color", f"{case['name']}-shadow"
                self.assert_rgb(control[color], [0, 200, 0])
                self.assertEqual(active[color], disabled[color], case)
                self.assertGreater(min(disabled[shadow]), 50, case)
                if case["visible"]:
                    self.assert_rgb(active[color], [0, 200, 0])
                    self.assert_rgb(active[color], control[color])
                    self.assert_rgb(active[shadow], control[shadow])
                    for channel in range(3):
                        self.assertGreater(disabled[shadow][channel] - active[shadow][channel], 20, case)
                else:
                    self.assert_rgb(active[color], active["clear"])
                    self.assert_rgb(active[shadow], disabled[shadow])
                    for channel in range(3):
                        self.assertGreater(active[shadow][channel] - control[shadow][channel], 20, case)


    def test_single_static_frame_matches_crop_with_color_holes_and_shadow(self):
        crop = self.run_case("texture-crop-control", texture_case="crop")
        self.assert_texture_coverage(crop)
        for texture_case in ("frame", "multi"):
            name = "texture-single-frame" if texture_case == "frame" else "texture-multi-frame"
            framed = self.run_case(name, texture_case=texture_case)
            for phase in ("ready", "after"):
                self.assertEqual(crop["pixels"][phase], framed["pixels"][phase])
        rejected = self.run_case("texture-rejected-zero", texture_case="zero")
        for phase in ("ready", "after"):
            pixels = rejected["pixels"][phase]["pixels"]
            for case in rejected["cases"]:
                self.assert_rgb(pixels[f"{case['name']}-color"], pixels["clear"])
                self.assert_rgb(pixels[f"{case['name']}-shadow"], pixels["clear"])

    def test_animated_albedo_frames_match_crops_with_color_holes_and_shadow(self):
        for frame, scene_time in enumerate((.25, 2.25)):
            crop = self.run_case(f"albedo-frame-{frame}-crop", texture_case="crop",
                frame_phase=frame, fixed_scene_time=scene_time)
            self.assert_texture_coverage(crop)
            animated = self.run_case(f"albedo-frame-{frame}-animated", texture_case="animated",
                frame_phase=frame, fixed_scene_time=scene_time)
            for phase in ("ready", "after"):
                self.assertEqual(crop["pixels"][phase], animated["pixels"][phase])

    def test_noise_atlas_frame_matches_crop_at_adjacent_physical_pixels(self):
        crop = self.run_case("noise-crop-control", noise_case="crop")
        for phase in ("ready", "after"):
            probes = crop["noiseProbes"][phase]
            dark, bright = [[p["rgb"] for p in probes if p["dark"] == value] for value in (True, False)]
            for channel in range(3):
                self.assertGreater(min(p[channel] for p in bright) - max(p[channel] for p in dark), 3)
            for case in crop["cases"]:
                self.assertLess(max(crop["pixels"][phase]["pixels"][f"{case['name']}-shadow"]), 15)
        atlas = self.run_case("noise-atlas-frame", noise_case="atlas")
        self.assertEqual(crop["noiseProbes"], atlas["noiseProbes"])
        for phase in ("ready", "after"):
            name = f"evidence/scene-{phase}-window.png"
            self.assertEqual((self.root / "noise-crop-control" / name).read_bytes(),
                             (self.root / "noise-atlas-frame" / name).read_bytes())


    def test_affine_albedo_frames_preserve_color_holes_and_shadow(self):
        for transform in ("rot90", "mirror"):
            crop_name, frame_name = f"{transform}-crop", f"{transform}-frame"
            crop = self.run_case(crop_name, affine_case=crop_name)
            self.assert_texture_coverage(crop)
            atlas = self.run_case(frame_name, affine_case=frame_name)
            self.assert_texture_coverage(atlas)
            for phase in ("ready", "after"):
                name = f"evidence/scene-{phase}-window.png"
                self.assertEqual((self.root / crop_name / name).read_bytes(),
                                 (self.root / frame_name / name).read_bytes())
        self.assert_texture_coverage(self.run_case("skew-frame", affine_case="skew"))


    def test_unused_normal_singular_planes_preserve_color_depth_and_shadow(self):
        for axis in ("xy", "yz"):
            control_name, singular_name = f"{axis}-control", f"{axis}-singular"
            control = self.run_case(control_name, normal_case=control_name)
            self.assert_texture_coverage(control, hole_rgb=[0, 0, 200])
            singular = self.run_case(singular_name, normal_case=singular_name)
            self.assert_texture_coverage(singular, hole_rgb=[0, 0, 200])
            for phase in ("ready", "after"):
                name = f"evidence/scene-{phase}-window.png"
                self.assertEqual((self.root / control_name / name).read_bytes(),
                                 (self.root / singular_name / name).read_bytes())


    def test_material_opacity_preserves_independent_caster_shadow(self):
        control = self.run_case("opacity-control", opacity_case="opacity-control")
        self.assert_texture_coverage(control)
        for name in ("opacity-huge-no-cast", "opacity-huge", "opacity-huge-renamed"):
            result = self.run_case(name, opacity_case=name)
            for phase in ("ready", "after"):
                pixels = result["pixels"][phase]["pixels"]
                self.assert_rgb(pixels["independent-caster-color"], [0, 200, 0])
                self.assertLess(max(pixels["independent-caster-shadow"]), 15)
            if name == "opacity-huge-no-cast":
                continue
            self.assert_texture_coverage(result)
            for phase in ("ready", "after"):
                png = f"evidence/scene-{phase}-window.png"
                self.assertEqual((self.root / "opacity-control" / png).read_bytes(),
                                 (self.root / name / png).read_bytes())


    def test_hdr_color_intermediates_match_safe_texture_control(self):
        control = self.run_case("hdr-control", hdr_case="hdr-control")
        for phase in ("ready", "after"):
            pixels = control["pixels"][phase]["pixels"]
            for case in control["cases"]:
                rgb = pixels[f"{case['name']}-color"]
                self.assertGreater(min(rgb) - max(pixels["clear"]), 100)
                self.assertLess(max(rgb), 250)
                self.assertLess(max(rgb)-min(rgb), TOLERANCE)
                self.assert_rgb(pixels[f"{case['name']}-shadow"], pixels["clear"])
        for name in ("hdr-high", "hdr-renamed"):
            self.run_case(name, hdr_case=name)
            for phase in ("ready", "after"):
                png = f"evidence/scene-{phase}-window.png"
                self.assertEqual((self.root / "hdr-control" / png).read_bytes(),
                                 (self.root / name / png).read_bytes())


    def test_hdr_disabled_brightness_preserves_color_holes_and_shadow(self):
        control = self.run_case("brightness-one", brightness_case="brightness-one")
        self.assert_texture_coverage(control)
        for name in ("brightness-huge", "brightness-renamed"):
            result = self.run_case(name, brightness_case=name)
            self.assert_texture_coverage(result)
            for phase in ("ready", "after"):
                png = f"evidence/scene-{phase}-window.png"
                self.assertEqual((self.root / "brightness-one" / png).read_bytes(),
                                 (self.root / name / png).read_bytes())


    def test_explicit_effect_role_reaches_named_model_albedo(self):
        for name in ("role-standard", "role-explicit", "role-renamed"):
            result = self.run_case(name, effect_role_case=name)
            self.assert_effect_role_result(result)
            for phase in ("ready", "after"):
                png = f"evidence/scene-{phase}-window.png"
                self.assertEqual((self.root / "role-standard" / png).read_bytes(), (self.root / name / png).read_bytes())

    def test_explicit_effect_in_material_directory_reaches_named_model_albedo(self):
        result = self.run_case("role-material-directory", effect_role_case="role-material-directory")
        self.assert_effect_role_result(result)

    def test_explicit_image_model_role_reaches_named_model_albedo(self):
        for name in ("image-model-standard", "image-model-outside", "image-model-renamed"):
            result = self.run_case(name, image_model_case=name)
            self.assert_effect_role_result(result)
            for phase in ("ready", "after"):
                png = f"evidence/scene-{phase}-window.png"
                self.assertEqual((self.root / "image-model-standard" / png).read_bytes(),
                                 (self.root / name / png).read_bytes())

    def test_named_graph_raster_is_independent_of_provider_world_scale(self):
        results = {}
        for name in ("extent-local", "extent-scaled", "extent-parent-renamed"):
            result = self.run_case(name, named_extent_case=name)
            results[name] = result
            for phase in ("ready", "after"):
                for actual, expected in zip(result["bandProbes"][phase], result["cases"][0]["bandRGB"], strict=True):
                    self.assert_rgb(actual, expected)
                self.assert_rgb(result["pixels"][phase]["pixels"]["caster-shadow"],
                    result["cases"][0]["expectedShadowRGB"], delta=result["cases"][0]["tolerance"])
                path = f"evidence/scene-{phase}-window.png"
                self.assertEqual((self.root / "extent-local" / path).read_bytes(),
                                 (self.root / name / path).read_bytes())
        # Check the actual texture product only after old scaled pixels can falsify the change.
        for result in results.values():
            provider = result["cases"][0]["providerID"]
            self.assertEqual({p["captureRequestID"] for p in result["effectRoleCaptures"]}, {1, 2})
            for packet in result["effectRoleCaptures"]:
                self.assertEqual((packet["gpuStatus"], packet["truncatedRows"]), ("completed", 0))
                rows = packet["rows"]
                capture = next(r for r in rows if r["kind"] == "sourceCapture" and r.get("layerID") == provider)
                material = next(r for r in rows if r["kind"] == "material" and r.get("layerID") == provider)
                published = next(r for r in rows if r["kind"] == "tail-consume" and r.get("layerID") == provider)
                model = next(r for r in rows if r["kind"] == "model" and r.get("layerID") == 2)
                seal = next(r for r in rows if r["kind"] == "frame-seal")
                for texture in (capture["source"], capture["target"], material["target"],
                                published["source"], model["source"]):
                    self.assertEqual([texture["width"], texture["height"]], [384, 192])
                self.assertEqual((material["outcome"], published["access"], model["outcome"], seal["outcome"]),
                    ("draw-encoded", "named-publication-only", "draw-encoded", "sealed"))
                self.assertEqual(material["target"]["textureToken"], published["source"]["textureToken"])
                self.assertEqual(model["target"]["textureToken"], seal["target"]["textureToken"])

    def assert_effect_role_result(self, result):
        case = result["cases"][0]
        for phase in ("ready", "after"):
            pixels = result["pixels"][phase]["pixels"]
            self.assert_rgb(pixels["caster-color"], case["expectedRGB"], delta=case["tolerance"])
            self.assert_rgb(pixels["caster-shadow"], case["expectedShadowRGB"], delta=case["tolerance"])
        self.assertEqual({p["captureRequestID"] for p in result["effectRoleCaptures"]}, {1, 2})
        for packet in result["effectRoleCaptures"]:
            self.assertEqual(packet["gpuStatus"], "completed")
            self.assertEqual(packet["truncatedRows"], 0)
            rows = packet["rows"]
            material = next(row for row in rows if row["kind"] == "material" and row.get("layerID") == 11)
            publication = next(row for row in rows if row["kind"] == "tail-consume" and row.get("layerID") == 11)
            model = next(row for row in rows if row["kind"] == "model" and row.get("layerID") == 2)
            seal = next(row for row in rows if row["kind"] == "frame-seal")
            self.assertEqual((material["outcome"], publication["access"], model["outcome"], seal["outcome"]),
                ("draw-encoded", "named-publication-only", "draw-encoded", "sealed"))
            self.assertEqual(material["target"]["textureToken"], publication["source"]["textureToken"])
            self.assertEqual(model["target"]["textureToken"], seal["target"]["textureToken"])


if __name__ == "__main__":
    unittest.main()
