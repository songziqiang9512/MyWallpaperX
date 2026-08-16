import Foundation

nonisolated enum SceneResolvedMaterialTemplateCompiler {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Template = SceneResolvedMaterialTemplate
    typealias Failure = SceneResolvedMaterialFailure

    private struct GraphContext {
        let node: Graph.Node
        let effect: Graph.Effect
        let textureUniverse: Set<Graph.TextureIdentity>
    }

    static func compile(
        material: SceneResolvedMaterialNode, graph: Graph,
        shaderContract: SceneShaderContract,
        provenSceneScriptValueTargets: Set<SceneDynamicTarget> = []
    ) -> Result<Template, Failure> {
        do {
            let context = try graphContext(material, graph: graph)
            try validateShader(material.shaderPath, contract: shaderContract)
            let textures = try textureSlots(material.textureSlots, context: context)
            let uniforms = try uniformDeclarations(
                material,
                node: context.node,
                provenSceneScriptValueTargets: provenSceneScriptValueTargets
            )
            guard let state = SceneMaterialRenderState.compile(
                blending: material.renderState.blending,
                depthTest: material.renderState.depthTest,
                depthWrite: material.renderState.depthWrite,
                cullMode: material.renderState.cullMode,
                alphaWriting: material.renderState.alphaWriting
            ) else { throw Failure(phase: .state, code: .renderStateInvalid) }
            let combos = material.combos.sorted { $0.key < $1.key }.map {
                Template.Combo(name: $0.key, value: $0.value)
            }
            guard let role = graphRole(context),
                  let template = Template.validated(
                    textureSlots: textures.slots,
                    combos: combos,
                    uniformDeclarations: uniforms.values,
                    renderState: state,
                    graphRole: role,
                    shaderContract: shaderContract,
                    diagnosticProvenance: .init(
                        nodeIndex: material.nodeIndex,
                        authoredShaderPath: material.shaderPath,
                        contractIdentity: shaderContract.identity,
                        contractCanonicalSHA256: shaderContract.canonicalSHA256,
                        textureSources: textures.diagnostics,
                        uniformSources: uniforms.diagnostics
                    )
                  ) else {
                throw Failure(phase: .invariant, code: .identityInvariant)
            }
            return .success(template)
        } catch {
            return .failure(error as? Failure
                ?? Failure(phase: .invariant, code: .identityInvariant))
        }
    }

    private static func graphContext(_ material: SceneResolvedMaterialNode, graph: Graph) throws -> GraphContext {
        guard graph.blockers.isEmpty, !graph.effects.isEmpty
        else { throw graphFailure("blocked-or-empty") }
        let effectsByKey = Dictionary(grouping: graph.effects, by: \.key)
        let nodesByIndex = Dictionary(grouping: graph.nodes, by: \.nodeIndex)
        guard effectsByKey.values.allSatisfy({ $0.count == 1 }),
              nodesByIndex.values.allSatisfy({ $0.count == 1 })
        else { throw graphFailure("duplicate-effect-or-node") }

        let effectKeys = Set(effectsByKey.keys)
        var owners: [Int: Graph.EffectKey] = [:]
        for effect in graph.effects {
            guard effect.key.layerID == graph.layerID,
                  !effect.nodeIndices.isEmpty,
                  Set(effect.nodeIndices).count == effect.nodeIndices.count,
                  SceneResolvedMaterialEffectIngress.accepts(effect.input, layerID: graph.layerID, owner: effect.key),
                  validTexture(effect.output, layerID: graph.layerID, effects: effectKeys),
                  effect.output.kind == .effectOutput,
                  effect.output.effect == effect.key else {
                throw graphFailure("invalid-effect")
            }
            for index in effect.nodeIndices {
                guard owners.updateValue(effect.key, forKey: index) == nil
                else { throw graphFailure("node-partition-overlap") }
            }
        }
        guard Set(owners.keys) == Set(nodesByIndex.keys)
        else { throw graphFailure("node-partition-incomplete") }

        let targets = graph.renderTargets.map(\.texture)
        guard Set(targets).count == targets.count,
              targets.allSatisfy({
                  $0.kind == .framebuffer
                      && validTexture($0, layerID: graph.layerID, effects: effectKeys)
              }) else { throw graphFailure("invalid-render-target") }
        let universe = Set(graph.effects.flatMap { [$0.input, $0.output] } + targets)
        guard graph.finalOutput.kind == .effectOutput,
              universe.contains(graph.finalOutput)
        else { throw graphFailure("invalid-final-output") }
        for node in graph.nodes {
            guard let owner = owners[node.nodeIndex], node.effect == owner,
                  let effect = effectsByKey[owner]?.first,
                  validNodeTextures(node, effect: effect, universe: universe)
            else { throw graphFailure("invalid-node-owner-or-texture") }
        }
        guard let node = nodesByIndex[material.nodeIndex]?.first,
              let owner = owners[material.nodeIndex],
              let effect = effectsByKey[owner]?.first,
              node.kind == .material
        else { throw graphFailure("material-node-invalid") }
        return .init(node: node, effect: effect, textureUniverse: universe)
    }

    private static func validateShader(_ authoredPath: String, contract: SceneShaderContract) throws {
        guard let authored = normalizedShaderPath(authoredPath),
              let identity = normalizedShaderPath(contract.identity),
              authored == identity
        else { throw Failure(phase: .shaderContract, code: .shaderIdentityMismatch) }
        guard contract.sourceKind == .authoredSource,
              SceneShaderMalformedMetadataAdmission.allowsDiagnostics(in: contract),
              contract.stages.count == 2,
              Set(contract.stages.map(\.kind)) == Set([.vertex, .fragment])
        else { throw Failure(phase: .shaderContract, code: .shaderContractInvalid) }
        guard contract.sourceGraph != nil
        else { throw Failure(phase: .shaderContract, code: .shaderSourceGraphMissing) }
    }

    private typealias TextureProjection = (
        slots: [Template.TextureSlot?],
        diagnostics: [Template.DiagnosticProvenance.TextureSource]
    )
    private static func textureSlots(
        _ authored: [SceneResolvedMaterialNode.TextureSlot?], context: GraphContext
    ) throws -> TextureProjection {
        guard authored.count == 8
        else { throw Failure(phase: .texture, code: .textureSlotsInvalid) }
        var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
        var diagnostics: [Template.DiagnosticProvenance.TextureSource] = []
        for (index, slot) in authored.enumerated() {
            guard let slot else { continue }
            guard slot.index == index, !slot.candidates.isEmpty
            else { throw Failure(phase: .texture, code: .textureSlotsInvalid, slot: index) }
            let candidates = try slot.candidates.enumerated().map { ordinal, candidate in
                let authoredValue: String
                switch candidate.source {
                case let .asset(value): authoredValue = value
                case let .userTexture(value):
                    authoredValue = "\(value.kind.rawValue):\(value.value)"
                case let .graph(value):
                    authoredValue = "graph:\(value.kind.rawValue):\(value.layerID):\(value.name ?? "")"
                }
                let reference = try textureReference(
                    candidate, slot: index, context: context
                )
                diagnostics.append(.init(
                    slot: index,
                    candidateIndex: ordinal,
                    provenance: candidate.provenance,
                    authoredValue: authoredValue
                ))
                return Template.TextureCandidate(
                    reference: reference, provenance: candidate.provenance
                )
            }
            slots[index] = .init(index: index, candidates: candidates)
        }
        return (slots, diagnostics)
    }

    private static func textureReference(
        _ candidate: SceneResolvedMaterialNode.TextureCandidate, slot: Int,
        context: GraphContext
    ) throws -> Template.TextureReference {
        switch candidate.source {
        case let .asset(value):
            if let reference = SceneNamedTextureReference.parse(value) {
                return .provider(.namedLayerTarget(reference))
            }
            guard let path = SceneVFSAssetPath(value)
            else { throw textureFailure(.textureReferenceInvalid, slot, candidate.provenance) }
            return .asset(path)
        case let .userTexture(input):
            guard let value = normalizedProviderValue(input.value)
            else { throw textureFailure(.textureReferenceInvalid, slot, candidate.provenance) }
            switch input.kind {
            case .path:
                guard let path = SceneVFSAssetPath(value)
                else { throw textureFailure(.textureReferenceInvalid, slot, candidate.provenance) }
                return .asset(path)
            case .property: return .userProperty(.init(key: value))
            case .system: return .provider(.system(value))
            case .unknown: throw textureFailure(.userTextureUnknown, slot, candidate.provenance)
            }
        case let .graph(identity):
            guard context.textureUniverse.contains(identity),
                  context.node.bindings.contains(where: {
                      $0.slot == slot && $0.texture == identity
                  }) else {
                throw textureFailure(.textureReferenceInvalid, slot, candidate.provenance)
            }
            return .graph(identity)
        }
    }

    private typealias UniformProjection = (
        values: [Template.UniformDeclaration],
        diagnostics: [Template.DiagnosticProvenance.UniformSource]
    )
    private static func uniformDeclarations(
        _ material: SceneResolvedMaterialNode, node: Graph.Node,
        provenSceneScriptValueTargets: Set<SceneDynamicTarget>
    ) throws -> UniformProjection {
        let names = Set(material.constants.keys).union(material.userShaderValues.keys).sorted()
        var values: [Template.UniformDeclaration] = []
        var diagnostics: [Template.DiagnosticProvenance.UniformSource] = []
        for name in names {
            let authored = material.constants[name]
            guard authored?.timelineDiagnostics.isEmpty ?? true else {
                throw uniformFailure(
                    .uniformDeclarationInvalid, name,
                    authored?.timelineDiagnostics ?? []
                )
            }
            let fallback = authored.flatMap { authored in
                authored.components.map {
                    Template.StaticUniformValue(
                        valueKind: authored.valueKind,
                        componentBitPatterns: $0.map(\.bitPattern),
                        authoredBindingKeys: authored.bindingKeys.sorted()
                    )
                }
            }
            let target = node.instancePassIndex.map {
                SceneDynamicTarget.effectConstant(
                    layerID: node.effect.layerID,
                    effectIndex: node.effect.effectIndex,
                    passIndex: $0,
                    name: name
                )
            }
            guard let dynamic = SceneResolvedMaterialScriptBindingClassifier.binding(
                authored: authored,
                userValue: material.userShaderValues[name],
                target: target,
                provenSceneScriptValueTargets: provenSceneScriptValueTargets
            ) else { throw uniformFailure(.uniformDeclarationInvalid, name) }
            guard fallback != nil || !dynamic.valueContributors.isEmpty
            else { throw uniformFailure(.uniformDeclarationInvalid, name) }
            let value: Template.UniformValue
            if dynamic.valueContributors.isEmpty && dynamic.scriptAttachments.isEmpty {
                value = .staticExact(fallback!)
            } else {
                guard let target else {
                    throw graphFailure("pass-missing-for-dynamic-uniform")
                }
                value = .dynamic(.init(
                    target: target,
                    valueContributors: dynamic.valueContributors,
                    scriptAttachments: dynamic.scriptAttachments,
                    authoredFallback: fallback,
                    authoredBindingKeys: authored?.bindingKeys.sorted() ?? []
                ))
            }
            values.append(.init(name: name, value: value))
            diagnostics.append(.init(
                name: name, rawValue: authored?.rawValue,
                authoredBindingKeys: authored?.bindingKeys.sorted() ?? []
            ))
        }
        return (values, diagnostics)
    }

    private static func graphRole(_ context: GraphContext) -> Template.GraphRole? {
        guard let input = Template.GraphTextureRole(
            rawValue: context.effect.input.kind.rawValue
        ), let output = Template.GraphTextureRole(
            rawValue: context.effect.output.kind.rawValue
        ), let targetKind = context.node.target?.kind,
           let target = Template.GraphTextureRole(rawValue: targetKind.rawValue) else { return nil }
        let bindings: [Template.GraphBindingRole] = context.node.bindings.compactMap {
            binding in
            guard let slot = binding.slot,
                  let role = Template.GraphTextureRole(
                      rawValue: binding.texture.kind.rawValue
                  ) else { return nil }
            return Template.GraphBindingRole(slot: slot, texture: role)
        }
        guard bindings.count == context.node.bindings.count else { return nil }
        return .init(effectInput: input, effectOutput: output,
                     nodeTarget: target, bindings: bindings)
    }

    private static func validNodeTextures(
        _ node: Graph.Node, effect: Graph.Effect,
        universe: Set<Graph.TextureIdentity>
    ) -> Bool {
        let identities = [node.target, node.commandSource, node.commandTarget].compactMap { $0 }
            + node.bindings.map(\.texture)
        guard identities.allSatisfy(universe.contains),
              node.bindings.allSatisfy({
                  $0.texture == effect.input
                      || ($0.texture.kind == .framebuffer && $0.texture.effect == effect.key)
              }) else { return false }
        guard let target = node.target else { return node.kind != .material }
        return [.framebuffer, .effectOutput].contains(target.kind)
            && target.effect == effect.key
    }

    private static func validTexture(
        _ identity: Graph.TextureIdentity, layerID: Int,
        effects: Set<Graph.EffectKey>
    ) -> Bool {
        guard identity.layerID == layerID else { return false }
        switch identity.kind {
        case .layerSource: return identity.effect == nil && identity.name == nil
        case .effectOutput:
            return identity.effect.map(effects.contains) == true && identity.name == nil
        case .framebuffer:
            return identity.effect.map(effects.contains) == true
                && identity.name?.isEmpty == false
        case .unresolved: return false
        }
    }

    private static func normalizedShaderPath(_ rawValue: String) -> String? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        guard !value.isEmpty,
              !value.hasPrefix("/"),
              value.range(of: #"^[A-Za-z]:"#, options: .regularExpression) == nil,
              !value.unicodeScalars.contains(where: { $0.value < 32 }) else { return nil }
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains(where: { $0.isEmpty || $0 == ".." }) else { return nil }
        var identity = components.filter { $0 != "." }.joined(separator: "/")
        for suffix in [".vert", ".frag", ".json"]
        where identity.lowercased().hasSuffix(suffix) {
            identity.removeLast(suffix.count)
            break
        }
        return identity.isEmpty ? nil : identity.lowercased()
    }

    private static func normalizedProviderValue(_ rawValue: String) -> String? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty && !value.unicodeScalars.contains(where: { $0.value < 32 })
            ? value : nil
    }

    private static func graphFailure(_ detail: String) -> Failure {
        .init(phase: .graph, code: .graphNodeInvalid, details: [detail])
    }
    private static func textureFailure(
        _ code: Failure.Code, _ slot: Int,
        _ provenance: SceneResolvedMaterialNode.TextureProvenance
    ) -> Failure {
        .init(phase: .texture, code: code, slot: slot, provenance: provenance)
    }
    private static func uniformFailure(
        _ code: Failure.Code, _ name: String, _ details: [String] = []
    ) -> Failure {
        .init(phase: .uniform, code: code, details: [name] + details)
    }
}
