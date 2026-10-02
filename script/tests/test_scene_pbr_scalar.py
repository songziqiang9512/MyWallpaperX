#!/usr/bin/env python3
"""Real Metal base-capture/composition behavior for bounded 2D material lighting."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from script.tests import test_scene_texture_candidate as texture_fixture

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / 'MyWallpaperX/Core/SteamWorkshopScene'

class ScenePBRScalarTests(unittest.TestCase):
    def test_startup_property_resolution_reaches_profile(self):
        from script.tests import test_scene_timeline_document as document, test_scene_user_properties as properties
        support=document.HARNESS_SOURCE.split('@main',1)[0]
        start=support.index('enum SceneUserPropertyValue {}');end=support.index('struct ScenePkgExtractionReport')
        support=support[:start]+support[end:]
        support+=r'''
enum SceneTextureLoadPurpose { case normal }
struct SceneAssetTextureIdentity: Hashable, Sendable {
    init?(virtualPath:String,purpose:SceneTextureLoadPurpose) {}
}
struct SceneRenderDescriptor {
    struct Layer { let id=1; let isImageRenderable=true; let imagePath:String?=nil }
    struct Link { let modelPath:String; let materialPath:String? }
    struct MaterialPassDescriptor {
        let materialPath="material"; let shaderPath:String?="genericimage2"
        let combos=["LIGHTING":1]; let textureSlots:[String?]=[]
        let userTextureInputs:[SceneEffectTextureInput?]=[]
        var constantShaderValues:[String:SceneDocument.ShaderValue]=[:]
    }
    let modelMaterialLinks:[Link]=[];let materialPasses:[MaterialPassDescriptor]=[];let layers:[Layer]=[]
}
@main enum StartupProbe {
    static func main() throws {
        let url=URL(fileURLWithPath:CommandLine.arguments[1])
        let catalog=SceneUserPropertyDefinitionParser().parse(properties:["m":["type":"slider","value":0.2]])
        let doc=try SceneDocumentLoader().load(from:url,propertyCatalog:catalog,propertyOverrides:["m":.number(0.8)])
        let profiles=doc.objects.map { object in
            SceneBaseMaterialLightingProfileCompiler.profile(layer:.init(),materialInstance:object.materialInstance,
                materialPasses:[.init()]).scalarMaterial!.x
        }
        let unresolved:[Any]=["m",["name":"m"],17]
        let unbound=unresolved.map { user in
            var pass=SceneRenderDescriptor.MaterialPassDescriptor()
            pass.constantShaderValues=["metallic":SceneDocumentLoader.shaderValue(from:["user":user,"value":0.8])]
            return SceneBaseMaterialLightingProfileCompiler.profile(layer:.init(),materialInstance:nil,materialPasses:[pass]).scalarMaterial!.x
        }
        print(String(decoding:try JSONSerialization.data(withJSONObject:["profiles":profiles,"unbound":unbound]),as:UTF8.self))
    }
}
'''
        with tempfile.TemporaryDirectory(prefix='mwx-pbr-startup-') as temporary:
            work=Path(temporary);source=work/'Probe.swift';source.write_text(support);binary=work/'probe'
            declarations=[{'user':'m','value':.2},{'user':{'name':'m'},'value':.2},
                          {'user':'missing','value':.8},{'user':17,'value':.8},
                          {'user':'m','value':.2,'script':'export function update(v){return v;}'},
                          {'user':'m','value':.8},{'user':'missing','value':None}]
            scene=work/'scene.json';scene.write_text(json.dumps({'objects':[{'id':i+1,'instance':{'constantshadervalues':{'metallic':v}}} for i,v in enumerate(declarations)]}))
            sources=list(dict.fromkeys([p for p in document.SWIFT_SOURCES if p.name != 'SceneUserPropertyResolutionStub.swift']+properties.SWIFT_SOURCES+[SCENE/'Compilation/Material/SceneBaseMaterialLightingProfile.swift',SCENE/'Compilation/ShaderContract/SceneBuiltinShaderIdentity.swift']))
            compiled=subprocess.run(['xcrun','swiftc',*map(str,sources),str(source),'-module-cache-path',str(work/'cache'),'-o',str(binary)],capture_output=True,text=True)
            self.assertEqual(compiled.returncode,0,compiled.stderr)
            result=subprocess.run([str(binary),str(scene)],capture_output=True,text=True);self.assertEqual(result.returncode,0,result.stderr)
            report=json.loads(result.stdout);print(report)
            for actual,expected in zip(report['profiles'],[.8,.8,.8,.5,.5,.8,.5]):self.assertAlmostEqual(actual,expected,places=6,msg=str(report))
            self.assertEqual(report['unbound'],[.5,.5,.5],report)

    def test_typed_instance_scalar_projection(self):
        from script.tests import test_scene_timeline_document as document
        with tempfile.TemporaryDirectory(prefix="mwx-pbr-instance-") as temporary:
            work=Path(temporary); source=work/'Harness.swift'; binary=work/'probe'
            source.write_text(document.HARNESS_SOURCE.split('@main',1)[0]+r'''
@main enum ScalarParserProbe {
    static func main() throws {
        let value: [String:Any] = ["constantshadervalues":["metallic":0.2,"roughness":"0.7","future":99]]
        let a=SceneDocument.SceneLayerMaterialInstance.parse(value)!
        precondition(a.scalarShaderValues!.keys.sorted() == ["metallic","roughness"])
        precondition(a.scalarShaderValues?["metallic"]?.components == [0.2])
        precondition(a.scalarShaderValues?["roughness"]?.components == [0.7])
        let encoded=try JSONEncoder().encode(a)
        var oldShape=try JSONSerialization.jsonObject(with:encoded) as! [String:Any]
        oldShape.removeValue(forKey:"scalarShaderValues")
        let oldData=try JSONSerialization.data(withJSONObject:oldShape)
        let legacy=try JSONDecoder().decode(SceneDocument.SceneLayerMaterialInstance.self,from:oldData)
        precondition(legacy.scalarShaderValues == nil)
        let decoded = try JSONDecoder().decode(SceneDocument.SceneLayerMaterialInstance.self,from:encoded)
        precondition(decoded == a)
        let malformed=SceneDocument.SceneLayerMaterialInstance.parse(["constantshadervalues":NSNull()])!
        precondition(malformed.scalarShaderValues?.count == 2)
        precondition(malformed.scalarShaderValues!.values.allSatisfy { $0.components == nil })
        let dynamic=SceneDocument.SceneLayerMaterialInstance.parse(["constantshadervalues":["roughness":["value":0.2,"script":"export function update(v){return v;}"]]])!
        precondition(dynamic.scalarShaderValues?["roughness"]?.scriptSource != nil)
        let resolved=SceneDocument.SceneLayerMaterialInstance.parse(value,authoredRaw:["constantshadervalues":["metallic":["user":"metal","value":0.9]]])!
        precondition(resolved.scalarShaderValues?["metallic"]?.components == [0.2])
        precondition(resolved.rawValue != a.rawValue)
        print("typed-instance: scalar/string/malformed/dynamic/resolved/roundtrip PASS")
    }
}
''')
            compiled=subprocess.run(['xcrun','swiftc',*[str(p) for p in document.SWIFT_SOURCES],str(source),'-module-cache-path',str(work/'module-cache'),'-o',str(binary)],capture_output=True,text=True)
            self.assertEqual(compiled.returncode,0,compiled.stderr)
            result=subprocess.run([str(binary)],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)

    def test_scalar_response_and_half_storage(self):
        with tempfile.TemporaryDirectory(prefix='scene-lit-image-') as temporary:
            work = Path(temporary)
            air = []
            for name in ['SceneImageLayer', 'SceneLitImageLayer']:
                output = work / (name + '.air')
                subprocess.run(['xcrun','-sdk','macosx','metal','-c',str(SCENE / 'Rendering/Composition' / (name+'.metal')),'-o',str(output)],check=True,capture_output=True,text=True)
                air.append(str(output))
            library = work / 'fixture.metallib'
            subprocess.run(['xcrun','-sdk','macosx','metallib',*air,'-o',str(library)],check=True,capture_output=True,text=True)
            sources = ['Rendering/Metal/SceneMetalPipeline.swift','Rendering/Metal/SceneLitImageLayerPipeline.swift',
                'Rendering/Composition/SceneOffscreenEffectRenderer+Capture.swift',
                'Diagnostics/ScenePerformanceCounterHub.swift','Diagnostics/SceneGPUCensus.swift']
            support = work / 'Support.swift'
            support.write_text(texture_fixture.HARNESS.split('@main', 1)[0] + 'import simd\nenum SceneMatrix { static func scale(_ v: SIMD3<Float>) -> simd_float4x4 { simd_float4x4(diagonal: SIMD4(v,1)) } }\n')
            binary = work / 'fixture'
            compiled = subprocess.run(['xcrun','swiftc','-D','SCENE_AUTHORED_NORMAL','-parse-as-library',*[str(p) for p in dict.fromkeys(texture_fixture.SWIFT_SOURCES + [SCENE / s for s in sources])],str(support),str(ROOT/'script/tests/fixtures/SceneLitImageLayerHarness.swift'),str(ROOT/'script/tests/fixtures/ScenePBRScalarHarness.swift'),'-module-cache-path',str(work/'module-cache'),'-o',str(binary)],capture_output=True,text=True)
            self.assertEqual(compiled.returncode,0,compiled.stderr)
            arguments=[str(binary),str(library)]
            if baseline:=os.environ.get('MWX_PBR_TIMING_LIBRARY'): arguments.append(baseline)
            result = subprocess.run(arguments,capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            report = json.loads(result.stdout)
            self.assertEqual(report['count'],31)
            print(json.dumps(report,sort_keys=True))
            if destination:=os.environ.get("MWX_PBR_EVIDENCE"):
                Path(destination).write_text(json.dumps(report,indent=2))

class ScenePBRScalarIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import hashlib
        value=os.environ.get('MWX_SCENE_INTEGRATION_APP')
        if not value: raise unittest.SkipTest('requires frozen Debug App executable')
        cls.app=Path(value).resolve(strict=True)
        cls.execution_test_sha=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()

    def run_case(self, name, *, expected, **kwargs):
        from script.tests.test_scene_authored_normal import SceneAuthoredNormalIntegrationTests
        self.scenario_id=name
        result=SceneAuthoredNormalIntegrationTests.run_normal(self,no_normal=True,**kwargs)
        for frame,value in result.items():
            self.assertLessEqual(abs(value['roiMean'][0]-expected),2,(name,frame,expected,value))
        return result

    def test_plain_scalar_material_response(self):
        from script.tests.test_scene_authored_normal import pbr_expected
        for shader,m,r in [('genericimage2',1,.5),('genericimage2',1,1),('genericimage4',0,1),('genericimage4',1,1)]:
            expected=pbr_expected(light=(0,0,100),metallic=m,roughness=r,intensity=.2)
            self.run_case(f'{shader}-{m}-{r}',expected=expected,shader=shader,
                scalar_values={'metallic':m,'roughness':r},light_origin='80 48 100',intensity=.2)

    def test_effect_scalar_material_response(self):
        from script.tests.test_scene_authored_normal import pbr_expected
        for r in [.5,1]:
            expected=pbr_expected(light=(0,0,100),metallic=1,roughness=r,intensity=.2)/2
            self.run_case(f'dim-{r}',expected=expected,effect=True,
                scalar_values={'metallic':1,'roughness':r},light_origin='80 48 100',intensity=.2)

    def test_defaults_instance_zero_and_local_invalid(self):
        from script.tests.test_scene_authored_normal import pbr_expected
        cases=[('default2','genericimage2',None,None,.5,.5),
               ('default4','genericimage4',None,None,0,.7),
               ('instance-zero','genericimage2',{'metallic':1,'roughness':1},{'metallic':0},0,1),
               ('instance-invalid','genericimage4',{'metallic':1,'roughness':1},{'metallic':None},0,1)]
        for name,shader,values,instance,m,r in cases:
            self.run_case(name,expected=pbr_expected(light=(0,0,100),metallic=m,roughness=r,intensity=.2),
                shader=shader,scalar_values=values,instance_scalar=instance,light_origin='80 48 100',intensity=.2)

    def test_startup_user_property_and_authored_fallback(self):
        from script.tests.test_scene_authored_normal import pbr_expected
        for name,user,defaults in [('resolved','m',{'m':{'type':'slider','value':.8}}),('fallback','missing',{})]:
            self.run_case(name,expected=pbr_expected(light=(0,0,100),metallic=.8,roughness=.5,intensity=.2),
                scalar_values={'roughness':.5},instance_scalar={'metallic':{'user':user,'value':.8 if name=='fallback' else .2}},
                property_defaults=defaults,light_origin='80 48 100',intensity=.2)

    def test_reflection_does_not_gate_direct_and_lighting_zero(self):
        from script.tests.test_scene_authored_normal import pbr_expected
        self.run_case('reflection1',expected=pbr_expected(light=(0,0,100),metallic=1,roughness=1,intensity=.2),
            reflection=1,scalar_values={'metallic':1,'roughness':1},light_origin='80 48 100',intensity=.2)
        self.run_case('lighting0',expected=128,lighting=0,scalar_values={'metallic':1,'roughness':0})

    def test_native_camera_eye_changes_specular(self):
        from script.tests.test_scene_authored_normal import pbr_expected
        for offset in [-100,100]:
            camera={'eye':f'{80+offset} 48 100','center':'80 48 0','up':'0 1 0'}
            self.run_case(f'eye{offset}',expected=pbr_expected(view=(offset,0,100)),native_camera=camera)

if __name__ == '__main__': unittest.main()
