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
        var visible: Bool?
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
        let shaderPathIndependentSHA256: String
        let passIndex: Int
        let shaderPath: String?
        let texturePaths: [String]
        let textureSlots: [String?]
        let userTextureInputs: [SceneEffectTextureInput?]
        let combos: [String: Int]
        let constantShaderValues: [String: SceneDocument.ShaderValue]
        /// `usershadervalues` 声明的「shader 值名 -> 用户属性名」绑定，与 `constantShaderValues`
        /// 并列且 key 不重叠；当前只保存声明，尚无 executor 消费。
        let userShaderValues: [String: String]
        let blending: String?
        let depthTest: String?
        let depthWrite: String?
        let cullMode: String?
        let alphaWriting: String?
    }
}
