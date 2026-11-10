import Foundation

/// Addresses the fixed model renderer's existing channels through a strict
/// authored interface proof. This does not execute a custom shader program.
nonisolated struct SceneStaticModelMaterialBindingCompiler {
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

    private static let fields = interfaces.map {
        SceneAuthoredShaderUniformLayout.Field(
            name: $0.name, stage: .fragment, type: $0.type, offset: 0
        )
    }

    private struct InterfaceKey: Hashable {
        let shader: String
        let combos: [String: Int]
    }

    private let contractsByShader: [String: SceneShaderContract]
    private var interfaceProofs: [InterfaceKey: [String: SceneResolvedMaterialShaderSchema.Uniform]?] = [:]

    init(shaderContracts: [SceneShaderContract]) {
        contractsByShader = Dictionary(grouping: shaderContracts) { Self.normalizedShader($0.identity) }
            .compactMapValues { $0.count == 1 ? $0[0] : nil }
    }

    func defaultAlbedoAssetPath(pass: SceneRenderDescriptor.MaterialPassDescriptor) -> String? {
        guard pass.passIndex == 0,
              pass.textureSlots.first.flatMap({ $0 }) == nil,
              pass.userTextureInputs.first.flatMap({ $0 }) == nil,
              let shaderPath = pass.shaderPath,
              let contract = contractsByShader[Self.normalizedShader(shaderPath)] else { return nil }
        return SceneResolvedMaterialShaderSchema.unconditionalColorAssetDefault(
            slot: 0, contract: contract, combos: pass.combos
        )?.value
    }

    mutating func compile(pass: SceneRenderDescriptor.MaterialPassDescriptor) -> SceneStaticModelMaterialBindings {
        guard pass.passIndex == 0 else { return unavailable("material-pass-index") }
        guard let shaderPath = pass.shaderPath else { return unavailable("shader-reference") }
        let shader = Self.normalizedShader(shaderPath)
        guard let contract = contractsByShader[shader], contract.diagnostics.isEmpty else {
            return unavailable("shader-contract")
        }
        if contract.sourceKind == .hostBuiltin {
            return .init(state: .hostBuiltin, bindings: [], rejectionReason: nil)
        }
        let proofKey = InterfaceKey(shader: shader, combos: pass.combos)
        let proof: [String: SceneResolvedMaterialShaderSchema.Uniform]?
        if let prepared = interfaceProofs[proofKey] {
            proof = prepared
        } else {
            proof = SceneResolvedMaterialShaderSchema.unconditionalStaticModelUniforms(
                Self.fields, contract: contract, explicitCombos: pass.combos
            )
            // updateValue retains a failed proof; subscript assignment of nil would remove it.
            interfaceProofs.updateValue(proof, forKey: proofKey)
        }
        guard let schemas = proof else { return unavailable("shader-interface-unproven") }

        var bindings: [SceneStaticModelMaterialBindings.Binding] = []
        for interface in Self.interfaces {
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
                if let state = Self.valueShapeFailure(authored.value) {
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

    private func rejected(_ reason: String) -> SceneStaticModelMaterialBindings {
        .init(state: .rejected, bindings: [], rejectionReason: reason)
    }

    private func unavailable(_ reason: String) -> SceneStaticModelMaterialBindings {
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
