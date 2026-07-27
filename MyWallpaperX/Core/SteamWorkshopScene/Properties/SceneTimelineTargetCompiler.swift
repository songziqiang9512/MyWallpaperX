import Foundation

/// 一条已定型的 Timeline：写哪个 target、值是什么类型、作者基值是多少，以及驱动它的动画。
nonisolated struct SceneTimelineBinding: Codable, Equatable {
    let definition: SceneDynamicTargetDefinition
    let animation: SceneTimelineAnimation

    nonisolated var target: SceneDynamicTarget {
        definition.target
    }
}

nonisolated struct SceneTimelineProgram: Codable, Equatable {
    let bindings: [SceneTimelineBinding]
    /// 被拒绝或被降级执行的原因，形如 `layer 6 angles: relativeUnsupported`。
    let diagnostics: [String]

    nonisolated static let empty = SceneTimelineProgram(bindings: [], diagnostics: [])
}

/// 把作者 Timeline 编译成 `SceneDynamicTargetDefinition` + 动画。
///
/// 只负责「能不能写、写到哪」，不求值；求值是 `SceneTimelineEvaluator` 的事。
/// 输出的 definition 之后要和 `propertyBindingProgram.definitions` 合并，否则
/// `SceneDynamicSnapshotResolver` 会把 Timeline 值判成 `unknownTarget` 丢弃。
nonisolated enum SceneTimelineTargetCompiler {
    private nonisolated enum Diagnostic: String {
        /// 宿主属性没有对应的 `SceneDynamicTarget`，或本批未接该 target。
        case unsupportedHost
        /// `relative` 的合成语义尚未定标，先整条拒绝而不是猜一个基准。
        case relativeUnsupported
        /// Combined Animation：同组成员共享持有方的 clock/settings，分组语义未实现。
        case combinedAnimationUnsupported
        /// lane 数与 target 的值类型不符（例如 3 lane 写 scalar）。
        case componentMismatch
        /// 同一 target 被多条 Timeline 写入，官方未定义优先级，全部拒绝。
        case duplicateTarget
        /// 非阻断：`wraploop` 的首尾平滑算法未实现，按普通 loop 执行。
        case wrapLoopIgnored
    }

    nonisolated static func compile(descriptor: SceneRenderDescriptor) -> SceneTimelineProgram {
        var candidates: [(binding: SceneTimelineBinding, label: String)] = []
        var diagnostics: [String] = []

        for layer in descriptor.layers {
            diagnostics.append(contentsOf: layer.timelineDiagnostics.map {
                "layer \(layer.id) \($0)"
            })
            for timeline in layer.timelines {
                let label = "layer \(layer.id) \(timeline.host.rawValue)"
                guard let resolved = layerTarget(host: timeline.host, layer: layer) else {
                    diagnostics.append("\(label): \(Diagnostic.unsupportedHost.rawValue)")
                    continue
                }
                append(
                    animation: timeline.animation,
                    target: resolved.target,
                    valueType: resolved.valueType,
                    authoredValue: resolved.authoredValue,
                    label: label,
                    into: &candidates,
                    diagnostics: &diagnostics
                )
            }
            appendEffectConstants(in: layer, into: &candidates, diagnostics: &diagnostics)
        }

        // 同一 target 的多条 Timeline 全部丢弃：官方 Combined Animation 页面没有定义
        // 冲突优先级，按字典序或声明序挑一条都是猜。
        var occurrences: [SceneDynamicTarget: Int] = [:]
        for candidate in candidates {
            occurrences[candidate.binding.target, default: 0] += 1
        }
        var bindings: [SceneTimelineBinding] = []
        for candidate in candidates {
            if occurrences[candidate.binding.target, default: 0] > 1 {
                diagnostics.append("\(candidate.label): \(Diagnostic.duplicateTarget.rawValue)")
                continue
            }
            bindings.append(candidate.binding)
        }
        return SceneTimelineProgram(bindings: bindings, diagnostics: diagnostics.sorted())
    }

    private nonisolated static func appendEffectConstants(
        in layer: SceneRenderDescriptor.Layer,
        into candidates: inout [(binding: SceneTimelineBinding, label: String)],
        diagnostics: inout [String]
    ) {
        for (effectIndex, effect) in layer.effects.enumerated() {
            for pass in effect.passes {
                // 字典顺序不稳定，按 constant 名排序保证同一份 scene.json 每次同序。
                for name in pass.constantShaderValues.keys.sorted() {
                    guard let value = pass.constantShaderValues[name] else { continue }
                    let label = "layer \(layer.id) effect \(effectIndex)"
                        + " pass \(pass.passIndex) \(name)"
                    diagnostics.append(contentsOf: value.timelineDiagnostics.map {
                        "\(label): \($0)"
                    })
                    guard let animation = value.timeline else { continue }
                    append(
                        animation: animation,
                        target: .effectConstant(
                            layerID: layer.id,
                            effectIndex: effectIndex,
                            passIndex: pass.passIndex,
                            name: name
                        ),
                        valueType: .scalar,
                        authoredValue: .scalar(value.components?.first ?? 0),
                        label: label,
                        into: &candidates,
                        diagnostics: &diagnostics
                    )
                }
            }
        }
    }

    private nonisolated static func append(
        animation: SceneTimelineAnimation,
        target: SceneDynamicTarget,
        valueType: SceneDynamicValueType,
        authoredValue: SceneDynamicValue,
        label: String,
        into candidates: inout [(binding: SceneTimelineBinding, label: String)],
        diagnostics: inout [String]
    ) {
        guard !animation.isRelative else {
            diagnostics.append("\(label): \(Diagnostic.relativeUnsupported.rawValue)")
            return
        }
        // 组内成员必须共用持有方的 clock，独立求值会让两条 lane 逐渐错相。
        guard animation.options.parent == nil, animation.options.children.isEmpty else {
            diagnostics.append("\(label): \(Diagnostic.combinedAnimationUnsupported.rawValue)")
            return
        }
        guard animation.componentCount == componentCount(of: valueType) else {
            diagnostics.append("\(label): \(Diagnostic.componentMismatch.rawValue)")
            return
        }
        if animation.options.wrapsLoop {
            diagnostics.append("\(label): \(Diagnostic.wrapLoopIgnored.rawValue)")
        }
        candidates.append((
            SceneTimelineBinding(
                definition: SceneDynamicTargetDefinition(
                    target: target,
                    valueType: valueType,
                    authoredValue: authoredValue
                ),
                animation: animation
            ),
            label
        ))
    }

    private nonisolated static func layerTarget(
        host: SceneDocument.SceneObjectTimeline.Host,
        layer: SceneRenderDescriptor.Layer
    ) -> (target: SceneDynamicTarget, valueType: SceneDynamicValueType, authoredValue: SceneDynamicValue)? {
        switch host {
        case .alpha:
            return (
                .layer(layerID: layer.id, field: .alpha),
                .scalar,
                .scalar(layer.alpha ?? 1)
            )
        case .origin:
            return vector3(layer: layer, field: .origin, authored: layer.originXYZ, fill: 0)
        case .angles:
            return vector3(layer: layer, field: .angles, authored: layer.anglesXYZ, fill: 0)
        case .scale:
            return vector3(layer: layer, field: .scale, authored: layer.scaleXYZ, fill: 1)
        // size/color 有 target 但随包没有 Timeline 样本，maxwidth/zoom 连 target 都没有；
        // 两类都不接，等出现真实样本再单独定合同。
        case .size, .color, .maxwidth, .zoom:
            return nil
        }
    }

    private nonisolated static func vector3(
        layer: SceneRenderDescriptor.Layer,
        field: SceneDynamicLayerField,
        authored: [Float]?,
        fill: Float
    ) -> (SceneDynamicTarget, SceneDynamicValueType, SceneDynamicValue) {
        let values = authored ?? []
        return (
            .layer(layerID: layer.id, field: field),
            .vector3,
            .vector3(
                Double(values.count > 0 ? values[0] : fill),
                Double(values.count > 1 ? values[1] : fill),
                Double(values.count > 2 ? values[2] : fill)
            )
        )
    }

    private nonisolated static func componentCount(of valueType: SceneDynamicValueType) -> Int {
        switch valueType {
        case .bool, .scalar, .string: 1
        case .vector2: 2
        case .vector3: 3
        case .vector4: 4
        }
    }
}
