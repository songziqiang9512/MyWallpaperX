import Foundation

/// Lowers the bounded stock `genericparticle` material profile into the one
/// particle Metal executor. Unknown shader combinations remain unavailable.
nonisolated enum SceneParticlePipelineRenderStateCompiler {
    static func compile(
        _ state: SceneMaterialRenderState,
        definition: SceneParticleDefinition,
        materialPass: SceneParticleMaterialPass?
    ) -> SceneParticlePipelineRenderState? {
        guard [.unspecified, .default].contains(state.alphaWriting),
              let overbright = overbright(in: materialPass) else { return nil }

        let spriteProfile = supportsSpriteStateProfile(
            definition: definition, materialPass: materialPass
        )
        let blendMode: SceneParticlePipelineBlendMode
        switch state.blending {
        case .translucent: blendMode = .translucent
        case .additive: blendMode = .additive
        case .alphaToCoverage:
            guard spriteProfile, let materialPass, materialPass.passIndex == 0,
                  materialPass.constantValues.keys.allSatisfy({
                      $0 == "ui_editor_properties_overbright"
                  }),
                  state.cullMode == .noCull, state.depthTest == .disabled,
                  state.depthWrite == .disabled else { return nil }
            blendMode = .alphaToCoverage
        case .normal: return nil
        }

        let needsSpriteStateProfile = state.cullMode == .normal
            || state.depthTest == .enabled
            || state.depthWrite == .enabled
        if needsSpriteStateProfile, !spriteProfile {
            return nil
        }

        return SceneParticlePipelineRenderState(
            blendMode: blendMode,
            cullMode: state.cullMode == .normal ? .back : .none,
            depthTestEnabled: state.depthTest == .enabled,
            usesSceneCamera: spriteProfile,
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
        guard value.isStatic, value.components.count == 1,
              let authored = value.components.first,
              authored.isFinite, (0 ... 64).contains(authored) else { return nil }
        return Float(authored)
    }

    private static func supportsSpriteStateProfile(
        definition: SceneParticleDefinition,
        materialPass: SceneParticleMaterialPass?
    ) -> Bool {
        guard let materialPass,
              !materialPass.hasUserTextureInputs,
              !materialPass.hasUserShaderValues,
              materialPass.combos.allSatisfy({ key, value in
                  ["REFRACT", "CUTOUT", "LIGHTING"].contains(key.uppercased())
                      && value == 0
              }),
              definition.renderers.count == 1,
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
