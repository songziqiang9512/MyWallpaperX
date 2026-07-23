import Foundation

extension SceneAuthoredEffectRenderPlanner {
    nonisolated static func resolvedBindings(
        _ authored: [SceneEffectDefinition.Binding],
        chainInput: Plan.TextureIdentity,
        key: Plan.EffectKey,
        definitions: [String: SceneEffectDefinition.Framebuffer],
        passIndex: Int,
        blockers: inout [Plan.Blocker]
    ) -> [Plan.Binding] {
        var usedSlots = Set<Int>()
        return authored.map { binding in
            if binding.conditions != nil {
                blockers.append(blocker(
                    key,
                    passIndex: passIndex,
                    reason: .unsupportedCondition,
                    detail: "Binding \(binding.name ?? "<missing>") has a runtime condition."
                ))
            }
            if let slot = binding.index, slot >= 0, usedSlots.insert(slot).inserted {
                // Authored indices remain sparse; later resolution must not compact slots.
            } else {
                blockers.append(blocker(
                    key,
                    passIndex: passIndex,
                    reason: .invalidBinding,
                    detail: "Binding slots must be present, non-negative, and unique per pass."
                ))
            }
            let source: Plan.TextureIdentity
            if binding.name == "previous" {
                source = chainInput
            } else if let name = binding.name, definitions[name] != nil {
                source = framebufferTexture(key, name: name)
            } else {
                source = texture(.unresolved, effect: key, name: binding.name)
                blockers.append(blocker(
                    key,
                    passIndex: passIndex,
                    reason: .unknownTexture,
                    detail: "Binding \(binding.name ?? "<missing>") is not previous or a declared framebuffer."
                ))
            }
            return Plan.Binding(
                slot: binding.index,
                authoredName: binding.name,
                texture: source,
                conditions: binding.conditions
            )
        }
    }

    nonisolated static func resolveFramebuffer(
        _ name: String,
        key: Plan.EffectKey,
        definitions: [String: SceneEffectDefinition.Framebuffer],
        passIndex: Int,
        blockers: inout [Plan.Blocker]
    ) -> Plan.TextureIdentity {
        guard definitions[name] != nil else {
            blockers.append(blocker(
                key,
                passIndex: passIndex,
                reason: .unknownTexture,
                detail: "Framebuffer \(name) is not declared by the effect."
            ))
            return texture(.unresolved, effect: key, name: name)
        }
        return framebufferTexture(key, name: name)
    }

    nonisolated static func targetExtent(
        _ framebuffer: SceneEffectDefinition.Framebuffer
    ) -> Plan.TargetExtent {
        let scale = framebuffer.scale?.numberValue
        let fit = framebuffer.fit?.numberValue
        let width = framebuffer.width?.numberValue
        let height = framebuffer.height?.numberValue
        let declared = [scale != nil, fit != nil, width != nil || height != nil].filter { $0 }.count
        guard declared <= 1 else { return .init(kind: .unsupported, first: nil, second: nil) }
        if let scale, scale > 0 { return .init(kind: .scale, first: scale, second: nil) }
        if let fit, fit > 0 { return .init(kind: .fit, first: fit, second: nil) }
        if let width, let height, width > 0, height > 0 {
            return .init(kind: .absolute, first: width, second: height)
        }
        if scale == nil, fit == nil, width == nil, height == nil {
            return .init(kind: .input, first: nil, second: nil)
        }
        return .init(kind: .unsupported, first: nil, second: nil)
    }

    nonisolated static func commandCompatible(
        _ kind: Plan.NodeKind,
        source: SceneEffectDefinition.Framebuffer,
        target: SceneEffectDefinition.Framebuffer
    ) -> Bool {
        guard storageCompatible(source, target) else { return false }
        guard kind == .swap else { return kind == .copy || kind == .unknownCommand }
        return source.unique == target.unique
            && source.uvs == target.uvs
            && source.clear == target.clear
            && source.conditions == target.conditions
    }

    nonisolated private static func storageCompatible(
        _ lhs: SceneEffectDefinition.Framebuffer,
        _ rhs: SceneEffectDefinition.Framebuffer
    ) -> Bool {
        targetExtent(lhs) == targetExtent(rhs) && lhs.format == rhs.format
    }

    nonisolated static func validClear(_ clear: SceneJSONValue?) -> Bool {
        guard let clear else { return true }
        let components: [Double]
        switch clear {
        case .string(let value):
            components = value.split(whereSeparator: { $0.isWhitespace }).compactMap {
                Double($0)
            }
            guard components.count == value.split(whereSeparator: { $0.isWhitespace }).count else {
                return false
            }
        case .array(let values):
            components = values.compactMap(\.numberValue)
            guard components.count == values.count else { return false }
        default:
            return false
        }
        return components.count == 4 && components.allSatisfy(\.isFinite)
    }

    nonisolated static func normalizedPath(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").localizedLowercase
    }

    nonisolated static func framebufferTexture(
        _ key: Plan.EffectKey,
        name: String
    ) -> Plan.TextureIdentity {
        texture(.framebuffer, effect: key, name: name)
    }

    nonisolated static func texture(
        _ kind: Plan.TextureKind,
        layerID: Int? = nil,
        effect: Plan.EffectKey? = nil,
        name: String? = nil
    ) -> Plan.TextureIdentity {
        .init(kind: kind, layerID: layerID ?? effect?.layerID ?? -1, effect: effect, name: name)
    }

    nonisolated static func blocker(
        _ effect: Plan.EffectKey,
        passIndex: Int? = nil,
        reason: Plan.BlockerReason,
        detail: String
    ) -> Plan.Blocker {
        .init(effect: effect, definitionPassIndex: passIndex, reason: reason, detail: detail)
    }

    nonisolated static let supportedFramebufferFormats = Set([
        "r8", "rg88", "r16f", "rg1616f", "rgba8888", "rgba_backbuffer",
    ])
}
