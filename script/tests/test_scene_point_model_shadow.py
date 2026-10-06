#!/usr/bin/env python3
"""Actual point model shadow tests; independent world-ray expected values."""
import hashlib
import itertools
import json
import math
import os
from pathlib import Path
import struct
import tempfile
import unittest
from script.tests import test_scene_directional_shadow as shared
from script.tests import test_scene_static_model_pipeline as model
from script.tests import test_scene_spot_model_shadow as spot

DEPTH_TOLERANCE=2e-6

def run_point(source_paths,support,**kwargs):
    parent=Path(os.environ.get('MWX_POINT_SHADOW_EVIDENCE','/private/tmp/mwx-rf15'))
    parent.mkdir(parents=True,exist_ok=True)
    root=Path(tempfile.mkdtemp(prefix='point-'+kwargs['label']+'-',dir=parent))
    helpers=[Path(__file__),Path(shared.__file__),Path(model.__file__),Path(spot.__file__)]
    ids={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in helpers}
    (root/'test-source-before.json').write_text(json.dumps(ids,indent=2))
    (root/'test.executed.py').write_bytes(Path(__file__).read_bytes())
    if kwargs.get('input_value') is not None:(root/'oracle-prerun.json').write_text(json.dumps(kwargs['input_value'],indent=2))
    manifest=os.environ.get('MWX_POINT_SHADOW_PRODUCT_MANIFEST')
    products=None
    if manifest:
        m=Path(manifest);products=json.loads(m.read_text())['products']
        repo=Path(__file__).resolve().parents[2]
        assert all(hashlib.sha256((repo/p).read_bytes()).hexdigest()==v for p,v in products.items())
        (root/'product-manifest.json').write_bytes(m.read_bytes())
    previous=os.environ.get('MWX_DIRECTIONAL_SHADOW_EVIDENCE')
    os.environ['MWX_DIRECTIONAL_SHADOW_EVIDENCE']=str(root)
    try:return shared.run_swift(source_paths,support,**kwargs)
    finally:
        after={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in helpers}
        (root/'test-source-after.json').write_text(json.dumps(after,indent=2))
        if previous is None:os.environ.pop('MWX_DIRECTIONAL_SHADOW_EVIDENCE',None)
        else:os.environ['MWX_DIRECTIONAL_SHADOW_EVIDENCE']=previous
        assert after==ids,'test source changed during execution'
        if products:assert all(hashlib.sha256((repo/p).read_bytes()).hexdigest()==v for p,v in products.items()),'product drift'

FACES=[('px',[0,0,-1],[0,1,0],[1,0,0],[0,0]),('nx',[0,0,1],[0,1,0],[-1,0,0],[1,0]),('py',[0,0,1],[1,0,0],[0,1,0],[2,0]),('ny',[0,0,-1],[1,0,0],[0,-1,0],[0,1]),('pz',[1,0,0],[0,1,0],[0,0,1],[1,1]),('nz',[-1,0,0],[0,1,0],[0,0,-1],[2,1])]
def f32(x):return struct.unpack('f',struct.pack('f',x))[0]
def sub(a,b):return [x-y for x,y in zip(a,b)]
def add(a,b):return [x+y for x,y in zip(a,b)]
def mul(a,s):return [x*s for x in a]
def dot(a,b):return sum(x*y for x,y in zip(a,b))
def cross(a,b):return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
def length(a):return math.sqrt(dot(a,a))
def quant(a):return [f32(x) for x in a]
def world(q,face):
 _,r,u,f,_=face;return quant([q[0]*r[i]+q[1]*u[i]+q[2]*f[i] for i in range(3)])
def hit(origin,ray,tri):
 a,b,c=tri;e1,e2=sub(b,a),sub(c,a);h=cross(ray,e2);den=dot(e1,h)
 if abs(den)<1e-18:return None
 s=sub(origin,a);u=dot(s,h)/den;q=cross(s,e1);v=dot(ray,q)/den;t=dot(e2,q)/den
 if u<0 or v<0 or u+v>1:return None
 return t,min(u,v,1-u-v)
def depth_case(name,triangles,size=32,radius=10):
 triangles=[[quant(p) for p in tri] for tri in triangles];faces=[]
 for face in FACES:
  values=[];skip=[]
  for y in range(size):
   for x in range(size):
    # Independent geometric basis from declared policy, not product projection.
    ray=world([2*(x+.5)/size-1,1-2*(y+.5)/size,1],face)
    hits=[h for t in triangles if (h:=hit([0,0,0],ray,t)) is not None and h[0]>0 and h[0]*length(ray)<radius]
    near=min(hits,default=None)
    values.append(near[0]*length(ray)/radius if near else 1.)
    skip.append(bool(near and near[1]<1e-4))
  faces.append({'face':face[0],'radialExpected':values,'barycentricSkip':skip,'covered':sum(v<1 for v in values),'clear':sum(v==1 for v in values)})
 draw_triangles=[tri if dot(cross(sub(tri[1],tri[0]),sub(tri[2],tri[0])),tri[0])>=0 else [tri[0],tri[2],tri[1]] for tri in triangles]
 return {'name':name,'size':size,'radius':radius,'triangles':triangles,'drawTriangles':draw_triangles,'faces':faces}

def directions():
 out=[]
 for axis in range(3):
  for s in [-1,1]:
   q=[0,0,0];q[axis]=s;out.append({'name':f'axis-{axis}-{s}','family':'axis','direction':q})
 for zero in range(3):
  active=[i for i in range(3) if i!=zero]
  for signs in itertools.product([-1,1],repeat=2):
   for side in [-1,0,1]:
    q=[0,0,0]
    for i,s in zip(active,signs):q[i]=s
    q[active[0]]*=1+side/4096
    out.append({'name':f'edge-{zero}-{signs}-{side}','family':'edge','side':side,'direction':q})
 for signs in itertools.product([-1,1],repeat=3):
  for dominant in [-1,0,1,2]:
   q=list(signs)
   if dominant>=0:q[dominant]*=1+1/4096
   out.append({'name':f'corner-{signs}-{dominant}','family':'corner','dominant':dominant,'direction':q})
 assert len(out)==74
 return out

def gap_cases():
 out=[]
 for row in directions():
  q=row['direction'];center=mul(q,16);axis=min(range(3),key=lambda i:abs(q[i]));reference=[0,0,0];reference[axis]=1
  # Dyadic vectors make shared self plane exact at central point before casting.
  u=mul(cross(q,reference),2);v=mul(cross(q,u),2)
  vertices=[quant(add(center,add(mul(u,a),mul(v,b)))) for a,b in [(-1,-1),(1,-1),(1,1),(-1,1)]]
  triangles=[[vertices[0],vertices[1],vertices[2]],[vertices[0],vertices[2],vertices[3]]]
  unit=mul(q,1/length(q))
  # Caster fixed; receiver moves outward (positive) / towardlight (negative).
  for gap in [0,.1,-.1]:
   receiver=quant(add(center,mul(unit,gap)))
   intersections=[h for tri in triangles if (h:=hit(receiver,mul(receiver,-1),tri)) is not None]
   interior=[t for t,margin in intersections if 1e-12<t<1]
   blocked=bool(interior)
   assert blocked==(gap>0),(row,gap,intersections)
   expected_depth=length(center)/100
   # Independent plane normal check supplements triangle test for signed gap.
   n=cross(sub(vertices[1],vertices[0]),sub(vertices[2],vertices[0]));plane_gap=dot(n,sub(receiver,vertices[0]))/length(n)
   out.append({**row,'name':row['name']+f'-gap{gap}','light':[0,0,0],'radius':100,'receiver':receiver,'casterTriangles':triangles,'gapWorld':gap,'expectedBlocked':blocked,'segmentT':interior,'signedPlaneDistance':plane_gap,'centralCasterRadialDepth':expected_depth})
 assert len(out)==222
 return out

