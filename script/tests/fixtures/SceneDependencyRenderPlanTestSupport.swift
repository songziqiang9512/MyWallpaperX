import Foundation
import Metal

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
    enum Kind: String { case composition, project, fullscreen }
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
        var combos: [String: Int] = [:]
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
        struct DisplayScriptOwnership { let visible: Bool }
        var displayScriptOwnership: DisplayScriptOwnership? = nil
        var parentID: Int? = nil
        var colorBlendMode: Int? = nil
        let id: Int
        var staticModelPath: String? = nil
        var puppetMeshPath: String? = nil
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

// Adjacent owners used by the utility planning harness. Tests below exercise
// dependency selection; parent visibility and source coverage have separate gates.
enum SceneLayerVisibility {
    static func visibleLayerIDs(in descriptor: SceneRenderDescriptor) -> Set<Int> {
        Set(descriptor.layers.filter { $0.visible != false }.map(\.id))
    }
}
struct SceneUtilityLayerSourceRoute {
    let usesIsolatedGroupTarget = false
    let orderedCompositionSubtreeLayerIDs: [Int] = []
    let capturesCompositionSubtree: Bool
    let triggerLayerID: Int
    static func resolve(layer: SceneRenderDescriptor.Layer, descriptor: SceneRenderDescriptor)
        -> Result<Self, NSError> {
        .success(.init(capturesCompositionSubtree: false, triggerLayerID: layer.id))
    }
}
enum SceneBlendModeShaderSource { static let maximumMode = 31 }

// This harness executes planning only. GPU dependencies share the production
// source file but must never execute through these link-only test doubles.
final class SceneMainPassEncoder {
    init(commandBuffer: MTLCommandBuffer, target: MTLTexture,
         clearColor: MTLClearColor, clearEnabled: Bool) {
        fatalError("GPU encoding is outside the dependency planning harness")
    }
    func closeForOffscreen() {
        fatalError("GPU encoding is outside the dependency planning harness")
    }
}

final class SceneOffscreenTexturePool {
    struct Target { let texture: MTLTexture }
    func compositionGroupTarget(layerID: Int, width: Int, height: Int) -> Target? {
        fatalError("GPU allocation is outside the dependency planning harness")
    }
}
