enum SceneMaterialPropertyBindingCompiler {
 static func staticComponents(_ key:String,instance:Any?,pass:SceneRenderDescriptor.MaterialPassDescriptor,
                              count:Int,fallback:[Double],requiresCompleteScalar:Bool=false)->[Double]? {
  // Values here are typed transport inputs; full raw projection is tested
  // against the actual shared compiler in the material property fixture.
  return pass.constantShaderValues[key]?.components ?? fallback
 }
}
struct SceneDocument {
 struct ShaderValue {let components:[Double];var userBinding:String?=nil;var scriptSource:String?=nil}
 let objects:[SceneRenderDescriptor.Layer]
}
extension SceneResourceView {
 init(root:URL) {
  self.init(projectRootURL:root,packageRootURL:nil,stockAssetsRootURL:nil)
 }
}
final class SceneTextureLoader {
 enum Result {case loaded(SceneTextureCandidate);case missing}
 var candidates:[String:SceneTextureCandidate]=[:]
 var requests:[[String:String]]=[]
 init(root:URL,device:MTLDevice)throws {
  let paths=try FileManager.default.contentsOfDirectory(at:root.appendingPathComponent("materials"),includingPropertiesForKeys:nil)
  for path in paths where path.pathExtension=="rgba" {
   let td=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:1,height:1,mipmapped:false)
   td.storageMode = .shared;td.usage = .shaderRead
   let texture=device.makeSceneTexture(descriptor:td)!
   let data=try Data(contentsOf:path)
   data.withUnsafeBytes{texture.replace(region:MTLRegionMake2D(0,0,1,1),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:4)}
   let png=path.deletingPathExtension().appendingPathExtension("png")
   // Match the product's canonical file identity across /var and /tmp aliases.
   candidates[png.resolvingSymlinksInPath().path] = .init(texture:texture,identity:.file(path:png.path),generation:.immutable(revision:1),purpose:.straightAlbedo,
      content:.color(.resolved(.straightAlpha)),physicalSize:CGSize(width:1,height:1),mappedSize:CGSize(width:1,height:1),uvTransform:.identity,sampling:.directImageFallback)
  }
 }
 func loadCandidate(from input:SceneResourceView.FileInput,purpose:SceneTextureLoadPurpose,device:MTLDevice,
                    checkCancellation:(() throws -> Void)?=nil) throws -> Result {
  try checkCancellation?()
  let url=URL(fileURLWithPath:input.diagnosticPath)
  requests.append(["path":url.lastPathComponent,"purpose":String(describing:purpose)])
  guard let candidate=candidates[url.resolvingSymlinksInPath().path] else {return .missing}
  return .loaded(.init(texture:candidate.texture,identity:candidate.identity,generation:candidate.generation,
      purpose:purpose,content:candidate.content,physicalSize:candidate.physicalSize,mappedSize:candidate.mappedSize,
      uvTransform:candidate.uvTransform,sampling:candidate.sampling,authoredFormat:candidate.authoredFormat))
 }
}
extension SceneRenderDescriptor {
 struct ModelMaterialLink {let modelPath:String;let materialPath:String?}
 struct ColorTargetFormat {var metalPixelFormat:MTLPixelFormat { .bgra8Unorm }}
 struct MaterialPassDescriptor {
  let materialPath:String;let textureSlots:[String?];let combos:[String:Int]
  var texturePaths:[String] {textureSlots.compactMap{$0}}
  let constantShaderValues:[String:SceneDocument.ShaderValue];var passIndex:Int=0;var depthWrite:String?=nil
  var depthTest:String?=nil
  var staticModelMaterialBindings:SceneStaticModelMaterialBindings? = .init(state:.hostBuiltin,bindings:[],rejectionReason:nil)
  var cullMode:String?=nil
  var staticModelDefaultAlbedoAssetPath:String?=nil;var shaderPath:String?=nil
  var blending:String?=nil
  var userShaderValues:[String:String]=[:]
  var userTextureInputs:[SceneEffectTextureInput?]=[]
 }
}
enum SceneAssetTextureEffectLocalUnavailable: Hashable { case animatedFrameMetadataInvalid }
enum SceneAssetTextureLaunchState: Hashable {
 case ready(SceneTextureContent), preparedVideo(SceneTextureContent)
 case absent, pending, unavailable
 case effectLocalUnavailable(SceneAssetTextureEffectLocalUnavailable)
}

// This fixture supplies already-decoded textures at the external loader
// boundary. Catalog/TEX decoding and animation are qualified by their own gates.
struct SceneStaticModelAssetInputs {
 let launchStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState]
 let candidates: [SceneAssetTextureIdentity: SceneTextureCandidate]

 init(materialPlan: ScenePreparedStaticModelResources.MaterialPlan,
      resourceView: SceneResourceView, descriptor: SceneRenderDescriptor,
      loader: SceneTextureLoader, device: MTLDevice) throws {
  let resolver = SceneTexturePathResolver(resourceView: resourceView, descriptor: descriptor)
  var states: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState] = [:]
  var loaded: [SceneAssetTextureIdentity: SceneTextureCandidate] = [:]
  for identity in materialPlan.assetDemands {
   guard let input = resolver.resolveTextureFile(named: identity.path.value) else {
    states[identity] = .absent; continue
   }
   switch try loader.loadCandidate(from: input, purpose: identity.purpose, device: device) {
   case let .loaded(candidate):
    states[identity] = .ready(candidate.content); loaded[identity] = candidate
   case .missing: states[identity] = .unavailable
   }
  }
  launchStates = states; candidates = loaded
 }

 func publish(to registry: TextureRegistry) {
  for (identity, candidate) in candidates { registry.setCandidate(candidate, for: identity) }
 }
}