def depth_vectors():
 panels=[]
 for i,face in enumerate(FACES):
  z=2+i*.5;quad=[[-.75,-.75,z],[.75,-.75,z],[.75,.75,z],[-.75,.75,z]]
  panels.extend([[world(quad[j],face) for j in tri] for tri in [(0,1,2),(0,2,3)]])
 depth=[depth_case('six-independent-radial-panels-32',panels),depth_case('six-independent-radial-panels-64',panels,64)]
 for name,tri in [('unequal-w',[[-.8,-.8,1],[1.2,-1,2],[0,1.8,3]]),('one-behind',[[-.8,-.7,1],[.8,-.7,1],[0,.3,-.5]]),('two-behind-nondegenerate',[[0,0,1],[-1,-1,-1],[1,-1,-1]]),('on-lamp-plane',[[-.8,-.7,1],[.8,-.7,1],[0,.4,0]]),('apex-plane-clear',[[-1,-1,1],[1,1,1],[0,0,-1]]),('sphere-crossing',[[-30,-30,9],[30,-30,9],[0,30,9]]),('sphere-outside',[[-30,-30,20],[30,-30,20],[0,30,20]])]:
  depth.append(depth_case(name,[tri]))
 # Six-lobe panel dataset must prove all six positive and clear footprint.
 assert all(0<f['covered']<32*32 for f in depth[0]['faces'])
 for name in ['unequal-w','one-behind','two-behind-nondegenerate','on-lamp-plane']:
  row=next(x for x in depth if x['name']==name);target=next(f for f in row['faces'] if f['face']=='pz');assert target['covered']>0 and target['clear']>0
 assert all(f['covered']==0 for f in next(x for x in depth if x['name']=='apex-plane-clear')['faces'])
 reverse=json.loads(json.dumps(depth[0]));reverse['name']='six-backfaces-clear'
 reverse['drawTriangles']=[[t[0],t[2],t[1]] for t in reverse['drawTriangles']]
 for face in reverse['faces']:
  face.update(radialExpected=[1.]*(32*32),barycentricSkip=[False]*(32*32),covered=0,clear=32*32)
 depth.append(reverse)
 far=[[mul(p,1.5) for p in tri] for tri in panels]
 depth.append(depth_case('six-overlap-near-first',panels+far))
 depth.append(depth_case('six-overlap-far-first',far+panels))
 assert [f['radialExpected'] for f in depth[-1]['faces']]==[f['radialExpected'] for f in depth[-2]['faces']]
 return depth

DEPTH_MAIN=r'''
@main enum PointDepthProbe {
 static func main() throws {
  let rows=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [[String:Any]]
  let d=MTLCreateSystemDefaultDevice()!,queue=d.makeCommandQueue()!,pipeline=SceneStaticModelPipeline(device:d,colorPixelFormat:.rgba16Float)!
  let td=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba32Float,width:1,height:1,mipmapped:false);td.storageMode = .shared;td.usage = .shaderRead
  let albedo=d.makeTexture(descriptor:td)!;var white:[Float]=[1,1,1,1];albedo.replace(region:MTLRegionMake2D(0,0,1,1),mipmapLevel:0,withBytes:&white,bytesPerRow:16)
  let material=SceneStaticModelMaterial(color:SIMD3(repeating:1),opacity:1,receivesLighting:true,textureAlphaIsOpacity:true,textureAlphaIsTintMask:false,emissiveColor:.zero,emissiveBrightness:1,brightness:1,usesHDRBrightness:false,viewTint:nil)
  var result:[[String:Any]]=[]
  for row in rows {
   let size=row["size"] as! Int,radius=Float(row["radius"] as! Double)
   let light=SceneLightSnapshot.Point(layerID:10,castsShadow:true,position:.zero,color:SIMD3(repeating:1),intensity:1,radius:radius)
   let projection=ScenePointShadowProjection(light:light)
   let triangles=row["drawTriangles"] as! [[[Double]]]
   let vertices=triangles.flatMap{$0}.map{p in SceneMdlStaticModel.Vertex(position:SIMD3(Float(p[0]),Float(p[1]),Float(p[2])),normal:SIMD3(0,0,-1),tangent:SIMD4(1,0,0,1),uv:SIMD2(0.5,0.5))}
   let mesh=pipeline.makeMesh(vertices:vertices,indices:Array(0..<UInt32(vertices.count)))!
   let targetDesc=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:3*size,height:2*size,mipmapped:false);targetDesc.storageMode = .private;targetDesc.usage = [.renderTarget,.shaderRead]
   let target=d.makeTexture(descriptor:targetDesc)!,cb=queue.makeCommandBuffer()!
   let rp=MTLRenderPassDescriptor();rp.depthAttachment.texture=target;rp.depthAttachment.loadAction = .clear;rp.depthAttachment.storeAction = .store;rp.depthAttachment.clearDepth=1
   let e=cb.makeRenderCommandEncoder(descriptor:rp)!
   var encoded:[Bool]=[]
   for face in 0..<6 {
    // Explicit actual tile extent; product face transform is only the tested input.
    let viewport=MTLViewport(originX:Double(face%3*size),originY:Double(face/3*size),width:Double(size),height:Double(size),znear:0,zfar:1)
    e.setViewport(viewport);e.setScissorRect(MTLScissorRect(x:face%3*size,y:face/3*size,width:size,height:size))
    encoded.append(pipeline.drawShadow(mesh:mesh,texture:albedo,textureFrame:.identity,sampling:.linearClamp,modelMatrix:matrix_identity_float4x4,projection:.point(projection),face:face,viewport:viewport,layerAlpha:1,material:material,encoder:e))
   }
   e.endEncoding()
   let rowBytes=((3*size*4+255)/256)*256,buf=d.makeBuffer(length:rowBytes*2*size,options:.storageModeShared)!,b=cb.makeBlitCommandEncoder()!
   b.copy(from:target,sourceSlice:0,sourceLevel:0,sourceOrigin:.init(x:0,y:0,z:0),sourceSize:.init(width:3*size,height:2*size,depth:1),to:buf,destinationOffset:0,destinationBytesPerRow:rowBytes,destinationBytesPerImage:rowBytes*2*size);b.endEncoding();cb.commit();cb.waitUntilCompleted()
   let faces=(0..<6).map{face in (0..<size).flatMap{y in Array(UnsafeBufferPointer(start:buf.contents().advanced(by:(face/3*size+y)*rowBytes+face%3*size*4).bindMemory(to:Float.self,capacity:size),count:size))}}
   result.append(["name":row["name"]!,"completed":cb.status == .completed && cb.error == nil,"encoded":encoded,"faces":faces])
  }
  print(String(data:try JSONSerialization.data(withJSONObject:["rows":result]),encoding:.utf8)!)
 }
}
'''

class ScenePointModelShadowDepthTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.vectors=depth_vectors()
  cls.report=run_point(spot.sources(),'import Foundation\nimport Metal\nimport simd\n'+model.LIGHTING_STUB+DEPTH_MAIN,label='point-depth',metal_sources=[model.METAL_SOURCE],input_value=cls.vectors)

 def test_actual_six_tile_radial_depth_and_cross_lamp_geometry(self):
  for expected,actual in zip(self.vectors,self.report['rows']):
   with self.subTest(case=expected['name']):
    self.assertTrue(actual['completed']);self.assertEqual(actual['encoded'],[True]*6)
    for f,written in zip(expected['faces'],actual['faces']):
     errors=[]
     for i,(want,got,skip) in enumerate(zip(f['radialExpected'],written,f['barycentricSkip'])):
      if skip:continue
      if (want==1 and got!=1) or not math.isfinite(got) or abs(want-got)>DEPTH_TOLERANCE:errors.append((i,want,got))
     self.assertEqual(errors,[],(expected['name'],f['face'],errors[:8]))

 def test_actual_nearest_radial_order_and_backface_control(self):
  rows={r['name']:r for r in self.report['rows']}
  self.assertEqual(rows['six-overlap-near-first']['faces'],rows['six-overlap-far-first']['faces'])
  self.assertTrue(all(z==1 for face in rows['six-backfaces-clear']['faces'] for z in face))

 def test_every_face_has_independent_content_at_two_actual_extents(self):
  for expected,actual in zip(self.vectors[:2],self.report['rows'][:2]):
   for face,values in zip(expected['faces'],actual['faces']):
    self.assertGreater(face['covered'],0);self.assertGreater(face['clear'],0)
    self.assertGreater(sum(v<1 for v in values),0);self.assertGreater(sum(v==1 for v in values),0)

def radiance_vectors():
 rows=gap_cases()
 # Smaller independently specified separation, frozen before any actual output.
 seeds=[r for r in rows if r['gapWorld']==0 and (r['family']=='axis' or r['name'] in ['edge-2-(1, 1)-0-gap0','corner-(1, 1, 1)--1-gap0'])]
 for seed in seeds:
  center=seed['receiver'];unit=mul(center,1/length(center))
  for gap in [.001,-.001]:
   r=json.loads(json.dumps(seed));r['name']=seed['name']+f'-small{gap}';r['receiver']=quant(add(center,mul(unit,gap)));r['gapWorld']=gap
   hits=[h for tri in r['casterTriangles'] if (h:=hit(r['receiver'],mul(r['receiver'],-1),tri)) is not None and 1e-12<h[0]<1]
   r['expectedBlocked']=bool(hits);assert r['expectedBlocked']==(gap>0);rows.append(r)
 for r in rows:
  normal=mul(r['direction'],-1/length(r['direction']));axis=min(range(3),key=lambda i:abs(normal[i]));reference=[0,0,0];reference[axis]=1
  right=cross(reference,normal);right=mul(right,1/length(right));up=cross(normal,right)
  r.update(receiverNormal=normal,cameraRight=right,cameraUp=up,faceSize=1024)
  assert abs(dot(normal,mul(r['receiver'],-1))/length(r['receiver'])-1)<1e-6
 return rows

