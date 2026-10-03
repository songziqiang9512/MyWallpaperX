#!/usr/bin/env python3
"""RF04 A normal-budget App regression for late named shadow and particle depth.

Reuse self-authored fixtures and the frozen App runner. No budget injection or
allocation-count claim is made: pixels and completed commands establish only
healthy model/F5/particle output at the actual normal budget. Named preparation
uses its existing hidden-provider contract; completed capture is a path witness.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import unittest
from unittest.mock import patch

from script.tests import test_scene_named_model_shadow as named_fixture_module
from script.tests import test_scene_reflection_history_integration as app_runner
from script.tests import test_scene_snapshot_shadow_integration as particle_fixture_module

BASE_REFLECTION_FIXTURE = app_runner.fixture_entries
ROIS = {"receiver": (80, 48), "lateProvider": (140, 48),
        "particle": (20, 80), "reflection": (80, 80)}
EXPECTED = {"receiver": [85, 85, 85], "lateProvider": [85, 85, 85],
            "particle": [0, 255, 0], "reflection": [128, 128, 128]}


def fixture_entries(reflection: int) -> dict[str, bytes]:
    scene, entries = named_fixture_module.named_fixture("named-late")
    named_model = next(layer for layer in scene["objects"] if layer["id"] == 2)
    # The normal matrix is singular before named-input lookup. This model's
    # empty draws do not make shadowDrawCandidates return incomplete.
    named_model["scale"] = "1 1 0"
    provider = next(layer for layer in scene["objects"] if layer["id"] == 11)
    # Direct model named albedo admits only a hidden provider. Making this
    # source visible would remove the named binding before frame preparation.
    provider.update(origin="140 48 0", size="16 16")
    assert provider["visible"] is False
    scene["objects"].remove(provider)
    reflected = BASE_REFLECTION_FIXTURE(reflection)
    material = json.loads(reflected["materials/receiver.json"])
    material["passes"][0]["textures"] = ["materials/rf04-albedo.png", "materials/rf04-normal.png"]
    entries.update({
        "models/rf04-reflection.json": json.dumps({"material": "materials/rf04-reflection.json"}).encode(),
        "materials/rf04-reflection.json": json.dumps(material).encode(),
        "materials/rf04-albedo.png": reflected["materials/albedo.png"],
        "materials/rf04-normal.png": reflected["materials/normal.png"],
    })
    # Reuse the already validated paused, nonempty sprite definition. The
    # normal/REFRACT material is replaced by a plain white depth consumer.
    _, particle_entries = particle_fixture_module.snapshot_fixture(color_blend=False)
    particle = json.loads(particle_entries["particles/refract.json"])
    particle["material"] = "materials/rf04-depth.json"
    for initializer in particle["initializer"]:
        if initializer["name"] == "colorrandom":
            initializer.update(min="0 255 0", max="0 255 0")
        elif initializer["name"] == "sizerandom":
            initializer.update(min=48, max=48)
    entries.update({
        "particles/rf04-depth.json": json.dumps(particle).encode(),
        "materials/rf04-depth.json": json.dumps({"passes": [{
            "shader": "genericparticle", "textures": ["materials/rf04-white.tex"],
            "blending": "translucent", "depthtest": "enabled", "depthwrite": "enabled",
            "cullmode": "nocull",
        }]}).encode(),
        "materials/rf04-white.tex": particle_fixture_module.raw_tex([255] * 4),
    })
    # Top-level authored Y is bottom-up; ROI Y is screenshot canvas Y.
    scene["objects"] += [
        {"id": 60, "name": "Legal builtin F5 consumer", "image": "models/rf04-reflection.json",
         "origin": "80 16 0", "size": "20 20"},
        {"id": 42, "name": "Healthy particle depth consumer", "particle": "particles/rf04-depth.json",
         "origin": "20 16 0", "visible": True, "scale": "1 1 1",
         "instanceoverride": {"alpha": {"value": 1, "script":
             "export function init(value) { thisLayer.pause(); return value; }"}}},
        provider,
    ]
    scene["general"].update(hdr=False, clearenabled=True)
    entries["scene.json"] = json.dumps(scene, sort_keys=True).encode()
    return entries


class SceneReflectionHistoryNamedDepthAppTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Reuse only runner methods; importing the module alias does not expose
        # or inherit its TestCase tests to unittest discovery.
        app_runner.SceneReflectionHistoryIntegrationTests.setUpClass.__func__(cls)
        sources = [Path(__file__), Path(named_fixture_module.__file__),
                   Path(particle_fixture_module.__file__),
                   app_runner.REPO / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Dependencies/SceneDependencyRenderPlan+StaticModel.swift",
                   app_runner.REPO / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Dependencies/SceneDependencyFrameRuntime+StaticModel.swift",
                   app_runner.REPO / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+SceneDrawing.swift",
                   app_runner.REPO / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+StaticModels.swift"]
        cls.source_identity.update({str(path): app_runner.sha256(path) for path in sources})
        protocol = {
            "app": cls.app_identity, "sources": cls.source_identity,
            "ROIs": ROIS, "expectedRGB": EXPECTED, "pixelTolerance": app_runner.PIXEL_TOLERANCE,
            "cases": {"Ref0": "named/particle control", "Ref1": "same scene with legal F5 enabled"},
            "inputEntries": {str(flag): {name: hashlib.sha256(data).hexdigest()
                for name, data in fixture_entries(flag).items()} for flag in (0, 1)},
            "path": "visible named model 2 with singular normal matrix, shadow light 3, hidden late provider 11, F5 60, particle depth 42",
            "staticCallerEvidence": {
                "namedAdmission": "SceneDependencyRenderPlan+StaticModel.staticModelNamedTextureBindings requires provider.visible == false",
                "emptyDraws": "SceneMetalRenderer.staticModelDraws rejects the singular normal transform before named albedo lookup",
                "latePreparation": "SceneDrawing computes preparesNamedModelShadow from visible named model resources and shadow receivers, then delegates ordered depth to prepareOrderedModelShadow",
                "captureDemand": "SceneDependencyFrameRuntime.requiresCapture uses active named consumer IDs; singular model draws do not remove its provider demand",
            },
            "budgetBoundary": "normal budget; no App budget injection or tight-budget failure reproduction",
            "observationBoundary": "completed snapshot log events are observations, not allocation counts; no lease-count claim",
        }
        (cls.evidence_root / "protocol.json").write_text(json.dumps(protocol, indent=2) + "\n")

    def run_sample(self, reflection: int) -> dict:
        with patch.object(app_runner, "fixture_entries", fixture_entries), patch.object(app_runner, "ROIS", ROIS):
            outcome = app_runner.SceneReflectionHistoryIntegrationTests.run_case(self, reflection, capture=True)
        work = self.evidence_root / f"Ref{reflection}-capture-on"
        log = (work / "app.log").read_text()
        preview = (work / "evidence/scene-preview.log").read_text()
        capture_events = [line for line in log.splitlines()
                          if "phase=named-target-capture layer=11 " in line]
        self.assertTrue(any("status=succeeded" in line for line in capture_events),
                        "legal hidden provider did not yield a completed named capture: " + log[-6000:])
        self.assertIn("particle current nonempty: layers=[42]", preview)
        prepared = re.search(r"prepared static model layers: \[([^\]]*)\]", preview)
        self.assertIsNotNone(prepared, preview)
        self.assertEqual({int(value) for value in prepared[1].split(",") if value.strip()}, {1, 2})
        completed = re.search(r"phase=performance-particle layer=42 ([^\n]+)", log)
        self.assertIsNotNone(completed, log[-6000:])
        metrics = {key: int(value) for key, value in re.findall(r"(\w+)=(\d+)", completed[1])}
        self.assertGreater(metrics["completedFrames"], 0, metrics)
        self.assertGreater(metrics["completedBatches"], 0, metrics)
        self.assertGreater(metrics["completedInstances"], 0, metrics)
        self.assertEqual(metrics["failedFrames"], 0, metrics)
        outcome.update(normalBudgetOnly=True, particleCompletedMetrics=metrics,
                       observedNamedCaptureEvents=capture_events,
                       namedCallerPathEvidence="static input and product call sites plus observed completed provider capture",
                       completedSnapshotEventsAreNotAllocationEvidence=True)
        (work / "named-depth-result.json").write_text(json.dumps(outcome, indent=2) + "\n")
        return outcome

    def test_legal_f5_keeps_singular_named_model_neighbor_and_depth_particle_healthy(self):
        control, reflected = self.run_sample(0), self.run_sample(1)
        for phase in ("scene-ready-window.png", "scene-after-window.png"):
            plain, mirror = control["pixels"][phase], reflected["pixels"][phase]
            self.assertEqual(plain["size"], mirror["size"])
            for label, expected in EXPECTED.items():
                with self.subTest(phase=phase, label=label):
                    for row in (plain, mirror):
                        app_runner.SceneReflectionHistoryIntegrationTests.assert_pixel(self, row[label], expected)
                    for before, after in zip(plain[label]["mean"], mirror[label]["mean"], strict=True):
                        self.assertAlmostEqual(before, after, delta=app_runner.PIXEL_TOLERANCE)


if __name__ == "__main__":
    unittest.main()
