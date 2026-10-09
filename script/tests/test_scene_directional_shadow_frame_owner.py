#!/usr/bin/env python3
"""Real frame-owner/Metal mandatory-depth handoff; peripheral preparation is stubbed.

Compiles both production renderer extensions, pipelines, depth pool, offscreen pool
and main-pass encoder unchanged. The renderer shell supplies prepared inputs only.
No App/daemon, real corpus, named-provider readiness or main renderer admission claim.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from script.tests import test_scene_directional_shadow as shadow_fixture
from script.tests import test_scene_offscreen_texture_pool as pool_fixture
from script.tests import test_scene_particle_rendering as particle_fixture
from script.tests import test_scene_static_model_pipeline as model_fixture

REPO = Path(__file__).resolve().parents[2]
SCENE = REPO / 'MyWallpaperX/Core/SteamWorkshopScene'
SOURCES = list(dict.fromkeys([
    *pool_fixture.SWIFT_SOURCES,
    *(p for p in particle_fixture.SWIFT_SOURCES if p.parent.name != 'fixtures'),
    *(getattr(model_fixture, name) for name in [
        'MODEL_SOURCE', 'DIRECTIONAL_LIGHT_SOURCE', 'POINT_LIGHT_SOURCE',
        'SPOT_LIGHT_SOURCE', 'LIGHT_SOURCE', 'VISIBILITY_SOURCE', 'DYNAMIC_SNAPSHOT_SOURCE',
        'DYNAMIC_LAYER_VALUES_SOURCE', 'MATERIAL_SOURCE', 'PIPELINE_SOURCE', 'SHADOW_SOURCE']),
    SCENE/'Runtime/Frame/SceneStaticModelMaterialBindings.swift',
    SCENE/'Rendering/Frame/SceneMetalRenderer+StaticModels.swift',
    SCENE/'Rendering/Frame/SceneMetalRenderer+Particles.swift',
]))

SHELL = r'''
import CoreGraphics
import Foundation
import Metal
import simd

struct SceneLayerDisplayScriptOwnership {
 let visible: Bool; let alpha: Bool
 var isEmpty: Bool { !visible && !alpha }; var fields: [String] { [] }
}
struct SceneRenderDescriptor {
 struct LightingDescriptor {
  struct DistanceFog { let color:[Float]; let start:Float; let end:Float; let startDensity:Float; let endDensity:Float }
  struct LightClassesDescriptor { var directional:Bool = true; var point:Bool = true; var spot:Bool = true }
  let ambientColorRGB:[Float]?;let skylightColorRGB:[Float]?;var lightClasses:LightClassesDescriptor = .init();var distanceFog:DistanceFog? = nil
 }
 struct Layer {
  let id:Int;var visible:Bool? = true;var pointLight:ScenePointLightDefinition? = nil
  var spotLight:SceneSpotLightDefinition? = nil;var directionalLight:SceneDirectionalLightDefinition? = nil
  var parentID:Int? = nil;var displayScriptOwnership:SceneLayerDisplayScriptOwnership? = nil
  var utilityLayer:Bool? = false;var usesPerspective:Bool? = false
  var alpha:Double? = 1;var contentKind:String = "model"
  var modelShadowCastIntent:SceneShadowCastIntent? = nil;var colorBlendMode:Int? = nil
  var anglesXYZ:[Float]? = nil
 }
 struct CameraDescriptor {
  let eye:[Float];let center:[Float];let up:[Float];let orthoWidth:Float?;let orthoHeight:Float?
  let fovDegrees:Float?;let perspectiveOverrideFOVDegrees:Float?;let nearZ:Float;let farZ:Float
 }
 let lighting:LightingDescriptor?;let layers:[Layer];let renderOrderLayerIDs:[Int]
 var camera:CameraDescriptor = CameraDescriptor(eye:[0,0,0],center:[0,0,-1],up:[0,1,0],orthoWidth:64,orthoHeight:64,fovDegrees:nil,perspectiveOverrideFOVDegrees:nil,nearZ:0.01,farZ:1000)
}
struct SceneFrameContext { let dynamicValues:SceneDynamicSnapshot }
struct SceneParticlePerformanceObservation { let layerID:Int;let instanceCount:Int;let isRefraction:Bool }
struct SceneParticleDrawBatch {
 let layerID:Int;let texture:MTLTexture;let colorUVScale:SIMD2<Float>;let colorSampling:SceneParticleTextureSampling
 let refraction:SceneParticleRefractionBinding?;let renderState:SceneParticlePipelineRenderState
 let instanceBuffer:SceneParticleMetalInstanceBuffer;let orientation:SceneParticleOrientation
 let orientationAxis:SIMD3<Float>?;let usesPerspective:Bool;var sizeIsWorldSpace:Bool = false
}
struct PreparedTexture {
 let texture:MTLTexture;var uvTransform:SceneTextureUVTransform = .identity
 var sampling:SceneTextureSampling = .directImageFallback
}
struct ScenePreparedStaticModelResources {
 struct Entry {
  let materialPath:String;let dynamicMaterialPath:String;let geometryIdentity:String;let mesh:SceneStaticModelMesh
  let albedo:PreparedTexture?;var namedAlbedo:String? = nil;var emissiveMask:PreparedTexture? = nil
  let material:SceneStaticModelMaterial;var writesDepth:Bool = true
 }
 let pipeline:SceneStaticModelPipeline?;let entries:[Int:[Entry]]
 subscript(_ id:Int)->[Entry]? { entries[id] }
}
struct NamedAlbedo {
 let texture:MTLTexture;let textureFrame:SceneTextureUVTransform;let sampling:SceneTextureSampling
 let isPremultiplied:Bool
}
final class BindingObserver {
 var encoded:[Int:Bool] = [:]
 func staticModelNamedAlbedo(for id:Int, materialPath:String, expectedReference:String,
                            textureRegistry:TextureRegistry)->NamedAlbedo? { nil }
 func recordStaticModelBindingFailure(for id:Int) { encoded[id] = false }
 func recordStaticModelBindingIfRequired(for id:Int, encoded value:Bool, on cb:MTLCommandBuffer) { encoded[id] = value }
}
struct TextureRegistry { let frameEpoch:UInt64 = 1 }
struct SceneCompositionGroupFrameRuntime {
 func renderPass(forLayerID:Int)->SceneMainPassEncoder? { nil }
 func closeAllGroupEncoders() {}
 func sourceIsAvailable(forLayerID:Int)->Bool {false}
 func compositeTargetPass(forRootID:Int)->SceneMainPassEncoder? {nil}
}

struct SceneResolvedMaterialFrameTargetPlan {}
struct SceneBaseImageTextureSnapshot {}
struct FixtureImageSelection {let source:MTLTexture?}
struct SceneUtilityLayerRuntimePlan {let layerID:Int;let usesIsolatedGroupTarget:Bool}
// Prepared schedule input only. This probe compiles the real snapshot/depth
// consumers; composition planning and group pixels are covered by the App gate.
enum SceneUtilityLayerRuntimePlanner {
 struct Execution {
  let plansByTriggerLayerID:[Int:[SceneUtilityLayerRuntimePlan]]
  init(plansByTriggerLayerID:[Int:[SceneUtilityLayerRuntimePlan]]=[:]) {
   self.plansByTriggerLayerID=plansByTriggerLayerID
  }
 }
}
enum SceneLayerColorBlendRenderer {static func supports(_ mode:Int)->Bool {fatalError("unused snapshot-demand shell")}}
final class SceneImageLayerCompositor {
 func prepareSnapshotCapacity(width:Int,height:Int,pixelFormat:MTLPixelFormat,then remaining:()->Bool)->Bool {fatalError("unused snapshot-demand shell")}
}

final class SceneMetalRenderer {
 let device:MTLDevice;let staticModelResources:ScenePreparedStaticModelResources
 var utilityExecution=SceneUtilityLayerRuntimePlanner.Execution()
 var layersByID:[Int:SceneRenderDescriptor.Layer]=[:]
 let imageCompositor=SceneImageLayerCompositor()
 func baseMaterialReadyProviderUsesAuthoredLayerColor(for layer:SceneRenderDescriptor.Layer,dynamicValues:SceneDynamicSnapshot)->Bool {fatalError("unused snapshot-demand shell")}
 func baseMaterialTextureSelection(for layer:SceneRenderDescriptor.Layer,imageTextures:SceneBaseImageTextureSnapshot,readyProviderUsesAuthoredLayerColor:Bool)->FixtureImageSelection {fatalError("unused snapshot-demand shell")}
 let staticModelDepthTargetPool = SceneParticleDepthTargetPool()
 let dependencyRuntime = BindingObserver();let textureRegistry = TextureRegistry()
 init(device:MTLDevice, resources:ScenePreparedStaticModelResources) {
  self.device=device;staticModelResources=resources
 }
}
'''


# RF13's ordered preparation is outside this F6 probe. Keep its compile-only
# dependencies separate: the named-model test imports SHELL and supplies real
# owners for these calls. Any accidental use here must fail, not emulate them.
UNUSED_ORDERED_SUPPORT = r'''
struct SceneImageLayerPipeline {}
struct SceneLayerParallax { struct Configuration {} }
enum SceneGraphOutputPublicationResult {
 case published
 case unavailable(reasonCode:String)
 case invalid(reasonCode:String)
}
enum SceneLitCapturePayloadResolution {
 enum Miss { case profileMissing }
 case miss(Miss)
}
struct SceneEffectExecutionFrameTrace {
 enum Outcome { case failed(reasonCode:String) }
 func recordRouteOperation(layerID:Int,origin:String,operation:String,outcome:Outcome) {
  fatalError("unused RF13 ordered preparation shell")
 }
}
struct FixtureLightingProfile { let surfaceEnabled:Bool }
struct FixtureProviderBindings { let lightingProfileByLayerID:[Int:FixtureLightingProfile] }
struct FixtureGeometryProduct {}
extension BindingObserver {
 func requiresDemandedGraphOutputCapture(for id:Int)->Bool { fatalError("unused RF13 ordered preparation shell") }
 func requiresCapture(for id:Int,activeStaticModelConsumerLayerIDs:Set<Int>)->Bool { fatalError("unused RF13 ordered preparation shell") }
 func requiresGraphOutputCapture(for id:Int)->Bool { fatalError("unused RF13 ordered preparation shell") }
 func isStaticModelSourceProvider(_ id:Int)->Bool { fatalError("unused RF13 ordered preparation shell") }
}
extension SceneFrameContext {
 var cameraParallaxPosition:SIMD2<Float> { fatalError("unused RF13 ordered preparation shell") }
}
extension SceneBaseImageTextureSnapshot {
 func layerSourceRenderSize(for id:Int)->[Float]? { fatalError("unused RF13 ordered preparation shell") }
 var geometryProducts:[Int:FixtureGeometryProduct] { fatalError("unused RF13 ordered preparation shell") }
}
extension SceneMetalRenderer {
 var baseMaterialProviderBindings:FixtureProviderBindings { fatalError("unused RF13 ordered preparation shell") }
 static func effectExecutionOrigin(for contentKind:String)->String { fatalError("unused RF13 ordered preparation shell") }
 func captureRawDependencyProvider(layer:SceneRenderDescriptor.Layer,source:MTLTexture?,
  imageTextures:SceneBaseImageTextureSnapshot,imagePipeline:SceneImageLayerPipeline,
  frameContext:SceneFrameContext,worldFrames:[Int:simd_float4x4],cameraFrame:SceneParticleCameraFrame,
  parallax:SceneLayerParallax.Configuration,viewportSize:CGSize,mainPass:SceneMainPassEncoder,
  preparesCapacityOnly:Bool)->SceneGraphOutputPublicationResult? {
  fatalError("unused RF13 ordered preparation shell")
 }
 func imageModelMatrix(for layer:SceneRenderDescriptor.Layer,worldFramesByLayerID:[Int:simd_float4x4],
  renderSizeOverride:[Float]?,parallaxMouseNormalized:SIMD2<Float>,configuration:SceneLayerParallax.Configuration,
  visibleHalfExtents:SIMD2<Float>,usesPerspective:Bool)->simd_float4x4 {
  fatalError("unused RF13 ordered preparation shell")
 }
 func makeLitCapturePayload(profile:FixtureLightingProfile,snapshot:SceneLightSnapshot,
  dynamicValues:SceneDynamicSnapshot,layerModelMatrix:simd_float4x4,layerWorldFrame:simd_float4x4,
  usesPerspective:Bool,cameraFrame:SceneParticleCameraFrame,sceneViewProjection:simd_float4x4,
  environmentSource:((MTLCommandBuffer)->SceneFrameTextureResource?)?,
  geometryProduct:FixtureGeometryProduct?)->SceneLitCapturePayloadResolution {
  fatalError("unused RF13 ordered preparation shell")
 }
 func compositionScratchDimensions(for layer:SceneRenderDescriptor.Layer,pool:SceneOffscreenTexturePool,
  imageTextures:SceneBaseImageTextureSnapshot,frameContext:SceneFrameContext,
  worldFrames:[Int:simd_float4x4],cameraFrame:SceneParticleCameraFrame,
  parallax:SceneLayerParallax.Configuration,lightingResolution:SceneLitCapturePayloadResolution)->[(width:Int,height:Int)]? {
  fatalError("unused RF13 ordered preparation shell")
 }
}
'''

MAIN = r'''
@main enum FrameOwnerProbe {
 static func main() throws {
  guard let device=MTLCreateSystemDefaultDevice(),let queue=device.makeCommandQueue() else {
   print("{\"metalUnavailable\":true}");return
  }
  var results:[[String:Any]]=[]
  for mode in ["original", "prepared", "optional-quota", "mandatory-quota"] {
   results.append(try run(mode,device,queue))
  }
  print(String(decoding:try JSONSerialization.data(withJSONObject:["rows":results]),as:UTF8.self))
 }
 static func run(_ mode:String,_ device:MTLDevice,_ queue:MTLCommandQueue)throws->[String:Any] {
  let pipeline=SceneStaticModelPipeline(device:device)!
  let particles=SceneParticleMetalPipeline(device:device)!
  let td=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:64,height:64,mipmapped:false)
  td.usage=[.renderTarget,.shaderRead];td.storageMode = .shared
  let output=device.makeTexture(descriptor:td)!
  let whiteDesc=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:1,height:1,mipmapped:false)
  whiteDesc.usage = .shaderRead;whiteDesc.storageMode = .shared
  let white=device.makeTexture(descriptor:whiteDesc)!
  var pixel:[UInt8]=[255,255,255,255]
  white.replace(region:MTLRegionMake2D(0,0,1,1),mipmapLevel:0,withBytes:&pixel,bytesPerRow:4)
  func quad(_ x:Float,_ y:Float,_ width:Float)->SceneStaticModelMesh {
   let vertices=[SIMD3(x,y,0),SIMD3(x+width,y,0),SIMD3(x+width,y+width,0),SIMD3(x,y+width,0)].map {
    SceneMdlStaticModel.Vertex(position:$0,normal:SIMD3(0,0,1),tangent:SIMD4(1,0,0,1),uv:SIMD2(0.5,0.5))
   }
   return pipeline.makeMesh(vertices:vertices,indices:[0,2,1,0,3,2])!
  }
  let meshA=quad(4,4,20),meshB=quad(36,4,20)
  func material(_ color:SIMD3<Float>)->SceneStaticModelMaterial {
   .init(color:color,opacity:1,receivesLighting:true,textureAlphaIsOpacity:true,textureAlphaIsTintMask:false,
         emissiveColor:.zero,emissiveBrightness:0,brightness:1,usesHDRBrightness:false,viewTint:nil)
  }
  func entry(_ mesh:SceneStaticModelMesh,_ identity:String,_ color:SIMD3<Float>)->ScenePreparedStaticModelResources.Entry {
   .init(materialPath:"self-authored",dynamicMaterialPath:"",geometryIdentity:identity,mesh:mesh,
         albedo:PreparedTexture(texture:white),material:material(color))
  }
  let renderer=SceneMetalRenderer(device:device,resources:.init(pipeline:pipeline,entries:[
   1:[entry(meshA,"one-geometry",SIMD3(1,0,0))],
   2:[entry(meshA,"one-geometry",SIMD3(0,1,0))],
   3:[entry(meshB,"other-geometry",SIMD3(0,0,1))],
   5:[entry(meshA,"singular",SIMD3(1,1,0))]
  ]))
  let layers=[SceneRenderDescriptor.Layer(id:1),.init(id:2),.init(id:3),.init(id:4,contentKind:"particle"),.init(id:5)]
  let world=Dictionary(uniqueKeysWithValues:layers.map { ($0.id,$0.id==5 ? SceneMatrix.scale(SIMD3(1,1,0)) : matrix_identity_float4x4) })
  let dynamic=SceneDynamicSnapshot.empty(frameIndex:1,generation:1)
  let camera=SceneParticleCameraFrame(camera:.init(eye:[0,0,0],center:[0,0,-1],up:[0,1,0],orthoWidth:64,
      orthoHeight:64,fovDegrees:nil,perspectiveOverrideFOVDegrees:nil,nearZ:0.01,farZ:1000),viewportSize:CGSize(width:64,height:64))
  let light=SceneLightSnapshot.Directional(layerID:7,castsShadow:true,directionTowardLight:SIMD3(0,0,1),color:SIMD3(repeating:1),intensity:0.5)
  let lighting=SceneLightSnapshot(ambient:SIMD3(repeating:0.5),skylight: .zero,directional:[light],point:[],spot:[],overflowCount:0)
  let instances=SceneParticleMetalInstanceBuffer()
  precondition(instances.update(device:device,instances:[.init(position:SIMD3(48,48,0),size:12,rotation:.zero,color:SIMD3(1,0,1),alpha:1)]))
  let batch=SceneParticleDrawBatch(layerID:4,texture:white,colorUVScale:SIMD2(repeating:1),colorSampling:.directImageFallback,
      refraction:nil,renderState:.init(blendMode:.translucent,cullMode:.none,depthTestEnabled:true,depthWriteEnabled:true),
      instanceBuffer:instances,orientation:.screen,orientationAxis:nil,usesPerspective:false)
  let cb=queue.makeCommandBuffer()!
  let pass=SceneMainPassEncoder(commandBuffer:cb,target:output,clearColor:MTLClearColorMake(0.05,0.1,0.15,1),clearEnabled:true)
  let pool=SceneOffscreenTexturePool(device:device,pixelFormat:.bgra8Unorm,residentByteBudget:8*1024*1024)
  let state=SceneMetalRenderer.StaticModelFrame()
  var leases:[SceneParticleDepthTargetLease]=[]
  var held=0
  let depthDescriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:64,height:64,mipmapped:false)
  depthDescriptor.storageMode = .private;depthDescriptor.usage = .renderTarget
  let depthBytes=device.heapTextureSizeAndAlign(descriptor:depthDescriptor).size
  if mode.hasSuffix("quota") {
   let capacity=mode=="mandatory-quota" ? depthBytes : 3*depthBytes
   held=SceneResourceBudget.shared.maximumBytes-SceneResourceBudget.shared.snapshot.residentBytes-capacity
   precondition(SceneResourceBudget.shared.reserve(held,kind:.gpu))
  }
  defer { if held>0 { SceneResourceBudget.shared.release(held,kind:.gpu) } }
  let visible=Set(layers.map(\.id))
  // Exercise the actual encoder handoff: an admitted shadow pass must close
  // this live color encoder before creating its depth-only encoder.
  precondition(pass.encoder() != nil)
  let candidates=renderer.shadowDrawCandidates(orderedLayers:layers,visible:visible,worldFrames:world,snapshot:dynamic,groups:nil)!
  precondition(candidates[5]?.isEmpty==true)
  if mode != "original" {
   renderer.prepareModelShadow(state:state,candidates:candidates,lights:[.directional(light)],orderedLayers:layers,visible:visible,
      batches:[4:[batch]],particlePipeline:particles,mainPass:pass,groups:nil,pool:pool,commandBuffer:cb,
      leases:&leases,mandatoryCapacity:{true},recordsEvidence:false,cameraFrame:camera)
  }
  let before=leases.count
  let shared=state.prepared?[1]?.first?.depth?.lease
  let isolated=state.prepared?[2]?.first?.depth?.lease
  let other=state.prepared?[3]?.first?.depth?.lease
  let preparedParticle=state.particleDepth[4]?.lease
  let published = !state.shadows.isEmpty
  let modelBytesBefore=renderer.staticModelDepthTargetPool.residentByteCost
  let particleBytesBefore=particles.renderTargetResidentByteCost
  let rejectionsBefore=SceneResourceBudget.shared.snapshot.rejectionCount
  // Restore headroom after failed admission: a second allocation would now succeed
  // and change both the image and resident/depth lease observations.
  if mode=="mandatory-quota" {SceneResourceBudget.shared.release(held,kind:.gpu);held=0}
  for layer in layers where layer.contentKind=="model" {
   _=renderer.drawStaticModel(layer:layer,state:state,worldFrames:world,frameContext:.init(dynamicValues:dynamic),
       cameraFrame:camera,lighting:lighting,pass:pass,commandBuffer:cb,leases:&leases)
  }
  var observations:[SceneParticlePerformanceObservation]?=[]
  let usedParticle=renderer.renderParticleBatches([batch],pipeline:particles,model:matrix_identity_float4x4,cameraFrame:camera,
      viewportSize:SIMD2(64,64),mainPass:pass,commandBuffer:cb,preparedDepth:state.particleDepth[4],performanceObservations:&observations)
  if mode=="original",let usedParticle {leases.append(usedParticle)}
  let after=leases.count
  let sameParticle=(usedParticle == nil && preparedParticle == nil) || (usedParticle === preparedParticle)
  let allocationsStable=modelBytesBefore==renderer.staticModelDepthTargetPool.residentByteCost && particleBytesBefore==particles.renderTargetResidentByteCost
  let noRetry=SceneResourceBudget.shared.snapshot.rejectionCount==rejectionsBefore
  precondition(pass.finishEnsuringClear())
  for lease in leases {lease.arm(on:cb)}
  state.arm(on:cb);cb.commit();cb.waitUntilCompleted()
  guard cb.status == .completed else {throw cb.error ?? NSError(domain:"frame-owner",code:1)}
  var bytes=[UInt8](repeating:0,count:64*64*4)
  output.getBytes(&bytes,bytesPerRow:64*4,from:MTLRegionMake2D(0,0,64,64),mipmapLevel:0)
  func rgb(_ x:Int,_ y:Int)->[UInt8] {let i=(y*64+x)*4;return [bytes[i+2],bytes[i+1],bytes[i],bytes[i+3]]}
  return ["mode":mode,"before":before,"after":after,"shadow":published,"completed":true,
      "sharedIdentity":shared != nil && shared?.texture === other?.texture,
      "isolatedIdentity":isolated != nil && shared?.texture !== isolated?.texture,
      "particleIdentity":sameParticle,"allocationsStable":allocationsStable,"noRetry":noRetry,
      "model1":renderer.dependencyRuntime.encoded[1] ?? false,"model2":renderer.dependencyRuntime.encoded[2] ?? false,
      "model3":renderer.dependencyRuntime.encoded[3] ?? false,"particleDraws":observations?.count ?? 0,
      "pixels":[rgb(12,12),rgb(44,12),rgb(48,48),rgb(30,30)],"shadowResident":pool.residentByteCost,
      "modelBytes":renderer.staticModelDepthTargetPool.residentByteCost,"particleBytes":particles.renderTargetResidentByteCost]
 }
}
'''
HARNESS = pool_fixture.HARNESS.split('@main', 1)[0] + SHELL + UNUSED_ORDERED_SUPPORT + MAIN



# Prepared geometry inputs only: the real camera, frame producer, all three
# shadow projections and the unique drawShadow encode remain unchanged.
CULL_MAIN = r'''
extension SIMD4 where Scalar == Float {var xyz:SIMD3<Float> {SIMD3(x,y,z)}}
@main enum CameraFamilyCullProbe {
 static func main() throws {
  guard let device=MTLCreateSystemDefaultDevice(),let queue=device.makeCommandQueue() else {
   print("{\"metalUnavailable\":true}");return
  }
  var rows:[[String:Any]]=[]
  for family in ["native","canvas","fitted","native-ortho","native-utility"] {
   for type in ["directional","spot","point"] {
    for transformed in [false,true] {
     for reverse in [false,true] { for noCull in [false,true] {
      rows.append(try run(family,type,transformed,reverse,noCull,device,queue))
     }}
    }
   }
  }
  print(String(decoding:try JSONSerialization.data(withJSONObject:["rows":rows],options:[.sortedKeys]),as:UTF8.self))
 }
 static func run(_ family:String,_ type:String,_ transformed:Bool,_ reverse:Bool,_ noCull:Bool,
                 _ device:MTLDevice,_ queue:MTLCommandQueue)throws->[String:Any] {
  let pipeline=SceneStaticModelPipeline(device:device)!
  let native=family.hasPrefix("native")
  let camera=SceneParticleCameraFrame(camera:.init(eye:[0,0,5],center:[0,0,0],up:[0,1,0],
   orthoWidth:native ? nil:8,orthoHeight:native ? nil:8,fovDegrees:native ? 60:nil,
   perspectiveOverrideFOVDegrees:family=="fitted" ? 60:nil,nearZ:0.01,farZ:100),viewportSize:CGSize(width:64,height:64))
  let layer=SceneRenderDescriptor.Layer(id:1,utilityLayer:family=="native-utility" ? true:nil,
    usesPerspective:family=="canvas" || family=="native-ortho" ? false:true)
  let positions:[SIMD3<Float>]=[SIMD3(-1,-1,0),SIMD3(1,-1,0),SIMD3(1,1,0),SIMD3(-1,1,0)]
  let vertices=positions.map{SceneMdlStaticModel.Vertex(position:$0,normal:SIMD3(0,0,1),tangent:SIMD4(1,0,0,1),uv:SIMD2(repeating:0.5))}
  let mesh=pipeline.makeMesh(vertices:vertices,indices:reverse ? [0,2,1,0,3,2]:[0,1,2,0,2,3])!
  let td=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:1,height:1,mipmapped:false)
  td.storageMode = .shared;td.usage = .shaderRead
  let white=device.makeTexture(descriptor:td)!,pixel:[UInt8]=[255,255,255,255]
  pixel.withUnsafeBytes{white.replace(region:MTLRegionMake2D(0,0,1,1),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:4)}
  var material=SceneStaticModelMaterial(color:SIMD3(repeating:1),opacity:1,receivesLighting:true,
   textureAlphaIsOpacity:true,textureAlphaIsTintMask:false,emissiveColor:.zero,emissiveBrightness:0,
   brightness:1,usesHDRBrightness:false,viewTint:nil)
  material.cullMode=noCull ? .none:.back
  let entry=ScenePreparedStaticModelResources.Entry(materialPath:"own-cull",dynamicMaterialPath:"",geometryIdentity:"quad",
   mesh:mesh,albedo:PreparedTexture(texture:white),material:material)
  var entries=[1:[entry]]
  var layers=[layer]
  if family=="native" {
   // Native, explicit canvas and utility casters share one encoder/map. Peers
   // use authored canvas front winding; reverse changes submission order too.
   let peerMesh=pipeline.makeMesh(vertices:vertices,indices:[0,2,1,0,3,2])!
   var peerMaterial=material;peerMaterial.cullMode = .back
   for id in [2,3] {
    entries[id]=[.init(materialPath:"own-peer",dynamicMaterialPath:"",geometryIdentity:"peer",
      mesh:peerMesh,albedo:PreparedTexture(texture:white),material:peerMaterial)]
   }
   layers += [.init(id:2,utilityLayer:nil,usesPerspective:false),.init(id:3,utilityLayer:true,usesPerspective:true)]
   if reverse {layers.reverse()}
  }
  let renderer=SceneMetalRenderer(device:device,resources:.init(pipeline:pipeline,entries:entries))
  var world=transformed ? SceneMatrix.eulerXYZ(SIMD3(0.2,-0.3,0.1))*SceneMatrix.scale(SIMD3(1.1,0.8,1.2)):matrix_identity_float4x4
  if transformed {world.columns.3=SIMD4(2,-3,-4,1)}
  let center=world.columns.3.xyz,position=(world*SIMD4(0,0,4,1)).xyz
  let toward=simd_normalize(position-center)
  let light:SceneLightSnapshot.ShadowLight
  if type=="directional" {light = .directional(.init(layerID:7,castsShadow:true,directionTowardLight:toward,color:SIMD3(repeating:1),intensity:1))}
  else if type=="spot" {light = .spot(.init(layerID:7,castsShadow:true,position:position,directionFromLight:-toward,
    color:SIMD3(repeating:1),intensity:1,radius:10,innerConeCosine:cos(.pi/6),outerConeCosine:cos(.pi/4),outerConeDegrees:45))}
  else {light = .point(.init(layerID:7,castsShadow:true,position:position,color:SIMD3(repeating:1),intensity:1,radius:10))}
  let outDesc=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:64,height:64,mipmapped:false)
  outDesc.storageMode = .private;outDesc.usage = .renderTarget
  let output=device.makeTexture(descriptor:outDesc)!,cb=queue.makeCommandBuffer()!
  let pass=SceneMainPassEncoder(commandBuffer:cb,target:output,clearColor:MTLClearColorMake(0,0,0,1),clearEnabled:true)
  let pool=SceneOffscreenTexturePool(device:device,pixelFormat:.bgra8Unorm,residentByteBudget:32*1024*1024)
  let state=SceneMetalRenderer.StaticModelFrame(),dynamic=SceneDynamicSnapshot.empty(frameIndex:1,generation:1)
  var worlds=[1:world]
  for (id,x) in [(2,Float(3)),(3,Float(-3))] where entries[id] != nil {
   worlds[id]=world*SceneMatrix.translation(SIMD3(x,0,0))
  }
  let visible=Set(layers.map(\.id))
  let candidates=renderer.shadowDrawCandidates(orderedLayers:layers,visible:visible,worldFrames:worlds,snapshot:dynamic,groups:nil)!
  var leases:[SceneParticleDepthTargetLease]=[]
  renderer.prepareModelShadow(state:state,candidates:candidates,lights:[light],orderedLayers:layers,visible:visible,batches:[:],
   particlePipeline:nil,mainPass:pass,groups:nil,pool:pool,commandBuffer:cb,leases:&leases,
   mandatoryCapacity:{true},recordsEvidence:false,cameraFrame:camera)
  let shadow=state.shadows.first!,map=shadow.texture
  let blit=cb.makeBlitCommandEncoder()!
  var buffers:[MTLBuffer]=[]
  for id in worlds.keys.sorted() {
   let point=worlds[id]!.columns.3.xyz
   let clip:SIMD3<Float>,face:Int
   switch shadow.projection {
   case .directional(let p):clip=(p.worldToClip*SIMD4(point,1)).xyz;face=0
   case .spot(let p):let q=(p.worldToLight*SIMD4(point-p.position,0)).xyz;clip=SIMD3(q.x/(q.z*p.tanHalfAngle),q.y/(q.z*p.tanHalfAngle),0);face=0
   case .point(let p):
    let ray=point-p.position,a=simd_abs(ray)
    face=a.x>=a.y && a.x>=a.z ? (ray.x>=0 ? 0:1):a.y>=a.z ? (ray.y>=0 ? 2:3):(ray.z>=0 ? 4:5)
    let q=(ScenePointShadowProjection.worldToFaces[face]*SIMD4(ray,0)).xyz
    clip=SIMD3(q.x/q.z,q.y/q.z,0)
   }
   let viewport=shadow.projection.viewport(face:face,width:map.width,height:map.height)
   let x=Int(viewport.originX+(Double(clip.x)+1)*viewport.width*0.5)
   let y=Int(viewport.originY+(1-Double(clip.y))*viewport.height*0.5)
   let buffer=device.makeBuffer(length:256,options:.storageModeShared)!
   blit.copy(from:map,sourceSlice:0,sourceLevel:0,sourceOrigin:.init(x:x,y:y,z:0),sourceSize:.init(width:1,height:1,depth:1),
    to:buffer,destinationOffset:0,destinationBytesPerRow:256,destinationBytesPerImage:256)
   buffers.append(buffer)
  }
  blit.endEncoding();leases.forEach{$0.arm(on:cb)};state.arm(on:cb);cb.commit();cb.waitUntilCompleted()
  precondition(cb.status == .completed && cb.error == nil)
  let depths=buffers.map{$0.contents().bindMemory(to:Float.self,capacity:1).pointee}
  return ["family":family,"light":type,"transformed":transformed,"reverse":reverse,"noCull":noCull,
   "nativeCamera":camera.defaultsToPerspective,"perspectiveLayer":camera.resolvesPerspective(for:layer),
   "depth":depths[0],"peerDepth":Array(depths.dropFirst()),"completed":true]
 }
}
'''


class SceneModelShadowCameraFamilyTests(unittest.TestCase):
    def test_real_frame_native_canvas_fitted_and_override_cull_for_three_lights(self):
        support = pool_fixture.HARNESS.split('@main', 1)[0] + SHELL + UNUSED_ORDERED_SUPPORT + CULL_MAIN
        report = shadow_fixture.run_swift(SOURCES, support, label='camera-family-cull',
                    metal_sources=[SCENE/'Rendering/Composition/SceneStaticModel.metal'])
        self.assertEqual(len(report['rows']), 120)
        for row in report['rows']:
            native = row['family'] == 'native'
            expected = row['noCull'] or (not row['reverse'] if native else row['reverse'])
            self.assertTrue(row['completed'], row)
            self.assertEqual(len(row['peerDepth']), 2 if native else 0, row)
            for depth in row['peerDepth']:
                self.assertGreaterEqual(depth, 0, row)
                self.assertLess(depth, .99, row)
            self.assertEqual(row['nativeCamera'], row['family'].startswith('native'), row)
            self.assertEqual(row['perspectiveLayer'], row['family'] in ('native', 'fitted'), row)
            if expected:
                self.assertLess(row['depth'], .99, row)
                self.assertGreaterEqual(row['depth'], 0, row)
            else:
                self.assertEqual(row['depth'], 1, row)


def typecheck():
    work = Path(tempfile.mkdtemp(prefix='mwx-shadow-frame-typecheck-'))
    source = work/'Harness.swift'; source.write_text(HARNESS)
    result = subprocess.run(['xcrun', 'swiftc', '-typecheck', '-module-cache-path', str(work/'cache'),
                             *map(str, SOURCES), str(source)], capture_output=True, text=True)
    (work/'typecheck.log').write_text(result.stdout+result.stderr)
    print(work);print(result.stderr)
    return result.returncode


class SceneDirectionalShadowFrameOwnerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # run_swift expects a JSON object; the probe returns mode-keyed results.
        report = shadow_fixture.run_swift(SOURCES, HARNESS, label='frame-owner',
                         metal_sources=[SCENE/'Rendering/Composition/SceneStaticModel.metal'])
        cls.rows = {row['mode']: row for row in report['rows']}

    def test_prepared_depth_is_consumed_once_by_both_actual_frame_owners(self):
        row = self.rows['prepared']
        self.assertTrue(row['shadow']);self.assertEqual((row['before'],row['after']),(3,3))
        for key in ['sharedIdentity','isolatedIdentity','particleIdentity','allocationsStable','noRetry','completed','model1','model2','model3']:
            self.assertTrue(row[key], key)
        self.assertEqual(row['particleDraws'],1)

    def test_optional_physical_quota_failure_preserves_original_model_and_particle_pixels(self):
        row = self.rows['optional-quota']
        self.assertFalse(row['shadow']);self.assertEqual(row['shadowResident'],0)
        self.assertEqual((row['before'],row['after']),(3,3))
        for key in ['sharedIdentity','isolatedIdentity','particleIdentity','allocationsStable','noRetry','model1','model2','model3']:
            self.assertTrue(row[key],key)
        self.assertEqual(row['particleDraws'],1)
        self.assertEqual(row['pixels'],self.rows['original']['pixels'])
        self.assertTrue(any(max(pixel[:3])>128 for pixel in row['pixels'][:3]))

    def test_failed_mandatory_lease_is_not_retried_after_budget_recovers(self):
        row=self.rows['mandatory-quota']
        self.assertFalse(row['shadow']);self.assertEqual((row['before'],row['after']),(1,1))
        self.assertTrue(row['model1']);self.assertTrue(row['model3']);self.assertFalse(row['model2'])
        self.assertEqual(row['particleDraws'],0)
        self.assertTrue(row['allocationsStable']);self.assertTrue(row['noRetry']);self.assertTrue(row['particleIdentity'])
        self.assertEqual(row['pixels'][1],self.rows['original']['pixels'][1])


if __name__ == '__main__':
    if '--typecheck' in sys.argv:
        raise SystemExit(typecheck())
    unittest.main()
