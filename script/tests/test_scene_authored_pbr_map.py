#!/usr/bin/env python3
"""Self-authored packed map data through the actual common material producer."""
import unittest
import json, math, os, struct, subprocess, tempfile
from pathlib import Path
from script.tests import test_scene_authored_normal as normal

def map_vectors():
    base=dict(rgba=[192,128,77,128],bits=3,allowed=11,material=[.2,.8],source=[.5,.25,.125,1],
              emission=[.25,.5,1,2],intensity=1,opacity=1,tint=[1,1,1],light=[0,0,1],normal=[0,0,1])
    specs=[('rg',{}),('metal',dict(bits=1)),('rough',dict(bits=2)),
           ('zero-metal',dict(bits=1,rgba=[0,128,77,128])),('zero-rough',dict(bits=2,rgba=[192,0,77,128])),
           ('emission-only-preserves-mr',dict(bits=8)),('all-three',dict(bits=11)),
           ('components-disabled',dict(bits=11,allowed=0)),
           ('no-header',dict(bits=0)),('no-light-black',dict(bits=8,intensity=0,source=[0,0,0,1])),
           ('coverage-quarter',dict(bits=8,intensity=0,source=[0,0,0,.25],tint=[.5,.25,1],opacity=.5)),
           ('coverage-zero',dict(bits=11,source=[0,0,0,0])),
           ('emission-zero',dict(bits=8,intensity=0,rgba=[255,255,255,0])),
           ('brightness-zero',dict(bits=8,intensity=0,emission=[1,1,1,0])),
           ('hdr-emission',dict(bits=8,intensity=0,emission=[1,2,3,1000000])),
           ('extreme-covered',dict(bits=8,intensity=0,emission=[1e20,2e20,3e20,1e20],opacity=1e-18,tint=[1e-20]*3)),
           ('non-axis-lit',dict(light=[.6,.2,1],normal=[0,0,1])),
           ('normal-opposite-emission',dict(bits=8,intensity=0,normal=[0,0,-1])),
           ('invalid-emission-keeps-mr',dict(bits=11,emission=None))]
    vectors=[dict(base,**changes,name=name) for name,changes in specs]
    for fmt,alpha in [(7,255),(6,136),(4,128)]:
        vectors.append(dict(base,name=f'tex-format-{fmt}-rg',format=fmt,rgba=[255,0,0,alpha],bits=3))
    return vectors

def map_oracle(v):
    # Independent double calculation, with explicitly represented Float32 inputs.
    f=lambda x:struct.unpack('f',struct.pack('f',x))[0]
    unit=lambda a:[x/math.sqrt(sum(y*y for y in a)) for x in a]
    n,l=unit(list(map(f,v['normal']))),unit(list(map(f,v['light'])))
    view=[0,0,1];dot=lambda a,b:sum(x*y for x,y in zip(a,b))
    bits=v['bits']&v['allowed'];sample=[f(x/255) for x in v['rgba']]
    m=sample[0] if bits&1 else f(v['material'][0]);r=sample[1] if bits&2 else f(v['material'][1])
    source=[struct.unpack('e',struct.pack('e',x))[0] for x in v['source']]
    nl=max(0,min(1,dot(n,l)));nv=max(0,min(1,dot(n,view)))
    falloff=max(0,1-math.sqrt(sum(f(x)**2 for x in v['light']))/1000)**2
    result=[]
    for c in range(3):
        albedo=source[c]/source[3] if source[3]>0 else 0
        fresnel=.04*(1-m)+min(1,max(0,albedo))*m;spec=0
        if nl>0 and nv>0:
            h=unit([a+b for a,b in zip(l,view)]);nh=max(0,min(1,dot(n,h)));a=max(.01,r*r)
            D=a*a/(math.pi*(1+(a*a-1)*nh*nh)**2)
            lam=lambda x:(math.sqrt(1+a*a*(1-x*x)/(x*x))-1)/2
            G=1/(1+lam(nl)+lam(nv));fresnel+=(1-fresnel)*(1-max(0,min(1,dot(view,h))))**5
            spec=math.pi*D*G*fresnel/(4*nl*nv)*nl
        direct=((1-m)*(1-fresnel)*albedo*nl+spec)*source[3]*f(v['intensity'])*falloff
        emission=sample[3]*f(v['emission'][c])*f(v['emission'][3])*source[3] if bits&8 and v['emission'] else 0
        result.append(min(65504,max(0,(direct+emission)*f(v['tint'][c])*f(v['opacity']))))
    return result+[source[3]*f(v['opacity'])]

