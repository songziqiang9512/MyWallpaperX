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

from script.tests.scene_pkg_fixture import make_package
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


HISTORY_ROIS = {"victim": (48, 48), "namedConsumer": (96, 48), "healthy": (20, 80)}
HISTORY_PROTOCOL = {
    "surfaces": 2, "durationSeconds": 8, "timeoutSeconds": 70,
    "held": {"destroySceneTime": 0, "startPaused": True, "pauseResume": "1.5:3",
             "resize": "1.1:0.8,2.25:0.75", "rebuildAfter": "3.5", "afterSnapshotDelay": 5.0,
             "pendingTail": {"reason": "resize-01", "terminal": "teardown"}},
    "warm": {"destroySceneTime": 2, "startPaused": False,
             "pauseResume": "1.5:2", "rebuildAfter": "5", "afterSnapshotDelay": 2.5},
    "ROIs": HISTORY_ROIS, "pixelTolerance": PIXEL_TOLERANCE,
    "colors": {"liveVictim": [255, 0, 255], "retiredVictim": [0, 0, 0],
               "namedConsumer": [0, 0, 255], "healthy": [0, 255, 0]},
    "history": "material -> copy current to unique history -> material; authored history clear equals source color",
    "qualification": "real graph materialNodes=2/copyNodes=1/history=seeded and GPU completed; warm also history=reused",
    "scope": "direct Host App lifecycle and visible compatibility; no dead-tail/pin census or user UI claim",
    "pixelBoundary": "first selected evidence window; graph GPU receipts on both independent views, not physical multiscreen proof",
    "oldNew": "identical authored input and schedule per arm; both Apps must pass functional assertions",
}


def history_lifecycle_entries(phase: str) -> dict[str, bytes]:
    encode = lambda value: json.dumps(value, sort_keys=True).encode()
    action = "true" if phase == "held" else "engine.runtime >= 2"
    controller = ("let removed=false; export function update(value) { "
                  f"if (!removed && {action}) {{ thisScene.destroyLayer('History victim'); removed=true; }} "
                  "return true; }")
    scene = {"version": 3, "general": {
        "orthogonalprojection": {"width": CANVAS[0], "height": CANVAS[1]},
        "clearcolor": "0 0 0", "clearenabled": True, "hdr": False}, "objects": [
        {"id": 31, "name": "History victim", "image": "models/history_magenta.json",
         "origin": "48 48 0", "size": "24 24", "visible": {"value": True,
             "script": "export function update(value) { return true; }"},
         "effects": [{"id": 310, "file": "effects/history_magenta/effect.json", "visible": True}]},
        {"id": 11, "name": "Hidden live history provider", "image": "models/history_blue.json",
         "origin": "16 48 0", "size": "24 24", "visible": False,
         "effects": [{"id": 110, "file": "effects/history_blue/effect.json", "visible": True}]},
        {"id": 22, "name": "Live named history consumer", "image": "models/history_white.json",
         "origin": "96 48 0", "size": "24 24", "dependencies": [11],
         "effects": [{"id": 220, "file": "effects/history_named/effect.json", "visible": True,
                      "passes": [{"id": 221, "textures": [None, "_rt_imageLayerComposite_11_a"]}]}]},
        {"id": 33, "name": "Healthy history neighbor", "image": "models/history_solid.json",
         "origin": "20 16 0", "size": "12 12", "color": "0 1 0"},
        {"id": 5, "name": "Live history retirement controller", "image": "models/history_solid.json",
         "origin": "0 0 0", "size": "1 1", "alpha": 0,
         "visible": {"value": True, "script": controller}},
    ]}
    vertex = (b"attribute vec3 a_Position;\nattribute vec2 a_TexCoord;\n"
              b"varying vec2 v_TexCoord;\n"
              b"void main(){gl_Position=vec4(a_Position,1.0);v_TexCoord=a_TexCoord;}\n")
    entries = {"scene.json": encode(scene),
        "models/history_solid.json": encode({"solidlayer": True, "width": 160, "height": 96}),
        "effects/history_named/effect.json": encode({"passes": [{"material": "materials/history_named.json"}]}),
        "shaders/history_accumulate.frag": (
            b"uniform sampler2D g_Texture0;\nuniform sampler2D g_Texture1;\nvarying vec2 v_TexCoord;\n"
            b"void main(){vec4 source=texSample2D(g_Texture0,v_TexCoord);"
            b"vec4 prior=texSample2D(g_Texture1,v_TexCoord);gl_FragColor=mix(prior,source,0.25);}\n"),
        "shaders/history_passthrough.frag": (
            b"uniform sampler2D g_Texture0;\nvarying vec2 v_TexCoord;\n"
            b"void main(){gl_FragColor=texSample2D(g_Texture0,v_TexCoord);}\n"),
        "shaders/history_named.frag": (
            b"uniform sampler2D g_Texture1;\nvarying vec2 v_TexCoord;\n"
            b"void main(){gl_FragColor=texSample2D(g_Texture1,v_TexCoord);}\n"),
    }
    for shader in ("history_accumulate", "history_passthrough", "history_named"):
        entries[f"shaders/{shader}.vert"] = vertex
        entries[f"materials/{shader}.json"] = encode({"passes": [{"shader": shader,
            "textures": [None, "_rt_imageLayerComposite_11_a"] if shader == "history_named" else [None],
            "blending": "normal", "depthtest": "disabled", "depthwrite": "disabled", "cullmode": "nocull"}]})
    for color, rgb in {"magenta": (255, 0, 255), "blue": (0, 0, 255), "white": (255, 255, 255)}.items():
        entries[f"models/history_{color}.json"] = encode({"material": f"materials/history_{color}.json"})
        entries[f"materials/history_{color}.json"] = encode({"passes": [{"shader": "genericimage",
            "textures": [f"materials/history_{color}.png"]}]})
        entries[f"materials/history_{color}.png"] = rgba_png(rgb)
        if color == "white":
            continue
        clear = "1 0 1 1" if color == "magenta" else "0 0 1 1"
        entries[f"effects/history_{color}/effect.json"] = encode({"passes": [
            {"material": "materials/history_accumulate.json", "target": "_rt_Current",
             "bind": [{"name": "previous", "index": 0}, {"name": "_rt_History", "index": 1}]},
            {"command": "copy", "source": "_rt_Current", "target": "_rt_History"},
            {"material": "materials/history_passthrough.json", "bind": [{"name": "_rt_Current", "index": 0}]}],
            "fbos": [{"name": "_rt_History", "scale": 1, "format": "rgba_backbuffer", "unique": True, "clear": clear},
                     {"name": "_rt_Current", "scale": 1, "format": "rgba_backbuffer"}]})
    return entries


