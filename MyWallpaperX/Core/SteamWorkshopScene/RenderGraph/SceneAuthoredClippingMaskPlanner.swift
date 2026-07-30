import CryptoKit
import Foundation

enum SceneAuthoredClippingMaskPlanner {
    typealias Graph = SceneAuthoredEffectRenderPlan

    private nonisolated struct CanonicalShaderPayload: Encodable {
        let identity: String
        let sourceKind: SceneShaderContract.SourceKind
        let stages: [SceneShaderContract.Stage]
        let diagnostics: [SceneShaderContract.Diagnostic]
    }

    nonisolated static func plan(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneClippingMaskExecutionPlan? {
        guard graph.blockers.isEmpty,
              graph.effects.count == 1,
              graph.nodes.count == 1,
              graph.renderTargets.isEmpty,
              descriptor.layers.filter({ $0.id == graph.layerID }).count == 1,
              let layer = descriptor.layers.first(where: { $0.id == graph.layerID }),
              supportedContentKinds.contains(layer.contentKind) else {
            return nil
        }
        let effect = graph.effects[0]
        let node = graph.nodes[0]
        guard layer.effects.indices.contains(effect.key.effectIndex),
              let declaration = SceneClippingMaskContract.declaration(
                  for: layer.effects[effect.key.effectIndex]
              ),
              declaration.effectID == effect.key.descriptorID,
              normalized(effect.definitionPath) == SceneClippingMaskContract.definitionPath,
              validDefinition(in: descriptor, profile: declaration.profile),
              shaderContractMatches(shaderContracts, profile: declaration.profile),
              effect.nodeIndices == [node.nodeIndex],
              SceneAuthoredEffectInputValidator.accepts(
                  effect.input,
                  layerID: graph.layerID,
                  role: inputRole
              ),
              effect.output == effectOutput(effect.key),
              graph.finalOutput == effect.output,
              validNode(node, effect: effect),
              validMaterialDescriptor(in: descriptor),
              let material = SceneAuthoredMaterialResolver.resolve(
                  node: node,
                  graph: graph,
                  descriptor: descriptor
              ).node,
              validResolvedMaterial(material, declaration: declaration) else {
            return nil
        }
        return SceneClippingMaskExecutionPlan(
            layerID: graph.layerID,
            effectKey: effect.key,
            renderGraph: graph,
            providerLayerID: declaration.providerLayerID,
            blendMode: declaration.blendMode,
            profile: declaration.profile
        )
    }

    private nonisolated static func validDefinition(
        in descriptor: SceneRenderDescriptor,
        profile: SceneClippingMaskProfile
    ) -> Bool {
        let matches = descriptor.effectDefinitions.filter {
            normalized($0.relativePath) == SceneClippingMaskContract.definitionPath
        }
        guard matches.count == 1, let definition = matches.first,
              definition.version == 1,
              definition.replacementKey == "clipping_mask",
              definition.name == definitionNames[profile],
              definition.description == nil,
              definition.group == "localeffects",
              definition.performance == nil,
              definition.previewPath == nil,
              definition.editable == false,
              definition.framebuffers.isEmpty,
              definition.dependencies.map(normalized) == dependencies,
              definition.functions == nil,
              definition.gizmos == nil,
              definition.extraFields.isEmpty,
              definition.unknownFieldPaths.isEmpty,
              definition.passes.count == 1,
              let pass = definition.passes.first else {
            return false
        }
        return pass.passIndex == 0
            && normalized(pass.materialPath ?? "") == materialPath
            && pass.target == nil
            && pass.bindings.isEmpty
            && pass.compose == nil
            && pass.command == nil
            && pass.source == nil
            && pass.conditions == nil
            && pass.extraFields.isEmpty
    }

    private nonisolated static func validNode(
        _ node: Graph.Node,
        effect: Graph.Effect
    ) -> Bool {
        node.effect == effect.key
            && node.definitionPassIndex == 0
            && node.materialOrdinal == 0
            && node.instancePassIndex == 0
            && node.kind == .material
            && normalized(node.materialPath ?? "") == materialPath
            && normalized(node.materialPassID ?? "") == materialPassID
            && node.target == effect.output
            && node.bindings.isEmpty
            && node.commandSource == nil
            && node.commandTarget == nil
            && node.compose == nil
            && node.conditions == nil
    }

    private nonisolated static func validMaterialDescriptor(
        in descriptor: SceneRenderDescriptor
    ) -> Bool {
        let matches = descriptor.materialPasses.filter {
            normalized($0.id) == materialPassID
        }
        guard matches.count == 1, let material = matches.first else { return false }
        return normalized(material.materialPath) == materialPath
            && material.materialRawSHA256 == materialSHA256
            && material.passIndex == 0
            && normalized(material.shaderPath ?? "") == shaderIdentity
            && material.texturePaths.isEmpty
            && material.textureSlots.isEmpty
            && material.userTextureInputs.isEmpty
            && material.combos.isEmpty
            && material.constantShaderValues.isEmpty
            && material.userShaderValues.isEmpty
            && material.blending?.lowercased() == "normal"
            && material.depthTest?.lowercased() == "disabled"
            && material.depthWrite?.lowercased() == "disabled"
            && material.cullMode?.lowercased() == "nocull"
            && material.alphaWriting == nil
    }

    private nonisolated static func validResolvedMaterial(
        _ material: SceneResolvedMaterialNode,
        declaration: SceneClippingMaskDeclaration
    ) -> Bool {
        guard normalized(material.shaderPath) == shaderIdentity,
              material.textureSlots.count == 8,
              let slot = material.textureSlots[1],
              slot.candidates.count == 1,
              slot.provenance == .instance,
              case .asset(let path) = slot.source,
              let reference = SceneNamedTextureReference.parse(path),
              reference.providerLayerID == declaration.providerLayerID,
              reference.variant == .primary,
              material.textureSlots.enumerated().allSatisfy({
                  $0.offset == 1 || $0.element == nil
              }) else {
            return false
        }
        return material.renderState.blending?.lowercased() == "normal"
            && material.renderState.depthTest?.lowercased() == "disabled"
            && material.renderState.depthWrite?.lowercased() == "disabled"
            && material.renderState.cullMode?.lowercased() == "nocull"
    }

    private nonisolated static func shaderContractMatches(
        _ contracts: [SceneShaderContract],
        profile: SceneClippingMaskProfile
    ) -> Bool {
        guard let fingerprint = shaderFingerprints[profile] else { return false }
        let matches = contracts.filter { normalized($0.identity) == shaderIdentity }
        guard matches.count == 1, let contract = matches.first,
              contract.sourceKind == .authoredSource,
              contract.diagnostics.isEmpty,
              contract.canonicalSHA256 == fingerprint.canonical,
              canonicalHash(contract) == fingerprint.canonical,
              contract.stages.count == 2 else {
            return false
        }
        let expected = [
            (SceneShaderContract.StageKind.vertex, vertexPath, fingerprint.vertex),
            (SceneShaderContract.StageKind.fragment, fragmentPath, fingerprint.fragment),
        ]
        return zip(contract.stages, expected).allSatisfy { stage, value in
            stage.kind == value.0
                && normalized(stage.relativePath) == value.1
                && stage.rawSHA256 == value.2
                && sha256(Data(stage.source.utf8)) == value.2
        }
    }

    private nonisolated static func canonicalHash(
        _ contract: SceneShaderContract
    ) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payload = CanonicalShaderPayload(
            identity: contract.identity,
            sourceKind: contract.sourceKind,
            stages: contract.stages,
            diagnostics: contract.diagnostics
        )
        guard let data = try? encoder.encode(payload) else { return "" }
        return sha256(data)
    }

