#!/usr/bin/env python3
"""Actual spot model shadows; independent geometric expectations, no source-shape gates."""
import hashlib
import json
import math
import os
from pathlib import Path
import unittest

from script.tests import test_scene_directional_shadow as shared
from script.tests import test_scene_static_model_pipeline as model

SCENE = shared.SCENE
DEPTH_TOLERANCE = 2e-6


def run_spot(source_paths, support, **kwargs):
    """Freeze executable test/helper identities in addition to actual product sources."""
    import tempfile
    parent=os.environ.get('MWX_DIRECTIONAL_SHADOW_EVIDENCE','/private/tmp/mwx-rf14')
    Path(parent).mkdir(parents=True,exist_ok=True)
    root=Path(tempfile.mkdtemp(prefix='spot-'+kwargs['label']+'-',dir=parent))
    helpers=[Path(__file__),Path(shared.__file__),Path(model.__file__),Path(f.__file__)]
    identity={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in helpers}
    (root/'test-source-before.json').write_text(json.dumps(identity,indent=2))
    (root/'test.executed.py').write_bytes(Path(__file__).read_bytes())
    if kwargs.get('input_value') is not None:
        (root/'oracle-prerun.json').write_text(json.dumps(kwargs['input_value'],indent=2))
    previous=os.environ.get('MWX_DIRECTIONAL_SHADOW_EVIDENCE')
    os.environ['MWX_DIRECTIONAL_SHADOW_EVIDENCE']=str(root)
    try:
        return shared.run_swift(source_paths,support,**kwargs)
    finally:
        after={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in helpers}
        (root/'test-source-after.json').write_text(json.dumps(after,indent=2))
        if previous is None:os.environ.pop('MWX_DIRECTIONAL_SHADOW_EVIDENCE',None)
        else:os.environ['MWX_DIRECTIONAL_SHADOW_EVIDENCE']=previous
        if after!=identity:raise AssertionError(f'test/helper source changed: {root}')


def _sub(a, b):
    return [x-y for x, y in zip(a, b)]


def _dot(a, b):
    return sum(x*y for x, y in zip(a, b))


def _cross(a, b):
    return [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]]


def ray_triangle(ray, triangle):
    """Double intersection from the origin, independent of product projection."""
    a, b, c = triangle
    e1, e2 = _sub(b, a), _sub(c, a)
    h = _cross(ray, e2)
    determinant = _dot(e1, h)
    if abs(determinant) < 1e-12:
        return None
    s = [-v for v in a]
    u = _dot(s, h)/determinant
    q = _cross(s, e1)
    v = _dot(ray, q)/determinant
    t = _dot(e2, q)/determinant
    if t <= 0 or u < 0 or v < 0 or u+v > 1:
        return None
    return t, min(u, v, 1-u-v)


def depth_vectors():
    cases = [
        ('unequal-w', [[[-.8,-.8,1],[1.2,-1,2],[0,1.8,3]]]),
        ('one-behind', [[[-.8,-.7,1],[.8,-.7,1],[0,.3,-.5]]]),
        ('two-behind-nondegenerate', [[[0,0,1],[-1,-1,-1],[1,-1,-1]]]),
        ('on-plane', [[[-.8,-.7,1],[.8,-.7,1],[0,.4,0]]]),
        ('through-apex', [[[-1,-1,1],[1,1,1],[0,0,-1]]]),
        ('side-clip', [[[-3,-3,1],[3,-3,1],[0,3,1]]]),
        ('overlap', [[[-.8,-.8,1],[1.2,-1,2],[0,1.8,3]],[[-1,-1,1],[1,-1,1],[0,1,1]]]),
        ('overlap-reverse', [[[-1,-1,1],[1,-1,1],[0,1,1]],[[-.8,-.8,1],[1.2,-1,2],[0,1.8,3]]]),
        ('unequal-w-dyadic', [[[-.5,-.5,1],[1,-1,2],[0,2,4]]]),
        ('one-behind-dyadic', [[[-.5,-.5,1],[.5,-.5,1],[0,.5,-.5]]]),
        ('on-plane-dyadic', [[[-.5,-.5,1],[.5,-.5,1],[0,.5,0]]]),
        ('very-near-positive', [[[-.00001,-.00001,.00002],[.00001,-.00001,.00002],[0,.00001,.00002]]]),
        ('sphere-crossing', [[[-30,-30,9],[30,-30,9],[0,30,9]]]),
        ('sphere-outside', [[[-30,-30,20],[30,-30,20],[0,30,20]]]),
    ]
    result = []
    expanded = [(name, triangles, 64, 1.0) for name, triangles in cases]
    expanded += [('cone-narrow-96', cases[0][1], 96, .5), ('cone-wide-96', cases[0][1], 96, 2.0)]
    for name, triangles, size, tangent in expanded:
        expected, skip = [], []
        for y in range(size):
            for x in range(size):
                ray = [(2*(x+.5)/size-1)*tangent, (1-2*(y+.5)/size)*tangent, 1]
                hits = [h for tri in triangles if (h := ray_triangle(ray, tri)) is not None
                        and h[0]*math.sqrt(_dot(ray, ray)) < 10]
                nearest = min(hits, default=None)
                expected.append(nearest[0]/10 if nearest else 1)
                skip.append(bool(nearest and nearest[1] < 1e-4))
        covered = sum(v < 1 for v in expected)
        if name not in ('through-apex', 'side-clip', 'sphere-outside'):
            assert 0 < covered < size*size, name
        # Retain geometric points; orient each plane consistently for the real
        # renderer counterclockwise convention after Metal viewport Y inversion.
        draw_triangles = [tri if _dot(_cross(_sub(tri[1], tri[0]), _sub(tri[2], tri[0])), tri[0]) >= 0
                          else [tri[0], tri[2], tri[1]] for tri in triangles]
        result.append(dict(name=name, triangles=triangles, draw_triangles=draw_triangles, expected=expected, skip=skip, size=size, outer_degrees=math.degrees(2*math.atan(tangent))))
    front = next(r for r in result if r['name'] == 'unequal-w-dyadic')
    result.append(dict(front, name='backface-culled', draw_triangles=[[t[0],t[2],t[1]] for t in front['draw_triangles']], expected=[1]*4096, skip=[False]*4096))
    return result


def sources():
    result = [getattr(model, name) for name in [
        'MODEL_SOURCE', 'SAMPLING_SOURCE', 'UV_TRANSFORM_SOURCE', 'DIRECTIONAL_LIGHT_SOURCE',
        'POINT_LIGHT_SOURCE', 'SPOT_LIGHT_SOURCE', 'LIGHT_SOURCE', 'DYNAMIC_SNAPSHOT_SOURCE',
        'DYNAMIC_LAYER_VALUES_SOURCE', 'PERFORMANCE_COUNTER_SOURCE', 'PIPELINE_SOURCE']]
    return result + [SCENE/'Resources/Textures/SceneResourceBudget.swift',
                     SCENE/'Rendering/Metal/SceneStaticModelShadow.swift']


