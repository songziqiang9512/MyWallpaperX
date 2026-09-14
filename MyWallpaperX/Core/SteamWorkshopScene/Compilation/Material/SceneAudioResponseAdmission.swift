//
//  SceneAudioResponseAdmission.swift
//  MyWallpaperX
//

import Foundation

/// stock effect 的 `AUDIOPROCESSING` 作者常量准入。
///
/// stock `shake.vert` 与 `pulse.vert` 的 audio uniform 组完全同名同义：
/// `frequencymin`/`frequencymax`/`audioexponent`/`audiobounds`/`audioamount`，
/// 且 `CreateAudioResponse` 逐字一致（见 `SceneAudioResponse`）。唯一差异是
/// `audiobounds` 的 annotation 默认值——shake 为 `0.0 1.2`，pulse 为 `0.5 1.0`——
/// 因此默认值由调用方传入，本类型不内置。
///
/// 这五个常量在 authored variants 中是**部分可选**的；缺省一律按
/// annotation 填充。
nonisolated enum SceneAudioResponseAdmission {
    /// 与各 effect 自身常量并存的 audio 常量键。
    nonisolated static let constantKeys = Set([
        "frequencymin", "frequencymax", "audioexponent",
        "audiobounds", "audioamount",
    ])

    /// `parameters == nil` 表示作者未启用，走该 effect 原有的时间驱动路径；
    /// 整体返回 nil 表示声明非法，由调用方 fail closed。
    nonisolated struct Result {
        let parameters: SceneAudioResponse.Parameters?

        nonisolated static let disabled = Result(parameters: nil)
    }

    nonisolated static func resolve(
        comboValue: Int,
        constants: [String: SceneDocument.ShaderValue],
        defaultBounds: SIMD2<Float>,
        isAudioCapableProfile: Bool
    ) -> Result? {
        guard comboValue != 0 else { return .disabled }
        guard isAudioCapableProfile,
              let channel = SceneAudioResponse.Channel(comboValue: comboValue)
        else {
            return nil
        }

        var values: [String: SceneDocument.ShaderValue] = [:]
        for (key, value) in constants where constantKeys.contains(key.lowercased()) {
            guard values.updateValue(value, forKey: key.lowercased()) == nil else {
                return nil
            }
        }

        guard let frequencyMin = scalar(values["frequencymin"], range: 0 ... 15, fallback: 0),
              let frequencyMax = scalar(values["frequencymax"], range: 0 ... 15, fallback: 1),
              let exponent = scalar(values["audioexponent"], range: 0 ... 4, fallback: 1),
              let multiply = scalar(values["audioamount"], range: 0 ... 2, fallback: 1),
              let bounds = vector(values["audiobounds"], fallback: defaultBounds)
        else {
            return nil
        }

        return Result(
            parameters: SceneAudioResponse.Parameters(
                channel: channel,
                frequencyMin: frequencyMin,
                frequencyMax: frequencyMax,
                boundsLower: bounds.x,
                boundsUpper: bounds.y,
                exponent: exponent,
                multiply: multiply
            )
        )
    }

    /// 与各 effect 非 audio 常量相同的准入口径：拒绝 user binding、非 number、
    /// 非有限值与越界。未声明时取 annotation 默认值。
    private nonisolated static func scalar(
        _ value: SceneDocument.ShaderValue?,
        range: ClosedRange<Double>,
        fallback: Float
    ) -> Float? {
        guard let value else { return fallback }
        guard value.userBinding == nil,
              value.valueKind.lowercased() == "number",
              let components = value.components,
              components.count == 1,
              let component = components.first,
              component.isFinite,
              range.contains(component)
        else {
            return nil
        }
        return Float(component)
    }

    private nonisolated static func vector(
        _ value: SceneDocument.ShaderValue?,
        fallback: SIMD2<Float>
    ) -> SIMD2<Float>? {
        guard let value else { return fallback }
        // 官方对 audiobounds 没有声明 range，语料实测落在 0...1.2；这里只要求
        // 有限，反序交由 SceneAudioResponse 的 UB 兜底处理。
        guard value.userBinding == nil,
              let components = value.components,
              components.count == 2,
              components.allSatisfy(\.isFinite)
        else {
            return nil
        }
        return SIMD2(Float(components[0]), Float(components[1]))
    }
}
