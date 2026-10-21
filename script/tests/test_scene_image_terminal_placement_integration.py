#!/usr/bin/env python3
"""Owned image placement through the existing frozen real-App runner.

CPU-only: python3.12 -B -m script.tests.test_scene_image_terminal_placement_integration --prepare-only
App execution is explicit through MWX_SCENE_INTEGRATION_APP. The legacy mode
is a preregistered countermodel, not a relaxed candidate assertion. No original
Workshop media, uniforms injected by a harness, or author shader is used.
"""
from __future__ import annotations

import hashlib
import json
import math
import os
from pathlib import Path
import re
import sys
import tempfile
import unittest
from unittest.mock import patch

from script.tests import test_scene_reflection_history_integration as runner
from script.tests.test_scene_native_world_composition import encoded, png
from script.tests.test_scene_pkg_cache_extractor import make_package
from script.web_benchmark_capture import png_rgb_pixels

REPO = Path(__file__).resolve().parents[2]
DEFAULT_ROOT = REPO / ".artifacts/pointer-domain-followup-20261021/synthetic"
CANVAS = (320, 180)
TEXTURE_SIZE = (192, 128)
LAYER_SIZE = (192, 128)
AUTHORED_ORIGIN = (164, 72)
LAYER_SCALE = (1.1, .8)
EXPECTED_OUTPUT = (3024, 1964)
POINTER = (.36, .14)
MARK_RADIUS = .035
MARK_RGB = (255, 38.25, 204)
TOLERANCE = 4
TARGET_LAYER = 20
CASES = ("canonical", "renamed-equivalent", "fragment-raster")
SOURCE_COLORS = ((40, 80, 120), (80, 40, 160), (120, 160, 40), (160, 120, 80))

VERTEX = """attribute vec3 a_Position;
attribute vec2 a_TexCoord;
uniform mat4 g_ModelViewProjectionMatrix;
varying vec2 v_UV;
void main() {
    gl_Position = g_ModelViewProjectionMatrix * vec4(a_Position, 1.0);
    v_UV = a_TexCoord;
}
"""
PREFIX = """uniform sampler2D g_Texture0;
uniform vec4 g_Texture0Resolution;
varying vec2 v_UV;
void main() {
    vec2 shifted = v_UV + vec2(3.0, -2.0) / g_Texture0Resolution.xy;
    vec4 source = texSample2D(g_Texture0, shifted);
    vec3 remapped = source.bgr * vec3(0.5, 0.75, 0.25) + vec3(0.125, 0.0625, 0.0);
    gl_FragColor = vec4(remapped, source.a);
}
"""
POINTER_FRAGMENT = """uniform sampler2D g_Texture0;
uniform vec4 g_Texture0Resolution;
uniform vec2 g_PointerPosition;
uniform mat4 g_ModelViewProjectionMatrixInverse;
varying vec2 v_UV;
void main() {
    vec4 source = texSample2D(g_Texture0, v_UV);
    vec2 pointerNDC = g_PointerPosition * vec2(2.0, -2.0) + vec2(-1.0, 1.0);
    vec4 local = g_ModelViewProjectionMatrixInverse * vec4(pointerNDC, 0.0, 1.0);
    vec2 pointerUV = vec2(0.5, 0.5) + (local.xy / local.w) / g_Texture0Resolution.xy * vec2(1.0, -1.0);
    float marker = 1.0 - step(0.035, length(v_UV - pointerUV));
    vec3 result = mix(source.rgb, vec3(1.0, 0.15, 0.8), marker);
    gl_FragColor = vec4(result, source.a);
}
"""


