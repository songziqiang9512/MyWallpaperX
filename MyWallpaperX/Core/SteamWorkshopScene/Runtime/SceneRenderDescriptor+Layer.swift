import Foundation

extension SceneRenderDescriptor {
    struct Layer: Identifiable, Codable {
        let id: Int
        let layerIndex: Int
        let name: String?
        let contentKind: String
        let imagePath: String?
        let particlePath: String?
        let particleInstanceOverride: SceneParticleInstanceOverride?
        let utilityLayer: SceneUtilityLayer?
        let dependencyLayerIDs: [Int]
        let parentID: Int?
        let childLayerIDs: [Int]
        let attachmentName: String?
        let parentAttachmentBindFrame: [Float]?
        let puppetAnimationLayers: [ScenePuppetAnimationLayer]
        let visible: Bool?
        let alpha: Double?
        let colorRGB: [Float]?
        let colorBlendMode: Int?
        // 作者 `brightness` 颜色乘数；text 通道已在 CoreText 栅格化阶段消费同名 key。
        let brightness: Double?
        // image/solid quad pivot: center/top/right/bottom/left and corner variants.
        let imageAlignment: String?
        let origin: String?
        let size: String?
        let scale: String?
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
        let modelCropOffsetXY: [Float]?
        // Puppet `.mdl` path plus the authored animation layer declarations.
        let puppetMeshPath: String?
        let text: String?
        let textStyle: SceneTextDescriptor?
        let hasInlineScript: Bool
        let effects: [EffectDescriptor]
        let effectFiles: [String]
        let texturePaths: [String]

        nonisolated var isImageRenderable: Bool {
            contentKind == "image" || contentKind == "solid"
        }

        nonisolated var renderSizeWH: [Float]? {
            guard contentKind == "text", let textStyle else { return sizeWH }
            return SceneTextGeometry.expandedSize(
                authoredSize: sizeWH,
                padding: textStyle.padding
            ) ?? sizeWH
        }

    }
}
