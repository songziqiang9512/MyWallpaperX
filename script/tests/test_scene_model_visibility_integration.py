"""Prepared static model/image cohorts reach real same-window Metal pixels.

Static show/hide controls supply independent visual references. All MDL, PNG,
material and scene bytes are owned fixtures; this does not establish official
model/shadow parity, animated model support or named-provider readiness.
"""
from pathlib import Path
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import tempfile
import unittest

from script.web_benchmark_capture import png_rgb_pixels
from script.scene_wallpaper_graph_output_metrics import (
    structured_runtime_observations, terminal_composition_snapshot,
)
from .test_scene_composition_authored_order_integration import encoded, measure_capture
from .test_scene_directional_shadow_integration import fixture_entries as shadow_fixture, png, quad
from .test_scene_fullscreen_visibility_integration import app_hashes, file_hashes
from .test_scene_static_model_reader import build_model
from script.tests.support.scene_pkg_fixture import make_package


CANVAS = (160, 96)
TOLERANCE = 4
RECTS = {"shadow": (58, 46, 62, 50), "caster": (78, 46, 82, 50),
         "receiver": (138, 46, 142, 50), "ownFalse": (130, 46, 134, 50),
         "image": (36, 70, 44, 78), "peer": (132, 70, 140, 78)}
SOURCES = (Path(__file__), Path(__file__).with_name("test_scene_directional_shadow_integration.py"),
           Path(__file__).with_name("test_scene_static_model_reader.py"),
           Path(__file__).with_name("scene_pkg_fixture.py"),
           Path(__file__).with_name("test_scene_fullscreen_visibility_integration.py"),
           Path(__file__).with_name("test_scene_composition_authored_order_integration.py"),
           Path(__file__).parents[1] / "scene_wallpaper_graph_output_metrics.py",
           Path(__file__).parents[1] / "web_benchmark_capture.py")


def fixture_entries(*, control=None, bad_model=False):
    # The existing owned fixture casts toward +X,+Z. Local caster X50..70
    # plus the ordinary parent's +20 produces world X70..90 and shadow X50..70.
    scene, entries = shadow_fixture(caster_x=50, parent_offset=20)
    caster = next(layer for layer in scene["objects"] if layer["id"] == 2)
    visibility = ({"user": {"name": "mode", "condition": "shown"}, "value": True}
                  if control is None else control)
    caster.update(name="Owned conditional model", visible=visibility)
    scene["objects"] += [
        {"id": 5, "name": "Owned model child remains individually false", "parent": 6,
         "model": "models/own_false.mdl", "origin": "0 96 0", "perspective": False,
         "visible": False, "castshadow": True},
        {"id": 9, "name": "Independent black image plate", "image": "models/own_solid.json",
         "origin": "40 24 0", "size": "20 20", "color": "0 0 0"},
        {"id": 10, "name": "Owned ordinary image in the same combo cohort",
         "image": "models/own_blue.json", "origin": "40 24 0", "size": "16 16",
         "visible": visibility},
        {"id": 30, "name": "Independent healthy green peer", "image": "models/own_solid.json",
         "origin": "136 24 0", "size": "16 16", "color": "0 1 0"}]
    entries.update({
        "models/own_false.mdl": quad(104, 120, 38, 58, 30, "materials/own_red.json"),
        "materials/own_red.json": encoded({"passes": [{"shader": "genericimage",
            "textures": ["materials/own_red.png"], "combos": {"LIGHTING": 0},
            "blending": "normal", "cullmode": "nocull", "depthtest": "enabled", "depthwrite": "enabled"}]}),
        "materials/own_red.png": png([255, 0, 0, 255]),
        "models/own_solid.json": encoded({"solidlayer": True, "width": 160, "height": 96}),
        "models/own_blue.json": encoded({"material": "materials/own_blue.json"}),
        "materials/own_blue.json": encoded({"passes": [{"shader": "genericimage", "textures": ["materials/own_blue.png"]}]}),
        "materials/own_blue.png": png([0, 0, 255, 255])})
    if bad_model:
        entries["models/caster.mdl"] = b"OWNED_INVALID_MDL\x00"
    entries["scene.json"] = encoded(scene)
    project = {"type": "scene", "file": "scene.json", "general": {"properties": {
        "mode": {"type": "combo", "value": "shown", "options": [
            {"label": value, "value": value} for value in ("hidden", "shown")]}}}}
    return project, entries


def measure(path):
    decoded = png_rgb_pixels(path)
    if decoded is None:
        raise AssertionError(f"invalid PNG: {path}")
    width, height, rows = decoded
    scale = max(width / CANVAS[0], height / CANVAS[1])
    def point(x, y):
        return ((x - CANVAS[0] / 2) * scale + width / 2,
                (y - CANVAS[1] / 2) * scale + height / 2)
    rois = {}
    for name, rect in RECTS.items():
        left, top = point(*rect[:2]); right, bottom = point(*rect[2:])
        if not (0 <= left < right <= width and 0 <= top < bottom <= height):
            raise AssertionError(f"preregistered ROI cropped: {name}, {(width, height)}")
        colors = [tuple(rows[y][x * 3:x * 3 + 3]) for y in range(math.ceil(top), math.floor(bottom))
                  for x in range(math.ceil(left), math.floor(right))]
        if not colors:
            raise AssertionError(f"empty ROI: {name}")
        expected = (0, 255, 0) if name == "peer" else None
        rois[name] = {"mean": [sum(rgb[c] for rgb in colors) / len(colors) for c in range(3)],
                      "total": len(colors), "greenFraction": sum(
                          max(abs(a - b) for a, b in zip(rgb, expected)) <= TOLERANCE
                          for rgb in colors) / len(colors) if expected else None}
    red_count = sum(row[x] >= 251 and row[x + 1] <= 4 and row[x + 2] <= 4
                    for row in rows for x in range(0, width * 3, 3))
    return {"dimensions": [width, height], "rois": rois, "redCount": red_count}


