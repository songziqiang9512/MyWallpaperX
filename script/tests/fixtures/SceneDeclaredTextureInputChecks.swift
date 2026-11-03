import Foundation

func admitTemplateGraph(_ graph: SceneAuthoredEffectRenderPlan)
    -> Result<SceneGraphAdmissionProduct, SceneGraphAdmissionFailure> {
    var effects: [SceneRenderDescriptor.EffectDescriptor] = []
    if let effect = graph.effects.first {
        let passes = graph.nodes.filter { $0.kind == .material }.compactMap { node in
            node.instancePassIndex.map {
                SceneRenderDescriptor.EffectDescriptor.PassDescriptor(passIndex: $0,
                    textureSlots: [], userTextureInputs: [], combos: [:], constantShaderValues: [:])
            }
        }
        effects = (0...max(0, effect.key.effectIndex)).map { index in
            .init(id: index == effect.key.effectIndex ? effect.key.descriptorID : "unused-\(index)",
                passes: index == effect.key.effectIndex ? passes : [])
        }
    }
    var seen = Set<String>()
    let materials: [SceneRenderDescriptor.MaterialPassDescriptor] = graph.nodes.compactMap { node in
        guard node.kind == .material, let id = node.materialPassID,
              seen.insert(id).inserted else { return nil }
        return .init(id: id, materialPath: node.materialPath ?? "", shaderPath: nil,
            textureSlots: [], userTextureInputs: [], combos: [:], constantShaderValues: [:],
            userShaderValues: [:], blending: nil, depthTest: nil, depthWrite: nil, cullMode: nil, alphaWriting: nil)
    }
    return SceneGraphAdmissionCompiler.compile(graph: graph,
        descriptor: .init(layers: [.init(id: graph.layerID, effects: effects)], materialPasses: materials),
        functions: nil)
}

func templateGraphRejection(_ graph: SceneAuthoredEffectRenderPlan) -> SceneGraphAdmissionFailure? {
    guard case let .failure(failure) = admitTemplateGraph(graph) else { return nil }
    return failure
}

func referenceToken(_ value: SceneResolvedMaterialTemplate.TextureReference) -> String {
    switch value {
    case let .asset(request): return "asset:\(request.value)"
    case let .userProperty(request): return "property:\(request.key)"
    case let .provider(identity):
        switch identity {
        case let .system(name): return "system:\(name)"
        case let .namedLayerTarget(reference):
            return "named:\(reference.providerLayerID):\(reference.variant.rawValue)"
        case let .sceneBackground(consumerLayerID):
            return "scene-background:\(consumerLayerID)"
        case .sceneEnvironment: return "scene-environment"
        }
    case let .graph(identity): return "graph:\(identity.kind.rawValue):\(identity.layerID)"
    }
}

