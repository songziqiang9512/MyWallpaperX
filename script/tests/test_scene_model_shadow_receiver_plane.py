#!/usr/bin/env python3
"""Real directional visibility on small, curved receiver neighborhoods."""
import hashlib
import json
import math
import os
from pathlib import Path
import unittest

from script.tests import test_scene_directional_shadow as shared

MODEL = shared.model_fixture
CASES = Path(__file__).with_name('fixtures') / 'scene_model_shadow_receiver_plane_cases.json'


def vectors():
    fixture = json.loads(CASES.read_text())
    result = []
    for case in fixture['cases']:
        def mesh(data):
            return dict(positions=[v[:3] for v in data['vertices']],
                        normals=[v[3:6] for v in data['vertices']],
                        uvs=[v[6:] for v in data['vertices']],
                        indices=[i for triangle in data['triangles'] for i in triangle])

        for prefix, kind in [(0, 'u16'), (65536, 'u32')]:
            receiver = mesh(case['receiver'])
            receiver['unreferencedPrefixVertexCount'] = prefix
            result.append(dict(
                fixture['frame'], name=case['name'] + '-' + kind,
                pixel=case['pixel'], receiver=case['point'],
                receiver_geometry=receiver, caster_geometry=mesh(case['caster']),
                light_intensity=1, casters=[dict(cast=True)]))
    return result


def harness():
    code = shared.skinny_plane_main()
    loader = r'''
  func suppliedMesh(_ g: [String:Any]) -> SceneStaticModelMesh {
   let positions=g["positions"] as! [[Double]], normals=g["normals"] as! [[Double]]
   let uvs=g["uvs"] as! [[Double]], indices=(g["indices"] as! [Int]).map(UInt32.init)
   let vertices=positions.indices.map { i in SceneMdlStaticModel.Vertex(
    position:SIMD3(Float(positions[i][0]),Float(positions[i][1]),Float(positions[i][2])),
    normal:SIMD3(Float(normals[i][0]),Float(normals[i][1]),Float(normals[i][2])),
    tangent:SIMD4(1,0,0,1),uv:SIMD2(Float(uvs[i][0]),Float(uvs[i][1]))) }
   // Unreferenced vertices change index storage without changing geometry or bounds.
   let prefix=g["unreferencedPrefixVertexCount"] as? Int ?? 0
   let suppliedVertices=prefix == 0 ? vertices : Array(repeating:vertices[0],count:prefix)+vertices
   let suppliedIndices=prefix == 0 ? indices : indices.map { $0+UInt32(prefix) }
   return pipeline.makeMesh(model:SceneStaticModelFixture.model(vertices:suppliedVertices,indices:suppliedIndices))!
  }
'''
    marker = '  let emissionMask = texture(0.25)'
    code = code.replace(marker, marker + '\n' + loader)
    start = code.index('   let normal=v[')
    end = code.index('   let toward = ', start)
    code = code[:start] + '   let receiver=suppliedMesh(v["receiver_geometry"] as! [String:Any])\n' + code[end:]
    start = code.index('   let meshes = casters.map')
    end = code.index('   let projection:', start)
    code = (code[:start] + '   let caster=suppliedMesh(v["caster_geometry"] as! [String:Any])\n'
            '   let meshes=casters.map { _ in caster }\n' + code[end:])
    code = code.replace('width:1024,height:1024', 'width:4096,height:4096')
    code = code.replace('for mode in 0..<9', 'for mode in 0..<3')
    code = code.replace('   var buffers:[MTLBuffer] = []',
                        '   let extent=v["camera_extent"] as! [Int]\n   var buffers:[MTLBuffer] = []')
    code = code.replace('width:1,height:1,mipmapped:false',
                        'width:extent[0],height:extent[1],mipmapped:false')
    marker = '    let e = cb.makeRenderCommandEncoder(descriptor:render)!'
    code = code.replace(marker, marker + '\n    let pixel=v["pixel"] as! [Int]\n'
                        '    e.setScissorRect(MTLScissorRect(x:pixel[0] & ~1,y:pixel[1] & ~1,width:2,height:2))')
    code = code.replace('viewProjection:view,cameraPosition:',
                        'viewProjection:view,frontFacing:.counterClockwise,cameraPosition:')
    code = code.replace('sourceOrigin:.init(x:0,y:0,z:0),sourceSize:.init(width:1,height:1,depth:1)',
                        'sourceOrigin:.init(x:pixel[0],y:pixel[1],z:0),sourceSize:.init(width:1,height:1,depth:1)')
    return 'import Foundation\nimport Metal\nimport simd\n' + MODEL.LIGHTING_STUB + code


class SceneModelShadowReceiverPlaneTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.inputs = vectors()
        paths = [getattr(MODEL, name) for name in [
            'MODEL_SOURCE', 'SAMPLING_SOURCE', 'UV_TRANSFORM_SOURCE',
            'DIRECTIONAL_LIGHT_SOURCE', 'POINT_LIGHT_SOURCE', 'TUBE_LIGHT_SOURCE',
            'SPOT_LIGHT_SOURCE', 'LIGHT_SOURCE', 'VISIBILITY_SOURCE',
            'DYNAMIC_SNAPSHOT_SOURCE', 'DYNAMIC_LAYER_VALUES_SOURCE',
            'PERFORMANCE_COUNTER_SOURCE', 'MATERIAL_SOURCE', 'PIPELINE_SOURCE', 'SHADOW_SOURCE']]
        paths += [*MODEL.MODEL_SUPPORT_SOURCES,
                  shared.SCENE / 'Runtime/Frame/SceneStaticModelMaterialBindings.swift',
                  shared.SCENE / 'Resources/Textures/SceneResourceBudget.swift']
        own = [Path(__file__), CASES]
        identity = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in own}
        evidence = os.environ.get('MWX_DIRECTIONAL_SHADOW_EVIDENCE')
        if evidence:
            Path(evidence).mkdir(parents=True, exist_ok=True)
            (Path(evidence) / 'receiver-plane-test-identity.json').write_text(json.dumps(identity, indent=2))
        cls.report = shared.run_swift(paths, harness(), label='receiver-plane',
                                      metal_sources=[MODEL.METAL_SOURCE], input_value=cls.inputs)
        if identity != {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in own}:
            raise AssertionError('Receiver-plane test input changed during execution')

    def test_actual_gpu_coverage_and_positive_direct_light(self):
        for expected, actual in zip(self.inputs, self.report['rows'], strict=True):
            with self.subTest(case=expected['name']):
                self.assertEqual(actual['name'], expected['name'])
                self.assertTrue(actual['completed'])
                ambient, full, shadowed = actual['pixels']
                for pixel in [ambient, full, shadowed]:
                    self.assertTrue(all(math.isfinite(v) for v in pixel))
                    self.assertEqual(pixel[3], .75)
                self.assertTrue(all(full[k] > ambient[k] for k in range(3)))

    def test_curved_receiver_is_unoccluded_at_lit_filter_taps(self):
        for row in self.report['rows']:
            with self.subTest(case=row['name']):
                _, full, shadowed = row['pixels']
                self.assertEqual(shadowed[:3], full[:3])

    def test_equivalent_receiver_index_width_preserves_pixels(self):
        rows = {row['name']: row for row in self.report['rows']}
        for case in json.loads(CASES.read_text())['cases']:
            with self.subTest(case=case['name']):
                self.assertEqual(rows[case['name'] + '-u16']['pixels'],
                                 rows[case['name'] + '-u32']['pixels'])


if __name__ == '__main__':
    unittest.main()
