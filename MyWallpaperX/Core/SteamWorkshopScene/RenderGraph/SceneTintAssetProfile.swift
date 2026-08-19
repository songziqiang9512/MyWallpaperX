import Foundation

/// Content-derived asset identity for the bounded Tint executor.
///
/// Paths are taken from the authored definition and material instead of being selected by a
/// sample, layer, Workshop ID, or resource name. Exact material bytes and exact shader-stage
/// bytes still gate execution, so unrelated authored effects remain fail-closed.
nonisolated struct SceneTintAssetProfile {
    let definitionPath: String
    let materialPath: String
    let materialPassID: String
    let materialSHA256: String
    let shaderIdentity: String
    let shaderProfile: SceneTintShaderProfile
    let dependencies: [String]

    static func resolve(
        descriptor: SceneRenderDescriptor,
        definitionPath authoredDefinitionPath: String,
        shaderContracts: [SceneShaderContract]
    ) -> SceneTintAssetProfile? {
        let definitionPath = normalized(authoredDefinitionPath)
        let definitions = descriptor.effectDefinitions.filter {
            normalized($0.relativePath) == definitionPath
        }
        guard definitions.count == 1,
              let definition = definitions.first,
              definition.passes.count == 1,
              let authoredMaterialPath = definition.passes.first?.materialPath else {
            return nil
        }

        let materialPath = normalized(authoredMaterialPath)
        let materialPassID = "\(materialPath)#0"
        let materials = descriptor.materialPasses.filter {
            normalized($0.id) == materialPassID
        }
        guard materials.count == 1,
              let material = materials.first,
              supportedMaterialHashes.contains(material.materialRawSHA256),
              let authoredShaderIdentity = material.shaderPath else {
            return nil
        }

        let shaderIdentity = normalized(authoredShaderIdentity)
        guard let shaderProfile = SceneTintShaderProfile.resolve(
            shaderContracts,
            shaderIdentity: shaderIdentity
        ) else {
            return nil
        }
        return SceneTintAssetProfile(
            definitionPath: definitionPath,
            materialPath: materialPath,
            materialPassID: materialPassID,
            materialSHA256: material.materialRawSHA256,
            shaderIdentity: shaderIdentity,
            shaderProfile: shaderProfile,
            dependencies: [
                materialPath,
                "shaders/\(shaderIdentity).frag",
                "shaders/\(shaderIdentity).vert",
            ]
        )
    }

    private static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private static let supportedMaterialHashes: Set<String> = [
        "d5a190abf6ebc13981b7e26ca623577d2cfe0783a343e05fc1a46dcce7cb5016",
        "d17d8d375f946a4714ec1082d0fcce06793d2ec44c2ea9463b4881147cf268bf",
    ]
}
