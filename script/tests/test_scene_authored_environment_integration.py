"""Authored environment sampling through the actual isolated Scene App."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests import test_scene_reflection_history_integration as reflection


def fixture_entries(slot: int, shader_default: bool, with_f5: bool = False) -> dict[str, bytes]:
    entries = reflection.fixture_entries(0)
    scene = json.loads(entries["scene.json"])
    scene["objects"][0]["name"] = "Authored completed environment receiver"
    scene["objects"][0]["effects"] = [
        {"id": 10, "file": "effects/environment/effect.json", "visible": True}
    ]
    if with_f5:
        scene["objects"].insert(1, {"id": 4, "name": "Shared default F5 receiver",
            "image": "models/shared_f5.json", "origin": "40 48 0", "size": "20 20"})
        f5 = json.loads(reflection.fixture_entries(1)["materials/receiver.json"])
        f5["passes"][0]["constantshadervalues"]["reflectivitydistance"] = 120
        entries["models/shared_f5.json"] = json.dumps({"material": "materials/shared_f5.json"}).encode()
        entries["materials/shared_f5.json"] = json.dumps(f5).encode()
    entries["scene.json"] = json.dumps(scene, sort_keys=True).encode()
    entries["effects/environment/effect.json"] = json.dumps({
        "passes": [{"material": "materials/environment.json"}]
    }).encode()
    textures = [None] * (slot + 1)
    if not shader_default:
        textures[slot] = "_rt_MipMappedFrameBuffer"
    entries["materials/environment.json"] = json.dumps({"passes": [{
        "shader": "own_environment", "textures": textures, "blending": "normal",
        "depthtest": "disabled", "depthwrite": "disabled", "cullmode": "nocull",
    }]}).encode()
    entries["shaders/own_environment.vert"] = (
        "attribute vec3 a_Position;\nattribute vec2 a_TexCoord;\n"
        "varying vec2 v_TexCoord;\n"
        "void main(){gl_Position=vec4(a_Position,1.0);v_TexCoord=a_TexCoord;}\n"
    ).encode()
    annotation = ' // {"hidden":true,"default":"_rt_MipMappedFrameBuffer"}' if shader_default else ""
    # The late red rectangle occupies x=.75..1. It is absent from the current
    # first-consumer prefix. The same previous completed image must serve every slot.
    entries["shaders/own_environment.frag"] = (
        f"uniform sampler2D g_Texture{slot};{annotation}\n"
        "varying vec2 v_TexCoord;\n"
        f"void main(){{gl_FragColor=texSample2D(g_Texture{slot},vec2(0.875,0.5));}}\n"
    ).encode()
    return entries


class SceneAuthoredEnvironmentIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        configured = os.environ.get("MWX_SCENE_INTEGRATION_APP")
        if not configured:
            raise unittest.SkipTest("requires an explicitly frozen Debug App executable")
        cls.app = Path(configured).resolve(strict=True)
        cls.artifacts = [cls.app, cls.app.with_name("MyWallpaperX.debug.dylib"),
                         cls.app.parent.parent / "Resources/default.metallib"]
        cls.identity = {str(p): reflection.sha256(p) for p in cls.artifacts}
        destination = os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE")
        if destination:
            Path(destination).mkdir(parents=True, exist_ok=True)
        cls.root = Path(tempfile.mkdtemp(prefix="authored-environment-", dir=destination))
        print(f"Authored environment App evidence: {cls.root}", flush=True)

    def run_case(self, slot: int, shader_default: bool, *, capture: bool = True, with_f5: bool = False):
        work = self.root / f"slot{slot}-{'default' if shader_default else 'explicit'}-{'capture' if capture else 'drawable'}-f5{int(with_f5)}"
        content = work / "content"
        content.mkdir(parents=True)
        home = work / "home"
        home.mkdir()
        entries = fixture_entries(slot, shader_default, with_f5)
        (content / "project.json").write_text(json.dumps({"type": "scene", "file": "scene.json"}))
        (content / "scene.pkg").write_bytes(reflection.make_package(list(entries.items())))
        command = [str(self.app), "--mwx-debug-scene-root", str(content),
                   "--mwx-debug-scene-duration", "6"]
        if capture:
            command += ["--mwx-debug-scene-evidence-dir", str(work / "evidence")]
        env = {k: v for k, v in os.environ.items() if not k.startswith("MWX_SCENE_DEBUG_")}
        env.update(HOME=str(home), CFFIXED_USER_HOME=str(home), MWX_SCENE_DEBUG_SURFACE_COUNT="1")
        (work / "identity.json").write_text(json.dumps({
            "app": self.identity, "command": command,
            "fixture": reflection.sha256(Path(__file__)),
            "package": reflection.sha256(content / "scene.pkg"),
        }, indent=2) + "\n")
        with (work / "app.log").open("w") as log_file:
            run = subprocess.run(command, cwd=reflection.REPO, env=env,
                                 stdout=log_file, stderr=subprocess.STDOUT, timeout=70)
        log = (work / "app.log").read_text()
        self.assertEqual(run.returncode, 0, log[-6000:])
        self.assertFalse(reflection.METAL_FAILURE.findall(log), log[-6000:])
        self.assertIn("gpuDrained=true", log)
        if not capture:
            # Normal playback deliberately omits frame diagnostic capture. Its
            # live draw counters and GPU-drained stop remain observable.
            self.assertIn("previewLog=- runtimeEvidence=-", log)
            self.assertRegex(log, r"phase=session-first-frame[^\n]*gpu=completed")
            self.assertRegex(log, r"phase=performance-gpu[^\n]*resolvedMaterialRenders=[1-9]\d*")
            self.assertEqual({str(p): reflection.sha256(p) for p in self.artifacts}, self.identity)
            return
        self.assertIn("reason=material-finalizer-scene-environment-unavailable", log)
        self.assertRegex(log, r"axis=graph-execution[^\n]*frame=[1-9]\d*[^\n]*materialNodes=1[^\n]*rejectedNodes=0[^\n]*compositorConsumed=true[^\n]*gpuCompletion=completed")
        self.assertRegex(log, r"state=completed frame=[1-9]\d* surface=\d+ gpu=completed")
        rois = dict(reflection.ROIS)
        if with_f5:
            rois["f5"] = (40, 48)
        measurements = {p.name: reflection.measure_capture(p, rois)
                        for p in sorted((work / "evidence").glob("*-window.png"))}
        (work / "pixels.json").write_text(json.dumps(measurements, indent=2) + "\n")
        self.assertIn("scene-after-window.png", measurements)
        after = measurements["scene-after-window.png"]
        for name, expected in (("receiver", (255, 0, 0)), ("lateRed", (255, 0, 0)),
                               ("greenPeer", (0, 255, 0))):
            for actual, golden in zip(after[name]["mean"], expected):
                self.assertAlmostEqual(actual, golden, delta=reflection.PIXEL_TOLERANCE,
                                       msg=f"{work}: {name} {after[name]}")
        if with_f5:
            for actual, expected in zip(after["f5"]["mean"], reflection.reflection_oracle()["Ref1"]):
                self.assertAlmostEqual(actual, expected, delta=reflection.PIXEL_TOLERANCE)
        self.assertEqual({str(p): reflection.sha256(p) for p in self.artifacts}, self.identity)

    def test_explicit_slot_zero_reads_completed_suffix_without_f5(self):
        self.run_case(0, False)

    def test_explicit_slot_three_has_same_resource_semantics(self):
        self.run_case(3, False)

    def test_shader_default_slot_two_reads_completed_suffix(self):
        self.run_case(2, True)

    def test_authored_and_default_f5_share_completed_suffix(self):
        self.run_case(3, False, with_f5=True)

    def test_authored_only_without_debug_capture(self):
        self.run_case(0, False, capture=False)


if __name__ == "__main__":
    unittest.main()
