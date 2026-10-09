
nonisolated enum SceneResolvedMaterialExecutionCapabilityCatalog {struct Token:Hashable {}}
struct FixtureSource {let texture:MTLTexture;let candidate:SceneTextureCandidate;var usesAuthoredLayerColor:Bool=true}
struct SceneLayerParallax {struct Configuration {}}
struct SceneEffectExecutionFrameTrace {
 enum Outcome {case failed(reasonCode:String)}
 func recordRouteOperation(layerID:Int,origin:String,operation:String,outcome:Outcome) {fatalError("unexpected invalid test input")}
}
final class SceneMetalRenderer {
 let device:MTLDevice;let staticModelResources:ScenePreparedStaticModelResources
 var utilityExecution=SceneUtilityLayerRuntimePlanner.Execution()
 var layersByID:[Int:SceneRenderDescriptor.Layer]=[:]
 let imageCompositor=SceneImageLayerCompositor()
 let staticModelDepthTargetPool=SceneParticleDepthTargetPool()
 let dependencyRuntime:SceneDependencyFrameRuntime;let textureRegistry=SceneFrameTextureRegistry()
 init(device:MTLDevice,resources:ScenePreparedStaticModelResources,descriptor:SceneRenderDescriptor) {
  self.device=device;staticModelResources=resources
  dependencyRuntime=SceneDependencyFrameRuntime(descriptor:descriptor,visibleLayerIDs:Set(descriptor.layers.filter{$0.visible != false}.map(\.id)),executableUtilityConsumerLayerIDs:[],device:device)
  layersByID=Dictionary(uniqueKeysWithValues:descriptor.layers.map{($0.id,$0)})
 }
 static func effectExecutionOrigin(for kind:String)->String {kind}
 func baseMaterialReadyProviderUsesAuthoredLayerColor(for layer:SceneRenderDescriptor.Layer,dynamicValues:SceneDynamicSnapshot)->Bool {true}
 func baseMaterialTextureSelection(for layer:SceneRenderDescriptor.Layer,imageTextures:SceneBaseImageTextureSnapshot,readyProviderUsesAuthoredLayerColor:Bool)->FixtureImageSelection {
  .init(source:imageTextures.sources[layer.id])
 }
 // Prepared source/pose adapter only. The actual dependency runtime below
 // owns allocation, capture, publication, missing/invalid outcome and reuse.
 // Dynamic value resolution and full forward graph routing are App/G3 scope.
 func captureRawDependencyProvider(layer:SceneRenderDescriptor.Layer,source:FixtureSource?,
  imageTextures:SceneBaseImageTextureSnapshot,imagePipeline:SceneImageLayerPipeline,
  frameContext:SceneFrameContext,worldFrames:[Int:simd_float4x4],cameraFrame:SceneParticleCameraFrame,
  parallax:SceneLayerParallax.Configuration,viewportSize:CGSize,mainPass:SceneMainPassEncoder,
  preparesCapacityOnly:Bool=false)->SceneGraphOutputPublicationResult? {
  if preparesCapacityOnly {
   return dependencyRuntime.prepareCaptureCapacity(layer:layer,sourceTexture:source?.texture,
    sourceCandidate:source?.candidate,layerMVP:worldFrames[layer.id] ?? matrix_identity_float4x4,viewportSize:viewportSize,
    textureRegistry:textureRegistry) ? nil : .unavailable(reasonCode:"fixture-capacity-unavailable")
  }
  return dependencyRuntime.captureProviderIfRequired(layer:layer,sourceTexture:source?.texture,
   sourceCandidate:source?.candidate,providerAlpha:Float(layer.alpha ?? 1),
   layerMVP:worldFrames[layer.id] ?? matrix_identity_float4x4,viewportSize:viewportSize,pipeline:imagePipeline,
   textureRegistry:textureRegistry,mainPass:mainPass)
 }
 func compositionScratchDimensions(for layer:SceneRenderDescriptor.Layer,pool:SceneOffscreenTexturePool,
  imageTextures:SceneBaseImageTextureSnapshot,frameContext:SceneFrameContext,worldFrames:[Int:simd_float4x4],
  cameraFrame:SceneParticleCameraFrame,parallax:SceneLayerParallax.Configuration)->[(width:Int,height:Int)]? {
  precondition(layer.contentKind=="model","G1 excludes visible composition consumers")
  return []
 }
}