DEPTH_MAIN = r'''
@main enum SpotDepthProbe {
 static func main() throws {
  let rows=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [[String:Any]]
  let d=MTLCreateSystemDefaultDevice()!,queue=d.makeCommandQueue()!
  let pipeline=SceneStaticModelPipeline(device:d,colorPixelFormat:.rgba16Float)!
  func projection(_ degrees:Float) -> SceneSpotShadowProjection { let light=SceneLightSnapshot.Spot(layerID:10,castsShadow:true,position:.zero,directionFromLight:SIMD3(0,0,1),color:SIMD3(repeating:1),intensity:1,radius:10,innerConeCosine:cos(Float.pi/6),outerConeCosine:cos(degrees*Float.pi/360),outerConeDegrees:degrees)
  return SceneSpotShadowProjection.make(light:light)! }
  let td=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba32Float,width:1,height:1,mipmapped:false);td.storageMode = .shared;td.usage = .shaderRead
  let albedo=d.makeTexture(descriptor:td)!;var white:[Float]=[1,1,1,1];albedo.replace(region:MTLRegionMake2D(0,0,1,1),mipmapLevel:0,withBytes:&white,bytesPerRow:16)
  let material=SceneStaticModelMaterial(color:SIMD3(repeating:1),opacity:1,receivesLighting:true,textureAlphaIsOpacity:true,textureAlphaIsTintMask:false,emissiveColor:.zero,emissiveBrightness:1,brightness:1,usesHDRBrightness:false,viewTint:nil)
  var result:[[String:Any]]=[]
  for row in rows {
   let size=row["size"] as! Int, projection=projection(Float(row["outer_degrees"] as! Double))
   let triangles=row["draw_triangles"] as! [[[Double]]]
   // Actual mesh uses front-facing winding toward this light. No cull override.
   let vertices=triangles.flatMap { $0 }.map { p in SceneMdlStaticModel.Vertex(position:SIMD3(Float(p[0]),Float(p[1]),Float(p[2])),normal:SIMD3(0,0,-1),tangent:SIMD4(1,0,0,1),uv:SIMD2(0.5,0.5)) }
   let mesh=pipeline.makeMesh(vertices:vertices,indices:Array(0..<UInt32(vertices.count)))!
   let td=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:size,height:size,mipmapped:false);td.storageMode = .private;td.usage = [.renderTarget,.shaderRead]
   let target=d.makeTexture(descriptor:td)!,cb=queue.makeCommandBuffer()!
   let rp=MTLRenderPassDescriptor();rp.depthAttachment.texture=target;rp.depthAttachment.loadAction = .clear;rp.depthAttachment.storeAction = .store;rp.depthAttachment.clearDepth=1
   let e=cb.makeRenderCommandEncoder(descriptor:rp)!
   precondition(pipeline.drawShadow(mesh:mesh,texture:albedo,textureFrame:.identity,sampling:.linearClamp,modelMatrix:matrix_identity_float4x4,projection:.spot(projection),targetExtent:(width:size,height:size),layerAlpha:1,material:material,encoder:e));e.endEncoding()
   let rowBytes=((size*4+255)/256)*256
   let buf=d.makeBuffer(length:rowBytes*size,options:.storageModeShared)!,b=cb.makeBlitCommandEncoder()!
   b.copy(from:target,sourceSlice:0,sourceLevel:0,sourceOrigin:.init(x:0,y:0,z:0),sourceSize:.init(width:size,height:size,depth:1),to:buf,destinationOffset:0,destinationBytesPerRow:rowBytes,destinationBytesPerImage:rowBytes*size);b.endEncoding();cb.commit();cb.waitUntilCompleted()
   result.append(["name":row["name"]!,"completed":cb.status == .completed && cb.error == nil,"depth":(0..<size).flatMap { y in Array(UnsafeBufferPointer(start:buf.contents().advanced(by:y*rowBytes).bindMemory(to:Float.self,capacity:size),count:size)) }])
  }
  print(String(data:try JSONSerialization.data(withJSONObject:["rows":result]),encoding:.utf8)!)
 }
}
'''


class SceneSpotModelShadowDepthTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.vectors = depth_vectors()
        parent = Path(os.environ.get('MWX_DIRECTIONAL_SHADOW_EVIDENCE', '/private/tmp/mwx-rf14'))
        parent.mkdir(parents=True, exist_ok=True)
        own = Path(__file__)
        identity = hashlib.sha256(own.read_bytes()).hexdigest()
        (parent/'spot-depth-prerun.json').write_text(json.dumps({
            'test': str(own), 'sha256': identity, 'tolerance': DEPTH_TOLERANCE,
            'vectors': cls.vectors}, indent=2))
        cls.report = run_spot(sources(), 'import Foundation\nimport Metal\nimport simd\n'+model.LIGHTING_STUB+DEPTH_MAIN,
                                     label='spot-product-depth', metal_sources=[model.METAL_SOURCE], input_value=cls.vectors)
        if hashlib.sha256(own.read_bytes()).hexdigest() != identity:
            raise AssertionError('test source changed during execution')

    def test_actual_perspective_depth_and_homogeneous_clip(self):
        for expected, actual in zip(self.vectors, self.report['rows']):
            with self.subTest(case=expected['name']):
                self.assertTrue(actual['completed'])
                errors = []
                for i, (wanted, value, skip) in enumerate(zip(expected['expected'], actual['depth'], expected['skip'])):
                    if skip:
                        continue
                    if wanted == 1:
                        if value != 1:
                            errors.append((i, value, wanted))
                    elif abs(value-wanted) > DEPTH_TOLERANCE:
                        errors.append((i, value, wanted))
                self.assertEqual(len(errors), 0, errors[:8])

    def test_actual_depth_order_is_independent_of_submission_order(self):
        rows = {r['name']: r for r in self.report['rows']}
        self.assertEqual(rows['overlap']['depth'], rows['overlap-reverse']['depth'])


def radiance_vectors():
    """Finite light segments and coverage policy, independent of shadow-map math."""
    from script.tests.fixtures.scene_directional_shadow_oracle import rectangle, ray_triangle as world_hit
    specs = [
        ('opaque', [92,48,0], rectangle(84,88,44,52)),
        ('healthy', [68,48,0], rectangle(84,88,44,52)),
        ('no-caster', [92,48,0], None),
        ('cast-false', [92,48,0], rectangle(84,88,44,52,cast=False)),
        ('unlit-caster', [92,48,0], rectangle(84,88,44,52,receives_lighting=False)),
        ('alpha-zero', [92,48,0], rectangle(84,88,44,52,texture_alpha=0)),
        ('alpha-half', [92,48,0], rectangle(84,88,44,52,texture_alpha=.5)),
        ('alpha-below-half', [92,48,0], rectangle(84,88,44,52,texture_alpha=.499755859375)),
        ('alpha-above-half', [92,48,0], rectangle(84,88,44,52,texture_alpha=.50048828125)),
        ('tint-mask', [92,48,0], rectangle(84,88,44,52,texture_alpha=0,tint_mask=True)),
        ('layer-half', [92,48,0], rectangle(84,88,44,52,layer_alpha=.5)),
        ('self-flat', [86,48,20], rectangle(70,102,32,64)),
    ]
    result=[]
    for name, point, caster in specs:
        result.append(dict(name=name,receiver=point,casters=[] if caster is None else [caster],slope=[0,0]))
    for slope in ([.25,.125],[-.5,.25],[2,.5]):
        center=[86.27,48.13,20]
        q=rectangle(70,102,32,64)
        q['triangles']=[[[x,y,20+slope[0]*(x-center[0])+slope[1]*(y-center[1])] for x,y,_ in tri] for tri in q['triangles']]
        toward=_sub([80,48,40],center);norm=math.sqrt(_dot(toward,toward));unit=[v/norm for v in toward]
        for gap in [0,.1,-.1]:
            point=[c-gap*d for c,d in zip(center,unit)]
            result.append(dict(name=f'slope-{slope}-gap-{gap}',receiver=point,casters=[q],slope=slope))
    import copy
    for original in result[-3:]:
        v=copy.deepcopy(original);v['name']='translated-'+v['name'];shift=[1024,-2048,256]
        v['receiver']=[x+d for x,d in zip(v['receiver'],shift)]
        for c in v['casters']:
            c['triangles']=[[[x+d for x,d in zip(point,shift)] for point in tri] for tri in c['triangles']]
        v['light_position']=[x+d for x,d in zip([80,48,40],shift)]
        v['receiver_half_extent']=10
        result.append(v)
    for name,extras in [('perspective-world-shift',{'camera':'perspective'}),
                         ('caster-parent-translation',{}),('caster-nonuniform-scale',{}),
                         ('narrow-cone',{'outer_degrees':40,'inner_degrees':35}),
                         ('wide-cone',{'outer_degrees':140,'inner_degrees':120})]:
        v=copy.deepcopy(result[0]);v.update(name=name,**extras);result.append(v)
    result.append(dict(name='receiver-near-light',receiver=[84,48,30],casters=[rectangle(81.5,82.5,47.5,48.5,z=35)],slope=[0,0]))
    result.append(dict(name='caster-behind-light',receiver=[92,48,0],casters=[rectangle(72,76,44,52,z=60)],slope=[0,0]))
    result.append(dict(name='outside-cone-direct-zero',receiver=[140,48,0],casters=[rectangle(109,111,47,49)],slope=[0,0],direct_positive=False))
    result.append(dict(name='outside-sphere-direct-zero',receiver=[200,48,0],receiver_half_extent=10,casters=[rectangle(139,141,47,49)],slope=[0,0],direct_positive=False))
    for v in result:
        v.setdefault('light_position',[80,48,40]);v['toward_light']=_sub(v['light_position'],v['receiver'])
        v['light_intensity']=2.0
        visibility=1
        for c in v['casters']:
            coverage=c.get('layer_alpha',1)*c.get('material_opacity',1)
            if c.get('uses_coverage_alpha',True) and not c.get('tint_mask',False):coverage*=c.get('texture_alpha',1)
            if not c.get('cast',True) or coverage<=.5:continue
            if any((t:=world_hit(v['receiver'],v['toward_light'],tri)) is not None and t<1 for tri in c['triangles']):visibility=0
        v['expected_visibility']=visibility
    return result


