import Foundation

/// 一条已定型的 Timeline：写哪个 target、值是什么类型、作者基值是多少，以及驱动它的动画。
nonisolated struct SceneTimelineBinding: Codable, Equatable {
    nonisolated enum Composition: String, Codable, Equatable {
        case absolute
        case additive
    }

    let definition: SceneDynamicTargetDefinition
    let animation: SceneTimelineAnimation
    let composition: Composition
    /// Nil preserves the standalone wire shape; a group uses its full root target.
    let playbackOwner: SceneDynamicTarget?

    init(
        definition: SceneDynamicTargetDefinition,
        animation: SceneTimelineAnimation,
        composition: Composition,
        playbackOwner: SceneDynamicTarget? = nil
    ) {
        self.definition = definition
        self.animation = animation
        self.composition = composition
        self.playbackOwner = playbackOwner
    }

    nonisolated var playbackOwnerTarget: SceneDynamicTarget {
        playbackOwner ?? target
    }

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
        /// Scene-level Script has no admitted value producer in this profile.
        case unsupportedScriptSource
        /// 当前只为 layer transform 定标了作者基值加动画偏移；其他 relative 仍拒绝。
        case relativeUnsupported
        /// Only complete flat transform groups and the bounded camera pair are admitted.
        case combinedAnimationUnsupported
        /// lane 数与 target 的值类型不符（例如 3 lane 写 scalar）。
        case componentMismatch
        /// instance override 缺少可用、无冲突的三分量作者基值。
        case invalidAuthoredValue
        /// target 有额外运行预算，作者 fallback 或任一 keyframe 越界。
        case valueOutOfRange
        /// 同一 target 被多条 Timeline 写入，官方未定义优先级，全部拒绝。
        case duplicateTarget
        /// `wraploop` 只支持合法 Loop 周期内的闭合段；其他形态不能猜周期边界。
        case invalidWrapLoop
    }

    private static let maximumDynamicTextWidth = 16_384.0

    nonisolated static func compile(descriptor: SceneRenderDescriptor) -> SceneTimelineProgram {
        let cameraProgram = Scene2DCameraTimelineCompiler.compile(descriptor: descriptor)
        var candidates: [(binding: SceneTimelineBinding, label: String)] = []
        var diagnostics = cameraProgram.diagnostics

        diagnostics.append(contentsOf: (descriptor.generalTimelineDiagnostics ?? []).map {
            "general \($0)"
        })
        for timeline in descriptor.generalTimelines ?? [] {
            let label = "general \(timeline.host.rawValue)"
            guard descriptor.camera.bloom.hdr == nil else {
                diagnostics.append("\(label): \(Diagnostic.unsupportedHost.rawValue)")
                continue
            }
            guard !timeline.hasScript else {
                diagnostics.append("\(label): \(Diagnostic.unsupportedScriptSource.rawValue)")
                continue
            }
            guard timeline.authoredValue.isFinite else {
                diagnostics.append("\(label): \(Diagnostic.invalidAuthoredValue.rawValue)")
                continue
            }
            switch timeline.host {
            case .bloomStrength:
                append(
                    animation: timeline.animation,
                    target: .scene(.bloomStrength), valueType: .scalar,
                    authoredValue: .scalar(Double(timeline.authoredValue)),
                    label: label, into: &candidates, diagnostics: &diagnostics
                )
            }
        }

        for layer in descriptor.layers {
            diagnostics.append(contentsOf: layer.timelineDiagnostics.map {
                "layer \(layer.id) \($0)"
            })
            appendLayerTimelines(in: layer, into: &candidates, diagnostics: &diagnostics)
            diagnostics.append(contentsOf: layer.particleTimelineDiagnostics.map {
                "layer \(layer.id) \($0)"
            })
            for timeline in layer.particleTimelines {
                let label = "layer \(layer.id) instanceoverride.\(timeline.hostLabel)"
                guard let target = particleTarget(
                    timeline: timeline,
                    override: layer.particleInstanceOverride
                ) else {
                    diagnostics.append("\(label): \(Diagnostic.invalidAuthoredValue.rawValue)")
                    continue
                }
                append(
                    animation: timeline.animation,
                    target: .particle(layerID: layer.id, field: target.field),
                    valueType: target.valueType,
                    authoredValue: target.authoredValue,
                    label: label,
                    into: &candidates,
                    diagnostics: &diagnostics
                )
            }
            appendEffectConstants(in: layer, into: &candidates, diagnostics: &diagnostics)
        }

        // 同一 target 的多条 Timeline 全部丢弃：官方 Combined Animation 页面没有定义
        // 冲突优先级，按字典序或声明序挑一条都是猜。
        let allCandidates = cameraProgram.bindings.map {
            (binding: $0, label: "camera \($0.target)")
        } + candidates
        var occurrences: [SceneDynamicTarget: Int] = [:]
        for candidate in allCandidates {
            occurrences[candidate.binding.target, default: 0] += 1
        }
        let rejectedOwners = Set(allCandidates.compactMap { candidate in
            occurrences[candidate.binding.target, default: 0] > 1
                ? candidate.binding.playbackOwnerTarget : nil
        })
        var bindings: [SceneTimelineBinding] = []
        for candidate in allCandidates {
            if rejectedOwners.contains(candidate.binding.playbackOwnerTarget) {
                diagnostics.append("\(candidate.label): \(Diagnostic.duplicateTarget.rawValue)")
                continue
            }
            bindings.append(candidate.binding)
        }
        return SceneTimelineProgram(bindings: bindings, diagnostics: diagnostics.sorted())
    }

    /// Resolve membership only inside this authored layer. Connected malformed
    /// references fail as a group, including otherwise standalone referenced lanes.
    private nonisolated static func appendLayerTimelines(
        in layer: SceneRenderDescriptor.Layer,
        into candidates: inout [(binding: SceneTimelineBinding, label: String)],
        diagnostics: inout [String]
    ) {
        let timelines = layer.timelines
        let indices = timelines.indices.filter {
            layer.cameraPath == nil || (timelines[$0].host != .origin && timelines[$0].host != .zoom)
        }
        let byKey = Dictionary(grouping: indices, by: { timelines[$0].host.rawValue })
        var links: [Int: Set<Int>] = [:]
        for index in indices {
            let options = timelines[index].animation.options
            var keys = options.children.map(\.key)
            if let parent = options.parent { keys.append(parent.key) }
            guard !keys.isEmpty else { continue }
            links[index] = links[index] ?? []
            for key in keys {
                for other in byKey[key] ?? [] {
                    links[index, default: []].insert(other)
                    links[other, default: []].insert(index)
                }
            }
        }
        var visited: Set<Int> = []
        var prepared: [Int: (binding: SceneTimelineBinding, label: String)] = [:]
        for index in indices where !visited.contains(index) {
            guard links[index] != nil else {
                var standalone: [(binding: SceneTimelineBinding, label: String)] = []
                appendLayerTimeline(timelines[index], in: layer, into: &standalone,
                    diagnostics: &diagnostics)
                prepared[index] = standalone.first
                continue
            }
            var pending = [index]
            var component: Set<Int> = []
            while let current = pending.popLast() {
                guard component.insert(current).inserted else { continue }
                pending.append(contentsOf: links[current] ?? [])
            }
            visited.formUnion(component)
            let members = indices.filter { component.contains($0) }
            let roots = members.filter { timelines[$0].animation.options.parent == nil }
            let keys = members.map { timelines[$0].host.rawValue }
            guard roots.count == 1, let rootIndex = roots.first,
                  Set(keys).count == keys.count else {
                rejectLayerGroup(members.map { timelines[$0] }, in: layer, diagnostics: &diagnostics)
                continue
            }
            let root = timelines[rootIndex]
            let children = root.animation.options.children.map(\.key)
            let childKeys = members.filter { $0 != rootIndex }.map { timelines[$0].host.rawValue }
            guard !children.isEmpty, Set(children).count == children.count,
                  Set(children) == Set(childKeys),
                  root.animation.options.smoothing == nil,
                  root.animation.options.stiffness == nil,
                  members.allSatisfy({ member in
                      let timeline = timelines[member]
                      let transform = timeline.host == .origin || timeline.host == .angles
                          || timeline.host == .scale
                      return transform && timeline.animation.isRelative
                          && (member == rootIndex || (
                              timeline.animation.options.parent?.key == root.host.rawValue
                                  && timeline.animation.options.children.isEmpty
                          ))
                  }), let resolvedRoot = layerTarget(host: root.host, layer: layer) else {
                rejectLayerGroup(members.map { timelines[$0] }, in: layer, diagnostics: &diagnostics)
                continue
            }
            var groupCandidates: [(binding: SceneTimelineBinding, label: String)] = []
            for member in members {
                let timeline = timelines[member]
                appendLayerTimeline(
                    .init(host: timeline.host, animation: groupedAnimation(
                        timeline.animation, owner: root.animation, isOwner: member == rootIndex
                    )), in: layer, playbackOwner: resolvedRoot.target,
                    into: &groupCandidates, diagnostics: &diagnostics
                )
            }
            guard groupCandidates.count == members.count else {
                rejectLayerGroup(members.map { timelines[$0] }, in: layer, diagnostics: &diagnostics)
                continue
            }
            for (member, candidate) in zip(members, groupCandidates) {
                prepared[member] = candidate
            }
        }
        candidates.append(contentsOf: indices.compactMap { prepared[$0] })
    }

    private nonisolated static func rejectLayerGroup(
        _ timelines: [SceneDocument.SceneObjectTimeline],
        in layer: SceneRenderDescriptor.Layer,
        diagnostics: inout [String]
    ) {
        diagnostics.append(contentsOf: timelines.map {
            "layer \(layer.id) \($0.host.rawValue): \(Diagnostic.combinedAnimationUnsupported.rawValue)"
        })
    }

    private nonisolated static func appendLayerTimeline(
        _ timeline: SceneDocument.SceneObjectTimeline,
        in layer: SceneRenderDescriptor.Layer,
        playbackOwner: SceneDynamicTarget? = nil,
        into candidates: inout [(binding: SceneTimelineBinding, label: String)],
        diagnostics: inout [String]
    ) {
        let label = "layer \(layer.id) \(timeline.host.rawValue)"
        guard let resolved = layerTarget(host: timeline.host, layer: layer) else {
            diagnostics.append("\(label): \(Diagnostic.unsupportedHost.rawValue)")
            return
        }
        if case .maxwidth = timeline.host, !isBoundedTextWidth(timeline.animation, layer: layer) {
            diagnostics.append("\(label): \(Diagnostic.valueOutOfRange.rawValue)")
            return
        }
        if playbackOwner != nil {
            guard case let .vector3(x, y, z) = resolved.authoredValue,
                  [x, y, z].allSatisfy(\.isFinite),
                  timeline.animation.lanes.allSatisfy({ lane in
                      timeline.animation.consumedControlValues(in: lane).allSatisfy(\.isFinite)
                  }) else {
                diagnostics.append("\(label): \(Diagnostic.invalidAuthoredValue.rawValue)")
                return
            }
        }
        append(animation: timeline.animation, target: resolved.target,
            valueType: resolved.valueType, authoredValue: resolved.authoredValue,
            label: label, playbackOwner: playbackOwner,
            into: &candidates, diagnostics: &diagnostics)
    }

    /// Both camera and ordinary groups inherit one clock without lending a
    /// display name to child bindings or retaining executable wire references.
    nonisolated static func groupedAnimation(
        _ animation: SceneTimelineAnimation,
        owner: SceneTimelineAnimation,
        isOwner: Bool
    ) -> SceneTimelineAnimation {
        let options = owner.options
        var clock = SceneTimelineOptions(
            fps: options.fps, length: options.length, mode: options.mode,
            startsPaused: options.startsPaused, wrapsLoop: options.wrapsLoop,
            smoothing: options.smoothing, stiffness: options.stiffness,
            parent: nil, children: []
        )
        clock.name = isOwner ? options.name : nil
        return SceneTimelineAnimation(lanes: animation.lanes, options: clock,
            isRelative: animation.isRelative, previewValue: animation.previewValue)
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
                    guard let dynamicValue = effectConstantValue(value) else {
                        diagnostics.append(
                            "\(label): \(Diagnostic.invalidAuthoredValue.rawValue)"
                        )
                        continue
                    }
                    append(
                        animation: animation,
                        target: .effectConstant(
                            layerID: layer.id,
                            effectIndex: effectIndex,
                            passIndex: pass.passIndex,
                            name: name
                        ),
                        valueType: dynamicValue.type,
                        authoredValue: dynamicValue.value,
                        label: label,
                        into: &candidates,
                        diagnostics: &diagnostics
                    )
                }
            }
        }
    }

    private nonisolated static func effectConstantValue(
        _ shaderValue: SceneDocument.ShaderValue
    ) -> (type: SceneDynamicValueType, value: SceneDynamicValue)? {
        let tokens = shaderValue.rawValue.split(
            whereSeparator: { $0 == " " || $0 == "," || $0 == "\t" }
        )
        guard (1...4).contains(tokens.count) else { return nil }
        let values = tokens.compactMap { Double($0) }
        guard values.count == tokens.count,
              values.allSatisfy(\.isFinite) else { return nil }
        switch values.count {
        case 1: return (.scalar, .scalar(values[0]))
        case 2: return (.vector2, .vector2(values[0], values[1]))
        case 3: return (.vector3, .vector3(values[0], values[1], values[2]))
        case 4:
            return (
                .vector4,
                .vector4(values[0], values[1], values[2], values[3])
            )
        default: return nil
        }
    }

    private nonisolated static func particleTarget(
        timeline: SceneDocument.SceneParticleTimeline,
        override: SceneParticleInstanceOverride?
    ) -> (field: SceneDynamicParticleField, valueType: SceneDynamicValueType,
          authoredValue: SceneDynamicValue)? {
        let boundValue: SceneParticleBoundValue?
        let field: SceneDynamicParticleField
        switch timeline.field {
        case .alpha: (boundValue, field) = (override?.alpha, .alpha)
        case .size: (boundValue, field) = (override?.size, .size)
        case .lifetime: (boundValue, field) = (override?.lifetime, .lifetime)
        case .rate: (boundValue, field) = (override?.rate, .rate)
        case .speed: (boundValue, field) = (override?.speed, .speed)
        case .count: (boundValue, field) = (override?.count, .count)
        case .brightness: (boundValue, field) = (override?.brightness, .brightness)
        case .position:
            guard let index = timeline.index else { return nil }
            boundValue = override?.controlPoints[index]
            field = .controlPoint(index)
        case .angles:
            guard let index = timeline.index else { return nil }
            boundValue = override?.controlPointAngles[index]
            field = .controlPointAngles(index)
        }
        guard boundValue?.userPropertyKey == nil,
              boundValue?.hasScript == false else { return nil }
        switch timeline.field {
        case .position, .angles:
            guard case let .vector(values)? = boundValue?.value,
                  values.count == 3, values.allSatisfy({ $0.isFinite }) else { return nil }
            return (field, .vector3, .vector3(values[0], values[1], values[2]))
        default:
            guard case let .scalar(value)? = boundValue?.value, value.isFinite else { return nil }
            return (field, .scalar, .scalar(value))
        }
    }

    private nonisolated static func append(
        animation: SceneTimelineAnimation,
        target: SceneDynamicTarget,
        valueType: SceneDynamicValueType,
        authoredValue: SceneDynamicValue,
        label: String,
        playbackOwner: SceneDynamicTarget? = nil,
        into candidates: inout [(binding: SceneTimelineBinding, label: String)],
        diagnostics: inout [String]
    ) {
        let composition: SceneTimelineBinding.Composition
        if animation.isRelative {
            guard supportsAdditiveComposition(target) else {
                diagnostics.append("\(label): \(Diagnostic.relativeUnsupported.rawValue)")
                return
            }
            composition = .additive
        } else {
            composition = .absolute
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
        guard animation.hasExecutableWrapLoop else {
            diagnostics.append("\(label): \(Diagnostic.invalidWrapLoop.rawValue)")
            return
        }
        candidates.append((
            SceneTimelineBinding(
                definition: SceneDynamicTargetDefinition(
                    target: target,
                    valueType: valueType,
                    authoredValue: authoredValue
                ),
                animation: animation,
                composition: composition,
                playbackOwner: playbackOwner
            ),
            label
        ))
    }

    private nonisolated static func supportsAdditiveComposition(
        _ target: SceneDynamicTarget
    ) -> Bool {
        guard case let .layer(_, field) = target else { return false }
        return field == .origin || field == .angles || field == .scale
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
        case .maxwidth:
            guard layer.contentKind == "text", let style = layer.textStyle,
                  style.limitWidth else { return nil }
            return (
                .text(layerID: layer.id, field: .maxWidth),
                .scalar,
                .scalar(Double(style.maxWidth))
            )
        // size/color 有 target 但随包没有 Timeline 样本；zoom 的唯一真实形态由
        // bounded 2D Camera Combined 编译器按组处理，不能脱组猜成普通 layer scalar。
        case .size, .color, .zoom:
            return nil
        }
    }

    private nonisolated static func isBoundedTextWidth(
        _ animation: SceneTimelineAnimation,
        layer: SceneRenderDescriptor.Layer
    ) -> Bool {
        guard let width = layer.textStyle.map({ Double($0.maxWidth) }),
              width.isFinite, width >= 1, width <= maximumDynamicTextWidth else {
            return false
        }
        return animation.lanes.allSatisfy { lane in
            animation.consumedControlValues(in: lane).allSatisfy {
                $0.isFinite && $0 >= 1 && $0 <= maximumDynamicTextWidth
            }
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