def shader_sources(case: str) -> tuple[bytes, bytes, bytes]:
    vertex, prefix, fragment = VERTEX, PREFIX, POINTER_FRAGMENT
    if case == "renamed-equivalent":
        prefix = prefix.replace(
            "source.bgr * vec3(0.5, 0.75, 0.25)",
            "vec3(source.b * 0.5, source.g * 0.75, source.r * 0.25)")
        fragment = fragment.replace("v_UV - pointerUV", "pointerUV - v_UV")
        for before, after in [("v_UV", "v_Sample"), ("source", "priorColor"),
                              ("local", "cardPoint"), ("pointerUV", "hitUV"),
                              ("marker", "insideMark"), ("result", "finalColor")]:
            vertex = re.sub(rf"\b{before}\b", after, vertex)
            prefix = re.sub(rf"\b{before}\b", after, prefix)
            fragment = re.sub(rf"\b{before}\b", after, fragment)
    elif case == "fragment-raster":
        fragment = fragment.replace(
            "vec3 result = mix(source.rgb,",
            "float rasterFactor = 0.8 + 0.2 * step(g_Texture0Resolution.x * 0.5, gl_FragCoord.x);\n"
            "    vec3 result = mix(source.rgb * rasterFactor,")
    elif case != "canonical":
        raise ValueError(case)
    return tuple(s.encode() for s in (vertex, prefix, fragment))


def material(shader: str, texture) -> bytes:
    return encoded({"passes": [{"shader": shader, "textures": [texture],
        "blending": "normal", "depthtest": "disabled", "depthwrite": "disabled", "cullmode": "nocull"}]})


