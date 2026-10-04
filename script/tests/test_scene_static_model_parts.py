#!/usr/bin/env python3
"""RF16 complete material parts through real reader/resources/frame owner and App.

The native resource probe supplies descriptor fields and a deterministic texture
transport at the outside boundary. Reader, resource prepare, material extraction,
mesh upload, native accounting, frame draw/depth and Metal are production code.
The separate actual builder probe and App exercise the authored disk chain.
"""
import hashlib
import json
import math
import os
from pathlib import Path
import re
import struct
import subprocess
import tempfile
import unittest

from script.tests import test_scene_static_model_reader as reader
from script.tests import test_scene_directional_shadow_frame_owner as frame
from script.tests import test_scene_directional_shadow as native
from script.tests import test_scene_alpha_display_builder_fixture as builder
from script.tests.test_scene_directional_shadow_integration import png, quad, make_package

REPO = Path(__file__).resolve().parents[2]
SCENE = REPO/'MyWallpaperX/Core/SteamWorkshopScene'
RESOURCE_SOURCE = SCENE/'Resources/Textures/ScenePreparedStaticModelResources.swift'
MODEL_METAL = SCENE/'Rendering/Composition/SceneStaticModel.metal'
PALETTE = [[255,0,0,255],[0,255,0,255],[0,0,255,255],[255,255,0,255],
           [255,0,255,255],[0,255,255,255],[255,255,255,255],[0,0,0,255]]


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def join_parts(blobs):
    """Assemble complete MDLV0023 bodies, preserving file order."""
    result = bytearray(blobs[0][:-7])
    struct.pack_into('<I', result, 17, len(blobs))
    for blob in blobs[1:]:
        result.extend(b'\0'*6 + blob[21:-7])
    return bytes(result) + b'\0'*7