@main enum OrderedProbe {
 static func main() throws {
  guard let d=MTLCreateSystemDefaultDevice(),let q=d.makeCommandQueue() else {print("{\"metalUnavailable\":true}");return}
  var rows:[[String:Any]]=[]
  for mode in ["cold-full","cold-prefix-quota","resize-prefix-quota","partial-mesh"] {
   rows.append(try autoreleasepool {try run(mode,d,q)})
  }
  print(String(decoding:try JSONSerialization.data(withJSONObject:["rows":rows]),as:UTF8.self))
 }
 static func texture(_ d:MTLDevice,_ size:Int,_ rgba:[UInt8])->MTLTexture {
  let td=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:size,height:size,mipmapped:false)
  td.storageMode = .shared;td.usage=[.shaderRead,.renderTarget]
  let t=d.makeTexture(descriptor:td)!,p=[rgba[2],rgba[1],rgba[0],rgba[3]]
  let pixels=Array(repeating:p,count:size*size).flatMap{$0}
  pixels.withUnsafeBytes{t.replace(region:MTLRegionMake2D(0,0,size,size),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:size*4)}
  return t
 }
 static func source(_ t:MTLTexture)->FixtureSource {
  let size=CGSize(width:t.width,height:t.height)
  return .init(texture:t,candidate:.init(texture:t,identity:.builtIn(name:"own-source"),generation:.immutable(revision:1),
   purpose:.premultipliedColor,content:.color(.resolved(.premultipliedAlpha)),physicalSize:size,mappedSize:size,
   uvTransform:.identity,sampling:.linearClamp))
 }
 static func material(_ rgb:SIMD3<Float>)->SceneStaticModelMaterial {
  .init(color:rgb,opacity:1,receivesLighting:true,textureAlphaIsOpacity:true,textureAlphaIsTintMask:false,
   emissiveColor:.zero,emissiveBrightness:0,brightness:1,usesHDRBrightness:false,viewTint:nil)
 }
 static func captures()->UInt64 {ScenePerformanceCounterHub.shared.snapshot()[.offscreenEffectCaptures] ?? 0}
 static func run(_ mode:String,_ d:MTLDevice,_ q:MTLCommandQueue)throws->[String:Any] {
  let pipeline=SceneStaticModelPipeline(device:d)!,image=SceneImageLayerPipeline(device:d)!
  let white=texture(d,1,[255,255,255,255])
  func quad(_ x:Float)->SceneStaticModelMesh {
   let vertices=[SIMD3(x,4,0),SIMD3(x+20,4,0),SIMD3(x+20,24,0),SIMD3(x,24,0)].map {
    SceneMdlStaticModel.Vertex(position:$0,normal:SIMD3(0,0,1),tangent:SIMD4(1,0,0,1),uv:SIMD2(repeating:0.5))
   }
   return pipeline.makeMesh(vertices:vertices,indices:[0,2,1,0,3,2])!
  }
  let a=quad(4),b=quad(36),reference=SceneNamedTextureReference(providerLayerID:11,variant:.primary)
  func entry(_ mesh:SceneStaticModelMesh,_ key:String,_ color:SIMD3<Float>,named:Bool=false)->ScenePreparedStaticModelResources.Entry {
   .init(materialPath:"materials/unseen/runtime.json",dynamicMaterialPath:"",geometryIdentity:key,mesh:mesh,
    albedo:named ? nil:PreparedTexture(texture:white),namedAlbedo:named ? reference:nil,material:material(color))
  }
  let partial=mode=="partial-mesh"
  let provider=SceneRenderDescriptor.Layer(id:11,visible:false,contentKind:"image")
  let layers:[SceneRenderDescriptor.Layer]=partial ? [.init(id:1)] : [.init(id:1),provider,.init(id:2)]
  let entries:[Int:[ScenePreparedStaticModelResources.Entry]]=partial
   ? [1:[entry(a,"same",SIMD3(1,0,0)),entry(a,"same",SIMD3(0,1,0)),entry(b,"other",SIMD3(0,0,1))]]
   : [1:[entry(a,"healthy",SIMD3(1,0,0))],2:[entry(b,"named",SIMD3(repeating:1),named:true)]]
  let descriptor=SceneRenderDescriptor(layers:layers,renderOrderLayerIDs:layers.map(\.id),staticModelConsumerProviders:partial ? [:]:[2:11])
  let renderer=SceneMetalRenderer(device:d,resources:.init(pipeline:pipeline,entries:entries),descriptor:descriptor)
  let pool=SceneOffscreenTexturePool(device:d,pixelFormat:.bgra8Unorm,residentByteBudget:16*1024*1024)
  let light=SceneLightSnapshot.Directional(layerID:3,castsShadow:true,directionTowardLight:SIMD3(0,0,1),color:SIMD3(repeating:1),intensity:0)
  let lighting=SceneLightSnapshot(ambient:SIMD3(repeating:1),skylight:.zero,directional:[light],point:[],spot:[],overflowCount:0)
  let camera=SceneParticleCameraFrame(camera:.init(eye:[0,0,0],center:[0,0,-1],up:[0,1,0],orthoWidth:64,orthoHeight:64,
   fovDegrees:nil,perspectiveOverrideFOVDegrees:nil,nearZ:0.01,farZ:1000),viewportSize:CGSize(width:256,height:256))
  let world=Dictionary(uniqueKeysWithValues:layers.map{($0.id,matrix_identity_float4x4)})
  var final:[String:Any]=[:]
  for size in (mode=="resize-prefix-quota" ? [64,256]:[256]) {
   let output=texture(d,size,[0,0,0,255]),green=texture(d,size,[0,255,0,255]),cb=q.makeCommandBuffer()!
   let pass=SceneMainPassEncoder(commandBuffer:cb,target:output,clearColor:MTLClearColorMake(0,0,0,1),clearEnabled:true)
   let sources=SceneBaseImageTextureSnapshot(sources:partial ? [:]:[11:source(green)])
   let epoch=renderer.textureRegistry.beginFrame(frameIndex:UInt64(size),layerSources:[:])
   let frame=SceneFrameContext(dynamicValues:.empty(frameIndex:UInt64(size),generation:1))
   let state=SceneMetalRenderer.StaticModelFrame();var leases:[SceneParticleDepthTargetLease]=[]
   let pressured=size==256 && mode != "cold-full"
   let dd=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:size,height:size,mipmapped:false)
   dd.storageMode = .private;dd.usage = .renderTarget
   let nativeDepth=d.heapTextureSizeAndAlign(descriptor:dd).size
   var held=0
   if pressured {
    held=SceneResourceBudget.shared.maximumBytes-SceneResourceBudget.shared.snapshot.residentBytes-nativeDepth
    precondition(SceneResourceBudget.shared.reserve(held,kind:.gpu))
   }
   defer {if held>0 {SceneResourceBudget.shared.release(held,kind:.gpu)}}
   let captureStart=captures(),rejectionStart=SceneResourceBudget.shared.snapshot.rejectionCount
   let error=renderer.prepareOrderedModelShadow(state:state,lights:[.directional(light)],lighting:lighting,orderedLayers:layers,visible:Set(layers.filter{$0.visible != false}.map(\.id)),
    activeNamedModels:partial ? []:[2],forwardGraphProviders:[],framePlans:[:],imageTextures:sources,imagePipeline:image,
    frameContext:frame,worldFrames:world,cameraFrame:camera,parallax:.init(),viewportSize:CGSize(width:size,height:size),
    batches:[:],particlePipeline:nil,mainPass:pass,groups:nil,utilityExecution:renderer.utilityExecution,pool:pool,commandBuffer:cb,leases:&leases,
    terminalCapacity:{true},recordsEvidence:false)
   let capturePrepared=captures()-captureStart,published = !state.shadows.isEmpty
   let preparedIDs=state.prepared?.keys.sorted() ?? []
   let depthStates=(state.prepared?[1] ?? []).map { draw->String in
    guard let depth=draw.depth else {return "unvisited"};return depth.lease == nil ? "failed":"ready"
   }
   let prefixCount=leases.count,rejections=SceneResourceBudget.shared.snapshot.rejectionCount-rejectionStart
   let namedAbsent=state.prepared?[2] == nil
   if held>0 {SceneResourceBudget.shared.release(held,kind:.gpu);held=0}
   // Replay only the original consumer calls. Ordering and stopped-prefix
   // preparation above are entirely the actual production frame owner.
   if !partial {
    let capture=renderer.captureRawDependencyProvider(layer:provider,source:sources.sources[11],imageTextures:sources,
     imagePipeline:image,frameContext:frame,worldFrames:world,cameraFrame:camera,parallax:.init(),
     viewportSize:CGSize(width:size,height:size),mainPass:pass)
    precondition(capture == .published)
   }
   let resource=renderer.textureRegistry.completeNamedLayerTargetTexture(reference:reference,frameEpoch:epoch)
   let named=partial ? nil:renderer.staticModelDraws(layer:layers.last!,worldFrames:world,snapshot:frame.dynamicValues,requiresCompleteNamedInputs:true)?.first
   let currentIdentity=partial || (named?.texture === resource && named?.premultiplied == true)
   let beforeDraw=leases.count
   for layer in layers where layer.contentKind=="model" {
    _=renderer.drawStaticModel(layer:layer,state:state,worldFrames:world,frameContext:frame,cameraFrame:camera,
      lighting:lighting,pass:pass,commandBuffer:cb,leases:&leases)
   }
   let afterDraw=leases.count,totalCaptures=captures()-captureStart
   precondition(pass.finishEnsuringClear());pass.armCompositionPins()
   for lease in leases {lease.arm(on:cb)};state.arm(on:cb);cb.commit();cb.waitUntilCompleted()
   precondition(cb.status == .completed);renderer.textureRegistry.commitFramePublication()
   var bytes=[UInt8](repeating:0,count:size*size*4)
   output.getBytes(&bytes,bytesPerRow:size*4,from:MTLRegionMake2D(0,0,size,size),mipmapLevel:0)
   func pixel(_ x:Int,_ y:Int)->[Int] {let i=((y*size/64)*size+x*size/64)*4;return [Int(bytes[i+2]),Int(bytes[i+1]),Int(bytes[i]),Int(bytes[i+3])]}
   final=["mode":mode,"extent":size,"typedInvalid":error as Any? ?? NSNull(),"preparedIDs":preparedIDs,
    "depthStates":depthStates,"namedUnvisited":namedAbsent,"prefixLeases":prefixCount,"beforeDrawLeases":beforeDraw,
    "afterDrawLeases":afterDraw,"capturesPrepared":capturePrepared,"capturesTotal":totalCaptures,
    "physicalRejections":rejections,"shadow":published,"currentIdentity":currentIdentity,
    "pixels":[pixel(12,12),pixel(44,12)],"completed":true,"nativeDepthBytes":nativeDepth]
  }
  return final
 }
}
