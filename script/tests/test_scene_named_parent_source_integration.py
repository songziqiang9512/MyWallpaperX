#!/usr/bin/env python3
"""Own layer sources and graph-final outputs -> named readers in the real App.

The existing reflection-history runner owns process, immutable inputs, Metal
snapshots and stop/drain. Controls distinguish parent base from descendants
and actual CoreText raster from hidden text effect output; they do not grant
utility/subtree, font-shape parity or dynamic-video semantics.
"""
from __future__ import annotations

import hashlib
import json
import math
import os
from pathlib import Path
import re
import tempfile
import unittest
from unittest.mock import patch

from script.tests import test_scene_reflection_history_integration as app_runner
from script.tests.test_scene_authored_sampling_integration import solid_texture
from script.scene_wallpaper_graph_output_metrics import (
    structured_runtime_observations, terminal_composition_snapshot,
)
from script.web_benchmark_capture import png_rgb_pixels

REPO = Path(__file__).resolve().parents[2]
CANVAS = (512, 320)
A, B, MAGENTA, FALLBACK = (192, 32, 16), (16, 160, 64), (224, 32, 208), (24, 40, 56)
CLEAR = (8, 12, 20)
TOLERANCE = 3


def encoded(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()


def fixture_entries(case):
    base_case, graph_parent = case % 3, case >= 3
    renamed = base_case == 1
    shift, word = (1000, "retitled_source") if renamed else (0, "own_parent")
    ids = {name: value + shift for name, value in
           {"parent": 20, "child": 22, "external": 23, "healthy": 21,
            "leaf": 30, "leafReader": 31, "peer": 40}.items()}
    slots = {"child": 3 if renamed else 1, "external": 2 if renamed else 5,
             "leafReader": 4 if renamed else 1}
    uv, sample = ("v_AnotherCoordinate", "incoming") if renamed else ("v_TexCoord", "sampled")
    entries = {}
    pair = solid_texture(A)[:-1024] + (bytes((*A, 255)) * 8 + bytes((*B, 255)) * 8) * 16
    for name, pixels in (("parent", pair), ("leaf", pair), ("sentinel", solid_texture(MAGENTA)),
                         ("fallback", solid_texture(FALLBACK)), ("green", solid_texture((0, 255, 0)))):
        key = f"{word}/{name}"
        entries[f"materials/{key}.tex"] = pixels
        entries[f"materials/{key}.json"] = encoded({"passes": [{"shader": "genericimage",
            "textures": [key], "blending": "normal", "depthtest": "disabled",
            "depthwrite": "disabled", "cullmode": "nocull"}]})
        entries[f"models/{key}.json"] = encoded({"material": f"materials/{key}.json",
            "width": 16, "height": 16, "autosize": False})
    vertex = ("attribute vec3 a_Position;\nattribute vec2 a_TexCoord;\n"
        f"uniform mat4 g_ModelViewProjectionMatrix;\nvarying vec2 {uv};\n"
        f"void main(){{gl_Position=mul(vec4(a_Position,1.0),g_ModelViewProjectionMatrix);{uv}=a_TexCoord;}}\n").encode()

    def effect(name, identifier, *, provider=None, slot=0, fixed=False, suffix=False,
               permute=False, paired=False):
        textures = [None] * (6 if paired else slot + 1)
        if provider is not None:
            textures[slot] = f"_rt_imageLayerComposite_{provider}_a"
        coordinate = "vec2(0.25,0.5)" if fixed else uv
        result = f"vec4({sample}.rgb*vec3(1.0,0.5,1.0),{sample}.a)" if suffix else sample
        if permute:
            result = f"vec4({sample}.gbr,{sample}.a)"
        material_key = "previous" if suffix or permute else "albedo"
        declarations = f'uniform sampler2D g_Texture{slot}; // {{"material":"{material_key}"}}\n'
        body = f"vec4 {sample}=texSample2D(g_Texture{slot},{coordinate});gl_FragColor={result};"
        if paired:
            textures[5] = textures[slot]
            declarations += 'uniform sampler2D g_Texture5; // {"material":"albedo"}\n'
            body = (f"vec4 {sample}=texSample2D(g_Texture{slot},vec2(0.75,0.5));"
                    f"vec4 other=texSample2D(g_Texture5,vec2(0.25,0.5));"
                    f"gl_FragColor=vec4(0.25*{sample}.rgb+0.75*other.rgb,1.0);")
        path = f"{word}/{name}"
        entries[f"effects/{path}/effect.json"] = encoded({"passes": [{"material": f"materials/{path}.json"}]})
        entries[f"materials/{path}.json"] = encoded({"passes": [{"shader": path,
            "textures": textures, "blending": "normal", "depthtest": "disabled",
            "depthwrite": "disabled", "cullmode": "nocull"}]})
        entries[f"shaders/{path}.vert"] = vertex
        entries[f"shaders/{path}.frag"] = (declarations + f"varying vec2 {uv};\nvoid main(){{{body}}}\n").encode()
        return {"id": identifier, "file": f"effects/{path}/effect.json", "visible": True}

    def card(name, model, x, y, width, height, **extra):
        return {"id": ids[name], "name": f"{word} {name}", "image": f"models/{word}/{model}.json",
                "origin": f"{x} {y} 0", "size": f"{width} {height}", "visible": True, **extra}

    child = card("child", "fallback", 96, 0, 24, 24, parent=ids["parent"],
        dependencies=[ids["parent"]], effects=[
            effect("read-child", ids["child"] * 10, provider=ids["parent"], slot=slots["child"], fixed=True),
            effect("child-suffix", ids["child"] * 10 + 1, suffix=True)])
    external = card("external", "fallback", 384, 128, 128, 64, dependencies=[ids["parent"]], effects=[
        effect("read-external", ids["external"] * 10, provider=ids["parent"], slot=slots["external"], paired=case == 4),
        effect("external-suffix", ids["external"] * 10 + 1, suffix=True)])
    leaf_reader = card("leafReader", "fallback", 384, 48, 128, 32, dependencies=[ids["leaf"]], effects=[
        effect("read-leaf", ids["leafReader"] * 10, provider=ids["leaf"], slot=slots["leafReader"])])
    parent = card("parent", "parent", 128, 128, 128, 64)
    if graph_parent:
        parent["effects"] = [effect("parent-gbr", ids["parent"] * 10, permute=True)]
    scene = {"version": 3, "general": {"orthogonalprojection": {"width": CANVAS[0], "height": CANVAS[1]},
        "clearcolor": " ".join(str(c / 255) for c in CLEAR)}, "objects": [
            card("leaf", "leaf", 128, 48, 128, 32), leaf_reader,
            parent,
            card("healthy", "sentinel", -32, 0, 24, 24, parent=ids["parent"]), child, external,
            card("peer", "green", 464, 48, 12, 12)]}
    entries["scene.json"] = encoded(scene)
    if base_case == 2:
        del entries[f"materials/{word}/parent.tex"]
    return entries



def text_entries(case):
    renamed = case in (8, 12)
    entries = fixture_entries(1 if renamed else 0)
    graph_entries = fixture_entries(4 if renamed else 3)
    word, shift = ("retitled_source", 1000) if renamed else ("own_parent", 0)
    scene = json.loads(entries["scene.json"])
    keep = {20 + shift, 23 + shift, 40 + shift}
    scene["objects"] = [obj for obj in scene["objects"] if obj["id"] in keep]
    source = next(obj for obj in scene["objects"] if obj["id"] == 20 + shift)
    source.clear()
    source.update(id=20 + shift, name=f"{word} hidden red text", text="MMMM",
        font="systemfont_arial", pointsize=20, color="1 0 0", origin="128 128 0",
        size="128 64", visible=False)
    if case != 6:
        graph_source = next(obj for obj in json.loads(graph_entries["scene.json"])["objects"] if obj["id"] == 20 + shift)
        source["effects"] = graph_source["effects"]
        for name, data in graph_entries.items():
            if "parent-gbr" in name:
                entries[name] = data
    if case in (9, 10):
        key = f"{word}/missing-text-effect-input"
        entries[f"effects/{key}/effect.json"] = encoded({"passes": [{"material": f"materials/{key}.json"}]})
        entries[f"materials/{key}.json"] = encoded({"passes": [{"shader": key,
            "textures": [None, f"{word}/absent-text-effect-asset"], "blending": "normal",
            "depthtest": "disabled", "depthwrite": "disabled", "cullmode": "nocull"}]})
        entries[f"shaders/{key}.vert"] = entries[f"shaders/{word}/read-external.vert"]
        entries[f"shaders/{key}.frag"] = b'\n'.join([
            b'uniform sampler2D g_Texture0; // {"material":"previous"}',
            b'uniform sampler2D g_Texture1; // {"material":"albedo"}',
            b'varying vec2 v_TexCoord;', b'void main(){gl_FragColor=texSample2D(g_Texture0,v_TexCoord)*texSample2D(g_Texture1,v_TexCoord);}'])
        source["effects"].insert(0, {"id": 299, "file": f"effects/{key}/effect.json", "visible": True})
        if case == 10:
            entries[f"materials/{word}/absent-text-effect-asset.tex"] = solid_texture((255,255,255))
    if case in (11, 12):
        slots = (1, 7) if renamed else (3,)
        uv, metadata = ("v_RetitledUV", "v_RetitledMetadata") if renamed else ("v_TexCoord", "v_Metadata")
        declarations = "".join(f"uniform vec4 g_Texture{slot}Resolution;\n" for slot in slots)
        value = (f"vec4(g_Texture{slots[0]}Resolution.xy,g_Texture{slots[-1]}Resolution.xy)"
                 if renamed else f"g_Texture{slots[0]}Resolution")
        entries[f"shaders/{word}/parent-gbr.vert"] = (
            "attribute vec3 a_Position;\nattribute vec2 a_TexCoord;\n"
            "uniform mat4 g_ModelViewProjectionMatrix;\n" + declarations +
            f"varying vec2 {uv};\nvarying vec4 {metadata};\n"
            f"void main(){{gl_Position=mul(vec4(a_Position,1.0),g_ModelViewProjectionMatrix);"
            f"{uv}=a_TexCoord;{metadata}={value};}}\n").encode()
        optional = "".join(f'uniform sampler2D g_Texture{slot}; // '
            f'{{"material":"{word}_optional_{ordinal}","combo":"OWN_AUX_{ordinal}"}}\n'
            for ordinal, slot in enumerate(slots))
        guarded = "".join(f"\n#if OWN_AUX_{ordinal}\n"
            f"color=texSample2D(g_Texture{slot},{uv});\n#endif\n"
            for ordinal, slot in enumerate(slots))
        gain = f"({metadata}.x+{metadata}.w)*0.125" if renamed else f"dot({metadata}.xy,vec2(0.125))"
        entries[f"shaders/{word}/parent-gbr.frag"] = (
            'uniform sampler2D g_Texture0; // {"material":"previous"}\n' + optional +
            f"varying vec2 {uv};\nvarying vec4 {metadata};\n"
            f"void main(){{vec4 color=texSample2D(g_Texture0,{uv});" + guarded +
            f"gl_FragColor=vec4(color.gbr*({gain}),color.a);}}\n").encode()
    suffix = f"shaders/{word}/external-suffix.frag"
    entries[suffix] = entries[suffix].replace(b"vec3(1.0,0.5,1.0)", b"vec3(0.5)")
    scene["objects"].append({"id": 42 + shift, "name": f"{word} green text peer",
        "text": "MMMM", "font": "systemfont_arial", "pointsize": 20, "color": "0 1 0",
        "origin": "128 48 0", "size": "128 32", "visible": True})
    entries["scene.json"] = encoded(scene)
    return entries


def text_protocol(case):
    return {"case": case, "source": 1020 if case in (8, 12) else 20,
        "consumer": 1023 if case in (8, 12) else 23, "slot": 2 if case in (8, 12) else 5,
        "sourceHasGraph": case != 6, "sourceMissingAsset": case == 9,
        "sourceHasAssetPass": case in (9,10), "sourceColorEffectIndex": 1 if case in (9,10) else 0,
        "consumerCoreRGB": [128, 0, 0] if case == 6 else [0, 0, 64] if case in (11, 12) else [0, 0, 128],
        "rects": {"consumer": [320, 96, 448, 160], "hidden": [64, 96, 192, 160],
                  "glyphPeer": [64, 32, 192, 64]},
        "minimumCorePixels": 64, "tolerance": 2,
        "scope": "Actual CoreText glyph, prepared effect output and explicit named slot; no font-shape or author parity."}


def measure_text_capture(path, requested):
    decoded = png_rgb_pixels(path)
    if decoded is None:
        raise AssertionError(f"undecodable text PNG: {path}")
    width, height, rows = decoded
    scale = max(width / CANVAS[0], height / CANVAS[1])
    result = {"size": [width, height]}
    for name, (left, bottom, right, top) in requested["rects"].items():
        x0, x1 = [round(width / 2 + (x - CANVAS[0] / 2) * scale) for x in (left, right)]
        y0, y1 = [round(height / 2 - (y - CANVAS[1] / 2) * scale) for y in (top, bottom)]
        if not (0 <= x0 < x1 <= width and 0 <= y0 < y1 <= height):
            raise AssertionError(f"declared text region cropped: {name}")
        values = [rows[y][x*3:x*3+3] for y in range(y0,y1) for x in range(x0,x1)]
        expected = CLEAR if name == "hidden" else (0,255,0) if name == "glyphPeer" else requested["consumerCoreRGB"]
        result[name] = {"bounds": [x0,y0,x1,y1], "pixels": len(values),
            "core": sum(max(abs(v[c]-expected[c]) for c in range(3)) <= requested["tolerance"] for v in values),
            "wrongRawRed": sum(v[0] > 64 and v[1] < 4 and v[2] < 4 for v in values)}
    return result


def protocol(case):
    base_case = case % 3
    shift = 1000 if base_case == 1 else 0
    good = base_case != 2
    requested = {"case": ("ordinary", "renamed", "missing-parent-source")[base_case],
        "canvas": CANVAS, "tolerance": TOLERANCE, "radiusPixels": 2,
        "ids": {k: v + shift for k, v in {"parent": 20, "child": 22, "external": 23,
            "healthy": 21, "leaf": 30, "leafReader": 31, "peer": 40}.items()},
        "slots": {"child": 3 if base_case == 1 else 1, "external": 2 if base_case == 1 else 5,
                  "leafReader": 4 if base_case == 1 else 1},
        "missingParentTexture": not good,
        "sourceRole": "ordinary image owns its base; transform children are not texture members",
        "ROIs": {
            "parentRight": {"world": (160, 128), "RGB": B if good else CLEAR},
            "healthyChild": {"world": (96, 128), "RGB": MAGENTA},
            "childReader": {"world": (224, 128), "RGB": (192, 16, 16) if good else (24, 20, 56)},
            "externalLeft": {"world": (352, 128), "RGB": (192, 16, 16) if good else (24, 20, 56)},
            "externalRight": {"world": (416, 128), "RGB": (16, 80, 64) if good else (24, 20, 56)},
            "leafLeft": {"world": (96, 48), "RGB": A},
            "leafRight": {"world": (160, 48), "RGB": B},
            "leafReaderLeft": {"world": (352, 48), "RGB": A},
            "leafReaderRight": {"world": (416, 48), "RGB": B},
            "peer": {"world": (464, 48), "RGB": (0, 255, 0)},
        }, "ceilings": ["No parent effect, alpha/tint, hidden lifecycle or video qualification",
            "Raw capture completion log is sticky; shared input tokens do not alone count physical captures",
            "Typed source fields only; Swift identity descriptions are not parsed"]}
    if case >= 3:
        requested.update(case=("graph", "graph-renamed-paired", "graph-missing-source")[base_case],
            parentGraph=True, sourceRole="ordinary parent own graph-final, excluding transform descendants")
        requested["ceilings"][0] = "No alpha/tint, utility/subtree, forward/hidden or video qualification"
        requested["ceilings"][1] = "Graph publication copies to a reserved target; no selected typed copy edge or physical-copy count"
        if good:
            colors = {"parentRight": (160, 64, 16), "childReader": (32, 8, 192),
                      "externalLeft": (32, 8, 192), "externalRight": (160, 32, 16)}
            if case == 4:
                colors.update(externalLeft=(64, 14, 148), externalRight=(64, 14, 148))
                requested["externalSlots"] = [2, 5]
            for region, color in colors.items():
                requested["ROIs"][region]["RGB"] = color
    return requested


def measure_capture(path, requested):
    decoded = png_rgb_pixels(path)
    if decoded is None:
        raise AssertionError(f"undecodable PNG: {path}")
    width, height, rows = decoded
    scale = max(width / CANVAS[0], height / CANVAS[1])
    result = {"size": [width, height]}
    for name, region in requested["ROIs"].items():
        x, y = region["world"]
        px, py = width / 2 + (x - CANVAS[0] / 2) * scale, height / 2 - (y - CANVAS[1] / 2) * scale
        bounds = (math.ceil(px - 2), math.ceil(py - 2), math.floor(px + 2), math.floor(py + 2))
        x0, y0, x1, y1 = bounds
        if not (0 <= x0 < x1 <= width and 0 <= y0 < y1 <= height):
            raise AssertionError(f"preregistered ROI cropped: {name} {bounds} {(width, height)}")
        values = [rows[yy][xx * 3:xx * 3 + 3] for yy in range(y0, y1) for xx in range(x0, x1)]
        result[name] = {"bounds": bounds, "count": len(values),
            "mean": [sum(v[c] for v in values) / len(values) for c in range(3)],
            "minimum": [min(v[c] for v in values) for c in range(3)],
            "maximum": [max(v[c] for v in values) for c in range(3)]}
    return result


class SceneNamedParentSourceIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        configured = os.environ.get("MWX_SCENE_INTEGRATION_APP")
        if not configured:
            raise unittest.SkipTest("requires an explicitly frozen Debug App executable")
        cls.app = Path(configured).resolve(strict=True)
        binaries = [cls.app, cls.app.with_name("MyWallpaperX.debug.dylib"),
                    cls.app.parent.parent / "Resources/default.metallib"]
        cls.app_identity = {str(p): app_runner.sha256(p) for p in binaries if p.is_file()}
        destination = os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE")
        if destination:
            Path(destination).mkdir(parents=True, exist_ok=True)
        cls.evidence_root = Path(tempfile.mkdtemp(prefix="named-parent-source-", dir=destination))
        sources = [Path(__file__), Path(app_runner.__file__),
            REPO / "script/tests/test_scene_authored_sampling_integration.py",
            REPO / "script/tests/scene_pkg_fixture.py", REPO / "script/web_benchmark_capture.py"]
        cls.source_identity = {str(p): app_runner.sha256(p) for p in sources}
        preregistered = {str(i): {"protocol": protocol(i), "entries": {
            name: hashlib.sha256(data).hexdigest() for name, data in fixture_entries(i).items()}} for i in range(6)}
        (cls.evidence_root / "protocol.json").write_bytes(encoded({"cases": preregistered,
            "app": cls.app_identity, "sources": cls.source_identity}))
        print(f"Named parent source App evidence: {cls.evidence_root}", flush=True)

    def test_raw_parent_base_supplies_child_and_external_without_descendants(self):
        self.run_parent_case(0)

    def test_renamed_parent_and_missing_source_preserve_healthy_children(self):
        for case in (1, 2):
            with self.subTest(case=case):
                self.run_parent_case(case)

    def test_parent_graph_final_supplies_child_and_external_without_descendants(self):
        self.run_parent_case(3)

    def test_parent_graph_paired_renaming_and_missing_source_stay_local(self):
        for case in (4, 5):
            with self.subTest(case=case):
                self.run_parent_case(case)

    def test_hidden_coretext_graph_final_and_local_failure_supply_named_readers(self):
        for case in range(6, 11):
            with self.subTest(case=case):
                self.run_text_case(case)

    def test_unbound_optional_resolution_reaches_coretext_named_output(self):
        for case in (11, 12):
            with self.subTest(case=case):
                self.run_text_case(case)

    def run_text_case(self, case):
        requested = text_protocol(case)
        (self.evidence_root / f"text-protocol-{case}.json").write_bytes(encoded(requested))
        word = "retitled_source" if case in (8, 12) else "own_parent"
        with patch.object(app_runner, "fixture_entries", text_entries), patch.object(
                app_runner, "measure_capture", lambda path: measure_text_capture(path, requested)):
            result = app_runner.SceneReflectionHistoryIntegrationTests.run_case(self, case, capture=True,
                extra_arguments=("--mwx-debug-scene-after-snapshot-delay", "3"),
                material_input_path=f"materials/{word}/parent.json")
        work = self.evidence_root / f"Ref{case}-capture-on"
        for name, measurements in result["pixels"].items():
            self.assertGreaterEqual(measurements["consumer"]["core"], requested["minimumCorePixels"], (name, measurements))
            self.assertGreaterEqual(measurements["glyphPeer"]["core"], requested["minimumCorePixels"], (name, measurements))
            self.assertEqual(measurements["hidden"]["core"], measurements["hidden"]["pixels"], (name, measurements))
            if requested["sourceHasGraph"]:
                self.assertEqual(measurements["consumer"]["wrongRawRed"], 0, (name, measurements))
        log = (work / "app.log").read_text()
        observations = structured_runtime_observations(log, "MWX SCENE COMPOSITION OBSERVATION: ")
        self.assertEqual(observations["parse_errors"], 0)
        receipts = []
        for name in ("scene-ready-window.png", "scene-after-window.png"):
            path = work / "evidence" / name
            reason = name.removeprefix("scene-").removesuffix("-window.png")
            request = re.search(rf"phase=snapshot reason={reason} request=(\d+) source=metal path={re.escape(str(path))}", log)
            self.assertIsNotNone(request)
            capture = re.search(rf"phase=snapshot-encoded request={request[1]} commandBufferToken=(\d+) textureToken=(\d+) width=(\d+) height=(\d+)", log)
            self.assertIsNotNone(capture)
            receipt = terminal_composition_snapshot({"status": "captured", "request_id": int(request[1]),
                "command_buffer_token": capture[1], "texture_token": capture[2],
                "source_width": int(capture[3]), "source_height": int(capture[4])}, observations)
            self.assertTrue(receipt["composition_receipt_matched"], receipt)
            event = next(e for e in observations["events"] if e.get("captureRequestID") == int(request[1])
                         and e.get("commandBufferToken") == capture[1])
            self.assertEqual(event["truncatedRows"], 0)
            rows, provider, consumer = event["rows"], requested["source"], requested["consumer"]
            reads = [r for r in rows if r["kind"] == "material" and r.get("layerID") == consumer
                and r.get("effectIndex") == 0 and r.get("slot") == requested["slot"] and r.get("outcome") == "draw-encoded"]
            self.assertEqual(len(reads), 1, reads)
            tail = [r for r in rows if r["kind"] == "tail-consume" and r.get("layerID") == consumer
                    and r.get("outcome") == "terminal-consumed"]
            self.assertEqual(len(tail), 1, tail)
            graph = [r for r in rows if r["kind"] == "graph-transaction" and r.get("layerID") == provider]
            self.assertEqual(len(graph), int(requested["sourceHasGraph"]))
            if requested["sourceHasGraph"]:
                materials = [r for r in rows if r["kind"] == "material" and r.get("layerID") == provider
                             and r.get("outcome") == "draw-encoded"]
                expected = [(requested["sourceColorEffectIndex"], 0)]
                if requested["sourceHasAssetPass"] and not requested["sourceMissingAsset"]:
                    expected = [(0,0), (0,1), (1,0)]
                self.assertEqual([(r["effectIndex"], r["slot"]) for r in materials], expected)
                publication = [r for r in rows if r["kind"] == "tail-consume" and r.get("layerID") == provider]
                self.assertEqual(len(publication), 1, publication)
                self.assertEqual(publication[0]["access"], "named-publication-only")
                self.assertLess(rows.index(materials[-1]), rows.index(publication[0]))
                self.assertLess(rows.index(publication[0]), rows.index(reads[0]))
                if requested["sourceMissingAsset"]:
                    self.assertTrue(any(r["kind"] == "copy" and r.get("layerID") == provider
                                        and r.get("effectIndex") == 0 for r in rows))
            receipts.append({"capture": name, "frame": event["frameIndex"], "request": event["captureRequestID"],
                "surface": event["surfaceIdentity"], "CB": event["commandBufferToken"],
                "read": reads[0], "tail": tail[0], "providerGraph": graph})
        (work / "named-text-chain.json").write_bytes(encoded(receipts))

    def run_parent_case(self, case):
        requested = protocol(case)
        word = "retitled_source" if case % 3 == 1 else "own_parent"
        with patch.object(app_runner, "fixture_entries", fixture_entries), patch.object(
                app_runner, "measure_capture", lambda path: measure_capture(path, requested)):
            result = app_runner.SceneReflectionHistoryIntegrationTests.run_case(self, case, capture=True,
                material_input_path=f"materials/{word}/parent.json")
        work = self.evidence_root / f"Ref{case}-capture-on"
        identity = json.loads((work / "identity.json").read_text())
        self.assertEqual(app_runner.sha256(work / "content/scene.pkg"), identity["package"])
        self.assertEqual(app_runner.sha256(work / "content/project.json"), identity["project"])
        (work / "oracle.json").write_bytes(encoded(requested))
        for name in ("scene-ready-window.png", "scene-after-window.png"):
            for region, spec in requested["ROIs"].items():
                actual = result["pixels"][name][region]
                self.assertGreater(actual["count"], 0)
                for value, expected in zip(actual["mean"], spec["RGB"], strict=True):
                    self.assertAlmostEqual(value, expected, delta=TOLERANCE, msg=str((name, region, actual, spec)))
        log = (work / "app.log").read_text()
        self.assert_capture_chain(work, log, requested)

    def assert_capture_chain(self, work, log, requested):
        ids, slots, missing = requested["ids"], requested["slots"], requested["missingParentTexture"]
        observations = structured_runtime_observations(log, "MWX SCENE COMPOSITION OBSERVATION: ")
        self.assertEqual(observations["parse_errors"], 0)
        receipts = []
        for png in sorted((work / "evidence").glob("*-window.png")):
            reason = "ready" if "ready" in png.name else "after"
            capture = re.search(rf"phase=snapshot reason={reason} request=(\d+) source=metal path={re.escape(str(png))}", log)
            self.assertIsNotNone(capture)
            encoded_frame = re.search(rf"phase=snapshot-encoded request={capture[1]} commandBufferToken=(\d+) "
                r"textureToken=(\d+) width=(\d+) height=(\d+)", log)
            self.assertIsNotNone(encoded_frame)
            matched = terminal_composition_snapshot({"status": "captured", "request_id": int(capture[1]),
                "command_buffer_token": encoded_frame[1], "texture_token": encoded_frame[2],
                "source_width": int(encoded_frame[3]), "source_height": int(encoded_frame[4])}, observations)
            self.assertTrue(matched["composition_receipt_matched"], matched)
            event = next(e for e in observations["events"] if e.get("captureRequestID") == int(capture[1])
                and e.get("commandBufferToken") == encoded_frame[1])
            self.assertEqual(event["truncatedRows"], 0)
            self.assertEqual(event["gpuStatus"], "completed")
            rows = event["rows"]
            inputs = []
            for name in ("child", "external", "leafReader"):
                identifier = ids[name]
                material = [r for r in rows if r["kind"] == "material" and r.get("layerID") == identifier
                            and "effectIndex" in r and r.get("outcome") == "draw-encoded"]
                replay = [r for r in rows if r["kind"] == "terminal-material-replay"
                          and r.get("layerID") == identifier and r.get("outcome") == "draw-encoded"]
                graph = [r for r in rows if r["kind"] == "graph-transaction" and r.get("layerID") == identifier]
                tail = [r for r in rows if r["kind"] == "tail-consume" and r.get("layerID") == identifier]
                self.assertEqual(len(graph), 1, (name, graph))
                self.assertEqual(len(tail), 1, (name, tail))
                failed = missing and name != "leafReader"
                read_slots = requested.get("externalSlots", [slots[name]]) if name == "external" else [slots[name]]
                self.assertEqual([(r["effectIndex"], r["slot"]) for r in material],
                    [(1, 0)] if failed else [(0, slot) for slot in read_slots] + ([] if name == "leafReader" else [(1, 0)]))
                copies = [r for r in rows if r["kind"] == "copy" and r.get("layerID") == identifier
                          and r.get("effectIndex") == 0 and r.get("outcome") == "encoded"]
                self.assertEqual(len(copies), int(failed), (name, copies))
                if failed:
                    self.assertEqual(copies[0]["target"]["textureToken"], material[0]["source"]["textureToken"])
                    self.assertLess(rows.index(copies[0]), rows.index(material[0]))
                else:
                    for binding in material[:len(read_slots)]:
                        first = binding["source"]
                        self.assertEqual(first["provenance"], "authored.material")
                        self.assertEqual(first["generation"], first["contentGeneration"])
                        inputs.append({"reader": name, "slot": binding["slot"], "texture": first["textureToken"],
                                       "generation": first["generation"], "contentGeneration": first["contentGeneration"]})
                        if name != "leafReader":
                            self.assertEqual(binding["target"]["textureToken"], material[-1]["source"]["textureToken"])
                composite = [r for r in rows if r["kind"] in ("ordinary", "group")
                             and r.get("layerID") == identifier and r.get("outcome") == "draw-encoded"]
                if replay:
                    self.assertEqual(len(replay), 1)
                    self.assertEqual(composite, [])
                    self.assertEqual((replay[0]["effectIndex"], replay[0]["slot"]),
                                     (material[-1]["effectIndex"], material[-1]["slot"]))
                    self.assertEqual(replay[0]["source"]["textureToken"], material[-1]["source"]["textureToken"])
                    self.assertEqual(replay[0]["target"]["textureToken"], encoded_frame[2])
                    self.assertEqual((replay[0]["target"]["width"], replay[0]["target"]["height"]),
                                     (int(encoded_frame[3]), int(encoded_frame[4])))
                    self.assertEqual(tail[0]["access"], "terminal-material-replay")
                else:
                    self.assertEqual(len(composite), 1)
                    self.assertEqual(material[-1]["target"]["textureToken"], composite[0]["source"]["textureToken"])
                    self.assertEqual(composite[0]["target"]["textureToken"], encoded_frame[2])
            if not missing:
                parent_inputs = [r for r in inputs if r["reader"] in ("child", "external")]
                self.assertEqual(len({(r["texture"], r["generation"]) for r in parent_inputs}), 1, parent_inputs)
            parent_graph = [r for r in rows if r["kind"] == "graph-transaction" and r.get("layerID") == ids["parent"]]
            parent_draws = [r for r in rows if r.get("layerID") == ids["parent"]
                            and r["kind"] in ("ordinary", "group", "terminal-material-replay")
                            and r.get("outcome") == "draw-encoded"]
            self.assertEqual(len(parent_draws), 0 if missing else 1, parent_draws)
            if requested.get("parentGraph"):
                parent_material = [r for r in rows if r["kind"] == "material" and r.get("layerID") == ids["parent"]
                                   and r.get("outcome") == "draw-encoded"]
                self.assertEqual([(r.get("effectIndex"), r.get("slot")) for r in parent_material],
                                 [] if missing else [(0, 0)])
                if not missing:
                    self.assertEqual(len(parent_graph), 1)
                    main = parent_draws[0]
                    parent_tail = [r for r in rows if r["kind"] == "tail-consume"
                                   and r.get("layerID") == ids["parent"] and r.get("outcome") == "terminal-consumed"]
                    self.assertEqual(len(parent_tail), 1)
                    self.assertEqual(parent_tail[0]["access"], "terminal-material-replay"
                        if main["kind"] == "terminal-material-replay" else "output-texture-composite")
                    self.assertLess(rows.index(parent_material[0]), rows.index(main))
                    self.assertLess(rows.index(main), rows.index(parent_tail[0]))
                    source = parent_material[0]["source"] if main["kind"] == "terminal-material-replay" else parent_material[0]["target"]
                    self.assertEqual(main["source"]["textureToken"], source["textureToken"])
                    self.assertEqual(main["target"]["textureToken"], encoded_frame[2])
                    for reader in ("child", "external"):
                        first = next(r for r in rows if r["kind"] == "material" and r.get("layerID") == ids[reader]
                                     and r.get("effectIndex") == 0)
                        self.assertLess(rows.index(main), rows.index(first))
            else:
                self.assertEqual(parent_graph, [])
            for name in ("healthy", "peer"):
                self.assertTrue(any(r.get("layerID") == ids[name] and r.get("outcome") == "draw-encoded" for r in rows), name)
            receipts.append({"capture": png.name, "frame": event["frameIndex"], "request": event["captureRequestID"],
                "commandBuffer": event["commandBufferToken"], "Surface": event["surfaceIdentity"],
                "inputBindings": inputs,
                "parentMainSourceTokens": [r.get("source", {}).get("textureToken") for r in parent_draws],
                "scope": requested["ceilings"]})
        for name in ("child", "external"):
            binding = f"phase=named-target-binding layer={ids[name]} status=succeeded"
            if missing:
                self.assertNotIn(binding, log)
            else:
                self.assertIn(binding, log)
        if not missing:
            phase = "visible-graph-output-publication" if requested.get("parentGraph") else "named-target-capture"
            self.assertIn(f"phase={phase} layer={ids['parent']} status=succeeded", log)
        if requested.get("parentGraph"):
            self.assertNotIn(f"phase=named-target-capture layer={ids['parent']} status=succeeded", log)
        (work / "named-parent-chain.json").write_bytes(encoded(receipts))


if __name__ == "__main__":
    unittest.main()
