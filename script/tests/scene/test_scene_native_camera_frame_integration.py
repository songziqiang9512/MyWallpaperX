#!/usr/bin/env python3
"""Native camera matrices and ordered background capture through the Debug App.

Both arms have identical authored transforms and differ only in the constant
Vec3 returned by the camera's angles script. This checks owned geometry and
the actual Debug App/Metal/compositor chain, without an official parity claim.
"""
from __future__ import annotations

import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from script.tests.scene import test_scene_native_world_composition as world
from script.tests.scene.test_scene_native_world_composition import encoded, mdl_quad, model_material, png
from script.tests.support.scene_pkg_fixture import make_package
from script.tests.scene.test_scene_reflection_history_integration import METAL_FAILURE, sha256
from script.tests.support.scene_color_blend_capture_test_support import assert_main_background_reader
from script.web.web_benchmark_capture import png_rgb_pixels


REPO = Path(__file__).resolve().parents[3]
CAMERA_ID = 7
BACKGROUND = (18, 30, 44)
MARKS = {"nearAmber": {"point": [-1.3, .9, 1.], "RGB": (232, 95, 20)},
         "farGreen": {"point": [.7, -.6, -1.2], "RGB": (20, 220, 60)}}
# Independent double pinhole projection, frozen before any App capture.
# Screen center + H * (x,y); camera eye (0,0,6), RY(.3)*RX(.2), FOV60.
OFFSETS = {
    "seed": {"nearAmber": (-.2251666049839541, -.15588457268119899),
             "farGreen": (.08419691425682044, .07216878364870323)},
    "rotated": {"nearAmber": (.03897249233595766, .023688819128118037),
                "farGreen": (.3772681149624183, .2581432630662912)}}
TOPOLOGY_OFFSETS = {**OFFSETS,
    "general": {"nearAmber": (-.28947877142104556, -.08872301780410938),
                "farGreen": (.11983285925962964, .006218505142546705)}}
TOLERANCE = 4
SOURCES = tuple(REPO / path for path in (
    "script/tests/scene/test_scene_native_camera_frame_integration.py",
    "script/tests/scene/test_scene_native_world_composition.py",
    "script/tests/scene/test_scene_static_model_reader.py",
    "script/tests/support/scene_color_blend_capture_test_support.py",
    "script/tests/support/scene_pkg_fixture.py",
    "script/tests/scene/test_scene_reflection_history_integration.py",
    "script/web/web_benchmark_capture.py"))


