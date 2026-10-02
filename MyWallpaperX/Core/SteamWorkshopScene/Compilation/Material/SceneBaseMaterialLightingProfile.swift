import Foundation

/// Launch-immutable diffuse-lighting intent for built-in image materials.
/// Custom shader sources retain their existing frontend and output authority.
nonisolated struct SceneBaseMaterialLightingProfile: Equatable, Sendable {
    let lightingEnabled: Bool
    /// Absent only for the legacy implicit-shader diffuse admission.
    var scalarMaterial: SIMD2<Float>? = nil
    enum NormalSource: Equatable, Sendable {
        case disabled, unsupported, invalid
        case asset(SceneAssetTextureIdentity)
    }
    let normalSource: NormalSource
    var normalAsset: SceneAssetTextureIdentity? {
        guard case let .asset(identity) = normalSource else { return nil }
        return identity
    }

    static let disabled = SceneBaseMaterialLightingProfile(
        lightingEnabled: false, normalSource: .disabled
    )
}

enum SceneBaseMaterialLightingProfileCompiler {
    /// Material-pass combos are the authored default; the layer instance can
    /// override them. Built-in generic-image references are material identities,
    /// not authored shader sources. Source-backed passes retain their frontend.
    static func profile(
        layer: SceneRenderDescriptor.Layer,
        materialInstance: SceneDocument.SceneLayerMaterialInstance?,
        materialPasses: [SceneRenderDescriptor.MaterialPassDescriptor]
    ) -> SceneBaseMaterialLightingProfile {
        guard layer.isImageRenderable,
              materialInstance?.isMalformed != true,
              materialPasses.count <= 1 else { return .disabled }
        let pass = materialPasses.first
        let isBuiltin = pass?.shaderPath.map(SceneBuiltinShaderIdentity.isImage) ?? true
        let lightingEnabled = isBuiltin
            && (materialInstance?.combos["LIGHTING"] ?? pass?.combos["LIGHTING"]) == 1
        // Fixed built-in slot 1 is the normal input. Null instance slots inherit
        // the material; an explicit NORMALMAP=0 disables that optional input.
        func slot(_ slots: [String?]) -> String? {
            guard slots.indices.contains(1), let value = slots[1],
                  !value.isEmpty else { return nil }
            return value
        }
        let input = materialInstance?.hasUserTextureOverride == true
            ? materialInstance?.userTextureInputs : pass?.userTextureInputs
        let hasUnsupportedProvider = input?.indices.contains(1) == true
            && input?[1] != nil
        let normalEnabled = lightingEnabled
            && pass?.shaderPath.map(SceneBuiltinShaderIdentity.isImage) == true
            && (materialInstance?.combos["NORMALMAP"] ?? pass?.combos["NORMALMAP"]) != 0
        let normalSource: SceneBaseMaterialLightingProfile.NormalSource
        if !normalEnabled { normalSource = .disabled }
        else if hasUnsupportedProvider { normalSource = .unsupported }
        else if let path = slot(materialInstance?.textureSlots ?? []) ?? slot(pass?.textureSlots ?? []) {
            normalSource = SceneAssetTextureIdentity(virtualPath: path, purpose: .normal)
                .map { .asset($0) } ?? .invalid
        } else { normalSource = .disabled }
        var profile = SceneBaseMaterialLightingProfile(
            lightingEnabled: lightingEnabled, normalSource: normalSource
        )
        if lightingEnabled, let shader = pass?.shaderPath,
           SceneBuiltinShaderIdentity.isImage(shader) {
            let tierFour = shader.lowercased() == "genericimage4"
            func scalar(_ key: String, default fallback: Float) -> Float {
                guard let value = materialInstance?.scalarShaderValues?[key]
                    ?? pass?.constantShaderValues[key] else { return fallback }
                // Unresolved dynamic wrappers are not startup scalar values.
                guard value.userBinding == nil,
                      value.userValueKind == nil || value.userValueKind == .null,
                      value.scriptSource == nil,
                      value.timeline == nil, value.timelineDiagnostics.isEmpty,
                      value.bindingKeys.allSatisfy({ $0 == "value" || $0 == "user" }),
                      let components = value.components, components.count == 1,
                      components[0].isFinite else {
                    NSLog("MWX SCENE: schema=base-material-scalar component=%@ fallback=tier-default reason=invalid-or-unresolved", key)
                    return fallback
                }
                return Float(min(1, max(0, components[0])))
            }
            profile.scalarMaterial = SIMD2(
                scalar("metallic", default: tierFour ? 0 : 0.5),
                scalar("roughness", default: tierFour ? 0.7 : 0.5)
            )
        }
        return profile
    }

    /// Projects every image-renderable layer of the launch descriptor. The
    /// material-pass association mirrors the base-material provider
    /// binding compiler: model material links resolve the layer's image
    /// path to a material path, then the descriptor's material passes.
    static func profiles(
        descriptor: SceneRenderDescriptor,
        materialInstancesByLayerID: [Int: SceneDocument.SceneLayerMaterialInstance]
    ) -> [Int: SceneBaseMaterialLightingProfile] {
        let materialPathByModelPath = descriptor.modelMaterialLinks.reduce(
            into: [String: String]()
        ) { result, link in
            guard let materialPath = link.materialPath else { return }
            result[normalized(link.modelPath)] = normalized(materialPath)
        }
        let materialPassesByPath = Dictionary(
            grouping: descriptor.materialPasses,
            by: { normalized($0.materialPath) }
        )
        var profiles: [Int: SceneBaseMaterialLightingProfile] = [:]
        for layer in descriptor.layers where layer.isImageRenderable {
            let materialPasses: [SceneRenderDescriptor.MaterialPassDescriptor]
            if let imagePath = layer.imagePath,
               let materialPath = materialPathByModelPath[normalized(imagePath)] {
                materialPasses = materialPassesByPath[materialPath] ?? []
            } else {
                materialPasses = []
            }
            profiles[layer.id] = profile(
                layer: layer,
                materialInstance: materialInstancesByLayerID[layer.id],
                materialPasses: materialPasses
            )
        }
        return profiles
    }

    private static func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").localizedLowercase
    }
}
