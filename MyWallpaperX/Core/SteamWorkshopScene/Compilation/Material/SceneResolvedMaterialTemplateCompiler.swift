import Foundation

nonisolated enum SceneResolvedMaterialTemplateCompiler {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Template = SceneResolvedMaterialTemplate
    typealias Failure = SceneResolvedMaterialFailure

    struct GraphScope {
        let effect: Graph.Effect
        let textureUniverse: Set<Graph.TextureIdentity>

        init(effect: Graph.Effect, renderTargets: [Graph.RenderTarget]) {
            self.effect = effect
            textureUniverse = Set([effect.input, effect.output] + renderTargets.map(\.texture))
        }
    }

    private typealias GraphContext = (node: Graph.Node, scope: GraphScope)

    static func compile(
        material: SceneResolvedMaterialNode, node: Graph.Node, graphScope: GraphScope,
        shaderContract: SceneShaderContract,
        inheritedInactiveCombos: Set<String> = [],
        previousBlurredCompositeGenericOwnerEligible: Bool = false,
        provenSceneScriptValueTargets: Set<SceneDynamicTarget> = [],
        compatibilityTarget: SceneShaderCompatibilityTarget = .unprofiledMetal
    ) -> Result<Template, Failure> {
        do {
            guard material.nodeIndex == node.nodeIndex, node.kind == .material,
                  node.effect == graphScope.effect.key else {
                throw graphFailure("material-node-invalid")
            }
            let context = (node: node, scope: graphScope)
            try validateShader(material.shaderPath, contract: shaderContract)
            let textures = try textureSlots(
                material.textureSlots,
                layerID: context.node.effect.layerID,
                context: context
            )
            let uniforms = try uniformDeclarations(
                material,
                target: { name in
                    context.node.instancePassIndex.map {
                        .effectConstant(
                            layerID: context.node.effect.layerID,
                            effectIndex: context.node.effect.effectIndex,
                            passIndex: $0,
                            name: name
                        )
                    }
                },
                provenSceneScriptValueTargets: provenSceneScriptValueTargets
            )
            guard let state = SceneMaterialRenderState.compile(
                blending: material.renderState.blending,
                depthTest: material.renderState.depthTest,
                depthWrite: material.renderState.depthWrite,
                cullMode: material.renderState.cullMode,
                alphaWriting: material.renderState.alphaWriting
            ) else { throw Failure(phase: .state, code: .renderStateInvalid) }
            guard let role = graphRole(context) else {
                throw Failure(phase: .invariant, code: .identityInvariant)
            }
            return .success(try makeTemplate(
                material: material,
                shaderContract: shaderContract,
                textures: textures,
                uniforms: uniforms,
                renderState: state,
                graphRole: role,
                effectContext: .init(key: graphScope.effect.key, input: graphScope.effect.input),
                inheritedInactiveCombos: inheritedInactiveCombos,
                previousBlurredCompositeGenericOwnerEligible:
                    previousBlurredCompositeGenericOwnerEligible,
                compatibilityTarget: compatibilityTarget
            ))
        } catch {
            return .failure(error as? Failure
                ?? Failure(phase: .invariant, code: .identityInvariant))
        }
    }

    /// Evaluates one real model material into the layer's raw source. Render
    /// state is lowered by the source admission owner; it is not an authored
    /// default and does not decide the layer's final composition blend.
    static func compileSourceMaterial(
        material: SceneResolvedMaterialNode,
        layerID: Int,
        materialPath: String,
        passIndex: Int,
        shaderContract: SceneShaderContract,
        renderState: SceneMaterialRenderState,
        inheritedInactiveCombos: Set<String> = [],
        provenSceneScriptValueTargets: Set<SceneDynamicTarget> = [],
        compatibilityTarget: SceneShaderCompatibilityTarget = .windowsDX11ShaderModel4
    ) -> Result<Template, Failure> {
        do {
            guard passIndex >= 0, let path = SceneVFSAssetPath(materialPath) else {
                throw Failure(phase: .invariant, code: .identityInvariant)
            }
            try validateShader(material.shaderPath, contract: shaderContract)
            let textures = try textureSlots(material.textureSlots, layerID: layerID)
            let uniforms = try uniformDeclarations(
                material,
                target: {
                    .materialConstant(
                        layerID: layerID, passIndex: passIndex,
                        name: $0, materialPath: path.value
                    )
                },
                provenSceneScriptValueTargets: provenSceneScriptValueTargets
            )
            return .success(try makeTemplate(
                material: material,
                shaderContract: shaderContract,
                textures: textures,
                uniforms: uniforms,
                renderState: renderState,
                graphRole: .init(
                    effectInput: .layerSource, effectOutput: .layerSource,
                    nodeTarget: .layerSource, bindings: []
                ),
                effectContext: nil,
                inheritedInactiveCombos: inheritedInactiveCombos,
                previousBlurredCompositeGenericOwnerEligible: false,
                compatibilityTarget: compatibilityTarget
            ))
        } catch {
            return .failure(error as? Failure
                ?? Failure(phase: .invariant, code: .identityInvariant))
        }
    }

    private static func makeTemplate(
        material: SceneResolvedMaterialNode,
        shaderContract: SceneShaderContract,
        textures: TextureProjection,
        uniforms: UniformProjection,
        renderState: SceneMaterialRenderState,
        graphRole: Template.GraphRole,
        effectContext: Template.EffectContext?,
        inheritedInactiveCombos: Set<String>,
        previousBlurredCompositeGenericOwnerEligible: Bool,
        compatibilityTarget: SceneShaderCompatibilityTarget
    ) throws -> Template {
        let combos = material.combos.sorted { $0.key < $1.key }.map {
            Template.Combo(name: $0.key, value: $0.value)
        }
        guard let template = Template.validated(
            textureSlots: textures.slots,
            combos: combos,
            inheritedInactiveCombos: inheritedInactiveCombos,
            uniformDeclarations: uniforms.values,
            renderState: renderState,
            graphRole: graphRole,
            previousBlurredCompositeGenericOwnerEligible:
                previousBlurredCompositeGenericOwnerEligible,
            effectContext: effectContext,
            compatibilityTarget: compatibilityTarget,
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
        return template
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
        _ authored: [SceneResolvedMaterialNode.TextureSlot?], layerID: Int,
        context: GraphContext? = nil
    ) throws -> TextureProjection {
        guard authored.count == 8
        else { throw Failure(phase: .texture, code: .textureSlotsInvalid) }
        var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
        var diagnostics: [Template.DiagnosticProvenance.TextureSource] = []
        for (index, slot) in authored.enumerated() {
            guard let slot else { continue }
            guard slot.index == index, !slot.candidates.isEmpty
            else { throw Failure(phase: .texture, code: .textureSlotsInvalid, slot: index) }
            let firstExecutableIndex: Int
            if let terminal = slot.candidates.last,
               terminal.provenance == .explicitBinding,
               case let .graph(identity) = terminal.source,
               identity.kind == .framebuffer {
                firstExecutableIndex = slot.candidates.count - 1
            } else {
                firstExecutableIndex = 0
            }
            let candidates = try slot.candidates.enumerated().compactMap { ordinal, candidate -> Template.TextureCandidate? in
                let authoredValue: String
                switch candidate.source {
                case let .asset(value): authoredValue = value
                case let .userTexture(value):
                    authoredValue = "\(value.kind.rawValue):\(value.value)"
                case let .graph(value):
                    authoredValue = "graph:\(value.kind.rawValue):\(value.layerID):\(value.name ?? "")"
                }
                diagnostics.append(.init(
                    slot: index,
                    candidateIndex: ordinal,
                    provenance: candidate.provenance,
                    authoredValue: authoredValue
                ))
                // An explicit framebuffer never falls back to these lower
                // values, but their original diagnostics remain available.
                guard ordinal >= firstExecutableIndex else { return nil }
                let reference = try textureReference(
                    candidate, slot: index, layerID: layerID, context: context
                )
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
        layerID: Int, context: GraphContext?
    ) throws -> Template.TextureReference {
        switch candidate.source {
        case let .asset(value):
            // D8：`_rt_` 名经词汇表单点准入分派（保留/清空/改写的唯一解释
            // 入口），不再内联叠加名字特判。未知 `_rt_` 名不当作资产路径：
            // 保留诊断 token 硬拒绝。
            switch SceneRenderTargetVocabulary.dispatch(authoredName: value) {
            case .typedFrameInput:
                return .provider(.sceneBackground(
                    consumerLayerID: layerID
                ))
            case .sceneEnvironment:
                return .provider(.sceneEnvironment)
            case let .namedLayerTarget(reference):
                return .provider(.namedLayerTarget(reference))
            case let .unadmitted(name):
                guard name.hasPrefix(SceneRenderTargetVocabulary.internalTargetPrefix) == false,
                      let path = SceneVFSAssetPath(value)
                else { throw textureFailure(.textureReferenceInvalid, slot, candidate.provenance) }
                return .asset(path)
            }
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
            case .userShortcut, .unknown:
                throw textureFailure(.userTextureUnknown, slot, candidate.provenance)
            }
        case let .graph(identity):
            guard let context, context.scope.textureUniverse.contains(identity),
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
        _ material: SceneResolvedMaterialNode,
        target targetForName: (String) -> SceneDynamicTarget?,
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
                        authoredBindingKeys: authored.bindingKeys.sorted(),
                        authoredScalarProjectionProven:
                            authoredScalarProjectionIsProven(authored)
                    )
                }
            }
            let target = targetForName(name)
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

    private static func authoredScalarProjectionIsProven(
        _ authored: SceneDocument.ShaderValue
    ) -> Bool {
        guard let components = authored.components,
              components.count == 1,
              let component = components.first,
              component.isFinite else { return false }
        let token = authored.rawValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !token.isEmpty,
              let parsed = Double(token),
              parsed.isFinite else { return false }
        return parsed.bitPattern == component.bitPattern
    }

    private static func graphRole(_ context: GraphContext) -> Template.GraphRole? {
        guard let input = Template.GraphTextureRole(
            rawValue: context.scope.effect.input.kind.rawValue
        ), let output = Template.GraphTextureRole(
            rawValue: context.scope.effect.output.kind.rawValue
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
