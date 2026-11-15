
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
  var coverageRows:[[String:Any]]=[],normalRows:[[String:Any]]=[]
  if CommandLine.arguments.count > 1 {
   let input=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [String:Any]
   for item in input["coverageCases"] as! [[String:Any]] {
    coverageRows.append(try run("native",item["light"] as! String,item["transformed"] as? Bool ?? false,
      item["reverse"] as? Bool ?? false,item["noCull"] as? Bool ?? false,device,queue,coverage:item))
   }
   for item in input["normalCases"] as? [[String:Any]] ?? [] {
    normalRows.append(try run("native",item["light"] as! String,item["transformed"] as? Bool ?? false,
      false,true,device,queue,coverage:item))
   }
  }
  print(String(decoding:try JSONSerialization.data(withJSONObject:["rows":rows,"coverageRows":coverageRows,"normalRows":normalRows],options:[.sortedKeys]),as:UTF8.self))
 }
 static func run(_ family:String,_ type:String,_ transformed:Bool,_ reverse:Bool,_ noCull:Bool,
                 _ device:MTLDevice,_ queue:MTLCommandQueue,coverage:[String:Any]?=nil)throws->[String:Any] {
  let pipeline=SceneStaticModelPipeline(device:device)!
  let native=family.hasPrefix("native")
  let normalConsumer=coverage?["normalConsumer"] as? Bool ?? false
  let yz=coverage?["plane"] as? String == "yz"
  let mode=coverage?["normalMode"] as? String ?? ""
  let cameraDescriptor=SceneRenderDescriptor.CameraDescriptor(eye:yz ? [5,0,0]:[0,0,5],center:[0,0,0],up:[0,1,0],
   orthoWidth:native ? nil:8,orthoHeight:native ? nil:8,fovDegrees:native ? 60:nil,
   perspectiveOverrideFOVDegrees:family=="fitted" ? 60:nil,nearZ:0.01,farZ:100)
  let camera=SceneParticleCameraFrame(camera:cameraDescriptor,viewportSize:CGSize(width:64,height:64))
  var layer=SceneRenderDescriptor.Layer(id:1,utilityLayer:family=="native-utility" ? true:nil,
    usesPerspective:family=="canvas" || family=="native-ortho" ? false:true)
  layer.alpha=coverage?["layerAlpha"] as? Double ?? 1
  if coverage?["castFalse"] as? Bool == true {layer.modelShadowCastIntent = .disabled}
  if coverage?["hidden"] as? Bool == true {layer.visible=false}
  let basePositions:[SIMD3<Float>]=[SIMD3(-1,-1,0),SIMD3(1,-1,0),SIMD3(1,1,0),SIMD3(-1,1,0)]
  let positions=basePositions.map{yz ? SIMD3(0,$0.y,$0.x):$0}
  let vertices=positions.map{SceneMdlStaticModel.Vertex(position:$0,normal:yz ? SIMD3(1,0,0):SIMD3(0,0,1),tangent:SIMD4(1,0,0,1),
    uv:coverage == nil ? SIMD2(repeating:0.5):SIMD2(((yz ? $0.z:$0.x)+1)*0.5,($0.y+1)*0.5))}
  let mesh=pipeline.makeMesh(model: SceneStaticModelFixture.model(vertices:vertices,indices:reverse ? [0,2,1,0,3,2]:[0,1,2,0,2,3]))!
  let td=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:1,height:1,mipmapped:false)
  td.storageMode = .shared;td.usage = .shaderRead
  let white=device.makeTexture(descriptor:td)!,pixel:[UInt8]=[255,255,255,255]
  pixel.withUnsafeBytes{white.replace(region:MTLRegionMake2D(0,0,1,1),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:4)}
  var casterTexture=white
  if let coverage {
   let alpha=coverage["textureAlpha"] as? [Double] ?? [1,1]
   let descriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba32Float,width:2,height:1,mipmapped:false)
   descriptor.storageMode = .shared;descriptor.usage = .shaderRead
   casterTexture=device.makeTexture(descriptor:descriptor)!
   let values:[Float]=[1,1,1,Float(alpha[0]),1,1,1,Float(alpha[1])]
   values.withUnsafeBytes{casterTexture.replace(region:MTLRegionMake2D(0,0,2,1),mipmapLevel:0,
     withBytes:$0.baseAddress!,bytesPerRow:32)}
  }
  func makeMaterial(_ opacity:Float=1,_ mask:Bool=false)->SceneStaticModelMaterial {
   .init(color:SIMD3(repeating:1),opacity:opacity,receivesLighting:!normalConsumer,
    textureAlphaIsOpacity:!mask,textureAlphaIsTintMask:mask,emissiveColor:.zero,emissiveBrightness:0,
    brightness:1,usesHDRBrightness:false,viewTint:nil)
  }
  var material=makeMaterial(Float(coverage?["opacity"] as? Double ?? 1),coverage?["tintMask"] as? Bool ?? false)
  material.cullMode=noCull ? .none:.back
  var textureFrame=SceneTextureUVTransform.identity
  if let scale=coverage?["frameScale"] as? Double {
   let origin=(coverage?["frameOrigin"] as? [Double] ?? [0,0]).map(Float.init)
   textureFrame = .init(origin:SIMD2(origin),xAxis:SIMD2(Float(scale),0),yAxis:SIMD2(0,Float(scale)))
   if coverage?["frameInvalid"] as? String == "nan" {textureFrame = .init(origin:.zero,xAxis:SIMD2(Float.nan,0),yAxis:SIMD2(0,1))}
  }
  let entry=ScenePreparedStaticModelResources.Entry(
   materialPath:coverage?["renamed"] as? Bool == true ? "surfaces/Φ renamed finish":"own-cull",dynamicMaterialPath:"",
   mesh:mesh,albedo:PreparedTexture(texture:casterTexture,uvTransform:textureFrame),material:material,
   writesDepth:coverage?["writesDepth"] as? Bool ?? true,testsDepth:coverage?["testsDepth"] as? Bool ?? true,
   materialBlending:(coverage?["blending"] as? String).flatMap(SceneMaterialRenderState.Blending.init(rawValue:)))
  var entries=[1:[entry]]
  if mode.hasPrefix("mixed") {
   let named=mode == "mixed-named"
   for consumer in ["lit","view","reflection"] {
    var dependent=SceneStaticModelMaterial(color:SIMD3(repeating:1),opacity:1,
      receivesLighting:consumer=="lit",textureAlphaIsOpacity:true,textureAlphaIsTintMask:false,
      emissiveColor:.zero,emissiveBrightness:0,brightness:1,usesHDRBrightness:false,
      viewTint:consumer=="view" ? .init(front:SIMD3(1,0,0),back:SIMD3(0,1,0),exponent:1,usesDynamicBackColor:false):nil)
    dependent.cullMode = .none
    if consumer=="reflection" {dependent.surfaceProfile = .init(metallic:0,roughness:0.7,reflectivity:0.5)}
    entries[1]!.append(.init(materialPath:"dependent-"+consumer,dynamicMaterialPath:"",mesh:mesh,
      albedo:named ? nil:PreparedTexture(texture:white),namedAlbedo:named ? "unavailable-"+consumer:nil,
      material:dependent,materialBlending:.normal))
   }
  }
  var layers=[layer]
  if family=="native" {
   // Native, explicit canvas and utility casters share one encoder/map. Peers
   // use authored canvas front winding; reverse changes submission order too.
   let peerMesh=pipeline.makeMesh(model: SceneStaticModelFixture.model(vertices:vertices,indices:[0,2,1,0,3,2]))!
   var peerMaterial=makeMaterial();peerMaterial.cullMode = normalConsumer ? .none:.back
   for id in [2,3] {
    entries[id]=[.init(materialPath:"own-peer",dynamicMaterialPath:"",
      mesh:peerMesh,albedo:PreparedTexture(texture:white),material:peerMaterial)]
   }
   layers += normalConsumer
    ? [.init(id:2,utilityLayer:nil,usesPerspective:true),.init(id:3,utilityLayer:nil,usesPerspective:true)]
    : [.init(id:2,utilityLayer:nil,usesPerspective:false),.init(id:3,utilityLayer:true,usesPerspective:true)]
   if reverse {layers.reverse()}
  }
  let renderer=SceneMetalRenderer(device:device,resources:.init(pipeline:pipeline,entries:entries))
  renderer.renderDescriptor.camera=cameraDescriptor
  var world=transformed ? SceneMatrix.eulerXYZ(SIMD3(0.2,-0.3,0.1))*SceneMatrix.scale(SIMD3(1.1,0.8,1.2)):matrix_identity_float4x4
  if transformed && !normalConsumer {world.columns.3=SIMD4(2,-3,-4,1)}
  if coverage?["mirror"] as? Bool == true {world=world*SceneMatrix.scale(SIMD3(1,-1,1))}
  let controlWorld=world
  if mode=="rank2" || mode=="mixed" || mode=="mixed-named" {world=world*SceneMatrix.scale(yz ? SIMD3(0,1,1):SIMD3(1,1,0))}
  if mode=="all-zero" {world.columns=(.zero,.zero,.zero,.zero)}
  if mode=="nan-world" {world.columns.3.x = .nan}
  let sourceNormal:SIMD4<Float> = yz ? SIMD4(4,0,0,1):SIMD4(0,0,4,1)
  let center=(normalConsumer ? controlWorld:world).columns.3.xyz
  let position=((normalConsumer ? controlWorld:world)*sourceNormal).xyz
  let toward=simd_normalize(position-center)
  let light:SceneLightSnapshot.ShadowLight
  if type=="directional" {light = .directional(.init(layerID:7,castsShadow:true,directionTowardLight:toward,color:SIMD3(repeating:1),intensity:1))}
  else if type=="spot" {light = .spot(.init(layerID:7,castsShadow:true,position:position,directionFromLight:-toward,
    color:SIMD3(repeating:1),intensity:1,radius:10,innerConeCosine:cos(.pi/6),outerConeCosine:cos(.pi/4),outerConeDegrees:45))}
  else {light = .point(.init(layerID:7,castsShadow:true,position:position,color:SIMD3(repeating:1),intensity:1,radius:10))}
  let outDesc=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:64,height:64,mipmapped:false)
  outDesc.storageMode = coverage?["frameScale"] == nil && !normalConsumer ? .private:.shared;outDesc.usage = .renderTarget
  let output=device.makeTexture(descriptor:outDesc)!,cb=queue.makeCommandBuffer()!
  let pass=SceneMainPassEncoder(commandBuffer:cb,target:output,clearColor:MTLClearColorMake(0,0,0,1),clearEnabled:true)
  let pool=SceneOffscreenTexturePool(device:device,pixelFormat:.bgra8Unorm,residentByteBudget:32*1024*1024)
  let state=SceneMetalRenderer.StaticModelFrame(commandBuffer:cb),dynamic=SceneDynamicSnapshot.empty(frameIndex:1,generation:1)
  var worlds=[1:world]
  for (id,x) in [(2,Float(3)),(3,Float(-3))] where entries[id] != nil {
   let offset=normalConsumer ? x*0.6:x
   worlds[id]=(normalConsumer ? controlWorld:world)*SceneMatrix.translation(yz ? SIMD3(0,0,offset):SIMD3(offset,0,0))
  }
  let visible=Set(layers.filter{$0.visible != false}.map(\.id))
  let candidates=renderer.shadowDrawCandidates(orderedLayers:layers,visible:visible,worldFrames:worlds,snapshot:dynamic,groups:nil)!
  var leases:[SceneParticleDepthTargetLease]=[]
  renderer.prepareModelShadow(state:state,candidates:candidates,lights:[light],orderedLayers:layers,visible:visible,batches:[:],
   particlePipeline:nil,mainPass:pass,groups:nil,pool:pool,commandBuffer:cb,leases:&leases,
   mandatoryCapacity:{true},recordsEvidence:false,cameraFrame:camera)
  let shadow=state.shadows.first
  var colorEncoded:Bool?=nil
  var leafEncoded:Bool?=nil,normalDraws:[SceneMetalRenderer.StaticModelDraw]=[]
  var cameraDepthBuffers:[MTLBuffer]=[]
  if coverage?["frameScale"] != nil || normalConsumer {
   let ambient=SceneLightSnapshot(ambient:SIMD3(repeating:0.25),skylight:.zero,directional:[],point:[],spot:[],overflowCount:0)
   if normalConsumer {normalDraws=renderer.staticModelDraws(layer:layer,worldFrames:worlds,snapshot:dynamic) ?? []}
   if coverage?["leaf"] as? Bool == true {
    _=state.sharedDepth(pass:pass,pool:renderer.staticModelDepthTargetPool,device:device,commandBuffer:cb,leases:&leases)
    let encoder=state.sceneDepthEncoder(pass:pass,commandBuffer:cb)!
    leafEncoded=pipeline.draw(mesh:mesh,texture:casterTexture,colorTextureIsPremultiplied:false,modelMatrix:world,
      viewProjection:pass.rasterClipProjection(camera.reverseDepthViewProjection(usesPerspective:true)),
      frontFacing:pass.rasterFrontFacing,cameraPosition:camera.perspectiveEyePosition,
      textureFrame:.identity,sampling:.directImageFallback,layerAlpha:1,material:material,
      lighting:ambient,writesDepth:true,encoder:encoder)
   } else {
    colorEncoded=renderer.drawStaticModel(layer:layer,state:state,worldFrames:worlds,
     frameContext:.init(dynamicValues:dynamic),cameraFrame:camera,lighting:ambient,
     pass:pass,commandBuffer:cb,leases:&leases)
   }
   if normalConsumer {
    for peer in layers where peer.id != 1 {
     _=renderer.drawStaticModel(layer:peer,state:state,worldFrames:worlds,
       frameContext:.init(dynamicValues:dynamic),cameraFrame:camera,lighting:ambient,
       pass:pass,commandBuffer:cb,leases:&leases)
    }
   }
   precondition(pass.finishEnsuringClear())
   if normalConsumer {
    let depth=state.sharedDepth(pass:pass,pool:renderer.staticModelDepthTargetPool,device:device,commandBuffer:cb,leases:&leases).lease!.texture
    let blit=cb.makeBlitCommandEncoder()!,vp=camera.reverseDepthViewProjection(usesPerspective:true)
    for point in [controlWorld.columns.3.xyz]+[2,3].map({worlds[$0]!.columns.3.xyz}) {
     let clip=vp*SIMD4(point,1),xy=SIMD2(clip.x,clip.y)/clip.w
     let x=Int((xy.x+1)*32),y=Int((1-xy.y)*32),buffer=device.makeBuffer(length:256,options:.storageModeShared)!
     blit.copy(from:depth,sourceSlice:0,sourceLevel:0,sourceOrigin:.init(x:x,y:y,z:0),sourceSize:.init(width:1,height:1,depth:1),
       to:buffer,destinationOffset:0,destinationBytesPerRow:256,destinationBytesPerImage:256)
     cameraDepthBuffers.append(buffer)
    }
    blit.endEncoding()
   }
  }
  var buffers:[MTLBuffer]=[]
  if let shadow {
  let map=shadow.texture,blit=cb.makeBlitCommandEncoder()!
  let points:[SIMD3<Float>] = coverage == nil ? worlds.keys.sorted().map{worlds[$0]!.columns.3.xyz}
    : [-Float(0.5),Float(0.5)].map { x in
        ((normalConsumer ? controlWorld:world)*(yz ? SIMD4(0,0,x,1):SIMD4(x,0,0,1))).xyz }
      + worlds.keys.sorted().filter{$0 != 1}.map{worlds[$0]!.columns.3.xyz}
  for point in points {
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
  blit.endEncoding()
  }
  leases.forEach{$0.arm(on:cb)};state.arm(on:cb);cb.commit();cb.waitUntilCompleted()
  precondition(cb.status == .completed && cb.error == nil)
  let depths=buffers.map{$0.contents().bindMemory(to:Float.self,capacity:1).pointee}
  var result:[String:Any] = ["family":family,"light":type,"transformed":transformed,"reverse":reverse,"noCull":noCull,
   "nativeCamera":camera.defaultsToPerspective,"perspectiveLayer":camera.resolvesPerspective(for:layer),
   "depth":depths.first.map{$0 as Any} ?? NSNull(),"peerDepth":Array(depths.dropFirst(coverage == nil ? 1:2)),
   "shadowPublished":shadow != nil,"completed":true]
  if let coverage {result["name"]=coverage["name"]!;result["coverageDepth"]=Array(depths.prefix(2))}
  if colorEncoded != nil || normalConsumer {
   var pixel=[UInt8](repeating:0,count:4)
   pixel.withUnsafeMutableBytes{output.getBytes($0.baseAddress!,bytesPerRow:4,from:.init(origin:.init(x:32,y:32,z:0),size:.init(width:1,height:1,depth:1)),mipmapLevel:0)}
   if let colorEncoded {result["colorEncoded"]=colorEncoded}
   result["colorRGBA"]=[pixel[2],pixel[1],pixel[0],pixel[3]]
  }
  if normalConsumer {
   var peerColors:[[Int]]=[]
   let vp=camera.reverseDepthViewProjection(usesPerspective:true)
   for id in [2,3] {
    let clip=vp*SIMD4(worlds[id]!.columns.3.xyz,1),xy=SIMD2(clip.x,clip.y)/clip.w
    var pixel=[UInt8](repeating:0,count:4)
    pixel.withUnsafeMutableBytes { output.getBytes($0.baseAddress!,bytesPerRow:4,
      from:.init(origin:.init(x:Int((xy.x+1)*32),y:Int((1-xy.y)*32),z:0),size:.init(width:1,height:1,depth:1)),mipmapLevel:0) }
    peerColors.append([Int(pixel[2]),Int(pixel[1]),Int(pixel[0]),Int(pixel[3])])
   }
   result["cameraDepth"]=cameraDepthBuffers.map{$0.contents().bindMemory(to:Float.self,capacity:1).pointee}
   result["peerColorRGBA"]=peerColors;result["namedQueries"]=renderer.dependencyRuntime.namedQueries
   result["drawMaterialPaths"]=normalDraws.map{$0.entry.materialPath};result["unlitMaterialPath"]=entry.materialPath
   result["normalMatrices"]=normalDraws.map{ d in (0..<3).flatMap { i in [d.normalMatrix[i].x,d.normalMatrix[i].y,d.normalMatrix[i].z] } }
   if let leafEncoded {result["leafEncoded"]=leafEncoded}
  }
  return result
 }
}