def model_subtree_fixture(preset="composition-depth"):
    """Owned model geometry, constant-color oracles and original group Program."""
    if preset.startswith("model-parent-"):
        return model_parent_visibility_fixture(preset)
    if preset not in ("composition-depth", "project-trs-renamed", "model-leaf-cycle"):
        raise ValueError(preset)
    renamed, live = preset == "project-trs-renamed", preset == "model-leaf-cycle"
    ids = {value: value + 800 if renamed else value for value in
           (20, 21, 22, 23, 24, 25, 26, 27, 30, 31, 40, 41, 42, 43, 44, 45, 47, 60)}
    stem = "moved_prism" if renamed else "own_model_cycle"
    utility = f"models/util/{'project' if renamed else 'compose'}layer.json"
    effect = f"effects/{stem}/effect.json"
    trs = {"angles": f"0 0 {math.pi / 2 if renamed else 0}",
           "scale": "-1.5 .75 1" if renamed else "1 1 1"}
    entries = {utility: encoded({"width": 200, "height": 120, "autosize": False}),
        f"models/{stem}_solid.json": encoded({"solidlayer": True, "width": 640, "height": 480}),
        effect: encoded({"passes": [{"material": f"materials/{stem}/cycle.json"}]}),
        f"materials/{stem}/cycle.json": encoded({"passes": [{"shader": stem, "textures": [None],
            "blending": "normal", "depthtest": "disabled", "depthwrite": "disabled", "cullmode": "nocull"}]})}
    uv, sample = ("v_Shifted", "pixelValue") if renamed else ("v_TexCoord", "c")
    entries[f"shaders/{stem}.vert"] = (f"attribute vec3 a_Position;attribute vec2 a_TexCoord;"
        f"varying vec2 {uv};void main(){{gl_Position=vec4(a_Position,1.0);{uv}=a_TexCoord;}}").encode()
    entries[f"shaders/{stem}.frag"] = (f"uniform sampler2D g_Texture0;varying vec2 {uv};"
        f"void main(){{vec4 {sample}=texSample2D(g_Texture0,{uv});"
        f"gl_FragColor=vec4({sample}.gbr,{sample}.a);}}").encode()

    def group(identifier, name):
        return {"id": ids[identifier], "name": name, "image": utility, "origin": "160 240 0",
                "size": "200 120", "copybackground": False, "visible": True, **trs,
                "effects": [{"id": ids[identifier] * 10, "file": effect, "visible": True}]}

    def material(name, rgb, *, alpha=1, writes=True, tint=False):
        path = f"materials/{stem}/{name}.json"
        image = f"materials/{stem}/{name}.png"
        constants = {"alpha": alpha}
        if tint:
            constants.update(tintfront=".2 .4 .6", tintback={"value": ".8 .1 .2",
                "scriptproperties": {},
                "script": "export function update(value){return new Vec3(.2,.4,.6);}"})
        entries[path] = encoded({"passes": [{"shader": "genericimage", "textures": [image],
            "combos": {"LIGHTING": 0}, "blending": "normal" if alpha == 1 else "translucent",
            "depthtest": "enabled", "depthwrite": "enabled" if writes else "disabled",
            "cullmode": "normal" if renamed else "nocull", "constantshadervalues": constants}]})
        entries[image] = png([*rgb, 255])
        return path

    def model(identifier, parent, bounds, z, paint, *, tint=False, visible=True, child_mirror=None):
        path = f"models/{stem}/{identifier}.mdl"
        x0, y0, x1, y1 = bounds
        if tint:
            # A valid authored grazing normal makes the back tint visible.
            # Front equals the script result, so the successful RGB oracle is
            # constant even away from the exact center; authored fallback differs.
            vertices = [((x, y, z), (0., 1., 0.), (1., 0., 0., 1.), texture_uv)
                        for x, y, texture_uv in ((x0, y0, (0., 0.)), (x1, y0, (1., 0.)),
                                                 (x1, y1, (1., 1.)), (x0, y1, (0., 1.)))]
            entries[path] = build_model(vertices=vertices, indices=(0, 2, 1, 0, 3, 2),
                bounds=(x0, y0, z, x1, y1, z), material=paint.encode())
        else:
            entries[path] = quad(x0, x1, y0, y1, z, paint)
        mirrored = renamed if child_mirror is None else child_mirror
        return {"id": ids[identifier], "name": f"Owned {stem} model {identifier}", "parent": ids[parent],
                "model": path, "origin": "0 0 0", "scale": "-1 -1 1" if mirrored else "1 -1 1",
                "perspective": False, "visible": visible, "castshadow": False}

    parent = group(20, "Owned prepared model group")
    ordinary = {"id": ids[40], "name": "Literal ordinary transform parent",
                "origin": "480 240 0", "visible": True, **trs}
    main_models, reference_models = [], []
    local_rois, expected, group_models = {}, {}, []
    visibility_key = "prepared_model_leaf"
    if live:
        paint = material("script_back_tint", (255, 255, 255), tint=True)
        leaf = model(21, 20, (-40, -16, 40, 16), 20, paint, tint=True,
                     visible={"user": visibility_key, "value": True})
        main_models = [leaf]
        reference_models = [model(41, 40, (-40, -16, 40, 16), 20,
                                 material("literal_post_cycle", (102, 153, 51)))]
        local_rois = {"scriptTint": (-5, -5, 5, 5), "modelOutside": (60, -5, 68, 5)}
        expected = {"scriptTint": [102, 153, 51], "modelOutside": [0, 0, 0]}
        group_models = [ids[21]]
    else:
        red, blue = material("red", (255, 0, 0)), material("blue", (0, 0, 255))
        half_red = material("half_red_nonwriting", (255, 0, 0), alpha=.5, writes=False)
        literal_blue, literal_green = material("literal_blue", (0, 0, 255)), material("literal_green", (0, 255, 0))
        literal_half_blue = material("literal_half_blue_nonwriting", (0, 0, 255), alpha=.5, writes=False)
        opaque, nonwriting = (-80, -20, -40, 20), (-20, -20, 20, 20)
        far_nonwriting, separate = (-10, -20, 20, 20), (50, -20, 80, 20)
        main_models = [model(21, 20, opaque, 20, red), model(22, 20, opaque, 0, blue),
            model(23, 20, nonwriting, 40, half_red), model(24, 20, far_nonwriting, 0, blue),
            model(25, 20, separate, 60, red)]
        reference_models = [model(41, 40, opaque, 20, literal_blue), model(42, 40, opaque, 0, literal_green),
            model(43, 40, nonwriting, 40, literal_half_blue), model(44, 40, far_nonwriting, 0, literal_green),
            model(45, 40, separate, -60, red)]
        bad = model(26, 20, (-6, 34, 6, 46), 20, red)
        entries[bad["model"]] = b"OWNED_INVALID_MODEL\x00"
        main_models.append(bad)
        group_models = [ids[i] for i in (21, 22, 23, 24, 25)]
        group_models_two = [model(31, 30, separate, -60, literal_green)]
        local_rois = {"nearOccludesLaterFar": (-64, -4, -56, 4),
            "nonwritingAllowsLaterFar": (2, -4, 10, 4), "halfAlphaVisible": (-18, -4, -14, 4),
            "independentDepth": (60, -4, 68, 4), "badModelIsLocal": (-3, 37, 3, 43),
            "modelOutside": (88, -4, 94, 4)}
        expected = {"nearOccludesLaterFar": [0, 0, 255], "nonwritingAllowsLaterFar": [0, 255, 0],
            "halfAlphaVisible": [0, 0, 128], "independentDepth": [255, 0, 0],
            "badModelIsLocal": [0, 0, 0], "modelOutside": [0, 0, 0]}
        if renamed:
            magenta = material("single_mirror_culled", (255, 0, 255))
            mirrored_bounds = (-8, -48, 8, -32)
            main_models.append(model(27, 20, mirrored_bounds, 20, magenta, child_mirror=False))
            reference_models.append(model(47, 40, mirrored_bounds, 20, magenta, child_mirror=False))
            group_models.append(ids[27])
            local_rois["singleMirrorCulled"] = (-4, -44, 4, -36)
            expected["singleMirrorCulled"] = [0, 0, 0]

    objects = [parent, *main_models]
    groups = [{"root": ids[20], "modelIDs": group_models}]
    if not live:
        objects += [group(30, "Independent farther model depth group"), *group_models_two]
        groups.append({"root": ids[30], "modelIDs": [ids[31]]})
    objects += [ordinary, *reference_models, {"id": ids[60], "name": "Healthy nonoverlapping green peer",
        "image": f"models/{stem}_solid.json", "origin": "320 100 0", "size": "20 20", "color": "0 1 0"}]
    scene = {"version": 3, "general": {"orthogonalprojection": {"width": 640, "height": 480},
              "clearcolor": "0 0 0", "bloom": False, "cameraparallax": False}, "objects": objects}
    entries["scene.json"] = encoded(scene)
    project = {"type": "scene", "file": "scene.json"}
    sequence = [{visibility_key: False}, {visibility_key: True}] if live else []
    if live:
        project["general"] = {"properties": {visibility_key: {"type": "bool", "value": True}}}

    def rectangle(rect, center_x):
        x0, y0, x1, y1 = rect
        # Literal -90deg parent rotation after (1.5,.75) scale. This is the
        # preregistered input's geometry, not a second general transform helper.
        return ([center_x + .75*y0, 240 - 1.5*x1, center_x + .75*y1, 240 - 1.5*x0]
                if renamed else [center_x+x0, 240+y0, center_x+x1, 240+y1])

    def oracle(shown):
        out = {"healthyPeer": {"canvasRect": [316, 376, 324, 384], "expectedRGB": [0, 255, 0]}}
        for name, rect in local_rois.items():
            for cohort, center in (("group", 160), ("reference", 480)):
                color = expected[name] if cohort == "reference" or shown else [0, 0, 0]
                out[f"{cohort}-{name}"] = {"canvasRect": rectangle(rect, center), "expectedRGB": color}
        return out

    captures = {"scene-ready-window.png": True, "scene-after-window.png": True}
    if live:
        captures["scene-series-0000-window.png"] = False  # interval3.5, between the +2/+4s edits.
    protocol = {"preset": preset, "canvas": [640, 480], "oracle": oracle(True),
        "snapshotOracles": {name: oracle(shown) for name, shown in captures.items()},
        "channelTolerance": TOLERANCE, "minimumCorrectAreaFraction": .99,
        "captureShown": captures, "afterDelay": 6 if live else 3, "sequence": sequence,
        "groups": groups, "referenceModelIDs": [obj["id"] for obj in reference_models],
        "peerID": ids[60], "badModelID": ids[26] if not live else None,
        "visibilityTargetID": ids[21] if live else None, "ownFalseModelIDs": [],
        "parentTransform": {"angle": math.pi/2 if renamed else 0, "scale": [-1.5,.75,1] if renamed else [1,1,1]},
        "mirrorOracle": {"cullMode": "normal", "positive": "parent X negative and child X negative: visible",
            "negative": "parent X negative only: culled", "negativeLayerIDs": [ids[27],ids[47]],
            "reference": "same complete parent and child TRS"} if renamed else None,
        "modelCoordinateConvention": "Child authored Y scale=-1 cancels static-model local Y conversion; parent canonical angle=-authored angle. Project parent X=-1.5 and positive-model child X=-1 cancel, giving literal Rz(-pi/2)S(1.5,.75) footprints; negative-model X interval is symmetric. World Y is PNG canvas Y. Reference uses identical complete TRS and post-GBR literal paints.",
        "depthOracle": "Near normal precedes far normal; half-alpha nonwriter precedes later far normal, with an exposed half-alpha strip. Second same-extent group draws an even farther green model over first group's near red; isolated depth gives final red after GBR. Reference independent-depth patch is the literal final red, without a nearer root blocker.",
        "typedTintBack": {"material": f"materials/{stem}/script_back_tint.json", "authored": [.8,.1,.2],
            "resolved": [.2,.4,.6], "postCycleRGB": [102,153,51], "normal": [0,1,0],
            "front": [.2,.4,.6], "layerColorAuthored": False} if live else None,
        "observation": {"clockModelLayerID": group_models[0], "timelineFields": ["origin", "angles", "scale"],
            "tintBackWitness": "material script input, sole prepared vector binding, no script failure and exact owned pixels; color is not a Timeline observation field"},
        "scope": "Parent group and Program always visible/active; only prepared model leaf changes visibility. Model/model depth only; no image-terminal Z ordering or cold-parent qualification. Internal owned behavior, no official parity."}
    return project, entries, protocol


