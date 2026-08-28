import CryptoKit
import Foundation

nonisolated enum SceneXRayStockIdentityVerifier {
    typealias Graph = SceneAuthoredEffectRenderPlan

    nonisolated struct StockIdentityProfile {
        let version: Int?
        let replacementKey: String?
        let group: String
        let materialSemanticSHA256: String
        let shaderCanonicalSHA256: String
        let shaderDependencySHA256: String
    }

#if SCENE_XRAY_STOCK_IDENTITY_TESTING
    nonisolated struct SyntheticStockIdentityProfile {
        let version: Int?
        let replacementKey: String?
        let group: String
        let materialSemanticSHA256: String
        let shaderCanonicalSHA256: String
        let shaderDependencySHA256: String
    }
#endif

    /// Returns exact descriptor instances backed by a registered X-Ray stock
    /// identity. Runtime declaration and dependency shape remain separate gates.
    nonisolated static func verifiedStockIdentityEffectKeys(
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract]
    ) -> Set<Graph.EffectKey> {
        verifiedStockIdentityEffectKeys(
            descriptor: descriptor,
            shaderContracts: shaderContracts,
            profiles: stockIdentityProfiles
        )
    }

#if SCENE_XRAY_STOCK_IDENTITY_TESTING
    nonisolated static func verifiedStockIdentityEffectKeysForTesting(
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        syntheticProfiles: [SyntheticStockIdentityProfile]
    ) -> Set<Graph.EffectKey> {
        verifiedStockIdentityEffectKeys(
            descriptor: descriptor,
            shaderContracts: shaderContracts,
            profiles: syntheticProfiles.map {
                StockIdentityProfile(
                    version: $0.version,
                    replacementKey: $0.replacementKey,
                    group: $0.group,
                    materialSemanticSHA256: $0.materialSemanticSHA256,
                    shaderCanonicalSHA256: $0.shaderCanonicalSHA256,
                    shaderDependencySHA256: $0.shaderDependencySHA256
                )
            }
        )
    }
