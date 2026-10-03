struct FixtureProfiles {var lightingProfileByLayerID:[Int:SceneBaseMaterialLightingProfile]=[:]}
struct FixturePipelines {let litImageLayer:SceneLitImageLayerPipeline?}
struct SceneSpriteAnimation {}
struct SceneMediaThumbnailTextureStore {struct Snapshot {}}
struct SceneBaseMaterialTextureSelection {}
struct SceneFramePerformanceTelemetry {
 func beginStage(_ name:String) {};func endStage(_ name:String) {}
}
struct SceneEffectTextureInput:Sendable {}
struct SceneDocument {
 struct SceneLayerMaterialInstance {
  let isMalformed:Bool;let combos:[String:Int];let textureSlots:[String?]
  let userTextureInputs:[SceneEffectTextureInput?];let hasUserTextureOverride:Bool
 }
}
extension SceneRenderDescriptor {
 struct MaterialPassDescriptor {
  let shaderPath:String?;let combos:[String:Int];let textureSlots:[String?]
  let userTextureInputs:[SceneEffectTextureInput?];let passIndex:Int;let materialPath:String
 }
}
enum SceneBuiltinShaderIdentity {
 static func isImage(_ name:String)->Bool {fatalError("profile compiler is outside this prepared-profile probe")}
}
enum SceneMaterialPropertyBindingCompiler {
 static func supportsBuiltinImage(layer:SceneRenderDescriptor.Layer,instance:SceneDocument.SceneLayerMaterialInstance?,passes:[SceneRenderDescriptor.MaterialPassDescriptor])->Bool {fatalError("outside prepared-profile probe")}
 static func staticComponents(_ key:String,instance:SceneDocument.SceneLayerMaterialInstance?,pass:SceneRenderDescriptor.MaterialPassDescriptor,count:Int,fallback:[Double])->[Double]? {fatalError("outside prepared-profile probe")}
 static func emissionColor(instance:SceneDocument.SceneLayerMaterialInstance?,pass:SceneRenderDescriptor.MaterialPassDescriptor)->SIMD3<Float>? {fatalError("outside prepared-profile probe")}
 static func imageMaterialPasses(descriptor:SceneRenderDescriptor)->[Int:[SceneRenderDescriptor.MaterialPassDescriptor]] {fatalError("outside prepared-profile probe")}
}
struct SceneImageLayerDrawRequest {
 let layer:SceneRenderDescriptor.Layer;let dynamicValues:SceneDynamicSnapshot
 var resolvedMaterialFrameTargetPlan:SceneResolvedMaterialFrameTargetPlan?=nil
 var geometryProduct:SceneGeometryProduct?=nil;var sourceLighting:SceneBaseMaterialLitCapturePayload?=nil
}
// This prepared-profile probe exercises real sizing/capacity and lighting
// owners; graph preflight and both admission phases remain outside its scope.
// Their signatures are synchronized, and every attempted call traps.
final class SceneResolvedMaterialRuntimeBridge {
 struct FramePreparationRequest {let targetPlan:SceneResolvedMaterialFrameTargetPlan}
 // This prepared-profile fixture has no authored environment sampler demand.
 func requiresSceneEnvironment(layerID:Int)->Bool {false}
 func prepareFrameResourceBundle(plans:[SceneResolvedMaterialFrameTargetPlan],pool:SceneOffscreenTexturePool,commandBuffer:MTLCommandBuffer)->SceneResolvedMaterialFrameResourceBundle? {fatalError("resource phase outside admission sizing probe")}
}
enum FixturePreflight {case ready([Int:SceneResolvedMaterialFrameTargetPlan],[Int:String],[SceneResolvedMaterialRuntimeBridge.FramePreparationRequest]),deferred,rejected(reasonCode:String)}
extension SceneMetalRenderer {
 enum ResolvedMaterialFrameAdmission {case ready(plans:[Int:SceneResolvedMaterialFrameTargetPlan],preparationRequests:[SceneResolvedMaterialRuntimeBridge.FramePreparationRequest],resourceBundle:SceneResolvedMaterialFrameResourceBundle?),deferred(reasonCode:String),rejected(reasonCode:String)}
 func imageModelMatrix(for layer:SceneRenderDescriptor.Layer,worldFramesByLayerID:[Int:simd_float4x4],renderSizeOverride:[Float]?,parallaxMouseNormalized:SIMD2<Float>,configuration:SceneLayerParallax.Configuration,visibleHalfExtents:SIMD2<Float>,usesPerspective:Bool)->simd_float4x4 {worldFramesByLayerID[layer.id] ?? matrix_identity_float4x4}
 func preflightResolvedMaterialFrameTargets(imageTextures:SceneBaseImageTextureSnapshot,spriteAnimations:[Int:SceneSpriteAnimation],spriteAnimationPlaybackTimes:[Int:Float],performanceTelemetry:SceneFramePerformanceTelemetry?,specializedBaseTextureSamplings:[Int:SceneTextureSampling],imagePipeline:SceneImageLayerPipeline?,offscreenTexturePool:SceneOffscreenTexturePool?,frameVisibleLayerIDs:Set<Int>,frameContext:SceneFrameContext,worldFramesByLayerID:[Int:simd_float4x4],cameraFrame:SceneParticleCameraFrame,parallaxConfiguration:SceneLayerParallax.Configuration,mainTarget:MTLTexture,commandBuffer:MTLCommandBuffer,baseMaterialSelections:inout[Int:SceneBaseMaterialTextureSelection],environmentSource:((MTLCommandBuffer)->SceneFrameTextureResource?)?,frameLightSnapshot:SceneLightSnapshot?,compositionGroupRuntime:SceneCompositionGroupFrameRuntime?)->FixturePreflight {fatalError("graph preflight outside admission sizing probe")}
}
extension SceneImageLayerCompositor {
 var resolvedMaterialRuntime:SceneResolvedMaterialRuntimeBridge? {nil}
 enum Preparation {case ready,rejected}
 func installResolvedMaterialFrameLocalFallbacks(_ value:[Int:String])->Bool {fatalError("unused graph admission")}
 func recordResolvedMaterialFramePreflightFailure(_ reason:String) {fatalError("unused graph admission")}
 func endResolvedMaterialFrame(on cb:MTLCommandBuffer)->Bool {fatalError("unused graph admission")}
 func deferResolvedMaterialFrame()->Bool {fatalError("unused graph admission")}
 func prepareResolvedMaterialFrame(_ value:[SceneResolvedMaterialRuntimeBridge.FramePreparationRequest],pool:SceneOffscreenTexturePool?,commandBuffer:MTLCommandBuffer,resourceBundle:SceneResolvedMaterialFrameResourceBundle? = nil,performanceTelemetry:SceneFramePerformanceTelemetry?)->Preparation {fatalError("graph finalization outside admission sizing probe")}
 func preparedResolvedMaterialOutputTexturesByLayerID()->[Int:MTLTexture]? {fatalError("unused graph admission")}
}