RADIANCE_MAIN=r'''
@main enum PointRadianceProbe {
 static func main() throws {
  let inputs=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [[String:Any]]
  let device=MTLCreateSystemDefaultDevice()!,queue=device.makeCommandQueue()!,pipeline=SceneStaticModelPipeline(device:device,colorPixelFormat:.rgba16Float)!
  func vector(_ a:[Double])->SIMD3<Float>{SIMD3(Float(a[0]),Float(a[1]),Float(a[2]))}
  func texture(_ a:Float)->MTLTexture {let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba32Float,width:1,height:1,mipmapped:false);d.storageMode = .shared;d.usage = .shaderRead;let t=device.makeTexture(descriptor:d)!;var v:[Float]=[1,1,1,a];t.replace(region:MTLRegionMake2D(0,0,1,1),mipmapLevel:0,withBytes:&v,bytesPerRow:16);return t}
  func material(_ emission:Float)->SceneStaticModelMaterial {.init(color:SIMD3(repeating:1),opacity:1,receivesLighting:true,textureAlphaIsOpacity:false,textureAlphaIsTintMask:false,emissiveColor:SIMD3(repeating:emission),emissiveBrightness:1,brightness:1,usesHDRBrightness:false,viewTint:nil)}
  func mesh(_ tris:[[[Double]]],normal:SIMD3<Float>)->SceneStaticModelMesh {let v=tris.flatMap{$0}.map{p in SceneMdlStaticModel.Vertex(position:vector(p),normal:normal,tangent:SIMD4(1,0,0,1),uv:SIMD2(0.5,0.5))};return pipeline.makeMesh(vertices:v,indices:Array(0..<UInt32(v.count)))!}
  let albedo=texture(1),emissionMask=texture(0.25)
  var rows:[[String:Any]]=[]
  for input in inputs {
   let p=vector(input["receiver"] as! [Double]),n=vector(input["receiverNormal"] as! [Double]),right=vector(input["cameraRight"] as! [Double]),up=vector(input["cameraUp"] as! [Double]),size=input["faceSize"] as! Int
   let caster=mesh(input["casterTriangles"] as! [[[Double]]],normal:n)
   func point(_ x:Float,_ y:Float)->[Double]{let v=p+right*x+up*y;return [Double(v.x),Double(v.y),Double(v.z)]}
   let receiver=mesh([[point(-2,-2),point(2,2),point(2,-2)],[point(-2,-2),point(-2,2),point(2,2)]],normal:n)
   func light(_ intensity:Float)->SceneLightSnapshot.Point{.init(layerID:10,castsShadow:true,position:.zero,color:SIMD3(repeating:1),intensity:intensity,radius:100)}
   let projection=ScenePointShadowProjection(light:light(2)),cb=queue.makeCommandBuffer()!
   let td=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:size*3,height:size*2,mipmapped:false);td.storageMode = .private;td.usage = [.renderTarget,.shaderRead]
   let map=device.makeTexture(descriptor:td)!,pass=MTLRenderPassDescriptor();pass.depthAttachment.texture=map;pass.depthAttachment.loadAction = .clear;pass.depthAttachment.storeAction = .store;pass.depthAttachment.clearDepth=1
   let e=cb.makeRenderCommandEncoder(descriptor:pass)!
   for face in 0..<6 {
    let vp=MTLViewport(originX:Double(face%3*size),originY:Double(face/3*size),width:Double(size),height:Double(size),znear:0,zfar:1)
    e.setViewport(vp);e.setScissorRect(MTLScissorRect(x:face%3*size,y:face/3*size,width:size,height:size))
    precondition(pipeline.drawShadow(mesh:caster,texture:albedo,textureFrame:.identity,sampling:.linearClamp,modelMatrix:matrix_identity_float4x4,projection:.point(projection),face:face,viewport:vp,layerAlpha:1,material:material(0),encoder:e))
   }
   e.endEncoding()
   let record=SceneStaticModelShadow(texture:map,frameEpoch:7,generation:1,lightLayerID:10,projection:.point(projection),commandBuffer:cb)
   let view=simd_float4x4(rows:[SIMD4(right*0.25,-simd_dot(right,p)*0.25),SIMD4(up*(-0.25),simd_dot(up,p)*0.25),SIMD4(n*(-0.001),0.5+simd_dot(n,p)*0.001),SIMD4(0,0,0,1)])
   var buffers:[MTLBuffer]=[]
   for mode in 0..<9 {
    let color=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba16Float,width:1,height:1,mipmapped:false);color.storageMode = .private;color.usage = .renderTarget
    let output=device.makeTexture(descriptor:color)!,zdesc=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:1,height:1,mipmapped:false);zdesc.storageMode = .private;zdesc.usage = .renderTarget
    let z=device.makeTexture(descriptor:zdesc)!,rp=MTLRenderPassDescriptor();rp.colorAttachments[0].texture=output;rp.colorAttachments[0].loadAction = .clear;rp.colorAttachments[0].storeAction = .store;rp.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,0);rp.depthAttachment.texture=z;rp.depthAttachment.loadAction = .clear;rp.depthAttachment.storeAction = .dontCare;rp.depthAttachment.clearDepth=0
    let enc=cb.makeRenderCommandEncoder(descriptor:rp)!
    let lighting=SceneLightSnapshot(ambient:SIMD3(repeating:mode==4 ? 0:0.08),ambientNormalYSpaceSign:1,directional:[.init(layerID:11,directionTowardLight:n,color:SIMD3(0.5,0.7,1),intensity:mode==5 ? 0:0.2)],point:[light(mode==0 || (4...6).contains(mode) ? 0:2)],spot:[],overflowCount:0)
    let wrong=SceneStaticModelShadow(texture:map,frameEpoch:7,generation:1,lightLayerID:999,projection:.point(projection),commandBuffer:cb)
    precondition(pipeline.draw(mesh:receiver,texture:albedo,colorTextureIsPremultiplied:false,emissiveMask:emissionMask,emissiveMaskTextureFrame:.identity,emissiveMaskSampling:.linearClamp,modelMatrix:matrix_identity_float4x4,viewProjection:view,cameraPosition:p+n*10,textureFrame:.identity,sampling:.linearClamp,layerAlpha:0.75,material:material(mode==6 ? 0:0.8),lighting:lighting,writesDepth:true,shadows:mode==2 || mode==3 || mode>=7 ? [mode==7 ? wrong:record]:[],frameEpoch:mode==3 ? 8:7,commandBuffer:mode==8 ? queue.makeCommandBuffer()!:cb,encoder:enc))
    enc.endEncoding();let b=device.makeBuffer(length:256,options:.storageModeShared)!,blit=cb.makeBlitCommandEncoder()!;blit.copy(from:output,sourceSlice:0,sourceLevel:0,sourceOrigin:.init(x:0,y:0,z:0),sourceSize:.init(width:1,height:1,depth:1),to:b,destinationOffset:0,destinationBytesPerRow:256,destinationBytesPerImage:256);blit.endEncoding();buffers.append(b)
   }
   cb.commit();cb.waitUntilCompleted()
   let pixels=buffers.map{b in let p=b.contents().bindMemory(to:UInt16.self,capacity:4);return (0..<4).map{Float(Float16(bitPattern:p[$0]))}}
   rows.append(["name":input["name"]!,"completed":cb.status == .completed && cb.error == nil,"pixels":pixels])
  }
  print(String(data:try JSONSerialization.data(withJSONObject:["rows":rows]),encoding:.utf8)!)
 }
}
'''

class ScenePointModelShadowRadianceTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.vectors=radiance_vectors()
  cls.report=run_point(spot.sources(),'import Foundation\nimport Metal\nimport simd\n'+model.LIGHTING_STUB+RADIANCE_MAIN,label='point-radiance',metal_sources=[model.METAL_SOURCE],input_value=cls.vectors)

 def test_all_axes_edges_corners_self_positive_and_negative_gaps(self):
  for vector,row in zip(self.vectors,self.report['rows']):
   with self.subTest(case=vector['name']):
    self.assertTrue(row['completed']);a,full,actual,stale,_,_,_,wrong,other=row['pixels']
    for c in range(3):
     self.assertGreater(full[c]-a[c],.02)
     wanted=a[c] if vector['expectedBlocked'] else full[c]
     tolerance=2*max(2**-24,2**(math.floor(math.log2(abs(wanted)))-10)) if wanted else 2**-23
     self.assertLessEqual(abs(actual[c]-wanted),tolerance)
    self.assertEqual([p[3] for p in row['pixels']],[.75]*9)
    self.assertEqual(stale,full);self.assertEqual(wrong,full);self.assertEqual(other,full)
    if not vector['expectedBlocked']:self.assertEqual(actual,full)

 def test_other_direct_ambient_and_emission_remain_independent(self):
  for row in self.report['rows']:
   a=row['pixels'][0]
   for mode in [4,5,6]:
    with self.subTest(case=row['name'],removed=mode):
     self.assertTrue(all(a[c]>row['pixels'][mode][c] for c in range(3)))

def face_for_ray(ray):
 axis=max(range(3),key=lambda i:abs(ray[i]))
 return axis*2+(1 if ray[axis]<0 else 0)


def geometric_tap_rays(point,size):
 """Independent declared discrete policy, never a product matrix or texture."""
 selected=face_for_ray(point);_,right,up,forward,_=FACES[selected]
 denominator=dot(point,forward)
 u=(dot(point,right)/denominator+1)*.5;v=(1-dot(point,up)/denominator)*.5
 base_x=math.floor(u*size);base_y=math.floor(v*size);out=[]
 def basis_ray(x,y,face):
  _,r,up,f,_=face
  return [x*r[i]+y*up[i]+f[i] for i in range(3)]
 for dy in [-1,0,1]:
  for dx in [-1,0,1]:
   extended=basis_ray(2*(base_x+dx+.5)/size-1,1-2*(base_y+dy+.5)/size,FACES[selected])
   actual_face=face_for_ray(extended);_,r,up,f,_=FACES[actual_face];den=dot(extended,f)
   tu=(dot(extended,r)/den+1)*.5;tv=(1-dot(extended,up)/den)*.5
   tx=min(size-1,max(0,math.floor(tu*size)));ty=min(size-1,max(0,math.floor(tv*size)))
   final=basis_ray(2*(tx+.5)/size-1,1-2*(ty+.5)/size,FACES[actual_face])
   out.append({'face':actual_face,'texel':[tx,ty],'ray':final})
 return out


