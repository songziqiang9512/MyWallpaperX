"""Real App mixed-provider color ABI with an ordinary three-sampler shader.

Owned package inputs only. A frozen MWX_SCENE_INTEGRATION_APP is required;
passing pixels/receipts establish this bounded chain, not official parity.
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
import zlib

from .test_scene_hidden_provider_integration import fixture_entries as hidden_fixture
from .test_scene_directional_shadow_integration import png
from .test_scene_fullscreen_visibility_integration import app_hashes, file_hashes
from .test_scene_composition_authored_order_integration import measure_capture, VERTEX
from .scene_pkg_fixture import make_package


REPO = Path(__file__).resolve().parents[2]
FRAGMENT = b'''uniform sampler2D g_Texture0;
uniform sampler2D g_Texture1; // {"mode":"rgbmask","default":"util/white"}
uniform sampler2D g_Texture2; // {"mode":"opacitymask"}
varying vec2 v_TexCoord;
void main() {
    vec4 base = texSample2D(g_Texture0, v_TexCoord);
    vec4 ink = texSample2D(g_Texture1, v_TexCoord);
    vec4 mask = texSample2D(g_Texture2, v_TexCoord);
    ink.rgb *= base.rgb;
    ink.a *= mask.r;
    gl_FragColor = ink;
}
'''
SOURCE_RGBA = (200, 80, 160, 128)
MASK_RGBA = (128, 128, 128, 255)
# Straight color crosses the named PMA publication boundary, then alpha and
# the independent mask are applied once. Double-premultiplication halves RGB.
EXPECTED_RGB = tuple(round(c * SOURCE_RGBA[3] / 255 * MASK_RGBA[0] / 255)
                     for c in SOURCE_RGBA[:3])


def encoded(value):
    return json.dumps(value, sort_keys=True).encode()


def horizontal_pair_png(left, right):
    raw = (b"\0" + bytes(left) * 2 + bytes(right) * 2) * 4
    chunks = [(b"IHDR", struct.pack(">IIBBBBB", 4, 4, 8, 6, 0, 0, 0)),
              (b"IDAT", zlib.compress(raw)), (b"IEND", b"")]
    return b"\x89PNG\r\n\x1a\n" + b"".join(
        struct.pack(">I", len(data)) + kind + data
        + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
        for kind, data in chunks)


def fixture_entries(*, three_candidates=False):
    project, entries = hidden_fixture(optional=True)
    scene = json.loads(entries["scene.json"])
    provider, consumer, peer = scene["objects"]
    provider["name"] = "Hidden half-alpha colored named source"
    consumer["name"] = "Ordinary three-slot color and opacity-mask consumer"
    peer["origin"] = "96 64 0"
    instance = consumer["effects"][0]["passes"][0]
    instance["textures"].append(None)
    instance["usertextures"].append(None)
    material = json.loads(entries["materials/own_sample.json"])
    material["passes"][0]["textures"] = [None,
        "_rt_imageLayerComposite_11_a" if three_candidates else None,
        "materials/own_opacity.png"]
    source_material = json.loads(entries["materials/blue.json"])
    source_material["passes"][0]["blending"] = "translucent"
    entries.update({"scene.json": encoded(scene),
                    "materials/own_sample.json": encoded(material),
                    "materials/blue.json": encoded(source_material),
                    "materials/blue.png": png(SOURCE_RGBA),
                    "materials/own_opacity.png": png(MASK_RGBA),
                    "shaders/own_sample.frag": FRAGMENT})
    return project, entries


def named_vector_entries(control, *, utility_provider=None):
    """Owned inputs; every consumer samples actual named publications."""
    renamed = control == "swapRename"
    shift, prefix, weight = (1000, "retitled_vector", "u_UnseenRatio") if renamed else (0, "own_vector", "g_OwnWeight")
    aid, bid, pid = 11 + shift, 12 + shift, 13 + shift
    a, b = ((0, 0, 0, 255) if control == "A0" else (192, 32, 16, 255)), \
           ((0, 0, 0, 255) if control == "B0" else (16, 160, 64, 255))
    entry = (24, 40, 56, 255)
    project, entries = hidden_fixture()
    project["general"]["properties"]["showVector"] = {"type": "bool", "value": True}
    scene = json.loads(entries["scene.json"])
    objects = []
    for identifier, asset, x in ((aid, "a", 24), (bid, "b", 64), (pid, "pattern", 104)):
        if control == "missing" and identifier == bid:
            continue
        objects.append({"id": identifier, "name": f"{prefix} hidden {asset}",
                        "image": f"models/{prefix}/{asset}.json", "origin": f"{x} 92 0",
                        "size": "24 24", "visible": False})
    sa, sb = (bid, aid) if renamed else (aid, bid)
    named = lambda identifier: f"_rt_imageLayerComposite_{identifier}_a"
    vertex = entries["shaders/own_sample.vert"]

    def effect(name, slot_sources, body, *, reads_previous=False):
        textures = [None] * (max(slot_sources, default=0) + 1)
        declarations = [f'uniform float {weight}; // {{"default":0.75}}']
        if reads_previous:
            declarations.append("uniform sampler2D g_Texture0;")
        for slot, provider in slot_sources.items():
            textures[slot] = named(provider)
            declarations.append(f"uniform sampler2D g_Texture{slot};")
        declarations.append("varying vec2 v_TexCoord;")
        shader = "\n".join(declarations) + "\nvoid main() { " + body + " }\n"
        path = f"{prefix}/{name}"
        entries[f"effects/{path}/effect.json"] = encoded({"passes": [{"material": f"materials/{path}.json"}]})
        entries[f"materials/{path}.json"] = encoded({"passes": [{"shader": path, "textures": textures,
            "blending": "normal", "depthtest": "disabled", "depthwrite": "disabled", "cullmode": "nocull"}]})
        entries[f"shaders/{path}.vert"], entries[f"shaders/{path}.frag"] = vertex, shader.encode()
        return {"id": f"{prefix}-{name}", "file": f"effects/{path}/effect.json", "visible": True}

    def mix(left, right):
        return f"gl_FragColor = vec4({weight} * ({left}).rgb + (1.0 - {weight}) * ({right}).rgb, 1.0);"

    single = effect("z-single", {2: sa, 5: sb}, mix("texSample2D(g_Texture2,v_TexCoord)", "texSample2D(g_Texture5,v_TexCoord)"))
    first = effect("z-first", {2: sa}, "gl_FragColor = texSample2D(g_Texture2,v_TexCoord);")
    second = effect("a-second", {5: sb}, mix("texSample2D(g_Texture0,v_TexCoord)", "texSample2D(g_Texture5,v_TexCoord)"), reads_previous=True)
    left, right = ("0.75", "0.25") if renamed else ("0.25", "0.75")
    paired = effect("same-provider", {2: pid, 5: pid}, mix(
        f"texSample2D(g_Texture2,vec2({left},0.5))", f"texSample2D(g_Texture5,vec2({right},0.5))"))
    healthy = effect("healthy-a-only", {2: aid}, "gl_FragColor = texSample2D(g_Texture2,v_TexCoord);")
    if utility_provider is not None:
        color = ", ".join(f"{channel}.0 / 255.0" for channel in a[:3])
        objects[0].update(name=f"{prefix} {utility_provider} composition a",
            image="models/util/composelayer.json", copybackground=False,
            visible=utility_provider == "visible",
            effects=[effect("constant-a", {}, f"gl_FragColor = vec4({color}, 1.0);")])
        entries["models/util/composelayer.json"] = encoded({"width": 24, "height": 24, "autosize": False})
    shown = {"user": "showVector", "value": True}
    consumers = [
        {"id": 22 + shift, "name": f"{prefix} solid", "image": "models/util/solidlayer.json",
         "origin": "24 72 0", "size": "24 24", "color": "0.094117647 0.156862745 0.219607843",
         "visible": shown, "dependencies": [aid, bid], "effects": [single]},
        {"id": 23 + shift, "name": f"{prefix} image cross effect", "image": f"models/{prefix}/entry.json",
         "origin": "64 72 0", "size": "24 24", "visible": shown,
         "dependencies": [aid, bid], "effects": [first, second]},
        {"id": 24 + shift, "name": f"{prefix} one provider two slots", "image": f"models/{prefix}/entry.json",
         "origin": "104 72 0", "size": "24 24", "visible": shown,
         "dependencies": [pid], "effects": [paired]},
        {"id": 25 + shift, "name": f"{prefix} healthy a-only", "image": f"models/{prefix}/entry.json",
         "origin": "64 40 0", "size": "24 24", "visible": shown,
         "dependencies": [aid], "effects": [healthy]},
        {"id": 33 + shift, "name": f"{prefix} green peer", "image": "models/util/solidlayer.json",
         "origin": "104 40 0", "size": "24 24", "color": "0 1 0"},
    ]
    scene["objects"] = objects + consumers
    entries["scene.json"] = encoded(scene)
    entries["models/util/solidlayer.json"] = encoded({"solidlayer": True, "width": 128, "height": 128})
    for name, color in (("a", a), ("b", b), ("entry", entry)):
        entries[f"models/{prefix}/{name}.json"] = encoded({"material": f"materials/{prefix}/{name}.json"})
        entries[f"materials/{prefix}/{name}.json"] = encoded({"passes": [{"shader": "genericimage", "textures": [f"materials/{prefix}/{name}.png"]}]})
        entries[f"materials/{prefix}/{name}.png"] = png(color)
    # Four rows of two constant left/right texels; UV .25/.75 samples each
    # source independently, even though both slots share one publication.
    entries[f"models/{prefix}/pattern.json"] = encoded({"material": f"materials/{prefix}/pattern.json"})
    entries[f"materials/{prefix}/pattern.json"] = encoded({"passes": [{"shader": "genericimage", "textures": [f"materials/{prefix}/pattern.png"]}]})
    entries[f"materials/{prefix}/pattern.png"] = horizontal_pair_png(a, b)
    return project, entries


def named_vector_oracle(control, shown, *, utility_provider=None):
    mixed = {"both": (148, 64, 28), "A0": (4, 40, 16), "B0": (144, 24, 12),
             "swapRename": (60, 128, 52), "missing": (148, 64, 28)}[control]
    a = (0, 0, 0) if control == "A0" else (192, 32, 16)
    expected = {"solid": (24, 40, 56) if control == "missing" else mixed,
                "image": a if control == "missing" else mixed, "sameProvider": mixed, "aOnly": a}
    rects = {"solid": (40, 104, 56, 120), "image": (120, 104, 136, 120),
             "sameProvider": (200, 104, 216, 120), "aOnly": (120, 168, 136, 184)}
    oracle = {name: {"canvasRect": rect, "expectedRGB": expected[name] if shown else (0, 0, 0)}
              for name, rect in rects.items()}
    oracle["peer"] = {"canvasRect": (200, 168, 216, 184), "expectedRGB": (0, 255, 0)}
    for name, x in (("hiddenA", 48), ("hiddenB", 128), ("hiddenPattern", 208)):
        oracle[name] = {"canvasRect": (x - 8, 64, x + 8, 80), "expectedRGB": (0, 0, 0)}
    if utility_provider == "visible":
        oracle["hiddenA"]["expectedRGB"] = a
    return oracle


def independent_source_entries(control):
    renamed = control == "renamed"
    prefix, sample = ("woven_inputs", "incoming") if renamed else ("own_source_boundary", "sampled")
    identifiers = dict(zip(("parent", "red", "empty", "solid", "consumer", "peer"),
                           (901, 403, 218, 709, 73, 42) if renamed else (20, 21, 30, 11, 22, 33)))
    empty_slot, solid_slot = (5, 2) if renamed else (2, 5)
    entries = {}

    def effect(name, slot, provider, body):
        path = f"{prefix}/{name}"
        textures = [None] * (slot + 1)
        if provider is not None:
            textures[slot] = f"_rt_imageLayerComposite_{provider}_a"
        entries[f"effects/{path}/effect.json"] = encoded({"passes": [{"material": f"materials/{path}.json"}]})
        entries[f"materials/{path}.json"] = encoded({"passes": [{"shader": path, "textures": textures,
            "blending": "normal", "depthtest": "disabled", "depthwrite": "disabled", "cullmode": "nocull"}]})
        entries[f"shaders/{path}.vert"] = VERTEX
        entries[f"shaders/{path}.frag"] = (
            f"uniform sampler2D g_Texture{slot};\nvarying vec2 v_TexCoord;\nvoid main() {{ {body} }}\n").encode()
        return {"id": f"{prefix}-{name}", "file": f"effects/{path}/effect.json", "visible": True}

    parent_effects = [
        effect("read-empty", empty_slot, identifiers["empty"],
            f"vec4 {sample}=texSample2D(g_Texture{empty_slot},v_TexCoord);"
            f"gl_FragColor=vec4({sample}.a,{sample}.r,{sample}.b,1.0);"),
        effect("blue-suffix", 0, None,
            f"vec4 {sample}=texSample2D(g_Texture0,v_TexCoord);"
            f"gl_FragColor=vec4({sample}.rgb+vec3(0.0,0.0,0.125),{sample}.a);"),
    ]
    consumer_effects = [
        effect("read-solid", solid_slot, identifiers["solid"],
            f"gl_FragColor=texSample2D(g_Texture{solid_slot},v_TexCoord);"),
        effect("green-suffix", 0, None,
            f"vec4 {sample}=texSample2D(g_Texture0,v_TexCoord);"
            f"{sample}.rgb*=vec3(1.0,0.5,1.0);gl_FragColor={sample};"),
    ]
    plain = f"models/{prefix}/plain.json"
    solid_model, solid_material = f"models/{prefix}/solid.json", f"materials/{prefix}/solid.json"
    solid_texture = f"materials/{prefix}/solid.png"
    entry_model, entry_material = f"models/{prefix}/entry.json", f"materials/{prefix}/entry.json"
    objects = [
        {"id": identifiers["parent"], "name": f"{prefix} enclosing composition", "image": "models/util/composelayer.json",
         "origin": "40 64 0", "size": "40 24", "copybackground": True,
         "dependencies": [identifiers["empty"]], "effects": parent_effects},
        {"id": identifiers["red"], "parent": identifiers["parent"], "name": f"{prefix} red enclosing prefix",
         "image": plain, "origin": "0 0 0", "size": "40 24", "color": "1 0 0"},
        {"id": identifiers["empty"], "parent": identifiers["parent"], "name": f"{prefix} source only",
         "image": "models/util/composelayer.json", "origin": "0 0 0", "size": "16 8",
         "copybackground": False, "visible": False},
        {"id": identifiers["consumer"], "name": f"{prefix} textured solid consumer", "image": entry_model,
         "origin": "88 64 0", "size": "24 24", "dependencies": [identifiers["solid"]], "effects": consumer_effects},
        {"id": identifiers["peer"], "name": f"{prefix} healthy green peer", "image": plain,
         "origin": "104 40 0", "size": "12 12", "color": "0 1 0"},
    ]
    if control == "missing-X":
        objects = [item for item in objects if item["id"] != identifiers["empty"]]
    solid = {"id": identifiers["solid"], "name": f"{prefix} hidden textured solid", "image": solid_model,
             "origin": "104 92 0", "size": "24 12", "color": "0.5 0.25 0.75", "alpha": 0.5, "visible": False,
             "instance": {"textures": [solid_texture]}}
    objects.insert(0 if control == "before" else len(objects), solid)
    scene = {"version": 3, "general": {"orthogonalprojection": {"width": 128, "height": 128},
        "clearcolor": "0 0 1"}, "objects": objects}
    entries.update({"scene.json": encoded(scene),
        "models/util/composelayer.json": encoded({"width": 40, "height": 24, "autosize": False}),
        plain: encoded({"solidlayer": True, "width": 128, "height": 128}),
        solid_model: encoded({"solidlayer": True, "material": solid_material, "width": 32, "height": 16}),
        solid_material: encoded({"passes": [{"shader": "genericimage", "textures": [solid_texture],
            "blending": "translucent", "depthtest": "disabled", "depthwrite": "disabled", "cullmode": "nocull"}]}),
        entry_model: encoded({"material": entry_material}),
        entry_material: encoded({"passes": [{"shader": "genericimage", "textures": [f"materials/{prefix}/entry.png"]}]}),
        f"materials/{prefix}/entry.png": png((24, 40, 56, 255)),
    })
    missing_solid = control == "decodeFailed-S-source"
    entries[solid_texture] = (b"owned decodeFailed PNG source" if missing_solid
                             else horizontal_pair_png((192, 128, 64, 128), (64, 192, 128, 255)))
    protocol = {"independentSourceControl": control, "layerIDs": identifiers,
        "slots": {"empty": empty_slot, "solid": solid_slot}, "rawLayerOrder": [item["id"] for item in objects],
        "emptyRGBA": (0, 0, 0, 0), "enclosingPrefixRGBA": (255, 0, 0, 255), "mainPrefixRGBA": (0, 0, 255, 255),
        "solidRGBA": ((192, 128, 64, 128), (64, 192, 128, 255)), "solidTint": (.5, .25, .75), "solidAlpha": .5,
        "solidTexture": solid_texture, "solidSourceOutcome": "decodeFailed" if missing_solid else "loaded",
        "sourceOnlyHasProgram": False,
        "sceneCanvas": 128, "oracleCanvas": 256, "channelTolerance": 2, "minimumCorrectFraction": .99,
        "oracle": {
            "transparentChild": {"canvasRect": (64, 120, 96, 136),
                                 "expectedRGB": (255, 0, 32) if control == "missing-X" else (0, 0, 32)},
            "solidLeft": {"canvasRect": (160, 120, 168, 136), "expectedRGB": (24, 20, 56) if missing_solid else (24, 4, 203)},
            "solidRight": {"canvasRect": (184, 120, 192, 136), "expectedRGB": (24, 20, 56) if missing_solid else (16, 12, 176)},
            "hiddenSolid": {"canvasRect": (200, 68, 216, 76), "expectedRGB": (0, 0, 255)},
            "mainPrefix": {"canvasRect": (124, 120, 136, 136), "expectedRGB": (0, 0, 255)},
            "peer": {"canvasRect": (200, 168, 216, 184), "expectedRGB": (0, 255, 0)},
        }, "colorBoundary": "source-only transparent RGBA; real solid texture/tint/alpha; healthy previous-current suffixes"}
    return {"type": "scene", "file": "scene.json"}, entries, protocol


class SceneMixedProviderABIIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        configured = os.environ.get("MWX_SCENE_INTEGRATION_APP")
        if not configured:
            raise unittest.SkipTest("requires an explicitly frozen Debug App")
        app = Path(configured).resolve(strict=True)
        cls.exe = app / "Contents/MacOS/MyWallpaperX" if app.suffix == ".app" else app
        cls.app_identity = app_hashes(cls.exe)

    def run_case(self, *, three_candidates=False, cache_condition="normal",
                 named_control=None, initially_shown=True, live_shown=None, utility_provider=None, source_control=None):
        parent = os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE")
        if parent:
            Path(parent).mkdir(parents=True, exist_ok=True)
        root = Path(tempfile.mkdtemp(prefix="mixed-provider-abi-", dir=parent))
        if not parent:
            self.addCleanup(shutil.rmtree, root)
        print(f"mixed provider ABI evidence: {root}", flush=True)
        content, home, evidence = root / "content", root / "home", root / "evidence"
        content.mkdir()
        home.mkdir()
        if source_control is not None:
            project, entries, source_protocol = independent_source_entries(source_control)
        else:
            project, entries = (named_vector_entries(named_control, utility_provider=utility_provider) if named_control is not None
                                else fixture_entries(three_candidates=three_candidates))
        (content / "project.json").write_bytes(encoded(project))
        (content / "scene.pkg").write_bytes(make_package(list(entries.items())))
        expected = (255, 255, 255) if three_candidates else EXPECTED_RGB
        # Reuse the existing 256-square capture mapper: this 128-square scene
        # occupies the same normalized coordinates after doubling the ROIs.
        oracle = {"consumer": {"canvasRect": (116, 116, 140, 140), "expectedRGB": expected},
                  "hiddenProvider": {"canvasRect": (36, 116, 60, 140), "expectedRGB": (0, 0, 0)},
                  "peer": {"canvasRect": (186, 122, 198, 134), "expectedRGB": (0, 255, 0)}}
        protocol = {"threeCandidates": three_candidates, "sourceRGBA": SOURCE_RGBA,
                    "cacheCondition": cache_condition,
                    "maskRGBA": MASK_RGBA, "expectedConsumerRGB": expected,
                    "sceneCanvas": 128, "oracleCanvas": 256,
                    "channelTolerance": 2, "minimumCorrectFraction": .99,
                    "oracle": oracle, "optionalSystemInput": "absent mediaThumbnail",
                    "colorBoundary": "named PMA sample -> straight RGB, alpha mask -> one PMA output"}
        if named_control is not None:
            later_shown = initially_shown if live_shown is None else live_shown
            protocol = {"namedControl": named_control,
                "sourceA": (0, 0, 0) if named_control == "A0" else (192, 32, 16),
                "sourceB": (0, 0, 0) if named_control == "B0" else (16, 160, 64),
                "sourceEntry": (24, 40, 56), "weightA": .75, "weightB": .25, "slots": (2, 5),
                "sourcePatternUV": ((.75, .5), (.25, .5)) if named_control == "swapRename" else ((.25, .5), (.75, .5)),
                "initiallyShown": initially_shown, "liveShown": live_shown,
                "utilityProvider": None if utility_provider is None else {
                    "kind": "composition", "visible": utility_provider == "visible",
                    "copybackground": False, "size": (24, 24), "childCount": 0, "alpha": 1},
                "sceneCanvas": 128, "oracleCanvas": 256,
                "channelTolerance": 2, "minimumCorrectFraction": .99,
                "oracle": named_vector_oracle(named_control, initially_shown, utility_provider=utility_provider),
                "afterOracle": named_vector_oracle(named_control, later_shown, utility_provider=utility_provider),
                "colorBoundary": "owned opaque color inputs; actual named samples, no output color substitution"}
        if source_control is not None:
            protocol = source_protocol
        properties = ({} if source_control is not None else
                      {"showVector": initially_shown} if named_control is not None else {"mode": "off"})
        command = [str(self.exe), "--mwx-debug-scene-root", str(content),
                   "--mwx-debug-scene-duration", "6", "--mwx-debug-scene-evidence-dir", str(evidence),
                   "--mwx-debug-scene-properties-json", json.dumps(properties)]
        if named_control is not None and live_shown is not None:
            command += ["--mwx-debug-scene-live-properties-json", json.dumps({"showVector": live_shown})]
        before_inputs = file_hashes(tuple(content.iterdir()))
        identity = {"command": command, "appSHA256": self.app_identity,
                    "inputSHA256": before_inputs,
                    "entrySHA256": {name: hashlib.sha256(value).hexdigest() for name, value in entries.items()},
                    "testSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), "protocol": protocol}
        (root / "prerun.json").write_bytes(encoded(identity))
        self.assertEqual(app_hashes(self.exe), self.app_identity)
        env = {key: value for key, value in os.environ.items()
               if not key.startswith(("MWX_SCENE_DEBUG_", "MYWALLPAPERX_SCENE_DEBUG_"))}
        cache_root = root / "shader-cache"
        if cache_condition == "file":
            cache_root.write_bytes(b"owned cache-root counterexample")
        elif cache_condition == "readonly":
            cache_root.mkdir()
            cache_root.chmod(0o500)
            self.addCleanup(cache_root.chmod, 0o700)
            self.assertFalse(os.access(cache_root, os.W_OK), "readonly cache fixture is still writable")
        env.update(HOME=str(home), CFFIXED_USER_HOME=str(home), MWX_SCENE_DEBUG_SURFACE_COUNT="1",
                   MWX_SCENE_GENERIC_SHADER_CACHE=str(cache_root))
        with (root / "app.log").open("w") as output:
            result = subprocess.run(command, cwd=REPO, env=env, stdout=output,
                                    stderr=subprocess.STDOUT, timeout=90)
        log = (root / "app.log").read_text()
        preview = "\n".join(path.read_text() for path in evidence.glob("*preview*.log"))
        captures = sorted(evidence.glob("*-window.png"))
        pixels = {path.name: measure_capture(path, {**protocol,
            "oracle": protocol.get("afterOracle", protocol["oracle"])
                if path.name == "scene-after-window.png" else protocol["oracle"]}) for path in captures}
        (root / "result.json").write_bytes(encoded({"exit": result.returncode, "pixels": pixels,
            "appAfter": app_hashes(self.exe), "inputsAfter": file_hashes(tuple(content.iterdir())),
            "boundary": "owned inputs and actual Metal/compositor, no official parity"}))
        self.assertEqual(app_hashes(self.exe), self.app_identity)
        self.assertEqual(file_hashes(tuple(content.iterdir())), before_inputs)
        self.assertEqual(result.returncode, 0, log[-5000:])
        if cache_condition == "file":
            self.assertEqual(cache_root.read_bytes(), b"owned cache-root counterexample")
        elif cache_condition == "readonly":
            self.assertEqual(list(cache_root.iterdir()), [])
        self.assertNotRegex(log, r"MWX SCENE STARTUP:[^\n]*phase=failed")
        self.assertNotIn("phase=launch-failed", log)
        completions = re.findall(r"state=completed frame=(\d+) surface=(\d+) gpu=completed", log)
        surfaces = {surface for frame, surface in completions if frame == "0"}
        self.assertTrue(surfaces, log[-5000:])
        self.assertTrue(any(int(frame) > 0 and surface in surfaces for frame, surface in completions))
        self.assertIn("phase=stopped surfacesBefore=1 surfacesAfter=0 gpuDrained=true", log)
        self.assertEqual(set(pixels), {"scene-ready-window.png", "scene-after-window.png"})
        for reason in ("ready", "after"):
            self.assertRegex(log, rf"phase=snapshot reason={reason} request=\d+ source=metal ")
        for capture, measured in pixels.items():
            for roi, value in measured["rois"].items():
                with self.subTest(capture=capture, roi=roi):
                    self.assertGreater(value["total"], 0, value)
                    self.assertGreaterEqual(value["correct"] / value["total"], .99, value)
        if source_control is not None:
            identifiers = protocol["layerIDs"]
            for kind, missing in (("empty", source_control == "missing-X"),
                                  ("solid", source_control == "decodeFailed-S-source")):
                capture = f"phase=named-target-capture layer={identifiers[kind]} status=succeeded"
                if missing:
                    self.assertNotIn(capture, log)
                else:
                    self.assertIn(capture, log)
            for kind in ("empty", "solid"):
                self.assertNotRegex(log + preview, rf"generic shader execution [^\n]*layer={identifiers[kind]} effect=")
                self.assertNotRegex(log, rf"axis=effect-cpu-invocation [^\n]*layer={identifiers[kind]} effect=")
                self.assertNotRegex(log, rf"axis=graph-execution [^\n]*layer={identifiers[kind]} ")
            if source_control == "decodeFailed-S-source":
                self.assertRegex(preview, rf'layer {identifiers["solid"]} "[^"\n]*": decode failed \(')
            for kind, missing in (("parent", source_control == "missing-X"),
                                  ("consumer", source_control == "decodeFailed-S-source")):
                layer_id = identifiers[kind]
                for effect_index in (0, 1):
                    outcome = "failed" if missing and effect_index == 0 else "encoded-output"
                    self.assertRegex(log, rf"axis=effect-cpu-invocation [^\n]*layer={layer_id} effect={effect_index} "
                        rf"[^\n]*backend=resolved-material-graph outcome={outcome} ")
                binding = f"phase=named-target-binding layer={layer_id} status=succeeded"
                if missing:
                    self.assertNotIn(binding, log)
                else:
                    self.assertIn(binding, log)
            return
        if named_control is not None:
            shift = 1000 if named_control == "swapRename" else 0
            if initially_shown or live_shown:
                phase = "named-target-capture" if utility_provider is None else (
                    "visible-graph-output-publication" if utility_provider == "visible"
                    else "named-graph-output-publication")
                self.assertIn(f"phase={phase} layer={11 + shift} status=succeeded", log)
                consumers = (23, 24, 25) if named_control == "missing" else (22, 23, 24, 25)
                for consumer in consumers:
                    self.assertIn(f"phase=named-target-binding layer={consumer + shift} status=succeeded", log)
                if named_control == "missing":
                    self.assertNotIn(f"phase=named-target-binding layer={22 + shift} status=succeeded", log)
            return
        capture_event = "phase=named-target-capture layer=11 status=succeeded"
        binding_event = "phase=named-target-binding layer=22 status=succeeded"
        if three_candidates:
            self.assertIn("optional-named-fallback-unproven", log + preview)
            self.assertNotIn(binding_event, log)
            self.assertNotRegex(log + preview, r"generic shader execution [^\n]*layer=22 effect=0 ")
        else:
            self.assertNotIn("optional-named-fallback-unproven", log + preview)
            self.assertIn(capture_event, log)
            self.assertIn(binding_event, log)
            self.assertRegex(log + preview, r"generic shader execution [^\n]*layer=22 effect=0 ")

    def test_ordinary_three_slot_fallback_preserves_half_alpha_named_color(self):
        self.run_case()

    def test_three_candidate_chain_degrades_locally_and_preserves_peer(self):
        self.run_case(three_candidates=True)

    def test_cache_root_file_preserves_half_alpha_named_color(self):
        self.run_case(cache_condition="file")

    def test_readonly_cache_preserves_half_alpha_named_color(self):
        self.run_case(cache_condition="readonly")

    def test_named_slot_vectors_have_independent_input_contribution_and_local_failure(self):
        for control in ("both", "A0", "B0", "swapRename", "missing"):
            with self.subTest(control=control):
                self.run_case(named_control=control)

    def test_named_slot_vector_consumers_toggle_without_exposing_hidden_providers(self):
        self.run_case(named_control="both", initially_shown=False, live_shown=True)
        self.run_case(named_control="both", initially_shown=True, live_shown=False)

    def test_childless_composition_provider_publishes_to_named_consumers_hidden_and_visible(self):
        for visibility in ("hidden", "visible"):
            with self.subTest(utilityProvider=visibility):
                self.run_case(named_control="both", utility_provider=visibility)

    def test_independent_sources_preserve_rgba_and_pixels_before_after_and_renamed(self):
        for control in ("before", "after", "renamed"):
            with self.subTest(sourceControl=control):
                self.run_case(source_control=control)

    def test_missing_or_decode_failed_independent_source_preserves_healthy_suffix_and_peer(self):
        for control in ("missing-X", "decodeFailed-S-source"):
            with self.subTest(sourceControl=control):
                self.run_case(source_control=control)


if __name__ == "__main__":
    unittest.main()
