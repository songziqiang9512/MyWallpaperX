import Foundation

nonisolated struct SceneParticleMaterialConstant: Equatable, Sendable {
    let components: [Double]
    let isStatic: Bool
}

nonisolated struct SceneParticleRefractionDeclaration: Equatable, Sendable {
    let normalTextureSource: SceneParticleTextureSource
    let amount: Float
    let overbright: Float
}

nonisolated enum SceneParticleRefractionPlanner {
    struct Plan: Equatable, Sendable {
        let colorReference: String
        let normalReference: String
        let amount: Float
        let overbright: Float
    }

    static func plan(for pass: SceneParticleMaterialPass) -> Plan? {
        guard let renderState = SceneMaterialRenderState.compile(
                  blending: pass.blending,
                  depthTest: pass.depthTest,
                  depthWrite: pass.depthWrite,
                  cullMode: pass.cullMode,
                  alphaWriting: pass.alphaWriting,
                  missingBlending: .translucent
              ),
              pass.passIndex == 0,
              pass.combos["REFRACT"] == 1,
              pass.combos.allSatisfy({
                  $0.key == "REFRACT"
                      || (($0.key == "CUTOUT" || $0.key == "LIGHTING") && $0.value == 0)
              }),
              pass.textureSlots.count == 2,
              let color = pass.textureSlots[0],
              let normal = pass.textureSlots[1],
              !color.isEmpty,
              !normal.isEmpty,
              !pass.hasUserTextureInputs,
              !pass.hasUserShaderValues,
              renderState.depthTest == .disabled,
              renderState.depthWrite == .disabled,
              renderState.cullMode == .noCull,
              [.unspecified, .default].contains(renderState.alphaWriting),
              [.translucent, .additive].contains(renderState.blending) else {
            return nil
        }

        let allowed = Set([
            "ui_editor_properties_refract_amount",
            "ui_editor_properties_overbright",
            "ui_editor_properties_cutout_start",
            "ui_editor_properties_cutout_end",
            "ui_editor_properties_cutout_opacity",
        ])
        guard pass.constantValues.keys.allSatisfy(allowed.contains),
              pass.constantValues.allSatisfy({ $0.value.isStatic }),
              pass.constantValues.allSatisfy({ value in
                  value.value.components.count == 1
                      && value.value.components[0].isFinite
              }),
              pass.combos["CUTOUT"] == 0
                  || pass.constantValues.keys.allSatisfy({
                      !$0.hasPrefix("ui_editor_properties_cutout_")
                  }) else {
            return nil
        }

        let amount = scalar(
            "ui_editor_properties_refract_amount",
            in: pass.constantValues,
            default: 0.05
        )
        let overbright = scalar(
            "ui_editor_properties_overbright",
            in: pass.constantValues,
            default: 1
        )
        guard amount.isFinite, overbright.isFinite, overbright >= 0 else { return nil }
        return Plan(
            colorReference: color,
            normalReference: normal,
            amount: amount,
            overbright: overbright
        )
    }

    private static func scalar(
        _ key: String,
        in values: [String: SceneParticleMaterialConstant],
        default fallback: Float
    ) -> Float {
        values[key]?.components.first.map(Float.init) ?? fallback
    }
}
