import Foundation

/// A fail-closed projection of authored current-album-cover bindings onto a
/// layer source. This is intentionally narrower than general SceneScript or
/// Blend execution: only a normal, full-strength current-thumbnail binding is
/// admitted, so the source texture can be replaced without changing the
/// authored result. Previous-thumbnail transitions remain a separate contract.
nonisolated struct SceneMediaThumbnailBindingProgram {
    static let currentIdentity = "$mediaThumbnail"
    static let previousIdentity = "$mediaPreviousThumbnail"

    let currentLayerIDs: Set<Int>

    static let empty = SceneMediaThumbnailBindingProgram(currentLayerIDs: [])

    var hasConsumers: Bool { !currentLayerIDs.isEmpty }

    func reportLines() -> [String] {
        [
            "mediaThumbnailCurrentBindingCount: \(currentLayerIDs.count)",
            "mediaThumbnailCurrentBindingLayerIDs: "
                + currentLayerIDs.sorted().map(String.init).joined(separator: ","),
        ]
    }
}

enum SceneMediaThumbnailBindingCompiler {
    nonisolated static func compile(
        descriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR]
    ) -> SceneMediaThumbnailBindingProgram {
        let mediaVisibilityEffects = Set(scriptBindings.compactMap { binding -> EffectOwner? in
            guard binding.owner.kind == .effect,
                  binding.targetKey == "visible",
                  binding.valueType == .boolean,
                  binding.properties.isEmpty,
                  isHasThumbnailVisibilitySource(binding.source),
                  let layerID = binding.owner.objectID,
                  let effectIndex = binding.owner.effectIndex else {
                return nil
            }
            return EffectOwner(layerID: layerID, effectIndex: effectIndex)
        })

        var layerIDs = Set<Int>()
        for layer in descriptor.layers where layer.isImageRenderable {
            for (effectIndex, effect) in layer.effects.enumerated() {
                guard effect.visible != false
                        || mediaVisibilityEffects.contains(.init(
                            layerID: layer.id,
                            effectIndex: effectIndex
                        )),
                      isCurrentThumbnailReplacement(effect) else {
                    continue
                }
                layerIDs.insert(layer.id)
            }
        }
        return SceneMediaThumbnailBindingProgram(currentLayerIDs: layerIDs)
    }

    private struct EffectOwner: Hashable {
        let layerID: Int
        let effectIndex: Int
    }

    private nonisolated static func isCurrentThumbnailReplacement(
        _ effect: SceneRenderDescriptor.EffectDescriptor
    ) -> Bool {
        let path = normalized(effect.file)
        guard path == "effects/blend/effect.json" || path.hasSuffix("/blend/effect.json"),
              effect.passes.count == 1,
              let pass = effect.passes.first,
              pass.textureSlots.count == 2,
              pass.textureSlots[0] == nil,
              pass.textureSlots[1]?.isEmpty == false,
              pass.userTextureInputs.count == 2,
              pass.userTextureInputs[0] == nil,
              pass.userTextureInputs[1] == SceneEffectTextureInput(
                  kind: .system,
                  value: SceneMediaThumbnailBindingProgram.currentIdentity
              ),
              normalizedCombos(pass.combos) != nil,
              isFullStrength(pass.constantShaderValues) else {
            return false
        }
        return true
    }

    private nonisolated static func normalizedCombos(_ source: [String: Int]) -> [String: Int]? {
        let allowed = Set([
            "BLENDMODE", "TRANSFORMUV", "TRANSFORMREPEAT", "WRITEALPHA",
            "NUMBLENDTEXTURES", "OPACITYMASK",
        ])
        var result: [String: Int] = [:]
        for (key, value) in source {
            guard result.updateValue(value, forKey: key.uppercased()) == nil else { return nil }
        }
        guard result.keys.allSatisfy(allowed.contains),
              result["BLENDMODE", default: 0] == 0,
              result["TRANSFORMUV", default: 0] == 0,
              (0...2).contains(result["TRANSFORMREPEAT", default: 0]),
              result["NUMBLENDTEXTURES", default: 1] == 1,
              result["OPACITYMASK", default: 0] == 0,
              (0...1).contains(result["WRITEALPHA", default: 0]) else {
            return nil
        }
        return result
    }

    private nonisolated static func isFullStrength(
        _ constants: [String: SceneDocument.ShaderValue]
    ) -> Bool {
        guard constants.keys.allSatisfy({
            ["multiply", "alpha", "blendangle", "blendoffset", "blendscale"]
                .contains($0.lowercased())
        }) else { return false }
        return scalar(named: "multiply", in: constants, default: 1) == 1
            && scalar(named: "alpha", in: constants, default: 1) == 1
    }

    private nonisolated static func scalar(
        named name: String,
        in constants: [String: SceneDocument.ShaderValue],
        default defaultValue: Double
    ) -> Double? {
        guard let value = constants.first(where: {
            $0.key.caseInsensitiveCompare(name) == .orderedSame
        })?.value else { return defaultValue }
        guard value.userBinding == nil,
              let components = value.components,
              components.count == 1,
              let result = components.first,
              result.isFinite else { return nil }
        return result
    }

    private nonisolated static func isHasThumbnailVisibilitySource(_ source: String) -> Bool {
        let withoutBlocks = source.replacingOccurrences(
            of: #"/\*[\s\S]*?\*/"#,
            with: "",
            options: .regularExpression
        )
        let withoutLines = withoutBlocks.replacingOccurrences(
            of: #"//[^\n\r]*"#,
            with: "",
            options: .regularExpression
        )
        let compact = withoutLines.replacingOccurrences(
            of: #"\s+"#,
            with: "",
            options: .regularExpression
        )
        return compact.range(
            of: #"exportfunctionmediaThumbnailChanged\(([A-Za-z_$][A-Za-z0-9_$]*)\)\{thisObject\.visible=\1\.hasThumbnail;?\}"#,
            options: .regularExpression
        ) != nil
    }

    private nonisolated static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}