def fixture_entries(arm: str, topology_action: str | None = None) -> dict[str, bytes]:
    # The existing SceneScript producer converts authored degrees to typed
    # radians. Hold the runtime angles at (.2,.3,0), independently of time.
    value = "0,0,0" if arm == "seed" else "0.2*180/Math.PI,0.3*180/Math.PI,0"
    scene = {"version": 3,
        "camera": {"eye": "0.7 3 6", "center": "0 0 0", "up": "0 1 0"},
        "general": {"orthogonalprojection": None, "fov": 47, "nearz": .1,
            "farz": 100, "clearcolor": "0 0 0", "clearenabled": True,
            "hdr": False, "bloom": False, "ambientcolor": "0 0 0",
            "skylightcolor": "0 0 0", "cameraparallax": False, "camerashake": False},
        "objects": [
            {"id": 1, "model": "models/background.mdl", "origin": "0 0 0",
             "perspective": True, "castshadow": False},
            {"id": 2, "model": "models/amber_stem.mdl", "origin": "0 0 0",
             "perspective": True, "castshadow": False},
            {"id": 3, "model": "models/amber_foot.mdl", "origin": "0 0 0",
             "perspective": True, "castshadow": False},
            {"id": 4, "model": "models/green.mdl", "origin": "0 0 0",
             "perspective": True, "castshadow": False},
            {"id": CAMERA_ID, "camera": "default", "path": "paths/owned_camera.json",
             "origin": "0 0 6", "fov": 60,
             "angles": {"value": "0 0 0", "script":
                 f"export function update() {{ return new Vec3({value}); }}"}}]}
    if topology_action:
        camera = scene["objects"][-1]
        camera["name"] = "Camera A"
        camera["angles"]["script"] = "export function update() { return new Vec3(0,0,0); }"
        scene["objects"].append({**camera, "id": 9, "name": "Camera B",
            "path": "paths/second_camera.json", "angles": {"value": "0 0 0", "script":
                "export function update() { return new Vec3(0.2*180/Math.PI,0.3*180/Math.PI,0); }"}})
        action = {"delete": "thisScene.destroyLayer('Camera B');",
            "sort": "thisScene.sortLayer(thisScene.getLayer('Camera A'), 6);",
            "all-removed": "thisScene.destroyLayer('Camera B'); thisScene.destroyLayer('Camera A');"}[topology_action]
        scene["objects"].append({"id": 10, "name": "Topology controller",
            "image": "models/util/solidlayer.json", "origin": "0 0 0", "size": "1 1",
            "perspective": False, "alpha": 0, "visible": {"value": True, "script":
                "let changed=false; export function update(value) { "
                f"if (!changed && engine.runtime>=1.5) {{ {action} changed=true; }} return true; }}"}})
    entries = {"scene.json": encoded(scene),
        "models/background.mdl": mdl_quad(-12, 12, -9, 9, -3, "materials/background.json"),
        "models/amber_stem.mdl": mdl_quad(-1.47, -1.13, .72, 1.38, 1, "materials/amber.json"),
        "models/amber_foot.mdl": mdl_quad(-1.47, -.88, .60, .78, 1, "materials/amber.json"),
        "models/green.mdl": mdl_quad(.56, .84, -.98, -.22, -1.2, "materials/green.json")}
    for label, color in {"background": BACKGROUND, "amber": MARKS["nearAmber"]["RGB"],
                         "green": MARKS["farGreen"]["RGB"]}.items():
        entries[f"materials/{label}.json"] = model_material(f"materials/{label}.png")
        entries[f"materials/{label}.png"] = png(4, 4, lambda _x, _y, c=color: c)
    return entries


