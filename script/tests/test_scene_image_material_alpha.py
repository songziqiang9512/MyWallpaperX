#!/usr/bin/env python3
"""Frozen App pixels for authored base material Alpha before effect composition."""
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import unittest
import tempfile
import zlib

ROOT = Path(__file__).resolve().parents[2]


def make_fixture(root):
    from script.tests.test_scene_pkg_cache_extractor import make_package
    root.mkdir(parents=True)
    def png(alpha):
        def chunk(kind, data):
            return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
        return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 4, 4, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress((b'\0' + bytes((255, 255, 255, alpha)) * 4) * 4)) + chunk(b'IEND', b'')
    project = {'type': 'scene', 'file': 'scene.json', 'general': {'properties': {'opacity': {'type': 'slider', 'value': 0, 'min': 0, 'max': 1}}}}
    objects = [
        {'id': 1, 'image': 'models/dynamic.json', 'origin': '32 48 0', 'size': '28 28'},
        {'id': 2, 'image': 'models/static.json', 'origin': '80 48 0', 'size': '28 28', 'alpha': .5},
        {'id': 3, 'image': 'models/dynamic.json', 'origin': '128 48 0', 'size': '28 28', 'effects': [{'id': 1, 'file': 'effects/alpha/effect.json', 'visible': True}]},
        {'id': 4, 'image': 'models/util/solidlayer.json', 'origin': '156 78 0', 'size': '16 16', 'color': '0 1 0'},
        {'id': 5, 'image': 'models/half.json', 'origin': '80 78 0', 'size': '20 12'},
        {'id': 7, 'image': 'models/dynamic.json', 'origin': '128 78 0', 'size': '20 12', 'effects': [{'id': 2, 'file': 'effects/dim/effect.json', 'visible': True}]},
        {'id': 6, 'image': 'models/dynamic.json', 'origin': '32 78 0', 'size': '20 12', 'instance': {'constantshadervalues': {'Alpha': .25}}},
    ]
    entries = {'scene.json': json.dumps({'version': 3, 'general': {'orthogonalprojection': {'width': 192, 'height': 96}, 'clearcolor': '0 0 1'}, 'objects': objects}).encode()}
    for name, alpha, texture in [('dynamic', {'user': 'opacity', 'value': 1}, 'white'), ('static', .5, 'white'), ('half', .5, 'half')]:
        entries['models/' + name + '.json'] = json.dumps({'material': 'materials/' + name + '.json'}).encode()
        entries['materials/' + name + '.json'] = json.dumps({'passes': [{'shader': 'genericimage2', 'constantshadervalues': {'Alpha': alpha, 'Brightness': 1}, 'textures': ['materials/' + texture + '.png'], 'blending': 'translucent', 'depthtest': 'disabled', 'depthwrite': 'disabled', 'cullmode': 'nocull'}]}).encode()
    entries.update({
        'materials/white.png': png(255), 'materials/half.png': png(128),
        'effects/alpha/effect.json': json.dumps({'passes': [{'material': 'materials/alpha.json'}]}).encode(),
        'materials/alpha.json': json.dumps({'passes': [{'shader': 'alpha_probe', 'textures': [None], 'blending': 'normal', 'depthtest': 'disabled', 'depthwrite': 'disabled', 'cullmode': 'nocull'}]}).encode(),
        'shaders/alpha_probe.vert': b'attribute vec3 a_Position;\nattribute vec2 a_TexCoord;\nvarying vec2 v_TexCoord;\nvoid main(){gl_Position=vec4(a_Position,1.0);v_TexCoord=a_TexCoord;}\n',
        'shaders/alpha_probe.frag': b'uniform sampler2D g_Texture0;\nvarying vec2 v_TexCoord;\nvoid main(){vec4 c=texSample2D(g_Texture0,v_TexCoord);gl_FragColor=vec4(1.0,0.0,0.0,1.0);}\n',
    })
    entries['effects/dim/effect.json'] = json.dumps({'passes': [{'material': 'materials/dim.json'}]}).encode()
    entries['materials/dim.json'] = entries['materials/alpha.json'].replace(b'alpha_probe', b'dim_probe')
    entries['shaders/dim_probe.vert'] = entries['shaders/alpha_probe.vert']
    entries['shaders/dim_probe.frag'] = entries['shaders/alpha_probe.frag'].replace(b'gl_FragColor=vec4(1.0,0.0,0.0,1.0);', b'c.rgb*=0.5;gl_FragColor=c;')
    (root / 'project.json').write_text(json.dumps(project))
    (root / 'scene.pkg').write_bytes(make_package(list(entries.items())))
    return entries


class SceneImageMaterialAlphaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from script.tests import test_scene_alpha_display_builder_fixture as builder
        cls.temp = tempfile.TemporaryDirectory(prefix='mwx-image-alpha-native-')
        cls.work = Path(cls.temp.name)
        source = cls.work / 'Probe.swift'
        source.write_text(builder.HARNESS_SOURCE.split('@main', 1)[0] + r"""
@main enum Probe {
 static func main() throws {
  let model = try SceneRuntimeModelBuilder().build(rootURL: URL(fileURLWithPath: CommandLine.arguments[1]))
  let program = model.runtimeInput.propertyBindingProgram
  let targets = Set(program.instructions.map(\.target))
  let passes = SceneMaterialPropertyBindingCompiler.imageMaterialPasses(descriptor:model.renderDescriptor)
  let profiles = model.renderDescriptor.layers.map { layer in
   SceneMaterialPropertyBindingCompiler.sourceMaterialAlpha(layer:layer,
    instance:model.sceneDocument.materialInstancesByLayerID[layer.id],
    passes:passes[layer.id] ?? [], materialPropertyTargets:targets)
  }
  func rows(_ values:[SceneDynamicTarget:SceneDynamicValue]) -> [Float] {
   let snapshot = SceneDynamicSnapshotResolver().resolve(frameIndex:1,generation:1,
    definitions:program.definitions,userValues:values).snapshot
   return profiles.map { $0?.resolve(snapshot:snapshot) ?? -1 }
  }
  var state = ScenePropertyLiveUpdateState(program:program,
   effectiveValues:model.runtimeInput.effectivePropertyValues, activeConsumerTargets:targets)
  var events:[[String:Any]] = []
  for value:SceneUserPropertyValue in [.number(0.25),.number(0.25),.number(0),.string("bad"),.number(2),.number(1)] {
   let accepted=state.apply(value,forPropertyKey:"opacity")
   events.append(["accepted":accepted,"revision":state.revision,"values":rows(state.userValues)])
  }
  let evaluation=program.evaluate(effectiveValues:model.runtimeInput.effectivePropertyValues)
  let output:[String:Any] = ["count":program.instructions.count,"unique":targets.count,
   "dynamic":profiles.map {$0?.propertyTarget != nil},"initial":rows(evaluation.userValues),
   "fallback":rows([:]),"events":events]
  print(String(decoding:try JSONSerialization.data(withJSONObject:output),as:UTF8.self))
 }
}
""")
        cls.binary = cls.work / 'probe'
        production = ROOT / 'MyWallpaperX/Core/SteamWorkshopScene'
        sources = builder.SWIFT_SOURCES + [production / 'Systems/Properties/ScenePropertyLiveUpdateState.swift']
        result = subprocess.run(['xcrun','swiftc',*map(str,sources),str(source),'-module-cache-path',str(cls.work/'cache'),'-o',str(cls.binary)],capture_output=True,text=True)
        if result.returncode: raise AssertionError(result.stderr)

    @classmethod
    def tearDownClass(cls): cls.temp.cleanup()

    def probe(self, *, value=None, instance=None, shader='genericimage2', multi=False, defined=True):
        root = self.work / 'input'; root.mkdir(exist_ok=True)
        (root/'models').mkdir(exist_ok=True);(root/'materials').mkdir(exist_ok=True)
        material={'shader':shader,'constantshadervalues':{'Alpha':{'user':'opacity','value':.75} if value is None else value},'textures':['materials/white.png']}
        objects=[{'id':i,'image':'models/image.json','size':'16 16',**({'instance':instance} if i==1 and instance is not None else {})} for i in range(1,13)]
        for path,data in {'project.json':{'type':'scene','file':'scene.json','general':{'properties':{'opacity':{'type':'slider','value':.5,'min':0,'max':1}} if defined else {}}},
                          'scene.json':{'version':3,'objects':objects},'models/image.json':{'material':'materials/image.json'},'materials/image.json':{'passes':[material,material] if multi else [material]}}.items():
            (root/path).write_text(json.dumps(data))
        run=subprocess.run([str(self.binary),str(root)],capture_output=True,text=True)
        self.assertEqual(run.returncode,0,run.stderr)
        return json.loads(run.stdout)

    def test_twelve_targets_resolve_initial_live_fallback_and_atomic_rejection(self):
        result=self.probe()
        self.assertEqual((result['count'],result['unique']),(12,12))
        self.assertEqual(result['initial'],[.5]*12);self.assertEqual(result['fallback'],[.75]*12)
        self.assertEqual([e['accepted'] for e in result['events']],[True,True,True,False,False,True])
        self.assertEqual([e['revision'] for e in result['events']],[1,1,2,2,2,3])
        for event,want in zip(result['events'],[.25,.25,0,0,0,1]):self.assertEqual(event['values'],[want]*12)

    def test_static_and_instance_override_have_no_material_writer(self):
        result=self.probe(value=.25)
        self.assertEqual(result['count'],0);self.assertEqual(result['initial'],[.25]*12)
        for value,want in [(.25,.25),(0,0),(None,-1),('invalid',-1),('0.5 junk',-1),('junk 0.5',-1),(-.1,-1)]:
            result=self.probe(instance={'constantshadervalues':{'Alpha':value}})
            self.assertEqual(result['count'],11,(value,result));self.assertFalse(result['dynamic'][0])
            self.assertEqual(result['initial'][0],want,(value,result))
            self.assertEqual(result['events'][0]['values'][1:],[.25]*11)

    def test_alpha_requires_a_complete_scalar_token(self):
        for raw in ['0.5 junk', 'junk 0.5', '0.5 0.5', '', 'false']:
            for value in [raw, {'user':'opacity','value':raw}]:
                result=self.probe(value=value)
                self.assertEqual(result['count'],0,(value,result))
                self.assertEqual(result['initial'],[-1]*12,(value,result))
        for raw in ['0.5', ' 0.5 ']:
            result=self.probe(value=raw)
            self.assertEqual(result['initial'],[.5]*12)

    def test_unknown_shader_wrappers_and_multi_pass_are_not_claimed(self):
        for case in [dict(shader='custom'),dict(shader='genericimage3'),dict(multi=True),dict(defined=False),
                     dict(value={'user':17,'value':.5}),dict(value={'user':'opacity','value':.5,'script':'export function update(v){return v;}'}),
                     dict(value={'user':'opacity','value':.5,'extra':True}),dict(value={'user':'opacity','value':-1})]:
            result=self.probe(**case)
            self.assertEqual(result['count'],0,(case,result))
            self.assertFalse(any(result['dynamic']),(case,result))
        result=self.probe(shader='genericimage')
        self.assertEqual(result['count'],12)


