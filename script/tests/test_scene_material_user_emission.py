#!/usr/bin/env python3
"""Actual disk builder, property transaction, and shared lit-capture consumer.

The capture shell replaces GPU allocation/light packing only; the production
makeLitCapturePayload selects the prepared target and consumes the snapshot.
Actual encoded/composited pixels are covered by the frozen App cases.
"""
import json, os, subprocess, tempfile, unittest
from pathlib import Path
from script.tests import test_scene_alpha_display_builder_fixture as builder

ROOT = Path(os.environ.get('MWX_MATERIAL_USER_REPOSITORY', str(Path(__file__).resolve().parents[2])))
SCENE = ROOT / 'MyWallpaperX/Core/SteamWorkshopScene'
SUPPORT = builder.HARNESS_SOURCE.split('@main',1)[0] + r'''
import simd
import Metal
// Leaves outside the material/property consumer under test.
enum SceneTextureLoadPurpose { case normal, mask }
struct SceneAssetTextureIdentity: Equatable, Sendable {
    let path:String; let purpose:SceneTextureLoadPurpose
    init?(virtualPath:String,purpose:SceneTextureLoadPurpose) { self.path=virtualPath;self.purpose=purpose }
}
enum SceneFrameTextureIdentity { case asset(SceneAssetTextureIdentity) }
struct Registry { func lookup(_ identity:SceneFrameTextureIdentity)->Bool { true } }
struct SceneGeometryProduct {}
struct SceneFrameTextureResource {}
struct SceneImageLayerDrawRequest {
    let layer:SceneRenderDescriptor.Layer
    let resolvedMaterialFrameTargetPlan:Int?=nil
    let dynamicValues:SceneDynamicSnapshot
    let geometryProduct:SceneGeometryProduct?=nil
    var sourceLighting:SceneBaseMaterialLitCapturePayload?
}
struct ProviderBindings { var lightingProfileByLayerID:[Int:SceneBaseMaterialLightingProfile]=[:] }
struct PackedLights { var sceneViewProjection=matrix_identity_float4x4; var reflection=SIMD4<Float>.zero }
struct SceneLightSnapshot {
    struct Light { let position:SIMD3<Float>;let directionFromLight:SIMD3<Float>;let color:SIMD3<Float>;let intensity:Float;let radius:Float;let innerConeCosine:Float;let outerConeCosine:Float;var illuminatesStaticModels:Bool = true }
    let point:[Light]=[];let spot:[Light]=[];let ambient=SIMD3<Float>.zero
}
struct SceneParticleCameraFrame { func materialView(usesPerspective:Bool)->Bool { false }; func viewProjection(for layer:SceneRenderDescriptor.Layer)->simd_float4x4 { matrix_identity_float4x4 } }
enum SceneCameraProjection { static func imageCardYDirection(usesPerspective:Bool,sceneOrthoHeight:Float?)->Float { 1 } }
struct SceneBaseMaterialLitCapturePayload {
    enum TextureInput { case disabled, unsupported, invalid, ready
        enum Kind { case materialMap }
        static func resolve(_ lookup:Bool,kind:Kind?=nil)->Self { .ready }
    }
    struct PointLight { let position:SIMD3<Float>;let color:SIMD3<Float>;let intensity:Float;let radius:Float }
    struct SpotLight { let position:SIMD3<Float>;let direction:SIMD3<Float>;let color:SIMD3<Float>;let intensity:Float;let radius:Float;let innerConeCosine:Float;let outerConeCosine:Float }
    static func packLights(pointLights:[PointLight],spotLights:[SpotLight],ambient:SIMD3<Float>,material:SIMD2<Float>?,view:Bool,layerModelMatrix:simd_float4x4,normalModelMatrix:simd_float4x4)->PackedLights? { PackedLights() }
    let emission:SIMD4<Float>?
    init?(pipeline:Int,lights:PackedLights,normal:TextureInput,materialMap:TextureInput,mapAllowedComponents:UInt32,mapRequiredComponents:UInt32,emission:SIMD4<Float>?,environmentSource:((MTLCommandBuffer)->SceneFrameTextureResource?)?) { self.emission=emission }
}
struct Pipelines { let litImageLayer:Int?=1 }
struct SceneMetalRenderer {
    let pipelineRepository=Pipelines();let textureRegistry=Registry();let baseMaterialProviderBindings=ProviderBindings()
    let renderDescriptor:SceneRenderDescriptor
}
@main enum Probe {
    static func main() throws {
        let model=try SceneRuntimeModelBuilder().build(rootURL:URL(fileURLWithPath:CommandLine.arguments[1]))
        let program=model.runtimeInput.propertyBindingProgram
        let targets=Set(program.instructions.map(\.target))
        let profiles=SceneBaseMaterialLightingProfileCompiler.profiles(descriptor:model.renderDescriptor,
            materialInstancesByLayerID:model.sceneDocument.materialInstancesByLayerID,materialPropertyTargets:targets)
        let renderer=SceneMetalRenderer(renderDescriptor:model.renderDescriptor)
        func snapshot(_ values:[SceneDynamicTarget:SceneDynamicValue])->SceneDynamicSnapshot {
            SceneDynamicSnapshotResolver().resolve(frameIndex:1,generation:1,definitions:program.definitions,userValues:values).snapshot
        }
        func values(_ snap:SceneDynamicSnapshot)->[[String:Any]] {
            [146,135,143].map { id in
                let p=profiles[id]!
                let emission:Any
                switch renderer.makeLitCapturePayload(profile:p,snapshot:SceneLightSnapshot(),dynamicValues:snap,
                    layerModelMatrix:SceneMatrix.identity(),layerWorldFrame:SceneMatrix.identity(),usesPerspective:false,cameraFrame:.init(),sceneViewProjection:matrix_identity_float4x4,environmentSource:nil) {
                case let .payload(payload): emission=payload.emission.map { [$0.x,$0.y,$0.z,$0.w] } as Any? ?? NSNull()
                case .miss: emission="miss"
                }
                return ["id":id,"dynamic":p.emissionPropertyTarget != nil,"mapDemand":p.mapAsset != nil,"emission":emission]
            }
        }
        var state=ScenePropertyLiveUpdateState(program:program,effectiveValues:model.runtimeInput.effectivePropertyValues,activeConsumerTargets:targets)
        var events:[[String:Any]]=[]
        for value:SceneUserPropertyValue in [.number(0),.number(1),.number(1),.number(0),.string("bad"),.number(2)] {
            let accepted=state.apply(value,forPropertyKey:"constellations")
            events.append(["accepted":accepted,"revision":state.revision,"rows":values(snapshot(state.userValues))])
        }
        let before=state.revision
        let removed=state.apply(replacements:[:],changedPropertyKeys:["constellations"])
        var blocked=ScenePropertyLiveUpdateState(program:program,effectiveValues:model.runtimeInput.effectivePropertyValues,activeConsumerTargets:targets.subtracting(targets.prefix(1)))
        let blockedAccepted=blocked.apply(.number(0),forPropertyKey:"constellations")
        let evaluation=program.evaluate(effectiveValues:model.runtimeInput.effectivePropertyValues)
        let output:[String:Any] = ["instructions":program.instructions.count,"rebuildKeys":program.rebuildRequiredPropertyKeys,
            "rows":values(snapshot(evaluation.userValues)),"fallback":values(snapshot([:])),"events":events,
            "deletedAccepted":removed,"deleteRevisionStable":before==state.revision,"blockedAccepted":blockedAccepted,"blockedRevision":blocked.revision]
        print(String(decoding:try JSONSerialization.data(withJSONObject:output),as:UTF8.self))
    }
}
'''

class SceneMaterialUserEmissionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary=tempfile.TemporaryDirectory(prefix='mwx-material-user-')
        cls.work=Path(cls.temporary.name);source=cls.work/'Probe.swift';source.write_text(SUPPORT)
        cls.binary=cls.work/'probe'
        sources=list(dict.fromkeys(builder.SWIFT_SOURCES+[
            SCENE/'Compilation/Material/SceneBaseMaterialLightingProfile.swift',
            SCENE/'Systems/Properties/ScenePropertyLiveUpdateState.swift',
            SCENE/'Rendering/Frame/SceneResolvedMaterialFramePreflight+LitCapture.swift']))
        result=subprocess.run(['xcrun','swiftc',*map(str,sources),str(source),'-module-cache-path',str(cls.work/'cache'),'-framework','Metal','-o',str(cls.binary)],capture_output=True,text=True)
        if result.returncode: raise AssertionError(result.stderr)
    @classmethod
    def tearDownClass(cls): cls.temporary.cleanup()

    def probe(self, *, instances=None, value=None, shader='genericimage2', lighting=1, alpha=False, multi=False, defined=True, color="0.25 0.5 0.125", map_combo=1, puppet=False):
        work=self.work/'content';work.mkdir(exist_ok=True)
        for sub in ['models','materials']:(work/sub).mkdir(exist_ok=True)
        project={'type':'scene','file':'scene.json','general':{'properties':{'constellations':{'type':'slider','value':1,'min':0,'max':1}} if defined else {}}}
        objects=[{'id':i,'image':'models/receiver.json','size':'28 28',**({'instance':instances[i]} if instances and i in instances else {}),**({'alpha':{'user':'constellations','value':1}} if alpha else {})} for i in [146,135,143]]
        material={'shader':shader,'combos':{'LIGHTING':lighting,'METALLIC_MAP':0,'ROUGHNESS_MAP':0,'EMISSIVE_MAP':map_combo},'textures':['materials/albedo.png',None,'materials/map.tex'],
            'constantshadervalues':{'emissivecolor':color,'emissivebrightness':{'user':'constellations','value':2.3} if value is None else value}}
        for path,data in {'project.json':project,'scene.json':{'version':3,'objects':objects},'models/receiver.json':{'material':'materials/receiver.json',**({'puppet':'models/mesh.mdl'} if puppet else {})},'materials/receiver.json':{'passes':[material,material] if multi else [material]}}.items():
            (work/path).write_text(json.dumps(data))
        run=subprocess.run([str(self.binary),str(work)],capture_output=True,text=True)
        self.assertEqual(run.returncode,0,run.stderr)
        return json.loads(run.stdout)

    def test_builder_snapshot_actual_capture_and_atomic_cycle(self):
        result=self.probe(alpha=True)
        self.assertEqual(result['instructions'],6,result)
        for row in result['rows']:
            self.assertEqual(row['emission'],[.25,.5,.125,1]);self.assertTrue(row['dynamic']);self.assertTrue(row['mapDemand'])
        for row in result['fallback']:self.assertAlmostEqual(row['emission'][3],2.3,places=6)
        self.assertEqual([e['accepted'] for e in result['events']],[True,True,True,True,False,False])
        self.assertEqual([e['revision'] for e in result['events']],[1,2,2,3,3,3])
        for event,want in zip(result['events'],[0,1,1,0,0,0]):
            self.assertEqual([r['emission'][3] for r in event['rows']],[want]*3)
            self.assertTrue(all(r['mapDemand'] for r in event['rows']))
        self.assertFalse(result['deletedAccepted']);self.assertTrue(result['deleteRevisionStable'])
        self.assertFalse(result['blockedAccepted']);self.assertEqual(result['blockedRevision'],0)

    def test_instance_presence_suppresses_material_writer(self):
        for value,want in [(0,0),(3,3),(None,None),('bad',None)]:
            result=self.probe(instances={146:{'constantshadervalues':{'emissivebrightness':value}}})
            self.assertEqual(result['instructions'],2,result)
            first=result['rows'][0];self.assertFalse(first['dynamic'])
            self.assertEqual(first['emission'],None if want is None else [.25,.5,.125,want])
            self.assertEqual(first['mapDemand'],want is not None)
        result=self.probe(instances={146:{'constantshadervalues':{'emissivebrightness':{'user':'constellations','value':2.3}}}})
        self.assertFalse(result['rows'][0]['dynamic']);self.assertEqual(result['rows'][0]['emission'],[.25,.5,.125,1])
        self.assertIn('constellations',result['rebuildKeys'])
        self.assertFalse(result['events'][0]['accepted'])

    def test_invalid_color_does_not_block_existing_alpha_siblings(self):
        result=self.probe(alpha=True,color="1 -1 1")
        self.assertEqual(result['instructions'],3,result)
        self.assertEqual([e['accepted'] for e in result['events']],[True,True,True,True,False,False])
        self.assertTrue(all(not r['dynamic'] and not r['mapDemand'] and r['emission'] is None for r in result['rows']))
        result=self.probe(alpha=True,map_combo=0)
        self.assertEqual(result['instructions'],6,result)
        self.assertTrue(all(r['dynamic'] and not r['mapDemand'] for r in result['rows']))
        self.assertTrue(result['events'][0]['accepted'])

        black=self.probe(alpha=True,color="0 0 0")
        self.assertEqual(black['instructions'],6)
        self.assertTrue(all(r['dynamic'] and r['mapDemand'] for r in black['rows']))
        self.assertEqual(black['rows'][0]['emission'],[0,0,0,1])
        for brightness in [-1,1e100]:
            recovery=self.probe(value={'user':'constellations','value':brightness})
            self.assertEqual(recovery['instructions'],3)
            self.assertTrue(all(r['dynamic'] and r['mapDemand'] for r in recovery['fallback']))
            self.assertTrue(all(r['emission'] is None for r in recovery['fallback']))
            self.assertTrue(all(r['emission']==[.25,.5,.125,1] for r in recovery['rows']))
        invalid_instance=self.probe(alpha=True,instances={146:{'constantshadervalues':{'emissivecolor':'0 -1 0'}}})
        self.assertEqual(invalid_instance['instructions'],5)
        self.assertIsNone(invalid_instance['rows'][0]['emission'])
        self.assertTrue(invalid_instance['events'][0]['accepted'])

    def test_puppet_geometry_does_not_claim_unsupported_lit_consumer(self):
        result=self.probe(alpha=True,puppet=True)
        self.assertEqual(result['instructions'],3,result)
        self.assertTrue(all(not r['dynamic'] and not r['mapDemand'] for r in result['rows']))
        self.assertTrue(result['events'][0]['accepted'])

    def test_unsupported_wrappers_and_routes_do_not_claim_consumer(self):
        cases=[dict(shader='custom'),dict(lighting=0),dict(multi=True),dict(defined=False),
               dict(value={'user':17,'value':2.3}),dict(value={'user':{'name':'constellations'},'value':2.3}),
               dict(value={'user':'constellations','value':2.3,'script':'export function update(v){return v;}'}),
               dict(value={'user':'constellations','value':None})]
        for case in cases:
            result=self.probe(**case)
            self.assertEqual(result['instructions'],0,(case,result))
            self.assertTrue(all(not r['dynamic'] and not r['mapDemand'] for r in result['rows']),(case,result))

