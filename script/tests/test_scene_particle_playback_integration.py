"""Real QuickJS -> per-surface particle state -> final compositor checks.

Requires MWX_SCENE_INTEGRATION_APP pointing at an explicitly frozen Debug App.
All content is authored here and all runtime state stays in an isolated directory.
"""
from pathlib import Path
import json
import hashlib
import os
import re
import shutil
import struct
import subprocess
import tempfile
import unittest
import zlib

from script.web_benchmark_capture import png_rgb_pixels
from .test_scene_pkg_cache_extractor import make_package


class SceneParticlePlaybackIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        app = os.environ.get("MWX_SCENE_INTEGRATION_APP")
        if not app:
            raise unittest.SkipTest("requires an explicitly frozen Debug executable")
        cls.app = Path(app).resolve(strict=True)

    def run_particle(self, init, update="", screens=1, fault=None, continuous=False,
                     script_field="alpha", return_expression="value",
                     directional_births=False, initial_value=1):
        def chunk(kind, payload):
            return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload) & 0xffffffff)
        png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 4, 4, 8, 6, 0, 0, 0))
               + chunk(b"IDAT", zlib.compress((b"\0" + b"\xff" * 16) * 4)) + chunk(b"IEND", b""))
        script = ("export function init(value) {" + init + "return " + return_expression
                  + ";} export function update(value) {" + update + "return " + return_expression + ";}")
        scene = {"version": 3, "general": {"orthogonalprojection": {"width": 128, "height": 128}, "clearcolor": "0 0 0"},
                 "objects": [{"id": 1, "name": "Stable green peer", "image": "models/util/solidlayer.json", "origin": "110 110 0", "size": "12 12", "color": "0 1 0"},
                             {"id": 42, "name": "Controlled particles", "particle": "particles/controlled.json", "origin": "64 64 0", "scale": "1 1 1", "visible": True,
                              "instanceoverride": {script_field: {"value": initial_value, "script": script}}}]}
        definition = {"material": "materials/controlled.json", "maxcount": 64, "starttime": 0.5,
                      "emitter": [{"name": "sphererandom", "rate": 8, "duration": 20, "instantaneous": 1, "distancemin": 0, "distancemax": 0}],
                      "initializer": [{"name": "lifetimerandom", "min": 30, "max": 30}, {"name": "sizerandom", "min": 20, "max": 20}, {"name": "colorrandom", "min": "255 0 0", "max": "255 0 0"}],
                      "renderer": [{"name": "sprite"}]}
        if continuous:
            definition["emitter"][0].pop("duration")
        if directional_births:
            definition["flags"] = 1
            definition["operator"] = [{"name": "movement", "flags": 1, "gravity": "0 0 0"}]
            definition["initializer"][1].update(min=6, max=6)
            definition["initializer"].append({"name": "velocityrandom", "min": "6 0 0", "max": "6 0 0"})
        material = {"passes": [{"shader": "genericparticle", "textures": ["controlled.png"], "blending": "translucent", "depthtest": "disabled", "depthwrite": "disabled", "cullmode": "nocull"}]}
        with tempfile.TemporaryDirectory(prefix="mwx-particle-playback-app-") as temp:
            root = Path(temp)
            content = root / "content"
            content.mkdir()
            (content / "project.json").write_text(json.dumps({"type": "scene", "file": "scene.json"}))
            (content / "scene.pkg").write_bytes(make_package([
                ("scene.json", json.dumps(scene).encode()), ("particles/controlled.json", json.dumps(definition).encode()),
                ("materials/controlled.json", json.dumps(material).encode()), ("materials/controlled.png", png)]))
            home = root / "home"
            home.mkdir()
            env = os.environ.copy()
            for key in ("MWX_SCENE_DEBUG_REJECT_PREPARED_FRAME_ONCE", "MWX_SCENE_DEBUG_DRAWABLE_UNAVAILABLE_FRAMES"):
                env.pop(key, None)
            env.update(HOME=str(home), CFFIXED_USER_HOME=str(home), MWX_SCENE_DEBUG_SURFACE_COUNT=str(screens))
            env.update(fault or {})
            evidence = root / "evidence"
            result = subprocess.run([str(self.app), "--mwx-debug-scene-root", str(content), "--mwx-debug-scene-duration", "7",
                                     "--mwx-debug-scene-evidence-dir", str(evidence)], env=env, capture_output=True, text=True, timeout=60)
            log = result.stdout + result.stderr
            preview = "\n".join(path.read_text() for path in evidence.glob("*preview*.log"))
            captures = list(evidence.glob("*-window.png"))
            if destination := os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE"):
                saved = Path(destination) / self._testMethodName
                saved.mkdir(parents=True, exist_ok=True)
                (saved / "app.log").write_text(log)
                (saved / "scene-preview.log").write_text(preview)
                for source in evidence.rglob("*"):
                    if source.is_file():
                        target = saved / source.relative_to(evidence)
                        target.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copy2(source, target)
                for name in ("project.json", "scene.pkg"):
                    shutil.copy2(content / name, saved / name)
                identity_files = [self.app, self.app.with_name("MyWallpaperX.debug.dylib")]
                (saved / "run-identity.json").write_text(json.dumps({
                    "command": result.args,
                    "returncode": result.returncode,
                    "contentSHA256": hashlib.sha256((content / "scene.pkg").read_bytes()).hexdigest(),
                    "appFilesSHA256": {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                                       for path in identity_files if path.is_file()},
                    "screens": screens,
                    "fault": fault or {},
                }, indent=2) + "\n")
            self.assertEqual(result.returncode, 0, log[-6000:])
            self.assertNotIn("failure=exception", log)
            self.assertNotIn("phase=launch-failed", log)
            self.assertIn(f"phase=stopped surfacesBefore={screens} surfacesAfter=0", log)
            self.assertGreaterEqual(len(captures), 2)
            colors = []
            for capture in captures:
                decoded = png_rgb_pixels(capture)
                self.assertIsNotNone(decoded)
                width, height, rows = decoded
                red = green = 0
                for row in rows:
                    for i in range(0, len(row), 3):
                        r, g, b = row[i:i + 3]
                        red += r > 160 and g < 80 and b < 80
                        green += g > 160 and r < 80 and b < 80
                self.assertGreater(green, width * height * 0.001, capture.name)
                colors.append(red)
                if directional_births and "after" in capture.name:
                    # Two call-time orientations must produce separated final
                    # positions on both axes. Reusing only the last orientation
                    # puts both particles on the same six-unit sprite footprint.
                    points = [(x, y) for y, row in enumerate(rows)
                              for x in range(width)
                              if row[x * 3] > 160 and row[x * 3 + 1] < 80 and row[x * 3 + 2] < 80]
                    self.assertTrue(points, capture.name)
                    self.assertGreater(max(x for x, _ in points) - min(x for x, _ in points), width * 0.1)
                    self.assertGreater(max(y for _, y in points) - min(y for _, y in points), height * 0.1)
            consumed = [tuple(map(int, row)) for row in re.findall(
                r"phase=particle-transition-consumed frame=(\d+) layer=(\d+) revision=(\d+) action=(\d+) surface=(\d+)", log)]
            self.assertTrue(consumed, log[-6000:])
            self.assertEqual(len(consumed), len({(layer, revision, surface) for _, layer, revision, _, surface in consumed}))
            completed = {(int(frame), int(surface)) for frame, surface in re.findall(r"state=completed frame=(\d+) surface=(\d+) gpu=completed", log)}
            self.assertTrue(any(frame >= 2 for frame, _ in completed))
            return log, preview, colors, consumed, completed

    def test_init_pause_preserves_warmup_without_new_births(self):
        _, preview, colors, consumed, _ = self.run_particle("thisLayer.pause(); if (!thisLayer.isPlaying()) throw new Error('lost prepared live');")
        self.assertTrue(all(red > 0 for red in colors))
        counts = [int(value) for value in re.findall(r"particle initial live: (\d+)", preview)]
        self.assertGreaterEqual(len(counts), 2)
        self.assertEqual(set(counts), {4})
        self.assertEqual([row[3] for row in consumed], [1])

    def test_init_stop_clears_first_and_next_compositor_output(self):
        _, _, colors, consumed, _ = self.run_particle("thisLayer.stop(); if (thisLayer.isPlaying()) throw new Error('stop query true');")
        self.assertEqual(set(colors), {0})
        self.assertEqual([row[3] for row in consumed], [2])

    def test_init_stop_play_rearms_and_draws(self):
        _, _, colors, consumed, _ = self.run_particle("thisLayer.stop(); if (thisLayer.isPlaying()) throw new Error('stop query true'); thisLayer.play(); if (!thisLayer.isPlaying()) throw new Error('play query false');")
        self.assertTrue(all(red > 0 for red in colors))
        self.assertEqual([row[3] for row in consumed], [2, 0])

    def test_continuous_init_stop_clears_first_and_next_output(self):
        _, _, colors, consumed, _ = self.run_particle("thisLayer.stop(); if (thisLayer.isPlaying()) throw Error('stop query');", continuous=True)
        self.assertEqual(set(colors), {0})
        self.assertEqual([row[3] for row in consumed], [2])

    def test_continuous_pause_keeps_live(self):
        _, preview, colors, consumed, _ = self.run_particle("thisLayer.pause(); if (!thisLayer.isPlaying()) throw Error('pause lost live');", continuous=True)
        self.assertTrue(all(red > 0 for red in colors))
        self.assertEqual(set(map(int, re.findall(r"particle initial live: (\d+)", preview))), {4})
        self.assertEqual([row[3] for row in consumed], [1])
    def test_continuous_stop_play_births(self):
        _, _, colors, consumed, _ = self.run_particle("thisLayer.stop(); thisLayer.play(); if (!thisLayer.isPlaying()) throw Error('rearm query');", continuous=True)
        self.assertTrue(all(red > 0 for red in colors))
        self.assertEqual([row[3] for row in consumed], [2, 0])

    def assert_live_at_teardown(self, log, expected, screens=1, births=None):
        # This count comes from the actual simulator before teardown, not the
        # C query mirror or the requested burst count.
        counts = list(map(int, re.findall(
            r"lifecycle=teardown[^\n]*rootParticles=(\d+)", log)))
        self.assertGreaterEqual(len(counts), screens, log[-6000:])
        self.assertEqual(set(counts), {expected})
        installed = [tuple(map(int, row)) for row in re.findall(
            r"phase=particle-explicit-installed frame=(\d+) layer=(\d+) surface=(\d+) "
            r"revision=(\d+) births=(\d+) live=(\d+) firstID=(\d+) lastID=(\d+)", log)]
        self.assertEqual(len(installed), screens, log[-6000:])
        self.assertEqual(len({row[2] for row in installed}), screens)
        expected_births = expected if births is None else births
        for _, layer, _, _, actual_births, live, first_id, last_id in installed:
            self.assertEqual(layer, 42)
            self.assertEqual(actual_births, expected_births)
            self.assertEqual(live, expected)
            self.assertEqual(last_id - first_id + 1, expected_births)

    def test_explicit_three_after_stop_keeps_automatic_emission_stopped(self):
        log, _, colors, _, _ = self.run_particle(
            "thisLayer.stop(); if(thisLayer.isPlaying()) throw Error('stop query');"
            "thisLayer.emitParticles(3); if(!thisLayer.isPlaying()) throw Error('emit query');")
        self.assertTrue(all(red > 0 for red in colors))
        self.assert_live_at_teardown(log, 3)

    def test_emit_uses_call_time_lifetime_before_callback_return(self):
        log, _, colors, _, _ = self.run_particle(
            "thisLayer.stop(); thisLayer.emitParticles(3);"
            "if(!thisLayer.isPlaying()) throw Error('call-time lifetime lost');",
            script_field="lifetime", return_expression="0")
        self.assertTrue(all(red > 0 for red in colors))
        # The lifetime factor returned after emit must not retroactively turn
        # the three already initialized particles into invalid zero-life births.
        self.assert_live_at_teardown(log, 3)

    def test_callback_return_cannot_rescue_zero_lifetime_births(self):
        log, _, colors, consumed, _ = self.run_particle(
            "thisLayer.stop(); if(typeof thisLayer.emitParticles!=='function') throw Error('API missing');"
            "let rejected=false; try{thisLayer.emitParticles(3);}catch(e){rejected=true;}"
            "if(!rejected || thisLayer.isPlaying()) throw Error('zero-life birth accepted');",
            script_field="lifetime", initial_value=0, return_expression="1")
        self.assertEqual(set(colors), {0})
        counts = list(map(int, re.findall(r"lifecycle=teardown[^\n]*rootParticles=(\d+)", log)))
        self.assertTrue(counts)
        self.assertEqual(set(counts), {0})
        self.assertNotIn("phase=particle-explicit-installed", log)
        self.assertEqual([row[3] for row in consumed], [2])

    def test_paused_explicit_births_preserve_live_without_automatic_births(self):
        log, _, colors, _, _ = self.run_particle(
            "thisLayer.pause(); thisLayer.emitParticles(2);"
            "if(!thisLayer.isPlaying()) throw Error('emit query');")
        self.assertTrue(all(red > 0 for red in colors))
        # Four real prepared warm-up particles and exactly two manual births.
        self.assert_live_at_teardown(log, 6, births=2)

    def test_explicit_births_capture_each_transform_setter_prefix(self):
        log, _, colors, _, _ = self.run_particle(
            "thisLayer.stop(); thisLayer.angles=new Vec3(0,0,0); thisLayer.emitParticles(1);"
            "thisLayer.angles=new Vec3(0,0,90); thisLayer.emitParticles(1);",
            directional_births=True)
        self.assertTrue(all(red > 0 for red in colors))
        self.assert_live_at_teardown(log, 2)

    def test_explicit_births_are_not_replayed_after_drawable_failure(self):
        log, _, colors, consumed, completed = self.run_particle(
            "thisLayer.stop();",
            "shared.ticks=(shared.ticks||0)+1; if(shared.ticks===1){"
            "thisLayer.emitParticles(3); if(!thisLayer.isPlaying()) throw Error('emit query');}",
            screens=2, fault={"MWX_SCENE_DEBUG_DRAWABLE_UNAVAILABLE_FRAMES": "2"})
        self.assertTrue(all(red > 0 for red in colors))
        self.assert_live_at_teardown(log, 3, screens=2)
        absent = int(re.search(r"phase=drawable-unavailable frame=0 surface=(\d+)", log)[1])
        self.assertNotIn((0, absent), completed)
        self.assertIn((2, absent), completed)
        self.assertTrue(any(frame == 0 and surface != absent for frame, surface in completed))
        # stop and one emit are consumed per surface, independent of output retries.
        self.assertEqual(len(consumed), 4)
        self.assertEqual(len({surface for _, _, _, _, surface in consumed}), 2)

    def test_explicit_births_are_not_replayed_after_submission_rejection(self):
        log, _, colors, consumed, completed = self.run_particle(
            "thisLayer.stop();",
            "shared.ticks=(shared.ticks||0)+1; if(shared.ticks===1) thisLayer.emitParticles(3);",
            screens=2, fault={"MWX_SCENE_DEBUG_REJECT_PREPARED_FRAME_ONCE": "0"})
        self.assertTrue(all(red > 0 for red in colors))
        self.assert_live_at_teardown(log, 3, screens=2)
        rejected = int(re.search(r"state=rejected frame=0 surface=(\d+)", log)[1])
        self.assertNotIn((0, rejected), completed)
        self.assertIn((1, rejected), completed)
        self.assertTrue(any(frame == 0 and surface != rejected for frame, surface in completed))
        self.assertEqual(len(consumed), 4)

    def test_explicit_births_survive_all_drawables_missing(self):
        log, _, colors, consumed, completed = self.run_particle(
            "thisLayer.stop(); thisLayer.emitParticles(3);",
            fault={"MWX_SCENE_DEBUG_DRAWABLE_UNAVAILABLE_FRAMES": "2"})
        self.assertTrue(all(red > 0 for red in colors))
        self.assert_live_at_teardown(log, 3)
        self.assertIn("phase=drawable-unavailable frame=0", log)
        self.assertIn("phase=drawable-unavailable frame=1", log)
        self.assertFalse(any(frame < 2 for frame, _ in completed))
        self.assertEqual(len(consumed), 2)

    def assert_fault_consumes_once(self, screens, fault):
        log, _, _, consumed, completed = self.run_particle("thisLayer.stop();", "shared.ticks=(shared.ticks||0)+1; if(shared.ticks===1) thisLayer.play(); if(shared.ticks===2) thisLayer.pause();", screens, fault)
        by_surface = {}
        for frame, layer, revision, action, surface in consumed:
            self.assertEqual(layer, 42)
            by_surface.setdefault(surface, []).append((frame, revision, action))
        self.assertEqual(len(by_surface), screens)
        for values in by_surface.values():
            self.assertEqual(values, [(0, 1, 2), (0, 2, 0), (1, 3, 1)])
        return log, completed

    def test_all_drawables_missing_does_not_replay(self):
        log, completed = self.assert_fault_consumes_once(1, {"MWX_SCENE_DEBUG_DRAWABLE_UNAVAILABLE_FRAMES": "2"})
        self.assertIn("phase=drawable-unavailable frame=0", log)
        self.assertIn("phase=drawable-unavailable frame=1", log)
        self.assertFalse(any(frame < 2 for frame, _ in completed))

    def test_one_missing_drawable_keeps_peer_and_recovers(self):
        log, completed = self.assert_fault_consumes_once(2, {"MWX_SCENE_DEBUG_DRAWABLE_UNAVAILABLE_FRAMES": "2"})
        absent = int(re.search(r"phase=drawable-unavailable frame=0 surface=(\d+)", log)[1])
        self.assertNotIn((0, absent), completed)
        self.assertIn((2, absent), completed)
        self.assertTrue(any(frame == 0 and surface != absent for frame, surface in completed))

    def test_prepared_submission_rejection_does_not_replay(self):
        log, completed = self.assert_fault_consumes_once(2, {"MWX_SCENE_DEBUG_REJECT_PREPARED_FRAME_ONCE": "0"})
        absent = int(re.search(r"state=rejected frame=0 surface=(\d+)", log)[1])
        self.assertNotIn((0, absent), completed)
        self.assertIn((1, absent), completed)
        self.assertTrue(any(frame == 0 and surface != absent for frame, surface in completed))
