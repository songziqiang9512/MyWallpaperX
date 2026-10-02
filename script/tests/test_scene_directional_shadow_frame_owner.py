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
        'SPOT_LIGHT_SOURCE', 'LIGHT_SOURCE', 'DYNAMIC_SNAPSHOT_SOURCE',
        'DYNAMIC_LAYER_VALUES_SOURCE', 'PIPELINE_SOURCE']),
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
  let ambientColorRGB:[Float]?;let skylightColorRGB:[Float]?;var distanceFog:DistanceFog? = nil
 }
 struct Layer {
  let id:Int;var visible:Bool? = true;var pointLight:ScenePointLightDefinition? = nil
  var spotLight:SceneSpotLightDefinition? = nil;var directionalLight:SceneDirectionalLightDefinition? = nil
  var parentID:Int? = nil;var displayScriptOwnership:SceneLayerDisplayScriptOwnership? = nil
  var utilityLayer:Bool? = false;var usesPerspective:Bool? = false
  var alpha:Double? = 1;var contentKind:String = "model"
  var modelShadowCastIntent:SceneShadowCastIntent? = nil;var colorBlendMode:Int? = nil
 }
 struct CameraDescriptor {
  let eye:[Float];let center:[Float];let up:[Float];let orthoWidth:Float?;let orthoHeight:Float?
  let fovDegrees:Float?;let perspectiveOverrideFOVDegrees:Float?;let nearZ:Float;let farZ:Float
 }
 let lighting:LightingDescriptor?;let layers:[Layer];let renderOrderLayerIDs:[Int]
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
enum SceneLayerColorBlendRenderer {static func supports(_ mode:Int)->Bool {fatalError("unused snapshot-demand shell")}}
final class SceneImageLayerCompositor {
 func prepareSnapshotCapacity(width:Int,height:Int,pixelFormat:MTLPixelFormat,then remaining:()->Bool)->Bool {fatalError("unused snapshot-demand shell")}
}

final class SceneMetalRenderer {
 let device:MTLDevice;let staticModelResources:ScenePreparedStaticModelResources
 var utilityPlansByTriggerLayerID:[Int:[SceneUtilityLayerRuntimePlan]]=[:]
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
  let lighting=SceneLightSnapshot(ambient:SIMD3(repeating:0.5),directional:[light],point:[],spot:[],overflowCount:0)
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
   renderer.prepareModelShadow(state:state,candidates:candidates,light:light,orderedLayers:layers,visible:visible,
      batches:[4:[batch]],particlePipeline:particles,mainPass:pass,groups:nil,pool:pool,commandBuffer:cb,
      leases:&leases,mandatoryCapacity:{true},recordsEvidence:false)
  }
  let before=leases.count
  let shared=state.prepared?[1]?.first?.depth?.lease
  let isolated=state.prepared?[2]?.first?.depth?.lease
  let other=state.prepared?[3]?.first?.depth?.lease
  let preparedParticle=state.particleDepth[4]?.lease
  let published=state.shadow != nil
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
HARNESS = pool_fixture.HARNESS.split('@main', 1)[0] + SHELL + MAIN


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
