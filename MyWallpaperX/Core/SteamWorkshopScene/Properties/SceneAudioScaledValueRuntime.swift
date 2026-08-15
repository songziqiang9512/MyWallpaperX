import Foundation

nonisolated struct SceneAudioScaledValueRuntime {
    let program: SceneAudioScaledValueProgram
    private var smoothedValues: [SceneDynamicTarget: Double]

    nonisolated init(program: SceneAudioScaledValueProgram) {
        self.program = program
        smoothedValues = Dictionary(
            uniqueKeysWithValues: program.bindings.map {
                ($0.definition.target, 0)
            }
        )
    }

    /// SceneScript initializes `smoothValue` to zero before the particle system
    /// performs its authored start-time warm-up.  Project the same launch value
    /// into that warm-up instead of letting particles pre-roll at the unscaled
    /// wrapper value and only applying the script on the first displayed frame.
    nonisolated static func initialValues(
        program: SceneAudioScaledValueProgram
    ) -> [SceneDynamicTarget: SceneDynamicValue] {
        var runtime = Self(program: program)
        return runtime.values(audioSpectrum: .silent, frameTime: 0)
    }

    nonisolated mutating func values(
        audioSpectrum: SceneAudioSpectrumSnapshot,
        frameTime: TimeInterval
    ) -> [SceneDynamicTarget: SceneDynamicValue] {
        let deltaTime = frameTime.isFinite ? max(frameTime, 0) : 0
        var result: [SceneDynamicTarget: SceneDynamicValue] = [:]
        for binding in program.bindings {
            let target = binding.definition.target
            let left = Double(audioSpectrum.left[binding.frequency])
            let right = Double(audioSpectrum.right[binding.frequency])
            let input = max(0, (left + right) * 0.5)
            let previous = smoothedValues[target] ?? 0
            let smoothingStep = min(1, deltaTime * binding.smoothing)
            let smoothed = min(1, previous + (input - previous) * smoothingStep)
            smoothedValues[target] = smoothed
            let initialValue: Double
            switch binding.definition.authoredValue {
            case let .scalar(value): initialValue = value
            case let .vector3(x, _, _): initialValue = x
            default: continue
            }
            let scale = smoothed
                * (binding.maximumScale - binding.minimumScale)
                + binding.minimumScale
            let value = initialValue * scale
            switch binding.definition.valueType {
            case .scalar:
                result[target] = .scalar(value)
            case .vector3:
                // Official Scale accepts this stock script's scalar return by
                // splatting it to all three axes. Preserve that typed result in
                // the shared dynamic snapshot.
                result[target] = .vector3(value, value, value)
            default:
                continue
            }
        }
        return result
    }
}
