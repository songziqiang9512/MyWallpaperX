"""Fullscreen layer/effect visibility and atomic unavailable-cohort rejection.

All package content is authored here or by existing owned fixture helpers.
Requires MWX_SCENE_INTEGRATION_APP; only MWX_SCENE_INTEGRATION_EVIDENCE retains
inputs, logs and captures. Owned fullscreen/particle cohorts do not establish
real293 whole-key repair or official pixel parity.
"""
from pathlib import Path
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zlib

from script.scene.scene_wallpaper_graph_output_metrics import (
    structured_runtime_observations, terminal_composition_snapshot,
)
from script.tests.scene.test_scene_composition_authored_order_integration import VERTEX, encoded, measure_capture
from script.tests.support.scene_pkg_fixture import make_package


WHITE, GRAY, GREEN, RED = (255, 255, 255), (128, 128, 128), (0, 255, 0), (255, 0, 0)
RECTS = {"background": (116, 116, 140, 140), "child": (52, 116, 76, 140),
         "nonchild": (180, 116, 204, 140)}
FRAGMENT = (b"uniform sampler2D g_Texture0;\nvarying vec2 v_TexCoord;\n"
            b"void main(){vec4 c=texSample2D(g_Texture0,v_TexCoord);c.rgb*=0.5;gl_FragColor=c;}\n")


def white_png():
    def chunk(kind, payload):
        return (struct.pack(">I", len(payload)) + kind + payload
                + struct.pack(">I", zlib.crc32(kind + payload) & 0xffffffff))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 4, 4, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress((b"\0" + b"\xff" * 16) * 4)) + chunk(b"IEND", b""))


