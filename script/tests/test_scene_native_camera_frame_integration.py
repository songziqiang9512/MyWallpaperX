#!/usr/bin/env python3
"""A current typed native-camera transform reaches fixed two-depth models.

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

from script.tests.test_scene_native_world_composition import encoded, mdl_quad, model_material, png
from script.tests.test_scene_pkg_cache_extractor import make_package
from script.tests.test_scene_reflection_history_integration import METAL_FAILURE, sha256
from script.web_benchmark_capture import png_rgb_pixels


REPO = Path(__file__).resolve().parents[2]
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
TOLERANCE = 4
SOURCES = tuple(REPO / path for path in (
    "script/tests/test_scene_native_camera_frame_integration.py",
    "script/tests/test_scene_native_world_composition.py",
    "script/tests/test_scene_static_model_reader.py",
    "script/tests/test_scene_pkg_cache_extractor.py",
    "script/tests/test_scene_reflection_history_integration.py",
    "script/web_benchmark_capture.py"))


def fixture_entries(arm: str) -> dict[str, bytes]:
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


def measure(path: Path) -> dict:
    decoded = png_rgb_pixels(path)
    if decoded is None:
        raise AssertionError(f"undecodable capture: {path}")
    width, height, rows = decoded
    measured = {"size": [width, height], "ROIs": {}}
    for arm, marks in OFFSETS.items():
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


def typed_angles(log: str) -> list[list[float]]:
    # Debug uses the Swift enum's qualified spelling for layer targets.
    outputs = re.findall(
        r"target=layer\(layerID: 7, field: [^)]+\.angles\) callback=completed "
        r"type=vector3 input=.*? output=vector3\(([^)]+)\)", log)
    return [[float(v.strip()) for v in value.split(",")] for value in outputs]


def pixel_checks(results: dict) -> list[dict]:
    checks = []
    for arm, result in results.items():
        for phase, measured in result["pixels"].items():
            for roi_arm in OFFSETS:
                for label, mark in MARKS.items():
                    occupied = arm == roi_arm
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

    def run_arm(self, arm: str) -> dict:
        work = self.evidence_root / arm
        content, home, evidence = work / "content", work / "home", work / "evidence"
        content.mkdir(parents=True); home.mkdir()
        entries = fixture_entries(arm)
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
        pixels = {p.name: measure(p) for p in sorted(evidence.glob("*-window.png"))}
        identity.update(appAfter={p: sha256(Path(p)) for p in self.app_hashes},
            sourceAfter={p: sha256(Path(p)) for p in self.source_hashes},
            inputAfter={str(p): sha256(p) for p in inputs})
        result = {"returncode": process.returncode, "typedAngles": typed, "pixels": pixels,
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
            typed[0], protocol()["typedAngles"][arm], strict=True)),
            f"STOP_UNQUALIFIED: unexpected typed angles {typed}")
        return result

    def test_typed_native_angles_move_fixed_two_depth_markers(self):
        results = {arm: self.run_arm(arm) for arm in OFFSETS}
        checks = pixel_checks(results)
        (self.evidence_root / "pixel-checks.json").write_bytes(encoded(checks))
        self.assertTrue(all(c["passed"] for c in checks), [c for c in checks if not c["passed"]])


if __name__ == "__main__":
    unittest.main()
