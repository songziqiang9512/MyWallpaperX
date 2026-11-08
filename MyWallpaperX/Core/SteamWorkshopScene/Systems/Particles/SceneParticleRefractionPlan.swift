import Foundation

nonisolated struct SceneParticleMaterialConstant: Equatable, Sendable {
    let components: [Double]
    let isStatic: Bool
}

nonisolated struct SceneParticleRefractionDeclaration: Equatable, Sendable {
    let normalTextureSource: SceneParticleTextureSource?
    let amount: Float
    let overbright: Float
    var usesAmbientLighting: Bool = false
    var cutout: SIMD3<Float>? = nil
}

nonisolated enum SceneParticleRefractionPlanner {
    struct Plan: Equatable, Sendable {
        let colorReference: String
        let normalReference: String?
        let amount: Float
        let overbright: Float
        let usesAmbientLighting: Bool
        let cutout: SIMD3<Float>?
    }

    static func plan(
        for pass: SceneParticleMaterialPass,
        renderState: SceneMaterialRenderState,
        supportsAmbientLighting: Bool = false
    ) -> Plan? {
        let usesAmbientLighting = supportsAmbientLighting && pass.combos["LIGHTING"] == 1
        let usesCutout = pass.combos["CUTOUT"] == 1
        // Both unlit and ambient-only plans have no direct-light sidedness term.
        guard pass.passIndex == 0,
              pass.combos["REFRACT"] == 1,
              pass.combos.allSatisfy({
                  $0.key == "REFRACT"
                      || ($0.key == "CUTOUT" && ($0.value == 0 || usesCutout))
                      || ($0.key == "LIGHTING" && ($0.value == 0 || usesAmbientLighting))
                      || ($0.key == "DOUBLESIDEDLIGHTING" && ($0.value == 0 || $0.value == 1))
              }),
              (1 ... 2).contains(pass.textureSlots.count),
              let color = pass.textureSlots[0],
              !color.isEmpty,
              !pass.hasUserTextureInputs,
              !pass.hasUserShaderValues,
              renderState.depthWrite == .disabled,
              [.unspecified, .default].contains(renderState.alphaWriting),
              [.translucent, .additive].contains(renderState.blending) else {
            return nil
        }

        let normal = pass.textureSlots.count == 2 ? pass.textureSlots[1] : nil

        let allowed = Set([
            "ui_editor_properties_refract_amount",
            "ui_editor_properties_overbright",
            "ui_editor_properties_cutout_start",
            "ui_editor_properties_cutout_end",
            "ui_editor_properties_cutout_opacity",
        ])
        guard pass.constantValues.allSatisfy({ key, value in
            guard allowed.contains(key) else { return false }
            if !usesCutout && key.hasPrefix("ui_editor_properties_cutout_") { return true }
            return value.isStatic && value.components.count == 1 && value.components[0].isFinite
        }) else {
            return nil
        }

        let cutout: SIMD3<Float>?
        if usesCutout {
            let value = SIMD3(
                scalar("ui_editor_properties_cutout_start", in: pass.constantValues, default: 0.1),
                scalar("ui_editor_properties_cutout_end", in: pass.constantValues, default: 0.2),
                scalar("ui_editor_properties_cutout_opacity", in: pass.constantValues, default: 1)
            )
            guard value.x.isFinite, value.y.isFinite, value.z.isFinite,
                  value.x < value.y, (0 ... 1).contains(value.z) else { return nil }
            cutout = value
        } else {
            cutout = nil
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
            overbright: overbright,
            usesAmbientLighting: usesAmbientLighting,
            cutout: cutout
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