def fixture_entries(*, mixed_particle=False, no_capture=False, inactive_effect=False,
                    missing_shader=False, legal_particle=False, project_script=False,
                    fullscreen_script=False, fullscreen_children=False):
    def visible(condition, fallback=True):
        return {"user": {"name": "mode", "condition": condition}, "value": fallback}
    objects = [
        {"id": 1, "name": "Owned white background", "image": "models/own_solid.json",
         "origin": "128 128 0", "size": "256 256", "color": "1 1 1"},
        {"id": 20, "name": "Owned fullscreen dim filter", "image": "models/util/fullscreenlayer.json",
         "origin": "128 128 0", "size": "256 256", "visible": visible("on"),
         "effects": [{"id": 200, "file": "effects/own_dim/effect.json",
                      "visible": {"user": "fx", "value": False} if inactive_effect else True}]},
        {"id": 30, "name": "Healthy later green peer", "image": "models/own_solid.json",
         "origin": "192 128 0", "size": "48 48", "color": "0 1 0"}]
    entries = {
        "models/own_solid.json": encoded({"solidlayer": True, "width": 256, "height": 256}),
        "models/util/fullscreenlayer.json": encoded({"width": 256, "height": 256, "autosize": False}),
        "effects/own_dim/effect.json": encoded({"passes": [{"material": "materials/own_dim.json"}]}),
        "materials/own_dim.json": encoded({"passes": [{"shader": "own_dim", "textures": [None],
            "blending": "normal", "depthtest": "disabled", "depthwrite": "disabled", "cullmode": "nocull"}]}),
        "shaders/own_dim.vert": VERTEX,
        "shaders/own_dim.frag": FRAGMENT}
    if fullscreen_children:
        objects[2:2] = [
            {"id": 70, "parent": 20, "name": "Red foreground inside effect", "image": "models/own_solid.json",
             "origin": "-64 0 0", "size": "48 48", "color": "1 0 0"},
            {"id": 71, "parent": 20, "name": "Hidden final child", "image": "models/own_solid.json",
             "origin": "-64 0 0", "size": "48 48", "color": "0 0 1", "visible": False}]
    if no_capture:
        # This authored fullscreen layer contributes no pixels. Visibility is
        # a legal no-op; an unavailable authored effect is a different case.
        objects[1].pop("effects")
        for name in ("effects/own_dim/effect.json", "materials/own_dim.json",
                     "shaders/own_dim.vert", "shaders/own_dim.frag"):
            entries.pop(name)
    if missing_shader:
        entries.pop("shaders/own_dim.frag")
    if mixed_particle or legal_particle:
        particle_visibility = ({"user": "fx", "value": False}
                               if legal_particle and inactive_effect
                               else visible("on" if legal_particle else "unsupported", False))
        size = 48 if legal_particle else 20
        objects.append({"id": 42, "name": "Owned red particle cohort" if legal_particle
                        else "Particle cohort with missing texture", "particle": "particles/owned.json",
                        "origin": "64 128 0", "scale": "1 1 1",
                        "visible": particle_visibility})
        # The negative cohort deliberately omits its actual texture. The legal
        # cohort uses a stationary sprite after the fullscreen authored slot.
        entries["particles/owned.json"] = encoded({"material": "materials/owned_particle.json",
            "maxcount": 64, "starttime": 0.5,
            "emitter": [{"name": "sphererandom", "rate": 8, "duration": 20, "instantaneous": 1,
                         "distancemin": 0, "distancemax": 0}],
            "initializer": [{"name": "lifetimerandom", "min": 30, "max": 30},
                            {"name": "sizerandom", "min": size, "max": size},
                            {"name": "colorrandom", "min": "255 0 0", "max": "255 0 0"}],
            "renderer": [{"name": "sprite"}]})
        entries["materials/owned_particle.json"] = encoded({"passes": [{"shader": "genericparticle",
            "textures": ["owned_particle.png"], "blending": "translucent", "depthtest": "disabled",
            "depthwrite": "disabled", "cullmode": "nocull"}]})
        if legal_particle:
            entries["materials/owned_particle.png"] = white_png()
    entries["scene.json"] = encoded({"version": 3, "general": {
        "orthogonalprojection": {"width": 256, "height": 256}, "clearcolor": "1 1 1"}, "objects": objects})
    definition = {"type": "combo", "value": "on", "options": [
        {"label": value, "value": value} for value in ("off", "on", "unsupported")]}
    properties = {"mode": definition}
    if inactive_effect:
        properties["fx"] = {"type": "bool", "value": False}
    if project_script or fullscreen_script:
        # Same captured-main consumer with an unseen resource name. The outer
        # Bool is an input to the real VM, whose return owns layer visibility.
        scene = json.loads(entries["scene.json"])
        if project_script:
            scene["objects"][1]["image"] = "models/util/projectlayer.json"
        scene["objects"][1]["visible"] = {
            "user": "mode", "value": False,
            "script": ("export function update(enabled) { return !enabled; }" if fullscreen_script
                       else "export function update(enabled) { return !!enabled; }")}
        entries["scene.json"] = encoded(scene)
        if project_script:
            entries["models/util/projectlayer.json"] = entries.pop("models/util/fullscreenlayer.json")
        entries = {name.replace("own_dim", "owned_project_gain"):
                   data.replace(b"own_dim", b"owned_project_gain")
                   for name, data in entries.items()}
        properties["mode"] = {"type": "bool", "value": False}
    return {"type": "scene", "file": "scene.json", "general": {"properties": properties}}, entries


