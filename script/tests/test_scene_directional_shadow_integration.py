#!/usr/bin/env python3
"""Self-authored MDL directional-shadow App evidence; no corpus assets.

Set MWX_DIRECTIONAL_SHADOW_APP to an immutable staged App/executable. Evidence
is isolated under MWX_DIRECTIONAL_SHADOW_EVIDENCE or a new temporary directory.
The old App pair is intentionally red: cast-on must darken the geometric shadow
ROI, while the unoccluded receiver stays unchanged. Existing evidence is never
reused or overwritten.
"""
import hashlib
import json
import os
import re
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest
import zlib

from script.tests.test_scene_pkg_cache_extractor import make_package
from script.tests.test_scene_static_model_reader import build_model

REPO = Path(__file__).resolve().parents[2]


def png(rgba):
    def chunk(kind, value):
        return struct.pack('>I', len(value)) + kind + value + struct.pack('>I', zlib.crc32(kind + value) & 0xffffffff)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 4, 4, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress((b'\0' + bytes(rgba) * 4) * 4)) + chunk(b'IEND', b''))


def quad(x0, x1, y0, y1, z, material):
    vertices = [((x, y, z), (0., 0., 1.), (1., 0., 0., 1.), uv)
                for x, y, uv in [(x0, y0, (0., 0.)), (x1, y0, (1., 0.)),
                                 (x1, y1, (1., 1.)), (x0, y1, (0., 1.))]]
    # Clockwise authored XY becomes the existing orthographic camera's front.
    return build_model(vertices=vertices, indices=(0, 2, 1, 0, 3, 2),
                       bounds=(x0, y0, z, x1, y1, z), material=material.encode())