def native_fixture(count, *, bad=False, overlap=False):
    entries = {}
    parts = []
    expected = []
    for i in range(count):
        x, y = (i % 8)*16+8, (i//8)*16+8
        if overlap:
            x, y = 32, 32
        path = f'materials/part{i:03}.json'
        geometry = quad(x-5,x+5,y-5,y+5,float(i) if overlap else 0,path)
        parts.append(geometry)
        # 64 independent byte colors; none equal the clear pixel or each other.
        rgba = [32 + (i % 4)*64, 32 + ((i//4) % 4)*64, 32+(i//16)*64, 255]
        if overlap:
            rgba = PALETTE[i % 8]
        entries[f'materials/part{i:03}.rgba'] = bytes(rgba)
        entries[f'materials/part{i:03}.png'] = png(rgba)
        entries[path] = json.dumps({'passes':[{'shader':'genericimage',
            'textures':[f'materials/part{i:03}.png'], 'combos':{'LIGHTING':0},
            'constantshadervalues':{'alpha': .5 if overlap else 1},
            'blending':'translucent' if overlap else 'normal',
            'depthwrite':'disabled' if overlap else 'enabled'}]}).encode()
        expected.append({'material':path,'point':[x,y],'rgba':rgba})
    model = join_parts(parts)
    if bad:
        model = model[:-13]
    entries['models/parts.mdl'] = model
    entries['models/peer.mdl'] = quad(140,152,4,16,0,'materials/peer.json')
    entries['materials/peer.rgba'] = bytes([255,255,255,255])
    entries['materials/peer.png'] = png([255,255,255,255])
    entries['materials/peer.json'] = json.dumps({'passes':[{'shader':'genericimage',
        'textures':['materials/peer.png'],'combos':{'LIGHTING':0}}]}).encode()
    scene={'version':3,'general':{'orthogonalprojection':{'width':160,'height':128}},'objects':[
        {'id':1,'model':'models/peer.mdl','origin':'0 128 0','perspective':False},
        {'id':2,'model':'models/parts.mdl','origin':'0 128 0','perspective':False}]}
    entries['scene.json']=json.dumps(scene).encode()
    entries['project.json']=json.dumps({'type':'scene','file':'scene.json'}).encode()
    return entries, expected


def freeze_inputs(label, variants):
    parent=os.environ.get('MWX_MODEL_PARTS_EVIDENCE')
    if parent: Path(parent).mkdir(parents=True,exist_ok=True)
    root=Path(tempfile.mkdtemp(prefix=f'model-parts-{label}-',dir=parent))
    manifest={}
    for name,(entries,expected) in variants.items():
        target=root/name
        for relative,data in entries.items():
            path=target/relative;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
        manifest[name]={'expected':expected,'inputs':{p:sha(target/p) for p in entries}}
    sources=[Path(__file__),Path(reader.__file__),Path(frame.__file__),Path(native.__file__)]
    for p in sources:(root/('source-'+p.name)).write_bytes(p.read_bytes())
    manifest['testSources']={str(p):sha(p) for p in sources}
    (root/'protocol.json').write_text(json.dumps(manifest,indent=2))
    print(f'RF16 frozen {label}: {root}',flush=True)
    return root


BUILDER_MAIN=r'''
@main enum PartsDependencies {
 static func main() throws {
  let input=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [String:String]
  let root=URL(fileURLWithPath:input["root"]!);var rows:[[String:Any]]=[]
  for name in ["parts5","parts8","parts64","bad8"] {
   let model=try SceneRuntimeModelBuilder().build(rootURL:root.appendingPathComponent(name))
   let d=model.renderDescriptor
   rows.append(["name":name,"links":d.modelMaterialLinks.filter{$0.modelPath=="models/parts.mdl"}.map(\.materialPath),
      "passes":d.materialPasses.filter{$0.materialPath.hasPrefix("materials/part")}.map{["material":$0.materialPath,"textures":$0.textureSlots.map{$0 ?? ""},"combos":$0.combos] as [String:Any]}])
  }
  print(String(decoding:try JSONSerialization.data(withJSONObject:["rows":rows]),as:UTF8.self))
 }
}
'''


def builder_support():
    s=builder.HARNESS_SOURCE.split('@main',1)[0]
    start=s.index('enum SceneMdlStaticModelReader {');end=s.index('nonisolated struct SceneScriptScalarProgram',start)
    return s[:start]+s[end:]+BUILDER_MAIN


class SceneModelPartsDependencyTests(unittest.TestCase):
    def test_actual_builder_complete_validated_material_dependencies(self):
        root=freeze_inputs('dependencies',{**{f'parts{n}':native_fixture(n) for n in [5,8,64]},'bad8':native_fixture(8,bad=True)})
        report=native.run_swift(list(dict.fromkeys([*builder.SWIFT_SOURCES,*reader.SWIFT_SOURCES])),builder_support(),
            label='parts-dependencies',input_value={'root':str(root)})
        for row in report['rows']:
            if row['name']=='bad8':
                self.assertEqual(row['links'],[])
                # The global disk material catalog survives an unrelated model rejection.
                self.assertEqual(len(row['passes']),8)
                continue
            count=int(row['name'][5:]);expected=[f'materials/part{i:03}.json' for i in range(count)]
            self.assertEqual(row['links'],expected)
            self.assertEqual({p['material'] for p in row['passes']},set(expected))
            for p in row['passes']:
                self.assertEqual(p['textures'],[p['material'].replace('.json','.png')])
                self.assertEqual(p['combos']['LIGHTING'],0)


# Native transport only. All material flags/extraction, reader, mesh upload and
# partial allocation policy remain inside the production resource owner.
RESOURCE_TRANSPORT=r'''
struct SceneDocument {
 struct ShaderValue {let components:[Double];var userBinding:Int?=nil;var scriptSource:String?=nil}
}
struct SceneResourceView {
 struct Resource {let url:URL}
 let root:URL
 func resource(relativePath:String)->Resource? {
  let url=root.appendingPathComponent(relativePath)
  return FileManager.default.fileExists(atPath:url.path) ? Resource(url:url):nil
 }
}
struct SceneTexturePathResolver {
 let resourceView:SceneResourceView;let descriptor:SceneRenderDescriptor
 func resolveTextureFile(named path:String)->URL? {resourceView.resource(relativePath:path)?.url}
}
final class SceneTextureLoader {
 enum Result {case loaded(SceneTextureCandidate);case missing}
 var candidates:[String:SceneTextureCandidate]=[:]
 init(root:URL,device:MTLDevice)throws {
  let paths=try FileManager.default.contentsOfDirectory(at:root.appendingPathComponent("materials"),includingPropertiesForKeys:nil)
  for path in paths where path.pathExtension=="rgba" {
   let td=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:1,height:1,mipmapped:false)
   td.storageMode = .shared;td.usage = .shaderRead
   let texture=device.makeSceneTexture(descriptor:td)!
   let data=try Data(contentsOf:path)
   data.withUnsafeBytes{texture.replace(region:MTLRegionMake2D(0,0,1,1),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:4)}
   let png=path.deletingPathExtension().appendingPathExtension("png")
   candidates[png.path] = .init(texture:texture,identity:.file(path:png.path),generation:.immutable(revision:1),purpose:.straightAlbedo,
      content:.data,physicalSize:CGSize(width:1,height:1),mappedSize:CGSize(width:1,height:1),uvTransform:.identity,sampling:.directImageFallback)
  }
 }
 func loadCandidate(from url:URL,purpose:SceneTextureLoadPurpose,device:MTLDevice)->Result {
  precondition(purpose == .straightAlbedo)
  return candidates[url.path].map{.loaded($0)} ?? .missing
 }
}
extension SceneRenderDescriptor {
 struct ColorTargetFormat {var metalPixelFormat:MTLPixelFormat { .bgra8Unorm }}
 struct MaterialPassDescriptor {
  let materialPath:String;let textureSlots:[String?];let combos:[String:Int]
  let constantShaderValues:[String:SceneDocument.ShaderValue];var passIndex:Int=0;var depthWrite:String?=nil
  var staticModelMaterialBindings:SceneStaticModelMaterialBindings?=nil;var cullMode:String?=nil
 }
}
'''


def resource_support():
    s=frame.SHELL
    start=s.index('struct ScenePreparedStaticModelResources {');end=s.index('struct NamedAlbedo',start)
    s=s[:start]+s[end:]
    s=s.replace('expectedReference:String','expectedReference:SceneNamedTextureReference')
    s=s.replace('var colorBlendMode:Int? = nil','var colorBlendMode:Int? = nil;var staticModelPath:String?=nil')
    s=s.replace(' let lighting:LightingDescriptor?;let layers:[Layer];let renderOrderLayerIDs:[Int]',
                ' let lighting:LightingDescriptor?;let layers:[Layer];let renderOrderLayerIDs:[Int]\n var materialPasses:[MaterialPassDescriptor]=[];let colorTargetFormat=ColorTargetFormat();var hdrEnabled:Bool=false')
    return frame.pool_fixture.HARNESS.split('@main',1)[0]+s+frame.UNUSED_ORDERED_SUPPORT+RESOURCE_TRANSPORT


NATIVE_SOURCES=list(dict.fromkeys([*frame.SOURCES,*reader.SWIFT_SOURCES,RESOURCE_SOURCE,
    SCENE/'Runtime/Frame/SceneStaticModelMaterialBindings.swift',
    SCENE/'Compilation/Material/SceneMaterialRenderState.swift',
    SCENE/'Resources/Textures/SceneNamedTextureReference.swift']))

NATIVE_MAIN=r'''
@main enum PartsResourceProbe {
 static func main() throws {
  guard let device=MTLCreateSystemDefaultDevice(),let queue=device.makeCommandQueue() else {fatalError("Metal unavailable")}
  let input=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [String:String]
  let root=URL(fileURLWithPath:input["root"]!)
  var rows:[[String:Any]]=[]
  for (name,fixture) in [("parts5","parts5"),("parts8","parts8"),("parts64","parts64"),
                          ("bad8","bad8"),("quota","parts8"),("recovery","parts8"),("overlap","overlap") ] {
   let before=SceneResourceBudget.shared.snapshot.residentBytes
   var row=try autoreleasepool {try run(name,root.appendingPathComponent(fixture),device,queue)}
   row["budgetBefore"]=before;row["budgetAfter"]=SceneResourceBudget.shared.snapshot.residentBytes
   rows.append(row)
  }
  print(String(decoding:try JSONSerialization.data(withJSONObject:["rows":rows]),as:UTF8.self))
 }
 static func run(_ mode:String,_ root:URL,_ device:MTLDevice,_ queue:MTLCommandQueue)throws->[String:Any] {
  let files=try FileManager.default.contentsOfDirectory(at:root.appendingPathComponent("materials"),includingPropertiesForKeys:nil).filter{$0.pathExtension=="json"}
  let passes=try files.map {url -> SceneRenderDescriptor.MaterialPassDescriptor in
   let object=try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as! [String:Any]
   let pass=(object["passes"] as! [[String:Any]])[0]
   let constants=(pass["constantshadervalues"] as? [String:Double] ?? [:]).mapValues{SceneDocument.ShaderValue(components:[$0])}
   return .init(materialPath:"materials/"+url.lastPathComponent,textureSlots:(pass["textures"] as! [String]).map{Optional($0)},
       combos:pass["combos"] as! [String:Int],constantShaderValues:constants,depthWrite:pass["depthwrite"] as? String)
  }
  let layers=[SceneRenderDescriptor.Layer(id:1,staticModelPath:"models/peer.mdl"),.init(id:2,staticModelPath:"models/parts.mdl")]
  let descriptor=SceneRenderDescriptor(lighting:nil,layers:layers,renderOrderLayerIDs:[1,2],materialPasses:passes)
  let loader=try SceneTextureLoader(root:root,device:device)
  let meshCost=device.heapBufferSizeAndAlign(length:4*MemoryLayout<SceneMdlStaticModel.Vertex>.stride,options:.storageModeShared).size
       + device.heapBufferSizeAndAlign(length:6*MemoryLayout<UInt32>.stride,options:.storageModeShared).size
  let rejectionBefore=SceneResourceBudget.shared.snapshot.rejectionCount
  var held=0
  if mode=="quota" {
   held=SceneResourceBudget.shared.maximumBytes-SceneResourceBudget.shared.snapshot.residentBytes-3*meshCost
   precondition(SceneResourceBudget.shared.reserve(held,kind:.gpu))
  }
  defer {if held>0 {SceneResourceBudget.shared.release(held,kind:.gpu)}}
  let resources=try ScenePreparedStaticModelResources.prepare(descriptor:descriptor,resourceView:.init(root:root),device:device,
      textureLoader:loader,cancellationCheck:{})
  let rejected=SceneResourceBudget.shared.snapshot.rejectionCount-rejectionBefore
  if held>0 {SceneResourceBudget.shared.release(held,kind:.gpu);held=0}
  let renderer=SceneMetalRenderer(device:device,resources:resources)
  let dynamic=SceneDynamicSnapshot.empty(frameIndex:1,generation:1)
  let world=[1:matrix_identity_float4x4,2:matrix_identity_float4x4]
  let camera=SceneParticleCameraFrame(camera:.init(eye:[0,0,0],center:[0,0,-1],up:[0,1,0],orthoWidth:160,
      orthoHeight:128,fovDegrees:nil,perspectiveOverrideFOVDegrees:nil,nearZ:0.01,farZ:1000),viewportSize:CGSize(width:160,height:128))
  let lighting=SceneLightSnapshot(ambient:.zero,directional:[],point:[],spot:[],overflowCount:0)
  let td=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:160,height:128,mipmapped:false)
  td.storageMode = .shared;td.usage=[.renderTarget,.shaderRead]
  let target=device.makeTexture(descriptor:td)!
  var frames:[[[Int]]]=[];var leaseCounts:[Int]=[]
  for _ in 0..<2 {
   let cb=queue.makeCommandBuffer()!
   let pass=SceneMainPassEncoder(commandBuffer:cb,target:target,clearColor:MTLClearColorMake(0,0,0,1),clearEnabled:true)
   let state=SceneMetalRenderer.StaticModelFrame();var leases:[SceneParticleDepthTargetLease]=[]
   for layer in layers {
    _=renderer.drawStaticModel(layer:layer,state:state,worldFrames:world,frameContext:.init(dynamicValues:dynamic),cameraFrame:camera,
       lighting:lighting,pass:pass,commandBuffer:cb,leases:&leases)
   }
   precondition(pass.finishEnsuringClear());leaseCounts.append(leases.count)
   leases.forEach{$0.arm(on:cb)};state.arm(on:cb);cb.commit();cb.waitUntilCompleted()
   precondition(cb.status == .completed && cb.error == nil)
   var bytes=[UInt8](repeating:0,count:160*128*4)
   target.getBytes(&bytes,bytesPerRow:160*4,from:MTLRegionMake2D(0,0,160,128),mipmapLevel:0)
   func rgba(_ x:Int,_ y:Int)->[Int] {let i=(y*160+x)*4;return [Int(bytes[i+2]),Int(bytes[i+1]),Int(bytes[i]),Int(bytes[i+3])]}
   var pixels=(0..<64).map{rgba(($0%8)*16+8,($0/8)*16+8)}
   pixels.append(rgba(146,10));pixels.append(rgba(32,32));frames.append(pixels)
  }
  let parts=resources[2] ?? []
  let row:[String:Any]=["mode":mode,"parts":parts.map(\.materialPath),"identities":parts.map(\.geometryIdentity),
      "materials":parts.map{[$0.material.color.x,$0.material.color.y,$0.material.color.z,$0.material.opacity]},
      "textureIDs":parts.map{String(describing:$0.albedo!.identity)},
      "meshIndexCounts":parts.map{$0.mesh.indexCount},"peerParts":resources[1]?.count ?? 0,"rejections":rejected,
      "frames":frames,"leaseCounts":leaseCounts,"completed":true,"encoded":renderer.dependencyRuntime.encoded[2] ?? false]
  return row
 }
}
'''


class SceneModelPartsNativeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root=freeze_inputs('native',{**{f'parts{n}':native_fixture(n) for n in [5,8,64]},
            'bad8':native_fixture(8,bad=True),'overlap':native_fixture(2,overlap=True)})
        cls.report=native.run_swift(NATIVE_SOURCES,resource_support()+NATIVE_MAIN,label='parts-native',
            metal_sources=[MODEL_METAL],input_value={'root':str(cls.root)})
        cls.rows={r['mode']:r for r in cls.report['rows']}

    def test_actual_resource_owner_prepares_and_main_loop_consumes_all_5_8_64(self):
        for count in [5,8,64]:
            row=self.rows[f'parts{count}'];expected=native_fixture(count)[1]
            self.assertEqual(row['parts'],[p['material'] for p in expected])
            self.assertEqual(len(set(row['identities'])),count)
            self.assertEqual(len(set(row['textureIDs'])),count)
            self.assertEqual(row['meshIndexCounts'],[6]*count)
            self.assertTrue(row['encoded']);self.assertTrue(row['completed'])
            for actual,want in zip(row['frames'][0],expected):
                for a,b in zip(actual,want['rgba']):self.assertLessEqual(abs(a-b),1,(count,actual,want))
            self.assertEqual(row['frames'][0],row['frames'][1])
            self.assertEqual(row['leaseCounts'],[1,1])

    def test_later_native_quota_failure_preserves_prefix_peer_and_new_load_recovers(self):
        row=self.rows['quota'];full=self.rows['recovery']
        self.assertEqual(row['parts'],['materials/part000.json','materials/part001.json'])
        self.assertGreater(row['rejections'],0)
        self.assertEqual(row['peerParts'],1)
        self.assertEqual(row['frames'][0][:2],full['frames'][0][:2])
        self.assertEqual(row['frames'][0][64],[255,255,255,255])
        self.assertEqual(row['frames'][0][2:8],[[0,0,0,255]]*6)
        self.assertEqual(full['parts'],self.rows['parts8']['parts'])
        self.assertEqual(full['frames'],self.rows['parts8']['frames'])
        for r in self.report['rows']:self.assertEqual(r['budgetAfter'],r['budgetBefore'],r['mode'])

    def test_bad_later_structure_rejects_model_but_peer_still_draws(self):
        row=self.rows['bad8'];self.assertEqual(row['parts'],[])
        self.assertEqual(row['frames'][0][:64],[[0,0,0,255]]*64)
        self.assertEqual(row['frames'][0][64],[255,255,255,255])
        self.assertEqual(row['frames'][0],row['frames'][1])

    def test_authored_segment_order_and_opacity_are_consumed(self):
        row=self.rows['overlap'];self.assertEqual(row['materials'],[[1,1,1,.5]]*2)
        # Authored red then green, each coverage .5, over black: .25 red + .5 green.
        for actual,want in zip(row['frames'][0][65],[64,128,0,255]):self.assertLessEqual(abs(actual-want),1)
        self.assertEqual(row['frames'][0],row['frames'][1])


def app_fixture(count, cast=True):
    """Independent world rectangles; ray toward (.6,0,1) shifts z20 by -12X."""
    centers=[30,54,78,102,126] if count==5 else [17,35,53,71,89,107,125,143]
    objects=[{'id':4,'model':'models/background.mdl','origin':'0 96 0','perspective':False,'castshadow':False},
             {'id':1,'model':'models/receivers.mdl','origin':'0 96 0','perspective':False,'castshadow':False},
             {'id':2,'model':'models/parts.mdl','origin':'0 96 0','perspective':False,'castshadow':cast},
             {'id':3,'light':'ldirectional','angles':f'0 {math.atan(.6)} 0','intensity':.7,'color':'1 1 1','castshadow':count==5}]
    scene={'version':3,'general':{'orthogonalprojection':{'width':160,'height':96},
        'clearcolor':'0 0 0','ambientcolor':'0.05 0.05 0.05','skylightcolor':'0 0 0'},'objects':objects}
    entries={'scene.json':json.dumps(scene).encode(),
        'project.json':json.dumps({'type':'scene','file':'scene.json'}).encode(),
        'models/background.mdl':quad(5,155,5,91,-1,'materials/background.json'),
        'materials/background.png':png([64,64,64,255]),
        'materials/background.json':json.dumps({'passes':[{'shader':'genericimage','textures':['materials/background.png'],'combos':{'LIGHTING':0}}]}).encode()}
    caster_parts=[];receiver_parts=[];rois={};oracle=[]
    for i,x in enumerate(centers):
        material=f'materials/part{i:03}.json';texture=f'materials/part{i:03}.png'
        caster_parts.append(quad(x-3,x+3,44,52,20,material))
        rgba=PALETTE[i]
        entries[texture]=png(rgba)
        entries[material]=json.dumps({'passes':[{'shader':'genericimage','textures':[texture],
            'combos':{'LIGHTING':int(count==5)},'depthwrite':'enabled'}]}).encode()
        receiver_x=x-12
        receiver_path=f'materials/receiver{i:03}.json'
        receiver_parts.append(quad(receiver_x-4,receiver_x+4,44,52,0,receiver_path))
        entries[receiver_path]=json.dumps({'passes':[{'shader':'genericimage','textures':['materials/receiver.png'],
            'combos':{'LIGHTING':1},'depthwrite':'enabled'}]}).encode()
        rois[f'part{i}']=[x,48]
        if count==5:rois[f'shadow{i}']=[receiver_x,48]
        # Each selected receiver ray meets only its corresponding elevated quad.
        hit_x=receiver_x+20*.6
        hits=[j for j,c in enumerate(centers) if c-3<=hit_x<=c+3]
        assert hits==[i]
        assert all(not (c-3<=receiver_x<=c+3) for c in centers)
        oracle.append({'part':i,'receiver':[receiver_x,48,0],'hit':[hit_x,48,20],'positiveRayT':20,'hitPartIndices':hits})
    entries['materials/receiver.png']=png([180,180,180,255])
    entries['models/parts.mdl']=join_parts(caster_parts)
    entries['models/receivers.mdl']=join_parts(receiver_parts)
    rois['healthy']=[145,70]
    return scene,entries,{'count':count,'rois':rois,'palette':PALETTE[:count],'geometry':oracle,
        'mapping':'cover max(W/160,H/96), center + (worldXY-[80,48])*cover',
        'thresholds':{'shadowDarkening':20,'healthyOnOffExact':True,'casterOnOffExact':True,'colorOnMinimum':30,'colorOffMaximum':2,'readyAfterWholeExact':True}}


class SceneModelPartsAppTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        app=os.environ.get('MWX_MODEL_PARTS_APP')
        if not app:raise unittest.SkipTest('immutable MWX_MODEL_PARTS_APP required')
        cls.app=Path(app).resolve(strict=True)
        cls.exe=cls.app/'Contents/MacOS/MyWallpaperX'
        binaries=[cls.exe,cls.exe.parent/'MyWallpaperX.debug.dylib',cls.app/'Contents/Resources/default.metallib',
                  cls.app/'Contents/Helpers/glslang',cls.app/'Contents/Helpers/spirv-cross']
        # Helper exact paths come from this immutable build's receipt when supplied.
        receipt=os.environ.get('MWX_MODEL_PARTS_APP_IDENTITY')
        if receipt:
            identity=json.loads(Path(receipt).read_text())
            # The App's own five-file identity is frozen again below; no dynamic lookup of runtime evidence.
            cls.buildReceipt={'path':receipt,'sha256':sha(receipt)}
        else:cls.buildReceipt=None
        cls.binaries=binaries
        assert all(p.is_file() for p in cls.binaries),cls.binaries
        if receipt:
            assert identity['app']==str(cls.app)
            assert {str(p.relative_to(cls.app)):sha(p) for p in cls.binaries}==identity['files']
        reuse=os.environ.get('MWX_MODEL_PARTS_APP_PROTOCOL_ROOT')
        if reuse:
            cls.root=Path(reuse);cls.protocol=json.loads((cls.root/'protocol.json').read_text());cls.runs={}
            return
        parent=os.environ.get('MWX_MODEL_PARTS_EVIDENCE')
        if parent:Path(parent).mkdir(parents=True,exist_ok=True)
        cls.root=Path(tempfile.mkdtemp(prefix='model-parts-app-',dir=parent))
        cls.protocol={'app':{str(p):sha(p) for p in cls.binaries},'buildReceipt':cls.buildReceipt,
            'sources':{str(p):sha(p) for p in [Path(__file__),Path(reader.__file__),REPO/'script/tests/test_scene_directional_shadow_integration.py',REPO/'script/tests/test_scene_pkg_cache_extractor.py']},'cases':{}}
        cls.runs={}
        for name,count,cast in [('five-on',5,True),('five-off',5,False),('eight',8,False)]:
            scene,entries,oracle=app_fixture(count,cast)
            work=cls.root/name;(work/'content').mkdir(parents=True);(work/'home').mkdir()
            (work/'content/project.json').write_bytes(entries.pop('project.json'))
            (work/'content/scene.pkg').write_bytes(make_package(list(entries.items())))
            (work/'scene-input.json').write_text(json.dumps(scene,indent=2))
            cls.protocol['cases'][name]={'count':count,'oracle':oracle,'files':{str(p):sha(p) for p in (work/'content').iterdir()},
                'entries':{p:hashlib.sha256(data).hexdigest() for p,data in entries.items()}}
        (cls.root/'protocol.json').write_text(json.dumps(cls.protocol,indent=2))
        (cls.root/'test.executed.py').write_bytes(Path(__file__).read_bytes())
        print(f'RF16 App frozen protocol: {cls.root}',flush=True)

    def run_case(self,name):
        from PIL import Image,ImageStat,ImageChops
        if name in self.runs:return self.runs[name]
        spec=self.protocol['cases'][name];work=self.root/name
        assert all(sha(p)==h for category in ['app','sources'] for p,h in self.protocol[category].items())
        assert all(sha(p)==h for p,h in spec['files'].items())
        command=[str(self.exe),'--mwx-debug-scene-root',str(work/'content'),'--mwx-debug-scene-duration','6',
                 '--mwx-debug-scene-evidence-dir',str(work/'evidence')]
        env=os.environ.copy();env.update(HOME=str(work/'home'),CFFIXED_USER_HOME=str(work/'home'),MWX_SCENE_DEBUG_SURFACE_COUNT='1')
        (work/'prerun.json').write_text(json.dumps({'protocolSHA256':sha(self.root/'protocol.json'),'command':command},indent=2))
        with (work/'app.log').open('w') as log:completed=subprocess.run(command,cwd=REPO,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=90)
        log=(work/'app.log').read_text();preview=(work/'evidence/scene-preview.log').read_text()
        ready=Image.open(work/'evidence/scene-ready-window.png').convert('RGB')
        after=Image.open(work/'evidence/scene-after-window.png').convert('RGB')
        scale=max(ready.width/160,ready.height/96)
        pixels={}
        for label,(x,y) in spec['oracle']['rois'].items():
            cx=round(ready.width/2+(x-80)*scale);cy=round(ready.height/2+(y-48)*scale)
            pixels[label]=ImageStat.Stat(ready.crop((cx-3,cy-3,cx+3,cy+3))).mean
        report={'exit':completed.returncode,'immutable':all(sha(p)==h for category in ['app','sources'] for p,h in self.protocol[category].items()),
            'inputsUnchanged':all(sha(p)==h for p,h in spec['files'].items()),'frame1':'state=completed frame=1 ' in log,
            'nextFrame':'state=completed frame=2 ' in log,'drained':'gpuDrained=true' in log,
            'stable':ImageChops.difference(ready,after).getbbox() is None,'pixels':pixels,
            'prepared':[line for line in preview.splitlines() if 'prepared static model layers:' in line],
            'shadowEvents':[line for line in log.splitlines() if 'shadow phase=' in line],
            'viewport':[ready.width,ready.height]}
        (work/'result.json').write_text(json.dumps(report,indent=2))
        self.assertEqual(report['exit'],0,report)
        for key in ['immutable','inputsUnchanged','frame1','nextFrame','drained','stable']:self.assertTrue(report[key],(key,report))
        self.assertTrue(any('[1, 2, 4]' in line for line in report['prepared']),report)
        self.runs[name]=report
        return report

    def test_five_real_material_segments_cast_and_receive_geometric_shadows(self):
        on=self.run_case('five-on');off=self.run_case('five-off')
        self.assertTrue(any('phase=depth-written' in line for line in on['shadowEvents']))
        self.assertTrue(any('phase=receiver' in line and 'layer=1' in line for line in on['shadowEvents']))
        self.assertTrue(any('phase=completed' in line for line in on['shadowEvents']))
        for i,rgba in enumerate(PALETTE[:5]):
            p=on['pixels'][f'part{i}'];self.assertEqual(p,off['pixels'][f'part{i}'])
            for c in range(3):
                if rgba[c]:self.assertGreater(p[c],30,(i,p))
                else:self.assertLessEqual(p[c],2,(i,p))
            for c in range(3):self.assertGreater(off['pixels'][f'shadow{i}'][c]-on['pixels'][f'shadow{i}'][c],20,(i,on,off))
        self.assertEqual(on['pixels']['healthy'],off['pixels']['healthy'])

    def test_eight_material_segments_all_reach_terminal_image(self):
        row=self.run_case('eight')
        for i,rgba in enumerate(PALETTE):
            p=row['pixels'][f'part{i}']
            for c in range(3):
                if rgba[c]:self.assertGreater(p[c],30,(i,p))
                else:self.assertLessEqual(p[c],2,(i,p))
        self.assertEqual(row['pixels']['healthy'],[64,64,64])


if __name__=='__main__':unittest.main()
