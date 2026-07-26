import Foundation

extension SceneDocument {
    /// 挂在 layer 级宿主属性上的作者 Timeline。
    ///
    /// 另外两条通路不走这里：effect constant 上的 Timeline 由 `ShaderValue.timeline`
    /// 携带（宿主身份是 effectIndex/passIndex/name）；粒子 `instanceoverride.*` 上的
    /// Timeline 属于粒子通路，随包 45 样本中有 7 处（全在 `2998757800`），当前两条通路
    /// 都不解析它。
    struct SceneObjectTimeline {
        /// 作者 JSON 中的宿主属性名，同时也是 target 身份的一部分。
        ///
        /// `maxwidth`/`zoom` 目前没有对应的 `SceneDynamicTarget`，但它们确实是 layer 级
        /// 宿主属性，IR 先无损保留，能否写回由 target 编译阶段判定并诊断，不在解析期
        /// 假装作者没写。
        enum Host: String, CaseIterable {
            case alpha
            case origin
            case angles
            case scale
            case size
            case color
            case maxwidth
            case zoom
        }

        let host: Host
        let animation: SceneTimelineAnimation
    }

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
        /// 作者在 layer 级属性上声明的 Timeline，按 `Host.allCases` 顺序保存。
        let timelines: [SceneObjectTimeline]
        /// layer 级 Timeline fail-closed 的原因，形如 `alpha:unknownMode`。
        let timelineDiagnostics: [String]
    }
}