def ordered_fullscreen_named_entries(*, renamed=False, consumer_visibility=False,
                                     forward_consumer=False, **parameters):
    project, entries = fixture_entries(**parameters)
    scene = json.loads(entries["scene.json"])
    canvas, red, peer = scene["objects"]
    offset = 330 if renamed else 0
    red_id, blue_id, consumer_id = (value + offset for value in (20, 21, 22))
    namespace, varying = ("color_cuts", "v_Alternate") if renamed else ("named_prefix", "v_TexCoord")
    first_key = "include_earlier_color" if renamed else "firstcut"
    placement = {"image": red["image"], "origin": red["origin"], "size": red["size"]}
    project["general"]["properties"][first_key] = {"type": "bool", "value": True}

    def effect(label, effect_id, code, *, sampled_provider=None, uses_current=False):
        name = f"{namespace}_{label}"
        descriptor = f"effects/{name}/effect.json"
        material = f"materials/{name}.json"
        entries[descriptor] = encoded({"passes": [{"material": material}]})
        # g_Texture0 refers to the current framebuffer, g_Texture1 to the authored named input.
        entries[material] = encoded({"passes": [{"shader": name,
            "textures": [None, None] if sampled_provider is not None else [None],
            "blending": "normal", "depthtest": "disabled", "depthwrite": "disabled", "cullmode": "nocull"}]})
        entries[f"shaders/{name}.vert"] = VERTEX.replace(b"v_TexCoord", varying.encode())
        declarations = []
        if uses_current:
            declarations.append("uniform sampler2D g_Texture0;")
        if sampled_provider is not None:
            declarations.append("uniform sampler2D g_Texture1;")
        code = code.replace("source*0.5", "source/2.0") if renamed else code
        fragment = "\n".join([*declarations, f"varying vec2 {varying};", "void main(){",
                              code.replace("v_TexCoord", varying), "}"])
        entries[f"shaders/{name}.frag"] = fragment.encode()
        entry = {"id": effect_id, "file": descriptor, "visible": True}
        if sampled_provider is not None:
            entry["passes"] = [{"id": effect_id + 1, "textures": [None, f"_rt_imageLayerComposite_{sampled_provider}_a"]}]
        return entry

    del entries["effects/own_dim/effect.json"], entries["materials/own_dim.json"]
    del entries["shaders/own_dim.vert"], entries["shaders/own_dim.frag"]
    first = effect("first", 220 + offset, "float source=texSample2D(g_Texture1,v_TexCoord).r;"
                   "gl_FragColor=vec4(source,0.125,0.0,1.0);", sampled_provider=red_id)
    first["visible"] = {"user": first_key, "value": True}
    red.update(id=red_id, name="Earlier red prefix", effects=[effect("red", 200 + offset,
        "float source=texSample2D(g_Texture0,v_TexCoord).r;gl_FragColor=vec4(source*0.5,0.0,0.0,1.0);",
        uses_current=True)])
    blue = dict(placement, id=blue_id, name="Second prefix turns red into blue",
                effects=[effect("blue", 210 + offset,
                    "float source=texSample2D(g_Texture0,v_TexCoord).r;gl_FragColor=vec4(0.0,0.0,source*0.5,1.0);",
                    uses_current=True)])
    consumer = dict(placement, id=consumer_id, name="Read both completed prefixes",
                    dependencies=[red_id, blue_id], effects=[first, effect("second", 222 + offset,
                        "vec4 previous=texSample2D(g_Texture0,v_TexCoord);"
                        "float namedBlue=texSample2D(g_Texture1,v_TexCoord).b;"
                        "gl_FragColor=vec4(previous.rg,namedBlue,1.0);", uses_current=True, sampled_provider=blue_id)])
    if consumer_visibility:
        key = "show_color_reader" if renamed else "showreader"
        project["general"]["properties"][key] = {"type": "bool", "value": True}
        consumer["visible"] = {"user": key, "value": True}
    canvas["id"] += offset
    peer["id"] += offset
    scene["objects"] = [canvas, red, consumer, blue, peer] if forward_consumer else [canvas, red, blue, consumer, peer]
    entries["scene.json"] = encoded(scene)
    return project, entries


def file_hashes(paths):
    return {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in paths if path.is_file()}


def app_hashes(app):
    return file_hashes((app, app.with_name("MyWallpaperX.debug.dylib"),
                        app.parents[2] / "Resources/default.metallib"))


class SceneFullscreenVisibilityIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        executable = os.environ.get("MWX_SCENE_INTEGRATION_APP")
        if not executable:
            raise unittest.SkipTest("requires explicitly frozen Debug App executable")
        cls.app = Path(executable).resolve(strict=True)
        cls.frozen_app_hashes = app_hashes(cls.app)

    def run_case(self, *, mixed_particle=False, no_capture=False, inactive_effect=False,
                 missing_shader=False, legal_particle=False, project_script=False, fullscreen_script=False,
                 fullscreen_children=False, launch=None, sequence=None,
                 expected_dims=None, expected_accepted=None, effect_layer_id=20,
                 initially_dimmed=False, expected_backgrounds=None, fixture=None):
        unavailable = mixed_particle or missing_shader
        launch = launch or {"mode": "off", **({"fx": False} if inactive_effect else {})}
        sequence = sequence or [{"mode": "on"}, {"mode": "unsupported" if mixed_particle else "off"}]
        if expected_dims is None:
            expected_dims = [not (unavailable or no_capture), False]
        if expected_backgrounds is None:
            expected_backgrounds = [GRAY if dim else WHITE for dim in [initially_dimmed, *expected_dims]]
        self.assertEqual(len(sequence) + 1, len(expected_backgrounds))
        accepted = ([str(value).lower() for value in expected_accepted]
                    if expected_accepted is not None
                    else ["false" if unavailable else "true"] * len(sequence))
        def oracle(background, particle=False, child_visible=False):
            child = (128, 0, 0) if background == GRAY else RED
            colors = {"background": background, "nonchild": GREEN,
                      "child": child if child_visible else RED if particle else background}
            return {key: {"canvasRect": rect, "expectedRGB": colors[key]} for key, rect in RECTS.items()}
        after_delay = 2 * len(sequence) + 3
        root_mode = launch.get("mode")
        snapshots = {"scene-ready-window.png": oracle(expected_backgrounds[0],
            child_visible=fullscreen_children and root_mode == "on")}
        times = {"scene-ready-window.png": 1}
        for index, background in enumerate(expected_backgrounds[1:]):
            # Each intermediate capture is 1.5s after its property request and
            # 0.5s before the next; the last gets the existing settled 'after'.
            name = ("scene-after-window.png" if index == len(sequence) - 1
                    else f"scene-series-{2 + index * 2:04d}-window.png")
            root_mode = sequence[index].get("mode", root_mode)
            snapshots[name] = oracle(background, legal_particle and index == 0,
                child_visible=fullscreen_children and root_mode == "on")
            times[name] = after_delay if index == len(sequence) - 1 else 3.5 + index * 2
        protocol = {"canvas": [256, 256], "channelTolerance": 4, "minimumCorrectFraction": .99,
                    "launch": launch, "sequenceEvery2Seconds": sequence,
                    "expectedStepAccepted": accepted, "mixedParticleMissingTexture": mixed_particle,
                    "noEffectNoOp": no_capture, "initiallyInactiveEffect": inactive_effect,
                    "missingEffectFragment": missing_shader, "legalParticleCohort": legal_particle,
                    "projectVisibilityScript": project_script, "fullscreenVisibilityScript": fullscreen_script,
                    "fullscreenChildren": fullscreen_children,
                    "effectLayerID": effect_layer_id, "initiallyDimmed": initially_dimmed,
                    "snapshotTimesSeconds": times, "snapshotOracles": snapshots,
                    "captureMapping": "centered orthographic cover, 256 square canvas"}
        project, entries = (fixture or fixture_entries)(mixed_particle=mixed_particle, no_capture=no_capture,
            inactive_effect=inactive_effect, missing_shader=missing_shader, legal_particle=legal_particle,
            project_script=project_script, fullscreen_script=fullscreen_script, fullscreen_children=fullscreen_children)
        self.assertEqual(app_hashes(self.app), self.frozen_app_hashes)
        with tempfile.TemporaryDirectory(prefix="mwx-fullscreen-visibility-") as temporary:
            root = Path(temporary)
            content, home, evidence = root / "content", root / "home", root / "evidence"
            content.mkdir()
            home.mkdir()
            (content / "project.json").write_bytes(encoded(project))
            (content / "scene.pkg").write_bytes(make_package(list(entries.items())))
            (root / "preregistration.json").write_bytes(encoded(protocol))
            input_paths = (content / "project.json", content / "scene.pkg")
            command = [str(self.app), "--mwx-debug-scene-root", str(content),
                "--mwx-debug-scene-duration", str(after_delay + 2), "--mwx-debug-scene-evidence-dir", str(evidence),
                "--mwx-debug-scene-after-snapshot-delay", str(after_delay), "--mwx-debug-scene-periodic-snapshot-interval", "1",
                "--mwx-debug-scene-properties-json", json.dumps(protocol["launch"]),
                "--mwx-debug-scene-live-property-sequence-json", json.dumps(sequence)]
            identity = {"command": command, "appSHA256": self.frozen_app_hashes,
                "inputSHA256": file_hashes(input_paths),
                "entrySHA256": {name: hashlib.sha256(value).hexdigest() for name, value in entries.items()},
                "testSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
            (root / "prerun.json").write_bytes(encoded(identity))
            env = os.environ.copy()
            env.update(HOME=str(home), CFFIXED_USER_HOME=str(home), MWX_SCENE_DEBUG_SURFACE_COUNT="1",
                       MWX_SCENE_GENERIC_SHADER_CACHE=str(root / "shader-cache"))
            log, pixels = "", {}
            try:
                result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=90)
                log = result.stdout + result.stderr
                identity["returncode"] = result.returncode
                preview = "\n".join(path.read_text() for path in evidence.glob("*preview*.log"))
                for name, expected in protocol["snapshotOracles"].items():
                    self.assertTrue((evidence / name).is_file(), (name, log[-5000:]))
                    pixels[name] = measure_capture(evidence / name, {
                        "canvas": protocol["canvas"], "oracle": expected, "channelTolerance": 4})
                self.assertEqual(result.returncode, 0, log[-5000:])
                steps = re.findall(r"phase=live-property-sequence-step index=(\d+) accepted=(true|false)", log)
                self.assertEqual(steps, [(str(i), value) for i, value in enumerate(accepted)], log[-5000:])
                updates = re.findall(r"phase=live-property-update accepted=(true|false) surfacesBefore=(\d+) surfacesAfter=(\d+) windowsBefore=(\S+) windowsAfter=(\S+)", log)
                self.assertEqual([u[0] for u in updates], accepted)
                self.assertTrue(all(u[1] == u[2] == "1" and u[3] == u[4] for u in updates), updates)
                self.assertEqual(log.count("phase=session-candidate "), 1, log[-5000:])
                self.assertEqual(log.count("phase=session-activated "), 1, log[-5000:])
                self.assertIn("gpuDrained=true", log)
                self.assertRegex(log, r"state=completed frame=[1-9]\d* surface=\d+ gpu=completed")
                for name in snapshots:
                    reason = name.removeprefix("scene-").removesuffix("-window.png")
                    self.assertRegex(log, rf"phase=snapshot reason={reason} request=\d+ source=metal ")
                self.assertNotRegex(log, r"phase=snapshot-(?:failed|rejected)")
                if not unavailable and not no_capture:
                    self.assertRegex(log + preview, rf"generic shader execution [^\n]*layer={effect_layer_id} effect=0 ")
                elif no_capture or missing_shader:
                    self.assertNotRegex(log + preview, rf"generic shader execution [^\n]*layer={effect_layer_id} effect=0 ")
                for name, measured in pixels.items():
                    for roi, value in measured["rois"].items():
                        with self.subTest(capture=name, roi=roi):
                            self.assertGreater(value["total"], 0, value)
                            self.assertGreaterEqual(value["correct"] / value["total"], .99, value)
                            self.assertTrue(all(abs(a - b) <= 4 for a, b in
                                zip(value["centerRGB"], value["expectedRGB"])), value)
                self.assertEqual(file_hashes(input_paths), identity["inputSHA256"])
                self.assertEqual(app_hashes(self.app), self.frozen_app_hashes)
                return log, pixels
            except subprocess.TimeoutExpired as error:
                log = "".join(v.decode(errors="replace") if isinstance(v, bytes) else v or ""
                              for v in (error.stdout, error.stderr))
                identity["failure"] = "subprocess-timeout"
                raise
            finally:
                identity.update(appSHA256After=app_hashes(self.app), inputSHA256After=file_hashes(input_paths))
                (root / "identity.json").write_bytes(encoded(identity))
                (root / "pixels.json").write_bytes(encoded(pixels))
                (root / "app.log").write_text(log)
                if destination := os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE"):
                    saved = Path(destination) / self._testMethodName
                    saved.mkdir(parents=True, exist_ok=True)
                    for name in ("content", "evidence"):
                        if (root / name).exists():
                            shutil.copytree(root / name, saved / name, dirs_exist_ok=True)
                    for path in root.glob("*.json"):
                        shutil.copy2(path, saved / path.name)
                    shutil.copy2(root / "app.log", saved / "app.log")

    def test_prepared_fullscreen_can_show_and_hide_in_authored_slot(self):
        self.run_case()

    def assert_ordered_fullscreen_named_inputs(self, *, renamed):
        both, second_only = (128, 32, 64), (0, 0, 64)
        offset = 330 if renamed else 0
        red, blue, consumer = (value + offset for value in (20, 21, 22))
        first_key = "include_earlier_color" if renamed else "firstcut"
        log, _ = self.run_case(launch={"mode": "on", first_key: True}, effect_layer_id=red,
            sequence=[{first_key: False}, {first_key: True}],
            expected_backgrounds=[both, second_only, both],
            fixture=lambda **kwargs: ordered_fullscreen_named_entries(renamed=renamed, **kwargs))
        self.assertNotRegex(log, r"frame-success-blueprint-rejected|predecessor-output-not-consumed")
        for layer in (red, blue):
            self.assertIn(f"phase=visible-graph-output-publication layer={layer} status=succeeded", log)
        self.assertIn(f"phase=named-target-binding layer={consumer} status=succeeded", log)
        self.assert_fullscreen_named_captures(log, consumer, [[0, 1], [1], [0, 1]])

    def assert_fullscreen_named_captures(self, log, consumer, expected_stages, *, final_fallback_stage=None):
        observations = structured_runtime_observations(log, "MWX SCENE COMPOSITION OBSERVATION: ")
        self.assertEqual(observations["parse_errors"], 0)
        reasons = ("ready", "series-0002", "after") if len(expected_stages) == 3 else ("ready", "after")
        self.assertEqual(len(reasons), len(expected_stages))
        surfaces, generations = set(), []
        for reason, stages in zip(reasons, expected_stages):
            with self.subTest(capture=reason):
                receipt = re.search(rf"phase=snapshot reason={reason} request=(\d+) source=metal ", log)
                self.assertIsNotNone(receipt)
                request = int(receipt[1])
                encoding = re.search(rf"phase=snapshot-encoded request={request} commandBufferToken=(\d+) "
                                     r"textureToken=(\d+) width=(\d+) height=(\d+)", log)
                self.assertIsNotNone(encoding)
                matched = terminal_composition_snapshot({"status": "captured", "request_id": request,
                    "command_buffer_token": encoding[1], "texture_token": encoding[2],
                    "source_width": int(encoding[3]), "source_height": int(encoding[4])}, observations)
                self.assertTrue(matched["composition_receipt_matched"], matched)
                event = next(e for e in observations["events"]
                             if e.get("captureRequestID") == request and e.get("commandBufferToken") == encoding[1])
                self.assertEqual(event["truncatedRows"], 0)
                surfaces.add(event["surfaceIdentity"])
                rows = [row for row in event["rows"] if row.get("layerID") == consumer]
                named_reads = [row for row in rows if row.get("kind") in ("material", "terminal-material-replay")
                    and row.get("slot") == 1 and row.get("outcome") == "draw-encoded"]
                self.assertEqual([row["effectIndex"] for row in named_reads], stages, named_reads)
                self.assertEqual(len({row["source"]["textureToken"] for row in named_reads}), len(stages))
                if stages:
                    generation = {row["source"]["contentGeneration"] for row in named_reads}
                    self.assertEqual(len(generation), 1, named_reads)
                    generations.append(generation.pop())
                tails = [row for row in rows if row.get("kind") == "tail-consume"
                         and row.get("outcome") == "terminal-consumed"]
                self.assertEqual(bool(tails), bool(stages))
                if final_fallback_stage is not None and reason == "after":
                    fallback = [row for row in rows if row.get("effectIndex") == final_fallback_stage]
                    self.assertEqual([(row["kind"], row["outcome"]) for row in fallback], [("copy", "encoded")])
                    self.assertEqual(fallback[0]["source"]["textureToken"], named_reads[-1]["target"]["textureToken"])
                    self.assertEqual(fallback[0]["target"]["textureToken"], tails[-1]["source"]["textureToken"])
        self.assertEqual(len(surfaces), 1)
        self.assertEqual(generations, sorted(set(generations)))

    def test_ordered_fullscreen_named_inputs_keep_both_provider_colors(self):
        self.assert_ordered_fullscreen_named_inputs(renamed=False)

    def test_renamed_fullscreen_named_inputs_keep_both_provider_colors(self):
        self.assert_ordered_fullscreen_named_inputs(renamed=True)

    def assert_named_consumer_visibility(self, *, renamed, initially_visible):
        key = "show_color_reader" if renamed else "showreader"
        red, consumer = (350, 352) if renamed else (20, 22)
        visibility = [initially_visible, not initially_visible, initially_visible]
        launch = {"mode": "on"}
        if not initially_visible:
            launch[key] = False
        log, _ = self.run_case(launch=launch, effect_layer_id=red,
            sequence=[{key: visible} for visible in visibility[1:]],
            expected_backgrounds=[(128, 32, 64) if visible else (0, 0, 64) for visible in visibility],
            fixture=lambda **kwargs: ordered_fullscreen_named_entries(
                renamed=renamed, consumer_visibility=True, **kwargs))
        self.assert_fullscreen_named_captures(log, consumer, [[0, 1] if visible else [] for visible in visibility])

    def test_hidden_fullscreen_named_consumer_reveals_and_hides_in_place(self):
        self.assert_named_consumer_visibility(renamed=False, initially_visible=False)

    def test_renamed_visible_fullscreen_named_consumer_hides_and_returns_in_place(self):
        self.assert_named_consumer_visibility(renamed=True, initially_visible=True)

    def test_forward_fullscreen_dependency_preserves_the_prepared_stage_on_reveal(self):
        log, _ = self.run_case(launch={"mode": "on", "showreader": False}, effect_layer_id=20,
            sequence=[{"showreader": True}],
            expected_backgrounds=[(0, 0, 64)] * 2,
            fixture=lambda **kwargs: ordered_fullscreen_named_entries(
                consumer_visibility=True, forward_consumer=True, **kwargs))
        self.assert_fullscreen_named_captures(log, 22, [[], [0]], final_fallback_stage=1)

    def test_forward_fullscreen_dependency_leaves_prefix_and_later_draws_playing(self):
        base_fixture = fixture_entries

        def with_forward_provider(**parameters):
            project, entries = base_fixture(**parameters)
            scene = json.loads(entries["scene.json"])
            # The provider captures the main target later; it cannot be executed early.
            scene["objects"].insert(1, {
                "id": 71, "name": "Read a later fullscreen cut", "image": "models/util/fullscreenlayer.json",
                "origin": "128 128 0", "size": "256 256", "dependencies": [20],
                "effects": [{"id": 713, "file": "effects/later_color/effect.json", "visible": True,
                             "passes": [{"id": 714, "textures": [None, "_rt_imageLayerComposite_20_a"]}]}]})
            entries.update({
                "scene.json": encoded(scene),
                "effects/later_color/effect.json": encoded({"passes": [{"material": "materials/later_color.json"}]}),
                "materials/later_color.json": encoded({"passes": [{
                    "shader": "later_color", "textures": [None, None], "blending": "normal",
                    "depthtest": "disabled", "depthwrite": "disabled", "cullmode": "nocull"}]}),
                "shaders/later_color.vert": VERTEX,
                "shaders/later_color.frag": b"uniform sampler2D g_Texture1;\nvarying vec2 v_TexCoord;\n"
                    b"void main(){float red=texSample2D(g_Texture1,v_TexCoord).r;"
                    b"gl_FragColor=vec4(red,0.0,0.0,1.0);}\n",
            })
            return project, entries

        with patch(f"{__name__}.fixture_entries", with_forward_provider):
            log, _ = self.run_case(launch={"mode": "on"}, initially_dimmed=True,
                                   sequence=[{"mode": "off"}, {"mode": "on"}], expected_dims=[False, True])
        self.assertNotRegex(log, r"frame-success-blueprint-rejected|predecessor-output-not-consumed")
        self.assertRegex(log, r"phase=utility-capture layer=20 status=succeeded")
        self.assertNotRegex(log, r"phase=utility-capture layer=71 status=")

    def test_fullscreen_reads_visible_children_before_later_peer_with_hidden_final_trigger(self):
        self.run_case(inactive_effect=True, fullscreen_children=True,
            launch={"mode": "on", "fx": False},
            sequence=[{"fx": True}, {"mode": "off"}, {"mode": "on"}, {"fx": False}],
            expected_dims=[True, False, True, False])

    def test_project_script_can_reveal_hide_and_reveal_its_prepared_capture(self):
        self.run_case(project_script=True, launch={"mode": False},
            sequence=[{"mode": True}, {"mode": False}, {"mode": True}],
            expected_dims=[True, False, True])

    def test_fullscreen_script_can_reveal_hide_and_reveal_its_prepared_capture(self):
        # The VM output opposes the direct user value, so a missing owner
        # cannot pass the captured-main pixel oracle through the lower lane.
        self.run_case(fullscreen_script=True, launch={"mode": True},
            sequence=[{"mode": False}, {"mode": True}, {"mode": False}],
            expected_dims=[True, False, True])

    def test_missing_particle_texture_rejects_the_entire_fullscreen_cohort(self):
        self.run_case(mixed_particle=True)

    def test_fullscreen_without_effect_accepts_visibility_as_noop(self):
        self.run_case(no_capture=True)

    def test_initially_inactive_effect_preserves_layer_toggle_and_live_bool(self):
        self.run_case(inactive_effect=True,
            sequence=[{"mode": "on"}, {"fx": True}, {"fx": False}, {"mode": "off"}],
            expected_dims=[False, True, False, False])

    def test_effect_changes_while_layer_hidden_are_retained_for_show(self):
        self.run_case(inactive_effect=True, launch={"mode": "on", "fx": False},
            sequence=[{"mode": "off"}, {"fx": True}, {"mode": "on"}, {"mode": "off"},
                      {"fx": False}, {"mode": "on"}],
            expected_dims=[False, False, True, False, False, False])

    def test_active_effect_missing_shader_rejects_fullscreen_visibility(self):
        self.run_case(missing_shader=True)

    def test_legal_particle_and_inactive_fullscreen_effect_share_bool_key(self):
        self.run_case(legal_particle=True, inactive_effect=True,
            launch={"mode": "on", "fx": False}, sequence=[{"fx": True}, {"fx": False}],
            expected_dims=[True, False])


if __name__ == "__main__":
    unittest.main()
