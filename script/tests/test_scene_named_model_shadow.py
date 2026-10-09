#!/usr/bin/env python3
"""RF13: self-authored named model color and directional-shadow consumers.

App cases require MWX_NAMED_MODEL_SHADOW_APP pointing to a frozen staged App.
Only own inputs, app.log, scene-preview.log and PNGs are inspected. The original
three-input RF12 red remains immutable under /private/tmp/mwx-rf13.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

from script.tests.test_scene_directional_shadow_integration import fixture_entries, make_package

REPO = Path(__file__).resolve().parents[2]
SCENE = REPO/'MyWallpaperX/Core/SteamWorkshopScene'
APP_CASES = ('static', 'named-early', 'named-late', 'middle-image-alpha', 'solid-late', 'forward-graph-neighbor', 'hidden-normal-consumer')
ROI = {'shadow': (60,48), 'caster': (80,48), 'control': (140,48),
       'peer-shadow': (20,48), 'peer-caster': (40,48)}
EXPECTED = {'shadow': [9,9,9], 'caster': [0,95,0], 'control': [85,85,85],
            'peer-shadow': [9,9,9], 'peer-caster': [0,95,0]}
TOLERANCE = 3


def named_fixture(case):
    """Keep baseline three byte-identical; two extensions change one producer."""
    dynamic = case == 'middle-image-alpha'
    scene, entries = fixture_entries(extra_valid_caster=dynamic)
    if case != 'static':
        caster = next(o for o in scene['objects'] if o['id'] == 2)
        caster['dependencies'] = [11]
        material = json.loads(entries['materials/caster.json'])
        material['passes'][0]['textures'] = ['_rt_imageLayerComposite_11_a']
        entries['materials/caster.json'] = json.dumps(material).encode()
        provider = {'id':11, 'image':'models/provider.json', 'origin':'80 48 0',
                    'size':'20 20', 'visible':False}
        entries['models/provider.json'] = json.dumps({'material':'materials/provider.json'}).encode()
        entries['materials/provider.json'] = json.dumps({'passes':[
            {'shader':'genericimage','textures':['materials/green.png']}]}).encode()
        if case == 'solid-late':
            provider.update(image='models/util/solidlayer.json',color='0 0.7843137254901961 0')
        if dynamic:
            # The peer must retain its static material; sharing the named caster
            # material would silently turn it into another named dependency.
            entries['materials/peer.json'] = json.dumps({'passes':[{
                'shader':'genericimage','textures':['materials/green.png'],
                'combos':{'LIGHTING':1},'blending':'normal','cullmode':'nocull',
                'depthtest':'enabled','depthwrite':'enabled'}]}).encode()
            from script.tests.test_scene_directional_shadow_integration import quad
            entries['models/valid.mdl'] = quad(30,50,38,58,20,'materials/peer.json')
            provider['alpha'] = {'value':1,'script':
                'export function update(value) { return engine.runtime >= 2.5 && engine.runtime < 5.5 ? 0 : 1; }'}
            receiver = next(o for o in scene['objects'] if o['id'] == 1)
            peer = next(o for o in scene['objects'] if o['id'] == 5)
            lamp = next(o for o in scene['objects'] if o['id'] == 3)
            scene['objects'] = [receiver,peer,provider,caster,lamp]
        else:
            scene['objects'].insert(0 if case == 'named-early' else len(scene['objects']),provider)
    if case == 'forward-graph-neighbor':
        entries['effects/own_dim/effect.json']=json.dumps({'passes':[{'material':'materials/own_dim.json'}]}).encode()
        entries['materials/own_dim.json']=json.dumps({'passes':[{'shader':'own_dim','textures':[None],
            'blending':'normal','depthtest':'disabled','depthwrite':'disabled','cullmode':'nocull'}]}).encode()
        entries['shaders/own_dim.vert']=b'attribute vec3 a_Position;\nattribute vec2 a_TexCoord;\nvarying vec2 v_TexCoord;\nvoid main(){gl_Position=vec4(a_Position,1.0);v_TexCoord=a_TexCoord;}\n'
        entries['shaders/own_dim.frag']=b'uniform sampler2D g_Texture0;\nvarying vec2 v_TexCoord;\nvoid main(){vec4 c=texSample2D(g_Texture0,v_TexCoord);c.rgb*=0.5;gl_FragColor=c;}\n'
        entries['effects/own_sample/effect.json']=json.dumps({'passes':[{'material':'materials/own_sample.json'}]}).encode()
        entries['materials/own_sample.json']=json.dumps({'passes':[{'shader':'own_sample','textures':[None,'_rt_imageLayerComposite_31_a'],
            'blending':'normal','depthtest':'disabled','depthwrite':'disabled','cullmode':'nocull'}]}).encode()
        entries['shaders/own_sample.vert']=entries['shaders/own_dim.vert']
        entries['shaders/own_sample.frag']=b'uniform sampler2D g_Texture1;\nvarying vec2 v_TexCoord;\nvoid main(){gl_FragColor=texSample2D(g_Texture1,v_TexCoord);}'
        scene['objects'] += [
            {'id':50,'image':'models/provider.json','origin':'20 16 0','size':'8 8','dependencies':[31],
             'effects':[{'id':500,'file':'effects/own_sample/effect.json','visible':True,
                         'passes':[{'id':501,'textures':[None,'_rt_imageLayerComposite_31_a']}]}]},
            {'id':31,'image':'models/provider.json','origin':'140 16 0','size':'8 8','visible':False,
             'effects':[{'id':310,'file':'effects/own_dim/effect.json','visible':True}]}]
    if case == 'hidden-normal-consumer':
        entries['effects/own_sample/effect.json']=json.dumps({'passes':[{'material':'materials/own_sample.json'}]}).encode()
        entries['materials/own_sample.json']=json.dumps({'passes':[{'shader':'own_sample','textures':[None,'_rt_imageLayerComposite_70_a'],
            'blending':'normal','depthtest':'disabled','depthwrite':'disabled','cullmode':'nocull'}]}).encode()
        entries['shaders/own_sample.vert']=b'attribute vec3 a_Position;\nattribute vec2 a_TexCoord;\nvarying vec2 v_TexCoord;\nvoid main(){gl_Position=vec4(a_Position,1.0);v_TexCoord=a_TexCoord;}\n'
        entries['shaders/own_sample.frag']=b'uniform sampler2D g_Texture1;\nvarying vec2 v_TexCoord;\nvoid main(){gl_FragColor=texSample2D(g_Texture1,v_TexCoord);}'
        scene['objects'] += [
            {'id':70,'image':'models/util/composelayer.json','origin':'80 48 0','size':'160 96','visible':False},
            {'id':71,'image':'models/provider.json','origin':'20 16 0','size':'8 8','dependencies':[70],
             'visible':{'value':True,'script':'export function update(value) { return engine.runtime >= 3; }'},
             'effects':[{'id':710,'file':'effects/own_sample/effect.json','visible':True,
                         'passes':[{'id':711,'textures':[None,'_rt_imageLayerComposite_70_a']}]}]}]
    entries['scene.json'] = json.dumps(scene).encode()
    return scene,entries


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def sample_canvas(image):
    """Independent camera cover mapping; no product camera/matrix is consulted."""
    from PIL import ImageStat
    scale=max(image.width/160,image.height/96)
    result={}
    for label,(x,y) in ROI.items():
        x=round(image.width/2+(x-80)*scale); y=round(image.height/2+(y-48)*scale)
        result[label]=ImageStat.Stat(image.crop((x-3,y-3,x+3,y+3))).mean
    return result


class SceneNamedModelShadowAppTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        app=os.environ.get('MWX_NAMED_MODEL_SHADOW_APP')
        if not app:
            raise unittest.SkipTest('requires frozen MWX_NAMED_MODEL_SHADOW_APP')
        cls.app=Path(app).resolve(strict=True)
        cls.executable=cls.app/'Contents/MacOS/MyWallpaperX'
        cls.binary_identity={str(p):sha(p) for p in [cls.executable,
            cls.executable.with_name('MyWallpaperX.debug.dylib'),cls.app/'Contents/Resources/default.metallib']}
        parent=os.environ.get('MWX_NAMED_MODEL_SHADOW_EVIDENCE')
        if parent: Path(parent).mkdir(parents=True,exist_ok=True)
        cls.root=Path(tempfile.mkdtemp(prefix='named-model-shadow-app-',dir=parent))
        sources=[Path(__file__),REPO/'script/tests/test_scene_directional_shadow_integration.py',
                 REPO/'script/tests/test_scene_static_model_reader.py',REPO/'script/tests/test_scene_pkg_cache_extractor.py']
        cls.source_identity={str(p):sha(p) for p in sources}
        inputs={}
        for case in APP_CASES:
            scene,entries=named_fixture(case)
            inputs[case]={'scene':scene,'entries':{k:hashlib.sha256(v).hexdigest() for k,v in entries.items()}}
        protocol={'app':cls.binary_identity,'sources':cls.source_identity,'inputs':inputs,
                  'roi':ROI,'mapping':'cover=max(W/160,H/96), aligned canvas/viewport centers',
                  'expected':EXPECTED,'tolerance':TOLERANCE,'forwardNeighborROI':{'canvas':[20,80],'expected':[0,100,0],'tolerance':3},'hiddenNormalROI':{'canvas':[20,80],'ready':[85,85,85],'after':[0,95,0],'tolerance':3},
                  'independentGeometry':'z20 caster x70..90 toward(+X,+Z) casts x50..70; peer x30..50 casts x10..30',
                  'dynamic':'valid current alpha1->0->1; not unavailable; peer/control unchanged in same image'}
        (cls.root/'protocol.json').write_text(json.dumps(protocol,indent=2))
        cls.runs={}
        print(f'RF13 App evidence: {cls.root}',flush=True)

    def run_case(self,case):
        if case in self.runs: return self.runs[case]
        from PIL import Image,ImageChops
        scene,entries=named_fixture(case)
        work=self.root/case; (work/'content').mkdir(parents=True); (work/'home').mkdir()
        (work/'content/scene.pkg').write_bytes(make_package(list(entries.items())))
        (work/'content/project.json').write_text(json.dumps({'type':'scene','file':'scene.json'}))
        (work/'scene-input.json').write_text(json.dumps(scene,indent=2))
        dynamic=case in ('middle-image-alpha','hidden-normal-consumer')
        command=[str(self.executable),'--mwx-debug-scene-root',str(work/'content'),
                 '--mwx-debug-scene-duration','9' if dynamic else '6',
                 '--mwx-debug-scene-evidence-dir',str(work/'evidence')]
        if dynamic:
            command += ['--mwx-debug-scene-periodic-snapshot-interval','1.5',
                        '--mwx-debug-scene-after-snapshot-delay','7.2']
        (work/'prerun.json').write_text(json.dumps({'command':command,
            'inputs':{p.name:sha(p) for p in (work/'content').iterdir()}},indent=2))
        env=os.environ.copy();env.update(HOME=str(work/'home'),CFFIXED_USER_HOME=str(work/'home'),MWX_SCENE_DEBUG_SURFACE_COUNT='1')
        with (work/'app.log').open('w') as log:
            process=subprocess.run(command,cwd=REPO,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=80)
        log=(work/'app.log').read_text();preview=(work/'evidence/scene-preview.log').read_text()
        images={p.name:Image.open(p).convert('RGB') for p in sorted((work/'evidence').glob('*window.png'))}
        pixels={name:sample_canvas(image) for name,image in images.items()}
        events={}
        for phase,epoch,light,generation,detail in re.findall(
                r'shadow phase=(depth-written|receiver|completed) epoch=(\d+) light=(\d+) generation=(\d+) ([^\n]+)',log):
            events.setdefault(f'{epoch}:{light}:{generation}',{}).setdefault(phase,[]).append(detail)
        result={'work':str(work),'exit':process.returncode,'pixels':pixels,'shadowEvents':events,
                'immutable':all(sha(p)==h for p,h in self.binary_identity.items()),
                'sourceUnchanged':all(sha(p)==h for p,h in self.source_identity.items()),
                'completion1':'state=completed frame=1 ' in log,'completion2':'state=completed frame=2 ' in log,
                'drained':'gpuDrained=true' in log,
                'captureSucceeded':'phase=named-target-capture layer=11 status=succeeded' in log,
                'bindingSucceeded':'phase=named-target-binding layer=2 status=succeeded' in log,
                'preparedLines':[l for l in preview.splitlines() if 'prepared static model layers:' in l],
                'scriptEvents':[l for l in log.splitlines() if 'script' in l.lower() and ('accept' in l.lower() or 'transaction' in l.lower())]}
        if not dynamic and 'scene-ready-window.png' in images and 'scene-after-window.png' in images:
            result['stable']=ImageChops.difference(images['scene-ready-window.png'],images['scene-after-window.png']).getbbox() is None
        (work/'result.json').write_text(json.dumps(result,indent=2))
        self.assertEqual(result['exit'],0,result)
        for key in ['immutable','sourceUnchanged','completion1','completion2','drained']:
            self.assertTrue(result[key],(case,key,result))
        if case!='static':
            self.assertTrue(result['captureSucceeded'] and result['bindingSucceeded'],result)
        if not dynamic: self.assertTrue(result.get('stable'),result)
        for name in ['scene-ready-window.png','scene-after-window.png']: self.assertIn(name,pixels,result)
        complete={key.split(':')[0] for key,phases in events.items()
                  if 'depth-written' in phases and 'layer=1' in phases.get('receiver',[]) and 'status=4' in phases.get('completed',[])}
        self.assertTrue({'1','2'}.issubset(complete),result)
        self.runs[case]=result
        return result

    def assert_pixel(self,row,label,expected):
        for a,b in zip(row[label],expected): self.assertAlmostEqual(a,b,delta=TOLERANCE,msg=str(row))

    def test_static_and_named_before_after_keep_color_and_add_shadow(self):
        for case in APP_CASES[:3]:
            with self.subTest(case=case):
                result=self.run_case(case)
                for phase in ['scene-ready-window.png','scene-after-window.png']:
                    for label in ['shadow','caster','control']:
                        self.assert_pixel(result['pixels'][phase],label,EXPECTED[label])

    def test_middle_source_current_alpha_changes_both_consumers_without_peer_drift(self):
        result=self.run_case('middle-image-alpha')
        for phase in ['scene-ready-window.png','scene-after-window.png']:
            for label in ROI: self.assert_pixel(result['pixels'][phase],label,EXPECTED[label])
        def near(rgb,expected): return all(abs(a-b)<=TOLERANCE for a,b in zip(rgb,expected))
        intermediates=[row for name,row in result['pixels'].items() if name.startswith('scene-series-')]
        self.assertTrue(any(near(row['shadow'],EXPECTED['control']) and near(row['caster'],EXPECTED['control'])
            and all(near(row[k],EXPECTED[k]) for k in ['peer-shadow','peer-caster','control']) for row in intermediates),result)

    def test_hidden_solid_source_uses_same_named_shadow_chain(self):
        result=self.run_case('solid-late')
        for phase in ['scene-ready-window.png','scene-after-window.png']:
            for label in ['shadow','caster','control']:
                self.assert_pixel(result['pixels'][phase],label,EXPECTED[label])

    def test_forward_effectful_neighbor_preserves_named_shadow_and_single_graph_consumption(self):
        from PIL import Image,ImageStat
        result=self.run_case('forward-graph-neighbor')
        work=Path(result['work']);log=(work/'app.log').read_text()
        for phase in ['scene-ready-window.png','scene-after-window.png']:
            for label in ['shadow','caster','control']:
                self.assert_pixel(result['pixels'][phase],label,EXPECTED[label])
            im=Image.open(work/'evidence'/phase).convert('RGB');scale=max(im.width/160,im.height/96)
            x=round(im.width/2+(20-80)*scale);y=round(im.height/2+(80-48)*scale)
            rgb=ImageStat.Stat(im.crop((x-3,y-3,x+3,y+3))).mean
            for a,b in zip(rgb,[0,100,0]):self.assertAlmostEqual(a,b,delta=3)
        self.assertIn('phase=named-graph-output-publication layer=31 status=succeeded',log)
        self.assertIn('phase=named-target-binding layer=50 status=succeeded',log)
        self.assertLess(log.index('origin=image subject=effect layer=31 '),log.index('origin=image subject=effect layer=50 '))
        self.assertRegex(log,r'axis=scene-frame-command-buffer frame=0 attemptedEffects=2 returnedOutputs=2 failedInvocations=0 routeOperations=0[^\n]+status=completed')
        lines=[l for l in log.splitlines() if 'axis=graph-execution' in l]
        self.assertTrue(any('layer=31 ' in l and 'compositorConsumed=false' in l and 'gpuCompletion=completed' in l for l in lines))
        self.assertTrue(any('layer=50 ' in l and 'dependencyProviders=31' in l and 'compositorConsumed=true' in l and 'gpuCompletion=completed' in l for l in lines))
        self.assertTrue(any('trigger=next-frame' in l and 'layer=50 ' in l and 'dependencyProviders=31' in l for l in lines))

    def test_dynamic_hidden_normal_consumer_keeps_original_provider_capture(self):
        from PIL import Image,ImageStat
        result=self.run_case('hidden-normal-consumer');work=Path(result['work'])
        log=(work/'app.log').read_text();preview=(work/'evidence/scene-preview.log').read_text()
        for phase,expected in [('scene-ready-window.png',[85,85,85]),('scene-after-window.png',[0,95,0])]:
            for label in ['shadow','caster','control']:self.assert_pixel(result['pixels'][phase],label,EXPECTED[label])
            im=Image.open(work/'evidence'/phase).convert('RGB');scale=max(im.width/160,im.height/96)
            x=round(im.width/2+(20-80)*scale);y=round(im.height/2+(80-48)*scale)
            rgb=ImageStat.Stat(im.crop((x-3,y-3,x+3,y+3))).mean
            for a,b in zip(rgb,expected):self.assertAlmostEqual(a,b,delta=3)
        self.assertRegex(log,r'frame=0[^\n]+layer=71 source=sceneScript value=false effective=false')
        self.assertRegex(log,r'layer=71 source=sceneScript value=true effective=true')
        capture=log.index('phase=named-target-capture layer=70 status=succeeded')
        restored=re.search(r'layer=71 source=sceneScript value=true effective=true',log).start()
        self.assertLess(capture,restored)
        self.assertIn('phase=named-target-binding layer=71 status=succeeded',log)
        self.assertTrue(any('axis=graph-execution' in line and 'layer=71 ' in line and 'dependencyProviders=70' in line and 'compositorConsumed=true' in line and 'gpuCompletion=completed' in line for line in log.splitlines()))

# The load-time plan shell below supplies already-prepared bindings. Capture,
# target allocation, publication, identity validation and GPU encode are real.
# This probe does not claim to test parser/admission (the real App does that).
from script.tests import test_scene_dependency_graph_output_runtime as dependency_fixture
from script.tests import test_scene_frame_texture_registry as registry_fixture

DEPENDENCY_SOURCES = list(dict.fromkeys([
    *registry_fixture.SWIFT_SOURCES,
    dependency_fixture.RUNTIME_SOURCE, dependency_fixture.STATIC_MODEL_RUNTIME_SOURCE,
    dependency_fixture.AGGREGATE_VALIDATION_RUNTIME_SOURCE,
    dependency_fixture.GEOMETRY_RUNTIME_SOURCE,
    dependency_fixture.EFFECT_INPUT_RESOLUTION_RUNTIME_SOURCE,
    SCENE/'Rendering/Dependencies/SceneNamedRenderTargetPool.swift',
    SCENE/'Rendering/Metal/SceneMetalPipeline.swift',
    SCENE/'Rendering/Composition/SceneOffscreenEffectRenderer+Capture.swift',
    SCENE/'Rendering/Composition/SceneMainPassEncoder.swift',
    SCENE/'Rendering/Geometry/SceneMatrix.swift',
    SCENE/'Diagnostics/SceneGPUCompletionTelemetry.swift',
    SCENE/'Diagnostics/ScenePerformanceCounterHub.swift',
    SCENE/'Diagnostics/SceneGPUCensus.swift',
]))


def dependency_support():
    fixture=dependency_fixture.HARNESS_SOURCE
    # Reuse prepared-input scaffolding only, excluding all fake runtime owners
    # (registry, target pool, capture renderer, main pass, telemetry and textures).
    plan=fixture.split('struct SceneUtilityLayer',1)[1].split('enum SceneFrameTextureIdentity',1)[0]
    peripheral=fixture.split('typealias ColorBlendBinder',1)[1].split('enum SceneMatrix',1)[0]
    geometry=fixture.split('struct SceneGeometryProduct',1)[1].split('final class SceneImageLayerPipeline',1)[0]
    return ('import Foundation\nimport CoreGraphics\nimport Metal\nimport simd\n'
        +'struct SceneUtilityLayer'+plan
        +'typealias ColorBlendBinder'+peripheral+'struct SceneGeometryProduct'+geometry
        +DEPENDENCY_EXTRA)


DEPENDENCY_EXTRA = r'''
enum SceneTextureLoadOutcome {
 case loaded(MTLTexture);case decodeFailed(String);case textureAllocationFailed(width:Int,height:Int)
}
final class SceneGraphRenderTargetResidencyPin {
 func release() {fatalError("graph residency outside this source-only probe")}
}
extension SceneLayerFragmentUniforms {
 static func neutral()->Self {
  .init(time:0,alpha:1,dependencyBlendMode:0,usesDependencyBlend:0,cursorUV:.zero,
        sourceSampling:.zero,tint:SIMD4(repeating:1),
        textureFrame0:SceneTextureUVTransform.identity.uniform0,
        textureFrame1:SceneTextureUVTransform.identity.uniform1)
 }
}
// captureSource's optional image-lighting route is outside this probe. If a
// fixture accidentally selects it, fail rather than emulate a lit algorithm.
struct UnusedLitPipeline {
 func bind(encoder:MTLRenderCommandEncoder) {fatalError("unexpected lit-image route")}
 func drawLayer(texture:MTLTexture,normalTexture:MTLTexture?,materialMapTexture:MTLTexture?,
  environmentTexture:MTLTexture?,mvp:simd_float4x4,uniforms:SceneLayerFragmentUniforms,
  litPayload:Int,encoder:MTLRenderCommandEncoder) {fatalError("unexpected lit-image route")}
}
struct SceneBaseMaterialLitCapturePayload {
 var pipeline:UnusedLitPipeline {fatalError("unexpected lit-image route")}
 var normalTexture:MTLTexture? {nil};var materialMapTexture:MTLTexture? {nil}
 var environmentTexture:MTLTexture? {nil};var lights:Int {0}
 func resolvingEnvironment(for texture:MTLTexture,commandBuffer:MTLCommandBuffer)->Self? {fatalError("unexpected lit-image route")}
 func validated(for texture:MTLTexture)->Self? {fatalError("unexpected lit-image route")}
}
'''


def typecheck_dependency_support():
    parent=os.environ.get('MWX_NAMED_MODEL_SHADOW_EVIDENCE')
    work=Path(tempfile.mkdtemp(prefix='named-dependency-typecheck-',dir=parent))
    source=work/'Harness.swift';source.write_text(dependency_support()+'\n@main enum Probe {static func main(){}}\n')
    result=subprocess.run(['xcrun','swiftc','-typecheck','-module-cache-path',str(work/'cache'),
                           *map(str,DEPENDENCY_SOURCES),str(source)],capture_output=True,text=True)
    (work/'compile.log').write_text(result.stdout+result.stderr)
    print(work,flush=True)
    print(result.stderr)
    return result.returncode

from script.tests import test_scene_directional_shadow_frame_owner as frame_fixture
from script.tests import test_scene_offscreen_texture_pool as pool_fixture
from script.tests.test_scene_resolved_material_runtime_bridge import RESOURCE_PHASE_UNAVAILABLE_HANDLE_SUPPORT

ORDERED_SOURCES=list(dict.fromkeys([*DEPENDENCY_SOURCES,*frame_fixture.SOURCES]))


def ordered_support():
    dep=dependency_support()
    a=dep.index('enum SceneEffectSourceExtentContract');b=dep.index('struct SceneGeometryProduct',a)
    dep=dep[:a]+dep[b:]
    descriptor=frame_fixture.SHELL.split('struct SceneLayerDisplayScriptOwnership',1)[1].split('struct SceneFrameContext',1)[0]
    descriptor='struct SceneLayerDisplayScriptOwnership'+descriptor
    descriptor=descriptor.replace('var utilityLayer:Bool? = false','var utilityLayer:SceneUtilityLayer? = nil')
    descriptor=descriptor.replace('var colorBlendMode:Int? = nil','var colorBlendMode:Int? = nil\n  var colorRGB:[Double]? = nil; var clampUVs:Bool? = nil; var noInterpolation:Bool? = nil\n  struct Effect {let visible:Bool?}; var effects:[Effect]=[]')
    descriptor=descriptor.replace(' let lighting:LightingDescriptor?;let layers:[Layer];let renderOrderLayerIDs:[Int]',
        ' struct ColorTargetFormat {let metalPixelFormat:MTLPixelFormat = .bgra8Unorm}\n'
        ' let colorTargetFormat=ColorTargetFormat();var lighting:LightingDescriptor? = nil\n'
        ' let layers:[Layer];var renderOrderLayerIDs:[Int]=[]\n'
        ' var bindings:[Int:SceneDependencyRenderPlan.Binding]=[:]\n'
        ' var graphOutputProviderLayerIDs:Set<Int>=[]\n'
        ' var aggregates:[Int:SceneDependencyRenderPlan.MultiProviderAggregate]=[:]\n'
        ' var staticModelConsumerProviders:[Int:Int]=[:]')
    start=dep.index('struct SceneRenderDescriptor');end=dep.index('struct SceneDependencyRenderPlan',start)
    dep=dep[:start]+descriptor+dep[end:]
    # Real offscreen pool sources supply the residency pin type.
    a=dep.index('final class SceneGraphRenderTargetResidencyPin');b=dep.index('extension SceneLayerFragmentUniforms',a)
    dep=dep[:a]+dep[b:]
    prepared=frame_fixture.SHELL.split('struct SceneFrameContext',1)[1].split('struct NamedAlbedo',1)[0]
    prepared=('struct SceneFrameContext'+prepared).replace('var namedAlbedo:String? = nil','var namedAlbedo:SceneNamedTextureReference? = nil')
    group=frame_fixture.SHELL.split('struct SceneCompositionGroupFrameRuntime',1)[1].split('final class SceneMetalRenderer',1)[0]
    group=('struct SceneCompositionGroupFrameRuntime'+group).replace('struct SceneBaseImageTextureSnapshot {}','struct SceneBaseImageTextureSnapshot {let sources:[Int:FixtureSource]}')
    group=group.replace('struct FixtureImageSelection {let source:MTLTexture?}',
                        'struct FixtureImageSelection {let source:FixtureSource?}')
    stage=pool_fixture.HARNESS.split('struct SceneEffectStageExecutionPlan',1)[1].split('nonisolated enum SceneTextureLoadPurpose',1)[0]
    return dep+prepared+group+'struct SceneEffectStageExecutionPlan'+stage+ORDERED_RENDERER


_ORDERED_HARNESS=(Path(__file__).with_name('fixtures')/'SceneNamedModelShadowOrderedHarness.swift').read_text(encoding='utf-8')
_ORDERED_MAIN_OFFSET=_ORDERED_HARNESS.index('\n@main enum OrderedProbe {')
ORDERED_RENDERER=_ORDERED_HARNESS[:_ORDERED_MAIN_OFFSET]
ORDERED_MAIN=_ORDERED_HARNESS[_ORDERED_MAIN_OFFSET:]


def typecheck_ordered_support():
    parent=os.environ.get('MWX_NAMED_MODEL_SHADOW_EVIDENCE')
    work=Path(tempfile.mkdtemp(prefix='named-ordered-typecheck-',dir=parent))
    source=work/'Harness.swift';source.write_text(ordered_support()+'\n@main enum Probe {static func main(){}}\n')
    result=subprocess.run(['xcrun','swiftc','-typecheck','-module-cache-path',str(work/'cache'),
                           *map(str,ORDERED_SOURCES),str(source)],capture_output=True,text=True)
    (work/'compile.log').write_text(result.stdout+result.stderr)
    print(work,flush=True);print(result.stderr)
    return result.returncode



def typecheck_ordered_probe():
    parent=os.environ.get('MWX_NAMED_MODEL_SHADOW_EVIDENCE')
    work=Path(tempfile.mkdtemp(prefix='named-ordered-probe-typecheck-',dir=parent))
    source=work/'Harness.swift';source.write_text(ordered_support()+ORDERED_MAIN)
    result=subprocess.run(['xcrun','swiftc','-typecheck','-module-cache-path',str(work/'cache'),
                           *map(str,ORDERED_SOURCES),str(source)],capture_output=True,text=True)
    (work/'compile.log').write_text(result.stdout+result.stderr)
    print(work,flush=True);print(result.stderr)
    return result.returncode


class SceneNamedModelShadowOrderedOwnerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from script.tests.test_scene_directional_shadow import run_swift
        cls.identity=sha(__file__)
        report=run_swift(ADMISSION_SOURCES,admission_support()+ORDERED_MAIN,label='rf13-ordered',
            metal_sources=[SCENE/'Rendering/Composition/SceneImageLayer.metal',SCENE/'Rendering/Composition/SceneStaticModel.metal',SCENE/'Rendering/Composition/SceneLitImageLayer.metal'])
        if sha(__file__)!=cls.identity: raise AssertionError('test changed during execution')
        cls.rows={row['mode']:row for row in report['rows']}

    def test_cold_and_resize_keep_original_mandatory_prefix_and_retry_missing_source(self):
        for name in ['cold-prefix-quota','resize-prefix-quota']:
            with self.subTest(name=name):
                row=self.rows[name]
                self.assertEqual(row['preparedIDs'],[1]);self.assertTrue(row['namedUnvisited'])
                self.assertEqual(row['depthStates'],['ready']);self.assertEqual(row['prefixLeases'],1)
                self.assertEqual(row['physicalRejections'],1);self.assertFalse(row['shadow'])
                self.assertEqual(row['capturesPrepared'],0);self.assertEqual(row['capturesTotal'],1)
                self.assertEqual(row['pixels'],[[128,0,0,255],[0,128,0,255]])
                self.assertTrue(row['currentIdentity'] and row['completed']);self.assertIsNone(row['typedInvalid'])
                self.assertEqual((row['beforeDrawLeases'],row['afterDrawLeases']),(1,1))

    def test_complete_walk_reuses_current_publication_and_depth_for_actual_draw(self):
        row=self.rows['cold-full']
        self.assertEqual(row['preparedIDs'],[1,2]);self.assertTrue(row['shadow'])
        self.assertEqual((row['capturesPrepared'],row['capturesTotal']),(1,1))
        self.assertEqual((row['beforeDrawLeases'],row['afterDrawLeases']),(1,1))
        self.assertTrue(row['currentIdentity'] and row['completed'])
        self.assertEqual(row['pixels'],[[128,0,0,255],[0,128,0,255]])

    def test_partial_model_distinguishes_failed_attempt_from_unvisited_mesh(self):
        row=self.rows['partial-mesh']
        self.assertEqual(row['depthStates'],['ready','failed','unvisited'])
        self.assertEqual(row['physicalRejections'],1);self.assertFalse(row['shadow'])
        self.assertEqual((row['prefixLeases'],row['beforeDrawLeases'],row['afterDrawLeases']),(1,1,1))
        self.assertEqual(row['pixels'],[[128,0,0,255],[0,0,128,255]])
        self.assertTrue(row['completed']);self.assertIsNone(row['typedInvalid'])

ADMISSION_SOURCES=list(dict.fromkeys([*ORDERED_SOURCES,
 SCENE/'Rendering/Frame/SceneResolvedMaterialFramePreflight+Admission.swift',
 SCENE/'Rendering/Frame/SceneResolvedMaterialFramePreflight+LitCapture.swift',
 SCENE/'Rendering/Metal/SceneLitImageLayerPipeline.swift',
 SCENE/'Runtime/Frame/SceneStaticModelMaterialBindings.swift',
 SCENE/'Compilation/Material/SceneBaseMaterialLightingProfile.swift',
 SCENE/'Rendering/Geometry/SceneCaptureGeometry.swift',
 SCENE/'Rendering/Composition/SceneLayerColorBlendPipeline.swift',
 SCENE/'Rendering/Composition/SceneBlendModeShaderSource.swift']))


def admission_support():
    s=ordered_support()
    s=s.replace('typealias ColorBlendBinder = () -> Void','typealias ColorBlendBinder = (MTLRenderCommandEncoder, MTLTexture, simd_float4x4) -> Void')
    s=s.replace('struct SceneGeometryProduct {','struct SceneGeometryProduct {\n typealias ColorBlendBinder = (MTLRenderCommandEncoder, MTLTexture, simd_float4x4) -> Void')
    s=s.replace('enum SceneLayerColorBlendRenderer {static func supports(_ mode:Int)->Bool {fatalError("unused snapshot-demand shell")}}','')
    a=s.index('// captureSource\'s optional image-lighting route');b=s.index('struct SceneFrameContext',a)
    s=s[:a]+s[b:]
    a=s.index('enum SceneCaptureGeometryResolver');b=s.index('enum SceneTextureLoadOutcome',a)
    s=s[:a]+s[b:]
    a=s.index(' func compositionScratchDimensions(',s.index('final class SceneMetalRenderer'))
    s=s[:a]+s[s.index('\n}',a):]
    s=s.replace('enum Kind { case composition }','enum Kind { case composition, fullscreen }')
    s=s.replace('var effects:[Effect]=[]','var effects:[Effect]=[]\n  var renderSizeWH:[Float]? = nil;var puppetMeshPath:String? = nil\n  var isImageRenderable:Bool {contentKind=="image" || contentKind=="solid"}')
    s=s.replace('struct SceneFrameContext { let dynamicValues:SceneDynamicSnapshot }',
        'struct SceneFrameContext { let dynamicValues:SceneDynamicSnapshot;var cameraParallaxPosition=SIMD2<Float>.zero;var screenSize=CGSize(width:256,height:256) }')
    s=s.replace('struct SceneBaseImageTextureSnapshot {let sources:[Int:FixtureSource]}',
        'struct SceneBaseImageTextureSnapshot {let sources:[Int:FixtureSource];var geometryProducts:[Int:SceneGeometryProduct]=[:]\n func layerSourceRenderSize(for id:Int)->[Float]? {nil}}')
    s=s.replace('let candidate:SceneTextureCandidate;','let candidate:SceneTextureCandidate?;')
    s=s.replace(' let imageCompositor=SceneImageLayerCompositor()',
        ' let imageCompositor=SceneImageLayerCompositor()\n var baseMaterialProviderBindings=FixtureProfiles()\n let pipelineRepository:FixturePipelines\n let renderDescriptor:SceneRenderDescriptor')
    s=s.replace('self.device=device;staticModelResources=resources',
        'self.device=device;staticModelResources=resources;renderDescriptor=descriptor\n  pipelineRepository=FixturePipelines(litImageLayer:SceneLitImageLayerPipeline(device:device))')
    s=s.replace('struct ColorTargetFormat {let metalPixelFormat:',
        ' struct ColorTargetFormat {let metalPixelFormat:')
    s=s.replace('struct SceneResolvedMaterialFrameTargetPlan {}',
        'struct SceneResolvedMaterialFrameTargetPlan {let token:SceneResolvedMaterialExecutionCapabilityCatalog.Token;let allocation:ScenePersistentGraphTargetFramePlan}')
    return s+RESOURCE_PHASE_UNAVAILABLE_HANDLE_SUPPORT+ADMISSION_EXTRA


ADMISSION_EXTRA=(Path(__file__).with_name('fixtures')/'SceneNamedModelShadowAdmissionSupport.swift').read_text(encoding='utf-8')


def typecheck_admission_support():
    parent=os.environ.get('MWX_NAMED_MODEL_SHADOW_EVIDENCE')
    work=Path(tempfile.mkdtemp(prefix='named-admission-typecheck-',dir=parent))
    source=work/'Harness.swift';source.write_text(admission_support()+'\n@main enum Probe {static func main(){}}\n')
    result=subprocess.run(['xcrun','swiftc','-typecheck','-module-cache-path',str(work/'cache'),
                           *map(str,ADMISSION_SOURCES),str(source)],capture_output=True,text=True)
    (work/'compile.log').write_text(result.stdout+result.stderr)
    print(work,flush=True);print(result.stderr)
    return result.returncode


def admission_main():
    """Same authored resource sequence as G1, with an earlier plain receiver."""
    s=ORDERED_MAIN.replace('["cold-full","cold-prefix-quota","resize-prefix-quota","partial-mesh"]',
                           '["plain-control","reflection-normal-missing","unsupported-blend"]')
    s=s.replace('let layers:[SceneRenderDescriptor.Layer]=partial ? [.init(id:1)] : [.init(id:1),provider,.init(id:2)]',
        'var plain=SceneRenderDescriptor.Layer(id:8,contentKind:"image");if mode=="unsupported-blend" {plain.colorBlendMode = -1}\n  let layers:[SceneRenderDescriptor.Layer]=[plain,.init(id:1),provider,.init(id:2)]')
    s=s.replace('let pool=SceneOffscreenTexturePool', '''if mode=="reflection-normal-missing" {
   renderer.baseMaterialProviderBindings.lightingProfileByLayerID[8] = .init(lightingEnabled:false,
    reflection:SIMD2(1,4),normalSource:.asset(SceneAssetTextureIdentity(virtualPath:"own/missing-normal",purpose:.normal)!))
  }
  let pool=SceneOffscreenTexturePool''')
    s=s.replace('let sources=SceneBaseImageTextureSnapshot(sources:partial ? [:]:[11:source(green)])',
        'let blue=texture(d,size,[0,0,64,255])\n   let sources=SceneBaseImageTextureSnapshot(sources:[8:source(blue),11:source(green)])')
    s=s.replace('let state=SceneMetalRenderer.StaticModelFrame();var leases:', '''var plainRequest=SceneImageLayerDrawRequest(layer:plain,dynamicValues:frame.dynamicValues)
   var environmentCalls=0
   renderer.preparePlainSourceLighting(request:&plainRequest,snapshot:lighting,model:matrix_identity_float4x4,
    worldFrame:matrix_identity_float4x4,cameraFrame:camera,usesPerspective:false,
    environmentSource:{_ in environmentCalls += 1;return nil})
   let payloadMiss=plainRequest.sourceLighting == nil
   let state=SceneMetalRenderer.StaticModelFrame();var leases:''')
    s=s.replace('// Replay only the original consumer calls.', '''var screen=matrix_identity_float4x4;screen.columns.0.x=2;screen.columns.1.y=2
   let plainDrawn=SceneLayerColorBlendRenderer.draw(texture:blue,mvp:screen,uniforms:.neutral(),dependencyTexture:nil,layer:plain,pipeline:image,colorBlendPipeline:nil,mainPass:pass)
   // Replay only the original consumer calls.''')
    s=s.replace('"mode":mode,"extent":size,', '"mode":mode,"extent":size,"payloadMiss":payloadMiss,"environmentCalls":environmentCalls,"plainDrawn":plainDrawn,')
    return s


class SceneNamedModelShadowLightingAdmissionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from script.tests.test_scene_directional_shadow import run_swift
        identity=sha(__file__)
        report=run_swift(ADMISSION_SOURCES,admission_support()+admission_main(),label='rf13-admission',
            metal_sources=[SCENE/'Rendering/Composition/SceneImageLayer.metal',
                           SCENE/'Rendering/Composition/SceneStaticModel.metal',
                           SCENE/'Rendering/Composition/SceneLitImageLayer.metal'])
        if sha(__file__)!=identity: raise AssertionError('test changed during execution')
        cls.rows={row['mode']:row for row in report['rows']}

    def test_missing_normal_reflection_keeps_direct_output_and_later_model_depth(self):
        for name in ['plain-control','reflection-normal-missing','unsupported-blend']:
            with self.subTest(name=name):
                row=self.rows[name]
                self.assertTrue(row['payloadMiss'] and row['completed'])
                self.assertEqual(row['environmentCalls'],0)
                self.assertEqual(row['plainDrawn'],name!='unsupported-blend')
                self.assertEqual(row['depthStates'],['ready'])
                self.assertEqual(row['pixels'],[[128,0,0,255],[0,128,0,255]])
                self.assertEqual((row['capturesPrepared'],row['capturesTotal']),(0,1))
                self.assertEqual((row['beforeDrawLeases'],row['afterDrawLeases']),(1,1))


PUBLICATION_FUNCTIONS=r'''
 static func publication(_ d:MTLDevice,_ q:MTLCommandQueue)throws->[[String:Any]] {
  let model=SceneStaticModelPipeline(device:d)!,image=SceneImageLayerPipeline(device:d)!
  let vertices=[SIMD3<Float>(4,4,0),SIMD3(24,4,0),SIMD3(24,24,0),SIMD3(4,24,0)].map {
   SceneMdlStaticModel.Vertex(position:$0,normal:SIMD3(0,0,1),tangent:SIMD4(1,0,0,1),uv:SIMD2(repeating:0.5))}
  let mesh=model.makeMesh(vertices:vertices,indices:[0,2,1,0,3,2])!
  let named=SceneNamedTextureReference(providerLayerID:11,variant:.primary)
  let consumer=SceneRenderDescriptor.Layer(id:2)
  var provider=SceneRenderDescriptor.Layer(id:11,visible:false,contentKind:"image")
  let descriptor=SceneRenderDescriptor(layers:[provider,consumer],renderOrderLayerIDs:[11,2],staticModelConsumerProviders:[2:11])
  let entry=ScenePreparedStaticModelResources.Entry(materialPath:"materials/unseen/runtime.json",dynamicMaterialPath:"",geometryIdentity:"quad",mesh:mesh,albedo:nil,namedAlbedo:named,material:material(SIMD3(repeating:1)))
  let renderer=SceneMetalRenderer(device:d,resources:.init(pipeline:model,entries:[2:[entry]]),descriptor:descriptor)
  let camera=SceneParticleCameraFrame(camera:descriptor.camera,viewportSize:CGSize(width:64,height:64))
  let lighting=SceneLightSnapshot(ambient:SIMD3(repeating:1),skylight:.zero,directional:[],point:[],spot:[],overflowCount:0)
  let green=texture(d,64,[0,255,0,255]),blue=texture(d,64,[0,0,255,255])
  var rows:[[String:Any]]=[]
  for (index,alpha) in [0.5,1.0,0.0,1.0].enumerated() {
   provider.alpha=alpha
   let cb=q.makeCommandBuffer()!,output=texture(d,64,[0,0,0,255])
   let pass=SceneMainPassEncoder(commandBuffer:cb,target:output,clearColor:MTLClearColorMake(0,0,0,1),clearEnabled:true)
   let epoch=renderer.textureRegistry.beginFrame(frameIndex:UInt64(index+1),layerSources:[:])
   let frame=SceneFrameContext(dynamicValues:.empty(frameIndex:UInt64(index+1),generation:1))
   let input=index==1 ? blue:green
   let sources=SceneBaseImageTextureSnapshot(sources:[11:source(input)])
   let count=captures()
   func capture(_ sourceTexture:MTLTexture)->SceneGraphOutputPublicationResult? {
    renderer.captureRawDependencyProvider(layer:provider,source:source(sourceTexture),imageTextures:sources,imagePipeline:image,
     frameContext:frame,worldFrames:[:],cameraFrame:camera,parallax:.init(),viewportSize:CGSize(width:64,height:64),mainPass:pass)
   }
   precondition(capture(input) == .published)
   let current=renderer.textureRegistry.completeNamedLayerTargetTexture(reference:named,frameEpoch:epoch)!
   precondition(capture(index==1 ? green:blue) == .published)
   let draws=renderer.staticModelDraws(layer:consumer,worldFrames:[:],snapshot:frame.dynamicValues,requiresCompleteNamedInputs:true)!
   let same=draws.count==1 && draws[0].texture === current && draws[0].premultiplied
   let state=SceneMetalRenderer.StaticModelFrame();var leases:[SceneParticleDepthTargetLease]=[]
   _=renderer.drawStaticModel(layer:consumer,state:state,worldFrames:[:],frameContext:frame,cameraFrame:camera,lighting:lighting,pass:pass,commandBuffer:cb,leases:&leases)
   precondition(pass.finishEnsuringClear());for lease in leases {lease.arm(on:cb)}
   let readback=texture(d,64,[0,0,0,0]),blit=cb.makeBlitCommandEncoder()!
   blit.copy(from:current,sourceSlice:0,sourceLevel:0,sourceOrigin:MTLOrigin(x:0,y:0,z:0),sourceSize:MTLSize(width:64,height:64,depth:1),to:readback,destinationSlice:0,destinationLevel:0,destinationOrigin:MTLOrigin(x:0,y:0,z:0));blit.endEncoding()
   cb.commit();cb.waitUntilCompleted();precondition(cb.status == .completed)
   var a=[UInt8](repeating:0,count:4),b=a
   readback.getBytes(&a,bytesPerRow:4,from:MTLRegionMake2D(32,32,1,1),mipmapLevel:0)
   output.getBytes(&b,bytesPerRow:4,from:MTLRegionMake2D(12,12,1,1),mipmapLevel:0)
   if index==1 {renderer.textureRegistry.discardFramePublication()} else {renderer.textureRegistry.commitFramePublication()}
   rows.append(["frame":index+1,"epoch":epoch,"alpha":alpha,"sameCurrent":same,"copies":captures()-count,
    "captureRGBA":[a[2],a[1],a[0],a[3]],"modelRGBA":[b[2],b[1],b[0],b[3]],"cancelled":index==1,"completed":true])
  }
  return rows
 }
 static func background(_ d:MTLDevice,_ q:MTLCommandQueue)throws->[String:Any] {
  let model=SceneStaticModelPipeline(device:d)!,image=SceneImageLayerPipeline(device:d)!
  var provider=SceneRenderDescriptor.Layer(id:11,visible:false,contentKind:"image")
  provider.utilityLayer = .init(kind:.composition)
  let slot=SceneEffectPassSlot(effectID:"own",passIndex:0,slotIndex:0)
  let binding=SceneDependencyRenderPlan.Binding(consumerLayerID:99,providerLayerID:11,slot:slot,blendMode:0,kind:.resolvedMaterial)
  var second=SceneRenderDescriptor.Layer(id:12,visible:false,contentKind:"image");second.utilityLayer = .init(kind:.composition)
  let binding2=SceneDependencyRenderPlan.Binding(consumerLayerID:100,providerLayerID:12,slot:slot,blendMode:0,kind:.resolvedMaterial)
  let descriptor=SceneRenderDescriptor(layers:[provider,second],renderOrderLayerIDs:[11,12],bindings:[99:binding,100:binding2])
  let renderer=SceneMetalRenderer(device:d,resources:.init(pipeline:model,entries:[:]),descriptor:descriptor)
  let camera=SceneParticleCameraFrame(camera:descriptor.camera,viewportSize:CGSize(width:64,height:64))
  let light=SceneLightSnapshot.Directional(layerID:3,castsShadow:true,directionTowardLight:SIMD3(0,0,1),color:SIMD3(repeating:1),intensity:1)
  let lighting=SceneLightSnapshot(ambient:.zero,skylight:.zero,directional:[light],point:[],spot:[],overflowCount:0)
  let red=texture(d,64,[255,0,0,255]),blue=texture(d,64,[0,0,255,255]),green=texture(d,64,[0,255,0,255])
  let output=texture(d,64,[0,0,0,255]),cb=q.makeCommandBuffer()!
  let pass=SceneMainPassEncoder(commandBuffer:cb,target:output,clearColor:MTLClearColorMake(0,0,0,1),clearEnabled:true)
  var screen=matrix_identity_float4x4;screen.columns.0.x=2;screen.columns.1.y=2
  func paint(_ texture:MTLTexture) {let e=pass.encoder()!;image.bind(encoder:e);image.drawLayer(texture:texture,mvp:screen,uniforms:.neutral(),encoder:e)}
  let epoch=renderer.textureRegistry.beginFrame(frameIndex:1,layerSources:[:]),ref=SceneNamedTextureReference(providerLayerID:11,variant:.primary)
  let frame=SceneFrameContext(dynamicValues:.empty(frameIndex:1,generation:1)),sources=SceneBaseImageTextureSnapshot(sources:[:])
  let state=SceneMetalRenderer.StaticModelFrame(),pool=SceneOffscreenTexturePool(device:d,pixelFormat:.bgra8Unorm,residentByteBudget:8*1024*1024)
  var leases:[SceneParticleDepthTargetLease]=[]
  paint(red);let before=captures()
  let invalid=renderer.prepareOrderedModelShadow(state:state,lights:[.directional(light)],lighting:lighting,orderedLayers:[provider,second],visible:[],activeNamedModels:[],forwardGraphProviders:[],framePlans:[:],imageTextures:sources,imagePipeline:image,frameContext:frame,worldFrames:[11:screen,12:screen],cameraFrame:camera,parallax:.init(),viewportSize:CGSize(width:64,height:64),batches:[:],particlePipeline:nil,mainPass:pass,groups:nil,utilityExecution:renderer.utilityExecution,pool:pool,commandBuffer:cb,leases:&leases,terminalCapacity:{true},recordsEvidence:false)
  let early=captures()-before,earlyPublication=renderer.textureRegistry.completeNamedLayerTargetTexture(reference:ref,frameEpoch:epoch) != nil
  paint(blue)
  func capture(_ layer:SceneRenderDescriptor.Layer)->SceneGraphOutputPublicationResult? {renderer.captureRawDependencyProvider(layer:layer,source:nil,imageTextures:sources,imagePipeline:image,frameContext:frame,worldFrames:[11:screen,12:screen],cameraFrame:camera,parallax:.init(),viewportSize:CGSize(width:64,height:64),mainPass:pass)}
  precondition(capture(provider) == .published)
  let actual=renderer.textureRegistry.completeNamedLayerTargetTexture(reference:ref,frameEpoch:epoch)!
  paint(green);precondition(capture(provider) == .published);precondition(capture(second) == .published)
  let secondTexture=renderer.textureRegistry.completeNamedLayerTargetTexture(reference:.init(providerLayerID:12,variant:.primary),frameEpoch:epoch)!
  precondition(pass.finishEnsuringClear())
  let readback=texture(d,64,[0,0,0,0]),readback2=texture(d,64,[0,0,0,0]),blit=cb.makeBlitCommandEncoder()!
  blit.copy(from:actual,sourceSlice:0,sourceLevel:0,sourceOrigin:MTLOrigin(x:0,y:0,z:0),sourceSize:MTLSize(width:64,height:64,depth:1),to:readback,destinationSlice:0,destinationLevel:0,destinationOrigin:MTLOrigin(x:0,y:0,z:0))
  blit.copy(from:secondTexture,sourceSlice:0,sourceLevel:0,sourceOrigin:MTLOrigin(x:0,y:0,z:0),sourceSize:MTLSize(width:64,height:64,depth:1),to:readback2,destinationSlice:0,destinationLevel:0,destinationOrigin:MTLOrigin(x:0,y:0,z:0));blit.endEncoding()
  cb.commit();cb.waitUntilCompleted();precondition(cb.status == .completed)
  var a=[UInt8](repeating:0,count:4),b=a,c=a
  readback.getBytes(&a,bytesPerRow:4,from:MTLRegionMake2D(32,32,1,1),mipmapLevel:0)
  output.getBytes(&b,bytesPerRow:4,from:MTLRegionMake2D(32,32,1,1),mipmapLevel:0)
  readback2.getBytes(&c,bytesPerRow:4,from:MTLRegionMake2D(32,32,1,1),mipmapLevel:0)
  renderer.textureRegistry.commitFramePublication()
  return ["invalid":invalid as Any? ?? NSNull(),"earlyCopies":early,"earlyPublication":earlyPublication,
   "secondRGBA":[c[2],c[1],c[0],c[3]],"totalCopies":captures()-before,"capturedRGBA":[a[2],a[1],a[0],a[3]],"finalRGBA":[b[2],b[1],b[0],b[3]],"completed":true]
 }
'''

def publication_main():
    helpers=ORDERED_MAIN[ORDERED_MAIN.index(' static func texture('):ORDERED_MAIN.index(' static func run(')]
    return r'''
@main enum PublicationProbe {
 static func main() throws {
  guard let d=MTLCreateSystemDefaultDevice(),let q=d.makeCommandQueue() else {print("{\"metalUnavailable\":true}");return}
  let report:[String:Any] = ["publication":try publication(d,q),"background":try background(d,q)]
  print(String(decoding:try JSONSerialization.data(withJSONObject:report),as:UTF8.self))
 }
'''+helpers+PUBLICATION_FUNCTIONS+'}\n'


class SceneNamedModelShadowPublicationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from script.tests.test_scene_directional_shadow import run_swift
        identity=sha(__file__)
        cls.report=run_swift(ADMISSION_SOURCES,admission_support()+publication_main(),label='rf13-publication',
            metal_sources=[SCENE/'Rendering/Composition'/name for name in
                ['SceneImageLayer.metal','SceneStaticModel.metal','SceneLitImageLayer.metal']])
        if sha(__file__)!=identity: raise AssertionError('test changed during execution')

    def test_same_current_alpha_once_next_frame_and_cancel_do_not_leak(self):
        rows=self.report['publication']
        self.assertEqual(len(rows),4)
        self.assertEqual(len({r['epoch'] for r in rows}),4)
        expected=[[0,128,0,128],[0,0,255,255],[0,0,0,0],[0,255,0,255]]
        for row,rgba in zip(rows,expected):
            with self.subTest(frame=row['frame']):
                self.assertTrue(row['completed'] and row['sameCurrent'])
                self.assertEqual(row['copies'],1)
                self.assertEqual(row['captureRGBA'],rgba)
                self.assertEqual(row['modelRGBA'],[round(c*0.5) for c in rgba[:3]]+[255])
        self.assertEqual([r['cancelled'] for r in rows],[False,True,False,False])

    def test_normal_provider_prepares_capacity_but_copies_original_authored_background(self):
        row=self.report['background']
        self.assertIsNone(row['invalid']);self.assertTrue(row['completed'])
        self.assertEqual(row['earlyCopies'],0);self.assertFalse(row['earlyPublication'])
        self.assertEqual(row['totalCopies'],2)
        self.assertEqual(row['secondRGBA'],[0,255,0,255])
        self.assertEqual(row['capturedRGBA'],[0,0,255,255])
        self.assertEqual(row['finalRGBA'],[0,255,0,255])

def mixed_support():
    s=admission_support()
    a=s.index('final class SceneImageLayerCompositor {');b=s.index('\n}\n',a)+3
    s=s[:a]+r'''
final class SceneImageLayerCompositor {
 let color:SceneLayerColorBlendPipeline
 init(device:MTLDevice) {
  let fogSource=try! String(contentsOfFile:__FOG_HEADER_PATH__,encoding:.utf8)
  color=SceneLayerColorBlendPipeline(device:device,state:SceneLayerColorBlendPipelineState(device:device,fogShaderSource:fogSource)!)
 }
 func prepareSnapshotCapacity(width:Int,height:Int,pixelFormat:MTLPixelFormat,then remaining:()->Bool)->Bool {
  color.framebufferSnapshot.prepareCapacity(width:width,height:height,pixelFormat:pixelFormat,then:remaining)
 }
}
'''+s[b:]
    s=s.replace('let imageCompositor=SceneImageLayerCompositor()','let imageCompositor:SceneImageLayerCompositor')
    s=s.replace('self.device=device;staticModelResources=resources;', 'self.device=device;staticModelResources=resources;imageCompositor=SceneImageLayerCompositor(device:device);')
    return s.replace('__FOG_HEADER_PATH__',json.dumps(str(SCENE/'Rendering/Composition/SceneDistanceFog.metalh')))

def mixed_main():
    from script.tests import test_scene_snapshot_capacity as previous
    s=previous.FRAME_MAIN
    # Reuse the established original encoders and output oracle. Only replace
    # the batch preparation call with the actual ordered owner under test.
    s=s.replace('let renderer=SceneMetalRenderer(device:d,resources:.init(pipeline:model,entries:[1:[entry]]))',
      'let descriptor=SceneRenderDescriptor(layers:[])\n  let renderer=SceneMetalRenderer(device:d,resources:.init(pipeline:model,entries:[1:[entry]]),descriptor:descriptor)')
    s=s.replace('let plans:[Int:SceneResolvedMaterialFrameTargetPlan]=utility ? [7:.init()]:[6:.init()]',r'''
  // Membership-only prepared-input marker; it never reaches a graph resource owner.
  let markerLayerID=utility ? 7:6
  let markerSource=SceneAuthoredEffectRenderPlan.TextureIdentity(kind:.layerSource,layerID:markerLayerID,effect:nil,name:nil)
  let markerAllocation=ScenePersistentGraphTargetFramePlan(residencyDomainID:UUID(),graphPlan:.init(
    key:.init(layerID:markerLayerID,effects:[],pairStorage:.owned),
    pairPlan:.init(layerID:markerLayerID,baseCaptureIdentity:markerSource,baseCaptureMember:.zero,
      transitionCount:0,effects:[],terminalMember:.zero,terminalOutputIdentity:markerSource),
    fullFramePair:.init(descriptor:.init(extent:.init(width:target.width,height:target.height),
      format:.rgbaBackbuffer,addressMode:.clampToEdge),zeroSlot:0,oneSlot:1),
    pairStorage:.owned,stages:[],slots:[],residentByteCost:0,historyByteCost:0),orderingContext:nil)
  let plans:[Int:SceneResolvedMaterialFrameTargetPlan]=utility
    ? [7:.init(token:.init(),allocation:markerAllocation)]
    : [6:.init(token:.init(),allocation:markerAllocation)]
''')
    a=s.index('  let candidates=renderer.shadowDrawCandidates(');b=s.index('  let noCopy=',a)
    s=s[:a]+r'''
  var terminalCalled=false
  let image=SceneImageLayerPipeline(device:d)!
  let error=renderer.prepareOrderedModelShadow(state:state,lights:[.directional(light)],lighting:lighting,orderedLayers:layers,visible:visible,
    activeNamedModels:[],forwardGraphProviders:[],framePlans:plans,imageTextures:.init(sources:[:]),imagePipeline:image,
    frameContext:context,worldFrames:world,cameraFrame:camera,parallax:.init(),viewportSize:CGSize(width:64,height:64),
    batches:batches,particlePipeline:particle,mainPass:pass,groups:nil,utilityExecution:renderer.utilityExecution,pool:pool,commandBuffer:cb,leases:&leases,
    terminalCapacity:{terminalCalled=true;return true},recordsEvidence:false)
  precondition(error == nil)
  let capacity=terminalCalled
'''+s[b:]
    s=s.replace('["normal","optional-quota","utility-trigger","hidden-no-demand"]',
                '["normal","optional-quota","utility-trigger","hidden-no-demand","color-prefix-failure","particle-prefix-failure","utility-prefix-failure","terminal-bloom-failure"]')
    s=s.replace('let utility=mode=="utility-trigger"', 'let utility=mode=="utility-trigger" || mode=="utility-prefix-failure"')
    s=s.replace('depthTestEnabled:false,depthWriteEnabled:false','depthTestEnabled:true,depthWriteEnabled:true')
    s=s.replace('if mode=="optional-quota" {','if mode=="optional-quota" || mode.hasSuffix("failure") {')
    s=s.replace('let mandatory=d.heapTextureSizeAndAlign(descriptor:td).size+2*d.heapTextureSizeAndAlign(descriptor:sd).size',
        '''let depthCost=d.heapTextureSizeAndAlign(descriptor:td).size,snapshotCost=d.heapTextureSizeAndAlign(descriptor:sd).size
   let mandatory:Int
   switch mode {
   case "color-prefix-failure","utility-prefix-failure": mandatory=depthCost
   case "particle-prefix-failure": mandatory=depthCost+snapshotCost
   default: mandatory=2*depthCost+2*snapshotCost
   }''')
    s=s.replace('var terminalCalled=false','''let bloom=SceneBloomPostProcess(device:d,pixelFormat:.bgra8Unorm)!
  let bloomConfig=SceneBloomConfiguration(enabled:true,strength:0.5,threshold:2,tint:SIMD3(repeating:1))
  var terminalCalled=false,terminalReady=true''')
    s=s.replace('terminalCapacity:{terminalCalled=true;return true}',
        'terminalCapacity:{terminalCalled=true;if mode=="terminal-bloom-failure" {terminalReady=bloom.prepareCapacity(configuration:bloomConfig,source:target)};return terminalReady}')
    s=s.replace('let published = !state.shadows.isEmpty','let published = !state.shadows.isEmpty\n  let prefixLeases=leases.count\n  if held>0 && mode != "optional-quota" {SceneResourceBudget.shared.release(held,kind:.gpu);held=0}')
    s=s.replace('commandBuffer:cb,performanceObservations:&observed)', 'commandBuffer:cb,preparedDepth:state.particleDepth[42],performanceObservations:&observed)')
    s=s.replace('precondition(pass.finishEnsuringClear());leases.forEach',
        'precondition(pass.finishEnsuringClear());var bloomEncoded=false;if mode=="terminal-bloom-failure" {bloomEncoded=bloom.encode(configuration:bloomConfig,source:target,commandBuffer:cb)};leases.forEach')
    s=s.replace('"mode":mode,"capacity":capacity,','"mode":mode,"capacity":capacity,"terminalReady":terminalReady,"bloomEncoded":bloomEncoded,"prefixLeases":prefixLeases,')
    return s


class SceneNamedModelShadowMixedOwnerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from script.tests.test_scene_directional_shadow import run_swift
        identity=sha(__file__)
        cls.report=run_swift([*ADMISSION_SOURCES,SCENE/'Rendering/Composition/SceneBloomPostProcess.swift'],mixed_support()+mixed_main(),label='rf13-mixed',
            metal_sources=[SCENE/'Rendering/Composition'/name for name in
                ['SceneImageLayer.metal','SceneStaticModel.metal','SceneLitImageLayer.metal','SceneBloomPostProcess.metal']])
        if sha(__file__)!=identity: raise AssertionError('test changed during execution')
        cls.rows={row['mode']:row for row in cls.report['rows']}

    def test_ordered_color_and_refraction_capacity_preserves_original_consumption(self):
        normal=self.rows['normal'];limited=self.rows['optional-quota']
        for row in [normal,limited]:
            for key in ['capacity','noEarlyCopy','modelDraw']:self.assertTrue(row[key],row)
            self.assertEqual(row['colorBytes'],64*64*4);self.assertEqual(row['particleBytes'],64*64*4)
            self.assertEqual(row['refractionDraws'],1);self.assertEqual(row['copies'],2)
        self.assertTrue(normal['shadow']);self.assertFalse(limited['shadow'])
        self.assertEqual(limited['pixels'],normal['pixels'])
        self.assertEqual(normal['pixels'][0],[102,0,0,255]);self.assertEqual(normal['pixels'][1],[0,64,0,255])

    def test_ordered_utility_trigger_and_hidden_consumer_keep_original_snapshot_owner(self):
        row=self.rows['utility-trigger'];self.assertTrue(row['capacity']);self.assertTrue(row['shadow'])
        self.assertEqual(row['colorBytes'],64*64*4);self.assertEqual(row['particleBytes'],0)
        self.assertEqual(row['copies'],1);self.assertEqual(row['pixels'][1],[0,64,0,255])
        hidden=self.rows['hidden-no-demand'];self.assertTrue(hidden['shadow'])
        self.assertEqual((hidden['colorBytes'],hidden['particleBytes'],hidden['copies']),(0,0,0))

    def test_middle_capacity_failures_keep_actual_prefix_and_original_retry_radius(self):
        for name in ['color-prefix-failure','utility-prefix-failure','particle-prefix-failure']:
            row=self.rows[name]
            self.assertFalse(row['capacity']);self.assertFalse(row['shadow'])
            self.assertTrue(row['noEarlyCopy'] and row['modelDraw'])
            self.assertEqual(row['prefixLeases'],1)
            self.assertEqual(row['pixels'][0],[102,0,0,255])
            self.assertEqual(row['pixels'][1],[0,64,0,255])
        self.assertEqual(self.rows['color-prefix-failure']['colorBytes'],0)
        self.assertEqual(self.rows['utility-prefix-failure']['colorBytes'],0)
        row=self.rows['particle-prefix-failure']
        self.assertEqual(row['colorBytes'],64*64*4);self.assertEqual(row['particleBytes'],0)
        self.assertEqual(row['refractionDraws'],0);self.assertEqual(row['copies'],1)

    def test_terminal_bloom_failure_preserves_mandatory_consumers_and_later_original_encode(self):
        row=self.rows['terminal-bloom-failure']
        self.assertTrue(row['capacity']);self.assertFalse(row['terminalReady']);self.assertFalse(row['shadow'])
        self.assertTrue(row['bloomEncoded'] and row['noEarlyCopy'] and row['modelDraw'])
        self.assertEqual(row['prefixLeases'],2);self.assertEqual(row['refractionDraws'],1)
        self.assertEqual(row['copies'],2);self.assertEqual(row['pixels'],self.rows['normal']['pixels'])


NAMED_RECEIVER_FUNCTIONS=r'''

 static func namedReceivers(_ mode:String,_ d:MTLDevice,_ q:MTLCommandQueue)throws->[String:Any] {
  let model=SceneStaticModelPipeline(device:d)!,image=SceneImageLayerPipeline(device:d)!
  func quad(_ x:Float,_ y:Float,_ width:Float,_ height:Float,_ z:Float)->SceneStaticModelMesh {
   let positions=[SIMD3(x,y,z),SIMD3(x+width,y,z),SIMD3(x+width,y+height,z),SIMD3(x,y+height,z)]
   return model.makeMesh(vertices:positions.map{.init(position:$0,normal:SIMD3(0,0,1),tangent:SIMD4(1,0,0,1),uv:SIMD2(repeating:0.5))},indices:[0,2,1,0,3,2])!
  }
  let reference=SceneNamedTextureReference(providerLayerID:11,variant:.primary)
  let provider=SceneRenderDescriptor.Layer(id:11,visible:false,contentKind:"image")
  let caster=SceneRenderDescriptor.Layer(id:1,modelShadowCastIntent:mode=="no-caster" ? .disabled:.enabled)
  let receiverA=SceneRenderDescriptor.Layer(id:2,modelShadowCastIntent:.disabled)
  let receiverB=SceneRenderDescriptor.Layer(id:3,modelShadowCastIntent:.disabled)
  let layers=[caster,provider,receiverA,receiverB]
  let descriptor=SceneRenderDescriptor(layers:layers,renderOrderLayerIDs:layers.map(\.id),staticModelConsumerProviders:[2:11,3:11])
  let white=texture(d,1,[255,255,255,255])
  func entry(_ mesh:SceneStaticModelMesh,_ key:String,_ isNamed:Bool)->ScenePreparedStaticModelResources.Entry {
   .init(materialPath:"materials/unseen/runtime.json",dynamicMaterialPath:"",geometryIdentity:key,mesh:mesh,
    albedo:isNamed ? nil:PreparedTexture(texture:white),namedAlbedo:isNamed ? reference:nil,material:material(SIMD3(repeating:1)))
  }
  let entries=[1:[entry(quad(20,20,16,24,10),"caster",false)],
               2:[entry(quad(0,0,64,32,0),"receiver-a",true)],
               3:[entry(quad(0,32,64,32,0),"receiver-b",true)]]
  let renderer=SceneMetalRenderer(device:d,resources:.init(pipeline:model,entries:entries),descriptor:descriptor)
  let pool=SceneOffscreenTexturePool(device:d,pixelFormat:.bgra8Unorm,residentByteBudget:16*1024*1024)
  let light=SceneLightSnapshot.Directional(layerID:7,castsShadow:true,directionTowardLight:SIMD3(1,0,1),color:SIMD3(repeating:1),intensity:0.5)
  let lighting=SceneLightSnapshot(ambient:SIMD3(repeating:0.2),skylight:.zero,directional:[light],point:[],spot:[],overflowCount:0)
  let camera=SceneParticleCameraFrame(camera:descriptor.camera,viewportSize:CGSize(width:64,height:64))
  let frame=SceneFrameContext(dynamicValues:.empty(frameIndex:1,generation:1))
  let green=texture(d,64,[0,255,0,255]),output=texture(d,64,[0,0,0,255])
  let sources=SceneBaseImageTextureSnapshot(sources:[11:source(green)])
  let epoch=renderer.textureRegistry.beginFrame(frameIndex:1,layerSources:[:])
  let cb=q.makeCommandBuffer()!,event=d.makeSharedEvent()!
  if mode=="flight" {cb.encodeWaitForEvent(event,value:1)}
  let pass=SceneMainPassEncoder(commandBuffer:cb,target:output,clearColor:MTLClearColorMake(0,0,0,1),clearEnabled:true)
  let state=SceneMetalRenderer.StaticModelFrame();var leases:[SceneParticleDepthTargetLease]=[]
  let before=captures()
  let invalid=renderer.prepareOrderedModelShadow(state:state,lights:[.directional(light)],lighting:lighting,orderedLayers:layers,
   visible:[1,2,3],activeNamedModels:[2,3],forwardGraphProviders:[],framePlans:[:],imageTextures:sources,imagePipeline:image,
   frameContext:frame,worldFrames:[:],cameraFrame:camera,parallax:.init(),viewportSize:CGSize(width:64,height:64),
   batches:[:],particlePipeline:nil,mainPass:pass,groups:nil,utilityExecution:renderer.utilityExecution,pool:pool,commandBuffer:cb,leases:&leases,
   terminalCapacity:{true},recordsEvidence:false)
  let shadowCreated = !state.shadows.isEmpty
  let current=renderer.textureRegistry.completeNamedLayerTargetTexture(reference:reference,frameEpoch:epoch)!
  let sharedCurrent=[2,3].allSatisfy{state.prepared?[$0]?.first?.texture === current}
  let noReceiverCast=[receiverA,receiverB].allSatisfy{$0.modelShadowCastIntent == .disabled}
  let depthBefore=leases.count
  var drawn:[Bool]=[]
  for layer in [caster,receiverA,receiverB] {
   drawn.append(renderer.drawStaticModel(layer:layer,state:state,worldFrames:[:],frameContext:frame,cameraFrame:camera,
    lighting:lighting,pass:pass,commandBuffer:cb,leases:&leases))
  }
  // The original provider visit must reuse the current completed publication.
  precondition(renderer.captureRawDependencyProvider(layer:provider,source:source(green),imageTextures:sources,imagePipeline:image,
   frameContext:frame,worldFrames:[:],cameraFrame:camera,parallax:.init(),viewportSize:CGSize(width:64,height:64),mainPass:pass) == .published)
  precondition(pass.finishEnsuringClear())
  let readback=texture(d,64,[0,0,0,0]),blit=cb.makeBlitCommandEncoder()!
  blit.copy(from:current,sourceSlice:0,sourceLevel:0,sourceOrigin:MTLOrigin(x:0,y:0,z:0),sourceSize:MTLSize(width:64,height:64,depth:1),to:readback,destinationSlice:0,destinationLevel:0,destinationOrigin:MTLOrigin(x:0,y:0,z:0));blit.endEncoding()
  let capturedOnce=captures()-before
  let originalShadowBytes=pool.residentByteCost
  let oldDepth=leases.first!.texture
  state.arm(on:cb);for lease in leases {lease.arm(on:cb)};pass.armCompositionPins()
  renderer.textureRegistry.commitFramePublication()
  let completion=DispatchSemaphore(value:0)
  cb.addCompletedHandler{_ in completion.signal()}
  cb.commit()
  var flight:[String:Any]=[:]
  if mode=="flight" {
   // No waitUntilScheduled: the hardware wait guarantees no completion until
   // the CPU releases the shared event, without sleeping or timing assumptions.
   defer {event.signaledValue=1}
   let pending=cb.status != .completed && cb.status != .error
   state.prepared=nil
   pool.reset()
   let retainedAfterReset=pool.residentByteCost
   let size=128,newOutput=texture(d,size,[0,0,0,255]),blue=texture(d,size,[0,0,255,255])
   let cancelledCB=q.makeCommandBuffer()!
   let cancelledPass=SceneMainPassEncoder(commandBuffer:cancelledCB,target:newOutput,clearColor:MTLClearColorMake(0,0,0,1),clearEnabled:true)
   let nextEpoch=renderer.textureRegistry.beginFrame(frameIndex:2,layerSources:[:])
   let nextFrame=SceneFrameContext(dynamicValues:.empty(frameIndex:2,generation:1))
   let nextState=SceneMetalRenderer.StaticModelFrame();var nextLeases:[SceneParticleDepthTargetLease]=[]
   let nextSources=SceneBaseImageTextureSnapshot(sources:[11:source(blue)])
   let nextInvalid=renderer.prepareOrderedModelShadow(state:nextState,lights:[.directional(light)],lighting:lighting,orderedLayers:layers,
    visible:[1,2,3],activeNamedModels:[2,3],forwardGraphProviders:[],framePlans:[:],imageTextures:nextSources,imagePipeline:image,
    frameContext:nextFrame,worldFrames:[:],cameraFrame:camera,parallax:.init(),viewportSize:CGSize(width:size,height:size),
    batches:[:],particlePipeline:nil,mainPass:cancelledPass,groups:nil,utilityExecution:renderer.utilityExecution,pool:pool,commandBuffer:cancelledCB,leases:&nextLeases,
    terminalCapacity:{true},recordsEvidence:false)
   let resized=renderer.textureRegistry.completeNamedLayerTargetTexture(reference:reference,frameEpoch:nextEpoch)!
   let newShadow = !nextState.shadows.isEmpty
   let independentDepth=nextLeases.first!.texture !== oldDepth
   let cancelledDepth=nextLeases.first!.texture
   cancelledPass.closeForOffscreen();cancelledPass.cancelCompositionPins()
   nextState.cancel();nextState.prepared=nil;nextLeases.forEach{$0.cancel()}
   renderer.textureRegistry.discardFramePublication();pool.reset()
   let afterCancel=pool.residentByteCost
   let reused=renderer.staticModelDepthTargetPool.acquire(device:d,width:size,height:size)!
   let cancelledDepthReusable=reused.texture === cancelledDepth;reused.cancel()
   flight=["pending":pending,"originalShadowBytes":originalShadowBytes,"retainedAfterReset":retainedAfterReset,
    "retainedAfterCancel":afterCancel,"nextInvalid":nextInvalid as Any? ?? NSNull(),"nextShadow":newShadow,
    "resizedNamed":resized !== current && resized.width==128 && current.width==64,
    "independentDepth":independentDepth,"cancelledDepthReusable":cancelledDepthReusable,
    "cancelledCBNotSubmitted":cancelledCB.status == .notEnqueued]
  }
  // Signals the unblocked modes harmlessly as well.
  event.signaledValue=1
  precondition(completion.wait(timeout:.now()+10) == .success)
  cb.waitUntilCompleted();precondition(cb.status == .completed)
  var captured=[UInt8](repeating:0,count:4)
  readback.getBytes(&captured,bytesPerRow:4,from:MTLRegionMake2D(32,32,1,1),mipmapLevel:0)
  func rgba(_ x:Int,_ y:Int)->[UInt8] {
   var p=[UInt8](repeating:0,count:4)
   output.getBytes(&p,bytesPerRow:4,from:MTLRegionMake2D(x,y,1,1),mipmapLevel:0)
   return [p[2],p[1],p[0],p[3]]
  }
  if mode=="flight" {
   flight["residentAfterCompletion"]=pool.residentByteCost
   let completedLease=renderer.staticModelDepthTargetPool.acquire(device:d,width:64,height:64)!
   flight["completedDepthReusable"]=completedLease.texture === oldDepth;completedLease.cancel()
  }
  return ["mode":mode,"invalid":invalid as Any? ?? NSNull(),"shadow":shadowCreated,"sameCurrent":sharedCurrent,
   "receiversCastDisabled":noReceiverCast,"drawn":drawn,"copies":capturedOnce,
   "depthBefore":depthBefore,"depthAfter":leases.count,"completed":true,
   "namedRGBA":[captured[2],captured[1],captured[0],captured[3]],
   "shadowPixels":[rgba(16,28),rgba(16,36)],"healthyPixels":[rgba(8,12),rgba(8,52)],"flight":flight]
 }
'''

def named_receivers_main():
    helpers=ORDERED_MAIN[ORDERED_MAIN.index(' static func texture('):ORDERED_MAIN.index(' static func run(')]
    return r'''
@main enum NamedReceiverProbe {
 static func main() throws {
  guard let d=MTLCreateSystemDefaultDevice(),let q=d.makeCommandQueue() else {print("{\"metalUnavailable\":true}");return}
  var rows:[[String:Any]]=[]
  for mode in ["shadow","no-caster","flight"] {rows.append(try autoreleasepool{try namedReceivers(mode,d,q)})}
  print(String(decoding:try JSONSerialization.data(withJSONObject:["rows":rows]),as:UTF8.self))
 }
'''+helpers+NAMED_RECEIVER_FUNCTIONS+'}\n'

# Assertions for f5 integration. Chosen before GPU execution; geometry rays:
# receiver (16,28,0)/(16,36,0) + t*(1,0,1), t=10 => caster (26,y,10).
# Healthy (8,12,0)/(8,52,0) rays miss caster y=[20,44].
def assert_named_receiver_rows(test, rows):
    by_mode={r['mode']:r for r in rows}
    for r in rows:
        test.assertIsNone(r['invalid'])
        test.assertTrue(r['completed'] and r['sameCurrent'] and r['receiversCastDisabled'])
        test.assertEqual(r['drawn'],[True,True,True])
        test.assertEqual(r['copies'],1)
        test.assertEqual(r['depthBefore'],r['depthAfter'])
        test.assertEqual(r['namedRGBA'],[0,255,0,255])
    test.assertTrue(by_mode['shadow']['shadow'])
    test.assertFalse(by_mode['no-caster']['shadow'])
    for on,off in zip(by_mode['shadow']['shadowPixels'],by_mode['no-caster']['shadowPixels']):
        # Shadow-to-lit contrast = the spot's direct term, which the official
        # energy contract scales by k=0.30 (2026-10-06): measured 25→41 green
        # (16 levels of direct over the ramped ambient), so the positivity
        # margin tracks the contracted magnitude rather than the pre-k era.
        test.assertLess(on[1],off[1]-10)
        test.assertEqual(on[3],off[3])
    test.assertEqual(by_mode['shadow']['healthyPixels'],by_mode['no-caster']['healthyPixels'])
    flight=by_mode['flight']; test.assertTrue(flight['shadow'])
    test.assertEqual(flight['shadowPixels'],by_mode['shadow']['shadowPixels'])
    test.assertEqual(flight['healthyPixels'],by_mode['shadow']['healthyPixels'])
    r=flight['flight']
    for k in ['pending','nextShadow','resizedNamed','independentDepth','cancelledDepthReusable','cancelledCBNotSubmitted','completedDepthReusable']:
        test.assertTrue(r[k],k)
    test.assertIsNone(r['nextInvalid'])
    test.assertGreater(r['originalShadowBytes'],0)
    test.assertEqual(r['retainedAfterReset'],r['originalShadowBytes'])
    test.assertEqual(r['retainedAfterCancel'],r['originalShadowBytes'])
    test.assertEqual(r['residentAfterCompletion'],0)


class SceneNamedModelShadowReceiverLifecycleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from script.tests.test_scene_directional_shadow import run_swift
        identity=sha(__file__)
        cls.report=run_swift(ADMISSION_SOURCES,admission_support()+named_receivers_main(),label='rf13-named-receivers',
            metal_sources=[SCENE/'Rendering/Composition'/name for name in
                ['SceneImageLayer.metal','SceneStaticModel.metal','SceneLitImageLayer.metal']])
        if sha(__file__)!=identity: raise AssertionError('test changed during execution')

    def test_two_cast_false_named_receivers_and_blocked_submission_resize_cancel(self):
        assert_named_receiver_rows(self,self.report['rows'])
