import Foundation

extension SceneRenderDescriptor {
    struct Layer: Identifiable, Codable {
        let id: Int
        let layerIndex: Int
        let name: String?
        var cameraPath: SceneDocument.Scene2DCameraPathDefinition? = nil
        let contentKind: String
        let imagePath: String?
        let particlePath: String?
        var spotLight: SceneSpotLightDefinition? = nil
        var particleInstanceOverride: SceneParticleInstanceOverride?
        let utilityLayer: SceneUtilityLayer?
        let dependencyLayerIDs: [Int]
        var authoredDependencies: [SceneObjectDependency] = []
        let parentID: Int?
        let childLayerIDs: [Int]
        let attachmentName: String?
        let parentAttachmentBindFrame: [Float]?
        let puppetAnimationLayers: [ScenePuppetAnimationLayer]
        var visible: Bool?
        let alpha: Double?
        var displayScriptOwnership: SceneLayerDisplayScriptOwnership? = nil
        let colorRGB: [Float]?
        let colorBlendMode: Int?
        // 作者 `brightness` 颜色乘数；text 通道已在 CoreText 栅格化阶段消费同名 key。
        let brightness: Double?
        // image/solid quad pivot: center/top/right/bottom/left and corner variants.
        let imageAlignment: String?
        let origin: String?
        let size: String?
        let scale: String?
        var scaleHasScript: Bool? = nil
        let angles: String?
        // Numeric transform fields parsed from the corresponding string fields.
        // originXYZ: world-space center (3 floats, defaults to [0,0,0]).
        // sizeWH: world-space size in pixels (2 floats, defaults to [0,0]).
        // scaleXYZ: per-axis scale factor (3 floats, defaults to [1,1,1]).
        // anglesXYZ: rotation in radians around X/Y/Z (3 floats, defaults to [0,0,0]).
        let originXYZ: [Float]?
        let sizeWH: [Float]?
        let scaleXYZ: [Float]?
        let anglesXYZ: [Float]?
        let parallaxDepthXY: [Float]?
        let disablesParallaxPropagation: Bool
        // layer 级宿主属性上的 Timeline；effect constant 的那份由
        // `effects[].passes[].constantShaderValues[].timeline` 携带。
        let timelines: [SceneDocument.SceneObjectTimeline]
        let timelineDiagnostics: [String]
        var particleTimelines: [SceneDocument.SceneParticleTimeline] = []
        var particleTimelineDiagnostics: [String] = []
        let modelCropOffsetXY: [Float]?
        // Puppet `.mdl` path plus the authored animation layer declarations.
        let puppetMeshPath: String?
        let text: String?
        let textStyle: SceneTextDescriptor?
        var textScript: SceneTextScriptDefinition? = nil
        var scriptBindings: [SceneScriptBindingDefinition]? = nil
        var textureAnimationScripts: [SceneTextureAnimationScriptDefinition]? = nil
        let hasInlineScript: Bool
        var effects: [EffectDescriptor]
        let effectFiles: [String]
        let texturePaths: [String]

        nonisolated var isImageRenderable: Bool {
            contentKind == "image" || contentKind == "solid"
        }

        nonisolated var renderSizeWH: [Float]? {
            sizeWH
        }

    }
}