def radiance_main():
    code=shared.PIXEL_MAIN
    start=code.index('   let projection = SceneDirectionalShadowProjection.make(')
    end=code.index('   let cb = queue.makeCommandBuffer()!',start)
    code=code[:start]+r'''
   let lp=v["light_position"] as! [Double]
   let lightPosition=SIMD3<Float>(Float(lp[0]),Float(lp[1]),Float(lp[2])+(perspective ? 20:0))
   let outer=Float(v["outer_degrees"] as? Double ?? 90),inner=Float(v["inner_degrees"] as? Double ?? 60)
   func spot(_ intensity:Float)->SceneLightSnapshot.Spot {
    .init(layerID:10,castsShadow:true,position:lightPosition,directionFromLight:SIMD3(0,0,-1),color:SIMD3(repeating:1),intensity:intensity,radius:100,innerConeCosine:cos(inner*Float.pi/360),outerConeCosine:cos(outer*Float.pi/360),outerConeDegrees:outer)
   }
   let projection=SceneSpotShadowProjection.make(light:spot(1))!
''' + code[end:]
    code=code.replace('.directional(projection)', '.spot(projection)')
    start=code.index('    let lights = SceneLightSnapshot(')
    end=code.index('    let enabled = ',start)
    code=code[:start]+r'''
    let lights=SceneLightSnapshot(ambient:SIMD3(repeating:mode == 4 ? 0 : 0.08),directional:[
      .init(layerID:11,directionTowardLight:SIMD3(0,0,1),color:SIMD3(0.5,0.7,1),intensity:mode == 5 ? 0 : 0.2)],point:[],spot:[spot(selected)],overflowCount:0)
''' +code[end:]
    line='   let receiver = mesh([[[x0,y0,receiverZ],[x1,y1,receiverZ],[x1,y0,receiverZ]],[[x0,y0,receiverZ],[x0,y1,receiverZ],[x1,y1,receiverZ]]])'
    replacement=r'''
   let slope=v["slope"] as! [Double]
   func z(_ x:Double,_ y:Double)->Double { receiverZ+slope[0]*(x-position[0])+slope[1]*(y-position[1]) }
   let receiver=mesh([[[x0,y0,z(x0,y0)],[x1,y1,z(x1,y1)],[x1,y0,z(x1,y0)]],[[x0,y0,z(x0,y0)],[x0,y1,z(x0,y1)],[x1,y1,z(x1,y1)]]])
'''
    code=code.replace(line,replacement)
    code=code.replace('   if v["camera"] as? String == "perspective" { view.columns.2.w = -0.01 }', '   view.columns.3.z += Float(position[2])*0.001\n   if v["camera"] as? String == "perspective" { view.columns.2.w = -0.01 }')
    code=code.replace('   if translated { casterWorld.columns.3.x = 5 }', '   if translated { casterWorld.columns.3.x = 5 }\n   if v["name"] as? String == "caster-nonuniform-scale" {casterWorld.columns.0.x=2;casterWorld.columns.1.y=0.5}')
    code=code.replace('    return mesh(triangles)', '    if v["name"] as? String == "caster-nonuniform-scale" { for i in triangles.indices { for j in triangles[i].indices {triangles[i][j][0] /= 2;triangles[i][j][1] *= 2} } }\n    return mesh(triangles)')
    return code


class SceneSpotModelShadowRadianceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.vectors=radiance_vectors()
        cls.report=run_spot(sources(),'import Foundation\nimport Metal\nimport simd\n'+model.LIGHTING_STUB+radiance_main(),label='spot-radiance',metal_sources=[model.METAL_SOURCE],input_value=cls.vectors)

    def test_finite_ray_visibility_and_self_positive_negative_gaps(self):
        for vector,row in zip(self.vectors,self.report['rows']):
            with self.subTest(case=vector['name']):
                a,full,actual,stale,_,_,_,wrong_light,wrong_cb=row['pixels']
                self.assertTrue(row['completed'])
                for c in range(3):
                    if vector.get("direct_positive",True):self.assertGreater(full[c]-a[c],.02)
                    else:self.assertEqual(full[c],a[c])
                    expected=a[c]+vector['expected_visibility']*(full[c]-a[c])
                    tolerance=2*max(2**-24,2**(math.floor(math.log2(abs(expected)))-10)) if expected else 2**-23
                    self.assertLessEqual(abs(actual[c]-expected),tolerance)
                self.assertEqual([p[3] for p in row['pixels']],[.75]*9)
                self.assertEqual(stale,full);self.assertEqual(wrong_light,full);self.assertEqual(wrong_cb,full)
                if vector['expected_visibility']==1:self.assertEqual(actual,full)

    def test_ambient_emission_and_other_light_are_preserved(self):
        for row in self.report['rows']:
            with self.subTest(case=row['name']):
                a,_,_,_,no_ambient,no_second,no_emission,_,_=row['pixels']
                for c in range(3):
                    self.assertGreater(a[c]-no_ambient[c],.005)
                    self.assertGreater(a[c]-no_second[c],.005)
                    self.assertGreater(a[c]-no_emission[c],.005)

PARSER_MAIN = r'''
@main enum SpotAuthoredProbe {
 static func main() throws {
  let json="""
  [{"light":"lspot"},{"light":"lspot","castshadow":true},{"light":"lspot","castshadow":false},{"light":"lspot","castshadow":1},{"light":"lspot","castshadow":0},{"light":"lspot","castshadow":"true"},{"light":"lspot","castshadow":null},{"light":"lspot","castshadow":{"value":true}},{"light":"lspot","castshadow":{"value":1}}]
  """
  let input=try JSONSerialization.jsonObject(with:Data(json.utf8)) as! [[String:Any]]
  let values=input.map { root -> String in let x=SceneSpotLightDefinition.parse(root)!.castsShadow;return x.map{$0 ? "true":"false"} ?? "nil" }
  let old=try JSONDecoder().decode(SceneSpotLightDefinition.self,from:Data("{\"kind\":\"lspot\"}".utf8))
  print(String(data:try JSONSerialization.data(withJSONObject:["values":values,"oldDecode":old.castsShadow == nil]),encoding:.utf8)!)
 }
}
'''


class SceneSpotModelShadowAuthoredTests(unittest.TestCase):
    def test_actual_strict_cast_boolean_and_old_codable_omission(self):
        report=run_spot([model.DIRECTIONAL_LIGHT_SOURCE,model.SPOT_LIGHT_SOURCE],
            'import Foundation\n'+PARSER_MAIN,label='spot-authored')
        self.assertEqual(report['values'],['nil','true','false','nil','nil','nil','nil','true','nil'])
        self.assertTrue(report['oldDecode'])