def seam_vectors():
 rows=[]
 for seed in gap_cases():
  if seed['gapWorld']!=.1 or seed['family']=='axis':continue
  center=mul(seed['direction'],16);q=seed['direction'];axis=min(range(3),key=lambda i:abs(q[i]));reference=[0,0,0];reference[axis]=1
  r=cross(q,reference);r=mul(r,1/length(r));u=cross(mul(q,1/length(q)),r)
  for side in [-1,1]:
   # A small independently chosen offset keeps actual sample centers off the
   # silhouette. This cuts the geometric PCF footprint, not the atlas layout.
   xs=[.007,8] if side==1 else [-8,-.007]
   vertices=[quant(add(center,add(mul(r,x),mul(u,y)))) for x,y in [(xs[0],-8),(xs[1],-8),(xs[1],8),(xs[0],8)]]
   triangles=[[vertices[0],vertices[1],vertices[2]],[vertices[0],vertices[2],vertices[3]]]
   row=json.loads(json.dumps(seed));row.update(name=seed['name']+f'-partial{side}',casterTriangles=triangles)
   n=mul(q,-1/length(q));camera_right=r;camera_up=cross(n,camera_right)
   row.update(receiverNormal=n,cameraRight=camera_right,cameraUp=camera_up,faceSize=1024)
   # Keep exact-axis ties observable: receiver at world origin makes the
   # 1-pixel camera center exact, rather than subtracting a rounded view offset.
   original_receiver=row['receiver'];light=quant(mul(original_receiver,-1))
   triangles=[[quant(sub(p,original_receiver)) for p in tri] for tri in triangles]
   row.update(receiver=[0,0,0],light_position=light,casterTriangles=triangles)
   relative=sub(row['receiver'],light);taps=geometric_tap_rays(relative,1024)
   for tap in taps:
    ray=tap['ray'];den=dot(n,ray);reference_t=dot(n,relative)/den
    hits=[h for tri in triangles if (h:=hit(light,ray,tri)) is not None and 0<h[0]<reference_t]
    tap['visibility']=0 if hits else 1;tap['receiverRadial']=reference_t*length(ray)
    tap['casterHitT']=[h[0] for h in hits]
    # Exclude no sample based on the eventual output. Positive hits must be
    # independently away from all authored triangle edges.
    assert all(h[1]>1e-5 for h in hits),(row['name'],tap,hits)
   row['independentTaps']=taps;row['expectedVisibility']=sum(t['visibility'] for t in taps)/9
   assert 0<row['expectedVisibility']<1,(row['name'],row['expectedVisibility'])
   rows.append(row)
 # Actual hard cutout texture values around the half storage boundary, same
 # seam geometry, with expected direct restored when coverage does not pass.
 for alpha in [0,.499755859375,.5,.50048828125,1]:
  row=json.loads(json.dumps(rows[0]));row['name']=f'seam-coverage-{alpha}';row['coverageAlpha']=alpha;row['usesCoverage']=True
  if alpha<=.5:row['expectedVisibility']=1
  rows.append(row)
 row=json.loads(json.dumps(rows[-5]));row.update(name='seam-tintmask-alpha0',coverageAlpha=0,usesCoverage=False,tintMask=True,expectedVisibility=rows[0]['expectedVisibility']);rows.append(row)
 row=json.loads(json.dumps(rows[0]));row.update(name='seam-unlit-caster',casterLit=False);rows.append(row)
 return rows


def seam_main():
 code=RADIANCE_MAIN.replace('position:.zero,color:SIMD3(repeating:1)', 'position:vector(input["light_position"] as? [Double] ?? [0,0,0]),color:SIMD3(repeating:1)')
 code=code.replace('let map=device.makeTexture(descriptor:td)!,pass=MTLRenderPassDescriptor();','let casterTexture=texture(Float(input["coverageAlpha"] as? Double ?? 1))\n   let casterMaterial=SceneStaticModelMaterial(color:SIMD3(repeating:1),opacity:1,receivesLighting:input["casterLit"] as? Bool ?? true,textureAlphaIsOpacity:input["usesCoverage"] as? Bool ?? false,textureAlphaIsTintMask:input["tintMask"] as? Bool ?? false,emissiveColor:.zero,emissiveBrightness:0,brightness:1,usesHDRBrightness:false,viewTint:nil)\n   let map=device.makeTexture(descriptor:td)!,pass=MTLRenderPassDescriptor();')
 code=code.replace('drawShadow(mesh:caster,texture:albedo,','drawShadow(mesh:caster,texture:casterTexture,').replace('layerAlpha:1,material:material(0),encoder:e)','layerAlpha:1,material:casterMaterial,encoder:e)')
 return code


class ScenePointModelShadowSeamTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.vectors=seam_vectors()
  cls.report=run_point(spot.sources(),'import Foundation\nimport Metal\nimport simd\n'+model.LIGHTING_STUB+seam_main(),label='point-seams',metal_sources=[model.METAL_SOURCE],input_value=cls.vectors)

 def test_independent_nine_ray_cross_face_fraction_and_coverage(self):
  for vector,row in zip(self.vectors,self.report['rows']):
   with self.subTest(case=vector['name']):
    self.assertTrue(row['completed']);a,full,actual,stale,_,_,_,wrong,other=row['pixels'];visibility=vector['expectedVisibility']
    for c in range(3):
     self.assertGreater(full[c]-a[c],.02)
     wanted=a[c]+visibility*(full[c]-a[c])
     tolerance=2*max(2**-24,2**(math.floor(math.log2(abs(wanted)))-10)) if wanted else 2**-23
     self.assertLessEqual(abs(actual[c]-wanted),tolerance)
    self.assertEqual([p[3] for p in row['pixels']],[.75]*9)
    self.assertEqual(stale,full);self.assertEqual(wrong,full);self.assertEqual(other,full)
    if visibility==1:self.assertEqual(actual,full)


POINT_FRAME_LIGHTS=r'''
  func spotLayer(_ id:Int,_ outer:Float)->SceneRenderDescriptor.Layer {
   let definition=SceneSpotLightDefinition.parse(["light":"lspot","color":"1 1 1","intensity":0,
     "radius":100,"innercone":Double(outer),"outercone":Double(outer),"castshadow":true])!
   return .init(id:id,spotLight:definition,contentKind:"light")
  }
  func pointLayer(_ id:Int)->SceneRenderDescriptor.Layer {
   let definition=ScenePointLightDefinition.parse(["light":"lpoint","color":"1 1 1","intensity":0,"radius":100,"castshadow":true])!
   return .init(id:id,pointLight:definition,contentKind:"light")
  }
  let directionalLayer=SceneRenderDescriptor.Layer(id:7,directionalLight:.init(colorRGB:[1,1,1],intensity:0,shadowCastIntent:.enabled),contentKind:"light")
  let lightLayers:[SceneRenderDescriptor.Layer]
  if mode=="four-points" || mode=="flight" {lightLayers=[pointLayer(8),pointLayer(9),pointLayer(10),pointLayer(11)]}
  else if mode=="gap" {lightLayers=[directionalLayer,spotLayer(8,90),spotLayer(9,Float.leastNonzeroMagnitude),pointLayer(10)]}
  else {lightLayers=[directionalLayer,spotLayer(8,90),pointLayer(9),pointLayer(10)]}
  var lightWorld=matrix_identity_float4x4;lightWorld.columns.3=SIMD4(32,32,40,1)
  let lightDescriptor=SceneRenderDescriptor(lighting:.init(ambientColorRGB:[0.5,0.5,0.5],skylightColorRGB:nil),layers:lightLayers,renderOrderLayerIDs:lightLayers.map(\.id))
  let lighting=SceneLightSnapshot.make(descriptor:lightDescriptor,worldFramesByLayerID:Dictionary(uniqueKeysWithValues:lightLayers.map{($0.id,lightWorld)}))
  precondition(lighting.shadowLights.count==4)
'''

