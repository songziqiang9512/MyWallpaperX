import Foundation

struct SceneDocument {
    struct ShaderValue {
        let valueKind: String
        let userBinding: String?
        let components: [Double]?

        init(
            valueKind: String = "number",
            userBinding: String? = nil,
            components: [Double]?
        ) {
            self.valueKind = valueKind
            self.userBinding = userBinding
            self.components = components
        }
    }
}

struct SceneUtilityLayer {
    enum Kind { case composition, project, fullscreen }
    let kind: Kind
}

struct SceneAuthoredEffectRenderPlan {
    struct EffectKey: Hashable {
        let layerID: Int
        let effectIndex: Int
        let descriptorID: String
    }
}

struct SceneEffectTextureInput {
    enum Kind: Equatable { case path, system, property, unknown }
    let kind: Kind
    let value: String
}

struct SceneRenderDescriptor {
    struct ModelMaterialLink {
        let modelPath: String
        let materialPath: String?
    }

    struct MaterialPassDescriptor {
        let materialPath: String
        let passIndex: Int
        let texturePaths: [String]
        let textureSlots: [String?]
        let userTextureInputs: [SceneEffectTextureInput?]
    }

    struct EffectDescriptor {
        struct PassDescriptor {
            let passIndex: Int
            let texturePaths: [String]
            let textureSlots: [String?]
            let userTextureInputs: [SceneEffectTextureInput?]
            let combos: [String: Int]
            let constantShaderValues: [String: SceneDocument.ShaderValue]

            init(
                passIndex: Int,
                texturePaths: [String] = [],
                textureSlots: [String?],
                userTextureInputs: [SceneEffectTextureInput?] = [],
                combos: [String: Int],
                constantShaderValues: [String: SceneDocument.ShaderValue]
            ) {
                self.passIndex = passIndex
                self.texturePaths = texturePaths
                self.textureSlots = textureSlots
                self.userTextureInputs = userTextureInputs
                self.combos = combos
                self.constantShaderValues = constantShaderValues
            }
        }

        let id: String
        let file: String
        let visible: Bool?
        let passes: [PassDescriptor]
    }

    struct Layer {
        let id: Int
        var staticModelPath: String? = nil
        let contentKind: String
        let utilityLayer: SceneUtilityLayer?
        let dependencyLayerIDs: [Int]
        var authoredDependencies: [Int] = []
        let childLayerIDs: [Int]
        let visible: Bool?
        let effects: [EffectDescriptor]
    }

    let layers: [Layer]
    let renderOrderLayerIDs: [Int]
    var modelMaterialLinks: [ModelMaterialLink] = []
    var materialPasses: [MaterialPassDescriptor] = []
}
