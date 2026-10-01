import Foundation

/// Launch-immutable diffuse-lighting intent for built-in image materials.
/// Custom shader sources retain their existing frontend and output authority.
nonisolated struct SceneBaseMaterialLightingProfile: Equatable, Sendable {
    let lightingEnabled: Bool
    let normalTextureSlotPath: String?

    static let disabled = SceneBaseMaterialLightingProfile(
        lightingEnabled: false, normalTextureSlotPath: nil
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
        // Until authored arbitrary-map slot semantics are established, only a
        // data-purpose semantic registry entry supplies a normal. Absent maps
        // use the same plane normal as a neutral normal texture.
        let slots = materialInstance?.textureSlots.isEmpty == false
            ? materialInstance!.textureSlots : (pass?.textureSlots ?? [])
        let normalTextureSlotPath = slots.first { slot in
            guard let slot, let path = SceneVFSAssetPath(slot) else { return false }
            return SceneStockTextureSemanticRegistry.purpose(for: path) == .normal
        } ?? nil
        return SceneBaseMaterialLightingProfile(
            lightingEnabled: lightingEnabled,
            normalTextureSlotPath: normalTextureSlotPath
        )
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