def point_frame_harness():
    s=spot.frame_owner_main().replace(spot.FRAME_LIGHT_INPUTS,POINT_FRAME_LIGHTS)
    s=s.replace('"four-spots"','"four-points"').replace('"quota2","gap"','"quota2","quota3","logical","gap"')
    # Use the actual automatic pool budget (no RF15 budget increase). Quota
    # rows restrict real global native headroom, never alter that limit.
    s=s.replace(',residentByteBudget:40*1024*1024',',residentByteBudget: mode=="logical" ? 32*1024*1024 : nil')
    s=s.replace('  if mode.hasPrefix("quota") {\n   let maps=',r'''
  let atlasDescriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:3072,height:2048,mipmapped:false)
  atlasDescriptor.storageMode = .private;atlasDescriptor.usage=[.renderTarget,.shaderRead]
  let atlasBytes=device.heapTextureSizeAndAlign(descriptor:atlasDescriptor).size
  if mode.hasPrefix("quota") {
   let maps=''')
    s=s.replace('let capacity=3*depthBytes+maps*shadowBytes','let capacity=3*depthBytes+(maps<3 ? maps*shadowBytes : 2*shadowBytes+atlasBytes)')
    s=s.replace('slot:3,width:1024,height:1024','slot:3,width:3072,height:2048').replace('slot:2,width:1024,height:1024','slot:2,width:3072,height:2048')
    # Actual typed record dimensions ensure the published point is a six-face
    # atlas, while original directional/spot remain their single-face targets.
    s=s.replace('  let shadowBytesPrepared=pool.residentByteCost','  let atlasExtents=state.shadows.map{[$0.texture.width,$0.texture.height]}\n  let shadowBytesPrepared=pool.residentByteCost')
    s=s.replace('return ["mapIDs":mapIDs,','return ["atlasExtents":atlasExtents,"nativeAtlasBytes":atlasBytes,"mapIDs":mapIDs,')
    return spot.f.pool_fixture.HARNESS.split('@main',1)[0]+spot.f.SHELL+spot.f.UNUSED_ORDERED_SUPPORT+s

def assert_point_frame_rows(test,rows):
    cases={r['mode']:r for r in rows}
    expected={'original':[],'full':[7,8,9,10],'four-points':[8,9,10,11],
              'quota0':[],'quota1':[7],'quota2':[7,8],'quota3':[7,8,9],'logical':[7,8,9],'gap':[7,8,10],'flight':[8,9,10,11]}
    costs={'original':0,'full':56,'four-points':96,'quota0':0,'quota1':4,'quota2':8,'quota3':32,'logical':32,'gap':32,'flight':96}
    for mode,r in cases.items():
        test.assertTrue(r['completed']);test.assertEqual(r['mapIDs'],expected[mode]);test.assertTrue(r['mapUnique'])
        test.assertEqual(r['pixels'],cases['original']['pixels'])
        test.assertEqual(r['mandatoryCalls'],0 if mode=='original' else 1)
        test.assertEqual(r['after'],3);test.assertEqual(r['particleDraws'],1)
        for k in ['model1','model2','model3']:test.assertTrue(r[k],(mode,k))
        if mode!='original':
            test.assertEqual(r['before'],3)
            for k in ['sharedIdentity','isolatedIdentity','particleIdentity','allocationsStable','noRetry']:test.assertTrue(r[k],(mode,k))
        test.assertEqual(r['shadowBytesPrepared'],costs[mode]*1024*1024)
        extent=[[3072,2048] if mode in ('four-points','flight') or i>=9 else [1024,1024] for i in expected[mode]]
        test.assertEqual(r['atlasExtents'],extent)
        test.assertGreaterEqual(r['nativeAtlasBytes'],24*1024*1024)
    g=cases['gap']['gap'];test.assertTrue(g['laterUsesSlot3'] and g['slot2WasDistinct']);test.assertEqual(g['extraSlotBytes'],24*1024*1024)
    r=cases['flight']['flight']
    for k in ['pending','separateMaps','separateDepth','cancelledDepthReusable','cancelledNotSubmitted','completedDepthReusable','recoveryCurrentCB','recoveryDraw','recoveryDepthOnce','recoveryCompleted']:test.assertTrue(r[k],k)
    test.assertEqual((r['nextCount'],r['nextMandatory'],r['nextDepth']),(4,1,1))
    test.assertEqual(r['retainedAfterReset'],96*1024*1024);test.assertEqual(r['retainedAfterCancel'],96*1024*1024)
    test.assertEqual(r['residentAfterCompletion'],0)
    test.assertEqual(r['recoveryMapIDs'],[8,9,10,11]);test.assertEqual(r['recoveryMandatory'],1)
    test.assertEqual(r['recoveryResidentAfterReset'],0)


class ScenePointModelShadowFrameOwnerTests(unittest.TestCase):
 def test_actual_priority_quota_six_face_publication_and_pending_lifecycle(self):
  report=run_point(spot.f.SOURCES,point_frame_harness(),label='point-frame-owner',metal_sources=[model.METAL_SOURCE])
  assert_point_frame_rows(self,report['rows'])


def partial_point_harness(alpha):
    s=spot.partial_frame_harness(alpha)
    # First actual face is +X: place the authored light so the finite first
    # XY mesh has real footprint there before the later material rejects.
    s=s.replace('SIMD4(32,32,40,1)','SIMD4(-40,32,20,1)')
    s=s.replace('SceneSpotLightDefinition.parse(["light":"lspot"','ScenePointLightDefinition.parse(["light":"lpoint"')
    s=s.replace('spotLight:spotDefinition','pointLight:spotDefinition')
    s=s.replace(',"innercone":90,"outercone":90','')
    s=s.replace(',residentByteBudget:8*1024*1024','')
    s=s.replace('slot:0,width:1024,height:1024','slot:0,width:3072,height:2048')
    s=s.replace('1024*1024','3072*2048').replace('width:1024,height:1024','width:3072,height:2048').replace('destinationBytesPerRow:1024*4','destinationBytesPerRow:3072*4')
    return s

def assert_partial_point_report(test,report):
    r=report['rows'][0]
    test.assertFalse(r['published']);test.assertEqual(r['pinCount'],1)
    for k in ['pending','completed','finiteDepth','model1','preparedFirstFinite']:test.assertTrue(r[k],k)
    for k in ['model2','preparedSecondFinite']:test.assertFalse(r[k],k)
    test.assertGreater(r['coveredDepthPixels'],0)
    test.assertEqual(r['retainedAfterReset'],24*1024*1024)
    test.assertEqual(r['residentAfterCompletion'],0)



