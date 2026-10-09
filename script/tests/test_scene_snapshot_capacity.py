#!/usr/bin/env python3
"""Real snapshot capacity, original capture and Metal retention boundaries."""
import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest
from script.tests.test_scene_directional_shadow import run_swift

REPO=Path(__file__).resolve().parents[2]
SCENE=REPO/'MyWallpaperX/Core/SteamWorkshopScene'
SOURCES=[SCENE/p for p in [
 'Resources/Textures/SceneResourceBudget.swift','Diagnostics/ScenePerformanceCounterHub.swift',
 'Diagnostics/SceneGPUCensus.swift','Rendering/Composition/SceneFramebufferSnapshot.swift',
 'Rendering/Composition/SceneMainPassEncoder.swift']]
HARNESS=r'''
import Foundation
import Metal
final class SceneGraphRenderTargetResidencyPin {func release() {fatalError("unused peripheral pin")}}
@main enum SnapshotProbe {
 static func texture(_ d:MTLDevice,_ n:Int,_ format:MTLPixelFormat = .bgra8Unorm)->MTLTexture {
  let desc=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:format,width:n,height:n,mipmapped:false)
  desc.storageMode = .shared;desc.usage=[.renderTarget,.shaderRead]
  return d.makeTexture(descriptor:desc)!
 }
 static func physical(_ d:MTLDevice,_ n:Int,_ f:MTLPixelFormat = .bgra8Unorm)->Int {
  let desc=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:f,width:n,height:n,mipmapped:false)
  desc.storageMode = .private;desc.usage = .shaderRead
  return d.heapTextureSizeAndAlign(descriptor:desc).size
 }
 static func clear(_ t:MTLTexture,_ cb:MTLCommandBuffer,_ c:MTLClearColor) {
  let p=MTLRenderPassDescriptor();p.colorAttachments[0].texture=t;p.colorAttachments[0].loadAction = .clear
  p.colorAttachments[0].storeAction = .store;p.colorAttachments[0].clearColor=c
  cb.makeRenderCommandEncoder(descriptor:p)!.endEncoding()
 }
 static func read(_ t:MTLTexture,_ cb:MTLCommandBuffer)->MTLBuffer {
  let b=t.device.makeBuffer(length:256,options:.storageModeShared)!
  let e=cb.makeBlitCommandEncoder()!;e.copy(from:t,sourceSlice:0,sourceLevel:0,sourceOrigin:.init(),sourceSize:.init(width:1,height:1,depth:1),to:b,destinationOffset:0,destinationBytesPerRow:256,destinationBytesPerImage:256);e.endEncoding();return b
 }
 static func rgb(_ b:MTLBuffer)->[Int] {let p=b.contents().assumingMemoryBound(to:UInt8.self);return [Int(p[2]),Int(p[1]),Int(p[0]),Int(p[3])]}
 static func half(_ b:MTLBuffer)->[Double] {let p=b.contents().assumingMemoryBound(to:UInt16.self);return (0..<4).map {Double(Float16(bitPattern:p[$0]))}}
 static func done(_ c:MTLCommandBuffer) {c.commit();c.waitUntilCompleted();precondition(c.status == .completed)}
 static func copies()->UInt64 {ScenePerformanceCounterHub.shared.snapshot()[.framebufferCaptures] ?? 0}
 static func main() throws {
  guard let d=MTLCreateSystemDefaultDevice(),let q=d.makeCommandQueue() else {print("{\"metalUnavailable\":true}");return}
  var r:[String:Any]=[:]
  r["contents"]=autoreleasepool {contents(d,q)};r["rollback"]=autoreleasepool {rollback(d,q)}
  let beforeLife=SceneResourceBudget.shared.snapshot.residentBytes
  var life=autoreleasepool {lifecycle(d,q)}
  for _ in 0..<200 where SceneResourceBudget.shared.snapshot.residentBytes != beforeLife {Thread.sleep(forTimeInterval:0.001)}
  life["finalReferencesReleased"]=SceneResourceBudget.shared.snapshot.residentBytes==beforeLife
  r["lifecycle"]=life;r["limits"]=autoreleasepool {limits(d,q)}
  print(String(decoding:try JSONSerialization.data(withJSONObject:r),as:UTF8.self))
 }
 static func contents(_ d:MTLDevice,_ q:MTLCommandQueue)->[[String:Any]] {
  return [MTLPixelFormat.bgra8Unorm,.rgba16Float].map { f in
   let s=SceneFramebufferSnapshot(device:d,label:"actual original snapshot")
   let t=texture(d,16,f),cb=q.makeCommandBuffer()!
   let pass=SceneMainPassEncoder(commandBuffer:cb,target:t,clearColor:MTLClearColorMake(1,0,0,1),clearEnabled:true)
   let encoder=pass.encoder()!,n=copies()
   let prepared=s.prepareCapacity(width:pass.targetExtent.width,height:pass.targetExtent.height,pixelFormat:pass.targetPixelFormat,then:{true})
   let noEncode=copies()==n && pass.encoder() === encoder
   pass.closeForOffscreen();clear(t,cb,MTLClearColorMake(0,0,2,0.25))
   let first=s.capture(target:t,commandBuffer:cb)!,a=read(first,cb)
   let bytes=SceneResourceBudget.shared.snapshot.residentBytes
   let same=s.prepareCapacity(width:16,height:16,pixelFormat:f,then:{true})
   let noNewAllocation=bytes==SceneResourceBudget.shared.snapshot.residentBytes
   clear(t,cb,MTLClearColorMake(0,0.5,0,0.75))
   let second=s.capture(target:t,commandBuffer:cb)!,b=read(second,cb)
   done(cb)
   return ["hdr":f == .rgba16Float,"prepared":prepared,"sameKey":same && first === second,
    "noEarlyEncode":noEncode,"noNewAllocation":noNewAllocation,"copies":copies()-n,"logical":s.residentByteCost,
    "first":f == .rgba16Float ? half(a):rgb(a).map(Double.init),"second":f == .rgba16Float ? half(b):rgb(b).map(Double.init)]
  }
 }
 static func rollback(_ d:MTLDevice,_ q:MTLCommandQueue)->[String:Any] {
  let a=SceneFramebufferSnapshot(device:d,label:"owner A"),b=SceneFramebufferSnapshot(device:d,label:"owner B")
  let oldA=texture(d,8),oldB=texture(d,8),next=texture(d,128),initCB=q.makeCommandBuffer()!
  clear(oldA,initCB,MTLClearColorMake(1,0,0,1));clear(oldB,initCB,MTLClearColorMake(0,0,1,1))
  let ta=a.capture(target:oldA,commandBuffer:initCB)!,tb=b.capture(target:oldB,commandBuffer:initCB)!;done(initCB)
  let resident=SceneResourceBudget.shared.snapshot.residentBytes
  var held=SceneResourceBudget.shared.maximumBytes-resident-physical(d,128)
  precondition(SceneResourceBudget.shared.reserve(held,kind:.gpu))
  defer {if held>0 {SceneResourceBudget.shared.release(held,kind:.gpu)}}
  let budgetBefore=SceneResourceBudget.shared.snapshot.residentBytes,rejections=SceneResourceBudget.shared.snapshot.rejectionCount
  let prepared=a.prepareCapacity(width:128,height:128,pixelFormat:.bgra8Unorm) {
   b.prepareCapacity(width:128,height:128,pixelFormat:.bgra8Unorm,then:{true})
  }
  let rolledBack = !prepared && a.residentByteCost==256 && b.residentByteCost==256
  let costRestored=SceneResourceBudget.shared.snapshot.residentBytes==budgetBefore
  let secondRejected=SceneResourceBudget.shared.snapshot.rejectionCount==rejections+1
  let cb=q.makeCommandBuffer()!;let aa=a.capture(target:oldA,commandBuffer:cb)!,bb=b.capture(target:oldB,commandBuffer:cb)!
  let ra=read(aa,cb),rb=read(bb,cb)
  clear(next,cb,MTLClearColorMake(0,1,0,1))
  let recovered=a.capture(target:next,commandBuffer:cb);let rr=recovered.map {read($0,cb)}
  done(cb)
  SceneResourceBudget.shared.release(held,kind:.gpu);held=0
  let beforeFalseA=a.residentByteCost,beforeFalseB=b.residentByteCost
  let allRollback = !a.prepareCapacity(width:64,height:64,pixelFormat:.rgba16Float) {
   b.prepareCapacity(width:64,height:64,pixelFormat:.rgba16Float,then:{false})
  } && a.residentByteCost==beforeFalseA && b.residentByteCost==beforeFalseB
  let retry=b.prepareCapacity(width:128,height:128,pixelFormat:.bgra8Unorm,then:{true})
  return ["rolledBack":rolledBack,"costRestored":costRestored,"physicalSecondRejected":secondRejected,
   "oldIdentity":aa === ta && bb === tb,"oldPixels":[rgb(ra),rgb(rb)],"fallbackRecovered":recovered != nil,
   "fallbackPixel":rr.map(rgb) ?? [],"continuationRollback":allRollback,"retry":retry]
 }
 static func lifecycle(_ d:MTLDevice,_ q:MTLCommandQueue)->[String:Any] {
  let baseline=SceneResourceBudget.shared.snapshot.residentBytes
  var s:SceneFramebufferSnapshot?=SceneFramebufferSnapshot(device:d,label:"queue retained snapshot")
  var a:MTLCommandBuffer?=q.makeCommandBuffer(),b:MTLCommandBuffer?=q.makeCommandBuffer(),c:MTLCommandBuffer?=q.makeCommandBuffer()
  let gate=d.makeSharedEvent()!,t=texture(d,8),resized=texture(d,32)
  a!.encodeWaitForEvent(gate,value:1);clear(t,a!,MTLClearColorMake(1,0,0,1))
  var external:MTLTexture?=s!.capture(target:t,commandBuffer:a!)
  weak var retired=external
  let oldID=ObjectIdentifier(external!),ra=read(external!,a!)
  a!.commit()
  clear(t,b!,MTLClearColorMake(0,1,0,1));let same=s!.capture(target:t,commandBuffer:b!)!
  let sameKey=ObjectIdentifier(same)==oldID,rb=read(same,b!);b!.commit()
  clear(resized,c!,MTLClearColorMake(0,0,1,1));var newer:MTLTexture?=s!.capture(target:resized,commandBuffer:c!)
  let newIdentity=ObjectIdentifier(newer!) != oldID,rc=read(newer!,c!);c!.commit()
  let blocked=a!.status != .completed && b!.status != .completed
  let retained=retired != nil && SceneResourceBudget.shared.snapshot.residentBytes>=baseline+physical(d,8)+physical(d,32)
  gate.signaledValue=1;c!.waitUntilCompleted();a!.waitUntilCompleted();b!.waitUntilCompleted()
  let complete=[a!,b!,c!].allSatisfy {$0.status == .completed}
  // A deliberate external reference proves completion alone cannot discharge cost.
  let referenceRetained=retired != nil && SceneResourceBudget.shared.snapshot.residentBytes>=baseline+physical(d,8)
  a=nil;b=nil;c=nil;s=nil;newer=nil
  external=nil
  return ["sameKeyBAllowed":sameKey,"resizedIdentity":newIdentity,"blocked":blocked,"retainedInFlight":retained,
   "completed":complete,"strongReferenceRetainsCost":referenceRetained,"pixels":[rgb(ra),rgb(rb),rgb(rc)],
   "note":"same local texture is retained until this function exits; final-reference release checked by caller scope"]
 }
 static func limits(_ d:MTLDevice,_ q:MTLCommandQueue)->[String:Any] {
  let tiny=SceneFramebufferSnapshot(device:d,byteBudget:255,label:"logical bound")
  var reached=false
  let rejected = !tiny.prepareCapacity(width:8,height:8,pixelFormat:.bgra8Unorm,then:{reached=true;return true})
  let s=SceneFramebufferSnapshot(device:d,label:"cancel capacity")
  let n=copies(),ok=s.prepareCapacity(width:8,height:8,pixelFormat:.bgra8Unorm,then:{true})
  let canceled=q.makeCommandBuffer()! // No encoding or commit: a capacity is not a captured image.
  withExtendedLifetime(canceled) {}
  let t=texture(d,8),next=q.makeCommandBuffer()!;clear(t,next,MTLClearColorMake(0.25,0.5,0.75,1))
  let got=s.capture(target:t,commandBuffer:next)!,out=read(got,next);done(next)
  return ["logicalRejected":rejected && !reached && tiny.residentByteCost==0,"preparedNoCapture":ok && copies()==n+1,
          "afterCanceledPrepare":rgb(out)]
 }
}
'''

class SceneSnapshotCapacityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        parent=Path(os.environ.get('MWX_SNAPSHOT_EVIDENCE','/private/tmp/mwx-rf12'));parent.mkdir(parents=True,exist_ok=True)
        cls.identity={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [Path(__file__),*SOURCES]}
        root=Path(tempfile.mkdtemp(prefix='snapshot-test-identity-',dir=parent));(root/'sources.json').write_text(json.dumps(cls.identity,indent=2))
        cls.result=run_swift(SOURCES,HARNESS,label='snapshot-capacity')
        assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in cls.identity.items()),'source identity drift'

    def test_capacity_is_not_content_and_each_consumer_gets_current_pixels(self):
        for row in self.result['contents']:
            for key in ['prepared','sameKey','noEarlyEncode','noNewAllocation']:self.assertTrue(row[key],row)
            self.assertEqual(row['copies'],2);self.assertEqual(row['logical'],16*16*(8 if row['hdr'] else 4))
            self.assertEqual(row['first'],[0,0,2,.25] if row['hdr'] else [0,0,255,64])
            self.assertEqual(row['second'],[0,.5,0,.75] if row['hdr'] else [0,128,0,191])

    def test_two_owners_rollback_real_second_allocation_failure_and_allow_lazy_recovery(self):
        row=self.result['rollback']
        for key in ['rolledBack','costRestored','physicalSecondRejected','oldIdentity','fallbackRecovered','continuationRollback','retry']:self.assertTrue(row[key],row)
        self.assertEqual(row['oldPixels'],[[255,0,0,255],[0,0,255,255]])
        self.assertEqual(row['fallbackPixel'],[0,255,0,255])

    def test_same_queue_blocked_submission_reuse_and_resize_preserve_each_read(self):
        row=self.result['lifecycle']
        for key in ['sameKeyBAllowed','resizedIdentity','blocked','retainedInFlight','completed','strongReferenceRetainsCost','finalReferencesReleased']:self.assertTrue(row[key],row)
        self.assertEqual(row['pixels'],[[255,0,0,255],[0,255,0,255],[0,0,255,255]])

    def test_logical_limit_and_canceled_prepare_do_not_publish_stale_content(self):
        row=self.result['limits'];self.assertTrue(row['logicalRejected']);self.assertTrue(row['preparedNoCapture'])
        self.assertEqual(row['afterCanceledPrepare'],[64,128,191,255])