@unittest.skipUnless(os.environ.get('MWX_IMAGE_ALPHA_APP'), 'requires frozen signed App')
class SceneImageMaterialAlphaAppTests(unittest.TestCase):
    def test_source_alpha_live_static_instance_and_effect_order(self):
        from PIL import Image, ImageStat
        work = Path(os.environ['MWX_IMAGE_ALPHA_EVIDENCE'])
        work.mkdir(parents=True)
        content = work / 'content'
        make_fixture(content)
        home = work / 'home'; home.mkdir()
        evidence = work / 'evidence'
        app = Path(os.environ['MWX_IMAGE_ALPHA_APP'])
        command = [str(app), '--mwx-debug-scene-root', str(content), '--mwx-debug-scene-evidence-dir', str(evidence), '--mwx-debug-scene-duration', '12', '--mwx-debug-scene-periodic-snapshot-interval', '1', '--mwx-debug-scene-after-snapshot-delay', '10', '--mwx-debug-scene-live-property-sequence-json', json.dumps([{'opacity': 1}, {'opacity': .5}, {'opacity': 0}])]
        identities = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in [app, app.parent / 'MyWallpaperX.debug.dylib', *content.iterdir()]}
        (work / 'input-identity.json').write_text(json.dumps(identities, indent=2))
        (work / 'command.json').write_text(json.dumps(command, indent=2))
        env = {k: v for k, v in os.environ.items() if not k.startswith(('MWX_SCENE_DEBUG_', 'MYWALLPAPERX_SCENE_DEBUG_'))}
        env.update(HOME=str(home), CFFIXED_USER_HOME=str(home), MWX_SCENE_DEBUG_SURFACE_COUNT='1', MWX_SCENE_GENERIC_SHADER_CACHE=str(work / 'cache'))
        with (work / 'app.log').open('w') as out:
            result = subprocess.run(command, cwd=ROOT, env=env, stdout=out, stderr=subprocess.STDOUT, timeout=120)
        log = (work / 'app.log').read_text()
        images = {}
        for path in sorted(evidence.glob('*-window.png')):
            im = Image.open(path).convert('RGB'); width, height = im.size
            def roi(x, y):
                # The fixed 2:1 scene is aspect-filled to the evidence target.
                scale = max(width / 192, height / 96)
                px = (width - 192 * scale) / 2 + x * scale
                py = (height - 96 * scale) / 2 + (96-y) * scale
                return ImageStat.Stat(im.crop((int(px)-3, int(py)-3, int(px)+3, int(py)+3))).mean
            images[path.name] = {name: roi(x, y) for name, x, y in [('dynamic',32,48),('static',80,48),('effect',128,48),('peer',156,78),('half',80,78),('instance',32,78),('dim',128,78)]}
        report = {'returncode': result.returncode, 'drained': 'gpuDrained=true' in log, 'unchanged': all(hashlib.sha256(Path(p).read_bytes()).hexdigest() == h for p,h in identities.items()), 'steps': re.findall(r'phase=live-property-sequence-step index=(\d+) accepted=(true|false)', log), 'images': images}
        (work / 'result.json').write_text(json.dumps(report, indent=2))
        self.assertEqual(result.returncode, 0)
        self.assertTrue(report['drained']); self.assertTrue(report['unchanged'])
        self.assertEqual([s[1] for s in report['steps']], ['true'] * 3)
        self.assertGreaterEqual(len(images), 8)
        self.assertNotIn('materialNodes=0', log)
        self.assertNotIn('outcome=failed', log)
        def close(actual, expected): return all(abs(a-b) <= 3 for a,b in zip(actual,expected))
        for name, row in images.items():
            for key, want in [('static',[64,64,255]),('half',[64,64,255]),('instance',[64,64,255]),('peer',[0,255,0])]:
                self.assertTrue(close(row[key],want),(name,key,row))
            # The effect replaces alpha with one. A material alpha wrongly
            # applied after it would let blue background leak into its output.
            self.assertLessEqual(row['effect'][1],3,(name,row))
            self.assertLessEqual(row['effect'][2],3,(name,row))
        for value in [0,.5,1]:
            self.assertTrue(any(close(row['dynamic'],[255*value,255*value,255]) and close(row['effect'],[255,0,0]) and close(row['dim'],[127.5*value,127.5*value,255-127.5*value]) for row in images.values()),(value,images))


if __name__ == '__main__': unittest.main()