def history_graph_receipts(log: str, layer: int) -> list[dict]:
    return [dict(re.findall(r"(\w+)=([^\s]+)", line)) for line in log.splitlines()
            if "axis=graph-execution " in line and re.search(rf"\blayer={layer}\b", line)]


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
        sources = [Path(__file__), REPO / "script/tests/scene_pkg_fixture.py",
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

    def run_case(self, reflection: int, *, capture: bool,
                 extra_arguments: tuple[str, ...] = (),
                 initial_snapshot: str = "scene-ready-window.png",
                 material_input_path: str = "materials/receiver.json") -> dict:
        name = f"Ref{reflection}-capture-{'on' if capture else 'off'}"
        work = self.evidence_root / name
        content, home = work / "content", work / "home"
        content.mkdir(parents=True); home.mkdir()
        entries = fixture_entries(reflection)
        (content / "project.json").write_text(json.dumps({"type": "scene", "file": "scene.json"}))
        (content / "scene.pkg").write_bytes(make_package(list(entries.items())))
        (work / "scene-input.json").write_bytes(entries["scene.json"])
        (work / "material-input.json").write_bytes(entries[material_input_path])
        command = [str(self.app), "--mwx-debug-scene-root", str(content),
                   "--mwx-debug-scene-duration", "6"]
        if capture:
            command += ["--mwx-debug-scene-evidence-dir", str(work / "evidence")]
        command += list(extra_arguments)
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
            self.assertIn(initial_snapshot, pixels)
            self.assertIn("scene-after-window.png", pixels)
        else:
            self.assertFalse(pixels, outcome)
            self.assertRegex(log, r"phase=ready [^\n]*previewLog=- runtimeEvidence=-")
        return outcome

    def assert_pixel(self, measurement: dict, expected: list[float]):
        for actual, golden in zip(measurement["mean"], expected, strict=True):
            self.assertAlmostEqual(actual, golden, delta=PIXEL_TOLERANCE, msg=str(measurement))

    def run_history_lifecycle(self, phase: str) -> None:
        work = self.evidence_root / f"graph-history-{phase}"
        content, home, evidence = work / "content", work / "home", work / "evidence"
        content.mkdir(parents=True)
        home.mkdir()
        entries = history_lifecycle_entries(phase)
        (content / "project.json").write_text(json.dumps({"type": "scene", "file": "scene.json"}))
        (content / "scene.pkg").write_bytes(make_package(list(entries.items())))
        (work / "scene-input.json").write_bytes(entries["scene.json"])
        cache, archive = work / "shader-cache", work / "pipeline-cache"
        cache.mkdir(); archive.mkdir()
        controls = {"HOME": str(home), "CFFIXED_USER_HOME": str(home),
            "MWX_SCENE_DEBUG_SURFACE_COUNT": "2", "MWX_SCENE_GENERIC_SHADER_CACHE": str(cache),
            "MWX_SCENE_PIPELINE_BINARY_ARCHIVE": str(archive),
            "MWX_SCENE_DEBUG_PAUSE_RESUME_AFTER": HISTORY_PROTOCOL[phase]["pauseResume"],
            "MWX_SCENE_DEBUG_SURFACE_REBUILD_AFTER": HISTORY_PROTOCOL[phase]["rebuildAfter"]}
        environment = {key: value for key, value in os.environ.items()
            if not key.startswith(("MWX_SCENE_DEBUG_", "MYWALLPAPERX_SCENE_DEBUG_"))}
        environment.pop("MWX_SCENE_GENERIC_SHADER_ROUTE", None)
        environment.update(controls)
        command = [str(self.app), "--mwx-debug-scene-root", str(content),
            "--mwx-debug-scene-duration", "8", "--mwx-debug-scene-evidence-dir", str(evidence),
            "--mwx-debug-scene-after-snapshot-delay", str(HISTORY_PROTOCOL[phase]["afterSnapshotDelay"])]
        if phase == "held":
            command += ["--mwx-debug-scene-start-paused", "--mwx-debug-scene-resize-sequence",
                        HISTORY_PROTOCOL[phase]["resize"]]
        sources = dict(self.source_identity)
        for relative in (
            "MyWallpaperX/App/Debug/DebugScenePlaybackRunner.swift",
            "MyWallpaperX/App/Debug/DebugScenePlaybackRunner+PauseResume.swift",
            "MyWallpaperX/App/Debug/DebugScenePlaybackRunner+HostOwnership.swift",
            "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+SurfaceSimulation.swift",
            "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialSubmissionCoordinator.swift",
            "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialSubmissionCoordinator+Lifecycle.swift",
            "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialSubmissionCoordinator+Completion.swift",
        ):
            sources[str(REPO / relative)] = sha256(REPO / relative)
        inputs = (content / "project.json", content / "scene.pkg")
        identity = {"phase": phase, "protocol": HISTORY_PROTOCOL, "command": command, "controls": controls,
            "appBefore": {path: sha256(Path(path)) for path in self.app_identity}, "sourcesBefore": sources,
            "inputsBefore": {path.name: sha256(path) for path in inputs},
            "entrySHA256": {path: hashlib.sha256(data).hexdigest() for path, data in entries.items()}}
        self.assertEqual(identity["appBefore"], self.app_identity, identity)
        (work / "preregister.json").write_text(json.dumps(identity, indent=2) + "\n")
        log, pixels, observed, qualification = "", {}, {}, {}
        try:
            with (work / "app.log").open("w") as output:
                process = subprocess.run(command, cwd=REPO, env=environment,
                    stdout=output, stderr=subprocess.STDOUT, timeout=HISTORY_PROTOCOL["timeoutSeconds"])
            log = (work / "app.log").read_text()
            identity["returncode"] = process.returncode
            pixels = {path.name: measure_capture(path, HISTORY_ROIS)
                      for path in sorted(evidence.glob("*-window.png"))}
            observed = {stage: json.loads((evidence / f"surface-rebuild-{stage}.json").read_text())
                        for stage in ("before", "after", "settled")}
            retired = re.search(r"(?m)^.*lifecycle=layer-retirement[^\n]*sceneTime=([\d.]+)", log)
            teardown = next((match for match in re.finditer(
                r"(?m)^.*phase=surface-teardown clearContext=false[^\n]*", log)
                if retired and match.start() > retired.end()), None)
            rebuild = teardown.start() if teardown else -1
            provider_before = history_graph_receipts(log[:rebuild], 11) if rebuild >= 0 else []
            provider_after = history_graph_receipts(log[rebuild:], 11) if rebuild >= 0 else []
            victim = history_graph_receipts(log, 31)
            completed = lambda rows: [row for row in rows if row.get("gpuCompletion") == "completed"
                and row.get("copyNodes") == "1" and row.get("materialNodes") == "2"
                and row.get("rejectedNodes") == "0"]
            qualification = {"retirementLine": retired.group(0) if retired else None,
                "retirementSceneTime": float(retired.group(1)) if retired else None,
                "rebuildTeardownLine": teardown.group(0) if teardown else None,
                "victimGraphCompleted": completed(victim),
                "hiddenProviderBeforeRebuild": completed(provider_before),
                "hiddenProviderAfterRebuild": completed(provider_after),
                "namedConsumerCompleted": [row for row in history_graph_receipts(log, 22)
                    if row.get("gpuCompletion") == "completed" and row.get("compositorConsumed") == "true"],
                "namedPublicationLines": [line for line in log.splitlines()
                    if "phase=named-graph-output-publication layer=11 status=succeeded" in line],
                "snapshotFailureLines": [line for line in log.splitlines() if "phase=snapshot-failed" in line],
                "observationCeiling": HISTORY_PROTOCOL["scope"]}
            self.assertEqual(process.returncode, 0, log[-6000:])
            self.assertFalse(METAL_FAILURE.findall(log), log[-6000:])
            self.assertNotRegex(log, r"phase=launch-failed|phase=snapshot-rejected|outcome=failed"
                r"|predecessor-output-not-consumed|frame-success-blueprint-rejected")
            self.assertRegex(log, r"phase=ready [^\n]*surfaces=2 ")
            self.assertRegex(log, r"phase=surface-rebuild state=rebuilt accepted=true surfacesBefore=2 surfacesAfter=2")
            self.assertRegex(log, r"phase=stopped surfacesBefore=2 surfacesAfter=0 gpuDrained=true")
            self.assertIsNotNone(retired, qualification)
            self.assertIsNotNone(teardown, qualification)
            self.assertLess(retired.start(), teardown.start(), qualification)
            self.assertRegex(retired.group(0), r"owners=1 destroyCallbacks=\d+ quiescent=1 failures=0")
            self.assertEqual(len({row["runtime"] for row in completed(victim)}), 2, qualification)
            self.assertTrue(any(row.get("history") == "seeded" for row in completed(victim)), qualification)
            self.assertTrue(qualification["namedPublicationLines"], qualification)
            before_ids = {row["runtime"] for row in completed(provider_before)}
            after_ids = {row["runtime"] for row in completed(provider_after)} - before_ids
            self.assertEqual(len(before_ids), 2, qualification)
            self.assertEqual(len(after_ids), 2, qualification)
            self.assertTrue(before_ids.isdisjoint(after_ids), qualification)
            self.assertTrue((before_ids | after_ids).issubset(
                {row["runtime"] for row in qualification["namedConsumerCompleted"]}), qualification)
            before, after, settled = (observed[stage] for stage in ("before", "after", "settled"))
            self.assertTrue(before["sessionID"] and before["requestID"], observed)
            for key in ("sessionID", "requestID", "surfaceCount"):
                self.assertEqual(before[key], after[key], observed)
                self.assertEqual(before[key], settled[key], observed)
            self.assertEqual(before["surfaceCount"], 2, observed)
            self.assertTrue(set(before["windowNumbers"]).isdisjoint(after["windowNumbers"]), observed)
            self.assertEqual(after["windowNumbers"], settled["windowNumbers"], observed)
            self.assertTrue(before["capturedTopology"] and before["requestedTopology"], observed)
            self.assertEqual([row["displayID"] for row in before["capturedTopology"]],
                             [row["displayID"] for row in before["requestedTopology"]], observed)
            self.assertNotEqual(before["capturedTopology"], before["requestedTopology"], observed)
            self.assertGreater(settled["sceneTime"], after["sceneTime"], observed)
            self.assertFalse(settled["isPlaybackPaused"], observed)
            self.assertTrue(settled["isFrameDriverActive"], observed)
            if phase == "held":
                failures = qualification["snapshotFailureLines"]
                self.assertEqual(len(failures), 1, qualification)
                self.assertRegex(failures[0], r"phase=snapshot-failed reason=resize-01 request=\d+ stage=teardown(?:\s|$)")
                self.assertNotIn("scene-resize-01-window.png", pixels, qualification)
                self.assertGreater(log.index(failures[0]), retired.end(), qualification)
                self.assertLess(log.index(failures[0]), teardown.start(), qualification)
                self.assertRegex(log, r"phase=surface-resize index=0 scale=0\.8000 accepted=true")
                self.assertRegex(log, r"phase=surface-resize index=1 scale=0\.7500 accepted=true")
                self.assertEqual(qualification["retirementSceneTime"], 0, qualification)
                self.assertTrue(before["isPlaybackPaused"] and after["isPlaybackPaused"], observed)
                self.assertFalse(before["isFrameDriverActive"] or after["isFrameDriverActive"], observed)
                self.assertEqual(before["sceneTime"], after["sceneTime"], observed)
                self.assertRegex(log, r"phase=pause-resume state=paused accepted=false[^\n]*pausedBefore=true pausedAfter=true")
                self.assertRegex(log, r"phase=pause-resume state=resumed accepted=false surfacesPaused=2 "
                    r"surfacesBeforeResume=2 surfacesAfterResume=2 pausedBeforeResume=true pausedAfterResume=false "
                    r"timerBeforeResume=inactive timerAfterResume=active")
                alive = ("scene-ready-window.png", "scene-resize-00-window.png")
                absent = ("scene-after-window.png", "scene-pause-resume-after-window.png",
                          "scene-surface-rebuild-after-window.png", "scene-surface-rebuild-settled-window.png")
            else:
                self.assertEqual(qualification["snapshotFailureLines"], [], qualification)
                self.assertGreaterEqual(qualification["retirementSceneTime"], 2, qualification)
                self.assertLess(qualification["retirementSceneTime"], before["sceneTime"], observed)
                for rows in (completed(victim), completed(provider_before)):
                    self.assertTrue(any(row.get("history") == "reused" for row in rows), qualification)
                self.assertFalse(before["isPlaybackPaused"] or after["isPlaybackPaused"], observed)
                self.assertTrue(before["isFrameDriverActive"] and after["isFrameDriverActive"], observed)
                self.assertGreater(after["sceneTime"], before["sceneTime"], observed)
                self.assertRegex(log, r"phase=pause-resume state=paused accepted=true")
                self.assertRegex(log, r"phase=pause-resume state=resumed accepted=true")
                alive = ("scene-ready-window.png", "scene-after-window.png", "scene-pause-resume-after-window.png")
                absent = ("scene-surface-rebuild-after-window.png", "scene-surface-rebuild-settled-window.png")
            for name, expected in [(name, [255, 0, 255]) for name in alive] + [(name, [0, 0, 0]) for name in absent]:
                self.assertIn(name, pixels, pixels)
                self.assert_pixel(pixels[name]["victim"], expected)
                self.assert_pixel(pixels[name]["namedConsumer"], [0, 0, 255])
                self.assert_pixel(pixels[name]["healthy"], [0, 255, 0])
        finally:
            identity.update(appAfter={path: sha256(Path(path)) for path in self.app_identity},
                sourcesAfter={path: sha256(Path(path)) for path in sources},
                inputsAfter={path.name: sha256(path) for path in inputs})
            for name, value in (("identity", identity), ("pixels", pixels),
                                ("surface-lifecycle", observed), ("qualification", qualification)):
                (work / f"{name}.json").write_text(json.dumps(value, indent=2) + "\n")
            self.assertEqual(identity["appBefore"], identity["appAfter"], identity)
            self.assertEqual(identity["sourcesBefore"], identity["sourcesAfter"], identity)
            self.assertEqual(identity["inputsBefore"], identity["inputsAfter"], identity)

    def test_graph_history_lifecycle_through_pause_rebuild_and_stop(self):
        for phase in ("held", "warm"):
            with self.subTest(phase=phase):
                self.run_history_lifecycle(phase)

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