SNAPSHOT_MAIN = r'''
@main enum SpotSnapshotProbe {
 static func main() throws {
  var layers:[SceneRenderDescriptor.Layer]=[]
  for i in 0..<5 {
   let root:[String:Any]=["light":"lspot","color":"1 1 1","intensity":1,"radius":100,"innercone":30,"outercone":60+i*10,"castshadow":i != 1]
   layers.append(.init(id:10+i,visible:true,spotLight:SceneSpotLightDefinition.parse(root),directionalLight:nil))
  }
  let descriptor=SceneRenderDescriptor(lighting:nil,layers:layers,renderOrderLayerIDs:[14,12,11,10,13])
  var world=matrix_identity_float4x4
  world.columns.0=SIMD4(0,0,-2,0);world.columns.2=SIMD4(3,0,0,0);world.columns.3=SIMD4(10,20,30,1)
  let frames=Dictionary(uniqueKeysWithValues:layers.map{($0.id,world)})
  let dynamic=SceneDynamicSnapshotResolver().resolve(frameIndex:1,generation:1,definitions:[.init(target:.layer(layerID:12,field:.intensity),valueType:.scalar,authoredValue:.scalar(1))],userValues:[:],sceneScriptValues:[.layer(layerID:12,field:.intensity):.scalar(2.5)]).snapshot
  let snapshot=SceneLightSnapshot.make(descriptor:descriptor,worldFramesByLayerID:frames,dynamicLayerColors:[12:SIMD3(0.2,0.4,0.6)],dynamicSnapshot:dynamic)
  var checks:[String:Bool]=[:]
  checks["order-budget"] = snapshot.spot.compactMap(\.layerID)==[14,12,11,10] && snapshot.overflowCount==1
  checks["cast-and-order"] = snapshot.shadowLights.compactMap(\.layerID)==[14,12,10]
  checks["world-position-direction"] = snapshot.spot.allSatisfy{$0.position==SIMD3(10,20,30) && $0.directionFromLight==SIMD3(-1,0,0)}
  checks["authored-cone"] = snapshot.spot.map(\.outerConeDegrees)==[100,80,70,60]
  checks["current-intensity-color"] = snapshot.spot[1].intensity==2.5 && snapshot.spot[1].color==SIMD3(0.2,0.4,0.6)
  let directional=SceneRenderDescriptor.Layer(id:2,visible:true,spotLight:nil,directionalLight:.parse(["light":"ldirectional","castshadow":true,"intensity":1]))
  let mixed=SceneRenderDescriptor(lighting:nil,layers:[layers[0],directional,layers[2],layers[3],layers[4]])
  let current=SceneLightSnapshot.make(descriptor:mixed,worldFramesByLayerID:frames.merging([2:matrix_identity_float4x4]){$1})
  checks["directional-priority-four-total"] = current.shadowLights.compactMap(\.layerID)==[2,10,12,13] && current.overflowCount==1
  var moved=world;moved.columns.3.x=40
  let next=SceneLightSnapshot.make(descriptor:descriptor,worldFramesByLayerID:Dictionary(uniqueKeysWithValues:layers.map{($0.id,moved)}))
  checks["next-current-no-stale-transform"] = next.spot.allSatisfy{$0.position.x==40} && snapshot.spot.allSatisfy{$0.position.x==10}
  print(String(data:try JSONSerialization.data(withJSONObject:checks),encoding:.utf8)!)
 }
}
'''

class SceneSpotModelShadowSnapshotTests(unittest.TestCase):
    def test_actual_current_snapshot_order_budget_cast_and_transforms(self):
        selected=[model.DIRECTIONAL_LIGHT_SOURCE,model.POINT_LIGHT_SOURCE,model.SPOT_LIGHT_SOURCE,
                  model.LIGHT_SOURCE,model.DYNAMIC_SNAPSHOT_SOURCE,model.DYNAMIC_LAYER_VALUES_SOURCE]
        report=run_spot(selected,'import Foundation\nimport simd\n'+model.LIGHTING_STUB+SNAPSHOT_MAIN,label='spot-snapshot')
        for name,passed in report.items():
            with self.subTest(check=name):self.assertTrue(passed)

MULTI_MAIN = r'''
@main enum SpotMultiProbe {
 static func main() throws {
  let inputs=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [[String:Any]]
  let d=MTLCreateSystemDefaultDevice()!,queue=d.makeCommandQueue()!,pipeline=SceneStaticModelPipeline(device:d,colorPixelFormat:.rgba16Float)!
  let td=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba32Float,width:1,height:1,mipmapped:false);td.storageMode = .shared;td.usage = .shaderRead
  let albedo=d.makeTexture(descriptor:td)!;var texels:[Float]=[0.6,0.4,0.2,1];albedo.replace(region:MTLRegionMake2D(0,0,1,1),mipmapLevel:0,withBytes:&texels,bytesPerRow:16)
  let material=SceneStaticModelMaterial(color:SIMD3(repeating:1),opacity:1,receivesLighting:true,textureAlphaIsOpacity:false,textureAlphaIsTintMask:false,emissiveColor:.zero,emissiveBrightness:0,brightness:1,usesHDRBrightness:false,viewTint:nil)
  func mesh(_ tris:[[[Double]]])->SceneStaticModelMesh { let v=tris.flatMap{$0}.map{p in SceneMdlStaticModel.Vertex(position:SIMD3(Float(p[0]),Float(p[1]),Float(p[2])),normal:SIMD3(0,0,1),tangent:SIMD4(1,0,0,1),uv:SIMD2(0.5,0.5))};return pipeline.makeMesh(vertices:v,indices:Array(0..<UInt32(v.count)))! }
  let receiver=mesh([[[10,10,0],[150,86,0],[150,10,0]],[[10,10,0],[10,86,0],[150,86,0]]])
  let lightPositions:[SIMD3<Float>]=[SIMD3(80,48,40),SIMD3(100,48,40),SIMD3(80,68,40),SIMD3(100,68,40)]
  let colors:[SIMD3<Float>]=[SIMD3(1,0.2,0.1),SIMD3(0.1,1,0.2),SIMD3(0.2,0.1,1),SIMD3(0.8,0.6,0.4)]
  func spot(_ i:Int,_ intensity:Float)->SceneLightSnapshot.Spot {.init(layerID:10+i,castsShadow:true,position:lightPositions[i],directionFromLight:SIMD3(0,0,-1),color:colors[i],intensity:intensity,radius:100,innerConeCosine:cos(Float.pi/6),outerConeCosine:cos(Float.pi/4),outerConeDegrees:90)}
  var output:[[String:Any]]=[]
  for input in inputs {
   let mixed=input["mixed"] as! Bool,triangles=input["triangles"] as! [[[Double]]]
   let casters=triangles.isEmpty ? nil : mesh(triangles)
   let cb=queue.makeCommandBuffer()!
   var records:[SceneStaticModelShadow]=[]
   for i in 0..<4 {
    let projection:SceneStaticModelShadowProjection
    if mixed && i==0 { projection = .directional(SceneDirectionalShadowProjection.make(bounds:[(receiver.boundsMinimum,receiver.boundsMaximum,matrix_identity_float4x4)]+(casters.map{[($0.boundsMinimum,$0.boundsMaximum,matrix_identity_float4x4)]} ?? []),directionTowardLight:SIMD3(0,0,1),resolution:1024)!) }
    else { projection = .spot(SceneSpotShadowProjection.make(light:spot(i,1))!) }
    let mapDesc=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:1024,height:1024,mipmapped:false);mapDesc.storageMode = .private;mapDesc.usage = [.renderTarget,.shaderRead]
    let map=d.makeTexture(descriptor:mapDesc)!,rp=MTLRenderPassDescriptor();rp.depthAttachment.texture=map;rp.depthAttachment.loadAction = .clear;rp.depthAttachment.storeAction = .store;rp.depthAttachment.clearDepth=1
    let e=cb.makeRenderCommandEncoder(descriptor:rp)!
    if let casters {precondition(pipeline.drawShadow(mesh:casters,texture:albedo,textureFrame:.identity,sampling:.linearClamp,modelMatrix:matrix_identity_float4x4,projection:projection,targetExtent:(1024,1024),layerAlpha:1,material:material,encoder:e))};e.endEncoding()
    records.append(.init(texture:map,frameEpoch:8,generation:UInt64(i+1),lightLayerID:10+i,projection:projection,commandBuffer:cb))
   }
   var buffers:[MTLBuffer]=[]
   for mode in 0..<17 {
    func intensity(_ i:Int)->Float { if mode==0{return 0};if (3..<11).contains(mode){return (mode-3)%4==i ? 2:0};return 2 }
    let directional:[SceneLightSnapshot.Directional]=mixed ? [.init(layerID:10,castsShadow:true,directionTowardLight:SIMD3(0,0,1),color:colors[0],intensity:intensity(0))] : []
    let lighting=SceneLightSnapshot(ambient:SIMD3(repeating:0.08),directional:directional,point:[],spot:(mixed ? 1..<4 : 0..<4).map{spot($0,intensity($0))},overflowCount:0)
    let shadows:[SceneStaticModelShadow]
    if mode==0 || mode==1 || (3..<7).contains(mode) {shadows=[]}
    else if (11..<15).contains(mode) { shadows=records.enumerated().filter{$0.offset != mode-11}.map(\.element) }
    else if mode==15 {shadows=[records[3]]}
    else if mode==16 {shadows=records.reversed()}
    else {shadows=records}
    let color=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba16Float,width:1,height:1,mipmapped:false);color.storageMode = .private;color.usage = .renderTarget
    let output=d.makeTexture(descriptor:color)!
    let zd=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:1,height:1,mipmapped:false);zd.storageMode = .private;zd.usage = .renderTarget
    let z=d.makeTexture(descriptor:zd)!,rp=MTLRenderPassDescriptor();rp.colorAttachments[0].texture=output;rp.colorAttachments[0].loadAction = .clear;rp.colorAttachments[0].storeAction = .store;rp.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,0);rp.depthAttachment.texture=z;rp.depthAttachment.loadAction = .clear;rp.depthAttachment.storeAction = .dontCare;rp.depthAttachment.clearDepth=0
    let e=cb.makeRenderCommandEncoder(descriptor:rp)!
    let view=simd_float4x4(rows:[SIMD4(0.1,0,0,-9.2),SIMD4(0,-0.1,0,4.8),SIMD4(0,0,-0.001,0.5),SIMD4(0,0,0,1)])
    precondition(pipeline.draw(mesh:receiver,texture:albedo,colorTextureIsPremultiplied:false,emissiveMask:nil,emissiveMaskTextureFrame:nil,emissiveMaskSampling:nil,modelMatrix:matrix_identity_float4x4,viewProjection:view,cameraPosition:SIMD3(92,48,100),textureFrame:.identity,sampling:.linearClamp,layerAlpha:0.75,material:material,lighting:lighting,writesDepth:true,shadows:shadows,frameEpoch:8,commandBuffer:cb,encoder:e));e.endEncoding()
    let b=d.makeBuffer(length:256,options:.storageModeShared)!,blit=cb.makeBlitCommandEncoder()!;blit.copy(from:output,sourceSlice:0,sourceLevel:0,sourceOrigin:.init(x:0,y:0,z:0),sourceSize:.init(width:1,height:1,depth:1),to:b,destinationOffset:0,destinationBytesPerRow:256,destinationBytesPerImage:256);blit.endEncoding();buffers.append(b)
   }
   cb.commit();cb.waitUntilCompleted()
   output.append(["name":input["name"]!,"completed":cb.status == .completed && cb.error == nil,"pixels":buffers.map{b in let p=b.contents().bindMemory(to:UInt16.self,capacity:4);return (0..<4).map{Float(Float16(bitPattern:p[$0]))}}])
  }
  print(String(data:try JSONSerialization.data(withJSONObject:["rows":output]),encoding:.utf8)!)
 }
}
'''