def fixture_entries(*, cast=True, light_cast=True, caster=True, caster_lit=True,
                    layer_alpha=1, texture_alpha=255, tint_mask=False,
                    caster_x=70, caster_z=20, angle=.78539816339,
                    caster_first=False, moving=False, bloom=False, healthy_effect=False, singular_caster=False, extra_valid_caster=False, perspective=False, parent_offset=0, moving_light=False, color_blend=0, healthy_visible=True):
    receiver = {'id': 1, 'model': 'models/receiver.mdl', 'origin': '0 96 0',
                'perspective': False, 'castshadow': False}
    occluder = {'id': 2, 'model': 'models/caster.mdl', 'origin': '0 96 0',
                'perspective': False, 'castshadow': cast}
    if cast == 'omitted':
        occluder.pop('castshadow')
    if singular_caster:
        occluder.update(scale='1 1 0', origin='0 96 20')
    if perspective:
        receiver['perspective'] = True; occluder['perspective'] = True
    if parent_offset:
        occluder['parent'] = 6
    if layer_alpha != 1:
        occluder['alpha'] = layer_alpha
    if moving:
        occluder['origin'] = {'value': '0 96 0', 'script':
            'export function update(v) { return new Vec3(engine.runtime >= 2.5 && engine.runtime < 5.5 ? 35 : 0, 96, 0); }'}
    lamp = {'id': 3, 'light': 'ldirectional', 'angles': f'0 {angle} 0',
            'color': '1 1 1', 'intensity': .6, 'castshadow': light_cast}
    if moving_light:
        lamp['angles'] = {'value': '0 .78539816339 0', 'script': 'export function update(v) { return new Vec3(0, engine.runtime >= 2.5 && engine.runtime < 5.5 ? -45 : 45, 0); }'}
    objects = ([occluder, receiver] if caster_first else [receiver, occluder]) if caster else [receiver]
    scene = {'version': 3, 'general': {'orthogonalprojection': {'width': 160, 'height': 96},
             'clearcolor': '0 0 0', 'ambientcolor': '0.05 0.05 0.05', 'skylightcolor': '0 0 0'},
             'objects': objects + [lamp]}
    if parent_offset:
        scene['objects'].insert(0, {'id': 6, 'name': 'transform-parent', 'origin': f'{parent_offset} 0 0'})
    if perspective:
        scene['general']['perspectiveoverridefov'] = 90
    if bloom:
        scene['general'].update(bloom=True, bloomstrength=.3, bloomthreshold=.8)
    entries = {'scene.json': json.dumps(scene).encode(),
               'models/receiver.mdl': quad(10, 150, 10, 86, 0, 'materials/receiver.json'),
               'models/caster.mdl': quad(caster_x, caster_x + 20, 38, 58, 0 if singular_caster else caster_z, 'materials/caster.json'),
               'materials/white.png': png([180, 180, 180, 255]),
               'materials/green.png': png([0, 200, 0, texture_alpha])}
    for kind, texture in [('receiver', 'white'), ('caster', 'green')]:
        combos = {'LIGHTING': int(kind == 'receiver' or caster_lit)}
        if kind == 'caster' and tint_mask:
            combos['TINTMASKALPHA'] = 1
        entries[f'materials/{kind}.json'] = json.dumps({'passes': [{
            'shader': 'genericimage', 'textures': [f'materials/{texture}.png'],
            'combos': combos, 'blending': 'translucent' if kind == 'caster' and texture_alpha < 255 else 'normal',
            'cullmode': 'nocull', 'depthtest': 'enabled', 'depthwrite': 'enabled'}]}).encode()
    if extra_valid_caster:
        scene['objects'].append({'id': 5, 'model': 'models/valid.mdl', 'origin': '0 96 0', 'perspective': False, 'castshadow': True})
        entries['models/valid.mdl'] = quad(30, 50, 38, 58, 20, 'materials/caster.json')
    entries['scene.json'] = json.dumps(scene).encode()
    if healthy_effect:
        scene['objects'].append({'id': 4, 'image': 'models/healthy.json', 'origin': '120 20 0',
            'size': '16 16', 'visible': healthy_visible, 'colorBlendMode': color_blend, 'effects': [{'id': 40, 'file': 'effects/own_dim/effect.json', 'visible': True}]})
        entries.update({
            'models/healthy.json': json.dumps({'material': 'materials/healthy.json'}).encode(),
            'materials/healthy.json': json.dumps({'passes': [{'shader': 'genericimage', 'textures': ['materials/green.png']}]}).encode(),
            'effects/own_dim/effect.json': json.dumps({'passes': [{'material': 'materials/own_dim.json'}]}).encode(),
            'materials/own_dim.json': json.dumps({'passes': [{'shader': 'own_dim', 'textures': [None],
                'blending': 'normal', 'depthtest': 'disabled', 'depthwrite': 'disabled', 'cullmode': 'nocull'}]}).encode(),
            'shaders/own_dim.vert': b'attribute vec3 a_Position;\nvarying vec2 v_TexCoord;\nattribute vec2 a_TexCoord;\nvoid main(){gl_Position=vec4(a_Position,1.0);v_TexCoord=a_TexCoord;}\n',
            'shaders/own_dim.frag': b'uniform sampler2D g_Texture0;\nvarying vec2 v_TexCoord;\nvoid main(){vec4 c=texSample2D(g_Texture0,v_TexCoord);c.rgb*=0.5;gl_FragColor=c;}\n'})
        entries['scene.json'] = json.dumps(scene).encode()
    return scene, entries


class SceneDirectionalShadowIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        configured = os.environ.get('MWX_DIRECTIONAL_SHADOW_APP')
        if not configured:
            raise unittest.SkipTest('requires immutable MWX_DIRECTIONAL_SHADOW_APP')
        app = Path(configured).resolve(strict=True)
        cls.executable = app / 'Contents/MacOS/MyWallpaperX' if app.suffix == '.app' else app
        cls.app = cls.executable.parents[2]
        cls.binaries = [cls.executable, cls.executable.parent / 'MyWallpaperX.debug.dylib',
                        cls.app / 'Contents/Resources/default.metallib']
        cls.identity = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in cls.binaries}
        parent = os.environ.get('MWX_DIRECTIONAL_SHADOW_EVIDENCE')
        if parent:
            Path(parent).mkdir(parents=True, exist_ok=True)
        cls.root = Path(tempfile.mkdtemp(prefix='directional-shadow-app-', dir=parent))
        sources = [Path(__file__), REPO/'script/tests/fixtures/scene_directional_shadow_oracle.py', REPO/'script/tests/test_scene_static_model_reader.py', REPO/'script/tests/test_scene_pkg_cache_extractor.py']
        (cls.root/'test-source-identity.json').write_text(json.dumps({str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}, indent=2))
        cls.runs = {}
        print(f'directional shadow App evidence: {cls.root}', flush=True)

    def run_case(self, name, **options):
        if name in self.runs:
            return self.runs[name]
        from PIL import Image, ImageChops, ImageStat
        work = self.root / name
        (work / 'content').mkdir(parents=True)
        (work / 'home').mkdir()
        scene, entries = fixture_entries(**options)
        (work / 'content/scene.pkg').write_bytes(make_package(list(entries.items())))
        (work / 'content/project.json').write_text(json.dumps({'type': 'scene', 'file': 'scene.json'}))
        (work / 'scene-input.json').write_text(json.dumps(scene, indent=2))
        moving = options.get('moving', False) or options.get('moving_light', False)
        command = [str(self.executable), '--mwx-debug-scene-root', str(work / 'content'),
                   '--mwx-debug-scene-duration', '9' if moving else '6',
                   '--mwx-debug-scene-evidence-dir', str(work / 'evidence')]
        if moving:
            command += ['--mwx-debug-scene-periodic-snapshot-interval', '1.5',
                        '--mwx-debug-scene-after-snapshot-delay', '7.2']
        sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
        (work / 'prerun.json').write_text(json.dumps({'app': self.identity, 'command': command,
            'inputs': {p.name: sha(p) for p in (work / 'content').iterdir()},
            'oracle': 'world ray toward(+X,+Z), caster z20 => receiver x50..70; strict coverage > 0.5 project policy'}, indent=2))
        environment = os.environ.copy()
        environment.update(HOME=str(work / 'home'), CFFIXED_USER_HOME=str(work / 'home'), MWX_SCENE_DEBUG_SURFACE_COUNT='1')
        with (work / 'app.log').open('w') as log:
            result = subprocess.run(command, cwd=REPO, env=environment, stdout=log, stderr=subprocess.STDOUT, timeout=90)
        log = (work / 'app.log').read_text()
        preview = (work / 'evidence/scene-preview.log').read_text()
        pixels = {}
        for path in sorted((work / 'evidence').glob('*window.png')):
            image = Image.open(path).convert('RGB')
            row = {}
            for label, point in {'shadow': (60/160, .5), 'control': (140/160, .5), 'caster': (.5, .5), 'healthy': (.75, 76/96), 'flipped_shadow': (100/160, .5), 'perspective_edge': (95/160, .5), 'valid_shadow': (20/160, .5), 'valid_caster': (40/160, .5)}.items():
                x, y = round(point[0] * image.width), round(point[1] * image.height)
                row[label] = ImageStat.Stat(image.crop((x-3, y-3, x+3, y+3))).mean
            pixels[path.name] = row
        events = {}
        for phase, epoch, light, generation, detail in re.findall(r'shadow phase=(depth-written|receiver|completed) epoch=(\d+) light=(\d+) generation=(\d+) ([^\n]+)', log):
            key = f'{epoch}:{light}:{generation}'
            events.setdefault(key, {}).setdefault(phase, []).append(detail)
        (work/'shadow-events.json').write_text(json.dumps(events, indent=2))
        report = {'shadowEvents': events, 'pixels': pixels, 'exit': result.returncode,
                  'completion': 'state=completed frame=1 ' in log, 'drained': 'gpuDrained=true' in log,
                  'prepared': set(map(int, re.search(r'prepared static model layers: \[([^\]]*)\]', preview).group(1).replace(' ', '').split(','))) == (({1, 2} if options.get('caster', True) else {1}) | ({5} if options.get('extra_valid_caster') else set())),
                  'immutable': all(sha(Path(k)) == v for k, v in self.identity.items()), 'work': str(work)}
        (work / 'result.json').write_text(json.dumps(report, indent=2))
        self.assertEqual(result.returncode, 0, report)
        for key in ['completion', 'drained', 'prepared', 'immutable']:
            self.assertTrue(report[key], (key, report))
        self.assertIn('scene-ready-window.png', pixels)
        self.assertIn('scene-after-window.png', pixels)
        if not moving:
            ready = Image.open(work / 'evidence/scene-ready-window.png').convert('RGB')
            after = Image.open(work / 'evidence/scene-after-window.png').convert('RGB')
            self.assertIsNone(ImageChops.difference(ready, after).getbbox(), report)
        if (options.get('caster', True) and options.get('layer_alpha', 1) == 1
                and options.get('texture_alpha', 255) == 255 and options.get('caster_x', 70) == 70
                and options.get('caster_z', 20) == 20 and not moving and not options.get('singular_caster') and not options.get('parent_offset')):
            rgb = pixels['scene-ready-window.png']['caster']
            self.assertGreater(rgb[1], max(rgb[0], rgb[2]) + 20, report)
        self.runs[name] = report
        return report

    def assert_shadow_lifecycle(self, result):
        complete = {key.split(':')[0] for key, phases in result['shadowEvents'].items()
                    if 'depth-written' in phases and 'layer=1' in phases.get('receiver', [])
                    and 'status=4' in phases.get('completed', [])}
        self.assertIn('1', complete, result)
        self.assertGreaterEqual(len(complete), 2, result)

    def assert_visibility(self, result, *, shadowed):
        baseline = self.run_case('cast-off', cast=False)
        if shadowed:
            self.assert_shadow_lifecycle(result)
        for phase in ['scene-ready-window.png', 'scene-after-window.png']:
            actual = result['pixels'][phase]
            reference = baseline['pixels'][phase]
            self.assertGreater(min(reference['shadow']), 50, baseline)
            for c in range(3):
                self.assertAlmostEqual(actual['control'][c], reference['control'][c], delta=3, msg=str(result))
                if shadowed:
                    self.assertLess(actual['shadow'][c], reference['shadow'][c] * .3, result)
                    self.assertGreater(actual['shadow'][c], 2, result)  # ambient must survive
                else:
                    self.assertAlmostEqual(actual['shadow'][c], reference['shadow'][c], delta=3, msg=str(result))

    def test_cast_switch_and_missing_caster(self):
        enabled = self.run_case('cast-on')
        self.assert_visibility(enabled, shadowed=True)
        disabled = self.run_case('cast-off', cast=False)
        for phase in ['scene-ready-window.png', 'scene-after-window.png']:
            for a, b in zip(enabled['pixels'][phase]['caster'], disabled['pixels'][phase]['caster']):
                self.assertAlmostEqual(a, b, delta=3, msg=str(enabled))
        self.assert_visibility(self.run_case('light-off', light_cast=False), shadowed=False)
        self.assert_visibility(self.run_case('no-caster', caster=False), shadowed=False)

    def test_singular_caster_is_local_and_valid_caster_still_shadows(self):
        result = self.run_case('singular-and-valid', singular_caster=True, extra_valid_caster=True)
        self.assert_visibility(result, shadowed=False)
        self.assert_shadow_lifecycle(result)
        for phase in ['scene-ready-window.png', 'scene-after-window.png']:
            pixels = result['pixels'][phase]
            self.assertLess(max(pixels['valid_shadow']), min(pixels['control']) * .3, result)
            self.assertGreater(min(pixels['valid_shadow']), 2, result)
            self.assertGreater(pixels['valid_caster'][1], max(pixels['valid_caster'][0], pixels['valid_caster'][2]) + 20, result)
            for a, b in zip(pixels['caster'], pixels['control']):
                self.assertAlmostEqual(a, b, delta=3, msg=str(result))

    def test_default_cast_and_bloom_preserve_shadow(self):
        self.assert_visibility(self.run_case('cast-omitted', cast='omitted'), shadowed=True)
        self.assert_visibility(self.run_case('bloom-enabled', bloom=True), shadowed=True)

    def test_unlit_caster_and_alpha_policy(self):
        for name, options, expected in [
            ('unlit-caster', {'caster_lit': False}, True),
            ('alpha-zero', {'layer_alpha': 0}, False),
            ('alpha-half', {'layer_alpha': .5}, False),
            ('alpha-one', {}, True),
            ('tint-mask-zero', {'texture_alpha': 0, 'tint_mask': True}, True)]:
            with self.subTest(name=name):
                self.assert_visibility(self.run_case(name, **options), shadowed=expected)

    def test_caster_depth_order_and_offscreen(self):
        for name, options, expected in [
            ('behind-receiver', {'caster_x': 30, 'caster_z': -20}, False),
            ('caster-before-receiver', {'caster_first': True}, True),
            ('offscreen-caster', {'caster_x': 170, 'caster_z': 120}, True)]:
            with self.subTest(name=name):
                self.assert_visibility(self.run_case(name, **options), shadowed=expected)

    def test_shadow_and_healthy_effect_neighbor_share_frame(self):
        result = self.run_case('healthy-effect', healthy_effect=True)
        self.assert_visibility(result, shadowed=True)
        for phase in ['scene-ready-window.png', 'scene-after-window.png']:
            rgb = result['pixels'][phase]['healthy']
            self.assertAlmostEqual(rgb[1], 100, delta=3, msg=str(result))
            self.assertLess(max(rgb[0], rgb[2]), 3, result)
        log = (Path(result['work']) / 'app.log').read_text()
        events = [line for line in log.splitlines() if 'axis=graph-execution' in line and 'layer=4 ' in line]
        self.assertTrue(any('compositorConsumed=true' in line and 'gpuCompletion=completed' in line for line in events), log)
        self.assertTrue(any('trigger=next-frame' in line for line in events), log)

    def test_actual_late_color_blend_coexists_with_shadow(self):
        active = self.run_case('late-color-blend-active', healthy_effect=True, color_blend=1)
        self.assert_visibility(active, shadowed=True)
        for phase in ['scene-ready-window.png', 'scene-after-window.png']:
            rgb = active['pixels'][phase]['healthy']
            self.assertGreater(rgb[1], max(rgb[0],rgb[2])+20, active)
        hidden = self.run_case('late-color-blend-hidden', healthy_effect=True, color_blend=1, healthy_visible=False)
        self.assert_visibility(hidden, shadowed=True)
        for phase in ['scene-ready-window.png', 'scene-after-window.png']:
            for a,b in zip(hidden['pixels'][phase]['healthy'], hidden['pixels'][phase]['control']):
                self.assertAlmostEqual(a,b,delta=3,msg=str(hidden))

    def test_real_perspective_camera_and_parent_transform(self):
        perspective = self.run_case('perspective-camera', perspective=True)
        self.assert_visibility(perspective, shadowed=True)
        for phase in ['scene-ready-window.png', 'scene-after-window.png']:
            edge = perspective['pixels'][phase]['perspective_edge']
            self.assertGreater(edge[1], max(edge[0], edge[2])+20, perspective)
        parent = self.run_case('parent-translated', parent_offset=20)
        self.assert_visibility(parent, shadowed=False)
        self.assert_shadow_lifecycle(parent)
        for phase in ['scene-ready-window.png', 'scene-after-window.png']:
            pixels = parent['pixels'][phase]
            self.assertLess(max(pixels['caster']), min(pixels['control'])*.3, parent)
            green = pixels['flipped_shadow']
            self.assertGreater(green[1], max(green[0],green[2])+20, parent)

    def test_directional_light_moves_shadow_and_restores(self):
        result = self.run_case('moving-light', moving_light=True)
        self.assert_visibility(result, shadowed=True)
        control = result['pixels']['scene-ready-window.png']['control']
        self.assertTrue(any(min(row['shadow']) > 50 and max(row['flipped_shadow']) < 25
                            and all(abs(a-b) <= 3 for a,b in zip(row['control'], control))
                            for name, row in result['pixels'].items() if name.startswith('scene-series-')), result)

    def test_moving_caster_later_frame_restores(self):
        result = self.run_case('moving-caster', moving=True)
        self.assert_visibility(result, shadowed=True)
        control = result['pixels']['scene-ready-window.png']['control']
        self.assertTrue(any(min(row['shadow']) > 50 and all(abs(a-b) <= 3 for a,b in zip(row['control'], control))
                            for name, row in result['pixels'].items() if name.startswith('scene-series-')), result)


if __name__ == '__main__':
    unittest.main()