def fixture_entries(case: str) -> dict[str, bytes]:
    renamed = case == "renamed-equivalent"
    prefix_name, pointer_name = (("copper_remap", "card_hotspot") if renamed
                                 else ("owned_prefix_color", "owned_pointer_mark"))
    model, image = (("models/renamed-card.json", "materials/renamed-pixels.png") if renamed
                    else ("models/ordinary-card.json", "materials/owned-pixels.png"))
    base, effects = (("materials/renamed-base.json", "effects/renamed") if renamed
                     else ("materials/owned-base.json", "effects/owned"))
    vertex, prefix, fragment = shader_sources(case)
    scene = {"version": 3, "general": {
        "orthogonalprojection": {"width": CANVAS[0], "height": CANVAS[1]},
        "clearcolor": "0 0 0", "clearenabled": True, "hdr": False, "bloom": False,
        "ambientcolor": "0 0 0", "skylightcolor": "0 0 0",
        "cameraparallax": False, "camerashake": False}, "objects": [{
        "id": TARGET_LAYER, "name": "Owned ordinary image placement",
        "image": model, "origin": f"{AUTHORED_ORIGIN[0]} {AUTHORED_ORIGIN[1]} 0",
        "size": f"{LAYER_SIZE[0]} {LAYER_SIZE[1]}",
        "scale": f"{LAYER_SCALE[0]} {LAYER_SCALE[1]} 1", "visible": True,
        "effects": [{"id": 200 + index, "file": f"{effects}/{name}/effect.json", "visible": True}
                    for index, name in enumerate((prefix_name, pointer_name))]}]}
    base_material = {"passes": [{"shader": "genericimage2", "textures": [image],
        "combos": {"LIGHTING": 0, "NORMALMAP": 0, "REFLECTION": 0},
        "blending": "translucent", "depthtest": "disabled", "depthwrite": "disabled", "cullmode": "nocull"}]}
    entries = {"scene.json": encoded(scene), model: encoded({"material": base}),
        base: encoded(base_material), image: png(*TEXTURE_SIZE,
            lambda x, y: SOURCE_COLORS[(2 if y >= TEXTURE_SIZE[1] // 2 else 0)
                                       + (1 if x >= TEXTURE_SIZE[0] // 2 else 0)])}
    for name, source in ((prefix_name, prefix), (pointer_name, fragment)):
        path = f"materials/{name}.json"
        entries.update({f"{effects}/{name}/effect.json": encoded({"passes": [{"material": path}]}),
                        path: material(name, None), f"shaders/{name}.vert": vertex,
                        f"shaders/{name}.frag": source})
    return entries


def geometry_oracle(width=EXPECTED_OUTPUT[0], height=EXPECTED_OUTPUT[1]) -> dict:
    # Scalar double arithmetic from authored dimensions. No product matrices,
    # shader reflection, measured marker coordinates, or image fitting.
    scale = max(width / CANVAS[0], height / CANVAS[1])
    center_world = (AUTHORED_ORIGIN[0], CANVAS[1] - AUTHORED_ORIGIN[1])
    card = tuple(a * b for a, b in zip(LAYER_SIZE, LAYER_SCALE))
    target = ((1 + POINTER[0]) * width / 2, (1 - POINTER[1]) * height / 2)
    target_world = (CANVAS[0] / 2 + POINTER[0] * width / (2 * scale),
                    CANVAS[1] / 2 - POINTER[1] * height / (2 * scale))
    target_uv = (.5 + (target_world[0] - center_world[0]) / card[0],
                 .5 + (target_world[1] - center_world[1]) / card[1])
    legacy_uv = ((1 + POINTER[0]) / 2, (1 - POINTER[1]) / 2)
    def uv_pixel(uv):
        world = (center_world[0] + (uv[0] - .5) * card[0],
                 center_world[1] + (uv[1] - .5) * card[1])
        return [width / 2 + (world[0] - CANVAS[0] / 2) * scale,
                height / 2 + (world[1] - CANVAS[1] / 2) * scale]
    extent = [max(LAYER_SIZE[i], math.ceil(card[i] / 128) * 128) for i in range(2)]
    return {"output": [width, height], "canvas": CANVAS, "coverScale": scale,
        "physicalTexture": TEXTURE_SIZE, "mappedTexture": TEXTURE_SIZE,
        "authoredEffectExtent": LAYER_SIZE, "onCanvasExtent": card,
        "predictedGraphExtent": extent, "quantization": "max(sourceExtent,ceil(onCanvas/128)*128)",
        "targetCenter": target, "legacyCenter": uv_pixel(legacy_uv),
        "targetUV": target_uv, "legacyUV": legacy_uv,
        "markerRadiiPixels": [MARK_RADIUS * value * scale for value in card],
        "probes": {"target": {"center": target, "uv": target_uv},
                   "legacy": {"center": uv_pixel(legacy_uv), "uv": legacy_uv},
                   "prefixLeft": {"center": uv_pixel((.2, .7)), "uv": [.2, .7]},
                   "prefixRight": {"center": uv_pixel((.8, .76)), "uv": [.8, .76]}},
        "pixelTolerance": TOLERANCE, "candidateCentroidTolerancePixels": 2,
        "legacyCentroidTolerancePixels": max(card[i] * scale / extent[i] for i in range(2)),
        "sourceAlpha": 1, "alphaBoundary": "Shaders preserve sampled alpha; this carrier uses opaque authored texels only."}


def prefix_rgb(uv, case="canonical"):
    extent = geometry_oracle()["predictedGraphExtent"]
    sampled = (uv[0] + 3 / extent[0], uv[1] - 2 / extent[1])
    rgb = SOURCE_COLORS[(2 if sampled[1] >= .5 else 0) + (1 if sampled[0] >= .5 else 0)]
    result = [rgb[2] * .5 + 255 * .125, rgb[1] * .75 + 255 * .0625, rgb[0] * .25]
    if case == "fragment-raster" and uv[0] < .5:
        result = [value * .8 for value in result]
    return result


def measure_capture(path: Path, case="canonical") -> dict:
    decoded = png_rgb_pixels(path)
    if decoded is None:
        raise AssertionError(f"Undecodable original PNG: {path}")
    width, height, rows = decoded
    if (width, height) != EXPECTED_OUTPUT:
        raise AssertionError(f"Frozen output extent changed: {(width,height)} != {EXPECTED_OUTPUT}")
    oracle = geometry_oracle(width, height)
    result = {"size": [width, height], "probes": {}, "markerMasks": {}}
    for name, probe in oracle["probes"].items():
        cx, cy = (round(v) for v in probe["center"])
        pixels = [rows[y][x * 3:x * 3 + 3] for y in range(cy - 2, cy + 3)
                  for x in range(cx - 2, cx + 3)]
        result["probes"][name] = {"bounds": [cx-2, cy-2, cx+3, cy+3], "count": len(pixels),
            "mean": [sum(p[c] for p in pixels) / len(pixels) for c in range(3)]}
    # Two disjoint geometry-predicted search windows. This does not choose an
    # oracle by searching for the observed marker; both locations are locked.
    rx, ry = oracle["markerRadiiPixels"]
    for name in ("target", "legacy"):
        cx, cy = oracle["probes"][name]["center"]
        x0, x1 = max(0, int(cx-rx-12)), min(width, math.ceil(cx+rx+12))
        y0, y1 = max(0, int(cy-ry-12)), min(height, math.ceil(cy+ry+12))
        count, sx, sy = 0, 0., 0.
        for y in range(y0, y1):
            for x in range(x0, x1):
                pixel = rows[y][x*3:x*3+3]
                if all(abs(pixel[c] - MARK_RGB[c]) <= TOLERANCE for c in range(3)):
                    count += 1; sx += x + .5; sy += y + .5
        result["markerMasks"][name] = {"count": count,
            "centroid": [sx/count, sy/count] if count else None,
            "searchBounds": [x0,y0,x1,y1]}
    return result


def prepare(root=DEFAULT_ROOT):
    root = Path(root);root.mkdir(parents=True, exist_ok=True)
    protocol = {"oracle": geometry_oracle(), "cases": CASES,
        "expectedAppRuns": {"legacy": ["canonical"], "candidate": list(CASES)},
        "chain": "authored ordinary image -> real preflight source capture -> two material stages -> actual unique compositor -> original PNG/normal stop",
        "counterexample": "fragment gl_FragCoord must retain ordinary graph placement despite targetPixels vertex ABI",
        "notProven": ["nonopaque alpha", "official parity", "other display extent", "performance"],
        "sourceSHA256": runner.sha256(Path(__file__)), "runnerSHA256": runner.sha256(Path(runner.__file__))}
    for case in CASES:
        work = root/"inputs"/case;work.mkdir(parents=True, exist_ok=True)
        entries=fixture_entries(case)
        # Earlier preparation revisions are preserved separately, never left as
        # undeclared resources beside the exact current loose/package input.
        for existing in work.rglob('*'):
            if existing.is_file() and existing.relative_to(work).as_posix() not in {*entries,'project.json','scene.pkg'}:
                old=root/'superseded-prequalification-inputs'/case/existing.relative_to(work)
                old.parent.mkdir(parents=True,exist_ok=True);old.write_bytes(existing.read_bytes());existing.unlink()
        for name,data in entries.items():
            p=work/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
        (work/"project.json").write_bytes(encoded({"type":"scene","file":"scene.json"}))
        (work/"scene.pkg").write_bytes(make_package(list(entries.items())))
        protocol.setdefault("inputHashes",{})[case]={n:hashlib.sha256(b).hexdigest() for n,b in entries.items()}
    (root/"preregistration.json").write_bytes(encoded(protocol))
    return protocol


class ImageTerminalPlacementCPUChecks(unittest.TestCase):
    def test_independent_cover_countermodel_and_preserved_prefix(self):
        o=geometry_oracle()
        self.assertEqual(o["predictedGraphExtent"],[256,128])
        self.assertNotEqual(tuple(o["output"]),TEXTURE_SIZE)
        self.assertGreater(abs(EXPECTED_OUTPUT[0]/EXPECTED_OUTPUT[1]-CANVAS[0]/CANVAS[1]),.1)
        self.assertGreater(math.dist(o["targetCenter"],o["legacyCenter"]),200)
        self.assertTrue(all(MARK_RADIUS < v < 1-MARK_RADIUS for v in o["targetUV"]))
        self.assertGreater(abs(o["targetCenter"][1]-o["legacyCenter"][1]),2*o["markerRadiiPixels"][1]+24)
        for case in CASES:
            entries=fixture_entries(case);scene=json.loads(entries['scene.json'])
            self.assertEqual(len(scene['objects']),1)
            self.assertIn('image',scene['objects'][0]);self.assertNotIn('model',scene['objects'][0])
            self.assertEqual(len(scene['objects'][0]['effects']),2)
            for effect in scene['objects'][0]['effects']:
                self.assertTrue(effect['file'].endswith('/effect.json'))
                definition=json.loads(entries[effect['file']])
                self.assertIn(definition['passes'][0]['material'],entries)
            self.assertNotIn('_rt_',b''.join(entries.values()).decode(errors='ignore'))
            self.assertNotEqual(prefix_rgb((.2,.7),case),list(SOURCE_COLORS[2]))
        self.assertNotIn(b'gl_FragCoord',shader_sources('canonical')[2])
        self.assertIn(b'gl_FragCoord',shader_sources('fragment-raster')[2])
        for case in CASES:
            vertex,prefix,fragment=shader_sources(case)
            self.assertNotIn(b'g_RenderSize',prefix+fragment)
            self.assertIn(b'g_Texture0Resolution',prefix)
            self.assertIn(b'g_Texture0Resolution',fragment)
            self.assertIn(b'g_PointerPosition * vec2(2.0, -2.0) + vec2(-1.0, 1.0)',fragment)
        self.assertNotEqual(set(fixture_entries('canonical')),set(fixture_entries('renamed-equivalent')))


class SceneImageTerminalPlacementIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        app=os.environ.get('MWX_SCENE_INTEGRATION_APP')
        if not app:raise unittest.SkipTest('requires explicitly frozen Debug App executable')
        cls.app=Path(app).resolve(strict=True)
        cls.expectation=os.environ.get('MWX_SCENE_IMAGE_PLACEMENT_EXPECTATION','placed')
        if cls.expectation not in ('legacy','placed'):raise ValueError(cls.expectation)
        binaries=[cls.app,cls.app.with_name('MyWallpaperX.debug.dylib'),cls.app.parent.parent/'Resources/default.metallib']
        cls.app_identity={str(p):runner.sha256(p) for p in binaries if p.is_file()}
        cls.source_identity={str(p):runner.sha256(p) for p in [Path(__file__),Path(runner.__file__),REPO/'script/tests/test_scene_pkg_cache_extractor.py',REPO/'script/web_benchmark_capture.py']}
        destination=Path(os.environ.get('MWX_SCENE_INTEGRATION_EVIDENCE',str(DEFAULT_ROOT/cls.expectation)))
        destination.mkdir(parents=True,exist_ok=True)
        cls.evidence_root=Path(tempfile.mkdtemp(prefix='image-terminal-placement-',dir=destination))
        (cls.evidence_root/'protocol.json').write_bytes(encoded({'oracle':geometry_oracle(),'expectation':cls.expectation,'app':cls.app_identity,'sources':cls.source_identity}))
        print(f'Image placement real-App evidence: {cls.evidence_root}',flush=True)

    def run_placement_case(self,case):
        label=CASES.index(case)
        with patch.object(runner,'fixture_entries',lambda _label:fixture_entries(case)),patch.object(runner,'measure_capture',lambda path:measure_capture(path,case)):
            result=runner.SceneReflectionHistoryIntegrationTests.run_case(self,label,capture=True,
                extra_arguments=('--mwx-debug-scene-hover-pointer-json',json.dumps(dict(zip(('x','y'),POINTER))), '--mwx-debug-scene-hover-pointer-stationary-entry'),
                initial_snapshot='scene-before-window.png',
                material_input_path='materials/renamed-base.json' if case=='renamed-equivalent' else 'materials/owned-base.json')
        self.verify_placement_case(case,result,self.evidence_root/f'Ref{label}-capture-on')

    def verify_placement_case(self,case,result,work):
        """Also supports offline validation of preserved original run receipts."""
        log=(work/'app.log').read_text()
        self.assertIn('scene-hover-window.png',result['pixels'])
        self.assertRegex(log,r'phase=pointer-state state=hold x=0\.360000 y=0\.140000')
        graph=[]
        for line in log.splitlines():
            if 'axis=graph-execution runtime=' not in line:continue
            fields=dict(re.findall(r'(\w+)=([^ ]+)',line))
            if fields.get('layer')==str(TARGET_LAYER) and fields.get('outcome')=='succeeded':
                graph.append(fields)
        self.assertGreaterEqual(len(graph),2,log[-6000:])
        by_frame={}
        for fields in graph:
            self.assertEqual((int(fields['inputWidth']),int(fields['inputHeight'])),tuple(geometry_oracle()['predictedGraphExtent']))
            self.assertEqual(int(fields['materialNodes']),1)
            self.assertEqual(fields.get('rejectedNodes'),'0')
            self.assertEqual(fields.get('gpuCompletion'),'completed')
            effect=int(fields['effect'])
            self.assertIn(effect,(0,1))
            self.assertEqual(fields.get('compositorConsumed'),'true' if effect==1 else 'false')
            by_frame.setdefault(int(fields['frame']),{})[effect]=fields
        self.assertGreaterEqual(len(by_frame),2,by_frame)
        for stages in by_frame.values():
            self.assertEqual(set(stages),{0,1},stages)
        m=result['pixels']['scene-hover-window.png'];o=geometry_oracle()
        placement=self.expectation=='placed' and case!='fragment-raster'
        expected_marker='target' if placement else 'legacy';other='legacy' if placement else 'target'
        for name,probe in o['probes'].items():
            expected=MARK_RGB if name==expected_marker else prefix_rgb(probe['uv'],case)
            for actual,golden in zip(m['probes'][name]['mean'],expected):
                self.assertAlmostEqual(actual,golden,delta=TOLERANCE,msg=str((case,name,m['probes'][name],expected)))
        component=m['markerMasks'][expected_marker]
        self.assertGreater(component['count'],1000,component)
        self.assertLessEqual(m['markerMasks'][other]['count'],10,m)
        error=math.dist(component['centroid'],o['probes'][expected_marker]['center'])
        limit=2 if placement else o['legacyCentroidTolerancePixels']
        self.assertLessEqual(error,limit,(component,o,error))
        checks={'case':case,'expectation':self.expectation,'oracle':o,'observedGraphExtent':[int(graph[0]['inputWidth']),int(graph[0]['inputHeight'])],
            'completedGraphFrames':sorted({int(v['frame']) for v in graph}),'markerCentroidErrorPixels':error,
            'measurements':m,'realImageInput':True,'productChain':'real App preflight/graph/compositor',
            'terminalReceiptBoundary':'Pixel countermodel and actual graph completion qualify behavior; exact prepared-ticket once-consumption is covered by existing owner tests, not inferred from PNG.',
            'inputAfter':{n:runner.sha256(work/'content'/n) for n in ('project.json','scene.pkg')}}
        identity=json.loads((work/'identity.json').read_text())
        self.assertEqual(checks['inputAfter']['project.json'],identity['project'])
        self.assertEqual(checks['inputAfter']['scene.pkg'],identity['package'])
        (work/'placement-checks.json').write_bytes(encoded(checks))

    def test_canonical(self):self.run_placement_case('canonical')
    def test_renamed_equivalent(self):self.run_placement_case('renamed-equivalent')
    def test_fragment_raster_stays_ordinary(self):self.run_placement_case('fragment-raster')


if __name__=='__main__':
    if '--prepare-only' in sys.argv:
        prepare();unittest.main(argv=[sys.argv[0]],defaultTest='ImageTerminalPlacementCPUChecks')
    else:unittest.main()
