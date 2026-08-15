import Foundation

extension SceneDocument {
    /// 编辑器生成的 2D camera path record。它没有可绘制内容，`path` 是作者路径身份；
    /// Timeline consumer 只在单一 default-camera record 上准入 bounded origin/zoom 组。
    struct Scene2DCameraPathDefinition: Codable, Equatable {
        let camera: String
        let path: String
        let queueMode: String?
        let zoom: Double?

        nonisolated static func parse(
            _ root: [String: Any]
        ) -> Scene2DCameraPathDefinition? {
            guard let camera = nonEmptyString(root["camera"]),
                  let path = nonEmptyString(root["path"]) else { return nil }
            return Scene2DCameraPathDefinition(
                camera: camera,
                path: path,
                queueMode: nonEmptyString(root["queuemode"])?.lowercased(),
                zoom: number(root["zoom"])
            )
        }

        private nonisolated static func nonEmptyString(_ value: Any?) -> String? {
            let string: String?
            if let value = value as? String {
                string = value
            } else {
                string = (value as? [String: Any])?["value"] as? String
            }
            guard let string else { return nil }
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        private nonisolated static func number(_ value: Any?) -> Double? {
            if let value = value as? Double { return value }
            if let value = value as? Int { return Double(value) }
            if let wrapper = value as? [String: Any] { return number(wrapper["value"]) }
            return nil
        }
    }

    /// 挂在 layer 级宿主属性上的作者 Timeline。
    ///
    /// 另外两条通路不走这里：effect constant 上的 Timeline 由 `ShaderValue.timeline`
    /// 携带（宿主身份是 effectIndex/passIndex/name）；粒子 `instanceoverride.*` 上的
    /// Timeline 属于粒子通路，由下方
    /// `SceneParticleTimeline` 单独保真，不走 layer Timeline target。
    struct SceneObjectTimeline: Codable, Equatable {
        /// 作者 JSON 中的宿主属性名，同时也是 target 身份的一部分。
        ///
        /// `maxwidth` 与 bounded 2D camera Combined `zoom` 已有 typed target；其余 zoom
        /// 形态仍只在 IR 保真，能否写回由 target 编译阶段判定并诊断，不在解析期假装
        /// 作者没写。
        enum Host: String, CaseIterable, Codable {
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

    /// Particle `instanceoverride.*` 上的作者 Timeline。
    ///
    /// position 与 angles 共用同一三 lane Timeline wire shape，但执行能力不同：
    /// position 可由现有 emitter origin 消费，angles 目前只保真到 typed snapshot。
    struct SceneParticleTimeline: Codable, Equatable {
        enum Field: String, Codable {
            case alpha
            case size
            case lifetime
            case rate
            case speed
            case count
            case brightness
            case position
            case angles
        }

        let index: Int?
        let field: Field
        let animation: SceneTimelineAnimation

        nonisolated var hostLabel: String {
            switch field {
            case .alpha: "alpha"
            case .size: "size"
            case .lifetime: "lifetime"
            case .rate: "rate"
            case .speed: "speed"
            case .count: "count"
            case .brightness: "brightness"
            case .position: "controlpoint\(index ?? -1)"
            case .angles: "controlpointangle\(index ?? -1)"
            }
        }
    }

    struct SceneObject: Identifiable {
        let id: Int
        let name: String?
        var cameraPath: Scene2DCameraPathDefinition? = nil
        let imagePath: String?
        let particlePath: String?
        var spotLight: SceneSpotLightDefinition? = nil
        let particleInstanceOverride: SceneParticleInstanceOverride?
        var particleRateAudioScript: SceneAudioScaledValueScriptDefinition? = nil
        let utilityLayer: SceneUtilityLayer?
        let shape: String?
        let dependencyLayerIDs: [Int]
        var authoredDependencies: [SceneObjectDependency] = []
        let parentID: Int?
        let attachmentName: String?
        let puppetAnimationLayers: [ScenePuppetAnimationLayer]
        let visible: Bool?
        let alpha: Double?
        let displayScriptOwnership: SceneLayerDisplayScriptOwnership
        let colorRGB: [Float]?
        let colorBlendMode: Int?
        // 作者 `brightness`：layer 颜色乘数，随包 `razer_bedroom` 的 wave layer 用 3.0/4.0
        // 做过曝发光，其余随包 object 都是 1.0。text 通道在 CoreText 栅格化阶段已消费同名
        // key（见 SceneTextDescriptor.brightness），所以这里保留原始声明而不折进 colorRGB。
        let brightness: Double?
        // IImageLayer 的 quad pivot；与 text 的 horizontal/vertical alignment 是两套合同。
        let imageAlignment: String?
        let origin: String?
        let size: String?
        let scale: String?
        var scaleHasScript: Bool? = nil
        var scaleAudioScript: SceneAudioScaledValueScriptDefinition? = nil
        let angles: String?
        let parallaxDepth: String?
        let disablesParallaxPropagation: Bool
        let text: String?
        let textStyle: SceneTextDescriptor?
        let textScript: SceneTextScriptDefinition?
        let scriptBindings: [SceneScriptBindingDefinition]
        let textureAnimationScripts: [SceneTextureAnimationScriptDefinition]
        let hasInlineScript: Bool
        let effects: [SceneEffect]
        let effectFiles: [String]
        let texturePaths: [String]
        /// 作者在 layer 级属性上声明的 Timeline，按 `Host.allCases` 顺序保存。
        let timelines: [SceneObjectTimeline]
        /// layer 级 Timeline fail-closed 的原因，形如 `alpha:unknownMode`。
        let timelineDiagnostics: [String]
        /// Particle instance Timeline，先 scalar，再按 CP index 排序。
        let particleTimelines: [SceneParticleTimeline]
        let particleTimelineDiagnostics: [String]
    }
}