class SceneAuthoredPBRMapTests(unittest.TestCase):
    def test_authored_map_profile_and_emission_projection(self):
        from script.tests import test_scene_alpha_display_builder_fixture as builder
        support=builder.HARNESS_SOURCE.split('@main',1)[0]+r'''
enum SceneTextureLoadPurpose { case normal, mask }
struct SceneAssetTextureIdentity: Equatable, Sendable {
    let path:String;let purpose:SceneTextureLoadPurpose
    init?(virtualPath:String,purpose:SceneTextureLoadPurpose) { self.path=virtualPath;self.purpose=purpose }
}
@main enum MapProfileProbe {
    static func main() throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1])
        let facts=SceneRuntimeSourceFactsBuilder().build(rootURL:root)
        let document=facts.sceneDocument!,descriptor=facts.renderDescriptor!
        let instances=Dictionary(uniqueKeysWithValues:document.objects.compactMap { o in o.materialInstance.map { (o.id,$0) } })
        let profiles=SceneBaseMaterialLightingProfileCompiler.profiles(descriptor:descriptor,materialInstancesByLayerID:instances,materialPropertyTargets:[])
        let result=descriptor.layers.map { layer -> [String:Any] in
            let p=profiles[layer.id]!
            let source:String
            switch p.mapSource { case .disabled:source="disabled";case .invalid:source="invalid";case .unsupported:source="unsupported";case let .asset(a):source=a.path }
            let emission: [Float]?
            if case let .constant(value) = p.emission { emission = [value.x,value.y,value.z,value.w] } else { emission = nil }
            return ["id":layer.id,"source":source,"allowed":p.mapAllowedComponents,"required":p.mapRequiredComponents,
                "emission":emission as Any? ?? NSNull(),
                "material":p.scalarMaterial.map { [$0.x,$0.y] } as Any? ?? NSNull()]
        }
        print(String(decoding:try JSONSerialization.data(withJSONObject:result),as:UTF8.self))
    }
}
'''
        base={'shader':'genericimage2','combos':{'LIGHTING':1},'textures':['materials/base.png','materials/normal.png','materials/map.tex']}
        cases=[]
        def add(name,patch=None,instance=None,source='materials/map.tex',emission=(1,1,1,1),allowed=11,required=0):
            material=json.loads(json.dumps(base));material.update(patch or {})
            cases.append((name,material,instance,dict(source=source,emission=list(emission) if emission is not None else None,allowed=allowed if emission is not None else allowed&3,required=required)))
        add('default')
        add('null-inherit',instance={'textures':[None,None,None]})
        add('instance-map',instance={'textures':[None,None,'materials/other.tex']},source='materials/other.tex')
        add('whole-disabled',{'combos':{'LIGHTING':1,'PBRMASKS':0},'usertextures':[None,None,'u']},source='disabled')
        add('explicit-enable',{'combos':{'LIGHTING':1,'PBRMASKS':1,'METALLIC_MAP':1,'ROUGHNESS_MAP':0}},allowed=9,required=1)
        add('bad-whole-combo',{'combos':{'LIGHTING':1,'PBRMASKS':2}},source='unsupported')
        add('bad-component-combo',{'combos':{'LIGHTING':1,'EMISSIVE_MAP':2}},allowed=3)
        add('material-provider',{'usertextures':[None,None,'u']},source='unsupported')
        add('empty-instance-retains-provider',{'usertextures':[None,None,'u']},{'usertextures':[]},source='unsupported')
        add('null-instance-retains-provider',{'usertextures':[None,None,'u']},{'usertextures':[None,None,None]},source='unsupported')
        add('instance-provider',instance={'usertextures':[None,None,17]},source='unsupported')
        add('other-slot-provider',{'usertextures':['u',None,None]})
        add('all-components-zero',{'combos':{'LIGHTING':1,'METALLIC_MAP':0,'ROUGHNESS_MAP':0,'EMISSIVE_MAP':0}},source='disabled',allowed=0)
        add('lighting-zero',{'combos':{'LIGHTING':0}},source='disabled',emission=None,allowed=0)
        add('custom',{'shader':'custom'},source='disabled',emission=None,allowed=0)
        add('emission-color',{'constantshadervalues':{'emissivecolor':'0.2 0.4 0.8','emissivebrightness':3}},emission=(.2,.4,.8,3))
        add('instance-zero',{'constantshadervalues':{'emissivebrightness':3}},{'constantshadervalues':{'emissivebrightness':0}},emission=(1,1,1,0))
        add('null-brightness',{'constantshadervalues':{'emissivebrightness':None}},emission=None)
        add('negative',{'constantshadervalues':{'emissivecolor':'1 -1 1'}},emission=None)
        add('overflow-float',{'constantshadervalues':{'emissivebrightness':1e100}},emission=None)
        add('material-unresolved',{'constantshadervalues':{'emissivebrightness':{'user':'brightness','value':3}}},emission=None)
        add('instance-startup',instance={'constantshadervalues':{'emissivebrightness':{'user':'brightness','value':3}}},emission=(1,1,1,2))
        add('instance-fallback',instance={'constantshadervalues':{'emissivebrightness':{'user':'absent','value':3}}},emission=(1,1,1,3))
        add('dynamic',instance={'constantshadervalues':{'emissivebrightness':{'value':3,'script':'export function update(v){return v;}'}}},emission=None)
        # Current numeric parser accepts these spellings; this is typed validation, not a stricter lexer.
        add('parser-word-compaction',{'constantshadervalues':{'emissivecolor':'1 junk 0 1'}},emission=(1,0,1,1))
        add('invalid-emission-only-no-demand',{'combos':{'LIGHTING':1,'METALLIC_MAP':0,'ROUGHNESS_MAP':0,'EMISSIVE_MAP':1},'constantshadervalues':{'emissivebrightness':None}},source='disabled',emission=None,allowed=0,required=8)
        add('parser-bool-bridge',{'constantshadervalues':{'emissivebrightness':True}},emission=(1,1,1,1))
        with tempfile.TemporaryDirectory(prefix='mwx-map-profile-') as temporary:
            work=Path(temporary);objects=[]
            for i,(name,material,instance,_) in enumerate(cases):
                (work/'materials').mkdir(exist_ok=True);(work/'models').mkdir(exist_ok=True)
                (work/f'materials/{i}.json').write_text(json.dumps({'passes':[material]}))
                (work/f'models/{i}.json').write_text(json.dumps({'material':f'materials/{i}.json','width':64,'height':64}))
                obj={'id':i+1,'image':f'models/{i}.json'}
                if instance is not None:obj['instance']=instance
                objects.append(obj)
            (work/'project.json').write_text(json.dumps({'type':'scene','file':'scene.json','general':{'properties':{'brightness':{'type':'slider','value':2}}}}))
            (work/'scene.json').write_text(json.dumps({'objects':objects}))
            source=work/'Harness.swift';source.write_text(support);binary=work/'probe'
            scene=builder.SOURCE_ROOT
            sources=list(dict.fromkeys(builder.SWIFT_SOURCES+[scene/'Compilation/Material/SceneBaseMaterialLightingProfile.swift',scene/'Compilation/ShaderContract/SceneBuiltinShaderIdentity.swift']))
            compiled=subprocess.run(['xcrun','swiftc',*map(str,sources),str(source),'-module-cache-path',str(work/'cache'),'-o',str(binary)],capture_output=True,text=True)
            self.assertEqual(compiled.returncode,0,compiled.stderr)
            run=subprocess.run([str(binary),str(work)],capture_output=True,text=True);self.assertEqual(run.returncode,0,run.stderr)
            result=json.loads(run.stdout);self.assertEqual(len(result),len(cases))
            for actual,(name,_,_,expected) in zip(result,cases):
                for key,wanted in expected.items():
                    if isinstance(wanted,list):
                        self.assertIsNotNone(actual[key],(name,actual))
                        for a,e in zip(actual[key],wanted):self.assertAlmostEqual(a,e,places=6,msg=str((name,actual)))
                    else:self.assertEqual(actual[key],wanted,(name,actual))
            print(json.dumps(dict(cases=[c[0] for c in cases],actual=result),sort_keys=True))

    def test_loader_map_sampling_and_material_output(self):
        from script.tests import test_scene_texture_candidate as texture
        root=Path(__file__).resolve().parents[2];scene=root/'MyWallpaperX/Core/SteamWorkshopScene'
        with tempfile.TemporaryDirectory(prefix='mwx-pbr-map-') as temporary:
            work=Path(temporary);vectors=map_vectors()
            for v in vectors:v['expected']=map_oracle(v)
            (work/'vectors.json').write_text(json.dumps(vectors,indent=2))
            import zlib
            def chunk(k,v):return struct.pack('>I',len(v))+k+v+struct.pack('>I',zlib.crc32(k+v)&0xffffffff)
            (work/'headerless.png').write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',4,4,8,6,0,0,0))+chunk(b'IDAT',zlib.compress((b'\0'+bytes([255,128,0,128])*4)*4))+chunk(b'IEND',b''))
            if destination:=os.environ.get('MWX_PBR_MAP_EVIDENCE'):
                Path(destination).mkdir(parents=True,exist_ok=True)
                (Path(destination)/'vectors-prerun.json').write_text(json.dumps(vectors,indent=2))
            air=[]
            for name in ['SceneImageLayer','SceneLitImageLayer']:
                output=work/(name+'.air');subprocess.run(['xcrun','-sdk','macosx','metal','-c',str(scene/'Rendering/Composition'/(name+'.metal')),'-o',str(output)],check=True,capture_output=True);air.append(str(output))
            library=work/'test.metallib';subprocess.run(['xcrun','-sdk','macosx','metallib',*air,'-o',str(library)],check=True,capture_output=True)
            sources=list(dict.fromkeys(texture.SWIFT_SOURCES+[scene/p for p in ['Rendering/Metal/SceneLitImageLayerPipeline.swift','Rendering/Composition/SceneOffscreenEffectRenderer+Capture.swift','Diagnostics/SceneGPUCensus.swift','Resources/Assets/SceneResourceIndex.swift','Resources/Assets/SceneResourceView.swift','Resources/Textures/SceneTexturePathResolver.swift','Resources/Textures/SceneMaterialAssetTextureCatalog.swift']]))
            support=texture.HARNESS.split('@main',1)[0]
            support=support.replace('struct SceneRenderDescriptor {','struct SceneRenderDescriptor { struct ModelMaterialLink { let modelPath:String; let materialPath:String }; struct MaterialPass { let materialPath:String; let texturePaths:[String] }; var modelMaterialLinks:[ModelMaterialLink]=[]; var materialPasses:[MaterialPass]=[];')
            support=support.replace('let contentKind: String\n        let brightness:', 'var imagePath:String?=nil\n        var staticBaseTexturePath:String?=nil\n        let contentKind: String\n        let brightness:')
            (work/'Support.swift').write_text(support+'\nimport simd\nenum SceneMatrix { static func scale(_ v: SIMD3<Float>) -> simd_float4x4 { simd_float4x4(diagonal: SIMD4(v,1)) } }')
            binary=work/'probe';compiled=subprocess.run(['xcrun','swiftc','-parse-as-library',*map(str,sources),str(work/'Support.swift'),str(root/'script/tests/fixtures/ScenePBRMapHarness.swift'),'-module-cache-path',str(work/'cache'),'-o',str(binary)],capture_output=True,text=True)
            self.assertEqual(compiled.returncode,0,compiled.stderr)
            run=subprocess.run([str(binary),str(library),str(work)],capture_output=True,text=True)
            self.assertEqual(run.returncode,0,run.stderr)
            report=json.loads(run.stdout);self.assertEqual(len(report['vectors']),len(vectors));self.assertTrue(all(report['contracts'].values()),report)
            print(json.dumps(report,sort_keys=True))
            if destination:(Path(destination)/'gpu-report.json').write_text(json.dumps(report,indent=2))

class SceneAuthoredPBRMapIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        normal.SceneAuthoredNormalIntegrationTests.setUpClass.__func__(cls)
        import hashlib
        cls.execution_test_sha=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    run_normal=normal.SceneAuthoredNormalIntegrationTests.run_normal

    def check_map(self,expected,**kwargs):
        kwargs.setdefault('no_normal',True);kwargs.setdefault('light_origin','80 48 100');kwargs.setdefault('intensity',.2)
        result=self.run_normal(**kwargs)
        for frame,value in result.items():
            for channel,wanted in enumerate(expected):
                self.assertLessEqual(abs(value['roiMean'][channel]-wanted),2,(frame,value,expected))
        return result

    def test_metal_map_replaces_scalar(self):
        expected=normal.pbr_expected(light=(0,0,100),metallic=1,roughness=.5,intensity=.2)
        self.check_map([expected]*3,scalar_values={'metallic':0,'roughness':.5},
            pbr_map={'rgba':[255,0,255,0],'flags':1<<20})

    def test_rough_map_replaces_scalar(self):
        expected=normal.pbr_expected(light=(0,0,100),metallic=1,roughness=128/255,intensity=.2)
        self.check_map([expected]*3,scalar_values={'metallic':1,'roughness':1},
            pbr_map={'rgba':[0,128,255,0],'flags':1<<21})

    def test_emission_visible_without_lights(self):
        self.check_map([64,128,32],no_lights=True,
            scalar_values={'emissivecolor':'0.25 0.5 0.125','emissivebrightness':1},
            pbr_map={'rgba':[255,255,0,255],'flags':1<<23})

    def test_effect_uses_same_map_and_emission(self):
        self.scenario_id='metal-effect'
        expected=normal.pbr_expected(light=(0,0,100),metallic=1,roughness=.5,intensity=.2)/2
        self.check_map([expected]*3,effect=True,scalar_values={'metallic':0,'roughness':.5},pbr_map={'rgba':[255,0,0,0],'flags':1<<20})
        self.scenario_id='emission-effect'
        self.check_map([32,64,16],effect=True,no_lights=True,scalar_values={'emissivecolor':'0.25 0.5 0.125'},pbr_map={'rgba':[0,0,0,255],'flags':1<<23})

    def test_zero_and_header_conflict_do_not_invent_presence(self):
        for name,values,combos,headerless in [
            ('brightness-zero',{'emissivebrightness':0},{},False),
            ('whole-zero',{}, {'PBRMASKS':0},False),
            ('component-zero',{}, {'EMISSIVE_MAP':0},False),
            ('headerless-explicit',{}, {'PBRMASKS':1,'EMISSIVE_MAP':1},True)]:
            self.scenario_id=name
            self.check_map([0]*3,no_lights=True,scalar_values=values,pbr_map={'rgba':[255]*4,'flags':1<<23,'combos':combos,'headerless':headerless})

    def test_missing_corrupt_map_preserves_actual_normal_and_scalar(self):
        expected=normal.pbr_expected((1,0,0),light=(100,0,100),metallic=.2,roughness=.8,intensity=1.5)
        for failure in ['missing','corrupt']:
            self.scenario_id=failure
            self.check_map([expected]*3,no_normal=False,encoding='bc5',light_origin='180 48 100',intensity=1.5,
                scalar_values={'metallic':.2,'roughness':.8},pbr_map={'rgba':[255]*4,'flags':11<<20,failure:True})

    def test_map_mr_preserves_normal_and_invalid_emission(self):
        expected=normal.pbr_expected((1,0,0),light=(100,0,100),metallic=0,roughness=128/255,intensity=1.5)
        self.check_map([expected]*3,no_normal=False,encoding='bc5',light_origin='180 48 100',intensity=1.5,
            scalar_values={'metallic':1,'roughness':1,'emissivebrightness':None},pbr_map={'rgba':[0,128,0,255],'flags':11<<20})

    def test_instance_map_and_emission_constants_override(self):
        self.check_map([32,64,128],no_lights=True,scalar_values={'emissivecolor':'1 0 0','emissivebrightness':3},
            instance_scalar={'emissivecolor':'0.125 0.25 0.5','emissivebrightness':1},
            pbr_map={'rgba':[0,0,0,0],'instance_rgba':[0,0,0,255],'flags':1<<23})

    def test_emission_animation_uses_current_map_frame(self):
        result=self.run_normal(no_normal=True,no_lights=True,scalar_values={'emissivecolor':'0.25 0.5 0.125'},
            pbr_map={'rgba':[0,0,0,0],'next_rgba':[0,0,0,255],'flags':1<<23,'animated':True})
        for key,wanted in [('scene-ready-window.png',[0,0,0]),('scene-after-window.png',[64,128,32])]:
            for actual,expected in zip(result[key]['roiMean'],wanted):self.assertLessEqual(abs(actual-expected),2,result)

    def test_lighting_zero_does_not_admit_emission(self):
        self.check_map([128]*3,no_lights=True,lighting=0,pbr_map={'rgba':[255]*4,'flags':11<<20})

if __name__=='__main__':unittest.main()
