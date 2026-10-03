#!/usr/bin/env python3
"""RF04 A: completed scene color reaches default F5 in a frozen real App.

Set MWX_SCENE_INTEGRATION_APP to a frozen Debug executable. Evidence is kept
under MWX_SCENE_INTEGRATION_EVIDENCE, or a printed task-specific temp root.
All media are authored here. This gate does not exercise the blocked authored
environment provider, official mip parity, HDR, or alpha behavior.
"""
from __future__ import annotations

import hashlib
import json
import math
import os
from pathlib import Path
import re
import struct
import subprocess
import tempfile
import unittest
import zlib

from script.tests.test_scene_pkg_cache_extractor import make_package
from script.web_benchmark_capture import png_rgb_pixels


REPO = Path(__file__).resolve().parents[2]
CANVAS = (160, 96)
NORMAL_RGB = (230, 128, 204)
ROIS = {"receiver": (80, 48), "lateRed": (140, 48), "greenPeer": (20, 80)}
PIXEL_TOLERANCE = 4
METAL_FAILURE = re.compile(
    r"MTLCommandBufferErrorDomain|Metal Validation Error|failed assertion"
    r"|gpu-command-buffer-failed|failure=exception"
    r"|execution of the command buffer was aborted"
    r"|framebufferOnly[^\n]*(?:must not|cannot|invalid)"
    r"|MTL[^\n]*(?:validation error|execution failed)", re.IGNORECASE
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def rgba_png(rgb: tuple[int, int, int]) -> bytes:
    def chunk(kind: bytes, data: bytes) -> bytes:
        return (struct.pack(">I", len(data)) + kind + data
                + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF))
    scanlines = (b"\0" + bytes((*rgb, 255)) * 4) * 4
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", 4, 4, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(scanlines)) + chunk(b"IEND", b""))


def fixture_entries(reflection: int) -> dict[str, bytes]:
    # Runtime/Frame/SceneRenderDescriptor preserves objects.map(id) as order.
    # The receiver precedes this red suffix and does not overlap it.
    scene = {
        "version": 3,
        "general": {
            "orthogonalprojection": {"width": CANVAS[0], "height": CANVAS[1]},
            "clearcolor": "0 0 0", "clearenabled": True, "hdr": False,
            "ambientcolor": "0 0 0", "skylightcolor": "0 0 0",
        },
        "objects": [
            {"id": 1, "name": "Default F5 receiver", "image": "models/receiver.json",
             "origin": "80 48 0", "size": "40 40"},
            {"id": 2, "name": "Late red source", "image": "models/util/solidlayer.json",
             "origin": "140 48 0", "size": "40 96", "color": "1 0 0"},
            {"id": 3, "name": "Healthy green peer", "image": "models/util/solidlayer.json",
             "origin": "20 16 0", "size": "12 12", "color": "0 1 0"},
        ],
    }
    material = {"passes": [{
        "shader": "genericimage2", "textures": ["materials/albedo.png", "materials/normal.png"],
        "combos": {"LIGHTING": 0, "NORMALMAP": 1, "REFLECTION": reflection},
        "constantshadervalues": {"reflectivity": 4, "reflectivitydistance": 80,
                                 "roughness": 0, "metallic": 0},
        "blending": "normal", "depthtest": "disabled", "depthwrite": "disabled",
        "cullmode": "nocull",
    }]}
    return {
        "scene.json": json.dumps(scene, sort_keys=True).encode(),
        "models/receiver.json": json.dumps({"material": "materials/receiver.json"}).encode(),
        "materials/receiver.json": json.dumps(material, sort_keys=True).encode(),
        "materials/albedo.png": rgba_png((128, 128, 128)),
        "materials/normal.png": rgba_png(NORMAL_RGB),
    }


def reflection_oracle() -> dict:
    # Independent double calculation for the project's documented F5 profile.
    # Y-down card orientation flips the decoded normal Y; orthographic view is
    # (0,0,1). Reflection travels 80 world units, then uses the scene camera.
    raw = (NORMAL_RGB[0] / 255 * 2 - 1, -(NORMAL_RGB[1] / 255 * 2 - 1),
           NORMAL_RGB[2] / 255 * 2 - 1)
    length = math.sqrt(sum(value * value for value in raw))
    normal = tuple(value / length for value in raw)
    direction = (2 * normal[2] * normal[0], 2 * normal[2] * normal[1],
                 2 * normal[2] * normal[2] - 1)
    sample = (80 + 80 * direction[0], 48 + 80 * direction[1])
    fresnel = .04 + .96 * (1 - abs(normal[2])) ** 5
    return {
        "normal": normal, "direction": direction, "sampleWorld": sample,
        "Ref0": [128, 128, 128], "Ref1": [128 + 255 * 4 * fresnel, 128, 128],
        "lateRed": [255, 0, 0], "greenPeer": [0, 255, 0],
        "receiverHalfExtent": 3, "pixelTolerance": PIXEL_TOLERANCE,
        "sourceRangeForReceiverROI": [sample[0] - 3, sample[0] + 3,
                                       sample[1] - 3, sample[1] + 3],
        "distinguishes": "Current first-consumer prefix is black at this UV; completed suffix is red.",
    }


