#!/usr/bin/env python3
"""RF16 complete material parts through real reader/resources/frame owner and App.

The native resource probe supplies descriptor fields and a deterministic texture
transport at the outside boundary. Reader, resource prepare, material extraction,
mesh upload, native accounting, frame draw/depth and Metal are production code.
Policy cases explicitly hand actual Builder-selected model/layer/pass fields and
Root material/PNG bytes to the native target on the same owned tree. The native
target reopens the real Root and prepares its own CPU snapshot; this is not the
App's in-memory descriptor handoff or the full production texture decoder.
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
from script.tests import test_scene_puppet_playback as puppet
from script.tests import test_scene_puppet_animation as animation
from script.tests import test_scene_puppet_mesh as puppet_mesh
from script.tests.test_scene_direct_model_bind_geometry import build_bind_model
from script.tests.test_scene_directional_shadow_integration import png, quad, make_package
from script.tests.test_scene_prepared_script_resource_catalog import swift_declaration

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


def native_fixture(count, *, bad=False, overlap=False, equivalent_paths=False, renamed=False):
    entries = {}
    parts = []
    expected = []
    height = max(128, ((count + 7) // 8) * 16)
    model_path = 'models/Renamed sixty-five Ω.mdl' if renamed else 'models/parts.mdl'
    for i in range(count):
        x, y = (i % 8)*16+8, (i//8)*16+8
        if overlap:
            x, y = 32, 32
        path = f'materials/Renamed Ω {i:03}.json' if renamed else f'materials/part{i:03}.json'
        spelling = path
        if equivalent_paths:
            spelling = ('./'+path, path.replace('/', '//./'), path.replace('/', '\\.\\'))[i % 3]
        geometry = quad(x-5,x+5,y-5,y+5,float(i) if overlap else 0,spelling)
        parts.append(geometry)
        # Preserve all original 64 colors; the 65th is a separate bounded color.
        rgba = [32 + (i % 4)*64, 32 + ((i//4) % 4)*64, 32+(i//16)*64, 255] if i < 64 else [255,128,255,255]
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
    entries[model_path] = model
    entries['models/peer.mdl'] = quad(140,152,4,16,0,'materials/peer.json')
    entries['materials/peer.rgba'] = bytes([255,255,255,255])
    entries['materials/peer.png'] = png([255,255,255,255])
    entries['materials/peer.json'] = json.dumps({'passes':[{'shader':'genericimage',
        'textures':['materials/peer.png'],'combos':{'LIGHTING':0}}]}).encode()
    scene={'version':3,'general':{'orthogonalprojection':{'width':160,'height':height}},'objects':[
        {'id':1,'model':'models/peer.mdl','origin':f'0 {height} 0','perspective':False},
        {'id':2,'model':model_path,'origin':f'0 {height} 0','perspective':False}]}
    for obj in scene['objects']:
        obj['scale']='1 -1 1'  # Legacy canonical-down quad carrier, not the basis oracle.
    entries['scene.json']=json.dumps(scene).encode()
    entries['project.json']=json.dumps({'type':'scene','file':'scene.json'}).encode()
    return entries, expected



def policy_fixtures():
    variants = {name: native_fixture(65, **options) for name, options in {
        'parts65': {}, 'renamed65': {'renamed': True},
        'equivalent65': {'equivalent_paths': True}, 'latebad65': {'bad': True}}.items()}
    entries, expected = native_fixture(65)
    entries['models/peer.mdl'] = quad(0, 160, 0, 144, -10, 'materials/peer.json')
    peer = json.loads(entries['materials/peer.json'])
    peer['passes'][0]['constantshadervalues'] = {'alpha': 0}
    entries['materials/peer.json'] = json.dumps(peer).encode()
    variants['parts65-shadow'] = entries, expected
    for name in ['long-dots', 'long-pkg', 'long-dots-pkg-bad']:
        entries, expected = native_fixture(1)
        canonical = 'materials/' + 'Ω' * 2050 + '.json' if name == 'long-pkg' else 'materials/part000.json'
        spelling = canonical if name == 'long-pkg' else './' * 2100 + 'materials//./part000.json'
        entries['models/parts.mdl'] = quad(3, 13, 3, 13, 0, spelling)
        if name == 'long-pkg':
            material = entries.pop('materials/part000.json')
            entries['scene.pkg'] = make_package([(canonical, material)])
        elif name == 'long-dots-pkg-bad':
            entries['scene.pkg'] = make_package([(canonical, b'not material JSON')])
        expected[0]['material'] = canonical
        variants[name] = entries, expected
    return variants


def actual_builder_rows(root, names):
    report = native.run_swift(list(dict.fromkeys([*builder.SWIFT_SOURCES, *reader.SWIFT_SOURCES])),
        builder_support(), label='parts-dependencies', input_value={'root': str(root), 'names': ','.join(names)})
    return {row['name']: row for row in report['rows']}


def animation_attachment_fixture(mode):
    """Keep the maintained 80B mesh/Rig and MDLA writers; vary only MDAT."""
    entries, _ = native_fixture(1)
    body = bytearray(build_bind_model(material=b'materials/part000.json')[:-9])
    attachments = bytearray()
    if mode != 'absent':
        options = {'attachment_names': ('socket Ω', 'other')}
        if mode == 'bad-name': options['attachment_names'] = ('', 'other')
        if mode == 'bad-bone': options['attachment_bone'] = 9
        if mode == 'bad-matrix':
            values = puppet_mesh.matrix(); values[5] = math.nan
            options['attachment_local'] = values
        carrier = puppet_mesh.build_attachment_mdl(**options)
        attachments = bytearray(carrier[carrier.index(b'MDAT0001\0'):])
        if mode in ('empty', 'bad-count'):
            struct.pack_into('<H', attachments, 13, 0 if mode == 'empty' else 1025)
            if mode == 'empty': attachments = attachments[:15]
        struct.pack_into('<I', attachments, 9, len(body) + len(attachments))
    carrier = animation.build_mdl([animation.animation_record(7, 'Motion Ω', 2, 2)])
    mdla = bytearray(carrier[carrier.index(b'MDLA0006\0'):])
    struct.pack_into('<I', mdla, 9, len(body) + len(attachments) + len(mdla))
    entries['models/parts.mdl'] = bytes(body + attachments + mdla)
    return entries, {'animationPrepared': mode in ('absent', 'nonempty')}


def vertex_basis_fixture(renamed=False):
    """Y-up slanted one-sided geometry; no compensating author scale."""
    model = 'models/alternate.mdl' if renamed else 'models/basis.mdl'
    entries, parts = {}, []
    for index, (name, rgba, reverse, nocull) in enumerate([
            ('front', [240, 40, 20, 255], False, False),
            ('back', [20, 220, 50, 255], True, False),
            ('two-sided', [30, 60, 240, 255], True, True)]):
        stem = f'materials/renamed-{index}' if renamed else f'materials/{name}'
        x0, x1, y0, y1 = 2 + index * 13, 10 + index * 13, 4, 22
        vertices = [((x, y, .4*y), (0., -0.3713906764, 0.9284766909),
                     (1., 0., 0., 1.), uv) for x, y, uv in [
            (x0, y0, (0., 0.)), (x1, y0, (1., 0.)),
            (x1, y1, (1., 1.)), (x0, y1, (0., 1.))]]
        indices = (0, 2, 1, 0, 3, 2) if reverse else (0, 1, 2, 0, 2, 3)
        parts.append(reader.build_model(vertices=vertices, indices=indices,
            bounds=(x0, y0, .4*y0, x1, y1, .4*y1), material=(stem+'.json').encode()))
        entries[stem+'.rgba'] = bytes(rgba)
        entries[stem+'.png'] = png(rgba)
        entries[stem+'.json'] = json.dumps({'passes': [{'shader': 'genericimage',
            'textures': [stem+'.png'], 'combos': {'LIGHTING': 1},
            'cullmode': 'nocull' if nocull else 'back'}]}).encode()
    entries[model] = join_parts(parts)
    return entries, {'model': model}


def blending_fixture():
    entries, expected = native_fixture(5)
    for part, blending in zip(expected, [' Normal ', ' TRANSLUCENT ', 'additive', 'unknown', None]):
        path = part['material']
        material = json.loads(entries[path])
        if blending is None:
            material['passes'][0].pop('blending')
        else:
            material['passes'][0]['blending'] = blending
        entries[path] = json.dumps(material).encode()
    # A zero-coverage caster keeps the same projection extent for cast=false.
    # It cannot hide the five real parts in either their color or depth maps.
    entries['models/peer.mdl'] = quad(0, 160, 0, 128, -10, 'materials/peer.json')
    peer = json.loads(entries['materials/peer.json'])
    peer['passes'][0]['constantshadervalues'] = {'alpha': 0}
    entries['materials/peer.json'] = json.dumps(peer).encode()
    return entries, expected


def default_albedo_fixture():
    entries, expected = native_fixture(8)
    for i in range(8):
        path = f'materials/part{i:03}.json'
        material = json.loads(entries[path]); p = material['passes'][0]
        p['textures'] = [None]
        p['defaultAlbedo'] = 'materials/peer.png'
        if i == 0:
            p['constantshadervalues']['color'] = [.25, .5, .75]
        elif i == 1:
            del p['textures']
            p['defaultAlbedo'] = 'materials/part001.png'
        elif i == 2:
            p['textures'] = ['materials/part002.png']
        elif i == 3:
            p['textures'] = ['materials/missing-explicit.png']
        elif i == 4:
            del p['defaultAlbedo']
        elif i == 5:
            p['rejectedMaterial'] = True
        elif i == 6:
            p['defaultAlbedo'] = 'materials/missing-default.png'
        entries[path] = json.dumps(material).encode()
    return entries, expected


def emission_mask_fixture():
    entries, expected = native_fixture(8)
    for i in range(8):
        path = f'materials/part{i:03}.json'
        material = json.loads(entries[path]); p = material['passes'][0]
        p['textures'] = [f'materials/part{i:03}.png', None, f'materials/mask{i:03}.png']
        entries[f'materials/mask{i:03}.png'] = png([255,255,255,255])
        entries[f'materials/mask{i:03}.rgba'] = bytes([255,255,255,255])
        gain = {'value': 0, 'script': 'export function update(value) { return value; }'}
        if i == 1: gain = {'value': 0, 'user': 'gain'}
        elif i == 2: gain = 0
        elif i == 3: p['textures'][2] = None
        elif i == 4: p['textures'][2] = 'materials/missing-mask.png'
        elif i == 5:
            # File resolves, but the deterministic transport rejects its payload.
            del entries[f'materials/mask{i:03}.rgba']
        elif i == 6: p['rejectedMaterial'] = True
        elif i == 7: gain = 1
        p['constantshadervalues']['emissivebrightness'] = gain
        p['constantshadervalues']['emissivecolor'] = [.25, .25, .25]
        entries[path] = json.dumps(material).encode()
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
    sources=[Path(__file__),Path(reader.__file__),Path(frame.__file__),Path(native.__file__),
        REPO/'script/tests/fixtures/SceneStaticModelPartsNativeChecks.swift',
        REPO/'script/tests/fixtures/SceneStaticModelPartsDependencyChecks.swift']
    for p in sources:(root/('source-'+p.name)).write_bytes(p.read_bytes())
    manifest['testSources']={str(p):sha(p) for p in sources}
    (root/'protocol.json').write_text(json.dumps(manifest,indent=2))
    print(f'RF16 frozen {label}: {root}',flush=True)
    return root


BUILDER_MAIN = (REPO/'script/tests/fixtures/SceneStaticModelPartsDependencyChecks.swift').read_text()


def builder_support():
    return builder.HARNESS_SOURCE.split('@main',1)[0]+BUILDER_MAIN


class SceneModelPartsDependencyTests(unittest.TestCase):
    def test_posix_material_names_reach_actual_reader_vfs_and_material_passes(self):
        drive, renamed, peer = 'materials/C:/paint.json', 'materials/Alternate Name:blue/coat.json', 'materials/peer.json'
        escape = 'materials/C:/escape.json'
        variants = [
            ('modern', reader.build_model(material=drive.encode()), [drive], False),
            ('legacy', reader.build_legacy_model(material=rb'materials\C:\paint.json'), [drive], False),
            ('packaged', reader.build_model(material=drive.encode()), [drive], True),
            ('later', join_parts([reader.build_model(material=peer.encode()),
                reader.build_model(material=rb'materials\C:\paint.json')]), [peer, drive], True),
            ('renamed', reader.build_model(material=renamed.encode()), [renamed], False),
            ('dots-modern', reader.build_model(material=b'././materials/./C:/paint.json'), [drive], False),
            ('separators-legacy', reader.build_legacy_model(material=b'materials//C:///paint.json'), [drive], True),
            ('backslash-dots', reader.build_model(material=rb'.\materials\\C:\.\paint.json'), [drive], True),
            ('renamed-dots', reader.build_legacy_model(material=b'./materials/./Alternate Name:blue//coat.json'), [renamed], False),
            ('later-dots', join_parts([reader.build_model(material=peer.encode()),
                reader.build_model(material=b'materials//./C:/paint.json')]), [peer, drive], False),
            ('symlink', join_parts([reader.build_model(material=peer.encode()),
                reader.build_model(material=escape.encode())]), [peer, escape], False),
        ]
        main = r'''
@main enum PosixMaterialDependencies {
 static func main() throws {
  let input=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [String:String]
  let root=URL(fileURLWithPath:input["root"]!);var rows:[[String:Any]]=[]
  for name in input["names"]!.components(separatedBy:",") {
   let content=root.appendingPathComponent(name)
   let model=try SceneRuntimeModelBuilder().build(rootURL:content)
   let links=model.renderDescriptor.modelMaterialLinks.filter{$0.modelPath=="models/input.mdl"}.compactMap(\.materialPath)
   let passes=model.renderDescriptor.materialPasses.filter{links.contains($0.materialPath)}
   let textureBytes=try passes.flatMap(\.texturePaths).map { path in
    [UInt8](try model.resourceView.resolvedResource(relativePath:path)!.readBytes())
   }
   var escapeRejected=false
   if name=="symlink" {
    let author=SceneResourceView.Root(source:.loose,url:content)
    if let handle=author.handle(relativePath:"materials/C:/escape.json",exact:true) {
     do {_ = try handle.readBytes()}
     catch SceneResourceView.ReadError.symlinkEscape {escapeRejected=true}
    }
   }
   rows.append(["name":name,"links":links,"escapeRejected":escapeRejected,"textureBytes":textureBytes,
       "passes":passes.map{["path":$0.materialPath,"textures":$0.textureSlots.map{$0 ?? ""},
           "alpha":$0.constantShaderValues["alpha"]?.components ?? []] as [String:Any]}])
  }
  print(String(decoding:try JSONSerialization.data(withJSONObject:["rows":rows]),as:UTF8.self))
 }
}
'''
        with tempfile.TemporaryDirectory(prefix='mwx-posix-mdl-materials-') as temporary:
            root = Path(temporary)
            material = json.dumps({'passes': [{'shader': 'genericimage', 'textures': ['materials/color.png'],
                'combos': {'LIGHTING': 0}, 'constantshadervalues': {'alpha': .375}}]}).encode()
            outside = root/'outside.json'
            outside.write_text(json.dumps({'passes': [{'shader': 'genericimage',
                'textures': ['materials/outside.png'], 'combos': {'LIGHTING': 0}}]}))
            for name, geometry, paths, packaged in variants:
                folder = root/name;folder.mkdir()
                entries = {'scene.json': json.dumps({'version': 3, 'general': {'orthogonalprojection':
                    {'width': 32, 'height': 32}}, 'objects': [{'id': 1, 'model': 'models/input.mdl'}]}).encode(),
                    'models/input.mdl': geometry, 'materials/color.png': png([64, 128, 192, 255])}
                entries.update({path: material for path in paths if path != escape})
                (folder/'project.json').write_text(json.dumps({'type': 'scene', 'file': 'scene.json'}))
                if packaged:
                    (folder/'scene.pkg').write_bytes(make_package(list(entries.items())))
                else:
                    for path, data in entries.items():
                        target=folder/path;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
                if name == 'symlink':
                    target=folder/escape;target.parent.mkdir(parents=True,exist_ok=True);target.symlink_to(outside)
            support = builder.HARNESS_SOURCE.split('@main', 1)[0] + main
            sources = list(dict.fromkeys([*builder.SWIFT_SOURCES, *reader.SWIFT_SOURCES]))
            report = native.run_swift(sources, support, label='posix-mdl-materials', input_value={
                'root': str(root), 'names': ','.join(row[0] for row in variants)})
            rows = {row['name']: row for row in report['rows']}
            self.assertEqual(set(rows), {row[0] for row in variants})
            for name, _, paths, _ in variants:
                with self.subTest(name=name):
                    row = rows[name];expected = [path for path in paths if path != escape]
                    self.assertEqual(row['links'], paths)
                    self.assertEqual(row['textureBytes'], [list(png([64, 128, 192, 255])) for _ in expected])
                    self.assertEqual({p['path'] for p in row['passes']}, set(expected))
                    for item in row['passes']:
                        self.assertEqual(item['textures'], ['materials/color.png'])
                        self.assertEqual(item['alpha'], [.375])
            self.assertTrue(rows['symlink']['escapeRejected'])

    def test_actual_builder_complete_validated_material_dependencies(self):
        variants = {**{f'parts{n}': native_fixture(n) for n in [5,8,64]},
                    'bad8': native_fixture(8,bad=True), **policy_fixtures()}
        root = freeze_inputs('dependencies', variants)
        rows = actual_builder_rows(root, variants)
        self.assertEqual(set(rows), set(variants))
        for name, row in rows.items():
            with self.subTest(name=name):
                rejected = name in ('bad8', 'latebad65')
                expected = [] if rejected else [p['material'] for p in variants[name][1]]
                self.assertEqual(row['links'], expected)
                selected_bad = name == 'long-dots-pkg-bad'
                self.assertEqual({p['material'] for p in row['passes']}, set() if selected_bad else set(expected))
                for item in row['passes']:
                    index = expected.index(item['material'])
                    self.assertEqual(item['textures'], [f'materials/part{index:03}.png'])
                    self.assertEqual(item['combos']['LIGHTING'], 0)
                    self.assertEqual(item['passIndex'], 0)
                    self.assertEqual(item['textureBytes'], [list(variants[name][0][f'materials/part{index:03}.png'])])
                if rejected:
                    # A rejected model publishes no dependencies or passes;
                    # unreferenced material files are not scanned.
                    self.assertEqual(row['passes'], [])



# Native transport only. All material flags/extraction, reader, mesh upload and
# partial allocation policy remain inside the production resource owner.
RESOURCE_TRANSPORT=r'''
enum SceneMaterialPropertyBindingCompiler {
 static func staticComponents(_ key:String,instance:Any?,pass:SceneRenderDescriptor.MaterialPassDescriptor,
                              count:Int,fallback:[Double],requiresCompleteScalar:Bool=false)->[Double]? {
  // Values here are typed transport inputs; full raw projection is tested
  // against the actual shared compiler in the material property fixture.
  return pass.constantShaderValues[key]?.components ?? fallback
 }
}
struct SceneDocument {
 struct ShaderValue {let components:[Double];var userBinding:String?=nil;var scriptSource:String?=nil}
 let objects:[SceneRenderDescriptor.Layer]
}
extension SceneResourceView {
 init(root:URL) {
  self.init(projectRootURL:root,packageRootURL:nil,stockAssetsRootURL:nil)
 }
}
struct SceneTexturePathResolver {
 let resourceView:SceneResourceView;let descriptor:SceneRenderDescriptor
 func resolveTextureFile(named path:String)->SceneResourceView.FileInput? {
  resourceView.resolvedResource(relativePath:path).map(SceneResourceView.FileInput.resource)
 }
}
final class SceneTextureLoader {
 enum Result {case loaded(SceneTextureCandidate);case missing}
 var candidates:[String:SceneTextureCandidate]=[:]
 var requests:[[String:String]]=[]
 init(root:URL,device:MTLDevice)throws {
  let paths=try FileManager.default.contentsOfDirectory(at:root.appendingPathComponent("materials"),includingPropertiesForKeys:nil)
  for path in paths where path.pathExtension=="rgba" {
   let td=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:1,height:1,mipmapped:false)
   td.storageMode = .shared;td.usage = .shaderRead
   let texture=device.makeSceneTexture(descriptor:td)!
   let data=try Data(contentsOf:path)
   data.withUnsafeBytes{texture.replace(region:MTLRegionMake2D(0,0,1,1),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:4)}
   let png=path.deletingPathExtension().appendingPathExtension("png")
   // Match the product's canonical file identity across /var and /tmp aliases.
   candidates[png.resolvingSymlinksInPath().path] = .init(texture:texture,identity:.file(path:png.path),generation:.immutable(revision:1),purpose:.straightAlbedo,
      content:.data,physicalSize:CGSize(width:1,height:1),mappedSize:CGSize(width:1,height:1),uvTransform:.identity,sampling:.directImageFallback)
  }
 }
 func loadCandidate(from input:SceneResourceView.FileInput,purpose:SceneTextureLoadPurpose,device:MTLDevice,
                    checkCancellation:(() throws -> Void)?=nil) throws -> Result {
  try checkCancellation?()
  let url=URL(fileURLWithPath:input.diagnosticPath)
  precondition(purpose == .straightAlbedo || purpose == .mask)
  requests.append(["path":url.lastPathComponent,"purpose":String(describing:purpose)])
  guard let candidate=candidates[url.resolvingSymlinksInPath().path] else {return .missing}
  return .loaded(.init(texture:candidate.texture,identity:candidate.identity,generation:candidate.generation,
      purpose:purpose,content:candidate.content,physicalSize:candidate.physicalSize,mappedSize:candidate.mappedSize,
      uvTransform:candidate.uvTransform,sampling:candidate.sampling))
 }
}
extension SceneRenderDescriptor {
 struct ModelMaterialLink {let modelPath:String;let materialPath:String?}
 struct ColorTargetFormat {var metalPixelFormat:MTLPixelFormat { .bgra8Unorm }}
 struct MaterialPassDescriptor {
  let materialPath:String;let textureSlots:[String?];let combos:[String:Int]
  let constantShaderValues:[String:SceneDocument.ShaderValue];var passIndex:Int=0;var depthWrite:String?=nil
  var staticModelMaterialBindings:SceneStaticModelMaterialBindings?=nil;var cullMode:String?=nil
  var staticModelDefaultAlbedoAssetPath:String?=nil;var shaderPath:String?=nil
  var blending:String?=nil
  var userShaderValues:[String:String]=[:]
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
    # Pure transport additions; all matrices still come from production owners.
    s=s.replace('var anglesXYZ:[Float]? = nil', 'var anglesXYZ:[Float]? = nil;'
        'var originXYZ:[Float]?=nil;var scaleXYZ:[Float]?=nil;'
        'var attachmentName:String?=nil;var parentAttachmentBindFrame:[Float]?=nil')
    # Static preparation now shares the production immutable initial-bone
    # projection. Compile that exact pure declaration without pulling the
    # unused image PlaybackState/renderer into this static resource carrier.
    load=(SCENE/'Systems/Puppet/ScenePuppetLayerLoad.swift').read_text()
    config=load[load.index('    struct BoneConfiguration {'):
                load.index('    /// A launch may retain this result')]
    initial=load[load.index('    static func initialBoneConfiguration('):
                 load.index('    struct Outcome {')]
    bones='\nenum ScenePuppetLayerLoad {\n'+config+initial+'\n}\n'
    properties=(SCENE/'Systems/Properties/ScenePuppetAnimationPropertyPreparation.swift').read_text()
    visibility=swift_declaration(properties, '    nonisolated static func visibilityTargets(')
    targets='\nenum ScenePuppetAnimationPropertyPreparation {\n'+visibility+'\n}\n'
    source_facts=(SCENE/'Runtime/Frame/SceneRuntimeSourceFacts.swift').read_text()
    source_type='\nextension SceneMdlStaticModel {\n'+swift_declaration(source_facts, '    struct PreparedSource {')+'\n}\n'
    prepare=swift_declaration(source_facts, '    private func directStaticModelMaterialLinks(')
    prepare=prepare.replace('    private func ', '    func ', 1)
    prepared='\nstruct SourceFactsPreparationProbe {\n'+prepare+'\n}\n'+r'''
func prepareModelSources(_ descriptor:SceneRenderDescriptor, view:SceneResourceView) throws
    -> [String:SceneMdlStaticModel.PreparedSource] {
 var sources:[String:SceneMdlStaticModel.PreparedSource]=[:]
 _ = try SourceFactsPreparationProbe().directStaticModelMaterialLinks(
    document:.init(objects:descriptor.layers),resourceView:view,
    preparedStaticModel:{sources[$0]=$1})
 return sources
}
'''
    return frame.pool_fixture.HARNESS.split('@main',1)[0]+s+frame.UNUSED_ORDERED_SUPPORT+RESOURCE_TRANSPORT+bones+targets+source_type+prepared


NATIVE_SOURCES=list(dict.fromkeys([*frame.SOURCES,*reader.SWIFT_SOURCES,*puppet.SWIFT_SOURCES,RESOURCE_SOURCE,
    SCENE/'Resources/Assets/SceneResourceIndex.swift',
    SCENE/'Resources/Assets/SceneResourceView.swift',
    SCENE/'Rendering/Lighting/SceneAuthoredShaderLightingInputs.swift',
    SCENE/'Systems/Properties/ScenePuppetAnimationPropertyTarget.swift',
    SCENE/'Format/SceneMdlPuppetAnimationReader.swift',
    SCENE/'Format/SceneMdlPuppetAttachmentReader.swift',
    SCENE/'Format/ScenePuppetBoneCatalog.swift',
    SCENE/'Systems/Script/ScenePuppetBoneTransformBridge.swift',
    SCENE/'Runtime/Frame/SceneStaticModelMaterialBindings.swift',
    SCENE/'Runtime/Frame/SceneMaterialRenderState.swift',
    SCENE/'Compilation/Material/SceneMaterialRenderState+Compilation.swift',
    SCENE/'Resources/Textures/SceneNamedTextureReference.swift',
    SCENE/'Rendering/Geometry/SceneLayerWorldFrameResolver.swift',
    SCENE/'Rendering/Geometry/SceneLayerDynamicWorldFrameResolver.swift',
    SCENE/'Systems/Puppet/ScenePuppetAttachmentFrameSnapshot.swift',
    REPO/'script/tests/fixtures/SceneStaticModelAnimationAttachmentChecks.swift',
    REPO/'script/tests/fixtures/SceneStaticModelMaterialSelectionChecks.swift',
    REPO/'script/tests/fixtures/SceneStaticModelVertexBasisChecks.swift']))

NATIVE_MAIN = (REPO/'script/tests/fixtures/SceneStaticModelPartsNativeChecks.swift').read_text()


class SceneStaticModelSurfaceAdmissionTests(unittest.TestCase):
    def test_default_profile_and_either_author_stage_override(self):
        # Executes the whole resource owner without constructing a Metal device.
        main=r'''
@main enum SurfaceAdmissionProbe {
 static func main() throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1])
  let view=SceneResourceView(root:root)
  var pass=SceneRenderDescriptor.MaterialPassDescriptor(materialPath:"material",textureSlots:[],
      combos:["LIGHTING":1],constantShaderValues:[:],shaderPath:"generic4")
  let profile=ScenePreparedStaticModelResources.surfaceProfile(pass,resourceView:view)!
  precondition(profile == .init(metallic:0,roughness:0.7))
  let shaderRoot=root.appendingPathComponent("shaders")
  try FileManager.default.createDirectory(at:shaderRoot,withIntermediateDirectories:true)
  for suffix in ["vert","frag"] {
   let stage=shaderRoot.appendingPathComponent("generic4."+suffix)
   try Data().write(to:stage)
   precondition(ScenePreparedStaticModelResources.surfaceProfile(pass,
       resourceView:SceneResourceView(root:root)) == nil)
   try FileManager.default.removeItem(at:stage)
  }
  pass.shaderPath="custom/generic4"
  precondition(ScenePreparedStaticModelResources.surfaceProfile(pass,resourceView:view) == nil)
  pass=SceneRenderDescriptor.MaterialPassDescriptor(materialPath:"material",textureSlots:[],
      combos:["LIGHTING":0],constantShaderValues:[:],shaderPath:"generic4")
  precondition(ScenePreparedStaticModelResources.surfaceProfile(pass,resourceView:view) == nil)
  for key in ["metallic","roughness"] {
   for constants in [[:],[key:SceneDocument.ShaderValue(components:[0.5])]] {
    var userPass=SceneRenderDescriptor.MaterialPassDescriptor(materialPath:"material",textureSlots:[],
        combos:["LIGHTING":1],constantShaderValues:constants,shaderPath:"generic4")
    userPass.userShaderValues[key]="control"
    precondition(ScenePreparedStaticModelResources.surfaceProfile(userPass,resourceView:view) == nil,
                 "User MR must preserve the legacy profile with or without a parallel constant")
   }
  }
  let domainPass=SceneRenderDescriptor.MaterialPassDescriptor(materialPath:"material",textureSlots:[],
      combos:["LIGHTING":1],constantShaderValues:["metallic":.init(components:[-2]),
      "roughness":.init(components:[2])],shaderPath:"generic4")
  precondition(ScenePreparedStaticModelResources.surfaceProfile(domainPass,resourceView:view)
               == .init(metallic:0,roughness:1))
  print("surface-admission: OK")
 }
}
'''
        with tempfile.TemporaryDirectory(prefix='mwx-model-surface-admission-') as temporary:
            work=Path(temporary);source=work/'Harness.swift';binary=work/'probe'
            source.write_text(resource_support()+main)
            compiled=subprocess.run(['xcrun','swiftc',*map(str,NATIVE_SOURCES),str(source),
                '-module-cache-path',str(work/'cache'),'-framework','Metal','-o',str(binary)],
                capture_output=True,text=True)
            self.assertEqual(compiled.returncode,0,compiled.stderr)
            result=subprocess.run([str(binary),str(work)],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertIn('surface-admission: OK',result.stdout)


class SceneModelPartsNativeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root=freeze_inputs('native',{**{f'parts{n}':native_fixture(n) for n in [5,8,64]},
            'spelled':native_fixture(5,equivalent_paths=True),
            'bad8':native_fixture(8,bad=True),'overlap':native_fixture(2,overlap=True),
            'defaults':default_albedo_fixture(),'emission':emission_mask_fixture(),
            'blends':blending_fixture(),
            **{'attachment-'+mode:animation_attachment_fixture(mode) for mode in
               ['absent','nonempty','empty','bad-count','bad-name','bad-bone','bad-matrix']},
            'basis':vertex_basis_fixture(),'basis-renamed':vertex_basis_fixture(True), **policy_fixtures()})
        cls.builder_rows = actual_builder_rows(cls.root, policy_fixtures())
        handoff = {}
        for name, row in cls.builder_rows.items():
            target = cls.root/name/'builder-handoff.json'
            target.write_text(json.dumps(row, ensure_ascii=False, indent=2))
            handoff[name] = sha(target)
        protocol = json.loads((cls.root/'protocol.json').read_text())
        protocol['builderHandoff'] = handoff
        (cls.root/'protocol.json').write_text(json.dumps(protocol, indent=2))
        cls.report=native.run_swift(NATIVE_SOURCES,resource_support()+NATIVE_MAIN,label='parts-native',
            metal_sources=[MODEL_METAL],input_value={'root':str(cls.root)})
        cls.rows={r['mode']:r for r in cls.report['rows']}
        cls.basis=cls.report['basis']

    def test_material_pass_first_wins_and_local_failures(self):
        self.assertEqual(len(self.report['selection']), 14)
        self.assertTrue(all(self.report['selection'].values()), self.report['selection'])

    def test_attachment_parse_failure_preserves_bind_geometry_and_peer(self):
        self.assertEqual(len(self.report['attachments']), 7)
        for row in self.report['attachments']:
            with self.subTest(mode=row['mode']):
                self.assertEqual((row['readerParts'], row['readerBones'], row['readerClips']), (1, 2, 1))
                self.assertEqual((row['bindParts'], row['bindIndices']), (1, 12))
                self.assertEqual((row['peerParts'], row['peerIndices']), (1, 6))
                self.assertEqual(row['peerMaterial'], 'materials/peer.json')
                valid = row['mode'] in ('absent', 'nonempty')
                self.assertEqual(row['attachmentParseOK'], valid, row)
                self.assertEqual(row['animationPrepared'], valid, row)
                self.assertEqual(row['retainedAttachmentNames'], ['socket Ω', 'other']
                                 if row['mode'] == 'nonempty' else [])
                if not valid:
                    expected = {'empty': 'attachment count', 'bad-count': 'attachment count',
                                'bad-name': 'attachment name', 'bad-bone': 'missing bone',
                                'bad-matrix': 'matrix'}[row['mode']]
                    self.assertIn(expected, row['attachmentError'])

    def test_authored_vertex_basis_reaches_color_normals_cull_and_all_shadow_types(self):
        self.assertEqual(len(self.basis), 12)
        for row in self.basis:
            with self.subTest(variant=row['variant'], mode=row['mode']):
                self.assertLess(row['worldError'], 0.0002)
                self.assertLess(row['normalError'], 0.0002)
                self.assertTrue(row['canonicalUnchanged'])
                self.assertTrue(row['colorMatchesReference'], row)
                self.assertTrue(row['colorCullAndMirror'], row)
                self.assertTrue(row['encoded'] and row['completed'])
                self.assertEqual(row['shadowKinds'], ['directional','spot','point'])
                self.assertTrue(all(row['shadowMatchesReference']), row)
                self.assertTrue(all(row['shadowHasGeometry']), row)
                self.assertTrue(all(row['shadowCullMatchesGeometry']), row)
        self.assertTrue(any(row['dynamic'] for row in self.basis))
        self.assertTrue(any(row['native'] for row in self.basis))

    def test_actual_resource_owner_prepares_and_main_loop_consumes_all_5_8_64(self):
        for name,count in [('parts5',5),('parts8',8),('parts64',64),('spelled',5)]:
            row=self.rows[name];expected=native_fixture(count)[1]
            self.assertEqual(row['parts'],[p['material'] for p in expected])
            self.assertEqual(len(set(row['textureIDs'])),count)
            self.assertEqual(row['meshIndexCounts'],[6]*count)
            self.assertTrue(row['encoded']);self.assertTrue(row['completed'])
            self.assertEqual(len(row['frames'][0]), 64)
            self.assertEqual(len(row['parts']), len(expected))
            for actual,want in zip(row['frames'][0],expected):
                for a,b in zip(actual,want['rgba']):self.assertLessEqual(abs(a-b),1,(count,actual,want))
            self.assertEqual(row['frames'][0],row['frames'][1])
            self.assertEqual(row['leaseCounts'],[1,1])
        for key in ('frames', 'peerFrames', 'overlapFrames'):
            self.assertEqual(self.rows['spelled'][key], self.rows['parts5'][key])

    def test_65_parts_builder_dependencies_and_every_main_pass_roi(self):
        variants = policy_fixtures()
        for name in ['parts65', 'renamed65', 'equivalent65']:
            row, expected = self.rows[name], variants[name][1]
            with self.subTest(name=name):
                self.assertEqual(row['builderLinks'], [p['material'] for p in expected])
                self.assertEqual(row['parts'], row['builderLinks'])
                self.assertEqual((row['canvasHeight'], row['gridCount']), (144,65))
                self.assertEqual(row['meshIndexCounts'], [6]*65)
                self.assertEqual(len(set(row['textureIDs'])), 65)
                self.assertTrue(row['encoded'] and row['completed'])
                self.assertEqual(row['leaseCounts'], [1,1])
                self.assertEqual(len(row['frames'][0]), len(expected))
                for actual, wanted in zip(row['frames'][0], expected):
                    for a, b in zip(actual, wanted['rgba']): self.assertLessEqual(abs(a-b), 1)
                self.assertEqual(row['frames'][0], row['frames'][1])
                self.assertEqual(row['peerFrames'], [[255,255,255,255]]*2)
                self.assertTrue(set(row['parts']).issubset(row['nativeMaterialReads']))
        for name in ['renamed65', 'equivalent65']:
            self.assertEqual(self.rows[name]['frames'], self.rows['parts65']['frames'])
        bad = self.rows['latebad65']
        self.assertEqual(bad['builderLinks'], [])
        self.assertEqual(bad['parts'], [])
        self.assertEqual(bad['frames'], [[[0,0,0,255]]*65]*2)
        self.assertEqual(bad['peerFrames'], [[255,255,255,255]]*2)

    def test_long_material_spellings_and_virtual_package_reach_real_pixels(self):
        for name in ['long-dots', 'long-pkg']:
            row = self.rows[name]
            expected = policy_fixtures()[name][1][0]
            with self.subTest(name=name):
                self.assertEqual(row['parts'], [expected['material']])
                self.assertEqual(row['builderLinks'], row['parts'])
                self.assertIn(expected['material'], row['nativeMaterialReads'])
                self.assertEqual(row['frames'][0][0], expected['rgba'])
                self.assertEqual(row['frames'][0], row['frames'][1])
                self.assertEqual(row['peerFrames'], [[255,255,255,255]]*2)
        bad = self.rows['long-dots-pkg-bad']
        self.assertEqual(bad['builderLinks'], ['materials/part000.json'])
        self.assertEqual(bad['parts'], [])
        self.assertEqual(bad['frames'], [[[0,0,0,255]]*64]*2)
        self.assertEqual(bad['peerFrames'], [[255,255,255,255]]*2)

    def test_65th_part_cast_intent_reaches_bounded_directional_depth(self):
        on, off = self.rows['parts65-shadow'], self.rows['parts65-shadow-false']
        for key in ('frames', 'peerFrames', 'overlapFrames'):
            self.assertEqual(on[key], off[key])
        self.assertEqual(len(on['parts']), 65)
        self.assertEqual(len(on['shadowDepths']), 1)
        self.assertEqual(len(on['shadowDepths'][0]), 65)
        self.assertTrue(all(value < 1 for value in on['shadowDepths'][0]), on['shadowDepths'])
        self.assertEqual(off['shadowDepths'], [[1]*65])

    def test_prepared_mixed_blending_and_layer_cast_intent_reach_three_shadow_maps(self):
        enabled, disabled = self.rows['blends'], self.rows['blends-false']
        for row in [enabled, disabled]:
            self.assertEqual(row['materialBlending'], ['normal', 'translucent', 'additive', 'unresolved', 'unresolved'])
            self.assertEqual(len(row['parts']), 5)
            self.assertTrue(row['completed'])
        for key in ('frames', 'peerFrames', 'overlapFrames'):
            self.assertEqual(enabled[key], disabled[key])
        self.assertEqual(enabled['frames'][0], self.rows['parts5']['frames'][0][:64])
        self.assertEqual(enabled['peerFrames'], [[0,0,0,255]]*2)
        self.assertEqual(enabled['overlapFrames'], [[0,0,0,255]]*2)
        for depths in enabled['shadowDepths']:
            self.assertEqual(depths[1], 1)
            self.assertTrue(all(depths[i] < 1 for i in [0, 2, 3, 4]), depths)
        self.assertEqual(len(enabled['shadowDepths']), 3)
        self.assertEqual(disabled['shadowDepths'], [[1] * 5] * 3)

    def test_later_native_quota_failure_preserves_prefix_peer_and_new_load_recovers(self):
        row=self.rows['quota'];full=self.rows['recovery']
        self.assertEqual(row['parts'],['materials/part000.json','materials/part001.json'])
        self.assertGreater(row['rejections'],0)
        self.assertEqual(row['peerParts'],1)
        self.assertEqual(row['frames'][0][:2],full['frames'][0][:2])
        self.assertEqual(row['peerFrames'][0],[255,255,255,255])
        self.assertEqual(row['frames'][0][2:8],[[0,0,0,255]]*6)
        self.assertEqual(full['parts'],self.rows['parts8']['parts'])
        for key in ('frames', 'peerFrames', 'overlapFrames'):
            self.assertEqual(full[key], self.rows['parts8'][key])
        for r in self.report['rows']:
            self.assertEqual(r['budgetAfter'], r['budgetBefore'], r['mode'])
            for key in ('peerFrames', 'overlapFrames'):
                self.assertEqual(len(r[key]), 2)
                self.assertEqual(r[key][0], r[key][1], (r['mode'], key))

    def test_gpu_consumes_same_cpu_snapshot_after_author_models_move(self):
        row=self.rows['snapshot']
        self.assertEqual(row['parts'],self.rows['parts8']['parts'])
        for key in ('frames', 'peerFrames', 'overlapFrames'):
            self.assertEqual(row[key], self.rows['parts8'][key])
        self.assertEqual(row['peerParts'],1)

    def test_bad_later_structure_rejects_model_but_peer_still_draws(self):
        row=self.rows['bad8'];self.assertEqual(row['parts'],[])
        self.assertEqual(row['frames'][0][:64],[[0,0,0,255]]*64)
        self.assertEqual(row['peerFrames'][0],[255,255,255,255])
        self.assertEqual(row['frames'][0],row['frames'][1])

    def test_authored_segment_order_and_opacity_are_consumed(self):
        row=self.rows['overlap'];self.assertEqual(row['materials'],[[1,1,1,.5]]*2)
        # Authored red then green, each coverage .5, over black: .25 red + .5 green.
        for actual,want in zip(row['overlapFrames'][0],[64,128,0,255]):self.assertLessEqual(abs(actual-want),1)
        self.assertEqual(row['frames'][0],row['frames'][1])

    def test_default_albedo_reaches_model_pixels_without_hiding_explicit_failure(self):
        row = self.rows['defaults']
        self.assertEqual(row['parts'], [f'materials/part{i:03}.json' for i in [0,1,2,7]])
        expected = default_albedo_fixture()[1]
        pixels = [[64,128,191,255], expected[1]['rgba'], expected[2]['rgba'],
                  *([[0,0,0,255]]*4), [255,255,255,255]]
        for actual, wanted in zip(row['frames'][0], pixels):
            for a, b in zip(actual, wanted): self.assertLessEqual(abs(a-b), 1)
        self.assertEqual(row['frames'][0], row['frames'][1])
        self.assertEqual(row['textureIDs'][0], row['textureIDs'][3])
        self.assertEqual(row['budgetBefore'], row['budgetAfter'])


    def test_zero_script_seed_reserves_typed_mask_with_local_optional_failures(self):
        row = self.rows['emission']
        self.assertEqual(row['parts'], [f'materials/part{i:03}.json' for i in [0,1,2,3,4,5,7]])
        self.assertEqual([bool(identity) for identity in row['maskIDs']], [True,True,False,False,False,False,True])
        self.assertEqual(row['maskPurposes'], ['mask','mask','','','','','mask'])
        self.assertEqual(row['emissionSeeds'], [0,0,0,0,0,0,1])
        mask_requests = [request['path'] for request in row['textureRequests'] if request['purpose'] == 'mask']
        self.assertEqual(sorted(mask_requests), ['mask000.png','mask001.png','mask005.png','mask007.png'])
        # Zero-seed scripts reserve resources without executing or creating a VM consumer.
        expected = emission_mask_fixture()[1]
        for i in range(6): self.assertEqual(row['frames'][0][i], expected[i]['rgba'])
        self.assertEqual(row['frames'][0][6], [0,0,0,255])
        self.assertEqual(row['peerParts'], 1)
        self.assertEqual(row['peerFrames'][0], [255,255,255,255])
        self.assertEqual(row['frames'][0], row['frames'][1])
        self.assertEqual(row['budgetBefore'], row['budgetAfter'])


def app_fixture(count, cast=True):
    """Independent world rectangles; ray toward (.6,0,1) shifts z20 by -12X."""
    centers=[30,54,78,102,126] if count==5 else [17,35,53,71,89,107,125,143]
    objects=[{'id':4,'model':'models/background.mdl','origin':'0 96 0','perspective':False,'castshadow':False},
             {'id':1,'model':'models/receivers.mdl','origin':'0 96 0','perspective':False,'castshadow':False},
             {'id':2,'model':'models/parts.mdl','origin':'0 96 0','perspective':False,'castshadow':cast},
             {'id':3,'light':'ldirectional','angles':f'0 {math.pi / 2 + math.atan(.6)} 0','intensity':.7,'color':'1 1 1','castshadow':count==5}]
    scene={'version':3,'general':{'orthogonalprojection':{'width':160,'height':96},
        'clearcolor':'0 0 0','ambientcolor':'0.05 0.05 0.05','skylightcolor':'0 0 0',
        'lightconfig':{'directional':1}},'objects':objects}
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
    # These older material/shadow ROIs use canonical-down authored quads.
    for obj in objects:
        if 'model' in obj: obj['scale']='1 -1 1'
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
            'sources':{str(p):sha(p) for p in [Path(__file__),Path(reader.__file__),REPO/'script/tests/test_scene_directional_shadow_integration.py',REPO/'script/tests/scene_pkg_fixture.py']},'cases':{}}
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
