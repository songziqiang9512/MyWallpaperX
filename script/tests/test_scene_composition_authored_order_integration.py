"""Self-authored composition order/copybackground -> completed App pixels.

The approved D1 behavior oracle is fixed before launch. Every resource here is
authored by this test; solid geometry uses the product's procedural solid lane.
This checks the bounded ordinary-composition behavior, not official pixel parity
between this solid fixture and the official client's differently formatted base.
Run only against an explicitly frozen Debug App with MWX_SCENE_INTEGRATION_APP.
Project variants reuse this internal fixture; they are not the official stock A/B input.
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
from .scene_pkg_fixture import make_package
from .test_scene_authored_sampling_integration import solid_texture


CANVAS = (256, 256)
CHANNEL_TOLERANCE = 4
MINIMUM_CORRECT_FRACTION = .99
BLUE = (0, 0, 255)
YELLOW = (255, 255, 0)
RED = (255, 0, 0)
CYAN = (0, 255, 255)
# Canvas coordinates, 12 units inside each 48x48 colored card. The central
# background ROI is disjoint from both cards and stays inside a cover viewport.
ROI_RECTS = {"background": (116, 116, 140, 140),
             "child": (52, 116, 76, 140),
             "nonchild": (180, 116, 204, 140)}
LAYER_IDS = {"background": 1, "composition": 20, "child": 21, "nonchild": 30,
             "containers": [42]}
RENAMED_LAYER_IDS = {"background": 73, "composition": 901, "child": 218, "nonchild": 709,
                     "containers": [403, 402]}
VERTEX = (b"attribute vec3 a_Position;\nattribute vec2 a_TexCoord;\n"
          b"varying vec2 v_TexCoord;\n"
          b"void main(){gl_Position=vec4(a_Position,1.0);v_TexCoord=a_TexCoord;}\n")
FRAGMENT = (b"uniform sampler2D g_Texture0;\nvarying vec2 v_TexCoord;\n"
            b"void main(){vec4 c=texSample2D(g_Texture0,v_TexCoord);"
            b"gl_FragColor=vec4(vec3(1.0)-c.rgb,c.a);}\n")


def encoded(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def fixture_entries(*, copy_background=None, order="baseline", enabled=True,
                    effect=True, childless=False, hide_child_next_frame=False,
                    container=False, renamed=False, hide_container_next_frame=False, quad=False,
                    quad_input=None, project_layer=False):
    """None omits the authored field; false and true remain distinct inputs."""
    if copy_background is not None and not isinstance(copy_background, bool):
        raise ValueError("copy_background must be omitted, false, or true")
    if order not in ("baseline", "nonchild-after-root", "child-before-root"):
        raise ValueError(f"unknown authored order: {order}")
    ids = RENAMED_LAYER_IDS if renamed else LAYER_IDS
    solid_path = "models/alternate_card.json" if renamed else "models/own_solid.json"
    shader = "alternate_invert" if renamed else "own_invert"
    effect_path = f"effects/{shader}/effect.json"
    utility_path = f"models/util/{'project' if project_layer else 'compose'}layer.json"
    root = {"id": ids["composition"], "name": "Owned composition root",
            "image": utility_path, "origin": "128 128 0",
            "size": "256 256", "visible": True}
    if copy_background is not None:
        root["copybackground"] = copy_background
    if effect:
        root["effects"] = [{"id": 200, "file": effect_path,
                            "visible": enabled}]
    background = {"id": ids["background"], "name": "Owned full-scene background",
                  "image": solid_path, "origin": "128 128 0",
                  "size": "256 256", "color": "1 1 0" if childless else "0 0 1",
                  "visible": True}
    child = {"id": ids["child"], "parent": ids["composition"], "name": "Owned yellow child",
             "image": solid_path, "origin": "-64 0 0",
             "size": "48 48", "color": "1 1 0", "visible": True}
    containers = []
    if container:
        for index, layer_id in enumerate(ids["containers"]):
            containers.append({"id": layer_id,
                               "parent": ids["composition"] if index == 0 else ids["containers"][index - 1],
                               "name": "Owned transform parent", "visible": True,
                               "origin": ("-32 0 0" if renamed else "-48 0 0") if index == 0 else "-8 0 0",
                               "scale": "2 0.5 1" if index == 0 else "1 1 1"})
        child.update(parent=ids["containers"][-1], origin="-8 0 0")
        if hide_container_next_frame:
            containers[0]["visible"] = {
                "script": "export function update(v) { return engine.runtime < 2.5; }", "value": True}
    if hide_child_next_frame:
        child["visible"] = {"script": "export function update(v) { return engine.runtime < 2.5; }",
                            "value": True}
    if quad:
        for key in ("image", "size", "color"):
            child.pop(key)
        child.update(shape="quad", scale="0.1875 0.1875 1", effects=[
            {"id": 210, "file": "effects/own_yellow/effect.json", "visible": True}])
        root["size"] = "224 112"
    nonchild = {"id": ids["nonchild"], "name": "Owned red nonchild",
                "image": solid_path, "origin": "192 128 0",
                "size": "48 48", "color": "1 0 0", "visible": True}
    if childless:
        objects = [background, root]
    elif order == "nonchild-after-root":
        objects = [background, root, nonchild, *containers, child]
    elif order == "child-before-root":
        objects = [background, nonchild, child, *reversed(containers), root]
    else:
        objects = [background, nonchild, root, *containers, child]
    scene = {"version": 3,
             "general": {"orthogonalprojection": {"width": CANVAS[0], "height": CANVAS[1]},
                         "clearcolor": "0 0 0"}, "objects": objects}
    entries = {
        "scene.json": encoded(scene),
        # Declare our own solid model, instead of resolving a stock model.
        solid_path: encoded({"solidlayer": True, "width": 256, "height": 256}),
        # This utility path is the public authored type discriminator. Its
        # bytes are ours; no stock model, material, image, or shader is read.
        utility_path: encoded({"width": 256, "height": 256, "autosize": False}),
        effect_path: encoded({"passes": [{"material": f"materials/{shader}.json"}]}),
        f"materials/{shader}.json": encoded({"passes": [{
            "shader": shader, "textures": [None], "blending": "normal",
            "depthtest": "disabled", "depthwrite": "disabled", "cullmode": "nocull"}]}),
        f"shaders/{shader}.vert": VERTEX,
        f"shaders/{shader}.frag": FRAGMENT,
    }
    if project_layer and renamed:
        entries[f"shaders/{shader}.vert"] = VERTEX.replace(b"v_TexCoord", b"v_ProjectUV")
        entries[f"shaders/{shader}.frag"] = (FRAGMENT.replace(b"v_TexCoord", b"v_ProjectUV")
            .replace(b"vec4 c=", b"vec4 sampled=").replace(b"-c.rgb", b"-sampled.rgb")
            .replace(b",c.a", b",sampled.a"))
    if quad:
        entries.update({
            "effects/own_yellow/effect.json": encoded({"passes": [{"material": "materials/own_yellow.json"}]}),
            "materials/own_yellow.json": encoded({"passes": [{"shader": "own_yellow", "textures": [],
                "blending": "normal", "depthtest": "disabled", "depthwrite": "disabled", "cullmode": "nocull"}]}),
            "shaders/own_yellow.vert": VERTEX,
            "shaders/own_yellow.frag": b"void main(){gl_FragColor=vec4(1.0,1.0,0.0,1.0);}\n"})
    project = {"type": "scene", "file": "scene.json"}
    if quad_input is not None:
        slot, initial = quad_input["slot"], quad_input["initialVisible"]
        key = "moved_quad_cohort" if renamed else "quad_cohort"
        prefix = "moved_sampled_light" if renamed else "own_sampled_light"
        path = f"materials/{prefix}/tiles.tex"
        for layer in (child, nonchild):
            layer["visible"] = {"user": key, "value": initial}
        root["effects"][0]["id"] = ids["composition"] * 10
        child["effects"] = [{"id": ids["child"] * 10,
                             "file": f"effects/{prefix}/effect.json", "visible": True}]
        project["general"] = {"properties": {key: {
            "type": "bool", "text": "Owned quad and healthy peer", "value": initial}}}
        palette = ((255, 0, 0, 255), (0, 255, 0, 255),
                   (255, 0, 255, 0), (255, 255, 0, 255))
        rgba = bytes(channel for y in range(16) for x in range(16)
                     for channel in palette[int(y >= 8) * 2 + int(x >= 8)])
        # Keep the existing tightly packed TEX writer's header; this input has
        # no padding, atlas frame, resize, or sampler-UV mapping dependency.
        packed = solid_texture((0, 0, 0))
        entries[path] = packed[:-len(rgba)] + rgba
        entries[f"effects/{prefix}/effect.json"] = encoded({
            "passes": [{"material": f"materials/{prefix}.json"}]})
        entries[f"materials/{prefix}.json"] = encoded({"passes": [{
            "shader": prefix, "textures": [None] * slot + [path], "blending": "normal",
            "depthtest": "disabled", "depthwrite": "disabled", "cullmode": "nocull"}]})
        uv = "v_MovedUV" if renamed else "v_TexCoord"
        entries[f"shaders/{prefix}.vert"] = VERTEX.replace(b"v_TexCoord", uv.encode())
        entries[f"shaders/{prefix}.frag"] = (
            f'uniform sampler2D g_Texture{slot}; // {{"material":"albedo"}}\nvarying vec2 {uv};\n'
            f"void main(){{vec4 sampled=texSample2D(g_Texture{slot},{uv});"
            "gl_FragColor=sampled;}\n").encode()
        for path in ("effects/own_yellow/effect.json", "materials/own_yellow.json",
                     "shaders/own_yellow.vert", "shaders/own_yellow.frag"):
            del entries[path]
        entries["scene.json"] = encoded(scene)
    return project, entries


def preregistration(*, copy_background=None, order="baseline", enabled=True,
                    effect=True, childless=False, hide_child_next_frame=False,
                    container=False, renamed=False, hide_container_next_frame=False, quad=False,
                    quad_input=None, project_layer=False):
    """The expected colors come from the approved contract, never the capture."""
    active_effect = effect and enabled
    copies = copy_background is not False
    ids = RENAMED_LAYER_IDS if renamed else LAYER_IDS
    rects = dict(ROI_RECTS)
    if childless:
        expected = dict.fromkeys(ROI_RECTS, BLUE if active_effect and copies else YELLOW)
    else:
        expected = {"background": YELLOW if active_effect and copies else BLUE,
                    "child": BLUE if active_effect else YELLOW,
                    "nonchild": CYAN if active_effect and copies and order != "nonchild-after-root" else RED}
    if quad and copies:
        expected["child"] = (0, 0, 0) if active_effect else (255, 255, 255)
    if container:
        rects.update(child=(56, 124, 72, 132), horizontalWing=(96, 124, 104, 132),
                     verticalOutside=(60, 144, 68, 148))
        expected.update(horizontalWing=expected["child"], verticalOutside=expected["background"])
    protocol = {"canvas": CANVAS,
            "parameters": {"copybackground": "omitted" if copy_background is None else copy_background,
                           "order": order, "effectPresent": effect, "effectEnabled": enabled,
                           "childless": childless, "container": container, "renamed": renamed, "quad": quad},
            "layerIDs": ids,
            "worldCenters": {"composition": [128, 128], "child": [64, 128], "nonchild": [192, 128]},
            "oracle": {name: {"canvasRect": rect, "expectedRGB": expected[name]}
                       for name, rect in rects.items()},
            "channelTolerance": CHANNEL_TOLERANCE,
            "minimumCorrectAreaFraction": MINIMUM_CORRECT_FRACTION,
            "captureMapping": "centered orthographic cover, scale=max(width/256,height/256)",
            "timingBoundary": "ready and later after Metal readbacks; no strict adjacent-frame binding",
            "evidenceBoundary": "bounded D1 order/copybackground behavior using owned procedural solids; not official pixel parity"}
    if project_layer:
        protocol["parameters"]["projectLayer"] = True
        protocol["evidenceBoundary"] = (
            "internal project subtree/copybackground behavior using owned models and shaders; "
            "not the official stock A/B fixture or official pixel parity")
    if container:
        protocol["containerGeometry"] = {
            "worldTransform": ("T(128,128) T(-32,0) S(2,.5) T(-8,0) T(-8,0)"
                               if renamed else "T(128,128) T(-48,0) S(2,.5) T(-8,0)"),
            "childAuthoredSize": [48, 48], "childWorldBounds": [16, 116, 112, 140],
            "oracleBasis": "center=(128-48+2*(-8),128)=(64,128); extent=(2*48,.5*48)=(96,24); "
                           "horizontalWing is inside only the widened card; verticalOutside is outside its reduced height",
            "alphaBoundary": "each draw retains its own layer alpha; container alpha inheritance is not claimed"}
    if quad:
        protocol["quadGeometry"] = {
            "unitExtent": [256, 256], "leafScale": [48 / 256, 48 / 256, 1],
            "compositionSize": [224, 112], "compositionWorldBounds": [16, 72, 240, 184],
            "oracleBasis": "source-less constant-yellow Program uses the existing alpha-weighted additive final lane; "
                           "alpha1 yellow + copied blue = white, then root invert = black; "
                           "the same parent transform produces child bounds [16,116,112,140]"}
        protocol["evidenceBoundary"] = "owned source-less quad Program and root Program through local group raster; not official pixel parity"
    if hide_child_next_frame or hide_container_next_frame:
        later_expected = dict(expected, child=expected["background"])
        if container:
            later_expected["horizontalWing"] = expected["background"]
        protocol["parameters"].update(hideChildNextFrame=hide_child_next_frame,
                                      hideContainerNextFrame=hide_container_next_frame)
        protocol["visibilityTransition"] = {"layer": ids["containers"][0] if hide_container_next_frame else ids["child"],
                                             "initialVisible": True,
                                             "hiddenAfterRuntimeSeconds": 2.5}
        protocol["snapshotOracles"] = {
            "scene-ready-window.png": protocol["oracle"],
            "scene-after-window.png": {
                name: {"canvasRect": rect, "expectedRGB": later_expected[name]}
                for name, rect in rects.items()}}
    if quad_input is not None:
        key = "moved_quad_cohort" if renamed else "quad_cohort"
        prefix = "moved_sampled_light" if renamed else "own_sampled_light"
        samples = {
            "sample0": ((28, 118, 40, 122), (0, 255, 0)),
            "sample1": ((84, 118, 96, 122), (255, 0, 0)),
            "sample2": ((28, 134, 40, 138), (255, 255, 0)),
            "sample3": ((84, 134, 96, 138), (0, 0, 0)),
        }
        def oracle(visible):
            values = {name: {"canvasRect": rect, "expectedRGB": color if visible else YELLOW}
                      for name, (rect, color) in samples.items()}
            values.update({"background": {"canvasRect": ROI_RECTS["background"], "expectedRGB": YELLOW},
                           "verticalOutside": {"canvasRect": (60, 144, 68, 148), "expectedRGB": YELLOW},
                           "nonchild": {"canvasRect": ROI_RECTS["nonchild"],
                                        "expectedRGB": CYAN if visible else YELLOW}})
            return values
        initial = quad_input["initialVisible"]
        protocol["quadInput"] = {**quad_input, "key": key,
            "samplerMaterial": "albedo", "loadPurpose": "straightAlbedo",
            "texturePath": f"materials/{prefix}/tiles.tex", "rgbaExtent": [16, 16],
            "rgbaQuadrants": [[255, 0, 0, 255], [0, 255, 0, 255], [255, 0, 255, 0], [255, 255, 0, 255]],
            "sequence": [{key: not initial}], "afterDelay": 3,
            "cohortLayerIDs": [ids["child"], ids["nonchild"]]}
        protocol["snapshotOracles"] = {
            "scene-ready-window.png": oracle(initial),
            "scene-after-window.png": oracle(not initial)}
        protocol["oracle"] = oracle(initial)
        protocol["quadGeometry"]["oracleBasis"] = (
            "Opaque literal RGBA TEX quadrants add into copied blue, then the parent's existing "
            "invert Program computes 1-rgb. Thus r/g become (0,255),(255,0),(255,255),(0,0), "
            "with blue0. Alpha0 magenta retains no ink under the existing coverage boundary; "
            "fractional alpha and representation-specific additive weighting are not qualified here. "
            "Hidden child/peer leave freshly copied blue, inverted to yellow.")
        protocol["timingBoundary"] = (
            "ready readback precedes the existing +2s Bool edit; after readback uses delay3s; "
            "each readback joins its exact request/CB/seal/completed event and bounded snapshot clock")
        protocol["evidenceBoundary"] = (
            "owned typed straight-albedo asset sampling and atomic live visibility through nearest group raster; "
            "sampler purpose is explicitly authored as material=albedo, not inferred from whole-vector color flow; "
            "no TEXS/atlas, implicit graph source, arbitrary parent alpha, or official parity claim")
    return protocol


def measure_capture(path, protocol):
    width, height, rows = png_rgb_pixels(path)
    scale = max(width / CANVAS[0], height / CANVAS[1])

    def point(x, y):
        return ((x - CANVAS[0] / 2) * scale + width / 2,
                (y - CANVAS[1] / 2) * scale + height / 2)

    measured = {}
    oracle = protocol.get("snapshotOracles", {}).get(path.name, protocol["oracle"])
    for name, spec in oracle.items():
        left, top, right, bottom = spec["canvasRect"]
        x0, y0 = point(left, top)
        x1, y1 = point(right, bottom)
        if not (0 <= x0 < x1 <= width and 0 <= y0 < y1 <= height):
            raise AssertionError(f"preregistered {name} ROI cropped: {(width, height)}")
        expected = spec["expectedRGB"]
        correct = total = 0
        maximum_error = 0
        for y in range(math.ceil(y0), math.floor(y1)):
            for x in range(math.ceil(x0), math.floor(x1)):
                rgb = rows[y][x * 3:x * 3 + 3]
                error = max(abs(actual - wanted) for actual, wanted in zip(rgb, expected))
                correct += error <= protocol["channelTolerance"]
                maximum_error = max(maximum_error, error)
                total += 1
        cx, cy = point((left + right) / 2, (top + bottom) / 2)
        center = list(rows[math.floor(cy)][math.floor(cx) * 3:math.floor(cx) * 3 + 3])
        measured[name] = {"expectedRGB": expected, "centerRGB": center,
                          "correct": correct, "total": total, "maximumChannelError": maximum_error}
    return {"size": [width, height], "rois": measured}


def app_hashes(app):
    return {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in (app, app.with_name("MyWallpaperX.debug.dylib")) if path.is_file()}


class SceneCompositionAuthoredOrderIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        executable = os.environ.get("MWX_SCENE_INTEGRATION_APP")
        if not executable:
            raise unittest.SkipTest("requires explicitly frozen Debug App executable")
        cls.app = Path(executable).resolve(strict=True)
        cls.frozen_app_hashes = app_hashes(cls.app)

    def check_quad_input_captures(self, protocol, log, captures, evidence):
        settings, ids = protocol["quadInput"], protocol["layerIDs"]
        self.assertEqual(re.findall(
            r"phase=live-property-sequence-step index=(\d+) accepted=(true|false)", log), [("0", "true")])
        updates = re.findall(
            r"phase=live-property-update accepted=true surfacesBefore=(\d+) surfacesAfter=(\d+) "
            r"windowsBefore=(\S+) windowsAfter=(\S+)", log)
        self.assertEqual(len(updates), 1)
        before, after, window_before, window_after = updates[0]
        self.assertEqual((before, after), ("1", "1"))
        self.assertEqual(window_before, window_after)
        self.assertNotEqual(window_before, "")
        update_position = log.index("phase=live-property-update accepted=true ")
        for layer in settings["cohortLayerIDs"]:
            for visible in (False, True):
                value = str(visible).lower()
                self.assertRegex(log, rf"layer={layer} source=userProperty value={value} effective={value}")
        observations = structured_runtime_observations(log, "MWX SCENE COMPOSITION OBSERVATION: ")
        self.assertEqual(observations["parse_errors"], 0)
        clock_prefix = "phase=timeline-frame-input json="
        clocks = [json.loads(line.split(clock_prefix, 1)[1])
                  for line in log.splitlines() if clock_prefix in line]
        self.assertEqual({p.name for p in captures}, {"scene-ready-window.png", "scene-after-window.png"})
        readout = []
        for path in captures:
            reason = "ready" if "ready" in path.name else "after"
            request = re.findall(
                rf"phase=snapshot reason={reason} request=(\d+) source=metal path={re.escape(str(path))}", log)
            self.assertEqual(len(request), 1)
            receipt_pattern = (rf"phase=snapshot-encoded request={request[0]} commandBufferToken=(\d+) "
                               r"textureToken=(\d+) width=(\d+) height=(\d+)")
            receipts = list(re.finditer(receipt_pattern, log))
            self.assertEqual(len(receipts), 1)
            receipt = receipts[0]
            matched = terminal_composition_snapshot({"status": "captured", "request_id": int(request[0]),
                "command_buffer_token": receipt[1], "texture_token": receipt[2],
                "source_width": int(receipt[3]), "source_height": int(receipt[4])}, observations)
            self.assertTrue(matched["composition_receipt_matched"], matched)
            event = next(e for e in observations["events"]
                         if e["captureRequestID"] == int(request[0]) and e["commandBufferToken"] == receipt[1])
            self.assertEqual(event["truncatedRows"], 0)
            self.assertEqual(event["gpuStatus"], "completed")
            event_position = log.index("MWX SCENE COMPOSITION OBSERVATION: " + next(
                line.split("MWX SCENE COMPOSITION OBSERVATION: ", 1)[1]
                for line in log.splitlines() if "MWX SCENE COMPOSITION OBSERVATION: " in line
                and json.loads(line.split("MWX SCENE COMPOSITION OBSERVATION: ", 1)[1]) == event))
            self.assertLess(receipt.start(), event_position)
            self.assertEqual(receipt.start() < update_position, reason == "ready")
            frames = [c for c in clocks if c["kind"] == "frame" and c["stream"] == event["displayID"]]
            lower = max((c for c in frames if c["frame"] <= event["frameIndex"]), key=lambda c: c["frame"])
            upper = min((c for c in frames if c["frame"] >= event["frameIndex"]), key=lambda c: c["frame"])
            self.assertTrue(lower["observationComplete"] and upper["observationComplete"])
            self.assertEqual(lower["frame"], lower["snapshotFrame"])
            self.assertEqual(upper["frame"], upper["snapshotFrame"])
            self.assertEqual(lower["generation"], upper["generation"])
            self.assertLessEqual(upper["sceneTime"] - lower["sceneTime"], .4)
            visible = settings["initialVisible"] if reason == "ready" else not settings["initialVisible"]
            rows = event["rows"]
            root_rows = [r for r in rows if r.get("layerID") == ids["composition"]]
            source = next(r for r in root_rows if r["kind"] == "sourceCapture" and r["outcome"] == "encoded")
            material = next(r for r in root_rows if r["kind"] == "material" and r["outcome"] == "draw-encoded")
            group = next(r for r in root_rows if r["kind"] == "group" and r["outcome"] == "draw-encoded")
            tail = next(r for r in root_rows if r["kind"] == "tail-consume" and r["outcome"] == "terminal-consumed")
            seal = next(r for r in rows if r["kind"] == "frame-seal" and r["outcome"] == "sealed")
            self.assertEqual(source["target"]["textureToken"], material["source"]["textureToken"])
            self.assertEqual(material["target"]["textureToken"], group["source"]["textureToken"])
            self.assertEqual(material["target"]["textureToken"], tail["source"]["textureToken"])
            self.assertEqual(group["target"]["textureToken"], seal["target"]["textureToken"])
            self.assertNotEqual(source["source"]["width"], source["source"]["height"])
            child_rows = [r for r in rows if r.get("layerID") == ids["child"]]
            sampled = [r for r in child_rows if r["kind"] == "material" and r["outcome"] == "draw-encoded"]
            peer = [r for r in rows if r.get("layerID") == ids["nonchild"]
                    and r["kind"] == "ordinary" and r["outcome"] == "draw-encoded"]
            self.assertEqual(bool(peer), visible)
            if visible:
                self.assertEqual(len(sampled), 1)
                sample = sampled[0]
                self.assertEqual(sample["slot"], settings["slot"])
                self.assertIn(settings["texturePath"], sample["source"]["logical"])
                self.assertEqual([sample["source"]["width"], sample["source"]["height"]], settings["rgbaExtent"])
                draw = next(r for r in child_rows if r["kind"] == "ordinary" and r["outcome"] == "draw-encoded")
                child_tail = next(r for r in child_rows if r["kind"] == "tail-consume"
                                  and r["outcome"] == "terminal-consumed")
                self.assertEqual(sample["target"]["textureToken"], draw["source"]["textureToken"])
                self.assertEqual(sample["target"]["textureToken"], child_tail["source"]["textureToken"])
                self.assertEqual(draw["target"]["textureToken"], source["source"]["textureToken"])
                self.assertNotEqual(draw["target"]["textureToken"], seal["target"]["textureToken"])
                self.assertLess(rows.index(draw), rows.index(source))
            else:
                self.assertFalse(sampled)
                self.assertFalse([r for r in child_rows if r["kind"] in ("ordinary", "tail-consume")])
                self.assertTrue(any(r["kind"] == "clear" and r["outcome"] == "encoded"
                                    and r["target"]["textureToken"] == source["source"]["textureToken"] for r in rows))
                self.assertTrue(any(r["kind"] == "group-background-capture" and r["outcome"] == "draw-encoded"
                                    and r["target"]["textureToken"] == source["source"]["textureToken"] for r in rows))
            readout.append({"capture": path.name, "visible": visible, "frame": event["frameIndex"],
                "generation": lower["generation"], "clockBracket": [lower["sceneTime"], upper["sceneTime"]],
                "request": int(request[0]), "commandBuffer": receipt[1], "surface": event["surfaceIdentity"],
                "sealedTexture": receipt[2], "sourceExtent": [int(receipt[3]), int(receipt[4])],
                "rows": [r for r in rows if r.get("layerID") in (ids["child"], ids["composition"], ids["nonchild"])
                         or r["kind"] in ("clear", "group-background-capture", "frame-seal")]})
        self.assertEqual(len({r["surface"] for r in readout}), 1)
        by_capture = {r["capture"]: r for r in readout}
        self.assertGreater(by_capture["scene-after-window.png"]["generation"],
                           by_capture["scene-ready-window.png"]["generation"])
        (evidence.parent / "quad-input-readout.json").write_bytes(encoded(readout))

    def run_case(self, **parameters):
        protocol = preregistration(**parameters)
        project, entries = fixture_entries(**parameters)
        project_bytes = encoded(project)
        package = make_package(list(entries.items()))
        inputs = {name: hashlib.sha256(value).hexdigest() for name, value in entries.items()}
        inputs.update({"project.json": hashlib.sha256(project_bytes).hexdigest(),
                       "scene.pkg": hashlib.sha256(package).hexdigest()})
        self.assertEqual(app_hashes(self.app), self.frozen_app_hashes,
                         "App changed since this integration suite began")
        with tempfile.TemporaryDirectory(prefix="mwx-composition-authored-order-") as temporary:
            root = Path(temporary)
            content, home, evidence = root / "content", root / "home", root / "evidence"
            content.mkdir()
            home.mkdir()
            (content / "project.json").write_bytes(project_bytes)
            (content / "scene.pkg").write_bytes(package)
            (root / "preregistration.json").write_bytes(encoded(protocol))
            env = os.environ.copy()
            if "quadInput" in protocol:
                for key in tuple(env):
                    if key.startswith(("MWX_SCENE_", "MYWALLPAPERX_SCENE_DEBUG_")):
                        del env[key]
                env["MYWALLPAPERX_SCENE_DEBUG_TIMELINE_EVIDENCE"] = json.dumps({
                    "layerIDs": protocol["quadInput"]["cohortLayerIDs"],
                    "sceneTimeWindow": [0, 8], "interval": .25, "maxSamples": 32})
            env.update(HOME=str(home), CFFIXED_USER_HOME=str(home),
                       MWX_SCENE_DEBUG_SURFACE_COUNT="1",
                       MWX_SCENE_GENERIC_SHADER_CACHE=str(root / "shader-cache"))
            command = [str(self.app), "--mwx-debug-scene-root", str(content),
                       "--mwx-debug-scene-duration", "7",
                       "--mwx-debug-scene-evidence-dir", str(evidence)]
            if settings := protocol.get("quadInput"):
                command += ["--mwx-debug-scene-after-snapshot-delay", str(settings["afterDelay"]),
                            "--mwx-debug-scene-live-property-sequence-json", json.dumps(settings["sequence"])]
            identity = {"command": command, "appSHA256": self.frozen_app_hashes,
                        "inputSHA256": inputs,
                        "testSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
            log, pixels = "", {}
            try:
                result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=70)
                log = result.stdout + result.stderr
                identity["returncode"] = result.returncode
                (root / "app.log").write_text(log)
                preview = "\n".join(path.read_text() for path in evidence.glob("*preview*.log"))
                captures = sorted(evidence.glob("*-window.png"))
                pixels = {path.name: measure_capture(path, protocol) for path in captures}
                (root / "pixels.json").write_bytes(encoded(pixels))
                self.assertEqual(result.returncode, 0, log[-6000:])
                self.assertIn("gpuDrained=true", log)
                self.assertRegex(log, r"state=completed frame=[1-9]\d* surface=\d+ gpu=completed")
                self.assertGreaterEqual(len(captures), 2, log[-6000:])
                self.assertIn("scene-ready-window.png", pixels)
                self.assertIn("scene-after-window.png", pixels)
                for reason in ("ready", "after"):
                    self.assertRegex(log, rf"phase=snapshot reason={reason} request=\d+ source=metal ")
                self.assertNotRegex(log, r"phase=snapshot-(?:failed|rejected)")
                needs_visible_effect = (parameters.get("effect", True)
                                        and parameters.get("enabled", True)
                                        and not (parameters.get("childless", False)
                                                 and parameters.get("copy_background") is False))
                if needs_visible_effect:
                    root_id = protocol.get("layerIDs", LAYER_IDS)["composition"]
                    self.assertRegex(log + preview, rf"generic shader execution [^\n]*layer={root_id} effect=0 ")
                if parameters.get("quad", False):
                    quad_id = protocol["layerIDs"]["child"]
                    self.assertRegex(log + preview, rf"generic shader execution [^\n]*layer={quad_id} effect=0 ")
                if transition := protocol.get("visibilityTransition"):
                    self.assertRegex(log, rf"layer={transition['layer']} source=sceneScript value=false effective=false")
                if "quadInput" in protocol:
                    self.check_quad_input_captures(protocol, log, captures, evidence)
                for name, measurement in pixels.items():
                    for roi, value in measurement["rois"].items():
                        with self.subTest(capture=name, roi=roi):
                            self.assertGreater(value["total"], 0, value)
                            self.assertGreaterEqual(value["correct"] / value["total"],
                                                    MINIMUM_CORRECT_FRACTION, value)
                            self.assertTrue(all(abs(actual - expected) <= CHANNEL_TOLERANCE
                                                for actual, expected in zip(value["centerRGB"], value["expectedRGB"])),
                                            value)
                self.assertEqual(app_hashes(self.app), self.frozen_app_hashes,
                                 "App changed while the integration case ran")
                return log, pixels
            except subprocess.TimeoutExpired as error:
                log = "".join(value.decode(errors="replace") if isinstance(value, bytes) else value or ""
                              for value in (error.stdout, error.stderr))
                (root / "app.log").write_text(log)
                identity["failure"] = "subprocess-timeout"
                raise
            finally:
                identity["appSHA256After"] = app_hashes(self.app)
                (root / "identity.json").write_bytes(encoded(identity))
                # Keep final evidence only when explicitly requested by the run.
                # The isolated HOME, cache, and extracted fixture are temporary.
                if destination := os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE"):
                    saved = Path(destination) / self._testMethodName
                    saved.mkdir(parents=True, exist_ok=True)
                    for name in ("content", "evidence"):
                        if (root / name).exists():
                            shutil.copytree(root / name, saved / name, dirs_exist_ok=True)
                    for path in root.glob("*.json"):
                        shutil.copy2(path, saved / path.name)
                    if (root / "app.log").exists():
                        shutil.copy2(root / "app.log", saved / "app.log")

    def test_effect_off_preserves_owned_geometry_and_colors(self):
        self.run_case(enabled=False)

    def test_missing_copybackground_inverts_background_child_and_prior_nonchild(self):
        self.run_case()

    def test_true_copybackground_matches_missing_field(self):
        self.run_case(copy_background=True)

    def test_false_copybackground_preserves_background_and_nonchild(self):
        self.run_case(copy_background=False)

    def test_nonchild_after_root_remains_red(self):
        self.run_case(order="nonchild-after-root")

    def test_child_before_root_still_enters_group(self):
        self.run_case(order="child-before-root")

    def test_no_effect_group_keeps_child_and_authored_peer(self):
        self.run_case(effect=False)

    def test_childless_false_copybackground_preserves_yellow_base(self):
        self.run_case(childless=True, copy_background=False)

    def test_childless_true_copybackground_inverts_yellow_base(self):
        self.run_case(childless=True, copy_background=True)

    def test_hidden_next_frame_child_reveals_fresh_copied_background(self):
        self.run_case(hide_child_next_frame=True)

    def test_transform_container_effect_keeps_scaled_wings(self):
        self.run_case(copy_background=True, container=True)

    def test_transform_container_effect_off_keeps_scaled_wings(self):
        self.run_case(copy_background=True, container=True, enabled=False)

    def test_hidden_transform_container_reveals_fresh_background(self):
        self.run_case(copy_background=True, container=True, hide_container_next_frame=True)

    def test_renamed_transform_chain_before_root_keeps_authored_order(self):
        self.run_case(copy_background=True, container=True, renamed=True, order="child-before-root")

    def test_parented_quad_program_uses_transform_container_raster(self):
        self.run_case(copy_background=True, container=True, quad=True)

    def test_parented_quad_samples_slot0_and_enables_with_healthy_cohort(self):
        self.run_case(copy_background=True, container=True, quad=True,
                      quad_input={"slot": 0, "initialVisible": False})

    def test_renamed_nested_quad_samples_slot3_and_clears_after_cohort_hides(self):
        self.run_case(copy_background=True, container=True, quad=True, renamed=True,
                      order="child-before-root", quad_input={"slot": 3, "initialVisible": True})

    def test_project_omitted_background_inverts_prior_scene_and_child(self):
        self.run_case(project_layer=True)

    def test_project_false_background_preserves_background_and_nonchild(self):
        self.run_case(project_layer=True, copy_background=False)

    def test_project_renamed_transform_chain_keeps_members_at_root_cut(self):
        self.run_case(project_layer=True, container=True, renamed=True, order="child-before-root")

    def test_project_inactive_effect_keeps_group_members(self):
        self.run_case(project_layer=True, enabled=False)

    def test_project_missing_effect_keeps_group_members(self):
        self.run_case(project_layer=True, effect=False)


if __name__ == "__main__":
    unittest.main()
