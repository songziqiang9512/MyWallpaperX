import Foundation
import Metal

extension SceneOffscreenTexturePool {
    var maxDimension: Int { fatalError("GPU allocation is outside dependency planning") }
}

// Dependency planning never encodes GPU work. Match the current constructor
// contract while retaining the fixture's fail-fast encoding boundary.
extension SceneMainPassEncoder {
    convenience init(commandBuffer: MTLCommandBuffer, target: MTLTexture,
                     clearColor: MTLClearColor, clearEnabled: Bool,
                     submissionOwner: SceneMainPassEncoder) {
        self.init(commandBuffer: commandBuffer, target: target,
                  clearColor: clearColor, clearEnabled: clearEnabled)
    }
}

extension Harness {

    static func layer(
        _ id: Int,
        kind: SceneUtilityLayer.Kind? = nil,
        dependencies: [Int] = [],
        visible: Bool? = true
    ) -> SceneRenderDescriptor.Layer {
        .init(
            id: id,
            contentKind: kind == nil ? "image" : "composition",
            utilityLayer: kind.map(SceneUtilityLayer.init(kind:)),
            dependencyLayerIDs: dependencies,
            childLayerIDs: [],
            visible: visible,
            effects: []
        )
    }

    static func consumer(
        _ id: Int,
        provider: Int,
        dependencies: [Int]? = nil,
        visible: Bool? = true,
        extraEffect: Bool = false,
        opacity: Double? = nil,
        variantSuffix: String = "a",
        userTextureOverride: Bool = false,
        effectPath: String = "effects/workshop/2800594362/clipping_mask/effect.json"
    ) -> SceneRenderDescriptor.Layer {
        var effects = [effect(
            id: id,
            provider: provider,
            opacity: opacity,
            variantSuffix: variantSuffix,
            userTextureOverride: userTextureOverride,
            path: effectPath
        )]
        if extraEffect {
            effects.append(.init(id: "tint", file: "effects/tint/effect.json", visible: true, passes: []))
        }
        return .init(
            id: id,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: dependencies ?? [provider],
            childLayerIDs: [],
            visible: visible,
            effects: effects
        )
    }

    static func localEffects(
        layerID: Int,
        count: Int,
        suffix: String
    ) -> [SceneRenderDescriptor.EffectDescriptor] {
        (0 ..< count).map { index in
            .init(
                id: "local-\(layerID)-\(suffix)-\(index)",
                file: "effects/tint/effect.json",
                visible: true,
                passes: [.init(
                    passIndex: 0,
                    texturePaths: [],
                    textureSlots: [],
                    userTextureInputs: [],
                    combos: [:],
                    constantShaderValues: [:]
                )]
            )
        }
    }

    static func effect(
        id: Int,
        provider: Int,
        opacity: Double? = nil,
        variantSuffix: String = "a",
        userTextureOverride: Bool = false,
        path: String = "effects/workshop/2800594362/clipping_mask/effect.json"
    ) -> SceneRenderDescriptor.EffectDescriptor {
        .init(
            id: "effect-\(id)",
            file: path,
            visible: true,
            passes: [.init(
                passIndex: 0,
                texturePaths: ["_rt_imageLayerComposite_\(provider)_\(variantSuffix)"],
                textureSlots: opacity == nil
                    ? [nil, "_rt_imageLayerComposite_\(provider)_\(variantSuffix)"]
                    : [nil, "_rt_imageLayerComposite_\(provider)_\(variantSuffix)", nil],
                userTextureInputs: userTextureOverride
                    ? [nil, SceneEffectTextureInput(kind: .path, value: "user.png")]
                    : [],
                combos: opacity == nil ? ["BLENDMODE": 5] : [:],
                constantShaderValues: opacity.map {
                    ["Opacity": SceneDocument.ShaderValue(components: [$0])]
                } ?? [:]
            )]
        )
    }

    static func shadowedEffect(
        id: Int,
        provider: Int,
        userTextureKind: SceneEffectTextureInput.Kind = .property
    ) -> SceneRenderDescriptor.EffectDescriptor {
        let path = "_rt_imageLayerComposite_\(provider)_a"
        return .init(
            id: "effect-\(id)",
            file: "effects/blend/effect.json",
            visible: true,
            passes: [.init(
                passIndex: 0,
                texturePaths: [path],
                textureSlots: [nil, path],
                userTextureInputs: [nil, .init(
                    kind: userTextureKind,
                    value: userTextureKind == .system
                        ? "$mediaThumbnail" : "userTexture"
                )],
                combos: ["BLENDMODE": 0],
                constantShaderValues: [
                    "alpha": .init(components: [1]),
                    "multiply": .init(components: [1]),
                ]
            )]
        )
    }

    static func gradientConsumer(
        _ id: Int,
        provider: Int,
        reversed: Bool = false,
        axis: Int = 1
    ) -> SceneRenderDescriptor.Layer {
        let gradient = SceneRenderDescriptor.EffectDescriptor(
            id: "gradient-\(id)",
            file: "effects/workshop/2552475732/gradient_color/effect.json",
            visible: true,
            passes: [.init(
                passIndex: 0,
                textureSlots: [],
                combos: ["AXIS": axis, "BLENDMODE": 0],
                constantShaderValues: [
                    "Amount": .init(components: [1]),
                    "Color 1": .init(components: [1, 0, 0.2]),
                    "Color 2": .init(components: [0, 0, 1]),
                    "Hue Speed": .init(components: [0]),
                    "Opacity": .init(components: [1]),
                    "Oscillate": .init(components: [0]),
                ]
            )]
        )
        let externalPrimary = effect(id: id, provider: provider)
        return .init(
            id: id,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: [provider],
            childLayerIDs: [],
            visible: true,
            effects: reversed ? [externalPrimary, gradient] : [gradient, externalPrimary]
        )
    }
}