class ScenePointModelShadowPartialFailureTests(unittest.TestCase):
    def test_actual_authored_overflow_partial_map_retains_pin_until_completion(self):
        import tempfile
        from script.tests import test_scene_alpha_display_builder_fixture as builder
        from script.tests.test_scene_directional_shadow_integration import fixture_entries
        parent=Path(os.environ.get('MWX_POINT_SHADOW_EVIDENCE','/private/tmp/mwx-rf15'))
        parent.mkdir(parents=True,exist_ok=True)
        root=Path(tempfile.mkdtemp(prefix='point-overflow-input-',dir=parent))
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
        producer=run_point(builder.SWIFT_SOURCES,builder.HARNESS_SOURCE.split('@main',1)[0]+main,
                          label='point-overflow-producer',input_value=str(root))
        self.assertTrue(producer['doubleFinite']);self.assertFalse(producer['floatFinite'])
        # Real CPU builder -> typed descriptor value -> prepared material boundary.
        # The GPU resource builder itself is outside this harness, not duplicated.
        report=run_point(spot.f.SOURCES,partial_point_harness(producer['descriptorAlpha']),label='point-partial-map',
                        metal_sources=[model.METAL_SOURCE],input_value=producer)
        assert_partial_point_report(self,report)


from script.tests import test_scene_alpha_display_builder_fixture as builder
POINT_AUTHORED_SOURCES=list(builder.SWIFT_SOURCES)
for relative in ['Rendering/Lighting/SceneLightSnapshot.swift','Systems/Properties/SceneDynamicLayerValues.swift','Rendering/Geometry/SceneLayerDynamicWorldFrameResolver.swift']:
    path=shared.SCENE/relative
    if path not in POINT_AUTHORED_SOURCES:POINT_AUTHORED_SOURCES.append(path)
POINT_AUTHORED_MAIN=r'''
@main enum PointAuthoredSnapshotProbe {
 static func main() throws {
  let root=URL(fileURLWithPath:try JSONDecoder().decode(String.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))))
  func build(_ name:String)throws->SceneRuntimeModel {try SceneRuntimeModelBuilder().build(rootURL:root.appendingPathComponent(name))}
  func frames(_ descriptor:SceneRenderDescriptor)->[Int:simd_float4x4] {
   SceneLayerWorldFrameResolver.compute(descriptor:descriptor,byID:Dictionary(uniqueKeysWithValues:descriptor.layers.map{($0.id,$0)}))
  }
  var checks:[String:Bool]=[:]
  let parser=try build("parser")
  let values=(0..<10).map { index -> String in
   let value=parser.renderDescriptor.layers.first{$0.id==100+index}!.pointLight!.castsShadow
   return value.map{$0 ? "true":"false"} ?? "nil"
  }
  checks["strict-authored-cast"] = values == ["nil","true","false","nil","nil","nil","nil","true","false","nil"]
  let alias=parser.renderDescriptor.layers.first{$0.id==109}!.pointLight!
  checks["point-alias"] = alias.kind == "point"
  let old=try JSONDecoder().decode(ScenePointLightDefinition.self,from:Data("{\"kind\":\"lpoint\",\"radius\":100,\"intensity\":1}".utf8))
  checks["old-codable-omission"] = old.castsShadow == nil
  let mixed=try build("mixed").renderDescriptor
  let admitted=SceneLightSnapshot.make(descriptor:mixed,worldFramesByLayerID:frames(mixed))
  checks["author-order-shared-four"] = admitted.point.compactMap(\.layerID)==[10,12] && admitted.spot.compactMap(\.layerID)==[11] && admitted.directional.compactMap(\.layerID)==[13] && admitted.overflowCount==1
  checks["original-dir-spot-before-point-priority"] = admitted.shadowLights.compactMap(\.layerID)==[13,11,10,12]
  let descriptor=try build("current").renderDescriptor
  let byID=Dictionary(uniqueKeysWithValues:descriptor.layers.map{($0.id,$0)})
  let staticFrames=frames(descriptor)
  let first=SceneLightSnapshot.make(descriptor:descriptor,worldFramesByLayerID:staticFrames)
  checks["parent-world-first"] = first.point.first!.position == SIMD3<Float>(11,74,33)
  let intensity=SceneDynamicTarget.layer(layerID:20,field:.intensity)
  let origin=SceneDynamicTarget.layer(layerID:90,field:.origin)
  let current=SceneDynamicSnapshotResolver().resolve(frameIndex:2,generation:1,definitions:[
   .init(target:intensity,valueType:.scalar,authoredValue:.scalar(2)),
   .init(target:origin,valueType:.vector3,authoredValue:.vector3(10,20,30))],userValues:[:],sceneScriptValues:[intensity:.scalar(3.5),origin:.vector3(20,30,40)]).snapshot
  let currentFrames=SceneLayerDynamicWorldFrameResolver.resolve(descriptor:descriptor,byID:byID,snapshot:current,staticFrames:staticFrames)
  let second=SceneLightSnapshot.make(descriptor:descriptor,worldFramesByLayerID:currentFrames,dynamicLayerColors:[20:SIMD3(0.2,0.4,0.6)],dynamicSnapshot:current)
  checks["current-parent-world"] = second.point.first!.position == SIMD3<Float>(21,64,43)
  checks["current-light-values"] = second.point.first!.intensity==3.5 && second.point.first!.radius==73 && second.point.first!.color==SIMD3<Float>(0.2,0.4,0.6)
  checks["cast-current-identity"] = second.point.compactMap(\.layerID)==[20,21] && second.point.map(\.castsShadow)==[true,false] && second.shadowLights.compactMap(\.layerID)==[20]
  checks["previous-immutable"] = first.point.first!.position==SIMD3<Float>(11,74,33) && first.point.first!.intensity==2
  let restored=SceneLightSnapshot.make(descriptor:descriptor,worldFramesByLayerID:staticFrames)
  checks["next-frame-authored-restored"] = restored.point.first!.position==first.point.first!.position && restored.point.first!.intensity==2
  let hidden=SceneLightSnapshot.make(descriptor:descriptor,worldFramesByLayerID:currentFrames,visibleLayerIDs:[21])
  checks["current-visibility"] = hidden.point.compactMap(\.layerID)==[21] && hidden.shadowLights.isEmpty
  let report:[String:Any]=["checks":checks,"castValues":values,"authoredOrder":mixed.renderOrderLayerIDs,"shadowOrder":admitted.shadowLights.compactMap(\.layerID),"firstPosition":[first.point[0].position.x,first.point[0].position.y,first.point[0].position.z],"currentPosition":[second.point[0].position.x,second.point[0].position.y,second.point[0].position.z]]
  print(String(decoding:try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),as:UTF8.self))
 }
}
'''
def point_authored_harness():return 'import simd\n'+builder.HARNESS_SOURCE.split('@main',1)[0]+POINT_AUTHORED_MAIN

