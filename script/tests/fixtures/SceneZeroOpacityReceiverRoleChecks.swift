extension SIMD4 where Scalar == Float {var xyz:SIMD3<Float> {SIMD3(x,y,z)}}
@main enum ZeroOpacityReceiverRoleProbe {
 static func main() throws {
  guard let device=MTLCreateSystemDefaultDevice(),let queue=device.makeCommandQueue() else {
   print("{\"metalUnavailable\":true}");return
  }
  let pipeline=SceneStaticModelPipeline(device:device)!
  let td=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:1,height:1,mipmapped:false)
  td.storageMode = .shared;td.usage = .shaderRead
  let white=device.makeTexture(descriptor:td)!
  [UInt8](repeating:255,count:4).withUnsafeBytes {white.replace(region:MTLRegionMake2D(0,0,1,1),mipmapLevel:0,
    withBytes:$0.baseAddress!,bytesPerRow:4)}
  func quad(_ half:Float)->SceneStaticModelMesh {
   let ps=[SIMD3(-half,-half,0),SIMD3(half,-half,0),SIMD3(half,half,0),SIMD3(-half,half,0)]
   let vs=ps.map{SceneMdlStaticModel.Vertex(position:$0,normal:SIMD3(0,0,1),tangent:SIMD4(1,0,0,1),uv:SIMD2(0.5,0.5))}
   return pipeline.makeMesh(model:SceneStaticModelFixture.model(vertices:vs,indices:[0,1,2,0,2,3]))!
  }
  let receiver=quad(1),caster=quad(0.5)
  func material(_ lit:Bool,_ opacity:Float)->SceneStaticModelMaterial {
   var m=SceneStaticModelMaterial(color:SIMD3(repeating:1),opacity:opacity,receivesLighting:lit,
    textureAlphaIsOpacity:true,textureAlphaIsTintMask:false,emissiveColor:.zero,emissiveBrightness:0,
    brightness:1,usesHDRBrightness:false,viewTint:nil)
   m.cullMode = .none;return m
  }
  func entry(_ mesh:SceneStaticModelMesh,_ m:SceneStaticModelMaterial)->ScenePreparedStaticModelResources.Entry {
   .init(materialPath:m.receivesLighting ? "lit-opacity-zero":"positive-unlit-caster",dynamicMaterialPath:"",
    mesh:mesh,albedo:PreparedTexture(texture:white),material:m,writesDepth:true,testsDepth:true,materialBlending:.normal)
  }
  let renderer=SceneMetalRenderer(device:device,resources:.init(pipeline:pipeline,
    entries:[1:[entry(receiver,material(true,0))],2:[entry(caster,material(false,1))]]))
  let descriptor=SceneRenderDescriptor.CameraDescriptor(eye:[0,0,5],center:[0,0,0],up:[0,1,0],
    orthoWidth:nil,orthoHeight:nil,fovDegrees:60,perspectiveOverrideFOVDegrees:nil,nearZ:0.01,farZ:100)
  renderer.renderDescriptor.camera=descriptor
  let camera=SceneParticleCameraFrame(camera:descriptor,viewportSize:CGSize(width:64,height:64))
  let layers=[SceneRenderDescriptor.Layer(id:1,utilityLayer:nil,usesPerspective:true),.init(id:2,utilityLayer:nil,usesPerspective:true)]
  let casterCenter=SIMD3<Float>(3,0,1),toward=simd_normalize(casterCenter)
  let world=[1:matrix_identity_float4x4,2:SceneMatrix.translation(casterCenter)]
  let vp=camera.reverseDepthViewProjection(usesPerspective:true)
  let casterClips=[SIMD3<Float>(-0.5,-0.5,0),SIMD3(0.5,-0.5,0),SIMD3(0.5,0.5,0),SIMD3(-0.5,0.5,0)]
    .map{vp*SIMD4($0+casterCenter,1)}
  let outside=casterClips.allSatisfy{$0.x>$0.w}
  precondition(outside && simd_length(simd_cross(casterCenter,toward))<1e-6)
  let lamp=SceneLightSnapshot.Directional(layerID:7,castsShadow:true,directionTowardLight:toward,color:SIMD3(repeating:1),intensity:1)
  let lighting=SceneLightSnapshot(ambient:SIMD3(repeating:0.25),skylight:.zero,directional:[lamp],point:[],spot:[],overflowCount:0)
  let dynamic=SceneDynamicSnapshot.empty(frameIndex:1,generation:1)
  var rows=[[String:Any]]()
  for enabled in [false,true] {
   let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:64,height:64,mipmapped:false)
   d.storageMode = .shared;d.usage = .renderTarget
   let output=device.makeTexture(descriptor:d)!,cb=queue.makeCommandBuffer()!
   let pass=SceneMainPassEncoder(commandBuffer:cb,target:output,clearColor:MTLClearColorMake(0,0,0,1),clearEnabled:true)
   let pool=SceneOffscreenTexturePool(device:device,pixelFormat:.bgra8Unorm,residentByteBudget:16*1024*1024)
   let state=SceneMetalRenderer.StaticModelFrame(commandBuffer:cb),visible=Set(layers.map(\.id))
   let candidates=renderer.shadowDrawCandidates(orderedLayers:layers,visible:visible,worldFrames:world,snapshot:dynamic,groups:nil)!
   var leases=[SceneParticleDepthTargetLease]()
   renderer.prepareModelShadow(state:state,candidates:candidates,lights:enabled ? [.directional(lamp)]:[],orderedLayers:layers,
    visible:visible,batches:[:],particlePipeline:nil,mainPass:pass,groups:nil,pool:pool,commandBuffer:cb,
    leases:&leases,mandatoryCapacity:{true},recordsEvidence:false,cameraFrame:camera)
   let shadow=state.shadows.first,pinCount=state.pins.count
   let draw=state.prepared![1]!.first!
   let encoded=renderer.drawStaticModel(layer:layers[0],state:state,worldFrames:world,
    frameContext:.init(dynamicValues:dynamic),cameraFrame:camera,lighting:lighting,pass:pass,commandBuffer:cb,leases:&leases)
   _=renderer.drawStaticModel(layer:layers[1],state:state,worldFrames:world,
    frameContext:.init(dynamicValues:dynamic),cameraFrame:camera,lighting:lighting,pass:pass,commandBuffer:cb,leases:&leases)
   precondition(pass.finishEnsuringClear())
   let before=leases.count
   let depth=state.sharedDepth(pass:pass,pool:renderer.staticModelDepthTargetPool,device:device,commandBuffer:cb,leases:&leases).lease!.texture
   precondition(before==leases.count)
   let depthBuffer=device.makeBuffer(length:256,options:.storageModeShared)!,blit=cb.makeBlitCommandEncoder()!
   blit.copy(from:depth,sourceSlice:0,sourceLevel:0,sourceOrigin:.init(x:32,y:32,z:0),sourceSize:.init(width:1,height:1,depth:1),
    to:depthBuffer,destinationOffset:0,destinationBytesPerRow:256,destinationBytesPerImage:256)
   var casterDepthBuffer:MTLBuffer?
   if let shadow,case let .directional(p)=shadow.projection {
    let clip=p.worldToClip*SIMD4(casterCenter,1),map=shadow.texture
    let x=Int((clip.x/clip.w+1)*0.5*Float(map.width)),y=Int((1-clip.y/clip.w)*0.5*Float(map.height))
    precondition(x>=0 && y>=0 && x<map.width && y<map.height)
    let b=device.makeBuffer(length:256,options:.storageModeShared)!
    blit.copy(from:map,sourceSlice:0,sourceLevel:0,sourceOrigin:.init(x:x,y:y,z:0),sourceSize:.init(width:1,height:1,depth:1),
     to:b,destinationOffset:0,destinationBytesPerRow:256,destinationBytesPerImage:256);casterDepthBuffer=b
   }
   blit.endEncoding()
   let published=shadow != nil,resident=pool.residentByteCost
   leases.forEach{$0.arm(on:cb)};state.arm(on:cb);cb.commit();cb.waitUntilCompleted()
   precondition(cb.status == .completed && cb.error == nil)
   var bytes=[UInt8](repeating:0,count:4)
   bytes.withUnsafeMutableBytes{output.getBytes($0.baseAddress!,bytesPerRow:4,from:MTLRegionMake2D(32,32,1,1),mipmapLevel:0)}
   rows.append(["shadowEnabled":enabled,"completed":true,"casterOutsideCamera":outside,
    "receiverPreparedCount":candidates[1]!.count,"receiverReceivesLighting":draw.material.receivesLighting,
    "receiverMaterialOpacity":draw.material.opacity,"receiverLayerAlpha":draw.alpha,"receiverEncodedLit":encoded,
    "RGBA":[bytes[2],bytes[1],bytes[0],bytes[3]],"cameraDepth":depthBuffer.contents().bindMemory(to:Float.self,capacity:1).pointee,
    "shadowPublished":published,"shadowPinsBeforeArm":pinCount,"shadowPoolBytes":resident,
    "actualCasterShadowDepth":casterDepthBuffer.map{$0.contents().bindMemory(to:Float.self,capacity:1).pointee as Any} ?? NSNull(),
    "commandBufferToken":String(UInt(bitPattern:Unmanaged.passUnretained(cb).toOpaque()))])
  }
  print(String(decoding:try JSONSerialization.data(withJSONObject:["rows":rows],options:[.sortedKeys]),as:UTF8.self))
 }
}