def multi_vectors():
    from script.tests.fixtures.scene_directional_shadow_oracle import rectangle, ray_triangle as world_hit
    result=[]
    positions=[[80,48,40],[100,48,40],[80,68,40],[100,68,40]]
    point=[92,48,0]
    for mixed in [False,True]:
        for selected in [[],[0],[1],[2],[3],[0,1,2,3]]:
            tris=[]
            for i in selected:
                center=[92,48] if mixed and i==0 else [(positions[i][0]+92)/2,(positions[i][1]+48)/2]
                tris+=rectangle(center[0]-1,center[0]+1,center[1]-1,center[1]+1)['triangles']
            visible=[]
            for i,light in enumerate(positions):
                direction=[0,0,1] if mixed and i==0 else _sub(light,point)
                visible.append(0 if any((t:=world_hit(point,direction,tri)) is not None and (mixed and i==0 or t<1) for tri in tris) else 1)
            result.append(dict(name=f'{"mixed" if mixed else "four-spots"}-{selected}',mixed=mixed,triangles=tris,visibility=visible))
    return result


class SceneSpotModelShadowMultiLightTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.vectors=multi_vectors()
        cls.report=run_spot(sources(),'import Foundation\nimport Metal\nimport simd\n'+model.LIGHTING_STUB+MULTI_MAIN,label='spot-multi',metal_sources=[model.METAL_SOURCE],input_value=cls.vectors)

    def test_each_light_contribution_four_maps_zero_maps_and_mixed_directional(self):
        for vector,row in zip(self.vectors,self.report['rows']):
            with self.subTest(case=vector['name']):
                self.assertTrue(row['completed'])
                pixels=row['pixels'];base=pixels[0]
                direct=[[pixels[3+i][c]-base[c] for c in range(3)] for i in range(4)]
                for d in direct:self.assertGreater(sum(d),.02)
                equivalent={tuple([0]*4):pixels[0],tuple([1]*4):pixels[1]}
                for mode in [1,2,*range(7,17)]:
                    weights=[1]*4
                    if mode==2 or mode==16:weights=vector['visibility']
                    elif 7<=mode<11:weights=[vector['visibility'][i] if i==mode-7 else 0 for i in range(4)]
                    elif 11<=mode<15:weights=[1 if i==mode-11 else vector['visibility'][i] for i in range(4)]
                    elif mode==15:weights=[1,1,1,vector['visibility'][3]]
                    key=tuple(weights)
                    if key in equivalent:self.assertEqual(pixels[mode],equivalent[key],(vector['name'],mode,key))
                    else:equivalent[key]=pixels[mode]
                    for c in range(3):
                        expected=base[c]+sum(w*d[c] for w,d in zip(weights,direct))
                        # Original F6 two-half-ULP engineering tolerance, propagated through
                        # A + sum(w*(singleFull-A)); not a global rounding theorem.
                        def half_engineering_bound(x):
                            return 2*max(2**-24,2**(math.floor(math.log2(abs(x)))-10)) if x else 2**-23
                        tolerance=abs(1-sum(weights))*half_engineering_bound(base[c])+sum(w*half_engineering_bound(pixels[3+i][c]) for i,w in enumerate(weights))+half_engineering_bound(expected)
                        self.assertLessEqual(abs(pixels[mode][c]-expected),tolerance,(mode,c,vector['visibility']))
                self.assertEqual([p[3] for p in pixels],[.75]*17)
                self.assertEqual(pixels[2],pixels[16])


from script.tests import test_scene_directional_shadow_frame_owner as f

FRAME_LIGHT_INPUTS=r'''
  func spotLayer(_ id:Int,_ outer:Float)->SceneRenderDescriptor.Layer {
   let definition=SceneSpotLightDefinition.parse(["light":"lspot","color":"1 1 1","intensity":0,
     "radius":100,"innercone":Double(outer),"outercone":Double(outer),"castshadow":true])!
   return .init(id:id,spotLight:definition,contentKind:"light")
  }
  let directionalLayer=SceneRenderDescriptor.Layer(id:7,directionalLight:.init(colorRGB:[1,1,1],intensity:0,shadowCastIntent:.enabled),contentKind:"light")
  let lightLayers:[SceneRenderDescriptor.Layer] = mode=="four-spots"
   ? [spotLayer(8,90),spotLayer(9,90),spotLayer(10,90),spotLayer(11,90)]
   : [directionalLayer,spotLayer(8,90),spotLayer(9,mode=="gap" ? Float.leastNonzeroMagnitude:90),spotLayer(10,90)]
  var lightWorld=matrix_identity_float4x4;lightWorld.columns.3=SIMD4(32,32,40,1)
  let lightDescriptor=SceneRenderDescriptor(lighting:.init(ambientColorRGB:[0.5,0.5,0.5],skylightColorRGB:nil),layers:lightLayers,renderOrderLayerIDs:lightLayers.map(\.id))
  let lighting=SceneLightSnapshot.make(descriptor:lightDescriptor,worldFramesByLayerID:Dictionary(uniqueKeysWithValues:lightLayers.map{($0.id,lightWorld)}))
  precondition(lighting.shadowLights.count==4)
'''

