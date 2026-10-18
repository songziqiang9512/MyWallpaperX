import Foundation

/// Launch-only model defaults. Texture publication and this complete built-in
/// recipe must both succeed before an ordinary dynamic image becomes available.
/// Full source Programs retain their existing compiler and runtime proof.
nonisolated struct ScenePreparedImageMaterialCatalog {
    let profiles: [String: SceneBaseMaterialLightingProfile]
    let builtinModelPaths: Set<String>
    let renderStates: [String: SceneMaterialRenderState]

    init(descriptor: SceneRenderDescriptor) {
        let passesByMaterial = Dictionary(grouping: descriptor.materialPasses) {
            SceneModelResourceIdentity($0.materialPath).value
        }
        let linksByModel = Dictionary(grouping: descriptor.modelMaterialLinks) {
            SceneModelResourceIdentity($0.modelPath).value
        }
        var profiles: [String: SceneBaseMaterialLightingProfile] = [:]
        var builtinModels = Set<String>()
        for (model, links) in linksByModel {
            let passes = links.compactMap(\.materialPath).flatMap {
                passesByMaterial[SceneModelResourceIdentity($0).value] ?? []
            }
            if passes.contains(where: { $0.shaderPath.map(SceneBuiltinShaderIdentity.isImage) == true }) {
                builtinModels.insert(model)
            }
            guard links.count == 1, passes.count == 1, let pass = passes.first,
                  let profile = Self.profile(pass: pass,
                    preparedState: descriptor.preparedImageMaterialStatesByModelPath?[model]) else { continue }
            profiles[model] = profile
        }
        self.profiles = profiles
        builtinModelPaths = builtinModels
        renderStates = (descriptor.preparedImageMaterialStatesByModelPath ?? [:]).filter {
            profiles[$0.key] != nil
        }
    }

    private static func profile(
        pass: SceneRenderDescriptor.MaterialPassDescriptor,
        preparedState: SceneMaterialRenderState?
    ) -> SceneBaseMaterialLightingProfile? {
        // The alpha-sensitive official fixture qualifies default only for this
        // lit built-in consumer, not a generic render-state/write-mask mapping.
        let supportsDefaultAlpha = pass.shaderPath?.lowercased() == "genericimage2"
            && pass.combos["LIGHTING"] == 1
        guard pass.passIndex == 0,
              pass.shaderPath.map(SceneBuiltinShaderIdentity.isImage) == true,
              pass.textureSlots.count == 1, let texture = pass.textureSlots[0],
              !texture.isEmpty, pass.texturePaths == [texture],
              pass.userTextureInputs.allSatisfy({ $0 == nil }), pass.userShaderValues.isEmpty,
              pass.combos.allSatisfy({
                  ($0.key == "VERSION" && $0.value == 2)
                      || ($0.key == "LIGHTING" && (0 ... 1).contains($0.value))
              }),
              pass.constantShaderValues.keys.allSatisfy({ ["metallic", "roughness"].contains($0) }),
              pass.constantShaderValues.isEmpty || pass.combos["LIGHTING"] == 1,
              let state = preparedState ?? SceneMaterialRenderState.compile(
                blending: pass.blending, depthTest: pass.depthTest,
                depthWrite: pass.depthWrite, cullMode: pass.cullMode, alphaWriting: pass.alphaWriting),
              state.blending == .translucent,
              preparedState != nil || (state.depthTest == .disabled
                && state.depthWrite == .disabled && state.cullMode == .noCull),
              state.alphaWriting == .unspecified
                || (state.alphaWriting == .default && supportsDefaultAlpha) else { return nil }
        for key in pass.constantShaderValues.keys {
            guard SceneMaterialPropertyBindingCompiler.staticComponents(key, instance: nil,
                pass: pass, count: 1, fallback: [], requiresCompleteScalar: true) != nil else { return nil }
        }
        return SceneBaseMaterialLightingProfileCompiler.profile(
            layerID: 0, usesPuppet: false, materialInstance: nil,
            materialPasses: [pass], materialPropertyTargets: [], builtinSurface: true)
    }
}