def model_parent_visibility_fixture(preset):
    """The existing model/Program is controlled through its parent visibility."""
    if preset not in ("model-parent-cycle", "model-parent-cycle-renamed",
                      "model-parent-cold-property", "model-parent-cold-script",
                      "model-parent-cold-script-mutation"):
        raise ValueError(preset)
    project, entries, protocol = model_subtree_fixture("model-leaf-cycle")
    scene = json.loads(entries["scene.json"])
    parent, leaf = [next(x for x in scene["objects"] if x["id"] == i) for i in (20, 21)]
    parent["visible"], leaf["visible"] = leaf["visible"], True
    parent["name"] = "Owned live model-parent visibility group"
    scene["objects"].insert(scene["objects"].index(leaf) + 1, dict(leaf, id=22,
        name="Owned model child stays individually false", origin="64 0 0", visible=False))
    key, ids = "prepared_model_leaf", {i: i for i in (20, 21, 22, 40, 41, 60)}
    if preset == "model-parent-cycle-renamed":
        key, ids = "unseen_parent_group_enabled", {20: 731, 21: 732, 22: 733, 40: 947, 41: 948, 60: 864}
        names = {20: "Renamed live parent capture", 21: "Renamed shaded model card",
            22: "Renamed false model card", 40: "Renamed literal reference parent",
            41: "Renamed literal reference model", 60: "Renamed independent green peer"}
        for layer in scene["objects"]:
            old = layer["id"]
            layer["id"], layer["name"] = ids[old], names[old]
            if "parent" in layer:
                layer["parent"] = ids[layer["parent"]]
            for effect in layer.get("effects", []):
                effect["id"] = layer["id"] * 10
        parent["visible"] = {"user": key, "value": True}
        project["general"]["properties"] = {key: {"type": "bool", "value": True}}
        replacements = {
            "models/own_model_cycle/21.mdl": "models/alternate_model_cycle/unseen_card.mdl",
            "models/own_model_cycle/41.mdl": "models/alternate_model_cycle/literal_card.mdl",
            "materials/own_model_cycle/script_back_tint": "materials/alternate_model_cycle/unseen_back_tone",
            "materials/own_model_cycle/literal_post_cycle": "materials/alternate_model_cycle/literal_post_tone",
            "materials/own_model_cycle/cycle.json": "materials/alternate_model_cycle/color_roll.json",
            "own_model_cycle": "alternate_model_cycle"}
        def renamed(value):
            for before, after in replacements.items():
                value = value.replace(before.encode(), after.encode())
            return value
        scene = json.loads(renamed(encoded(scene)))
        entries = {renamed(name.encode()).decode(): renamed(data) for name, data in entries.items()
                   if name != "scene.json"}
        entries["shaders/alternate_model_cycle.vert"] = entries["shaders/alternate_model_cycle.vert"].replace(
            b"v_TexCoord", b"v_AlternateUV")
        entries["shaders/alternate_model_cycle.frag"] = (
            b"uniform sampler2D g_Texture0;varying vec2 v_AlternateUV;"
            b"void main(){vec4 sampledPixel=texSample2D(g_Texture0,v_AlternateUV);"
            b"gl_FragColor=vec4(sampledPixel.g,sampledPixel.b,sampledPixel.r,sampledPixel.a);}")
        material_path = "materials/alternate_model_cycle/unseen_back_tone.json"
        material = json.loads(entries[material_path])
        material["passes"][0]["constantshadervalues"]["tintback"]["script"] = (
            "export function update(previousTint){let unit=1/5;return new Vec3(unit,unit*2,unit*3);}")
        entries[material_path] = encoded(material)
        protocol["typedTintBack"]["material"] = material_path
    parent = next(x for x in scene["objects"] if x["id"] == ids[20])
    cold = "-cold-" in preset
    sequence = [{key: cold}, {key: not cold}]
    if cold:
        parent["visible"]["value"] = False
        project["general"]["properties"][key]["value"] = False
    if preset in ("model-parent-cold-script", "model-parent-cold-script-mutation"):
        sequence = []
        parent["visible"] = {"value": False, "scriptproperties": {}, "script":
            "export function update(previous){return engine.runtime>=2 && engine.runtime<4;}"}
        project.pop("general")
        if preset == "model-parent-cold-script-mutation":
            parent["visible"] = False
            peer = next(x for x in scene["objects"] if x["id"] == ids[60])
            peer["origin"] = {"value": peer["origin"], "scriptproperties": {}, "script":
                'export function update(value){thisScene.getLayer("Owned live model-parent visibility group")'
                '.visible=engine.runtime>=2 && engine.runtime<4;return value;}'}
    entries["scene.json"] = encoded(scene)
    captures = {"scene-ready-window.png": not cold, "scene-series-0000-window.png": cold,
                "scene-after-window.png": not cold}
    shown_oracle = protocol["oracle"]
    hidden_oracle = {name: dict(value, expectedRGB=[0, 0, 0]) if name.startswith("group-") else value
                     for name, value in shown_oracle.items()}
    protocol.update(preset=preset, sequence=sequence, visibilityTargetID=ids[20],
        groups=[{"root": ids[20], "modelIDs": [ids[21]]}], referenceModelIDs=[ids[41]],
        ownFalseModelIDs=[ids[22]], peerID=ids[60], captureShown=captures,
        snapshotOracles={name: shown_oracle if shown else hidden_oracle for name, shown in captures.items()},
        periodicSnapshotInterval=3.5,
        scope="Parent visibility controls the prepared local model, tintback and original group Program; child false and literal reference/peer remain independent. No official parity.")
    protocol["observation"]["clockModelLayerID"] = ids[21]
    protocol["observation"]["tintBackWitness"] = "actual model color callback and exact literal-reference pixels"
    return project, entries, protocol


class SceneModelVisibilityIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        configured = os.environ.get("MWX_SCENE_INTEGRATION_APP")
        if not configured:
            raise unittest.SkipTest("requires an explicitly frozen Debug App executable")
        app = Path(configured).resolve(strict=True)
        cls.app = app / "Contents/MacOS/MyWallpaperX" if app.suffix == ".app" else app
        cls.frozen_app_hashes = app_hashes(cls.app)
        cls.frozen_source_hashes = file_hashes(SOURCES)
        cls.controls = None

    def run_scene(self, label, *, control=None, bad_model=False):
        sequence = [] if control is not None else ([{"mode": "shown"}, {"mode": "hidden"}]
                    if bad_model else [{"mode": "shown"}, {"mode": "hidden"}, {"mode": "shown"}])
        after = 2 if control is not None else 2 * len(sequence) + 2
        snapshots = {"scene-ready-window.png": bool(control)}
        for index in range(len(sequence)):
            name = ("scene-after-window.png" if index == len(sequence) - 1
                    else f"scene-series-{2 + index * 2:04d}-window.png")
            snapshots[name] = not bad_model and sequence[index]["mode"] == "shown"
        snapshots.setdefault("scene-after-window.png", bool(control))
        # A rejected show leaves the retained hidden value unchanged; its repeat is a host no-op.
        accepted = ["false", "true"] if bad_model else ["true"] * len(sequence)
        protocol = {"canvas": CANVAS, "rectangles": RECTS, "tolerance": TOLERANCE,
            "initialMode": "shown" if control else "hidden", "staticControl": control,
            "sequenceEvery2Seconds": sequence, "acceptedSteps": accepted,
            "snapshotShown": snapshots, "badModel": bad_model, "parentOffset": [20, 0, 0],
            "snapshotTimesSeconds": {name: after if name == "scene-after-window.png" else 1
                                     if name == "scene-ready-window.png" else 1.5 + int(name.split("-")[2])
                                     for name in snapshots},
            "ownFalseModelLayerID": 5, "expectedRedPixels": 0, "peerRGB": [0, 255, 0],
            "imageShownRGB": [0, 0, 255], "imageHiddenRGB": [0, 0, 0],
            "shadowOracle": "show: ambient survives and shadow <30% of unoccluded receiver; hide: receiver restored",
            "comparisonOracle": "same geometry with authored literal visibility, every ROI mean within 4 channels",
            "evidenceBoundary": "owned static model/image cohort, no official pixel parity"}
        self.assertEqual(app_hashes(self.app), self.frozen_app_hashes)
        self.assertEqual(file_hashes(SOURCES), self.frozen_source_hashes)
        with tempfile.TemporaryDirectory(prefix="mwx-model-visibility-") as temporary:
            root = Path(temporary)
            content, home, evidence = root / "content", root / "home", root / "evidence"
            content.mkdir(); home.mkdir()
            project, entries = fixture_entries(control=control, bad_model=bad_model)
            (content / "project.json").write_bytes(encoded(project))
            (content / "scene.pkg").write_bytes(make_package(list(entries.items())))
            inputs = (content / "project.json", content / "scene.pkg")
            command = [str(self.app), "--mwx-debug-scene-root", str(content),
                "--mwx-debug-scene-duration", str(after + 2), "--mwx-debug-scene-evidence-dir", str(evidence),
                "--mwx-debug-scene-after-snapshot-delay", str(after),
                "--mwx-debug-scene-properties-json", json.dumps({"mode": protocol["initialMode"]})]
            if sequence:
                command += ["--mwx-debug-scene-live-property-sequence-json", json.dumps(sequence),
                            "--mwx-debug-scene-periodic-snapshot-interval", "1"]
            env = {key: value for key, value in os.environ.items()
                   if not key.startswith(("MWX_SCENE_DEBUG_", "MYWALLPAPERX_SCENE_DEBUG_"))}
            env.update(HOME=str(home), CFFIXED_USER_HOME=str(home), MWX_SCENE_DEBUG_SURFACE_COUNT="1",
                       MWX_SCENE_GENERIC_SHADER_CACHE=str(root / "shader-cache"))
            identity = {"command": command, "appSHA256": self.frozen_app_hashes,
                "sourceSHA256": self.frozen_source_hashes, "inputSHA256": file_hashes(inputs),
                "entrySHA256": {name: hashlib.sha256(data).hexdigest() for name, data in entries.items()}}
            (root / "prerun.json").write_bytes(encoded(identity))
            (root / "preregistration.json").write_bytes(encoded(protocol))
            (root / "scene-input.json").write_bytes(entries["scene.json"])
            log, pixels = "", {}
            try:
                result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=90)
                log = result.stdout + result.stderr
                identity["returncode"] = result.returncode
                for name in snapshots:
                    self.assertTrue((evidence / name).is_file(), (name, log[-6000:]))
                    pixels[name] = measure(evidence / name)
                self.assertEqual(result.returncode, 0, log[-6000:])
                self.assertEqual(re.findall(r"phase=live-property-sequence-step index=(\d+) accepted=(true|false)", log),
                                 [(str(i), value) for i, value in enumerate(accepted)], log[-6000:])
                updates = re.findall(r"phase=live-property-update accepted=(true|false) surfacesBefore=(\d+) surfacesAfter=(\d+) windowsBefore=(\S+) windowsAfter=(\S+)", log)
                self.assertEqual([row[0] for row in updates], accepted)
                self.assertTrue(all(row[1] == row[2] == "1" and row[3] == row[4] for row in updates), updates)
                self.assertEqual(log.count("phase=session-candidate "), 1)
                self.assertEqual(log.count("phase=session-activated "), 1)
                self.assertIn("gpuDrained=true", log)
                self.assertRegex(log, r"state=completed frame=[1-9]\d* surface=\d+ gpu=completed")
                self.assertNotRegex(log, r"phase=launch-failed|phase=snapshot-(?:failed|rejected)|failure=exception")
                preview = "\n".join(path.read_text() for path in evidence.glob("*preview*.log"))
                prepared = re.search(r"prepared static model layers: \[([^\]]*)\]", preview)
                self.assertIsNotNone(prepared, preview[-3000:])
                self.assertEqual({int(value.strip()) for value in prepared[1].split(",") if value.strip()},
                                 {1, 5} if bad_model else {1, 2, 5})
                for name, measurement in pixels.items():
                    reason = name.removeprefix("scene-").removesuffix("-window.png")
                    self.assertRegex(log, rf"phase=snapshot reason={reason} request=\d+ source=metal ")
                    self.assertEqual(measurement["redCount"], 0, (name, measurement))
                    self.assertGreaterEqual(measurement["rois"]["peer"]["greenFraction"], .99)
                    expected = [0, 0, 255] if snapshots[name] else [0, 0, 0]
                    for actual, wanted in zip(measurement["rois"]["image"]["mean"], expected):
                        self.assertAlmostEqual(actual, wanted, delta=TOLERANCE, msg=name)
                if control is not None:
                    for roi in RECTS:
                        for ready, later in zip(pixels["scene-ready-window.png"]["rois"][roi]["mean"],
                                                pixels["scene-after-window.png"]["rois"][roi]["mean"]):
                            self.assertAlmostEqual(ready, later, delta=TOLERANCE, msg=f"static control: {roi}")
                self.assertEqual(app_hashes(self.app), self.frozen_app_hashes)
                self.assertEqual(file_hashes(inputs), identity["inputSHA256"])
                self.assertEqual(file_hashes(SOURCES), self.frozen_source_hashes)
                return pixels, snapshots
            except subprocess.TimeoutExpired as error:
                log = "".join(value.decode(errors="replace") if isinstance(value, bytes) else value or ""
                              for value in (error.stdout, error.stderr))
                identity["failure"] = "subprocess-timeout"
                raise
            finally:
                identity.update(appSHA256After=app_hashes(self.app), inputSHA256After=file_hashes(inputs),
                                sourceSHA256After=file_hashes(SOURCES))
                (root / "identity.json").write_bytes(encoded(identity))
                (root / "pixels.json").write_bytes(encoded(pixels))
                (root / "app.log").write_text(log)
                if destination := os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE"):
                    saved = Path(destination) / self._testMethodName / label
                    saved.mkdir(parents=True, exist_ok=True)
                    for name in ("content", "evidence"):
                        if (root / name).exists():
                            shutil.copytree(root / name, saved / name, dirs_exist_ok=True)
                    for path in root.glob("*.json"):
                        shutil.copy2(path, saved / path.name)
                    shutil.copy2(root / "app.log", saved / "app.log")

    def static_controls(self):
        if self.controls is None:
            self.__class__.controls = {shown: self.run_scene("control-shown" if shown else "control-hidden",
                control=shown)[0]["scene-ready-window.png"] for shown in (False, True)}
        hidden, shown = self.controls[False]["rois"], self.controls[True]["rois"]
        self.assertGreater(min(hidden["receiver"]["mean"]), 50)
        for channel in range(3):
            self.assertAlmostEqual(hidden["caster"]["mean"][channel], hidden["receiver"]["mean"][channel], delta=TOLERANCE)
            self.assertAlmostEqual(hidden["shadow"]["mean"][channel], hidden["receiver"]["mean"][channel], delta=TOLERANCE)
            for control in (hidden, shown):
                self.assertAlmostEqual(control["ownFalse"]["mean"][channel], control["receiver"]["mean"][channel], delta=TOLERANCE)
            self.assertAlmostEqual(shown["receiver"]["mean"][channel], hidden["receiver"]["mean"][channel], delta=TOLERANCE)
            self.assertGreater(shown["shadow"]["mean"][channel], 2)
            self.assertLess(shown["shadow"]["mean"][channel], hidden["shadow"]["mean"][channel] * .3)
        green = shown["caster"]["mean"]
        self.assertGreater(green[1], max(green[0], green[2]) + 20)
        return self.controls

    def compare_controls(self, pixels, snapshots):
        controls = self.static_controls()
        for name, shown in snapshots.items():
            self.assertEqual(pixels[name]["dimensions"], controls[shown]["dimensions"])
            for roi in RECTS:
                for actual, expected in zip(pixels[name]["rois"][roi]["mean"], controls[shown]["rois"][roi]["mean"]):
                    self.assertAlmostEqual(actual, expected, delta=TOLERANCE, msg=f"{name}: {roi}")

    def test_initially_hidden_model_and_image_show_hide_show_without_depth_or_shadow_ghosts(self):
        self.static_controls()
        self.compare_controls(*self.run_scene("live-cycle"))

    def test_unprepared_model_rejects_the_whole_combo_and_keeps_the_image_hidden(self):
        self.static_controls()
        self.compare_controls(*self.run_scene("bad-model", bad_model=True))

    def subtree_readout(self, protocol, log, preview, evidence, *, require_clock=True):
        observations = structured_runtime_observations(log, "MWX SCENE COMPOSITION OBSERVATION: ")
        self.assertEqual(observations["parse_errors"], 0)
        prefix = "phase=timeline-frame-input json="
        clocks = [json.loads(line.split(prefix, 1)[1]) for line in log.splitlines() if prefix in line]
        readout = []
        updates = list(re.finditer(r"phase=live-property-update accepted=true ", log))
        self.assertEqual(re.findall(r"phase=live-property-sequence-step index=(\d+) accepted=(true|false)", log),
                         [(str(i), "true") for i in range(len(protocol["sequence"]))])
        windows = re.findall(r"phase=live-property-update accepted=true surfacesBefore=(\d+) surfacesAfter=(\d+) "
                             r"windowsBefore=(\S+) windowsAfter=(\S+)", log)
        self.assertTrue(all(before == after == "1" and a == b for before, after, a, b in windows), windows)
        self.assertEqual(len(windows), len(protocol["sequence"]))
        prepared = re.search(r"prepared static model layers: \[([^\]]*)\]", preview)
        self.assertIsNotNone(prepared, preview[-3000:])
        expected_drawable = set(protocol["referenceModelIDs"]).union(
            *(set(group["modelIDs"]) for group in protocol["groups"]))
        expected_prepared = expected_drawable.union(protocol["ownFalseModelIDs"])
        self.assertEqual({int(x.strip()) for x in prepared[1].split(",") if x.strip()}, expected_prepared)
        tint_observation = None
        if tint := protocol["typedTintBack"]:
            self.assertRegex(log + preview, r"(?i)scene\s*script VM: schema=quickjs-ng-typed-v2 bindings=\d+ vectorBindings=[1-9]\d* ")
            callbacks = [line for line in log.splitlines() if "MWX SceneScript VM: target=" in line
                         and "callback=completed type=vector3 " in line]
            model_id = protocol["groups"][0]["modelIDs"][0]
            completed = re.findall(rf"target=layer\(layerID: {model_id}, field: \S+\.color\) "
                r"callback=completed type=vector3 .* output=vector3\(([^)]+)\)", log)
            self.assertTrue(completed, callbacks)
            for actual, expected in zip(completed[0].split(","), tint["resolved"], strict=True):
                self.assertAlmostEqual(float(actual), expected, places=12)
            self.assertNotRegex(log + preview, r"scene-script-(?:exception|timeout)|scriptValueInvalid|callback=failed")
            tint_observation = {"material": tint["material"], "completedVectorObservations": callbacks,
                "authored": tint["authored"], "resolved": tint["resolved"],
                "scope": "actual model color callback; per-capture consumption is tested by literal PNG/reference pixels, not Timeline color"}
        for filename, shown in protocol["captureShown"].items():
            path = evidence / filename
            self.assertTrue(path.is_file(), (filename, log[-6000:]))
            reason = filename.removeprefix("scene-").removesuffix("-window.png")
            requests = re.findall(rf"phase=snapshot reason={reason} request=(\d+) source=metal path=(\S+)", log)
            self.assertEqual(len(requests), 1, filename)
            request_id, captured_path = requests[0]
            self.assertEqual(Path(captured_path).name, filename)
            if require_clock:
                self.assertEqual(captured_path, str(path))
            request = [request_id]
            receipts = list(re.finditer(rf"phase=snapshot-encoded request={request[0]} commandBufferToken=(\d+) "
                r"textureToken=(\d+) width=(\d+) height=(\d+)", log))
            self.assertEqual(len(receipts), 1, filename)
            receipt = receipts[0]
            matched = terminal_composition_snapshot({"status": "captured", "request_id": int(request[0]),
                "command_buffer_token": receipt[1], "texture_token": receipt[2],
                "source_width": int(receipt[3]), "source_height": int(receipt[4])}, observations)
            self.assertTrue(matched["composition_receipt_matched"], matched)
            event = next(e for e in observations["events"] if e["captureRequestID"] == int(request[0])
                         and e["commandBufferToken"] == receipt[1])
            self.assertEqual((event["truncatedRows"], event["gpuStatus"]), (0, "completed"))
            frames = [c for c in clocks if c["kind"] == "frame" and c["stream"] == event["displayID"]]
            lower = upper = None
            if require_clock:
                self.assertTrue(frames, "Missing qualified frame clock; Timeline observer accepts at most eight layer IDs")
                lower = max((c for c in frames if c["frame"] <= event["frameIndex"]), key=lambda c: c["frame"])
                upper = min((c for c in frames if c["frame"] >= event["frameIndex"]), key=lambda c: c["frame"])
                self.assertLessEqual(upper["sceneTime"] - lower["sceneTime"], .4)
                self.assertEqual(lower["generation"], upper["generation"])
                for clock in (lower, upper):
                    self.assertTrue(clock["observationComplete"])
                    self.assertEqual(clock["frame"], clock["snapshotFrame"])
            if updates:
                self.assertEqual(sum(update.start() < receipt.start() for update in updates),
                                 {"ready": 0, "series-0000": 1, "after": 2}[reason])
            rows = event["rows"]
            seal = next(r for r in rows if r["kind"] == "frame-seal" and r["outcome"] == "sealed")
            model_rows = [r for r in rows if r["kind"] == "model" and r["outcome"] == "draw-encoded"]
            for identifier in protocol["referenceModelIDs"]:
                model = next(r for r in model_rows if r.get("layerID") == identifier)
                self.assertEqual(model["target"]["textureToken"], seal["target"]["textureToken"])
            for group in protocol["groups"]:
                root = [r for r in rows if r.get("layerID") == group["root"]]
                if not shown and protocol["visibilityTargetID"] == group["root"]:
                    self.assertFalse(any(r["kind"] in ("sourceCapture", "material", "group", "ordinary", "tail-consume")
                                         for r in root), root)
                    self.assertFalse(any(r.get("layerID") in group["modelIDs"] for r in model_rows), model_rows)
                    continue
                source = next(r for r in root if r["kind"] == "sourceCapture" and r["outcome"] == "encoded")
                material = next(r for r in root if r["kind"] == "material" and r["outcome"] == "draw-encoded")
                composite = next(r for r in root if r["kind"] in ("group", "ordinary") and r["outcome"] == "draw-encoded")
                tail = next(r for r in root if r["kind"] == "tail-consume" and r["outcome"] == "terminal-consumed")
                self.assertEqual(source["target"]["textureToken"], material["source"]["textureToken"])
                self.assertEqual(material["target"]["textureToken"], composite["source"]["textureToken"])
                self.assertEqual(material["target"]["textureToken"], tail["source"]["textureToken"])
                self.assertEqual(composite["target"]["textureToken"], seal["target"]["textureToken"])
                self.assertEqual([source["source"]["width"], source["source"]["height"]], [200, 120])
                for identifier in group["modelIDs"]:
                    actual = [r for r in model_rows if r.get("layerID") == identifier]
                    self.assertEqual(len(actual), int(shown or identifier != protocol["visibilityTargetID"]))
                    if actual:
                        self.assertEqual(actual[0]["target"]["textureToken"], source["source"]["textureToken"])
                        self.assertLess(rows.index(actual[0]), rows.index(source))
                if not shown:
                    self.assertTrue(any(r["kind"] == "clear" and r["outcome"] == "encoded"
                        and r["target"]["textureToken"] == source["source"]["textureToken"] for r in rows))
            self.assertTrue(any(r["kind"] == "ordinary" and r.get("layerID") == protocol["peerID"]
                                and r["outcome"] == "draw-encoded" for r in rows))
            if bad := protocol["badModelID"]:
                self.assertFalse(any(r.get("layerID") == bad for r in model_rows))
            self.assertFalse(any(r.get("layerID") in protocol["ownFalseModelIDs"] for r in model_rows))
            readout.append({"capture": filename, "shown": shown, "request": request[0],
                "capturedPath": captured_path, "evidenceCopyPath": str(path),
                "commandBuffer": receipt[1], "surface": event["surfaceIdentity"], "frame": event["frameIndex"],
                "generation": lower["generation"] if lower else None,
                "clockQualified": require_clock,
                "clockBracket": [lower["sceneTime"], upper["sceneTime"]] if lower else None,
                "rows": rows})
        self.assertEqual(len({r["surface"] for r in readout}), 1)
        depth = re.findall(r"MWX Scene model-depth frame=(\d+) layer=(\d+) material=(\S+) domain=scene "
                           r"pass=(\S+) command=(\S+) encoded=true world=\[([^\]]+)\]", log)
        by_frame = {}
        for frame, layer, material, domain, command, world in depth:
            by_frame.setdefault((frame, command), {})[int(layer)] = domain
        complete = [frame for frame in by_frame.values() if expected_drawable.issubset(frame)]
        if protocol["captureShown"]["scene-ready-window.png"]:
            self.assertTrue(complete, {"depthRows": depth, "expectedIDs": sorted(expected_drawable)})
        for frame in complete:
            domains = []
            for group in protocol["groups"]:
                owners = {frame[layer] for layer in group["modelIDs"]}
                self.assertEqual(len(owners), 1, frame)
                domains.append(next(iter(owners)))
            main = {frame[layer] for layer in protocol["referenceModelIDs"]}
            self.assertEqual(len(main), 1, frame)
            self.assertEqual(len(set(domains + list(main))), len(domains) + 1, frame)
        return {"captures": readout, "depthDomains": complete, "depthQualified": bool(complete),
                "tintBackExecution": tint_observation,
                "boundary": "model rows observe actual albedo texture binding and target; internal material slots are not separately observed"}

    def run_model_subtree(self, preset):
        project, entries, protocol = model_subtree_fixture(preset)
        self.assertEqual(app_hashes(self.app), self.frozen_app_hashes)
        self.assertEqual(file_hashes(SOURCES), self.frozen_source_hashes)
        with tempfile.TemporaryDirectory(prefix="mwx-model-subtree-") as temporary:
            root = Path(temporary)
            content, home, evidence = root / "content", root / "home", root / "evidence"
            content.mkdir(); home.mkdir()
            (content / "project.json").write_bytes(encoded(project))
            (content / "scene.pkg").write_bytes(make_package(list(entries.items())))
            inputs = (content / "project.json", content / "scene.pkg")
            after = protocol["afterDelay"]
            command = [str(self.app), "--mwx-debug-scene-root", str(content),
                "--mwx-debug-scene-duration", str(after + 1), "--mwx-debug-scene-evidence-dir", str(evidence),
                "--mwx-debug-scene-after-snapshot-delay", str(after)]
            if protocol["sequence"]:
                command += ["--mwx-debug-scene-live-property-sequence-json", json.dumps(protocol["sequence"])]
            if "scene-series-0000-window.png" in protocol["captureShown"]:
                command += ["--mwx-debug-scene-periodic-snapshot-interval",
                            str(protocol.get("periodicSnapshotInterval", 3.5))]
            env = {k: v for k, v in os.environ.items()
                   if not k.startswith(("MWX_SCENE_", "MYWALLPAPERX_SCENE_DEBUG_"))}
            sampled_ids = [protocol["observation"]["clockModelLayerID"]]
            env.update(HOME=str(home), CFFIXED_USER_HOME=str(home), MWX_SCENE_DEBUG_SURFACE_COUNT="1",
                MWX_SCENE_GENERIC_SHADER_CACHE=str(root / "shader-cache"),
                MYWALLPAPERX_SCENE_DEBUG_TIMELINE_EVIDENCE=json.dumps({"layerIDs": sampled_ids,
                    "sceneTimeWindow": [0, 8], "interval": .25, "maxSamples": 32}))
            identity = {"command": command, "appSHA256": self.frozen_app_hashes,
                "sourceSHA256": self.frozen_source_hashes, "inputSHA256": file_hashes(inputs),
                "entrySHA256": {name: hashlib.sha256(data).hexdigest() for name, data in entries.items()}}
            (root / "prerun.json").write_bytes(encoded(identity))
            (root / "preregistration.json").write_bytes(encoded(protocol))
            (root / "scene-input.json").write_bytes(entries["scene.json"])
            log, pixels, readout = "", {}, {}
            try:
                result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=90)
                log = result.stdout + result.stderr
                identity["returncode"] = result.returncode
                self.assertEqual(result.returncode, 0, log[-6000:])
                self.assertIn("gpuDrained=true", log)
                self.assertEqual(log.count("phase=session-candidate "), 1)
                self.assertEqual(log.count("phase=session-activated "), 1)
                self.assertNotRegex(log, r"phase=launch-failed|phase=snapshot-(?:failed|rejected)|failure=exception")
                preview = "\n".join(path.read_text() for path in evidence.glob("*preview*.log"))
                readout = self.subtree_readout(protocol, log, preview, evidence)
                for filename in protocol["captureShown"]:
                    measurement = measure_capture(evidence / filename, protocol)
                    pixels[filename] = measurement
                    for name, value in measurement["rois"].items():
                        with self.subTest(capture=filename, roi=name):
                            self.assertGreater(value["total"], 0, value)
                            self.assertGreaterEqual(value["correct"] / value["total"], .99, value)
                            self.assertTrue(all(abs(a-b) <= TOLERANCE
                                for a, b in zip(value["centerRGB"], value["expectedRGB"])), value)
                self.assertEqual(app_hashes(self.app), self.frozen_app_hashes)
                self.assertEqual(file_hashes(inputs), identity["inputSHA256"])
                self.assertEqual(file_hashes(SOURCES), self.frozen_source_hashes)
            except subprocess.TimeoutExpired as error:
                log = "".join(x.decode(errors="replace") if isinstance(x, bytes) else x or ""
                              for x in (error.stdout, error.stderr))
                identity["failure"] = "subprocess-timeout"
                raise
            finally:
                identity.update(appSHA256After=app_hashes(self.app), inputSHA256After=file_hashes(inputs),
                                sourceSHA256After=file_hashes(SOURCES))
                (root / "identity.json").write_bytes(encoded(identity))
                (root / "pixels.json").write_bytes(encoded(pixels))
                (root / "model-subtree-readout.json").write_bytes(encoded(readout))
                (root / "app.log").write_text(log)
                if destination := os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE"):
                    saved = Path(destination) / self._testMethodName / preset
                    saved.mkdir(parents=True, exist_ok=True)
                    for name in ("content", "evidence"):
                        if (root / name).exists():
                            shutil.copytree(root / name, saved / name, dirs_exist_ok=True)
                    for path in root.glob("*.json"):
                        shutil.copy2(path, saved / path.name)
                    shutil.copy2(root / "app.log", saved / "app.log")

    def test_composition_models_keep_pass_depth_and_local_bad_model_failure(self):
        self.run_model_subtree("composition-depth")

    def test_renamed_project_models_match_mirrored_nonuniform_parent_reference(self):
        self.run_model_subtree("project-trs-renamed")

    def test_prepared_model_leaf_visibility_keeps_tintback_script_and_group_program(self):
        self.run_model_subtree("model-leaf-cycle")

    def test_model_parent_visibility_keeps_tintback_program_and_child_false(self):
        self.run_model_subtree("model-parent-cycle")

    def test_renamed_model_parent_visibility_keeps_tintback_program_and_child_false(self):
        self.run_model_subtree("model-parent-cycle-renamed")

    def test_cold_model_parent_property_prepares_tintback_and_preserves_child_false(self):
        self.run_model_subtree("model-parent-cold-property")

    def test_cold_model_parent_script_prepares_tintback_and_preserves_child_false(self):
        self.run_model_subtree("model-parent-cold-script")

    def test_cold_model_parent_script_mutation_prepares_tintback_and_preserves_child_false(self):
        self.run_model_subtree("model-parent-cold-script-mutation")
