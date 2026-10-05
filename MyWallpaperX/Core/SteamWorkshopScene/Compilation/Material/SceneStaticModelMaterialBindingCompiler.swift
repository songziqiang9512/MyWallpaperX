import Foundation

/// Addresses the fixed model renderer's existing channels through a strict
/// authored interface proof. This does not execute a custom shader program.
nonisolated enum SceneStaticModelMaterialBindingCompiler {
    private struct Interface {
        let channel: SceneStaticModelMaterialBindings.Channel
        let name: String
        let type: SceneAuthoredShaderValueType
        let componentCount: Int
    }

    private static let interfaces: [Interface] = [
        .init(channel: .alpha, name: "g_TintAlpha", type: .float, componentCount: 1),
        .init(channel: .color, name: "g_TintColor", type: .float3, componentCount: 3),
        .init(channel: .brightness, name: "g_Brightness", type: .float, componentCount: 1),
    ]

    static func defaultAlbedoAssetPath(
        pass: SceneRenderDescriptor.MaterialPassDescriptor,
        shaderContracts: [SceneShaderContract]
    ) -> String? {
        guard pass.passIndex == 0,
              pass.textureSlots.first.flatMap({ $0 }) == nil,
              pass.userTextureInputs.first.flatMap({ $0 }) == nil,
              let shaderPath = pass.shaderPath else { return nil }
        let contracts = shaderContracts.filter {
            normalizedShader($0.identity) == normalizedShader(shaderPath)
        }
        guard contracts.count == 1, let contract = contracts.first else { return nil }
        return SceneResolvedMaterialShaderSchema.unconditionalColorAssetDefault(
            slot: 0, contract: contract, combos: pass.combos
        )?.value
    }

    static func compile(
        pass: SceneRenderDescriptor.MaterialPassDescriptor,
        shaderContracts: [SceneShaderContract]
    ) -> SceneStaticModelMaterialBindings {
        guard pass.passIndex == 0 else { return unavailable("material-pass-index") }
        guard let shaderPath = pass.shaderPath else { return unavailable("shader-reference") }
        let contracts = shaderContracts.filter {
            normalizedShader($0.identity) == normalizedShader(shaderPath)
        }
        guard contracts.count == 1, let contract = contracts.first,
              contract.diagnostics.isEmpty else { return unavailable("shader-contract") }
        if contract.sourceKind == .hostBuiltin {
            return .init(state: .hostBuiltin, bindings: [], rejectionReason: nil)
        }
        let fields = interfaces.map {
            SceneAuthoredShaderUniformLayout.Field(
                name: $0.name, stage: .fragment, type: $0.type, offset: 0
            )
        }
        guard let schemas = SceneResolvedMaterialShaderSchema.unconditionalStaticModelUniforms(
            fields, contract: contract, explicitCombos: pass.combos
        ) else { return unavailable("shader-interface-unproven") }

        var bindings: [SceneStaticModelMaterialBindings.Binding] = []
        for interface in interfaces {
            guard let schema = schemas[interface.name] else {
                return unavailable("\(interface.channel.rawValue)-interface")
            }
            let authored = pass.constantShaderValues.filter {
                schema.materialKeys.contains($0.key)
            }
            guard authored.count <= 1 else {
                return rejected("\(interface.channel.rawValue)-producer-conflict")
            }
            guard !pass.userShaderValues.keys.contains(where: schema.materialKeys.contains) else {
                return unavailable("\(interface.channel.rawValue)-user-shader-producer")
            }
            let key: String?
            let components: [Double]
            if let authored = authored.first {
                // The existing property target mapper only admits trimmed
                // names. Preserve its old route when an exact key cannot wire.
                if authored.value.userBinding != nil,
                   authored.key.isEmpty || authored.key != authored.key.trimmingCharacters(
                    in: .whitespacesAndNewlines
                   ) {
                    return unavailable("\(interface.channel.rawValue)-property-key")
                }
                if let state = valueShapeFailure(authored.value) {
                    return .init(
                        state: state, bindings: [],
                        rejectionReason: "\(interface.channel.rawValue)-producer-shape"
                    )
                }
                guard let value = authored.value.components else {
                    return rejected("\(interface.channel.rawValue)-components")
                }
                // The catalog's legacy projection can drop nonnumeric tokens.
                // A proven binding must account for the preserved input in full.
                let tokens = authored.value.rawValue.split(whereSeparator: {
                    $0 == " " || $0 == "," || $0 == "\t"
                })
                guard tokens.count == value.count,
                      zip(tokens, value).allSatisfy({ Double($0.0) == $0.1 }) else {
                    return rejected("\(interface.channel.rawValue)-numeric-input")
                }
                key = authored.key
                components = value
            } else {
                guard let fallback = schema.defaultValue,
                      fallback.authoredBindingKeys.isEmpty else {
                    return unavailable("\(interface.channel.rawValue)-default")
                }
                key = nil
                components = fallback.componentBitPatterns.map { Double(bitPattern: $0) }
            }
            guard components.count == interface.componentCount,
                  components.allSatisfy({ $0.isFinite && Float($0).isFinite }) else {
                return rejected("\(interface.channel.rawValue)-components")
            }
            bindings.append(.init(
                channel: interface.channel, uniformName: interface.name,
                materialKey: key, components: components
            ))
        }
        return .init(state: .authored, bindings: bindings, rejectionReason: nil)
    }

    private static func valueShapeFailure(
        _ value: SceneDocument.ShaderValue
    ) -> SceneStaticModelMaterialBindings.State? {
        // Unknown producer semantics keep the prior consumer. Proven malformed
        // values in the admitted static/user wrapper have a local reject.
        guard value.scriptSource == nil, value.scriptProperties == nil,
              value.timeline == nil, value.timelineDiagnostics.isEmpty else { return .unavailable }
        guard ["number", "string", "vector", "binding"].contains(value.valueKind) else {
            return .unavailable
        }
        switch value.bindingKeys.sorted() {
        case [], ["value"]:
            return value.userBinding == nil && value.userValueKind == nil ? nil : .rejected
        case ["user", "value"]:
            let valid = (value.userValueKind == .string && value.userBinding != nil)
                || (value.userValueKind == .null && value.userBinding == nil)
            return valid ? nil : .rejected
        default:
            return .unavailable
        }
    }

    private static func rejected(_ reason: String) -> SceneStaticModelMaterialBindings {
        .init(state: .rejected, bindings: [], rejectionReason: reason)
    }

    private static func unavailable(_ reason: String) -> SceneStaticModelMaterialBindings {
        .init(state: .unavailable, bindings: [], rejectionReason: reason)
    }

    private static func normalizedShader(_ path: String) -> String {
        var value = path.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        for suffix in [".vert", ".frag", ".json"] where value.hasSuffix(suffix) {
            value.removeLast(suffix.count)
            break
        }
        if value.hasPrefix("shaders/") { value.removeFirst("shaders/".count) }
        return value
    }
}