def prepare_point_authored_inputs(root):
    def light(id,kind='lpoint',**kwargs):return {'id':id,'light':kind,'color':'1 1 1','intensity':2,'radius':73,'origin':'0 0 0','castshadow':True,**kwargs}
    sentinel=object();values=[sentinel,True,False,1,0,'true',None,{'value':True},{'value':False},{'value':1}]
    parser=[]
    for index,value in enumerate(values):
        entry=light(100+index,'point' if index==9 else 'lpoint');entry.pop('castshadow')
        if value is not sentinel:entry['castshadow']=value
        parser.append(entry)
    scenes={'parser':parser,
        'mixed':[light(10),light(11,'lspot',innercone=30,outercone=60),light(12),light(13,'ldirectional'),light(14)],
        'current':[{'id':90,'image':'models/util/solidlayer.json','size':'1 1','origin':'10 20 30'},light(20,parent=90,origin='1 2 3'),light(21,castshadow=False)]}
    for name,objects in scenes.items():
        target=root/name;target.mkdir(parents=True,exist_ok=True)
        (target/'project.json').write_text(json.dumps({'type':'scene','file':'scene.json'}))
        (target/'scene.json').write_text(json.dumps({'version':3,'general':{'orthogonalprojection':{'width':160,'height':96},'lightconfig':{'directional':1,'point':1,'spot':1}},'objects':objects}))
    return root

def assert_point_authored_report(test,report):
    for name,value in report['checks'].items():test.assertTrue(value,name)


class ScenePointModelShadowAuthoredTests(unittest.TestCase):
 def test_strict_authoring_shared_admission_and_current_parent_world(self):
  parent=Path(os.environ.get('MWX_POINT_SHADOW_EVIDENCE','/private/tmp/mwx-rf15'));parent.mkdir(parents=True,exist_ok=True)
  root=Path(tempfile.mkdtemp(prefix='point-authored-input-',dir=parent))
  prepare_point_authored_inputs(root)
  identity={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in root.rglob('*.json')}
  (root/'input-identity.json').write_text(json.dumps(identity,indent=2))
  report=run_point(POINT_AUTHORED_SOURCES,point_authored_harness(),label='point-authored',input_value=str(root))
  assert_point_authored_report(self,report)
  self.assertTrue(all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==v for p,v in identity.items()))


class ScenePointModelShadowOptionalPipelineTests(unittest.TestCase):
 def test_missing_depth_entries_preserve_other_lights_and_original_color(self):
  # Point and spot intentionally share the perspective vertex entry.
  variants=[('point','sceneStaticModelPointShadowFragment',[7,8],[]),
            ('spot','sceneStaticModelSpotShadowFragment',[7,9,10],[8,9,10,11]),
            ('directional','sceneStaticModelShadowFragment',[8,9,10],[8,9,10,11]),
            ('shared-perspective-vertex','sceneStaticModelSpotShadowVertex',[7],[])]
  for name,entry,expected,four in variants:
   with self.subTest(missing=name):
    parent=Path(os.environ.get('MWX_POINT_SHADOW_EVIDENCE','/private/tmp/mwx-rf15'));parent.mkdir(parents=True,exist_ok=True)
    root=Path(tempfile.mkdtemp(prefix='point-missing-function-',dir=parent))
    # The library omits an entry, without changing any executed algorithm.
    source=root/'StaticModel.metal'
    source.write_text(model.METAL_SOURCE.read_text().replace(entry+'(', 'testUnavailableShadowEntry('))
    harness=point_frame_harness().replace('["original","full","four-points","quota0","quota1","quota2","quota3","logical","gap","flight"]','["original","full","four-points"]')
    report=run_point(spot.f.SOURCES,harness,label='point-optional-pso-'+name,metal_sources=[source],input_value={'missingEntry':entry,'expectedMixedIDs':expected,'expectedFourPointIDs':four})
    rows={r['mode']:r for r in report['rows']}
    self.assertEqual(set(rows),{'original','full','four-points'})
    self.assertEqual(rows['full']['mapIDs'],expected);self.assertEqual(rows['four-points']['mapIDs'],four)
    for r in rows.values():
     self.assertTrue(r['completed']);self.assertEqual(r['pixels'],rows['original']['pixels'])
     for k in ['model1','model2','model3']:self.assertTrue(r[k])


def transformed_vectors():
 rows=[];center=[16,0,8];normal=mul([.5,0,1],1/length([.5,0,1]));right=[0,1,0];up=cross(mul(normal,-1),right)
 vertices=[add(center,add(mul([2,0,-1],x),mul([0,2,0],y))) for x,y in [(-2,-2),(2,-2),(2,2),(-2,2)]]
 scale=[2,.5,4];local=[[p[i]/scale[i] for i in range(3)] for p in vertices]
 triangles=[[local[0],local[1],local[2]],[local[0],local[2],local[3]]]
 for translation in [[0,0,0],[1024,-512,256]]:
  world_triangles=[[quant(add([p[i]*scale[i] for i in range(3)],translation)) for p in tri] for tri in triangles]
  for gap in [0,.1,-.1]:
   receiver=quant(add(translation,add(center,mul(normal,gap))))
   hits=[h for tri in world_triangles if (h:=hit(receiver,sub(translation,receiver),tri)) is not None and 1e-12<h[0]<1]
   assert bool(hits)==(gap>0)
   rows.append({'name':f'tilted-nonuniform-{translation}-gap{gap}','light_position':translation,'receiver':receiver,'casterTriangles':triangles,'worldCasterTriangles':world_triangles,'modelScale':scale,'modelTranslation':translation,'expectedBlocked':bool(hits),'segmentT':[h[0] for h in hits],'receiverNormal':mul(normal,-1),'cameraRight':right,'cameraUp':up,'faceSize':1024})
 return rows


def transformed_main():
 code=seam_main().replace('let caster=mesh(input["casterTriangles"] as! [[[Double]]],normal:n)','let caster=mesh(input["casterTriangles"] as! [[[Double]]],normal:n)\n   let scale=vector(input["modelScale"] as! [Double]),translation=vector(input["modelTranslation"] as! [Double])\n   let casterWorld=simd_float4x4(columns:(SIMD4(scale.x,0,0,0),SIMD4(0,scale.y,0,0),SIMD4(0,0,scale.z,0),SIMD4(translation,1)))')
 return code.replace('sampling:.linearClamp,modelMatrix:matrix_identity_float4x4,projection:', 'sampling:.linearClamp,modelMatrix:casterWorld,projection:')

class ScenePointModelShadowTransformTests(unittest.TestCase):
 def test_tilted_translated_nonuniform_geometry_self_and_signed_gap(self):
  vectors=transformed_vectors()
  report=run_point(spot.sources(),'import Foundation\nimport Metal\nimport simd\n'+model.LIGHTING_STUB+transformed_main(),label='point-transform',metal_sources=[model.METAL_SOURCE],input_value=vectors)
  for vector,row in zip(vectors,report['rows']):
   with self.subTest(case=vector['name']):
    self.assertTrue(row['completed']);a,full,actual,stale,_,_,_,wrong,other=row['pixels']
    for c in range(3):
     self.assertGreater(full[c]-a[c],.02)
     wanted=a[c] if vector['expectedBlocked'] else full[c]
     tolerance=2*max(2**-24,2**(math.floor(math.log2(abs(wanted)))-10)) if wanted else 2**-23
     self.assertLessEqual(abs(actual[c]-wanted),tolerance)
    self.assertEqual([p[3] for p in row['pixels']],[.75]*9)
    self.assertEqual(stale,full);self.assertEqual(wrong,full);self.assertEqual(other,full)
    if not vector['expectedBlocked']:self.assertEqual(actual,full)
