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

        let blendMode: SceneParticlePipelineBlendMode
        switch state.blending {
        case .translucent: blendMode = .translucent
        case .additive: blendMode = .additive
        case .normal: return nil
        }

        let needsScreenSpriteProfile = state.cullMode == .normal
            || state.depthTest == .enabled
            || state.depthWrite == .enabled
        if needsScreenSpriteProfile,
           !supportsScreenSpriteProfile(
               definition: definition,
               materialPass: materialPass
           ) {
            return nil
        }

        return SceneParticlePipelineRenderState(
            blendMode: blendMode,
            cullMode: state.cullMode == .normal ? .back : .none,
            depthTestEnabled: state.depthTest == .enabled,
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

    private static func supportsScreenSpriteProfile(
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
              !definition.flags.isWorldSpace,
              !definition.flags.usesPerspective,
              definition.renderers.count == 1,
              let renderer = definition.renderers.first,
              !renderer.isWorldSpace,
              renderer.rawFlags == 0,
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
