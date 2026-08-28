import Foundation

/// 把编译好的 Timeline 接到每帧的动态值求值上。
///
/// 求值发生在 host 层而不是 `SceneSurfaceEvaluationTransaction` 内部：Timeline 只依赖
/// 绝对 scene time，对所有 surface 同值，算一次即可；transaction 仍按 surface 独立提交。
nonisolated enum SceneTimelineRuntime {
    /// Timeline target 必须出现在 definitions 里，否则 `SceneDynamicSnapshotResolver`
    /// 会判 `unknownTarget` 丢弃。
    ///
    /// 同一 target 两边都声明时只保留 property 那份：definition 只提供值类型和作者基值，
    /// 两边本就同源，重复反而会触发 resolver 的 `duplicateDefinition` 把该 target 整个
    /// 丢掉。真正的取值优先级由 `SceneDynamicSource` 决定（timeline 高于 userProperty）。
    nonisolated static func mergedDefinitions(
        propertyDefinitions: [SceneDynamicTargetDefinition],
        timelineProgram: SceneTimelineProgram
    ) -> [SceneDynamicTargetDefinition] {
        guard !timelineProgram.bindings.isEmpty else { return propertyDefinitions }
        let existing = Set(propertyDefinitions.map(\.target))
        return propertyDefinitions + timelineProgram.bindings.compactMap { binding in
            existing.contains(binding.target) ? nil : binding.definition
        }
    }

    /// 求出该 scene time 下全部 Timeline 的值。
    nonisolated static func values(
        program: SceneTimelineProgram,
        sceneTime: Double
    ) -> [SceneDynamicTarget: SceneDynamicValue] {
        program.bindings.reduce(into: [:]) { values, binding in
            guard let value = value(of: binding, sceneTime: sceneTime) else { return }
            values[binding.target] = value
        }
    }

    /// lane 值按 target 的声明类型装箱。编译期已保证 lane 数与类型一致，这里只兜底。
    private nonisolated static func value(
        of binding: SceneTimelineBinding,
        sceneTime: Double
    ) -> SceneDynamicValue? {
        value(
            of: binding,
            lanes: SceneTimelineEvaluator.values(
                of: binding.animation,
                sceneTime: sceneTime
            )
        )
    }

    nonisolated static func value(
        of binding: SceneTimelineBinding,
        elapsedFrames: Double
    ) -> SceneDynamicValue? {
        value(
            of: binding,
            lanes: SceneTimelineEvaluator.values(
                of: binding.animation,
                elapsedFrames: elapsedFrames
            )
        )
    }

    private nonisolated static func value(
        of binding: SceneTimelineBinding,
        lanes sourceLanes: [Double]
    ) -> SceneDynamicValue? {
        var lanes = sourceLanes
        guard lanes.allSatisfy(\.isFinite) else { return nil }
        if binding.composition == .additive {
            guard let authored = components(of: binding.definition.authoredValue),
                  authored.count == lanes.count else { return nil }
            lanes = zip(authored, lanes).map { $0 + $1 }
            guard lanes.allSatisfy(\.isFinite) else { return nil }
        }
        switch binding.definition.valueType {
        case .scalar:
            guard lanes.count == 1 else { return nil }
            return .scalar(lanes[0])
        case .vector2:
            guard lanes.count == 2 else { return nil }
            return .vector2(lanes[0], lanes[1])
        case .vector3:
            guard lanes.count == 3 else { return nil }
            return .vector3(lanes[0], lanes[1], lanes[2])
        case .vector4:
            guard lanes.count == 4 else { return nil }
            return .vector4(lanes[0], lanes[1], lanes[2], lanes[3])
        case .bool, .string:
            return nil
        }
    }

    private nonisolated static func components(
        of value: SceneDynamicValue
    ) -> [Double]? {
        switch value {
        case let .scalar(value): [value]
        case let .vector2(x, y): [x, y]
        case let .vector3(x, y, z): [x, y, z]
        case let .vector4(x, y, z, w): [x, y, z, w]
        case .bool, .string: nil
        }
    }
}