FRAME_OBSERVE=r'''
  let mapIDs=state.shadows.map(\.lightLayerID)
  let mapTextures=state.shadows.map{ObjectIdentifier($0.texture)}
  let mapUnique=Set(mapTextures).count==mapTextures.count
  let shadowBytesPrepared=pool.residentByteCost
  var gap:[String:Any]=[:]
  if mode=="gap" {
   // The tiny but finite authored cone was admitted by the real parser and
   // snapshot; its projection is unrepresentable. The later light keeps slot3.
   let last=state.shadows.first{$0.lightLayerID==10}!
   let probe=pool.reserveModelShadow(slot:3,width:1024,height:1024,commandBuffer:cb)!
   let stable=probe.texture === last.texture;probe.pin.release()
   let empty=pool.reserveModelShadow(slot:2,width:1024,height:1024,commandBuffer:cb)!
   gap=["laterUsesSlot3":stable,"slot2WasDistinct":!mapTextures.contains(ObjectIdentifier(empty.texture)),
        "extraSlotBytes":pool.residentByteCost-shadowBytesPrepared]
   empty.pin.release()
  }
'''

FRAME_FLIGHT=r'''
  state.arm(on:cb)
  let completion=DispatchSemaphore(value:0);cb.addCompletedHandler{_ in completion.signal()}
  cb.commit()
  var flight:[String:Any]=[:]
  if mode=="flight" {
   defer {event.signaledValue=1}
   let pending=cb.status != .completed && cb.status != .error
   pool.reset();let retained=pool.residentByteCost
   // Only one real model is needed for B. A holds two model-depth slots;
   // using a third preserves the real three-slot admission limit.
   let resizedDescriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:128,height:128,mipmapped:false)
   resizedDescriptor.usage=[.renderTarget,.shaderRead];resizedDescriptor.storageMode = .shared
   let resized=device.makeTexture(descriptor:resizedDescriptor)!,nextCB=queue.makeCommandBuffer()!
   let nextPass=SceneMainPassEncoder(commandBuffer:nextCB,target:resized,clearColor:MTLClearColorMake(0,0,0,1),clearEnabled:true)
   let nextLayers=[layers[0]],nextState=SceneMetalRenderer.StaticModelFrame()
   var nextLeases:[SceneParticleDepthTargetLease]=[],nextMandatory=0
   let nextCandidates=renderer.shadowDrawCandidates(orderedLayers:nextLayers,visible:[1],worldFrames:world,snapshot:dynamic,groups:nil)!
   renderer.prepareModelShadow(state:nextState,candidates:nextCandidates,lights:lighting.shadowLights,
    orderedLayers:nextLayers,visible:[1],batches:[:],particlePipeline:nil,mainPass:nextPass,groups:nil,pool:pool,
    commandBuffer:nextCB,leases:&nextLeases,mandatoryCapacity:{nextMandatory+=1;return true},recordsEvidence:false)
   let separate=nextState.shadows.allSatisfy{!mapTextures.contains(ObjectIdentifier($0.texture))}
   let nextCount=nextState.shadows.count,nextDepth=nextLeases.count
   let oldDepth=shared!.texture,cancelledDepth=nextLeases.first!.texture
   let separateDepth=oldDepth !== cancelledDepth
   nextPass.closeForOffscreen();nextPass.cancelCompositionPins();nextState.cancel();nextLeases.forEach{$0.cancel()}
   pool.reset()
   let probe=renderer.staticModelDepthTargetPool.acquire(device:device,width:128,height:128)!
   let cancellationReusable=probe.texture === cancelledDepth;probe.cancel()
   flight=["pending":pending,"retainedAfterReset":retained,"nextCount":nextCount,"nextMandatory":nextMandatory,
    "nextDepth":nextDepth,"separateMaps":separate,"separateDepth":separateDepth,
    "retainedAfterCancel":pool.residentByteCost,"cancelledDepthReusable":cancellationReusable,
    "cancelledNotSubmitted":nextCB.status == .notEnqueued]
  }
  event.signaledValue=1
  precondition(completion.wait(timeout:.now()+15) == .success)
  cb.waitUntilCompleted()
  if mode=="flight" {
   flight["residentAfterCompletion"]=pool.residentByteCost
   let probe=renderer.staticModelDepthTargetPool.acquire(device:device,width:64,height:64)!
   flight["completedDepthReusable"]=probe.texture === shared!.texture;probe.cancel()
   // C is a fresh, completed actual owner frame after A completion and B cancel.
   let recoveryCB=queue.makeCommandBuffer()!
   let recoveryDescriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:64,height:64,mipmapped:false)
   recoveryDescriptor.usage=[.renderTarget,.shaderRead];recoveryDescriptor.storageMode = .shared
   let recoveryOutput=device.makeTexture(descriptor:recoveryDescriptor)!
   let recoveryPass=SceneMainPassEncoder(commandBuffer:recoveryCB,target:recoveryOutput,clearColor:MTLClearColorMake(0,0,0,1),clearEnabled:true)
   let recoveryState=SceneMetalRenderer.StaticModelFrame(),recoveryLayers=[layers[0]]
   var recoveryLeases:[SceneParticleDepthTargetLease]=[],recoveryMandatory=0
   let recoveryCandidates=renderer.shadowDrawCandidates(orderedLayers:recoveryLayers,visible:[1],worldFrames:world,snapshot:dynamic,groups:nil)!
   renderer.prepareModelShadow(state:recoveryState,candidates:recoveryCandidates,lights:lighting.shadowLights,
    orderedLayers:recoveryLayers,visible:[1],batches:[:],particlePipeline:nil,mainPass:recoveryPass,groups:nil,pool:pool,
    commandBuffer:recoveryCB,leases:&recoveryLeases,mandatoryCapacity:{recoveryMandatory+=1;return true},recordsEvidence:false)
   flight["recoveryMapIDs"]=recoveryState.shadows.map(\.lightLayerID)
   flight["recoveryCurrentCB"]=recoveryState.shadows.allSatisfy{$0.commandBuffer === recoveryCB}
   flight["recoveryMandatory"]=recoveryMandatory
   let recoveryDepthBefore=recoveryLeases.count
   let recoveryDraw=renderer.drawStaticModel(layer:layers[0],state:recoveryState,worldFrames:world,frameContext:.init(dynamicValues:dynamic),
    cameraFrame:camera,lighting:lighting,pass:recoveryPass,commandBuffer:recoveryCB,leases:&recoveryLeases)
   flight["recoveryDraw"]=recoveryDraw
   flight["recoveryDepthOnce"]=recoveryDepthBefore==1 && recoveryLeases.count==1
   precondition(recoveryPass.finishEnsuringClear())
   recoveryLeases.forEach{$0.arm(on:recoveryCB)};recoveryState.arm(on:recoveryCB)
   let recoveryCompletion=DispatchSemaphore(value:0)
   recoveryCB.addCompletedHandler{_ in recoveryCompletion.signal()}
   recoveryCB.commit();precondition(recoveryCompletion.wait(timeout:.now()+15) == .success);recoveryCB.waitUntilCompleted()
   flight["recoveryCompleted"]=recoveryCB.status == .completed
   pool.reset();flight["recoveryResidentAfterReset"]=pool.residentByteCost

  }
'''


