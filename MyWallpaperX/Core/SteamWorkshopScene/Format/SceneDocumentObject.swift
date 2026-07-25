import Foundation

extension SceneDocument {
    struct SceneObject: Identifiable {
        let id: Int
        let name: String?
        let imagePath: String?
        let particlePath: String?
        let particleInstanceOverride: SceneParticleInstanceOverride?
        let utilityLayer: SceneUtilityLayer?
        let dependencyLayerIDs: [Int]
        let parentID: Int?
        let attachmentName: String?
        let puppetAnimationLayers: [ScenePuppetAnimationLayer]
        let visible: Bool?
        let alpha: Double?
        let colorRGB: [Float]?
        let colorBlendMode: Int?
        // 作者 `brightness`：layer 颜色乘数，随包 `razer_bedroom` 的 wave layer 用 3.0/4.0
        // 做过曝发光，其余随包 object 都是 1.0。text 通道在 CoreText 栅格化阶段已消费同名
        // key（见 SceneTextDescriptor.brightness），所以这里保留原始声明而不折进 colorRGB。
        let brightness: Double?
        let origin: String?
        let size: String?
        let scale: String?
        let angles: String?
        let parallaxDepth: String?
        let disablesParallaxPropagation: Bool
        let text: String?
        let textStyle: SceneTextDescriptor?
        let hasInlineScript: Bool
        let effects: [SceneEffect]
        let effectFiles: [String]
        let texturePaths: [String]
    }
}
