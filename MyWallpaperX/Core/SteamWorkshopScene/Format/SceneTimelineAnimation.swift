import Foundation

/// 作者 Timeline（编辑器 "Animation"）的无损 IR。
///
/// 数据形态直接来自随包 `scene.json`：`animation` 与作者基值 `value` 同级挂在宿主属性
/// 对象上，lane 以 `c0`/`c1`/`c2` 命名并共享同一份 `options`，`front`/`back` 是官方
/// Bézier `both/left/right/none` 的序列化形态。
///
/// 时间基是 `frame / fps` 而不是秒（随包三例交叉验证：`fps=15,length=15` → 1.0s；
/// `fps=4,length=2` → 0.5s；`fps=120,length=60` → 0.5s），所以帧号与 fps 必须原样
/// 保存，换算只发生在求值期。
nonisolated enum SceneTimelineMode: String, Codable, Equatable {
    case single
    case loop
    case mirror
}

/// 单侧 Bézier handle。`isEnabled == false` 对应官方 tangent mode 的 `none`，该侧退化
/// 为直线段。
///
/// clean-room corpus 定标表明 `x` 是相对当前 keyframe segment span 的比例：多组自定义
/// handle 乘回各自 span 后稳定得到整数或半帧；`y` 是当前 property value 空间中的偏移。
/// front 只接受 `0...1`，back 只接受 `-1...0`，从而保证 frame -> curve parameter 唯一。
nonisolated struct SceneTimelineTangent: Codable, Equatable {
    let isEnabled: Bool
    let x: Double
    let y: Double
}

nonisolated struct SceneTimelineKeyframe: Codable, Equatable {
    let frame: Double
    let value: Double
    let back: SceneTimelineTangent?
    let front: SceneTimelineTangent?
    /// 编辑器 handle 对称锁，运行时不消费，仅为无损往返保留。
    let locksAngle: Bool?
    let locksLength: Bool?

    /// 当前 keyframe 到 `end` 这一条普通相邻段消费的端点与 control value。首帧 back /
    /// 末帧 front 只在 wrap-loop 闭合段消费，由 animation 级 helper 另行纳入。
    nonisolated func valuesIncludingEnabledControls(
        to end: SceneTimelineKeyframe
    ) -> [Double] {
        var values = [value]
        if let front, front.isEnabled { values.append(value + front.y) }
        if let back = end.back, back.isEnabled { values.append(end.value + back.y) }
        values.append(end.value)
        return values
    }
}

/// 官方 Combined Animation 的序列化形态：同组 animation 用 property key 互相引用，并
/// 复用持有方的 mode/时长。已知 authored payload 的 `origin` 带
/// `children: [{"key": "zoom"}]`，`zoom` 带 `parent: {"key": "origin"}`。
nonisolated struct SceneTimelineGroupReference: Codable, Equatable {
    let key: String
}

nonisolated struct SceneTimelineOptions: Codable, Equatable {
    let fps: Double
    let length: Double
    let mode: SceneTimelineMode
    let startsPaused: Bool
    let wrapsLoop: Bool
    /// 随包 16 处声明但全为 null，语义未知，只做无损保留。
    let smoothing: Double?
    let stiffness: Double?
    /// Combined Animation 分组。持有方在 `children` 列出成员，成员用 `parent` 指回。
    let parent: SceneTimelineGroupReference?
    let children: [SceneTimelineGroupReference]

    /// 作者声明的总时长。`length` 是帧数，不是秒。
    nonisolated var durationSeconds: Double {
        fps > 0 ? length / fps : 0
    }
}

