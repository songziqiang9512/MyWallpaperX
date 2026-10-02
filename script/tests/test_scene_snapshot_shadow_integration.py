#!/usr/bin/env python3
"""RF12 self-authored snapshots and model shadows through a frozen real App.

No corpus/stock shader source is read. All evidence is retained under an isolated
root; only app.log, scene-preview.log, own inputs and screenshots are inspected.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import tempfile
import unittest

from script.tests.test_scene_directional_shadow_integration import fixture_entries, make_package

REPO = Path(__file__).resolve().parents[2]
CASES = {
    'mixed-active': {}, 'mixed-zero': {'amount': 0},
    'hidden': {'hidden': True}, 'empty': {'empty': True, 'color_blend': False},
    'utility-active': {'utility': True, 'refraction': False},
    'utility-normal': {'utility': True, 'refraction': False, 'color_blend': False},
}


def raw_tex(pixel):
    payload = bytes(pixel) * 16
    return (b'TEXV0005\0TEXI0001\0' + struct.pack('<7I', 0, 0, 4, 4, 4, 4, 0)
            + b'TEXB0002\0' + struct.pack('<7I', 1, 1, 4, 4, 0, 0, len(payload)) + payload)


def snapshot_fixture(*, amount=.05, hidden=False, empty=False, color_blend=True,
                     utility=False, refraction=True):
    scene, entries = fixture_entries(healthy_effect=True, color_blend=int(color_blend))
    consumer = scene['objects'].pop()
    consumer.update(origin='35 20 0', visible=not hidden)
    scene['objects'].append({'id': 12, 'image': 'models/util/solidlayer.json',
                             'origin': '35 20 0', 'size': '24 24', 'color': '1 .25 0'})
    if utility:
        scene['objects'] += [
            {'id': 30, 'image': 'models/util/composelayer.json', 'origin': '0 0 0',
             'size': '160 96', 'colorBlendMode': int(color_blend),
             'effects': [{'id': 300, 'file': 'effects/own_dim/effect.json', 'visible': True}]},
            {'id': 31, 'parent': 30, 'image': 'models/util/solidlayer.json',
             'origin': '35 20 0', 'size': '16 16', 'color': '0 .7843137254901961 0'}]
    else:
        scene['objects'].append(consumer)
    # These layers are authored after A and before B, so B cannot use A's prefix.
    scene['objects'] += [
        {'id': 10, 'image': 'models/util/solidlayer.json', 'origin': '108 20 0', 'size': '24 24', 'color': '1 0 0'},
        {'id': 11, 'image': 'models/util/solidlayer.json', 'origin': '132 20 0', 'size': '24 24', 'color': '0 0 1'}]
    if refraction:
        scene['objects'].append({'id': 42, 'particle': 'particles/refract.json', 'origin': '115 20 0',
            'scale': '1 1 1', 'visible': not hidden, 'instanceoverride': {'alpha': {'value': 1,
            'script': 'export function init(value) { thisLayer.' + ('stop' if empty else 'pause') + '(); return value; }'}}})
    definition = {'material': 'materials/refract.json', 'maxcount': 8, 'starttime': .5,
        'emitter': [{'name': 'sphererandom', 'rate': 8, 'duration': 20, 'instantaneous': 1, 'distancemin': 0, 'distancemax': 0}],
        'initializer': [{'name': 'lifetimerandom', 'min': 30, 'max': 30},
                        {'name': 'sizerandom', 'min': 24, 'max': 24},
                        {'name': 'colorrandom', 'min': '255 255 255', 'max': '255 255 255'}],
        'renderer': [{'name': 'sprite'}]}
    material = {'passes': [{'shader': 'genericparticle', 'textures': ['materials/white.tex', 'materials/normal.tex'],
        'combos': {'REFRACT': 1}, 'constantshadervalues': {'ui_editor_properties_refract_amount': amount},
        'blending': 'translucent', 'depthtest': 'disabled', 'depthwrite': 'disabled', 'cullmode': 'nocull'}]}
    entries.update({'scene.json': json.dumps(scene).encode(), 'particles/refract.json': json.dumps(definition).encode(),
        'materials/refract.json': json.dumps(material).encode(), 'materials/white.tex': raw_tex([255]*4),
        'materials/normal.tex': raw_tex([255, 128, 0, 255])})
    return scene, entries


class SceneSnapshotShadowIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        configured = os.environ.get('MWX_SNAPSHOT_APP')
        if not configured:
            raise unittest.SkipTest('requires frozen MWX_SNAPSHOT_APP')
        cls.app = Path(configured).resolve(strict=True)
        cls.executable = cls.app/'Contents/MacOS/MyWallpaperX'
        cls.identity = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in [cls.executable,
            cls.executable.with_name('MyWallpaperX.debug.dylib'), cls.app/'Contents/Resources/default.metallib']}
        parent = os.environ.get('MWX_SNAPSHOT_EVIDENCE')
        if parent:
            Path(parent).mkdir(parents=True, exist_ok=True)
        cls.root = Path(tempfile.mkdtemp(prefix='snapshot-shadow-app-', dir=parent))
        sources = [Path(__file__), REPO/'script/tests/test_scene_directional_shadow_integration.py',
                   REPO/'script/tests/test_scene_static_model_reader.py', REPO/'script/tests/test_scene_pkg_cache_extractor.py']
        protocol = {'sources': {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}, 'app': cls.identity,
                    'inputs': {}, 'ROI': 'cover scale=max(W/160,H/96); canvas center maps viewport center',
                    'expected': 'shadow9/control85; colorblend64 (normal100); refraction positive blue/zero red; tolerance3'}
        for name, options in CASES.items():
            scene, entries = snapshot_fixture(**options)
            protocol['inputs'][name] = {'scene': scene, 'options': options,
                'entries': {k: hashlib.sha256(v).hexdigest() for k,v in entries.items()}}
        (cls.root/'protocol.json').write_text(json.dumps(protocol, indent=2))
        print(f'RF12 App evidence: {cls.root}', flush=True)

    def run_case(self, name):
        from PIL import Image, ImageChops, ImageStat
        options = CASES[name]; scene, entries = snapshot_fixture(**options)
        work = self.root/name; (work/'content').mkdir(parents=True); (work/'home').mkdir()
        (work/'content/project.json').write_text(json.dumps({'type':'scene','file':'scene.json'}))
        (work/'content/scene.pkg').write_bytes(make_package(list(entries.items())))
        (work/'scene-input.json').write_text(json.dumps(scene, indent=2))
        env = os.environ.copy(); env.update(HOME=str(work/'home'), CFFIXED_USER_HOME=str(work/'home'), MWX_SCENE_DEBUG_SURFACE_COUNT='1')
        command = [str(self.executable), '--mwx-debug-scene-root', str(work/'content'), '--mwx-debug-scene-duration', '6',
                   '--mwx-debug-scene-evidence-dir', str(work/'evidence')]
        with (work/'app.log').open('w') as log:
            process = subprocess.run(command, cwd=REPO, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=70)
        log = (work/'app.log').read_text(); preview = (work/'evidence/scene-preview.log').read_text()
        pictures = {}; pixels = {}
        for phase in ['ready', 'after']:
            im = Image.open(work/f'evidence/scene-{phase}-window.png').convert('RGB'); pictures[phase] = im; row = {}
            scale = max(im.width/160, im.height/96)
            for label, (x,y) in {'shadow':(60,48),'control':(140,48),'refract':(115,76),'colorblend':(35,76)}.items():
                x = round(im.width/2+(x-80)*scale); y = round(im.height/2+(y-48)*scale)
                row[label] = ImageStat.Stat(im.crop((x-3,y-3,x+3,y+3))).mean
            pixels[phase] = row
        census = re.search(r'phase=performance-gpu frames=(\d+)[^\n]*framebufferCaptures=(\d+)', log)
        particle = re.search(r'phase=performance-particle layer=42 [^\n]*completedRefractionBatches=(\d+)', log)
        result = {'exit':process.returncode,'appImmutable':all(hashlib.sha256(Path(k).read_bytes()).hexdigest()==v for k,v in self.identity.items()),
            'completion1':'state=completed frame=1 ' in log, 'completion2':'state=completed frame=2 ' in log,
            'drained':'gpuDrained=true' in log, 'pixels':pixels, 'stable':ImageChops.difference(pictures['ready'],pictures['after']).getbbox() is None,
            'frames':int(census[1]) if census else None,'captures':int(census[2]) if census else None,
            'refractionBatches':int(particle[1]) if particle else 0,
            'shadow': 'shadow phase=depth-written' in log,
            'shadowCompleted': 'shadow phase=completed' in log,
            'particleEmpty': 'particle current nonempty: layers=[]' in preview,
            'utilityEvents':[line for line in log.splitlines() if 'layer=30 ' in line and ('utility' in line or 'graph-execution' in line)]}
        (work/'result.json').write_text(json.dumps(result,indent=2))
        self.assertEqual(result['exit'],0)
        for key in ['appImmutable','completion1','completion2','drained','stable']:
            self.assertTrue(result[key], (name,key,result))
        self.assertIsNotNone(census,log)
        return result

    def assert_shadow(self, result):
        self.assertTrue(result['shadow'] and result['shadowCompleted'], result)
        for row in result['pixels'].values():
            self.assertAlmostEqual(min(row['shadow']),9,delta=3)
            self.assertAlmostEqual(max(row['shadow']),9,delta=3)
            for c in row['control']:
                self.assertAlmostEqual(c,85,delta=3)

    def assert_rgb(self, actual, expected):
        for a,b in zip(actual,expected):
            self.assertAlmostEqual(a,b,delta=3)

    def test_two_consumers_capture_their_current_background_with_shadow(self):
        for name, expected in [('mixed-active',[0,0,255]),('mixed-zero',[255,0,0])]:
            with self.subTest(name=name):
                result=self.run_case(name)
                for row in result['pixels'].values():
                    self.assert_rgb(row['colorblend'],[0,64,0]);self.assert_rgb(row['refract'],expected)
                self.assertGreater(result['refractionBatches'],0)
                self.assertEqual(result['captures'],2*result['frames'])
                self.assert_shadow(result)

    def test_hidden_consumers_do_not_capture(self):
        result=self.run_case('hidden');self.assertEqual(result['captures'],0);self.assertEqual(result['refractionBatches'],0)
        self.assert_shadow(result)

    def test_stopped_empty_uploaded_batch_does_not_capture(self):
        result=self.run_case('empty');self.assertTrue(result['particleEmpty']);self.assertEqual(result['refractionBatches'],0)
        self.assertEqual(result['captures'],0);self.assert_shadow(result)

    def test_utility_composite_uses_enclosing_background_capacity(self):
        for name,color,copies in [('utility-active',[0,64,0],1),('utility-normal',[0,100,0],0)]:
            with self.subTest(name=name):
                result=self.run_case(name)
                for row in result['pixels'].values():self.assert_rgb(row['colorblend'],color)
                self.assertTrue(any('compositorConsumed=true' in x and 'gpuCompletion=completed' in x for x in result['utilityEvents']),result)
                self.assertEqual(result['captures'],copies*result['frames'])
                self.assert_shadow(result)