    private nonisolated static func effectOutput(
        _ effect: Graph.EffectKey
    ) -> Graph.TextureIdentity {
        .init(kind: .effectOutput, layerID: effect.layerID, effect: effect, name: nil)
    }

    private nonisolated static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private nonisolated static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static let supportedContentKinds = Set([
        "image", "solid", "text", "composition",
    ])
    private nonisolated static let materialPath =
        "materials/workshop/2800594362/effects/clipping_mask.json"
    private nonisolated static let materialPassID = "\(materialPath)#0"
    private nonisolated static let materialSHA256 =
        "965a3cdd8000344a01cf0b86effb9af93fe0d33668ce13b1b0db8e0a809d1caa"
    private nonisolated static let shaderIdentity =
        "workshop/2800594362/effects/clipping_mask"
    private nonisolated static let dependencies = [
        materialPath,
        "shaders/workshop/2800594362/effects/clipping_mask.frag",
        "shaders/workshop/2800594362/effects/clipping_mask.vert",
    ]
    private nonisolated static let vertexPath =
        "shaders/workshop/2800594362/effects/clipping_mask.vert"
    private nonisolated static let fragmentPath =
        "shaders/workshop/2800594362/effects/clipping_mask.frag"
    private nonisolated static let definitionNames: [SceneClippingMaskProfile: String] = [
        .classic: "Clipping mask",
        .weightedNeutral: "ui_editor_properties_clipping_mask",
    ]
    private nonisolated static let shaderFingerprints: [
        SceneClippingMaskProfile: (canonical: String, vertex: String, fragment: String)
    ] = [
        .classic: (
            "82119d559341b8452ef12917733536fe24193c791f2efd3412fc21a7c5b1a16b",
            "32c2e9e24977466c46c07914bf3a8cd1889744109ea3a826c6df0573702f2a02",
            "f8eb4048164c6f67caed316e558eadcaed85fa7f505d5816d91a37ad26bace39"
        ),
        .weightedNeutral: (
            "622e8dc7d63c4c7f6371d2f601f32dd442e2a26c8279853acdfee93aedf4c404",
            "181b333c52ce2acfbea6fa01f5062f74bc2dfe4ed7e578194ecc1968c55dbcd2",
            "ca9ed8959e77f751a09260e39d97404dc2157a509f821f575c06eb6b0489fe58"
        ),
    ]
}
