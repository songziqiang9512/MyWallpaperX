#!/usr/bin/env python3
"""Actual document/catalog/descriptor preparation to shared base-asset resolution."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from script.tests import test_scene_alpha_display_builder_fixture as builder

HARNESS = builder.HARNESS_SOURCE.split('@main', 1)[0] + r'''
@main enum Harness {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let facts = SceneRuntimeSourceFactsBuilder().build(rootURL: root)
        let descriptor = facts.renderDescriptor!
        let resolver = SceneTexturePathResolver(resourceView: facts.resourceView, descriptor: descriptor)
        let encoded = try JSONEncoder().encode(descriptor)
        var legacy = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        legacy["layers"] = (legacy["layers"] as! [[String: Any]]).map { layer in
            var copy = layer; copy.removeValue(forKey: "staticBaseTexturePath"); return copy
        }
        let old = try JSONDecoder().decode(SceneRenderDescriptor.self,
            from: JSONSerialization.data(withJSONObject: legacy))
        let oldResolver = SceneTexturePathResolver(resourceView: facts.resourceView, descriptor: old)
        let result: [String: Any] = [
            "layers": descriptor.layers.map { layer -> [String: Any] in
                ["id": layer.id,
                 "path": resolver.resolvePrimaryTexture(for: layer)?.lastPathComponent as Any? ?? NSNull(),
                 "size": layer.sizeWH as Any? ?? NSNull()]
            },
            "modelOnly": resolver.resolvePrimaryTexture(modelPath: "models/card.json")!.lastPathComponent,
            "materialSlots": descriptor.materialPasses.first!.texturePaths,
            "legacyPaths": old.layers.map { oldResolver.resolvePrimaryTexture(for: $0)?.lastPathComponent as Any? ?? NSNull() }
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''

class SceneInstanceBaseTextureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='mwx-instance-base-')
        work = Path(cls.temporary.name)
        cls.root = work/'scene'; cls.root.mkdir()
        instances = [
            {'textures':['materials/override.png',None]}, None,
            {'textures':[None]}, {'textures':['   ']},
            {'textures':['materials/override.png'],'usertextures':[]},
            {'textures':['materials/override.png'],'usertextures':[None,'  ',None]},
            {'textures':['materials/override.png'],'usertextures':['property_name']},
            {'textures':['materials/override.png'],'usertextures':[{'type':'system','name':'cursor'}]},
            {'textures':['materials/override.png'],'usertextures':[17]},
            {'textures':['materials/override.png'],'usertextures':{}},
            {'textures':['materials/missing.png']},
            {'textures':['../outside.png']},
            {'textures':['materials\\override.png']},
            {'textures':['materials/override.png'],'usertextures':['materials/other.png']},
            {'textures':['materials/override.png'],'usertextures':[{'user':''}]},
        ]
        objects=[]
        for index, instance in enumerate(instances):
            obj={'id':index+1,'image':'models/card.json'}
            if instance is not None:obj['instance']=instance
            if index==0:obj['size']='91 37'
            objects.append(obj)
        files={'project.json':{'type':'scene','file':'scene.json'},
               'scene.json':{'version':3,'objects':objects},
               'models/card.json':{'material':'materials/card.json','width':73,'height':29},
               'materials/card.json':{'passes':[{'shader':'genericimage2','textures':['materials/base.png','materials/normal.png']}]}}
        for name,value in files.items():
            p=cls.root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(value))
        for name in ['base.png','override.png','normal.png','other.png']:
            (cls.root/'materials'/name).write_bytes(b'path selection fixture; no decoder invoked')
        (work/'outside.png').write_bytes(b'not in VFS')
        source=work/'Harness.swift';source.write_text(HARNESS)
        binary=work/'probe'
        sources=builder.SWIFT_SOURCES+[builder.SOURCE_ROOT/'Resources/Textures/SceneTexturePathResolver.swift']
        result=subprocess.run(['xcrun','swiftc',*[str(p) for p in sources],str(source),'-module-cache-path',str(work/'cache'),'-framework','Metal','-o',str(binary)],capture_output=True,text=True)
        if result.returncode:raise RuntimeError(result.stderr)
        run=subprocess.run([str(binary),str(cls.root)],capture_output=True,text=True,check=True)
        cls.result=json.loads(run.stdout)
        print(json.dumps(cls.result,sort_keys=True))

    @classmethod
    def tearDownClass(cls):cls.temporary.cleanup()

    def test_layer_local_selection_preserves_shared_material_and_model_route(self):
        self.assertEqual([v['path'] for v in self.result['layers'][:4]],['override.png','base.png','base.png','base.png'])
        self.assertEqual(self.result['modelOnly'],'base.png')
        self.assertEqual(self.result['materialSlots'],['materials/base.png','materials/normal.png'])
        self.assertEqual(self.result['layers'][12]['path'],'override.png')

    def test_empty_user_collection_allows_static_but_typed_provider_retains_route(self):
        self.assertEqual([v['path'] for v in self.result['layers'][4:10]],['override.png','override.png','base.png','base.png','base.png','base.png'])
        self.assertEqual(self.result['layers'][13]['path'],'base.png')
        self.assertEqual(self.result['layers'][14]['path'],'base.png')

    def test_missing_and_escape_never_select_material_fallback(self):
        self.assertIsNone(self.result['layers'][10]['path'])
        self.assertIsNone(self.result['layers'][11]['path'])

    def test_explicit_and_model_geometry_do_not_follow_texture_selection(self):
        self.assertEqual(self.result['layers'][0]['size'],[91,37])
        self.assertTrue(all(v['size']==[73,29] for v in self.result['layers'][1:]))

    def test_legacy_descriptor_without_optional_selection_decodes(self):
        self.assertEqual(self.result['legacyPaths'],['base.png']*15)

from script.tests import test_scene_authored_normal as normal_fixture
pbr_expected = normal_fixture.pbr_expected

class SceneInstanceBaseTextureIntegrationTests(unittest.TestCase):
    setUpClass = classmethod(normal_fixture.SceneAuthoredNormalIntegrationTests.setUpClass.__func__)
    run_normal = normal_fixture.SceneAuthoredNormalIntegrationTests.run_normal

    def test_selected_non_square_source_and_same_model_peer(self):
        expected=pbr_expected((1,0,0),albedo=64)
        peer=pbr_expected((1,0,0),light=(160,0,100),albedo=128)
        for value in self.run_normal(instance=True,encoding='bc5',instance_base_size=(12,4),same_model_peer=True).values():
            self.assertLessEqual(abs(value['roiMean'][0]-expected),2,value)
            self.assertLessEqual(abs(value['sameModelPeerMean'][0]-peer),2,value)

    def test_selected_source_reaches_effect_and_normal_zero(self):
        for effect, normalmap in [(True,1),(False,0)]:
            self.scenario_id=f'effect{effect}-normal{normalmap}'
            expected=pbr_expected((1,0,0) if normalmap else (0,0,1),albedo=64)/(2 if effect else 1)
            for value in self.run_normal(instance=True,encoding='bc5',effect=effect,normalmap=normalmap).values():
                self.assertLessEqual(abs(value['roiMean'][0]-expected),2,value)

    def test_selected_missing_or_corrupt_asset_never_uses_material_image(self):
        for failure in ['missing','corrupt']:
            self.scenario_id=failure
            for value in self.run_normal(instance=True,encoding='bc5',instance_base_failure=failure).values():
                self.assertEqual(value['center'],[0,0,0],value)

    def test_selected_asset_frame_advances_without_changing_inherited_normal(self):
        result=self.run_normal(instance=True,encoding='bc5',instance_base_animated=True)
        self.assertLessEqual(abs(result['scene-ready-window.png']['roiMean'][0]-pbr_expected((1,0,0),albedo=64)),2,result)
        self.assertLessEqual(abs(result['scene-after-window.png']['roiMean'][0]-pbr_expected((1,0,0),albedo=192)),2,result)

if __name__=='__main__':unittest.main()