# Compile the real renderer capacity owner and original consumers. Only external
# prepared inputs/provider/group plumbing are supplied by this fixture shell.
from script.tests import test_scene_directional_shadow_frame_owner as frame_fixture
FRAME_SOURCES=list(dict.fromkeys([*frame_fixture.SOURCES,
 SCENE/'Rendering/Composition/SceneLayerColorBlendPipeline.swift',
 SCENE/'Rendering/Metal/SceneMetalPipeline.swift',
 SCENE/'Rendering/Composition/SceneBlendModeShaderSource.swift']))
FRAME_SHELL=frame_fixture.SHELL.replace(
 'enum SceneLayerColorBlendRenderer {static func supports(_ mode:Int)->Bool {fatalError("unused snapshot-demand shell")}}','')
FRAME_SHELL=FRAME_SHELL.replace('let imageCompositor=SceneImageLayerCompositor()',
 'let imageCompositor:SceneImageLayerCompositor')
FRAME_SHELL=FRAME_SHELL.replace('self.device=device;staticModelResources=resources',
 'self.device=device;staticModelResources=resources;imageCompositor=SceneImageLayerCompositor(device:device)')
FRAME_SHELL=FRAME_SHELL.replace('->Bool {fatalError("unused snapshot-demand shell")}', '->Bool {false}')
FRAME_SHELL=FRAME_SHELL.replace('->FixtureImageSelection {fatalError("unused snapshot-demand shell")}', '->FixtureImageSelection {FixtureImageSelection(source:nil)}')
# The compositor shell delegates to the actual pre-existing pipeline instance;
# its full provider/graph resolution is covered by the real App utility test.
start=FRAME_SHELL.index('final class SceneImageLayerCompositor {')
end=FRAME_SHELL.index('\n}\n',start)+3
FRAME_SHELL=FRAME_SHELL[:start]+r'''
struct SceneGeometryProduct {
 typealias AuxiliaryRetainer=(@escaping ()->Void)->Void
 let prepare:((MTLCommandBuffer,SIMD2<Int>,simd_float4x4,AuxiliaryRetainer)->Void)?=nil
 typealias ColorBlendBinder=(MTLRenderCommandEncoder,MTLTexture,simd_float4x4)->Void
 let encode:(MTLRenderCommandEncoder,MTLTexture,MTLTexture?,simd_float4x4,SceneLayerFragmentUniforms,ColorBlendBinder?)->Bool
}
final class SceneImageLayerCompositor {
 let color:SceneLayerColorBlendPipeline
 init(device:MTLDevice) {color=SceneLayerColorBlendPipeline(device:device)!}
 func prepareSnapshotCapacity(width:Int,height:Int,pixelFormat:MTLPixelFormat,then remaining:()->Bool)->Bool {
  color.framebufferSnapshot.prepareCapacity(width:width,height:height,pixelFormat:pixelFormat,then:remaining)
 }
}
'''+FRAME_SHELL[end:]
FRAME_MAIN=r'''
@main enum CapacityFrameProbe {
 static func main() throws {
  let d=MTLCreateSystemDefaultDevice()!,q=d.makeCommandQueue()!
  var rows:[[String:Any]]=[]
  for mode in ["normal","optional-quota","utility-trigger","hidden-no-demand"] {rows.append(run(mode,d,q))}
  let buffer=SceneParticleMetalInstanceBuffer()
  let valid=SceneParticleGPUInstance(position:.zero,size:1,rotation:.zero,color:SIMD3(repeating:1),alpha:1)
  let invalid=SceneParticleGPUInstance(position:SIMD3(.infinity,0,0),size:1,rotation:.zero,color:SIMD3(repeating:1),alpha:1)
  precondition(buffer.update(device:d,instances:[valid]));let initial=buffer.currentDrawState() != nil
  let empty=buffer.update(device:d,instances:[]) && buffer.currentDrawState()==nil && buffer.count==0
  precondition(buffer.update(device:d,instances:[valid]));let bad=buffer.update(device:d,instances:[invalid]) && buffer.currentDrawState()==nil && buffer.count==0
  let peer=buffer.update(device:d,instances:[invalid,valid]) && buffer.currentDrawState() != nil && buffer.count==1
  print(String(decoding:try! JSONSerialization.data(withJSONObject:["rows":rows,"upload":["initial":initial,"emptyClears":empty,"invalidClears":bad,"validPeer":peer]]),as:UTF8.self))
 }
 static func run(_ mode:String,_ d:MTLDevice,_ q:MTLCommandQueue)->[String:Any] {
  let model=SceneStaticModelPipeline(device:d)!,particle=SceneParticleMetalPipeline(device:d)!
  func texture(_ n:Int,_ pixel:[UInt8]?=nil)->MTLTexture {
   let desc=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:pixel==nil ? .bgra8Unorm:.rgba8Unorm,width:n,height:n,mipmapped:false)
   desc.storageMode = .shared;desc.usage=[.renderTarget,.shaderRead];let t=d.makeTexture(descriptor:desc)!
   if var pixel {t.replace(region:MTLRegionMake2D(0,0,1,1),mipmapLevel:0,withBytes:&pixel,bytesPerRow:4)}
   return t
  }
  let target=texture(64),white=texture(1,[255,255,255,255]),green=texture(1,[0,255,0,255])
  let vertices=[SIMD3<Float>(4,4,0),SIMD3(20,4,0),SIMD3(20,20,0),SIMD3(4,20,0)].map {
   SceneMdlStaticModel.Vertex(position:$0,normal:SIMD3(0,0,1),tangent:SIMD4(1,0,0,1),uv:SIMD2(repeating:0.5))
  }
  let mesh=model.makeMesh(vertices:vertices,indices:[0,2,1,0,3,2])!
  let material=SceneStaticModelMaterial(color:SIMD3(1,0,0),opacity:1,receivesLighting:true,textureAlphaIsOpacity:true,textureAlphaIsTintMask:false,emissiveColor:.zero,emissiveBrightness:0,brightness:1,usesHDRBrightness:false,viewTint:nil)
  let entry=ScenePreparedStaticModelResources.Entry(materialPath:"self",dynamicMaterialPath:"",geometryIdentity:"quad",mesh:mesh,albedo:PreparedTexture(texture:white),material:material)
  let renderer=SceneMetalRenderer(device:d,resources:.init(pipeline:model,entries:[1:[entry]]))
  let utility=mode=="utility-trigger",hidden=mode=="hidden-no-demand"
  let layers=[SceneRenderDescriptor.Layer(id:1),.init(id:6,contentKind:"image",colorBlendMode:1),.init(id:42,contentKind:"particle"),.init(id:7,contentKind:"utility",colorBlendMode:1),.init(id:8,visible:false,contentKind:"trigger")]
  renderer.layersByID=Dictionary(uniqueKeysWithValues:layers.map{($0.id,$0)})
  if utility {renderer.utilityExecution = .init(plansByTriggerLayerID:[8:[.init(layerID:7,usesIsolatedGroupTarget:false)]])}
  let visible:Set<Int>=hidden || utility ? [1]:[1,6,42]
  let plans:[Int:SceneResolvedMaterialFrameTargetPlan]=utility ? [7:.init()]:[6:.init()]
  let dynamic=SceneDynamicSnapshot.empty(frameIndex:1,generation:1),context=SceneFrameContext(dynamicValues:dynamic)
  let instances=SceneParticleMetalInstanceBuffer();precondition(instances.update(device:d,instances:[.init(position:SIMD3(48,48,0),size:12,rotation:.zero,color:SIMD3(repeating:1),alpha:1)]))
  let binding=SceneParticleRefractionBinding(normalTexture:white,amount:0,overbright:1,colorEncoding:.rgba,normalUsesParticleFrames:false,normalUVScale:SIMD2(repeating:1),normalSampling:.directImageFallback,normalFormat:nil)
  let batch=SceneParticleDrawBatch(layerID:42,texture:white,colorUVScale:SIMD2(repeating:1),colorSampling:.directImageFallback,refraction:binding,renderState:.init(blendMode:.translucent,cullMode:.none,depthTestEnabled:false,depthWriteEnabled:false),instanceBuffer:instances,orientation:.screen,orientationAxis:nil,usesPerspective:false)
  let batches:[Int:[SceneParticleDrawBatch]]=hidden || utility ? [:]:[42:[batch]]
  let cb=q.makeCommandBuffer()!,pass=SceneMainPassEncoder(commandBuffer:cb,target:target,clearColor:MTLClearColorMake(0.5,0.25,0.75,1),clearEnabled:true)
  let camera=SceneParticleCameraFrame(camera:.init(eye:[0,0,0],center:[0,0,-1],up:[0,1,0],orthoWidth:64,orthoHeight:64,fovDegrees:nil,perspectiveOverrideFOVDegrees:nil,nearZ:0.01,farZ:1000),viewportSize:CGSize(width:64,height:64))
  let world=Dictionary(uniqueKeysWithValues:layers.map{($0.id,matrix_identity_float4x4)})
  let light=SceneLightSnapshot.Directional(layerID:9,castsShadow:true,directionTowardLight:SIMD3(0,0,1),color:SIMD3(repeating:1),intensity:0.5)
  let lighting=SceneLightSnapshot(ambient:SIMD3(repeating:0.5),skylight: .zero,directional:[light],point:[],spot:[],overflowCount:0)
  let pool=SceneOffscreenTexturePool(device:d,pixelFormat:.bgra8Unorm,residentByteBudget:8*1024*1024)
  let state=SceneMetalRenderer.StaticModelFrame();var leases:[SceneParticleDepthTargetLease]=[]
  var held=0
  if mode=="optional-quota" {
   let td=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:64,height:64,mipmapped:false);td.storageMode = .private;td.usage = .renderTarget
   let sd=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:64,height:64,mipmapped:false);sd.storageMode = .private;sd.usage = .shaderRead
   let mandatory=d.heapTextureSizeAndAlign(descriptor:td).size+2*d.heapTextureSizeAndAlign(descriptor:sd).size
   held=SceneResourceBudget.shared.maximumBytes-SceneResourceBudget.shared.snapshot.residentBytes-mandatory
   precondition(SceneResourceBudget.shared.reserve(held,kind:.gpu))
  }
  defer {if held>0 {SceneResourceBudget.shared.release(held,kind:.gpu)}}
  let pre=ScenePerformanceCounterHub.shared.snapshot()[.framebufferCaptures] ?? 0
  let candidates=renderer.shadowDrawCandidates(orderedLayers:layers,visible:visible,worldFrames:world,snapshot:dynamic,groups:nil)!
  var capacity=false
  renderer.prepareModelShadow(state:state,candidates:candidates,lights:[.directional(light)],orderedLayers:layers,visible:visible,batches:batches,particlePipeline:particle,mainPass:pass,groups:nil,pool:pool,commandBuffer:cb,leases:&leases,mandatoryCapacity:{
   capacity=renderer.prepareFramebufferSnapshotCapacity(orderedLayers:layers,visible:visible,framePlans:plans,imageTextures:.init(),frameContext:context,batches:batches,particlePipeline:particle,mainPass:pass,groups:nil,utilityExecution:renderer.utilityExecution)
   return capacity
  },recordsEvidence:false)
  let noCopy=(ScenePerformanceCounterHub.shared.snapshot()[.framebufferCaptures] ?? 0)==pre
  let colorBytes=renderer.imageCompositor.color.renderTargetResidentByteCost,particleBytes=particle.framebufferSnapshot.residentByteCost
  let published = !state.shadows.isEmpty
  let modelDraw=renderer.drawStaticModel(layer:layers[0],state:state,worldFrames:world,frameContext:context,cameraFrame:camera,lighting:lighting,pass:pass,commandBuffer:cb,leases:&leases)
  if !hidden {
   let bg=pass.withReadableTarget {t,c in renderer.imageCompositor.color.snapshot(target:t,commandBuffer:c)}!!
   let transform=SceneMatrix.translation(SIMD3(-0.5,-0.5,0))*SceneMatrix.scale(SIMD3(0.5,0.5,1))
   renderer.imageCompositor.color.draw(layerTexture:green,backgroundTexture:bg,blendMode:1,mvp:transform,encoder:pass.encoder()!)
  }
  var observed:[SceneParticlePerformanceObservation]?=[]
  if !hidden && !utility {_=renderer.renderParticleBatches([batch],pipeline:particle,model:matrix_identity_float4x4,cameraFrame:camera,viewportSize:SIMD2(64,64),mainPass:pass,commandBuffer:cb,performanceObservations:&observed)}
  precondition(pass.finishEnsuringClear());leases.forEach {$0.arm(on:cb)};state.arm(on:cb);cb.commit();cb.waitUntilCompleted();precondition(cb.status == .completed)
  var bytes=[UInt8](repeating:0,count:64*64*4);target.getBytes(&bytes,bytesPerRow:256,from:MTLRegionMake2D(0,0,64,64),mipmapLevel:0)
  func rgb(_ x:Int,_ y:Int)->[UInt8] {let i=(y*64+x)*4;return [bytes[i+2],bytes[i+1],bytes[i],bytes[i+3]]}
  return ["mode":mode,"capacity":capacity,"noEarlyCopy":noCopy,"colorBytes":colorBytes,"particleBytes":particleBytes,"modelDraw":modelDraw,
   "shadow":published,"refractionDraws":observed?.filter(\.isRefraction).count ?? 0,"copies":(ScenePerformanceCounterHub.shared.snapshot()[.framebufferCaptures] ?? 0)-pre,
   "pixels":[rgb(12,12),rgb(16,48),rgb(48,48),rgb(32,32)]]
 }
}
'''
FRAME_HARNESS=frame_fixture.pool_fixture.HARNESS.split('@main',1)[0]+FRAME_SHELL+frame_fixture.UNUSED_ORDERED_SUPPORT.replace('struct SceneImageLayerPipeline {}','')+FRAME_MAIN

class SceneSnapshotFrameOwnerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        paths=[Path(__file__),Path(frame_fixture.__file__),*FRAME_SOURCES,SCENE/'Rendering/Composition/SceneStaticModel.metal']
        identity={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
        parent=Path(os.environ.get('MWX_SNAPSHOT_EVIDENCE','/private/tmp/mwx-rf12'));parent.mkdir(parents=True,exist_ok=True)
        work=Path(tempfile.mkdtemp(prefix='snapshot-frame-identity-',dir=parent));(work/'sources.json').write_text(json.dumps(identity,indent=2))
        cls.result=run_swift(FRAME_SOURCES,FRAME_HARNESS,label='snapshot-frame-owner',
                            metal_sources=[SCENE/'Rendering/Composition/SceneStaticModel.metal'])
        assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in identity.items()),'source identity drift'
        cls.rows={row['mode']:row for row in cls.result['rows']}

    def test_real_frame_owner_prepares_both_consumers_before_optional_quota_failure(self):
        normal=self.rows['normal'];limited=self.rows['optional-quota']
        for row in [normal,limited]:
            for key in ['capacity','noEarlyCopy','modelDraw']:self.assertTrue(row[key],row)
            self.assertEqual(row['colorBytes'],64*64*4);self.assertEqual(row['particleBytes'],64*64*4)
            self.assertEqual(row['refractionDraws'],1);self.assertEqual(row['copies'],2)
        self.assertTrue(normal['shadow']);self.assertFalse(limited['shadow'])
        self.assertEqual(limited['pixels'],normal['pixels'])
        # Red albedo: ambient .5 * equatorial .5 + directional .5 * .30 = .4.
        self.assertEqual(normal['pixels'][0],[102,0,0,255]);self.assertEqual(normal['pixels'][1],[0,64,0,255])

    def test_admitted_utility_at_hidden_trigger_reserves_original_color_owner(self):
        row=self.rows['utility-trigger'];self.assertTrue(row['capacity']);self.assertTrue(row['shadow'])
        self.assertEqual(row['colorBytes'],64*64*4);self.assertEqual(row['particleBytes'],0)
        self.assertEqual(row['copies'],1);self.assertEqual(row['pixels'][1],[0,64,0,255])
        hidden=self.rows['hidden-no-demand'];self.assertTrue(hidden['shadow'])
        self.assertEqual((hidden['colorBytes'],hidden['particleBytes'],hidden['copies']),(0,0,0))

    def test_actual_upload_clears_stale_empty_invalid_and_preserves_valid_peer(self):
        self.assertEqual(self.result['upload'],{'initial':True,'emptyClears':True,'invalidClears':True,'validPeer':True})
