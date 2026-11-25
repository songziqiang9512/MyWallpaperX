"""Point-volume quality through the real prepared Scene and Metal output."""

import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from script.tests.scene import test_scene_native_world_composition as world
from script.tests.scene import test_scene_reflection_history_integration as app_runner


LIGHT = 41
FOREGROUND = 12
RECEIVER = 18
MATERIAL_PATH = "materials/foreground.json"
REGIONS = {
    "halo": {"world": (0.25, 0, 0)},
    "occluded": {"world": (-0.35, 0, 2)},
    "direct": {"world": (2.1, 0, -1.5)},
    "outside": {"world": (0, 2.1, 0)},
}


def fixture(variant):
    light = {"id": LIGHT, "light": "lpoint", "origin": "0 0 0", "color": "1 0 0",
             "intensity": 2, "radius": 1, "exponent": 0, "density": 4,
             "volumetricsexponent": 0, "castvolumetrics": variant != "author-disabled",
             "castshadow": variant == "author-shadow"}
    objects = [
        {"id": FOREGROUND, "model": "models/foreground.mdl", "castshadow": False},
        {"id": RECEIVER, "model": "models/receiver.mdl", "castshadow": False},
        light,
    ]
    scene = world.native_world_scene(objects)
    scene["general"]["lightconfig"] = {"point": 1}
    if variant == "accumulating":
        scene["general"]["clearenabled"] = False
    if variant == "orthographic":
        scene.pop("camera")
        scene["general"].pop("fov")
        scene["general"]["orthogonalprojection"] = {"width": 8, "height": 6}
        for obj in objects:
            obj["origin"] = "4 3 0"
    entries = {"scene.json": world.encoded(scene)}
    for stem, bounds, z, rgb, lit in (
        ("foreground", (-1.15, -.10, -.5, .5), 2, (0, 180, 0), False),
        ("receiver", (1.6, 2.6, -.8, .8), -1.5, (180, 180, 180), True),
    ):
        material = f"materials/{stem}.json"
        texture = f"materials/{stem}.png"
        entries[f"models/{stem}.mdl"] = world.mdl_quad(*bounds, z, material)
        source = json.loads(world.model_material(texture))
        render_pass = source["passes"][0]
        render_pass["combos"]["LIGHTING"] = int(lit)
        if variant == "no-writer":
            render_pass["depthwrite"] = "disabled"
        entries[material] = world.encoded(source)
        entries[texture] = world.png(4, 4, lambda _x, _y: rgb)
    return entries


class ScenePointVolumeIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        configured = os.environ.get("MWX_SCENE_INTEGRATION_APP")
        if not configured:
            raise unittest.SkipTest("requires an explicitly frozen Debug App executable")
        cls.app = Path(configured).resolve(strict=True)
        if cls.app.suffix == ".app":
            cls.app = cls.app / "Contents/MacOS/MyWallpaperX"
        artifacts = (cls.app, cls.app.with_name("MyWallpaperX.debug.dylib"),
                     cls.app.parent.parent / "Resources/default.metallib")
        cls.app_identity = {str(path): app_runner.sha256(path) for path in artifacts if path.is_file()}
        parent = os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE")
        if parent:
            Path(parent).mkdir(parents=True, exist_ok=True)
        cls.evidence_root = Path(tempfile.mkdtemp(prefix="point-volume-app-", dir=parent))
        cls.source_identity = {str(path): app_runner.sha256(path) for path in
                               map(Path, (__file__, world.__file__, app_runner.__file__))}
        (cls.evidence_root / "regions.json").write_bytes(world.encoded(REGIONS))
        print(f"Point-volume App evidence: {cls.evidence_root}", flush=True)

    def run_volume_case(self, name, *, quality, variant="base", contributes=False):
        defaults = ("{ scenePostProcessingMode = enabled; sceneShadowQuality = disabled; "
                    f"scenePointVolumeQuality = {quality}; }}")
        with patch.object(app_runner, "measure_capture",
                          lambda path: world.measure_capture(path, REGIONS)):
            result = app_runner.SceneReflectionHistoryIntegrationTests.run_case(
                self, 0, capture=True, name=name, entries=fixture(variant),
                material_input_path=MATERIAL_PATH,
                extra_arguments=("-mwx.playback.quality", defaults))
        work = self.evidence_root / name
        log = (work / "app.log").read_text()
        identity = json.loads((work / "identity.json").read_text())
        for field, filename in (("package", "scene.pkg"), ("project", "project.json")):
            self.assertEqual(app_runner.sha256(work / "content" / filename), identity[field])
        self.assertRegex(log, rf"phase=session-candidate .*shadowQuality=disabled pointVolumeQuality={quality}\b")
        captures = {}
        for path, event in world.SceneNativeWorldCompositionTests.composition_captures(self, work, log):
            rows = event["rows"]
            model_draws = [row for row in rows if row["kind"] == "model" and row["outcome"] == "draw-encoded"]
            self.assertTrue({FOREGROUND, RECEIVER}.issubset(row["layerID"] for row in model_draws), rows)
            depth = [row for row in rows if row["kind"] == "volume-occluder-depth"]
            volume = [row for row in rows if row["kind"] == "point-volume"]
            self.assertEqual((len(depth), len(volume)), (int(contributes), int(contributes)), rows)
            if contributes:
                seal = next(row for row in rows if row["kind"] == "frame-seal" and row["outcome"] == "sealed")
                self.assertEqual(depth[0]["details"]["partCount"], "2")
                self.assertEqual(depth[0]["target"]["textureToken"], volume[0]["source"]["textureToken"])
                self.assertEqual(volume[0]["details"]["layerIDs"], str(LIGHT))
                self.assertEqual(volume[0]["details"]["quadrature"], "6" if quality == "ultra" else "4")
                self.assertEqual(volume[0]["target"]["textureToken"], seal["target"]["textureToken"])
                self.assertLess(rows.index(depth[0]), rows.index(volume[0]))
                self.assertLess(rows.index(volume[0]), rows.index(seal))
            captures[path.name] = result["pixels"][path.name]
        self.assertEqual(set(captures), {"scene-ready-window.png", "scene-after-window.png"})
        return captures, identity["package"]

    def test_on_off_preserves_direct_light_and_opaque_foreground(self):
        enabled, enabled_package = self.run_volume_case("enabled", quality="enabled", contributes=True)
        disabled, disabled_package = self.run_volume_case("disabled", quality="disabled")
        ultra, ultra_package = self.run_volume_case("ultra", quality="ultra", contributes=True)
        self.assertEqual(enabled_package, disabled_package)
        self.assertEqual(enabled_package, ultra_package)
        self.assertEqual(enabled, ultra)  # This fixture uses an exactly integrated uniform light.
        for phase, on in enabled.items():
            with self.subTest(phase=phase):
                off = disabled[phase]
                self.assertGreater(on["halo"]["mean"][0], off["halo"]["mean"][0] + 30)
                self.assertLessEqual(off["halo"]["maximum"][0], 1)
                self.assertGreater(off["direct"]["mean"][0], 10)
                self.assertGreater(off["occluded"]["mean"][1], 100)
                for region in ("direct", "occluded", "outside"):
                    self.assertEqual(on[region]["mean"], off[region]["mean"], (region, on, off))

    def test_user_enabled_does_not_change_author_or_camera_admission(self):
        for variant in ("author-disabled", "author-shadow", "no-writer", "accumulating", "orthographic"):
            with self.subTest(variant=variant):
                quality = "ultra" if variant in ("author-shadow", "accumulating") else "enabled"
                measurements, _ = self.run_volume_case(variant, quality=quality, variant=variant)
                if variant != "orthographic":
                    for capture in measurements.values():
                        self.assertLessEqual(capture["halo"]["maximum"][0], 1)
                        self.assertGreater(capture["direct"]["mean"][0], 10)


if __name__ == "__main__":
    unittest.main()
