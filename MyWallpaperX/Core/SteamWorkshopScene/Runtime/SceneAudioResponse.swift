//
//  SceneAudioResponse.swift
//  MyWallpaperX
//

import Foundation

/// 官方 audio response 求值。
///
/// 来源是 stock `effects/shake/shaders/effects/shake.vert` 与
/// `effects/pulse/shaders/effects/pulse.vert` 中的 `CreateAudioResponse`，
/// 两份实现逐字一致，因此 effect 侧共用这一个求值器。
///
/// ```glsl
/// float audioFrequencyEnd = max(g_AudioFrequencyMin, g_AudioFrequencyMax); // 官方死代码
/// float audioResponse = 0.0;
/// for (int a = int(g_AudioFrequencyMin); a <= int(g_AudioFrequencyMax); ++a)
///     audioResponse += bufferLeft[a];            // mode 3 同时累加 bufferRight[a]
/// audioResponse /= (g_AudioFrequencyMax - g_AudioFrequencyMin + 1.0);  // mode 3 再 * 2.0
/// audioResponse = smoothstep(g_AudioBounds.x, g_AudioBounds.y, audioResponse);
/// audioResponse = saturate(pow(audioResponse, g_AudioPower)) * g_AudioMultiply;
/// ```
///
/// 三处必须按原样保留、不得「化简」：
/// 1. `audioFrequencyEnd` 官方算出后从未使用，这里同样不参与求值；
/// 2. 除数用的是未经 `max()` 修正的 `frequencyMax - frequencyMin + 1`，
///    因此 `min > max` 时循环不执行、除数为负，结果是 `smoothstep(bounds, 0)`
///    而不是「非法输入」——这是官方的既有行为，不在本层 fail closed；
/// 3. `saturate` 只作用于 `pow` 的结果，`multiply` 在其后相乘，
///    所以返回值可以大于 1（`audioamount` 官方范围是 `[0,2]`）。
///
/// 与官方的差异仅限于官方未定义行为（GLSL UB）必须被替换成安全行为的地方，
/// 逐条见 `evaluate` 内注释。作者声明层面的合法性由各 planner 的准入负责，
/// 本层只保证「不崩、不返回非有限值」。
///
/// 边界：本求值器只承诺 effect 侧语义。粒子的 `audioprocessingmode` 等字段虽同名，
/// 官方没有公开对应 shader，是否共用同一公式需在接入粒子消费者时单独取证。
nonisolated enum SceneAudioResponse {
    /// `AUDIOPROCESSING` combo 取值。
    nonisolated enum Channel: Int, Equatable {
        case off = 0
        case left = 1
        case right = 2
        case average = 3

        nonisolated init?(comboValue: Int) {
            self.init(rawValue: comboValue)
        }
    }

    /// 官方 uniform 对应的作者参数。默认值由各 consumer 从自身 shader annotation 提供：
    /// stock shake 的 `audiobounds` 默认 `0.0 1.2`，stock pulse 默认 `0.5 1.0`，
    /// 因此这里不内置任何默认值。
    nonisolated struct Parameters: Equatable {
        let channel: Channel
        let frequencyMin: Float
        let frequencyMax: Float
        let boundsLower: Float
        let boundsUpper: Float
        let exponent: Float
        let multiply: Float

        nonisolated init(
            channel: Channel,
            frequencyMin: Float,
            frequencyMax: Float,
            boundsLower: Float,
            boundsUpper: Float,
            exponent: Float,
            multiply: Float
        ) {
            self.channel = channel
            self.frequencyMin = frequencyMin
            self.frequencyMax = frequencyMax
            self.boundsLower = boundsLower
            self.boundsUpper = boundsUpper
            self.exponent = exponent
            self.multiply = multiply
        }
    }

    static func evaluate(
        spectrum: SceneAudioSpectrumSnapshot,
        parameters: Parameters
    ) -> Float {
        guard parameters.channel != .off else { return 0 }
        // UB 替换：官方 uniform 无有限性校验，非有限参数会把 NaN 传播到顶点位移。
        guard parameters.frequencyMin.isFinite,
              parameters.frequencyMax.isFinite,
              parameters.boundsLower.isFinite,
              parameters.boundsUpper.isFinite,
              parameters.exponent.isFinite,
              parameters.multiply.isFinite
        else {
            return 0
        }

        let accumulated = accumulate(spectrum: spectrum, parameters: parameters)
        // 官方除数：未经 max() 修正，min > max 时为负、min == max + 1 时为零。
        var divisor = parameters.frequencyMax - parameters.frequencyMin + 1
        if parameters.channel == .average {
            divisor *= 2
        }
        // UB 替换：官方 0/0 得到 NaN 并一路传播，这里退回零响应。
        guard divisor != 0 else { return 0 }

        let averaged = accumulated / divisor
        let shaped = smoothstep(
            lower: parameters.boundsLower,
            upper: parameters.boundsUpper,
            value: averaged
        )
        // 官方顺序：先 pow 再 saturate，最后才乘 multiply，因此结果可超过 1。
        let powered = saturate(power(shaped, parameters.exponent))
        let response = powered * parameters.multiply
        return response.isFinite ? response : 0
    }

    private static func accumulate(
        spectrum: SceneAudioSpectrumSnapshot,
        parameters: Parameters
    ) -> Float {
        // UB 替换：官方按 int(uniform) 直接索引 float[16]，作者值越界即数组越界读。
        // 这里把遍历区间夹到合法下标内；夹断只影响读取范围，不修改上面的官方除数。
        let bandCount = SceneAudioSpectrumSnapshot.bandCount
        let rawLower = Int(parameters.frequencyMin)
        let rawUpper = Int(parameters.frequencyMax)
        guard rawLower <= rawUpper else { return 0 }

        let lower = max(0, rawLower)
        let upper = min(bandCount - 1, rawUpper)
        guard lower <= upper else { return 0 }

        var total: Float = 0
        for band in lower ... upper {
            switch parameters.channel {
            case .off:
                break
            case .left:
                total += spectrum.left[band]
            case .right:
                total += spectrum.right[band]
            case .average:
                total += spectrum.left[band]
                total += spectrum.right[band]
            }
        }
        return total
    }

    /// GLSL `smoothstep` 语义。
    /// UB 替换：官方在 `upper <= lower` 时除零，这里退化为阶跃。
    private static func smoothstep(lower: Float, upper: Float, value: Float) -> Float {
        guard upper > lower else { return value >= upper ? 1 : 0 }
        let t = min(1, max(0, (value - lower) / (upper - lower)))
        return t * t * (3 - 2 * t)
    }

    /// UB 替换：底数已被 `smoothstep` 限制在 `[0,1]`，但 `pow(0, 0)` 与负指数
    /// 仍可能产生 inf/NaN，这里统一归零。
    private static func power(_ base: Float, _ exponent: Float) -> Float {
        let result = pow(base, exponent)
        return result.isFinite ? result : 0
    }

    private static func saturate(_ value: Float) -> Float {
        min(1, max(0, value))
    }
}