nonisolated struct SceneTimelineAnimation: Codable, Equatable {
    /// 按 component 下标排列的 lane：`[0]` 对应 `c0`。随包只出现 1 或 3 条。
    let lanes: [[SceneTimelineKeyframe]]
    let options: SceneTimelineOptions
    /// 推断语义为「最终值 = 作者基值 + 动画值」，尚未取得官方定义，消费方必须显式处理。
    let isRelative: Bool
    /// 编辑器预览值。**运行时不得消费**，仅为无损往返保留。
    let previewValue: Double?

    nonisolated var componentCount: Int {
        lanes.count
    }

    /// `wraploop` 只对 Loop 有执行意义。合法作者 wire 把末关键帧留在 `length` 之前，
    /// 播放器再把末帧与下一周期首帧连接成一段；范围外 keyframe 会让该段跨越哪个周期
    /// 变得不唯一，因此执行层失败关闭。
    nonisolated var hasExecutableWrapLoop: Bool {
        guard options.wrapsLoop else { return true }
        guard options.mode == .loop else { return false }
        return lanes.allSatisfy { lane in
            guard let first = lane.first, let last = lane.last else { return false }
            return first.frame >= 0 && last.frame < options.length
        }
    }

    /// 当前动画真正消费的端点与 Bézier control values。普通段使用 `start.front` /
    /// `end.back`；wrap-loop 另消费末帧 `front` 与首帧 `back`。bounded target 必须检查
    /// 这整个凸包，不能遗漏循环闭合段，也不能让单关键帧绕过作者值校验。
    nonisolated func consumedControlValues(
        in lane: [SceneTimelineKeyframe]
    ) -> [Double] {
        var values = lane.map(\.value)
        for (start, end) in zip(lane, lane.dropFirst()) {
            if let front = start.front, front.isEnabled {
                values.append(start.value + front.y)
            }
            if let back = end.back, back.isEnabled {
                values.append(end.value + back.y)
            }
        }
        if options.wrapsLoop, let first = lane.first, let last = lane.last {
            if let front = last.front, front.isEnabled {
                values.append(last.value + front.y)
            }
            if let back = first.back, back.isEnabled {
                values.append(first.value + back.y)
            }
        }
        return values
    }
}

nonisolated struct SceneTimelineDiagnostic: Equatable {
    nonisolated enum Code: String, Equatable {
        case missingOptions
        case unknownMode
        case invalidFPS
        case invalidLength
        case missingLanes
        case laneGap
        case emptyLane
        case unorderedFrames
        case nonFiniteValue
        case invalidTangent
        case invalidGroupReference
    }

    let code: Code
    /// 对应 lane 的 component 下标；整体性问题为 `nil`。
    let laneIndex: Int?

    /// 报告用的稳定短标识，宿主前缀由聚合方补。
    nonisolated var token: String {
        laneIndex.map { "\(code.rawValue)@c\($0)" } ?? code.rawValue
    }
}

nonisolated struct SceneTimelineParseResult: Equatable {
    let animation: SceneTimelineAnimation?
    let diagnostics: [SceneTimelineDiagnostic]

    nonisolated static let absent = SceneTimelineParseResult(
        animation: nil,
        diagnostics: []
    )
}