#endif

    nonisolated static func currentStockDefinitionMatches(
        descriptor: SceneRenderDescriptor,
        path: String
    ) -> Bool {
        definitionMatches(
            in: descriptor,
            path: path,
            profile: currentStockIdentityProfile
        )
    }

    nonisolated static func currentStockMaterialMatches(
        descriptor: SceneRenderDescriptor
    ) -> Bool {
        materialMatches(
            in: descriptor,
            semanticSHA256: currentStockIdentityProfile.materialSemanticSHA256
        )
    }

    nonisolated static func currentStockShaderContractMatches(
        _ contracts: [SceneShaderContract]
    ) -> Bool {
        shaderContractMatches(
            contracts,
            profile: currentStockIdentityProfile,
            requiresSourceGraphIdentity: true
        )
    }

    private nonisolated static func verifiedStockIdentityEffectKeys(
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        profiles: [StockIdentityProfile]
    ) -> Set<Graph.EffectKey> {
        guard profiles.contains(where: { profile in
            definitionMatches(
                in: descriptor,
                path: definitionPath,
                profile: profile
            ) && materialMatches(
                in: descriptor,
                semanticSHA256: profile.materialSemanticSHA256
            ) && shaderContractMatches(
                shaderContracts,
                profile: profile,
                requiresSourceGraphIdentity: true
            )
        }) else {
            return []
        }

        return Set(descriptor.layers.flatMap { layer in
            layer.effects.enumerated().compactMap { effectIndex, effect in
                guard effect.visible != false,
                      normalizedStockPath(effect.file) == definitionPath else {
                    return nil
                }
                return Graph.EffectKey(
                    layerID: layer.id,
                    effectIndex: effectIndex,
                    descriptorID: effect.id
                )
            }
        })
    }

    private nonisolated static func definitionMatches(
        in descriptor: SceneRenderDescriptor,
        path: String,
        profile: StockIdentityProfile
    ) -> Bool {
        let matches = descriptor.effectDefinitions.filter {
            normalizedStockPath($0.relativePath) == normalizedStockPath(path)
        }
        guard matches.count == 1, let definition = matches.first,
              normalizedStockPath(path) == definitionPath,
              definition.version == profile.version,
              definition.replacementKey == profile.replacementKey,
              definition.name == "ui_editor_effect_xray_title",
              definition.description == "ui_editor_effect_xray_description",
              definition.group == profile.group,
              definition.performance == nil,
              definition.previewPath == "preview/project.json",
              definition.editable == nil,
              definition.framebuffers.isEmpty,
              definition.dependencies.map(normalizedStockPath) == dependencies,
              definition.functions == nil,
              definition.gizmos == nil,
              definition.extraFields.isEmpty,
              definition.unknownFieldPaths.isEmpty,
              definition.passes.count == 1,
              let pass = definition.passes.first else {
            return false
        }
        return pass.passIndex == 0
            && normalizedStockPath(pass.materialPath ?? "") == materialPath
            && pass.target == nil
            && pass.bindings.isEmpty
            && pass.compose == nil
            && pass.command == nil
            && pass.source == nil
            && pass.conditions == nil
            && pass.extraFields.isEmpty
    }

    private nonisolated static func materialMatches(
        in descriptor: SceneRenderDescriptor,
        semanticSHA256: String
    ) -> Bool {
        let matches = descriptor.materialPasses.filter {
            normalizedStockPath($0.materialPath) == materialPath
        }
        guard matches.count == 1, let material = matches.first else { return false }
        return normalizedStockPath(material.id) == materialPassID
            && material.shaderPathIndependentSHA256 == semanticSHA256
            && material.passIndex == 0
            && normalizedStockPath(material.shaderPath ?? "") == shaderIdentity
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

    private nonisolated static func shaderContractMatches(
        _ contracts: [SceneShaderContract],
        profile: StockIdentityProfile,
        requiresSourceGraphIdentity: Bool
    ) -> Bool {
        let matches = contracts.filter {
            normalizedStockPath($0.identity) == shaderIdentity
        }
        guard matches.count == 1, let contract = matches.first,
              contract.sourceKind == .authoredSource,
              contract.diagnostics.isEmpty,
              contract.canonicalSHA256 == profile.shaderCanonicalSHA256,
              canonicalStockHash(contract) == profile.shaderCanonicalSHA256,
              contract.stages.count == 2 else {
            return false
        }
        let expected: [(SceneShaderContract.StageKind, String)] = [
            (.vertex, vertexPath),
            (.fragment, fragmentPath),
        ]
        let stagesMatch = zip(contract.stages, expected).allSatisfy {
            stage, fingerprint in
            stage.kind == fingerprint.0
                && normalizedStockPath(stage.relativePath) == fingerprint.1
                && stockSHA256(Data(stage.source.utf8)) == stage.rawSHA256
        }
        guard stagesMatch else { return false }
        guard requiresSourceGraphIdentity else { return true }
        guard let sourceGraph = contract.sourceGraph,
              sourceGraph.diagnostics.isEmpty,
              sourceGraph.roots.count == 2,
              sourceGraph.roots[0].label == "fragment",
              normalizedStockPath(sourceGraph.roots[0].virtualPath)
                == fragmentPath,
              sourceGraph.roots[1].label == "vertex",
              normalizedStockPath(sourceGraph.roots[1].virtualPath)
                == vertexPath,
              sourceGraph.dependencySHA256 == profile.shaderDependencySHA256,
              sourceGraph.recomputedDependencySHA256
                == profile.shaderDependencySHA256,
              sourceGraph.nodes.allSatisfy({ node in
                  let data = Data(node.source.utf8)
                  return data.count == node.byteCount
                      && stockSHA256(data) == node.rawSHA256
              }) else {
            return false
        }
        let includes = sourceGraph.nodes.filter {
            normalizedStockPath($0.virtualPath) == commonBlendingIncludePath
        }
        guard includes.count == 1, let include = includes.first else { return false }
        return include.provenance == .stock
            && stockSHA256(Data(include.source.utf8)) == include.rawSHA256
    }

    private nonisolated struct CanonicalStockShaderPayload: Encodable {
        let identity: String
        let sourceKind: SceneShaderContract.SourceKind
        let stages: [SceneShaderContract.Stage]
        let diagnostics: [SceneShaderContract.Diagnostic]
    }

    private nonisolated static func canonicalStockHash(
        _ contract: SceneShaderContract
    ) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payload = CanonicalStockShaderPayload(
            identity: contract.identity,
            sourceKind: contract.sourceKind,
            stages: contract.stages,
            diagnostics: contract.diagnostics
        )
        guard let data = try? encoder.encode(payload) else { return "" }
        return stockSHA256(data)
    }

    private nonisolated static func normalizedStockPath(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private nonisolated static func stockSHA256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static let definitionPath = "effects/xray/effect.json"
    nonisolated static let materialPath = "materials/effects/xray.json"
    nonisolated static let materialPassID = "\(materialPath)#0"
    nonisolated static let shaderIdentity = "effects/xray"
    nonisolated static let currentStockIdentityProfile = StockIdentityProfile(
        version: 1,
        replacementKey: "xray",
        group: "interactive",
        materialSemanticSHA256: stockMaterialSemanticSHA256,
        shaderCanonicalSHA256:
            "ae769d9b366c49d19957a5f9254bb113a0250c648e3df1e477160e407e652e00",
        shaderDependencySHA256:
            "085fdbac854d56bc33880f217065210dbb1d6d694da79ff4d66a7a86b7a911e9"
    )
    nonisolated static let legacyStockIdentityProfile = StockIdentityProfile(
        version: nil,
        replacementKey: nil,
        group: "colorize",
        materialSemanticSHA256: stockMaterialSemanticSHA256,
        shaderCanonicalSHA256:
            "2282ff824267047378841e0b504c1f20137f7527883d8de5914ea6ab942cd44e",
        shaderDependencySHA256:
            "86764cbeed420c09ca2d18eff1ba6ac217a5b14cdf8aaeba071f9cac089275c8"
    )
    nonisolated static let stockIdentityProfiles = [
        currentStockIdentityProfile,
        legacyStockIdentityProfile,
    ]
    private nonisolated static let stockMaterialSemanticSHA256 =
        "f07dfa1b7f21c1c99742c66dfa14ab8c747ebc78a1a7573680329950ad40e121"
    private nonisolated static let dependencies = [
        materialPath,
        "shaders/effects/xray.frag",
        "shaders/effects/xray.vert",
    ]
    private nonisolated static let vertexPath = "shaders/effects/xray.vert"
    private nonisolated static let fragmentPath = "shaders/effects/xray.frag"
    private nonisolated static let commonBlendingIncludePath =
        "shaders/common_blending.h"
}
