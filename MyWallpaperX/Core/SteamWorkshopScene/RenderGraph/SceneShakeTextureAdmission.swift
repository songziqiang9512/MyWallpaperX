import Foundation

nonisolated struct SceneShakeTexturePaths {
    let flow: String
    let phase: String?
    let mask: String?
}

/// Shake 的实例纹理槽合同。
///
/// `g_Texture3` 是可选 opacity mask。官方编辑器根据该槽是否绑图自动选择
/// `MASK` shader 变体，因此实例 JSON 不需要显式写 `MASK=1`。
enum SceneShakeTextureAdmission {
    nonisolated static func paths(
        from pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor,
        profile: SceneShakeShaderProfile
    ) -> SceneShakeTexturePaths? {
        let supportsOmittedPhase = profile == .legacyUnconditionalPhase
            || (profile == .timeOffsetCombo
                && comboValue("TIMEOFFSET", in: pass.combos) != 1)
        guard (pass.textureSlots.count == 3
                || pass.textureSlots.count == 4
                || (supportsOmittedPhase && pass.textureSlots.count == 2)),
              pass.textureSlots[0] == nil,
              let flow = pass.textureSlots[1],
              !flow.isEmpty else {
            return nil
        }

        let phase = pass.textureSlots.indices.contains(2) ? pass.textureSlots[2] : nil
        let mask = pass.textureSlots.indices.contains(3) ? pass.textureSlots[3] : nil
        guard phase?.isEmpty != true,
              mask?.isEmpty != true,
              pass.textureSlots.count != 4 || mask != nil else {
            return nil
        }
        if profile == .timeOffsetCombo {
            let usesPhase = comboValue("TIMEOFFSET", in: pass.combos) == 1
            guard usesPhase == (phase != nil) else { return nil }
        }
        let expected = [flow]
            + (phase.map { [$0] } ?? [])
            + (mask.map { [$0] } ?? [])
        guard pass.texturePaths == expected else { return nil }

        // legacy 实例会显式写 shader 默认 `util/white`。白 phase 等价于 2π≡0，
        // 归一为 nil 后走 pipeline 内置 R8 白回退。
        let normalizedPhase = profile == .legacyUnconditionalPhase
            && phase.map(normalized) == "util/white" ? nil : phase
        return SceneShakeTexturePaths(flow: flow, phase: normalizedPhase, mask: mask)
    }

    nonisolated static func validResolvedMaterial(
        _ material: SceneResolvedMaterialNode,
        flowPath: String,
        phasePath: String?,
        maskPath: String?,
        profile: SceneShakeShaderProfile
    ) -> Bool {
        let resolvedPhase = assetPath(material.textureSlots[2])
        let phaseMatches = resolvedPhase == phasePath
            || (profile == .legacyUnconditionalPhase
                && phasePath == nil
                && resolvedPhase.map(normalized) == "util/white")
        guard normalized(material.shaderPath) == "effects/shake",
              material.textureSlots.count == 8,
              assetPath(material.textureSlots[1]) == flowPath,
              phaseMatches,
              assetPath(material.textureSlots[3]) == maskPath,
              material.textureSlots.enumerated().allSatisfy({
                  [1, 2, 3].contains($0.offset) || $0.element == nil
              }),
              SceneAuthoredShakePlanner.validCombos(
                  material.combos,
                  profile: profile
              ),
              SceneAuthoredShakePlanner.hasValidParameters(material.constants) else {
            return false
        }
        return material.renderState.blending?.lowercased() == "normal"
            && material.renderState.depthTest?.lowercased() == "disabled"
            && material.renderState.depthWrite?.lowercased() == "disabled"
            && material.renderState.cullMode?.lowercased() == "nocull"
    }

    private nonisolated static func assetPath(
        _ slot: SceneResolvedMaterialNode.TextureSlot?
    ) -> String? {
        guard let slot, slot.candidates.count == 1,
              slot.provenance == .instance,
              case .asset(let path) = slot.source else {
            return nil
        }
        return path
    }

    private nonisolated static func comboValue(
        _ key: String,
        in authored: [String: Int]
    ) -> Int? {
        authored.first { $0.key.uppercased() == key }?.value
    }

    private nonisolated static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}
