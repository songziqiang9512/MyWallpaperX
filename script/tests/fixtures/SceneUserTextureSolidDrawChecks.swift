import CoreGraphics
import Foundation
import simd

// CPU-only member stubs. The draw request, candidate validation, provider
// selection, color policy, and fragment-uniform producers compile unchanged.
enum MTLPixelFormat: UInt { case rgba8Unorm, bgra8Unorm, r8Unorm }
enum MTLTextureType { case type2D, type3D }
struct MTLTextureUsage: OptionSet {
    let rawValue: Int
    static let shaderRead = Self(rawValue: 1)
}
protocol MTLTexture: AnyObject {
    var width: Int { get }
    var height: Int { get }
    var pixelFormat: MTLPixelFormat { get }
    var textureType: MTLTextureType { get }
    var sampleCount: Int { get }
    var mipmapLevelCount: Int { get }
    var usage: MTLTextureUsage { get }
}
final class Texture: MTLTexture {
    let width = 4
    let height = 2
    var pixelFormat: MTLPixelFormat = .rgba8Unorm
    var textureType: MTLTextureType = .type2D
    var sampleCount = 1
    var mipmapLevelCount = 1
    var usage: MTLTextureUsage = .shaderRead
}
struct MTLSamplerState {}
enum MTLSamplerMinMagFilter { case nearest, linear }
enum MTLSamplerAddressMode { case `repeat`, clampToEdge }
final class MTLSamplerDescriptor {
    var normalizedCoordinates = true
    var minFilter = MTLSamplerMinMagFilter.linear
    var magFilter = MTLSamplerMinMagFilter.linear
    var mipFilter = MTLSamplerMinMagFilter.linear
    var sAddressMode = MTLSamplerAddressMode.clampToEdge
    var tAddressMode = MTLSamplerAddressMode.clampToEdge
    var rAddressMode = MTLSamplerAddressMode.clampToEdge
}
struct MTLDevice {
    func makeSamplerState(descriptor: MTLSamplerDescriptor) -> MTLSamplerState? { nil }
}
enum SceneTextureLoadPurpose: Hashable {
    case premultipliedColor, straightAlbedo, preservedChannels, mask, noise
    case flow, phase, normal, depth, lookupTable
}
struct SceneSystemProviderTextureIdentity: Hashable {
    let name: String
    let purpose: SceneTextureLoadPurpose
    var reportToken: String { name }
}
enum SceneFrameTextureIdentity: Hashable {
    case system(SceneSystemProviderTextureIdentity)
    case materialUserProperty(SceneUserPropertyTextureIdentity)
}
struct SceneTextureProviderPublication {
    let requestIdentity: SceneFrameTextureIdentity
    let candidate: SceneTextureCandidate
    var isComplete = true
}
struct SceneFrameTextureRegistry {
    struct Resource { let publication: SceneTextureProviderPublication }
    enum Status { case ready(Resource), incomplete, absent, pending, unavailable }
    var states: [SceneFrameTextureIdentity: Status] = [:]
    func lookup(_ identity: SceneFrameTextureIdentity) -> Status? { states[identity] }
}
struct SceneRenderDescriptor {
    struct Layer {
        let id: Int
        let contentKind: String
        var colorRGB: SIMD3<Float> = .zero
        var clampUVs: Bool? = nil
        var noInterpolation: Bool? = nil
        var brightness: Double? = nil
    }
    struct EffectDescriptor {
        struct PassDescriptor {
            let passIndex: Int
            let texturePaths: [String]
            let textureSlots: [String?]
            let userTextureInputs: [String]
            let combos: [String: Int]
        }
        let file: String
        let visible: Bool?
        let passes: [PassDescriptor]
    }
}
enum SceneDynamicTarget: Hashable {
    enum Field { case color }
    case layer(layerID: Int, field: Field)
}
struct SceneDynamicSnapshot {
    var colors: [SceneDynamicTarget: SIMD3<Float>] = [:]
    subscript(_ target: SceneDynamicTarget) -> SIMD3<Float>? { colors[target] }
    static func empty(frameIndex: Int) -> Self { .init() }
}
struct SceneBaseImageTextureSnapshot {
    let textures: [Int: MTLTexture]
    subscript(_ layerID: Int) -> MTLTexture? { textures[layerID] }
    func candidate(for layerID: Int, matching texture: MTLTexture) -> SceneTextureCandidate? { nil }
}
struct SceneMetalRenderer {
    let baseMaterialProviderBindings: SceneBaseMaterialProviderBindingProgram
    let textureRegistry: SceneFrameTextureRegistry
}
struct SceneEffectTextureInput {
    enum Kind { case system, property }
}
struct SceneBaseMaterialLightingProfile {}
enum SceneMaterialPropertyBindingCompiler {
    struct SourceMaterialAlpha {
        let propertyTarget: SceneDynamicTarget?
        func resolve(snapshot: SceneDynamicSnapshot) -> Float { 1 }
    }
}
enum SceneNamedTextureReference {
    enum Variant { case primary }
    init(providerLayerID: Int, variant: Variant) { self = .placeholder }
    case placeholder
}
struct SceneEffectPassSlot { let slotIndex: Int }
struct SceneFrameTextureResource {
    static func reservedNamedLayerTarget(
        reference: SceneNamedTextureReference, frameEpoch: UInt64,
        texture: MTLTexture, content: SceneTextureContent, consumerLayerID: Int
    ) -> Self? { nil }
}
struct SceneOffscreenTexturePool {}
struct SceneResolvedMaterialFrameTargetPlan {}
struct SceneLayerEffectSourceExtent { let pixelSize: CGSize }
enum SceneAudioSpectrumSnapshot { case silent }
struct SceneAuthoredShaderFrameInputs {}
struct SceneGeometryProduct {}
struct SceneBaseMaterialLitCapturePayload {}
enum SceneBlendModeShaderSource { static let maximumMode = 19 }
enum SceneGraphExecutionResetReason { case test }
struct SceneImageLayerCompositor {
    struct Runtime {
        let shouldDeferFrame = false
        func invalidate(reason: SceneGraphExecutionResetReason) {}
    }
    let resolvedMaterialRuntime: Runtime? = nil
}
struct SceneLayerFragmentUniforms {
    let time: Float
    var alpha: Float
    let dependencyBlendMode: UInt32
    let usesDependencyBlend: UInt32
    let cursorUV: SIMD2<Float>
    let sourceSampling: SIMD2<UInt32>
    let tint: SIMD4<Float>
    let textureFrame0: SIMD4<Float>
    let textureFrame1: SIMD4<Float>
}

