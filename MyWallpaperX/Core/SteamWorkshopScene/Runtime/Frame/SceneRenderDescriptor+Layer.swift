import Foundation

extension SceneRenderDescriptor {
    struct Layer: Identifiable, Codable {
        let id: Int
        let layerIndex: Int
        let name: String?
        /// Immutable authored object for SceneScript initial-configuration queries.
        var initialConfiguration: SceneJSONValue? = nil
        var cameraPath: SceneDocument.Scene2DCameraPathDefinition? = nil
        let contentKind: String
        let imagePath: String?
        /// Prepared layer-local static slot 0; nil inherits the model material.
        var staticBaseTexturePath: String? = nil
        var staticModelPath: String? = nil
        var modelShadowCastIntent: SceneShadowCastIntent? = nil
        var usesPerspective: Bool? = nil
        let particlePath: String?
        var pointLight: ScenePointLightDefinition? = nil
        var spotLight: SceneSpotLightDefinition? = nil
        var directionalLight: SceneDirectionalLightDefinition? = nil
        var particleInstanceOverride: SceneParticleInstanceOverride?
        let utilityLayer: SceneUtilityLayer?
        let dependencyLayerIDs: [Int]
        var authoredDependencies: [SceneObjectDependency] = []
        let parentID: Int?
        var childLayerIDs: [Int]
        let attachmentName: String?
        let parentAttachmentBindFrame: [Float]?
        let puppetAnimationLayers: [ScenePuppetAnimationLayer]
        /// Omission retains the layer default; false disables cursor hits, not scripts.
        var solid: Bool? = nil
        var visible: Bool?
        var alpha: Double?
        var displayScriptOwnership: SceneLayerDisplayScriptOwnership? = nil
        var colorRGB: [Float]?
        let colorBlendMode: Int?
        /// Layer-local sampler overrides; omission preserves the candidate's
        /// authored TEX sampler state.
        var clampUVs: Bool? = nil
        var noInterpolation: Bool? = nil
        // 作者 `brightness` 颜色乘数；text 通道已在 CoreText 栅格化阶段消费同名 key。
        let brightness: Double?
        // image/solid quad pivot: center/top/right/bottom/left and corner variants.
        let imageAlignment: String?
        let origin: String?
        let size: String?
        let scale: String?
        var scaleHasScript: Bool? = nil
        let angles: String?
        var originHasScript: Bool? = nil
        var anglesHasScript: Bool? = nil
        // Numeric transform fields parsed from the corresponding string fields.
        // originXYZ: world-space center (3 floats, defaults to [0,0,0]).
        // sizeWH: world-space size in pixels (2 floats, defaults to [0,0]).
        // scaleXYZ: per-axis scale factor (3 floats, defaults to [1,1,1]).
        // anglesXYZ: rotation in radians around X/Y/Z (3 floats, defaults to [0,0,0]).
        var originXYZ: [Float]?
        var sizeWH: [Float]?
        var scaleXYZ: [Float]?
        var anglesXYZ: [Float]?
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

        /// The local capture/replay profile. Group targets already contain
        /// member world transforms and retain their full-viewport output.
        nonisolated var hasPerspectiveGeometryConsumer: Bool {
            guard let utility = utilityLayer else {
                return ["image", "solid", "text", "model"].contains(contentKind)
            }
            return utility.kind == .composition && contentKind == "composition"
                && utility.copyBackground && !utility.passthrough
                && parentID == nil && childLayerIDs.isEmpty
                && dependencyLayerIDs.isEmpty && authoredDependencies.isEmpty
        }

        nonisolated var supportsDirectLayerColorConsumer: Bool {
            contentKind == "solid"
                || (contentKind == "image" && effects.isEmpty)
        }

        /// Potential user-property input. Effectful images additionally need
        /// their prepared capture route at launch; script admission is separate.
        nonisolated var supportsUserPropertyLayerColorConsumer: Bool {
            supportsDirectLayerColorConsumer
                || supportsUserPropertyImageSourceModulationConsumer
        }

        nonisolated var supportsUserPropertyImageSourceModulationConsumer: Bool {
            contentKind == "image" && puppetMeshPath == nil && staticModelPath == nil
                && dependencyLayerIDs.isEmpty && authoredDependencies.isEmpty
        }

        nonisolated var renderSizeWH: [Float]? {
            sizeWH
        }

        nonisolated var authoredLightIntensity: Float? {
            pointLight?.intensity
                ?? spotLight?.intensity
                ?? directionalLight?.intensity
        }

    }
}

extension SceneRenderDescriptor {
    /// Launch-prepared logical geometry. Authored configuration and all other
    /// fields retain their provenance while every consumer shares sizeWH.
    func applyingPreparedImageGeometry(_ sizes: [Int: [Float]]) -> Self {
        var prepared = self
        for index in prepared.layers.indices {
            if let size = sizes[prepared.layers[index].id] {
                prepared.layers[index].sizeWH = size
            }
        }
        return prepared
    }
}