/// The preparation ingress changes identity only; Resolver/Template retain
/// their real candidate precedence and existing provider/path admission.
func declaredTextureInputChecks(shader: SceneShaderContract) -> [String: Bool] {
    typealias Input = SceneEffectTextureInput
    let declared: Set<String> = ["_1", "_renamedCover", "photo", "path.png",
        "folder/cover", "_rt_FullFrameBuffer", "_RT_FullFrameBuffer", "_rt_unknown"]
    func parse(_ raw: Any, keys: Set<String>? = nil) -> Input? {
        Input.parse(raw, declaredTexturePropertyKeys: keys ?? declared)
    }
    func reference(_ raw: Any, keys: Set<String>? = nil) -> String? {
        let pass = SceneRenderDescriptor.MaterialPassDescriptor(
            id: "materials/renamed.json#0", materialPath: "materials/renamed.json",
            shaderPath: shader.identity, textureSlots: ["textures/renamed.png"],
            userTextureInputs: [parse(raw, keys: keys)], combos: [:],
            constantShaderValues: [:], userShaderValues: [:], blending: "normal",
            depthTest: "disabled", depthWrite: "disabled", cullMode: "nocull",
            alphaWriting: nil)
        guard let node = SceneAuthoredMaterialResolver.resolveSourceMaterial(material: pass).node,
              case let .success(template) = SceneResolvedMaterialTemplateCompiler.compileSourceMaterial(
                material: node, layerID: 909, materialPath: pass.materialPath, passIndex: 0,
                shaderContract: shader, renderState: .init(
                    rawValues: .init(blending: "normal", depthTest: "disabled",
                        depthWrite: "disabled", cullMode: "nocull", alphaWriting: nil),
                    blending: .normal, depthTest: .disabled, depthWrite: .disabled,
                    cullMode: .noCull, alphaWriting: .unspecified)),
              let input = template.textureSlots[0]?.candidates.last?.reference else { return nil }
        switch input {
        case let .userProperty(value): return "property:" + value.key
        case let .asset(value): return "asset:" + value.value
        case .provider(.sceneBackground): return "background"
        default: return "other"
        }
    }
    return [
        "declaredUnderscoreReachesTemplate": reference("_1") == "property:_1",
        "declaredRenamedKeyReachesTemplate": reference("_renamedCover") == "property:_renamedCover",
        "declaredBareKeyUnchanged": reference("photo") == "property:photo",
        "undeclaredUnderscoreStaysAsset": reference("_1", keys: []) == "asset:_1",
        "declarationIsCaseSensitive": reference("_RenamedCover") == "asset:_renamedcover",
        "declaredDotPathStaysAsset": reference("path.png") == "asset:path.png",
        "declaredSlashPathStaysAsset": reference("folder/cover") == "asset:folder/cover",
        "declaredBackslashStaysPath": parse("folder\\cover")?.kind == .path,
        "declaredInternalRTKeepsVocabulary": ["_rt_FullFrameBuffer", "_RT_FullFrameBuffer", "_rt_unknown"].allSatisfy {
            parse($0)?.kind == .path && reference($0) == reference($0, keys: [])
        },
        "explicitUserKeepsIdentity": reference(["user": "_1"], keys: []) == "property:_1",
        "explicitSystemKeepsIdentity": parse(["type": "system", "name": "_1"])?.kind == .system,
        "explicitShortcutKeepsIdentity": parse(["type": "usershortcut", "name": "_1"])?.kind == .userShortcut,
        "explicitUnknownStaysUnknown": parse(["type": "future", "name": "_1"])?.kind == .unknown,
        "explicitMalformedSystemStaysUnknown": parse(["type": "system", "name": "_1", "extra": true])?.kind == .unknown,
        "emptyAndNullRemainAbsent": parse("") == nil && parse(NSNull()) == nil,
    ]
}