@main
enum Checks {
    static func main() throws {
        let selectedTexture = Texture()
        let fallbackTexture = Texture()
        let layer = SceneRenderDescriptor.Layer(id: 42, contentKind: "solid")
        let property = SceneUserPropertyTextureIdentity(
            propertyKey: "background", purpose: .premultipliedColor
        )!
        let frameIdentity = SceneFrameTextureIdentity.materialUserProperty(property)
        let program = SceneBaseMaterialProviderBindingProgram(baseMaterialBindings: [
            layer.id: .init(layerID: layer.id, source: .layerInstance, slotIndex: 0,
                            provider: .userProperty(property))
        ])
        let candidate = SceneTextureCandidate(
            texture: selectedTexture, identity: .file(path: "/fixture/background.png"),
            generation: .file(byteCount: 12, modifiedAtBits: 1,
                              revision: .init(fileSystemID: 1, fileID: 2,
                                              statusChangedAtSeconds: 1,
                                              statusChangedAtNanoseconds: 0)),
            purpose: .premultipliedColor, content: .color(.resolved(.premultipliedAlpha)),
            physicalSize: CGSize(width: 4, height: 2), mappedSize: CGSize(width: 2, height: 2),
            uvTransform: .init(origin: .zero, xAxis: SIMD2(0.5, 0), yAxis: SIMD2(0, 1)),
            sampling: .linearRepeat
        )
        func replacing(
            _ original: SceneTextureCandidate,
            purpose: SceneTextureLoadPurpose? = nil,
            content: SceneTextureContent? = nil,
            uv: SceneTextureUVTransform? = nil,
            sampling: SceneTextureSampling? = nil
        ) -> SceneTextureCandidate {
            .init(texture: original.texture, identity: original.identity,
                  generation: original.generation, purpose: purpose ?? original.purpose,
                  content: content ?? original.content, physicalSize: original.physicalSize,
                  mappedSize: original.mappedSize, uvTransform: uv ?? original.uvTransform,
                  sampling: sampling ?? original.sampling)
        }
        func request(
            _ source: SceneBaseMaterialTextureSource,
            snapshot: SceneDynamicSnapshot = .empty(frameIndex: 0)
        ) -> SceneImageLayerDrawRequest {
            .init(layer: layer, texture: source.texture, baseTextureCandidate: source.candidate,
                  masks: .empty, textureFrame: .identity, mvp: matrix_identity_float4x4,
                  uniforms: .init(time: 0, alpha: 1, cursorUV: .zero,
                                  tint: source.usesAuthoredLayerColor
                                    ? snapshot[.layer(layerID: layer.id, field: .color)] ?? layer.colorRGB
                                    : SIMD3(repeating: 1)),
                  offscreenTexturePool: nil, effectSourceExtent: nil,
                  requiresSourceCopy: false, finalCompositeAlpha: nil)
        }
        func renderer(_ status: SceneFrameTextureRegistry.Status) -> SceneMetalRenderer {
            .init(baseMaterialProviderBindings: program,
                  textureRegistry: .init(states: [frameIdentity: status]))
        }
        let publication = SceneTextureProviderPublication(requestIdentity: frameIdentity,
                                                          candidate: candidate)
        let selectedRenderer = renderer(.ready(.init(publication: publication)))
        let fallback = SceneBaseImageTextureSnapshot(textures: [layer.id: fallbackTexture])
        let snapshot = SceneDynamicSnapshot.empty(frameIndex: 0)
        let selected = selectedRenderer.baseMaterialTextureSource(
            for: layer, imageTextures: fallback,
            readyProviderUsesAuthoredLayerColor: selectedRenderer.baseMaterialReadyProviderUsesAuthoredLayerColor(
                for: layer, dynamicValues: snapshot)
        )!
        let selectedRequest = request(selected)
        let compositor = SceneImageLayerCompositor()
        let dynamic = SceneDynamicSnapshot(colors: [.layer(layerID: layer.id, field: .color): SIMD3(0.25, 0.5, 0.75)])
        let tinted = selectedRenderer.baseMaterialTextureSource(
            for: layer, imageTextures: fallback,
            readyProviderUsesAuthoredLayerColor: selectedRenderer.baseMaterialReadyProviderUsesAuthoredLayerColor(
                for: layer, dynamicValues: dynamic)
        )!
        let reset = renderer(.absent).baseMaterialTextureSource(for: layer, imageTextures: fallback)!
        var checks: [String: Bool] = [
            "solidFileCandidateReachesActualDrawSample": selectedRequest.resolvedBaseTextureSample() != nil,
            "selectedFileOwnsUVAndSampling": selectedRequest.resolvedBaseTextureSample()?.textureFrame == candidate.uvTransform
                && selectedRequest.resolvedBaseTextureSample()?.sampling == candidate.sampling,
            "staticBlackFallbackDoesNotTintSelectedFile": compositor.sourceFragmentUniforms(for: selectedRequest, routesOffscreen: false)?.tint == SIMD4(1, 1, 1, 1),
            "dynamicColorStillTintsSelectedFile": compositor.sourceFragmentUniforms(for: request(tinted, snapshot: dynamic), routesOffscreen: true)?.tint == SIMD4(0.25, 0.5, 0.75, 1),
            "resetReturnsToAuthoredBlack": reset.texture === fallbackTexture && reset.candidate == nil
                && compositor.sourceFragmentUniforms(for: request(reset), routesOffscreen: false)?.tint == SIMD4(0, 0, 0, 1),
        ]
        for (name, bad) in [
            ("wrongPurpose", replacing(candidate, purpose: .mask)),
            ("straightAlpha", replacing(candidate, content: .color(.resolved(.straightAlpha)))),
            ("dataContent", replacing(candidate, content: .data)),
            ("wrongUV", replacing(candidate, uv: .identity)),
            ("clampBorder", replacing(candidate, sampling: .init(texFlags: 8))),
            ("unknownSampler", replacing(candidate, sampling: .init(texFlags: 16))),
        ] {
            var badRequest = selectedRequest
            badRequest.baseTextureCandidate = bad
            checks["rejects_\(name)"] = badRequest.resolvedBaseTextureSample() == nil
        }
        let wrongTextureRequest = SceneImageLayerDrawRequest(
            layer: layer, texture: fallbackTexture, baseTextureCandidate: candidate, masks: .empty,
            textureFrame: .identity, mvp: matrix_identity_float4x4, uniforms: selectedRequest.uniforms,
            offscreenTexturePool: nil, effectSourceExtent: nil, requiresSourceCopy: false, finalCompositeAlpha: nil)
        checks["rejectsWrongPhysicalTexture"] = wrongTextureRequest.resolvedBaseTextureSample() == nil
        selectedTexture.usage = []
        checks["rejectsMissingShaderReadUsage"] = selectedRequest.resolvedBaseTextureSample() == nil
        selectedTexture.usage = .shaderRead
        selectedTexture.sampleCount = 2
        checks["rejectsMultisampleTexture"] = selectedRequest.resolvedBaseTextureSample() == nil
        selectedTexture.sampleCount = 1
        selectedTexture.pixelFormat = .r8Unorm
        checks["rejectsDataPixelFormat"] = selectedRequest.resolvedBaseTextureSample() == nil
        let data = try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
