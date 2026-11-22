#!/usr/bin/env python3
"""Real frame-owner/Metal mandatory-depth handoff; peripheral preparation is stubbed.

Compiles the production renderer/particle frame owners, pipelines, depth pool, offscreen pool
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
from script.tests.scene import test_scene_particle_rendering as particle_fixture
from script.tests.scene import test_scene_static_model_pipeline as model_fixture
from script.scene_swift_source_sets import scene_swift_sources

REPO = Path(__file__).resolve().parents[2]
SCENE = REPO / 'MyWallpaperX/Core/SteamWorkshopScene'
SOURCES = list(dict.fromkeys([
    *scene_swift_sources("scene_resource_input"),
    *pool_fixture.SWIFT_SOURCES,
    SCENE/'Diagnostics/SceneEffectExecutionFrameTrace.swift',
    SCENE/'Diagnostics/SceneEffectExecutionTelemetry.swift',
    *model_fixture.MODEL_SUPPORT_SOURCES,
    *(p for p in particle_fixture.SWIFT_SOURCES if p.parent.name != 'fixtures'),
    *(getattr(model_fixture, name) for name in [
        'MODEL_SOURCE', 'DIRECTIONAL_LIGHT_SOURCE', 'POINT_LIGHT_SOURCE', 'TUBE_LIGHT_SOURCE',
        'SPOT_LIGHT_SOURCE', 'LIGHT_SOURCE', 'VISIBILITY_SOURCE', 'DYNAMIC_SNAPSHOT_SOURCE',
        'DYNAMIC_LAYER_VALUES_SOURCE', 'MATERIAL_SOURCE', 'PIPELINE_SOURCE', 'SHADOW_SOURCE']),
    SCENE/'Runtime/Frame/SceneStaticModelMaterialBindings.swift',
    SCENE/'Runtime/Frame/SceneMaterialRenderState.swift',
    SCENE/'Compilation/Material/SceneMaterialRenderState+Compilation.swift',
    SCENE/'Format/SceneMdlPuppetMeshReader.swift',
    SCENE/'Format/SceneMdlPuppetRigReader.swift',
    SCENE/'Format/ScenePuppetAnimationLayer.swift',
    SCENE/'Format/SceneTimelineAnimation.swift',
    SCENE/'Rendering/Metal/SceneStaticModelVertexStream.swift',
    SCENE/'Rendering/Frame/SceneSourceUpdateTransaction.swift',
    SCENE/'Rendering/Frame/SceneMetalRenderer+StaticModels.swift',
    SCENE/'Rendering/Particles/SceneParticleMetalPipeline+Frame.swift',
]))

SHELL = r'''
// Prepared-input shell only; no framebuffer-source role is admitted here.
extension Bool { var framebufferSource: Bool? { nil } }
struct SceneImageLayerTerminalDepthBinding {
 let encoder:(SceneMainPassEncoder)->MTLRenderCommandEncoder?
}
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
  struct LightClassesDescriptor { var directional:Bool = true; var point:Bool = true; var spot:Bool = true; var tube:Bool = true }
  let ambientColorRGB:[Float]?;let skylightColorRGB:[Float]?;var lightClasses:LightClassesDescriptor = .init();var distanceFog:DistanceFog? = nil
 }
 struct Layer {
  let id:Int;var visible:Bool? = true;var pointLight:ScenePointLightDefinition? = nil
  var tubeLight:SceneTubeLightDefinition? = nil
  var spotLight:SceneSpotLightDefinition? = nil;var directionalLight:SceneDirectionalLightDefinition? = nil
  var dependencyLayerIDs:[Int]=[]
  var parentID:Int? = nil;var displayScriptOwnership:SceneLayerDisplayScriptOwnership? = nil
  var utilityLayer:Bool? = false;var usesPerspective:Bool? = false
  // This shadow fixture has ordinary model/image receivers, no composition.
  var hasPerspectiveGeometryConsumer:Bool {utilityLayer == nil}
  var hasFramebufferMaterialSource:Bool {utilityLayer?.framebufferSource != nil}
  var alpha:Double? = 1;var contentKind:String = "model"
  var modelShadowCastIntent:SceneShadowCastIntent? = nil;var colorBlendMode:Int? = nil
  var anglesXYZ:[Float]? = nil
  var puppetAnimationLayers:[ScenePuppetAnimationLayer] = []
 }
 struct CameraDescriptor {
  let eye:[Float];let center:[Float];let up:[Float];let orthoWidth:Float?;let orthoHeight:Float?
  let fovDegrees:Float?;let perspectiveOverrideFOVDegrees:Float?;let nearZ:Float;let farZ:Float
  var default2DOriginInputLayerID:Int? = nil
 }
 let lighting:LightingDescriptor?;let layers:[Layer];let renderOrderLayerIDs:[Int]
 var camera:CameraDescriptor = CameraDescriptor(eye:[0,0,0],center:[0,0,-1],up:[0,1,0],orthoWidth:64,orthoHeight:64,fovDegrees:nil,perspectiveOverrideFOVDegrees:nil,nearZ:0.01,farZ:1000)
}
struct SceneFrameContext { let dynamicValues:SceneDynamicSnapshot }
extension SceneFrameContext { var frameIndex:UInt64 {0} }
#if DEBUG
enum SceneDesktopWallpaperHost {static let usesDebugEvidenceWindow=false}
// Timestamp requests are outside this resource/pixel fixture. With none
// selected, the leaf performs the same real Metal encoder creation.
enum SceneGPUStageTimestampHook {
 static func render(_ buffer:MTLCommandBuffer,_ descriptor:MTLRenderPassDescriptor,
                    role:String)->MTLRenderCommandEncoder? {buffer.makeRenderCommandEncoder(descriptor:descriptor)}
 static func blit(_ buffer:MTLCommandBuffer,role:String)->MTLBlitCommandEncoder? {buffer.makeBlitCommandEncoder()}
 static func drew(_ encoder:MTLRenderCommandEncoder) {}
 static func endedMain(_ encoder:MTLRenderCommandEncoder) {}
}
#endif
struct SceneParticlePerformanceObservation { let layerID:Int;let instanceCount:Int;let isRefraction:Bool }
struct PreparedTexture {
 let texture:MTLTexture;var uvTransform:SceneTextureUVTransform = .identity
 var sampling:SceneTextureSampling = .directImageFallback
 func candidate(for identity:SceneAssetTextureIdentity)->SceneTextureCandidate {
  let size=CGSize(width:texture.width,height:texture.height)
  return .init(texture:texture,identity:.builtIn(name:identity.reportToken),
   generation:.immutable(revision:1),purpose:.straightAlbedo,content:.color(.resolved(.straightAlpha)),
   physicalSize:size,mappedSize:size,uvTransform:uvTransform,sampling:sampling)
 }
}
struct ScenePreparedStaticModelResources {
 enum AlbedoSource: Equatable { case asset(SceneAssetTextureIdentity), named(String) }
 struct Entry {
  let materialPath:String;let dynamicMaterialPath:String;let mesh:SceneStaticModelMesh
  let albedoSource:AlbedoSource?
  var userAlbedoProperty:SceneUserPropertyTextureIdentity? = nil
  let fixtureAlbedo:PreparedTexture?
  var materialMap:SceneStaticModelMaterialMap? = nil
  var normalMap:SceneStaticModelNormalMap? = nil
  var gradient:SceneStaticModelGradient? = nil
  var pigment:SceneStaticModelPigment? = nil
  let material:SceneStaticModelMaterial;var writesDepth:Bool = true
  var testsDepth:Bool = true
  var materialBlending:SceneMaterialRenderState.Blending? = nil
  var geometryState:SceneMdlStaticModel.GeometryState = .authoredStatic
  init(materialPath:String,dynamicMaterialPath:String,mesh:SceneStaticModelMesh,
       albedo:PreparedTexture?,namedAlbedo:String?=nil,
       materialMap:SceneStaticModelMaterialMap?=nil,normalMap:SceneStaticModelNormalMap?=nil,
       gradient:SceneStaticModelGradient?=nil,pigment:SceneStaticModelPigment?=nil,
       material:SceneStaticModelMaterial,writesDepth:Bool=true,testsDepth:Bool=true,
       materialBlending:SceneMaterialRenderState.Blending?=nil,
       geometryState:SceneMdlStaticModel.GeometryState = .authoredStatic) {
   self.materialPath=materialPath;self.dynamicMaterialPath=dynamicMaterialPath;self.mesh=mesh
   albedoSource=namedAlbedo.map(AlbedoSource.named)
    ?? .asset(SceneAssetTextureIdentity(virtualPath:"fixture/"+UUID().uuidString,purpose:.straightAlbedo)!)
   fixtureAlbedo=albedo;self.materialMap=materialMap;self.normalMap=normalMap
   self.gradient=gradient;self.pigment=pigment;self.material=material
   self.writesDepth=writesDepth;self.testsDepth=testsDepth
   self.materialBlending=materialBlending;self.geometryState=geometryState
  }
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
 var namedQueries:[String] = []
 func staticModelNamedAlbedo(for id:Int, materialPath:String, expectedReference:String,
                            textureRegistry:TextureRegistry)->NamedAlbedo? {
  namedQueries.append(materialPath);return nil
 }
 func recordStaticModelBindingFailure(for id:Int) { encoded[id] = false }
 func recordStaticModelBindingIfRequired(for id:Int, encoded value:Bool, on cb:MTLCommandBuffer) { encoded[id] = value }
}
enum FixtureAssetRequest {case asset(SceneAssetTextureIdentity), materialUserProperty(SceneUserPropertyTextureIdentity)}
struct FixtureAssetPublication {let candidate:SceneTextureCandidate}
struct FixtureAssetResource {let publication:FixtureAssetPublication}
enum FixturePropertyLookup {case ready(FixtureAssetResource), absent, pending, unavailable, incomplete}
final class TextureRegistry {
 let frameEpoch:UInt64 = 1
 var candidates:[SceneAssetTextureIdentity:SceneTextureCandidate]=[:]
 var properties:[SceneUserPropertyTextureIdentity:FixturePropertyLookup]=[:]
 func lookup(_ request:FixtureAssetRequest)->FixturePropertyLookup? {
  guard case let .materialUserProperty(identity)=request else {return nil}
  return properties[identity]
 }
 func setCandidate(_ candidate:SceneTextureCandidate,for identity:SceneAssetTextureIdentity) {
  candidates[identity]=candidate
 }
 func resource(for request:FixtureAssetRequest)->FixtureAssetResource? {
  guard case let .asset(identity)=request,let candidate=candidates[identity] else {return nil}
  return .init(publication:.init(candidate:candidate))
 }
 func supply(_ source:PreparedTexture,for identity:SceneAssetTextureIdentity) {
  setCandidate(source.candidate(for:identity),for:identity)
 }
}
struct SceneCompositionGroupFrameRuntime {
 func renderPass(forLayerID:Int)->SceneMainPassEncoder? { nil }
 func closeAllGroupEncoders() {}
 func terminalScratch(matching:MTLTexture,on:MTLCommandBuffer)->MTLTexture? {nil}
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
 var renderDescriptor=SceneRenderDescriptor(lighting:nil,layers:[],renderOrderLayerIDs:[])
 var utilityExecution=SceneUtilityLayerRuntimePlanner.Execution()
 var layersByID:[Int:SceneRenderDescriptor.Layer]=[:]
 let imageCompositor=SceneImageLayerCompositor()
 func baseMaterialReadyProviderUsesAuthoredLayerColor(for layer:SceneRenderDescriptor.Layer,dynamicValues:SceneDynamicSnapshot)->Bool {fatalError("unused snapshot-demand shell")}
 func baseMaterialTextureSelection(for layer:SceneRenderDescriptor.Layer,imageTextures:SceneBaseImageTextureSnapshot,readyProviderUsesAuthoredLayerColor:Bool)->FixtureImageSelection {fatalError("unused snapshot-demand shell")}
 let staticModelDepthTargetPool = SceneParticleDepthTargetPool()
 let dependencyRuntime = BindingObserver();let textureRegistry = TextureRegistry()
 init(device:MTLDevice, resources:ScenePreparedStaticModelResources) {
  self.device=device;staticModelResources=resources
  for entry in resources.entries.values.flatMap({$0}) {
   if case let .asset(identity)=entry.albedoSource,let source=entry.fixtureAlbedo {
    textureRegistry.supply(source,for:identity)
   }
  }
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
struct FixtureLightingProfile { let surfaceEnabled:Bool }
struct FixtureProviderBindings {
 let lightingProfileByLayerID:[Int:FixtureLightingProfile]
 func lightingProfile(for layer:SceneRenderDescriptor.Layer)->FixtureLightingProfile? {lightingProfileByLayerID[layer.id]}
}
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
 func layerSourceTextPlacement(for id:Int) -> (centerOffsetY: Float, rasterOffsetY: Float)? { fatalError("unused RF13 ordered preparation shell") }
 var geometryProducts:[Int:FixtureGeometryProduct] { fatalError("unused RF13 ordered preparation shell") }
}
extension SceneMetalRenderer {
 var baseMaterialProviderBindings:FixtureProviderBindings { fatalError("unused RF13 ordered preparation shell") }
 static func effectExecutionOrigin(for contentKind:String)->SceneEffectExecutionOrigin { fatalError("unused RF13 ordered preparation shell") }
 func captureRawDependencyProvider(layer:SceneRenderDescriptor.Layer,source:MTLTexture?,
  imageTextures:SceneBaseImageTextureSnapshot,imagePipeline:SceneImageLayerPipeline,
  frameContext:SceneFrameContext,worldFrames:[Int:simd_float4x4],cameraFrame:SceneParticleCameraFrame,
  parallax:SceneLayerParallax.Configuration,viewportSize:CGSize,mainPass:SceneMainPassEncoder,
  preparesCapacityOnly:Bool)->SceneGraphOutputPublicationResult? {
  fatalError("unused RF13 ordered preparation shell")
 }
 func imageModelMatrix(for layer:SceneRenderDescriptor.Layer,worldFramesByLayerID:[Int:simd_float4x4],
  renderSizeOverride:[Float]?,textPlacement: (centerOffsetY: Float, rasterOffsetY: Float)? = nil,parallaxMouseNormalized:SIMD2<Float>,configuration:SceneLayerParallax.Configuration,
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
   return pipeline.makeMesh(model: SceneStaticModelFixture.model(vertices:vertices,indices:[0,2,1,0,3,2]))!
  }
  let meshA=quad(4,4,20),meshB=quad(36,4,20)
  func material(_ color:SIMD3<Float>)->SceneStaticModelMaterial {
   .init(color:color,opacity:1,receivesLighting:true,textureAlphaIsOpacity:true,textureAlphaIsTintMask:false,
         emissiveColor:.zero,emissiveBrightness:0,brightness:1,usesHDRBrightness:false,viewTint:nil)
  }
  func entry(_ mesh:SceneStaticModelMesh,_ color:SIMD3<Float>)->ScenePreparedStaticModelResources.Entry {
   .init(materialPath:"self-authored",dynamicMaterialPath:"",mesh:mesh,
         albedo:PreparedTexture(texture:white),material:material(color))
  }
  let renderer=SceneMetalRenderer(device:device,resources:.init(pipeline:pipeline,entries:[
   1:[entry(meshA,SIMD3(1,0,0))],
   2:[entry(meshA,SIMD3(0,1,0))],
   3:[entry(meshB,SIMD3(0,0,1))],
   5:[entry(meshA,SIMD3(1,1,0))]
  ]))
  let layers=[SceneRenderDescriptor.Layer(id:1),.init(id:2),.init(id:3),.init(id:4,contentKind:"particle"),.init(id:5)]
  // Legacy canonical-down quad carrier: express its author Y reflection.
  let world=Dictionary(uniqueKeysWithValues:layers.map { ($0.id,SceneMatrix.scale(SIMD3(1,-1,$0.id==5 ? 0:1))) })
  let dynamic=SceneDynamicSnapshot.empty(frameIndex:1,generation:1)
  let camera=SceneParticleCameraFrame(camera:.init(eye:[0,0,0],center:[0,0,-1],up:[0,1,0],orthoWidth:64,
      orthoHeight:64,fovDegrees:nil,perspectiveOverrideFOVDegrees:nil,nearZ:0.01,farZ:1000),viewportSize:CGSize(width:64,height:64))
  let light=SceneLightSnapshot.Directional(layerID:7,castsShadow:true,directionTowardLight:SIMD3(0,0,1),color:SIMD3(repeating:1),intensity:0.5)
  let lighting=SceneLightSnapshot(ambient:SIMD3(repeating:0.5),skylight: .zero,directional:[light],point:[],spot:[],overflowCount:0)
  let batch=SceneParticleDrawBatch(layerID:4,particlePath:"particles/depth.json",texture:white,colorUVScale:SIMD2(repeating:1),colorSampling:.directImageFallback,
      refraction:nil,renderState:.init(blendMode:.translucent,cullMode:.none,depthTestEnabled:true,depthWriteEnabled:true),
      childTemplateIndex:nil,instances:[.init(position:SIMD3(48,48,0),size:12,rotation:.zero,color:SIMD3(1,0,1),alpha:1)],
      orientation:.screen,orientationAxis:nil,usesPerspective:false)
  let prepared=particles.prepare([batch]);precondition(prepared.count==1)
  let cb=queue.makeCommandBuffer()!
  let pass=SceneMainPassEncoder(commandBuffer:cb,target:output,clearColor:MTLClearColorMake(0.05,0.1,0.15,1),clearEnabled:true)
  let pool=SceneOffscreenTexturePool(device:device,pixelFormat:.bgra8Unorm,residentByteBudget:8*1024*1024)
  let state=SceneMetalRenderer.StaticModelFrame(commandBuffer:cb)
  var leases:[SceneParticleDepthTargetLease]=[]
  var held=0
  let depthDescriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:64,height:64,mipmapped:false)
  depthDescriptor.storageMode = .private;depthDescriptor.usage = .renderTarget
  let depthBytes=device.heapTextureSizeAndAlign(descriptor:depthDescriptor).size
  if mode.hasSuffix("quota") {
   let capacity=mode=="mandatory-quota" ? depthBytes : 2*depthBytes
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
      batches:[4:prepared],particlePipeline:particles,mainPass:pass,groups:nil,pool:pool,commandBuffer:cb,
      leases:&leases,mandatoryCapacity:{true},recordsEvidence:false,cameraFrame:camera)
  }
  let before=leases.count
  // Read the real prepared pass domain; this is a cached acquisition, not a
  // per-mesh depth reservation. The original path acquires during actual draw.
  let shared=state.prepared == nil ? nil : state.sharedDepth(pass:pass,
      pool:renderer.staticModelDepthTargetPool,device:device,commandBuffer:cb,leases:&leases).lease
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
  let usedParticle=particles.drawBatches(prepared,model:matrix_identity_float4x4,cameraFrame:camera,
      viewportSize:SIMD2(64,64),mainPass:pass,commandBuffer:cb,preparedDepth:state.particleDepth[4]?.acquisition,performanceObservations:&observations)
  if mode=="original",let usedParticle {leases.append(usedParticle)}
  let after=leases.count
  let consumedModel=state.sharedDepth(pass:pass,pool:renderer.staticModelDepthTargetPool,
      device:device,commandBuffer:cb,leases:&leases).lease
  precondition(leases.count==after) // No observation may allocate another domain.
  let modelDepthCount=after-(usedParticle == nil ? 0:1)
  let separateParticle=usedParticle == nil || consumedModel?.texture !== usedParticle?.texture
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
      "sharedIdentity":shared != nil && shared?.texture === consumedModel?.texture,
      "modelDepthCount":modelDepthCount,"particleDomainSeparate":separateParticle,
      "particleIdentity":sameParticle,"allocationsStable":allocationsStable,"noRetry":noRetry,
      "model1":renderer.dependencyRuntime.encoded[1] ?? false,"model2":renderer.dependencyRuntime.encoded[2] ?? false,
      "model3":renderer.dependencyRuntime.encoded[3] ?? false,"particleDraws":observations?.count ?? 0,
      "pixels":[rgb(12,12),rgb(44,12),rgb(48,48),rgb(30,30)],"shadowResident":pool.residentByteCost,
      "modelBytes":renderer.staticModelDepthTargetPool.residentByteCost,"particleBytes":particles.renderTargetResidentByteCost]
 }
}
'''
HARNESS = pool_fixture.HARNESS.split('@main', 1)[0] + SHELL + UNUSED_ORDERED_SUPPORT + MAIN


def model_shadow_coverage_cases():
    def row(name, light="directional", expected=(True, True), **changes):
        return dict(name=name, light=light, expected=list(expected), blending="translucent", **changes)

    rows = []
    for light in ["directional", "spot", "point"]:
        rows += [dict(row(light + "-normal", light), blending="normal"),
                 row(light + "-translucent", light),
                 row(light + "-holes", light, (False, True), textureAlpha=[0, 1])]
    rows += [dict(row("additive-covered"), blending="additive"),
             dict(row("additive-cast-false", expected=(False, False), castFalse=True), blending="additive"),
             row("texture-half", expected=(False, False), textureAlpha=[.5, .5]),
             row("texture-above-half", textureAlpha=[.50048828125, .50048828125]),
             row("alpha-product-covered", opacity=.75, layerAlpha=.75),
             row("alpha-product-hole", expected=(False, False), opacity=.75, layerAlpha=.75, textureAlpha=[.75, .75]),
             row("tint-mask-zero", textureAlpha=[0, 0], tintMask=True),
             row("camera-test-off", testsDepth=False),
             row("camera-write-off", writesDepth=False),
             row("camera-test-write-off", testsDepth=False, writesDepth=False),
             row("renamed-transformed", renamed=True, transformed=True),
             row("reverse-culled", expected=(False, False), reverse=True),
             row("reverse-nocull", reverse=True, noCull=True),
             row("hidden-covered", expected=(False, False), hidden=True)]
    for light in ["directional", "spot", "point"]:
        rows += [row(light+"-uv-reference", light, frameScale=1, noCull=True),
                 row(light+"-uv-tiny", light, frameScale=1/4096, frameOrigin=[.5,.5], noCull=True)]
    rows += [row("uv-zero", expected=(False, False), frameScale=0, expectedShadow=False, noCull=True),
             row("uv-nan", expected=(False, False), frameScale=1, frameInvalid="nan", expectedShadow=False, noCull=True)]
    return rows



# Prepared geometry inputs only: the real camera, frame producer, all three
# shadow projections and the unique drawShadow encode remain unchanged.
CULL_MAIN = (Path(__file__).with_name("fixtures") / "SceneModelShadowCameraFamilyChecks.swift").read_text(encoding="utf-8")


def model_normal_consumer_cases():
    rows=[]
    def pair(plane,light,**values):
        prefix=f'normal-{plane}-{light}'+''.join('-'+key for key,value in values.items() if value)
        for mode in ('control','rank2'):
            rows.append(dict(name=prefix+'-'+mode,normalConsumer=True,plane=plane,light=light,
                normalMode=mode,noCull=True,reference=prefix+'-control',**values))
    for plane in ('xy','yz'):
        for light in ('directional','spot','point'):pair(plane,light)
        for values in (dict(transformed=True),dict(mirror=True),dict(renamed=True)):
            pair(plane,'directional',**values)
        pair(plane,'directional',leaf=True)
    for light in ('directional','spot','point'):
        for mode in ('mixed','mixed-named','all-zero','nan-world'):
            rows.append(dict(name='normal-'+light+'-'+mode,normalConsumer=True,plane='xy',light=light,
                normalMode=mode,noCull=True,reference='normal-xy-'+light+'-control'))
    rows.append(dict(name='normal-mixed-invertible',normalConsumer=True,plane='xy',light='directional',
        normalMode='mixed-control',noCull=True,reference='normal-xy-directional-control'))
    return rows


def model_alpha_sampling_cases():
    rows=[]
    for light in ('directional','spot','point'):
        for renamed in (False,True):
            for label,u,alpha in [('below',.5-1/64,[127,128]),('exact',.5,[127,128]),
                                  ('above',.5+1/64,[127,128]),('one',.5,[255,255])]:
                rows.append(dict(name=f'linear-alpha-{light}-{renamed}-{label}',light=light,
                    renamed=renamed,blending='translucent',linearRGBA8UV=u,textureAlphaBytes=alpha,
                    boundary=label,reference=f'linear-alpha-{light}-{renamed}-one'))
    rows.append(dict(name='linear-alpha-directional-no-receiver',light='directional',
        blending='translucent',linearRGBA8UV=.5,textureAlphaBytes=[255,255],boundary='one',
        noLitReceiver=True,reference='linear-alpha-directional-False-one'))
    return rows


def model_layer_alpha_cases():
    return [dict(name=name, light='directional', normalConsumer=True, normalMode='control',
                 layerAlphaCase=True, noncasterPeers=True, noCull=True, blending='normal',
                 layerAlpha=alpha, opacity=opacity)
            for name, alpha, opacity in [('layer-alpha-zero', 0, 1),
                                         ('layer-alpha-restored', 1, 1),
                                         ('material-opacity-zero-normal', 1, 0)]]


def model_material_coverage_cases():
    common = dict(light='directional', normalConsumer=True, normalMode='control',
                  materialCoverageCase=True, noncasterPeers=True, noCull=True)
    rows = [dict(common, name=name, blending=blend, opacity=cold, writesDepth=False,
                 **({'dynamicOpacity': current} if current is not None else {}))
            for name, blend, cold, current in [('cold1-dynamic0', 'translucent', 1, 0),
                                               ('cold0-dynamic1', 'translucent', 0, 1),
                                               ('additive-zero', 'additive', 0, None)]]
    rows += [dict(common, name=name, blending='normal', missingNamedOpacity=opacity,
                  missingNamedBlend=blend)
             for name, blend, opacity in [('named-zero', 'translucent', 0),
                                           ('named-positive', 'translucent', 1), ('named-normal0', 'normal', 0)]]
    return rows


class SceneModelShadowCameraFamilyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        support = pool_fixture.HARNESS.split('@main', 1)[0] + SHELL + UNUSED_ORDERED_SUPPORT + CULL_MAIN
        cls.coverageCases = model_shadow_coverage_cases()
        cls.normalCases = model_normal_consumer_cases()
        cls.alphaCases = model_alpha_sampling_cases()
        cls.layerAlphaCases = model_layer_alpha_cases()
        cls.materialCoverageCases = model_material_coverage_cases()
        cls.report = shadow_fixture.run_swift(SOURCES, support, label='camera-family-cull',
                    metal_sources=[SCENE/'Rendering/Composition/SceneStaticModel.metal'],
                    input_value={'coverageCases': cls.coverageCases,'normalCases':cls.normalCases,
                                 'alphaSamplingCases':cls.alphaCases,'layerAlphaCases':cls.layerAlphaCases,
                                 'materialCoverageCases':cls.materialCoverageCases})

    def test_real_frame_native_canvas_fitted_and_override_cull_for_three_lights(self):
        self.assertEqual(len(self.report['rows']), 120)
        for row in self.report['rows']:
            native = row['family'] == 'native'
            # Canvas/fitted geometry has the authored-Y reflection. It pairs
            # with CCW admission just as native geometry pairs with CW.
            front_indices = row['family'] in ('native', 'canvas', 'fitted')
            expected = row['noCull'] or (not row['reverse'] if front_indices else row['reverse'])
            self.assertTrue(row['completed'], row)
            self.assertTrue(row['shadowSamplesInBounds'], row)
            if row['light'] == 'directional': self.assertTrue(row['receiverColorEncoded'], row)
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

    def test_real_frame_blended_casters_keep_binary_coverage_and_light_depth_independent(self):
        rows = {row['name']: row for row in self.report['coverageRows']}
        self.assertEqual(set(rows), {case['name'] for case in self.coverageCases})
        for case in self.coverageCases:
            row = rows[case['name']]
            self.assertTrue(row['completed'], row)
            self.assertTrue(row['shadowSamplesInBounds'], row)
            if row['light'] == 'directional': self.assertTrue(row['receiverColorEncoded'], row)
            self.assertTrue(row['nativeCamera'] and row['perspectiveLayer'], row)
            self.assertEqual(row['light'], case['light'])
            self.assertEqual(row['shadowPublished'], case.get('expectedShadow', True), row)
            if not case.get('expectedShadow', True):
                self.assertEqual(row['coverageDepth'], [])
                self.assertEqual(row['peerDepth'], [])
                continue
            self.assertEqual(len(row['peerDepth']), 2, row)
            for depth in row['peerDepth']:
                self.assertGreaterEqual(depth, 0, row)
                self.assertLess(depth, .99, row)
            for covered, depth in zip(case['expected'], row['coverageDepth']):
                if covered:
                    self.assertGreaterEqual(depth, 0, row)
                    self.assertLess(depth, .99, row)
                else:
                    self.assertEqual(depth, 1, row)
        for light in ['directional', 'spot', 'point']:
            self.assertEqual(rows[light+'-normal']['coverageDepth'], rows[light+'-translucent']['coverageDepth'])
            self.assertEqual(rows[light+'-normal']['coverageDepth'][1], rows[light+'-holes']['coverageDepth'][1])
        for name in ['camera-test-off', 'camera-write-off', 'camera-test-write-off', 'additive-covered']:
            self.assertEqual(rows[name]['coverageDepth'], rows['directional-translucent']['coverageDepth'])


    def test_small_texture_frame_keeps_model_color_and_three_shadow_projections(self):
        rows = {row['name']: row for row in self.report['coverageRows']}
        for light in ['directional', 'spot', 'point']:
            reference, tiny = [rows[light+suffix] for suffix in ['-uv-reference', '-uv-tiny']]
            self.assertTrue(reference['shadowSamplesInBounds'] and tiny['shadowSamplesInBounds'])
            self.assertTrue(reference['colorEncoded'] and tiny['colorEncoded'], (reference, tiny))
            self.assertGreater(min(reference['colorRGBA'][:3]), 0, reference)
            self.assertEqual(tiny['colorRGBA'], reference['colorRGBA'])
            self.assertEqual(tiny['coverageDepth'], reference['coverageDepth'])
            self.assertTrue(all(0 <= d < .99 for d in tiny['coverageDepth']), tiny)
            self.assertEqual(tiny['peerDepth'], reference['peerDepth'])
        for name in ['uv-zero', 'uv-nan']:
            row = rows[name]
            self.assertFalse(row['colorEncoded'], row)
            self.assertEqual(row['colorRGBA'], [0, 0, 0, 255])
            self.assertFalse(row['shadowPublished'], row)
            self.assertEqual(row['coverageDepth'], [])
            self.assertEqual(row['peerDepth'], [])

    def test_linear_rgba8_alpha_keeps_sampled_shadow_cutoff_and_camera_coverage(self):
        rows={row['name']:row for row in self.report['alphaRows']}
        self.assertEqual(set(rows),{case['name'] for case in self.alphaCases})
        for case in self.alphaCases:
            row,control=rows[case['name']],rows[case['reference']]
            with self.subTest(case=case['name']):
                self.assertTrue(row['completed'] and row['shadowSamplesInBounds'],row)
                if case.get('noLitReceiver'):
                    self.assertFalse(row['receiverColorEncoded'],row)
                    self.assertFalse(row['shadowPublished'],row)
                    self.assertEqual(row['coverageDepth'],[],row)
                    self.assertEqual(row['peerDepth'],[],row)
                else:
                    self.assertTrue(row['shadowPublished'],row)
                    if row['light']=='directional':self.assertTrue(row['receiverColorEncoded'],row)
                    if case['boundary'] in ('above','one'):
                        self.assertEqual(row['coverageDepth'],control['coverageDepth'],row)
                        self.assertTrue(all(0<=value<.99 for value in row['coverageDepth']),row)
                    else:self.assertEqual(row['coverageDepth'],[1,1],row)
                    self.assertEqual(row['peerDepth'],control['peerDepth'],row)
                    self.assertTrue(all(0<=value<.99 for value in row['peerDepth']),row)
                self.assertEqual(row['peerColorRGBA'],[[255,255,255,255]]*2,row)
                self.assertEqual(row['cameraDepth'],control['cameraDepth'],row)
                self.assertTrue(all(value>0 for value in row['cameraDepth']),row)
                if case['boundary']=='below':
                    self.assertEqual(row['colorRGBA'][3],255,row)
                    for value in row['colorRGBA'][:3]:
                        self.assertGreaterEqual(value,127,row)
                        self.assertLessEqual(value,128,row)
                else:
                    value={'exact':128,'above':128,'one':255}[case['boundary']]
                    self.assertEqual(row['colorRGBA'],[value,value,value,255],row)
                ordinary=rows[case['name'].replace('-True-','-False-')]
                for field in ('coverageDepth','peerDepth','colorRGBA','cameraDepth','peerColorRGBA'):
                    self.assertEqual(row[field],ordinary[field],field)

    def test_zero_layer_alpha_empties_draws_before_shadow_resources_but_not_normal_opacity(self):
        rows = {row['name']: row for row in self.report['layerAlphaRows']}
        self.assertEqual(set(rows), {case['name'] for case in self.layerAlphaCases})
        control = rows['layer-alpha-restored']
        for case in self.layerAlphaCases:
            row = rows[case['name']]
            with self.subTest(case=case['name']):
                self.assertTrue(row['completed'] and row['shadowSamplesInBounds'], row)
                self.assertTrue(row['receiverColorEncoded'], row)
                self.assertEqual(row['peerColorRGBA'], [[255,255,255,255]] * 2, row)
                self.assertEqual(row['cameraDepth'][1:], control['cameraDepth'][1:], row)
                self.assertTrue(all(value > 0 for value in row['cameraDepth'][1:]), row)
                self.assertGreater(row['cameraDepthResidentAfterPrepare'], 0, row)
                self.assertEqual(row['peerDepth'], [], row)
                self.assertEqual(row['namedQueries'], [], row)
                count = 0 if case['layerAlpha'] == 0 else 1
                self.assertEqual(row['candidateSubjectDrawCount'], count, row)
                self.assertEqual(row['preparedSubjectDrawCount'], count, row)
                self.assertEqual(row['subjectDrawAlphas'], [1] * count, row)
                self.assertEqual(row['subjectMaterialOpacities'], [case['opacity']] * count, row)
                if not count:
                    self.assertFalse(row['shadowPublished'], row)
                    self.assertEqual(row['shadowResidentAfterPrepare'], 0, row)
                    self.assertEqual(row['drawMaterialPaths'], [], row)
                    self.assertEqual(row['colorRGBA'], [0,0,0,255], row)
                    self.assertEqual(row['cameraDepth'][0], 0, row)
                    self.assertEqual(row['coverageDepth'], [], row)
                else:
                    self.assertEqual(row['drawMaterialPaths'], [row['unlitMaterialPath']], row)
                    self.assertEqual(row['colorRGBA'], [255,255,255,255], row)
                    self.assertEqual(row['cameraDepth'], control['cameraDepth'], row)
                    self.assertGreater(row['cameraDepth'][0], 0, row)
                    if case['opacity'] == 0:
                        self.assertFalse(row['shadowPublished'], row)
                        self.assertEqual(row['shadowResidentAfterPrepare'], 0, row)
                        self.assertEqual(row['coverageDepth'], [], row)
                    else:
                        self.assertTrue(row['shadowPublished'], row)
                        self.assertGreater(row['shadowResidentAfterPrepare'], 0, row)
                        self.assertEqual(len(row['coverageDepth']), 2, row)
                        self.assertTrue(all(0 <= value < .99 for value in row['coverageDepth']), row)

    def test_rank_two_unlit_planes_keep_actual_color_camera_depth_and_three_shadows(self):
        rows={row['name']:row for row in self.report['normalRows']}
        self.assertEqual(set(rows),{case['name'] for case in self.normalCases})
        for case in self.normalCases:
            if case['normalMode'] not in ('control','rank2'):continue
            row,reference=rows[case['name']],rows[case['reference']]
            with self.subTest(case=case['name']):
                self.assertTrue(row['completed'],row)
                self.assertTrue(row['shadowSamplesInBounds'],row)
                if row['light']=='directional':self.assertTrue(row['receiverColorEncoded'],row)
                self.assertEqual(row['colorRGBA'],[255,255,255,255],row)
                self.assertEqual(row['colorRGBA'],reference['colorRGBA'])
                self.assertGreater(row['cameraDepth'][0],0,row)
                self.assertEqual(row['cameraDepth'],reference['cameraDepth'])
                self.assertEqual(row['coverageDepth'],reference['coverageDepth'])
                self.assertTrue(all(0<=value<.99 for value in row['coverageDepth']),row)
                self.assertEqual(row['peerDepth'],reference['peerDepth'])
                self.assertEqual(row['namedQueries'],[],row)
                if case.get('leaf'):self.assertTrue(row['leafEncoded'],row)
                else:
                    self.assertFalse(row['colorEncoded'],row)  # The real return is encodedLit.
                    self.assertEqual(row['normalMatrices'],[[1,0,0,0,1,0,0,0,1]],row)

    def test_singular_mixed_consumers_and_bad_worlds_keep_independent_peers(self):
        rows={row['name']:row for row in self.report['normalRows']}
        for case in self.normalCases:
            mode=case['normalMode']
            if mode in ('control','rank2'):continue
            row,reference=rows[case['name']],rows[case['reference']]
            with self.subTest(case=case['name']):
                self.assertTrue(row['completed'],row)
                self.assertTrue(row['shadowSamplesInBounds'],row)
                if row['light']=='directional':self.assertTrue(row['receiverColorEncoded'],row)
                self.assertEqual(row['peerColorRGBA'],[[255,255,255,255]]*2,row)
                self.assertTrue(all(value>0 for value in row['cameraDepth'][1:]),row)
                self.assertTrue(all(0<=value<.99 for value in row['peerDepth']),row)
                if mode in ('mixed','mixed-named'):
                    self.assertEqual(row['drawMaterialPaths'],[row['unlitMaterialPath']],row)
                    self.assertEqual(row['normalMatrices'],[[1,0,0,0,1,0,0,0,1]],row)
                    self.assertEqual(row['namedQueries'],[],row)
                    self.assertEqual(row['colorRGBA'],reference['colorRGBA'])
                    self.assertEqual(row['cameraDepth'],reference['cameraDepth'])
                    self.assertEqual(row['coverageDepth'],reference['coverageDepth'])
                elif mode=='mixed-control':
                    self.assertEqual(len(row['drawMaterialPaths']),4,row)
                    self.assertEqual(row['namedQueries'],[],row)
                    self.assertEqual(row['colorRGBA'],reference['colorRGBA'])
                    self.assertEqual(row['cameraDepth'],reference['cameraDepth'])
                    self.assertEqual(row['coverageDepth'],reference['coverageDepth'])
                else:
                    self.assertEqual(row['colorRGBA'],[0,0,0,255],row)
                    self.assertEqual(row['cameraDepth'][0],0,row)
                    self.assertEqual(row['coverageDepth'],[1,1],row)
                    if mode=='nan-world':self.assertEqual(row['drawMaterialPaths'],[],row)


    def test_current_zero_material_coverage_skips_named_work_and_preserves_healthy_parts(self):
        rows = {row['name']: row for row in self.report['materialCoverageRows']}
        self.assertEqual(set(rows), {case['name'] for case in self.materialCoverageCases})
        for case in self.materialCoverageCases:
            row = rows[case['name']]
            named = 'missingNamedOpacity' in case
            active_named = named and case['name'] != 'named-zero'
            visible = named or case['name'] == 'cold0-dynamic1'
            shadow = visible and not active_named
            with self.subTest(case=case['name']):
                self.assertTrue(row['completed'] and row['shadowSamplesInBounds'], row)
                self.assertTrue(row['receiverColorEncoded'], row)
                self.assertEqual(row['peerColorRGBA'], [[255,255,255,255]] * 2, row)
                self.assertTrue(all(value > 0 for value in row['cameraDepth'][1:]), row)
                self.assertEqual(row['peerDepth'], [], row)
                self.assertEqual(row['completeCandidates'], not active_named, row)
                if not active_named:
                    self.assertEqual(row['preparedSubjectDrawCount'], int(visible), row)
                    self.assertEqual(row['candidateSubjectDrawCount'], int(visible), row)
                    self.assertEqual(row['shadowPublished'], shadow, row)
                self.assertEqual(row['drawMaterialPaths'], [row['unlitMaterialPath']] if visible else [], row)
                self.assertEqual(row['subjectDrawAlphas'], [1] if visible else [], row)
                self.assertEqual(row['subjectMaterialOpacities'], [1] if visible else [], row)
                self.assertEqual(row['colorRGBA'], [255,255,255,255] if visible else [0,0,0,255], row)
                self.assertEqual(row['cameraDepth'][0] > 0, named, row)
                if active_named:
                    self.assertEqual(set(row['namedQueries']), {'zero-material-missing-named'}, row)
                else:
                    self.assertEqual(row['namedQueries'], [], row)
                if active_named:
                    continue
                if shadow:
                    self.assertGreater(row['shadowResidentAfterPrepare'], 0, row)
                    self.assertEqual(len(row['coverageDepth']), 2, row)
                    self.assertTrue(all(0 <= value < .99 for value in row['coverageDepth']), row)
                else:
                    self.assertEqual(row['shadowResidentAfterPrepare'], 0, row)
                    self.assertEqual(row['coverageDepth'], [], row)


class SceneZeroOpacityReceiverRoleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        main = (Path(__file__).with_name('fixtures') / 'SceneZeroOpacityReceiverRoleChecks.swift').read_text()
        support = pool_fixture.HARNESS.split('@main', 1)[0] + SHELL + UNUSED_ORDERED_SUPPORT + main
        cls.report = shadow_fixture.run_swift(SOURCES, support, label='zero-opacity-receiver-role',
                         metal_sources=[SCENE/'Rendering/Composition/SceneStaticModel.metal'])
        if cls.report.get('metalUnavailable'):
            raise unittest.SkipTest('Metal device or command queue unavailable')

    def test_zero_opacity_normal_remains_lit_depth_receiver_for_offscreen_caster(self):
        rows = {row['shadowEnabled']: row for row in self.report['rows']}
        self.assertEqual(set(rows), {False, True})
        off, on = rows[False], rows[True]
        for row in rows.values():
            self.assertTrue(row['completed'] and row['casterOutsideCamera'], row)
            self.assertEqual(row['receiverPreparedCount'], 1, row)
            self.assertTrue(row['receiverReceivesLighting'] and row['receiverEncodedLit'], row)
            self.assertEqual(row['receiverMaterialOpacity'], 0, row)
            self.assertEqual(row['receiverLayerAlpha'], 1, row)
            self.assertGreater(row['cameraDepth'], 0, row)
        self.assertEqual(off['RGBA'], [56,56,56,255], off)
        self.assertEqual(on['RGBA'], [32,32,32,255], on)
        self.assertEqual(on['cameraDepth'], off['cameraDepth'])
        self.assertFalse(off['shadowPublished'], off)
        self.assertEqual(off['shadowPoolBytes'], 0, off)
        self.assertEqual(off['shadowPinsBeforeArm'], 0, off)
        self.assertIsNone(off['actualCasterShadowDepth'], off)
        self.assertTrue(on['shadowPublished'], on)
        self.assertGreater(on['shadowPoolBytes'], 0, on)
        self.assertEqual(on['shadowPinsBeforeArm'], 1, on)
        self.assertGreaterEqual(on['actualCasterShadowDepth'], 0, on)
        self.assertLess(on['actualCasterShadowDepth'], 1, on)


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
                         metal_sources=[SCENE/'Rendering/Composition/SceneStaticModel.metal'],
                         swift_flags=('-DDEBUG',))
        cls.rows = {row['mode']: row for row in report['rows']}

    def test_prepared_depth_is_consumed_once_by_both_actual_frame_owners(self):
        row = self.rows['prepared']
        self.assertTrue(row['shadow']);self.assertEqual((row['before'],row['after']),(2,2))
        self.assertEqual(row['modelDepthCount'],1)
        for key in ['sharedIdentity','particleDomainSeparate','particleIdentity','allocationsStable','noRetry','completed','model1','model2','model3']:
            self.assertTrue(row[key], key)
        self.assertEqual(row['pixels'][2],[255,0,255,255])
        self.assertEqual([row['pixels'][0][0],row['pixels'][0][2]],[0,0])
        self.assertGreater(row['pixels'][0][1],0)
        self.assertEqual(row['pixels'][1][:2],[0,0])
        self.assertGreater(row['pixels'][1][2],0)

    def test_optional_physical_quota_failure_preserves_original_model_and_particle_pixels(self):
        row = self.rows['optional-quota']
        self.assertFalse(row['shadow']);self.assertEqual(row['shadowResident'],0)
        self.assertEqual((row['before'],row['after']),(2,2))
        self.assertEqual(row['modelDepthCount'],1)
        for key in ['sharedIdentity','particleDomainSeparate','particleIdentity','allocationsStable','noRetry','model1','model2','model3']:
            self.assertTrue(row[key],key)
        self.assertEqual(row['pixels'][2],[255,0,255,255])
        self.assertEqual(row['pixels'],self.rows['original']['pixels'])
        self.assertTrue(any(max(pixel[:3])>128 for pixel in row['pixels'][:3]))

    def test_failed_mandatory_lease_is_not_retried_after_budget_recovers(self):
        row=self.rows['mandatory-quota']
        self.assertFalse(row['shadow']);self.assertEqual((row['before'],row['after']),(1,1))
        self.assertTrue(row['model1']);self.assertTrue(row['model2']);self.assertTrue(row['model3'])
        self.assertEqual(row['modelDepthCount'],1)
        self.assertEqual(row['pixels'][2],[13,26,38,255])
        self.assertEqual(row['pixels'][0],self.rows['original']['pixels'][0])
        self.assertTrue(row['allocationsStable']);self.assertTrue(row['noRetry']);self.assertTrue(row['particleIdentity'])
        self.assertEqual(row['pixels'][1],self.rows['original']['pixels'][1])


def model_shadow_density_cases():
    directional = [{'kind': 'directional', 'id': 101}]
    four = [{'kind': 'directional', 'id': i} for i in [101, 102, 103, 104]]
    rows = [dict(name=f'extent-{width}', width=width, height=64 if width == 64 else 8,
                 budgetBytes=384 * 1024 * 1024, lights=directional)
            for width in [64, 1024, 1025, 2048, 2049, 4096]]
    rows += [dict(name='height-dominant', width=8, height=1025,
                  budgetBytes=384 * 1024 * 1024, lights=directional),
             dict(name='renamed-extent-2049', width=2049, height=8, layerID=8113,
                  materialPath='surfaces/Π renamed finish',
                  budgetBytes=384 * 1024 * 1024, lights=directional)]
    rows += [dict(name=f'four-budget-{budget}', width=2049, height=8,
                  budgetBytes=budget * 1024 * 1024, lights=four)
             for budget in [16, 12, 384]]
    rows += [dict(name='mixed-with-spot-gap', width=2049, height=8,
                  budgetBytes=384 * 1024 * 1024,
                  lights=[{'kind': kind, 'id': i} for kind, i in
                          [('directional', 101), ('invalid-spot', 102),
                           ('point', 103), ('spot', 104)]]),
             dict(name='unlit-large-pass', width=4096, height=8, lit=False,
                  budgetBytes=384 * 1024 * 1024, lights=directional)]
    return rows


class SceneDirectionalShadowDensityTests(unittest.TestCase):
    """Real Frame/pool outputs; typed lights do not qualify authored light selection."""

    @classmethod
    def setUpClass(cls):
        fixture = Path(__file__).with_name('fixtures') / 'SceneDirectionalShadowDensityChecks.swift'
        support = (pool_fixture.HARNESS.split('@main', 1)[0] + SHELL
                   + UNUSED_ORDERED_SUPPORT + fixture.read_text())
        cls.cases = model_shadow_density_cases()
        report = shadow_fixture.run_swift(SOURCES, support, label='shadow-density',
                    metal_sources=[SCENE/'Rendering/Composition/SceneStaticModel.metal'],
                    input_value=cls.cases, swift_flags=('-DDEBUG',))
        cls.rows = {row['name']: row for row in report['rows']}

    def assert_healthy_color(self, row):
        for key in ['finished', 'completed']:
            self.assertTrue(row[key], row)
        self.assertGreater(max(row['colorRGBA'][:3]), 0, row)
        self.assertEqual(row['colorRGBA'][3], 255, row)

    def assert_maps(self, row, expected):
        actual = [(m['lightID'], m['slots'], m['width'], m['height']) for m in row['maps']]
        self.assertEqual(actual, expected, row)

    def test_actual_receiver_pass_extent_selects_literal_shadow_sizes(self):
        for name, edge in [('extent-64', 1024), ('extent-1024', 1024),
                           ('extent-1025', 2048), ('extent-2048', 2048),
                           ('extent-2049', 4096), ('extent-4096', 4096),
                           ('height-dominant', 2048), ('renamed-extent-2049', 4096)]:
            with self.subTest(case=name):
                row = self.rows[name]
                self.assert_healthy_color(row)
                self.assertTrue(row['colorEncodedLit'], row)
                self.assert_maps(row, [(101, [0], edge, edge)])
                supplied = next(case for case in self.cases if case['name'] == name)
                self.assertEqual(row['physicalExtent'], [supplied['width'], supplied['height']])
        self.assertEqual(self.rows['renamed-extent-2049']['maps'], self.rows['extent-2049']['maps'])
        self.assertEqual(self.rows['renamed-extent-2049']['colorRGBA'], self.rows['extent-2049']['colorRGBA'])

    def test_atomic_upgrade_rejection_retains_original_four_light_partial_prefix(self):
        for name, ids, edge in [('four-budget-16', [101, 102, 103, 104], 1024),
                                ('four-budget-12', [101, 102, 103], 1024),
                                ('four-budget-384', [101, 102, 103, 104], 4096)]:
            with self.subTest(case=name):
                row = self.rows[name]
                self.assert_healthy_color(row)
                self.assertTrue(row['colorEncodedLit'], row)
                self.assert_maps(row, [(i, [slot], edge, edge) for slot, i in enumerate(ids)])
                for actual, upgraded in zip(row['maps'], self.rows['four-budget-384']['maps']):
                    self.assertEqual(actual['matrix'], upgraded['matrix'])

    def test_mixed_projection_sizes_keep_original_slots_after_invalid_spot(self):
        row = self.rows['mixed-with-spot-gap']
        self.assert_healthy_color(row)
        self.assertTrue(row['colorEncodedLit'], row)
        self.assert_maps(row, [(101, [0], 4096, 4096),
                               (103, [2], 3072, 2048), (104, [3], 1024, 1024)])

    def test_no_lit_receiver_keeps_color_without_directional_target(self):
        row = self.rows['unlit-large-pass']
        self.assert_healthy_color(row)
        self.assertFalse(row['colorEncodedLit'], row)
        self.assertEqual(row['maps'], [], row)
        self.assertEqual(row['shadowResidentBytes'], 0, row)


if __name__ == '__main__':
    if '--typecheck' in sys.argv:
        raise SystemExit(typecheck())
    unittest.main()
