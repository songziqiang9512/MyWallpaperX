import Foundation

extension SceneRenderDescriptor {
    struct EffectDescriptor: Identifiable, Codable {
        struct PassDescriptor: Identifiable, Codable {
            let id: Int?
            let passIndex: Int
            let texturePaths: [String]
            let textureSlots: [String?]
            let userTextureInputs: [SceneEffectTextureInput?]
            let combos: [String: Int]
            let constantShaderValues: [String: SceneDocument.ShaderValue]
            let constantShaderValueKeys: [String]
        }

        let id: String
        let effectID: Int?
        let name: String?
        let file: String
        let visible: Bool?
        let passes: [PassDescriptor]
    }

    struct ModelMaterialLink: Identifiable, Codable {
        let modelPath: String
        let materialPath: String?

        var id: String { modelPath }
    }

    struct MaterialPassDescriptor: Identifiable, Codable {
        let id: String
        let materialPath: String
        let materialRawSHA256: String
        let passIndex: Int
        let shaderPath: String?
        let texturePaths: [String]
        let textureSlots: [String?]
        let userTextureInputs: [SceneEffectTextureInput?]
        let combos: [String: Int]
        let constantShaderValues: [String: SceneDocument.ShaderValue]
        let blending: String?
        let depthTest: String?
        let depthWrite: String?
        let cullMode: String?
    }
}
