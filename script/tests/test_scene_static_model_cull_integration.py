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
from script.tests.test_scene_static_model_parts import join_parts
from script.tests.scene_pkg_fixture import make_package
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
    "scene_pkg_fixture.py", "test_scene_fullscreen_visibility_integration.py"
)) + (REPO / "script/web_benchmark_capture.py",)


def encoded(value):
    return json.dumps(value, sort_keys=True).encode()


def fixture_entries(*, cast=True, all_nocull=False, texture_case=None, frame_phase=None, noise_case=None,
                    affine_case=None):
    if noise_case is not None:
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
            if texture_case is not None:
                render_pass.update(textures=["materials/model-surface.tex"], blending="translucent")
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
    # This geometric oracle is fixed before GPU execution. A ray from each
    # shadow ROI toward +X,+Z travels 20 in Z and 12 in X, hitting only its part.
    for case in cases:
        hit = [case["shadowPoint"][0] + 12, case["shadowPoint"][1]]
        case["rayHitParts"] = ([0] if texture_case is not None else [i for i, other in enumerate(cases)
            if abs(hit[0] - other["colorPoint"][0]) <= 3
            and abs(hit[1] - other["colorPoint"][1]) <= 4])
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

    def run_case(self, name, *, fixed_scene_time=None, **options):
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
            "tolerance": TOLERANCE,
            "colorVisibleRGB": ({case["name"]: case["rgba"] for case in cases}
                if options.get("texture_case") or options.get("affine_case") else [0, 200, 0]), "healthyRGB": [0, 0, 255],
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
               if options.get("affine_case") else {})}))
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
        pixels = {phase: measure(work / f"evidence/scene-{phase}-window.png", cases)
                  for phase in ("ready", "after")}
        report = {"exit": result.returncode, "pixels": pixels, "cases": cases,
            "shadowEvents": [line for line in log.splitlines() if "shadow phase=" in line],
            "appAfter": app_hashes(self.exe), "sourcesAfter": file_hashes(SOURCES),
            "inputsAfter": file_hashes(inputs)}
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
        if options.get("texture_case") != "animated" and not options.get("affine_case"):
            expected_prepared = "[1, 4]" if options.get("texture_case") == "zero" else "[1, 2, 4]"
            self.assertIn("prepared static model layers: " + expected_prepared, preview)
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

    def assert_texture_coverage(self, result):
        for phase in ("ready", "after"):
            reference = result["pixels"][phase]["pixels"]
            for case in result["cases"]:
                color, shadow = f"{case['name']}-color", f"{case['name']}-shadow"
                if case["visible"]:
                    self.assert_rgb(reference[color], case["rgba"][:3])
                    self.assertLess(max(reference[shadow]), 15)
                else:
                    self.assert_rgb(reference[color], reference["clear"])
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


if __name__ == "__main__":
    unittest.main()
