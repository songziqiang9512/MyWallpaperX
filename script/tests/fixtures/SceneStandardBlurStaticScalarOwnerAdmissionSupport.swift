import Foundation

struct SceneDocument {}
struct SceneTimelineAnimation: Codable {}

struct SceneLayerDisplayScriptOwnership {
    let fields: [String]

    var isEmpty: Bool { fields.isEmpty }
}

struct SceneUtilityLayer {
    enum Kind { case composition, project, fullscreen }

    let kind: Kind
    let copyBackground: Bool
    let passthrough: Bool
}

struct SceneRenderDescriptor {
    struct EffectDescriptor {
        struct PassDescriptor {
            let passIndex: Int
            let texturePaths: [String]
            let textureSlots: [String?]
            let userTextureInputs: [SceneEffectTextureInput?]
            let combos: [String: Int]
            let constantShaderValues: [String: SceneDocument.ShaderValue]
        }

        let id: String
        let file: String
        let visible: Bool?
        let passes: [PassDescriptor]
    }

    struct Layer {
        let id: Int
        let contentKind: String
        var utilityLayer: SceneUtilityLayer? = nil
        var dependencyLayerIDs: [Int] = []
        var authoredDependencies: [Int] = []
        var parentID: Int? = nil
        var childLayerIDs: [Int] = []
        var visible: Bool? = true
        var displayScriptOwnership: SceneLayerDisplayScriptOwnership? = nil
        let effects: [EffectDescriptor]
    }

    struct MaterialPassDescriptor {
        let id: String
        let materialPath: String
        let passIndex: Int
        let shaderPath: String?
        let texturePaths: [String]
        let textureSlots: [String?]
        let userTextureInputs: [SceneEffectTextureInput?]
        let combos: [String: Int]
        let constantShaderValues: [String: SceneDocument.ShaderValue]
        let userShaderValues: [String: String]
        let blending: String?
        let depthTest: String?
        let depthWrite: String?
        let cullMode: String?
        let alphaWriting: String?
    }

    let layers: [Layer]
    let renderOrderLayerIDs: [Int]
    let materialPasses: [MaterialPassDescriptor]

    init(
        layers: [Layer],
        renderOrderLayerIDs: [Int]? = nil,
        materialPasses: [MaterialPassDescriptor]
    ) {
        self.layers = layers
        self.renderOrderLayerIDs = renderOrderLayerIDs ?? layers.map(\.id)
        self.materialPasses = materialPasses
    }
}

nonisolated struct SceneResolvedMaterialRuntimeCatalog {
    struct Key: Hashable {
        let effect: SceneAuthoredEffectRenderPlan.EffectKey
        let nodeIndex: Int
    }
}

extension SceneEffectStageExecutionPlan {
    enum Backend { case standardBlur(SceneStandardBlurPlan) }
}