nonisolated enum SceneTimelineAnimationParser {
    private static let maximumLaneCount = 4

    /// 解析宿主属性对象上的 `animation`。传入的是宿主对象本身（例如 `alpha` 的
    /// `{"value": …, "animation": …}`），不是 `animation` 子对象。
    ///
    /// 任何硬错误都 fail closed：返回 `animation == nil` 并附带诊断，绝不产出半个动画。
    nonisolated static func parse(host value: Any?) -> SceneTimelineParseResult {
        guard let host = value as? [String: Any],
              let root = host["animation"] as? [String: Any]
        else {
            return .absent
        }
        return parse(animation: root)
    }

    nonisolated static func parse(animation root: [String: Any]) -> SceneTimelineParseResult {
        var diagnostics: [SceneTimelineDiagnostic] = []
        guard let optionsValue = root["options"] as? [String: Any] else {
            return .init(animation: nil, diagnostics: [.init(
                code: .missingOptions, laneIndex: nil
            )])
        }
        let options = parseOptions(optionsValue, diagnostics: &diagnostics)
        let lanes = parseLanes(root, diagnostics: &diagnostics)
        guard let options, let lanes else {
            return .init(animation: nil, diagnostics: diagnostics)
        }
        let previewValue = doubleValue(root["previewvalue"])
        if let previewValue, !previewValue.isFinite {
            diagnostics.append(.init(code: .nonFiniteValue, laneIndex: nil))
            return .init(animation: nil, diagnostics: diagnostics)
        }
        return .init(
            animation: SceneTimelineAnimation(
                lanes: lanes,
                options: options,
                isRelative: root["relative"] as? Bool ?? false,
                previewValue: previewValue
            ),
            diagnostics: diagnostics
        )
    }

    private nonisolated static func parseOptions(
        _ root: [String: Any],
        diagnostics: inout [SceneTimelineDiagnostic]
    ) -> SceneTimelineOptions? {
        guard let rawMode = root["mode"] as? String,
              let mode = SceneTimelineMode(rawValue: rawMode.lowercased())
        else {
            diagnostics.append(.init(code: .unknownMode, laneIndex: nil))
            return nil
        }
        guard let fps = doubleValue(root["fps"]), fps.isFinite, fps > 0 else {
            diagnostics.append(.init(code: .invalidFPS, laneIndex: nil))
            return nil
        }
        guard let length = doubleValue(root["length"]), length.isFinite, length > 0 else {
            diagnostics.append(.init(code: .invalidLength, laneIndex: nil))
            return nil
        }
        guard let parent = parseGroupReference(
            root["parent"], diagnostics: &diagnostics
        ), let children = parseGroupReferences(
            root["children"], diagnostics: &diagnostics
        ) else {
            return nil
        }
        return SceneTimelineOptions(
            fps: fps,
            length: length,
            mode: mode,
            startsPaused: root["startpaused"] as? Bool ?? false,
            wrapsLoop: root["wraploop"] as? Bool ?? false,
            smoothing: doubleValue(root["smoothing"]),
            stiffness: doubleValue(root["stiffness"]),
            parent: parent.reference,
            children: children
        )
    }

    /// lane 必须从 `c0` 起连续。`c0` 缺失或中间缺号都 fail closed，避免把 `c2` 当成
    /// component 0 写回错误的轴。
    private nonisolated static func parseLanes(
        _ root: [String: Any],
        diagnostics: inout [SceneTimelineDiagnostic]
    ) -> [[SceneTimelineKeyframe]]? {
        var lanes: [[SceneTimelineKeyframe]] = []
        for index in 0 ..< maximumLaneCount {
            guard let rawLane = root["c\(index)"] else { break }
            guard let entries = rawLane as? [[String: Any]], !entries.isEmpty else {
                diagnostics.append(.init(code: .emptyLane, laneIndex: index))
                return nil
            }
            guard let keyframes = parseKeyframes(
                entries, laneIndex: index, diagnostics: &diagnostics
            ) else {
                return nil
            }
            lanes.append(keyframes)
        }
        guard !lanes.isEmpty else {
            diagnostics.append(.init(code: .missingLanes, laneIndex: nil))
            return nil
        }
        let declared = (0 ..< maximumLaneCount).filter { root["c\($0)"] != nil }
        guard declared == Array(0 ..< lanes.count) else {
            diagnostics.append(.init(code: .laneGap, laneIndex: nil))
            return nil
        }
        return lanes
    }

    private nonisolated static func parseKeyframes(
        _ entries: [[String: Any]],
        laneIndex: Int,
        diagnostics: inout [SceneTimelineDiagnostic]
    ) -> [SceneTimelineKeyframe]? {
        var keyframes: [SceneTimelineKeyframe] = []
        keyframes.reserveCapacity(entries.count)
        for entry in entries {
            guard let frame = doubleValue(entry["frame"]),
                  let value = doubleValue(entry["value"]),
                  frame.isFinite, value.isFinite
            else {
                diagnostics.append(.init(code: .nonFiniteValue, laneIndex: laneIndex))
                return nil
            }
            guard let back = parseTangent(
                entry["back"], allowedX: -1 ... 0,
                laneIndex: laneIndex, diagnostics: &diagnostics
            ), let front = parseTangent(
                entry["front"], allowedX: 0 ... 1,
                laneIndex: laneIndex, diagnostics: &diagnostics
            )
            else {
                return nil
            }
            keyframes.append(SceneTimelineKeyframe(
                frame: frame,
                value: value,
                back: back.tangent,
                front: front.tangent,
                locksAngle: entry["lockangle"] as? Bool,
                locksLength: entry["locklength"] as? Bool
            ))
        }
        guard zip(keyframes, keyframes.dropFirst()).allSatisfy({ $0.frame < $1.frame }) else {
            diagnostics.append(.init(code: .unorderedFrames, laneIndex: laneIndex))
            return nil
        }
        guard zip(keyframes, keyframes.dropFirst()).allSatisfy({
            $0.valuesIncludingEnabledControls(to: $1).allSatisfy(\.isFinite)
        }) else {
            diagnostics.append(.init(code: .nonFiniteValue, laneIndex: laneIndex))
            return nil
        }
        return keyframes
    }

    /// 返回值区分「缺省」与「非法」：缺省是合法的（`tangent == nil`），非法要 fail closed。
    private nonisolated static func parseTangent(
        _ value: Any?,
        allowedX: ClosedRange<Double>,
        laneIndex: Int,
        diagnostics: inout [SceneTimelineDiagnostic]
    ) -> (tangent: SceneTimelineTangent?, Void)? {
        guard let value, !(value is NSNull) else { return (nil, ()) }
        guard let root = value as? [String: Any] else {
            diagnostics.append(.init(code: .invalidTangent, laneIndex: laneIndex))
            return nil
        }
        let x = doubleValue(root["x"]) ?? 0
        let y = doubleValue(root["y"]) ?? 0
        let isEnabled = root["enabled"] as? Bool ?? false
        guard x.isFinite, y.isFinite else {
            diagnostics.append(.init(code: .nonFiniteValue, laneIndex: laneIndex))
            return nil
        }
        guard !isEnabled || allowedX.contains(x) else {
            diagnostics.append(.init(code: .invalidTangent, laneIndex: laneIndex))
            return nil
        }
        return (SceneTimelineTangent(
            isEnabled: isEnabled,
            x: x,
            y: y
        ), ())
    }

    /// Combined 引用同样区分缺省与非法，避免坏 `parent`/`children` 被静默丢弃后
    /// 让成员动画作为独立动画继续执行。
    private nonisolated static func parseGroupReference(
        _ value: Any?,
        diagnostics: inout [SceneTimelineDiagnostic]
    ) -> (reference: SceneTimelineGroupReference?, Void)? {
        guard let value, !(value is NSNull) else { return (nil, ()) }
        guard let root = value as? [String: Any],
              let key = root["key"] as? String, !key.isEmpty
        else {
            diagnostics.append(.init(code: .invalidGroupReference, laneIndex: nil))
            return nil
        }
        return (SceneTimelineGroupReference(key: key), ())
    }

    private nonisolated static func parseGroupReferences(
        _ value: Any?,
        diagnostics: inout [SceneTimelineDiagnostic]
    ) -> [SceneTimelineGroupReference]? {
        guard let value, !(value is NSNull) else { return [] }
        guard let values = value as? [Any] else {
            diagnostics.append(.init(code: .invalidGroupReference, laneIndex: nil))
            return nil
        }
        var references: [SceneTimelineGroupReference] = []
        references.reserveCapacity(values.count)
        for value in values {
            guard let parsed = parseGroupReference(value, diagnostics: &diagnostics),
                  let reference = parsed.reference
            else {
                return nil
            }
            references.append(reference)
        }
        return references
    }

    private nonisolated static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        return nil
    }
}
