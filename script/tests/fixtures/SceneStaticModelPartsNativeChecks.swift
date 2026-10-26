import Foundation
import Metal
import simd

@main enum PartsResourceProbe {
 static func main() throws {
  guard let device=MTLCreateSystemDefaultDevice(),let queue=device.makeCommandQueue() else {fatalError("Metal unavailable")}
  let input=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [String:String]
  let root=URL(fileURLWithPath:input["root"]!)
  var rows:[[String:Any]]=[]
  for (name,fixture) in [("parts5","parts5"),("parts8","parts8"),("parts64","parts64"),
                          ("spelled","spelled"),
                          ("parts65","parts65"),("renamed65","renamed65"),("equivalent65","equivalent65"),
                          ("latebad65","latebad65"),("long-dots","long-dots"),("long-pkg","long-pkg"),
                          ("long-dots-pkg-bad","long-dots-pkg-bad"),
                          ("parts65-shadow","parts65-shadow"),("parts65-shadow-false","parts65-shadow"),
                          ("bad8","bad8"),("quota","parts8"),("recovery","parts8"),("snapshot","parts8"),("overlap","overlap"),
                          ("defaults","defaults"),("emission","emission"),
                          ("blends","blends"),("blends-false","blends") ] {
   let before=SceneResourceBudget.shared.snapshot.residentBytes
   var row=try autoreleasepool {try run(name,root.appendingPathComponent(fixture),device,queue)}
   row["budgetBefore"]=before;row["budgetAfter"]=SceneResourceBudget.shared.snapshot.residentBytes
   rows.append(row)
  }
  let basis=try SceneStaticModelVertexBasisChecks.run(root:root,device:device,queue:queue)
  let attachments=try SceneStaticModelAnimationAttachmentChecks.run(root:root,device:device)
  let selection=try SceneStaticModelMaterialSelectionChecks.run(root:root,device:device)
  print(String(decoding:try JSONSerialization.data(withJSONObject:["rows":rows,"basis":basis,"attachments":attachments,"selection":selection]),as:UTF8.self))
 }
 static func materialPass(_ path:String,_ pass:[String:Any]) -> SceneRenderDescriptor.MaterialPassDescriptor {
   let constants=(pass["constantshadervalues"] as? [String:Any] ?? [:]).mapValues { raw in
       let wrapper=raw as? [String:Any];let value=wrapper?["value"] ?? raw
       return SceneDocument.ShaderValue(components:(value as? [Double]) ?? [(value as! NSNumber).doubleValue],
           userBinding:wrapper?["user"] as? String,scriptSource:wrapper?["script"] as? String)
   }
   var result = SceneRenderDescriptor.MaterialPassDescriptor(materialPath:path,
       textureSlots:(pass["textures"] as? [Any] ?? []).map{$0 as? String},
       combos:pass["combos"] as! [String:Int],constantShaderValues:constants,depthWrite:pass["depthwrite"] as? String)
   result.staticModelDefaultAlbedoAssetPath = pass["defaultAlbedo"] as? String
   result.blending = pass["blending"] as? String
   if pass["rejectedMaterial"] as? Bool == true {
       result.staticModelMaterialBindings = .init(state:.rejected,bindings:[],rejectionReason:"fixture-rejected-value")
   }
   return result
 }
 static func run(_ mode:String,_ root:URL,_ device:MTLDevice,_ queue:MTLCommandQueue)throws->[String:Any] {
  let looseRoot=SceneResourceView.Root(source:.loose,url:root)
  let packageRoot:SceneResourceView.Root?
  if let handle=try looseRoot.existingLiteralHandle(relativePath:"scene.pkg") {
   let opened=try looseRoot.openPackage(handle,limits:.compatibility)
   packageRoot=try .package(openedPackage:opened)
  } else {packageRoot=nil}
  let resourceView=SceneResourceView(projectRoot:looseRoot,packageRoot:packageRoot,stockRoot:nil)
  let scene=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("scene.json"))) as! [String:Any]
  let general=scene["general"] as! [String:Any], projection=general["orthogonalprojection"] as! [String:Any]
  let height=(projection["height"] as! NSNumber).intValue
  let handoffURL=root.appendingPathComponent("builder-handoff.json")
  let handoff: [String:Any]? = FileManager.default.fileExists(atPath:handoffURL.path)
      ? try JSONSerialization.jsonObject(with:Data(contentsOf:handoffURL)) as? [String:Any] : nil
  var materialReads:[String]=[]
  let passes:[SceneRenderDescriptor.MaterialPassDescriptor]
  if let handoff {
   precondition((handoff["canvasHeight"] as! Int)==height)
   passes=try (handoff["allPasses"] as! [[String:Any]]).map { value in
    let path=value["material"] as! String
    let bytes=try resourceView.resolvedResource(relativePath:path)!.readBytes()
    precondition([UInt8](bytes)==(value["materialBytes"] as! [UInt8]),"Builder/native selected different material bytes")
    materialReads.append(path)
    var pass:[String:Any]=["textures":value["textures"]!,"combos":value["combos"]!,
        "constantshadervalues":value["constants"]!]
    for (field,key) in [("depthwrite","depthWrite"),("blending","blending"),("defaultAlbedo","defaultAlbedo")] {
     if let text=value[key] as? String,!text.isEmpty {pass[field]=text}
    }
    pass["rejectedMaterial"]=(value["bindingState"] as? String)=="rejected"
    var result=materialPass(path,pass)
    result.passIndex=value["passIndex"] as! Int
    result.shaderPath=(value["shaderPath"] as? String).flatMap{$0.isEmpty ? nil:$0}
    result.cullMode=(value["cullMode"] as? String).flatMap{$0.isEmpty ? nil:$0}
    return result
   }
  } else {
   let files=try FileManager.default.contentsOfDirectory(at:root.appendingPathComponent("materials"),includingPropertiesForKeys:nil).filter{$0.pathExtension=="json"}
   passes=try files.map {url in
    let object=try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as! [String:Any]
    return materialPass("materials/"+url.lastPathComponent,(object["passes"] as! [[String:Any]])[0])
   }
  }
  var layers:[SceneRenderDescriptor.Layer]
  if let handoff {
   layers=(handoff["layers"] as! [[String:Any]]).map { value in
    var layer=SceneRenderDescriptor.Layer(id:value["id"] as! Int,staticModelPath:value["modelPath"] as? String)
    layer.originXYZ=(value["origin"] as! [NSNumber]).map(\.floatValue)
    layer.scaleXYZ=(value["scale"] as! [NSNumber]).map(\.floatValue)
    if value["castsShadow"] as? Bool == false {layer.modelShadowCastIntent = .disabled}
    return layer
   }
  } else {
   layers=[SceneRenderDescriptor.Layer(id:1,staticModelPath:"models/peer.mdl"),.init(id:2,staticModelPath:"models/parts.mdl")]
   for index in layers.indices {layers[index].originXYZ=[0,Float(height),0];layers[index].scaleXYZ=[1,-1,1]}
  }
  if mode=="blends-false" || mode=="parts65-shadow-false" {layers[layers.firstIndex{$0.id==2}!].modelShadowCastIntent = .disabled}
  var descriptor=SceneRenderDescriptor(lighting:nil,layers:layers,renderOrderLayerIDs:layers.map(\.id),materialPasses:passes)
  descriptor.camera = .init(eye:[0,0,0],center:[0,0,-1],up:[0,1,0],orthoWidth:160,
      orthoHeight:Float(height),fovDegrees:nil,perspectiveOverrideFOVDegrees:nil,nearZ:0.01,farZ:1000)
  let loader=try SceneTextureLoader(root:root,device:device)
  let meshCost=device.heapBufferSizeAndAlign(length:4*MemoryLayout<SceneMdlStaticModel.Vertex>.stride,options:.storageModeShared).size
       + device.heapBufferSizeAndAlign(length:6*MemoryLayout<UInt32>.stride,options:.storageModeShared).size
  let rejectionBefore=SceneResourceBudget.shared.snapshot.rejectionCount
  var held=0
  if mode=="quota" {
   held=SceneResourceBudget.shared.maximumBytes-SceneResourceBudget.shared.snapshot.residentBytes-3*meshCost
   precondition(SceneResourceBudget.shared.reserve(held,kind:.gpu))
  }
  defer {if held>0 {SceneResourceBudget.shared.release(held,kind:.gpu)}}
  var preparedSources=try prepareModelSources(descriptor,view:resourceView)
  let modelDirectory=root.appendingPathComponent("models")
  let movedModels=root.appendingPathComponent("models-after-capture")
  if mode=="snapshot" {try FileManager.default.moveItem(at:modelDirectory,to:movedModels)}
  defer {if mode=="snapshot" {try! FileManager.default.moveItem(at:movedModels,to:modelDirectory)}}
  let resources=try ScenePreparedStaticModelResources.prepare(descriptor:descriptor,resourceView:resourceView,device:device,
      textureLoader:loader,preparedSources:&preparedSources,cancellationCheck:{})
  precondition(preparedSources.isEmpty,"GPU owner must consume the transient CPU inputs")
  let rejected=SceneResourceBudget.shared.snapshot.rejectionCount-rejectionBefore
  if held>0 {SceneResourceBudget.shared.release(held,kind:.gpu);held=0}
  let renderer=SceneMetalRenderer(device:device,resources:resources)
  renderer.renderDescriptor=descriptor
  let dynamic=SceneDynamicSnapshot.empty(frameIndex:1,generation:1)
  let world=SceneLayerWorldFrameResolver.compute(descriptor:descriptor,
      byID:Dictionary(uniqueKeysWithValues:layers.map{($0.id,$0)}))
  let camera=SceneParticleCameraFrame(camera:.init(eye:[0,0,0],center:[0,0,-1],up:[0,1,0],orthoWidth:160,
      orthoHeight:Float(height),fovDegrees:nil,perspectiveOverrideFOVDegrees:nil,nearZ:0.01,farZ:1000),viewportSize:CGSize(width:160,height:height))
  let lighting=SceneLightSnapshot(ambient:.zero,skylight: .zero,directional:[],point:[],spot:[],overflowCount:0)
  let td=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:160,height:height,mipmapped:false)
  td.storageMode = .shared;td.usage=[.renderTarget,.shaderRead]
  let target=device.makeTexture(descriptor:td)!
  var shadowDepths:[[Float]]=[]
  if mode.hasPrefix("blends") || mode.hasPrefix("parts65-shadow") {
   for kind in (mode.hasPrefix("blends") ? ["directional","spot","point"]:["directional"]) {
    let light:SceneLightSnapshot.ShadowLight
    if kind=="directional" {light = .directional(.init(layerID:7,castsShadow:true,directionTowardLight:SIMD3(0,0,1),color:SIMD3(repeating:1),intensity:1))}
    else if kind=="spot" {light = .spot(.init(layerID:7,castsShadow:true,position:SIMD3(40,8,100),directionFromLight:SIMD3(0,0,-1),color:SIMD3(repeating:1),intensity:1,radius:200,innerConeCosine:0.9,outerConeCosine:cos(.pi/4),outerConeDegrees:45))}
    else {light = .point(.init(layerID:7,castsShadow:true,position:SIMD3(40,8,100),color:SIMD3(repeating:1),intensity:1,radius:200))}
    let cb=queue.makeCommandBuffer()!
    let state=SceneMetalRenderer.StaticModelFrame(commandBuffer:cb)
    let pass=SceneMainPassEncoder(commandBuffer:cb,target:target,clearColor:MTLClearColorMake(0,0,0,1),clearEnabled:true)
    let pool=SceneOffscreenTexturePool(device:device,pixelFormat:.bgra8Unorm,residentByteBudget:64*1024*1024)
    var leases:[SceneParticleDepthTargetLease]=[]
    let visible=Set(layers.map(\.id))
    let candidates=renderer.shadowDrawCandidates(orderedLayers:layers,visible:visible,worldFrames:world,snapshot:dynamic,groups:nil)!
    renderer.prepareModelShadow(state:state,candidates:candidates,lights:[light],orderedLayers:layers,visible:visible,batches:[:],particlePipeline:nil,mainPass:pass,groups:nil,pool:pool,commandBuffer:cb,leases:&leases,mandatoryCapacity:{true},recordsEvidence:false,cameraFrame:camera)
    let shadow=state.shadows.first!,map=shadow.texture,blit=cb.makeBlitCommandEncoder()!
    var buffers:[MTLBuffer]=[]
    let draws=renderer.staticModelDraws(layer:layers.first{$0.id==2}!,worldFrames:world,snapshot:dynamic)!
    for (index,part) in resources[2]!.enumerated() {
     let local=(part.mesh.boundsMinimum+part.mesh.boundsMaximum)*0.5
     let mapped=draws[index].world*SIMD4(local,1)
     let point=mode.hasPrefix("parts65-shadow") ? SIMD3(mapped.x,mapped.y,mapped.z)/mapped.w:local
     let clip:SIMD3<Float>,face:Int
     switch shadow.projection {
     case .directional(let p):let q=p.worldToClip*SIMD4(point,1);clip=SIMD3(q.x,q.y,q.z);face=0
     case .spot(let p):let q=p.worldToLight*SIMD4(point-p.position,0);clip=SIMD3(q.x/(q.z*p.tanHalfAngle),q.y/(q.z*p.tanHalfAngle),0);face=0
     case .point(let p):let ray=point-p.position;face=5;let q=ScenePointShadowProjection.worldToFaces[face]*SIMD4(ray,0);clip=SIMD3(q.x/q.z,q.y/q.z,0)
     }
     let v=shadow.projection.viewport(face:face,width:map.width,height:map.height)
     let x=Int(v.originX+(Double(clip.x)+1)*v.width*0.5),y=Int(v.originY+(1-Double(clip.y))*v.height*0.5)
     precondition(x>=0 && x<map.width && y>=0 && y<map.height)
     let buffer=device.makeBuffer(length:256,options:.storageModeShared)!
     blit.copy(from:map,sourceSlice:0,sourceLevel:0,sourceOrigin:.init(x:x,y:y,z:0),sourceSize:.init(width:1,height:1,depth:1),to:buffer,destinationOffset:0,destinationBytesPerRow:256,destinationBytesPerImage:256)
     buffers.append(buffer)
    }
    blit.endEncoding();precondition(pass.finishEnsuringClear())
    leases.forEach{$0.arm(on:cb)};state.arm(on:cb);cb.commit();cb.waitUntilCompleted()
    precondition(cb.status == .completed && cb.error == nil)
    shadowDepths.append(buffers.map{$0.contents().bindMemory(to:Float.self,capacity:1).pointee})
   }
  }
  let gridCount=height>128 ? 65:64
  var frames:[[[Int]]]=[],peerFrames:[[Int]]=[],overlapFrames:[[Int]]=[]
  var leaseCounts:[Int]=[]
  for _ in 0..<2 {
   let cb=queue.makeCommandBuffer()!
   let pass=SceneMainPassEncoder(commandBuffer:cb,target:target,clearColor:MTLClearColorMake(0,0,0,1),clearEnabled:true)
   let state=SceneMetalRenderer.StaticModelFrame(commandBuffer:cb);var leases:[SceneParticleDepthTargetLease]=[]
   for layer in layers {
    _=renderer.drawStaticModel(layer:layer,state:state,worldFrames:world,frameContext:.init(dynamicValues:dynamic),cameraFrame:camera,
       lighting:lighting,pass:pass,commandBuffer:cb,leases:&leases)
   }
   precondition(pass.finishEnsuringClear());leaseCounts.append(leases.count)
   leases.forEach{$0.arm(on:cb)};state.arm(on:cb);cb.commit();cb.waitUntilCompleted()
   precondition(cb.status == .completed && cb.error == nil)
   var bytes=[UInt8](repeating:0,count:160*height*4)
   target.getBytes(&bytes,bytesPerRow:160*4,from:MTLRegionMake2D(0,0,160,height),mipmapLevel:0)
   func rgba(_ x:Int,_ y:Int)->[Int] {let i=(y*160+x)*4;return [Int(bytes[i+2]),Int(bytes[i+1]),Int(bytes[i]),Int(bytes[i+3])]}
   frames.append((0..<gridCount).map{rgba(($0%8)*16+8,($0/8)*16+8)})
   peerFrames.append(rgba(146,10));overlapFrames.append(rgba(32,32))
  }
  let parts=resources[2] ?? []
  let row:[String:Any]=["mode":mode,"parts":parts.map(\.materialPath),
      "materials":parts.map{[$0.material.color.x,$0.material.color.y,$0.material.color.z,$0.material.opacity]},
      "materialBlending":parts.map{$0.materialBlending?.rawValue ?? "unresolved"},"shadowDepths":shadowDepths,
      "textureIDs":parts.map{String(describing:$0.albedo!.identity)},
      "maskIDs":parts.map{$0.emissiveMask.map{String(describing:$0.identity)} ?? ""},
      "maskPurposes":parts.map{$0.emissiveMask.map{String(describing:$0.purpose)} ?? ""},
      "emissionSeeds":parts.map{$0.material.emissiveBrightness},"textureRequests":loader.requests,
      "meshIndexCounts":parts.map{$0.mesh.indexCount},"peerParts":resources[1]?.count ?? 0,"rejections":rejected,
      "frames":frames,"peerFrames":peerFrames,"overlapFrames":overlapFrames,
      "canvasHeight":height,"gridCount":gridCount,"builderLinks":handoff?["links"] ?? [],
      "nativeMaterialReads":materialReads,"leaseCounts":leaseCounts,"completed":true,"encoded":renderer.dependencyRuntime.encoded[2] ?? false]
  return row
 }
}
