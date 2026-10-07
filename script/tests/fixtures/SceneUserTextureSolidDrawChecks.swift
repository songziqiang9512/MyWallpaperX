import CoreGraphics
import Foundation
import simd

// CPU-only member stubs. The draw request, candidate validation, provider
// selection, color policy, and fragment-uniform producers compile unchanged.
enum MTLPixelFormat: UInt { case rgba8Unorm, bgra8Unorm, rgba16Float, r8Unorm }
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
        var imagePath: String? = nil
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
    case materialConstant(layerID: Int, passIndex: Int, name: String, materialPath: String)
}
enum SceneDynamicValue {
    case vector3(Double, Double, Double)
    case scalar(Double)
}
struct SceneDynamicResolvedValue {
    let value: SceneDynamicValue
}
struct SceneDynamicSnapshot {
    var values: [SceneDynamicTarget: SceneDynamicResolvedValue]
    init(values: [SceneDynamicTarget: SceneDynamicResolvedValue] = [:]) { self.values = values }
    init(colors: [SceneDynamicTarget: SIMD3<Float>]) {
        values = colors.mapValues { .init(value: .vector3(Double($0.x), Double($0.y), Double($0.z))) }
    }
    subscript(_ target: SceneDynamicTarget) -> SceneDynamicResolvedValue? { values[target] }
    func color(_ target: SceneDynamicTarget) -> SIMD3<Float>? {
        guard case let .vector3(red, green, blue)? = values[target]?.value else { return nil }
        return .init(Float(red), Float(green), Float(blue))
    }
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
                                    ? snapshot.color(.layer(layerID: layer.id, field: .color)) ?? layer.colorRGB
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
        let materialColors = SceneBaseMaterialProviderBindingProgram(
            baseMaterialBindings: [:], authoredMaterialColors: ["models/tint.json": SIMD3(0.5, 0.25, 1)])
        let originalLayer = SceneRenderDescriptor.Layer(id: 7, contentKind: "image", imagePath: "models/tint.json")
        let dynamicLayer = SceneRenderDescriptor.Layer(id: 99, contentKind: "image", imagePath: "models/tint.json")
        checks["dynamicInstanceSharesPreparedMaterialColor"] =
            materialColors.sourceMaterialColor(layer: originalLayer, snapshot: dynamic)
                == materialColors.sourceMaterialColor(layer: dynamicLayer, snapshot: dynamic)
        checks["unrelatedMaterialRemainsNeutral"] = materialColors.sourceMaterialColor(layer: layer, snapshot: dynamic) == SIMD3(repeating: 1)
        var materialRequest = request(tinted, snapshot: dynamic)
        materialRequest.sourceMaterialColor = materialColors.sourceMaterialColor(layer: originalLayer, snapshot: dynamic)
        materialRequest.sourceMaterialAlpha = 0.5
        for offscreen in [false, true] {
            let uniforms = compositor.sourceFragmentUniforms(for: materialRequest, routesOffscreen: offscreen)
            checks["materialMultipliesLayerColorOnce_\(offscreen)"] = uniforms?.tint == SIMD4(0.125, 0.125, 0.75, 1)
            checks["materialAlphaPreserved_\(offscreen)"] = uniforms?.alpha == 0.5
        }
        let materialTarget = SceneDynamicTarget.materialConstant(layerID: originalLayer.id,
            passIndex: 0, name: "surface-key", materialPath: "materials/unseen/tint.json")
        let alphaTarget = SceneDynamicTarget.materialConstant(layerID: originalLayer.id,
            passIndex: 0, name: "coverage-parameter", materialPath: "materials/unseen/tint.json")
        let dynamicMaterial = SceneBaseMaterialProviderBindingProgram(baseMaterialBindings: [:],
            authoredMaterialColors: ["models/tint.json": SIMD3(0.5, 0.25, 1)],
            materialColorTargets: ["models/tint.json": materialTarget],
            sourceMaterialAlphaByModel: ["models/tint.json": .property(target: alphaTarget, fallback: 0.6)])
        let frame = SceneDynamicSnapshot(values: [
            materialTarget: .init(value: .vector3(0.5, 0.25, 0.75)),
            alphaTarget: .init(value: .scalar(0.3)),
            .layer(layerID: originalLayer.id, field: .color): .init(value: .vector3(0.4, 0.8, 0.2)),
            .layer(layerID: dynamicLayer.id, field: .color): .init(value: .vector3(0.2, 0.1, 0.6)),
        ])
        let originalColor = dynamicMaterial.sourceMaterialColor(layer: originalLayer, snapshot: frame)
        let cloneColor = dynamicMaterial.sourceMaterialColor(layer: dynamicLayer, snapshot: frame)
        checks["originalAndCloneReadOneMaterialTarget"] = originalColor == SIMD3(0.5, 0.25, 0.75)
            && originalColor == cloneColor
        let changedUserFrame = SceneDynamicSnapshot(values: [
            materialTarget: .init(value: .vector3(0.2, 0.6, 0.8)),
            alphaTarget: .init(value: .scalar(0.3)),
        ])
        func near(_ value: SIMD4<Float>, _ expected: SIMD4<Float>) -> Bool {
            (0 ..< 4).allSatisfy { abs(value[$0] - expected[$0]) < 0.000_001 }
        }
        for (sourceLayer, expected) in [(originalLayer, SIMD4<Float>(0.2, 0.2, 0.15, 1)),
                                      (dynamicLayer, SIMD4<Float>(0.1, 0.025, 0.45, 1))] {
            for offscreen in [false, true] {
                let ownAlpha: Float = sourceLayer.id == originalLayer.id ? 0.5 : 0.8
                let values = SceneImageLayerUniformValues(time: 0, alpha: ownAlpha, cursorUV: .zero,
                    tint: frame.color(.layer(layerID: sourceLayer.id, field: .color))!)
                let uniforms = compositor.sourceFragmentUniforms(values: values, layer: sourceLayer,
                    sourceSample: selectedRequest.resolvedBaseTextureSample()!, routesOffscreen: offscreen,
                    dependencyBlendMode: nil, sourceMaterialAlpha: dynamicMaterial.sourceMaterialAlpha(layer: sourceLayer, snapshot: frame),
                    sourceMaterialColor: dynamicMaterial.sourceMaterialColor(layer: sourceLayer, snapshot: frame))
                checks["materialAndOwnStyleMultiplyOnce_\(sourceLayer.id)_\(offscreen)"] = near(uniforms.tint, expected)
                    && abs(uniforms.alpha - ownAlpha * 0.3) < 0.000_001
                let changed = compositor.sourceFragmentUniforms(values: values, layer: sourceLayer,
                    sourceSample: selectedRequest.resolvedBaseTextureSample()!, routesOffscreen: offscreen,
                    dependencyBlendMode: nil,
                    sourceMaterialAlpha: dynamicMaterial.sourceMaterialAlpha(layer: sourceLayer, snapshot: changedUserFrame),
                    sourceMaterialColor: dynamicMaterial.sourceMaterialColor(layer: sourceLayer, snapshot: changedUserFrame))
                let changedExpected = sourceLayer.id == originalLayer.id
                    ? SIMD4<Float>(0.08, 0.48, 0.16, 1) : SIMD4<Float>(0.04, 0.06, 0.48, 1)
                checks["currentUserMaterialKeepsOwnStyle_\(sourceLayer.id)_\(offscreen)"] = near(changed.tint, changedExpected)
                    && abs(changed.alpha - ownAlpha * 0.3) < 0.000_001
                let zeroFrame = SceneDynamicSnapshot(values: [alphaTarget: .init(value: .scalar(0))])
                let zero = compositor.sourceFragmentUniforms(values: values, layer: sourceLayer,
                    sourceSample: selectedRequest.resolvedBaseTextureSample()!, routesOffscreen: offscreen,
                    dependencyBlendMode: nil, sourceMaterialAlpha: dynamicMaterial.sourceMaterialAlpha(layer: sourceLayer, snapshot: zeroFrame),
                    sourceMaterialColor: dynamicMaterial.sourceMaterialColor(layer: sourceLayer, snapshot: frame))
                checks["zeroMaterialAlphaRetained_\(sourceLayer.id)_\(offscreen)"] = zero.alpha == 0
            }
        }
        for (name, bad) in [("wrongType", SceneDynamicValue.vector3(0.1, 0.2, 0.3)),
                            ("nonfinite", .scalar(.nan)), ("negative", .scalar(-0.1)),
                            ("oversized", .scalar(1.1))] {
            checks["invalidMaterialAlphaFallsBack_\(name)"] = dynamicMaterial.sourceMaterialAlpha(
                layer: originalLayer, snapshot: .init(values: [alphaTarget: .init(value: bad)])) == 0.6
        }
        checks["absentMaterialAlphaFallsBackForClone"] = dynamicMaterial.sourceMaterialAlpha(
            layer: dynamicLayer, snapshot: .empty(frameIndex: 0)) == 0.6
        for (name, bad) in [("wrongType", SceneDynamicValue.scalar(0.2)),
                            ("nonfinite", .vector3(.nan, 0.2, 0.3))] {
            checks["invalidMaterialValueFallsBack_\(name)"] = dynamicMaterial.sourceMaterialColor(
                layer: originalLayer, snapshot: .init(values: [materialTarget: .init(value: bad)])) == SIMD3(0.5, 0.25, 1)
        }
        checks["absentMaterialValueFallsBack"] = dynamicMaterial.sourceMaterialColor(
            layer: dynamicLayer, snapshot: .empty(frameIndex: 0)) == SIMD3(0.5, 0.25, 1)
        checks["materialValueClampsAsBefore"] = dynamicMaterial.sourceMaterialColor(
            layer: originalLayer, snapshot: .init(values: [materialTarget: .init(value: .vector3(-2, 0.4, 3))])) == SIMD3(0, 0.4, 1)
        let unlowered = SceneBaseMaterialProviderBindingProgram(baseMaterialBindings: [:],
            materialColorTargets: ["models/tint.json": materialTarget])
        checks["targetCannotBypassUnloweredModel"] = unlowered.sourceMaterialColor(
            layer: originalLayer, snapshot: frame) == SIMD3(repeating: 1)
        let wrongKey = SceneDynamicTarget.materialConstant(layerID: originalLayer.id,
            passIndex: 0, name: "other-key", materialPath: "materials/unseen/tint.json")
        checks["wrongMaterialIdentityCannotSupplyValue"] = dynamicMaterial.sourceMaterialColor(
            layer: originalLayer, snapshot: .init(values: [wrongKey: .init(value: .vector3(0.9, 0.9, 0.9))])) == SIMD3(0.5, 0.25, 1)
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