@unittest.skipUnless(os.environ.get('MWX_MATERIAL_USER_APP'), 'requires frozen signed App')
class SceneMaterialUserEmissionAppTests(unittest.TestCase):
    def run_case(self,name,*,effect=False,instance=False,sequence=(1,0),single=None,invalid_sequence=False,missing_payload=False,invalid_color=False):
        import hashlib, re, struct, zlib
        from script.tests.test_scene_pkg_cache_extractor import make_package
        from PIL import Image, ImageStat
        work=Path(os.environ['MWX_MATERIAL_USER_EVIDENCE'])/name
        work.mkdir(parents=True,exist_ok=False);content=work/'content';content.mkdir();home=work/'home';home.mkdir();evidence=work/'evidence'
        def png():
            def chunk(k,v):return struct.pack('>I',len(v))+k+v+struct.pack('>I',zlib.crc32(k+v)&0xffffffff)
            return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',4,4,8,6,0,0,0))+chunk(b'IDAT',zlib.compress((b'\0'+bytes((128,128,128,255) if invalid_color else (0,0,0,255))*4)*4))+chunk(b'IEND',b'')
        project={'type':'scene','file':'scene.json','general':{'properties':{'constellations':{'type':'slider','value':1,'min':0,'max':1}}}}
        objects=[{'id':i,'image':'models/receiver.json','origin':f'{x} 48 0','size':'28 28'} for i,x in [(146,40),(135,80),(143,120)]]
        if invalid_color:
            for o in objects:o['alpha']={'user':'constellations','value':1}
        if effect:
            for o in objects:o['effects']=[{'id':10,'file':'effects/own_dim/effect.json','visible':True}]
        if instance:
            objects[0]['instance']={'constantshadervalues':{'emissivebrightness':0}}
            objects[2]['instance']={'constantshadervalues':{'emissivebrightness':.5}}
        objects.append({'id':99,'image':'models/util/solidlayer.json','origin':'140 80 0','size':'12 12','color':'0 1 0'})
        scene={'version':3,'general':{'orthogonalprojection':{'width':160,'height':96},'clearcolor':'0 0 0','ambientcolor':'1 1 1' if invalid_color else '0 0 0','skylightcolor':'0 0 0'},'objects':objects}
        material={'passes':[{'shader':'genericimage2','constantshadervalues':{'emissivecolor':'0.25 0.5 0.125','emissivebrightness':{'user':'constellations','value':2.3}},'combos':{'LIGHTING':1,'METALLIC_MAP':0,'ROUGHNESS_MAP':0,'EMISSIVE_MAP':1},'textures':['materials/albedo.png',None,'materials/map.tex'],'blending':'normal','depthtest':'disabled','depthwrite':'disabled','cullmode':'nocull'}]}
        if invalid_color:material['passes'][0]['constantshadervalues']['emissivecolor']='1 -1 1'
        payload=bytes((0,0,0,255))*16
        tex=b'TEXV0005\0TEXI0001\0'+struct.pack('<7I',0,1<<23,4,4,4,4,0)+b'TEXB0002\0'+struct.pack('<7I',1,1,4,4,0,0,len(payload))+payload
        entries={'scene.json':json.dumps(scene).encode(),'models/receiver.json':json.dumps({'material':'materials/receiver.json'}).encode(),'materials/receiver.json':json.dumps(material).encode(),'materials/albedo.png':png(),'materials/map.tex':tex}
        if effect:entries.update({
            'effects/own_dim/effect.json':json.dumps({'passes':[{'material':'materials/own_dim.json'}]}).encode(),
            'materials/own_dim.json':json.dumps({'passes':[{'shader':'own_dim','textures':[None],'blending':'normal','depthtest':'disabled','depthwrite':'disabled','cullmode':'nocull'}]}).encode(),
            'shaders/own_dim.vert':b'attribute vec3 a_Position;\nattribute vec2 a_TexCoord;\nvarying vec2 v_TexCoord;\nvoid main(){gl_Position=vec4(a_Position,1.0);v_TexCoord=a_TexCoord;}\n',
            'shaders/own_dim.frag':b'uniform sampler2D g_Texture0;\nvarying vec2 v_TexCoord;\nvoid main(){vec4 c=texSample2D(g_Texture0,v_TexCoord);c.rgb*=0.5;gl_FragColor=c;}\n'})
        (content/'project.json').write_text(json.dumps(project));(content/'scene.pkg').write_bytes(make_package(list(entries.items())))
        app=Path(os.environ['MWX_MATERIAL_USER_APP']);bundle=app.parents[1]
        cmd=[str(app),'--mwx-debug-scene-root',str(content),'--mwx-debug-scene-duration','9','--mwx-debug-scene-evidence-dir',str(evidence),
             '--mwx-debug-scene-properties-json','{"constellations":0}','--mwx-debug-scene-periodic-snapshot-interval','1.5','--mwx-debug-scene-after-snapshot-delay','7.2']
        if single is not None:cmd+=['--mwx-debug-scene-live-properties-json',json.dumps({'constellations':single})]
        if sequence is not None:
            raw=[{'constellations':v} for v in sequence]
            if invalid_sequence:raw.append(False)
            cmd+=['--mwx-debug-scene-live-property-sequence-json']
            if not missing_payload:cmd.append(json.dumps(raw))
        sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
        unit_rgb=[128,128,128] if invalid_color else [63.75,127.5,31.875]
        identity={'command':cmd,'cwd':str(ROOT),'testPath':str(Path(__file__).resolve()),'testSHA':sha(Path(__file__)),
                  'binaries':{str(p):sha(p) for p in [app,bundle/'MacOS/MyWallpaperX.debug.dylib',bundle/'Resources/default.metallib']},
                  'inputSHA':{str(p.relative_to(content)):sha(p) for p in content.iterdir()},
                  'entrySHA':{k:hashlib.sha256(v).hexdigest() for k,v in entries.items()},
                  'oracle':{'fullBrightnessRGB':unit_rgb,'effectFactor':.5 if effect else 1,'tolerance':2,'instanceBrightness':[0,'property',.5] if instance else None,'healthyPeerSamplesMin':20,'sequence':sequence,'transportRejected':invalid_sequence or missing_payload}}
        (work/'prerun.json').write_text(json.dumps(identity,indent=2))
        env=os.environ.copy();env.update(HOME=str(home),CFFIXED_USER_HOME=str(home),MWX_SCENE_DEBUG_SURFACE_COUNT='1')
        with (work/'app.log').open('w') as log:run=subprocess.run(cmd,cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=90)
        log=(work/'app.log').read_text();images={}
        for path in sorted(evidence.glob('*-window.png')):
            image=Image.open(path).convert('RGB');w,h=image.size;rois=[]
            for xratio in [.25,.5,.75]:
                x=int(w*xratio);rois.append(ImageStat.Stat(image.crop((x-10,h//2-10,x+10,h//2+10))).mean)
            pixels=image.load()
            images[path.name]={'roi':rois,'healthy':sum(pixels[x,y][0]<5 and pixels[x,y][1]>245 and pixels[x,y][2]<5 for y in range(0,h,4) for x in range(0,w,4))}
        updates=re.findall(r'phase=live-property-update accepted=(true|false) surfacesBefore=(\d+) surfacesAfter=(\d+) windowsBefore=(\S+) windowsAfter=(\S+)',log)
        steps=re.findall(r'phase=live-property-sequence-step index=(\d+) accepted=(true|false)',log)
        result={'steps':steps,'returncode':run.returncode,'images':images,'updates':updates,'sessions':re.findall(r'phase=session-activated session=(\S+)',log),'drained':'gpuDrained=true' in log}
        (work/'result.json').write_text(json.dumps(result,indent=2));print(json.dumps({'case':name,**result}),flush=True)
        self.assertEqual(run.returncode,0);self.assertTrue(result['drained']);self.assertEqual(len(result['sessions']),1)
        self.assertEqual(log.count('phase=session-candidate '),1);self.assertIn('state=completed frame=1 ',log)
        self.assertTrue(all(u[1]==u[2]=='1' and u[3]==u[4] for u in updates))
        rejected=invalid_sequence or missing_payload
        expected_accept=[] if rejected else ['true'] if sequence is None else ['false' if isinstance(v,str) else 'true' for v in sequence]
        self.assertEqual([u[0] for u in updates],expected_accept)
        self.assertEqual(steps,[(str(i),value) for i,value in enumerate(expected_accept)])
        if rejected:self.assertIn('phase=live-property-sequence state=rejected',log)
        expected={'scene-ready-window.png':0,'scene-series-0000-window.png':0}
        if rejected:expected['scene-after-window.png']=0
        elif sequence is None:expected.update({'scene-series-0001-window.png':single,'scene-after-window.png':single})
        else:
            expected['scene-series-0001-window.png']=1
            expected['scene-after-window.png']=0
            if len(sequence)==3:expected['scene-series-0002-window.png']=1
            else:expected['scene-series-0002-window.png']=0
        for filename,brightness in expected.items():
            self.assertIn(filename,images,images.keys());image=images[filename];self.assertGreater(image['healthy'],20)
            for index,roi in enumerate(image['roi']):
                scalar=([0,brightness,.5][index] if instance else brightness)*(.5 if effect else 1)
                for actual,unit in zip(roi,unit_rgb):self.assertAlmostEqual(actual,unit*scalar,delta=2,msg=f'{filename} layer{index} {roi}')
        self.assertEqual(identity['binaries'],{p:sha(Path(p)) for p in identity['binaries']})

    def test_plain_same_session_cycle(self):self.run_case('plain-cycle')
    def test_effect_same_session_cycle(self):self.run_case('effect-cycle',effect=True)
    def test_invalid_live_value_rolls_back_then_recovers(self):self.run_case('rollback',sequence=(1,'bad',0))
    def test_static_instance_suppresses_shared_material_writer(self):self.run_case('instance-cycle',instance=True)
    def test_invalid_sequence_has_no_prefix_or_single_fallback(self):self.run_case('invalid-sequence',sequence=(1,),invalid_sequence=True,single=1)
    def test_missing_sequence_payload_has_no_single_fallback(self):self.run_case('missing-sequence',sequence=(),missing_payload=True,single=1)
    def test_existing_single_update(self):self.run_case('single-update',sequence=None,single=1)

    def test_invalid_color_preserves_same_key_alpha_cycle(self):self.run_case('invalid-color',invalid_color=True)
