"""Authored environment sampling through the actual isolated Scene App."""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

from script.tests.scene import test_scene_reflection_history_integration as reflection
from script.tests.scene.test_scene_native_world_composition import png


STOCK_REFLECTION_PROBES = {
    "mirrorTop": ((52, 17), (0, 0, 255)),
    "mirrorBottom": ((52, 29), (255, 0, 0)),
    "sourceTop": ((96, 17), (255, 0, 0)),
    "sourceBottom": ((96, 29), (0, 0, 255)),
}


def add_stock_reflection_control(entries: dict[str, bytes], scene: dict) -> None:
    # Workshop packages carry the stock effect's material and shaders alongside the definition.
    stock = reflection.REPO / "MyWallpaperX/Resources/SceneStockAssets.bundle/assets/effects/reflection"
    for path in ("effect.json", "materials/effects/reflection.json",
                 "shaders/effects/reflection.vert", "shaders/effects/reflection.frag"):
        target = "effects/reflection/effect.json" if path == "effect.json" else path
        entries[target] = (stock / path).read_bytes()

    scene["objects"].extend([
        {"id": 8, "image": "models/mirror_source.json", "origin": "52 73 0", "size": "32 24",
         "effects": [{"id": 80, "file": "effects/reflection/effect.json", "visible": True,
                      "passes": [{"id": 81, "combos": {"BLENDMODE": 0}, "constantshadervalues": {
                          "alpha": 1, "direction": 0, "offset": 0}}]}]},
        {"id": 9, "image": "models/mirror_source.json", "origin": "96 73 0", "size": "32 24"},
    ])
    entries["models/mirror_source.json"] = b'{"material":"materials/mirror_source.json"}'
    entries["materials/mirror_source.json"] = json.dumps({"passes": [{
        "shader": "genericimage2", "textures": ["materials/mirror_source.png"],
        "combos": {"LIGHTING": 0, "NORMALMAP": 0, "REFLECTION": 0},
        "blending": "normal", "depthtest": "disabled", "depthwrite": "disabled", "cullmode": "nocull",
    }]}).encode()
    entries["materials/mirror_source.png"] = png(16, 16, lambda _x, y: (255, 0, 0) if y < 8 else (0, 0, 255))


def fixture_entries(slot: int, shader_default: bool, with_f5: bool = False,
                    with_stock_reflection: bool = False) -> dict[str, bytes]:
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
    if with_stock_reflection:
        add_stock_reflection_control(entries, scene)
    entries["scene.json"] = json.dumps(scene, sort_keys=True).encode()
    return entries


class SceneAuthoredEnvironmentIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        configured = os.environ.get("MWX_SCENE_INTEGRATION_APP")
        if not configured:
            raise unittest.SkipTest("requires an explicitly frozen Debug App executable")
        cls.app = Path(configured).resolve(strict=True)
        cls.artifacts = [cls.app, cls.app.parent.parent / "Resources/default.metallib"]
        debug_library = cls.app.with_name("MyWallpaperX.debug.dylib")
        if debug_library.is_file():
            cls.artifacts.append(debug_library)
        cls.identity = {str(p): reflection.sha256(p) for p in cls.artifacts}
        destination = os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE")
        if destination:
            Path(destination).mkdir(parents=True, exist_ok=True)
        cls.root = Path(tempfile.mkdtemp(prefix="authored-environment-", dir=destination))
        print(f"Authored environment App evidence: {cls.root}", flush=True)

    def run_case(self, slot: int, shader_default: bool, *, capture: bool = True,
                 with_f5: bool = False, reflection_quality: str | None = None, hdr_history: bool = False):
        name = f"slot{slot}-{'default' if shader_default else 'explicit'}-{'capture' if capture else 'drawable'}-f5{int(with_f5)}"
        if hdr_history:
            name += "-hdr-persistence"
        work = self.root / (f"{name}-{reflection_quality}" if reflection_quality is not None else name)
        content = work / "content"
        content.mkdir(parents=True)
        home = work / "home"
        home.mkdir()
        entries = fixture_entries(slot, shader_default, with_f5, reflection_quality is not None and not hdr_history)
        if hdr_history:
            scene = json.loads(entries["scene.json"])
            scene["general"].update(hdr=True, clearenabled=False)
            entries["scene.json"] = json.dumps(scene, sort_keys=True).encode()
            entries["shaders/own_environment.frag"] = (
                f"uniform sampler2D g_Texture{slot};\n"
                f"uniform vec4 g_Texture{slot}Resolution;\n"
                "void main(){\n"
                f"vec4 history=texSample2DLod(g_Texture{slot},vec2(0.875,0.5),3.0);\n"
                f"vec4 size=g_Texture{slot}Resolution;\n"
                "float extent=step(64.0,size.x)*step(64.0,size.y)"
                "*step(abs(size.x-size.z)+abs(size.y-size.w),0.0);\n"
                "gl_FragColor=vec4(history.r,history.a,extent,1.0);\n"
                "}\n"
            ).encode()
        (content / "project.json").write_text(json.dumps({"type": "scene", "file": "scene.json"}))
        (content / "scene.pkg").write_bytes(reflection.make_package(list(entries.items())))
        command = [str(self.app), "--mwx-debug-scene-root", str(content),
                   "--mwx-debug-scene-background", "--mwx-debug-scene-duration", "6"]
        if capture:
            command += ["--mwx-debug-scene-evidence-dir", str(work / "evidence")]
        if reflection_quality is not None:
            post = " scenePostProcessingMode = ultra;" if hdr_history else ""
            command += ["-mwx.playback.quality", f"{{ sceneReflectionQuality = {reflection_quality};{post} }}"]
        env = {k: v for k, v in os.environ.items() if not k.startswith("MWX_SCENE_DEBUG_")}
        env.update(HOME=str(home), CFFIXED_USER_HOME=str(home), MWX_SCENE_DEBUG_SURFACE_COUNT="1")
        package_hash = reflection.sha256(content / "scene.pkg")
        (work / "identity.json").write_text(json.dumps({
            "app": self.identity, "command": command,
            "fixture": reflection.sha256(Path(__file__)),
            "package": package_hash,
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
        if reflection_quality == "disabled":
            self.assertNotIn("reason=material-finalizer-scene-environment-unavailable", log)
        else:
            self.assertIn("reason=material-finalizer-scene-environment-unavailable", log)
        self.assertRegex(log, r"axis=graph-execution[^\n]*frame=[1-9]\d*[^\n]*materialNodes=1[^\n]*rejectedNodes=0[^\n]*compositorConsumed=true[^\n]*gpuCompletion=completed")
        self.assertRegex(log, r"state=completed frame=[1-9]\d* surface=\d+ gpu=completed")
        rois = dict(reflection.ROIS)
        if with_f5:
            rois["f5"] = (40, 48)
        if reflection_quality is not None and not hdr_history:
            rois.update({name: point for name, (point, _) in STOCK_REFLECTION_PROBES.items()})
        measurements = {p.name: reflection.measure_capture(p, rois)
                        for p in sorted((work / "evidence").glob("*-window.png"))}
        (work / "pixels.json").write_text(json.dumps(measurements, indent=2) + "\n")
        self.assertIn("scene-after-window.png", measurements)
        after = measurements["scene-after-window.png"]
        receiver_color = (255, 0, 0)
        if hdr_history:
            receiver_color = (0, 255, 255)
        elif reflection_quality == "disabled":
            receiver_color = (0, 0, 0)
        for name, expected in (("receiver", receiver_color), ("lateRed", (255, 0, 0)),
                               ("greenPeer", (0, 255, 0))):
            for actual, golden in zip(after[name]["mean"], expected):
                self.assertAlmostEqual(actual, golden, delta=reflection.PIXEL_TOLERANCE,
                                       msg=f"{work}: {name} {after[name]}")
        if with_f5:
            oracle = reflection.reflection_oracle()["Ref0" if reflection_quality == "disabled" else "Ref1"]
            for actual, expected in zip(after["f5"]["mean"], oracle, strict=True):
                self.assertAlmostEqual(actual, expected, delta=reflection.PIXEL_TOLERANCE)
        if reflection_quality is not None:
            if not hdr_history:
                for name, (_, expected) in STOCK_REFLECTION_PROBES.items():
                    for actual, channel in zip(after[name]["mean"], expected, strict=True):
                        self.assertAlmostEqual(actual, channel, delta=reflection.PIXEL_TOLERANCE,
                                               msg=f"{work}: {name} {after[name]}")
            else:
                raw = re.findall(r"diagnostic=scene-color-completed[^\n]*intent=persistence sourceSubmission=(\S+)", log)
                self.assertGreaterEqual(len(set(raw)), 2, log[-6000:])
            self.assertRegex(log, rf"phase=session-candidate [^\n]*reflectionQuality={reflection_quality}\b")
            receipts = re.findall(r"diagnostic=scene-color-completed[^\n]*intent=snapshot sourceSubmission=(\S+)", log)
            if reflection_quality == "disabled":
                self.assertEqual(receipts, [], log[-6000:])
            else:
                self.assertGreaterEqual(len(set(receipts)), 2, log[-6000:])
            event = reflection.SceneReflectionHistoryIntegrationTests.settled_composition(self, work, log)
            inputs = [r["source"] for r in event["rows"] if r["kind"] == "material" and r.get("layerID") == 1
                      and r.get("slot") == slot and r.get("outcome") == "draw-encoded"]
            self.assertEqual([item["logical"] for item in inputs], ["provider:sceneEnvironment"], event)
            source = inputs[0]
            drawable = next(row["target"] for row in event["rows"] if row["kind"] == "frame-seal")
            self.assertEqual((source["width"], source["height"]), (drawable["width"], drawable["height"]))
            self.assertEqual(source["provenance"], "shader-default" if shader_default else "authored.material")
            self.assertEqual("clearedSceneEnvironment(" in source["candidateIdentity"],
                             reflection_quality == "disabled")
        self.assertEqual({str(p): reflection.sha256(p) for p in self.artifacts}, self.identity)
        return package_hash

    def test_explicit_slot_zero_reads_completed_suffix_without_f5(self):
        self.run_case(0, False)

    def test_explicit_slot_three_has_same_resource_semantics(self):
        self.run_case(3, False)

    def test_shader_default_slot_two_reads_completed_suffix(self):
        self.run_case(2, True)

    def test_authored_and_default_f5_share_completed_suffix(self):
        self.run_case(3, False, with_f5=True)

    def test_image_reflection_quality_clears_explicit_and_shader_default_environment(self):
        for slot, shader_default in ((3, False), (2, True)):
            with self.subTest(slot=slot, shader_default=shader_default):
                enabled = self.run_case(slot, shader_default, with_f5=True, reflection_quality="enabled")
                disabled = self.run_case(slot, shader_default, with_f5=True, reflection_quality="disabled")
                self.assertEqual(enabled, disabled)

    def test_disabled_environment_lod_keeps_opaque_alpha_and_hdr_persistence(self):
        self.run_case(3, False, reflection_quality="disabled", hdr_history=True)

    def test_authored_only_without_debug_capture(self):
        self.run_case(0, False, capture=False)


if __name__ == "__main__":
    unittest.main()
