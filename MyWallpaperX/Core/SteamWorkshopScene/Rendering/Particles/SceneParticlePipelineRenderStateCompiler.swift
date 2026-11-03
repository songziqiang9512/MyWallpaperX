import Foundation

/// Shared material/raster state; geometry and camera selection remain separate.
nonisolated enum SceneParticlePipelineRenderStateCompiler {
    static func compile(
        _ state: SceneMaterialRenderState,
        definition: SceneParticleDefinition,
        materialPass: SceneParticleMaterialPass?,
        isRefraction: Bool = false
    ) -> SceneParticlePipelineRenderState? {
        guard [.unspecified, .default].contains(state.alphaWriting),
              let overbright = overbright(in: materialPass) else { return nil }

        let ordinaryInputs = supportsOrdinaryMaterialProfile(materialPass)
        let usesSceneCamera = selectsSceneCamera(definition) && ordinaryInputs
        let blendMode: SceneParticlePipelineBlendMode
        switch state.blending {
        case .translucent: blendMode = .translucent
        case .additive: blendMode = .additive
        case .alphaToCoverage:
            guard ordinaryInputs, let materialPass, materialPass.passIndex == 0,
                  materialPass.constantValues.keys.allSatisfy({
                      $0 == "ui_editor_properties_overbright"
                  }) else { return nil }
            blendMode = .alphaToCoverage
        case .normal: return nil
        }

        if state.requiresDepthAttachment, !ordinaryInputs, !isRefraction {
            return nil
        }

        return SceneParticlePipelineRenderState(
            blendMode: blendMode,
            cullMode: state.cullMode == .normal ? .back : .none,
            depthTestEnabled: state.depthTest == .enabled,
            usesSceneCamera: usesSceneCamera,
            depthWriteEnabled: state.depthWrite == .enabled,
            overbright: overbright
        )
    }

    private static func overbright(
        in materialPass: SceneParticleMaterialPass?
    ) -> Float? {
        guard let value = materialPass?.constantValues[
            "ui_editor_properties_overbright"
        ] else { return 1 }
        guard value.isStatic, value.components.count == 1 else { return nil }
        let scalar = Float(value.components[0])
        return scalar.isFinite && scalar >= 0 ? scalar : nil
    }

    private static func supportsOrdinaryMaterialProfile(
        _ materialPass: SceneParticleMaterialPass?
    ) -> Bool {
        guard let materialPass,
              !materialPass.hasUserTextureInputs,
              !materialPass.hasUserShaderValues,
              materialPass.combos.allSatisfy({ key, value in
                  ["REFRACT", "CUTOUT", "LIGHTING"].contains(key.uppercased())
                      && value == 0
              }) else { return false }
        return true
    }

    // This selects the existing coordinate convention, not execution rights.
    private static func selectsSceneCamera(_ definition: SceneParticleDefinition) -> Bool {
        guard definition.renderers.count == 1,
              let renderer = definition.renderers.first,
              renderer.rawFlags == 0 || renderer.rawFlags == 1,
              renderer.axis == nil,
              !renderer.hasMalformedFields,
              renderer.unsupportedFieldNames.isEmpty,
              renderer.orientation.map({
                  $0.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
              }).map({ $0.isEmpty || $0 == "screen" }) ?? true,
              !definition.diagnostics.contains(where: {
                  $0.kind == .malformedComponent && $0.path.hasPrefix("renderer[")
              }) else { return false }
        return renderer.kind == .sprite
    }
}