func declaredFramebufferBindingChecks(shader: SceneShaderContract) -> [String: Bool] {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Material = SceneResolvedMaterialNode
    typealias Template = SceneResolvedMaterialTemplate
    var checks: [String: Bool] = [:]
    for (variant, layer, index, descriptor, name, asset, property) in [
        ("original", 128, 4, "394", "_rt_FullCompoBuffer1", "textures/idle.png", "skin"),
        ("renamed", 947, 7, "unseen-effect", "_rt_unseen_history", "fixtures/other.png", "cover"),
    ] {
        let prefix = "framebufferShadow:\(variant):"
        let key = Graph.EffectKey(layerID: layer, effectIndex: index, descriptorID: descriptor)
        let input = Graph.TextureIdentity(kind: .layerSource, layerID: layer, effect: nil, name: nil)
        let output = Graph.TextureIdentity(kind: .effectOutput, layerID: layer, effect: key, name: nil)
        let target = Graph.TextureIdentity(kind: .framebuffer, layerID: layer, effect: key, name: name)
        let unknown = "\(name)_\(layer)_\(descriptor)"
        let lowerAsset = Material.TextureCandidate(source: .asset(asset), provenance: .material)
        let lowerRT = Material.TextureCandidate(source: .asset(unknown), provenance: .instance)
        let lowerUser = Material.TextureCandidate(
            source: .userTexture(.init(kind: .property, value: property)), provenance: .userTexture)
        let terminal = Material.TextureCandidate(source: .graph(target), provenance: .explicitBinding)
        func material(_ candidates: [Material.TextureCandidate]) -> Material {
            var slots = Array<Material.TextureSlot?>(repeating: nil, count: 8)
            slots[1] = .init(index: 1, candidates: candidates)
            return .init(nodeIndex: 7, shaderPath: shader.identity, textureSlots: slots,
                combos: [:], constants: [:], userShaderValues: [:], renderState: .init(
                    blending: "normal", depthTest: "disabled", depthWrite: "disabled",
                    cullMode: "nocull", alphaWriting: nil))
        }
        func graph(declared: Bool = true, binding: Graph.TextureIdentity? = nil,
                   bindingSlot: Int? = 1) -> Graph {
            let node = Graph.Node(nodeIndex: 7, effect: key, definitionPassIndex: 0,
                materialOrdinal: 0, instancePassIndex: 0, kind: .material,
                materialPath: "materials/\(variant).json", materialPassID: "\(variant)#0", target: output,
                bindings: bindingSlot.map { [.init(slot: $0, authoredName: name,
                    texture: binding ?? target, conditions: nil)] } ?? [],
                commandSource: nil, commandTarget: nil, compose: nil, conditions: nil)
            return .init(layerID: layer, effects: [.init(key: key,
                definitionPath: "effects/\(variant).json", input: input, output: output, nodeIndices: [7])],
                renderTargets: declared ? [.init(texture: target,
                    extent: .init(kind: .input, first: nil, second: nil), format: "rgba8888",
                    declaredUnique: true, clear: nil, uvs: nil, conditions: nil)] : [],
                nodes: [node], finalOutput: output, blockers: [])
        }
        func record(_ label: String, _ result: Result<Template, SceneResolvedMaterialFailure>) {
            let observation: String
            switch result {
            case let .success(value):
                observation = "references=" + (value.textureSlots[1]?.candidates.map {
                    referenceToken($0.reference)
                }.joined(separator: ",") ?? "absent")
            case let .failure(error):
                observation = "\(error.phase.rawValue)/\(error.code.rawValue) slot=\(error.slot ?? -1)"
                    + " provenance=\(error.provenance?.rawValue ?? "none")"
            }
            FileHandle.standardError.write(Data("\(prefix)\(label) \(observation)\n".utf8))
        }
        func compile(_ label: String, _ candidates: [Material.TextureCandidate],
                     context: Graph? = nil) -> Result<Template, SceneResolvedMaterialFailure> {
            guard case let .success(product) = admitTemplateGraph(context ?? graph()) else {
                preconditionFailure("invalid graphs must be checked at graph admission")
            }
            let result = SceneResolvedMaterialTemplateCompiler.compile(
                material: material(candidates), node: product.graph.nodes[0],
                graphScope: .init(effect: product.graph.effects[0], renderTargets: product.graph.renderTargets),
                shaderContract: shader)
            record(label, result)
            return result
        }
        func value(_ result: Result<Template, SceneResolvedMaterialFailure>) -> Template? {
            guard case let .success(value) = result else { return nil }
            return value
        }
        func rejected(_ result: Result<Template, SceneResolvedMaterialFailure>,
                      _ code: SceneResolvedMaterialFailure.Code) -> Bool {
            guard case let .failure(error) = result else { return false }
            return error.code == code
        }
        for (label, lower) in [("unknownRT", [lowerRT]), ("asset", [lowerAsset]),
                               ("user", [lowerUser]), ("mixed", [lowerAsset, lowerRT, lowerUser])] {
            let projected = value(compile(label, lower + [terminal]))
            checks[prefix + label + ":execution"] = projected?.textureSlots[1]?.candidates.count == 1
                && projected?.textureSlots[1]?.candidates.first?.reference == .graph(target)
                && projected?.textureSlots[1]?.candidates.first?.provenance == .explicitBinding
            if label == "mixed" {
                checks[prefix + "mixed:rawDiagnostics"] = projected?.diagnosticProvenance.textureSources == [
                    .init(slot: 1, candidateIndex: 0, provenance: .material, authoredValue: asset),
                    .init(slot: 1, candidateIndex: 1, provenance: .instance, authoredValue: unknown),
                    .init(slot: 1, candidateIndex: 2, provenance: .userTexture, authoredValue: "property:\(property)"),
                    .init(slot: 1, candidateIndex: 3, provenance: .explicitBinding,
                          authoredValue: "graph:framebuffer:\(layer):\(name)"),
                ]
            }
        }
        let foreign = Graph.TextureIdentity(kind: .framebuffer, layerID: layer + 1,
            effect: .init(layerID: layer + 1, effectIndex: index, descriptorID: descriptor), name: name)
        checks[prefix + "foreignRejected"] = rejected(compile("foreign", [
            .init(source: .graph(foreign), provenance: .explicitBinding)]), .textureReferenceInvalid)
        checks[prefix + "undeclaredRejected"] = templateGraphRejection(graph(declared: false))?.code == .prunedResourceReferenced
        checks[prefix + "missingBindingRejected"] = rejected(compile("missing-binding", [lowerRT, terminal],
            context: graph(bindingSlot: nil)), .textureReferenceInvalid)
        checks[prefix + "wrongSlotRejected"] = rejected(compile("wrong-slot", [terminal],
            context: graph(bindingSlot: 2)), .textureReferenceInvalid)
        let source = SceneResolvedMaterialTemplateCompiler.compileSourceMaterial(
            material: material([terminal]), layerID: layer, materialPath: "materials/\(variant).json",
            passIndex: 0, shaderContract: shader, renderState: SceneMaterialRenderState.compile(
                blending: "normal", depthTest: "disabled", depthWrite: "disabled", cullMode: "nocull",
                alphaWriting: nil)!)
        record("source-no-context", source)
        checks[prefix + "sourceWithoutContextRejected"] = rejected(source, .textureReferenceInvalid)
        for (label, last, context, expected) in [
            ("nonexplicitFBO", Material.TextureCandidate(source: .graph(target), provenance: .instance),
             graph(), "graph:framebuffer:\(layer)"),
            ("assetTerminal", Material.TextureCandidate(source: .asset("textures/last.png"), provenance: .instance),
             graph(), "asset:textures/last.png"),
            ("providerTerminal", Material.TextureCandidate(source: .asset("_rt_FullFrameBuffer"), provenance: .instance),
             graph(), "scene-background:\(layer)"),
            ("previousTerminal", Material.TextureCandidate(source: .graph(input), provenance: .explicitBinding),
             graph(binding: input), "graph:layerSource:\(layer)"),
        ] {
            let unchanged = value(compile(label, [lowerAsset, lowerUser, last], context: context))
            checks[prefix + label + ":unchanged"] = unchanged?.textureSlots[1]?.candidates.map {
                referenceToken($0.reference)
            } == ["asset:\(asset)", "property:\(property)", expected]
        }
        checks[prefix + "nonexplicitFBOStillRejectsUnknownLower"] = rejected(compile("nonexplicit-invalid", [
            lowerRT, .init(source: .graph(target), provenance: .instance)]), .textureReferenceInvalid)
        checks[prefix + "previousStillRejectsUnknownLower"] = rejected(compile("previous-invalid", [
            lowerRT, .init(source: .graph(input), provenance: .explicitBinding)], context: graph(binding: input)),
            .textureReferenceInvalid)
    }
    return checks
}