def frame_owner_main():
    s=f.MAIN
    s=s.replace('["original", "prepared", "optional-quota", "mandatory-quota"]',
        '["original","full","four-spots","quota0","quota1","quota2","gap","flight"]')
    s=s.replace('try run(mode,device,queue)','try autoreleasepool {try run(mode,device,queue)}')
    a=s.index('  let light=SceneLightSnapshot.Directional');b=s.index('  let instances=',a)
    s=s[:a]+FRAME_LIGHT_INPUTS+s[b:]
    s=s.replace('  let cb=queue.makeCommandBuffer()!',
        '  let cb=queue.makeCommandBuffer()!,event=device.makeSharedEvent()!\n  if mode=="flight" {cb.encodeWaitForEvent(event,value:1)}')
    s=s.replace('residentByteBudget:8*1024*1024','residentByteBudget:40*1024*1024')
    s=s.replace('  var held=0','  var held=0,mandatoryCalls=0')
    a=s.index('  if mode.hasSuffix("quota")');b=s.index('  defer { if held>0',a)
    s=s[:a]+r'''
  let shadowDescriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:1024,height:1024,mipmapped:false)
  shadowDescriptor.storageMode = .private;shadowDescriptor.usage=[.renderTarget,.shaderRead]
  let shadowBytes=device.heapTextureSizeAndAlign(descriptor:shadowDescriptor).size
  if mode.hasPrefix("quota") {
   let maps=Int(mode.suffix(1))!
   let capacity=3*depthBytes+maps*shadowBytes
   held=SceneResourceBudget.shared.maximumBytes-SceneResourceBudget.shared.snapshot.residentBytes-capacity
   precondition(SceneResourceBudget.shared.reserve(held,kind:.gpu))
  }
'''+s[b:]
    s=s.replace('lights:[.directional(light)]','lights:lighting.shadowLights')
    s=s.replace('mandatoryCapacity:{true}','mandatoryCapacity:{mandatoryCalls+=1;return true}')
    s=s.replace('  let published = !state.shadows.isEmpty','  let published = !state.shadows.isEmpty\n'+FRAME_OBSERVE)
    s=s.replace('if mode=="mandatory-quota" {SceneResourceBudget.shared.release(held,kind:.gpu);held=0}',
                'if mode.hasPrefix("quota") {SceneResourceBudget.shared.release(held,kind:.gpu);held=0}')
    s=s.replace('  state.arm(on:cb);cb.commit();cb.waitUntilCompleted()',FRAME_FLIGHT)
    s=s.replace('return ["mode":mode,','return ["mapIDs":mapIDs,"mapUnique":mapUnique,"mandatoryCalls":mandatoryCalls,"shadowBytesPrepared":shadowBytesPrepared,"gap":gap,"flight":flight,"mode":mode,')
    return s


def frame_owner_harness():
    return f.pool_fixture.HARNESS.split('@main',1)[0]+f.SHELL+f.UNUSED_ORDERED_SUPPORT+frame_owner_main()


def assert_frame_owner_rows(test, rows):
    cases={r['mode']:r for r in rows}
    expected={'original':[],'full':[7,8,9,10],'four-spots':[8,9,10,11],
              'quota0':[],'quota1':[7],'quota2':[7,8],'gap':[7,8,10],'flight':[7,8,9,10]}
    for mode,r in cases.items():
        test.assertTrue(r['completed']);test.assertEqual(r['mapIDs'],expected[mode]);test.assertTrue(r['mapUnique'])
        test.assertEqual(r['pixels'],cases['original']['pixels'])
        test.assertEqual(r['mandatoryCalls'],0 if mode=='original' else 1)
        test.assertEqual(r['after'],3);test.assertEqual(r['particleDraws'],1)
        for k in ['model1','model2','model3']:test.assertTrue(r[k],(mode,k))
        if mode!='original':
            test.assertEqual(r['before'],3)
            for k in ['sharedIdentity','isolatedIdentity','particleIdentity','allocationsStable','noRetry']:
                test.assertTrue(r[k],(mode,k))
            test.assertEqual(r['shadowBytesPrepared'],len(expected[mode])*1024*1024*4)
    g=cases['gap']['gap'];test.assertTrue(g['laterUsesSlot3'] and g['slot2WasDistinct']);test.assertEqual(g['extraSlotBytes'],1024*1024*4)
    r=cases['flight']['flight']
    for k in ['pending','separateMaps','separateDepth','cancelledDepthReusable','cancelledNotSubmitted','completedDepthReusable']:
        test.assertTrue(r[k],k)
    test.assertEqual((r['nextCount'],r['nextMandatory'],r['nextDepth']),(4,1,1))
    test.assertEqual(r['retainedAfterReset'],4*1024*1024*4)
    test.assertEqual(r['retainedAfterCancel'],r['retainedAfterReset'])
    test.assertEqual(r['residentAfterCompletion'],0)
    test.assertEqual(r['recoveryMapIDs'],[7,8,9,10]);test.assertEqual(r['recoveryMandatory'],1)
    for k in ['recoveryCurrentCB','recoveryDraw','recoveryDepthOnce','recoveryCompleted']:test.assertTrue(r[k],k)
    test.assertEqual(r['recoveryResidentAfterReset'],0)



class SceneSpotModelShadowFrameOwnerTests(unittest.TestCase):
    def test_real_mandatory_once_quota_stable_slots_and_pending_lifecycle(self):
        report=run_spot(f.SOURCES,frame_owner_harness(),label='spot-frame-owner',metal_sources=[model.METAL_SOURCE])
        assert_frame_owner_rows(self,report['rows'])


def named_spot_main():
    from script.tests import test_scene_named_model_shadow as named
    code=named.named_receivers_main()
    code=code.replace('let layers=[caster,provider,receiverA,receiverB]','let layers=[provider,caster,receiverA,receiverB]')
    code=code.replace('staticModelConsumerProviders:[2:11,3:11]','staticModelConsumerProviders:[1:11,2:11,3:11]')
    code=code.replace('"caster",false','"caster",true')
    code=code.replace('activeNamedModels:[2,3]','activeNamedModels:[1,2,3]')
    code=code.replace('let sharedCurrent=[2,3].allSatisfy','let sharedCurrent=[1,2,3].allSatisfy')
    code=code.replace('let light=SceneLightSnapshot.Directional(layerID:7,castsShadow:true,directionTowardLight:SIMD3(1,0,1),color:SIMD3(repeating:1),intensity:0.5)', 'let light=SceneLightSnapshot.Spot(layerID:7,castsShadow:true,position:SIMD3(116,32,100),directionFromLight:simd_normalize(SIMD3(-1,0,-1)),color:SIMD3(repeating:1),intensity:1,radius:300,innerConeCosine:cos(Float.pi/6),outerConeCosine:cos(Float.pi/4),outerConeDegrees:90)')
    code=code.replace('directional:[light],point:[],spot:[]','directional:[],point:[],spot:[light]')
    return code.replace('lights:[.directional(light)]','lights:[.spot(light)]')


class SceneSpotModelShadowNamedTests(unittest.TestCase):
    def test_named_caster_and_two_cast_false_receivers_share_current_source(self):
        from script.tests import test_scene_named_model_shadow as named
        from script.tests.fixtures.scene_directional_shadow_oracle import rectangle, ray_triangle as world_hit
        triangles=rectangle(20,36,20,44,z=10)['triangles']
        light=[116,32,100]
        # Pre-execution world-ray checks; no product matrix or sampled map consulted.
        for point in ([16,28,0],[16,36,0]):
            self.assertTrue(any((t:=world_hit(point,_sub(light,point),tri)) is not None and t<1 for tri in triangles))
        for point in ([8,12,0],[8,52,0]):
            self.assertFalse(any((t:=world_hit(point,_sub(light,point),tri)) is not None and t<1 for tri in triangles))
        report=run_spot(named.ADMISSION_SOURCES,named.admission_support()+named_spot_main(),label='spot-named',
            metal_sources=[SCENE/'Rendering/Composition'/n for n in ['SceneImageLayer.metal','SceneStaticModel.metal','SceneLitImageLayer.metal']],
            input_value={'light':light,'caster':triangles,'shadowROI':[[16,28,0],[16,36,0]],'healthyROI':[[8,12,0],[8,52,0]]})
        named.assert_named_receiver_rows(self,report['rows'])