def background_cut_entries(*, sorting: bool, writes_depth: bool,
                           main_observer: bool = False, named_albedo: bool = False,
                           implicit_text: bool = False) -> dict[str, bytes]:
    scene = world.native_world_scene([
        {"id": 1, "model": "models/red_field.mdl", "perspective": True, "castshadow": False},
        {"id": 20, "image": "models/util/composelayer.json", "config": {"passthrough": True},
         "origin": "0 0 0", "size": "128 96", "scale": f"{2.4 / 128} {1.6 / 96} 1",
         "perspective": True, "effects": [{"id": 200, "file": "effects/shift_invert/effect.json",
                                          "visible": True}]},
        {"id": 21, "text": "HH", "font": "systemfont_arial", "pointsize": 24, "padding": 40,
         "color": "1 1 1", "origin": "-1.7 1.15 0", "scale": ".0055 .0055 1",
         "horizontalalign": "center", "verticalalign": "center",
         "depthtest": "enabled", "perspective": True},
        {"id": 30, "model": "models/green_marker.mdl", "perspective": True, "castshadow": False},
    ])
    if implicit_text:
        del scene["objects"][2]["depthtest"]
    scene["general"]["transparentsorting"] = sorting
    if main_observer:
        scene["objects"].insert(3, {"id": 22, "image": "models/prefix_filter.json",
            "origin": ".36 .56 0", "size": "128 96", "scale": f"{.38 / 128} {.24 / 96} 1",
            "perspective": True, "colorBlendMode": 2})
    marker = json.loads(model_material("_rt_imageLayerComposite_41_a" if named_albedo
                                      else "materials/green_marker.png"))
    if named_albedo:
        scene["objects"][-1]["dependencies"] = [41]
        scene["objects"].append({"id": 41, "image": "models/named_marker_source.json",
            "origin": "0 0 0", "size": "4 4", "visible": False,
            "effects": [{"id": 410, "file": "effects/named_marker/effect.json", "visible": True}]})
    if not writes_depth:
        marker["passes"][0]["depthwrite"] = "disabled"
    entries = {
        "scene.json": encoded(scene),
        "models/red_field.mdl": mdl_quad(-9, 9, -6, 6, -2, "materials/red_field.json"),
        "models/green_marker.mdl": mdl_quad(.14, 1.7, -.24, .24, -.6, "materials/green_marker.json"),
        "materials/red_field.json": model_material("materials/red_field.png"),
        "materials/green_marker.json": encoded(marker),
        "materials/red_field.png": png(4, 4, lambda _x, _y: (255, 0, 0)),
        "effects/shift_invert/effect.json": encoded({"passes": [{"material": "materials/shift_invert.json"}]}),
        "materials/shift_invert.json": encoded({"passes": [{
            "shader": "shift_invert", "textures": [None], "blending": "normal",
            "depthtest": "disabled", "depthwrite": "disabled", "cullmode": "nocull"}]}),
        "shaders/shift_invert.vert": world.EFFECT_VERTEX,
        "shaders/shift_invert.frag": b"""uniform sampler2D g_Texture0;
varying vec2 v_TexCoord;
void main() {
    vec3 color = texSample2D(g_Texture0, v_TexCoord + vec2(0.25, 0.0)).rgb;
    gl_FragColor = vec4(vec3(1.0) - color, 1.0);
}
""",
    }
    if not named_albedo or main_observer:
        entries["materials/green_marker.png"] = png(4, 4, lambda _x, _y: (0, 255, 0))
    if main_observer:
        entries["models/prefix_filter.json"] = encoded({"material": "materials/prefix_filter.json"})
        entries["materials/prefix_filter.json"] = encoded({"passes": [{
            "shader": "genericimage", "textures": ["materials/green_marker.png"]}]})
    if named_albedo:
        # Green exists only in the hidden provider's completed graph output.
        entries.update({
            "models/named_marker_source.json": encoded({"material": "materials/named_marker_source.json"}),
            "materials/named_marker_source.json": encoded({"passes": [{
                "shader": "genericimage", "textures": ["materials/red_field.png"]}]}),
            "effects/named_marker/effect.json": encoded({"passes": [{"material": "materials/named_marker.json"}]}),
            "materials/named_marker.json": encoded({"passes": [{
                "shader": "named_marker", "textures": [None], "blending": "normal",
                "depthtest": "disabled", "depthwrite": "disabled", "cullmode": "nocull"}]}),
            "shaders/named_marker.vert": world.EFFECT_VERTEX,
            "shaders/named_marker.frag": b"""uniform sampler2D g_Texture0;
varying vec2 v_TexCoord;
void main() { gl_FragColor = texSample2D(g_Texture0, v_TexCoord).brga; }
""",
        })
    return entries


def protocol() -> dict:
    return {"cameraLayer": CAMERA_ID, "authoredEye": [0, 0, 6], "authoredAngles": [0, 0, 0],
        "FOVDegrees": 60, "typedAngles": {"seed": [0, 0, 0], "rotated": [.2, .3, 0]},
        "marks": MARKS, "screenOffsetsPerHeight": OFFSETS, "radiusPixels": 2,
        "backgroundRGB": BACKGROUND, "tolerance": TOLERANCE,
        "qualification": "actual first completed Vec3 output for layer7.angles in each constant arm",
        "scriptAngleUnits": "authored degrees converted by the existing producer to typed radians",
        "invariants": "all model bytes/transforms, lights, general camera and native authored seed identical",
        "expected": "active projection ROIs contain each mark RGB; inactive ROIs exclude that mark RGB",
        "scope": "owned two-depth static geometry; no official, live-media or whole-scene parity"}


