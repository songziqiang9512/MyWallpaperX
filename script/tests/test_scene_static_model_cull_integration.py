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
import subprocess
import tempfile
import unittest

from script.tests import test_scene_static_model_reader as reader
from script.tests.test_scene_directional_shadow_integration import png, quad
from script.tests.test_scene_static_model_parts import join_parts
from script.tests.test_scene_pkg_cache_extractor import make_package
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
    "test_scene_pkg_cache_extractor.py", "test_scene_fullscreen_visibility_integration.py"
)) + (REPO / "script/web_benchmark_capture.py",)


def encoded(value):
    return json.dumps(value, sort_keys=True).encode()


def fixture_entries(*, cast=True, all_nocull=False):
    entries, parts, cases = {}, [], []
    for column, (state, raw) in enumerate(STATES):
        x = 30 + column * 35
        for reverse in (False, True):
            y = 32 if not reverse else 64
            name = f"{state}-{'reverse' if reverse else 'front'}"
            material = f"materials/{name}.json"
            model = quad(x - 3, x + 3, y - 4, y + 4, 20, material)
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
            if all_nocull or raw is not None:
                render_pass["cullmode"] = "nocull" if all_nocull else raw
            entries[material] = encoded({"passes": [render_pass]})
            cases.append({"name": name, "state": state, "reverse": reverse,
                "material": material, "colorPoint": [x, y], "shadowPoint": [x - 12, y],
                "visible": all_nocull or not reverse or state == "nocull",
                "shadowed": cast and (all_nocull or not reverse or state == "nocull")})
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
    # This geometric oracle is fixed before GPU execution. A ray from each
    # shadow ROI toward +X,+Z travels 20 in Z and 12 in X, hitting only its part.
    for case in cases:
        hit = [case["shadowPoint"][0] + 12, case["shadowPoint"][1]]
        case["rayHitParts"] = [i for i, other in enumerate(cases)
            if abs(hit[0] - other["colorPoint"][0]) <= 3
            and abs(hit[1] - other["colorPoint"][1]) <= 4]
    return scene, entries, cases


def measure(path, cases):
    decoded = png_rgb_pixels(path)
    if decoded is None:
        raise AssertionError(f"invalid PNG: {path}")
    width, height, rows = decoded
    scale = max(width / CANVAS[0], height / CANVAS[1])
    points = {f"{case['name']}-{kind}": case[f"{kind}Point"]
              for case in cases for kind in ("color", "shadow")}
    points.update(healthy=[145, 80], clear=[80, 16])
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

    def run_case(self, name, **options):
        if name in self.runs:
            return self.runs[name]
        work = self.root / name
        (work / "content").mkdir(parents=True)
        (work / "home").mkdir()
        scene, entries, cases = fixture_entries(**options)
        (work / "content/project.json").write_bytes(encoded({"type": "scene", "file": "scene.json"}))
        (work / "content/scene.pkg").write_bytes(make_package(list(entries.items())))
        inputs = tuple((work / "content").iterdir())
        identity = {"app": self.app_identity, "sources": self.source_identity,
            "inputs": file_hashes(inputs), "entries": {
                key: hashlib.sha256(data).hexdigest() for key, data in entries.items()}}
        (work / "scene-input.json").write_bytes(encoded(scene))
        (work / "preregistration.json").write_bytes(encoded({"canvas": CANVAS, "cases": cases,
            "tolerance": TOLERANCE, "colorVisibleRGB": [0, 200, 0], "healthyRGB": [0, 0, 255],
            "shadowDarkeningMinimum": 20, "unoccludedReceiverMinimum": 50,
            "oracle": "each z20 quad shadows only its x-12 receiver point; cull closes both color and shadow",
            "evidenceBoundary": "owned static MDL cull cases, no official pixel parity"}))
        command = [str(self.exe), "--mwx-debug-scene-root", str(work / "content"),
            "--mwx-debug-scene-duration", "6", "--mwx-debug-scene-evidence-dir", str(work / "evidence")]
        (work / "prerun.json").write_bytes(encoded({**identity, "command": command}))
        self.assertEqual(app_hashes(self.exe), self.app_identity)
        self.assertEqual(file_hashes(SOURCES), self.source_identity)
        env = {key: value for key, value in os.environ.items()
               if not key.startswith(("MWX_SCENE_DEBUG_", "MYWALLPAPERX_SCENE_DEBUG_"))}
        env.update(HOME=str(work / "home"), CFFIXED_USER_HOME=str(work / "home"),
            MWX_SCENE_DEBUG_SURFACE_COUNT="1", MWX_SCENE_GENERIC_SHADER_CACHE=str(work / "cache"))
        with (work / "app.log").open("w") as output:
            result = subprocess.run(command, cwd=REPO, env=env, stdout=output,
                stderr=subprocess.STDOUT, timeout=90)
        log = (work / "app.log").read_text()
        pixels = {phase: measure(work / f"evidence/scene-{phase}-window.png", cases)
                  for phase in ("ready", "after")}
        report = {"exit": result.returncode, "pixels": pixels, "cases": cases,
            "shadowEvents": [line for line in log.splitlines() if "shadow phase=" in line],
            "appAfter": app_hashes(self.exe), "sourcesAfter": file_hashes(SOURCES),
            "inputsAfter": file_hashes(inputs)}
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
        self.assertIn("prepared static model layers: [1, 2, 4]", preview)
        self.assertEqual(pixels["ready"], pixels["after"])
        for phase in ("ready", "after"):
            self.assert_rgb(pixels[phase]["pixels"]["healthy"], [0, 0, 255])
            self.assertGreater(min(pixels[phase]["pixels"]["clear"]), 50)
            self.assertRegex(log, rf"phase=snapshot reason={phase} request=\d+ source=metal ")
        self.runs[name] = report
        return report

    def assert_rgb(self, actual, expected):
        for value, wanted in zip(actual, expected):
            self.assertAlmostEqual(value, wanted, delta=TOLERANCE)

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


if __name__ == "__main__":
    unittest.main()