def partial_frame_harness(alpha):
    s=f.MAIN.replace('["original", "prepared", "optional-quota", "mandatory-quota"]','["partial"]')
    s=s.replace('func material(_ color:SIMD3<Float>)->SceneStaticModelMaterial {','func material(_ color:SIMD3<Float>,_ opacity:Float = 1)->SceneStaticModelMaterial {')
    s=s.replace('.init(color:color,opacity:1,receivesLighting:true','.init(color:color,opacity:opacity,receivesLighting:true')
    s=s.replace('func entry(_ mesh:SceneStaticModelMesh,_ identity:String,_ color:SIMD3<Float>)->ScenePreparedStaticModelResources.Entry {','func entry(_ mesh:SceneStaticModelMesh,_ identity:String,_ color:SIMD3<Float>,_ opacity:Float = 1)->ScenePreparedStaticModelResources.Entry {')
    s=s.replace('material:material(color))','material:material(color,opacity))')
    s=s.replace('2:[entry(meshA,"one-geometry",SIMD3(0,1,0))]',f'2:[entry(meshA,"one-geometry",SIMD3(0,1,0),Float(Double({alpha!r})))]')
    s=s.replace('.init(id:3),.init(id:4,contentKind:"particle")','.init(id:4,contentKind:"particle")')
    a=s.index('  let light=SceneLightSnapshot.Directional');b=s.index('  let instances=',a)
    s=s[:a]+r'''
  let spotDefinition=SceneSpotLightDefinition.parse(["light":"lspot","color":"1 1 1","intensity":0,"radius":100,"innercone":90,"outercone":90,"castshadow":true])!
  let lamp=SceneRenderDescriptor.Layer(id:7,spotLight:spotDefinition,contentKind:"light")
  var lampWorld=matrix_identity_float4x4;lampWorld.columns.3=SIMD4(32,32,40,1)
  let lighting=SceneLightSnapshot.make(descriptor:SceneRenderDescriptor(lighting:.init(ambientColorRGB:[0.5,0.5,0.5],skylightColorRGB:nil),layers:[lamp],renderOrderLayerIDs:[7]),worldFramesByLayerID:[7:lampWorld])
  precondition(lighting.shadowLights.count==1)
'''+s[b:]
    s=s.replace('lights:[.directional(light)]','lights:lighting.shadowLights')
    s=s.replace('  let cb=queue.makeCommandBuffer()!','  let cb=queue.makeCommandBuffer()!,event=device.makeSharedEvent()!\n  cb.encodeWaitForEvent(event,value:1)')
    marker='  let published = !state.shadows.isEmpty'
    assert marker in s
    s=s.replace(marker,marker+r'''
  let pinCount=state.pins.count
  // This is a read-only observation of the same slot after actual owner encode.
  // Drop the probe's extra pin so only actual frame ownership guards retirement.
  let map=pool.reserveModelShadow(slot:0,width:1024,height:1024,commandBuffer:cb)!
  let depthTexture=map.texture;map.pin.release()
''')
    start=s.index('  state.arm(on:cb);cb.commit();cb.waitUntilCompleted()')
    end=s.index('\n }\n}',start)
    s=s[:start]+r'''
  let depthReadback=device.makeBuffer(length:1024*1024*4,options:.storageModeShared)!
  let blit=cb.makeBlitCommandEncoder()!
  blit.copy(from:depthTexture,sourceSlice:0,sourceLevel:0,sourceOrigin:MTLOrigin(x:0,y:0,z:0),sourceSize:MTLSize(width:1024,height:1024,depth:1),
    to:depthReadback,destinationOffset:0,destinationBytesPerRow:1024*4,destinationBytesPerImage:1024*1024*4)
  blit.endEncoding()
  state.arm(on:cb)
  let completed=DispatchSemaphore(value:0);cb.addCompletedHandler{_ in completed.signal()}
  cb.commit()
  let pending=cb.status != .completed && cb.status != .error
  pool.reset();let retained=pool.residentByteCost
  event.signaledValue=1
  precondition(completed.wait(timeout:.now()+15) == .success);cb.waitUntilCompleted()
  let depths=depthReadback.contents().bindMemory(to:Float.self,capacity:1024*1024)
  var covered=0,finite=true
  for i in 0..<(1024*1024) {let z=depths[i];finite=finite && z.isFinite;if z<1 {covered+=1}}
  return ["mode":mode,"published":published,"pinCount":pinCount,"pending":pending,"retainedAfterReset":retained,
   "residentAfterCompletion":pool.residentByteCost,"completed":cb.status == .completed,
   "coveredDepthPixels":covered,"finiteDepth":finite,"model1":renderer.dependencyRuntime.encoded[1] ?? false,
   "model2":renderer.dependencyRuntime.encoded[2] ?? true,"preparedFirstFinite":state.prepared?[1]?.first?.material.opacity.isFinite ?? false,
   "preparedSecondFinite":state.prepared?[2]?.first?.material.opacity.isFinite ?? true]
'''+s[end:]
    return f.pool_fixture.HARNESS.split('@main',1)[0]+f.SHELL+f.UNUSED_ORDERED_SUPPORT+s

def assert_partial_frame_report(test,report):
    r=report['rows'][0]
    test.assertFalse(r['published']);test.assertEqual(r['pinCount'],1)
    for k in ['pending','completed','finiteDepth','model1','preparedFirstFinite']:test.assertTrue(r[k],k)
    for k in ['model2','preparedSecondFinite']:test.assertFalse(r[k],k)
    test.assertGreater(r['coveredDepthPixels'],0)
    test.assertEqual(r['retainedAfterReset'],4*1024*1024)
    test.assertEqual(r['residentAfterCompletion'],0)


class SceneSpotModelShadowPartialFailureTests(unittest.TestCase):
    def test_actual_authored_overflow_partial_map_retains_pin_until_completion(self):
        import tempfile
        from script.tests import test_scene_alpha_display_builder_fixture as builder
        from script.tests.test_scene_directional_shadow_integration import fixture_entries
        parent=Path(os.environ.get('MWX_DIRECTIONAL_SHADOW_EVIDENCE','/private/tmp/mwx-rf14'))
        parent.mkdir(parents=True,exist_ok=True)
        root=Path(tempfile.mkdtemp(prefix='spot-overflow-input-',dir=parent))
        scene,entries=fixture_entries()
        material=json.loads(entries['materials/caster.json'])
        material['passes'][0]['constantshadervalues']={'alpha':1e100}
        entries['materials/caster.json']=json.dumps(material).encode()
        entries['project.json']=json.dumps({'type':'scene','file':'scene.json'}).encode()
        for name,data in entries.items():
            path=root/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
        (root/'input-identity.json').write_text(json.dumps({name:hashlib.sha256(data).hexdigest() for name,data in entries.items()},indent=2))
        main=r'''
@main enum AlphaProducerProbe {
 static func main() throws {
  let root=try JSONDecoder().decode(String.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
  let model=try SceneRuntimeModelBuilder().build(rootURL:URL(fileURLWithPath:root))
  let pass=model.renderDescriptor.materialPasses.first{$0.materialPath == "materials/caster.json"}!
  let alpha=pass.constantShaderValues["alpha"]!.components!.first!
  print(String(data:try JSONSerialization.data(withJSONObject:["descriptorAlpha":alpha,"doubleFinite":alpha.isFinite,"floatFinite":Float(alpha).isFinite]),encoding:.utf8)!)
 }
}
'''
        producer=run_spot(builder.SWIFT_SOURCES,builder.HARNESS_SOURCE.split('@main',1)[0]+main,
                          label='spot-overflow-producer',input_value=str(root))
        self.assertTrue(producer['doubleFinite']);self.assertFalse(producer['floatFinite'])
        # Real CPU builder -> typed descriptor value -> prepared material boundary.
        # The GPU resource builder itself is outside this harness, not duplicated.
        report=run_spot(f.SOURCES,partial_frame_harness(producer['descriptorAlpha']),label='spot-partial-map',
                        metal_sources=[model.METAL_SOURCE],input_value=producer)
        assert_partial_frame_report(self,report)