def measure(path: Path, offsets: dict = OFFSETS) -> dict:
    decoded = png_rgb_pixels(path)
    if decoded is None:
        raise AssertionError(f"undecodable capture: {path}")
    width, height, rows = decoded
    measured = {"size": [width, height], "ROIs": {}}
    for arm, marks in offsets.items():
        for label, (dx, dy) in marks.items():
            px, py = width / 2 + height * dx, height / 2 + height * dy
            bounds = (math.ceil(px - 2), math.ceil(py - 2), math.floor(px + 2), math.floor(py + 2))
            x0, y0, x1, y1 = bounds
            if not (0 <= x0 < x1 <= width and 0 <= y0 < y1 <= height):
                raise AssertionError(f"preregistered ROI cropped: {(arm, label, bounds)}")
            values = [rows[y][x * 3:x * 3 + 3] for y in range(y0, y1) for x in range(x0, x1)]
            measured["ROIs"][f"{arm}.{label}"] = {"bounds": bounds, "count": len(values),
                "mean": [sum(pixel[c] for pixel in values) / len(values) for c in range(3)]}
    return measured


def typed_angles(log: str, camera_id: int = CAMERA_ID) -> list[list[float]]:
    # Debug uses the Swift enum's qualified spelling for layer targets.
    outputs = re.findall(
        rf"target=layer\(layerID: {camera_id}, field: [^)]+\.angles\) callback=completed "
        r"type=vector3 input=.*? output=vector3\(([^)]+)\)", log)
    return [[float(v.strip()) for v in value.split(",")] for value in outputs]


def pixel_checks(results: dict, offsets: dict = OFFSETS, selections: dict | None = None) -> list[dict]:
    checks = []
    for arm, result in results.items():
        for phase, measured in result["pixels"].items():
            for roi_arm in offsets:
                for label, mark in MARKS.items():
                    occupied = (selections[arm][phase] if selections else arm) == roi_arm
                    expected = {"RGB" if occupied else "excludedRGB": mark["RGB"]}
                    actual = measured["ROIs"][f"{roi_arm}.{label}"]["mean"]
                    color_matches = all(abs(a - b) <= TOLERANCE for a, b in zip(actual, mark["RGB"]))
                    checks.append({"arm": arm, "phase": phase, "ROI": f"{roi_arm}.{label}",
                        "expected": expected, "actual": actual,
                        "passed": color_matches if occupied else not color_matches})
    return checks


class SceneNativeCameraFrameIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        configured = os.environ.get("MWX_SCENE_INTEGRATION_APP")
        if not configured:
            raise unittest.SkipTest("requires an explicitly frozen Debug App executable")
        cls.app = Path(configured).resolve(strict=True)
        paths = [cls.app, cls.app.with_name("MyWallpaperX.debug.dylib"),
                 cls.app.parent.parent / "Resources/default.metallib"]
        cls.app_hashes = {str(p): sha256(p) for p in paths if p.is_file()}
        cls.source_hashes = {str(p): sha256(p) for p in SOURCES}
        parent = os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE")
        if parent:
            Path(parent).mkdir(parents=True, exist_ok=True)
        cls.evidence_root = Path(tempfile.mkdtemp(prefix="native-camera-app-", dir=parent))
        registration = {"oracle": protocol(), "app": cls.app_hashes, "sources": cls.source_hashes,
            "entryHashes": {arm: {p: hashlib.sha256(v).hexdigest() for p, v in fixture_entries(arm).items()}
                            for arm in OFFSETS}}
        (cls.evidence_root / "preregistration.json").write_bytes(encoded(registration))
        print(f"Native camera App evidence: {cls.evidence_root}", flush=True)

    def run_arm(self, arm: str, topology_action: str | None = None) -> dict:
        work = self.evidence_root / (topology_action or arm)
        content, home, evidence = work / "content", work / "home", work / "evidence"
        content.mkdir(parents=True); home.mkdir()
        entries = fixture_entries(arm, topology_action)
        (content / "scene.pkg").write_bytes(make_package(list(entries.items())))
        (content / "project.json").write_bytes(encoded({"type": "scene", "file": "scene.json"}))
        (work / "scene-input.json").write_bytes(entries["scene.json"])
        inputs = [content / "scene.pkg", content / "project.json"]
        command = [str(self.app), "--mwx-debug-scene-root", str(content),
            "--mwx-debug-scene-duration", "6", "--mwx-debug-scene-evidence-dir", str(evidence)]
        environment = {k: v for k, v in os.environ.items()
            if not k.startswith(("MWX_SCENE_DEBUG_", "MYWALLPAPERX_SCENE_DEBUG_"))}
        controls = {"HOME": str(home), "CFFIXED_USER_HOME": str(home),
            "MWX_SCENE_DEBUG_SURFACE_COUNT": "1", "MWX_SCENE_GENERIC_SHADER_CACHE": str(work / "cache")}
        environment.update(controls)
        identity = {"command": command, "controls": controls,
            "appBefore": {p: sha256(Path(p)) for p in self.app_hashes},
            "sourceBefore": {p: sha256(Path(p)) for p in self.source_hashes},
            "inputBefore": {str(p): sha256(p) for p in inputs}}
        (work / "identity.json").write_bytes(encoded(identity))
        with (work / "app.log").open("w") as output:
            process = subprocess.run(command, cwd=REPO, env=environment, stdout=output,
                stderr=subprocess.STDOUT, timeout=70)
        log = (work / "app.log").read_text()
        typed = typed_angles(log)
        offsets = TOPOLOGY_OFFSETS if topology_action else OFFSETS
        pixels = {p.name: measure(p, offsets) for p in sorted(evidence.glob("*-window.png"))}
        identity.update(appAfter={p: sha256(Path(p)) for p in self.app_hashes},
            sourceAfter={p: sha256(Path(p)) for p in self.source_hashes},
            inputAfter={str(p): sha256(p) for p in inputs})
        result = {"returncode": process.returncode, "typedAngles": typed, "pixels": pixels,
            "topologyAction": topology_action, "secondCameraAngles": typed_angles(log, 9),
            "metalFailures": METAL_FAILURE.findall(log), "gpuDrained": "gpuDrained=true" in log,
            "completedFrames": re.findall(r"state=completed frame=(\d+) surface=\d+ gpu=completed", log),
            "immutable": all(identity[f"{key}Before"] == identity[f"{key}After"]
                             for key in ("app", "source", "input"))}
        (work / "identity.json").write_bytes(encoded(identity))
        (work / "result.json").write_bytes(encoded(result))
        # Transient homes and caches have no evidence value after normal exit.
        shutil.rmtree(home); shutil.rmtree(work / "cache", ignore_errors=True)
        self.assertEqual(process.returncode, 0, log[-6000:])
        self.assertTrue(result["immutable"], result)
        self.assertFalse(result["metalFailures"], result)
        self.assertTrue(result["gpuDrained"] and result["completedFrames"], result)
        self.assertRegex(log, r"phase=stopped surfacesBefore=1 surfacesAfter=0 gpuDrained=true")
        self.assertEqual(set(pixels), {"scene-ready-window.png", "scene-after-window.png"})
        self.assertEqual(len(typed), 1, "STOP_UNQUALIFIED: actual typed angle output missing")
        self.assertTrue(all(abs(a - b) < 1e-12 for a, b in zip(
            typed[0], protocol()["typedAngles"]["seed" if topology_action else arm], strict=True)),
            f"STOP_UNQUALIFIED: unexpected typed angles {typed}")
        if topology_action:
            self.assertEqual(len(result["secondCameraAngles"]), 1, result)
            self.assertTrue(all(abs(a - b) < 1e-12 for a, b in zip(
                result["secondCameraAngles"][0], [.2, .3, 0], strict=True)), result)
        return result

    def test_typed_native_angles_move_fixed_two_depth_markers(self):
        results = {arm: self.run_arm(arm) for arm in OFFSETS}
        checks = pixel_checks(results)
        (self.evidence_root / "pixel-checks.json").write_bytes(encoded(checks))
        self.assertTrue(all(c["passed"] for c in checks), [c for c in checks if not c["passed"]])

    def test_current_camera_topology_moves_fixed_markers_and_retires_output(self):
        selections = {action: {"scene-ready-window.png": "rotated",
            "scene-after-window.png": "general" if action == "all-removed" else "seed"}
            for action in ("delete", "sort", "all-removed")}
        registration = {"cameraLayerIDs": [7, 9], "actionsAtSceneTime": 1.5,
            "selections": selections, "screenOffsetsPerHeight": TOPOLOGY_OFFSETS,
            "generalCamera": {"eye": [.7, 3, 6], "center": [0, 0, 0], "up": [0, 1, 0], "fov": 47},
            "entryHashes": {action: {p: hashlib.sha256(v).hexdigest()
                for p, v in fixture_entries("seed", action).items()} for action in selections},
            "scope": "same authored models; current camera deletion/sort/default through real VM and compositor"}
        (self.evidence_root / "topology-preregistration.json").write_bytes(encoded(registration))
        results = {action: self.run_arm("seed", action) for action in selections}
        checks = pixel_checks(results, TOPOLOGY_OFFSETS, selections)
        (self.evidence_root / "topology-pixel-checks.json").write_bytes(encoded(checks))
        self.assertTrue(all(c["passed"] for c in checks), [c for c in checks if not c["passed"]])

    def test_native_background_cut_admits_only_the_sorted_depth_writer(self):
        self.app_identity, self.source_identity = self.app_hashes, self.source_hashes
        for name, sorting, writes_depth, observer, named_albedo in (
            ("sort-off", False, True, False, False), ("sort-on", True, True, False, False),
            ("read-only-model", True, False, False, False), ("main-reader", True, True, True, False),
            ("named-writer", True, True, False, True),
            ("implicit-text", True, True, False, False),
        ):
            with self.subTest(name=name):
                implicit_text = name == "implicit-text"
                moves = sorting and writes_depth and not (observer or named_albedo or implicit_text)
                entries = background_cut_entries(sorting=sorting, writes_depth=writes_depth,
                                                 main_observer=observer, named_albedo=named_albedo,
                                                 implicit_text=implicit_text)
                # Shift the right-side source marker to a witness the model
                # cannot subsequently cover. World x=-.36 maps to source
                # x=.24 on the card and x=.264 at the marker's depth.
                rois = {
                    "sampled-prefix": {"world": [-.36, 0., 0.],
                        "expectedRGB": (255, 0, 255) if moves else (0, 255, 255)},
                    "marker-outside-cut": {"world": [1.5, 0., -.6], "expectedRGB": (0, 255, 0)},
                    "background-outside-cut": {"world": [-2., 0., -2.], "expectedRGB": (255, 0, 0)},
                }
                if observer:
                    rois["main-reader"] = {"world": [.36, .56, 0.], "expectedRGB": (0, 255, 0)}
                label = "native-background-cut-" + name
                (self.evidence_root / f"{label}-preregistration.json").write_bytes(encoded({
                    "sorting": sorting, "modelWritesDepth": writes_depth, "modelBeforeSource": moves,
                    "mainColorObserver": 22 if observer else None,
                    "namedModelAlbedoProvider": 41 if named_albedo else None,
                    "regions": rois, "tolerance": TOLERANCE,
                    "entries": {path: hashlib.sha256(data).hexdigest() for path, data in entries.items()},
                }))
                with patch.object(world.app_runner, "measure_capture", world.measure_capture):
                    result = world.app_runner.SceneReflectionHistoryIntegrationTests.run_case(
                        self, 0, name=label, capture=True, entries=entries, rois=rois,
                        material_input_path="materials/green_marker.json")
                work = self.evidence_root / label
                log = (work / "app.log").read_text()
                if named_albedo:
                    self.assertIn("phase=named-graph-output-publication layer=41 status=succeeded", log)
                    self.assertIn("phase=named-target-binding layer=30 status=succeeded", log)
                captures = list(world.SceneNativeWorldCompositionTests.composition_captures(self, work, log))
                self.assertCountEqual([path.name for path, _ in captures], result["pixels"])
                for path, event in captures:
                    rows = event["rows"]
                    source, = (r for r in rows if r["kind"] == "sourceCapture"
                               and r.get("layerID") == 20 and r.get("outcome") == "encoded")
                    paint, = (r for r in rows if r["kind"] == "material"
                              and r.get("layerID") == 20 and r.get("effectIndex") == 0
                              and r.get("outcome") == "draw-encoded")
                    group, = (r for r in rows if r["kind"] == "group"
                              and r.get("layerID") == 20 and r.get("outcome") == "draw-encoded")
                    model, = (r for r in rows if r["kind"] == "model"
                              and r.get("layerID") == 30 and r.get("outcome") == "draw-encoded")
                    seal, = (r for r in rows if r["kind"] == "frame-seal" and r["outcome"] == "sealed")
                    self.assertEqual(source["source"]["textureToken"], model["target"]["textureToken"])
                    self.assertEqual(source["target"]["textureToken"], paint["source"]["textureToken"])
                    self.assertEqual(paint["target"]["textureToken"], group["source"]["textureToken"])
                    self.assertEqual(group["target"]["textureToken"], seal["target"]["textureToken"])
                    reads = ()
                    if observer:
                        self.assertEqual(source["source"]["textureToken"], seal["target"]["textureToken"])
                        reads = assert_main_background_reader(self, rows, 22, seal["target"])
                    if named_albedo:
                        provider_paint, = (r for r in rows if r["kind"] == "material" and r.get("layerID") == 41
                                           and r.get("effectIndex") == 0 and r.get("outcome") == "draw-encoded")
                        published, = (r for r in rows if r["kind"] == "tail-consume" and r.get("layerID") == 41
                                      and r.get("access") == "named-publication-only"
                                      and r.get("outcome") == "terminal-consumed")
                        self.assertEqual(provider_paint["target"]["textureToken"], published["source"]["textureToken"])
                        self.assertLess(rows.index(provider_paint), rows.index(published))
                        self.assertLess(rows.index(published), rows.index(model))
                        self.assertEqual(model["slot"], 0)
                        self.assertNotEqual(model["source"]["textureToken"],
                                            provider_paint["source"]["textureToken"])
                        for axis in ("width", "height"):
                            self.assertEqual(model["source"][axis], published["source"][axis])
                        self.assertEqual(model["details"]["depthTest"], "true")
                        self.assertEqual(model["details"]["depthWrite"], "true")
                    cut = (source, paint, group)
                    timeline = (model, *cut, seal) if moves else (*cut, *reads, model, seal)
                    positions = [rows.index(row) for row in timeline]
                    self.assertEqual(positions, sorted(positions))
                    for name, info in rois.items():
                        measured = result["pixels"][path.name][name]
                        self.assertGreater(measured["count"], 0, (label, path.name, name))
                        for bound in ("minimum", "maximum"):
                            for actual, expected in zip(measured[bound], info["expectedRGB"], strict=True):
                                self.assertAlmostEqual(actual, expected, delta=TOLERANCE,
                                    msg=str((label, path.name, name, measured)))


if __name__ == "__main__":
    unittest.main()
