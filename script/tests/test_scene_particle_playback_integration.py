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
from .scene_pkg_fixture import make_package
from .scene_display_reconciliation_fixture import (
    SURFACE_IDENTITIES, assert_retained_particles, assert_retained_surfaces,
    capture_receipts, load_reconciliation_snapshots, reconciliation_interval,
)


class SceneParticlePlaybackIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        app = os.environ.get("MWX_SCENE_INTEGRATION_APP")
        if not app:
            raise unittest.SkipTest("requires an explicitly frozen Debug executable")
        cls.app = Path(app).resolve(strict=True)

    def run_particle(self, init, update="", screens=1, fault=None, continuous=False,
                     script_field="alpha", return_expression="value",
                     directional_births=False, initial_value=1, retirement=None, removal=None, transition=None):
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
        extra_definitions = []
        if retirement or removal or transition:
            destroy_update = 1 if retirement == "held" else 75
            definition["initializer"][1].update(min=24, max=24)
            definition["children"] = [{"name": "particles/child.json", "type": "eventspawn", "maxcount": 4,
                                       "offset": "20 0 0"}]
            child = {"material": "materials/controlled.json", "maxcount": 8, "starttime": 0.1,
                     "emitter": [{"name": "sphererandom", "rate": 0, "instantaneous": 1,
                                  "distancemin": 0, "distancemax": 0}],
                     "initializer": [{"name": "lifetimerandom", "min": 30, "max": 30},
                                     {"name": "sizerandom", "min": 6, "max": 6},
                                     {"name": "colorrandom", "min": "0 0 255", "max": "0 0 255"}],
                     "renderer": [{"name": "sprite"}]}
            if retirement == "active-held" or removal or transition:
                # Child batches precede opaque root sprites; keep a visible outer border.
                child["initializer"][1].update(min=36, max=36)
            if removal or transition:
                definition["children"][0].pop("offset")
            if transition:
                definition["starttime"] = 512
                definition["emitter"][0].pop("duration")
                definition["initializer"][0].update(min=4, max=4)
            peer = {**child, "starttime": 0.1}
            peer["initializer"] = [{"name": "lifetimerandom", "min": 30, "max": 30},
                                   {"name": "sizerandom", "min": 10, "max": 10},
                                   {"name": "colorrandom", "min": "0 255 255", "max": "0 255 255"}]
            scene["objects"] += [
                {"id": 43, "name": "Live particle peer", "particle": "particles/peer.json",
                 "origin": "24 24 0", "visible": True}]
            if retirement:
                scene["objects"].append({"id": 7, "name": "Live retirement controller", "image": "models/util/solidlayer.json",
                 "size": "1 1", "alpha": 0, "visible": {"value": True, "script": f"""
                    let removed=false, updates=0;
                    export function update(v){{
                        updates++;
                        if(!removed && updates>={destroy_update}){{
                            removed=true;thisScene.destroyLayer('Controlled particles');
                        }}
                        return true;
                    }}
                 """}})
            extra_definitions = [("particles/child.json", json.dumps(child).encode()),
                                 ("particles/peer.json", json.dumps(peer).encode())]
        material = {"passes": [{"shader": "genericparticle", "textures": ["controlled.png"], "blending": "translucent", "depthtest": "disabled", "depthwrite": "disabled", "cullmode": "nocull"}]}
        with tempfile.TemporaryDirectory(prefix="mwx-particle-playback-app-") as temp:
            root = Path(temp)
            content = root / "content"
            content.mkdir()
            (content / "project.json").write_text(json.dumps({"type": "scene", "file": "scene.json"}))
            (content / "scene.pkg").write_bytes(make_package([
                ("scene.json", json.dumps(scene).encode()), ("particles/controlled.json", json.dumps(definition).encode()),
                ("materials/controlled.json", json.dumps(material).encode()), ("materials/controlled.png", png),
                *extra_definitions]))
            home = root / "home"
            home.mkdir()
            env = os.environ.copy()
            for key in ("MWX_SCENE_DEBUG_REJECT_PREPARED_FRAME_ONCE", "MWX_SCENE_DEBUG_DRAWABLE_UNAVAILABLE_FRAMES",
                        "MWX_SCENE_DEBUG_REJECT_FRAME_ONCE", "MWX_SCENE_DEBUG_SURFACE_RETAIN_COUNT",
                        "MWX_SCENE_DEBUG_SURFACE_INITIAL_INDICES", "MWX_SCENE_DEBUG_SURFACE_TARGET_INDICES"):
                env.pop(key, None)
            env.update(HOME=str(home), CFFIXED_USER_HOME=str(home), MWX_SCENE_DEBUG_SURFACE_COUNT=str(screens))
            env.update(fault or {})
            if retirement:
                reconcile, pause_resume = {"held": ("2.5", "1.5:2"),
                    "missing": ("3.5", None), "active-held": ("2", "1:3")}[retirement]
                env["MWX_SCENE_DEBUG_SURFACE_REBUILD_AFTER"] = reconcile
                if pause_resume:
                    env["MWX_SCENE_DEBUG_PAUSE_RESUME_AFTER"] = pause_resume
            if removal:
                env.update(MWX_SCENE_DEBUG_SURFACE_REBUILD_AFTER="3" if removal == "paused" else "2",
                           MWX_SCENE_DEBUG_SURFACE_RETAIN_COUNT="1")
                if removal == "paused":
                    env["MWX_SCENE_DEBUG_PAUSE_RESUME_AFTER"] = "2:3"
            if transition:
                env.update(MWX_SCENE_DEBUG_SURFACE_COUNT="3", MWX_SCENE_DEBUG_SURFACE_REBUILD_AFTER="3",
                    MWX_SCENE_DEBUG_SURFACE_INITIAL_INDICES="0,1" if transition == "mixed-playing" else "0",
                    MWX_SCENE_DEBUG_SURFACE_TARGET_INDICES=("1,2" if transition == "mixed-playing"
                        else "1" if transition == "disjoint-playing" else "0,1"))
                if transition == "add-paused":
                    env["MWX_SCENE_DEBUG_PAUSE_RESUME_AFTER"] = "2:3"
            evidence = root / "evidence"
            command = [str(self.app), "--mwx-debug-scene-root", str(content),
                       "--mwx-debug-scene-duration", "8" if removal == "paused" or transition else "7",
                       "--mwx-debug-scene-evidence-dir", str(evidence)]
            if retirement == "held":
                command += ["--mwx-debug-scene-start-paused", "--mwx-debug-scene-resize-sequence", "0.5:0.8"]
            if removal or transition:
                command += ["--mwx-debug-scene-after-snapshot-delay", "2.5" if removal == "paused" or transition else "1.5"]
            result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=60)
            log = result.stdout + result.stderr
            retirement_qualification = None
            if retirement:
                retired = re.search(r"(?m)^.*lifecycle=layer-retirement[^\n]*sceneTime=([\d.]+)", log)
                limit = retired.start() if retired else 0
                census = []
                for match in re.finditer(
                    r"(?m)^.*phase=particle-child-census layer=42 templates=(\d+) systems=(\d+) "
                    r"systemParticles=(\d+) spawnedTotal=(\d+) emptyTemplates=(\d+) nonEmptySystems=(\d+) batches=(\d+)", log[:limit]):
                    census.append(dict(zip(("templates", "systems", "particles", "instances", "emptyTemplates", "nonEmptySystems", "batches"),
                                           map(int, match.groups())), line=log.count("\n", 0, match.start()) + 1, text=match.group(0)))
                action_fault = re.search(
                    rf"(?m)^.*phase=drawable-unavailable frame={destroy_update - 1} surface=(\d+)[^\n]*", log[:limit])
                retirement_qualification = {
                    "phase": retirement, "destroyUpdate": destroy_update, "expectedDestroyFrame": destroy_update - 1,
                    "missingFrames": (fault or {}).get("MWX_SCENE_DEBUG_DRAWABLE_UNAVAILABLE_FRAMES"),
                    "childQualification": "dormant-template-before-retirement" if retirement == "held" else "active-before-retirement",
                    "censusBeforeRetirement": census,
                    "retirementLine": retired.group(0) if retired else None,
                    "retirementSceneTime": float(retired.group(1)) if retired else None,
                    "faultAtActionBeforeRetirement": action_fault.group(0) if action_fault else None,
                    "faultSurface": int(action_fault.group(1)) if action_fault else None,
                    "healthyActionFrameGPUCompletion": "not-directly-observed; existing frame receipts cover indices 0...2",
                }
            preview = "\n".join(path.read_text() for path in evidence.glob("*preview*.log"))
            captures = list(evidence.glob("*-window.png"))
            if destination := os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE"):
                saved = Path(destination) / self._testMethodName
                if retirement:
                    saved /= retirement
                saved.mkdir(parents=True, exist_ok=True)
                (saved / "app.log").write_text(log)
                if retirement_qualification:
                    (saved / "retirement-qualification.json").write_text(json.dumps(retirement_qualification, indent=2) + "\n")
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
                    "removal": removal,
                    "transition": transition,
                }, indent=2) + "\n")
            self.assertEqual(result.returncode, 0, log[-6000:])
            self.assertNotIn("failure=exception", log)
            self.assertNotIn("phase=launch-failed", log)
            final_surfaces = (1 if transition == "disjoint-playing" else 2) if transition else 1 if removal else screens
            self.assertIn(f"phase=stopped surfacesBefore={final_surfaces} surfacesAfter=0", log)
            self.assertGreaterEqual(len(captures), 2)
            if retirement:
                self.assertRegex(log, r"phase=stopped[^\n]*gpuDrained=true")
                self.assertIsNotNone(retirement_qualification["retirementLine"], retirement_qualification)
                census = retirement_qualification["censusBeforeRetirement"]
                if retirement == "held":
                    self.assertGreaterEqual(len(census), screens, retirement_qualification)
                    self.assertTrue(all(row["templates"] == 1 and row["systems"] == 0 and row["particles"] == 0
                                        and row["batches"] == 0 for row in census), retirement_qualification)
                    self.assertEqual(retirement_qualification["retirementSceneTime"], 0)
                else:
                    active_children = [row for row in census if row["systems"] > 0 and row["particles"] > 0
                                       and row["instances"] > 0 and row["nonEmptySystems"] > 0 and row["batches"] > 0]
                    self.assertGreaterEqual(len(active_children), screens * (2 if retirement == "missing" else 1),
                                            retirement_qualification)
                    self.assertGreater(retirement_qualification["retirementSceneTime"], 0, retirement_qualification)
                    if retirement == "missing":
                        self.assertIsNotNone(retirement_qualification["faultAtActionBeforeRetirement"], retirement_qualification)
                self.assertRegex(log, r"phase=surface-reconciliation state=retained accepted=true")
                self.assertLess(retired.start(), log.index("lifecycle=teardown id="), retirement_qualification)
                observed = load_reconciliation_snapshots(evidence)
                paused = retirement != "missing"
                before, after, settled = assert_retained_surfaces(self, observed, screens, paused=paused)
                interval = reconciliation_interval(self, log)
                identities = assert_retained_particles(self, observed, paused=paused,
                                                        active_children=retirement == "active-held")
                for snapshot in observed.values():
                    for row in snapshot["surfacesByDisplay"].values():
                        self.assertIn(43, [layer["layerID"] for layer in row["particleLayers"]], observed)
                for row in settled["surfacesByDisplay"].values():
                    self.assertNotIn(42, [layer["layerID"] for layer in row["particleLayers"]], observed)
                if paused:
                    self.assertNotIn("phase=owner-effects-admission", interval)
                retired_ids = re.findall(r"lifecycle=teardown id=(\S+)", log)
                self.assertEqual(len(retired_ids), screens, log[-6000:])
                self.assertEqual(set(retired_ids), identities, observed)
                final = re.findall(r"lifecycle=teardown[^\n]*layers=(\d+) rootSystems=(\d+) "
                                    r"childSystems=(\d+) rootParticles=(\d+)", log)
                self.assertEqual(len(final), screens, log[-6000:])
                self.assertTrue(all(int(layers) == 1 and int(roots) == 1 and int(children) == 0
                                    and int(particles) > 0 for layers, roots, children, particles in final), final)
                if retirement == "held":
                    self.assertRegex(log, r"state=paused accepted=false[^\n]*pausedBefore=true pausedAfter=true")
                    self.assertRegex(log, rf"phase=pause-resume state=resumed accepted=false surfacesPaused={screens} "
                        rf"surfacesBeforeResume={screens} surfacesAfterResume={screens} pausedBeforeResume=true "
                        r"pausedAfterResume=false timerBeforeResume=inactive timerAfterResume=active")
                    self.assertTrue(any("scene-resize-00" in path.name for path in captures))
                elif retirement == "active-held":
                    self.assertRegex(log, r"phase=pause-resume state=paused accepted=true")
                    self.assertRegex(log, r"phase=pause-resume state=resumed accepted=true")
                    self.assertGreater(retirement_qualification["retirementSceneTime"], after["sceneTime"], observed)
                self.assertFalse(settled["isPlaybackPaused"], observed)
                self.assertGreater(settled["sceneTime"], after["sceneTime"], observed)
                self.assertTrue(any("surface-rebuild-settled" in path.name for path in captures))
            if removal:
                observed = load_reconciliation_snapshots(evidence)
                paused = removal == "paused"
                before, after, settled = assert_retained_surfaces(self, observed, screens,
                    paused=paused, remaining_screens=1)
                interval = reconciliation_interval(self, log, state="removed")
                retained = set(after["surfacesByDisplay"])
                identities = assert_retained_particles(self, observed, paused=paused,
                    active_children=True, retained_displays=retained)
                removed_ids = {row["particleStateIdentity"] for display, row in
                               before["surfacesByDisplay"].items() if display not in retained}
                during = re.findall(r"lifecycle=teardown id=(\S+)", interval)
                self.assertEqual(len(during), screens - 1, interval)
                self.assertEqual(set(during), removed_ids, observed)
                retired_ids = re.findall(r"lifecycle=teardown id=(\S+)", log)
                self.assertEqual(len(retired_ids), screens, log[-6000:])
                self.assertEqual(set(retired_ids), identities, observed)
                after_interval = log[log.index(interval) + len(interval):]
                self.assertEqual(set(re.findall(r"lifecycle=teardown id=(\S+)", after_interval)),
                                 identities - removed_ids, observed)
                populations = re.findall(r"lifecycle=teardown[^\n]*layers=(\d+) rootSystems=(\d+) "
                    r"childSystems=(\d+) rootParticles=(\d+) childParticles=(\d+)", log)
                self.assertEqual(len(populations), screens, log[-6000:])
                self.assertTrue(all(int(layers) == 2 and int(roots) == 2 and int(children) > 0
                    and int(root_count) > 0 and int(child_count) > 0
                    for layers, roots, children, root_count, child_count in populations), populations)
                for snapshot in observed.values():
                    for row in snapshot["surfacesByDisplay"].values():
                        self.assertEqual({layer["layerID"] for layer in row["particleLayers"]}, {42, 43}, observed)
                survivor = next(iter(retained))
                root_before = next(row["root"] for row in before["surfacesByDisplay"][survivor]["particleLayers"]
                                   if row["layerID"] == 42)
                root_settled = next(row["root"] for row in settled["surfacesByDisplay"][survivor]["particleLayers"]
                                    if row["layerID"] == 42)
                self.assertGreater(int(root_settled["nextParticleID"]), int(root_before["nextParticleID"]), observed)
                self.assertFalse(settled["isPlaybackPaused"], observed)
                self.assertTrue(settled["isFrameDriverActive"], observed)
                self.assertGreater(settled["sceneTime"], after["sceneTime"], observed)
                self.assertRegex(log, rf"state=removed accepted=true surfacesBefore={screens} surfacesAfter=1")
                self.assertRegex(log, r"phase=stopped[^\n]*gpuDrained=true")
                lines = log.splitlines()
                if paused:
                    trigger_index = next(index for index, line in enumerate(lines)
                        if "phase=surface-reconciliation state=triggered" in line)
                    resume_requested_index = next(index for index, line in enumerate(lines)
                        if index > trigger_index and "phase=playback-state requested=resumed" in line)
                targets = {reason: (survivor, before["surfacesByDisplay"][survivor]["surfaceIdentity"])
                    for reason in ("after", "surface-rebuild-after", "surface-rebuild-settled")}
                for reason, (encoded_index, receipt) in capture_receipts(self, log, targets).items():
                    self.assertEqual(receipt["surfaceIdentity"], before["surfacesByDisplay"][survivor]["surfaceIdentity"], receipt)
                    self.assertEqual(str(receipt["displayID"]), survivor, receipt)
                    self.assertEqual(receipt["gpuStatus"], "completed", receipt)
                    rows = receipt["rows"]
                    self.assertTrue(any(row["kind"] == "clear" and row["outcome"] == "encoded" for row in rows), receipt)
                    self.assertTrue(any(row["kind"] == "frame-seal" and row["outcome"] == "sealed" for row in rows), receipt)
                    paths = {row["details"]["particlePath"] for row in rows if row["kind"] == "particle"}
                    self.assertTrue({"particles/controlled.json", "particles/child.json", "particles/peer.json"}.issubset(paths), receipt)
                    if paused and reason != "surface-rebuild-settled":
                        if reason == "after":
                            self.assertLess(encoded_index, trigger_index, "paused pre-removal capture encoded after removal began")
                        else:
                            self.assertGreater(encoded_index, trigger_index)
                            self.assertLess(encoded_index, resume_requested_index, "paused post-removal capture encoded after resume was requested")
                        self.assertEqual(receipt["frameIndex"], before["surfacesByDisplay"][survivor]["simulationFrameIndex"], receipt)
                if paused:
                    self.assertNotIn("phase=owner-effects-admission", interval)
                    pre = png_rgb_pixels(evidence / "scene-after-window.png")
                    post = png_rgb_pixels(evidence / "scene-surface-rebuild-after-window.png")
                    self.assertEqual(pre[:2], post[:2])
                    self.assertTrue(pre[2] == post[2], "paused survivor pixels changed across display removal")
            if transition:
                observed = load_reconciliation_snapshots(evidence)
                expected = {str(row["displayID"]) for row in observed["before"]["requestedTopology"]}
                paused = transition == "add-paused"
                before, after, settled = assert_retained_surfaces(self, observed, screens,
                    paused=paused, target_displays=expected)
                originals, targets = set(before["surfacesByDisplay"]), set(after["surfacesByDisplay"])
                retained, added, removed = originals & targets, targets - originals, originals - targets
                self.assertEqual((len(retained), len(added), len(removed)),
                    (0 if transition == "disjoint-playing" else 1, 1,
                     1 if transition in ("mixed-playing", "disjoint-playing") else 0), observed)
                original_lifecycles = assert_retained_particles(self, observed, paused=paused,
                    active_children=True, retained_displays=retained, all_particles_survive=False)
                interval = reconciliation_interval(self, log, state="changed")
                removed_lifecycles = {before["surfacesByDisplay"][display]["particleStateIdentity"] for display in removed}
                self.assertEqual(set(re.findall(r"lifecycle=teardown id=(\S+)", interval)), removed_lifecycles, observed)
                for snapshot in (after, settled):
                    simulator_ids = []
                    for row in snapshot["surfacesByDisplay"].values():
                        self.assertEqual({layer["layerID"] for layer in row["particleLayers"]}, {42, 43}, observed)
                        for layer in row["particleLayers"]:
                            simulator_ids.append(layer["root"]["simulatorIdentity"])
                            simulator_ids += [child["frame"]["simulatorIdentity"] for child in layer["children"]]
                    self.assertEqual(len(simulator_ids), len(set(simulator_ids)), observed)
                for display in added:
                    newcomer = after["surfacesByDisplay"][display]
                    self.assertNotIn(newcomer["particleStateIdentity"], original_lifecycles, observed)
                    self.assertNotIn(newcomer["graphRuntimeIdentity"],
                        {row["graphRuntimeIdentity"] for row in before["surfacesByDisplay"].values()}, observed)
                    root = next(layer["root"] for layer in newcomer["particleLayers"] if layer["layerID"] == 42)
                    self.assertGreaterEqual(root["simulationTime"], 512 - 1e-7, observed)
                    if paused:
                        self.assertAlmostEqual(root["simulationTime"], 512, delta=1e-7, msg=str(observed))
                    self.assertTrue(root["particles"], observed)
                    later = settled["surfacesByDisplay"][display]
                    for field in (*SURFACE_IDENTITIES, "particleStateIdentity"):
                        self.assertEqual(later[field], newcomer[field], (display, field, observed))
                    later_root = next(layer["root"] for layer in later["particleLayers"] if layer["layerID"] == 42)
                    self.assertEqual(later_root["simulatorIdentity"], root["simulatorIdentity"], observed)
                    self.assertGreater(later_root["simulationTime"], root["simulationTime"], observed)
                final_ids = original_lifecycles | {after["surfacesByDisplay"][display]["particleStateIdentity"] for display in added}
                retired = re.findall(r"lifecycle=teardown id=(\S+)", log)
                self.assertEqual(len(retired), len(final_ids), log[-6000:])
                self.assertEqual(set(retired), final_ids, observed)
                self.assertFalse(settled["isPlaybackPaused"], observed)
                self.assertTrue(settled["isFrameDriverActive"], observed)
                self.assertGreater(settled["sceneTime"], after["sceneTime"], observed)
                self.assertNotIn("phase=surface-preparation-failed", log)
                self.assertRegex(log, r"phase=stopped[^\n]*gpuDrained=true")
                lines = log.splitlines()
                events = [(index, dict(re.findall(r"(\w+)=([^\s]+)", line)))
                    for index, line in enumerate(lines) if "phase=surface-preparation job=" in line]
                jobs = {row["job"] for _, row in events}
                self.assertEqual(len(jobs), 1, events)
                self.assertEqual([row["state"] for _, row in events],
                    ["queued", "started", "worker-returned", "adopted-or-discarded", "resources-finished"], events)
                self.assertEqual([row["mainThread"] for _, row in events], ["true", "false", "false", "true", "true"], events)
                self.assertTrue(all(set(row["displays"].split(",")) == added for _, row in events), events)
                self.assertEqual(events[-2][1]["installed"], "1", events)
                self.assertEqual(events[-1][1]["installed"], "1", events)
                observed_after = next(index for index, line in enumerate(lines)
                    if "phase=surface-reconciliation state=changed accepted=true" in line)
                self.assertLess(events[-1][0], observed_after, events)
                selected_before = min(originals, key=lambda display: before["surfacesByDisplay"][display]["windowNumber"])
                selected_after = min(targets, key=lambda display: after["surfacesByDisplay"][display]["windowNumber"])
                capture_targets = {"after": (selected_before, before["surfacesByDisplay"][selected_before]["surfaceIdentity"]),
                    "surface-rebuild-settled": (selected_after, settled["surfacesByDisplay"][selected_after]["surfaceIdentity"])}
                if retained:
                    keeper = next(iter(retained))
                    capture_targets["surface-rebuild-after"] = (keeper, after["surfacesByDisplay"][keeper]["surfaceIdentity"])
                    if not paused:
                        capture_targets["surface-preparation-during"] = (keeper, before["surfacesByDisplay"][keeper]["surfaceIdentity"])
                capture_targets.update({f"surface-added-{display}": (display, after["surfacesByDisplay"][display]["surfaceIdentity"])
                                        for display in added})
                receipts = capture_receipts(self, log, capture_targets)
                for reason, (encoded_index, receipt) in receipts.items():
                    self.assertEqual(receipt["gpuStatus"], "completed", receipt)
                    rows = receipt["rows"]
                    self.assertTrue(any(row["kind"] == "clear" and row["outcome"] == "encoded" for row in rows), receipt)
                    particle_rows = [row for row in rows if row["kind"] == "particle"]
                    paths = {row["details"]["particlePath"] for row in particle_rows}
                    self.assertTrue({"particles/controlled.json", "particles/peer.json"}.issubset(paths), receipt)
                    self.assertTrue(all(int(row["details"]["instanceCount"]) > 0 for row in particle_rows), receipt)
                    if reason.startswith("surface-added-"):
                        self.assertGreater(encoded_index, events[-2][0], receipt)
                    elif reason != "after":
                        self.assertIn("particles/child.json", paths, receipt)
                    if reason == "surface-preparation-during":
                        completed_index = next(index for index, line in enumerate(lines)
                            if "MWX SCENE COMPOSITION OBSERVATION: " in line
                            and json.loads(line.split("MWX SCENE COMPOSITION OBSERVATION: ", 1)[1]) == receipt)
                        self.assertGreater(encoded_index, events[1][0], receipt)
                        self.assertLess(encoded_index, completed_index, receipt)
                        self.assertLess(completed_index, events[2][0], receipt)
                if paused:
                    trigger = next(index for index, line in enumerate(lines) if "state=triggered surfaces=" in line)
                    resume = next(index for index, line in enumerate(lines)
                        if index > trigger and "phase=playback-state requested=resumed" in line)
                    self.assertLess(receipts["after"][0], trigger)
                    for reason in ("after", "surface-rebuild-after"):
                        self.assertEqual(receipts[reason][1]["frameIndex"],
                                         before["surfacesByDisplay"][keeper]["simulationFrameIndex"])
                    self.assertLess(receipts["surface-rebuild-after"][0], resume)
                    self.assertGreater(receipts["surface-rebuild-after"][0], trigger)
                    self.assertNotIn("phase=owner-effects-admission", interval)
                    pre = png_rgb_pixels(evidence / "scene-after-window.png")
                    post = png_rgb_pixels(evidence / "scene-surface-rebuild-after-window.png")
                    self.assertEqual(pre[:2], post[:2])
                    self.assertTrue(pre[2] == post[2], "paused retained pixels changed while preparing a new display")
            colors = []
            for capture in captures:
                decoded = png_rgb_pixels(capture)
                self.assertIsNotNone(decoded)
                width, height, rows = decoded
                red = green = blue = cyan = 0
                for row in rows:
                    for i in range(0, len(row), 3):
                        r, g, b = row[i:i + 3]
                        red += r > 160 and g < 80 and b < 80
                        green += g > 160 and r < 80 and b < 80
                        blue += b > 160 and r < 80 and g < 80
                        cyan += b > 160 and g > 160 and r < 80
                self.assertGreater(green, width * height * 0.001, capture.name)
                colors.append(red)
                if retirement or removal or transition:
                    self.assertGreater(cyan, width * height * 0.001, capture.name)
                    if removal or transition:
                        self.assertGreater(red, width * height * 0.01, capture.name)
                        if not transition or "surface-added-" not in capture.name:
                            self.assertGreater(blue, width * height * 0.001, capture.name)
                    elif (retirement == "held" and "scene-resize-00" in capture.name
                        or retirement != "missing" and "surface-rebuild-after" in capture.name):
                        self.assertGreater(red, width * height * 0.01, capture.name)
                    if retirement == "active-held" and "surface-rebuild-after" in capture.name:
                        self.assertGreater(blue, width * height * 0.001, capture.name)
                    if retirement and ("surface-rebuild-settled" in capture.name
                        or retirement != "active-held" and "pause-resume-after" in capture.name):
                        self.assertLess(red, width * height * 0.001, capture.name)
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
            if retirement or removal or transition:
                self.assertEqual(consumed, [], log[-6000:])
            else:
                self.assertTrue(consumed, log[-6000:])
            self.assertEqual(len(consumed), len({(layer, revision, surface) for _, layer, revision, _, surface in consumed}))
            completed = {(int(frame), int(surface)) for frame, surface in re.findall(r"state=completed frame=(\d+) surface=(\d+) gpu=completed", log)}
            self.assertTrue(any(frame >= 2 for frame, _ in completed))
            if retirement == "missing":
                absent = retirement_qualification["faultSurface"]
                self.assertRegex(log, rf"phase=drawable-unavailable frame=0 surface={absent}\b")
                self.assertNotIn((0, absent), completed)
                self.assertTrue(any(frame == 0 and surface != absent for frame, surface in completed), completed)
                self.assertRegex(log, rf"phase=session-first-frame[^\n]*surface={absent} gpu=completed")
            return log, preview, colors, consumed, completed

    def test_authored_root_retirement_preserves_held_output_and_retains_live_instances(self):
        for phase, fault in (("held", None), ("missing", {"MWX_SCENE_DEBUG_DRAWABLE_UNAVAILABLE_FRAMES": "90"})):
            with self.subTest(phase=phase):
                self.run_particle("", screens=2, retirement=phase, fault=fault)

    def test_active_root_and_children_remain_frozen_through_display_reconciliation(self):
        self.run_particle("", screens=2, retirement="active-held")

    def test_removed_display_preserves_playing_root_and_child_instances(self):
        self.run_particle("", screens=2, removal="playing")

    def test_removed_displays_preserve_paused_root_and_active_children(self):
        self.run_particle("", screens=3, removal="paused")

    def test_added_display_uses_full_worker_prewarm_while_retained_particles_play(self):
        self.run_particle("", screens=1, transition="add-playing")

    def test_added_display_preserves_paused_retained_root_and_children(self):
        self.run_particle("", screens=1, transition="add-paused")

    def test_mixed_display_change_retires_only_removed_and_prepares_new_owner(self):
        self.run_particle("", screens=2, transition="mixed-playing")

    def test_disjoint_display_change_recovers_with_new_worker_owned_output(self):
        self.run_particle("", screens=1, transition="disjoint-playing")

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

    def test_both_surface_seal_rejections_do_not_replay_particle_transitions(self):
        log, completed = self.assert_fault_consumes_once(2, {"MWX_SCENE_DEBUG_REJECT_FRAME_ONCE": "0"})
        self.assertEqual(len(re.findall(r"phase=frame-seal-fault state=rejected frame=0 submitted=false", log)), 2)
        self.assertFalse(any(frame == 0 for frame, _ in completed), log[-6000:])
        recovered = {surface for frame, surface in completed if frame == 1}
        self.assertEqual(len(recovered), 2, log[-6000:])
        self.assertEqual({surface for frame, surface in completed if frame == 2}, recovered)
