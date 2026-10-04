
import Foundation

struct SceneFrameTiming {
    let wallDate: Date
    let simulationFrameTime: TimeInterval
    let sceneTime: TimeInterval
}

final class SceneMediaThumbnailInbox {
    struct Snapshot {
        struct Properties {
            let title, artist, subTitle, albumTitle, albumArtist, genres, contentType: String
        }
        struct Timeline { let position, duration: Double }
        let current: Data?
        let primaryColor: SIMD3<Double>?
        let secondaryColor: SIMD3<Double>?
        let tertiaryColor: SIMD3<Double>?
        let textColor: SIMD3<Double>?
        let highContrastColor: SIMD3<Double>?
        let generation: UInt64
        let playbackState: Int?
        let playbackGeneration: UInt64
        let properties: Properties?
        let propertiesGeneration: UInt64
        let timeline: Timeline?
        let timelineGeneration: UInt64
    }
}

struct SceneTextScriptDefinition {
    let source: String
}

struct SceneScriptDynamicImageReference: Equatable, Hashable, Sendable {
    let authoredPath: String
    let modelPath: String
}

enum SceneScriptDynamicImageReferenceAnalysis {
    static func references(
        in source: String,
        descriptor: SceneRenderDescriptor
    ) -> [SceneScriptDynamicImageReference]? { nil }
}

struct SceneShaderContract {}

enum SceneBaseMaterialColorModulationCompiler {
    struct Binding {
        let modelPath: String
        let sourceLayerID: Int
        let scriptSource: String
        let scriptProperties: [String: SceneJSONValue]
        let authoredColor: SIMD3<Double>
    }

    static func compile(
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        dynamicImageModelPaths: Set<String>,
        admittedLayerColorConsumerIDs: Set<Int>
    ) -> [Binding] { [] }
}

struct SceneScriptMaterialFunctionMutation: Equatable, Sendable {
    let layerID: Int
    let effectIndex: Int
    let functionName: String
}

enum SceneTimelinePlaybackCommand: String, Equatable, Sendable {
    case play
    case pause
    case stop
}

struct SceneTimelinePlaybackMutation: Equatable, Sendable {
    let target: SceneDynamicTarget
    let command: SceneTimelinePlaybackCommand
}

enum SceneParticleNumericValue: Equatable, Sendable {
    case scalar(Double)
    case vector([Double])
    var scalarValue: Double? {
        guard case let .scalar(value) = self else { return nil }
        return value
    }
}

struct SceneParticleBoundValue: Equatable, Sendable {
    let value: SceneParticleNumericValue?
    let userPropertyKey: String?
    let hasScript: Bool
    let hasAnimation: Bool
}

struct SceneParticleInstanceOverride: Equatable, Sendable {
    let id: Int?
    let alpha: SceneParticleBoundValue?
    let size: SceneParticleBoundValue?
    let lifetime: SceneParticleBoundValue?
    let rate: SceneParticleBoundValue?
    let speed: SceneParticleBoundValue?
    let count: SceneParticleBoundValue?
    let brightness: SceneParticleBoundValue?
    let color: SceneParticleBoundValue?
    let normalizedColor: SceneParticleBoundValue?
    let controlPoints: [Int: SceneParticleBoundValue]
    let controlPointAngles: [Int: SceneParticleBoundValue]
}

struct SceneUtilityLayer {
    enum Kind { case composition, project, fullscreen }
    let kind: Kind
    let copyBackground: Bool
    let passthrough: Bool
}

struct SceneRenderDescriptor {
    enum SceneShaderUserValueKind { case null, string }
    struct Camera { var orthoHeight: Float? = nil }
    var camera = Camera()
    struct TextStyle {
        let fontPath: String?
        let colorRGB: [Float]?
        let pointSize: Float?
    }
    struct ShaderValue {
        let scriptSource: String?
        let components: [Double]?
        let userValueKind: SceneShaderUserValueKind?
        var userBinding: String? = nil
        let bindingKeys: [String]
        let timeline: Bool?
        let timelineDiagnostics: [String]
        let scriptProperties: [String: SceneJSONValue]?

        init(
            scriptSource: String?, components: [Double]?,
            userValueKind: SceneShaderUserValueKind? = nil,
            userBinding: String? = nil,
            bindingKeys: [String] = [],
            timeline: Bool? = nil,
            timelineDiagnostics: [String] = [],
            scriptProperties: [String: SceneJSONValue]? = nil
        ) {
            self.scriptSource = scriptSource
            self.components = components
            self.userValueKind = userValueKind
            self.userBinding = userBinding
            self.bindingKeys = bindingKeys
            self.timeline = timeline
            self.timelineDiagnostics = timelineDiagnostics
            self.scriptProperties = scriptProperties
        }
    }
    struct ModelMaterialLink {
        let modelPath: String
        let materialPath: String?
    }
    struct MaterialPassDescriptor {
        let materialPath: String
        let passIndex: Int
        let constantShaderValues: [String: ShaderValue]
    }
    struct EffectDescriptor {
        struct PassDescriptor {
            let passIndex: Int
            let id: Int?
            let constantShaderValues: [String: ShaderValue]
            let textureSlots: [String?]
            let userTextureInputs: [SceneEffectTextureInput?]

            init(
                passIndex: Int,
                id: Int?,
                constantShaderValues: [String: ShaderValue],
                textureSlots: [String?] = [],
                userTextureInputs: [SceneEffectTextureInput?] = []
            ) {
                self.passIndex = passIndex
                self.id = id
                self.constantShaderValues = constantShaderValues
                self.textureSlots = textureSlots
                self.userTextureInputs = userTextureInputs
            }
        }

        let name: String?
        let effectID: Int?
        let passes: [PassDescriptor]
        let id: String
        let visible: Bool?

        init(
            name: String?,
            effectID: Int? = nil,
            passes: [PassDescriptor] = [],
            id: String = "effect",
            visible: Bool? = true
        ) {
            self.name = name
            self.effectID = effectID
            self.passes = passes
            self.id = id
            self.visible = visible
        }
    }
    struct Layer {
        let id: Int
        let layerIndex: Int
        let name: String?
        var solid: Bool? = nil
        var visible: Bool?
        let originXYZ: [Float]?
        let sizeWH: [Float]? = nil
        let scaleXYZ: [Float]?
        var anglesXYZ: [Float]? = nil
        var colorRGB: [Float]? = nil
        var spotLight: Bool? = nil
        var directionalLight: Bool? = nil
        var authoredLightIntensity: Float? { nil }
        let scaleHasScript: Bool?
        let alpha: Double?
        let effects: [EffectDescriptor]
        var contentKind: String = "image"
        var particleInstanceOverride: SceneParticleInstanceOverride? = nil
        var textScript: SceneTextScriptDefinition? = nil
        var text: String? = nil
        var textStyle: TextStyle? = nil
        var parentID: Int? = nil
        var childLayerIDs: [Int] = []
        var effectFiles: [String] = []
        var dependencyLayerIDs: [Int] = []
        var authoredDependencies: [Int] = []
        var utilityLayer: SceneUtilityLayer? = nil
        var staticModelPath: String? = nil
        var attachmentName: String? = nil
        var parentAttachmentBindFrame: [Float]? = nil
    }
    var layers: [Layer]
    var modelMaterialLinks: [ModelMaterialLink] = []
    var materialPasses: [MaterialPassDescriptor] = []
}