def measure_capture(path: Path, rois: dict | None = None) -> dict:
    decoded = png_rgb_pixels(path)
    if decoded is None:
        raise AssertionError(f"undecodable capture: {path}")
    width, height, rows = decoded
    scale = max(width / CANVAS[0], height / CANVAS[1])
    measurements = {"size": [width, height], "coverScale": scale}
    for label, (world_x, world_y) in (ROIS if rois is None else rois).items():
        center_x = width / 2 + (world_x - CANVAS[0] / 2) * scale
        center_y = height / 2 + (world_y - CANVAS[1] / 2) * scale
        radius = 3 * scale
        bounds = (math.ceil(center_x - radius), math.ceil(center_y - radius),
                  math.floor(center_x + radius), math.floor(center_y + radius))
        x0, y0, x1, y1 = bounds
        if not (0 <= x0 < x1 <= width and 0 <= y0 < y1 <= height):
            raise AssertionError(f"declared {label} ROI cropped: {bounds}, capture={width}x{height}")
        samples = [rows[y][x * 3:x * 3 + 3] for y in range(y0, y1) for x in range(x0, x1)]
        measurements[label] = {
            "bounds": bounds, "count": len(samples),
            "mean": [sum(pixel[c] for pixel in samples) / len(samples) for c in range(3)],
            "minimum": [min(pixel[c] for pixel in samples) for c in range(3)],
            "maximum": [max(pixel[c] for pixel in samples) for c in range(3)],
        }
    return measurements


class SceneReflectionHistoryIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        configured = os.environ.get("MWX_SCENE_INTEGRATION_APP")
        if not configured:
            raise unittest.SkipTest("requires an explicitly frozen Debug App executable")
        cls.app = Path(configured).resolve(strict=True)
        artifacts = [cls.app, cls.app.with_name("MyWallpaperX.debug.dylib"),
                     cls.app.parent.parent / "Resources/default.metallib"]
        cls.app_identity = {str(path): sha256(path) for path in artifacts if path.is_file()}
        destination = os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE")
        if destination:
            Path(destination).mkdir(parents=True, exist_ok=True)
        cls.evidence_root = Path(tempfile.mkdtemp(prefix="rf04-reflection-history-", dir=destination))
        sources = [Path(__file__), REPO / "script/tests/test_scene_pkg_cache_extractor.py",
                   REPO / "script/web_benchmark_capture.py",
                   REPO / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneLitImageLayer.metal",
                   REPO / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneResolvedMaterialFramePreflight+LitCapture.swift",
                   REPO / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Input/SceneCameraProjection.swift",
                   REPO / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneRenderDescriptor.swift"]
        cls.source_identity = {str(path): sha256(path) for path in sources}
        cls.oracle = reflection_oracle()
        protocol = {"app": cls.app_identity, "sources": cls.source_identity,
                    "oracle": cls.oracle, "ROIs": ROIS,
                    "ROITransform": "viewportCenter + (world - canvasCenter) * max(W/160,H/96)",
                    "cases": ["Ref0-capture-on", "Ref1-capture-on", "Ref1-capture-off"],
                    "captureOffBoundary": "No evidence-dir flag; no forced readable drawable or pixel claim.",
                    "retention": "Keep compact inputs/logs/pixels/identity; remove isolated homes after review."}
        (cls.evidence_root / "protocol.json").write_text(json.dumps(protocol, indent=2) + "\n")
        print(f"RF04 A App evidence: {cls.evidence_root}", flush=True)

    def run_case(self, reflection: int, *, capture: bool) -> dict:
        name = f"Ref{reflection}-capture-{'on' if capture else 'off'}"
        work = self.evidence_root / name
        content, home = work / "content", work / "home"
        content.mkdir(parents=True); home.mkdir()
        entries = fixture_entries(reflection)
        (content / "project.json").write_text(json.dumps({"type": "scene", "file": "scene.json"}))
        (content / "scene.pkg").write_bytes(make_package(list(entries.items())))
        (work / "scene-input.json").write_bytes(entries["scene.json"])
        (work / "material-input.json").write_bytes(entries["materials/receiver.json"])
        command = [str(self.app), "--mwx-debug-scene-root", str(content),
                   "--mwx-debug-scene-duration", "6"]
        if capture:
            command += ["--mwx-debug-scene-evidence-dir", str(work / "evidence")]
        environment = {key: value for key, value in os.environ.items()
                       if not key.startswith("MWX_SCENE_DEBUG_")}
        controls = {"HOME": str(home), "CFFIXED_USER_HOME": str(home), "MWX_SCENE_DEBUG_SURFACE_COUNT": "1"}
        environment.update(controls)
        identity = {"command": command, "environmentControls": controls,
                    "appBefore": {path: sha256(Path(path)) for path in self.app_identity},
                    "sourcesBefore": {path: sha256(Path(path)) for path in self.source_identity},
                    "inputEntries": {path: hashlib.sha256(data).hexdigest() for path, data in entries.items()},
                    "package": sha256(content / "scene.pkg"), "project": sha256(content / "project.json")}
        (work / "identity.json").write_text(json.dumps(identity, indent=2) + "\n")
        with (work / "app.log").open("w") as output:
            process = subprocess.run(command, cwd=REPO, env=environment, stdout=output,
                                     stderr=subprocess.STDOUT, timeout=70)
        log = (work / "app.log").read_text()
        pixels = {}
        for path in sorted((work / "evidence").glob("*-window.png")):
            pixels[path.name] = measure_capture(path)
        identity.update(appAfter={path: sha256(Path(path)) for path in self.app_identity},
                        sourcesAfter={path: sha256(Path(path)) for path in self.source_identity})
        (work / "identity.json").write_text(json.dumps(identity, indent=2) + "\n")
        (work / "pixels.json").write_text(json.dumps(pixels, indent=2) + "\n")
        outcome = {
            "returncode": process.returncode, "capture": capture, "reflection": reflection,
            "appImmutable": identity["appBefore"] == identity["appAfter"] == self.app_identity,
            "sourcesImmutable": identity["sourcesBefore"] == identity["sourcesAfter"] == self.source_identity,
            "gpuDrained": "gpuDrained=true" in log,
            "metalFailures": METAL_FAILURE.findall(log), "pixels": pixels,
            "completedSourceSubmissions": re.findall(
                r"diagnostic=scene-color-completed[^\n]*intent=snapshot sourceSubmission=([0-9A-Fa-f-]+)", log),
        }
        (work / "result.json").write_text(json.dumps(outcome, indent=2) + "\n")
        self.assertEqual(process.returncode, 0, log[-6000:])
        self.assertTrue(outcome["appImmutable"] and outcome["sourcesImmutable"], outcome)
        self.assertTrue(outcome["gpuDrained"], log[-6000:])
        self.assertFalse(outcome["metalFailures"], outcome)
        self.assertRegex(log, r"phase=ready [^\n]*surfaces=[1-9]\d*")
        self.assertRegex(log, r"phase=stopped surfacesBefore=[1-9]\d* surfacesAfter=0 gpuDrained=true")
        if capture:
            self.assertRegex(log, r"state=completed frame=[1-9]\d* surface=\d+ gpu=completed")
            self.assertIn("scene-ready-window.png", pixels)
            self.assertIn("scene-after-window.png", pixels)
        else:
            self.assertFalse(pixels, outcome)
            self.assertRegex(log, r"phase=ready [^\n]*previewLog=- runtimeEvidence=-")
        return outcome

    def assert_pixel(self, measurement: dict, expected: list[float]):
        for actual, golden in zip(measurement["mean"], expected, strict=True):
            self.assertAlmostEqual(actual, golden, delta=PIXEL_TOLERANCE, msg=str(measurement))

    def test_late_suffix_enters_completed_default_reflection(self):
        control = self.run_case(0, capture=True)
        reflected = self.run_case(1, capture=True)
        self.assertFalse(control["completedSourceSubmissions"], control)
        self.assertGreaterEqual(len(set(reflected["completedSourceSubmissions"])), 2, reflected)
        for phase in ("scene-ready-window.png", "scene-after-window.png"):
            with self.subTest(phase=phase):
                plain, mirror = control["pixels"][phase], reflected["pixels"][phase]
                self.assertEqual(plain["size"], mirror["size"])
                self.assert_pixel(plain["receiver"], self.oracle["Ref0"])
                self.assert_pixel(mirror["receiver"], self.oracle["Ref1"])
                for row in (plain, mirror):
                    self.assert_pixel(row["lateRed"], self.oracle["lateRed"])
                    self.assert_pixel(row["greenPeer"], self.oracle["greenPeer"])
                delta = [mirror["receiver"]["mean"][c] - plain["receiver"]["mean"][c] for c in range(3)]
                self.assertGreater(delta[0], 40, delta)
                self.assertLessEqual(max(abs(delta[1]), abs(delta[2])), PIXEL_TOLERANCE, delta)

    def test_capture_off_product_drawable_remains_legal(self):
        # SceneDebugFrameCapture.configure forces framebufferOnly=false only
        # with evidence-dir. This run exercises the product demand predicate.
        self.run_case(1, capture=False)


if __name__ == "__main__":
    unittest.main()
